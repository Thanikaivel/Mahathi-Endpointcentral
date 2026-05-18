# User Activity Monitoring (UAM) System

End-to-end activity monitoring for ~300 Windows client machines reporting into a
central server. Tracks logon/logoff/lock/unlock/shutdown events, session
duration & idle time, and application usage (foreground & running).

```
+-------------------+  HTTPS/HTTP    +---------------------+    +------------------+
|  Windows Client   | -------------> |  Node.js Backend    | -> | MSSQL Server     |
|  (uam-agent.exe)  |   JSON batch   |  (Express on IIS)   |    | UserActivityDB   |
|  spool to JSON    |                |  /api/ingest        |    +------------------+
|  delete on 200 OK |                |  /api/dashboard/*   |             ^
+-------------------+                +---------------------+             |
                                                  ^                      |
                                                  | /api proxy           |
                                          +--------------+               |
                                          | React SPA    | --------------+
                                          | (IIS static) |
                                          +--------------+
```

## Repository layout

```
sql/                   T-SQL: create DB, schema, optional seed data
backend/               Node.js Express API (mssql), IIS web.config
frontend/              React + Vite dashboard, IIS web.config (with /api proxy)
client-agent/          Windows agent (Node.js + PowerShell probe + service installer)
```

## 1. Database setup

Open SQL Server Management Studio against `localhost` as `sa` / `C0nn3ct@123` and
run the scripts in order:

1. `sql/01_create_database.sql` — creates `UserActivityDB` if it doesn't exist.
2. `sql/02_schema.sql`         — creates tables, indexes, and dashboard views.
3. `sql/03_seed_optional.sql`  — optional demo rows.

Or via `sqlcmd`:

```cmd
sqlcmd -S localhost -U sa -P C0nn3ct@123 -i sql\01_create_database.sql
sqlcmd -S localhost -U sa -P C0nn3ct@123 -i sql\02_schema.sql
sqlcmd -S localhost -U sa -P C0nn3ct@123 -i sql\03_seed_optional.sql
```

## 2. Backend (Node.js + IIS)

### Install dependencies

```cmd
cd backend
npm install
```

### Local run

```cmd
copy .env.example .env
node src\server.js
```

The API will start on `http://localhost:5321`. Health check:
`GET http://localhost:5321/api/health`.

### Deploy on IIS (Windows Server 2022)

Prerequisites on the server:

1. **IIS** (Web Server role) with **URL Rewrite** module installed.
2. **iisnode** for IIS — https://github.com/Azure/iisnode/releases.
3. **Node.js LTS** installed and on PATH (so `node.exe` is callable).

Steps:

1. Copy the `backend` folder to e.g. `C:\inetpub\uam-backend`.
2. From an elevated CMD inside that folder:

   ```cmd
   npm install --production
   copy .env.example .env
   notepad .env  REM set DB_PASSWORD, AGENT_SHARED_KEY, CORS_ORIGINS
   ```

3. In IIS Manager, **Add Site**:
   - Site name: `uam-backend`
   - Physical path: `C:\inetpub\uam-backend`
   - Binding: `http`, port `5321`
4. Application pool: **No Managed Code**, identity `LocalSystem` (or a custom
   service account that can read the folder).
5. Browse `http://localhost:5321/api/health` — should return `{ ok: true, db: "up" }`.

Logs land in `iisnode-logs/` next to `web.config`.

## 3. Frontend (React)

```cmd
cd frontend
npm install
npm run dev          REM dev server on http://localhost:5173 (proxies /api -> :5321)
npm run build        REM produces dist/
```

### Deploy on IIS

1. Run `npm run build`.
2. Copy `frontend/dist/*` and `frontend/web.config` to e.g. `C:\inetpub\uam-frontend`.
3. Install the **Application Request Routing (ARR)** module on IIS and enable
   "Enable proxy" in **Server Farms / ARR** settings — required for the
   `/api/*` -> `http://localhost:5321` reverse proxy in `web.config`.
4. In IIS Manager, **Add Site**:
   - Site name: `uam-frontend`
   - Physical path: `C:\inetpub\uam-frontend`
   - Binding: `http`, port `80` (or `443` with a TLS cert).
5. Browse `http://<server>/` — you should see the dashboard.

## 4. Client Agent (Windows)

The agent runs as a **Windows Service** on each of the 300 machines. It writes
batches to `C:\ProgramData\UAMAgent\spool\*.json` and pushes them to the API
on a 60-second timer. Successful uploads delete the JSON; transient failures
keep it for retry. Idempotency is enforced by the server using
`ClientBatchId`, so retries are safe.

### Build a single-file `.exe` once on a dev box

```cmd
cd client-agent
npm install
npm install -g pkg
npm run build:exe
REM produces dist\uam-agent.exe (~50MB, includes Node runtime)
```

### Per-machine install (run on each client, elevated)

