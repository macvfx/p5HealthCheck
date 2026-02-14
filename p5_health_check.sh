#!/bin/bash
set -euo pipefail

# Optional hardcoded defaults. Leave blank to prompt.
HARDCODED_ALIAS=""
HARDCODED_HOST=""
HARDCODED_PORT="8000"
HARDCODED_USERNAME=""
HARDCODED_PASSWORD=""
HARDCODED_API_VERSION="v1"
HARDCODED_USE_HTTPS="false"

DEFAULT_CONFIG_FILE="/Users/Shared/P5HealthCheckServers.json"
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
  -c FILE  Server config JSON file (default: /Users/Shared/P5HealthCheckServers.json if present)
  -l N     Warning/error jobs lookback days (default: 7)
  -m N     Max volume details to fetch (default: 500, 0 = unlimited)
  -k       Allow insecure TLS (curl -k)
  -n       Non-interactive mode (runs all checks once; no prompts)
  -p       Force password prompt (ignore Keychain for this run)
  -K       In interactive mode, try Keychain password before prompting
  -U NAME  Override username for this run
  -A AUTH  Override auth as raw 'user:pass' for this run
  -h       Show this help
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

if [[ -z "$CONFIG_FILE" && -f "$DEFAULT_CONFIG_FILE" ]]; then
  CONFIG_FILE="$DEFAULT_CONFIG_FILE"
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required." >&2
  exit 1
fi
if ! command -v security >/dev/null 2>&1; then
  echo "security command is required (macOS Keychain)." >&2
  exit 1
fi

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

kbytes_human() {
  python3 - "$1" <<'PY'
import sys
raw = (sys.argv[1] or '').strip()
try:
    kb = float(raw)
except Exception:
    print('')
    raise SystemExit
GIB = 1024.0 * 1024.0
TIB = GIB * 1024.0
if kb >= TIB:
    print(f"{kb / TIB:.2f} TiB")
else:
    print(f"{kb / GIB:.2f} GiB")
PY
}

json_get() {
  local file="$1"
  local expr="$2"
  python3 - "$file" "$expr" <<'PY'
import json, sys
path, expr = sys.argv[1], sys.argv[2]
with open(path, 'r', encoding='utf-8') as f:
    obj = json.load(f)
cur = obj
for part in expr.split('.'):
    if not part:
        continue
    if isinstance(cur, dict):
        cur = cur.get(part)
    else:
        cur = None
        break
if cur is None:
    print('')
elif isinstance(cur, bool):
    print('true' if cur else 'false')
else:
    print(cur)
PY
}

json_count_ids() {
  local file="$1"
  local key="$2"
  python3 - "$file" "$key" <<'PY'
import json, sys
path, key = sys.argv[1], sys.argv[2]
with open(path, 'r', encoding='utf-8') as f:
    obj = json.load(f)
arr = obj.get(key) if isinstance(obj, dict) else None
if not isinstance(arr, list):
    print(0)
    raise SystemExit
count = 0
for item in arr:
    if isinstance(item, dict) and 'ID' in item:
        count += 1
print(count)
PY
}

json_ids_to_lines() {
  local file="$1"
  local key="$2"
  python3 - "$file" "$key" <<'PY'
import json, sys
path, key = sys.argv[1], sys.argv[2]
with open(path, 'r', encoding='utf-8') as f:
    obj = json.load(f)
arr = obj.get(key) if isinstance(obj, dict) else None
if not isinstance(arr, list):
    raise SystemExit
for item in arr:
    if isinstance(item, dict) and 'ID' in item:
        print(str(item['ID']))
PY
}

