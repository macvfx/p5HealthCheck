# What's New — P5 Health Check v1.3

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
