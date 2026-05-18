'use strict';

/**
 * Session state machine driven by snapshots from winApi.probe().
 * Emits structured events:
 *   - sessionStart, sessionEnd
 *   - logon, logoff, lock, unlock
 *   - idleStart, idleEnd
 * Tracks per-session active vs idle seconds and per-app foreground time.
 */
const { v4: uuidv4 } = require('uuid');

class StateMachine {
  constructor({ idleThresholdSeconds = 120, pollIntervalSeconds = 5, endSessionAfterIdleSeconds = 3600 } = {}) {
    this.idleThreshold = idleThresholdSeconds;
    this.pollInterval = pollIntervalSeconds;
    // After this many seconds of continuous user idleness (per OS LastInputTime),
    // automatically end the current session. Set to 0 to disable.
    this.endSessionAfterIdle = endSessionAfterIdleSeconds;

    this.session = null;            // current session record
    this.lastSnapshot = null;
    this.lastForegroundApp = null;
    this.lastForegroundChangeAt = null;

    // Outputs awaiting flush to disk
    this.pendingEvents = [];
    this.pendingSessions = [];      // updated session snapshots
    this.pendingAppUsage = new Map(); // key clientSessionId|appName -> AppUsageDelta

    // Running app last-seen times (for delta accounting)
    this.runningAppFirstSeen = new Map(); // appName -> ISO timestamp
    this.runningAppLastSeen  = new Map(); // appName -> ISO timestamp
  }

  emit(type, details = null, opts = {}) {
    const evt = {
      clientEventId: uuidv4(),
      eventType: type,
      eventTimeUtc: opts.eventTimeUtc || new Date().toISOString(),
      userName: this.session ? this.session.userName : null,
      domain:   this.session ? this.session.domain   : null,
      details
    };
    this.pendingEvents.push(evt);
  }

  startSession({ userName, domain, machineName, eventTimeUtc }) {
    if (this.session) this.endSession({ reason: 'Replaced', eventTimeUtc });
    this.session = {
      clientSessionId: uuidv4(),
      userName, domain, machineName,
      logonTimeUtc: eventTimeUtc || new Date().toISOString(),
      logoffTimeUtc: null,
      idleSeconds: 0,
      activeSeconds: 0,
      lockCount: 0,
      isLocked: false,
      isIdle: false,
      endReason: null
    };
    this.emit('Logon', `User ${domain ? domain+'\\' : ''}${userName} logged on`, { eventTimeUtc });
    this.emit('SessionStart', null, { eventTimeUtc });
    this.flushSession();
  }

  endSession({ reason = 'Logoff', eventTimeUtc } = {}) {
    if (!this.session) return;
    this.session.logoffTimeUtc = eventTimeUtc || new Date().toISOString();
    this.session.endReason = reason;
    if (reason === 'Shutdown') this.emit('Shutdown', null, { eventTimeUtc });
    this.emit(reason === 'Shutdown' ? 'SessionEnd' : 'Logoff', null, { eventTimeUtc });
    this.flushSession();
    this.session = null;
    this.lastForegroundApp = null;
    this.lastForegroundChangeAt = null;
  }

  flushSession() {
    if (!this.session) return;
    // We replace any earlier pending update for this session (last-write-wins)
    this.pendingSessions = this.pendingSessions.filter(
      s => s.clientSessionId !== this.session.clientSessionId
    );
    this.pendingSessions.push({
      clientSessionId: this.session.clientSessionId,
      userName: this.session.userName,
      domain: this.session.domain,
      logonTimeUtc: this.session.logonTimeUtc,
      logoffTimeUtc: this.session.logoffTimeUtc,
      idleSeconds: this.session.idleSeconds,
      activeSeconds: this.session.activeSeconds,
      lockCount: this.session.lockCount,
      isLocked: !!this.session.isLocked,
      endReason: this.session.endReason
    });
  }

  addAppUsageDelta(appName, appPath, windowTitle, foregroundDelta, runningDelta, launchDelta = 0) {
    if (!this.session || !appName) return;
    const key = `${this.session.clientSessionId}|${appName}`;
    let rec = this.pendingAppUsage.get(key);
    const now = new Date().toISOString();
    if (!rec) {
      rec = {
        clientSessionId: this.session.clientSessionId,
        userName: this.session.userName,
        domain: this.session.domain,
        appName,
        appPath: appPath || null,
        windowTitleSample: windowTitle || null,
        firstSeenUtc: this.runningAppFirstSeen.get(appName) || now,
        lastSeenUtc: now,
        foregroundSeconds: 0,
        runningSeconds: 0,
        launchCount: 0
      };
      this.pendingAppUsage.set(key, rec);
    }
    rec.lastSeenUtc = now;
    if (windowTitle) rec.windowTitleSample = windowTitle;
    if (appPath && !rec.appPath) rec.appPath = appPath;
    rec.foregroundSeconds += Math.max(0, foregroundDelta);
    rec.runningSeconds    += Math.max(0, runningDelta);
    rec.launchCount       += Math.max(0, launchDelta);
  }

