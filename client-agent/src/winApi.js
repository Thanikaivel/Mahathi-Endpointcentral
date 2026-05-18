'use strict';

/**
 * Wraps probe.ps1 to read the current Windows state.
 * Spawns powershell.exe (Windows PowerShell, present on all Windows 10/11/Server).
 */
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

function findPs1() {
  const bundled = path.join(__dirname, 'ps', 'probe.ps1');

  // Detect pkg-bundled mode: pkg sets process.pkg and __dirname starts with /snapshot or C:\\snapshot.
  const isPkg = !!process.pkg ||
                (typeof __dirname === 'string' &&
                 /^(\/snapshot|[a-zA-Z]:\\snapshot)/.test(__dirname));

  if (!isPkg) {
    // Running from source — use the file directly.
    if (fs.existsSync(bundled)) return bundled;
  }

  // Under pkg the bundled path lives in the virtual snapshot, which
  // PowerShell (a separate process) cannot read. Extract once to a real
  // path next to the exe (or in TEMP) and reuse it.
  const exeDir = path.dirname(process.execPath);
  const extracted = path.join(
    exeDir.toLowerCase().includes('windows\\system32') || !canWrite(exeDir)
      ? (process.env.TEMP || 'C:\\Windows\\Temp')
      : exeDir,
    'uam-probe.ps1'
  );

  try {
    // Copy on first run, or whenever the bundled copy is newer than the cached one.
    let needsWrite = true;
    try {
      if (fs.existsSync(extracted)) {
        const src = fs.readFileSync(bundled, 'utf8');
        const dst = fs.readFileSync(extracted, 'utf8');
        needsWrite = src !== dst;
      }
    } catch (_) { /* fall through to write */ }
    if (needsWrite) {
      const data = fs.readFileSync(bundled, 'utf8');
      fs.writeFileSync(extracted, data, 'utf8');
    }
    return extracted;
  } catch (e) {
    throw new Error('Could not extract probe.ps1: ' + e.message);
  }
}

function canWrite(dir) {
  try {
    const probe = path.join(dir, '.uam-write-test');
    fs.writeFileSync(probe, '');
    fs.unlinkSync(probe);
    return true;
  } catch (_) { return false; }
}

let ps1Path = null;

function probe({ includeProcesses = false, timeoutMs = 8000 } = {}) {
  if (!ps1Path) ps1Path = findPs1();
  return new Promise((resolve, reject) => {
    const args = [
      '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
      '-File', ps1Path
    ];
    if (includeProcesses) args.push('-IncludeProcesses');

    const child = spawn('powershell.exe', args, { windowsHide: true });

    let stdout = '';
    let stderr = '';
    const timer = setTimeout(() => {
      try { child.kill(); } catch (_) {}
      reject(new Error(`probe.ps1 timeout after ${timeoutMs}ms`));
    }, timeoutMs);

    child.stdout.on('data', d => { stdout += d.toString(); });
    child.stderr.on('data', d => { stderr += d.toString(); });
    child.on('error', err => { clearTimeout(timer); reject(err); });
    child.on('close', code => {
      clearTimeout(timer);
      if (code !== 0) return reject(new Error(`probe.ps1 exited ${code}: ${stderr}`));
      try {
        const trimmed = stdout.trim();
        if (!trimmed) return reject(new Error('probe.ps1 produced empty output'));
        resolve(JSON.parse(trimmed));
      } catch (e) {
        reject(new Error(`probe.ps1 produced invalid JSON: ${e.message}\n${stdout.slice(0,500)}`));
      }
    });
  });
}

module.exports = { probe };
