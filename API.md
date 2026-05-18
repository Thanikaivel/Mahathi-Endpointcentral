# UAM API Reference

All endpoints are mounted under `/api`. The dashboard endpoints are
read-only. The ingest endpoint requires the `X-Agent-Key` header.

## Health

`GET /api/health` → `{ ok, db, time }`

## Ingest (agent → server)

`POST /api/ingest`
Headers: `X-Agent-Key: <shared key>` and `Content-Type: application/json`.

Idempotent on `batch.clientBatchId`: re-sending the same batch returns
`{ ok: true, duplicate: true }` and the agent should delete its local
JSON.

Request body:

```jsonc
{
  "machine": {
    "machineName": "PC-001",
    "domain": "CORP",
    "osVersion": "Windows 11 Pro 23H2 (10.0.22631)",
    "ipAddress": "10.0.0.10",
    "agentVersion": "1.0.0"
  },
  "batch": {
    "clientBatchId": "uuid-v4",
    "generatedAtUtc": "2026-05-05T10:30:00.000Z",
    "events": [
      {
        "clientEventId": "uuid-v4",
        "eventType": "Logon",
        "eventTimeUtc": "2026-05-05T09:00:00Z",
        "userName": "alice",
        "domain": "CORP",
        "details": "User CORP\\alice logged on"
      }
    ],
    "sessions": [
      {
        "clientSessionId": "uuid-v4",
        "userName": "alice",
        "domain": "CORP",
        "logonTimeUtc": "2026-05-05T09:00:00Z",
        "logoffTimeUtc": null,
        "idleSeconds": 120,
        "activeSeconds": 5280,
        "lockCount": 1,
        "endReason": null
      }
    ],
    "appUsages": [
      {
        "clientSessionId": "uuid-v4-of-session",
        "userName": "alice",
        "domain": "CORP",
        "appName": "chrome",
        "appPath": "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
        "windowTitleSample": "Inbox - alice@corp.com",
        "firstSeenUtc": "2026-05-05T09:01:00Z",
        "lastSeenUtc":  "2026-05-05T10:29:45Z",
        "foregroundSeconds": 1320,
        "runningSeconds": 4500,
        "launchCount": 1
      }
    ]
  }
}
```

Response:

```json
{ "ok": true, "duplicate": false,
  "eventsAccepted": 1, "sessionsAccepted": 1, "appUsagesAccepted": 1 }
```

## Dashboard (server → frontend)

| Method | Path                                          | Description                                |
|-------:|------------------------------------------------|--------------------------------------------|
| GET    | `/api/dashboard/overview`                      | Stat cards + active sessions + recent machines |
| GET    | `/api/dashboard/machines?search=...`           | Machine list                               |
| GET    | `/api/dashboard/machines/:id`                  | Machine detail + recent events + top apps  |
| GET    | `/api/dashboard/machines/:id/sessions?limit=`  | Sessions for a machine                     |
| GET    | `/api/dashboard/users`                         | All users with totals                      |
| GET    | `/api/dashboard/sessions/:id`                  | Session detail (events + apps)             |
| GET    | `/api/dashboard/events?limit=&type=`           | Recent event stream                        |
| GET    | `/api/dashboard/apps/top?days=`                | Top apps by foreground time                |
| GET    | `/api/dashboard/reports/daily?days=`           | Per-day machine summary                    |
