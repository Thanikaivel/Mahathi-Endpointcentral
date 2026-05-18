'use strict';

/**
 * Pushes spooled JSON files to the API. On 2xx response (or duplicate ack),
 * deletes the local file. On network or 5xx errors, keeps the file for retry.
 * 4xx errors (client error) also delete the file because retrying won't help.
 */
const axios = require('axios');
const log   = require('./logger');
const storage = require('./storage');

async function pushOne(apiBaseUrl, agentKey, file, payload) {
  const url = `${apiBaseUrl.replace(/\/+$/,'')}/ingest`;
  const res = await axios.post(url, payload, {
    headers: {
      'Content-Type': 'application/json',
      'X-Agent-Key': agentKey
    },
    timeout: 30000,
    validateStatus: () => true
  });
  if (res.status >= 200 && res.status < 300) {
    storage.deleteBatch(file);
    log.info(`pushed ${file} (${res.data && res.data.duplicate ? 'duplicate' : 'ok'})`);
    return { ok: true };
  }
  if (res.status >= 400 && res.status < 500) {
    log.warn(`server rejected ${file} status=${res.status} body=${JSON.stringify(res.data)} - dropping`);
    storage.deleteBatch(file);
    return { ok: false, dropped: true };
  }
  log.warn(`push failed ${file} status=${res.status} - will retry`);
  return { ok: false };
}

async function pushAll(cfg) {
  const files = storage.listBatches(cfg.spoolDir);
  if (files.length === 0) return { pushed: 0, kept: 0 };
  let pushed = 0, kept = 0;
  for (const file of files) {
    let payload;
    try {
      payload = storage.readBatch(file);
    } catch (e) {
      log.error(`spool file unreadable, dropping ${file}: ${e.message}`);
      storage.deleteBatch(file);
      continue;
    }
    try {
      const r = await pushOne(cfg.apiBaseUrl, cfg.agentKey, file, payload);
      if (r.ok) pushed++; else if (!r.dropped) { kept++; break; } // stop on transient err
    } catch (e) {
      log.warn(`push exception for ${file}: ${e.message}`);
      kept++;
      break; // network down - stop trying for now
    }
  }
  return { pushed, kept };
}

module.exports = { pushAll };
