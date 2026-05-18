import React, { useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import { api } from '../api/client.js';
import { fmtDateTime, fmtDuration, Spinner, ErrorBox, EventBadge } from '../components/Helpers.jsx';

export default function SessionDetail() {
  const { id } = useParams();
  const [data, setData] = useState(null);
  const [error, setError] = useState(null);
  useEffect(() => { api.session(id).then(setData).catch(setError); }, [id]);

  if (error) return <><h1 className="page-title">Session</h1><ErrorBox error={error} /></>;
  if (!data) return <><h1 className="page-title">Session</h1><Spinner /></>;

  const { session, events, apps } = data;
  return (
    <>
      <h1 className="page-title">Session #{session.SessionId} — {session.MachineName}</h1>
      <div className="cards">
        <div className="card"><div className="label">User</div><div className="value" style={{fontSize:18}}>{session.Domain ? `${session.Domain}\\`:''}{session.UserName}</div></div>
        <div className="card"><div className="label">Logon</div><div className="value" style={{fontSize:14}}>{fmtDateTime(session.LogonTimeUtc)}</div></div>
        <div className="card"><div className="label">Logoff</div><div className="value" style={{fontSize:14}}>{session.LogoffTimeUtc ? fmtDateTime(session.LogoffTimeUtc) : 'Active'}</div></div>
        <div className="card"><div className="label">Duration</div><div className="value">{fmtDuration(session.DurationSeconds)}</div></div>
        <div className="card green"><div className="label">Active</div><div className="value">{fmtDuration(session.ActiveSeconds)}</div></div>
        <div className="card amber"><div className="label">Idle</div><div className="value">{fmtDuration(session.IdleSeconds)}</div></div>
        <div className="card"><div className="label">Locks</div><div className="value">{session.LockCount}</div></div>
        <div className="card"><div className="label">End</div><div className="value" style={{fontSize:18}}>{session.EndReason || '—'}</div></div>
      </div>

      <div className="panel">
        <h2>Events in session</h2>
        <table>
          <thead><tr><th>Time</th><th>Event</th><th>Details</th></tr></thead>
          <tbody>
            {events.map((e, i) => (
              <tr key={i}>
                <td>{fmtDateTime(e.EventTimeUtc)}</td>
                <td><EventBadge type={e.EventType} /></td>
                <td className="muted">{e.Details || ''}</td>
              </tr>
            ))}
            {events.length === 0 && <tr><td colSpan={3} className="muted">No events.</td></tr>}
          </tbody>
        </table>
      </div>

      <div className="panel">
        <h2>Application usage</h2>
        <table>
          <thead><tr><th>App</th><th>Foreground</th><th>Background</th><th>Launches</th><th>First</th><th>Last</th></tr></thead>
          <tbody>
            {apps.map(a => (
              <tr key={a.AppName}>
                <td>{a.AppName}</td>
                <td>{fmtDuration(a.ForegroundSeconds)}</td>
                <td>{fmtDuration(a.RunningSeconds)}</td>
                <td>{a.LaunchCount}</td>
                <td>{fmtDateTime(a.FirstSeenUtc)}</td>
                <td>{fmtDateTime(a.LastSeenUtc)}</td>
              </tr>
            ))}
            {apps.length === 0 && <tr><td colSpan={6} className="muted">No app usage.</td></tr>}
          </tbody>
        </table>
      </div>
    </>
  );
}