1. Copy these to `C:\Program Files\UAMAgent\`:
   - `uam-agent.exe` (built above)
   - `config.json` (edit `apiBaseUrl`, `agentKey` first)
2. From an elevated CMD in that folder:

   ```cmd
   sc create "UAM Activity Agent" binPath= "\"C:\Program Files\UAMAgent\uam-agent.exe\"" start= auto obj= LocalSystem
   sc description "UAM Activity Agent" "User Activity Monitoring Agent"
   sc start "UAM Activity Agent"
   ```

   Or, if you prefer running from source on a few test machines:

   ```cmd
   cd client-agent
   npm install
   node service\install-service.js     REM uses node-windows to register the service
   ```

3. Verify:
   - Service `UAM Activity Agent` is **Running** in `services.msc`.
   - `C:\ProgramData\UAMAgent\agent.log` shows polling activity.
   - The machine appears in the Dashboard within ~1 minute.

### Mass deployment options for 300 machines

- **GPO Software Installation** (MSI wrapper around `uam-agent.exe`).
- **Microsoft Intune** Win32 app deployment.
- **PsExec / PowerShell remoting** to copy + `sc create` in a loop.
- **SCCM/MECM** package.

For all options, the per-machine `config.json` should be templated with the
correct `apiBaseUrl` and a single shared `agentKey`.

## 5. Configuration reference

`client-agent/config.json` keys:

- `apiBaseUrl`             — e.g. `http://uam-server.corp.local:5321/api`.
- `agentKey`               — must match `AGENT_SHARED_KEY` in backend `.env`.
- `pollIntervalSeconds`    — how often to sample Windows state (default `5`).
- `syncIntervalSeconds`    — how often to flush spool & try API push (default `60`).
- `idleThresholdSeconds`   — input inactivity that counts as "idle" (default `120`).
- `spoolDir` / `logFile`   — local paths under `C:\ProgramData\UAMAgent\`.
- `trackForegroundApp`     — true/false. Always recommended.
- `trackRunningApps`       — true/false. Heavier; aggregates running app time.

## 6. End-to-end smoke test

1. Start backend: `cd backend && node src\server.js`.
2. Start frontend dev: `cd frontend && npm run dev`. Open `http://localhost:5173`.
3. Run the agent in foreground (no service) on a Windows box:

   ```cmd
   cd client-agent
   npm install
   notepad config.json     REM set apiBaseUrl=http://<dev-box>:5321/api and agentKey
   node src\index.js
   ```

4. Lock and unlock the workstation (Win+L), open a few apps, then wait ~60s.
5. The dashboard's **Overview** page should show your machine and an active
   session. **Events** should list `Logon`, `Lock`, `Unlock`. **Top Apps**
   should populate within a couple of minutes.

## 7. Troubleshooting

- **Backend can't connect to SQL** — confirm SQL Server has TCP enabled
  (`SQL Server Configuration Manager` -> Network Configuration -> TCP/IP -> Enable),
  check `DB_SERVER` and that the SQL Browser/named instance settings are correct.
- **CORS errors in dev** — make sure `CORS_ORIGINS` in `.env` includes
  `http://localhost:5173`.
- **`401 Unauthorized agent`** on ingest — `agentKey` mismatch between
  client `config.json` and backend `.env` `AGENT_SHARED_KEY`.
- **Agent not starting as service** — check the EventViewer Application log for
  `UAM Activity Agent` errors; verify `node-windows` was installed before
  running `install-service.js`.
- **Spool growing without uploads** — check `agent.log`; the agent keeps trying
  forever, so this usually means the API URL is wrong or the server is down.
- **`probe.ps1` fails** — confirm PowerShell ExecutionPolicy. The agent already
  passes `-ExecutionPolicy Bypass`, but Group Policy can still block it; in
  that case copy the script to a signed location.

## 8. Security notes

- **Always use HTTPS** in production. Front IIS with a TLS cert, set
  `apiBaseUrl` to `https://...` on the agent side.
- Rotate `AGENT_SHARED_KEY` when an agent install is decommissioned.
- The dashboard endpoints are currently unauthenticated — put them behind
  Windows Auth in IIS or add an auth middleware before exposing externally.
- Agent stores nothing sensitive locally beyond machine/user names. Spool
  files contain only metadata, never credentials.

## 9. Database schema overview

| Table             | Purpose                                                |
|-------------------|--------------------------------------------------------|
| `Machines`        | One row per client machine.                            |
| `Users`           | One row per Windows user observed.                     |
| `SessionEvents`   | Raw event stream (Logon, Logoff, Lock, Unlock, Idle…). |
| `Sessions`        | Per-logon aggregate: duration, idle, active, locks.    |
| `AppUsage`        | Per (Session, App): foreground/running time, launches. |
| `IngestBatches`   | Audit trail of every batch the agent pushed.           |
| `vw_ActiveSessions`        | Currently active sessions across the fleet.   |
| `vw_DailyMachineSummary`   | Per-day per-machine session totals.           |
