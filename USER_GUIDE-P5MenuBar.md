# User Guide - P5MenuBar

## What It Is
`P5MenuBar` is the compact monitoring app that runs in the macOS menu bar. It provides a fast, always-available health snapshot for one or more P5 servers without needing to open a full window.

## App vs CLI

P5 Health Check ships two independent tools for the same P5 REST API:

- **Mac apps** (`P5Window` + `P5MenuBar`) — interactive monitoring with auto-refresh, multi-server comparison, history tracking, and a colour-coded UI. Best for daily oversight.
- **CLI** (`p5_health_check.sh`) — automation-friendly: runs unattended via cron/launchd, outputs a structured JSON report and CSVs per run, prints `[ALERT]`/`[WARN]` flags to stdout for licence and tape errors. Best for scripting and alerting pipelines.

Both tools share the same `P5Servers.json` config format and Keychain password storage.

## Main Features
- Fast health snapshot for selected server.
- Multi-server top summary (when more than one server exists).
- Multi-server grouped status cards (one group per server).
- Per-server group shows:
  - Server name
  - Compact status row: `P5 Up/Down - LTO ●`
    - Only `Up/Down` is colour-coded (green/red)
    - LTO state is shown by end-of-line dot colour (green/red)
  - Uptime
  - Warning and error counts (green when 0, orange/red when > 0)
  - Tape mode counts: Appendable / Readonly / Full
- For more than 3 servers, `Server Reports` provides two display modes:
  - `Detailed` (full stacked cards)
  - `Grid` (compact 3-per-row cards)
- The popover is taller in v1.3 to show at least about 3 server reports before scrolling.
- Scroll appears on the right only if report content exceeds available popover height in the current mode.
- Jukebox status per server: volumes loaded / slot count per library.
- Licence warnings when any resource is depleted or low.
- Buttons: `Refresh All`, `Settings`.
- Footer actions: `Open Main App` (opens `P5Window`) and `Quit`.
- Menu bar icon flashes red when any configured server reports a cleaning-required drive.

## How To Use
1. Launch `P5MenuBar`.
2. Click the menu bar icon to open the popover.
3. Click `Settings` to add/edit/duplicate/remove servers.
4. In Settings, use `Import JSON` or `Export JSON` to load or save a server list.
5. Use `Refresh All` to update all configured servers.
6. If you have more than 3 servers, choose `Detailed` or `Grid` in `Server Reports`.
7. Review server groups and status pills.
8. Use `Open Main App` in the popover footer to jump directly to the full `P5Window` app when you need deeper analysis.

## JSON Import & Export

### Import
1. Open `Settings`.
2. Click `Import JSON` in the Servers section.
3. Choose a JSON file — supports `{ "servers": [ ... ] }` or `[ ... ]` format.
4. Imported servers are added without passwords; duplicates are skipped.
5. Edit each new server once to enter its password (saved to Keychain).

### Export
1. Open `Settings`.
2. Click `Export JSON` in the Servers section.
3. Choose a save location — filename defaults to `P5Servers.json`.
4. The file contains all server details except passwords.
5. The exported file can be imported by any other P5 Archive app.

### Auto-detection at launch
The app automatically imports new servers on launch if either of these files is present:

| File | Location |
|---|---|
| `P5Servers.json` | `/Users/Shared/` or `~/Documents/` |
| `P5HealthCheckServers.json` | `/Users/Shared/` or `~/Documents/` |

Duplicate servers (matched by alias) are skipped. Passwords are never stored in the file — enter them in Settings after import.

## Settings Window
The Settings window is organised into two sections:

**Servers**
- Server list (no row is treated as selected until you click it).
- Action buttons (first row): `Add`, `Edit`, `Duplicate`, `Delete`.
- Action buttons (second row): `Import JSON`, `Export JSON`.
- `Edit` opens the selected server immediately with fields prefilled (v1.3 fix for first-click empty editor timing issue).
- Server editor fields: Alias, Host / IP Address, Port, Username, Password (with show/hide toggle), API version, HTTPS toggle.

**Scheduler**
- Horizontal row of rounded boxes:
  - `1) Refresh all info via API` (Manual / Hourly / Daily + interval/time detail)
  - `2) Check uptime` (connectivity interval presets: `15 min`, `1 hour`, `1 day`, `Custom`)
  - `Retention` (history days)
- Custom uptime interval supports `5...1440` minutes in 5-minute steps.
- `Refresh All` action button below the scheduler.

## Menu Bar Status Readout
- Current compact format in cards/summaries is:
  - `P5 Up/Down - LTO ●`
- Interpretation:
  - `P5 Up` (green `Up`) means the connectivity check reached the server.
  - `P5 Down` (red `Down`) means the connectivity check failed.
  - `LTO` end-dot indicates drive-cleaning state (green = clean, red = cleaning required).

## Notes
- Best for quick checks and persistent monitoring.
- Use `P5Window` for deeper analysis, historical trends, and CSV exports.
- Requires macOS 14+.
