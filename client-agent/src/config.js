'use strict';

const fs = require('fs');
const path = require('path');

function load() {
  // Look for config.json next to the executable / source
  const candidates = [
    path.join(process.cwd(), 'config.json'),
    path.join(__dirname, '..', 'config.json'),
    path.join(path.dirname(process.execPath), 'config.json')
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) {
      try {
        const raw = fs.readFileSync(p, 'utf8');
        const cfg = JSON.parse(raw);
        cfg.__loadedFrom = p;
        return cfg;
      } catch (e) {
        console.error(`Failed to parse ${p}: ${e.message}`);
      }
    }
  }
  throw new Error('config.json not found in any expected location');
}

module.exports = { load };
