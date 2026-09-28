# P5 Health Check 1.9.0 (Build 8)

Released 2026-09-28 for P5Window and P5MenuBar. The iPhone app stays at 1.2.1 (3) and is not part of this release.

## Live monitor

- **Running jobs only, by default.** Queued and pending jobs are hidden unless you turn on **Show queued jobs** (window Monitor toolbar, both Settings windows). The choice is remembered between launches, and a "N queued hidden" note shows how many are left out while it is off.
- **Status header.** The window shows Drives, P5 Server, Uptime, and Running jobs tiles above the tabs, with the server info line beneath.
- **Traffic-light colours**, shared by the window and menu bar: drives clean green, cleaning needed orange, unknown red; uptime under 24 hours green, 1 to 7 days orange, over 7 days red; server reachable green, slow orange, unreachable red.
- **All Servers** shows one coloured row per server; click a row to select that server.

## Help

The in-app Help and What's New were updated to describe the running/queued jobs behaviour and the status colours.

## Requirements and testing

Both DMGs contain universal Apple silicon and Intel apps, signed with a Developer ID, notarized and stapled. The window app needs macOS 13.5 or later, the menu bar app macOS 14 or later.

Automated core tests pass. Testing against a live P5 server, with saved Keychain items, and on the oldest supported macOS is still to be done, so treat this as a build to try on servers you can afford to watch, and tell us what you find.

Passwords remain outside JSON files and are stored in the macOS Keychain.
