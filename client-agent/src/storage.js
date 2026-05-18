'use strict';

/**
 * Local JSON spool. Every flush writes a single .json file in spoolDir.
 * After successful upload the file is deleted. On startup, all .json
 * files in the spool are picked up and pushed.
 */
const fs   = require('fs');
const path = require('path');
const { v4: uuidv4 } = require('uuid');

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function writeBatch(spoolDir, payload) {
  ensureDir(spoolDir);
  const id = payload.batch.clientBatchId || uuidv4();
  payload.batch.clientBatchId = id;
  const tmp  = path.join(spoolDir, `.${id}.json.tmp`);
  const dest = path.join(spoolDir, `${id}.json`);
  fs.writeFileSync(tmp, JSON.stringify(payload), 'utf8');
  fs.renameSync(tmp, dest);
  return dest;
}

function listBatches(spoolDir) {
  ensureDir(spoolDir);
  return fs.readdirSync(spoolDir)
    .filter(f => f.endsWith('.json'))
    .map(f => path.join(spoolDir, f))
    .sort(); // chronological-ish (uuid v4 isn't sortable but fs order is fine)
}

function readBatch(file) {
  const raw = fs.readFileSync(file, 'utf8');
  return JSON.parse(raw);
}

function deleteBatch(file) {
  try { fs.unlinkSync(file); } catch (_) { /* ignore */ }
}

function totalSpoolBytes(spoolDir) {
  ensureDir(spoolDir);
  let total = 0;
  for (const f of listBatches(spoolDir)) {
    try { total += fs.statSync(f).size; } catch (_) {}
  }
  return total;
}

module.exports = { writeBatch, listBatches, readBatch, deleteBatch, totalSpoolBytes, ensureDir };
