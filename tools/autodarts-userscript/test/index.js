'use strict';
// Test des Browser-Skripts mit einer nachgebauten Seite (kein Browser, kein Netz).
// Aufruf: node --test tools/autodarts-userscript/test
// Alle Match-Daten sind selbst gebaut und synthetisch.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const SCRIPT = path.join(__dirname, '..', 'dartlab-autodarts.user.js');
const lib = require(SCRIPT);

const SECRET = 'Bearer geheim-token-123';
const COOKIE = 'session=geheim-cookie';

function match(extra = {}) {
  return {
    id: 'm-001',
    variant: 'X01',
    finished: true,
    players: [
      { id: 'a', name: 'Ben' },
      { id: 'b', name: 'Gegner' },
    ],
    games: [{ set: 1, leg: 1, winnerPlayerId: 'a', turns: [{ playerId: 'a', throws: [{ segment: { name: 'T20' } }] }] }],
    ...extra,
  };
}

/** Eine Antwort, die jeden Zugriff auf Header sofort meldet. */
function fakeResponse(body, { ok = true, status = 200 } = {}) {
  const text = typeof body === 'string' ? body : JSON.stringify(body);
  const res = {
    ok,
    status,
    clone() {
      return res;
    },
    text() {
      return Promise.resolve(text);
    },
    json() {
      return Promise.resolve(JSON.parse(text));
    },
    get headers() {
      throw new Error('Header gelesen!');
    },
  };
  return res;
}

class FakeXHR {
  constructor() {
    this.listeners = {};
    this.status = 0;
    this.responseText = '';
    this.responseType = '';
    FakeXHR.instances.push(this);
  }
  open(method, url) {
    this.method = method;
    this.url = url;
  }
  setRequestHeader(name, value) {
    // Die Seite selbst setzt hier ihr Token; das Skript darf das nie lesen.
    this.sentHeaders = { ...(this.sentHeaders || {}), [name]: value };
  }
  send() {
    this.sent = true;
  }
  addEventListener(type, fn) {
    (this.listeners[type] ||= []).push(fn);
  }
  getResponseHeader() {
    throw new Error('Header gelesen!');
  }
  getAllResponseHeaders() {
    throw new Error('Header gelesen!');
  }
  /** Der Server antwortet. */
  respond(status, body) {
    this.status = status;
    this.responseText = typeof body === 'string' ? body : JSON.stringify(body);
    (this.listeners.load || []).forEach((fn) => fn.call(this, {}));
  }
}
FakeXHR.instances = [];

const flush = () => new Promise((resolve) => setImmediate(resolve));
async function settle() {
  for (let i = 0; i < 8; i++) await flush();
}

