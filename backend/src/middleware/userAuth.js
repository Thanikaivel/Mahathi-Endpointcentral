'use strict';

const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET || 'change-me-in-production-uam-jwt-secret';

/**
 * Verifies the Authorization: Bearer <token> header and populates req.user.
 * Returns 401 if the token is missing/invalid/expired.
 */
function userAuth(req, res, next) {
  const auth = req.headers['authorization'] || '';
  const m = auth.match(/^Bearer\s+(.+)$/i);
  if (!m) {
    return res.status(401).json({ error: 'Missing or invalid Authorization header' });
  }
  try {
    const payload = jwt.verify(m[1], JWT_SECRET);
    req.user = { id: payload.sub, username: payload.username, displayName: payload.displayName };
    next();
  } catch (e) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}

module.exports = userAuth;
module.exports.JWT_SECRET = JWT_SECRET;