extract_protocol_summary() {
  local file="$1"
  python3 - "$file" <<'PY'
import json, sys
keywords = [
    'error', 'failed', 'failure', 'warning', 'exception',
    'media', 'volume', 'tape', 'blank', 'appendable',
    'mount', 'load', 'blocked', 'waiting', 'timeout',
    'restore', 'archive', 'backup'
]

def walk(v, out):
    if isinstance(v, str):
        out.append(v)
    elif isinstance(v, (int, float, bool)):
        out.append(str(v))
    elif isinstance(v, list):
        for i in v:
            walk(i, out)
    elif isinstance(v, dict):
        for k, val in v.items():
            out.append(str(k))
            walk(val, out)

with open(sys.argv[1], 'r', encoding='utf-8') as f:
    obj = json.load(f)
parts = []
walk(obj, parts)
clean = []
for p in parts:
    s = p.strip()
    if not s:
        continue
    low = s.lower()
    if any(k in low for k in keywords):
        clean.append(s)
if clean:
    print(' | '.join(clean[:3]))
else:
    print('')
PY
}

read_config_servers() {
  local config_file="$1"
  python3 - "$config_file" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)
if isinstance(data, dict):
    servers = data.get('servers', [])
elif isinstance(data, list):
    servers = data
else:
    servers = []
for s in servers:
    if not isinstance(s, dict):
        continue
    alias = str(s.get('alias', '')).strip()
    host = str(s.get('host', '')).strip()
    if not alias or not host:
        continue
    port = str(s.get('port', '8000')).strip() or '8000'
    username = str(s.get('username', 'admin')).strip() or 'admin'
    api_version = str(s.get('apiVersion', 'v1')).strip() or 'v1'
    use_https = s.get('useHTTPS', False)
    use_https = 'true' if str(use_https).lower() in ('true', '1', 'yes') else 'false'
    print('\t'.join([alias, host, port, username, api_version, use_https]))
PY
}

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
    RUN_VOLUMES=1
    return
  fi

  echo
  echo "Choose checks to run (comma-separated numbers or 'all'):"
  echo "  1) Server info + uptime"
  echo "  2) Devices (cleaning needed)"
  echo "  3) Job warnings"
  echo "  4) Job errors"
  echo "  5) Volumes + mode counts + CSV"
  local choice
  read -r -p "Selection [all]: " choice
  choice="$(to_lower "$(trim "$choice")")"
  if [[ -z "$choice" || "$choice" == "all" ]]; then
    RUN_SERVER_INFO=1
    RUN_DEVICES=1
    RUN_WARNINGS=1
    RUN_ERRORS=1
    RUN_VOLUMES=1
    return
  fi
  RUN_SERVER_INFO=0
  RUN_DEVICES=0
  RUN_WARNINGS=0
  RUN_ERRORS=0
  RUN_VOLUMES=0
  IFS=',' read -r -a items <<< "$choice"
  local item
  for item in "${items[@]}"; do
    item="$(trim "$item")"
    case "$item" in
      1) RUN_SERVER_INFO=1 ;;
      2) RUN_DEVICES=1 ;;
      3) RUN_WARNINGS=1 ;;
      4) RUN_ERRORS=1 ;;
      5) RUN_VOLUMES=1 ;;
      *) ;;
    esac
  done
}

