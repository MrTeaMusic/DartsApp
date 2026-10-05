# 🎯 DartsApp

Eine komplette Darts-App in **einer einzigen HTML-Datei** – ohne Installation, ohne Server, funktioniert offline.
Einfach `index.html` im Browser öffnen (am Handy z. B. über GitHub Pages und dann „Zum Startbildschirm hinzufügen“).

## Funktionen

### Training (allein)
- **501 Solo** (301/501/701, Double/Single Out, 1–10 Legs) – Average, First-9, bestes Leg, Checkouts
- **Scoring-Training** – 10/20/33/50 Aufnahmen, nur Punkte werfen
- **Around the Clock** – 1–20 + Bull, benötigte Darts & Trefferquote
- **Doppel-Training** – Trefferquote pro Doppel (der Reihe nach oder zufällig, 3/6/9 Darts pro Ziel)
- **Bob's 27** – der Doppel-Klassiker

### Spiele mit Freunden
- **X01** (301/501/701) mit Double In/Out, „First to“ 1–5 Legs, beliebig viele Spieler, wechselnder Anwurf
- **Cricket** (15–20 + Bull, mit Punkten), MPR-Statistik
- Eingabe per **Aufnahme-Summe** (Keypad + Schnelltasten) oder **Dart für Dart** (Single/Double/Triple)
- Checkout-Vorschläge, Bust-Erkennung, Undo, Pausieren & später fortsetzen

### Historie & Statistik
- Alle Trainings und Spiele mit Datum, Dauer und Detail-Statistiken
- **Nachtragen**: Trainings oder Spiele, die ohne App gespielt wurden, manuell eintragen
- Statistik pro Spieler: Average-Verlauf (Diagramm), Bestwerte, 180er, Checkouts, Doppelquote pro Feld, Bilanz gegen jeden Freund
- Einträge nachträglich **bearbeiten** (Datum, Sieger, Legs, Average, 180er, Highfinishes, Notiz …) oder löschen
- Backup als JSON exportieren/importieren

## Autodarts-Anbindung (experimentell)
Unter **Start → Autodarts** die IP des Boards (Board Manager 2, Port 3180) eintragen und die Wurf-Übernahme einschalten.
Die App liest `http://<IP>:3180/api/state` und übernimmt jeden erkannten Dart ins laufende Spiel
(X01, Cricket, Around the Clock, Doppel-Training, Bob's 27, Scoring). Beim Entnehmen der Darts wird die Aufnahme abgeschlossen.
- Inoffizielle Schnittstelle, das Format kann sich ändern. Unter „Diagnose“ stehen die Rohdaten.
- Blockiert der Browser die Verbindung (CORS), `node autodarts-bridge.js <Board-IP>` auf einem Rechner im Netz starten und dessen Adresse mit Port 3181 eintragen.
- Die App muss als Datei oder über http geöffnet sein (eine https-Seite darf keine http-Verbindung öffnen).

## Daten
Alle Daten werden lokal im Browser gespeichert (`localStorage`). Zum Gerätewechsel oder als Sicherung
unter **Start → Einstellungen → Backup exportieren** eine Datei sichern und auf dem anderen Gerät importieren.

## Tastatur (Desktop)
Ziffern + `Enter` zur Punkteeingabe, `Backspace` zum Löschen, `U` oder `Strg+Z` für Undo.
