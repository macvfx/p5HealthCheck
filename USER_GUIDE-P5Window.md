# User Guide - P5Window

## What It Is
`P5Window` is the full dashboard app for detailed health checks and volume analysis.

## App vs CLI

P5 Health Check ships two independent tools for the same P5 REST API:

- **Mac apps** (`P5Window` + `P5MenuBar`) — interactive monitoring with auto-refresh, multi-server comparison, history tracking, and a colour-coded UI. Best for daily oversight.
- **CLI** (`p5_health_check.sh`) — automation-friendly: runs unattended via cron/launchd, outputs a structured JSON report and CSVs per run, prints `[ALERT]`/`[WARN]` flags to stdout for licence and tape errors. Best for scripting and alerting pipelines.

Both tools share the same `P5Servers.json` config format and Keychain password storage.

## Main Areas
- **Server list** (sidebar): add/edit/duplicate/delete server configs; import/export as JSON.
- **Refresh Selected / Refresh All** (sidebar buttons): fetch latest health data for the selected server or all servers.
- **Settings** (sidebar button): opens a sheet with Data Fetch, Auto Refresh, connectivity uptime-check interval, and History retention controls.
- **Server info**: hostname, Lexx version, platform, uptime, and last checked timestamp.
- **Devices**: whether drive cleaning is needed.
- **Jukeboxes** (shown after Devices, if configured): tape library name, slot count, and volumes-loaded count per library.
- **Licence** (shown after Jukeboxes, if available): collapsible section (click triangle to expand). Resources grouped by urgency — depleted (red "None"), low (orange count), normal (green count), unlimited (single "Unlimited" row). Header shows badge counts for depleted and low resources so you can spot issues without opening the section.
- **Volumes panel** (shown after Licence, collapsible):
  - Header stays visible when collapsed, with total volume count plus coloured pills for **Appendable** (green) / **Readonly** (orange) / **Full** (red).
  - Total mode count chips: **Appendable** (green) / **Readonly** (orange) / **Full** (red) — colour matches urgency.
  - Usage split by mode: Archive vs Backup counts for each mode.
  - Volume series list: volumes grouped by label prefix and mode into compact range rows (e.g. `ProjectArchive.0001–0126 · Appendable · Archive`) with colour-coded mode badges, plus a secondary health line showing Last Used date, total Use Count, and Error Count (in orange if > 0).
- **Plans** (collapsible, shown after Volumes): grouped by kind (Archive / Backup / Sync) with plan ID, description, enabled state, source/target endpoint details, and schedule rows when available.
- **Jobs** (collapsible): combined Errors + Warnings section with live count badge in the header. Auto-opens when issues exist; can be manually collapsed at any time.
- **Multi-server summary**: drive status + warning/error counts per server (shown when more than one server is configured).
- **History** (collapsible GroupBox): auto-opens when any history records exist; can be manually collapsed.
  - Action Required: always visible inside History; surfaces blocking job events and tape pressure snapshots.
  - Recent Job Issues (collapsible): auto-opens when records exist.
  - Recent Volume Changes (collapsible): auto-opens when records exist.
- **Export menu** (toolbar):
  - volume CSV exports — All Volumes, Archive Tape Usage, Backup Tape Usage
  - plan markdown exports — All Plans, Archive Plans, Backup Plans, Sync Plans
  - job result CSV exports — All Job Results, Error Job Results, Warning Job Results

## How To Use
1. Launch `P5Window`.
2. Click `Add Server` and enter server values:
   - Alias
   - Host / IP Address
   - Port (default `8000`)
   - Username/password
   - API version (default `v1`)
   - HTTPS toggle if needed
3. Select a server from the list.
   - Tip: right-click a server row and choose `Edit Server` as a shortcut.
   - Dot indicator at left: green = password saved in Keychain, orange = no saved password yet.
   - Use `Duplicate Selected` when you need a copy with only small changes (for example IP or password variant).
   - In v1.3, selection is explicit in settings flows and `Edit` opens the selected server with fields populated on the first click (timing issue fixed).
4. Click `Refresh Selected` in the sidebar to fetch one server, or `Refresh All` for all servers.
5. Review sections (scroll order):
   - `Devices`: `Needs cleaning: Yes/No`
   - `Jukeboxes`: library ID · slot count · volumes loaded (hidden when no jukeboxes configured)
   - `Licence`: collapsible — click triangle to expand; depleted/low badge counts shown in header even when collapsed
   - `Volumes`: disclosure section with header totals/pills, plus Archive/Backup split and grouped series list
   - `Plans`: grouped Archive/Backup/Sync plan details — click triangle to collapse/expand
   - `Jobs`: combined Errors + Warnings — click the triangle to collapse/expand
   - `History`: click the triangle to expand — Action Required always visible inside, plus collapsible job and volume change logs
6. Use the `Export` menu in the toolbar to generate exports:
   - **All Volumes** — full volume list (includes Last Used, Use Count, Error Count columns)
   - **Archive Tape Usage** — archive-usage volumes only
   - **Backup Tape Usage** — backup-usage volumes only
   - **All Plans / Archive Plans / Backup Plans / Sync Plans** — markdown documentation export of configured plans
   - **All Job Results / Error Job Results / Warning Job Results** — job-result CSV exports
7. Click `Settings` at the bottom of the sidebar to adjust Data Fetch, Auto Refresh, and History retention.
   - Connectivity uptime checks use presets (`15 min`, `1 hour`, `1 day`) or a custom minute interval.

## JSON Import & Export

### Import
1. Click `Import Servers JSON` in the server sidebar.
2. Select a JSON file — supports `{ "servers": [ ... ] }` or `[ ... ]` format.
3. Imported servers are added without passwords; duplicates are skipped.
4. Edit each new server once to enter its password (saved to Keychain).

### Export
1. Click `Export Servers JSON` in the server sidebar.
2. Choose a save location — filename defaults to `P5Servers.json`.
3. The file contains all server details except passwords.
4. Use the exported file to populate any other P5 Archive app.

### Auto-detection at launch
Place `P5Servers.json` (or `P5HealthCheckServers.json`) in `/Users/Shared/` or `~/Documents/` and the app imports new servers automatically on next launch.

## Tips
- Increase `Max volume details` (in Settings) when you need broader volume coverage.
- Set `Warning job lookback (days)` (in Settings) to widen or narrow the job history window.
- Use multi-server summary for quick comparison before drilling into one server.
- Disclosure sections (History, Jobs, Recent Job Issues, Recent Volume Changes) all auto-open when new data arrives but can be collapsed manually at any time by clicking the triangle.
- Licence section only appears if the P5 server returns licence resource data; it is silently hidden otherwise. `-1` free means Unlimited — those resources are grouped into one row at the bottom. `0` free means None (shown in red) — check with your P5 admin.
- Volume mode count chips (Appendable / Readonly / Full) use traffic-light colours: green = healthy, orange = monitor, red = attention needed.
- CSV exports include `Last Used`, `Use Count`, and `Error Count` columns for tape-health analysis.
- Plan markdown exports provide filtered documentation sets: All Plans, Archive Plans, Backup Plans, and Sync Plans.
- `Duplicate Selected` is the fastest way to create a near-copy when only host/IP, username, or password changes between environments.
