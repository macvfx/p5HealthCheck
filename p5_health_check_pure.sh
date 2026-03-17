#!/bin/bash
# Pure-bash version of p5_health_check.sh — ZERO python3 dependency.
# All JSON parsing, CSV generation, and data transformation use
# grep, sed, awk, and built-in bash string operations only.
set -euo pipefail

# Optional hardcoded defaults. Leave blank to prompt.
HARDCODED_ALIAS=""
HARDCODED_HOST=""
HARDCODED_PORT="8000"
HARDCODED_USERNAME=""
HARDCODED_PASSWORD=""
HARDCODED_API_VERSION="v1"
HARDCODED_USE_HTTPS="false"

DEFAULT_CONFIG_FILES=(
  "/Users/Shared/P5Servers.json"
  "/Users/Shared/P5HealthCheckServers.json"
  "$HOME/Documents/P5Servers.json"
  "$HOME/Documents/P5HealthCheckServers.json"
)
KEYCHAIN_SERVICE="com.p5healthcheck.shell"
LOOKBACK_DAYS=7
MAX_VOLUME_DETAILS=500
OUT_DIR="$(pwd)"
CONFIG_FILE=""
ALLOW_INSECURE_TLS=0
NON_INTERACTIVE=0
FORCE_PASSWORD_PROMPT=0
OVERRIDE_USERNAME=""
AUTH_OVERRIDE=""
CURL_AUTH_USERPASS=""
PREFER_KEYCHAIN=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") [-o output_dir] [-c config.json] [-l lookback_days] [-m max_volume_details] [-k] [-n] [-p] [-K] [-U username] [-A user:pass]

Options:
  -o DIR   Output directory (default: current working directory)
  -c FILE  Server config JSON file (default auto-detect: /Users/Shared/P5Servers.json, /Users/Shared/P5HealthCheckServers.json, ~/Documents/P5Servers.json, ~/Documents/P5HealthCheckServers.json)
  -l N     Warning/error jobs lookback days (default: 7)
  -m N     Max volume details to fetch (default: 500, 0 = unlimited)
  -k       Allow insecure TLS (curl -k)
  -n       Non-interactive mode (runs all checks once; no prompts)
  -p       Force password prompt (ignore Keychain for this run)
  -K       In interactive mode, try Keychain password before prompting
  -U NAME  Override username for this run
  -A AUTH  Override auth as raw 'user:pass' for this run
  -h       Show this help

Exports produced:
  - report JSON
  - connectivity CSV
  - volumes CSV
  - warning job results CSV
  - error job results CSV
  - all job results CSV
  - plans markdown (all, archive, backup, sync)
USAGE
}

while getopts ":o:c:l:m:knpKU:A:h" opt; do
  case "$opt" in
    o) OUT_DIR="$OPTARG" ;;
    c) CONFIG_FILE="$OPTARG" ;;
    l) LOOKBACK_DAYS="$OPTARG" ;;
    m) MAX_VOLUME_DETAILS="$OPTARG" ;;
    k) ALLOW_INSECURE_TLS=1 ;;
    n) NON_INTERACTIVE=1 ;;
    p) FORCE_PASSWORD_PROMPT=1 ;;
    K) PREFER_KEYCHAIN=1 ;;
    U) OVERRIDE_USERNAME="$OPTARG" ;;
    A) AUTH_OVERRIDE="$OPTARG" ;;
    h) usage; exit 0 ;;
    :) echo "Missing value for -$OPTARG" >&2; exit 1 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage; exit 1 ;;
  esac
done

if (( NON_INTERACTIVE == 1 && FORCE_PASSWORD_PROMPT == 1 )); then
  echo "Options -n and -p cannot be used together." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
if [[ ! -d "$OUT_DIR" ]]; then
  echo "Output directory does not exist: $OUT_DIR" >&2
  exit 1
fi

if [[ -z "$CONFIG_FILE" ]]; then
  for candidate in "${DEFAULT_CONFIG_FILES[@]}"; do
    if [[ -f "$candidate" ]]; then
      CONFIG_FILE="$candidate"
      break
    fi
  done
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required." >&2
  exit 1
fi
if ! command -v security >/dev/null 2>&1; then
  echo "security command is required (macOS Keychain)." >&2
  exit 1
fi

# ── Pure-bash utility functions ───────────────────────────────────────────────

trim() {
  echo "$1" | awk '{$1=$1;print}'
}

to_lower() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

safe_name() {
  echo "$1" | sed 's/[^A-Za-z0-9._-]/-/g'
}

bool_norm() {
  local v
  v="$(to_lower "$(trim "$1")")"
  case "$v" in
    true|1|yes|y) echo "true" ;;
    *) echo "false" ;;
  esac
}

prompt_default() {
  local prompt="$1"
  local default_value="$2"
  local out
  if [[ -n "$default_value" ]]; then
    read -r -p "$prompt [$default_value]: " out
    out="$(trim "$out")"
    if [[ -z "$out" ]]; then
      out="$default_value"
    fi
  else
    read -r -p "$prompt: " out
    out="$(trim "$out")"
  fi
  echo "$out"
}

prompt_secret_into() {
  local var_name="$1"
  local prompt="$2"
  local out=""
  IFS= read -r -s -p "$prompt: " out
  echo
  printf -v "$var_name" '%s' "$out"
}

keychain_account() {
  local username="$1"
  local host="$2"
  local port="$3"
  local api_version="$4"
  echo "${username}@${host}:${port}/rest/${api_version}"
}

keychain_get_password() {
  local account="$1"
  security find-generic-password -a "$account" -s "$KEYCHAIN_SERVICE" -w 2>/dev/null || true
}

keychain_set_password() {
  local account="$1"
  local password="$2"
  security add-generic-password -a "$account" -s "$KEYCHAIN_SERVICE" -w "$password" -U >/dev/null
}

# ── Replacement for python3 time helpers ──────────────────────────────────────

now_millis() {
  # macOS date doesn't support %N; use perl as fallback for sub-second precision
  if date +%s%N >/dev/null 2>&1 && [[ "$(date +%s%N)" != *N* ]]; then
    echo $(( $(date +%s%N) / 1000000 ))
  else
    echo "$(date +%s)000"
  fi
}

now_iso() {
  date +%Y-%m-%dT%H:%M:%S
}

format_uptime() {
  local seconds="$1"
  if [[ -z "$seconds" || "$seconds" == "null" ]]; then
    echo "-"
    return
  fi
  if ! [[ "$seconds" =~ ^[0-9]+$ ]]; then
    echo "$seconds"
    return
  fi
  local days=$((seconds / 86400))
  local hours=$(((seconds % 86400) / 3600))
  local mins=$(((seconds % 3600) / 60))
  if (( days > 0 )); then
    echo "${days}d ${hours}h ${mins}m"
  elif (( hours > 0 )); then
    echo "${hours}h ${mins}m"
  else
    echo "${mins}m"
  fi
}

# ── Pure-bash kbytes_human (replaces python3 version) ─────────────────────────

kbytes_human() {
  local raw="${1:-}"
  raw="$(echo "$raw" | awk '{$1=$1;print}')"
  if [[ -z "$raw" || "$raw" == "null" ]]; then
    echo ""
    return
  fi
  # Use awk for floating-point arithmetic
  echo "$raw" | awk '{
    kb = $1 + 0
    gib = 1024.0 * 1024.0
    tib = gib * 1024.0
    if (kb >= tib)
      printf "%.2f TiB\n", kb / tib
    else
      printf "%.2f GiB\n", kb / gib
  }'
}

# ── Pure-bash JSON helpers (replaces python3 json_get / json_count / etc) ─────

json_get() {
  local file="$1"
  local key="$2"
  if [[ ! -f "$file" ]]; then
    echo ""
    return
  fi
  # Extract value for a simple top-level key from flat JSON.
  # Handles: "key":"string", "key":123, "key":true, "key":false, "key":null
  local val
  # First try string values (quoted)
  val="$(grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" 2>/dev/null | head -1 | sed 's/^[^:]*:[[:space:]]*//' | sed 's/^"//;s/"$//')"
  if [[ -n "$val" ]]; then
    echo "$val"
    return
  fi
  # Then try non-string values (number, boolean, null)
  val="$(grep -o "\"${key}\"[[:space:]]*:[[:space:]]*[^,\"}\r\n]*" "$file" 2>/dev/null | head -1 | sed 's/^[^:]*:[[:space:]]*//' | sed 's/[[:space:]]*$//')"
  if [[ "$val" == "null" || "$val" == "null " ]]; then
    echo ""
    return
  fi
  # Normalize booleans
  if [[ "$val" == "true" || "$val" == "false" ]]; then
    echo "$val"
    return
  fi
  echo "$val"
}

json_count_ids() {
  local file="$1"
  local key="$2"
  if [[ ! -f "$file" ]]; then
    echo "0"
    return
  fi
  local count
  count="$(grep -o '"ID"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" 2>/dev/null | wc -l | awk '{print $1}')"
  echo "${count:-0}"
}

json_ids_to_lines() {
  local file="$1"
  local key="$2"
  if [[ ! -f "$file" ]]; then
    return
  fi
  grep -o '"ID"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" 2>/dev/null | sed 's/"ID"[[:space:]]*:[[:space:]]*"//;s/"$//' || true
}

json_ids_to_lines_flexible() {
  local file="$1"
  local preferred="$2"
  if [[ ! -f "$file" ]]; then
    return
  fi
  # Same as json_ids_to_lines — for P5 API the structure is the same
  grep -o '"ID"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" 2>/dev/null | sed 's/"ID"[[:space:]]*:[[:space:]]*"//;s/"$//' || true
}

# ── Pure-bash JSON/CSV escape helpers ─────────────────────────────────────────

json_escape() {
  # Escape a string value for JSON embedding.
  # Handles backslash, double-quote, newline, tab, carriage return.
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  echo "$s"
}

csv_escape() {
  # Escape a value for CSV: if it contains comma, quote, or newline, wrap in quotes.
  # Double any internal quotes.
  local val="$1"
  if [[ "$val" == *[\",]* || "$val" == *$'\n'* ]]; then
    val="${val//\"/\"\"}"
    echo "\"${val}\""
  else
    echo "$val"
  fi
}

csv_row() {
  # Write a CSV row from arguments, properly escaped.
  local first=1
  local arg
  for arg in "$@"; do
    if (( first )); then
      first=0
    else
      printf ','
    fi
    printf '%s' "$(csv_escape "$arg")"
  done
  printf '\n'
}

# ── Pure-bash JSON value helper (null or string or number) ────────────────────

json_str_or_null() {
  local val="$1"
  if [[ -z "$val" ]]; then
    echo "null"
  else
    echo "\"$(json_escape "$val")\""
  fi
}

json_int_or_null() {
  local val="$1"
  if [[ "$val" =~ ^-?[0-9]+$ ]]; then
    echo "$val"
  else
    echo "null"
  fi
}

json_bool() {
  local val="$1"
  local v
  v="$(to_lower "$(trim "$val")")"
  case "$v" in
    true|1|yes|y) echo "true" ;;
    false|0|no|n) echo "false" ;;
    *) echo "null" ;;
  esac
}

# ── NDJSON to JSON array conversion ──────────────────────────────────────────

