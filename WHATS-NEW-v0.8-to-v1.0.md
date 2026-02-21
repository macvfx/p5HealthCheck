# What's New — P5 Health Check v0.8 → v1.0

A concise summary of everything added, changed, and improved between v0.8 and the current v1.0 release.

---

## Jukebox Support (App + CLI)

Tape library status is now a first-class check in both tools.

- **Window app** — new **Jukeboxes** section (between Devices and Licence) shows each library's ID, total slot count, and how many volumes are currently loaded. Hidden automatically when no jukeboxes are configured on the server.
- **Menu bar** — `JB:` pills appear in the per-server popover with loaded/total slot counts.
- **CLI** — option 6 fetches jukebox list, detail, and volumes per library; results included in report JSON and printed in the run summary. Non-fatal if the endpoint is unavailable.

---

## Licence Monitoring (App + CLI)

Free-licence counts per resource type (Device, Jukebox, Client, ArchivePlan, BackupPlan, etc.) are now monitored and highlighted.

- **Window app** — collapsible **Licence** section (click triangle to expand). Resources grouped by urgency:
  - **Depleted** (`free = 0`) → "None" in red, shown first
  - **Low** (`free 1–2`) → count in orange
  - **Normal** (`free > 2`) → count in green
  - **Unlimited** (`free = -1`) → single grouped row at the bottom
  - Header shows depleted/low badge counts so you can spot issues without expanding the section.
- **Menu bar** — `Lic:` pills show licence warnings. *(Note: removed in build 2 pending a better compact format; planned for a future update with maintenance date info.)*
- **CLI** — option 7 fetches all licence resources and prints `[ALERT]` for depleted and `[WARN]` for low resources to stdout. Results included in report JSON with `status` field (`unlimited` / `depleted` / `low` / `ok`).

---

## Tape Health Columns (App + CLI)

Volume-level tape-health data is now fetched, displayed, and exported.

- Three new fields decoded from the P5 API per volume: **Last Used**, **Use Count**, and **Error Count** (combined hard/soft read/write errors).
- **Window app** — each volume series row now shows a secondary health line below the range label (e.g. `Last used: 2024-11-03 · Uses: 412 · Errors: 2` — errors shown in orange when > 0).
- **CSV exports** — all three export types (All Volumes, Archive Tape Usage, Backup Tape Usage) now include `Last Used`, `Use Count`, and `Error Count` columns.
- **CLI** — volume CSV gains the same three columns; JSON report includes `dateused`, `usecount`, plus all individual hard/soft error counters and `totalErrors` per volume. A `[WARN]` line is printed in the summary if any volume has errors.

---

## UI Improvements (Window App)

- **Volume chips colour-coded** — the Appendable / Readonly / Full count chips in the Volumes section now use green / orange / red text and tinted backgrounds (matching the menu bar pill style).
- **Jobs section merged** — Job Warnings and Job Errors are combined into a single collapsible **Jobs** section. The header shows a live error/warning count; the section auto-opens when issues exist.
- **History collapsible** — the entire History GroupBox is now wrapped in a top-level disclosure triangle. Starts collapsed; auto-opens when any history records exist.
- **History sub-sections** — Recent Job Issues and Recent Volume Changes are independently collapsible inside History.
- **Volume series summary** — instead of individual tape names, volumes are grouped by label prefix, mode, and usage into compact range rows (e.g. `ProjectArchive.0001–0126 · Appendable · Archive`) with colour-coded mode badges.
- **Multi-server summary restyled** — Drive status split into grey "Drive:" label + semibold green/red "Clean"/"Not Clean". "Jobs:" grey label added before Warn/Err tags. Tags colour-code green when 0, orange/red when > 0.
- **Volumes section moved above Jobs** — tape counts are visible without scrolling past job lists.
- **Refresh buttons moved to sidebar** — Refresh Selected and Refresh All appear directly in the sidebar alongside import/export, keeping all server actions together.
- **Settings moved to a sheet** — Health Check Settings (Data Fetch, Auto Refresh, History retention) now open as a dedicated sheet via a `Settings` button at the bottom of the sidebar.
- **Export dropdown** — the single Export button replaced with an `Export` menu offering three options: All Volumes, Archive Tape Usage, Backup Tape Usage. Each export is sorted by mode and includes a `Usage` column.

---

## UI Improvements (Menu Bar App)

- **Drive status styled** — "Drive:" label renders in secondary grey; "Clean" / "Not Clean" in semibold green / red in both single-server and multi-server popover views.
- **DisclosureGroup triangles fixed** — all collapsible sections (Jobs, Recent Job Issues, Recent Volume Changes) can be manually collapsed at any time, not just auto-opened by data.
- **Settings window redesigned** — Servers section in a labelled GroupBox; action buttons reorganised into Add/Edit/Delete and Import/Export rows; scheduler redesigned as a horizontal row of rounded boxes (Mode + detail + retention at a glance); Refresh actions separated into their own row.
- **Show-password toggle** added to server editor password field.

---

## CLI (`p5_health_check.sh`) — New Features

The shell script was substantially expanded to match the app's feature set:

| Check | v0.8 | v1.0 |
|---|---|---|
| Server info | ✅ | ✅ |
| Device cleaning | ✅ | ✅ |
| Job warnings/errors | ✅ | ✅ |
| Volume list + mode counts | ✅ | ✅ |
| Volume CSV export | ✅ | ✅ |
| Tape health columns (Last Used, Use Count, Error Count) | ❌ | ✅ build 3 |
| Volume error `[WARN]` flag | ❌ | ✅ build 3 |
| Jukebox check | ❌ | ✅ build 3 |
| Licence check + `[ALERT]`/`[WARN]` flags | ❌ | ✅ build 3 |

Additional CLI fixes: "LTO modes" renamed to "Volume modes"; non-interactive mode (`-n`) now runs all seven checks by default; report JSON extended with `jukeboxes`, `licenceResources`, `volumeTotalErrors`, `licenceAlertCount`, `licenceWarnCount`.

---

## Bug Fixes

- **Swift type-checker timeout** in `HealthMonitor.swift` (large array literal) — fixed with explicit `[String]` type annotations and extracted sub-expressions.
- **`.utf8` encoding inference failure** in `HealthMonitor.swift` — fixed by using fully-qualified `String.Encoding.utf8`.
- **Settings sheet layout clipping** — replaced `Form`/`.formStyle(.grouped)` with `GroupBox`-based layout matching the menu bar style.
- **macOS 12 build error** (`formStyle(.grouped)`) — guarded behind `#available(macOS 13.0, *)`.
- **ATS HTTP blocking** — transport security exception added to app plist.
- **Menu bar selected-server picker stability** — keychain status checks during view updates stabilised.

---

*For the complete build-by-build history see `CHANGELOG-P5-Health-Check.md`.*
*For the full App vs CLI feature comparison table see the top of the changelog.*
