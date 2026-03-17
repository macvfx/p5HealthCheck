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

now_millis() {
  python3 - <<'PY'
import time
print(time.time_ns() // 1_000_000)
PY
}

now_iso() {
  python3 - <<'PY'
import datetime
print(datetime.datetime.now().isoformat())
PY
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

json_ids_to_lines_flexible() {
  local file="$1"
  local preferred="$2"
  python3 - "$file" "$preferred" <<'PY'
import json, sys
path, preferred = sys.argv[1], sys.argv[2]
with open(path, 'r', encoding='utf-8') as f:
    obj = json.load(f)

def from_list(arr):
    for item in arr:
        if isinstance(item, dict) and 'ID' in item:
            print(str(item['ID']))

if isinstance(obj, list):
    from_list(obj)
    raise SystemExit

if not isinstance(obj, dict):
    raise SystemExit

keys = [preferred, 'resources', 'plans', 'tasks', 'events', 'jobs', 'volumes', 'devices', 'jukeboxes']
for key in keys:
    arr = obj.get(key)
    if isinstance(arr, list):
        from_list(arr)
        raise SystemExit

for value in obj.values():
    if isinstance(value, list):
        from_list(value)
        raise SystemExit
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

write_plans_markdown() {
  local output_file="$1"
  local alias_name="$2"
  local host="$3"
  local port="$4"
  local filter_kind="$5"
  local plans_ndjson="$6"

  python3 - "$output_file" "$alias_name" "$host" "$port" "$filter_kind" "$plans_ndjson" <<'PY'
import datetime
import json
import sys

output_file, alias_name, host, port, filter_kind, plans_ndjson = sys.argv[1:]

def endpoint(host_value, paths):
    host_text = host_value if host_value else "-"
    if not paths:
        return host_text
    return f"{host_text} :: {', '.join(paths)}"

def schedule_text(event):
    parts = []
    start_val = event.get("start")
    first_val = event.get("firstrun")
    value = start_val if start_val is not None else first_val
    if value is not None:
        try:
            dt = datetime.datetime.fromtimestamp(float(value))
            parts.append(f"start {dt.isoformat(sep=' ', timespec='minutes')}")
        except Exception:
            parts.append(f"start {value}")
    freq = event.get("frequency")
    if freq:
        parts.append(f"freq {freq}")
    interval = event.get("interval")
    if interval is not None:
        parts.append(f"interval {interval}s")
    duration = event.get("duration")
    if duration is not None:
        parts.append(f"duration {duration}s")
    exception = event.get("exception")
    if exception:
        parts.append(f"exception {exception}")
    pool = event.get("pool")
    if pool:
        parts.append(f"pool {pool}")
    return "; ".join(parts) if parts else "-"

plans = []
try:
    with open(plans_ndjson, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                plans.append(json.loads(line))
except FileNotFoundError:
    plans = []

if filter_kind != "all":
    plans = [p for p in plans if p.get("kind") == filter_kind]

plans.sort(key=lambda p: (p.get("kind", ""), str(p.get("planID", ""))))

lines = []
lines.append("# P5 Plan Documentation")
lines.append("")
lines.append(f"- Server: {alias_name}")
lines.append(f"- Host: {host}:{port}")
lines.append(f"- Exported: {datetime.datetime.now(datetime.timezone.utc).isoformat()}")
lines.append(f"- Total plans: {len(plans)}")
lines.append("")

if not plans:
    lines.append("_No Archive, Backup, or Sync plans were returned by the API._")
else:
    for plan in plans:
        kind = plan.get("kind", "")
        pid = plan.get("planID", "")
        lines.append(f"## {kind} Plan `{pid}`")
        lines.append("")
        lines.append(f"- Description: {plan.get('description') or '-'}")
        enabled = plan.get("enabled")
        if enabled is True:
            enabled_text = "Yes"
        elif enabled is False:
            enabled_text = "No"
        else:
            enabled_text = "-"
        lines.append(f"- Enabled: {enabled_text}")

        if kind != "Archive":
            lines.append(f"- Source: {endpoint(plan.get('sourceHost'), plan.get('sourcePaths') or [])}")
            lines.append(f"- Target: {endpoint(plan.get('targetHost'), plan.get('targetPaths') or [])}")
            schedule = plan.get("schedule") or []
            if not schedule:
                lines.append("- Schedule: -")
            else:
                for idx, event in enumerate(schedule):
                    prefix = "- Schedule:" if idx == 0 else "  -"
                    lines.append(f"{prefix} {schedule_text(event)}")

        notes = plan.get("notes") or []
        for idx, note in enumerate(notes):
            prefix = "- Notes:" if idx == 0 else "  -"
            lines.append(f"{prefix} {note}")

        lines.append("")

with open(output_file, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))
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

  python3 - "$connectivity_csv" \
    "$connectivity_captured_at" "$ALIAS" "$HOST" "$PORT" \
    "$connectivity_reachable" "$connectivity_response_ms" "$uptime" "$(format_uptime "$uptime")" <<'PY'
import csv, sys
(
    out_path,
    captured_at, alias_name, host, port,
    reachable, response_ms, uptime_seconds, uptime_human
) = sys.argv[1:]

with open(out_path, 'w', encoding='utf-8', newline='') as f:
    w = csv.writer(f, lineterminator='\n')
    w.writerow([
        "Captured At",
        "Alias",
        "Host",
        "Port",
        "Reachable",
        "Response MS",
        "Uptime Seconds",
        "Uptime Human",
    ])
    w.writerow([
        captured_at,
        alias_name,
        host,
        port,
        "true" if reachable == "1" else "false",
        response_ms,
        uptime_seconds,
        uptime_human,
    ])
PY

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

  if (( RUN_WARNINGS == 1 && connectivity_reachable == 1 )); then
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

  if (( RUN_ERRORS == 1 && connectivity_reachable == 1 )); then
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

  # ── Running jobs ──────────────────────────────────────────────────────────
  if (( RUN_RUNNING == 1 && connectivity_reachable == 1 )); then
    curl_request "GET" "$base_url/general/jobs" "$run_list_file" -H "filter: running"
    running_count="$(json_count_ids "$run_list_file" "jobs")"
    : > "$workdir/running.ndjson"
    : > "$running_csv"
    echo "Job ID,Label,Status,Completion,Run At,Error" > "$running_csv"
    while IFS= read -r job_id; do
      local jfile="$workdir/run-job-${job_id}.json"
      curl_request "GET" "$base_url/general/jobs/${job_id}" "$jfile"
      local label status completion runat err
      label="$(json_get "$jfile" "label")"
      status="$(json_get "$jfile" "status")"
      completion="$(json_get "$jfile" "completion")"
      runat="$(json_get "$jfile" "runat")"
      err="$(json_get "$jfile" "error")"

      python3 - "$job_id" "$label" "$status" "$completion" "$runat" "$err" >> "$workdir/running.ndjson" <<'PY'
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
      python3 - "$job_id" "$label" "$status" "$completion" "$runat" "$err" >> "$running_csv" <<'PY'
import csv, sys
row = [sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]]
w = csv.writer(sys.stdout, lineterminator='\n')
w.writerow(row)
PY
    done < <(json_ids_to_lines "$run_list_file" "jobs")

    running_json="$(python3 - "$workdir/running.ndjson" <<'PY'
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

  if (( RUN_WARNINGS == 1 || RUN_ERRORS == 1 )); then
    python3 - "$workdir/warnings.ndjson" "$workdir/errors.ndjson" "$all_jobs_csv" <<'PY'
import csv
import json
import os
import sys

warn_path, err_path, out_path = sys.argv[1:]

jobs = []
for path in [err_path, warn_path]:
    if not os.path.exists(path):
        continue
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            jobs.append(json.loads(line))

seen = set()
unique = []
for job in jobs:
    job_id = str(job.get("jobID") or "")
    if not job_id or job_id in seen:
        continue
    seen.add(job_id)
    unique.append(job)
unique.sort(key=lambda j: str(j.get("jobID") or ""))

with open(out_path, 'w', encoding='utf-8', newline='') as f:
    w = csv.writer(f, lineterminator='\n')
    w.writerow(["Job ID", "Label", "Status", "Completion", "Run At", "Error"])
    for job in unique:
        w.writerow([
            job.get("jobID") or "",
            job.get("label") or "",
            job.get("status") or "",
            job.get("completion") or "",
            job.get("runat") or "",
            job.get("error") or "",
        ])
PY
  fi

  if (( RUN_VOLUMES == 1 && connectivity_reachable == 1 )); then
    curl_request "GET" "$base_url/general/volumes" "$vol_list_file"
    : > "$workdir/volumes.ndjson"
    : > "$volumes_csv"
    echo "Volume ID,Label,Barcode,Location,Mode,Usage,State,Media Type,Used Size (KBytes),Total Size (KBytes),Used Size (Human),Total Size (Human),Last Used,Use Count,Error Count" > "$volumes_csv"

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

      python3 - "$vol_id" "$label" "$barcode" "$location" "$mode" "$usage" "$state" "$mediatype" \
        "$usedsize" "$totalsize" "$used_human" "$total_human" \
        "$dateused" "$usecount" "$vol_errors" >> "$volumes_csv" <<'PY'
import csv, sys
row = [
    sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6],
    sys.argv[7], sys.argv[8], sys.argv[9], sys.argv[10], sys.argv[11], sys.argv[12],
    sys.argv[13], sys.argv[14], sys.argv[15],
]
w = csv.writer(sys.stdout, lineterminator='\n')
w.writerow(row)
PY

      python3 - "$vol_id" "$label" "$barcode" "$location" "$mode" "$usage" "$state" "$mediatype" \
        "$usedsize" "$totalsize" "$used_human" "$total_human" \
        "$dateused" "$usecount" "$hardwrercnt" "$softwrercnt" "$hardrdercnt" "$softrdercnt" \
        "$vol_errors" >> "$workdir/volumes.ndjson" <<'PY'
import json, sys

def to_int(x):
    try: return int(x)
    except Exception: return None

obj = {
    "volumeID":    sys.argv[1],
    "label":       sys.argv[2] or None,
    "barcode":     sys.argv[3] or None,
    "location":    sys.argv[4] or None,
    "mode":        sys.argv[5] or None,
    "usage":       sys.argv[6] or None,
    "state":       sys.argv[7] or None,
    "mediatype":   sys.argv[8] or None,
    "usedsize":    sys.argv[9] or None,
    "totalsize":   sys.argv[10] or None,
    "usedHuman":   sys.argv[11] or None,
    "totalHuman":  sys.argv[12] or None,
    "dateused":    sys.argv[13] or None,
    "usecount":    to_int(sys.argv[14]),
    "hardWrErCnt": to_int(sys.argv[15]),
    "softWrErCnt": to_int(sys.argv[16]),
    "hardRdErCnt": to_int(sys.argv[17]),
    "softRdErCnt": to_int(sys.argv[18]),
    "totalErrors": to_int(sys.argv[19]),
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

    # ── Recyclable Backup Volumes CSV ──
    python3 - "$workdir/volumes.ndjson" "$recyclable_backup_csv" <<'PY'
import csv, json, sys

ndjson_path, out_path = sys.argv[1], sys.argv[2]
rows = []
with open(ndjson_path, 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        obj = json.loads(line)
        mode = (obj.get("mode") or "").lower()
        usage = (obj.get("usage") or "").lower()
        if mode == "recyclable" and usage == "backup":
            rows.append(obj)

with open(out_path, 'w', encoding='utf-8', newline='') as f:
    w = csv.writer(f, lineterminator='\n')
    w.writerow(["Volume ID", "Label", "Barcode", "Location", "State", "Media Type",
                 "Used Size (Human)", "Total Size (Human)", "Last Used", "Use Count", "Error Count"])
    for obj in rows:
        w.writerow([
            obj.get("volumeID") or "",
            obj.get("label") or "",
            obj.get("barcode") or "",
            obj.get("location") or "",
            obj.get("state") or "",
            obj.get("mediatype") or "",
            obj.get("usedHuman") or "",
            obj.get("totalHuman") or "",
            obj.get("dateused") or "",
            obj.get("usecount") if obj.get("usecount") is not None else "",
            obj.get("totalErrors") if obj.get("totalErrors") is not None else "",
        ])
PY
  fi

  # ── Jukeboxes ─────────────────────────────────────────────────────────────
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
        python3 - "$jb_id" "$slotcount" "$volcount" >> "$workdir/jukeboxes.ndjson" <<'PY'
import json, sys
obj = {
    "jukeboxID":   sys.argv[1],
    "slotCount":   int(sys.argv[2]) if sys.argv[2].isdigit() else 0,
    "volumeCount": int(sys.argv[3]) if sys.argv[3].isdigit() else 0,
}
print(json.dumps(obj, separators=(',', ':')))
PY
        jukebox_count=$((jukebox_count + 1))
      done < <(json_ids_to_lines "$jb_list_file" "jukeboxes")

      jukeboxes_json="$(python3 - "$workdir/jukeboxes.ndjson" <<'PY'
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
    else
      echo "  [INFO] Jukeboxes: endpoint not available or no jukeboxes configured." >&2
    fi
  fi

  # ── Licence resources ──────────────────────────────────────────────────────
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
        python3 - "$res_id" "${free_count:-}" >> "$workdir/licence.ndjson" <<'PY'
import json, sys

def to_int(x):
    try: return int(x)
    except Exception: return None

free_val = to_int(sys.argv[2])
obj = {
    "resourceID": sys.argv[1],
    "free": free_val,
    "status": (
        "unlimited" if free_val == -1
        else "depleted" if free_val == 0
        else "low" if (free_val is not None and free_val <= 2)
        else "ok"
    ),
}
print(json.dumps(obj, separators=(',', ':')))
PY
      done < <(json_ids_to_lines "$lic_list_file" "resources")

      licence_json="$(python3 - "$workdir/licence.ndjson" <<'PY'
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
    else
      echo "  [INFO] Licence: endpoint not available." >&2
    fi
  fi

  if (( RUN_PLANS == 1 && connectivity_reachable == 1 )); then
    local plans_ndjson="$workdir/plans.ndjson"
    : > "$plans_ndjson"

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
        python3 - "$plan_id" "$ap_desc" "$ap_enabled" "$ap_database" "$ap_pool" "$ap_autostart" >> "$plans_ndjson" <<'PY'
import json, sys
def to_bool(v):
    t = (v or '').strip().lower()
    if t in ('true', '1', 'yes'):
        return True
    if t in ('false', '0', 'no'):
        return False
    return None
notes = []
if sys.argv[4]:
    notes.append(f"Database: {sys.argv[4]}")
if sys.argv[5]:
    notes.append(f"Pool: {sys.argv[5]}")
if sys.argv[6]:
    state = "Enabled" if to_bool(sys.argv[6]) else "Disabled"
    notes.append(f"Autostart: {state}")
obj = {
    "kind": "Archive",
    "planID": sys.argv[1],
    "description": sys.argv[2] or None,
    "enabled": to_bool(sys.argv[3]),
    "sourceHost": None,
    "sourcePaths": [],
    "targetHost": None,
    "targetPaths": [],
    "schedule": [],
    "notes": notes,
}
print(json.dumps(obj, separators=(',', ':')))
PY
      done < <(json_ids_to_lines_flexible "$archive_plan_list_file" "plans")
    else
      echo "  [INFO] Archive plans: endpoint not available." >&2
    fi

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
            python3 - "$bt_file" >> "$bp_paths_file" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    obj = json.load(f)
for path in obj.get('dirlist') or []:
    if path:
        print(path)
PY
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
            python3 - "$be_file" >> "$bp_schedule_file" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    e = json.load(f)
obj = {
    "start": None,
    "firstrun": e.get("firstrun"),
    "interval": None,
    "duration": e.get("duration"),
    "frequency": e.get("frequency"),
    "exception": e.get("exception"),
    "pool": e.get("pool"),
}
print(json.dumps(obj, separators=(',', ':')))
PY
          done < <(json_ids_to_lines_flexible "$bp_event_list_file" "events")
        fi

        local bp_desc bp_enabled
        bp_desc="$(json_get "$bp_file" "description")"
        bp_enabled="$(json_get "$bp_file" "enabled")"
        python3 - "$plan_id" "$bp_desc" "$bp_enabled" "$bp_hosts_file" "$bp_paths_file" "$bp_pools_file" "$bp_schedule_file" >> "$plans_ndjson" <<'PY'
import json, sys
def to_bool(v):
    t = (v or '').strip().lower()
    if t in ('true', '1', 'yes'):
        return True
    if t in ('false', '0', 'no'):
        return False
    return None
def uniq_lines(path):
    items = []
    try:
        with open(path, 'r', encoding='utf-8') as f:
            items = [line.strip() for line in f if line.strip()]
    except Exception:
        return []
    return sorted(set(items))
def load_schedule(path):
    out = []
    try:
        with open(path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line:
                    out.append(json.loads(line))
    except Exception:
        return []
    return out
hosts = uniq_lines(sys.argv[4])
paths = uniq_lines(sys.argv[5])
pools = uniq_lines(sys.argv[6])
obj = {
    "kind": "Backup",
    "planID": sys.argv[1],
    "description": sys.argv[2] or None,
    "enabled": to_bool(sys.argv[3]),
    "sourceHost": ", ".join(hosts) if hosts else None,
    "sourcePaths": paths,
    "targetHost": None,
    "targetPaths": pools,
    "schedule": load_schedule(sys.argv[7]),
    "notes": [],
}
print(json.dumps(obj, separators=(',', ':')))
PY
      done < <(json_ids_to_lines_flexible "$backup_plan_list_file" "plans")
    else
      echo "  [INFO] Backup plans: endpoint not available." >&2
    fi

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
            python3 - "$se_file" >> "$sp_schedule_file" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    e = json.load(f)
obj = {
    "start": e.get("start"),
    "firstrun": None,
    "interval": e.get("interval"),
    "duration": e.get("duration"),
    "frequency": e.get("frequency"),
    "exception": e.get("exception"),
    "pool": None,
}
print(json.dumps(obj, separators=(',', ':')))
PY
          done < <(json_ids_to_lines_flexible "$sp_event_list_file" "events")
        fi

        local sp_desc sp_enabled sp_sourcehost sp_targethost sp_autostart
        sp_desc="$(json_get "$sp_file" "description")"
        sp_enabled="$(json_get "$sp_file" "enabled")"
        sp_sourcehost="$(json_get "$sp_file" "sourcehost")"
        sp_targethost="$(json_get "$sp_file" "targethost")"
        sp_autostart="$(json_get "$sp_file" "autostart")"
        python3 - "$plan_id" "$sp_desc" "$sp_enabled" "$sp_sourcehost" "$sp_targethost" "$sp_autostart" "$sp_file" "$sp_schedule_file" >> "$plans_ndjson" <<'PY'
import json, sys
def to_bool(v):
    t = (v or '').strip().lower()
    if t in ('true', '1', 'yes'):
        return True
    if t in ('false', '0', 'no'):
        return False
    return None
def load_schedule(path):
    out = []
    try:
        with open(path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line:
                    out.append(json.loads(line))
    except Exception:
        return []
    return out
source_paths = []
target_paths = []
with open(sys.argv[7], 'r', encoding='utf-8') as f:
    d = json.load(f)
for p in d.get("sourcepath") or []:
    if p:
        source_paths.append(str(p))
tp = d.get("targetpath")
if tp:
    target_paths = [str(tp)]
notes = []
autostart = sys.argv[6]
if autostart:
    notes.append(f"Autostart: {autostart}")
obj = {
    "kind": "Sync",
    "planID": sys.argv[1],
    "description": sys.argv[2] or None,
    "enabled": to_bool(sys.argv[3]),
    "sourceHost": sys.argv[4] or None,
    "sourcePaths": source_paths,
    "targetHost": sys.argv[5] or None,
    "targetPaths": target_paths,
    "schedule": load_schedule(sys.argv[8]),
    "notes": notes,
}
print(json.dumps(obj, separators=(',', ':')))
PY
      done < <(json_ids_to_lines_flexible "$sync_plan_list_file" "plans")
    else
      echo "  [INFO] Sync plans: endpoint not available." >&2
    fi

    write_plans_markdown "$all_plans_md" "$ALIAS" "$HOST" "$PORT" "all" "$plans_ndjson"
    write_plans_markdown "$archive_plans_md" "$ALIAS" "$HOST" "$PORT" "Archive" "$plans_ndjson"
    write_plans_markdown "$backup_plans_md" "$ALIAS" "$HOST" "$PORT" "Backup" "$plans_ndjson"
    write_plans_markdown "$sync_plans_md" "$ALIAS" "$HOST" "$PORT" "Sync" "$plans_ndjson"

    read -r plan_total_count archive_plan_count backup_plan_count sync_plan_count < <(
      python3 - "$plans_ndjson" <<'PY'
import json, sys
total = archive = backup = sync = 0
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        total += 1
        k = (json.loads(line).get("kind") or "").lower()
        if k == "archive":
            archive += 1
        elif k == "backup":
            backup += 1
        elif k == "sync":
            sync += 1
print(total, archive, backup, sync)
PY
    )

    plans_json="$(python3 - "$plans_ndjson" <<'PY'
import json, sys
arr = []
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if line:
            arr.append(json.loads(line))
arr.sort(key=lambda p: (p.get("kind", ""), str(p.get("planID", ""))))
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
    "$connectivity_captured_at" "$connectivity_reachable" "$connectivity_response_ms" "$(format_uptime "$uptime")" \
    "$needs_cleaning_count" "$warning_count" "$error_count" "$running_count" \
    "$appendable_count" "$readonly_count" "$full_count" "$recyclable_count" "$total_error_count" \
    "$needs_cleaning_text" \
    "$devices_json" "$warnings_json" "$errors_json" "$running_json" "$volumes_json" \
    "$jukeboxes_json" "$licence_json" "$plans_json" \
    "$jukebox_count" "$licence_alert_count" "$licence_warn_count" \
    "$plan_total_count" "$archive_plan_count" "$backup_plan_count" "$sync_plan_count" \
    "$RUN_SERVER_INFO" "$RUN_DEVICES" "$RUN_WARNINGS" "$RUN_ERRORS" "$RUN_RUNNING" \
    "$RUN_VOLUMES" "$RUN_JUKEBOXES" "$RUN_LICENCE" "$RUN_PLANS" <<'PY'
import json, sys, datetime
(
 report,
 alias, host, port, username, api_version, use_https,
 hostname, lexxvers, platform, uptime,
 connectivity_captured_at, connectivity_reachable, connectivity_response_ms, uptime_human,
 clean_count, warn_count, err_count, running_count,
 app_count, ro_count, full_count, recyclable_count, total_errs,
 clean_text,
 devices_json, warnings_json, errors_json, running_json, volumes_json,
 jukeboxes_json, licence_json, plans_json,
 jukebox_count, lic_alert, lic_warn,
 plan_total, archive_count, backup_count, sync_count,
 run_info, run_dev, run_warn, run_err, run_running, run_vol, run_jb, run_lic, run_plans
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
        "serverInfo":       run_info == '1',
        "devices":          run_dev  == '1',
        "warnings":         run_warn == '1',
        "errors":           run_err  == '1',
        "running":          run_running == '1',
        "volumes":          run_vol  == '1',
        "jukeboxes":        run_jb   == '1',
        "licenceResources": run_lic  == '1',
        "plans":            run_plans == '1',
    },
    "summary": {
        "hostname":            hostname or None,
        "lexxvers":            lexxvers or None,
        "platform":            platform or None,
        "uptimeSeconds":       to_int(uptime) if uptime else None,
        "uptimeHuman":         uptime_human or None,
        "connectivityReachable": connectivity_reachable == '1',
        "connectivityResponseMS": to_int(connectivity_response_ms),
        "needsCleaning":       clean_text,
        "needsCleaningCount":  to_int(clean_count),
        "warningCount":        to_int(warn_count),
        "errorCount":          to_int(err_count),
        "runningCount":        to_int(running_count),
        "appendableCount":     to_int(app_count),
        "readonlyCount":       to_int(ro_count),
        "fullCount":           to_int(full_count),
        "recyclableCount":     to_int(recyclable_count),
        "volumeTotalErrors":   to_int(total_errs),
        "jukeboxCount":        to_int(jukebox_count),
        "licenceAlertCount":   to_int(lic_alert),
        "licenceWarnCount":    to_int(lic_warn),
        "planTotalCount":      to_int(plan_total),
        "archivePlanCount":    to_int(archive_count),
        "backupPlanCount":     to_int(backup_count),
        "syncPlanCount":       to_int(sync_count),
    },
    "devices":          from_json(devices_json),
    "warnings":         from_json(warnings_json),
    "errors":           from_json(errors_json),
    "running":          from_json(running_json),
    "volumes":          from_json(volumes_json),
    "jukeboxes":        from_json(jukeboxes_json),
    "licenceResources": from_json(licence_json),
    "plans":            from_json(plans_json),
    "connectivity": {
        "capturedAt": connectivity_captured_at or None,
        "reachable": connectivity_reachable == '1',
        "responseMS": to_int(connectivity_response_ms),
        "uptimeSeconds": to_int(uptime) if uptime else None,
        "uptimeHuman": uptime_human or None,
    },
}
with open(report, 'w', encoding='utf-8') as f:
    json.dump(obj, f, indent=2)
PY

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
    local all_job_count
    all_job_count="$(python3 - "$all_jobs_csv" <<'PY'
import csv, sys
count = 0
with open(sys.argv[1], 'r', encoding='utf-8', newline='') as f:
    r = csv.reader(f)
    next(r, None)
    for _ in r:
        count += 1
print(count)
PY
)"
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
    if (( jukebox_count > 0 )); then
      python3 - "$workdir/jukeboxes.ndjson" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        obj = json.loads(line)
        print(f"    {obj['jukeboxID']}: {obj['volumeCount']} volumes loaded / {obj['slotCount']} slots")
PY
    fi
  fi
  if (( RUN_LICENCE == 1 )); then
    echo "  Licence resources: ${licence_alert_count} depleted, ${licence_warn_count} low"
    if [[ -f "$workdir/licence.ndjson" ]]; then
      python3 - "$workdir/licence.ndjson" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        obj = json.loads(line)
        free = obj.get('free')
        status = obj.get('status', '')
        display = 'Unlimited' if free == -1 else str(free) if free is not None else '-'
        tag = ''
        if status == 'depleted': tag = ' [ALERT]'
        elif status == 'low':    tag = ' [WARN]'
        print(f"    {obj['resourceID']}: free={display}{tag}")
PY
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
