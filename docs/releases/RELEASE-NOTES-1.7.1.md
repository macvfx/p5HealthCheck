# P5 Health Check 1.7.1 (Build 3)

Released 2026-08-10 for P5Window and P5MenuBar.

## Reviewed server discovery

- Standard and legacy server JSON files are detected without silently changing the saved server list.
- A review sheet shows the source and connection details before anything is added.
- Choose **Add New Servers**, **Not Now**, or **Ignore This File Version**.
- Accepted and ignored file revisions are remembered by SHA-256 fingerprint, preventing repeated prompts and unwanted re-creation of deleted configurations.
- Connection identity uses host, port, username, API version, and HTTP/HTTPS mode. The editable alias is excluded, so a local alias change does not invalidate an imported connection.

Passwords remain outside JSON files and are stored separately in macOS Keychain.
