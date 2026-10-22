// Tests fuer cloud/worker.js. Ausfuehren: node --test cloud/test
// Das SQL laeuft echt: eine kleine D1-Attrappe auf node:sqlite.
import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { createHash } from 'node:crypto';

// ----------------------------------------------------------- D1-Attrappe

function makeD1() {
  const sqlite = new DatabaseSync(':memory:');
  const log = [];
  const tick = () => new Promise((resolve) => setImmediate(resolve));

  function runStatement(sql, args) {
    log.push(sql);
    const st = sqlite.prepare(sql);
    if (/^\s*select/i.test(sql)) {
      const rows = st.all(...args).map((r) => ({ ...r }));
      return { success: true, results: rows, meta: { changes: 0, rows_read: rows.length } };
    }
    const info = st.run(...args);
    return {
      success: true,
      results: [],
      meta: { changes: Number(info.changes), last_row_id: Number(info.lastInsertRowid) },
    };
  }

  function stmt(sql, args) {
    return {
      bind: (...a) => stmt(sql, a),
      // Jeder Aufruf gibt den Event-Loop frei, damit parallele Anfragen
      // wirklich zwischen den Statements durcheinanderlaufen koennen.
      async run() {
        await tick();
        return runStatement(sql, args);
      },
      async all() {
        await tick();
        return runStatement(sql, args);
      },
      async first(col) {
        await tick();
        const row = runStatement(sql, args).results[0] ?? null;
        return col && row ? row[col] : row;
      },
      _sql: sql,
      _args: args,
    };
  }

  return {
    prepare: (sql) => stmt(sql, []),
    async batch(stmts) {
      await tick();
      sqlite.exec('BEGIN');
      try {
        const out = stmts.map((s) => runStatement(s._sql, s._args));
        sqlite.exec('COMMIT');
        return out;
      } catch (e) {
        sqlite.exec('ROLLBACK');
        throw e;
      }
    },
    log,
    sqlite,
  };
}

// ------------------------------------------------------------- Helfer

let counter = 0;
async function setup(extraEnv = {}) {
  // Frische Modulinstanz pro Test (das Schema-Flag ist Modul-Zustand).
  const worker = (await import(`../worker.js?t=${counter++}`)).default;
  const db = makeD1();
  const env = { DB: db, ...extraEnv };
  const call = (method, path, { token, body, headers, raw } = {}) => {
    const h = { ...(headers || {}) };
    if (token) h.Authorization = `Bearer ${token}`;
    const init = { method, headers: h };
    if (raw !== undefined) init.body = raw;
    else if (body !== undefined) init.body = JSON.stringify(body);
    return worker.fetch(new Request('https://example.test' + path, init), env);
  };
  return { worker, db, env, call };
}

const T1 = 'a'.repeat(64);
const T2 = 'b'.repeat(64);
const B64 = Buffer.from('geheim').toString('base64');
const sha = (s) => createHash('sha256').update(s).digest('hex');

async function read(res) {
  return { status: res.status, json: await res.json(), res };
}

// -------------------------------------------------------------- Tests

test('hello: ohne Auth, mit Kopfzeile', async () => {
  const { call } = await setup();
  const { status, json, res } = await read(await call('GET', '/v1/hello'));
  assert.equal(status, 200);
  assert.deepEqual(json, { app: 'dartlab-cloud', version: 1 });
  assert.equal(res.headers.get('X-DartLab-Cloud'), '1');
});

test('hello braucht keine Datenbank', async () => {
  const worker = (await import(`../worker.js?t=${counter++}`)).default;
  const res = await worker.fetch(new Request('https://example.test/v1/hello'), {});
  assert.equal(res.status, 200);
});

test('fehlende Datenbank-Bindung -> 500 db-missing', async () => {
  const worker = (await import(`../worker.js?t=${counter++}`)).default;
  const res = await worker.fetch(
    new Request('https://example.test/v1/meta', { headers: { Authorization: `Bearer ${T1}` } }),
    {}
  );
  assert.equal(res.status, 500);
  assert.deepEqual(await res.json(), { error: 'db-missing' });
});

