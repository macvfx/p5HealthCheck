# What's New — P5 Health Check v1.0 to v1.6

A highlight reel of the most visible changes across **P5Window**, **P5MenuBar**, and the brand-new **P5iPhone** app — from the v1.0 public release through the current v1.6 / v1.1 candidate.

For full build-by-build history, see `CHANGELOG-P5-Health-Check.md`.

---

## v1.6 (Mac) / v1.1 (iPhone) — 2026-03-14

### Import Duplicate Safety (All Apps)

- Manual JSON import now warns when duplicates are detected and imports only new servers if you continue.
- Launch-time auto-import silently skips exact duplicates.
- All three apps share the same identity rule: `alias + host + port + username + apiVersion + useHTTPS`.
- Shared import-preview support in `P5HealthCore` drives the same duplicate warning flow across macOS and iOS.

### P5Window Sidebar Reorganisation

- The main sidebar is now focused on server selection plus `Refresh Selected`, `Refresh All`, and `Settings`.
- Server management (add / edit / duplicate / delete / import / export) moved into the Settings sheet alongside scheduler, data-fetch, and history controls.
- Settings sheet widened to fit the merged server-management controls without clipping.

### iPhone Plans Display Improvements

- Plans are grouped into `Archive`, `Backup`, and `Sync`.
- Plan names and descriptions are shown first (matching the Mac window app), with plan ID as secondary text.
- `Enabled` / `Disabled` state is now visible per plan.

### Version Alignment

- `P5Window` and `P5MenuBar` set to `1.6 (1)`.
- `P5iPhone` set to `1.1 (1)`.

---

## P5 Health Check iPhone — v1.0 Builds 7–10 — 2026-03-09

The iPhone app's first public candidate received a concentrated round of UI polish:

### Layout & Style

- **Full-screen support** — added `UILaunchScreen` to eliminate legacy black bars (build 10).
- **Servers tab restyled** — replaced `List` with a `ScrollView` + card-based layout matching the Dashboard's rounded-rect style (build 7).
- **Single-line dashboard title** — switched to `.title2` with `lineLimit(1)` so "P5 Health Check" never wraps (build 9).
- **Tighter spacing** — reduced `VStack` spacing from 16pt to 12pt across Dashboard and Servers (build 7).
- **Consistent status-pill text** — standardised all pill labels to "number then word" format across Fleet Summary, Server Cards, and Server Detail, e.g. `"2 Online"`, `"3 Warnings"`, `"5 Appendable"` (build 7).

### Bug Fixes

- **Double bottom inset** — removed redundant safe-area inset that was creating excessive blank space (build 9).
- **Editor buttons showing "..."** — fixed SwiftUI button-chrome issue that was truncating Cancel/Save text (build 9).
- **Edit sheet blank fields** — replaced `.sheet(isPresented:)` with `.sheet(item:)` driven by an identifiable `SheetMode` enum to eliminate race conditions (build 8).

### New Features

- **Demo server** — `HealthSettings.ensureDemoServer()` creates a built-in demo entry with offline snapshot data so users can explore the app before configuring a real server (build 7).
- **DEMO button** appears only in the empty-state Servers view (build 8).

---

## v1.5 — 2026-03-06

### P5Window

- **Single-server auto-selection** — when one server is configured, the app auto-selects it and loads detail immediately.
- **Background multi-server refresh** — summary refresh continues in the background while the operator inspects a specific server.
- **Detail view reorganisation** — `Connectivity` is now its own top-level section; `Recent Volume Changes` lives under `Volumes`; `Recent Job Issues` lives under `Jobs`; the mixed `History` wrapper is removed.
- **Detail polish** — connectivity badge in collapsed header, licence section shows `devices (LTO)` and `slots (jukebox)` clearly, devices no longer show redundant `Yes/No` text.
- **Export menu clarity** — `Connectivity CSV` now separated from job-result exports.

### P5MenuBar

- **Report width and scroll** — detailed/grid content claims full popover width so the scroll indicator stays at the outer edge.

### P5iPhone (Initial Scaffold)

- New iOS target built on `P5HealthCore` with `Dashboard` and `Servers` tabs.
- Fleet summary and per-server status cards inspired by `P5MenuBar`.
- Server detail drill-down reusing selected sections from `P5Window`.
- Files-based JSON import and full add/edit/delete/duplicate server management.

### P5HealthCore

- **Cross-platform support** — expanded the Swift package to iOS; replaced macOS-only shell-based keychain helper with a `Security` framework implementation usable by both platforms.
- **SQLite maintenance** — removed `VACUUM` from normal history-prune path to reduce overhead.
- **Refresh lease gating** — lease checks now apply to manual/UI refreshes too, reducing duplicate polling when both Mac apps are open.
- **Volume-removal history** — volume history now records `removed` events and clears stale entries when media disappears.
- **Core regression tests** — added coverage for history pruning, scheduler leases, removed-volume persistence, settings selection persistence, server import parsing/deduplication, and monitor refresh gating.

