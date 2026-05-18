import React, { useEffect, useState } from 'react';
import { api } from '../api/client.js';
import { fmtDuration, Spinner, ErrorBox } from '../components/Helpers.jsx';

export default function Reports() {
  const [rows, setRows] = useState(null);
  const [error, setError] = useState(null);
  const [days, setDays] = useState(14);

  useEffect(() => {
    setRows(null);
    api.daily(days).then(setRows).catch(setError);
  }, [days]);

  function exportCsv() {
    if (!rows) return;
    const header = ['Day','Machine','Sessions','Total','Active','Idle'];
    const lines = rows.map(r => [
      new Date(r.Day).toISOString().slice(0,10),
      r.MachineName, r.Sessions, r.TotalSeconds, r.ActiveSeconds, r.IdleSeconds
    ].join(','));
    const csv = [header.join(','), ...lines].join('\n');
    const blob = new Blob([csv], { type: 'text/csv' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `daily-report-${days}d.csv`;
    a.click();
  }

  return (
    <>
      <h1 className="page-title">Daily Reports</h1>
      <div className="toolbar">
        <label className="muted">Window:</label>
        <select className="search" value={days} onChange={e => setDays(parseInt(e.target.value,10))}>
          {[7,14,30,60,90].map(n => <option key={n} value={n}>Last {n} day(s)</option>)}
        </select>
        <button className="btn" onClick={exportCsv} disabled={!rows}>Export CSV</button>
      </div>
      <ErrorBox error={error} />
      {!rows && !error && <Spinner />}
      {rows && (
        <div className="panel">
          <table>
            <thead><tr><th>Day</th><th>Machine</th><th>Sessions</th><th>Total</th><th>Active</th><th>Idle</th></tr></thead>
            <tbody>
              {rows.map((r, i) => (
                <tr key={i}>
                  <td>{new Date(r.Day).toISOString().slice(0,10)}</td>
                  <td>{r.MachineName}</td>
                  <td>{r.Sessions}</td>
                  <td>{fmtDuration(r.TotalSeconds)}</td>
                  <td>{fmtDuration(r.ActiveSeconds)}</td>
                  <td>{fmtDuration(r.IdleSeconds)}</td>
                </tr>
              ))}
              {rows.length === 0 && <tr><td colSpan={6} className="muted">No data in this window.</td></tr>}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