ndjson_to_array() {
  # Read an NDJSON file and output a JSON array string.
  local file="$1"
  if [[ ! -f "$file" || ! -s "$file" ]]; then
    echo "[]"
    return
  fi
  local result="["
  local first=1
  while IFS= read -r line; do
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [[ -z "$line" ]]; then
      continue
    fi
    if (( first )); then
      first=0
    else
      result="${result},"
    fi
    result="${result}${line}"
  done < "$file"
  result="${result}]"
  echo "$result"
}

ndjson_to_array_sorted() {
  # Read an NDJSON file, sort by kind+planID, output JSON array.
  local file="$1"
  if [[ ! -f "$file" || ! -s "$file" ]]; then
    echo "[]"
    return
  fi
  # Prepend sort key (kind|planID) then sort, then strip key
  local tmpfile
  tmpfile="$(mktemp)"
  while IFS= read -r line; do
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [[ -z "$line" ]]; then
      continue
    fi
    local kind planID
    kind="$(echo "$line" | grep -o '"kind"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"kind"[[:space:]]*:[[:space:]]*"//;s/"$//')"
    planID="$(echo "$line" | grep -o '"planID"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"planID"[[:space:]]*:[[:space:]]*"//;s/"$//')"
    echo "${kind}|${planID}|${line}" >> "$tmpfile"
  done < "$file"
  sort -t'|' -k1,1 -k2,2 "$tmpfile" > "${tmpfile}.sorted"
  local result="["
  local first=1
  while IFS= read -r sortline; do
    local json_part="${sortline#*|}"
    json_part="${json_part#*|}"
    if (( first )); then
      first=0
    else
      result="${result},"
    fi
    result="${result}${json_part}"
  done < "${tmpfile}.sorted"
  result="${result}]"
  rm -f "$tmpfile" "${tmpfile}.sorted"
  echo "$result"
}

# ── Pure-bash extract_protocol_summary ────────────────────────────────────────

extract_protocol_summary() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo ""
    return
  fi
  # Extract all string values from the JSON, search for keywords
  local keywords="error|failed|failure|warning|exception|media|volume|tape|blank|appendable|mount|load|blocked|waiting|timeout|restore|archive|backup"
  local matches
  matches="$(grep -oiE "[a-zA-Z][a-zA-Z0-9 _.,:;/()-]*($keywords)[a-zA-Z0-9 _.,:;/()-]*" "$file" 2>/dev/null | head -3)" || true
  if [[ -z "$matches" ]]; then
    echo ""
    return
  fi
  # Join first 3 matches with " | "
  local result=""
  local count=0
  while IFS= read -r m; do
    m="$(echo "$m" | sed 's/^[[:space:]"]*//;s/[[:space:]"]*$//')"
    if [[ -z "$m" ]]; then
      continue
    fi
    if (( count > 0 )); then
      result="${result} | "
    fi
    result="${result}${m}"
    count=$((count + 1))
    if (( count >= 3 )); then
      break
    fi
  done <<< "$matches"
  echo "$result"
}

# ── Pure-bash write_plans_markdown ────────────────────────────────────────────

_schedule_text() {
  # Parse a single schedule NDJSON line and produce text.
  local line="$1"
  local parts=""
  local start firstrun freq interval duration exception pool
  start="$(echo "$line" | grep -o '"start"[[:space:]]*:[[:space:]]*[^,}]*' | head -1 | sed 's/^[^:]*:[[:space:]]*//' | sed 's/^"//;s/"$//' | sed 's/^null$//')"
  firstrun="$(echo "$line" | grep -o '"firstrun"[[:space:]]*:[[:space:]]*[^,}]*' | head -1 | sed 's/^[^:]*:[[:space:]]*//' | sed 's/^"//;s/"$//' | sed 's/^null$//')"
  freq="$(echo "$line" | grep -o '"frequency"[[:space:]]*:[[:space:]]*[^,}]*' | head -1 | sed 's/^[^:]*:[[:space:]]*//' | sed 's/^"//;s/"$//' | sed 's/^null$//')"
  interval="$(echo "$line" | grep -o '"interval"[[:space:]]*:[[:space:]]*[^,}]*' | head -1 | sed 's/^[^:]*:[[:space:]]*//' | sed 's/^"//;s/"$//' | sed 's/^null$//')"
  duration="$(echo "$line" | grep -o '"duration"[[:space:]]*:[[:space:]]*[^,}]*' | head -1 | sed 's/^[^:]*:[[:space:]]*//' | sed 's/^"//;s/"$//' | sed 's/^null$//')"
  exception="$(echo "$line" | grep -o '"exception"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/^[^:]*:[[:space:]]*"//;s/"$//')"
  pool="$(echo "$line" | grep -o '"pool"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/^[^:]*:[[:space:]]*"//;s/"$//')"

  local value=""
  if [[ -n "$start" ]]; then
    value="$start"
  elif [[ -n "$firstrun" ]]; then
    value="$firstrun"
  fi
  if [[ -n "$value" ]]; then
    # Try to convert epoch to human-readable date
    if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      local int_val="${value%%.*}"
      local dt
      dt="$(date -r "$int_val" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$value")"
      parts="start ${dt}"
    else
      parts="start ${value}"
    fi
  fi

  if [[ -n "$freq" ]]; then
    if [[ -n "$parts" ]]; then
      parts="${parts}; freq ${freq}"
    else
      parts="freq ${freq}"
    fi
  fi
  if [[ -n "$interval" ]]; then
    if [[ -n "$parts" ]]; then
      parts="${parts}; interval ${interval}s"
    else
      parts="interval ${interval}s"
    fi
  fi
  if [[ -n "$duration" ]]; then
    if [[ -n "$parts" ]]; then
      parts="${parts}; duration ${duration}s"
    else
      parts="duration ${duration}s"
    fi
  fi
  if [[ -n "$exception" ]]; then
    if [[ -n "$parts" ]]; then
      parts="${parts}; exception ${exception}"
    else
      parts="exception ${exception}"
    fi
  fi
  if [[ -n "$pool" ]]; then
    if [[ -n "$parts" ]]; then
      parts="${parts}; pool ${pool}"
    else
      parts="pool ${pool}"
    fi
  fi

  if [[ -z "$parts" ]]; then
    echo "-"
  else
    echo "$parts"
  fi
}

write_plans_markdown() {
  local output_file="$1"
  local alias_name="$2"
  local host="$3"
  local port="$4"
  local filter_kind="$5"
  local plans_ndjson="$6"

  local plans_tmpfile
  plans_tmpfile="$(mktemp)"

  # Read and optionally filter plans, then sort by kind+planID
  if [[ -f "$plans_ndjson" ]]; then
    while IFS= read -r line; do
      line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      if [[ -z "$line" ]]; then
        continue
      fi
      if [[ "$filter_kind" != "all" ]]; then
        local kind
        kind="$(echo "$line" | grep -o '"kind"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"kind"[[:space:]]*:[[:space:]]*"//;s/"$//')"
        if [[ "$kind" != "$filter_kind" ]]; then
          continue
        fi
      fi
      local sort_kind sort_planID
      sort_kind="$(echo "$line" | grep -o '"kind"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"kind"[[:space:]]*:[[:space:]]*"//;s/"$//')"
      sort_planID="$(echo "$line" | grep -o '"planID"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"planID"[[:space:]]*:[[:space:]]*"//;s/"$//')"
      echo "${sort_kind}|${sort_planID}|${line}" >> "$plans_tmpfile"
    done < "$plans_ndjson"
  fi

  local sorted_file="${plans_tmpfile}.sorted"
  sort -t'|' -k1,1 -k2,2 "$plans_tmpfile" > "$sorted_file"

  local plan_count
  plan_count="$(wc -l < "$sorted_file" | awk '{print $1}')"

  {
    echo "# P5 Plan Documentation"
    echo ""
    echo "- Server: ${alias_name}"
    echo "- Host: ${host}:${port}"
    echo "- Exported: $(date -u +%Y-%m-%dT%H:%M:%S%z)"
    echo "- Total plans: ${plan_count}"
    echo ""

    if (( plan_count == 0 )); then
      echo "_No Archive, Backup, or Sync plans were returned by the API._"
    else
      while IFS= read -r sorted_line; do
        local json_line="${sorted_line#*|}"
        json_line="${json_line#*|}"

        local kind planID description enabled
        kind="$(echo "$json_line" | grep -o '"kind"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"kind"[[:space:]]*:[[:space:]]*"//;s/"$//')"
        planID="$(echo "$json_line" | grep -o '"planID"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"planID"[[:space:]]*:[[:space:]]*"//;s/"$//')"
        description="$(echo "$json_line" | grep -o '"description"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"description"[[:space:]]*:[[:space:]]*"//;s/"$//')"
        enabled="$(echo "$json_line" | grep -o '"enabled"[[:space:]]*:[[:space:]]*[^,}]*' | head -1 | sed 's/^[^:]*:[[:space:]]*//')"

        local enabled_text="-"
        if [[ "$enabled" == "true" ]]; then
          enabled_text="Yes"
        elif [[ "$enabled" == "false" ]]; then
          enabled_text="No"
        fi

        echo "## ${kind} Plan \`${planID}\`"
        echo ""
        echo "- Description: ${description:--}"
        echo "- Enabled: ${enabled_text}"

        if [[ "$kind" != "Archive" ]]; then
          # Extract sourceHost
          local sourceHost
          sourceHost="$(echo "$json_line" | grep -o '"sourceHost"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"sourceHost"[[:space:]]*:[[:space:]]*"//;s/"$//')"
          if [[ -z "$sourceHost" ]]; then
            sourceHost="$(echo "$json_line" | grep -o '"sourceHost"[[:space:]]*:[[:space:]]*null' | head -1)"
            if [[ -n "$sourceHost" ]]; then
              sourceHost=""
            fi
          fi
          # Extract sourcePaths array values
          local sourcePaths
          sourcePaths="$(echo "$json_line" | grep -o '"sourcePaths"[[:space:]]*:[[:space:]]*\[[^]]*\]' | head -1 | grep -o '"[^"]*"' | sed 's/"//g' | tr '\n' ', ' | sed 's/,$//')"

          local source_display="${sourceHost:--}"
          if [[ -n "$sourcePaths" ]]; then
            source_display="${source_display} :: ${sourcePaths}"
          fi
          echo "- Source: ${source_display}"

          # Extract targetHost
          local targetHost
          targetHost="$(echo "$json_line" | grep -o '"targetHost"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"targetHost"[[:space:]]*:[[:space:]]*"//;s/"$//')"
          # Extract targetPaths array values
          local targetPaths
          targetPaths="$(echo "$json_line" | grep -o '"targetPaths"[[:space:]]*:[[:space:]]*\[[^]]*\]' | head -1 | grep -o '"[^"]*"' | sed 's/"//g' | tr '\n' ', ' | sed 's/,$//')"

          local target_display="${targetHost:--}"
          if [[ -n "$targetPaths" ]]; then
            target_display="${target_display} :: ${targetPaths}"
          fi
          echo "- Target: ${target_display}"

          # Extract schedule array - each element is a JSON object
          local schedule_raw
          schedule_raw="$(echo "$json_line" | grep -o '"schedule"[[:space:]]*:[[:space:]]*\[.*\]' | head -1 | sed 's/"schedule"[[:space:]]*:[[:space:]]*\[//;s/\]$//')"
          if [[ -z "$schedule_raw" || "$schedule_raw" == "[]" ]]; then
            echo "- Schedule: -"
          else
            # Split by },{
            local sched_items=()
            local remaining="$schedule_raw"
            while [[ -n "$remaining" ]]; do
              # Find the next complete object
              local obj
              if [[ "$remaining" == *"},{"* ]]; then
                obj="${remaining%%\},\{*}}"
                remaining="${remaining#*\},\{}"
                remaining="{${remaining}"
              else
                obj="$remaining"
                remaining=""
              fi
              obj="$(echo "$obj" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
              # Ensure it starts with { and ends with }
              [[ "$obj" != \{* ]] && obj="{${obj}"
              [[ "$obj" != *\} ]] && obj="${obj}}"
              sched_items+=("$obj")
            done
            local sched_idx=0
            for sched_item in "${sched_items[@]}"; do
              local sched_text
              sched_text="$(_schedule_text "$sched_item")"
              if (( sched_idx == 0 )); then
                echo "- Schedule: ${sched_text}"
              else
                echo "  - ${sched_text}"
              fi
              sched_idx=$((sched_idx + 1))
            done
          fi
        fi

        # Extract notes array
        local notes_raw
        notes_raw="$(echo "$json_line" | grep -o '"notes"[[:space:]]*:[[:space:]]*\[[^]]*\]' | head -1 | sed 's/"notes"[[:space:]]*:[[:space:]]*\[//;s/\]$//')"
        if [[ -n "$notes_raw" && "$notes_raw" != "[]" ]]; then
          local note_idx=0
          # Extract individual quoted note strings
          while IFS= read -r note_val; do
            note_val="$(echo "$note_val" | sed 's/^"//;s/"$//')"
            if [[ -z "$note_val" ]]; then
              continue
            fi
            if (( note_idx == 0 )); then
              echo "- Notes: ${note_val}"
            else
              echo "  - ${note_val}"
            fi
            note_idx=$((note_idx + 1))
          done < <(echo "$notes_raw" | grep -o '"[^"]*"' || true)
        fi

        echo ""
      done < "$sorted_file"
    fi
  } > "$output_file"

  rm -f "$plans_tmpfile" "$sorted_file"
}

# ── Pure-bash read_config_servers ─────────────────────────────────────────────

read_config_servers() {
  local config_file="$1"
  if [[ ! -f "$config_file" ]]; then
    return
  fi
  # Parse server entries from the config JSON.
  # Each server has: alias, host, port, username, apiVersion, useHTTPS
  # We look for blocks that contain "alias" and "host" fields.

  # Use awk to extract server objects and emit tab-separated fields
  awk '
  BEGIN { in_server=0; alias_val=""; host_val=""; port_val="8000"; user_val="admin"; api_val="v1"; https_val="false" }
  /{/ { in_server=1; alias_val=""; host_val=""; port_val="8000"; user_val="admin"; api_val="v1"; https_val="false" }
  /"alias"/ {
    match($0, /"alias"[[:space:]]*:[[:space:]]*"([^"]*)"/, m)
    if (m[1] != "") alias_val = m[1]
  }
  /"host"/ {
    # Avoid matching sourceHost, targetHost etc.
    if ($0 ~ /"host"[[:space:]]*:/) {
      match($0, /"host"[[:space:]]*:[[:space:]]*"([^"]*)"/, m)
      if (m[1] != "") host_val = m[1]
    }
  }
  /"port"/ {
    match($0, /"port"[[:space:]]*:[[:space:]]*"?([0-9]+)"?/, m)
    if (m[1] != "") port_val = m[1]
  }
  /"username"/ {
    match($0, /"username"[[:space:]]*:[[:space:]]*"([^"]*)"/, m)
    if (m[1] != "") user_val = m[1]
  }
  /"apiVersion"/ {
    match($0, /"apiVersion"[[:space:]]*:[[:space:]]*"([^"]*)"/, m)
    if (m[1] != "") api_val = m[1]
  }
  /"useHTTPS"/ {
    if ($0 ~ /true/) https_val = "true"
    else https_val = "false"
  }
  /}/ {
    if (in_server && alias_val != "" && host_val != "") {
      printf "%s\t%s\t%s\t%s\t%s\t%s\n", alias_val, host_val, port_val, user_val, api_val, https_val
    }
    in_server=0
  }
  ' "$config_file"
}

