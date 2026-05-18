import React from 'react';

export function fmtDateTime(v) {
  if (!v) return '—';
  try {
    const d = new Date(v);
    return d.toLocaleString();
  } catch { return String(v); }
}

export function fmtDuration(seconds) {
  if (seconds == null || isNaN(seconds)) return '—';
  const s = Math.max(0, Math.floor(seconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${sec}s`;
  return `${sec}s`;
}

export function Spinner() { return <div className="spinner" />; }

export function ErrorBox({ error }) {
  if (!error) return null;
  return (
    <div className="panel" style={{ borderColor: '#7f1d1d', color: '#fecaca' }}>
      <strong>Error:</strong> {String(error.message || error)}
    </div>
  );
}

const EVENT_COLORS = {
  Logon: 'green', Logoff: 'gray', Lock: 'amber', Unlock: 'green',
  Shutdown: 'red', Startup: 'green', SessionStart: 'green', SessionEnd: 'gray',
  IdleStart: 'amber', IdleEnd: 'green'
};
export function EventBadge({ type }) {
  const cls = EVENT_COLORS[type] || 'gray';
  return <span className={`badge ${cls}`}>{type}</span>;
}
