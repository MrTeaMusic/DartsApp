// ==UserScript==
// @name         DartLab für Autodarts
// @namespace    dartlab
// @version      1.0.0
// @description  Schickt fertige Online-Matches von play.autodarts.com an deine lokale DartLab-App. Liest nur mit, was die Seite ohnehin bekommt.
// @match        https://play.autodarts.com/*
// @match        https://play.autodarts.io/*
// @run-at       document-start
// @grant        GM_getValue
// @grant        GM_setValue
// @grant        GM_registerMenuCommand
// @grant        GM_xmlhttpRequest
// @grant        GM_setClipboard
// @grant        unsafeWindow
// @connect      localhost
// @connect      127.0.0.1
// @noframes
// ==/UserScript==

/*
 * DartLab für Autodarts
 * =====================
 *
 * Was das Skript tut
 *   Es schaut passiv zu, was die Autodarts-Seite in DEINEM Browser ohnehin
 *   lädt. Kommt die Antwort auf
 *     /as/v0/matches/<id>/stats            (Match-Statistik) oder
 *     /gs/v0/matches/<id>/state            (nur wenn das Match zu Ende ist)
 *   mit den Feldern "players" und "games", schickt es genau diese Antwort
 *   (den JSON-Text) per POST an die DartLab-App auf DIESEM Rechner
 *   (http://127.0.0.1:<Port>/import/autodarts).
 *
 * Was das Skript NICHT tut
 *   - Es stellt keine eigenen Anfragen an Autodarts.
 *   - Es liest keine Header, keine Cookies, keinen localStorage, kein
 *     Token und nichts aus "Authorization".
 *   - Es lädt keine fremden Skripte nach und sendet nichts an Dritte.
 *     Das einzige Ziel ist die eingestellte lokale Adresse (127.0.0.1 oder
 *     localhost, sonst verweigert das Skript das Senden).
 *
 * Wozu die Rechte (@grant) gebraucht werden
 *   GM_getValue / GM_setValue   Adresse und Code der App speichern.
 *   GM_registerMenuCommand      Menü "DartLab einrichten" usw.
 *   GM_xmlhttpRequest           Rückfall zum Senden an 127.0.0.1, falls der
 *                               Browser das normale Senden blockiert
 *                               (@connect erlaubt nur localhost/127.0.0.1).
 *   GM_setClipboard             "DartLab: Match kopieren".
 *   unsafeWindow                Nur damit fetch und XMLHttpRequest der SEITE
 *                               mitgelesen werden können (ohne das sieht das
 *                               Skript die Antworten der Seite nicht).
 */