# ── Pure-bash JSON list extraction from files ─────────────────────────────────

# Extract "dirlist" array values from a JSON file
json_get_string_array() {
  local file="$1"
  local key="$2"
  if [[ ! -f "$file" ]]; then
    return
  fi
  # Extract the array contents after the key, then pull out quoted strings
  local raw
  raw="$(grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\[[^]]*\]" "$file" 2>/dev/null | head -1 | sed "s/\"${key}\"[[:space:]]*:[[:space:]]*\[//;s/\]$//")"
  if [[ -n "$raw" ]]; then
    echo "$raw" | grep -o '"[^"]*"' | sed 's/"//g'
  fi
}

# ── Build job NDJSON line ────────────────────────────────────────────────────

build_job_ndjson() {
  local jobID="$1" label="$2" status="$3" completion="$4" runat="$5" err="$6"
  printf '{"jobID":%s,"label":%s,"status":%s,"completion":%s,"runat":%s,"error":%s}\n' \
    "$(json_str_or_null "$jobID")" \
    "$(json_str_or_null "$label")" \
    "$(json_str_or_null "$status")" \
    "$(json_str_or_null "$completion")" \
    "$(json_str_or_null "$runat")" \
    "$(json_str_or_null "$err")"
}

# ── curl_request ──────────────────────────────────────────────────────────────

curl_request() {
  local method="$1"
  local url="$2"
  local output_file="$3"
  shift 3

  local insecure_arg=""
  if (( ALLOW_INSECURE_TLS == 1 )); then
    insecure_arg="-k"
  fi

  local status
  status="$(curl -s ${insecure_arg:+$insecure_arg} \
    -u "${CURL_AUTH_USERPASS}" \
    -H "Accept: application/json" \
    "$@" \
    "$url" \
    -o "$output_file" \
    -w "%{http_code}")"

  if [[ "$status" =~ ^2[0-9][0-9]$ ]]; then
    return 0
  fi

  echo "HTTP $status for $method $url" >&2
  if [[ -s "$output_file" ]]; then
    echo "Response (first 300 chars): $(head -c 300 "$output_file")" >&2
  fi
  if [[ "$status" == "400" && "$url" == *"/general/srvinfo" ]]; then
    echo "Hint: this can happen when server requires HTTPS but useHTTPS=false." >&2
  fi
  return 1
}

auth_preflight() {
  local scheme="http"
  if [[ "$USE_HTTPS" == "true" ]]; then
    scheme="https"
  fi
  local url="${scheme}://${HOST}:${PORT}/rest/${API_VERSION}/general/srvinfo"
  local tmp
  tmp="$(mktemp)"

  if curl_request "GET" "$url" "$tmp"; then
    rm -f "$tmp"
    return 0
  fi

  rm -f "$tmp"
  return 1
}

choose_checks() {
  if (( NON_INTERACTIVE == 1 )); then
    RUN_SERVER_INFO=1
    RUN_DEVICES=1
    RUN_WARNINGS=1
    RUN_ERRORS=1
    RUN_RUNNING=1
    RUN_VOLUMES=1
    RUN_JUKEBOXES=1
    RUN_LICENCE=1
    RUN_PLANS=1
    return
  fi

  echo
  echo "Choose checks to run (comma-separated numbers or 'all'):"
  echo "  1) Server info + uptime"
  echo "  2) Devices (cleaning needed)"
  echo "  3) Job warnings"
  echo "  4) Job errors"
  echo "  5) Running jobs"
  echo "  6) Volumes + mode counts + CSV"
  echo "  7) Jukeboxes (slot count + volumes loaded)"
  echo "  8) Licence resources (free counts)"
  echo "  9) Plans export (all/archive/backup/sync markdown)"
  local choice
  read -r -p "Selection [all]: " choice
  choice="$(to_lower "$(trim "$choice")")"
  if [[ -z "$choice" || "$choice" == "all" ]]; then
    RUN_SERVER_INFO=1
    RUN_DEVICES=1
    RUN_WARNINGS=1
    RUN_ERRORS=1
    RUN_RUNNING=1
    RUN_VOLUMES=1
    RUN_JUKEBOXES=1
    RUN_LICENCE=1
    RUN_PLANS=1
    return
  fi
  RUN_SERVER_INFO=0
  RUN_DEVICES=0
  RUN_WARNINGS=0
  RUN_ERRORS=0
  RUN_RUNNING=0
  RUN_VOLUMES=0
  RUN_JUKEBOXES=0
  RUN_LICENCE=0
  RUN_PLANS=0
  IFS=',' read -r -a items <<< "$choice"
  local item
  for item in "${items[@]}"; do
    item="$(trim "$item")"
    case "$item" in
      1) RUN_SERVER_INFO=1 ;;
      2) RUN_DEVICES=1 ;;
      3) RUN_WARNINGS=1 ;;
      4) RUN_ERRORS=1 ;;
      5) RUN_RUNNING=1 ;;
      6) RUN_VOLUMES=1 ;;
      7) RUN_JUKEBOXES=1 ;;
      8) RUN_LICENCE=1 ;;
      9) RUN_PLANS=1 ;;
      *) ;;
    esac
  done
}

# ── Main health check function ────────────────────────────────────────────────