run_server_health_check() {
  local alias_safe timestamp base_name
  alias_safe="$(safe_name "$ALIAS")"
  timestamp="$(date '+%Y%m%d-%H%M%S')"
  base_name="${alias_safe}-${timestamp}"

  local workdir
  workdir="$(mktemp -d)"
  trap '[[ -n "${workdir:-}" ]] && rm -rf "${workdir}"' RETURN

  local report_json="$OUT_DIR/${base_name}-report.json"
  local volumes_csv="$OUT_DIR/${base_name}-volumes.csv"
  local warnings_csv="$OUT_DIR/${base_name}-warnings.csv"
  local errors_csv="$OUT_DIR/${base_name}-errors.csv"

  local srvinfo_file="$workdir/srvinfo.json"
  local dev_list_file="$workdir/devices-list.json"
  local warn_list_file="$workdir/warn-list.json"
  local err_list_file="$workdir/err-list.json"
  local vol_list_file="$workdir/vol-list.json"

  echo
  echo "Running checks for: $ALIAS ($HOST:$PORT, user=$USERNAME, api=$API_VERSION, https=$USE_HTTPS)"

  local scheme="http"
  if [[ "$USE_HTTPS" == "true" ]]; then
    scheme="https"
  fi
  local base_url="${scheme}://${HOST}:${PORT}/rest/${API_VERSION}"

  local hostname="" lexxvers="" platform="" uptime=""
  local needs_cleaning_count=0
  local warning_count=0
  local error_count=0
  local appendable_count=0
  local readonly_count=0
  local full_count=0

  local devices_json='[]'
  local warnings_json='[]'
  local errors_json='[]'
  local volumes_json='[]'

  if (( RUN_SERVER_INFO == 1 )); then
    curl_request "GET" "$base_url/general/srvinfo" "$srvinfo_file"
    hostname="$(json_get "$srvinfo_file" "hostname")"
    lexxvers="$(json_get "$srvinfo_file" "lexxvers")"
    platform="$(json_get "$srvinfo_file" "platform")"
    uptime="$(json_get "$srvinfo_file" "uptime")"
  fi

  if (( RUN_DEVICES == 1 )); then
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
      python3 - "$device_id" "$cleaning" >> "$workdir/devices.ndjson" <<'PY'
import json, sys
obj = {"id": sys.argv[1], "cleaning": (sys.argv[2].strip().lower() == 'true')}
print(json.dumps(obj, separators=(',', ':')))
PY
    done < <(json_ids_to_lines "$dev_list_file" "devices")

    devices_json="$(python3 - "$workdir/devices.ndjson" <<'PY'
import json, sys
arr = []
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        arr.append(json.loads(line))
print(json.dumps(arr, separators=(',', ':')))
PY
)"
  fi

  if (( RUN_WARNINGS == 1 )); then
    curl_request "GET" "$base_url/general/jobs" "$warn_list_file" -H "filter: warning" -H "lastdays: ${LOOKBACK_DAYS}"
    warning_count="$(json_count_ids "$warn_list_file" "jobs")"
    : > "$workdir/warnings.ndjson"
    : > "$warnings_csv"
    echo "Job ID,Label,Status,Completion,Run At,Error" > "$warnings_csv"
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

      python3 - "$job_id" "$label" "$status" "$completion" "$runat" "$err" >> "$workdir/warnings.ndjson" <<'PY'
import csv, io, json, sys
job = {
    "jobID": sys.argv[1],
    "label": sys.argv[2] if sys.argv[2] else None,
    "status": sys.argv[3] if sys.argv[3] else None,
    "completion": sys.argv[4] if sys.argv[4] else None,
    "runat": sys.argv[5] if sys.argv[5] else None,
    "error": sys.argv[6] if sys.argv[6] else None,
}
print(json.dumps(job, separators=(',', ':')))
PY
      python3 - "$job_id" "$label" "$status" "$completion" "$runat" "$err" >> "$warnings_csv" <<'PY'
import csv, sys
row = [sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]]
w = csv.writer(sys.stdout, lineterminator='\n')
w.writerow(row)
PY
    done < <(json_ids_to_lines "$warn_list_file" "jobs")

    warnings_json="$(python3 - "$workdir/warnings.ndjson" <<'PY'
import json, sys
arr = []
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if line:
            arr.append(json.loads(line))
print(json.dumps(arr, separators=(',', ':')))
PY
)"
  fi

  if (( RUN_ERRORS == 1 )); then
    curl_request "GET" "$base_url/general/jobs" "$err_list_file" -H "filter: failed" -H "lastdays: ${LOOKBACK_DAYS}"
    error_count="$(json_count_ids "$err_list_file" "jobs")"
    : > "$workdir/errors.ndjson"
    : > "$errors_csv"
    echo "Job ID,Label,Status,Completion,Run At,Error" > "$errors_csv"
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

      python3 - "$job_id" "$label" "$status" "$completion" "$runat" "$err" >> "$workdir/errors.ndjson" <<'PY'
import json, sys
job = {
    "jobID": sys.argv[1],
    "label": sys.argv[2] if sys.argv[2] else None,
    "status": sys.argv[3] if sys.argv[3] else None,
    "completion": sys.argv[4] if sys.argv[4] else None,
    "runat": sys.argv[5] if sys.argv[5] else None,
    "error": sys.argv[6] if sys.argv[6] else None,
}
print(json.dumps(job, separators=(',', ':')))
PY
      python3 - "$job_id" "$label" "$status" "$completion" "$runat" "$err" >> "$errors_csv" <<'PY'
