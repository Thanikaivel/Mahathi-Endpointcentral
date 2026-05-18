import React, { useEffect, useState, useCallback } from 'react';
import { api } from '../api/client.js';
import { Spinner, ErrorBox } from '../components/Helpers.jsx';

// "08:58:19 AM" style
function fmtTime(v) {
  if (!v) return '—';
  try {
    return new Date(v).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: true });
  } catch { return String(v); }
}
// "5/5/2026"
function fmtDate(v) {
  if (!v) return '—';
  try {
    const d = new Date(v);
    return `${d.getMonth() + 1}/${d.getDate()}/${d.getFullYear()}`;
  } catch { return String(v); }
}
// "01h 31m"
function fmtActiveHours(seconds) {
  if (seconds == null || isNaN(seconds)) return '—';
  const s = Math.max(0, Math.floor(seconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  return `${String(h).padStart(2, '0')}h ${String(m).padStart(2, '0')}m`;
}
// today as yyyy-mm-dd in local time
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

export default function Users() {
  const [rows, setRows]   = useState(null);
  const [error, setError] = useState(null);
  const [start, setStart] = useState(todayIso());
  const [end,   setEnd]   = useState(todayIso());
  const [q,     setQ]     = useState('');

  const load = useCallback(() => {
    setRows(null); setError(null);
    api.usersDaily({ start, end, q }).then(setRows).catch(setError);
  }, [start, end, q]);

  useEffect(() => { load(); }, [load]);

  function clearFilter() { setQ(''); }
  function clearAll()    { setQ(''); setStart(todayIso()); setEnd(todayIso()); }

  return (
    <>
      <h1 className="page-title">Users Dashboard</h1>

      <div className="toolbar">
        <label className="muted">Start date:</label>
        <input type="date" className="search" style={{ width: 160 }}
               value={start} onChange={e => setStart(e.target.value)} />
        <label className="muted">End date:</label>
        <input type="date" className="search" style={{ width: 160 }}
               value={end} onChange={e => setEnd(e.target.value)} />
        <label className="muted">Filter:</label>
        <input className="search" placeholder="filter by user/computer/login"
               value={q}
               onChange={e => setQ(e.target.value)}
               onKeyDown={e => e.key === 'Enter' && load()} />
        <button className="btn ghost" onClick={clearFilter}>Clear filter</button>
        <button className="btn ghost" onClick={clearAll}>Clear</button>
      </div>

      <ErrorBox error={error} />
      {!rows && !error && <Spinner />}

      {rows && (
        <div className="panel">
          <table>
            <thead>
              <tr>
                <th>Date</th>
                <th>Computer</th>
                <th>User</th>
                <th>First Login</th>
                <th>Last Lock</th>
                <th>Last Unlock</th>
                <th>Active Hours</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r, i) => (
                <tr key={`${r.Date}-${r.MachineName}-${r.UserName}-${i}`}>
                  <td>{fmtDate(r.Date)}</td>
                  <td>{r.MachineName}</td>
                  <td>{r.UserName}</td>
                  <td>{fmtTime(r.FirstLogin)}</td>
                  <td>{fmtTime(r.LastLock)}</td>
                  <td>{fmtTime(r.LastUnlock)}</td>
                  <td>{fmtActiveHours(r.ActiveSeconds)}</td>
                </tr>
              ))}
              {rows.length === 0 && (
                <tr><td colSpan={7} className="muted">No activity in this date range.</td></tr>
              )}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
