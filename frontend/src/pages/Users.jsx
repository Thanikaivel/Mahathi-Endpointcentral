import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../api/client.js';
import { Spinner, ErrorBox } from '../components/Helpers.jsx';
import Pagination from '../components/Pagination.jsx';

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
// Badge component for the Status column
function StatusBadge({ status }) {
  const colors = {
    Active:    { bg: '#1d5a2c', fg: '#7ee7a3' },  // green
    Locked:    { bg: '#5a4a1d', fg: '#e7c97e' },  // amber
    Shutdown:  { bg: '#5a1d1d', fg: '#ff8a8a' },  // red
    Restarted: { bg: '#1d3a5a', fg: '#7ec7ff' },  // blue
    Logoff:    { bg: '#3a3a3a', fg: '#c9d1d9' },  // gray
    Offline:   { bg: '#3a3a3a', fg: '#c9d1d9' },  // gray
    Idle:      { bg: '#5a4a1d', fg: '#e7c97e' },  // amber
  };
  const c = colors[status] || { bg: '#3a3a3a', fg: '#c9d1d9' };
  return (
    <span style={{
      padding: '2px 8px',
      borderRadius: '12px',
      fontSize: '12px',
      fontWeight: 600,
      background: c.bg,
      color: c.fg,
      whiteSpace: 'nowrap'
    }}>
      {status || '—'}
    </span>
  );
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

// Sortable table header
function Th({ label, col, sort, setSort, defaultDir = 'asc' }) {
  const active = sort.col === col;
  const arrow  = !active ? '' : sort.dir === 'asc' ? ' ▲' : ' ▼';
  return (
    <th
      style={{ cursor: 'pointer', userSelect: 'none' }}
      onClick={() =>
        setSort(s =>
          s.col === col
            ? { col, dir: s.dir === 'asc' ? 'desc' : 'asc' }
            : { col, dir: defaultDir }
        )
      }
    >
      {label}{arrow}
    </th>
  );
}

export default function Users() {
  const [rows, setRows]         = useState(null);
  const [total, setTotal]       = useState(0);
  const [page, setPage]         = useState(1);
  const [pageSize, setPageSize] = useState(50);
  const [error, setError]       = useState(null);
  const [start, setStart] = useState(todayIso());
  const [end,   setEnd]   = useState(todayIso());
  const [q,     setQ]     = useState('');
  const [sort,  setSort]  = useState({ col: 'FirstLogin', dir: 'asc' });

  const load = useCallback(() => {
    setRows(null); setError(null);
    api.usersDaily({ start, end, q, page, pageSize })
      .then(r => { setRows(r.rows || []); setTotal(r.total || 0); })
      .catch(setError);
  }, [start, end, q, page, pageSize]);

  useEffect(() => { load(); }, [load]);
  // Reset to page 1 whenever filters change
  useEffect(() => { setPage(1); }, [start, end, q, pageSize]);

  function clearFilter() { setQ(''); }
  function clearAll()    { setQ(''); setStart(todayIso()); setEnd(todayIso()); }

  const [exporting, setExporting] = useState(false);

  async function exportToExcel() {
    setExporting(true);
    try {
      // Fetch ALL matching rows (not just the current page) by requesting a big page.
      // 5000 is the server-side cap for usersDaily — adjust there if you need more.
      const all = await api.usersDaily({ start, end, q, page: 1, pageSize: 5000 });
      const rows = all.rows || [];
      if (rows.length === 0) {
        alert('No data to export for the selected filters.');
        return;
      }

      // Dynamic import keeps the xlsx library out of the initial bundle.
      const XLSX = await import('xlsx');

      // Reshape rows for export — make headers human-friendly and dates readable.
      const sheetData = rows.map(r => ({
        'Date':         r.Date ? new Date(r.Date).toISOString().slice(0, 10) : '',
        'Computer':     r.MachineName || '',
        'User':         (r.Domain ? r.Domain + '\\' : '') + (r.UserName || ''),
        'First Login':  r.FirstLogin ? new Date(r.FirstLogin).toLocaleString() : '',
        'Last Lock':    r.LastLock    ? new Date(r.LastLock).toLocaleString()    : '',
        'Last Unlock':  r.LastUnlock  ? new Date(r.LastUnlock).toLocaleString()  : '',
        'Last Seen':    r.MachineLastSeen ? new Date(r.MachineLastSeen).toLocaleString() : '',
        'Active Hours': fmtActiveHours(r.ActiveSeconds),
        'Active Seconds (raw)': r.ActiveSeconds || 0,
        'Status':       r.LastStatus || ''
      }));

      const ws = XLSX.utils.json_to_sheet(sheetData);
      // Set column widths so the file looks polished
      ws['!cols'] = [
        { wch: 12 }, // Date
        { wch: 14 }, // Computer
        { wch: 26 }, // User
        { wch: 22 }, // First Login
        { wch: 22 }, // Last Lock
        { wch: 22 }, // Last Unlock
        { wch: 22 }, // Last Seen
        { wch: 12 }, // Active Hours
        { wch: 14 }, // Active Seconds
        { wch: 12 }  // Status
      ];

      const wb = XLSX.utils.book_new();
      XLSX.utils.book_append_sheet(wb, ws, 'User Activity');

      const filename = `user-activity_${start}_to_${end}.xlsx`;
      XLSX.writeFile(wb, filename);
    } catch (e) {
      alert('Export failed: ' + (e.message || e));
    } finally {
      setExporting(false);
    }
  }

  // Apply client-side sorting
  const sortedRows = useMemo(() => {
    if (!rows) return null;
    const dir = sort.dir === 'asc' ? 1 : -1;
    const col = sort.col;

    // For time/date columns, sort by the raw ISO value; nulls last.
    const isTimeCol = ['FirstLogin', 'LastLock', 'LastUnlock', 'MachineLastSeen', 'Date'].includes(col);
    const isNumCol  = ['ActiveSeconds', 'TotalSeconds'].includes(col);

    const cmp = (a, b) => {
      const av = a[col];
      const bv = b[col];
      // null/undefined go last regardless of direction
      if (av == null && bv == null) return 0;
      if (av == null) return 1;
      if (bv == null) return -1;
      if (isTimeCol) {
        return (new Date(av).getTime() - new Date(bv).getTime()) * dir;
      }
      if (isNumCol) {
        return ((Number(av) || 0) - (Number(bv) || 0)) * dir;
      }
      return String(av).localeCompare(String(bv), undefined, { sensitivity: 'base' }) * dir;
    };

    return [...rows].sort(cmp);
  }, [rows, sort]);

  return (
    <>
      <h1 className="page-title">User Activity Summary</h1>

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
        <button className="btn" onClick={exportToExcel} disabled={exporting || !rows || rows.length === 0}>
          {exporting ? 'Exporting...' : 'Export to Excel'}
        </button>
      </div>

      <ErrorBox error={error} />
      {!sortedRows && !error && <Spinner />}

      {sortedRows && (
        <div className="panel">
          <div style={{ marginBottom: 8 }} className="muted">
            {sortedRows.length} row(s) — click any column header to sort.
          </div>
          <table>
            <thead>
              <tr>
                <Th label="Date"          col="Date"          sort={sort} setSort={setSort} defaultDir="desc" />
                <Th label="Computer"      col="MachineName"   sort={sort} setSort={setSort} defaultDir="asc" />
                <Th label="User"          col="UserName"      sort={sort} setSort={setSort} defaultDir="asc" />
                <Th label="First Login"   col="FirstLogin"    sort={sort} setSort={setSort} defaultDir="asc" />
                <Th label="Last Lock"     col="LastLock"      sort={sort} setSort={setSort} defaultDir="asc" />
                <Th label="Last Unlock"   col="LastUnlock"       sort={sort} setSort={setSort} defaultDir="asc" />
                <Th label="Last Seen"     col="MachineLastSeen"  sort={sort} setSort={setSort} defaultDir="desc" />
                <Th label="Active Hours"  col="ActiveSeconds"    sort={sort} setSort={setSort} defaultDir="desc" />
                <Th label="Status"        col="LastStatus"       sort={sort} setSort={setSort} defaultDir="asc" />
              </tr>
            </thead>
            <tbody>
              {sortedRows.map((r, i) => (
                <tr key={`${r.Date}-${r.MachineName}-${r.UserName}-${i}`}>
                  <td>{fmtDate(r.Date)}</td>
                  <td>
                    {r.MachineName
                      ? <Link to={`/apps?machine=${encodeURIComponent(r.MachineName)}&start=${r.Date.slice(0,10)}&end=${r.Date.slice(0,10)}`}>
                          {r.MachineName}
                        </Link>
                      : r.MachineName}
                  </td>
                  <td>{r.UserName}</td>
                  <td>{fmtTime(r.FirstLogin)}</td>
                  <td>{fmtTime(r.LastLock)}</td>
                  <td>{fmtTime(r.LastUnlock)}</td>
                  <td>{fmtTime(r.MachineLastSeen)}</td>
                  <td>{fmtActiveHours(r.ActiveSeconds)}</td>
                  <td><StatusBadge status={r.LastStatus} /></td>
                </tr>
              ))}
              {sortedRows.length === 0 && (
                <tr><td colSpan={9} className="muted">No activity in this date range.</td></tr>
              )}
            </tbody>
          </table>
          <Pagination total={total} page={page} pageSize={pageSize}
                      onPageChange={setPage} onPageSizeChange={setPageSize} />
        </div>
      )}
    </>
  );
}