---

## v1.4 — 2026-02-27

### Uptime Check Scheduling

- Dedicated uptime/connectivity interval controls in both Mac app settings.
- Presets: `15 min`, `1 hour`, `1 day`, plus `Custom` (up to 1440 minutes).

### Scheduler UX Clarified (Menu Bar)

- Labels now clearly separate two independent schedules:
  1. Refresh all info via API
  2. Check uptime
- Settings window enlarged so expanded scheduler controls fit without clipping.

### Menu Bar Status Readout

- Compact status line: `P5 Up/Down - LTO ●`
- Only `Up/Down` is colour-coded; `LTO` state indicated by end-of-line dot colour.
- `Clean/Not Clean` text removed to reduce crowding.

### Other

- **Last-checked timestamp** visible in P5Window server info.
- **CLI connectivity CSV export** added (`p5_health_check.sh`).
- Fixed SwiftUI publish-cycle warnings and menu bar settings compile issue.

---

## v1.3 — 2026-02-25

### Menu Bar Multi-Server Layout Modes

- For more than 3 servers, `P5MenuBar` offers two report layouts:
  - `Detailed` — stacked full cards.
  - `Grid` — compact 3-per-row cards.
- Scroll appears only when the selected layout exceeds available popover height.

### Server Edit Prefill Bug Fixed

- Editing a server now opens with fields pre-populated every time (both apps).

### Duplicate Server Action

- `Duplicate` button in P5Window and P5MenuBar settings.
- Preserves host/port/user/API/HTTPS, auto-generates a unique `Copy` alias, and copies Keychain password.

### Menu Bar Refresh Simplified

- Removed individual server picker and `Refresh Selected`.
- Menu bar now uses `Refresh All` only.

### Volumes Disclosure (P5Window)

- Volumes is now a collapsible disclosure group.
- Collapsed header shows total volume count and coloured mode pills (Appendable / Readonly / Full).

---

## v1.2 — 2026-02-24

### Plans Section (P5Window)

- New disclosure section listing configured Archive, Backup, and Sync plans from the P5 API.

### Export Additions (P5Window)

- **Plan Markdown exports** — `All Plans`, `Archive Plans`, `Backup Plans`, and `Sync Plans`.
- **Job result CSV exports** — `All Job Results`, `Error Job Results`, and `Warning Job Results`.

### Menu Bar Footer

- `Open Main App` button added next to `Quit` in the popover footer.

### Stability

- Sync plan loading now tolerates per-plan/per-event API failures and returns partial results instead of collapsing to `No plans`.
- Flexible sync-plan decoding for variant response shapes.

---

## App vs CLI — Feature Comparison

| Feature | Mac App (P5Window + P5MenuBar) | iPhone (P5iPhone) | CLI (`p5_health_check.sh`) |
|---|---|---|---|
| Server info (hostname, version, platform, uptime) | v1.0 | v1.0 | v1.0 |
| Device cleaning status | v1.0 | v1.0 | v1.0 |
| Job warnings / errors (with protocol detail) | v1.0 | v1.0 | v1.0 |
| Job CSV export (all / errors / warnings) | v1.2 | — | v1.0 |
| Volume list + mode counts | v1.0 | v1.0 | v1.0 |
| Volume CSV export | v1.0 | — | v1.0 |
| Plan visibility (Archive / Backup / Sync) | v1.2 | v1.0 | v1.0 |
| Plan Markdown export | v1.2 | — | v1.0 |
| Jukebox panel (slot count + volumes loaded) | v1.0 | v1.0 | v1.0 |
| Licence resource free counts (with alert colouring) | v1.0 | v1.0 | v1.0 |
| Multi-server support | v1.0 | v1.0 | — |
| Menu bar detailed/grid report toggle (>3 servers) | v1.3 | — | — |
| Duplicate server action | v1.3 | v1.0 | — |
| Import duplicate detection & warning | v1.6 | v1.1 | — |
| Connectivity CSV export | v1.0 | — | v1.4 |
| Auto-refresh scheduler | v1.0 | — | — |
| History (job + volume change tracking, SQLite) | v1.0 | — | — |
| Keychain password storage | v1.0 | v1.0 | v1.0 |
| Config JSON import (`P5Servers.json`) | v1.0 | v1.0 (Files) | v1.0 |
| Demo server (offline preview) | — | v1.0 | — |
| Non-interactive / automation mode | — | — | v1.0 |
| Report JSON output | — | — | v1.0 |