test('Auth: fehlendes oder kaputtes Token -> 401', async () => {
  const { call } = await setup();
  for (const headers of [
    undefined,
    { Authorization: 'Bearer ' },
    { Authorization: 'Bearer abc' },
    { Authorization: 'Bearer ' + 'g'.repeat(64) },
    { Authorization: 'Bearer ' + 'a'.repeat(63) },
    { Authorization: 'Bearer ' + 'a'.repeat(65) },
    { Authorization: 'Basic ' + 'a'.repeat(64) },
    { Authorization: T1 },
  ]) {
    for (const [m, p] of [
      ['GET', '/v1/meta'],
      ['PUT', '/v1/meta'],
      ['GET', '/v1/s/x'],
      ['PUT', '/v1/s/x'],
      ['DELETE', '/v1/s/x'],
    ]) {
      const { status, json, res } = await read(await call(m, p, { headers }));
      assert.equal(status, 401, `${m} ${p} ${JSON.stringify(headers)}`);
      assert.deepEqual(json, { error: 'unauthorized' });
      assert.equal(res.headers.get('X-DartLab-Cloud'), '1');
    }
  }
});

test('Token wird nicht gespeichert, Tresor = sha256 des Tokens', async () => {
  const { call, db } = await setup();
  await call('PUT', '/v1/meta', { token: T1, body: { ifRev: 0, body: B64 } });
  const rows = db.sqlite.prepare('SELECT * FROM objects').all();
  assert.equal(rows.length, 1);
  assert.equal(rows[0].vault, sha(T1));
  assert.ok(!JSON.stringify(rows).includes(T1));
  // Grossbuchstaben im Token ergeben denselben Tresor.
  const r = await read(await call('GET', '/v1/meta', { token: T1.toUpperCase() }));
  assert.equal(r.status, 200);
});

test('Meta: anlegen, lesen, fortschreiben', async () => {
  const { call } = await setup();
  let r = await read(await call('GET', '/v1/meta', { token: T1 }));
  assert.equal(r.status, 404);
  assert.deepEqual(r.json, { error: 'no-vault' });

  r = await read(await call('PUT', '/v1/meta', { token: T1, body: { ifRev: 0, body: B64 } }));
  assert.equal(r.status, 200);
  assert.deepEqual(r.json, { rev: 1 });

  r = await read(await call('GET', '/v1/meta', { token: T1 }));
  assert.deepEqual(r.json, { rev: 1, body: B64 });

  const b2 = Buffer.from('zwei').toString('base64');
  r = await read(await call('PUT', '/v1/meta', { token: T1, body: { ifRev: 1, body: b2 } }));
  assert.deepEqual(r.json, { rev: 2 });
  r = await read(await call('GET', '/v1/meta', { token: T1 }));
  assert.deepEqual(r.json, { rev: 2, body: b2 });
});

test('Meta: CAS-Konflikte', async () => {
  const { call } = await setup();
  await call('PUT', '/v1/meta', { token: T1, body: { ifRev: 0, body: B64 } });

  // Neu anlegen, obwohl es schon eine Meta gibt.
  let r = await read(await call('PUT', '/v1/meta', { token: T1, body: { ifRev: 0, body: B64 } }));
  assert.equal(r.status, 409);
  assert.deepEqual(r.json, { error: 'conflict', rev: 1 });

  // Falsche (zu alte und zu neue) rev.
  r = await read(await call('PUT', '/v1/meta', { token: T1, body: { ifRev: 5, body: B64 } }));
  assert.deepEqual(r.json, { error: 'conflict', rev: 1 });
  await call('PUT', '/v1/meta', { token: T1, body: { ifRev: 1, body: B64 } });
  r = await read(await call('PUT', '/v1/meta', { token: T1, body: { ifRev: 1, body: B64 } }));
  assert.equal(r.status, 409);
  assert.deepEqual(r.json, { error: 'conflict', rev: 2 });

  // Fortschreiben ohne Tresor: aktuelle rev ist 0.
  r = await read(await call('PUT', '/v1/meta', { token: T2, body: { ifRev: 3, body: B64 } }));
  assert.equal(r.status, 409);
  assert.deepEqual(r.json, { error: 'conflict', rev: 0 });
});

