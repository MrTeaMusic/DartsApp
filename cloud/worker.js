// DartLab Cloud Sync - Cloudflare Worker (ein einziges File, kein Build-Schritt).
//
// Der Worker ist ein "dummer" Speicher fuer Ende-zu-Ende-verschluesselte Blobs.
// Er sieht nie Klartext. Er braucht eine D1-Datenbank, die unter dem
// Variablennamen "DB" an den Worker gebunden ist (siehe README.md).
//
// Optionale Einstellungen (Worker > Settings > Variables and Secrets):
//   SETUP_KEY     Wenn gesetzt, muss jede Anfrage den Header "X-Setup-Key" mit
//                 genau diesem Wert tragen (sonst 401). Standard: aus.
//   MAX_SESSIONS  Hoechstzahl Session-Objekte pro Tresor (Standard 50000).
//
// API (JSON, UTF-8, Basis-Pfad /v1, Auth: "Authorization: Bearer <64 Hex>"):
//   GET    /v1/hello                      (ohne Auth)
//   GET    /v1/meta                       PUT /v1/meta  {ifRev, body}
//   GET    /v1/s/<uid>                    PUT /v1/s/<uid> {stamp, darts, body}
//   DELETE /v1/s/<uid>
//
// Der Tresor ("vault") ist sha256hex(token-als-Text, kleingeschrieben). Das
// Token selbst wird weder gespeichert noch geloggt.

const VERSION = 1;
const DEFAULT_MAX_SESSIONS = 50000;
// Maximale Laenge des base64-Strings eines Objekts (D1-Zeilenlimit: 2 MB).
const MAX_BODY_CHARS = 1500000;
// Obergrenze fuer die ganze Anfrage (base64-Body plus JSON-Drumherum).
const MAX_REQUEST_CHARS = MAX_BODY_CHARS + 4096;

const TOKEN_RE = /^Bearer +([0-9a-fA-F]{64})$/i;
const UID_RE = /^[A-Za-z0-9_-]{1,64}$/;
const BASE64_CHARS_RE = /^[A-Za-z0-9+/]*={0,2}$/;

const CREATE_TABLE_SQL =
  'CREATE TABLE IF NOT EXISTS objects (' +
  'vault TEXT NOT NULL, key TEXT NOT NULL, ' +
  'rev INTEGER NOT NULL DEFAULT 0, stamp INTEGER NOT NULL DEFAULT 0, ' +
  'darts INTEGER NOT NULL DEFAULT 0, body TEXT NOT NULL, ' +
  'updated INTEGER NOT NULL, PRIMARY KEY (vault, key))';

// Das Schema wird einmal pro Isolate beim ersten Request angelegt.
let schemaPromise = null;

class HttpError extends Error {
  constructor(status, code, extra) {
    super(code);
    this.status = status;
    this.code = code;
    this.extra = extra;
  }
}

function json(status, data) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-DartLab-Cloud': '1',
    },
  });
}

function errorResponse(status, code, extra) {
  return json(status, Object.assign({ error: code }, extra || {}));
}

function bytesToHex(buffer) {
  const bytes = new Uint8Array(buffer);
  let out = '';
  for (let i = 0; i < bytes.length; i++) {
    out += bytes[i].toString(16).padStart(2, '0');
  }
  return out;
}

async function sha256(text) {
  const data = new TextEncoder().encode(text);
  return new Uint8Array(await crypto.subtle.digest('SHA-256', data));
}

// Konstanter Zeitvergleich: beide Werte werden gehasht (gleiche Laenge), dann
// wird ohne vorzeitigen Abbruch verglichen.
async function safeEqual(a, b) {
  const ha = await sha256(a);
  const hb = await sha256(b);
  let diff = 0;
  for (let i = 0; i < ha.length; i++) diff |= ha[i] ^ hb[i];
  return diff === 0;
}

function changesOf(result) {
  return (result && result.meta && result.meta.changes) || 0;
}

function ensureSchema(db) {
  if (!schemaPromise) {
    schemaPromise = db
      .prepare(CREATE_TABLE_SQL)
      .run()
      .catch((err) => {
        schemaPromise = null;
        throw err;
      });
  }
  return schemaPromise;
}

function isNonNegInt(v) {
  return typeof v === 'number' && Number.isSafeInteger(v) && v >= 0;
}