/** Baut Seite, Speicher und Anzeige nach und hängt das Skript ein. */
function setup({ store = {}, appReply, ownFetchFails = false, gm = true, gmFails = false, onPageFetch } = {}) {
  const calls = []; // alles, was das Skript selbst nach außen schickt
  const shown = [];
  const timers = [];
  const clipboard = [];
  const asked = [];
  let answers = [];
  const storage = { ...store };

  const page = {
    location: { href: 'https://play.autodarts.com/history/matches' },
    // Zugriffe darauf wären ein Fehler:
    get localStorage() {
      throw new Error('localStorage gelesen!');
    },
    get sessionStorage() {
      throw new Error('sessionStorage gelesen!');
    },
    get document() {
      throw new Error('document gelesen!');
    },
    get indexedDB() {
      throw new Error('indexedDB gelesen!');
    },
    fetch: async (input, init) => {
      if (onPageFetch) return onPageFetch(input, init);
      return fakeResponse({});
    },
    XMLHttpRequest: FakeXHR,
  };

  const reply = appReply || ((url) => ({ status: 200, body: { ok: true, status: 'imported', id: 'm-001', opponent: 'Gegner', legs: '3:2' } }));

  const ownFetch = ownFetchFails
    ? async (url, init) => {
        calls.push({ via: 'fetch', url, init });
        throw new TypeError('Failed to fetch');
      }
    : async (url, init) => {
        calls.push({ via: 'fetch', url, init });
        const r = reply(url, init);
        return fakeResponse(r.body, { status: r.status });
      };

  const gmRequest = gm
    ? (opts) => {
        calls.push({ via: 'gm', url: opts.url, init: opts });
        if (gmFails) return setImmediate(() => opts.onerror && opts.onerror({}));
        const r = reply(opts.url, opts);
        setImmediate(() => opts.onload({ status: r.status, responseText: JSON.stringify(r.body) }));
      }
    : null;

  const menu = {};
  const api = lib.install({
    page,
    ownFetch,
    gmRequest,
    getValue: (k, d) => (k in storage ? storage[k] : d),
    setValue: (k, v) => {
      storage[k] = v;
    },
    registerMenu: (name, fn) => {
      menu[name] = fn;
    },
    setClipboard: (t) => clipboard.push(t),
    ask: (message, def) => {
      asked.push({ message, def });
      return answers.shift();
    },
    show: (s) => shown.push(s),
    setTimeout: (fn) => timers.push(fn),
  });
  return {
    page,
    api,
    calls,
    shown,
    timers,
    clipboard,
    asked,
    storage,
    menu,
    answer: (...a) => (answers = a),
    lastShown: () => shown[shown.length - 1],
    runTimers: () => timers.splice(0).forEach((fn) => fn()),
  };
}

const configured = { 'dartlab.url': 'http://127.0.0.1:3191', 'dartlab.code': '482913' };
const STATS = 'https://api.autodarts.com/as/v0/matches/m-001/stats';
const STATE = 'https://api.autodarts.com/gs/v0/matches/m-001/state';

// ---------------------------------------------------------------------

test('fetch: eine /stats-Antwort wird unverändert an die lokale App geschickt', async () => {
  const t = setup({ store: configured, onPageFetch: async () => fakeResponse(match()) });
  const res = await t.page.fetch(STATS, { headers: { Authorization: SECRET } });
  assert.equal(res.ok, true, 'die Seite bekommt ihre Antwort wie gewohnt');
  await settle();

  assert.equal(t.calls.length, 1);
  const call = t.calls[0];
  assert.equal(call.via, 'fetch');
  assert.equal(call.url, 'http://127.0.0.1:3191/import/autodarts?id=m-001');
  assert.equal(call.init.method, 'POST');
  assert.equal(call.init.body, JSON.stringify(match()), 'der Text wird nicht umgebaut');
  assert.deepEqual(call.init.headers, { 'Content-Type': 'application/json', 'X-DartLab-Key': '482913' });
  assert.equal(call.init.credentials, 'omit');
  assert.equal(t.lastShown().state, 'ok');
  assert.match(t.lastShown().text, /Gegner/);
  assert.match(t.lastShown().text, /3:2/);
});

test('fetch: Request-Objekt und URL-Objekt werden ebenfalls erkannt', async () => {
  const t = setup({ store: configured, onPageFetch: async () => fakeResponse(match()) });
  await t.page.fetch({ url: STATS });
  await settle();
  assert.equal(t.calls.length, 1);
  const t2 = setup({ store: configured, onPageFetch: async () => fakeResponse(match()) });
  await t2.page.fetch(new URL(STATS));
  await settle();
  assert.equal(t2.calls.length, 1);
});

test('XMLHttpRequest: Antwort auf /stats wird gelesen, Header nie', async () => {
  FakeXHR.instances.length = 0;
  const t = setup({ store: configured });
  const x = new t.page.XMLHttpRequest();
  x.open('GET', '/as/v0/matches/m-001/stats'.replace(/^/, 'https://play.autodarts.io'));
  x.setRequestHeader('Authorization', SECRET);
  x.send();
  x.respond(200, match());
  await settle();
  assert.equal(t.calls.length, 1);
  assert.equal(t.calls[0].init.body, JSON.stringify(match()));
  assert.equal(x.sentHeaders.Authorization, SECRET, 'die Anfrage der Seite bleibt unberührt');
});

