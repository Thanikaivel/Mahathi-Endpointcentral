#!/usr/bin/env node
'use strict';

/**
 * UAM Client Agent - main entry point.
 * Runs as a Windows Service (or interactively for debugging).
 *
 * Loop:
 *   - every pollIntervalSeconds: probe Windows state, feed StateMachine.
 *   - every syncIntervalSeconds: drain pending output to a JSON spool file
 *     and try to upload all spool files; delete each on success.
 */
const os      = require('os');
const path    = require('path');
const { v4: uuidv4 } = require('uuid');

const config  = require('./config');
const log     = require('./logger');
const winApi  = require('./winApi');
const storage = require('./storage');
const sync    = require('./sync');
const { StateMachine } = require('./state');
const shutdownEvents = require('./shutdownEvents');

let browserHistory = null;
try { browserHistory = require('./browserHistory'); }
catch (e) { /* better-sqlite3 native binding may fail - feature is optional */ }

let cfg;
try {
  cfg = config.load();
} catch (e) {
  console.error(e.message);
  process.exit(1);
}
log.init(cfg.logFile);
log.info(`UAM Agent ${cfg.agentVersion} starting (config from ${cfg.__loadedFrom})`);
log.info(`API base: ${cfg.apiBaseUrl}`);
log.info(`Spool: ${cfg.spoolDir}`);

const machineNameDefault = os.hostname();

const sm = new StateMachine({
  idleThresholdSeconds: cfg.idleThresholdSeconds,
  pollIntervalSeconds: cfg.pollIntervalSeconds,
  endSessionAfterIdleSeconds: cfg.endSessionAfterIdleSeconds || 3600  // 1 hour default
});

let machineMeta = {
  machineName: machineNameDefault,
  domain: process.env.USERDOMAIN || null,
  osVersion: null,
  ipAddress: null,
  agentVersion: cfg.agentVersion
};

// Track a "running" snapshot so we can mark Shutdown if we exit cleanly.
let lastUserSnapshotAt = null;

// Browser history collection state — see collectBrowserHistoryIfDue
let browserHistoryState = {};
let pendingBrowserHistory = [];
let lastBrowserCheckMs = 0;
const BROWSER_HISTORY_INTERVAL_MS = 5 * 60 * 1000;  // every 5 minutes

function collectBrowserHistoryIfDue() {
  if (!browserHistory) return;
  const now = Date.now();
  if (now - lastBrowserCheckMs < BROWSER_HISTORY_INTERVAL_MS) return;
  lastBrowserCheckMs = now;
  try {
    const userName        = (sm.session && sm.session.userName) || null;
    const userDomain      = (sm.session && sm.session.domain)   || null;
    const clientSessionId = (sm.session && sm.session.clientSessionId) || null;
    const result = browserHistory.collect(browserHistoryState);
    browserHistoryState = result.lastTimestamps;
    if (result.rows.length > 0) {
      for (const r of result.rows) {
        r.userName        = userName;
        r.userDomain      = userDomain;
        r.clientSessionId = clientSessionId;
      }
      pendingBrowserHistory.push(...result.rows);
      log.info(`browserHistory: collected ${result.rows.length} new visit(s)`);
    }
  } catch (e) {
    log.warn(`browserHistory: collect failed: ${e.message}`);
  }
}

// Backfill Shutdown events from Windows Event Log on agent startup
async function backfillShutdownEvents() {
  try {
    const events = await shutdownEvents.readRecent(0);
    if (!events.length) return;
    // Take only Event ID 1074 (user/process initiated) — 6006 is essentially a duplicate
    const seen = new Set();
    let backfilled = 0;
    for (const e of events) {
      if (e.eventId !== 1074) continue;
      if (seen.has(e.timeUtc)) continue;
      seen.add(e.timeUtc);
      sm.emit('Shutdown', `From Windows Event Log (ID 1074): ${(e.message || '').slice(0, 200)}`,
              { eventTimeUtc: e.timeUtc });
      backfilled++;
    }
    if (backfilled > 0) log.info(`shutdownEvents: backfilled ${backfilled} Shutdown event(s) from Windows Event Log`);
  } catch (e) {
    log.warn(`shutdownEvents: backfill failed: ${e.message}`);
  }
}