(function () {
  'use strict';

  var DEFAULT_URL = 'http://127.0.0.1:3191';
  var KEY_URL = 'dartlab.url';
  var KEY_CODE = 'dartlab.code';
  var MAX_BYTES = 2 * 1024 * 1024; // Obergrenze der App
  var STATE_GRACE_MS = 4000; // /state wartet kurz auf die vollständigere /stats-Antwort
  var SEND_TIMEOUT_MS = 10000;

  // -------------------------------------------------------------------
  // Reine Hilfsfunktionen (ohne Zugriff auf die Seite)
  // -------------------------------------------------------------------

  /**
   * Erkennt die beiden Adressen, die uns interessieren.
   * Gibt { kind: 'stats' | 'state', id } zurück oder null.
   */
  function classifyUrl(raw, baseHref) {
    var u;
    try {
      u = new URL(String(raw), baseHref || 'https://play.autodarts.com/');
    } catch (e) {
      return null;
    }
    if (u.protocol !== 'https:') return null;
    var host = u.hostname.toLowerCase();
    if (!/(^|\.)autodarts\.(com|io)$/.test(host)) return null;
    var m = /^\/as\/v0\/matches\/([A-Za-z0-9_-]{1,80})\/stats\/?$/.exec(u.pathname);
    if (m) return { kind: 'stats', id: m[1] };
    m = /^\/gs\/v0\/matches\/([A-Za-z0-9_-]{1,80})\/state\/?$/.exec(u.pathname);
    if (m) return { kind: 'state', id: m[1] };
    return null;
  }

  /** Nur lokale Ziele: http://127.0.0.1:<Port> oder http://localhost:<Port>. */
  function checkTarget(raw) {
    var u;
    try {
      u = new URL(String(raw || '').trim());
    } catch (e) {
      return { ok: false, reason: 'Das ist keine Adresse.' };
    }
    if (u.protocol !== 'http:') return { ok: false, reason: 'Die Adresse muss mit http:// beginnen.' };
    var host = u.hostname.toLowerCase();
    if (host !== '127.0.0.1' && host !== 'localhost') {
      return { ok: false, reason: 'Nur 127.0.0.1 oder localhost sind erlaubt (die App läuft auf diesem Rechner).' };
    }
    var port = u.port === '' ? 80 : Number(u.port);
    if (!(port >= 1024 && port <= 65535)) return { ok: false, reason: 'Der Port muss zwischen 1024 und 65535 liegen.' };
    return { ok: true, base: u.protocol + '//' + u.hostname + ':' + port };
  }

  /** Ist das ein fertiges Match mit Spielern und Legs? */
  function inspectMatch(kind, json) {
    if (!json || typeof json !== 'object' || Array.isArray(json)) return { ok: false };
    if (!Array.isArray(json.players) || !Array.isArray(json.games)) return { ok: false };
    if (json.players.length === 0 || json.games.length === 0) return { ok: false };
    if (kind === 'state') return { ok: json.finished === true };
    // /stats: wird auch während des Spiels geladen; ein ausdrücklich offenes Match überspringen.
    if (json.finished === false) return { ok: false };
    return { ok: true };
  }

  /** Für "Match kopieren": der Text bleibt wie geliefert; fehlt die Id, kommt sie dazu. */
  function withId(text, json, id) {
    if (json && typeof json === 'object' && json.id) return text;
    var copy = {};
    Object.keys(json).forEach(function (k) {
      copy[k] = json[k];
    });
    copy.id = id;
    return JSON.stringify(copy);
  }

  function describe(status, body) {
    var name = body && body.opponent ? ' gegen ' + body.opponent : '';
    var legs = body && body.legs ? ' (' + body.legs + ')' : '';
    switch (status) {
      case 'imported':
        return { state: 'ok', text: 'In DartLab gespeichert' + name + legs + '.' };
      case 'duplicate':
        return { state: 'ok', text: 'Dieses Match ist schon in DartLab.' };
      case 'ignored':
        return { state: 'info', text: 'Nicht importiert' + (body && body.message ? ': ' + body.message : ' (kein X01-Match).') };
      case 'pending':
        return { state: 'info', text: 'DartLab fragt nach, welcher Spieler du bist. Bitte in der App antworten.' };
      default:
        return { state: 'error', text: 'Unerwartete Antwort von DartLab.' };
    }
  }

  function describeHttp(code) {
    switch (code) {
      case 401:
        return 'Falscher Code. Im Menü „DartLab einrichten“ den Code aus den DartLab-Optionen eintragen.';
      case 403:
        return 'DartLab hat die Anfrage abgelehnt (falsche Adresse?).';
      case 413:
        return 'Das Match ist zu groß für DartLab.';
      case 415:
      case 400:
        return 'DartLab konnte die Daten nicht lesen.';
      case 422:
        return 'DartLab kann dieses Match nicht lesen (Format unbekannt).';
      case 429:
        return 'Zu viele Anfragen. Bitte kurz warten.';
      default:
        return 'DartLab antwortet mit Fehler ' + code + '.';
    }
  }

  var NOT_REACHABLE =
    'DartLab ist nicht erreichbar. Läuft die App, ist „Empfänger einschalten“ an und stimmen Adresse und Port?';

  // -------------------------------------------------------------------
  // Kern: hängt sich in die Seite und schickt Treffer weiter
  // -------------------------------------------------------------------

  /**
   * env:
   *   page            Fenster der Seite (fetch, XMLHttpRequest, location)
   *   ownFetch        fetch für die eigenen Anfragen an die App (vor dem Einhängen gesichert)
   *   gmRequest       GM_xmlhttpRequest (optional)
   *   getValue/setValue   Speicher des Skripts
   *   registerMenu    GM_registerMenuCommand
   *   setClipboard    GM_setClipboard oder Ersatz
   *   ask             Eingabefenster (prompt)
   *   show            Anzeige { state: 'busy'|'ok'|'info'|'error', text }
   *   setTimeout      Zeitgeber
   *   exportFunction  nur Firefox-Skriptmanager (optional)
   */
  function install(env) {
    var page = env.page;
    var timer = env.setTimeout || setTimeout;
    var done = {}; // Match-Ids, die DartLab bereits beantwortet hat
    var waiting = {}; // /state-Treffer, die auf /stats warten
    var last = null; // zuletzt gesehenes fertiges Match { id, text, json }

    function show(state, text) {
      try {
        if (env.show) env.show({ state: state, text: text });
      } catch (e) {
        /* Anzeige ist nie wichtig genug, um etwas zu stören */
      }
    }

    function config() {
      var url = env.getValue(KEY_URL, DEFAULT_URL);
      var code = env.getValue(KEY_CODE, '');
      return { url: url || DEFAULT_URL, code: String(code || '').trim() };
    }

    // ---- Senden -------------------------------------------------------

    function request(target, code, id, text) {
      var url = target.base + '/import/autodarts?id=' + encodeURIComponent(id);
      var headers = { 'Content-Type': 'application/json', 'X-DartLab-Key': code };
      return new Promise(function (resolve, reject) {
        function viaGm() {
          if (!env.gmRequest) return reject(new Error('unreachable'));
          try {
            env.gmRequest({
              method: 'POST',
              url: url,
              headers: headers,
              data: text,
              anonymous: true,
              timeout: SEND_TIMEOUT_MS,
              onload: function (r) {
                resolve({ status: r.status, text: r.responseText });
              },
              onerror: function () {
                reject(new Error('unreachable'));
              },
              ontimeout: function () {
                reject(new Error('unreachable'));
              },
            });
          } catch (e) {
            reject(e);
          }
        }
        if (!env.ownFetch) return viaGm();
        var p;
        try {
          p = env.ownFetch(url, {
            method: 'POST',
            headers: headers,
            body: text,
            mode: 'cors',
            credentials: 'omit',
            cache: 'no-store',
            referrerPolicy: 'no-referrer',
          });
        } catch (e) {
          return viaGm();
        }
        Promise.resolve(p).then(function (res) {
          return res.text().then(
            function (t) {
              resolve({ status: res.status, text: t });
            },
            function () {
              resolve({ status: res.status, text: '' });
            }
          );
        }, viaGm);
      });
    }

    function send(id, text) {
      var cfg = config();
      var target = checkTarget(cfg.url);
      if (!target.ok) {
        show('error', target.reason + ' Im Menü „DartLab einrichten“ ändern.');
        return Promise.resolve(false);
      }
      if (!cfg.code) {
        show('error', 'Der Code fehlt. Im Menü „DartLab einrichten“ den Code aus den DartLab-Optionen eintragen.');
        return Promise.resolve(false);
      }
      show('busy', 'Sende an DartLab …');
      return request(target, cfg.code, id, text).then(
        function (res) {
          if (res.status >= 200 && res.status < 300) {
            var body = null;
            try {
              body = JSON.parse(res.text);
            } catch (e) {
              /* leere Antwort */
            }
            var d = describe(body && body.status, body);
            show(d.state, d.text);
            if (d.state !== 'error') done[id] = true;
            return d.state !== 'error';
          }
          show('error', describeHttp(res.status));
          return false;
        },
        function () {
          show('error', NOT_REACHABLE);
          return false;
        }
      );
    }

    // ---- Treffer verarbeiten -----------------------------------------

    function remember(id, text, json, kind) {
      // /stats ist vollständiger als /state; ein späterer /state überschreibt es nicht.
      if (last && last.id === id && last.kind === 'stats' && kind === 'state') return;
      last = { id: id, text: text, json: json, kind: kind };
    }

    function handle(hit, text) {
      if (typeof text !== 'string' || text.length === 0 || text.length > MAX_BYTES) return;
      var json;
      try {
        json = JSON.parse(text);
      } catch (e) {
        return;
      }
      if (!inspectMatch(hit.kind, json).ok) return;
      var id = hit.id;
      remember(id, text, json, hit.kind);
      if (done[id]) return;
      if (hit.kind === 'stats') {
        delete waiting[id];
        send(id, text);
        return;
      }
      // /state: kurz warten, ob die vollständige /stats-Antwort nachkommt.
      if (waiting[id]) return;
      waiting[id] = true;
      timer(function () {
        if (!waiting[id]) return;
        delete waiting[id];
        if (!done[id]) send(id, text);
      }, STATE_GRACE_MS);
    }

    function safe(fn) {
      return function () {
        try {
          return fn.apply(this, arguments);
        } catch (e) {
          /* Das Mitlesen darf die Seite nie stören */
        }
      };
    }

    function exported(fn) {
      return typeof env.exportFunction === 'function' ? env.exportFunction(fn, page) : fn;
    }

    var base = (page.location && page.location.href) || 'https://play.autodarts.com/';

    // ---- fetch der Seite mitlesen ------------------------------------

    if (typeof page.fetch === 'function') {
      var origFetch = page.fetch;
      page.fetch = exported(function () {
        var result = origFetch.apply(this === undefined || this === null ? page : this, arguments);
        try {
          var input = arguments[0];
          var raw = typeof input === 'string' ? input : input && (input.url || input.href) ? input.url || input.href : String(input);
          var hit = classifyUrl(raw, base);
          if (hit) {
            Promise.resolve(result).then(
              safe(function (res) {
                if (!res || !res.ok) return;
                // Nur der Antwort-Text; Header werden nie angefasst.
                res
                  .clone()
                  .text()
                  .then(
                    safe(function (text) {
                      handle(hit, text);
                    }),
                    function () {}
                  );
              }),
              function () {}
            );
          }
        } catch (e) {
          /* ignorieren */
        }
        return result;
      });
    }

    // ---- XMLHttpRequest der Seite mitlesen ---------------------------

    var XHR = page.XMLHttpRequest;
    if (XHR && XHR.prototype && typeof XHR.prototype.open === 'function' && typeof XHR.prototype.send === 'function') {
      var urls = typeof WeakMap === 'function' ? new WeakMap() : null;
      var origOpen = XHR.prototype.open;
      var origSend = XHR.prototype.send;
      XHR.prototype.open = exported(function (method, url) {
        try {
          if (urls) urls.set(this, String(url));
        } catch (e) {
          /* ignorieren */
        }
        return origOpen.apply(this, arguments);
      });
      XHR.prototype.send = exported(function () {
        try {
          var raw = urls && urls.get(this);
          var hit = raw ? classifyUrl(raw, base) : null;
          if (hit) {
            var xhr = this;
            xhr.addEventListener(
              'load',
              safe(function () {
                if (xhr.status < 200 || xhr.status >= 300) return;
                var type = xhr.responseType;
                if (type === '' || type === 'text') handle(hit, xhr.responseText);
                else if (type === 'json' && xhr.response) handle(hit, JSON.stringify(xhr.response));
              })
            );
          }
        } catch (e) {
          /* ignorieren */
        }
        return origSend.apply(this, arguments);
      });
    }

    // ---- Menü ---------------------------------------------------------

    function setup() {
      var cfg = config();
      var url = env.ask('Adresse der DartLab-App (nur dieser Rechner):', cfg.url);
      if (url === null || url === undefined) return;
      var target = checkTarget(url);
      if (!target.ok) {
        show('error', target.reason);
        return;
      }
      var code = env.ask('Code aus den DartLab-Optionen (6 Ziffern):', cfg.code);
      if (code === null || code === undefined) return;
      code = String(code).trim();
      if (!/^[0-9]{6}$/.test(code)) {
        show('error', 'Der Code besteht aus 6 Ziffern.');
        return;
      }
      env.setValue(KEY_URL, target.base);
      env.setValue(KEY_CODE, code);
      show('ok', 'Gespeichert. Mit „DartLab: Verbindung testen“ prüfst du die Verbindung.');
    }

    function copyLast() {
      if (!last) {
        show('info', 'Noch kein fertiges Match gesehen. Öffne ein beendetes Match auf Autodarts und versuche es noch einmal.');
        return;
      }
      var text = withId(last.text, last.json, last.id);
      var ok = true;
      try {
        if (env.setClipboard) env.setClipboard(text);
        else ok = false;
      } catch (e) {
        ok = false;
      }
      show(ok ? 'ok' : 'error', ok ? 'Match kopiert. In DartLab: Optionen › „Match-JSON einfügen“.' : 'Kopieren hat nicht geklappt.');
    }

    function resend() {
      if (!last) {
        show('info', 'Noch kein fertiges Match gesehen.');
        return;
      }
      delete done[last.id];
      send(last.id, last.text);
    }

    function test() {
      var cfg = config();
      var target = checkTarget(cfg.url);
      if (!target.ok) {
        show('error', target.reason);
        return;
      }
      show('busy', 'Teste Verbindung …');
      var url = target.base + '/import/ping';
      var headers = { 'X-DartLab-Key': cfg.code };
      function report(status) {
        if (status === 200) show('ok', 'Verbindung steht. DartLab antwortet.');
        else show('error', describeHttp(status));
      }
      function viaGm() {
        if (!env.gmRequest) return show('error', NOT_REACHABLE);
        env.gmRequest({
          method: 'GET',
          url: url,
          headers: headers,
          anonymous: true,
          timeout: SEND_TIMEOUT_MS,
          onload: function (r) {
            report(r.status);
          },
          onerror: function () {
            show('error', NOT_REACHABLE);
          },
          ontimeout: function () {
            show('error', NOT_REACHABLE);
          },
        });
      }
      if (!env.ownFetch) return viaGm();
      Promise.resolve(env.ownFetch(url, { method: 'GET', headers: headers, mode: 'cors', credentials: 'omit', cache: 'no-store' })).then(
        function (res) {
          report(res.status);
        },
        viaGm
      );
    }

    if (env.registerMenu) {
      env.registerMenu('DartLab einrichten', setup);
      env.registerMenu('DartLab: Match kopieren', copyLast);
      env.registerMenu('DartLab: Verbindung testen', test);
      env.registerMenu('DartLab: letztes Match erneut senden', resend);
    }

    return { setup: setup, copyLast: copyLast, resend: resend, test: test, handle: handle, state: function () { return { done: done, last: last }; } };
  }

  // -------------------------------------------------------------------
  // Kleine Statusanzeige (nur im Browser)
  // -------------------------------------------------------------------

  function createBadge(win) {
    var doc = win.document;
    var root = null;
    var dot = null;
    var label = null;
    var hideTimer = null;
    var COLORS = { ok: '#2e9e5b', error: '#d64545', busy: '#8a8f98', info: '#d9a21b' };
    var SYMBOL = { ok: '✓', error: '!', busy: '…', info: 'i' };

    function build() {
      if (root || !doc.body) return !!root;
      root = doc.createElement('div');
      root.setAttribute('data-dartlab', 'status');
      root.style.cssText =
        'position:fixed;right:12px;bottom:12px;z-index:2147483647;display:flex;align-items:center;gap:8px;' +
        'font:13px/1.3 system-ui,sans-serif;color:#fff;pointer-events:none;';
      label = doc.createElement('span');
      label.style.cssText =
        'display:none;max-width:320px;padding:6px 10px;border-radius:8px;background:rgba(20,22,28,0.92);pointer-events:auto;';
      dot = doc.createElement('span');
      dot.style.cssText =
        'width:26px;height:26px;border-radius:50%;display:flex;align-items:center;justify-content:center;' +
        'font-weight:700;cursor:pointer;pointer-events:auto;box-shadow:0 1px 4px rgba(0,0,0,0.4);';
      dot.addEventListener('click', function () {
        label.style.display = label.style.display === 'none' ? 'block' : 'none';
      });
      root.appendChild(label);
      root.appendChild(dot);
      doc.body.appendChild(root);
      return true;
    }

    return function show(s) {
      function apply() {
        if (!build()) return;
        dot.style.background = COLORS[s.state] || COLORS.info;
        dot.textContent = SYMBOL[s.state] || 'i';
        dot.title = s.text;
        label.textContent = 'DartLab: ' + s.text;
        label.style.display = 'block';
        root.style.opacity = '1';
        if (hideTimer) win.clearTimeout(hideTimer);
        // Fehler bleiben stehen; alles andere zieht sich nach ein paar Sekunden zurück.
        if (s.state === 'ok' || s.state === 'info') {
          hideTimer = win.setTimeout(function () {
            label.style.display = 'none';
            root.style.opacity = '0.55';
          }, 6000);
        }
      }
      if (doc.body) apply();
      else doc.addEventListener('DOMContentLoaded', apply, { once: true });
    };
  }

  function boot() {
    var page = typeof unsafeWindow !== 'undefined' ? unsafeWindow : window;
    // Eigene Anfragen an die App laufen NICHT über das eingehängte fetch der Seite.
    var ownFetch = typeof fetch === 'function' ? fetch.bind(window) : null;
    install({
      page: page,
      ownFetch: ownFetch,
      gmRequest: typeof GM_xmlhttpRequest === 'function' ? GM_xmlhttpRequest : null,
      getValue: GM_getValue,
      setValue: GM_setValue,
      registerMenu: GM_registerMenuCommand,
      setClipboard: typeof GM_setClipboard === 'function' ? GM_setClipboard : null,
      ask: function (message, def) {
        return page.prompt(message, def);
      },
      show: createBadge(page),
      setTimeout: function (fn, ms) {
        return window.setTimeout(fn, ms);
      },
      exportFunction: typeof exportFunction === 'function' ? exportFunction : undefined,
    });
  }

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
      install: install,
      classifyUrl: classifyUrl,
      checkTarget: checkTarget,
      inspectMatch: inspectMatch,
      withId: withId,
      DEFAULT_URL: DEFAULT_URL,
      KEY_URL: KEY_URL,
      KEY_CODE: KEY_CODE,
      STATE_GRACE_MS: STATE_GRACE_MS,
    };
  } else {
    boot();
  }
})();
