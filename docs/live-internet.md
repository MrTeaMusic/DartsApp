# Live übers Internet

Bens Vater schaut mit der Lite-App (siehe [lite-app.md](lite-app.md)) beim Darten zu, auch wenn er
nicht im selben Netz ist. Der [zweite Bildschirm](zweiter-bildschirm.md) funktioniert nur im
Heimnetz; Live nimmt denselben Spielstand und schickt ihn über den eigenen Cloud-Speicher
([sync.md](sync.md), [cloud/README.md](../cloud/README.md)).

## Benutzen

1. **Ben (Haupt-App):** Optionen › Sync zwischen Geräten › *Über die Cloud abgleichen* (Cloud-Rolle),
   darunter den Schalter **Live übers Internet zeigen** einschalten. Er ist standardmäßig **aus**:
   Solange er aus ist, verlässt nichts das Gerät, und die App tut dafür auch nichts.
2. Der Cloud-Speicher braucht einmal die neue Fassung von `worker.js`
   ([Anleitung](../cloud/README.md), Abschnitt 3). Ist er noch alt, steht in der Karte *"Der
   Cloud-Speicher muss aktualisiert werden"*, und im Reiter Live der Lite-App *"Der Cloud-Speicher
   kennt Live noch nicht"*. Beides erledigt sich, sobald der Worker aktualisiert ist (Bens App prüft das alle 5 Minuten,
   die Lite-App jede Minute, solange der Reiter offen ist).
3. **Vater (Lite):** Reiter **Live** (links neben Statistik und Optionen). Die Lite-App startet
   weiter in der Statistik. Der Reiter fragt nur ab, solange er offen und die App im Vordergrund ist, und
   hält den Bildschirm an.

## Was zu sehen ist

Dieselbe Anzeigetafel wie beim zweiten Bildschirm (Stand, Aufnahme, Checkout-Weg, Scheibe,
Kennzahlen), im Arena-Look. Die Beschriftungen kommen fertig auf Deutsch im Paket. Zustände:

| Zustand | Wann |
|---|---|
| Spielstand mit Pill *Live* | Ben spielt (X01-Match, X01 solo, Training, Mitschreiben vom Board) |
| *Ben spielt gerade nicht* | kein Paket, ein `idle`-Paket oder ein Paket, das älter als 60 Sekunden ist |
| *Verbindung verloren*, letzter Stand abgeblendet | der Cloud-Speicher ist vom Handy aus nicht erreichbar; Wiederholung nach 2, 4, 8, dann alle 10 s; *Jetzt verbinden* sofort |
| *Der Cloud-Speicher kennt Live noch nicht* | alter Worker (`hello` ohne `live`) |
| *Geheimnis passt nicht* | Zugang abgelehnt, kein Tresor zum Geheimnis oder Paket nicht lesbar; Knopf zu den Optionen |

## Das Paket

Ein einziges Paket pro Tresor, der letzte Stand ersetzt den davor (`PUT /v1/live`, `GET /v1/live`).
Im Klartext, vor dem Verschlüsseln:

```json
{"v": 1, "t": 1760000000000, "state": {"v": 1, "kind": "match", "title": "501 · X01-Match", "…": "…"}}
```

* `state` ist exakt der `ScreenState` des zweiten Bildschirms ([zweiter-bildschirm.md](zweiter-bildschirm.md)),
  gebaut von derselben Funktion (`ScreenFeed.snapshot`), die auch der Hub benutzt. Ohne Spiel:
  `{"kind": "idle"}`.
* `t` ist die Uhrzeit des Senders (Millisekunden). Wie alt das Paket ist, sagt dem Zuschauer
  bevorzugt der Server (Kopfzeile `X-Live-Age`, seine eigene Uhr), damit die Handy-Uhren egal sind.
* Verschlüsselt wie alles im Cloud-Speicher: gzip, AES-256-GCM mit dem Datenschlüssel aus dem
  Geheimnis, der Name `live` ist an die Verschlüsselung gebunden (Paket unter anderem Namen
  oder mit falschem Geheimnis lässt sich nicht öffnen). Ein Paket ist meist unter 2 KB groß; der
  Worker nimmt höchstens 16 KB.
* Der Cloud-Speicher sieht nur, **wann** Pakete kommen und wie groß sie sind, nie, was drinsteht.
  Wer das Geheimnis hat, sieht das Spiel; das sind Ben und die Menschen, denen er es gibt.

**Worker** (`cloud/worker.js`): Zeile `live` in der vorhandenen Tabelle `objects` (keine
Datenbankänderung), `rev` zählt je Paket hoch. `GET /v1/live?since=<rev>` (oder `If-None-Match`)
antwortet bei unverändertem Stand mit `304` ohne Inhalt, sonst `200 {rev, body}`; beide mit `ETag` und
`X-Live-Age`. Ohne Paket `404 no-live`, ohne Tresor `404 no-vault`. `hello` meldet `"live": 1`.

## Wann gesendet und abgefragt wird

**Sender** (`LivePusher`, `lib/features/live_remote/data/live_pusher.dart`)

