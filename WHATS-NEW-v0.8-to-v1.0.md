# What's New — P5 Health Check (latest highlights)

## v1.4 Highlights

### Release
- **Version:** `1.4`
- **Date:** `2026-02-27`

### Uptime Check Scheduling Added
- Added dedicated uptime/connectivity interval controls in both app settings.
- Presets: `15 min`, `1 hour`, `1 day`, plus `Custom`.
- Custom uptime interval supports up to `1440` minutes.

### Scheduler UX Clarified (Menu Bar Settings)
- Scheduler labels now clearly separate:
  - `1) Refresh all info via API`
  - `2) Check uptime`
- Settings window dimensions were increased so scheduler controls fit cleanly.

### Menu Bar Status Readout Refinement
- Compact status line now uses:
  - `P5 Up/Down - LTO ●`
- Only `Up/Down` is colour-coded; `LTO` state is indicated by end-of-line dot colour.
- Removed `Clean/Not Clean` text from that compact row to reduce crowding.

### Stability & Build Fixes
- Fixed SwiftUI publish-cycle warnings in monitor refresh paths (`Publishing changes from within view updates...`).
- Fixed menu bar settings compile/scope issue around `MenuBarSettingsWindow`.

---

## v1.3 Highlights

A concise summary of the v1.3 release updates for the Mac apps.

---

## Release
- **Version:** `1.3`
- **Date:** `2026-02-25`

---

## Highlights

### Menu Bar Multi-Server Layout Modes
- For more than 3 servers, `P5MenuBar` now supports two report layouts:
  - `Detailed` (stacked full cards)
  - `Grid` (compact 3-per-row cards)
- Scroll appears only when the selected layout exceeds available popover height.

### Server Edit Prefill Bug Fixed
- Editing an existing server in either app now opens with fields pre-populated every time.
- Removed the prior add/close workaround requirement.

### Duplicate Server Action (Both Apps)
- Added `Duplicate` server action in settings/server controls for `P5Window` and `P5MenuBar`.
- Useful for quickly cloning an entry and changing only IP, port, or credentials.
- Duplicate preserves key server fields and copies saved Keychain password when available.

### Menu Bar Refresh Workflow Simplified
- Removed selected-server picker and `Refresh Selected` action from the menu bar UI.
- Menu bar now uses `Refresh All` only, keeping controls simpler and consistent with compact monitoring use.

### Volumes Disclosure Improvements (P5Window)
- `Volumes` is now a disclosure section with a richer header.
- Closed-state header shows total volume count and coloured mode pills (Appendable/Readonly/Full), matching other grouped sections.

---

## Documentation Updates in v1.3
- Updated changelog with v1.3 issue/fix breakdown.
- Updated menu bar and window user guides for new controls and section behaviour.
- Updated overview/readme docs, roadmap, and UI/API flow notes for v1.3 UI changes.
