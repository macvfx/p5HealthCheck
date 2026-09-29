# P5 Health Check 1.10.0 (Build 10)

Released 2026-09-29 for P5Window and P5MenuBar. The iPhone app stays at 1.2.1 (3) and is not part of this release.

## Drive cleaning log

LTO cleaning cartridges wear out, and P5 only tells us whether a drive needs cleaning: no count, date, drive generation or location. Media & Drives now keeps that record.

- **Flag history.** Every change to a drive's needs-cleaning flag is recorded while the app polls. A drive first seen already flagged is stored as a starting point and not counted as a new flag.
- **Log Cleaning.** Record the drive, date and time, cleaning tape and notes. The outcome is not typed in: it is read from the flag afterwards (cleared, still flagged, drive was not flagged, or unknown).
- **Was the drive cleaned?** When a flag clears and no cleaning was logged, the log asks. Log the cleaning, or mark it not cleaned if it cleared by itself.
- **Per-drive totals and labels.** Flagged and cleaned counts, last cleaned, and an optional label such as "LTO-8, rack 2", because P5 reports only a device ID.
- **Cleaning tapes.** Uses are counted per barcode across all servers; a tape without a barcode can be given a label. The rated life defaults to 50 uses and can be changed per tape; tapes warn from 80% and can be retired.
- **Frequent-cleaning warning.** A drive flagged 3 times in 14 days gets a banner, a badge and an export entry. Both numbers are settings.
- **Charts and export.** Flags and cleanings per month, a per-drive timeline, and a plain-text receipt or CSV for a chosen period and drive.

Counts cover only the time the app was watching, and a cleaning that was not logged cannot be counted. Cleaning records are kept regardless of the history retention setting. The shared database moves to a newer schema on first launch; existing data is not altered.

## Menu bar and uptime colours

- The menu bar shows each server's uptime in colour, and the app version in the footer.
- A new window-app setting (off by default) opens the menu bar app when the window app quits, unless the Mac is logging out, restarting or shutting down.
- **Uptime colours changed** in both apps: green up to 24 hours, orange up to 48 hours, red beyond 48 hours. Previously orange ran to 7 days.

## Fixed

- A failed refresh now names the server and is shown only for that server, instead of a nameless red banner on every workspace.
- The Auto Refresh row in the Settings sheet wraps instead of being cut off.

## Requirements and testing

Both DMGs contain universal Apple silicon and Intel apps, signed with a Developer ID, notarized and stapled. The window app needs macOS 13.5 or later, the menu bar app macOS 14 or later. <!-- claim-check: allow -->

Automated core tests pass. The cleaning log has not yet been exercised against a live P5 server with a real drive-cleaning event, so the log starts empty; treat this as a build to try on servers you can watch, and tell us what you find.