function isBase64(s) {
  if (typeof s !== 'string' || s.length === 0 || s.length % 4 !== 0) {
    return false;
  }
  return BASE64_CHARS_RE.test(s);
}

async function readJsonBody(request) {
  const declared = Number(request.headers.get('Content-Length'));
  if (Number.isFinite(declared) && declared > MAX_REQUEST_CHARS) {
    throw new HttpError(413, 'too-large');
  }
  const text = await request.text();
  if (text.length > MAX_REQUEST_CHARS) throw new HttpError(413, 'too-large');
  let data;
  try {
    data = JSON.parse(text);
  } catch (_) {
    throw new HttpError(400, 'bad-json');
  }
  if (data === null || typeof data !== 'object' || Array.isArray(data)) {
    throw new HttpError(400, 'bad-json');
  }
  return data;
}

function checkBody(body) {
  if (typeof body !== 'string') throw new HttpError(400, 'bad-body');
  if (body.length > MAX_BODY_CHARS) throw new HttpError(413, 'too-large');
  if (!isBase64(body)) throw new HttpError(400, 'bad-body');
  return body;
}

// ---------------------------------------------------------------- Meta

async function getMeta(db, vault) {
  const row = await db
    .prepare("SELECT rev, body FROM objects WHERE vault = ? AND key = 'meta'")
    .bind(vault)
    .first();
  if (!row) throw new HttpError(404, 'no-vault');
  return json(200, { rev: row.rev, body: row.body });
}

async function putMeta(db, vault, request) {
  const data = await readJsonBody(request);
  if (!isNonNegInt(data.ifRev)) throw new HttpError(400, 'bad-field');
  const body = checkBody(data.body);
  const now = Date.now();
  const ifRev = data.ifRev;

  let result;
  if (ifRev === 0) {
    // Tresor neu anlegen: klappt nur, wenn es noch keine Meta gibt.
    result = await db
      .prepare(
        "INSERT INTO objects (vault, key, rev, stamp, darts, body, updated) " +
          "VALUES (?, 'meta', 1, 0, 0, ?, ?) " +
          'ON CONFLICT (vault, key) DO NOTHING'
      )
      .bind(vault, body, now)
      .run();
  } else {
    // Compare-and-set in einem einzigen Statement.
    result = await db
      .prepare(
        "UPDATE objects SET body = ?, rev = rev + 1, updated = ? " +
          "WHERE vault = ? AND key = 'meta' AND rev = ?"
      )
      .bind(body, now, vault, ifRev)
      .run();
  }
  if (changesOf(result) > 0) return json(200, { rev: ifRev + 1 });

  const cur = await db
    .prepare("SELECT rev FROM objects WHERE vault = ? AND key = 'meta'")
    .bind(vault)
    .first();
  return errorResponse(409, 'conflict', { rev: cur ? cur.rev : 0 });
}

// ------------------------------------------------------------ Sessions

async function getSession(db, vault, uid) {
  const row = await db
    .prepare('SELECT stamp, darts, body FROM objects WHERE vault = ? AND key = ?')
    .bind(vault, 's:' + uid)
    .first();
  if (!row) throw new HttpError(404, 'not-found');
  return json(200, { stamp: row.stamp, darts: row.darts, body: row.body });
}