test('Meta: zwei gleichzeitige PUTs mit derselben ifRev, nur einer gewinnt', async () => {
  const { call } = await setup();
  const mk = (s) => Buffer.from(s).toString('base64');

  // Gleichzeitiges Anlegen (ifRev 0).
  let res = await Promise.all([
    call('PUT', '/v1/meta', { token: T1, body: { ifRev: 0, body: mk('A') } }),
    call('PUT', '/v1/meta', { token: T1, body: { ifRev: 0, body: mk('B') } }),
  ]);
  let codes = res.map((r) => r.status).sort();
  assert.deepEqual(codes, [200, 409]);

  // Gleichzeitiges Fortschreiben (ifRev 1).
  res = await Promise.all([
    call('PUT', '/v1/meta', { token: T1, body: { ifRev: 1, body: mk('C') } }),
    call('PUT', '/v1/meta', { token: T1, body: { ifRev: 1, body: mk('D') } }),
    call('PUT', '/v1/meta', { token: T1, body: { ifRev: 1, body: mk('E') } }),
  ]);
  codes = res.map((r) => r.status).sort();
  assert.deepEqual(codes, [200, 409, 409]);
  const loser = await res.find((r) => r.status === 409).json();
  assert.deepEqual(loser, { error: 'conflict', rev: 2 });

  const cur = await read(await call('GET', '/v1/meta', { token: T1 }));
  assert.equal(cur.json.rev, 2);
});

test('Tresor-Isolation: zwei Tokens sehen nichts voneinander', async () => {
  const { call } = await setup();
  await call('PUT', '/v1/meta', { token: T1, body: { ifRev: 0, body: B64 } });
  await call('PUT', '/v1/s/abc', { token: T1, body: { stamp: 10, darts: 1, body: B64 } });

  let r = await read(await call('GET', '/v1/meta', { token: T2 }));
  assert.equal(r.status, 404);
  r = await read(await call('GET', '/v1/s/abc', { token: T2 }));
  assert.equal(r.status, 404);
  r = await read(await call('DELETE', '/v1/s/abc', { token: T2 }));
  assert.deepEqual(r.json, { deleted: false });

  // T2 legt unter derselben uid etwas Eigenes an, T1 bleibt unberuehrt.
  const b2 = Buffer.from('anders').toString('base64');
  r = await read(await call('PUT', '/v1/s/abc', { token: T2, body: { stamp: 5, darts: 9, body: b2 } }));
  assert.deepEqual(r.json, { stored: true });
  r = await read(await call('GET', '/v1/s/abc', { token: T1 }));
  assert.deepEqual(r.json, { stamp: 10, darts: 1, body: B64 });
  r = await read(await call('GET', '/v1/s/abc', { token: T2 }));
  assert.deepEqual(r.json, { stamp: 5, darts: 9, body: b2 });
});

test('Session: anlegen, lesen, 404', async () => {
  const { call } = await setup();
  let r = await read(await call('GET', '/v1/s/neu', { token: T1 }));
  assert.equal(r.status, 404);
  assert.deepEqual(r.json, { error: 'not-found' });

  // Sessions gehen auch ohne Meta.
  r = await read(await call('PUT', '/v1/s/neu', { token: T1, body: { stamp: 100, darts: 3, body: B64 } }));
  assert.equal(r.status, 200);
  assert.deepEqual(r.json, { stored: true });
  r = await read(await call('GET', '/v1/s/neu', { token: T1 }));
  assert.deepEqual(r.json, { stamp: 100, darts: 3, body: B64 });
  // ... und die Meta bleibt davon unberuehrt.
  r = await read(await call('GET', '/v1/meta', { token: T1 }));
  assert.equal(r.status, 404);
});

