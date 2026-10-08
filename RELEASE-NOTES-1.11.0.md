# P5 Health Check 1.11.0 (Build 11)

Released 2026-10-08 for P5Window and P5MenuBar. The iPhone app stays at 1.2.1 (3) and is not part of this release.

## Archive LTO inventory

- One permanent Archive LTO card replaces the former outer Volumes disclosure and duplicate legacy blocks.
- All, Appendable, Full, Read Only, and Loaded to Remove pills show counts and filter individual Archive + TAPE rows.
- Rows show P5 evidence for barcode/label, mode, online/enabled state, location, capacity, last use, and jukebox membership when available.
- Loaded to Remove identifies Full or Read Only media that P5 reports as loaded. It is a review list for operators, not an automated eject action.
- A visible Partial marker warns when volume detail or jukebox membership coverage is incomplete.

## Operator exports

The window app can export:

- the current Archive LTO filter;
- Full or Read Only archive removal candidates; and
- the remaining appendable archive inventory.

Exports are sorted and CSV escaped. The UI and exports are read-only: this release does not change P5 volume modes.

## Cleaning tapes per server/site

Cleaning cartridge identity, current cycle baseline, rated maximum, and retired state now belong to the selected P5 server/site. A cartridge entered for one facility no longer appears on unrelated servers. Existing data is migrated conservatively and is only attached where matching cleaning history proves use.

## Requirements and testing

All three DMGs contain universal Apple silicon and Intel apps, signed with a Developer ID, notarized and stapled. The window app needs macOS 13.5 or later; the menu bar app needs macOS 14 or later. <!-- claim-check: allow -->

Core, dependency, REST-probe, TLS-loopback, documentation, and Debug/Release build gates passed. Live-P5 GUI acceptance and real-site operator confirmation remain separate from automated release verification.
