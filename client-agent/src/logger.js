'use strict';

const fs = require('fs');
const path = require('path');

let stream = null;
let logFilePath = null;

function init(logFile) {
  logFilePath = logFile;
  try {
    fs.mkdirSync(path.dirname(logFile), { recursive: true });
    // Probe whether we can actually write to the file BEFORE attaching the
    // stream — createWriteStream is lazy and EPERM/EBUSY only surface on the
    // first write as an emitted 'error' event, which would crash the process.
    try {
      fs.accessSync(logFile, fs.constants.W_OK);
    } catch (e) {
      // File doesn't exist yet, or we can't write to it. Try to create it
      // briefly to confirm; if that fails, fall back to console-only.
      try {
        const fd = fs.openSync(logFile, 'a');
        fs.closeSync(fd);
      } catch (e2) {
        console.error('[logger] Cannot write to ' + logFile + ': ' + e2.message);
        console.error('[logger] Continuing with console-only logging.');
        console.error('[logger] (This is normal when running from source while the service is also running' +
                      ' — the service has the log file open. Stop the service first, or point the dev run at' +
                      ' a different log via config.json -> "logFile".)');
        stream = null;
        return;
      }
    }
    stream = fs.createWriteStream(logFile, { flags: 'a' });
    // Crucially: handle async errors so EPERM doesn't kill the process
    stream.on('error', (err) => {
      console.error('[logger] log stream error: ' + err.message + ' — disabling file logging.');
      try { stream.destroy(); } catch (_) {}
      stream = null;
    });
  } catch (e) {
    console.error('[logger] Failed to init log file: ' + e.message);
    stream = null;
  }
}

function ts() { return new Date().toISOString(); }

function write(level, args) {
  const line = `[${ts()}] [${level}] ${args.map(a => typeof a === 'string' ? a : JSON.stringify(a)).join(' ')}`;
  // eslint-disable-next-line no-console
  (level === 'ERROR' ? console.error : console.log)(line);
  if (stream) {
    try { stream.write(line + '\n'); } catch (_) { /* ignore */ }
  }
}

module.exports = {
  init,
  info:  (...a) => write('INFO',  a),
  warn:  (...a) => write('WARN',  a),
  error: (...a) => write('ERROR', a)
};