async function putSession(db, vault, uid, request, maxSessions) {
  const data = await readJsonBody(request);
  if (!isNonNegInt(data.stamp) || !isNonNegInt(data.darts)) {
    throw new HttpError(400, 'bad-field');
  }
  const body = checkBody(data.body);
  const { stamp, darts } = data;
  const key = 's:' + uid;
  const now = Date.now();

  for (let attempt = 0; attempt < 3; attempt++) {
    // Normalfall (Objekt existiert, Stand ist neuer oder gleich): 1 Statement.
    const upd = await db
      .prepare(
        'UPDATE objects SET rev = rev + 1, stamp = ?, darts = ?, body = ?, updated = ? ' +
          'WHERE vault = ? AND key = ? AND (stamp < ? OR (stamp = ? AND darts <= ?))'
      )
      .bind(stamp, darts, body, now, vault, key, stamp, stamp, darts)
      .run();
    if (changesOf(upd) > 0) return json(200, { stored: true });

    // Nichts geaendert: entweder ist der gespeicherte Stand neuer oder es gibt
    // das Objekt noch nicht.
    const cur = await db
      .prepare('SELECT stamp, darts FROM objects WHERE vault = ? AND key = ?')
      .bind(vault, key)
      .first();
    if (cur) {
      const ours = stamp > cur.stamp || (stamp === cur.stamp && darts >= cur.darts);
      if (!ours) return json(200, { stored: false });
      continue; // zwischenzeitlich angelegt und unser Stand ist neuer: nochmal
    }

    // Neues Objekt: erst hier wird das Limit geprueft (Bereichsabfrage ueber
    // den Primaerschluessel, ohne die Meta-Zeile).
    const count = await db
      .prepare("SELECT COUNT(*) AS n FROM objects WHERE vault = ? AND key >= 's:' AND key < 's;'")
      .bind(vault)
      .first();
    if (count && count.n >= maxSessions) {
      throw new HttpError(413, 'too-many-sessions');
    }
    const ins = await db
      .prepare(
        'INSERT INTO objects (vault, key, rev, stamp, darts, body, updated) ' +
          'VALUES (?, ?, 1, ?, ?, ?, ?) ON CONFLICT (vault, key) DO NOTHING'
      )
      .bind(vault, key, stamp, darts, body, now)
      .run();
    if (changesOf(ins) > 0) return json(200, { stored: true });
    // Jemand war schneller: nochmal von vorn.
  }
  throw new HttpError(503, 'busy');
}

async function deleteSession(db, vault, uid) {
  const res = await db
    .prepare('DELETE FROM objects WHERE vault = ? AND key = ?')
    .bind(vault, 's:' + uid)
    .run();
  return json(200, { deleted: changesOf(res) > 0 });
}

// -------------------------------------------------------------- Routing

function parseMaxSessions(env) {
  const n = parseInt(env && env.MAX_SESSIONS, 10);
  return Number.isFinite(n) && n > 0 ? n : DEFAULT_MAX_SESSIONS;
}

function matchRoute(pathname) {
  if (pathname === '/v1/hello') return { name: 'hello', methods: ['GET'] };
  if (pathname === '/v1/meta') return { name: 'meta', methods: ['GET', 'PUT'] };
  if (pathname.startsWith('/v1/s/')) {
    return {
      name: 'session',
      uid: pathname.slice('/v1/s/'.length),
      methods: ['GET', 'PUT', 'DELETE'],
    };
  }
  return null;
}

async function handle(request, env) {
  if (env && env.SETUP_KEY) {
    const given = request.headers.get('X-Setup-Key') || '';
    if (!(await safeEqual(given, String(env.SETUP_KEY)))) {
      throw new HttpError(401, 'unauthorized');
    }
  }

  const route = matchRoute(new URL(request.url).pathname);
  if (!route) throw new HttpError(404, 'not-found');
  if (!route.methods.includes(request.method)) {
    throw new HttpError(405, 'method-not-allowed');
  }

  if (route.name === 'hello') {
    return json(200, { app: 'dartlab-cloud', version: VERSION });
  }

  const match = TOKEN_RE.exec(request.headers.get('Authorization') || '');
  if (!match) throw new HttpError(401, 'unauthorized');

  if (route.name === 'session' && !UID_RE.test(route.uid)) {
    throw new HttpError(400, 'bad-uid');
  }

  if (!env || !env.DB) throw new HttpError(500, 'db-missing');
  const db = env.DB;
  await ensureSchema(db);

  const vault = bytesToHex(await sha256(match[1].toLowerCase()));

  if (route.name === 'meta') {
    return request.method === 'GET' ? getMeta(db, vault) : putMeta(db, vault, request);
  }
  if (request.method === 'GET') return getSession(db, vault, route.uid);
  if (request.method === 'PUT') {
    return putSession(db, vault, route.uid, request, parseMaxSessions(env));
  }
  return deleteSession(db, vault, route.uid);
}

export default {
  async fetch(request, env) {
    try {
      return await handle(request, env);
    } catch (err) {
      if (err instanceof HttpError) {
        return errorResponse(err.status, err.code, err.extra);
      }
      // Keine Details nach aussen; im Cloudflare-Log steht nur die Meldung.
      console.error('internal error: ' + String(err && err.message));
      return errorResponse(500, 'internal');
    }
  },
};