run_server_health_check() {
  local alias_safe timestamp base_name
  alias_safe="$(safe_name "$ALIAS")"
  timestamp="$(date '+%Y%m%d-%H%M%S')"
  base_name="${alias_safe}-${timestamp}"

  local workdir
  workdir="$(mktemp -d)"
  trap '[[ -n "${workdir:-}" ]] && rm -rf "${workdir}"' RETURN

  local report_json="$OUT_DIR/${base_name}-report.json"
  local connectivity_csv="$OUT_DIR/${base_name}-connectivity.csv"
  local volumes_csv="$OUT_DIR/${base_name}-volumes.csv"
  local warnings_csv="$OUT_DIR/${base_name}-warnings.csv"
  local errors_csv="$OUT_DIR/${base_name}-errors.csv"
  local all_jobs_csv="$OUT_DIR/${base_name}-all-job-results.csv"
  local running_csv="$OUT_DIR/${base_name}-running.csv"
  local recyclable_backup_csv="$OUT_DIR/${base_name}-recyclable-backup-volumes.csv"
  local all_plans_md="$OUT_DIR/${base_name}-all-plans.md"
  local archive_plans_md="$OUT_DIR/${base_name}-archive-plans.md"
  local backup_plans_md="$OUT_DIR/${base_name}-backup-plans.md"
  local sync_plans_md="$OUT_DIR/${base_name}-sync-plans.md"

  local srvinfo_file="$workdir/srvinfo.json"
  local dev_list_file="$workdir/devices-list.json"
  local warn_list_file="$workdir/warn-list.json"
  local err_list_file="$workdir/err-list.json"
  local run_list_file="$workdir/run-list.json"
  local vol_list_file="$workdir/vol-list.json"

  echo
  echo "Running checks for: $ALIAS ($HOST:$PORT, user=$USERNAME, api=$API_VERSION, https=$USE_HTTPS)"

  local scheme="http"
  if [[ "$USE_HTTPS" == "true" ]]; then
    scheme="https"
  fi
  local base_url="${scheme}://${HOST}:${PORT}/rest/${API_VERSION}"

  local hostname="" lexxvers="" platform="" uptime=""
  local connectivity_reachable=0
  local connectivity_response_ms=0
  local connectivity_captured_at=""
  local skipped_due_to_connectivity=0
  local needs_cleaning_count=0
  local warning_count=0
  local error_count=0
  local running_count=0
  local appendable_count=0
  local readonly_count=0
  local full_count=0
  local recyclable_count=0
  local total_error_count=0
  local plan_total_count=0
  local archive_plan_count=0
  local backup_plan_count=0
  local sync_plan_count=0

  local devices_json='[]'
  local warnings_json='[]'
  local errors_json='[]'
  local running_json='[]'
  local volumes_json='[]'
  local jukeboxes_json='[]'
  local licence_json='[]'
  local plans_json='[]'

  connectivity_captured_at="$(now_iso)"
  local probe_started_ms probe_finished_ms
  probe_started_ms="$(now_millis)"
  if curl_request "GET" "$base_url/general/srvinfo" "$srvinfo_file"; then
    connectivity_reachable=1
    hostname="$(json_get "$srvinfo_file" "hostname")"
    lexxvers="$(json_get "$srvinfo_file" "lexxvers")"
    platform="$(json_get "$srvinfo_file" "platform")"
    uptime="$(json_get "$srvinfo_file" "uptime")"
  else
    connectivity_reachable=0
    skipped_due_to_connectivity=1
  fi
  probe_finished_ms="$(now_millis)"
  connectivity_response_ms=$((probe_finished_ms - probe_started_ms))

  # ── Connectivity CSV ──────────────────────────────────────────────────────
  local reachable_text="false"
  if (( connectivity_reachable == 1 )); then
    reachable_text="true"
  fi
  {
    csv_row "Captured At" "Alias" "Host" "Port" "Reachable" "Response MS" "Uptime Seconds" "Uptime Human"
    csv_row "$connectivity_captured_at" "$ALIAS" "$HOST" "$PORT" "$reachable_text" "$connectivity_response_ms" "$uptime" "$(format_uptime "$uptime")"
  } > "$connectivity_csv"

  # ── Devices ─────────────────────────────────────────────────────────────────
  if (( RUN_DEVICES == 1 && connectivity_reachable == 1 )); then
    curl_request "GET" "$base_url/general/devices" "$dev_list_file"
    : > "$workdir/devices.ndjson"
    while IFS= read -r device_id; do
      local dfile="$workdir/device-${device_id}.json"
      curl_request "GET" "$base_url/general/devices/${device_id}" "$dfile"
      local cleaning
      cleaning="$(json_get "$dfile" "cleaning")"
      if [[ "$cleaning" == "true" ]]; then
        needs_cleaning_count=$((needs_cleaning_count + 1))
      fi
      local cleaning_bool="false"
      if [[ "$cleaning" == "true" ]]; then
        cleaning_bool="true"
      fi
      printf '{"id":"%s","cleaning":%s}\n' "$(json_escape "$device_id")" "$cleaning_bool" >> "$workdir/devices.ndjson"
    done < <(json_ids_to_lines "$dev_list_file" "devices")

    devices_json="$(ndjson_to_array "$workdir/devices.ndjson")"
  fi

  # ── Warning jobs ────────────────────────────────────────────────────────────
  if (( RUN_WARNINGS == 1 && connectivity_reachable == 1 )); then
    curl_request "GET" "$base_url/general/jobs" "$warn_list_file" -H "filter: warning" -H "lastdays: ${LOOKBACK_DAYS}"
    warning_count="$(json_count_ids "$warn_list_file" "jobs")"
    : > "$workdir/warnings.ndjson"
    : > "$warnings_csv"
    csv_row "Job ID" "Label" "Status" "Completion" "Run At" "Error" > "$warnings_csv"
    while IFS= read -r job_id; do
      local jfile="$workdir/warn-job-${job_id}.json"
      local pfile="$workdir/warn-proto-${job_id}.json"
      curl_request "GET" "$base_url/general/jobs/${job_id}" "$jfile"
      local label status completion runat err
      label="$(json_get "$jfile" "label")"
      status="$(json_get "$jfile" "status")"
      completion="$(json_get "$jfile" "completion")"
      runat="$(json_get "$jfile" "runat")"
      err="$(json_get "$jfile" "error")"

      if curl_request "GET" "$base_url/general/jobs/${job_id}/protocol" "$pfile" -H "format: json"; then
        local proto
        proto="$(extract_protocol_summary "$pfile")"
        if [[ -n "$proto" ]]; then
          if [[ -n "$err" ]]; then
            err="${err} | ${proto}"
          else
            err="$proto"
          fi
        fi
      fi

      build_job_ndjson "$job_id" "$label" "$status" "$completion" "$runat" "$err" >> "$workdir/warnings.ndjson"
      csv_row "$job_id" "$label" "$status" "$completion" "$runat" "$err" >> "$warnings_csv"
    done < <(json_ids_to_lines "$warn_list_file" "jobs")

    warnings_json="$(ndjson_to_array "$workdir/warnings.ndjson")"
  fi

  # ── Error jobs ──────────────────────────────────────────────────────────────
  if (( RUN_ERRORS == 1 && connectivity_reachable == 1 )); then
    curl_request "GET" "$base_url/general/jobs" "$err_list_file" -H "filter: failed" -H "lastdays: ${LOOKBACK_DAYS}"
    error_count="$(json_count_ids "$err_list_file" "jobs")"
    : > "$workdir/errors.ndjson"
    : > "$errors_csv"
    csv_row "Job ID" "Label" "Status" "Completion" "Run At" "Error" > "$errors_csv"
    while IFS= read -r job_id; do
      local jfile="$workdir/err-job-${job_id}.json"
      local pfile="$workdir/err-proto-${job_id}.json"
      curl_request "GET" "$base_url/general/jobs/${job_id}" "$jfile"
      local label status completion runat err
      label="$(json_get "$jfile" "label")"
      status="$(json_get "$jfile" "status")"
      completion="$(json_get "$jfile" "completion")"
      runat="$(json_get "$jfile" "runat")"
      err="$(json_get "$jfile" "error")"

      if curl_request "GET" "$base_url/general/jobs/${job_id}/protocol" "$pfile" -H "format: json"; then
        local proto
        proto="$(extract_protocol_summary "$pfile")"
        if [[ -n "$proto" ]]; then
          if [[ -n "$err" ]]; then
            err="${err} | ${proto}"
          else
            err="$proto"
          fi
        fi
      fi

      build_job_ndjson "$job_id" "$label" "$status" "$completion" "$runat" "$err" >> "$workdir/errors.ndjson"
      csv_row "$job_id" "$label" "$status" "$completion" "$runat" "$err" >> "$errors_csv"
    done < <(json_ids_to_lines "$err_list_file" "jobs")

    errors_json="$(ndjson_to_array "$workdir/errors.ndjson")"
  fi

  # ── Running jobs ────────────────────────────────────────────────────────────
  if (( RUN_RUNNING == 1 && connectivity_reachable == 1 )); then
    curl_request "GET" "$base_url/general/jobs" "$run_list_file" -H "filter: running"
    running_count="$(json_count_ids "$run_list_file" "jobs")"
    : > "$workdir/running.ndjson"
    : > "$running_csv"
    csv_row "Job ID" "Label" "Status" "Completion" "Run At" "Error" > "$running_csv"
    while IFS= read -r job_id; do
      local jfile="$workdir/run-job-${job_id}.json"
      curl_request "GET" "$base_url/general/jobs/${job_id}" "$jfile"
      local label status completion runat err
      label="$(json_get "$jfile" "label")"
      status="$(json_get "$jfile" "status")"
      completion="$(json_get "$jfile" "completion")"
      runat="$(json_get "$jfile" "runat")"
      err="$(json_get "$jfile" "error")"

      build_job_ndjson "$job_id" "$label" "$status" "$completion" "$runat" "$err" >> "$workdir/running.ndjson"
      csv_row "$job_id" "$label" "$status" "$completion" "$runat" "$err" >> "$running_csv"
    done < <(json_ids_to_lines "$run_list_file" "jobs")

    running_json="$(ndjson_to_array "$workdir/running.ndjson")"
  fi

  # ── All-jobs CSV merge ──────────────────────────────────────────────────────
  if (( RUN_WARNINGS == 1 || RUN_ERRORS == 1 )); then
    # Merge warnings + errors NDJSON, deduplicate by jobID, sort, write CSV
    csv_row "Job ID" "Label" "Status" "Completion" "Run At" "Error" > "$all_jobs_csv"

    local merge_tmp="$workdir/merge-all-jobs.tmp"
    : > "$merge_tmp"
    for ndf in "$workdir/errors.ndjson" "$workdir/warnings.ndjson"; do
      if [[ -f "$ndf" ]]; then
        while IFS= read -r line; do
          line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
          if [[ -z "$line" ]]; then
            continue
          fi
          local jid
          jid="$(echo "$line" | grep -o '"jobID"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"jobID"[[:space:]]*:[[:space:]]*"//;s/"$//')"
          echo "${jid}|${line}" >> "$merge_tmp"
        done < "$ndf"
      fi
    done

    # Deduplicate by jobID (first column), sort
    sort -t'|' -k1,1 -u "$merge_tmp" | while IFS= read -r mline; do
      local json_part="${mline#*|}"
      local jid label_v status_v comp_v runat_v err_v
      jid="$(echo "$json_part" | grep -o '"jobID"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"jobID"[[:space:]]*:[[:space:]]*"//;s/"$//')"
      label_v="$(echo "$json_part" | grep -o '"label"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"label"[[:space:]]*:[[:space:]]*"//;s/"$//')"
      status_v="$(echo "$json_part" | grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"status"[[:space:]]*:[[:space:]]*"//;s/"$//')"
      comp_v="$(echo "$json_part" | grep -o '"completion"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"completion"[[:space:]]*:[[:space:]]*"//;s/"$//')"
      runat_v="$(echo "$json_part" | grep -o '"runat"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"runat"[[:space:]]*:[[:space:]]*"//;s/"$//')"
      err_v="$(echo "$json_part" | grep -o '"error"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"error"[[:space:]]*:[[:space:]]*"//;s/"$//')"
      # Handle null values (grep won't match null, so they stay empty — which is correct)
      csv_row "$jid" "$label_v" "$status_v" "$comp_v" "$runat_v" "$err_v"
    done >> "$all_jobs_csv"
    rm -f "$merge_tmp"
  fi

  # ── Volumes ─────────────────────────────────────────────────────────────────
  if (( RUN_VOLUMES == 1 && connectivity_reachable == 1 )); then
    curl_request "GET" "$base_url/general/volumes" "$vol_list_file"
    : > "$workdir/volumes.ndjson"
    : > "$volumes_csv"
    csv_row "Volume ID" "Label" "Barcode" "Location" "Mode" "Usage" "State" "Media Type" "Used Size (KBytes)" "Total Size (KBytes)" "Used Size (Human)" "Total Size (Human)" "Last Used" "Use Count" "Error Count" > "$volumes_csv"

    local count=0
    while IFS= read -r vol_id; do
      if [[ "$MAX_VOLUME_DETAILS" != "0" && "$count" -ge "$MAX_VOLUME_DETAILS" ]]; then
        break
      fi
      local vfile="$workdir/volume-${vol_id}.json"
      curl_request "GET" "$base_url/general/volumes/${vol_id}" "$vfile"

      local label barcode location mode usage state mediatype usedsize totalsize
      local dateused usecount hardwrercnt softwrercnt hardrdercnt softrdercnt
      label="$(json_get "$vfile" "label")"
      barcode="$(json_get "$vfile" "barcode")"
      location="$(json_get "$vfile" "location")"
      mode="$(json_get "$vfile" "mode")"
      usage="$(json_get "$vfile" "usage")"
      state="$(json_get "$vfile" "state")"
      mediatype="$(json_get "$vfile" "mediatype")"
      usedsize="$(json_get "$vfile" "usedsize")"
      totalsize="$(json_get "$vfile" "totalsize")"
      dateused="$(json_get "$vfile" "dateused")"
      usecount="$(json_get "$vfile" "usecount")"
      hardwrercnt="$(json_get "$vfile" "hardWrErCnt")"
      softwrercnt="$(json_get "$vfile" "softWrErCnt")"
      hardrdercnt="$(json_get "$vfile" "hardRdErCnt")"
      softrdercnt="$(json_get "$vfile" "softRdErCnt")"
      local used_human total_human
      used_human="$(kbytes_human "$usedsize")"
      total_human="$(kbytes_human "$totalsize")"

      # Sum total errors for this volume
      local vol_errors=0
      for ec in "$hardwrercnt" "$softwrercnt" "$hardrdercnt" "$softrdercnt"; do
        if [[ "$ec" =~ ^[0-9]+$ ]]; then
          vol_errors=$((vol_errors + ec))
        fi
      done
      total_error_count=$((total_error_count + vol_errors))

      case "$(to_lower "$mode")" in
        appendable)  appendable_count=$((appendable_count + 1)) ;;
        readonly)    readonly_count=$((readonly_count + 1)) ;;
        full)        full_count=$((full_count + 1)) ;;
        recyclable)  recyclable_count=$((recyclable_count + 1)) ;;
        *) ;;
      esac

      csv_row "$vol_id" "$label" "$barcode" "$location" "$mode" "$usage" "$state" "$mediatype" \
        "$usedsize" "$totalsize" "$used_human" "$total_human" \
        "$dateused" "$usecount" "$vol_errors" >> "$volumes_csv"

      # Build volume NDJSON
      printf '{"volumeID":%s,"label":%s,"barcode":%s,"location":%s,"mode":%s,"usage":%s,"state":%s,"mediatype":%s,"usedsize":%s,"totalsize":%s,"usedHuman":%s,"totalHuman":%s,"dateused":%s,"usecount":%s,"hardWrErCnt":%s,"softWrErCnt":%s,"hardRdErCnt":%s,"softRdErCnt":%s,"totalErrors":%s}\n' \
        "$(json_str_or_null "$vol_id")" \
        "$(json_str_or_null "$label")" \
        "$(json_str_or_null "$barcode")" \
        "$(json_str_or_null "$location")" \
        "$(json_str_or_null "$mode")" \
        "$(json_str_or_null "$usage")" \
        "$(json_str_or_null "$state")" \
        "$(json_str_or_null "$mediatype")" \
        "$(json_str_or_null "$usedsize")" \
        "$(json_str_or_null "$totalsize")" \
        "$(json_str_or_null "$used_human")" \
        "$(json_str_or_null "$total_human")" \
        "$(json_str_or_null "$dateused")" \
        "$(json_int_or_null "$usecount")" \
        "$(json_int_or_null "$hardwrercnt")" \
        "$(json_int_or_null "$softwrercnt")" \
        "$(json_int_or_null "$hardrdercnt")" \
        "$(json_int_or_null "$softrdercnt")" \
        "$(json_int_or_null "$vol_errors")" >> "$workdir/volumes.ndjson"
      count=$((count + 1))
    done < <(json_ids_to_lines "$vol_list_file" "volumes")

    volumes_json="$(ndjson_to_array "$workdir/volumes.ndjson")"

    # ── Recyclable Backup Volumes CSV ──
    {
      csv_row "Volume ID" "Label" "Barcode" "Location" "State" "Media Type" \
        "Used Size (Human)" "Total Size (Human)" "Last Used" "Use Count" "Error Count"
      if [[ -f "$workdir/volumes.ndjson" ]]; then
        while IFS= read -r vline; do
          vline="$(echo "$vline" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
          if [[ -z "$vline" ]]; then
            continue
          fi
          local v_mode v_usage
          v_mode="$(echo "$vline" | grep -o '"mode"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"mode"[[:space:]]*:[[:space:]]*"//;s/"$//' | tr '[:upper:]' '[:lower:]')"
          v_usage="$(echo "$vline" | grep -o '"usage"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"usage"[[:space:]]*:[[:space:]]*"//;s/"$//' | tr '[:upper:]' '[:lower:]')"
          if [[ "$v_mode" == "recyclable" && "$v_usage" == "backup" ]]; then
            local rv_id rv_label rv_barcode rv_location rv_state rv_mediatype rv_usedHuman rv_totalHuman rv_dateused rv_usecount rv_totalErrors
            rv_id="$(echo "$vline" | grep -o '"volumeID"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"volumeID"[[:space:]]*:[[:space:]]*"//;s/"$//')"
            rv_label="$(echo "$vline" | grep -o '"label"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"label"[[:space:]]*:[[:space:]]*"//;s/"$//')"
            rv_barcode="$(echo "$vline" | grep -o '"barcode"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"barcode"[[:space:]]*:[[:space:]]*"//;s/"$//')"
            rv_location="$(echo "$vline" | grep -o '"location"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"location"[[:space:]]*:[[:space:]]*"//;s/"$//')"
            rv_state="$(echo "$vline" | grep -o '"state"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"state"[[:space:]]*:[[:space:]]*"//;s/"$//')"
            rv_mediatype="$(echo "$vline" | grep -o '"mediatype"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"mediatype"[[:space:]]*:[[:space:]]*"//;s/"$//')"
            rv_usedHuman="$(echo "$vline" | grep -o '"usedHuman"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"usedHuman"[[:space:]]*:[[:space:]]*"//;s/"$//')"
            rv_totalHuman="$(echo "$vline" | grep -o '"totalHuman"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"totalHuman"[[:space:]]*:[[:space:]]*"//;s/"$//')"
            rv_dateused="$(echo "$vline" | grep -o '"dateused"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"dateused"[[:space:]]*:[[:space:]]*"//;s/"$//')"
            rv_usecount="$(echo "$vline" | grep -o '"usecount"[[:space:]]*:[[:space:]]*[0-9]*' | head -1 | sed 's/.*"usecount"[[:space:]]*:[[:space:]]*//')"
            rv_totalErrors="$(echo "$vline" | grep -o '"totalErrors"[[:space:]]*:[[:space:]]*[0-9]*' | head -1 | sed 's/.*"totalErrors"[[:space:]]*:[[:space:]]*//')"
            csv_row "$rv_id" "$rv_label" "$rv_barcode" "$rv_location" "$rv_state" "$rv_mediatype" \
              "$rv_usedHuman" "$rv_totalHuman" "$rv_dateused" "$rv_usecount" "$rv_totalErrors"
          fi
        done < "$workdir/volumes.ndjson"
      fi
    } > "$recyclable_backup_csv"
  fi

  # ── Jukeboxes ───────────────────────────────────────────────────────────────
  local jukebox_count=0
  if (( RUN_JUKEBOXES == 1 && connectivity_reachable == 1 )); then
    local jb_list_file="$workdir/jb-list.json"
    if curl_request "GET" "$base_url/general/jukeboxes" "$jb_list_file"; then
      : > "$workdir/jukeboxes.ndjson"
      while IFS= read -r jb_id; do
        local jb_detail_file="$workdir/jb-${jb_id}.json"
        local jb_vols_file="$workdir/jb-${jb_id}-vols.json"
        local slotcount=0 volcount=0
        if curl_request "GET" "$base_url/general/jukeboxes/${jb_id}" "$jb_detail_file"; then
          slotcount="$(json_get "$jb_detail_file" "slotcount")"
          slotcount="${slotcount:-0}"
        fi
        if curl_request "GET" "$base_url/general/jukeboxes/${jb_id}/volumes" "$jb_vols_file"; then
          volcount="$(json_count_ids "$jb_vols_file" "volumes")"
        fi
        local sc_int=0 vc_int=0
        [[ "$slotcount" =~ ^[0-9]+$ ]] && sc_int="$slotcount"
        [[ "$volcount" =~ ^[0-9]+$ ]] && vc_int="$volcount"
        printf '{"jukeboxID":"%s","slotCount":%s,"volumeCount":%s}\n' \
          "$(json_escape "$jb_id")" "$sc_int" "$vc_int" >> "$workdir/jukeboxes.ndjson"
        jukebox_count=$((jukebox_count + 1))
      done < <(json_ids_to_lines "$jb_list_file" "jukeboxes")

      jukeboxes_json="$(ndjson_to_array "$workdir/jukeboxes.ndjson")"
    else
      echo "  [INFO] Jukeboxes: endpoint not available or no jukeboxes configured." >&2
    fi
  fi

  # ── Licence resources ───────────────────────────────────────────────────────
  local licence_alert_count=0
  local licence_warn_count=0
  if (( RUN_LICENCE == 1 && connectivity_reachable == 1 )); then
    local lic_list_file="$workdir/lic-list.json"
    if curl_request "GET" "$base_url/license/resources" "$lic_list_file"; then
      : > "$workdir/licence.ndjson"
      while IFS= read -r res_id; do
        local lic_detail_file="$workdir/lic-${res_id}.json"
        local free_count=""
        if curl_request "GET" "$base_url/license/resources/${res_id}" "$lic_detail_file"; then
          free_count="$(json_get "$lic_detail_file" "free")"
        fi
        # -1 = unlimited; skip alerting
        if [[ "$free_count" =~ ^-?[0-9]+$ && "$free_count" != "-1" ]]; then
          if [[ "$free_count" == "0" ]]; then
            echo "  [ALERT] Licence depleted: ${res_id} — free=0"
            licence_alert_count=$((licence_alert_count + 1))
          elif (( free_count <= 2 )); then
            echo "  [WARN]  Licence low:      ${res_id} — free=${free_count}"
            licence_warn_count=$((licence_warn_count + 1))
          fi
        fi
        local lic_status="ok"
        if [[ "$free_count" =~ ^-?[0-9]+$ ]]; then
          if [[ "$free_count" == "-1" ]]; then
            lic_status="unlimited"
          elif [[ "$free_count" == "0" ]]; then
            lic_status="depleted"
          elif (( free_count <= 2 )); then
            lic_status="low"
          fi
        fi
        printf '{"resourceID":"%s","free":%s,"status":"%s"}\n' \
          "$(json_escape "$res_id")" \
          "$(json_int_or_null "$free_count")" \
          "$lic_status" >> "$workdir/licence.ndjson"
      done < <(json_ids_to_lines "$lic_list_file" "resources")

      licence_json="$(ndjson_to_array "$workdir/licence.ndjson")"
    else
      echo "  [INFO] Licence: endpoint not available." >&2
    fi
  fi

  # ── Plans ───────────────────────────────────────────────────────────────────
  if (( RUN_PLANS == 1 && connectivity_reachable == 1 )); then
    local plans_ndjson="$workdir/plans.ndjson"
    : > "$plans_ndjson"

    # ── Archive plans ──
    local archive_plan_list_file="$workdir/archive-plans-list.json"
    if curl_request "GET" "$base_url/archive/plans" "$archive_plan_list_file"; then
      while IFS= read -r plan_id; do
        local ap_file="$workdir/archive-plan-${plan_id}.json"
        if ! curl_request "GET" "$base_url/archive/plans/${plan_id}" "$ap_file"; then
          continue
        fi
        local ap_desc ap_enabled ap_database ap_pool ap_autostart
        ap_desc="$(json_get "$ap_file" "description")"
        ap_enabled="$(json_get "$ap_file" "enabled")"
        ap_database="$(json_get "$ap_file" "database")"
        ap_pool="$(json_get "$ap_file" "pool")"
        ap_autostart="$(json_get "$ap_file" "autostart")"

        local notes_arr=""
        if [[ -n "$ap_database" ]]; then
          notes_arr="${notes_arr}\"Database: $(json_escape "$ap_database")\","
        fi
        if [[ -n "$ap_pool" ]]; then
          notes_arr="${notes_arr}\"Pool: $(json_escape "$ap_pool")\","
        fi
        if [[ -n "$ap_autostart" ]]; then
          local autostart_state="Disabled"
          local as_lower
          as_lower="$(to_lower "$ap_autostart")"
          case "$as_lower" in
            true|1|yes) autostart_state="Enabled" ;;
          esac
          notes_arr="${notes_arr}\"Autostart: ${autostart_state}\","
        fi
        # Remove trailing comma
        notes_arr="${notes_arr%,}"

        printf '{"kind":"Archive","planID":"%s","description":%s,"enabled":%s,"sourceHost":null,"sourcePaths":[],"targetHost":null,"targetPaths":[],"schedule":[],"notes":[%s]}\n' \
          "$(json_escape "$plan_id")" \
          "$(json_str_or_null "$ap_desc")" \
          "$(json_bool "$ap_enabled")" \
          "$notes_arr" >> "$plans_ndjson"
      done < <(json_ids_to_lines_flexible "$archive_plan_list_file" "plans")
    else
      echo "  [INFO] Archive plans: endpoint not available." >&2
    fi

    # ── Backup plans ──
    local backup_plan_list_file="$workdir/backup-plans-list.json"
    if curl_request "GET" "$base_url/backup/plans" "$backup_plan_list_file"; then
      while IFS= read -r plan_id; do
        local bp_file="$workdir/backup-plan-${plan_id}.json"
        local bp_task_list_file="$workdir/backup-plan-${plan_id}-tasks-list.json"
        local bp_event_list_file="$workdir/backup-plan-${plan_id}-events-list.json"
        local bp_hosts_file="$workdir/backup-plan-${plan_id}-hosts.txt"
        local bp_paths_file="$workdir/backup-plan-${plan_id}-paths.txt"
        local bp_pools_file="$workdir/backup-plan-${plan_id}-pools.txt"
        local bp_schedule_file="$workdir/backup-plan-${plan_id}-schedule.ndjson"
        : > "$bp_hosts_file"
        : > "$bp_paths_file"
        : > "$bp_pools_file"
        : > "$bp_schedule_file"

        if ! curl_request "GET" "$base_url/backup/plans/${plan_id}" "$bp_file"; then
          continue
        fi

        if curl_request "GET" "$base_url/backup/plans/${plan_id}/tasks/" "$bp_task_list_file"; then
          while IFS= read -r task_id; do
            local bt_file="$workdir/backup-plan-${plan_id}-task-${task_id}.json"
            if ! curl_request "GET" "$base_url/backup/plans/${plan_id}/tasks/${task_id}" "$bt_file"; then
              continue
            fi
            local client
            client="$(json_get "$bt_file" "client")"
            if [[ -n "$client" ]]; then
              echo "$client" >> "$bp_hosts_file"
            fi
            # Extract dirlist paths
            json_get_string_array "$bt_file" "dirlist" >> "$bp_paths_file"
          done < <(json_ids_to_lines_flexible "$bp_task_list_file" "tasks")
        fi

        if curl_request "GET" "$base_url/backup/plans/${plan_id}/events/" "$bp_event_list_file"; then
          while IFS= read -r event_id; do
            local be_file="$workdir/backup-plan-${plan_id}-event-${event_id}.json"
            if ! curl_request "GET" "$base_url/backup/plans/${plan_id}/events/${event_id}" "$be_file"; then
              continue
            fi
            local pool
            pool="$(json_get "$be_file" "pool")"
            if [[ -n "$pool" ]]; then
              echo "$pool" >> "$bp_pools_file"
            fi
            # Build schedule NDJSON line from event file
            local ev_firstrun ev_duration ev_frequency ev_exception ev_pool
            ev_firstrun="$(json_get "$be_file" "firstrun")"
            ev_duration="$(json_get "$be_file" "duration")"
            ev_frequency="$(json_get "$be_file" "frequency")"
            ev_exception="$(json_get "$be_file" "exception")"
            ev_pool="$(json_get "$be_file" "pool")"
            printf '{"start":null,"firstrun":%s,"interval":null,"duration":%s,"frequency":%s,"exception":%s,"pool":%s}\n' \
              "$(json_str_or_null "$ev_firstrun")" \
              "$(json_str_or_null "$ev_duration")" \
              "$(json_str_or_null "$ev_frequency")" \
              "$(json_str_or_null "$ev_exception")" \
              "$(json_str_or_null "$ev_pool")" >> "$bp_schedule_file"
          done < <(json_ids_to_lines_flexible "$bp_event_list_file" "events")
        fi

        local bp_desc bp_enabled
        bp_desc="$(json_get "$bp_file" "description")"
        bp_enabled="$(json_get "$bp_file" "enabled")"

        # Collect unique hosts
        local hosts_json=""
        if [[ -s "$bp_hosts_file" ]]; then
          hosts_json="$(sort -u "$bp_hosts_file" | paste -sd ',' - | sed 's/^/"/;s/$/"/;s/,/", "/g')"
          # Actually we need a plain string for sourceHost, not array
          hosts_json="$(sort -u "$bp_hosts_file" | paste -sd ',' -)"
        fi

        # Collect unique paths
        local paths_json_arr=""
        if [[ -s "$bp_paths_file" ]]; then
          paths_json_arr="$(sort -u "$bp_paths_file" | while IFS= read -r p; do
            printf '"%s",' "$(json_escape "$p")"
          done | sed 's/,$//')"
        fi

        # Collect unique pools as targetPaths
        local pools_json_arr=""
        if [[ -s "$bp_pools_file" ]]; then
          pools_json_arr="$(sort -u "$bp_pools_file" | while IFS= read -r p; do
            printf '"%s",' "$(json_escape "$p")"
          done | sed 's/,$//')"
        fi

        # Collect schedule
        local schedule_json_arr=""
        if [[ -s "$bp_schedule_file" ]]; then
          schedule_json_arr="$(ndjson_to_array "$bp_schedule_file")"
        else
          schedule_json_arr="[]"
        fi

        printf '{"kind":"Backup","planID":"%s","description":%s,"enabled":%s,"sourceHost":%s,"sourcePaths":[%s],"targetHost":null,"targetPaths":[%s],"schedule":%s,"notes":[]}\n' \
          "$(json_escape "$plan_id")" \
          "$(json_str_or_null "$bp_desc")" \
          "$(json_bool "$bp_enabled")" \
          "$(json_str_or_null "$hosts_json")" \
          "$paths_json_arr" \
          "$pools_json_arr" \
          "$schedule_json_arr" >> "$plans_ndjson"
      done < <(json_ids_to_lines_flexible "$backup_plan_list_file" "plans")
    else
      echo "  [INFO] Backup plans: endpoint not available." >&2
    fi

    # ── Sync plans ──
    local sync_plan_list_file="$workdir/sync-plans-list.json"
    if curl_request "GET" "$base_url/synchronize/plans" "$sync_plan_list_file"; then
      while IFS= read -r plan_id; do
        local sp_file="$workdir/sync-plan-${plan_id}.json"
        local sp_event_list_file="$workdir/sync-plan-${plan_id}-events-list.json"
        local sp_schedule_file="$workdir/sync-plan-${plan_id}-schedule.ndjson"
        : > "$sp_schedule_file"

        if ! curl_request "GET" "$base_url/synchronize/plans/${plan_id}" "$sp_file"; then
          continue
        fi

        if curl_request "GET" "$base_url/synchronize/plans/${plan_id}/events" "$sp_event_list_file"; then
          while IFS= read -r event_id; do
            local se_file="$workdir/sync-plan-${plan_id}-event-${event_id}.json"
            if ! curl_request "GET" "$base_url/synchronize/plans/${plan_id}/events/${event_id}" "$se_file"; then
              continue
            fi
            local ev_start ev_interval ev_duration ev_frequency ev_exception
            ev_start="$(json_get "$se_file" "start")"
            ev_interval="$(json_get "$se_file" "interval")"
            ev_duration="$(json_get "$se_file" "duration")"
            ev_frequency="$(json_get "$se_file" "frequency")"
            ev_exception="$(json_get "$se_file" "exception")"
            printf '{"start":%s,"firstrun":null,"interval":%s,"duration":%s,"frequency":%s,"exception":%s,"pool":null}\n' \
              "$(json_str_or_null "$ev_start")" \
              "$(json_str_or_null "$ev_interval")" \
              "$(json_str_or_null "$ev_duration")" \
              "$(json_str_or_null "$ev_frequency")" \
              "$(json_str_or_null "$ev_exception")" >> "$sp_schedule_file"
          done < <(json_ids_to_lines_flexible "$sp_event_list_file" "events")
        fi

        local sp_desc sp_enabled sp_sourcehost sp_targethost sp_autostart
        sp_desc="$(json_get "$sp_file" "description")"
        sp_enabled="$(json_get "$sp_file" "enabled")"
        sp_sourcehost="$(json_get "$sp_file" "sourcehost")"
        sp_targethost="$(json_get "$sp_file" "targethost")"
        sp_autostart="$(json_get "$sp_file" "autostart")"

        # Extract sourcepath array and targetpath from sync plan file
        local source_paths_arr=""
        if [[ -f "$sp_file" ]]; then
          source_paths_arr="$(json_get_string_array "$sp_file" "sourcepath" | while IFS= read -r sp; do
            if [[ -n "$sp" ]]; then
              printf '"%s",' "$(json_escape "$sp")"
            fi
          done | sed 's/,$//')"
        fi
        local target_path
        target_path="$(json_get "$sp_file" "targetpath")"
        local target_paths_arr=""
        if [[ -n "$target_path" ]]; then
          target_paths_arr="\"$(json_escape "$target_path")\""
        fi

        local sp_notes_arr=""
        if [[ -n "$sp_autostart" ]]; then
          sp_notes_arr="\"Autostart: $(json_escape "$sp_autostart")\""
        fi

        local sp_schedule_json
        if [[ -s "$sp_schedule_file" ]]; then
          sp_schedule_json="$(ndjson_to_array "$sp_schedule_file")"
        else
          sp_schedule_json="[]"
        fi

        printf '{"kind":"Sync","planID":"%s","description":%s,"enabled":%s,"sourceHost":%s,"sourcePaths":[%s],"targetHost":%s,"targetPaths":[%s],"schedule":%s,"notes":[%s]}\n' \
          "$(json_escape "$plan_id")" \
          "$(json_str_or_null "$sp_desc")" \
          "$(json_bool "$sp_enabled")" \
          "$(json_str_or_null "$sp_sourcehost")" \
          "$source_paths_arr" \
          "$(json_str_or_null "$sp_targethost")" \
          "$target_paths_arr" \
          "$sp_schedule_json" \
          "$sp_notes_arr" >> "$plans_ndjson"
      done < <(json_ids_to_lines_flexible "$sync_plan_list_file" "plans")
    else
      echo "  [INFO] Sync plans: endpoint not available." >&2
    fi

    write_plans_markdown "$all_plans_md" "$ALIAS" "$HOST" "$PORT" "all" "$plans_ndjson"
    write_plans_markdown "$archive_plans_md" "$ALIAS" "$HOST" "$PORT" "Archive" "$plans_ndjson"
    write_plans_markdown "$backup_plans_md" "$ALIAS" "$HOST" "$PORT" "Backup" "$plans_ndjson"
    write_plans_markdown "$sync_plans_md" "$ALIAS" "$HOST" "$PORT" "Sync" "$plans_ndjson"

    # Count plans by kind
    plan_total_count=0
    archive_plan_count=0
    backup_plan_count=0
    sync_plan_count=0
    if [[ -f "$plans_ndjson" ]]; then
      while IFS= read -r pline; do
        pline="$(echo "$pline" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if [[ -z "$pline" ]]; then
          continue
        fi
        plan_total_count=$((plan_total_count + 1))
        local pk
        pk="$(echo "$pline" | grep -o '"kind"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"kind"[[:space:]]*:[[:space:]]*"//;s/"$//' | tr '[:upper:]' '[:lower:]')"
        case "$pk" in
          archive) archive_plan_count=$((archive_plan_count + 1)) ;;
          backup) backup_plan_count=$((backup_plan_count + 1)) ;;
          sync) sync_plan_count=$((sync_plan_count + 1)) ;;
        esac
      done < "$plans_ndjson"
    fi

    plans_json="$(ndjson_to_array_sorted "$plans_ndjson")"
  fi

  # ── Needs cleaning text ─────────────────────────────────────────────────────
  local needs_cleaning_text="No"
  if (( needs_cleaning_count > 0 )); then
    needs_cleaning_text="Yes"
  fi

  # ── Build report JSON ──────────────────────────────────────────────────────
  local captured_at_report
  captured_at_report="$(now_iso)"

  local use_https_bool="false"
  if [[ "$(to_lower "$USE_HTTPS")" == "true" ]]; then
    use_https_bool="true"
  fi

  local uptime_int_or_null
  if [[ -n "$uptime" && "$uptime" =~ ^[0-9]+$ ]]; then
    uptime_int_or_null="$uptime"
  else
    uptime_int_or_null="null"
  fi

  local conn_reachable_bool="false"
  if (( connectivity_reachable == 1 )); then
    conn_reachable_bool="true"
  fi

  local cr_info="false" cr_dev="false" cr_warn="false" cr_err="false" cr_run="false"
  local cr_vol="false" cr_jb="false" cr_lic="false" cr_plans="false"
  (( RUN_SERVER_INFO == 1 )) && cr_info="true"
  (( RUN_DEVICES == 1 )) && cr_dev="true"
  (( RUN_WARNINGS == 1 )) && cr_warn="true"
  (( RUN_ERRORS == 1 )) && cr_err="true"
  (( RUN_RUNNING == 1 )) && cr_run="true"
  (( RUN_VOLUMES == 1 )) && cr_vol="true"
  (( RUN_JUKEBOXES == 1 )) && cr_jb="true"
  (( RUN_LICENCE == 1 )) && cr_lic="true"
  (( RUN_PLANS == 1 )) && cr_plans="true"

  cat > "$report_json" <<REPORT_EOF
{
  "capturedAt": "$(json_escape "$captured_at_report")",
  "server": {
    "alias": "$(json_escape "$ALIAS")",
    "host": "$(json_escape "$HOST")",
    "port": "$(json_escape "$PORT")",
    "username": "$(json_escape "$USERNAME")",
    "apiVersion": "$(json_escape "$API_VERSION")",
    "useHTTPS": ${use_https_bool}
  },
  "checksRun": {
    "serverInfo": ${cr_info},
    "devices": ${cr_dev},
    "warnings": ${cr_warn},
    "errors": ${cr_err},
    "running": ${cr_run},
    "volumes": ${cr_vol},
    "jukeboxes": ${cr_jb},
    "licenceResources": ${cr_lic},
    "plans": ${cr_plans}
  },
  "summary": {
    "hostname": $(json_str_or_null "$hostname"),
    "lexxvers": $(json_str_or_null "$lexxvers"),
    "platform": $(json_str_or_null "$platform"),
    "uptimeSeconds": ${uptime_int_or_null},
    "uptimeHuman": $(json_str_or_null "$(format_uptime "$uptime")"),
    "connectivityReachable": ${conn_reachable_bool},
    "connectivityResponseMS": ${connectivity_response_ms},
    "needsCleaning": "$(json_escape "$needs_cleaning_text")",
    "needsCleaningCount": ${needs_cleaning_count},
    "warningCount": ${warning_count},
    "errorCount": ${error_count},
    "runningCount": ${running_count},
    "appendableCount": ${appendable_count},
    "readonlyCount": ${readonly_count},
    "fullCount": ${full_count},
    "recyclableCount": ${recyclable_count},
    "volumeTotalErrors": ${total_error_count},
    "jukeboxCount": ${jukebox_count},
    "licenceAlertCount": ${licence_alert_count},
    "licenceWarnCount": ${licence_warn_count},
    "planTotalCount": ${plan_total_count},
    "archivePlanCount": ${archive_plan_count},
    "backupPlanCount": ${backup_plan_count},
    "syncPlanCount": ${sync_plan_count}
  },
  "devices": ${devices_json},
  "warnings": ${warnings_json},
  "errors": ${errors_json},
  "running": ${running_json},
  "volumes": ${volumes_json},
  "jukeboxes": ${jukeboxes_json},
  "licenceResources": ${licence_json},
  "plans": ${plans_json},
  "connectivity": {
    "capturedAt": $(json_str_or_null "$connectivity_captured_at"),
    "reachable": ${conn_reachable_bool},
    "responseMS": ${connectivity_response_ms},
    "uptimeSeconds": ${uptime_int_or_null},
    "uptimeHuman": $(json_str_or_null "$(format_uptime "$uptime")")
  }
}
REPORT_EOF

  # ── Console summary ─────────────────────────────────────────────────────────
  echo
  echo "Summary for ${ALIAS}:"
  echo "  P5: $( (( connectivity_reachable == 1 )) && echo "Up" || echo "Down" ) (${connectivity_response_ms} ms)"
  if (( RUN_SERVER_INFO == 1 )); then
    echo "  Hostname:     ${hostname:--}"
    echo "  Lexx Version: ${lexxvers:--}"
    echo "  Platform:     ${platform:--}"
    echo "  Uptime:       $(format_uptime "$uptime")"
  fi
  if (( skipped_due_to_connectivity == 1 )); then
    echo "  [WARN]  Server unreachable; skipped detailed API checks for this run."
  fi
  if (( RUN_DEVICES == 1 )); then
    echo "  Needs cleaning: ${needs_cleaning_text} (${needs_cleaning_count} device(s))"
  fi
  if (( RUN_WARNINGS == 1 )); then
    echo "  Warning jobs: ${warning_count}"
  fi
  if (( RUN_ERRORS == 1 )); then
    echo "  Error jobs:   ${error_count}"
  fi
  if (( RUN_RUNNING == 1 )); then
    echo "  Running jobs: ${running_count}"
  fi
  if (( RUN_WARNINGS == 1 || RUN_ERRORS == 1 )); then
    local all_job_count=0
    if [[ -f "$all_jobs_csv" ]]; then
      all_job_count=$(( $(wc -l < "$all_jobs_csv" | awk '{print $1}') - 1 ))
      if (( all_job_count < 0 )); then
        all_job_count=0
      fi
    fi
    echo "  All job results: ${all_job_count}"
  fi
  if (( RUN_VOLUMES == 1 )); then
    echo "  Volume modes: appendable=${appendable_count}, readonly=${readonly_count}, full=${full_count}, recyclable=${recyclable_count}"
    if (( total_error_count > 0 )); then
      echo "  [WARN]  Volume tape errors detected: ${total_error_count} total hard/soft read+write errors across all volumes"
    else
      echo "  Volume tape errors: none"
    fi
  fi
  if (( RUN_JUKEBOXES == 1 )); then
    echo "  Jukeboxes: ${jukebox_count}"
    if (( jukebox_count > 0 )) && [[ -f "$workdir/jukeboxes.ndjson" ]]; then
      while IFS= read -r jb_line; do
        jb_line="$(echo "$jb_line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if [[ -z "$jb_line" ]]; then
          continue
        fi
        local jb_name jb_vc jb_sc
        jb_name="$(echo "$jb_line" | grep -o '"jukeboxID"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"jukeboxID"[[:space:]]*:[[:space:]]*"//;s/"$//')"
        jb_vc="$(echo "$jb_line" | grep -o '"volumeCount"[[:space:]]*:[[:space:]]*[0-9]*' | head -1 | sed 's/.*"volumeCount"[[:space:]]*:[[:space:]]*//')"
        jb_sc="$(echo "$jb_line" | grep -o '"slotCount"[[:space:]]*:[[:space:]]*[0-9]*' | head -1 | sed 's/.*"slotCount"[[:space:]]*:[[:space:]]*//')"
        echo "    ${jb_name}: ${jb_vc} volumes loaded / ${jb_sc} slots"
      done < "$workdir/jukeboxes.ndjson"
    fi
  fi
  if (( RUN_LICENCE == 1 )); then
    echo "  Licence resources: ${licence_alert_count} depleted, ${licence_warn_count} low"
    if [[ -f "$workdir/licence.ndjson" ]]; then
      while IFS= read -r lic_line; do
        lic_line="$(echo "$lic_line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if [[ -z "$lic_line" ]]; then
          continue
        fi
        local lic_rid lic_free lic_stat lic_display lic_tag
        lic_rid="$(echo "$lic_line" | grep -o '"resourceID"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"resourceID"[[:space:]]*:[[:space:]]*"//;s/"$//')"
        lic_free="$(echo "$lic_line" | grep -o '"free"[[:space:]]*:[[:space:]]*-\?[0-9]*' | head -1 | sed 's/.*"free"[[:space:]]*:[[:space:]]*//')"
        lic_stat="$(echo "$lic_line" | grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"status"[[:space:]]*:[[:space:]]*"//;s/"$//')"
        if [[ "$lic_free" == "-1" ]]; then
          lic_display="Unlimited"
        elif [[ -n "$lic_free" ]]; then
          lic_display="$lic_free"
        else
          lic_display="-"
        fi
        lic_tag=""
        if [[ "$lic_stat" == "depleted" ]]; then
          lic_tag=" [ALERT]"
        elif [[ "$lic_stat" == "low" ]]; then
          lic_tag=" [WARN]"
        fi
        echo "    ${lic_rid}: free=${lic_display}${lic_tag}"
      done < "$workdir/licence.ndjson"
    fi
  fi
  if (( RUN_PLANS == 1 )); then
    echo "  Plans: ${plan_total_count} total (archive=${archive_plan_count}, backup=${backup_plan_count}, sync=${sync_plan_count})"
  fi

  echo
  echo "Created files:"
  echo "  - $report_json"
  echo "  - $connectivity_csv"
  if (( RUN_VOLUMES == 1 )); then
    [[ -f "$volumes_csv" ]] && echo "  - $volumes_csv"
    [[ -f "$recyclable_backup_csv" ]] && echo "  - $recyclable_backup_csv"
  fi
  if (( RUN_WARNINGS == 1 )); then
    [[ -f "$warnings_csv" ]] && echo "  - $warnings_csv"
  fi
  if (( RUN_ERRORS == 1 )); then
    [[ -f "$errors_csv" ]] && echo "  - $errors_csv"
  fi
  if (( RUN_RUNNING == 1 )); then
    [[ -f "$running_csv" ]] && echo "  - $running_csv"
  fi
  if (( RUN_WARNINGS == 1 || RUN_ERRORS == 1 )); then
    [[ -f "$all_jobs_csv" ]] && echo "  - $all_jobs_csv"
  fi
  if (( RUN_PLANS == 1 )); then
    [[ -f "$all_plans_md" ]] && echo "  - $all_plans_md"
    [[ -f "$archive_plans_md" ]] && echo "  - $archive_plans_md"
    [[ -f "$backup_plans_md" ]] && echo "  - $backup_plans_md"
    [[ -f "$sync_plans_md" ]] && echo "  - $sync_plans_md"
  fi

  trap - RETURN
  rm -rf "$workdir"
}

