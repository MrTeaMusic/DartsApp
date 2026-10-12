# Match & Turnier

X01 gegen einen echten Gegner: einen Freund am selben Board oder einen Computergegner (Bot), dazu
ein K.-o.-Turnier gegen 15 Bots mit Namen bekannter PDC-Spieler. Zu finden unter
**Training › Match & Turnier**.

## Gegner-Modus

* **Gegner**: *CPU* (Bot mit einstellbarem Average 20–110 und frei wählbarem Namen) oder
  *Freund*. Beim Freund wählt man ein Profil oder spielt mit einem Gast. Mit Profil zählen die
  Würfe des Freundes in seiner eigenen Statistik, ein Gast wird nicht gespeichert.
* **Format**: Startwert 101, 301, 501 oder 701; Ausstieg Straight, Double oder Master; optional
  Double-In. Gespielt wird entweder nach **Legs** („first to“ 1–15 Legs) oder nach **Sätzen**
  („first to“ 1–10 Sätze, jeder Satz „first to“ 1–6 Legs).
* **Anwurf**: ich, der Gegner oder zufällig. Danach wechselt der Anwurf mit jedem Leg; im
  Satzmodus wechselt zusätzlich der Anwurf jedes Satzes, innerhalb des Satzes dann wieder Leg für
  Leg (wie bei der PDC).
* Die letzte Wahl wird gemerkt.

Beide Menschen werfen abwechselnd auf dasselbe Board: echtes Board über Autodarts, der Simulator
oder die manuelle Eingabe. Nach drei Darts, Bust oder Checkout ist die Aufnahme vorbei; der
Wechsel passiert mit dem Takeout (Darts ziehen) oder mit **Weiter**. Wird ein vierter Dart
erkannt, ohne dass ein Takeout kam, gehört er dem nächsten Spieler (vergessener Takeout) – außer
der nächste ist ein Bot, dann beendet der Dart nur die Aufnahme.

### Spielansicht

* **Anzeigetafel** je Spieler: Rest (groß), Legs bzw. Sätze und Legs im laufenden Satz,
  3-Dart-Average, geworfene Darts. Ein farbiger Balken zeigt, wer am Zug ist, ein gelber Punkt,
  wer im laufenden Leg Anwurf hatte. Bei möglichem Finish steht der Checkout-Weg in Gelb unter
  dem Rest des Spielers am Zug.
* **Board** mit den Darts der laufenden Aufnahme – auch denen des Bots. Bei Menschen pulsiert
  das erste Feld des Checkout-Wegs.
* **Aufnahme-Karte** mit den drei Dart-Plätzen; offene Plätze zeigen den Checkout-Weg in Gelb.
  Geht mit den restlichen Darts kein Finish mehr, zeigen sie in Blau, wie man sich stellt
  („Stellen auf 32“, siehe unten).
  Eigene Darts lassen sich antippen und korrigieren, **Würfe korrigieren** listet alle eigenen
  Darts des laufenden Legs. **Rückgängig** nimmt den letzten eigenen Dart der laufenden Aufnahme
  zurück.
* Banner für Bust, Leg- und Satzgewinn, 180 und Matchgewinn.
* Nach dem Match: Endstand und eine Tabelle je Spieler (Average, First 9, Checkout-Quote,
  höchstes Finish, bestes Leg, 100+/140+/180, Darts). **Revanche** startet dasselbe Match, der
  andere Spieler fängt an.

**Caller**: Ist der Caller an, sagt er „Game on“ zu Matchbeginn, nach jeder abgeschlossenen
Aufnahme die Punkte bzw. „Bust“ – bei Menschen wie beim Bot, dort nach dessen drittem Dart –, dazu
„You require …“ für den Spieler, der als Nächstes wirft, wenn sein Rest auscheckbar ist, und
„Game shot, and the leg / the set / the match“ beim Leg-, Satz- und Matchgewinn. Rückgängig und
Korrekturen bleiben still. Der Stumm-Knopf sitzt in der App-Leiste der Spielansicht.

Bust- und Checkout-Regeln sowie der Checkout-Weg kommen aus denselben Bausteinen wie beim
X01-Solo (`CheckoutRules`, `CheckoutCalculator`).

