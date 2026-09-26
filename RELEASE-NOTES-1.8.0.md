# P5 Health Check 1.8.0 (Build 7)

Released 2026-09-24 for P5Window and P5MenuBar. The iPhone app stays at 1.2.1 (3) and is not part of this release.

## Live monitor

- **Choose the live-monitor cadence:** 30 seconds, 1 minute, 5 minutes or 10 minutes. The setting is shared by both Mac apps, and every cadence label reads from it.
- **A steadier menu-bar status.** The menu-bar label now shows one stable summary: cleaning takes precedence, an incomplete or stale observation stays *unavailable*, and an unchanged summary is not redrawn.
- **Active and Recent Archives tabs.** Recent Archives is a read-only request to P5's archive overview and lists finished archive outcomes with client, plan, pool, size, time and the archived paths. It is an on-demand overview, **not durable job history**: it does not cover restores or backups, has no P5 job ID, and Health Check does not keep it.

## The window app

- Native **Settings**, **Help** and **What's New** windows, an in-app guide, and the real version and build in a footer.
- Refreshed dashboard cards and summary-first **Media & Drives**, **Plans**, **History** and **Licenses** layouts. Licences have their own tab.
- HTTPS locks beside server names in the sidebar, title and monitor cards. A lock shows that HTTPS is configured, not that a connection succeeded.

## Fixed

- An empty active-job list (P5 answers `{}`) is accepted instead of raising a false connection or decode error over HTTP and HTTPS.
- **Refresh All** shows each server's result as soon as it arrives. One slow or unreachable server no longer holds back the others, including the one on screen, for its whole timeout.
- The Add/Edit Server sheet no longer risks crashing on macOS 13.5 to 15.

## Requirements and testing

Both DMGs contain universal Apple silicon and Intel apps, signed with a Developer ID, notarized and stapled. The window app needs macOS 13.5 or later.

Automated core and loopback TLS tests pass. Testing against a live P5 server, with saved Keychain items, and on the oldest supported macOS is still to be done, so treat this as a build to try on servers you can afford to watch, and tell us what you find.

Passwords remain outside JSON files and are stored in the macOS Keychain.
