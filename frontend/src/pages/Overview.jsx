import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../api/client.js';
import { fmtDateTime, fmtDuration, Spinner, ErrorBox } from '../components/Helpers.jsx';

export default function Overview() {
  const [data, setData] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    let mounted = true;
    api.overview().then(d => mounted && setData(d)).catch(e => mounted && setError(e));
    const t = setInterval(() => api.overview().then(d => mounted && setData(d)).catch(()=>{}), 30000);
    return () => { mounted = false; clearInterval(t); };
  }, []);

  if (error) return <><h1 className="page-title">Overview</h1><ErrorBox error={error} /></>;
  if (!data) return <><h1 className="page-title">Overview</h1><Spinner /></>;

  const { stats, recentMachines, activeSessions } = data;
  return (
    <>
      <h1 className="page-title">Overview</h1>
      <div className="cards">
        <div className="card"><div className="label">Total Machines</div><div className="value">{stats.TotalMachines}</div></div>
        <div className="card green"><div className="label">Online (15 min)</div><div className="value">{stats.OnlineMachines}</div></div>
        <div className="card amber"><div className="label">Active Sessions</div><div className="value">{stats.ActiveSessions}</div></div>
        <div className="card">
          <div className="label">Offline (3+ days)</div>
          <div className="value">{stats.OfflineLast3Days?.toLocaleString() ?? '—'}</div>
          <div className="muted" style={{ fontSize: 11, marginTop: 4 }}>
            machines silent for 3+ days
          </div>
        </div>
        <div className="card">
          <div className="label">Offline (7+ days)</div>
          <div className="value">{stats.OfflineLast7Days?.toLocaleString() ?? '—'}</div>
          <div className="muted" style={{ fontSize: 11, marginTop: 4 }}>
            machines silent for 7+ days
          </div>
        </div>
      </div>

      <div className="panel">
        <h2>Active Sessions</h2>
        {activeSessions.length === 0 && <p className="muted">No active sessions right now.</p>}
        {activeSessions.length > 0 && (
          <table>
            <thead><tr><th>Machine</th><th>User</th><th>Logon</th><th>Live duration</th><th>Idle</th><th>Active</th><th>Locks</th><th>Status</th></tr></thead>
            <tbody>
              {activeSessions.map(s => (
                <tr key={s.SessionId}>
                  <td><Link to={`/sessions/${s.SessionId}`}>{s.MachineName}</Link></td>
                  <td>{s.Domain ? `${s.Domain}\\` : ''}{s.UserName}</td>
                  <td>{fmtDateTime(s.LogonTimeUtc)}</td>
                  <td>{fmtDuration(s.LiveDurationSeconds)}</td>
                  <td>{fmtDuration(s.IdleSeconds)}</td>
                  <td>{fmtDuration(s.ActiveSeconds)}</td>
                  <td>{s.LockCount}</td>
                  <td>
                    <span style={{
                      padding: '2px 8px',
                      borderRadius: '12px',
                      fontSize: '12px',
                      fontWeight: 600,
                      background: s.IsLocked ? '#5a1d1d' : '#1d5a2c',
                      color: s.IsLocked ? '#ff8a8a' : '#7ee7a3'
                    }}>
                      {s.IsLocked ? 'Locked' : 'Working'}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="panel">
        <h2>Recently Seen Machines</h2>
        <table>
          <thead><tr><th>Machine</th><th>OS</th><th>Agent</th><th>Last seen</th></tr></thead>
          <tbody>
            {recentMachines.map(m => (
              <tr key={m.MachineName}>
                <td>{m.MachineName}</td>
                <td>{m.OSVersion || '—'}</td>
                <td>{m.AgentVersion || '—'}</td>
                <td>{fmtDateTime(m.LastSeenUtc)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