# ── Server selection / configuration ──────────────────────────────────────────

select_server_from_config() {
  local config_file="$1"
  local lines
  lines="$(read_config_servers "$config_file")"
  if [[ -z "$lines" ]]; then
    echo ""
    return
  fi

  echo >&2
  echo "Servers from config: $config_file" >&2
  local i=1
  while IFS=$'\t' read -r a h p u v s; do
    echo "  $i) $a ($h:$p, user=$u, api=$v, https=$s)" >&2
    i=$((i + 1))
  done <<< "$lines"

  local pick
  read -r -p "Select server number (or Enter to skip config): " pick >&2
  pick="$(trim "$pick")"
  if [[ -z "$pick" ]]; then
    echo ""
    return
  fi
  if ! [[ "$pick" =~ ^[0-9]+$ ]]; then
    echo ""
    return
  fi

  local idx=1
  while IFS=$'\t' read -r a h p u v s; do
    if (( idx == pick )); then
      echo "$a|$h|$p|$u|$v|$s"
      return
    fi
    idx=$((idx + 1))
  done <<< "$lines"

  echo ""
}

first_server_from_config() {
  local config_file="$1"
  local first
  first="$(read_config_servers "$config_file" | head -n 1 || true)"
  if [[ -z "$first" ]]; then
    echo ""
    return
  fi
  local a h p u v s
  IFS=$'\t' read -r a h p u v s <<< "$first"
  echo "$a|$h|$p|$u|$v|$s"
}

