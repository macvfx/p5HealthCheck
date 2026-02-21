# P5 Health Check Overview

## Purpose
P5 Health Check provides quick operational visibility into one or more Archiware P5 servers via the P5 REST API.

It includes:
- A full macOS window app (`P5Window`) for detailed review, history tracking, and exports.
- A macOS menu bar app (`P5MenuBar`) for fast status checks and persistent monitoring.
- A macOS Bash CLI script (`p5_health_check.sh`) for terminal-based checks and automation.

## Components

### 1) P5Window (macOS app)
Primary desktop UI for detailed health analysis.

Key features:
- Multi-server management (add/edit/delete/select); import/export server list as JSON.
- Secure password storage in Keychain.
- Health checks for:
  - server info and uptime
  - device cleaning state
  - jukebox status (slot count and volumes loaded per library)
  - licence resource free counts (colour-coded by urgency)
  - warning jobs and error jobs (collapsible, with live count badge)
  - volume inventory and mode counts (Appendable / Readonly / Full) with tape health stats
- Multi-server summary view with colour-coded drive and job status.
- Historical sections for job issues and volume changes (SQLite-backed).
- CSV export (All Volumes / Archive Tape Usage / Backup Tape Usage) including Last Used, Use Count, and Error Count columns.
- Auto-refresh scheduler (manual / hourly / daily).

### 2) P5MenuBar (macOS menu bar app)
Always-available compact monitor from the menu bar.

Key features:
- Popover status for selected/all configured servers.
- Multi-server summary at top (when multiple servers are configured).
- Per-server group: Drive status (green/red), uptime, job warn/error counts, tape mode counts, jukebox pills.
- Licence warning pills when any resource is depleted or low.
- Cleaning alert: menu bar icon flashes red when any server needs drive cleaning.
- Quick actions: Refresh Selected, Refresh All, open Settings.

### 3) Bash CLI (`p5_health_check.sh`)
Terminal-first health checks for manual runs or automation.

Key features:
- Interactive mode: prompts for server/credentials, optional Keychain save, optional repeat checks for additional servers.
- Non-interactive mode (`-n`) for one-shot execution (all 7 checks run automatically).
- Optional config file input (`-c`) using shared server JSON.
- Seven checks (all enabled by default in `-n` mode):
  1. Server info + uptime
  2. Devices (cleaning needed)
  3. Job warnings
  4. Job errors
  5. Volumes + mode counts + CSV (including Last Used, Use Count, Error Count)
  6. Jukeboxes (slot count + volumes loaded per library)
  7. Licence resources (`[ALERT]` for depleted, `[WARN]` for low)
- Output artifacts per run: JSON report, volumes CSV, warnings CSV, errors CSV.
- Optional output path override (`-o`).

## Shared Behaviour Across Tools
- Uses P5 REST API endpoints for health data.
- Supports multiple servers via shared `P5Servers.json` config format.
- Keeps passwords out of JSON config — secrets stored in macOS Keychain.
- Common actionable signals monitored across all tools:
  - drive cleaning needs
  - warning/error jobs (with protocol-summary enrichment)
  - tape mode pressure (appendable/readonly/full)
  - jukebox capacity (slots vs loaded volumes)
  - licence resource free counts

## Server Config JSON

All three tools share the same JSON format. The default filename is `P5Servers.json`.

**Auto-detection at launch (apps)** — servers are imported silently on startup if either file is found:

| File | Location |
|---|---|
| `P5Servers.json` | `/Users/Shared/` or `~/Documents/` |
| `P5HealthCheckServers.json` | `/Users/Shared/` or `~/Documents/` |

**CLI default** — the script looks for `/Users/Shared/P5Servers.json` when no `-c` flag is given. Override with `-c /path/to/file.json`.

**Format:**
```json
{
  "servers": [
    {
      "alias": "P5 Primary",
      "host": "p5-primary.local",
      "port": "8000",
      "username": "admin",
      "apiVersion": "v1",
      "useHTTPS": false
    }
  ]
}
```

Passwords are never stored in the file. Enter them in each app's Settings (saved to Keychain) or allow the CLI to save them on first interactive run.

**P5Window** — `Import Servers JSON` and `Export Servers JSON` buttons in the server sidebar.

**P5MenuBar** — `Import JSON` and `Export JSON` buttons in Settings → Servers section.

Exported files default to `P5Servers.json` and can be shared with any other P5 Archive app.

## Typical Workflow
1. Place `P5Servers.json` in `/Users/Shared/` (or add servers manually in app settings).
2. Launch either app — servers are imported automatically.
3. Enter passwords in Settings (saved to Keychain).
4. Use the menu bar app for quick daily monitoring.
5. Use the window app for deeper review, history, and CSV exports.
6. Use the CLI for scripted/scheduled runs or integration with alerting pipelines.

## Related Docs
- Window app guide: `USER_GUIDE-P5Window.md`
- Menu bar guide: `USER_GUIDE-P5MenuBar.md`
- CLI guide: `USER_GUIDE-P5-Health-Check-CLI.md`
- Changelog: `CHANGELOG-P5-Health-Check.md`
- What's new (v0.8 → v1.0): `WHATS-NEW-v0.8-to-v1.0.md`
- Roadmap: `ROADMAP-P5HealthCheck.md`