test('Session-Ordnung: aelterer Stand ueberschreibt nicht', async () => {
  const { call } = await setup();
  const mk = (s) => Buffer.from(s).toString('base64');
  const put = async (stamp, darts, text) =>
    (await read(await call('PUT', '/v1/s/x', { token: T1, body: { stamp, darts, body: mk(text) } }))).json
      .stored;
  const get = async () => (await read(await call('GET', '/v1/s/x', { token: T1 }))).json;

  assert.equal(await put(100, 5, 'v1'), true);
  assert.equal(await put(99, 50, 'alt'), false); // aelterer Stamp
  assert.deepEqual(await get(), { stamp: 100, darts: 5, body: mk('v1') });
  assert.equal(await put(100, 4, 'weniger'), false); // gleicher Stamp, weniger Darts
  assert.deepEqual(await get(), { stamp: 100, darts: 5, body: mk('v1') });
  assert.equal(await put(100, 6, 'mehr'), true); // gleicher Stamp, mehr Darts
  assert.deepEqual(await get(), { stamp: 100, darts: 6, body: mk('mehr') });
  assert.equal(await put(100, 6, 'gleich'), true); // exakt gleich zaehlt (>=)
  assert.deepEqual(await get(), { stamp: 100, darts: 6, body: mk('gleich') });
  assert.equal(await put(101, 0, 'neuer'), true); // neuerer Stamp, weniger Darts
  assert.deepEqual(await get(), { stamp: 101, darts: 0, body: mk('neuer') });
  assert.equal(await put(0, 0, 'null'), false);
});

test('Session-PUT: Normalfall braucht nur ein Statement, GET eines', async () => {
  const { call, db } = await setup();
  await call('PUT', '/v1/s/x', { token: T1, body: { stamp: 1, darts: 1, body: B64 } });
  db.log.length = 0;
  await call('PUT', '/v1/s/x', { token: T1, body: { stamp: 2, darts: 1, body: B64 } });
  assert.equal(db.log.length, 1);
  assert.match(db.log[0], /^UPDATE/);
  db.log.length = 0;
  await call('GET', '/v1/s/x', { token: T1 });
  assert.equal(db.log.length, 1);
  db.log.length = 0;
  await call('PUT', '/v1/s/x', { token: T1, body: { stamp: 1, darts: 1, body: B64 } });
  assert.ok(!db.log.some((s) => /COUNT/i.test(s)), 'kein COUNT bei vorhandenem Key');
});

test('Session-PUT: gleichzeitige Uploads gleicher uid enden beim neuesten Stand', async () => {
  const { call } = await setup();
  const mk = (s) => Buffer.from(s).toString('base64');
  await Promise.all(
    [3, 1, 4, 2].map((n) =>
      call('PUT', '/v1/s/x', { token: T1, body: { stamp: n, darts: 0, body: mk('v' + n) } })
    )
  );
  const r = await read(await call('GET', '/v1/s/x', { token: T1 }));
  assert.deepEqual(r.json, { stamp: 4, darts: 0, body: mk('v4') });
});

test('DELETE ist idempotent', async () => {
  const { call } = await setup();
  await call('PUT', '/v1/s/x', { token: T1, body: { stamp: 1, darts: 1, body: B64 } });
  let r = await read(await call('DELETE', '/v1/s/x', { token: T1 }));
  assert.equal(r.status, 200);
  assert.deepEqual(r.json, { deleted: true });
  r = await read(await call('DELETE', '/v1/s/x', { token: T1 }));
  assert.equal(r.status, 200);
  assert.deepEqual(r.json, { deleted: false });
  r = await read(await call('GET', '/v1/s/x', { token: T1 }));
  assert.equal(r.status, 404);
  // Danach darf die uid wieder beschrieben werden, auch mit kleinem Stamp.
  r = await read(await call('PUT', '/v1/s/x', { token: T1, body: { stamp: 0, darts: 0, body: B64 } }));
  assert.deepEqual(r.json, { stored: true });
});

