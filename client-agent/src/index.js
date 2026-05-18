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
      appUsages: drained.appUsages
    }
  };
}

async function flushAndSync() {
  const drained = sm.drain();
  const isEmpty = drained.events.length === 0 && drained.sessions.length === 0 && drained.appUsages.length === 0;
  if (!isEmpty) {
    try {
      const file = storage.writeBatch(cfg.spoolDir, buildPayload(drained));
      log.info(`spooled batch -> ${path.basename(file)} ` +
               `(events=${drained.events.length} sessions=${drained.sessions.length} apps=${drained.appUsages.length})`);
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

  pollTimer = setInterval(() => { pollOnce().catch(e => log.error('poll error:', e.message)); },
                          cfg.pollIntervalSeconds * 1000);
  syncTimer = setInterval(() => { flushAndSync().catch(e => log.error('sync error:', e.message)); },
                          cfg.syncIntervalSeconds * 1000);

  log.info(`agent ready (poll=${cfg.pollIntervalSeconds}s sync=${cfg.syncIntervalSeconds}s idleThreshold=${cfg.idleThresholdSeconds}s)`);
})();