**Verlassen**: Ein Match im Gegner-Modus wird nach Rückfrage abgebrochen. Wird die App mitten im
Match geschlossen, bietet **Match & Turnier** beim nächsten Mal **Match fortsetzen** an.

## Turnier

* **16 Spieler im K.-o.-System**: du und 15 Bots, zufällig aus der CPU-Spielerliste gezogen und
  zufällig ausgelost. Runden: Achtelfinale, Viertelfinale, Halbfinale, Finale.
* **501 Double-Out**, Legs je Runde als „Best of“. Formate:

  | Format | Achtelfinale | Viertelfinale | Halbfinale | Finale |
  |---|---|---|---|---|
  | Sprint | Bo3 | Bo3 | Bo5 | Bo7 |
  | Kurz (Standard) | Bo5 | Bo7 | Bo9 | Bo11 |
  | PDC | Bo11 | Bo13 | Bo17 | Bo21 |

  Jede Runde lässt sich auch einzeln einstellen (ungerade Werte 1–41, „Eigenes“). Ein volles
  PDC-Turnier dauert lange, Sprint und Kurz passen in eine Trainingssession.
* **Schwierigkeit** 30–100 %: Jeder Bot spielt mit diesem Anteil am Average seines Vorbilds.
  Bei 60 % wird aus einem 100er-Spieler ein Bot mit etwa 60er Average, aus einem 92er etwa 55.
* Dein Spiel spielst du am Board, wer anfängt, wird wie beim Ausbullen zufällig bestimmt. Die
  übrigen Spiele der Runde werden danach Dart für Dart simuliert (dasselbe Bot-Modell), die
  Ergebnisse stehen im Turnierbaum.
* Ausgeschieden? **Nächste Runde simulieren** oder **Rest simulieren** zeigt, wer gewinnt.
* Ein Turnierspiel lässt sich **unterbrechen** (Schließen) und später mit **Fortsetzen** genau
  dort weiterspielen. Turnier und unterbrochenes Spiel liegen nur auf diesem Gerät (Einstellungen
  der App, kein Abgleich). Es gibt höchstens ein Turnier; ein neues ersetzt das alte.

## CPU-Spieler

Die Liste der Computergegner ist frei bearbeitbar (**Match & Turnier › CPU-Spieler**): Name und
Average bei 100 % Stärke, Spieler hinzufügen, ändern, löschen und **Standardliste** wiederherstellen.
Mitgeliefert sind 32 bekannte aktuelle bzw. frühere PDC-Spieler. **Die Averages sind grobe
Richtwerte für die Spielstärke (etwa 91–101), keine offiziellen oder aktuellen Statistiken.**
Hat die Liste weniger als 15 Einträge, wird für ein Turnier aus der Standardliste ergänzt.

## Bot-Modell

Der Bot wirft wie ein Mensch, nur auf dem virtuellen Board:

1. **Ziel wählen**
   * Mit Double-In und noch nicht eröffnet: D20.
   * Finish mit den restlichen Darts der Aufnahme möglich: der erste Dart des Checkout-Wegs aus
     dem `CheckoutCalculator` (derselbe Weg, den die App auch Menschen vorschlägt).
   * Rest ab 230: T20.
   * Sonst ein **Aufbau**: aus T20–T15, den Singles und dem Single-Bull das Feld, das möglichst
     viele Punkte bringt und einen guten Rest lässt (bevorzugt ein Ein-Dart-Finish wie D20/D16,
     sonst ein Zwei- oder Drei-Dart-Finish) und nicht überwirft.
2. **Treffer würfeln**: Der Zielpunkt ist die Mitte des Feldes (`BoardGeometry.centerOf`). Der
   Landepunkt weicht davon in x und y unabhängig normalverteilt ab (Standardabweichung σ, in
   Board-Einheiten; 1,0 = Außenkante Double-Ring = 170 mm). Welches Feld getroffen wurde,
   entscheidet die echte Board-Geometrie (`BoardGeometry.segmentAt`) – daneben ist auch
   daneben, Bust ist Bust.
3. **Tempo**: Der Bot tritt nach etwa 1,2 s ans Board, wirft alle 0,85 s einen Dart und lässt die
   Darts 1,6 s stecken, bevor wieder der Mensch dran ist.