test('/state zählt nur, wenn das Match zu Ende ist, und wartet kurz auf /stats', async () => {
  const open = setup({ store: configured, onPageFetch: async () => fakeResponse(match({ finished: false })) });
  await open.page.fetch(STATE);
  await settle();
  open.runTimers();
  await settle();
  assert.equal(open.calls.length, 0, 'laufendes Match: nichts');

  const t = setup({ store: configured, onPageFetch: async (u) => fakeResponse(match()) });
  await t.page.fetch(STATE);
  await settle();
  assert.equal(t.calls.length, 0, 'noch in der Wartezeit');
  assert.equal(t.timers.length, 1);
  t.runTimers();
  await settle();
  assert.equal(t.calls.length, 1, 'danach geht es raus');
});

test('/state und danach /stats desselben Matches: nur die vollständigere /stats geht raus', async () => {
  let n = 0;
  const t = setup({
    store: configured,
    onPageFetch: async (u) => fakeResponse(n++ === 0 ? match({ games: [{ turns: [] }] }) : match()),
  });
  await t.page.fetch(STATE);
  await t.page.fetch(STATS);
  await settle();
  t.runTimers();
  await settle();
  assert.equal(t.calls.length, 1);
  assert.equal(JSON.parse(t.calls[0].init.body).games[0].leg, 1);
});

test('andere Adressen, andere Hosts und unfertige Antworten werden ignoriert', async () => {
  const urls = [
    'https://api.autodarts.com/as/v0/matches/filter?size=20',
    'https://api.autodarts.com/as/v0/matches/m-001',
    'https://api.autodarts.com/as/v0/matches/m-001/stats/extra',
    'https://api.autodarts.com/bs/v0/boards/',
    'https://evil.example/as/v0/matches/m-001/stats',
    'https://autodarts.com.evil.example/as/v0/matches/m-001/stats',
    'http://api.autodarts.com/as/v0/matches/m-001/stats',
  ];
  for (const u of urls) {
    const t = setup({ store: configured, onPageFetch: async () => fakeResponse(match()) });
    await t.page.fetch(u);
    await settle();
    assert.equal(t.calls.length, 0, u);
  }
  const bad = [{}, [], { players: [], games: [] }, { players: [{}], games: 'x' }, match({ finished: false }), match({ finished: undefined, finishedAt: null }), 'kein json', ''];
  for (const b of bad) {
    const t = setup({ store: configured, onPageFetch: async () => fakeResponse(b) });
    await t.page.fetch(STATS);
    await settle();
    assert.equal(t.calls.length, 0, JSON.stringify(b));
  }
  const failed = setup({ store: configured, onPageFetch: async () => fakeResponse(match(), { ok: false, status: 500 }) });
  await failed.page.fetch(STATS);
  await settle();
  assert.equal(failed.calls.length, 0, 'Fehlerantwort der Seite');
});

test('nie Header, Cookies, Speicher oder Token: weder gelesen noch weitergegeben', async () => {
  // Das Fake-Fenster wirft bei jedem Zugriff auf localStorage/document/...,
  // die Fake-Antwort und das Fake-XHR bei jedem Zugriff auf Header.
  const t = setup({ store: configured, onPageFetch: async () => fakeResponse(match()) });
  await t.page.fetch(STATS, { headers: { Authorization: SECRET, Cookie: COOKIE } });
  FakeXHR.instances.length = 0;
  const x = new t.page.XMLHttpRequest();
  x.open('GET', 'https://api.autodarts.com/as/v0/matches/m-002/stats');
  x.setRequestHeader('Authorization', SECRET);
  x.send();
  x.respond(200, match({ id: 'm-002' }));
  await settle();
  assert.equal(t.calls.length, 2);
  for (const c of t.calls) {
    const dump = JSON.stringify(c);
    assert.ok(!dump.includes('geheim'), 'weder Token noch Cookie');
    assert.ok(!/authorization/i.test(dump), 'kein Authorization-Header');
    assert.ok(!/cookie/i.test(dump.replace('"credentials":"omit"', '')), 'kein Cookie');
    assert.deepEqual(Object.keys(c.init.headers).sort(), ['Content-Type', 'X-DartLab-Key']);
  }
});

