import React, { useEffect, useState, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../api/client.js';
import { fmtDateTime, Spinner, ErrorBox } from '../components/Helpers.jsx';
import Pagination from '../components/Pagination.jsx';

export default function Machines() {
  const [rows, setRows]         = useState(null);
  const [total, setTotal]       = useState(0);
  const [page, setPage]         = useState(1);
  const [pageSize, setPageSize] = useState(50);
  const [error, setError]       = useState(null);
  const [search, setSearch]     = useState('');
  const [activeQuery, setActiveQuery] = useState('');

  const load = useCallback(() => {
    setRows(null);
    api.machines({ q: activeQuery, page, pageSize })
      .then(r => { setRows(r.rows || []); setTotal(r.total || 0); })
      .catch(setError);
  }, [activeQuery, page, pageSize]);

  useEffect(() => { load(); }, [load]);
  // Reset to page 1 whenever the search or pageSize changes
  useEffect(() => { setPage(1); }, [activeQuery, pageSize]);

  function runSearch() { setActiveQuery(search); }

  function onlineBadge(lastSeen) {
    const ms = Date.now() - new Date(lastSeen).getTime();
    if (ms < 15*60*1000) return <span className="badge green">Online</span>;
    if (ms < 24*60*60*1000) return <span className="badge amber">Idle</span>;
    return <span className="badge gray">Offline</span>;
  }

  return (
    <>
      <h1 className="page-title">Machines</h1>
      <div className="toolbar">
        <input className="search" placeholder="Search machine name..." value={search}
               onChange={e => setSearch(e.target.value)}
               onKeyDown={e => e.key === 'Enter' && runSearch()} />
        <button className="btn" onClick={runSearch}>Search</button>
      </div>
      <ErrorBox error={error} />
      {!rows && !error && <Spinner />}
      {rows && (
        <div className="panel">
          <table>
            <thead>
              <tr>
                <th>Status</th><th>Name</th><th>User</th><th>OS</th>
                <th>IP</th><th>Sessions</th><th>Active</th><th>Last seen</th>
              </tr>
            </thead>
            <tbody>
              {rows.map(m => (
                <tr key={m.MachineId}>
                  <td>{onlineBadge(m.LastSeenUtc)}</td>
                  <td><Link to={`/machines/${m.MachineId}`}>{m.MachineName}</Link></td>
                  <td>
                    {m.LatestUserName
                      ? `${m.LatestUserDomain ? m.LatestUserDomain + '\\' : ''}${m.LatestUserName}`
                      : '—'}
                  </td>
                  <td>{m.OSVersion || '—'}</td>
                  <td>{m.IPAddress || '—'}</td>
                  <td>{m.SessionCount}</td>
                  <td>{m.ActiveSessionCount > 0 ? <span className="badge green">{m.ActiveSessionCount}</span> : '0'}</td>
                  <td>{fmtDateTime(m.LastSeenUtc)}</td>
                </tr>
              ))}
              {rows.length === 0 && <tr><td colSpan={8} className="muted">No machines found.</td></tr>}
            </tbody>
          </table>
          <Pagination total={total} page={page} pageSize={pageSize}
                      onPageChange={setPage} onPageSizeChange={setPageSize} />
        </div>
      )}
    </>
  );
}
