'use strict';

/**
 * Simple shared-key auth for client agents.
 * Agents must send: X-Agent-Key: <AGENT_SHARED_KEY>
 */
module.exports = function agentAuth(req, res, next) {
  const expected = process.env.AGENT_SHARED_KEY;
  if (!expected) {
    return res.status(500).json({ error: 'Server misconfigured: AGENT_SHARED_KEY not set' });
  }
  const provided = req.header('X-Agent-Key');
  if (!provided || provided !== expected) {
    return res.status(401).json({ error: 'Unauthorized agent' });
  }
  next();
};
