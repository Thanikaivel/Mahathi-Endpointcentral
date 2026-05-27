import React from 'react';

/**
 * Reusable pagination controls.
 *   <Pagination total={1234} page={1} pageSize={50} onPageChange={fn} onPageSizeChange={fn}/>
 */
export default function Pagination({ total = 0, page = 1, pageSize = 50, onPageChange, onPageSizeChange, pageSizes = [25, 50, 100, 250] }) {
  const totalPages = Math.max(1, Math.ceil(total / pageSize));
  const from = total === 0 ? 0 : (page - 1) * pageSize + 1;
  const to   = Math.min(total, page * pageSize);

  const go = (p) => { if (p >= 1 && p <= totalPages && p !== page && onPageChange) onPageChange(p); };

  const btn = {
    padding: '4px 10px',
    background: '#161b22',
    border: '1px solid #2a313c',
    color: '#c9d1d9',
    borderRadius: 4,
    fontSize: 12,
    cursor: 'pointer',
  };
  const btnDisabled = { ...btn, opacity: 0.4, cursor: 'not-allowed' };

  return (
    <div style={{
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      gap: 12,
      marginTop: 10,
      flexWrap: 'wrap'
    }}>
      <div className="muted" style={{ fontSize: 12 }}>
        Showing {from.toLocaleString()}–{to.toLocaleString()} of {total.toLocaleString()} row{total === 1 ? '' : 's'}
      </div>

      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <button style={page <= 1 ? btnDisabled : btn} onClick={() => go(1)} disabled={page <= 1}>« First</button>
        <button style={page <= 1 ? btnDisabled : btn} onClick={() => go(page - 1)} disabled={page <= 1}>‹ Prev</button>
        <span className="muted" style={{ fontSize: 12, padding: '0 6px' }}>
          Page {page} of {totalPages}
        </span>
        <button style={page >= totalPages ? btnDisabled : btn} onClick={() => go(page + 1)} disabled={page >= totalPages}>Next ›</button>
        <button style={page >= totalPages ? btnDisabled : btn} onClick={() => go(totalPages)} disabled={page >= totalPages}>Last »</button>

        {onPageSizeChange && (
          <select
            value={pageSize}
            onChange={e => onPageSizeChange(parseInt(e.target.value, 10))}
            style={{ ...btn, marginLeft: 10 }}
          >
            {pageSizes.map(n => <option key={n} value={n}>{n} / page</option>)}
          </select>
        )}
      </div>
    </div>
  );
}
