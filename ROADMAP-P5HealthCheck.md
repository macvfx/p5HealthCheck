# P5 Health Check Roadmap

## Completed — v0.1 to v0.5
- Basic health snapshot pipeline: server info, devices, jobs, volumes.
- Shared settings between window app and menu bar app.
- Multi-server monitoring with `Refresh Selected` and `Refresh All`.
- Menu bar multi-server clean-status summary with flashing red icon when cleaning needed.
- Server uptime visibility in both apps.
- Job warning and failed job visibility.
- Volume mode summary (`Appendable`, `Readonly`, `Full`) with Archive/Backup split.
- CSV export: server-prefixed and timestamped filenames, Location field, human-readable size columns.
- App icon and UX fixes for settings window behaviour.

## Completed — v0.6 to v0.8
- SQLite persistence layer for health snapshots and summaries.
- Historical summary views: Action Required, Recent Job Issues, Recent Volume Changes.
- Configurable refresh schedule: manual / hourly / daily.
- Volume series summary: volumes grouped by label prefix, mode, and usage into compact range rows.
- Merged Jobs section (Warnings + Errors in one collapsible DisclosureGroup).
- Export dropdown: All Volumes / Archive Tape Usage / Backup Tape Usage, with Usage column.
- Settings moved to dedicated sheet in sidebar (window app).
- Refresh buttons moved to sidebar.
- Menu bar settings window redesigned with horizontal scheduler layout.
- Show-password toggle in server editor.
- Server list JSON import/export with auto-detection (`P5Servers.json`, `P5HealthCheckServers.json`) in `/Users/Shared/` and `~/Documents/`.

## Completed — v1.0
- **Jukebox panel** (window app, menu bar, CLI) — slot count and volumes loaded per library.
- **Licence monitoring** (window app, menu bar, CLI) — free counts per resource type, colour-coded by urgency (depleted / low / normal / unlimited). CLI prints `[ALERT]`/`[WARN]` to stdout.
- **Tape health columns** — Last Used, Use Count, Error Count added to volume series display, CSV exports, and CLI JSON report.
- **Volume series health line** — secondary line per series showing last used date, total use count, and error count (orange when > 0).
- **Licence section redesigned** — collapsible DisclosureGroup, tiered urgency grouping, header badge counts.
- **Volume chips colour-coded** — Appendable (green) / Readonly (orange) / Full (red) in both apps.
- **Menu bar Drive: styling** — grey label + semibold green/red Clean/Not Clean text.
- **Window multi-server summary restyled** — drive/jobs colour-coded, grey labels.
- **CLI expanded to 8 checks** — jukeboxes (check 6), licence (check 7), and plans export (check 8); all 8 run by default in `-n` mode.
- **CLI volume CSV gains health columns** — Last Used, Use Count, Error Count.
- **CLI report JSON extended** — `jukeboxes`, `licenceResources`, `volumeTotalErrors`, `licenceAlertCount`, `licenceWarnCount` in report output.

## Completed — v1.2
- **Plans section** (P5Window) — disclosure section listing configured Archive, Backup, and Sync plans.
- **Export menu expansion** (P5Window) — plan markdown exports now include All Plans, Archive Plans, Backup Plans, and Sync Plans; job CSV exports now include All Job Results in addition to Error/Warning.
- **Archive plan cleanup** — archive plans no longer display empty Source/Target/Schedule fields in app export output.
- **CLI plan markdown exports** — added All Plans, Archive Plans, Backup Plans, and Sync Plans markdown outputs.
- **CLI all-job-results CSV export** — merged/deduplicated warning+error job export added.
- **CLI report JSON plan data** — added `checksRun.plans`, plan summary counts, and `plans` array.
- **CLI config auto-detect alignment** — default config lookup now checks `P5Servers.json` and `P5HealthCheckServers.json` in `/Users/Shared` and `~/Documents`, matching app behavior.
- **Sync plan loading hardening (build 8)** — synchronize plans now handle endpoint/payload variations and partial failures without showing false `No plans` states.

## Completed — v1.3
- **Menu bar server-list overflow fix** — multi-server cards are now scrollable when server count is greater than 3.
- **Menu bar report layout toggle** — for server counts greater than 3, users can switch `Server Reports` between `Detailed` and compact `Grid` (3-per-row) modes.
- **Server editor prefill bug fix** — editing an existing server now opens pre-populated in both app settings UIs (no add/close workaround required).
- **Duplicate server action** — added duplicate button in both app settings UIs; duplicate clones server fields and copies Keychain password when available.
- **Menu bar control simplification** — removed selected-server picker and selected refresh action from menu bar UI; retained `Refresh All`.
- **Volumes section UX update (window app)** — Volumes converted to disclosure group with closed-state total and mode status pills in header.

## Planned — Near Term
- **Licence maintenance/renewal date** — expose maintenance expiry date in the menu bar popover and window app once the P5 REST API surfaces this field. (TODO placeholder already in both views.)
- **Per-volume status flags** — surface suspect/quarantine volume state from P5 API alongside error counts.
- **Volume → Jobs linkage** — correlate which volumes are blocking active archive/backup jobs (restore media requests, missing appendable media).
- **isonline / dateexpires / usetime fields** — decode and display licence `isonline`, `dateexpires`, and `usetime` fields when available.
- **Filter controls** — filter volume list by mode, usage type, or label prefix in the window app.

## Planned — Longer Term
- Server groups and quick filter tags.
- Export profiles (JSON, custom CSV column templates).
- Scheduled background refresh notifications (macOS UserNotifications).
- Multi-server dashboard view (side-by-side comparison).
- Integration hooks (Slack webhook / email on alert conditions).
- Report templates and saved health check snapshots.
- Device inventory action and status.
- Add per-server tags/labels for environment grouping (e.g. Production / DR / Staging).