configure_server() {
  local chosen=""
  CURL_AUTH_USERPASS=""

  if (( NON_INTERACTIVE == 1 )); then
    if [[ -n "$HARDCODED_ALIAS" && -n "$HARDCODED_HOST" && -n "$HARDCODED_USERNAME" ]]; then
      ALIAS="$HARDCODED_ALIAS"
      HOST="$HARDCODED_HOST"
      PORT="$HARDCODED_PORT"
      USERNAME="$HARDCODED_USERNAME"
      API_VERSION="$HARDCODED_API_VERSION"
      USE_HTTPS="$(bool_norm "$HARDCODED_USE_HTTPS")"
    elif [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
      chosen="$(first_server_from_config "$CONFIG_FILE")"
      if [[ -n "$chosen" ]]; then
        IFS='|' read -r ALIAS HOST PORT USERNAME API_VERSION USE_HTTPS <<< "$chosen"
      fi
    fi
  else
    if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
      chosen="$(select_server_from_config "$CONFIG_FILE")"
    fi

    if [[ -n "$chosen" ]]; then
      IFS='|' read -r ALIAS HOST PORT USERNAME API_VERSION USE_HTTPS <<< "$chosen"
    else
      ALIAS="$(prompt_default "Server alias" "$HARDCODED_ALIAS")"
      HOST="$(prompt_default "Host/IP" "$HARDCODED_HOST")"
      PORT="$(prompt_default "Port" "$HARDCODED_PORT")"
      USERNAME="$(prompt_default "API username" "$HARDCODED_USERNAME")"
      API_VERSION="$(prompt_default "API version" "$HARDCODED_API_VERSION")"
      local https_raw
      https_raw="$(prompt_default "Use HTTPS (true/false)" "$HARDCODED_USE_HTTPS")"
      USE_HTTPS="$(bool_norm "$https_raw")"
    fi
  fi

  if [[ -z "$ALIAS" || -z "$HOST" || -z "$PORT" || -z "$USERNAME" || -z "$API_VERSION" ]]; then
    if (( NON_INTERACTIVE == 1 )); then
      echo "Server config is incomplete. In -n mode provide hardcoded values in script or use -c with at least one server entry." >&2
    else
      echo "Server config is incomplete." >&2
    fi
    return 1
  fi

  if [[ -n "$OVERRIDE_USERNAME" ]]; then
    USERNAME="$(trim "${OVERRIDE_USERNAME%$'\r'}")"
  fi

  if (( NON_INTERACTIVE == 0 )); then
    USERNAME="$(prompt_default "API username" "$USERNAME")"
    USERNAME="$(trim "${USERNAME%$'\r'}")"
    if [[ -z "$USERNAME" ]]; then
      echo "Username is required." >&2
      return 1
    fi
  fi

  PASSWORD="$HARDCODED_PASSWORD"
  if (( FORCE_PASSWORD_PROMPT == 1 )); then
    PASSWORD=""
  fi

  if [[ -n "$AUTH_OVERRIDE" ]]; then
    CURL_AUTH_USERPASS="$AUTH_OVERRIDE"
    if [[ -z "$OVERRIDE_USERNAME" && "$AUTH_OVERRIDE" == *:* ]]; then
      USERNAME="${AUTH_OVERRIDE%%:*}"
    fi
    return 0
  fi

  local account
  account="$(keychain_account "$USERNAME" "$HOST" "$PORT" "$API_VERSION")"

  local should_try_keychain=0
  if (( NON_INTERACTIVE == 1 )); then
    should_try_keychain=1
  elif (( PREFER_KEYCHAIN == 1 )) && (( FORCE_PASSWORD_PROMPT == 0 )); then
    should_try_keychain=1
  fi

  if [[ -z "$PASSWORD" && "$should_try_keychain" -eq 1 ]]; then
    PASSWORD="$(keychain_get_password "$account")"
    if [[ -n "$PASSWORD" ]]; then
      echo "Using password from Keychain for $account" >&2
    fi
  fi

  if [[ -z "$PASSWORD" ]]; then
    if (( NON_INTERACTIVE == 1 )); then
      echo "Password not found for ${USERNAME}@${HOST}:${PORT}. In -n mode set HARDCODED_PASSWORD or save it first to Keychain." >&2
      return 1
    else
      local raw_auth=""
      prompt_secret_into raw_auth "Credentials as user:pass (recommended, Enter to skip)"
      raw_auth="${raw_auth%$'\r'}"
      if [[ -n "$raw_auth" ]]; then
        if [[ "$raw_auth" != *:* || "$raw_auth" == :* || "$raw_auth" == *: ]]; then
          echo "Invalid format. Use exactly: username:password" >&2
          return 1
        fi
        CURL_AUTH_USERPASS="$raw_auth"
        if [[ "$raw_auth" == *:* ]]; then
          USERNAME="${raw_auth%%:*}"
        fi
        return 0
      fi

      prompt_secret_into PASSWORD "Password for ${USERNAME}@${HOST}:${PORT}"
      local save_choice
      read -r -p "Save password to macOS Keychain? [Y/n]: " save_choice
      save_choice="$(to_lower "$(trim "$save_choice")")"
      if [[ -z "$save_choice" || "$save_choice" == "y" || "$save_choice" == "yes" ]]; then
        keychain_set_password "$account" "$PASSWORD"
        echo "Saved password in Keychain service: $KEYCHAIN_SERVICE"
      fi
    fi
  fi

  # Remove accidental carriage return from paste/input.
  PASSWORD="$(trim "${PASSWORD%$'\r'}")"

  if [[ -z "$PASSWORD" ]]; then
    echo "Password is required." >&2
    return 1
  fi

  CURL_AUTH_USERPASS="${USERNAME}:${PASSWORD}"

  return 0
}

main_loop() {
  if (( NON_INTERACTIVE == 1 )); then
    if ! configure_server; then
      echo "Failed to configure server."
      exit 1
    fi
    if ! auth_preflight; then
      echo "Authentication preflight failed."
      exit 1
    fi
    choose_checks
    run_server_health_check
    return
  fi

  while true; do
    if ! configure_server; then
      echo "Failed to configure server."
      exit 1
    fi

    if ! auth_preflight; then
      echo "Authentication preflight failed. Re-enter credentials."
      FORCE_PASSWORD_PROMPT=1
      if ! configure_server; then
        echo "Failed to configure server."
        exit 1
      fi
      FORCE_PASSWORD_PROMPT=0
      if ! auth_preflight; then
        echo "Authentication still failing."
        local raw_auth_choice
        read -r -p "Try raw auth entry (user:pass) without command-line history? [Y/n]: " raw_auth_choice
        raw_auth_choice="$(to_lower "$(trim "$raw_auth_choice")")"
        if [[ -z "$raw_auth_choice" || "$raw_auth_choice" == "y" || "$raw_auth_choice" == "yes" ]]; then
          local raw_auth
          raw_auth=""
          prompt_secret_into raw_auth "Raw auth user:pass"
          raw_auth="${raw_auth%$'\r'}"
          if [[ -n "$raw_auth" ]]; then
            if [[ "$raw_auth" != *:* || "$raw_auth" == :* || "$raw_auth" == *: ]]; then
              echo "Invalid format. Use exactly: username:password" >&2
              exit 1
            fi
            CURL_AUTH_USERPASS="$raw_auth"
            if [[ "$raw_auth" == *:* ]]; then
              USERNAME="${raw_auth%%:*}"
            fi
            if ! auth_preflight; then
              echo "Authentication still failing with raw auth; aborting."
              exit 1
            fi
          else
            echo "No raw auth entered; aborting."
            exit 1
          fi
        else
          echo "Aborting."
          exit 1
        fi
      fi
    fi

    choose_checks
    run_server_health_check

    local more
    echo
    read -r -p "Check another server? [y/N]: " more
    more="$(to_lower "$(trim "$more")")"
    if [[ "$more" != "y" && "$more" != "yes" ]]; then
      break
    fi
  done
}

main_loop
