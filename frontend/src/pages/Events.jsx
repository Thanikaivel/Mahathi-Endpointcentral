import React, { useEffect, useState } from 'react';
import { api } from '../api/client.js';
import { fmtDateTime, Spinner, ErrorBox, EventBadge } from '../components/Helpers.jsx';

const TYPES = ['', 'Logon','Logoff','Lock','Unlock','Shutdown','Startup','SessionStart','SessionEnd','IdleStart','IdleEnd'];

export default function Events() {
  const [rows, setRows] = useState(null);
  const [error, setError] = useState(null);
  const [type, setType] = useState('');
  const [limit, setLimit] = useState(200);

  function load() {
    setRows(null);
    api.events(limit, type).then(setRows).catch(setError);
  }
  useEffect(() => { load(); /* eslint-disable-next-line */ }, [type, limit]);

  return (
    <>
      <h1 className="page-title">Event Stream</h1>
      <div className="toolbar">
        <label className="muted">Type:</label>
        <select className="search" value={type} onChange={e => setType(e.target.value)}>
          {TYPES.map(t => <option key={t} value={t}>{t || 'All'}</option>)}
        </select>
        <label className="muted">Limit:</label>
        <select className="search" value={limit} onChange={e => setLimit(parseInt(e.target.value,10))}>
          {[100,200,500,1000].map(n => <option key={n} value={n}>{n}</option>)}
        </select>
        <button className="btn ghost" onClick={load}>Refresh</button>
      </div>
      <ErrorBox error={error} />
      {!rows && !error && <Spinner />}
      {rows && (
        <div className="panel">
          <table>
            <thead><tr><th>Time</th><th>Event</th><th>Machine</th><th>User</th><th>Details</th></tr></thead>
            <tbody>
              {rows.map(e => (
                <tr key={e.EventId}>
                  <td>{fmtDateTime(e.EventTimeUtc)}</td>
                  <td><EventBadge type={e.EventType} /></td>
                  <td>{e.MachineName}</td>
                  <td>{e.UserName ? `${e.Domain ? e.Domain+'\\':''}${e.UserName}` : '—'}</td>
                  <td className="muted">{e.Details || ''}</td>
                </tr>
              ))}
              {rows.length === 0 && <tr><td colSpan={5} className="muted">No events.</td></tr>}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
