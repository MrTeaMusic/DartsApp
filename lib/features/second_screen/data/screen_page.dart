/// Browser-Seite des zweiten Bildschirms (z. B. für den Browser eines
/// Smart-TVs): nur lesen, keine Schreib-Endpunkte, alle Texte über
/// `textContent` (Spielernamen werden nie als HTML eingesetzt).
library;

/// Sicherheitsregeln für beide Seiten: nur eigene Skripte/Stile, Verbindung
/// nur zum Hub selbst.
const String screenPageCsp =
    "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self' ws:; form-action 'self'";

const String _style = '''
*{box-sizing:border-box;margin:0}
body{background:#0e1116;color:#f2f4f7;font-family:system-ui,-apple-system,"Segoe UI",sans-serif;height:100vh;overflow:hidden;display:flex;flex-direction:column}
header{display:flex;align-items:baseline;gap:2vw;padding:2vh 3vw;background:#161b22}
h1{font-size:4vh;font-weight:700}
#sub,#status{font-size:2.6vh;color:#9aa4b2}
#conn{margin-left:auto;font-size:2.2vh;color:#9aa4b2}
#conn.ok{color:#3fb950}
main{flex:1;display:flex;flex-direction:column;gap:2vh;padding:2vh 3vw;min-height:0}
#players{flex:1;display:flex;gap:2vw;min-height:0}
.p{flex:1;background:#161b22;border-radius:1.5vh;padding:2vh 2vw;display:flex;flex-direction:column;opacity:.55;min-width:0}
.p.on{opacity:1;box-shadow:inset 0 .8vh 0 #e5484d}
.p.win{opacity:1;box-shadow:inset 0 .8vh 0 #3fb950}
.name{font-size:4vh;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.label{font-size:2.2vh;color:#9aa4b2;text-transform:uppercase;letter-spacing:.1em}
.score{flex:1;display:flex;align-items:center;font-weight:800;line-height:1;font-variant-numeric:tabular-nums}
.meta{font-size:2.8vh;color:#c9d1d9}
#visit{display:flex;gap:1.5vw;align-items:center}
.d{min-width:12vw;text-align:center;font-size:6vh;font-weight:700;padding:1vh 1vw;border-radius:1vh;background:#21262d}
.d.plan{color:#f5c518;border:.3vh dashed #f5c518;background:none}
#vs{margin-left:auto;font-size:7vh;font-weight:800}
#banner{font-size:4vh;font-weight:700;padding:1vh 2vw;border-radius:1vh;display:none}
#banner.positive{background:#238636;display:block}#banner.negative{background:#da3633;display:block}#banner.neutral{background:#30363d;display:block}
#idle{flex:1;display:none;align-items:center;justify-content:center;flex-direction:column;gap:2vh;text-align:center;font-size:5vh}
#idle small{font-size:2.6vh;color:#9aa4b2;max-width:70vw}
input,button{font-size:3vh;padding:1vh 2vw;border-radius:1vh;border:0}
''';

/// Seite mit gültigem Code.
const String screenPageHtml = '''<!doctype html>
<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>DartLab · Zweiter Bildschirm</title><style>$_style</style></head>
<body>
<header><h1 id="title">DartLab</h1><span id="sub"></span><span id="status"></span><span id="conn">Verbinde …</span></header>
<main>
<div id="banner"></div>
<div id="players"></div>
<div id="visit"></div>
<div id="idle">Warte auf Spiel am PC<small>Sobald am PC ein Training, ein Match oder das Mitschreiben läuft, erscheint hier der Spielstand.</small></div>
</main>
<script>
"use strict";
const key = new URLSearchParams(location.search).get("key") || "";
const \$ = (id) => document.getElementById(id);
function el(tag, cls, text) { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }
function render(s) {
  const idle = s.kind === "idle";
  \$("idle").style.display = idle ? "flex" : "none";
  \$("players").style.display = idle ? "none" : "flex";
  \$("visit").style.display = idle ? "none" : "flex";
  \$("title").textContent = idle ? "DartLab" : (s.title || "");
  \$("sub").textContent = idle ? "" : (s.subtitle || "");
  \$("status").textContent = idle ? "" : (s.status || "");
  const b = \$("banner"); b.textContent = s.banner || ""; b.className = s.banner ? (s.bannerTone || "neutral") : "";
  if (idle) return;
  const players = s.players || [];
  const box = \$("players"); box.replaceChildren();
  for (const p of players) {
    const c = el("div", "p" + (p.winner ? " win" : (p.active || players.length === 1 ? " on" : "")));
    c.append(el("div", "name", p.name || ""), el("div", "label", p.scoreLabel || ""));
    const sc = el("div", "score", p.score || ""); sc.style.fontSize = "min(" + Math.round(70 / Math.max(players.length, 1)) + "vw, 34vh)"; c.append(sc);
    const meta = [];
    if (p.sets != null) meta.push("Sätze " + p.sets);
    if (p.legs != null) meta.push("Legs " + p.legs);
    if (p.average) meta.push("Avg " + p.average);
    if (p.lastVisit != null) meta.push("Letzte " + p.lastVisit);
    c.append(el("div", "meta", meta.join(" · "))); box.append(c);
  }
  const v = \$("visit"); v.replaceChildren();
  const darts = s.visit || [], plan = (s.route && s.route.length ? s.route : s.setup) || [];
  for (let i = 0; i < 3; i++) {
    if (i < darts.length) v.append(el("div", "d", darts[i]));
    else if (i - darts.length < plan.length) v.append(el("div", "d plan", plan[i - darts.length]));
    else v.append(el("div", "d", "–"));
  }
  v.append(el("div", "", s.bust ? "BUST" : (s.visitScore != null ? String(s.visitScore) : "")));
  v.lastChild.id = "vs";
}
function connect() {
  const ws = new WebSocket("ws://" + location.host + "/screen/ws?key=" + encodeURIComponent(key));
  ws.onmessage = (e) => { try { const m = JSON.parse(e.data); if (m.type === "state") render(m.state); } catch (_) {} };
  ws.onopen = () => { \$("conn").textContent = "Verbunden"; \$("conn").className = "ok"; };
  ws.onclose = () => { \$("conn").textContent = "Verbindung verloren – neuer Versuch …"; \$("conn").className = ""; setTimeout(connect, 2000); };
}
connect();
</script>
</body></html>
''';

/// Seite ohne (gültigen) Code: fragt ihn ab und lädt mit `?key=` neu.
const String screenLoginHtml = '''<!doctype html>
<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>DartLab · Zweiter Bildschirm</title><style>$_style</style></head>
<body><main><div id="idle" style="display:flex">Code vom PC eingeben
<small>Steht am PC unter Optionen › Sync zwischen Geräten.</small>
<form method="get" action="/screen"><input name="key" inputmode="numeric" autocomplete="off" autofocus> <button>Anzeigen</button></form>
</div></main></body></html>
''';
