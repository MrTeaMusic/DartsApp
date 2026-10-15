# Online-Matches auswerten und Training gegen Match

Stand: 15.10.2026.

Matches, die du mit **Autodarts Live** mitschreibst (siehe `docs/autodarts-live.md`), bekommen in der
Statistik einen eigenen Reiter **Online**. Dort stehen deine Online-Matches mit Verlauf und der direkte
Vergleich mit deinem Training. Was online deutlich schlechter läuft, nimmt der „Plan für mich“ als
Schwerpunkt auf.

Alles wird im `StatsCalculator` berechnet (`onlineReport`, `onlineComparison`, `liveDoublesOf`) und je
Zeitraum zwischengespeichert; die Datenklassen stehen in `lib/features/stats/domain/online_stats.dart`.
Die Oberfläche (`online_tab.dart`) liest nur fertige Werte.

## Was ein Online-Match ist

* Jede Live-Session ist ein Match-Eintrag: `x01_live` (mit „X01 mitzählen“) und `autodarts_live`
  (nur mitgeschrieben). Nach 20 Minuten ohne Dart beginnt eine neue Session, also ein neues Match.
* **Bot-Matches** (`x01_match`) sind keine Online-Matches. Sie zählen weder hier noch im Vergleich als
  Training; Liste und Detailansicht der Bot-Matches bleiben, wie sie waren.
* Der Reiter gilt für den gewählten **Zeitraum** (7/30/90 Tage, alles). Der Spielfilter ist dort
  ausgeblendet, weil der Reiter immer alle Live-Sessions zeigt.

## Reiter „Online“

* **Kennzahlen:** Matches (mit Darts und Legs gewonnen:verloren), 3-Dart-Average, First 9,
  Checkout-Quote, höchstes Finish, Aufnahmen ab 100 / 180er.
  * Average: mit X01 der Average wie im Match (Bust-Aufnahmen zählen 0), ohne X01 der Rohschnitt aller
    Darts. Zusammengefasst wird nach Darts gewichtet.
  * First 9: Schnitt der First-9-Werte aller abgeschlossenen Legs (nur mit X01).
  * Checkout-Quote: gewonnene Legs je Dart auf ein Finish (Rest mit einem Dart checkbar), wie bei X01.
* **Verlauf je Woche** (Montag bis Sonntag) für Average, First 9 oder Checkout-Quote. Gibt es im
  Zeitraum weniger als drei Wochen mit Matches, zeigt der Verlauf die einzelnen Matches.
* **Matches im Zeitraum**, neueste zuerst: Tag, Uhrzeit, Legs, Darts, Dauer, Average und als kleine
  Werte First 9, Checkout-Quote, höchstes Finish, 100+ und 180er. Antippen klappt die Legs auf (je Leg
  gewonnen/verloren, Darts, Average, First 9, Finish); „Alle Aufnahmen“ öffnet die Session im Verlauf.
  Sessions ohne X01 öffnen direkt die Detailansicht.

## Training gegen Match

Verglichen wird der gewählte Zeitraum. Online sind immer die Live-Sessions. Welche Spiele als
Training zählen, hängt von der Kennzahl ab (`TrainingSources`):

| Kennzahl | Online | Training | Mindestens je Seite |
|---|---|---|---|
| 3-Dart-Average | alle Live-Sessions (X01-Average bzw. Rohschnitt) | X01-Solo (`x01`, Average mit Bust = 0) und die Scoring-Drills T20-Training, Score-Ziel, Highscore-Jagd (Rohpunkte) | 90 Darts |
| First 9 | Legs aus `x01_live` | Legs aus X01-Solo | 5 Legs |
| Checkout-Quote | `x01_live`: gewonnene Legs / Darts aufs Finish | X01-Solo, gleich gerechnet | 15 Finish-Darts |
| Double-Quote | `x01_live`: Darts aufs Finish-Doppel (siehe unten), Treffer = genau dieses Doppel | jedes Trainingsspiel, in dem ein Dart genau ein Doppel als Ziel hatte: Checkout-Training, 121, X01-Solo auf dem Finish, Bob's 27, Around the Clock auf Doppel, Doubles 420, Doppel-Leiter … | 20 Doppel-Darts |
| Aufnahmen 100+ und Punkteverteilung | volle Aufnahmen (3 gezählte Darts) aller Live-Sessions | volle Aufnahmen aus X01-Solo und den Scoring-Drills | 30 Aufnahmen |
| Doppel einzeln | wie Double-Quote, je Doppel | wie Double-Quote, je Doppel | 8 Darts je Doppel |

