import React, { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { api } from '../api/client.js';
import { fmtDateTime, fmtDuration, Spinner, ErrorBox, EventBadge } from '../components/Helpers.jsx';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from 'recharts';

export default function MachineDetail() {
  const { id } = useParams();
  const [data, setData] = useState(null);
  const [sessions, setSessions] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    api.machine(id).then(setData).catch(setError);
    api.machineSessions(id, 50).then(setSessions).catch(setError);
  }, [id]);

  if (error) return <><h1 className="page-title">Machine</h1><ErrorBox error={error} /></>;
  if (!data) return <><h1 className="page-title">Machine</h1><Spinner /></>;

  const { machine, recentEvents, topApps } = data;
  const chartData = topApps.map(a => ({ name: a.AppName, mins: Math.round(a.ForegroundSeconds/60) }));

  return (
    <>
      <h1 className="page-title">{machine.MachineName}</h1>
      <div className="cards">
        <div className="card"><div className="label">Domain</div><div className="value" style={{fontSize:18}}>{machine.Domain || '—'}</div></div>
        <div className="card"><div className="label">OS</div><div className="value" style={{fontSize:14}}>{machine.OSVersion || '—'}</div></div>
        <div className="card"><div className="label">IP</div><div className="value" style={{fontSize:18}}>{machine.IPAddress || '—'}</div></div>
        <div className="card"><div className="label">Agent</div><div className="value" style={{fontSize:18}}>{machine.AgentVersion || '—'}</div></div>
        <div className="card"><div className="label">First seen</div><div className="value" style={{fontSize:14}}>{fmtDateTime(machine.FirstSeenUtc)}</div></div>
        <div className="card"><div className="label">Last seen</div><div className="value" style={{fontSize:14}}>{fmtDateTime(machine.LastSeenUtc)}</div></div>
      </div>

      <div className="panel">
        <h2>Top Applications (foreground time, all sessions)</h2>
        {chartData.length === 0 ? <p className="muted">No application data yet.</p> : (
          <ResponsiveContainer width="100%" height={300}>
            <BarChart data={chartData}>
              <CartesianGrid stroke="#0b1220" />
              <XAxis dataKey="name" stroke="#94a3b8" tick={{ fontSize: 11 }} interval={0} angle={-25} textAnchor="end" height={70} />
              <YAxis stroke="#94a3b8" label={{ value: 'minutes', angle: -90, fill: '#94a3b8', position: 'insideLeft' }} />
              <Tooltip contentStyle={{ background: '#1e293b', border: '1px solid #0b1220' }} />
              <Bar dataKey="mins" fill="#38bdf8" />
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>

      <div className="panel">
        <h2>Recent Sessions</h2>
        {!sessions ? <Spinner /> : (
          <table>
            <thead><tr><th>User</th><th>Logon</th><th>Logoff</th><th>Duration</th><th>Active</th><th>Idle</th><th>Locks</th><th>End</th><th></th></tr></thead>
            <tbody>
              {sessions.map(s => (
                <tr key={s.SessionId}>
                  <td>{s.Domain ? `${s.Domain}\\` : ''}{s.UserName}</td>
                  <td>{fmtDateTime(s.LogonTimeUtc)}</td>
                  <td>{s.LogoffTimeUtc ? fmtDateTime(s.LogoffTimeUtc) : <span className="badge green">Active</span>}</td>
                  <td>{fmtDuration(s.DurationSeconds)}</td>
                  <td>{fmtDuration(s.ActiveSeconds)}</td>
                  <td>{fmtDuration(s.IdleSeconds)}</td>
                  <td>{s.LockCount}</td>
                  <td>{s.EndReason || '—'}</td>
                  <td><Link to={`/sessions/${s.SessionId}`}>view</Link></td>
                </tr>
              ))}
              {sessions.length === 0 && <tr><td colSpan={9} className="muted">No sessions yet.</td></tr>}
            </tbody>
          </table>
        )}
      </div>

      <div className="panel">
        <h2>Recent Events</h2>
        <table>
          <thead><tr><th>Time</th><th>Event</th><th>User</th><th>Details</th></tr></thead>
          <tbody>
            {recentEvents.map((e, i) => (
              <tr key={i}>
                <td>{fmtDateTime(e.EventTimeUtc)}</td>
                <td><EventBadge type={e.EventType} /></td>
                <td>{e.UserName || '—'}</td>
                <td className="muted">{e.Details || ''}</td>
              </tr>
            ))}
            {recentEvents.length === 0 && <tr><td colSpan={4} className="muted">No events yet.</td></tr>}
          </tbody>
        </table>
      </div>
    </>
  );
}
