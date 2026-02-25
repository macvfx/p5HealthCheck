# P5 Health Check — UI Flow & REST API Mapping

Maps every user-visible action in P5 Health Check (v1.3) to the underlying P5 REST API calls, then lists untapped endpoints from `P5_openapi.json` (API v7.1.0+) and the tested calls in `P5 rest API example.json` that are not yet implemented.

Base URL: `http(s)://{host}:{port}/rest/{apiVersion}/`
Auth: HTTP Basic (username + password from Keychain)

---

## Part 1 — Current UI Actions → REST API Calls

All calls are initiated by `HealthMonitor.fetchSnapshot()` via `P5APIClient.request()`.
Every request is `GET` with `Accept: application/json`. Additional filter parameters are passed as HTTP request headers.

### Refresh Selected / Refresh All
Both buttons trigger `HealthMonitor.refresh()` or `HealthMonitor.refreshAll()`.
Each server fetch runs these calls concurrently (`async let` for core data; non-fatal `try?` for jukeboxes and licence):

Note: in v1.3, `P5MenuBar` uses `Refresh All` only; `Refresh Selected` remains available in `P5Window`.

| UI Section Populated | REST Call | Headers | Source method |
|---|---|---|---|
| Server Info (hostname, version, platform, uptime) | `GET /general/srvinfo` | — | `fetchServerInfo()` |
| Devices — list of device IDs | `GET /general/devices` | — | `fetchDevices()` |
| Devices — cleaning status per device | `GET /general/devices/{deviceID}` | — | `fetchDevice()` |
| Jobs — warning job IDs | `GET /general/jobs` | `filter: warning`, `lastdays: N` | `fetchWarningJobs()` |
| Jobs — error job IDs | `GET /general/jobs` | `filter: failed`, `lastdays: N` | `fetchErrorJobs()` |
| Jobs — detail per warning/error job | `GET /general/jobs/{jobID}` | — | `fetchJob()` |
| Jobs — protocol text per job | `GET /general/jobs/{jobID}/protocol` | `format: json` | `fetchJobProtocolSummary()` |
| Volumes — volume ID list | `GET /general/volumes` | — | `fetchVolumes()` |
| Volumes — detail per volume (incl. tape health fields) | `GET /general/volumes/{volumeID}` | — | `fetchVolume()` |
| Jukeboxes — library IDs | `GET /general/jukeboxes` | — | `fetchJukeboxes()` |
| Jukeboxes — slot count per library | `GET /general/jukeboxes/{jukeboxID}` | — | `fetchJukebox()` |
| Jukeboxes — volumes loaded per library | `GET /general/jukeboxes/{jukeboxID}/volumes` | — | `fetchJukebox()` |
| Licence — resource type IDs | `GET /license/resources` | — | `fetchLicenceResources()` |
| Licence — free count per resource | `GET /license/resources/{resourceID}` | — | `fetchLicenceResource()` |
| Plans — archive plan IDs/details | `GET /archive/plans`, `GET /archive/plans/{planID}` | — | `fetchArchivePlans()` |
| Plans — backup plan IDs/details/tasks/events | `GET /backup/plans`, `GET /backup/plans/{planID}`, `GET /backup/plans/{planID}/tasks/`, `GET /backup/plans/{planID}/tasks/{taskID}`, `GET /backup/plans/{planID}/events/`, `GET /backup/plans/{planID}/events/{eventID}` | — | `fetchBackupPlans()` |
| Plans — sync plan IDs/details/events | `GET /synchronize/plans`, `GET /synchronize/plans/{planID}`, `GET /synchronize/plans/{planID}/events`, `GET /synchronize/plans/{planID}/events/{eventID}` | — | `fetchSyncPlans()` |

Sync plan fetching is fault-tolerant in build 8: if one synchronize plan or event request fails, other sync plans are still shown.

**Settings that affect calls:**
- `Warning job lookback (days)` → sets the `lastdays` header value (0 = omit header, returns all)
- `Max volume details` → caps how many volume IDs are fetched with individual `GET /general/volumes/{id}` calls

### Auto Refresh (Scheduled)
Runs `HealthMonitor.refreshAll()` automatically on a timer.
Same API calls as Refresh All. A SQLite scheduler lease prevents concurrent refreshes across app restarts.

| Schedule mode | Behaviour |
|---|---|
| Manual | Timer disabled; only manual refresh buttons trigger calls |
| Hourly | Fires every N hours |
| Daily | Fires at configured HH:MM |

