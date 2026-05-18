#!/usr/bin/env node
'use strict';

/**
 * Set or reset a dashboard admin user's password.
 * Usage:
 *   node scripts/set-admin-password.js <username> <new-password> [--display "Display Name"] [--create]
 *
 * Examples:
 *   node scripts/set-admin-password.js admin Sup3rS3cret!
 *   node scripts/set-admin-password.js sarah Welcome2026 --display "Sarah Admin" --create
 *
 * Requires the same DB env vars the backend uses (.env in backend folder).
 */
require('dotenv').config();
const bcrypt = require('bcryptjs');
const { sql, getPool } = require('../src/db/pool');

async function main() {
  const args = process.argv.slice(2);
  if (args.length < 2) {
    console.error('Usage: node scripts/set-admin-password.js <username> <new-password> [--display "Name"] [--create]');
    process.exit(1);
  }

  const username = args[0];
  const password = args[1];
  let display = null;
  let create  = false;
  for (let i = 2; i < args.length; i++) {
    if (args[i] === '--display' && args[i+1]) { display = args[i+1]; i++; }
    else if (args[i] === '--create') { create = true; }
  }

  if (password.length < 8) {
    console.error('Password must be at least 8 characters.');
    process.exit(1);
  }

  const hash = await bcrypt.hash(password, 10);
  const pool = await getPool();

  // Check if user exists
  const r = await pool.request()
    .input('Username', sql.NVarChar(64), username)
    .query('SELECT AdminUserId FROM dbo.AdminUsers WHERE Username = @Username');

  if (r.recordset.length === 0) {
    if (!create) {
      console.error(`User '${username}' not found. Re-run with --create to create them.`);
      process.exit(1);
    }
    await pool.request()
      .input('Username', sql.NVarChar(64), username)
      .input('PasswordHash', sql.NVarChar(256), hash)
      .input('DisplayName', sql.NVarChar(128), display || username)
      .query(`INSERT INTO dbo.AdminUsers (Username, PasswordHash, DisplayName)
              VALUES (@Username, @PasswordHash, @DisplayName);`);
    console.log(`Created admin user '${username}'.`);
  } else {
    await pool.request()
      .input('Username', sql.NVarChar(64), username)
      .input('PasswordHash', sql.NVarChar(256), hash)
      .input('DisplayName', sql.NVarChar(128), display)
      .query(`UPDATE dbo.AdminUsers
                 SET PasswordHash = @PasswordHash,
                     DisplayName  = COALESCE(@DisplayName, DisplayName),
                     IsEnabled    = 1
               WHERE Username = @Username;`);
    console.log(`Password updated for '${username}'.`);
  }

  process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
