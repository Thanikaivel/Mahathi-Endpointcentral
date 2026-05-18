import React from 'react';
import { Routes, Route, Navigate, useLocation } from 'react-router-dom';
import Layout from './components/Layout.jsx';
import Overview from './pages/Overview.jsx';
import Machines from './pages/Machines.jsx';
import MachineDetail from './pages/MachineDetail.jsx';
import Users from './pages/Users.jsx';
import Events from './pages/Events.jsx';
import TopApps from './pages/TopApps.jsx';
import Reports from './pages/Reports.jsx';
import SessionDetail from './pages/SessionDetail.jsx';
import Login from './pages/Login.jsx';
import { api } from './api/client.js';

function RequireAuth({ children }) {
  const location = useLocation();
  if (!api.isAuthenticated()) {
    return <Navigate to="/login" state={{ from: location.pathname }} replace />;
  }
  return children;
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route element={<RequireAuth><Layout /></RequireAuth>}>
        <Route path="/"             element={<Overview />} />
        <Route path="/machines"     element={<Machines />} />
        <Route path="/machines/:id" element={<MachineDetail />} />
        <Route path="/users"        element={<Users />} />
        <Route path="/events"       element={<Events />} />
        <Route path="/apps"         element={<TopApps />} />
        <Route path="/reports"      element={<Reports />} />
        <Route path="/sessions/:id" element={<SessionDetail />} />
      </Route>
    </Routes>
  );
}
