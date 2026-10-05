#!/usr/bin/env node
// Optionaler CORS-Helfer für die DartsApp.
// Falls der Browser die Verbindung zum Autodarts Board Manager blockiert (CORS),
// auf einem Rechner im selben Netz starten:
//   node autodarts-bridge.js 192.168.1.50      (IP des Boards, Standard: 127.0.0.1)
// In der App dann die Adresse dieses Rechners mit Port 3181 eintragen.
const http = require('http');
const target = process.argv[2] || '127.0.0.1';
const targetPort = Number(process.argv[3]) || 3180;
const listen = Number(process.argv[4]) || 3181;

http.createServer((req, res) => {
  const headers = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*', 'Access-Control-Allow-Methods': 'GET, OPTIONS' };
  if (req.method === 'OPTIONS') { res.writeHead(204, headers); return res.end(); }
  const up = http.request({ host: target, port: targetPort, path: req.url, method: 'GET', headers: { accept: 'application/json' } }, r => {
    res.writeHead(r.statusCode, Object.assign({}, headers, { 'content-type': r.headers['content-type'] || 'application/json' }));
    r.pipe(res);
  });
  up.on('error', e => { res.writeHead(502, headers); res.end(JSON.stringify({ error: e.message })); });
  up.end();
}).listen(listen, '0.0.0.0', () => console.log(`Bridge läuft: http://<dieser-rechner>:${listen}  →  http://${target}:${targetPort}`));
