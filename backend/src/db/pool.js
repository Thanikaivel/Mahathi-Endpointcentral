'use strict';

const sql = require('mssql');

const config = {
  server:   process.env.DB_SERVER   || 'localhost',
  port:     parseInt(process.env.DB_PORT || '1433', 10),
  database: process.env.DB_NAME     || 'UserActivityDB',
  user:     process.env.DB_USER     || 'sa',
  password: process.env.DB_PASSWORD || '',

  // Per-request timeouts (avoid one slow query hogging the pool forever)
  requestTimeout: parseInt(process.env.DB_REQUEST_TIMEOUT_MS || '30000', 10),
  connectionTimeout: parseInt(process.env.DB_CONNECT_TIMEOUT_MS || '15000', 10),

  pool: {
    // For 300 machines syncing every 60s plus the dashboard, 50 is a sane default.
    // Tune up if you see "operation timed out" in the logs.
    max: parseInt(process.env.DB_POOL_MAX || '50', 10),
    min: parseInt(process.env.DB_POOL_MIN || '2',  10),
    // Wait at most 30s for a free connection before returning a TimeoutError.
    // Without this, requests can hang indefinitely under burst load.
    acquireTimeoutMillis: parseInt(process.env.DB_POOL_ACQUIRE_TIMEOUT_MS || '30000', 10),
    idleTimeoutMillis:    parseInt(process.env.DB_POOL_IDLE_TIMEOUT_MS    || '30000', 10),
    // Periodically check idle connections; reap broken ones automatically.
    reapIntervalMillis:   parseInt(process.env.DB_POOL_REAP_MS || '5000', 10),
    createRetryIntervalMillis: 2000,
  },

  options: {
    encrypt: String(process.env.DB_ENCRYPT || 'false').toLowerCase() === 'true',
    trustServerCertificate:
      String(process.env.DB_TRUST_SERVER_CERTIFICATE || 'true').toLowerCase() === 'true',
    enableArithAbort: true
  }
};

let poolPromise;

function attachHandlers(pool) {
  // CRITICAL: without this listener, the pool's 'error' event becomes
  // an uncaught exception that crashes the entire backend process.
  pool.on('error', (err) => {
    console.error('[db] pool error:', err.message);
    // Some pool errors mean the underlying connection is now dead.
    // Mark the pool as failed so the next getPool() reconnects.
    const fatal = ['ECONNRESET', 'ECONNREFUSED', 'ETIMEDOUT', 'EPIPE'].includes(err.code)
               || /timed out|connection.*lost|server.*unavailable/i.test(err.message || '');
    if (fatal) {
      console.error('[db] fatal pool error - will reconnect on next request');
      try { pool.close(); } catch (_) {}
      poolPromise = undefined;
    }
  });
}

function getPool() {
  if (!poolPromise) {
    const pool = new sql.ConnectionPool(config);
    attachHandlers(pool);
    poolPromise = pool
      .connect()
      .then((p) => {
        console.log(`[db] Connected to ${config.server}/${config.database} ` +
                    `(pool max=${config.pool.max}, min=${config.pool.min})`);
        return p;
      })
      .catch((err) => {
        console.error('[db] Connection failed:', err.message);
        poolPromise = undefined; // allow retry on next call
        throw err;
      });
  }
  return poolPromise;
}

module.exports = { sql, getPool };
