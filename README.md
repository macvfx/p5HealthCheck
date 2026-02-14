# P5 Health Check Overview

## Purpose
P5 Health Check provides quick operational visibility into one or more P5 servers.

It includes:
- A full macOS window app (`P5Window`) for detailed review and exports.
- A macOS menu bar app (`P5MenuBar`) for fast status checks and quick actions.
- A macOS Bash CLI script for terminal-based checks and automation.

## Components

### 1) P5Window (macOS app)
Primary desktop UI for detailed health analysis.

Key features:
- Multi-server management (add/edit/delete/select).
- Server import from JSON.
- Secure password storage in Keychain.
- Health checks for:
  - server info and uptime
  - device cleaning state
  - warning jobs and error jobs
  - volume inventory and mode counts
- Multi-server summary view.
- Historical sections for job issues and volume changes.
- CSV export for volume details.

## 2) P5MenuBar (macOS menu bar app)
Always-available compact monitor from the menu bar.

Key features:
- Popover status for selected/all configured servers.
- Multi-server summary at top (when multiple servers are configured).
- Quick actions:
  - refresh selected
  - refresh all
  - open settings
- Cleaning alert visibility, including flashing red menu bar icon when cleaning is required.
- Per-server clean/warn/error and LTO mode indicators.

## 3) Bash CLI (`p5_health_check.sh`)
Terminal-first health checks for manual runs or automation.

Key features:
- Interactive mode:
  - prompts for server/credentials
  - optional Keychain save
  - optional repeat checks for additional servers
- Non-interactive mode (`-n`) for one-shot execution.
- Optional config file input (`-c`) using server JSON.
- Selective checks or full check set.
- Output artifacts:
  - JSON report
  - warnings CSV
  - errors CSV
  - volumes CSV
- Optional output path override (`-o`).

## Shared Behavior Across Tools
- Uses P5 REST API endpoints for health data.
- Supports multiple servers via shared JSON format.
- Keeps passwords out of JSON config and stores secrets in Keychain.
- Focuses on actionable operational signals:
  - drive cleaning needs
  - warning/error jobs (with protocol-summary enrichment where available)
  - tape mode pressure (appendable/readonly/full)

## Typical Workflow
1. Define servers in JSON (`/Users/Shared/P5HealthCheckServers.json`) or add manually in app settings.
2. Add passwords in each app (stored in Keychain).
3. Use menu bar app for quick monitoring.
4. Use window app for deeper review and exports.
5. Use CLI for scripted runs, scheduled tasks, or offline report generation.