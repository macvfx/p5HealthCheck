# What's New — P5 Health Check v1.2

A concise summary of the v1.2 release updates for the apps and CLI.

---

## Release
- **Version:** `1.2`
- **Build:** `7`
- **Date:** `2026-02-24`

---

## Highlights

### Plans Visibility (P5Window)
- Added a dedicated **Plans** disclosure section in the main dashboard.
- Displays configured **Archive**, **Backup**, and **Sync** plans returned by the P5 API.
- Shows grouped counts and plan detail rows directly in the UI.

### Export Menu Expansion (P5Window)
- Export menu now includes plan markdown exports:
  - `All Plans`
  - `Archive Plans`
  - `Backup Plans`
  - `Sync Plans`
- Export menu now includes job CSV exports:
  - `All Job Results`
  - `Error Job Results`
  - `Warning Job Results`

### Archive Plan Output Cleanup
- Archive plans no longer show empty **Source**, **Target**, or **Schedule** rows in UI export output.
- Plan markdown export now keeps archive entries concise and relevant.

---

## CLI (`p5_health_check.sh`) Updates

### New Exports
- Added plan markdown exports:
  - `<alias>-<timestamp>-all-plans.md`
  - `<alias>-<timestamp>-archive-plans.md`
  - `<alias>-<timestamp>-backup-plans.md`
  - `<alias>-<timestamp>-sync-plans.md`
- Added merged job export:
  - `<alias>-<timestamp>-all-job-results.csv`

### Check Set Expansion
- CLI now runs **8 checks** in non-interactive mode (`-n`), including plans export.

### Report JSON Additions
- `checksRun.plans`
- `summary.planTotalCount`
- `summary.archivePlanCount`
- `summary.backupPlanCount`
- `summary.syncPlanCount`
- `plans` array in report output

### Config Auto-Detection Alignment
- CLI default config detection now matches app behavior:
  1. `/Users/Shared/P5Servers.json`
  2. `/Users/Shared/P5HealthCheckServers.json`
  3. `~/Documents/P5Servers.json`
  4. `~/Documents/P5HealthCheckServers.json`

---

## Documentation Updates in v1.2
- Updated CLI guide with 8-check flow and new export outputs.
- Updated P5Window guide with Plans section and export flow details.
- Updated roadmap and UI/API flow docs to reflect shipped v1.2 functionality.