test('DELETE einer Session beruehrt die Meta nicht', async () => {
  const { call } = await setup();
  await call('PUT', '/v1/meta', { token: T1, body: { ifRev: 0, body: B64 } });
  await call('DELETE', '/v1/s/meta', { token: T1 });
  const r = await read(await call('GET', '/v1/meta', { token: T1 }));
  assert.equal(r.status, 200);
});

test('Groessenlimit: 1,5 MB base64 geht, mehr gibt 413', async () => {
  const { call } = await setup();
  const ok = 'QUJD'.repeat(375000); // exakt 1.500.000 Zeichen
  assert.equal(ok.length, 1500000);
  let r = await read(await call('PUT', '/v1/s/big', { token: T1, body: { stamp: 1, darts: 1, body: ok } }));
  assert.equal(r.status, 200);
  assert.deepEqual(r.json, { stored: true });
  r = await read(await call('GET', '/v1/s/big', { token: T1 }));
  assert.equal(r.json.body.length, 1500000);

  const tooBig = 'QUJD'.repeat(375001);
  for (const [path, body] of [
    ['/v1/s/big2', { stamp: 1, darts: 1, body: tooBig }],
    ['/v1/meta', { ifRev: 0, body: tooBig }],
  ]) {
    r = await read(await call('PUT', path, { token: T1, body }));
    assert.equal(r.status, 413, path);
    assert.deepEqual(r.json, { error: 'too-large' });
  }
  // Riesige Anfrage ohne passenden JSON-Aufbau: ebenfalls 413.
  r = await read(await call('PUT', '/v1/s/big3', { token: T1, raw: 'x'.repeat(2000000) }));
  assert.equal(r.status, 413);
  r = await read(await call('GET', '/v1/s/big2', { token: T1 }));
  assert.equal(r.status, 404);
});

test('ungueltige uid -> 400', async () => {
  const { call } = await setup();
  const good = { stamp: 1, darts: 1, body: B64 };
  for (const uid of ['', 'a'.repeat(65), 'a b', 'a.b', 'a/b', 'a%41', 'ü', 'a:b']) {
    for (const method of ['GET', 'PUT', 'DELETE']) {
      const r = await read(
        await call(method, '/v1/s/' + uid, { token: T1, body: method === 'PUT' ? good : undefined })
      );
      assert.equal(r.status, 400, `${method} "${uid}"`);
      assert.deepEqual(r.json, { error: 'bad-uid' });
    }
  }
  for (const uid of ['a', 'A-z_09', 'a'.repeat(64)]) {
    const r = await read(await call('PUT', '/v1/s/' + uid, { token: T1, body: good }));
    assert.equal(r.status, 200, uid);
  }
});

