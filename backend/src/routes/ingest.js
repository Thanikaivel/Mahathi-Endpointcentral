'use strict';

/**
 * Agent ingest endpoint.
 * POST /api/ingest
 * Headers:  X-Agent-Key: <shared key>
 * Body shape: see contract below.
 *
 * The endpoint is idempotent — if the same ClientBatchId is sent twice,
 * the second call is acknowledged but not re-applied (so the agent can
 * safely retry on transient network failures before deleting its JSON).
 */
const express = require('express');
const router = express.Router();
const repo = require('../db/repository');
const { sql, getPool } = require('../db/pool');
const agentAuth = require('../middleware/agentAuth');

router.use(agentAuth);

router.post('/', async (req, res) => {
  const body = req.body || {};
  const { machine, batch } = body;

  if (!machine || !machine.machineName) {
    return res.status(400).json({ error: 'machine.machineName is required' });
  }
  if (!batch || !batch.clientBatchId) {
    return res.status(400).json({ error: 'batch.clientBatchId is required' });
  }

  // Idempotency check
  const already = await repo.batchAlreadyProcessed(machine.machineName, batch.clientBatchId);
  if (already) {
    return res.json({
      ok: true,
      duplicate: true,
      message: 'Batch already processed; safe to delete local JSON.'
    });
  }

  const events    = Array.isArray(batch.events)    ? batch.events    : [];
  const sessions  = Array.isArray(batch.sessions)  ? batch.sessions  : [];
  const appUsages = Array.isArray(batch.appUsages) ? batch.appUsages : [];

  const pool = await getPool();
  const tx = new sql.Transaction(pool);

  try {
    // 1. Upsert machine outside the tx (it's its own MERGE) — get ID
    const machineId = await repo.upsertMachine(machine);

    await tx.begin();

    // 2. Pre-upsert any users referenced
    const userIdCache = new Map();
    async function getUserId(userKey, userName, domain) {
      if (!userName) return null;
      const cacheKey = `${domain || ''}|${userName}`;
      if (userIdCache.has(cacheKey)) return userIdCache.get(cacheKey);
      const id = await repo.upsertUser({ userName, domain, displayName: null });
      userIdCache.set(cacheKey, id);
      return id;
    }

    // 3. Sessions first (so AppUsage can reference SessionId)
    const sessionIdMap = new Map(); // clientSessionId -> SessionId
    for (const s of sessions) {
      const userId = await getUserId(null, s.userName, s.domain);
      if (!userId) continue;
      const sessionId = await repo.upsertSession(tx, {
        machineId,
        userId,
        clientSessionId: s.clientSessionId,
        logonTimeUtc: s.logonTimeUtc,
        logoffTimeUtc: s.logoffTimeUtc || null,
        idleSeconds: s.idleSeconds,
        activeSeconds: s.activeSeconds,
        lockCount: s.lockCount,
        isLocked: !!s.isLocked,
        endReason: s.endReason
      });
      sessionIdMap.set(s.clientSessionId, sessionId);
    }

    // 4. Events
    for (const e of events) {
      const userId = await getUserId(null, e.userName, e.domain);
      await repo.insertEvent(tx, {
        machineId,
        userId,
        eventType: e.eventType,
        eventTimeUtc: e.eventTimeUtc,
        clientEventId: e.clientEventId,
        details: e.details
      });
    }

    // 5. App usage (resolve SessionId via clientSessionId)
    for (const a of appUsages) {
      let sessionId = sessionIdMap.get(a.clientSessionId);
      if (!sessionId) {
        sessionId = await repo.getSessionIdByClientGuid(tx, a.clientSessionId);
        if (sessionId) sessionIdMap.set(a.clientSessionId, sessionId);
      }
      if (!sessionId) continue; // skip orphan app rows
      const userId = await getUserId(null, a.userName, a.domain);
      if (!userId) continue;
      await repo.upsertAppUsage(tx, {
        sessionId,
        machineId,
        userId,
        appName: a.appName,
        appPath: a.appPath,
        windowTitleSample: a.windowTitleSample,
        firstSeenUtc: a.firstSeenUtc,
        lastSeenUtc: a.lastSeenUtc,
        foregroundSeconds: a.foregroundSeconds,
        runningSeconds: a.runningSeconds,
        launchCount: a.launchCount
      });
    }

    await tx.commit();

    await repo.recordBatch({
      machineId,
      machineName: machine.machineName,
      clientBatchId: batch.clientBatchId,
      eventCount: events.length,
      sessionCount: sessions.length,
      appUsageCount: appUsages.length,
      status: 'OK'
    });

    res.json({
      ok: true,
      duplicate: false,
      eventsAccepted: events.length,
      sessionsAccepted: sessions.length,
      appUsagesAccepted: appUsages.length
    });
  } catch (err) {
    try { await tx.rollback(); } catch (_) { /* swallow */ }
    console.error('[ingest] error:', err);
    try {
      await repo.recordBatch({
        machineId: null,
        machineName: machine.machineName,
        clientBatchId: batch.clientBatchId,
        eventCount: events.length,
        sessionCount: sessions.length,
        appUsageCount: appUsages.length,
        status: 'ERROR',
        errorMessage: String(err.message || err).slice(0, 1900)
      });
    } catch (_) { /* swallow */ }
    res.status(500).json({ ok: false, error: err.message || String(err) });
  }
});

module.exports = router;
