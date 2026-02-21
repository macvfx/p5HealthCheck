#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CSV_FILE="$SCRIPT_DIR/PlugEV_Charging_Sessions/PlugEV_Charging_Sessions.csv"
CSV_FILE="$DEFAULT_CSV_FILE"
CSV_DIR="$(dirname "$CSV_FILE")"
HEADER='Date and Time,Duration (Min),Location,Charger,Energy Added (kWh),Cost'

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") [--csv /path/to/output.csv] <receipt.rtf> [receipt2.rtf ...]

Parses PlugEV receipt RTF files using macOS tools (textutil + awk) and updates:
  $CSV_FILE
USAGE
}

files=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --csv)
      if [[ $# -lt 2 ]]; then
        echo "Error: --csv requires a file path." >&2
        exit 1
      fi
      CSV_FILE="$2"
      CSV_DIR="$(dirname "$CSV_FILE")"
      shift 2
      ;;
    *)
      files+=("$1")
      shift
      ;;
  esac
done

if [[ ${#files[@]} -lt 1 ]]; then
  usage
  exit 1
fi

for f in "${files[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "Error: file not found: $f" >&2
    exit 1
  fi
  case "$f" in
    *.rtf|*.RTF) ;;
    *)
      echo "Error: expected .rtf file, got: $f" >&2
      exit 1
      ;;
  esac
done

mkdir -p "$CSV_DIR"

tmp_existing="$(mktemp)"
tmp_new_tsv="$(mktemp)"
tmp_combined="$(mktemp)"
tmp_sorted="$(mktemp)"
trap 'rm -f "$tmp_existing" "$tmp_new_tsv" "$tmp_combined" "$tmp_sorted"' EXIT

# Load existing session rows only (ignore header, blanks, and summary row).
if [[ -f "$CSV_FILE" ]]; then
  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [[ "$line" =~ ^\"([^\"]+)\",([0-9]+),([^,]*),([^,]*),([0-9]+\.[0-9]+),([0-9]+\.[0-9]+)$ ]]; then
      key="${BASH_REMATCH[1]}"
      printf '%s\t%s\n' "$key" "$line" >> "$tmp_existing"
    fi
  done < "$CSV_FILE"
fi

# Use associative array for de-dup keyed by Date and Time.
declare -A rows_by_key=()
while IFS=$'\t' read -r k row; do
  [[ -z "${k:-}" ]] && continue
  rows_by_key["$k"]="$row"
done < "$tmp_existing"

extract_one_file() {
  local rtf_file="$1"
  textutil -convert txt -stdout "$rtf_file" | awk '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }
    function duration_to_min(s, h, m, a, b) {
      h = 0
      m = 0
      if (index(s, " hr ") > 0) {
        split(s, a, " hr ")
        h = a[1] + 0
        split(a[2], b, " min")
        m = b[1] + 0
      } else {
        split(s, b, " min")
        m = b[1] + 0
      }
      return h * 60 + m
    }
    function short_loc(s) {
      if (index(s, "Hillcrest") > 0) return "Hillcrest CC"
      if (index(s, "Killarney") > 0) return "Killarney CC"
      if (index(s, " - ") > 0) return substr(s, 1, index(s, " - ") - 1)
      return s
    }
    function flush_if_ready() {
      if (dt != "" && dur != "" && loc != "" && charger != "" && energy != "" && cost != "") {
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", dt, dur, loc, charger, energy, cost
        dt = ""
        dur = ""
        loc = ""
        charger = ""
        energy = ""
        cost = ""
      }
    }
    BEGIN {
      dt = ""
      dur = ""
      loc = ""
      charger = ""
      energy = ""
      cost = ""
    }
    {
      line = trim($0)
      if (line == "") next

      if (line ~ /^[A-Z][a-z]+ [0-9][0-9]*, [0-9][0-9][0-9][0-9] [0-9][0-9]*:[0-9][0-9] [AP]M - [0-9][0-9]*:[0-9][0-9] [AP]M$/) {
        dt = line
        dur = ""
        loc = ""
        charger = ""
        energy = ""
        cost = ""
        next
      }

      if (dt == "") next

      if (dur == "" && line ~ /^([0-9][0-9]* hr )?[0-9][0-9]* min$/) {
        dur = duration_to_min(line)
        next
      }

      if (loc == "" && index(line, " - ") > 0) {
        loc = short_loc(line)
        next
      }

      if (charger == "" && line ~ /^PEV-[0-9]+$/) {
        charger = line
        next
      }

      if (energy == "" && line ~ /^[0-9][0-9]*\.[0-9][0-9]* kWh$/) {
        sub(/ kWh$/, "", line)
        energy = line
        next
      }

      if (cost == "" && line ~ /^CA\$ [0-9][0-9]*\.[0-9][0-9]$/) {
        sub(/^CA\$ /, "", line)
        cost = line
        flush_if_ready()
        next
      }
    }
    END {
      flush_if_ready()
    }
  '
}

for rtf_file in "${files[@]}"; do
  extract_one_file "$rtf_file" >> "$tmp_new_tsv"
done

all_new=0
added=0
while IFS=$'\t' read -r dt dur loc charger energy cost; do
  [[ -z "${dt:-}" ]] && continue
  all_new=$((all_new + 1))
  if [[ -z "${rows_by_key[$dt]+x}" ]]; then
    row="\"$dt\",$dur,$loc,$charger,$energy,$cost"
    rows_by_key["$dt"]="$row"
    added=$((added + 1))
  fi
done < "$tmp_new_tsv"

# Prepare rows for sorting by start datetime (newest first).
for k in "${!rows_by_key[@]}"; do
  row="${rows_by_key[$k]}"
  start_part="${k%% - *}"
  if epoch="$(date -j -f "%B %d, %Y %l:%M %p" "$start_part" "+%s" 2>/dev/null)"; then
    :
  else
    epoch=0
  fi
  printf '%s\t%s\n' "$epoch" "$row" >> "$tmp_combined"
done

sort -t $'\t' -k1,1nr "$tmp_combined" > "$tmp_sorted"

total_sessions=0
total_duration=0
sum_energy="0"
sum_cost="0"

while IFS=$'\t' read -r _epoch row; do
  [[ -z "${row:-}" ]] && continue
  total_sessions=$((total_sessions + 1))
  if [[ "$row" =~ ^\"([^\"]+)\",([0-9]+),([^,]*),([^,]*),([0-9]+\.[0-9]+),([0-9]+\.[0-9]+)$ ]]; then
    dur="${BASH_REMATCH[2]}"
    energy="${BASH_REMATCH[5]}"
    cost="${BASH_REMATCH[6]}"
    total_duration=$((total_duration + dur))
    sum_energy="$(awk -v a="$sum_energy" -v b="$energy" 'BEGIN { printf "%.4f", a + b }')"
    sum_cost="$(awk -v a="$sum_cost" -v b="$cost" 'BEGIN { printf "%.2f", a + b }')"
  fi
done < "$tmp_sorted"

{
  echo "$HEADER"
  while IFS=$'\t' read -r _epoch row; do
    [[ -n "${row:-}" ]] && echo "$row"
  done < "$tmp_sorted"

  blanks=$((30 - total_sessions))
  if (( blanks < 0 )); then
    blanks=0
  fi
  for ((i = 0; i < blanks; i++)); do
    echo ",,,,,"
  done

  echo ",$total_duration,,,$sum_energy,$sum_cost"
} > "$CSV_FILE"

echo "Found $all_new sessions in input file(s)"
echo "Added $added new sessions ($((all_new - added)) duplicates skipped)"
echo "Total sessions in CSV: $total_sessions"
echo "Totals: $total_duration min | $sum_energy kWh | CA\$ $sum_cost"
echo "CSV saved to: $CSV_FILE"
