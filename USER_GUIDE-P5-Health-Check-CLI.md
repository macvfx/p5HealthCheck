# P5 Health Check CLI (macOS) User Guide

## Files
- Script: `p5_health_check.sh`
- Sample server config: `P5HealthCheckServers.example.json`

## What it does
- Checks one P5 server per run (non-interactive) or prompts to check additional servers (interactive).
- Runs up to 8 checks — all enabled by default in non-interactive mode.
- Reads credentials from macOS Keychain (or prompts interactively).
- Outputs per-run files to the current directory (or a specified output path).

## Checks
1. Server info + uptime
2. Devices (cleaning needed)
3. Job warnings
4. Job errors
5. Volumes + mode counts + CSV (Appendable / Readonly / Full, with Last Used, Use Count, Error Count)
6. Jukeboxes (slot count and volumes loaded per library) — non-fatal if unavailable
7. Licence resources — prints `[ALERT]` for depleted (`free = 0`), `[WARN]` for low (`free ≤ 2`); non-fatal if unavailable
8. Plans export (all/archive/backup/sync markdown)

## Output files
Default output directory: current working directory. Override with `-o DIR`.

| File | Contents |
|---|---|
| `<alias>-YYYYMMDD-HHMMSS-report.json` | Full structured report for all checks |
| `<alias>-YYYYMMDD-HHMMSS-connectivity.csv` | Reachability snapshot with timestamp, up/down, response ms, uptime seconds, uptime human |
| `<alias>-YYYYMMDD-HHMMSS-volumes.csv` | Volume list with Last Used, Use Count, Error Count |
| `<alias>-YYYYMMDD-HHMMSS-warnings.csv` | Warning jobs |
| `<alias>-YYYYMMDD-HHMMSS-errors.csv` | Error jobs |
| `<alias>-YYYYMMDD-HHMMSS-all-job-results.csv` | Combined warning + error job results (deduplicated by Job ID) |
| `<alias>-YYYYMMDD-HHMMSS-all-plans.md` | Markdown export of all plans |
| `<alias>-YYYYMMDD-HHMMSS-archive-plans.md` | Markdown export of archive plans |
| `<alias>-YYYYMMDD-HHMMSS-backup-plans.md` | Markdown export of backup plans |
| `<alias>-YYYYMMDD-HHMMSS-sync-plans.md` | Markdown export of sync plans |

### Connectivity CSV example

```csv
Captured At,Alias,Host,Port,Reachable,Response MS,Uptime Seconds,Uptime Human
2026-02-27T09:15:00,P5 Primary,p5-primary.local,8000,true,182,93784,1d 2h 3m
```

## Usage
Run from Terminal:

```bash
chmod +x p5_health_check.sh
./p5_health_check.sh
```

You can also place `p5_health_check.sh` in `/Library/Scripts`, `/usr/local/bin`, `~/bin`, or any other location in your `PATH`.

Common options:

```bash
# Non-interactive run using shared server config
./p5_health_check.sh -n -c "/Users/Shared/P5Servers.json"

# Save reports to a specific folder
./p5_health_check.sh -o "/p5-reports"

# Wider job lookback and more volume records
./p5_health_check.sh -l 14 -m 1000

# Use Keychain password in interactive mode
./p5_health_check.sh -K

# Force password prompt (ignores Keychain and hardcoded values)
./p5_health_check.sh -p

# Full non-interactive run with custom config and output path
./p5_health_check.sh -n -c "/Users/Shared/P5Servers.json" -o "/p5-reports"
```

## Option Reference

| Option | Description |
|---|---|
| `-o DIR` | Output directory for generated files. Default: current working directory. |
| `-c FILE` | Server config JSON path. Default: auto-detect in this order: `/Users/Shared/P5Servers.json`, `/Users/Shared/P5HealthCheckServers.json`, `~/Documents/P5Servers.json`, `~/Documents/P5HealthCheckServers.json`. |
| `-l N` | Job lookback window in days. Default: `7`. |
| `-m N` | Max volume detail records to fetch. Default: `500`. Use `0` for unlimited. |
| `-n` | Non-interactive mode — runs once, all 8 checks, no prompts. |
| `-k` | Allow insecure TLS (`curl -k`) for self-signed certificates. |
| `-K` | Try Keychain password before prompting (interactive mode). |
| `-p` | Force password prompt — ignores Keychain and hardcoded values. |
| `-U NAME` | Override username for this run. |
| `-A AUTH` | Override auth as `user:pass` (use only for non-secret test credentials — stored in shell history). |
| `-h` | Print help and exit. |