  /**
   * Process a single snapshot.
   */
  ingest(snapshot) {
    const nowIso = snapshot.timestampUtc || new Date().toISOString();

    // 1. Logon / logoff / user switch
    const haveUser = !!snapshot.activeUser;
    if (haveUser && !this.session) {
      this.startSession({
        userName: snapshot.activeUser,
        domain: snapshot.activeDomain,
        machineName: snapshot.machineName,
        eventTimeUtc: nowIso
      });
    } else if (!haveUser && this.session) {
      this.endSession({ reason: 'Logoff', eventTimeUtc: nowIso });
    } else if (haveUser && this.session &&
               (snapshot.activeUser !== this.session.userName ||
                snapshot.activeDomain !== this.session.domain)) {
      this.endSession({ reason: 'Logoff', eventTimeUtc: nowIso });
      this.startSession({
        userName: snapshot.activeUser,
        domain: snapshot.activeDomain,
        machineName: snapshot.machineName,
        eventTimeUtc: nowIso
      });
    }

    if (!this.session) {
      this.lastSnapshot = snapshot;
      return;
    }

    // 2. Lock / Unlock — flag a "needsImmediateSync" so the runner can flush
    // to the backend right away on state change, rather than waiting up to
    // syncIntervalSeconds (60s by default). Without this, the dashboard would
    // show stale "Working" for almost a minute after a screen lock.
    if (snapshot.locked && !this.session.isLocked) {
      this.session.isLocked = true;
      this.session.lockCount += 1;
      this.emit('Lock', null, { eventTimeUtc: nowIso });
      this.needsImmediateSync = true;
    } else if (!snapshot.locked && this.session.isLocked) {
      this.session.isLocked = false;
      this.emit('Unlock', null, { eventTimeUtc: nowIso });
      this.needsImmediateSync = true;
    }

    // 3. Idle / Active accounting
    const interval = this.pollInterval;
    const isIdle = snapshot.idleSeconds >= this.idleThreshold || snapshot.locked;
    if (isIdle) {
      this.session.idleSeconds += interval;
      if (!this.session.isIdle) {
        this.session.isIdle = true;
        this.emit('IdleStart', `idle=${snapshot.idleSeconds}s`, { eventTimeUtc: nowIso });
      }

      // 3b. Long-idle auto-close: if the user has been continuously idle for
      // longer than the configured threshold, end the session here. A new
      // session will start automatically on the next snapshot when the user
      // returns. This prevents "14h sessions" from accruing across overnight
      // sleeps / breaks / abandoned-but-not-logged-off machines.
      if (this.endSessionAfterIdle > 0 && snapshot.idleSeconds >= this.endSessionAfterIdle) {
        this.emit('IdleEnd', `auto-ending session after ${snapshot.idleSeconds}s idle`, { eventTimeUtc: nowIso });
        this.endSession({ reason: 'LongIdle', eventTimeUtc: nowIso });
        this.lastSnapshot = snapshot;
        return;
      }
    } else {
      this.session.activeSeconds += interval;
      if (this.session.isIdle) {
        this.session.isIdle = false;
        this.emit('IdleEnd', null, { eventTimeUtc: nowIso });
      }
    }

    // 4. Foreground app accounting
    const fg = snapshot.foreground || {};
    const fgName = fg.name && fg.name.trim() ? fg.name.trim() : null;
    if (fgName && !snapshot.locked) {
      const fgDelta = interval; // attribute the whole interval to current fg app
      this.addAppUsageDelta(fgName, fg.path || null, fg.title || null, fgDelta, 0,
        (this.lastForegroundApp !== fgName) ? 1 : 0);
      this.lastForegroundApp = fgName;
      this.lastForegroundChangeAt = nowIso;
    }

    // 5. Running apps
    if (Array.isArray(snapshot.processes)) {
      for (const p of snapshot.processes) {
        if (!p || !p.name) continue;
        if (!this.runningAppFirstSeen.has(p.name)) this.runningAppFirstSeen.set(p.name, nowIso);
        this.runningAppLastSeen.set(p.name, nowIso);
        // accumulate "running seconds" only for non-foreground processes (foreground already counted)
        if (p.name !== fgName) {
          this.addAppUsageDelta(p.name, p.path || null, null, 0, interval, 0);
        }
      }
    }

    // 6. Periodic session flush
    this.flushSession();
    this.lastSnapshot = snapshot;
  }

  /**
   * Returns and clears the pending output payload.
   */
  drain() {
    const events    = this.pendingEvents;
    const sessions  = this.pendingSessions;
    const appUsages = Array.from(this.pendingAppUsage.values());

    this.pendingEvents = [];
    this.pendingSessions = [];
    // Reset pending app usage but keep first-seen registry across flushes
    this.pendingAppUsage = new Map();
    return { events, sessions, appUsages };
  }
}

module.exports = { StateMachine };
