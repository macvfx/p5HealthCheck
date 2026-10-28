# P5 Health Check 1.14 (Build 14)

Released 2026-10-28 for P5Window and P5MenuBar. The iPhone app stays at 1.2.1 (3) and is not part of this release. This release folds in the changes from the 1.12 and 1.13 test builds, which were not separately published.

## Demo Mode

- Add Server on both Mac apps now offers a **Demo Mode** toggle: answer from a built-in scenario — Healthy Fleet, Drive Needs Cleaning, Busy Archive Week, or Index Discovery — instead of a real P5 install, with no host, credentials, or network connection needed.
- Covers jobs, drives, Archive LTO, licence resources, and archive plans, so the same views behave the same as against a real server. The editor suggests a name, with a shuffle button for another.
- Separate from, and not a replacement for, the iPhone app's own demo mode used for App Store review.

## Menu bar Help

- The menu bar app's popover gains a Help button next to Settings, showing the same guide as the window app's Help menu. The menu bar app previously had no in-app help at all.

## Corrected removal candidates

- **Removal Candidates** (renamed from Loaded to Remove) now means Full or Read Only Archive LTO currently **In Drive** (an exact Location-to-device match) or **In Jukebox**. Read Only candidates are Ready to Remove; Full candidates are Mark Read Only First. Offline tapes are excluded; incomplete evidence stays Unknown rather than being guessed.
- Archive LTO CSV exports include Placement and Removal Readiness columns.
- Successful exports show a brief non-blocking confirmation instead of a modal OK dialog. Export failures still open an alert.

## Requirements and testing

Both DMGs contain universal Apple silicon and Intel apps, signed with a Developer ID, notarized and stapled. The window app needs macOS 13.5 or later; the menu bar app needs macOS 14 or later. <!-- claim-check: allow -->

Core, dependency, REST-probe, TLS-loopback, documentation, and Debug/Release build gates passed. Live-P5 GUI acceptance and real-site operator confirmation remain separate from automated release verification.
