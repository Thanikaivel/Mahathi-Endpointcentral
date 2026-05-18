import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { api } from '../api/client.js';
import { Spinner, ErrorBox } from '../components/Helpers.jsx';

// --- formatters mirrored from the Users Dashboard ----------------------------
function fmtDate(v) {
  if (!v) return '—';
  try {
    const d = new Date(v);
    return `${d.getMonth() + 1}/${d.getDate()}/${d.getFullYear()}`;
  } catch { return String(v); }
}
function fmtTime(v) {
  if (!v) return '—';
  try {
    return new Date(v).toLocaleTimeString([], {
      hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: true
    });
  } catch { return String(v); }
}
function fmtDateTime(v) {
  if (!v) return '—';
  return `${fmtDate(v)} ${fmtTime(v)}`;
}
function fmtHM(seconds) {
  if (seconds == null || isNaN(seconds)) return '—';
  const s = Math.max(0, Math.floor(seconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  return `${String(h).padStart(2, '0')}h ${String(m).padStart(2, '0')}m`;
}
function todayIso() {
  const d = new Date();
  const z = d.getTimezoneOffset() * 60000;
  return new Date(d - z).toISOString().slice(0, 10);
}
function daysAgoIso(n) {
  const d = new Date(Date.now() - n * 86400000);
  const z = d.getTimezoneOffset() * 60000;
  return new Date(d - z).toISOString().slice(0, 10);
}

// Sortable column header
function Th({ label, col, sort, setSort }) {
  const active = sort.col === col;
  const arrow  = !active ? '' : sort.dir === 'asc' ? ' ▲' : ' ▼';
  return (
    <th
      style={{ cursor: 'pointer', userSelect: 'none' }}
      onClick={() =>
        setSort(s =>
          s.col === col
            ? { col, dir: s.dir === 'asc' ? 'desc' : 'asc' }
            : { col, dir: col === 'AppName' || col === 'MachineName' || col === 'UserName' ? 'asc' : 'desc' }
        )
      }
    >
      {label}{arrow}
    </th>
  );
}

export default function TopApps() {
  const [rows, setRows]   = useState(null);
  const [error, setError] = useState(null);
  const [start, setStart] = useState(daysAgoIso(7));
  const [end,   setEnd]   = useState(todayIso());
  const [q,     setQ]     = useState('');
  const [sort,  setSort]  = useState({ col: 'ForegroundSeconds', dir: 'desc' });

  const load = useCallback(() => {
    setRows(null); setError(null);
    api.appsList({ start, end, q }).then(setRows).catch(setError);
  }, [start, end, q]);

  useEffect(() => { load(); }, [load]);

  function clearFilter() { setQ(''); }
  function clearAll()    { setQ(''); setStart(daysAgoIso(7)); setEnd(todayIso()); }

  const sortedRows = useMemo(() => {
    if (!rows) return null;
    const dir = sort.dir === 'asc' ? 1 : -1;
    const col = sort.col;
    return [...rows].sort((a, b) => {
      const av = a[col]; const bv = b[col];
      if (av == null && bv == null) return 0;
      if (av == null) return 1;
      if (bv == null) return -1;
      if (typeof av === 'number' && typeof bv === 'number') return (av - bv) * dir;
      return String(av).localeCompare(String(bv)) * dir;
    });
  }, [rows, sort]);

  function exportCsv() {
    if (!sortedRows) return;
    const header = ['App', 'User', 'Domain', 'Computer', 'First Seen', 'Last Seen', 'Foreground (s)', 'Background (s)', 'Launches'];
    const esc = v => `"${String(v ?? '').replace(/"/g, '""')}"`;
    const lines = sortedRows.map(r => [
      esc(r.AppName), esc(r.UserName), esc(r.Domain || ''), esc(r.MachineName),
      r.FirstSeenUtc, r.LastSeenUtc,
      r.ForegroundSeconds, r.RunningSeconds, r.LaunchCount
    ].join(','));
    const csv = [header.join(','), ...lines].join('\n');
    const blob = new Blob([csv], { type: 'text/csv' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `apps-${start}_to_${end}.csv`;
    a.click();
  }

  return (
    <>
      <h1 className="page-title">Application Usage</h1>

      <div className="toolbar">
        <label className="muted">Start date:</label>
        <input type="date" className="search" style={{ width: 160 }}
               value={start} onChange={e => setStart(e.target.value)} />
        <label className="muted">End date:</label>
        <input type="date" className="search" style={{ width: 160 }}
               value={end} onChange={e => setEnd(e.target.value)} />
        <label className="muted">Filter:</label>
        <input className="search" placeholder="filter by app/user/computer"
               value={q}
               onChange={e => setQ(e.target.value)}
               onKeyDown={e => e.key === 'Enter' && load()} />
        <button className="btn ghost" onClick={clearFilter}>Clear filter</button>
        <button className="btn ghost" onClick={clearAll}>Clear</button>
        <button className="btn" onClick={exportCsv} disabled={!sortedRows || sortedRows.length === 0}>Export CSV</button>
      </div>

      <ErrorBox error={error} />
      {!rows && !error && <Spinner />}

      {sortedRows && (
        <div className="panel">
          <div style={{ marginBottom: 8 }} className="muted">
            {sortedRows.length} application row(s) — click any column header to sort.
          </div>
          <table>
            <thead>
              <tr>
                <Th label="Application" col="AppName"        sort={sort} setSort={setSort} />
                <Th label="User"        col="UserName"       sort={sort} setSort={setSort} />
                <Th label="Computer"    col="MachineName"    sort={sort} setSort={setSort} />
                <Th label="First Seen"  col="FirstSeenUtc"   sort={sort} setSort={setSort} />
                <Th label="Last Seen"   col="LastSeenUtc"    sort={sort} setSort={setSort} />
                <Th label="Foreground"  col="ForegroundSeconds" sort={sort} setSort={setSort} />
                <Th label="Background"  col="RunningSeconds"    sort={sort} setSort={setSort} />
                <Th label="Launches"    col="LaunchCount"       sort={sort} setSort={setSort} />
              </tr>
            </thead>
            <tbody>
              {sortedRows.map((r, i) => (
                <tr key={`${r.AppName}|${r.MachineName}|${r.UserName}|${i}`}>
                  <td title={r.AppPath || ''}>{r.AppName}</td>
                  <td>{r.Domain ? `${r.Domain}\\` : ''}{r.UserName}</td>
                  <td>{r.MachineName}</td>
                  <td>{fmtDateTime(r.FirstSeenUtc)}</td>
                  <td>{fmtDateTime(r.LastSeenUtc)}</td>
                  <td>{fmtHM(r.ForegroundSeconds)}</td>
                  <td>{fmtHM(r.RunningSeconds)}</td>
                  <td>{r.LaunchCount}</td>
                </tr>
              ))}
              {sortedRows.length === 0 && (
                <tr><td colSpan={8} className="muted">No application activity in this date range.</td></tr>
              )}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
