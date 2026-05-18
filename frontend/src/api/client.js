// Lightweight fetch wrapper. Base path defaults to /api so it works behind IIS rewrite.
const BASE = import.meta.env.VITE_API_BASE || '/api';
const TOKEN_KEY = 'uam_jwt';

function getToken()         { return localStorage.getItem(TOKEN_KEY); }
function setToken(t)        { if (t) localStorage.setItem(TOKEN_KEY, t); else localStorage.removeItem(TOKEN_KEY); }
function authHeaders() {
  const t = getToken();
  return t ? { Authorization: `Bearer ${t}` } : {};
}

async function get(path) {
  const res = await fetch(`${BASE}${path}`, {
    credentials: 'include',
    headers: { ...authHeaders() }
  });
  if (res.status === 401) {
    setToken(null);
    if (typeof window !== 'undefined' && !window.location.pathname.endsWith('/login')) {
      window.location.replace('/login');
    }
    throw new Error('Not authenticated');
  }
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`GET ${path} -> ${res.status} ${text}`);
  }
  return res.json();
}

async function post(path, body) {
  const res = await fetch(`${BASE}${path}`, {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json', ...authHeaders() },
    body: JSON.stringify(body || {})
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`POST ${path} -> ${res.status} ${text}`);
  }
  return res.json();
}

export const api = {
  health:        ()                => get('/health'),
  overview:      ()                => get('/dashboard/overview'),
  machines:      (q='')            => get(`/dashboard/machines?search=${encodeURIComponent(q)}`),
  machine:       (id)              => get(`/dashboard/machines/${id}`),
  machineSessions: (id, limit=50)  => get(`/dashboard/machines/${id}/sessions?limit=${limit}`),
  users:         ()                => get('/dashboard/users'),
  usersDaily:    ({ start='', end='', q='' } = {}) => {
    const p = new URLSearchParams();
    if (start) p.set('start', start);
    if (end)   p.set('end',   end);
    if (q)     p.set('q',     q);
    // Browser timezone offset in minutes (positive east of UTC).
    // JS getTimezoneOffset() is the *opposite* sign convention, hence the negation.
    p.set('tz', String(-new Date().getTimezoneOffset()));
    return get(`/dashboard/users/daily?${p.toString()}`);
  },
  session:       (id)              => get(`/dashboard/sessions/${id}`),
  events:        (limit=100, type='') => get(`/dashboard/events?limit=${limit}${type ? `&type=${encodeURIComponent(type)}`:''}`),
  topApps:       ({ days=7, users=[], machines=[] } = {}) => {
    const p = new URLSearchParams();
    p.set('days', String(days));
    if (users.length)    p.set('users',    users.join(','));
    if (machines.length) p.set('machines', machines.join(','));
    return get(`/dashboard/apps/top?${p.toString()}`);
  },
  appsList:      ({ start='', end='', q='', limit=5000 } = {}) => {
    const p = new URLSearchParams();
    if (start) p.set('start', start);
    if (end)   p.set('end',   end);
    if (q)     p.set('q',     q);
    p.set('limit', String(limit));
    return get(`/dashboard/apps/list?${p.toString()}`);
  },
  daily:         (days=14)         => get(`/dashboard/reports/daily?days=${days}`),

  // --- Auth ---
  login: async (username, password) => {
    const r = await post('/auth/login', { username, password });
    if (r && r.token) setToken(r.token);
    return r;
  },
  me:     () => get('/auth/me'),
  logout: () => { setToken(null); },
  isAuthenticated: () => !!getToken()
};