import csv, sys
row = [sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]]
w = csv.writer(sys.stdout, lineterminator='\n')
w.writerow(row)
PY
    done < <(json_ids_to_lines "$err_list_file" "jobs")

    errors_json="$(python3 - "$workdir/errors.ndjson" <<'PY'
import json, sys
arr = []
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if line:
            arr.append(json.loads(line))
print(json.dumps(arr, separators=(',', ':')))
PY
)"
  fi

  if (( RUN_VOLUMES == 1 )); then
    curl_request "GET" "$base_url/general/volumes" "$vol_list_file"
    : > "$workdir/volumes.ndjson"
    : > "$volumes_csv"
    echo "Volume ID,Label,Barcode,Location,Mode,Usage,State,Media Type,Used Size (KBytes),Total Size (KBytes),Used Size (Human),Total Size (Human)" > "$volumes_csv"

    local count=0
    while IFS= read -r vol_id; do
      if [[ "$MAX_VOLUME_DETAILS" != "0" && "$count" -ge "$MAX_VOLUME_DETAILS" ]]; then
        break
      fi
      local vfile="$workdir/volume-${vol_id}.json"
      curl_request "GET" "$base_url/general/volumes/${vol_id}" "$vfile"

      local label barcode location mode usage state mediatype usedsize totalsize
      label="$(json_get "$vfile" "label")"
      barcode="$(json_get "$vfile" "barcode")"
      location="$(json_get "$vfile" "location")"
      mode="$(json_get "$vfile" "mode")"
      usage="$(json_get "$vfile" "usage")"
      state="$(json_get "$vfile" "state")"
      mediatype="$(json_get "$vfile" "mediatype")"
      usedsize="$(json_get "$vfile" "usedsize")"
      totalsize="$(json_get "$vfile" "totalsize")"
      local used_human total_human
      used_human="$(kbytes_human "$usedsize")"
      total_human="$(kbytes_human "$totalsize")"

      case "$(to_lower "$mode")" in
        appendable) appendable_count=$((appendable_count + 1)) ;;
        readonly) readonly_count=$((readonly_count + 1)) ;;
        full) full_count=$((full_count + 1)) ;;
        *) ;;
      esac

      python3 - "$vol_id" "$label" "$barcode" "$location" "$mode" "$usage" "$state" "$mediatype" "$usedsize" "$totalsize" "$used_human" "$total_human" >> "$volumes_csv" <<'PY'
import csv, sys
row = [
    sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6],
    sys.argv[7], sys.argv[8], sys.argv[9], sys.argv[10], sys.argv[11], sys.argv[12]
]
w = csv.writer(sys.stdout, lineterminator='\n')
w.writerow(row)
PY

      python3 - "$vol_id" "$label" "$barcode" "$location" "$mode" "$usage" "$state" "$mediatype" "$usedsize" "$totalsize" "$used_human" "$total_human" >> "$workdir/volumes.ndjson" <<'PY'
import json, sys
obj = {
    "volumeID": sys.argv[1],
    "label": sys.argv[2] or None,
    "barcode": sys.argv[3] or None,
    "location": sys.argv[4] or None,
    "mode": sys.argv[5] or None,
    "usage": sys.argv[6] or None,
    "state": sys.argv[7] or None,
    "mediatype": sys.argv[8] or None,
    "usedsize": sys.argv[9] or None,
    "totalsize": sys.argv[10] or None,
    "usedHuman": sys.argv[11] or None,
    "totalHuman": sys.argv[12] or None,
}
print(json.dumps(obj, separators=(',', ':')))
PY
      count=$((count + 1))
    done < <(json_ids_to_lines "$vol_list_file" "volumes")

    volumes_json="$(python3 - "$workdir/volumes.ndjson" <<'PY'
