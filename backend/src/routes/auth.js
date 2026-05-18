'use strict';

/**
 * Authentication routes for dashboard users.
 *   POST /api/auth/login    -> body: { username, password }   -> returns { token, user }
 *   GET  /api/auth/me       -> (requires bearer token)        -> returns { user }
 */
const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const jwt    = require('jsonwebtoken');
const { sql, getPool } = require('../db/pool');
const userAuth = require('../middleware/userAuth');

const JWT_SECRET    = userAuth.JWT_SECRET;
const TOKEN_TTL_HRS = parseInt(process.env.JWT_TTL_HOURS || '12', 10);

router.post('/login', async (req, res) => {
  try {
    const { username, password } = req.body || {};
    if (!username || !password) {
      return res.status(400).json({ error: 'username and password are required' });
    }

    const pool = await getPool();
    const r = await pool.request()
      .input('Username', sql.NVarChar(64), username)
      .query(`
        SELECT AdminUserId, Username, PasswordHash, DisplayName, IsEnabled
        FROM dbo.AdminUsers
        WHERE Username = @Username;
      `);

    const row = r.recordset[0];
    if (!row || !row.IsEnabled) {
      // Same error message regardless of cause to avoid username enumeration
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const ok = await bcrypt.compare(password, row.PasswordHash);
    if (!ok) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Update LastLoginUtc (best-effort, don't fail the login if this errors)
    pool.request()
      .input('Id', sql.Int, row.AdminUserId)
      .query('UPDATE dbo.AdminUsers SET LastLoginUtc = SYSUTCDATETIME() WHERE AdminUserId = @Id')
      .catch(() => {});

    const token = jwt.sign(
      { sub: row.AdminUserId, username: row.Username, displayName: row.DisplayName || row.Username },
      JWT_SECRET,
      { expiresIn: `${TOKEN_TTL_HRS}h` }
    );

    res.json({
      token,
      user: {
        id: row.AdminUserId,
        username: row.Username,
        displayName: row.DisplayName || row.Username
      },
      expiresInHours: TOKEN_TTL_HRS
    });
  } catch (e) {
    console.error('[auth/login]', e);
    res.status(500).json({ error: e.message || 'Login failed' });
  }
});

router.get('/me', userAuth, (req, res) => {
  res.json({ user: req.user });
});

module.exports = router;
