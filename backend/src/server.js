'use strict';

require('dotenv').config();

const express = require('express');
const cors    = require('cors');
const helmet  = require('helmet');
const morgan  = require('morgan');

const { getPool } = require('./db/pool');
const ingestRoutes    = require('./routes/ingest');
const dashboardRoutes = require('./routes/dashboard');
const authRoutes      = require('./routes/auth');
const userAuth        = require('./middleware/userAuth');

const app = express();
const PORT = parseInt(process.env.PORT || '5321', 10);

// CORS
const origins = (process.env.CORS_ORIGINS || '')
  .split(',').map(s => s.trim()).filter(Boolean);
app.use(cors({
  origin: origins.length ? origins : true,
  credentials: true
}));

app.use(helmet());
app.use(express.json({ limit: '5mb' })); // batches can be sizable
app.use(morgan('tiny'));

// Health
app.get('/api/health', async (req, res) => {
  try {
    const pool = await getPool();
    await pool.request().query('SELECT 1 AS ok');
    res.json({ ok: true, db: 'up', time: new Date().toISOString() });
  } catch (e) {
    res.status(500).json({ ok: false, db: 'down', error: e.message });
  }
});

// /api/auth is unprotected (it's where you obtain the token)
app.use('/api/auth',      authRoutes);
// /api/ingest uses agentKey auth (already inside the route module) - DO NOT add userAuth here
app.use('/api/ingest',    ingestRoutes);
// /api/dashboard requires a logged-in user
app.use('/api/dashboard', userAuth, dashboardRoutes);

// Default error handler
app.use((err, req, res, _next) => {
  console.error('[error]', err);
  res.status(500).json({ error: err.message || 'Internal error' });
});

// Periodic stale-session cleanup: closes sessions whose machine has been
// silent for >15 minutes (agent killed or crashed without sending Logoff).
async function runStaleCleanup() {
  try {
    const pool = await getPool();
    const r = await pool.request().execute('dbo.usp_CloseStaleSessions');
    const closed = (r.recordset && r.recordset[0] && r.recordset[0].Closed) || 0;
    if (closed > 0) console.log(`[cleanup] closed ${closed} stale session(s)`);
  } catch (e) {
    console.warn('[cleanup] failed:', e.message);
  }
}
const STALE_INTERVAL_MS = 5 * 60 * 1000;
setTimeout(runStaleCleanup, 30 * 1000);             // first run 30s after start
setInterval(runStaleCleanup, STALE_INTERVAL_MS);    // every 5 minutes thereafter

// Last-resort safety nets so a stray unhandled error doesn't crash the
// whole backend (we'd rather log and keep serving the other 299 agents).
process.on('uncaughtException',  (err) => {
  console.error('[uncaughtException]', err && err.stack || err);
});
process.on('unhandledRejection', (reason) => {
  console.error('[unhandledRejection]', reason && (reason.stack || reason.message || reason));
});

app.listen(PORT, () => {
  console.log(`[uam-backend] listening on :${PORT}`);
});

module.exports = app;