import json, sys
arr = []
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if line:
            arr.append(json.loads(line))
print(json.dumps(arr, separators=(',', ':')))
PY
)"
  fi

  local needs_cleaning_text="No"
  if (( needs_cleaning_count > 0 )); then
    needs_cleaning_text="Yes"
  fi

  python3 - "$report_json" \
    "$ALIAS" "$HOST" "$PORT" "$USERNAME" "$API_VERSION" "$USE_HTTPS" \
    "$hostname" "$lexxvers" "$platform" "$uptime" \
    "$needs_cleaning_count" "$warning_count" "$error_count" "$appendable_count" "$readonly_count" "$full_count" \
    "$needs_cleaning_text" "$devices_json" "$warnings_json" "$errors_json" "$volumes_json" \
    "$RUN_SERVER_INFO" "$RUN_DEVICES" "$RUN_WARNINGS" "$RUN_ERRORS" "$RUN_VOLUMES" <<'PY'
import json, sys, datetime
(
 report,
 alias, host, port, username, api_version, use_https,
 hostname, lexxvers, platform, uptime,
 clean_count, warn_count, err_count, app_count, ro_count, full_count,
 clean_text, devices_json, warnings_json, errors_json, volumes_json,
 run_info, run_dev, run_warn, run_err, run_vol
) = sys.argv[1:]

def to_int(x):
    try:
        return int(x)
    except Exception:
        return 0

def from_json(s):
    try:
        return json.loads(s)
    except Exception:
        return []

obj = {
    "capturedAt": datetime.datetime.now().isoformat(),
    "server": {
        "alias": alias,
        "host": host,
        "port": port,
        "username": username,
        "apiVersion": api_version,
        "useHTTPS": use_https.lower() == 'true',
    },
    "checksRun": {
        "serverInfo": run_info == '1',
        "devices": run_dev == '1',
        "warnings": run_warn == '1',
        "errors": run_err == '1',
        "volumes": run_vol == '1',
    },
    "summary": {
        "hostname": hostname or None,
        "lexxvers": lexxvers or None,
        "platform": platform or None,
        "uptimeSeconds": to_int(uptime) if uptime else None,
        "needsCleaning": clean_text,
        "needsCleaningCount": to_int(clean_count),
        "warningCount": to_int(warn_count),
        "errorCount": to_int(err_count),
        "appendableCount": to_int(app_count),
        "readonlyCount": to_int(ro_count),
        "fullCount": to_int(full_count),
    },
    "devices": from_json(devices_json),
    "warnings": from_json(warnings_json),
    "errors": from_json(errors_json),
    "volumes": from_json(volumes_json),
}
with open(report, 'w', encoding='utf-8') as f:
    json.dump(obj, f, indent=2)
PY

  echo
  echo "Summary for ${ALIAS}:"
  if (( RUN_SERVER_INFO == 1 )); then
    echo "  Hostname: ${hostname:--}"
    echo "  Lexx Version: ${lexxvers:--}"
    echo "  Platform: ${platform:--}"
    echo "  Uptime: $(format_uptime "$uptime")"
  fi
  if (( RUN_DEVICES == 1 )); then
    echo "  Needs cleaning: ${needs_cleaning_text} (${needs_cleaning_count})"
  fi
  if (( RUN_WARNINGS == 1 )); then
    echo "  Warning jobs: ${warning_count}"
  fi
  if (( RUN_ERRORS == 1 )); then
    echo "  Error jobs: ${error_count}"
  fi
  if (( RUN_VOLUMES == 1 )); then
    echo "  LTO modes: appendable=${appendable_count}, readonly=${readonly_count}, full=${full_count}"
  fi

  echo
  echo "Created files:"
  echo "  - $report_json"
  if (( RUN_VOLUMES == 1 )); then
    echo "  - $volumes_csv"
  fi
  if (( RUN_WARNINGS == 1 )); then
    echo "  - $warnings_csv"
  fi
  if (( RUN_ERRORS == 1 )); then
    echo "  - $errors_csv"
  fi

  trap - RETURN
  rm -rf "$workdir"
}

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