test('keine eigenen Anfragen an Autodarts: alles geht nur an 127.0.0.1/localhost', async () => {
  const t = setup({ store: configured, onPageFetch: async () => fakeResponse(match()) });
  await t.page.fetch(STATS);
  await t.page.fetch(STATE);
  t.menu['DartLab: Verbindung testen']();
  t.menu['DartLab: letztes Match erneut senden']();
  await settle();
  t.runTimers();
  await settle();
  assert.ok(t.calls.length >= 3);
  for (const c of t.calls) {
    const u = new URL(c.url);
    assert.ok(['127.0.0.1', 'localhost'].includes(u.hostname), c.url);
    assert.ok(!/autodarts/i.test(u.hostname), c.url);
  }
});

test('sendet an die eingestellte lokale Adresse und den eingestellten Code', async () => {
  const t = setup({
    store: { 'dartlab.url': 'http://localhost:4567', 'dartlab.code': '111222' },
    onPageFetch: async () => fakeResponse(match()),
  });
  await t.page.fetch(STATS);
  await settle();
  assert.equal(t.calls[0].url, 'http://localhost:4567/import/autodarts?id=m-001');
  assert.equal(t.calls[0].init.headers['X-DartLab-Key'], '111222');
});

test('Ziel außerhalb dieses Rechners wird verweigert, nichts geht raus', async () => {
  for (const url of ['https://example.com', 'http://192.168.1.20:3191', 'http://evil.example:3191', 'http://127.0.0.1.evil.example:3191', 'http://127.0.0.1:80', 'ftp://127.0.0.1:3191']) {
    const t = setup({ store: { 'dartlab.url': url, 'dartlab.code': '482913' }, onPageFetch: async () => fakeResponse(match()) });
    await t.page.fetch(STATS);
    await settle();
    assert.equal(t.calls.length, 0, url);
    assert.equal(t.lastShown().state, 'error', url);
  }
});

test('ohne Code: Hinweis statt Senden', async () => {
  const t = setup({ store: { 'dartlab.url': 'http://127.0.0.1:3191' }, onPageFetch: async () => fakeResponse(match()) });
  await t.page.fetch(STATS);
  await settle();
  assert.equal(t.calls.length, 0);
  assert.match(t.lastShown().text, /Code/);
});

test('Fehler sind kein Problem: App aus, Rückfall über GM, Seite läuft weiter', async () => {
  // fetch scheitert (z. B. Seitenregel), GM_xmlhttpRequest klappt.
  const viaGm = setup({ store: configured, ownFetchFails: true, onPageFetch: async () => fakeResponse(match()) });
  await viaGm.page.fetch(STATS);
  await settle();
  assert.deepEqual(viaGm.calls.map((c) => c.via), ['fetch', 'gm']);
  assert.equal(viaGm.calls[1].init.anonymous, true);
  assert.equal(viaGm.lastShown().state, 'ok');

  // App nicht erreichbar: beide scheitern.
  const off = setup({ store: configured, ownFetchFails: true, gmFails: true, onPageFetch: async () => fakeResponse(match()) });
  const res = await off.page.fetch(STATS);
  await settle();
  assert.equal(res.ok, true, 'die Seite merkt nichts');
  assert.equal(off.lastShown().state, 'error');
  assert.match(off.lastShown().text, /nicht erreichbar/);

  // Ohne GM-Rechte ebenso.
  const noGm = setup({ store: configured, ownFetchFails: true, gm: false, onPageFetch: async () => fakeResponse(match()) });
  await noGm.page.fetch(STATS);
  await settle();
  assert.equal(noGm.lastShown().state, 'error');
});

