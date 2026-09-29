# P5 Health Check 1.9.1 (Build 9)

Released 2026-09-28 for P5Window and P5MenuBar. The iPhone app stays at 1.2.1 (3) and is not part of this release.

This release replaces 1.9.0, which is withdrawn: it shipped with the refresh-lock bug fixed below, so an app quit or crash could lock the other app out of Refresh All for up to 15 minutes. 1.9.1 includes everything 1.9.0 added, plus the fix, and is the first build to actually use it comfortably with both apps open.

## Live monitor

- **Running jobs only, by default.** Queued and pending jobs are hidden unless you turn on **Show queued jobs** (window Monitor toolbar, both Settings windows). The choice is remembered between launches, and a "N queued hidden" note shows how many are left out while it is off.
- **Status header.** The window shows Drives, P5 Server, Uptime, and Running jobs tiles above the tabs, with the server info line beneath.
- **Traffic-light colours**, shared by the window and menu bar: drives clean green, cleaning needed orange, unknown red; uptime under 24 hours green, 1 to 7 days orange, over 7 days red; server reachable green, slow orange, unreachable red.
- **All Servers** shows one coloured row per server; click a row to select that server.

## Fixed: a stuck refresh lock

- **A stuck refresh lock.** Both Mac apps share a lock that stops them refreshing the same P5 server at once. If an app quit or crashed while it held that lock, the other app could show "Another P5 Health Check instance is already refreshing" for up to 15 minutes. Quitting now releases the lock right away; a lock left behind by a crash or force-quit now clears itself within about a minute instead of fifteen.
- This only ever affected the full inventory refresh (Refresh All, and the automatic inventory schedule) that both apps share. The Monitor tab's live jobs and Recent Archives polling was never gated by this lock and was unaffected either way.

## Help

The in-app Help and What's New were updated to describe the running/queued jobs behaviour and the status colours.

## Requirements and testing

Both DMGs contain universal Apple silicon and Intel apps, signed with a Developer ID, notarized and stapled. The window app needs macOS 13.5 or later, the menu bar app macOS 14 or later. <!-- claim-check: allow -->

Automated core tests pass, including two new regressions for the refresh-lock fix. Testing against a live P5 server, with saved Keychain items, and on the oldest supported macOS is still to be done, so treat this as a build to try on servers you can afford to watch, and tell us what you find.

Passwords remain outside JSON files and are stored in the macOS Keychain.