### Export Menu
**No new API call** — uses cached data already fetched by Refresh.

- Volume CSV export:
  - `All Volumes`
  - `Archive Tape Usage`
  - `Backup Tape Usage`
- Plan markdown export:
  - `All Plans`
  - `Archive Plans`
  - `Backup Plans`
  - `Sync Plans`
  - Archive plan markdown intentionally omits Source/Target/Schedule rows when those fields are not applicable.
- Job CSV export:
  - `All Job Results`
  - `Error Job Results`
  - `Warning Job Results`
  - `All Job Results` merges warning + error jobs and de-duplicates by `jobID`.

### Add / Edit / Delete Server (sidebar)
**No API call** — operates only on local `HealthSettings` (UserDefaults + Keychain).

### Import Servers JSON / Export Servers JSON (sidebar)
**No API call** — reads/writes a local JSON file (`P5Servers.json`).

### Settings sheet (Data Fetch / Auto Refresh / History)
**No API call** — updates local `HealthSettings` stored in UserDefaults.

---

## Part 2 — Tested Calls in `P5 rest API example.json` Not Yet Implemented

These endpoints were confirmed working against a real P5 server during early development.

> **✅ Implemented in v1.0 (build 1):** Jukeboxes (`GET /general/jukeboxes`, `/{id}`, `/{id}/volumes`), Licence resources (`GET /license/resources`, `/{id}`), and all volume tape-health fields (`dateused`, `usecount`, `hardWrErCnt`, `softWrErCnt`, `hardRdErCnt`, `softRdErCnt`) are now fully decoded and displayed.

The following confirmed-working calls remain unimplemented:

### Volume → Jobs
| Call | Response fields | Notes |
|---|---|---|
| `GET /general/volumes/{volumeID}/jobs` | `jobs[].ID` | Jobs that wrote to this specific volume |

### Volumes — additional decoded fields not yet displayed
`GET /general/volumes/{volumeID}` decodes most fields, but these are fetched and not yet surfaced in the UI:

| Field | Type | Example value | Notes |
|---|---|---|---|
| `isonline` | bool | `true` | Whether volume is currently accessible |
| `dateexpires` | string | `Not a scheduled job` | Expiry date or policy string |
| `usetime` | int | `90073` | Cumulative seconds the tape has been in the drive |

### Filters
| Call | Response fields | Notes |
|---|---|---|
| `GET /general/filters` | `filters[].ID` | Lists archive/backup filter IDs |
| `GET /general/filters/{filterID}` | `description`, `enabled`, `include`, `exclude`, `extendedinclude`, `extendedexclude` | Filter rules detail |

---

## Part 3 — Additional Endpoints from `P5_openapi.json` (v7.1.0+)

Full endpoint inventory from the OpenAPI spec, grouped by feature area, with suggested UI additions for P5 Health Check.

### 3.1 General — Pools

| Endpoint | Summary | Potential UI use |
|---|---|---|
| `GET /general/pools` | List all media pools | Show pool names alongside volume summary |
| `GET /general/pools/{poolID}` | Pool detail | Pool capacity / policy info |
| `GET /general/pools/{poolID}/volumes` | Volumes in pool | Filter volume list by pool |

### 3.2 General — Clients

| Endpoint | Summary | Potential UI use |
|---|---|---|
| `GET /general/clients` | List all clients | Client inventory panel |
| `GET /general/clients/{clientID}` | Client detail | Per-client connectivity status |
| `POST /general/clients/{clientID}` | Ping client | Live connectivity test button |

### 3.3 General — Jobs (additional)

| Endpoint | Summary | Potential UI use |
|---|---|---|
| `GET /general/jobs/{jobID}/report` | Report of currently running job | Live progress for active jobs |
| `GET /general/jobs/{jobID}/inventory` | Files saved by job | Drill-down file list per job |
| `DELETE /general/jobs/{jobID}` | Cancel/remove scheduled job | Stop job button (requires POST support) |

### 3.4 General — Devices (additional)

| Endpoint | Summary | Potential UI use |
|---|---|---|
| `POST /general/devices/{deviceID}` | Inventory operation on device | Trigger drive inventory |

### 3.5 General — Jukeboxes (additional, beyond tested calls)

| Endpoint | Summary | Potential UI use |
|---|---|---|
| `POST /general/jukeboxes/{jukeboxID}` | Start inventory or label job | Jukebox inventory trigger |

### 3.6 Archive