test('Fehlerantworten der App werden verständlich gemeldet', async () => {
  for (const [status, re] of [[401, /Code/], [403, /abgelehnt/], [413, /groß/], [422, /lesen/], [429, /Zu viele/], [500, /500/]]) {
    const t = setup({ store: configured, appReply: () => ({ status, body: { ok: false } }), onPageFetch: async () => fakeResponse(match()) });
    await t.page.fetch(STATS);
    await settle();
    assert.equal(t.lastShown().state, 'error', String(status));
    assert.match(t.lastShown().text, re, String(status));
  }
});

test('Antworten der App: duplicate, ignored, pending', async () => {
  const cases = {
    duplicate: ['ok', /schon in DartLab/],
    ignored: ['info', /Nicht importiert/],
    pending: ['info', /welcher Spieler/],
  };
  for (const [status, [state, re]] of Object.entries(cases)) {
    const t = setup({ store: configured, appReply: () => ({ status: 200, body: { ok: true, status } }), onPageFetch: async () => fakeResponse(match()) });
    await t.page.fetch(STATS);
    await settle();
    assert.equal(t.lastShown().state, state, status);
    assert.match(t.lastShown().text, re, status);
  }
});

test('ein Match wird nur einmal geschickt, auch wenn die Seite die Antwort mehrfach lädt', async () => {
  const t = setup({ store: configured, onPageFetch: async () => fakeResponse(match()) });
  await t.page.fetch(STATS);
  await settle();
  await t.page.fetch(STATS);
  await t.page.fetch(STATS);
  await settle();
  assert.equal(t.calls.length, 1);
});

test('nach einem Fehler wird beim nächsten Laden erneut versucht', async () => {
  let up = false;
  const t = setup({
    store: configured,
    appReply: () => (up ? { status: 200, body: { ok: true, status: 'imported' } } : { status: 401, body: { ok: false } }),
    onPageFetch: async () => fakeResponse(match()),
  });
  await t.page.fetch(STATS);
  await settle();
  assert.equal(t.lastShown().state, 'error');
  up = true;
  await t.page.fetch(STATS);
  await settle();
  assert.equal(t.calls.length, 2);
  assert.equal(t.lastShown().state, 'ok');
});

test('kaputte Antworten und Ausnahmen in der Seite bringen nichts zum Absturz', async () => {
  const t = setup({
    store: configured,
    onPageFetch: async () => ({
      ok: true,
      clone() {
        throw new Error('clone kaputt');
      },
    }),
  });
  const res = await t.page.fetch(STATS);
  await settle();
  assert.equal(res.ok, true);
  assert.equal(t.calls.length, 0);

  const rejecting = setup({
    store: configured,
    onPageFetch: async () => {
      throw new TypeError('Netzwerk der Seite');
    },
  });
  await assert.rejects(rejecting.page.fetch(STATS), /Netzwerk der Seite/, 'Fehler der Seite bleiben Fehler der Seite');

  FakeXHR.instances.length = 0;
  const x = setup({ store: configured });
  const xhr = new x.page.XMLHttpRequest();
  xhr.open('GET', STATS);
  xhr.send();
  xhr.respond(200, '{kaputt');
  xhr.respond(500, match());
  await settle();
  assert.equal(x.calls.length, 0);
});

test('Antwort über 2 MB wird nicht geschickt', async () => {
  const t = setup({ store: configured, onPageFetch: async () => fakeResponse(match({ pad: 'x'.repeat(2 * 1024 * 1024) })) });
  await t.page.fetch(STATS);
  await settle();
  assert.equal(t.calls.length, 0);
});

test('Menü „DartLab einrichten“ speichert Adresse und Code, prüft beides', () => {
  const t = setup();
  t.answer('http://127.0.0.1:3500', '654321');
  t.menu['DartLab einrichten']();
  assert.equal(t.storage['dartlab.url'], 'http://127.0.0.1:3500');
  assert.equal(t.storage['dartlab.code'], '654321');

  const bad = setup();
  bad.answer('http://example.com:3191', '654321');
  bad.menu['DartLab einrichten']();
  assert.equal(bad.storage['dartlab.url'], undefined);
  assert.equal(bad.lastShown().state, 'error');

  const badCode = setup();
  badCode.answer('http://127.0.0.1:3191', 'abc');
  badCode.menu['DartLab einrichten']();
  assert.equal(badCode.storage['dartlab.code'], undefined);

  const cancel = setup();
  cancel.answer(null);
  cancel.menu['DartLab einrichten']();
  assert.deepEqual(cancel.storage, {});
  assert.deepEqual(cancel.asked.map((a) => a.def), [lib.DEFAULT_URL]);
});

