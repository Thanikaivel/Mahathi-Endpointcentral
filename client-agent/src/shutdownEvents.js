'use strict';

/**
 * Reads Windows shutdown events from the System event log.
 *
 * The agent's own Shutdown event (emitted from the SIGTERM handler) is
 * unreliable on Windows because Node.js processes are often killed by
 * Windows during shutdown without SIGTERM firing. Event ID 1074, written
 * by Windows itself, is the authoritative record of when a shutdown was
 * initiated.
 *
 * We invoke this at agent startup so that any shutdown that happened while
 * the agent wasn't running gets backfilled into our SessionEvents table.
 */
const { spawn } = require('child_process');

let log;
try { log = require('./logger'); }
catch (_) { log = { info: console.log, warn: console.warn, error: console.error }; }

/**
 * Returns recent shutdown events from Windows Event Log as
 *   [{ timeUtc: ISO string, eventId: 1074, message: '...' }, ...]
 *
 * @param {number} sinceUnixMs - only events after this time
 * @returns Promise<Array>
 */
function readRecent(sinceUnixMs = 0) {
  // Query both 1074 (user/process initiated shutdown) and 6006 (event log
  // service stopping, which is a clean-shutdown marker).
  // Limit to the most recent 20 to keep PowerShell fast.
  const psCommand = `
    $events = Get-WinEvent -FilterHashtable @{ LogName='System'; Id=1074,6006 } -MaxEvents 20 -ErrorAction SilentlyContinue
    if ($events) {
      $events | Select-Object @{
        Name='timeUtc'; Expression={ $_.TimeCreated.ToUniversalTime().ToString('o') }
      }, @{
        Name='eventId'; Expression={ $_.Id }
      }, @{
        Name='message'; Expression={ ($_.Message -split "\`n")[0] }
      } | ConvertTo-Json -Compress
    }
  `.trim();

  return new Promise((resolve) => {
    const child = spawn('powershell.exe', [
      '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
      '-Command', psCommand
    ], { windowsHide: true });

    let stdout = '';
    let stderr = '';
    const timer = setTimeout(() => { try { child.kill(); } catch (_) {} resolve([]); }, 15000);

    child.stdout.on('data', d => { stdout += d.toString(); });
    child.stderr.on('data', d => { stderr += d.toString(); });
    child.on('close', () => {
      clearTimeout(timer);
      if (!stdout.trim()) return resolve([]);
      try {
        let parsed = JSON.parse(stdout);
        if (!Array.isArray(parsed)) parsed = [parsed];
        const filtered = parsed
          .filter(e => e && e.timeUtc)
          .filter(e => new Date(e.timeUtc).getTime() > sinceUnixMs);
        resolve(filtered);
      } catch (e) {
        log.warn(`shutdownEvents: parse failed: ${e.message}`);
        resolve([]);
      }
    });
    child.on('error', () => { clearTimeout(timer); resolve([]); });
  });
}

module.exports = { readRecent };
