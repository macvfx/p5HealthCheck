# User Guide - P5MenuBar

## What It Is
`P5MenuBar` is the compact monitoring app that runs in the macOS menu bar.

## Main Features
- Fast health snapshot for selected server.
- Multi-server top summary (when more than one server exists).
- Multi-server grouped status cards (one group per server).
- Per-server group shows:
  - Server name
  - Drive status: `Clean` or `Not Clean`
  - Uptime
  - Warning and error counts
  - Tape mode counts: Appendable / Readonly / Full
- Buttons: `Refresh Selected`, `All` (refresh all), `Settings`.
- Menu bar icon flashes red when any configured server reports a cleaning-required drive.

## How To Use
1. Launch `P5MenuBar`.
2. Open the menu bar icon.
3. Click `Settings` to add/edit/remove servers.
4. In Settings, you can also import server definitions with `Import JSON`.
5. Use `Refresh Selected` for the current server or `All` for all servers.
5. Review server groups and status pills.

## JSON Import
1. Open `Settings`.
2. Click `Import JSON`.
3. Choose a file using either:
   - `{ "servers": [ ... ] }`
   - `[ ... ]`
4. Imported servers are added without passwords.
5. Edit each imported server once to enter password (saved to Keychain).

## Notes
- Best for quick checks and monitoring.
- Use `P5Window` for deeper analysis and CSV exports.
