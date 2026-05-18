'use strict';

const sql = require('mssql');

const config = {
  server: process.env.DB_SERVER || 'localhost',
  port: parseInt(process.env.DB_PORT || '1433', 10),
  database: process.env.DB_NAME || 'UserActivityDB',
  user: process.env.DB_USER || 'sa',
  password: process.env.DB_PASSWORD || '',
  pool: {
    max: 20,
    min: 0,
    idleTimeoutMillis: 30000
  },
  options: {
    encrypt: String(process.env.DB_ENCRYPT || 'false').toLowerCase() === 'true',
    trustServerCertificate:
      String(process.env.DB_TRUST_SERVER_CERTIFICATE || 'true').toLowerCase() === 'true',
    enableArithAbort: true
  }
};

let poolPromise;

function getPool() {
  if (!poolPromise) {
    poolPromise = new sql.ConnectionPool(config)
      .connect()
      .then((pool) => {
        console.log(`[db] Connected to ${config.server}/${config.database}`);
        return pool;
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
