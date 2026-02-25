# P5 Health Check

P5 Health Check is a macOS Swift project with two independent apps that share server settings:
- `P5Window`: full desktop dashboard.
- `P5MenuBar`: compact menu bar monitor.

Both apps use the P5 REST API to surface health and tape status details from one or more configured P5 servers.

## Core Features
- Shared server configuration (alias, host, port, API version, auth).
- Duplicate server action for fast cloning/editing variants.
- Server info and uptime monitoring.
- Device cleaning status (clean / not clean).
- Jukebox status: slot count and volumes loaded per library.
- Licence resource free-count monitoring with alert colouring.
- Job warning and failed job visibility.
- Plans visibility: configured Archive / Backup / Sync plans.
- Tape volume overview by mode (`Appendable`, `Readonly`, `Full`) with tape health stats (last used, use count, error count).
- Export menu options (window app):
  - volume CSV export (All Volumes / Archive Tape Usage / Backup Tape Usage)
  - plan markdown export (All / Archive / Backup / Sync)
  - job result CSV export (All / Error / Warning)
- Multi-server refresh and quick comparison.
- Menu bar popover uses `Refresh All` (selected-server controls removed in v1.3).
- Menu bar `Server Reports` supports `Detailed` and `Grid` layouts when more than 3 servers are configured.
- Menu bar report area is taller in v1.3 and only scrolls when the chosen layout exceeds available popover space.
- Settings edit flow in both apps now opens the selected server editor populated on the first click (no add/close workaround).

## App vs CLI

The project ships two independent tools that cover the same P5 REST API checks:

| Tool | Best for |
|---|---|
| `P5Window` + `P5MenuBar` (Mac apps) | Daily monitoring — visual dashboard, auto-refresh, multi-server comparison, history tracking |
| `p5_health_check.sh` (CLI) | Automation — cron/launchd scheduling, JSON report output, CSV export, scripting and alerting pipelines |

**Mac apps add:** multi-server support, auto-refresh scheduler, SQLite history (job + volume change tracking), richer UI (colour-coded licence tiers, collapsible sections, grouped volume series).

**CLI adds:** non-interactive mode (`-n`), structured JSON report per run, machine-parseable `[ALERT]`/`[WARN]` stdout flags for licence and tape errors, easy piping into other scripts.

Both tools share the same server config format (`P5Servers.json`) and Keychain password storage, so a server added in the app is immediately usable by the script.

See `Documents/CHANGELOG-P5-Health-Check.md` for the full feature comparison table.

## App Guides
- Window app guide: `USER_GUIDE-P5Window.md`
- Menu bar app guide: `USER_GUIDE-P5MenuBar.md`
- CLI guide: `p5_health_check.sh --help` (or run the script without arguments)


## Requirements
- macOS 12+ for `P5Window`.
- macOS 14+ for `P5MenuBar`.
- Reachable P5 REST endpoint.
- Valid username/password per server.

## Quick Start
1. Open `P5HealthCheck.xcodeproj` in Xcode.
2. Build and run either `P5Window` or `P5MenuBar` scheme.
3. Add one or more servers in settings.
4. Run `Refresh` or `Refresh All`.