test('Menü „Match kopieren“: Zwischenablage bekommt das Match, die Id wird nur ergänzt, wenn sie fehlt', async () => {
  const t = setup({ store: configured, onPageFetch: async () => fakeResponse(match()) });
  t.menu['DartLab: Match kopieren']();
  assert.equal(t.clipboard.length, 0);
  assert.match(t.lastShown().text, /Noch kein/);

  await t.page.fetch(STATS);
  await settle();
  t.menu['DartLab: Match kopieren']();
  assert.equal(t.clipboard[0], JSON.stringify(match()));

  const noId = match();
  delete noId.id;
  const t2 = setup({ store: configured, onPageFetch: async () => fakeResponse(noId) });
  await t2.page.fetch(STATS);
  await settle();
  t2.menu['DartLab: Match kopieren']();
  assert.equal(JSON.parse(t2.clipboard[0]).id, 'm-001');
  assert.equal(t2.calls[0].init.body, JSON.stringify(noId), 'gesendet wird der Text unverändert; die Id steht in der Adresse');
});

test('Menü „Verbindung testen“ ruft nur /import/ping lokal auf', async () => {
  const t = setup({ store: configured, appReply: () => ({ status: 200, body: { ok: true } }) });
  t.menu['DartLab: Verbindung testen']();
  await settle();
  assert.equal(t.calls[0].url, 'http://127.0.0.1:3191/import/ping');
  assert.equal(t.calls[0].init.method, 'GET');
  assert.equal(t.lastShown().state, 'ok');
});

test('echte Form: fertiges Match hat finishedAt statt finished', async () => {
  const real = match({ finished: undefined, finishedAt: '2026-10-22T20:49:03.609993Z' });
  const t = setup({ store: configured, onPageFetch: async () => fakeResponse(real) });
  await t.page.fetch(STATS);
  await settle();
  assert.equal(t.calls.length, 1);
});

test('Hilfsfunktionen', () => {
  assert.deepEqual(lib.classifyUrl('/as/v0/matches/abc/stats', 'https://play.autodarts.com/x'), { kind: 'stats', id: 'abc' });
  assert.equal(lib.classifyUrl('/as/v0/matches/abc/stats', 'https://example.org/'), null);
  assert.equal(lib.classifyUrl('not a url at all', 'x'), null);
  assert.equal(lib.checkTarget('http://localhost:3191').ok, true);
  assert.equal(lib.checkTarget('http://127.0.0.1:1023').ok, false);
  assert.equal(lib.checkTarget('http://[::1]:3191').ok, false);
});

// ---------------------------------------------------------------------
// Prüfungen am Quelltext selbst
// ---------------------------------------------------------------------

