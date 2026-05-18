import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// During `vite dev` we proxy /api -> backend on :5321.
// In production the backend should be reverse-proxied at /api by IIS,
// or set VITE_API_BASE at build time.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://localhost:5321',
        changeOrigin: true
      }
    }
  },
  build: {
    outDir: 'dist',
    sourcemap: false
  }
});