test('ungueltiges base64, JSON und Felder -> 400', async () => {
  const { call } = await setup();
  const put = (path, body, raw) => call('PUT', path, { token: T1, body, raw });

  for (const b of ['', 'abc', 'abcd=', 'ab=c', 'a===', '!!!!', 'ab cd', 'QUJD\n', 12, null, ['QUJD']]) {
    let r = await read(await put('/v1/s/x', { stamp: 1, darts: 1, body: b }));
    assert.equal(r.status, 400, JSON.stringify(b));
    assert.deepEqual(r.json, { error: 'bad-body' });
    r = await read(await put('/v1/meta', { ifRev: 0, body: b }));
    assert.equal(r.status, 400, JSON.stringify(b));
  }
  // Gueltig: Padding mit = und ==
  for (const b of ['QUI=', 'QQ==', 'QUJD']) {
    const r = await read(await put('/v1/s/x', { stamp: 1, darts: 1, body: b }));
    assert.equal(r.status, 200, b);
  }
  let r = await read(await put('/v1/s/x', undefined, 'kein json'));
  assert.equal(r.status, 400);
  assert.deepEqual(r.json, { error: 'bad-json' });
  for (const raw of ['', '[]', 'null', '"x"', '12']) {
    r = await read(await put('/v1/s/x', undefined, raw));
    assert.deepEqual(r.json, { error: 'bad-json' }, raw);
    r = await read(await put('/v1/meta', undefined, raw));
    assert.deepEqual(r.json, { error: 'bad-json' }, raw);
  }

  const badNums = [-1, 1.5, '1', null, 2 ** 53, 1e300, true];
  for (const n of badNums) {
    r = await read(await put('/v1/s/x', { stamp: n, darts: 1, body: B64 }));
    assert.equal(r.status, 400, `stamp ${n}`);
    assert.deepEqual(r.json, { error: 'bad-field' });
    r = await read(await put('/v1/s/x', { stamp: 1, darts: n, body: B64 }));
    assert.equal(r.status, 400, `darts ${n}`);
    r = await read(await put('/v1/meta', { ifRev: n, body: B64 }));
    assert.equal(r.status, 400, `ifRev ${n}`);
  }
  r = await read(await put('/v1/s/x', { darts: 1, body: B64 }));
  assert.equal(r.status, 400);
  r = await read(await put('/v1/meta', { body: B64 }));
  assert.equal(r.status, 400);
  // Obergrenze 2^53 - 1 ist erlaubt.
  r = await read(await put('/v1/s/x', { stamp: 2 ** 53 - 1, darts: 0, body: B64 }));
  assert.equal(r.status, 200);
});

test('unbekannte Pfade 404, falsche Methoden 405', async () => {
  const { call } = await setup();
  for (const p of ['/', '/v1', '/v1/', '/v2/hello', '/v1/unknown', '/v1/meta/', '/v1/hello/x', '/hello']) {
    const r = await read(await call('GET', p, { token: T1 }));
    assert.equal(r.status, 404, p);
    assert.deepEqual(r.json, { error: 'not-found' });
    assert.equal(r.res.headers.get('X-DartLab-Cloud'), '1');
  }
  for (const [m, p] of [
    ['POST', '/v1/hello'],
    ['PUT', '/v1/hello'],
    ['DELETE', '/v1/meta'],
    ['POST', '/v1/meta'],
    ['POST', '/v1/s/x'],
    ['PATCH', '/v1/s/x'],
    ['DELETE', '/v1/hello'],
  ]) {
    const r = await read(await call(m, p, { token: T1 }));
    assert.equal(r.status, 405, `${m} ${p}`);
    assert.deepEqual(r.json, { error: 'method-not-allowed' });
  }
});

test('SETUP_KEY aus: X-Setup-Key wird ignoriert', async () => {
  const { call } = await setup();
  let r = await read(await call('GET', '/v1/hello', { headers: { 'X-Setup-Key': 'egal' } }));
  assert.equal(r.status, 200);
  r = await read(await call('GET', '/v1/meta', { token: T1 }));
  assert.equal(r.status, 404);
});

test('SETUP_KEY an: jede Anfrage braucht den Header', async () => {
  const { call } = await setup({ SETUP_KEY: 'geheim-123' });
  const good = { 'X-Setup-Key': 'geheim-123' };

  for (const headers of [undefined, { 'X-Setup-Key': '' }, { 'X-Setup-Key': 'falsch' }, { 'X-Setup-Key': 'geheim-12' }, { 'X-Setup-Key': 'geheim-1234' }]) {
    for (const [m, p] of [
      ['GET', '/v1/hello'],
      ['GET', '/v1/meta'],
      ['GET', '/v1/s/x'],
      ['GET', '/v1/unbekannt'],
    ]) {
      const r = await read(await call(m, p, { token: T1, headers }));
      assert.equal(r.status, 401, `${m} ${p} ${JSON.stringify(headers)}`);
      assert.deepEqual(r.json, { error: 'unauthorized' });
      assert.equal(r.res.headers.get('X-DartLab-Cloud'), '1');
    }
  }

  let r = await read(await call('GET', '/v1/hello', { headers: good }));
  assert.equal(r.status, 200);
  r = await read(await call('PUT', '/v1/meta', { token: T1, headers: good, body: { ifRev: 0, body: B64 } }));
  assert.deepEqual(r.json, { rev: 1 });
  r = await read(await call('GET', '/v1/meta', { token: T1, headers: good }));
  assert.equal(r.status, 200);
  // Setup-Key ersetzt das Token nicht.
  r = await read(await call('GET', '/v1/meta', { headers: good }));
  assert.equal(r.status, 401);
});