Hat eine Kennzahl auf einer Seite zu wenig, steht sie grau mit „Noch zu wenig: online …, Training …
(mind. …)“. Hat keine Kennzahl genug, erklärt eine Karte, was fehlt.

**Finish-Doppel online:** Die Live-Session wird mit ihren gespeicherten Darts und „Leg verloren“/„Leg
neu starten“ noch einmal abgespielt (`LiveX01.replay`). Ein Dart zählt als Wurf aufs Doppel, wenn der
Checkout-Weg für die restlichen Darts der Aufnahme aus genau einem Doppel bestand (Rest 32 → D16, Rest
50 → Bull), dieselbe Regel wie bei X01-Solo im Training. Nur Double- und Master-Out; ohne „X01
mitzählen“ kennt DartLab keinen Rest und es gibt keine Finish-Doppel.

**Deutlich schwächer** (rot in der Doppel-Liste, im Hinweis unter der Tabelle und im Plan):

* ein Doppel: online mindestens 10 Prozentpunkte unter dem Training (beide Seiten ab 8 Darts),
* die Double-Quote insgesamt: online mindestens 10 Prozentpunkte darunter,
* die First 9: online mindestens 5 Punkte darunter.

Die Doppel-Liste zeigt höchstens zehn Doppel, größter Einbruch zuerst; grüne Werte heißen, dass es
online besser läuft.

**Grenzen:** Der Average vergleicht nicht exakt Gleiches: Im X01 zählen Darts aufs Finish mit, in den
Scoring-Drills nur Darts auf Punkte. Für den Start ist die First 9 der sauberere Vergleich (X01-Solo
gegen Online-X01), deshalb fließt beim Scoring nur sie in den Plan ein.

## Plan für mich

`autoPlanInputProvider` gibt dem Generator zusätzlich den Vergleich desselben Zeitraums mit
(`AutoPlanInput.online`). `AutoPlanGenerator.onlineWeaknesses` macht daraus Schwerpunkte:

* bis zu zwei Doppel, die online deutlich schwächer sind („D8 online“, Begründung „D8 triffst du
  online nur zu 6 % (Training: 23 %), Ziel: 25 %“; Ziel = Trainingsquote, auf 5 % aufgerundet),
* die Double-Quote insgesamt („Doppel online“),
* die First 9 („First 9 online“, Ziel = First 9 im Training).

Ihre Stärke ist 0,3 plus der doppelte Abstand in Prozentpunkten (bzw. Abstand / 25 bei der First 9),
sodass sie meist vor den Schwächen aus dem Training landen. Eine Online-Schwäche ersetzt dieselbe
Schwäche aus dem Training (gleiche Art und Zahl). Die Spiele sind dieselben wie bei der Schwäche aus
dem Training (z. B. Checkout mit festem Rest 16 für D8). Der Hinweis oben im Plan erklärt „online“.

## Verlauf

Live-Sessions stehen im Spielverlauf unter dem Filter **Matches** (nicht mehr unter Training), mit
einem Globus-Symbol und, mit X01, den Legs in der Zeile. Ihre Detailansicht bleibt die der
Trainings (Aufnahmen ohne Gegner); die Match-Detailansicht mit Gegnern gibt es weiter nur für
Bot-Matches.