## Server Config JSON

The script uses the same JSON format as the Mac apps. Default filename is `P5Servers.json`.

**Default search path (no `-c` flag):**
1. `/Users/Shared/P5Servers.json`
2. `/Users/Shared/P5HealthCheckServers.json`
3. `~/Documents/P5Servers.json`
4. `~/Documents/P5HealthCheckServers.json`

**Format** (`{ "servers": [ ... ] }` or `[ ... ]`):

```json
{
  "servers": [
    {
      "alias": "Example Primary",
      "host": "p5-primary.example.invalid",
      "port": "8000",
      "username": "<username>",
      "apiVersion": "v1",
      "useHTTPS": false
    },
    {
      "alias": "Example Secondary",
      "host": "p5-secondary.example.invalid",
      "port": "8000",
      "username": "<username>",
      "apiVersion": "v1",
      "useHTTPS": false
    }
  ]
}
```

Per-server fields:

| Field | Required | Default |
|---|---|---|
| `alias` | Yes | — |
| `host` | Yes | — |
| `port` | No | `8000` |
| `username` | No | `admin` |
| `apiVersion` | No | `v1` |
| `useHTTPS` | No | `false` |

Passwords are never stored in the file. The script reads them from Keychain or prompts interactively.

## Non-Interactive Mode (`-n`)
- Runs once without any prompts.
- All 9 checks run automatically.
- Server selection: uses hardcoded values if set in script, otherwise uses the first server from the config file.
- Credential lookup: uses the configured password override if set, otherwise reads from Keychain. If missing, exits with an error.
- A connectivity CSV is always produced for the selected server, even if the server is unreachable.
- If the server is down, the script records `P5 Down`, writes the connectivity CSV + JSON report, and skips the detailed API checks for that run.

## Keychain Behaviour
- Service name: `com.p5healthcheck.shell`
- Account key format: `username@host:port/rest/apiVersion`
- In interactive mode: prompts for credentials, then offers to save to Keychain.
- Use `-K` to try Keychain first before prompting.
- In non-interactive mode (`-n`): uses Keychain or hardcoded values only — no prompts.

## Secure Credential Entry (Recommended)
To keep passwords out of shell history:
1. Run with `-p` to force the hidden credential prompt.
2. At `Credentials as user:pass (recommended, Enter to skip):` enter `username:password` including the colon.
3. Do not add quotes at the prompt.

Avoid `-A "username:password"` for real credentials — command-line arguments are visible in process listings and shell history.

## Hardcoded Credentials (Optional)
Edit the top of the script to set static values (useful for dedicated monitoring accounts):

```bash
HARDCODED_ALIAS=""
HARDCODED_HOST=""
HARDCODED_PORT="8000"
HARDCODED_USERNAME=""
HARDCODED_PASSWORD=""
HARDCODED_API_VERSION="v1"
HARDCODED_USE_HTTPS="false"
```

Leave fields blank to use the config file or interactive prompts instead.

## Scheduling with launchd (macOS)
To run on a schedule without cron, create a launchd plist:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.p5healthcheck.daily</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/Shared/p5_health_check.sh</string>
        <!-- Replace the path above with the actual absolute path where you installed p5_health_check.sh -->
        <string>-n</string>
        <string>-c</string>
        <string>/Users/Shared/P5Servers.json</string>
        <string>-o</string>
        <string>/Users/Shared/p5-reports</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>7</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
```

Save to `~/Library/LaunchAgents/com.p5healthcheck.daily.plist` and load with:
```bash
launchctl load ~/Library/LaunchAgents/com.p5healthcheck.daily.plist
```