async function pollOnce() {
  let snap;
  try {
    snap = await winApi.probe({ includeProcesses: !!cfg.trackRunningApps });
  } catch (e) {
    log.warn(`probe failed: ${e.message}`);
    return;
  }
  if (snap.machineName) machineMeta.machineName = snap.machineName;
  if (snap.domain)      machineMeta.domain      = snap.domain;
  if (snap.osCaption)   machineMeta.osVersion   = `${snap.osCaption} (${snap.osVersion || ''})`.trim();
  if (snap.ipAddress)   machineMeta.ipAddress   = snap.ipAddress;
  lastUserSnapshotAt = new Date();
  sm.ingest(snap);

  // Collect browser history if it's time
  collectBrowserHistoryIfDue();

  // If the state machine flagged an immediate sync need (e.g. lock/unlock
  // transition), flush right now so the dashboard reflects it within seconds
  // instead of waiting up to the full sync interval.
  if (sm.needsImmediateSync) {
    sm.needsImmediateSync = false;
    flushAndSync().catch(e => log.warn(`immediate sync failed: ${e.message}`));
  }
}

function buildPayload(drained) {
  return {
    machine: machineMeta,
    batch: {
      clientBatchId: uuidv4(),
      generatedAtUtc: new Date().toISOString(),
      events: drained.events,
      sessions: drained.sessions,
      appUsages: drained.appUsages,
      browserHistory: drained.browserHistory || []
    }
  };
}

async function flushAndSync() {
  const drained = sm.drain();
  drained.browserHistory = pendingBrowserHistory;
  pendingBrowserHistory  = [];
  const isEmpty = drained.events.length === 0 && drained.sessions.length === 0 && drained.appUsages.length === 0 && drained.browserHistory.length === 0;
  if (!isEmpty) {
    try {
      const file = storage.writeBatch(cfg.spoolDir, buildPayload(drained));
      log.info(`spooled batch -> ${path.basename(file)} ` +
               `(events=${drained.events.length} sessions=${drained.sessions.length} apps=${drained.appUsages.length} browser=${drained.browserHistory.length})`);
    } catch (e) {
      log.error(`spool write failed: ${e.message}`);
    }
  }
  try {
    const r = await sync.pushAll(cfg);
    if (r.pushed || r.kept) log.info(`sync: pushed=${r.pushed} kept=${r.kept}`);
  } catch (e) {
    log.warn(`sync failed: ${e.message}`);
  }
}

let pollTimer = null;
let syncTimer = null;
let stopping = false;

async function shutdown(reason = 'Shutdown') {
  if (stopping) return;
  stopping = true;
  log.info(`shutting down (${reason})`);
  if (pollTimer) clearInterval(pollTimer);
  if (syncTimer) clearInterval(syncTimer);
  try {
    sm.endSession({ reason, eventTimeUtc: new Date().toISOString() });
  } catch (_) {}
  await flushAndSync();
  log.info('agent stopped.');
  process.exit(0);
}

process.on('SIGINT',  () => shutdown('Shutdown'));
process.on('SIGTERM', () => shutdown('Shutdown'));
process.on('uncaughtException', e => { log.error('uncaught:', e.stack || e.message); });
process.on('unhandledRejection', e => { log.error('unhandled rejection:', e); });

(async function main() {
  // Push any spooled files left from a previous run before we start collecting
  try { await sync.pushAll(cfg); } catch (e) { log.warn(`startup sync failed: ${e.message}`); }

  // First poll immediately so we capture the initial session
  await pollOnce();

  // Backfill shutdown events from Windows Event Log (catches shutdowns that
  // happened while the agent wasn't running, since Node.js SIGTERM is unreliable
  // during Windows shutdown). This runs after the first poll so we have a
  // session to attach the Shutdown event to.
  backfillShutdownEvents().catch(e => log.warn(`shutdownEvents init failed: ${e.message}`));

  pollTimer = setInterval(() => { pollOnce().catch(e => log.error('poll error:', e.message)); },
                          cfg.pollIntervalSeconds * 1000);
  syncTimer = setInterval(() => { flushAndSync().catch(e => log.error('sync error:', e.message)); },
                          cfg.syncIntervalSeconds * 1000);

  log.info(`agent ready (poll=${cfg.pollIntervalSeconds}s sync=${cfg.syncIntervalSeconds}s idleThreshold=${cfg.idleThresholdSeconds}s)`);
})();
