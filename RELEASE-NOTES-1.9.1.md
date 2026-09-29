# P5 Health Check 1.9.1 (Build 9)

Released 2026-09-28 for P5Window and P5MenuBar. The iPhone app stays at 1.2.1 (3) and is not part of this release.

## Fixed

- **A stuck refresh lock.** Both Mac apps share a lock that stops them refreshing the same P5 server at once. If an app quit or crashed while it held that lock, the other app could show "Another P5 Health Check instance is already refreshing" for up to 15 minutes. Quitting now releases the lock right away; a lock left behind by a crash or force-quit now clears itself within about a minute instead of fifteen.
- This only ever affected the full inventory refresh (Refresh All, and the automatic inventory schedule) that both apps share. The Monitor tab's live jobs and Recent Archives polling was never gated by this lock and was unaffected either way.

## Requirements and testing

Both DMGs contain universal Apple silicon and Intel apps, signed with a Developer ID, notarized and stapled. The window app needs macOS 13.5 or later, the menu bar app macOS 14 or later.

Automated core tests pass, including two new regressions for this fix. Testing against a live P5 server, with saved Keychain items, and on the oldest supported macOS is still to be done, so treat this as a build to try on servers you can afford to watch, and tell us what you find.

Passwords remain outside JSON files and are stored in the macOS Keychain.
