# P5 Health Check 1.15 (Build 15)

Released 2026-10-28 for P5Window and P5MenuBar. The iPhone app stays at 1.2.1 (3) and is not part of this release.

## Last-known inventory for an unreachable server

- Licence resources, configured plans, volumes, and jukeboxes are now cached to disk after every successful full refresh and restored on launch.
- A server that's currently unreachable — or hasn't answered yet this session — shows that last-known inventory in Media & Drives, Plans, and Licenses instead of nothing, labelled **Showing inventory as of …** above the section. The notice clears the moment a live refresh for that server succeeds.
- Jobs and drive state are deliberately excluded from this cache: they change too often for a stale value to be anything but misleading, so those stay live-only exactly as before.

## Requirements and testing

Both DMGs contain universal Apple silicon and Intel apps, signed with a Developer ID, notarized and stapled. The window app needs macOS 13.5 or later; the menu bar app needs macOS 14 or later. <!-- claim-check: allow -->

Core, dependency, REST-probe, TLS-loopback, documentation, and Debug/Release build gates passed. Live-P5 GUI acceptance and real-site operator confirmation remain separate from automated release verification.
