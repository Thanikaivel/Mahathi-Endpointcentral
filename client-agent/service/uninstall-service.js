'use strict';

const path = require('path');

let Service;
try {
  Service = require('node-windows').Service;
} catch (e) {
  console.error('node-windows is not installed.');
  process.exit(1);
}

const svc = new Service({
  name: 'UAM Activity Agent',
  script: path.resolve(__dirname, '..', 'src', 'index.js')
});

svc.on('uninstall', () => console.log('Service uninstalled.'));
svc.on('error',     (e) => console.error('Service error:', e));

svc.uninstall();
