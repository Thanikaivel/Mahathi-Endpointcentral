import React, { useState } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { api } from '../api/client.js';

export default function Login() {
  const navigate = useNavigate();
  const location = useLocation();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [busy,     setBusy]     = useState(false);
  const [error,    setError]    = useState(null);

  async function submit(e) {
    e.preventDefault();
    setBusy(true); setError(null);
    try {
      await api.login(username.trim(), password);
      const redirectTo = (location.state && location.state.from) || '/';
      navigate(redirectTo, { replace: true });
    } catch (err) {
      setError(err.message.includes('401') || err.message.toLowerCase().includes('invalid')
        ? 'Invalid username or password.'
        : 'Login failed: ' + err.message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div style={styles.page}>
      <div style={styles.card}>
        <h1 style={styles.title}>UAM Dashboard</h1>
        <p style={styles.subtitle}>Sign in to continue</p>

        <form onSubmit={submit}>
          <label style={styles.label}>Username</label>
          <input
            type="text"
            value={username}
            onChange={e => setUsername(e.target.value)}
            autoFocus
            required
            style={styles.input}
          />

          <label style={styles.label}>Password</label>
          <input
            type="password"
            value={password}
            onChange={e => setPassword(e.target.value)}
            required
            style={styles.input}
          />

          {error && <div style={styles.error}>{error}</div>}

          <button type="submit" disabled={busy} style={{ ...styles.button, opacity: busy ? 0.6 : 1 }}>
            {busy ? 'Signing in...' : 'Sign in'}
          </button>
        </form>
      </div>
    </div>
  );
}

const styles = {
  page: {
    minHeight: '100vh',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    background: '#0c1117',
    padding: 20
  },
  card: {
    width: '100%',
    maxWidth: 380,
    background: '#161b22',
    border: '1px solid #2a313c',
    borderRadius: 8,
    padding: '32px 28px',
    boxShadow: '0 4px 20px rgba(0,0,0,0.4)'
  },
  title:    { margin: 0, color: '#e6edf3', fontSize: 24, fontWeight: 600 },
  subtitle: { margin: '6px 0 24px 0', color: '#7d8590', fontSize: 13 },
  label:    { display: 'block', color: '#c9d1d9', fontSize: 12, fontWeight: 500, margin: '14px 0 6px' },
  input: {
    width: '100%',
    padding: '8px 12px',
    background: '#0d1117',
    border: '1px solid #30363d',
    borderRadius: 6,
    color: '#e6edf3',
    fontSize: 14,
    outline: 'none',
    boxSizing: 'border-box'
  },
  button: {
    width: '100%',
    marginTop: 22,
    padding: '10px',
    background: '#1f6feb',
    border: 'none',
    borderRadius: 6,
    color: '#fff',
    fontSize: 14,
    fontWeight: 600,
    cursor: 'pointer'
  },
  error: {
    marginTop: 16,
    padding: '8px 12px',
    background: '#5a1d1d',
    border: '1px solid #8b2c2c',
    borderRadius: 6,
    color: '#ff8a8a',
    fontSize: 13
  }
};
