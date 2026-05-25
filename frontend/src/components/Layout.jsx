import React, { useEffect, useState } from 'react';
import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import { api } from '../api/client.js';

export default function Layout() {
  const linkClass = ({ isActive }) => isActive ? 'active' : '';
  const navigate = useNavigate();
  const [user, setUser] = useState(null);

  useEffect(() => {
    api.me().then(r => setUser(r.user)).catch(() => setUser(null));
  }, []);

  function handleLogout() {
    api.logout();
    navigate('/login', { replace: true });
  }

  return (
    <div className="app">
      <aside className="sidebar">
        <h1>UAM Dashboard</h1>
        <nav>
          <NavLink to="/" end className={linkClass}>Overview</NavLink>
          <NavLink to="/machines" className={linkClass}>Machines</NavLink>
          <NavLink to="/users" className={linkClass}>User Activity</NavLink>
          <NavLink to="/apps" className={linkClass}>Application Usage</NavLink>
          <NavLink to="/reports" className={linkClass}>Reports</NavLink>
        </nav>
        <div style={{ flex: 1 }} />
        <div style={{ borderTop: '1px solid #2a313c', paddingTop: 12, marginTop: 12 }}>
          {user && (
            <div style={{ color: '#c9d1d9', fontSize: 12, marginBottom: 8 }}>
              <div style={{ fontWeight: 600 }}>{user.displayName || user.username}</div>
              <div className="muted" style={{ fontSize: 11 }}>{user.username}</div>
            </div>
          )}
          <button
            onClick={handleLogout}
            style={{
              width: '100%',
              padding: '6px 10px',
              background: 'transparent',
              border: '1px solid #30363d',
              borderRadius: 4,
              color: '#c9d1d9',
              fontSize: 12,
              cursor: 'pointer'
            }}
          >
            Logout
          </button>
        </div>
        <div className="muted" style={{ fontSize: 11, marginTop: 8 }}>v1.0.0</div>
      </aside>
      <main className="main">
        <Outlet />
      </main>
    </div>
  );
}
