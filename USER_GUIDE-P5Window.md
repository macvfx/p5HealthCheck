# User Guide - P5Window

## What It Is
`P5Window` is the full dashboard app for detailed health checks and volume analysis.

## Main Areas
- Server list: add/edit/delete server configs.
- Server import: import server definitions from JSON (`Import Servers JSON`).
- Server info: hostname, Lexx version, platform, uptime.
- Device status: whether cleaning is needed.
- Job warnings/errors: warning and failed job lists.
- Multi-server summary: drive status + warning/error counts per server.
- Volumes panel:
  - Total mode counts: Appendable / Readonly / Full.
  - Usage split by mode: Archive vs Backup counts for each mode.
- Export: save current volume dataset to CSV.

## How To Use
1. Launch `P5Window`.
2. Click `Add` and enter server values:
   - Alias
   - Host
   - Port (default `8000`)
   - Username/password
   - API version (default `v1`)
   - HTTPS toggle if needed
3. Select a server from the list.
   - Tip: right-click a server row and choose `Edit Server` as a shortcut.
   - Dot indicator at left: green = password saved in Keychain, yellow = no saved password yet.
4. Click `Refresh` for one server or `Refresh All` for all configured servers.
5. Review sections:
   - `Devices`: `Needs cleaning: Yes/No`
   - `Job Warnings` and `Job Errors`
   - `Volumes` totals and Archive/Backup split
6. Use `Export Volumes` to generate a CSV report.

## JSON Import
1. Click `Import Servers JSON` in the server sidebar.
2. Select a JSON file with either:
   - `{ "servers": [ ... ] }`
   - `[ ... ]`
3. Imported servers are added without passwords.
4. Open each imported server and add password once (saved to Keychain).

## Tips
- Increase `Max volume details` when you need broader volume coverage.
- Set `Warning job lookback (days)` to widen or narrow job history.
- Use multi-server summary for quick comparison before drilling into one server.