| Endpoint | Summary | Potential UI use |
|---|---|---|
| `GET /archive/overview` | Archive state overview | Summary stats (total archived size, plan count) |
| `GET /archive/plans` | List archive plans | Archive plan health panel |
| `GET /archive/plans/{planID}` | Plan detail | Per-plan status, last run, next run |
| `GET /archive/indexes` | List archive indexes | Index inventory count |

### 3.7 Backup

| Endpoint | Summary | Potential UI use |
|---|---|---|
| `GET /backup/overview` | Backup state overview | Summary stats (total backup size, plan count) |
| `GET /backup/plans` | List backup plans | Backup plan health panel |
| `GET /backup/plans/{planID}` | Plan detail | Per-plan status, last run, next run |
| `GET /backup/plans/{planID}/tasks/` | Backup tasks | Task list per plan |

### 3.8 Synchronize

| Endpoint | Summary | Potential UI use |
|---|---|---|
| `GET /synchronize/overview` | Sync state overview | Sync plan summary |
| `GET /synchronize/plans` | List sync plans | Sync plan health panel |
| `GET /synchronize/plans/{planID}` | Plan detail | Per-plan status |

### 3.9 License

| Endpoint | Summary | Status |
|---|---|---|
| `GET /license/resources` | List resource types | ✅ Implemented (v1.0 build 1) |
| `GET /license/resources/{resourceID}` | Free licence count | ✅ Implemented (v1.0 build 1) |

> **Future:** Maintenance/renewal date — not currently exposed by this endpoint. When available, add to both the window app Licence section and the menu bar popover (see `// TODO` comment in `StatusPopoverView.swift`).

---

## Part 4 — Suggested Next Features (Prioritised)

Based on the tested calls and OpenAPI spec, these additions would add the most value for a health-check tool, roughly in order of effort vs. impact.

> **✅ Completed in v1.0 (build 1):** Jukebox panel, Licence status panel, Volume health columns (Last Used, Use Count, Error Count) in UI and CSV.

### High value / medium effort

1. **Plan run-health enrichment** — `GET /archive/overview` + `GET /backup/overview` + `GET /synchronize/overview`
   Extend the existing Plans section with last-run/next-run and aggregate run-health signals so operators can quickly identify stalled schedules.

2. **Pool panel** — `GET /general/pools` + `GET /general/pools/{id}` + `GET /general/pools/{id}/volumes`
   Show pool names with volume counts and capacity — useful when tapes span multiple pools or pool capacity is a concern.

3. **Licence maintenance/renewal date** — currently not exposed by `GET /license/resources/{id}`.
   When the P5 API surfaces this field, add it to the Licence section (window app) and the menu bar popover. See `// TODO` in `StatusPopoverView.swift`.

### Medium value / medium effort

4. **Active job progress** — `GET /general/jobs/{id}/report`
   Poll for currently running jobs and show live progress. Requires a separate polling loop distinct from the snapshot refresh.

5. **Volume → Jobs drill-down** — `GET /general/volumes/{volumeID}/jobs`
   Show which jobs wrote to a selected tape — useful for tracing when a tape was last used and by what plan.

6. **Additional volume fields** — `isonline`, `dateexpires`, `usetime` already fetched but not displayed.
   `isonline` could flag offline/vaulted tapes; `dateexpires` useful for retention policy review; `usetime` for drive wear analysis.

### Lower priority / read-only monitoring scope

7. **Client list** — `GET /general/clients`
   Show configured clients and connectivity (via `POST /general/clients/{id}` ping).

8. **Backup2Go overview** — `GET /backup2go/overview`
   Quick workstation backup status if Backup2Go is in use.

9. **Filter inventory** — `GET /general/filters` + `GET /general/filters/{id}`
   Show configured archive/backup filter rules — low monitoring value but useful for audit/documentation.

---

## Appendix — API Authentication & URL Construction

```
Base URL:  {scheme}://{host}:{port}/rest/{apiVersion}/
Scheme:    http or https (controlled by ServerConfig.useHTTPS)
Auth:      Authorization: Basic base64("{username}:{password}")
Accept:    application/json
```

`P5APIClient.request(path:headers:)` builds the URL from `ServerConfig.baseURL` and appends the path. Additional filter/format parameters are passed as standard HTTP headers (not query parameters), consistent with the P5 API convention.

---

*Document based on P5 Health Check v1.3 and P5 REST API v7.1.0+*
*Source files: `P5_openapi.json`, `P5 rest API example.json`*
