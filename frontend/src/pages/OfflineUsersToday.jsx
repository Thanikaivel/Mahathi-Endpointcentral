import React, { useEffect, useState } from 'react';
import { api } from '../api/client.js';
import { fmtDateTime, Spinner, ErrorBox } from '../components/Helpers.jsx';

function fmtHoursAgo(hours) {
  if (hours == null || isNaN(hours)) return '—';
  if (hours < 24) return `${hours}h ago`;
  const d = Math.floor(hours / 24);
  const h = hours % 24;
  return `${d}d ${h}h ago`;
}

export default function OfflineUsersToday() {
  const [rows, setRows]   = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    setRows(null); setError(null);
    api.offlineUsersToday().then(setRows).catch(setError);
  }, []);

  return (
    <>
      <h1 className="page-title">Offline Users Today</h1>

      <ErrorBox error={error} />
      {!rows && !error && <Spinner />}

      {rows && (
        <div className="panel">
          <div style={{ marginBottom: 8 }} className="muted">
            {rows.length} user{rows.length === 1 ? '' : 's'} who were active in the last 7 days but have not signed in today
          </div>
          {rows.length === 0 ? (
            <p className="muted">All recent users have signed in today. 🎉</p>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>User</th>
                  <th>Domain</th>
                  <th>Last Login</th>
                  <th>Last Machine</th>
                  <th>Since</th>
                </tr>
              </thead>
              <tbody>
                {rows.map(u => (
                  <tr key={u.UserId}>
                    <td>{u.UserName}{u.DisplayName ? <span className="muted" style={{ marginLeft: 8 }}>({u.DisplayName})</span> : null}</td>
                    <td>{u.Domain || '—'}</td>
                    <td>{fmtDateTime(u.LastLogonUtc)}</td>
                    <td>{u.LastMachine || '—'}</td>
                    <td>{fmtHoursAgo(u.HoursSinceLastLogon)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}
    </>
  );
}
