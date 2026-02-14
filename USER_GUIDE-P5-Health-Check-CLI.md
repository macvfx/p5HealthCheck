# P5 Health Check CLI (macOS) User Guide

## Files
- Script: `p5_health_check.sh`
- Sample server config: `P5HealthCheck-CLI-servers.example.json`

## What it does
- Checks one P5 server at a time.
- Prompts to check another server after each run.
- Supports selecting which checks to run (`1-5` or `all`).
- Prompts for credentials when not hardcoded.
- Can read/save passwords in macOS Keychain.
- Creates:
  - JSON summary report
  - Volumes CSV
  - Warning jobs CSV
  - Error jobs CSV

## Checks
1. Server info + uptime
2. Devices (cleaning needed)
3. Job warnings
4. Job errors
5. Volumes + mode counts + CSV

## Output
- Default output directory: current working directory.
- Optional output directory: pass `-o /path/to/output`.

File naming format:
- `<server-alias>-YYYYMMDD-HHMMSS-report.json`
- `<server-alias>-YYYYMMDD-HHMMSS-volumes.csv`
- `<server-alias>-YYYYMMDD-HHMMSS-warnings.csv`
- `<server-alias>-YYYYMMDD-HHMMSS-errors.csv`

## Usage
Run from Terminal:

```bash
cd "/Users/username/Downloads/"
chmod +x p5_health_check.sh
./scripts/p5_health_check.sh
```

Common options:

```bash
./scripts/p5_health_check.sh -o "/Users/username/Desktop/p5-reports"
./scripts/p5_health_check.sh -c "/Users/Shared/P5HealthCheckServers.json"
./scripts/p5_health_check.sh -l 7 -m 500
./scripts/p5_health_check.sh -k
```

## CLI Option Examples

```bash
./scripts/p5_health_check.sh -o "/Users/username/Desktop/p5-reports"
./scripts/p5_health_check.sh -c "/Users/Shared/P5HealthCheckServers.json"
./scripts/p5_health_check.sh -l 7 -m 500
./scripts/p5_health_check.sh -k
./scripts/p5_health_check.sh -K
./scripts/p5_health_check.sh -n -c "/Users/Shared/P5HealthCheckServers.json" -o "/Users/username/Desktop/p5-reports"
./scripts/p5_health_check.sh -p
./scripts/p5_health_check.sh -c "/Users/Shared/P5HealthCheckServers.json" -U "myuser" -p
```

## Option Reference
- `-o DIR`: Output directory for generated files. Default is the current working directory.
- `-c FILE`: Server config JSON path. If omitted, script uses `/Users/Shared/P5HealthCheckServers.json` when that file exists.
- `-l N`: Warning/error job lookback window in days. Default is `7`.
- `-m N`: Maximum number of volume detail records to fetch. Default is `500`; use `0` for unlimited.
- `-k`: Allow insecure TLS (`curl -k`) for environments with self-signed or untrusted certificates.
- `-n`: Non-interactive mode. Runs once, executes all checks, and does not prompt.
- `-p`: Force password prompt for this run and ignore both Keychain and hardcoded password values.
- `-K`: In interactive mode, try Keychain password before prompting.
- `-U NAME`: Override username for this run (useful when config username is outdated).
- `-A AUTH`: Override auth as raw `user:pass` for this run. Use only for troubleshooting with non-secret test credentials, because command-line arguments are stored in shell history.
- `-h`: Print help/usage and exit.

## Non-Interactive Mode
- Use `-n` to run once without prompts.
- In `-n` mode, script runs all checks automatically.
- Server selection in `-n` mode:
  - uses hardcoded values if set in script
  - otherwise uses the first server from `-c` config file (or default `/Users/Shared/P5HealthCheckServers.json` if present)
- Password in `-n` mode:
  - uses `HARDCODED_PASSWORD` if set
  - otherwise reads from Keychain
  - if missing, script exits with an error (no password prompt in `-n` mode)

## Config file format
- Supported JSON shapes:
  - `{ "servers": [ ... ] }`
  - `[ ... ]`
- Per server fields:
  - `alias` (required)
  - `host` (required)
  - `port` (optional, default `8000`)
  - `username` (optional, default `admin`)
  - `apiVersion` (optional, default `v1`)
  - `useHTTPS` (optional, default `false`)

## Keychain behavior
- Service name used by script: `com.p5healthcheck.shell`
- Account key format: `username@host:port/rest/apiVersion`
- If no hardcoded password is present:
  - interactive mode first prompts for raw credentials as `user:pass` (recommended)
  - if skipped, prompts for password-only
  - optional `-K` makes script try Keychain first in interactive mode
  - non-interactive mode (`-n`) uses Keychain/hardcoded values only
  - offers to save password to Keychain

## Secure Credential Entry (Recommended)
- To keep secrets out of shell history, run with `-p` and enter credentials at the hidden prompt.
- At prompt `Credentials as user:pass (recommended, Enter to skip):` enter exactly:
  - `username:password`
- Include the colon between username and password.
- Do not add quotes at the prompt.

## `-A` Safety Note
- `-A "username:password"` places credentials in shell history and process arguments.
- Use `-A` only for testing/troubleshooting and only with non-secret account info.
- Prefer `-p` with hidden interactive entry for real credentials.

## Hardcoded credentials (optional)
Edit the top of the script and set:
- `HARDCODED_ALIAS`
- `HARDCODED_HOST`
- `HARDCODED_PORT`
- `HARDCODED_USERNAME`
- `HARDCODED_PASSWORD`
- `HARDCODED_API_VERSION`
- `HARDCODED_USE_HTTPS`

If fields are blank, the script prompts interactively.