const source = fs.readFileSync(SCRIPT, 'utf8');
const header = /\/\/ ==UserScript==([\s\S]*?)\/\/ ==\/UserScript==/.exec(source)[1];
const code = source
  .slice(source.indexOf('// ==/UserScript==') + 18)
  .replace(/\/\*[\s\S]*?\*\//g, '')
  .split('\n')
  .filter((l) => !/^\s*\/\//.test(l))
  .join('\n');

test('Kopfzeilen: nur die zwei Autodarts-Seiten, nur lokale Ziele, keine Nachlade-Skripte', () => {
  const lines = header.split('\n').map((l) => l.trim()).filter(Boolean);
  const of = (key) => lines.filter((l) => l.startsWith(`// @${key} `)).map((l) => l.replace(`// @${key}`, '').trim());
  assert.deepEqual(of('match'), ['https://play.autodarts.com/*', 'https://play.autodarts.io/*']);
  assert.deepEqual(of('connect'), ['localhost', '127.0.0.1']);
  assert.deepEqual(of('grant').sort(), ['GM_getValue', 'GM_registerMenuCommand', 'GM_setClipboard', 'GM_setValue', 'GM_xmlhttpRequest', 'unsafeWindow']);
  assert.deepEqual(of('run-at'), ['document-start']);
  for (const forbidden of ['require', 'resource', 'include', 'exclude', 'updateURL', 'downloadURL']) {
    assert.deepEqual(of(forbidden), [], forbidden);
  }
});

test('Quelltext: kein Zugriff auf Header, Cookies, Speicher oder Token; keine fremden Adressen', () => {
  const banned = [
    /localStorage/,
    /sessionStorage/,
    /indexedDB/,
    /document\.cookie/,
    /cookieStore/,
    /authorization/i,
    /bearer/i,
    /getResponseHeader/,
    /getAllResponseHeaders/,
    /\.headers\b(?!\s*[:=])/, // Lesen von response.headers
    /setRequestHeader/,
    /navigator\.sendBeacon/,
    /new\s+WebSocket/,
    /importScripts/,
    /\beval\s*\(/,
    /new\s+Function/,
    /\.innerHTML/,
    /document\.write/,
    /@require/,
  ];
  for (const re of banned) assert.ok(!re.test(code), `verboten im Code: ${re}`);
  const urls = code.match(/https?:\/\/[^\s'"`)]+/g) || [];
  const allowed = (u) => /^https:\/\/play\.autodarts\.com\/?$/.test(u) || /^http:\/\/(127\.0\.0\.1|localhost)/.test(u) || /^https?:\/\/$/.test(u);
  for (const u of urls) assert.ok(allowed(u), `Adresse im Code: ${u}`);
});

test('Quelltext: jede Anfrage geht über ownFetch oder gmRequest, beide nur mit der geprüften Basis-Adresse', () => {
  const sends = code.match(/(ownFetch|gmRequest)\(/g) || [];
  assert.ok(sends.length >= 4);
  // url wird in send() und test() aus target.base gebaut:
  assert.equal((code.match(/target\.base \+ '\/import\//g) || []).length, 2);
});

test('als Skript geladen (ohne module): hängt sich ein, registriert das Menü, wirft nicht', async () => {
  const vm = require('node:vm');
  const menus = [];
  const sent = [];
  const pageFetch = async () => fakeResponse(match());
  const unsafe = {
    location: { href: 'https://play.autodarts.com/' },
    fetch: pageFetch,
    XMLHttpRequest: FakeXHR,
    prompt: () => null,
    document: { body: null, addEventListener() {} },
    setTimeout,
    clearTimeout,
  };
  const sandbox = {
    unsafeWindow: unsafe,
    window: { setTimeout, clearTimeout },
    fetch: async (url, init) => {
      sent.push({ url, init });
      return fakeResponse({ ok: true, status: 'imported' });
    },
    GM_getValue: (k, d) => (k === 'dartlab.code' ? '482913' : d),
    GM_setValue() {},
    GM_registerMenuCommand: (name) => menus.push(name),
    GM_xmlhttpRequest() {},
    GM_setClipboard() {},
    URL,
    WeakMap,
    Promise,
    JSON,
    String,
    Number,
    Object,
    Array,
    encodeURIComponent,
  };
  sandbox.window.fetch = sandbox.fetch;
  vm.runInNewContext(source, sandbox);
  assert.deepEqual(menus.sort(), ['DartLab einrichten', 'DartLab: Match kopieren', 'DartLab: Verbindung testen', 'DartLab: letztes Match erneut senden']);
  assert.notEqual(unsafe.fetch, pageFetch, 'fetch der Seite ist eingehängt');
  await unsafe.fetch('https://api.autodarts.com/as/v0/matches/m-001/stats');
  await settle();
  assert.equal(sent.length, 1);
  assert.equal(sent[0].url, 'http://127.0.0.1:3191/import/autodarts?id=m-001');
});