### Wie der Average zur Streuung wird

Die Zuordnung Average → σ ist eine Tabelle (`BotCalibration`), gemessen durch Simulation von je
4000 Legs 501 Double-Out mit genau diesem Bot. Zwischenwerte werden linear interpoliert.

| Ziel-Average | σ (Board-Einheiten) | ≈ Streuung je Achse |
|---|---|---|
| 25 | 0,206 | 35 mm |
| 40 | 0,123 | 21 mm |
| 50 | 0,097 | 16 mm |
| 60 | 0,079 | 13 mm |
| 75 | 0,060 | 10 mm |
| 85 | 0,050 | 8,5 mm |
| 97 | 0,040 | 6,8 mm |
| 104 | 0,035 | 6 mm |

Der Average zählt wie bei der PDC alle Darts des Legs (inklusive Checkout-Versuche, Bust-Aufnahmen
mit 0 Punkten). Ein Test simuliert Bots mit 30, 45, 60, 80 und 100 und prüft, dass der
gemessene Average höchstens 5 % (plus 1 Punkt) vom Ziel abweicht. Einzelne Legs und kurze
Matches streuen natürlich stärker – auch ein 50er-Bot wirft mal eine 140.

## Statistik und Speicherung

* Die Würfe der Menschen mit Profil werden wie bei jedem Spiel gespeichert, als Spiel
  **X01-Match** (`x01_match`): jeder Mensch bekommt eine eigene Session mit nur seinen Darts.
  Die Darts des Gegners – Bot oder Freund – zählen nie in der eigenen Statistik. Bot-Darts
  werden gar nicht gespeichert.
* Die Session meldet `average`, `darts`, `first9`, `highestCheckout`, Legs, Sieg usw. Damit
  gehen Matches in den 3-Dart-Average, First 9, höchstes Checkout, Punkteverteilung, Konstanz
  und 180er-Rekorde ein (die Spiel-ID beginnt mit `x01`).
* Ein abgebrochenes Match zählt wie ein abgebrochenes Spiel (die bisherigen Darts zählen).
  Beim Fortsetzen eines unterbrochenen Matches wird die Teil-Session durch eine neue mit allen
  Darts ersetzt, nichts zählt doppelt.
* Sessions werden wie alle anderen über den Abgleich synchronisiert. Turnier, CPU-Liste und
  unterbrochene Matches bleiben auf dem Gerät.

## Grenzen

* Korrekturen sind auf eigene Darts im laufenden Leg beschränkt. Eine Korrektur rechnet das
  Match neu durch; bereits geworfene Bot-Darts bleiben dabei, wie sie waren.
* Mehr als zwei Spieler sind in der Engine vorbereitet, aber noch nicht in der Oberfläche.
* Die Streuung des Bots ist rund (gleich in x und y). Echte Spieler streuen meist stärker in der
  Höhe; für die Spielstärke spielt das kaum eine Rolle.

## Stellen statt Checkout

Wenn mit den restlichen Darts der Aufnahme kein Finish mehr geht, rechnet
`SetupAdvisor` (`lib/features/games/domain/games/checkout/setup_advisor.dart`)
aus, welche Darts einen guten Rest für die nächste Aufnahme lassen. Das gilt im
Match und im X01-Training.

* Am besten ist ein Lieblings-Double (32, 40, 16, 36, 24, 20, 8), dann jedes
  andere Ein-Dart-Finish, dann ein leichtes Zwei-Dart-Finish (Single + Double).
  Reste ohne Finish (169, 168, 166, 165, 163, 162, 159) und über 170 sind schlecht.
* Große Single-Felder kosten fast nichts, Triples mehr, das Bull am meisten.
* Beispiele: 169 mit drei Darts → T20 T20 S17 (Rest 32); 120 mit zwei → T20 S20
  (40); 41 mit einem → S9 (32).
* Nach jedem Dart wird neu gerechnet; geht wieder ein Finish, erscheint der
  gelbe Checkout-Weg.
* Bleibt selbst mit maximalen Punkten über 170 nur ein Drei-Dart-Finish (z. B.
  301), geht es nur ums Punkten und es erscheint kein Vorschlag.