test('Session-Limit pro Tresor (MAX_SESSIONS)', async () => {
  const { call } = await setup({ MAX_SESSIONS: '3' });
  const put = (token, uid, stamp = 1) =>
    call('PUT', '/v1/s/' + uid, { token, body: { stamp, darts: 0, body: B64 } });

  // Meta zaehlt nicht mit.
  await call('PUT', '/v1/meta', { token: T1, body: { ifRev: 0, body: B64 } });
  for (const uid of ['a', 'b', 'c']) assert.equal((await put(T1, uid)).status, 200);

  let r = await read(await put(T1, 'd'));
  assert.equal(r.status, 413);
  assert.deepEqual(r.json, { error: 'too-many-sessions' });
  assert.equal((await call('GET', '/v1/s/d', { token: T1 })).status, 404);

  // Bestehende Objekte duerfen weiter aktualisiert werden.
  r = await read(await put(T1, 'a', 2));
  assert.deepEqual(r.json, { stored: true });
  r = await read(await put(T1, 'a', 1));
  assert.deepEqual(r.json, { stored: false });

  // Anderer Tresor hat sein eigenes Limit.
  assert.equal((await put(T2, 'd')).status, 200);

  // Nach dem Loeschen ist wieder Platz.
  await call('DELETE', '/v1/s/b', { token: T1 });
  assert.equal((await put(T1, 'd')).status, 200);
  assert.equal((await put(T1, 'e')).status, 413);
});

test('Standard-Limit ist 50000 und MAX_SESSIONS=Unsinn faellt darauf zurueck', async () => {
  const { call, db } = await setup({ MAX_SESSIONS: 'abc' });
  // 49999 Zeilen direkt in die DB schreiben, dann den 50000. und 50001. versuchen.
  await call('GET', '/v1/hello'); // Schema wird erst bei DB-Zugriff angelegt:
  await call('GET', '/v1/meta', { token: T1 });
  const vault = sha(T1);
  db.sqlite.exec('BEGIN');
  const ins = db.sqlite.prepare(
    "INSERT INTO objects (vault, key, body, updated) VALUES (?, ?, 'QUJD', 0)"
  );
  for (let i = 0; i < 49999; i++) ins.run(vault, 's:f' + i);
  db.sqlite.exec('COMMIT');
  const put = (uid) => call('PUT', '/v1/s/' + uid, { token: T1, body: { stamp: 1, darts: 0, body: B64 } });
  assert.equal((await put('last')).status, 200);
  assert.equal((await put('over')).status, 413);
});

test('Fehlerantworten verraten keine Interna', async () => {
  const { call, env } = await setup();
  await call('GET', '/v1/meta', { token: T1 }); // Schema anlegen
  env.DB.prepare = () => {
    throw new Error('SQLITE_SECRET_DETAIL at /srv/x.js:12');
  };
  const origError = console.error;
  console.error = () => {};
  try {
    const r = await read(await call('GET', '/v1/meta', { token: T1 }));
    assert.equal(r.status, 500);
    assert.deepEqual(r.json, { error: 'internal' });
  } finally {
    console.error = origError;
  }
});

test('Schema wird nur einmal pro Instanz angelegt', async () => {
  const { call, db } = await setup();
  await call('GET', '/v1/meta', { token: T1 });
  await call('GET', '/v1/meta', { token: T1 });
  await call('GET', '/v1/s/x', { token: T1 });
  assert.equal(db.log.filter((s) => /CREATE TABLE/i.test(s)).length, 1);
});