* nur wenn sich der Stand (als JSON) geändert hat, **höchstens ein Paket je 1,5 Sekunden** (der erste
  geht sofort, Änderungen dazwischen werden gesammelt, der letzte Stand geht danach raus);
* läuft ein Spiel ohne Änderung, alle **20 Sekunden** ein Herzschlag (derselbe Stand), daran sieht der
  Zuschauer, dass Ben noch da ist; ohne Spiel gibt es keinen Herzschlag;
* am Spielende genau **ein `idle`-Paket**; wer nie gespielt hat, schickt auch kein `idle`; beim
  Ausschalten des Schalters mitten im Spiel ebenfalls eins;
* Fehler (kein Netz, alter Worker, Tageslimit) stören das Spiel nie: alles läuft asynchron, nach einem
  Fehler wird nach 3, 6, 12, 30, dann alle 60 Sekunden mit dem dann aktuellen Stand neu versucht, ein
  alter Worker wird nur alle 5 Minuten neu geprüft. Die Sync-Karte zeigt den Grund.

**Zuschauer** (`LiveViewerController`, `lib/features/live_remote/presentation/`)

* nur wenn der Reiter offen **und** die App im Vordergrund ist (`TickerMode` des Router-Zweigs und
  `WidgetsBindingObserver`); sonst gibt es keine Anfrage und der Bildschirm darf ausgehen;
* alle **2 Sekunden**, solange Ben spielt; sonst alle **5 Sekunden**, nach 10 Minuten Ruhe alle
  **15 Sekunden** (damit ein vergessen offenes Handy das Tageslimit nicht aufzehrt);
* jede Anfrage mit `?since=<rev>`, bei Stillstand antwortet der Server mit `304`;
* die Lite-App schickt nie etwas (nur `GET`).

## Kosten im Cloudflare-Gratis-Tarif

Grenzen (Stand 22.10.2026): 100.000 Worker-Anfragen pro Tag, 100.000 geschriebene D1-Zeilen pro Tag.
Rechnung für einen **Abend von 3 Stunden (10.800 s)** mit Ben und **einem** Zuschauer, der die ganze
Zeit auf dem Reiter Live bleibt:

| Posten | Rechnung | Anfragen |
|---|---|---|
| Ben sendet, **Obergrenze** | 10.800 s / 1,5 s | 7.200 |
| Ben sendet, **realistisch** | ein Dart alle 5 s, je Dart etwa 2 Änderungen (Dart, Aufnahme): 2.160 × 2 | 4.320 |
| Zuschauer fragt ab | 10.800 s / 2 s (jede Abfrage, auch die mit `304`, ist eine Anfrage) | 5.400 |
| Normaler Abgleich | alle 5 Minuten eine Leseanfrage plus ein paar Sessions | etwa 100 |
| **Summe realistisch** | | **etwa 9.800 (10 %)** |
| **Summe im ungünstigsten Fall** | 7.200 + 5.400 + 100 | **12.700 (13 %)** |

**Geschriebene D1-Zeilen:** ein Paket ist ein einziges Schreib-Statement auf eine Zeile (der Test
`cloud/test` prüft das). Sicherheitshalber mit 2 Zeilen je Paket gerechnet (falls ein Index
mitzählt): 2 × 4.320 = 8.640 realistisch, 2 × 7.200 = 14.400 im ungünstigsten Fall, dazu ein paar
hundert vom Abgleich, also **höchstens etwa 15 %** der 100.000. Gelesene Zeilen: eine je Abfrage
(5.400 von 5 Millionen).

Weitere Zuschauer kosten je etwa 5.400 Anfragen pro 3 Stunden. Bei einem Abend wie oben bleiben
auch **rund 15 Zuschauer gleichzeitig** unter der Tagesgrenze ((100.000 − 7.300) / 5.400 ≈ 17).
Ein Handy, das den ganzen Tag auf Live offen liegt (ohne Spiel), fragt erst alle 5 s, nach 10 Minuten alle 15 s:
höchstens etwa 6.000 Anfragen pro Tag. Bei geschlossenem Reiter oder Hintergrund sind es 0.

Wird die Tagesgrenze trotzdem erreicht, scheitern Anfragen bis 00:00 Uhr UTC; beide Apps zeigen den
Fehler, spielen und zuschauen geht danach von selbst weiter. Das Spiel selbst und der normale Abgleich
leiden nicht darunter (der Abgleich wiederholt später).

## Nicht getestet

Alles ist mit Tests gegen Attrappen geprüft (`FakeCloud` baut den Worker nach, der echte Worker hat
eigene Tests in `cloud/test` mit einer D1-Attrappe). Nicht gesehen wurde es mit einem echten
Cloudflare-Worker, einer echten D1-Datenbank und einem echten Handy: ob die Gratis-Zähler von
Cloudflare genau so zählen wie oben gerechnet, wie schnell der Spielstand bei echter
Mobilfunkverbindung ankommt und wie sich Bildschirm-an auf Android verhält.
