'use strict';

/**
 * Install the UAM Agent as a Windows Service using node-windows.
 * Run from an elevated PowerShell/CMD:
 *   node service\install-service.js
 *
 * On uninstall:
 *   node service\uninstall-service.js
 */
const path = require('path');

let Service;
try {
  Service = require('node-windows').Service;
} catch (e) {
  console.error('node-windows is not installed. Run: npm install node-windows');
  process.exit(1);
}

const svc = new Service({
  name: 'UAM Activity Agent',
  description: 'User Activity Monitoring Agent — collects login/lock/app usage and forwards to UAM server.',
  script: path.resolve(__dirname, '..', 'src', 'index.js'),
  nodeOptions: ['--max_old_space_size=256'],
  workingDirectory: path.resolve(__dirname, '..'),
  allowServiceLogon: true
});

svc.on('install',   () => { console.log('Service installed. Starting...'); svc.start(); });
svc.on('alreadyinstalled', () => console.log('Service is already installed.'));
svc.on('start',     () => console.log('Service started.'));
svc.on('error',     (e) => console.error('Service error:', e));

svc.install();
