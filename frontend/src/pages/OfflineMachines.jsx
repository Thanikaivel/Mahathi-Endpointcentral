import React, { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { api } from '../api/client.js';
import { fmtDateTime, Spinner, ErrorBox } from '../components/Helpers.jsx';

export default function OfflineMachines() {
  const { days } = useParams();   // route is /offline-machines/:days  (e.g. /offline-machines/3)
  const minDays = parseInt(days, 10) || 3;
  const [rows, setRows]   = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    setRows(null); setError(null);
    api.offlineMachines(minDays).then(setRows).catch(setError);
  }, [minDays]);

  return (
    <>
      <h1 className="page-title">Offline Machines ({minDays}+ days)</h1>

      <ErrorBox error={error} />
      {!rows && !error && <Spinner />}

      {rows && (
        <div className="panel">
          <div style={{ marginBottom: 8 }} className="muted">
            {rows.length} machine{rows.length === 1 ? '' : 's'} silent for {minDays}+ days
          </div>
          {rows.length === 0 ? (
            <p className="muted">No machines have been silent for {minDays}+ days. 🎉</p>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>Machine</th>
                  <th>Last User</th>
                  <th>Domain</th>
                  <th>OS</th>
                  <th>IP</th>
                  <th>Agent</th>
                  <th>Last Seen</th>
                  <th>Days Silent</th>
                </tr>
              </thead>
              <tbody>
                {rows.map(m => (
                  <tr key={m.MachineId}>
                    <td><Link to={`/machines/${m.MachineId}`}>{m.MachineName}</Link></td>
                    <td>
                      {m.LastUser
                        ? (m.LastUserDomain ? `${m.LastUserDomain}\\` : '') + m.LastUser
                        : '—'}
                    </td>
                    <td>{m.Domain || '—'}</td>
                    <td>{m.OSVersion || '—'}</td>
                    <td>{m.IPAddress || '—'}</td>
                    <td>{m.AgentVersion || '—'}</td>
                    <td>{fmtDateTime(m.LastSeenUtc)}</td>
                    <td>
                      <span style={{
                        padding: '2px 8px',
                        borderRadius: 12,
                        fontSize: 12,
                        fontWeight: 600,
                        background: m.DaysSilent >= 7 ? '#5a1d1d' : '#5a4a1d',
                        color:      m.DaysSilent >= 7 ? '#ff8a8a' : '#e7c97e'
                      }}>
                        {m.DaysSilent}
                      </span>
                    </td>
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
