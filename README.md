# DartLab (Arbeitstitel)

Darts-Trainings-App für **Windows, macOS und iOS** (iPhone und iPad) aus einer Flutter-Codebasis.
Würfe kommen live vom Autodarts-Board, aus einem Simulator oder per manueller Eingabe.

> Die Datei `index.html` im Repo-Wurzelordner ist der frühere Web-Prototyp und bleibt vorerst
> unverändert liegen. Die Flutter-App ist davon unabhängig.

## Stand: Phase 5

| Bereich | Status |
|---|---|
| Projekt-Setup (Flutter 3.47, Riverpod 3, go_router, i18n Deutsch) | fertig |
| Design-System (Farben, Abstände, Typografie, Komponenten, Dark/Light) | fertig |
| Adaptive Navigation (Seitenleiste ab 840 px, sonst Bottom-Navigation) | fertig |
| `DartSource`-Schnittstelle | fertig |
| `SimulatorSource` (klickbares Board, optionale Streuung) | fertig |
| `ManualSource` (Tastenfeld oder Board antippen) | fertig |
| `AutodartsLocalSource` (WebSocket, HTTP-Fallback, Wiederverbindung, Status) | Würfe, Takeout und Koordinaten am echten Board bestätigt (BM 2.0.2); Bull, Korrektur und Bouncer noch offen |
| Debug-Bildschirm mit Live-Rohdaten und Datei-Log | fertig |
| Animiertes Dartboard (CustomPainter, Treffer, Aufleuchten, Heatmap-Overlay) | fertig |
| Spiel-Engine (Aufnahmen, Rückgängig, Korrektur, Wiederholbarkeit per Seed) | fertig |
| Checkout-Training, Around the Clock, Bullseye-Drill, T20-Training, Score-Ziel, Highscore-Jagd | fertig |
| Lokale Datenbank (drift/SQLite): Sessions und jeder einzelne Wurf | fertig |
| Cricket (Solo), 121, Bob's 27, Drei-Treffer-Runde, Around the World mit Überspringen | fertig |
| X01-Solo, Halve-It, Catch 40, JDC-Challenge, Shanghai, Darts-Golf, 420, Frustration, Ziel-Wechsel, Doppel-Leiter, Genau 100, Drei im Bett, Stellen | fertig |
| Statistik (Überblick mit Vorzeitraum-Vergleich, Scoring-Verteilung, Doubles im Detail, Verläufe, Trainingsmuster, Rekorde) | fertig |
| Ziele und Serien | fertig |
| Mehrere Profile | fertig |
| Export/Import (JSON-Backup, CSV) | fertig |
| Neues Design: Schrift Inter, Startseite, Spielansicht mit Aufnahme-Leiste, Triple lila | fertig |
| Checkout-Weg gelb in den freien Dart-Feldern (alle Spiele mit Wurfvorschlag) | fertig |
| Darts korrigieren (antippen, auch frühere Aufnahmen) | fertig |
| Vollbild (Knopf, F11, Esc) | fertig |
| Trainingspläne (feste und eigene, Fortschritt merken, Zusammenfassung) | fertig |
| Sync im Heimnetz (Desktop-App als Hub, iPhone/iPad gleichen automatisch ab) | fertig, am echten Heimnetz noch nicht getestet |
| Autodarts-Verbindungstest, Mitschnitt-Prüfung, Koordinaten-Kalibrierung | fertig |
| Build-Anleitung, native Builds in GitHub Actions | fertig |

Was über das Autodarts-Protokoll bekannt und was offen ist: [docs/autodarts-protokoll.md](docs/autodarts-protokoll.md).
Wie der Sync funktioniert: [docs/sync.md](docs/sync.md).
Regeln und Optionen der Trainingsspiele: [docs/trainingsspiele.md](docs/trainingsspiele.md).
Die 13 weiteren Spiele (X01-Solo bis Stellen): [docs/trainingsspiele-erweitert.md](docs/trainingsspiele-erweitert.md).
Regeln der zwei eigenen Spiele: [docs/spielregeln.md](docs/spielregeln.md).
Feste und eigene Trainingspläne: [docs/trainingsplaene.md](docs/trainingsplaene.md).
Checkout-Quiz (Wege lernen ohne zu werfen): [docs/checkout-quiz.md](docs/checkout-quiz.md).
Spielansicht (Arena oder Look) und Aufnahmen-Tabelle für Match und X01-Solo: [docs/spielansicht.md](docs/spielansicht.md).
Wie Statistiken berechnet werden, Ziele, Profile, Export-Formate: [docs/statistik-und-daten.md](docs/statistik-und-daten.md).
Streuungs-Analyse (wohin man je Feld verzieht, mit Tipp): [docs/streuungs-analyse.md](docs/streuungs-analyse.md).

## Starten

Voraussetzung: [Flutter](https://docs.flutter.dev/get-started/install) (stable, ≥ 3.47).

```bash
flutter pub get          # erzeugt auch die Übersetzungen (lib/l10n/gen)
flutter run -d macos     # auf einem Mac
flutter run -d windows   # auf einem Windows-PC (Visual Studio mit "Desktop development with C++")
flutter run -d <iPhone>  # iOS, braucht Xcode auf dem Mac
```

Tests und Analyse:

```bash
flutter analyze
flutter test
```

Ausführliche Build- und Installationsanleitung für alle drei Plattformen (inkl. iPhone mit kostenloser
Apple-ID): [docs/build-anleitung.md](docs/build-anleitung.md).

## Architektur

```
lib/
  core/
    database/      drift-Datenbank (Spieler, Sessions, Würfe)
    design/        Tokens, Theme, DartColors, wiederverwendbare Komponenten
    router/        go_router mit StatefulShellRoute
    settings/      AppSettings (shared_preferences) + Riverpod-Notifier
    widgets/       AdaptiveScaffold (Seitenleiste / Bottom-Navigation)
  features/
    board/
      domain/      Segment, BoardGeometry (reine Dart-Klassen)
      presentation/DartboardPainter, DartboardView, LiveVisitController
    dart_source/
      domain/      DartSource, DartEvent, DartThrow, SourceStatus
      data/        Simulator-, Manual-, AutodartsLocal-Quelle, Mapper, RawMessageLog
      presentation/Provider, Statusanzeige, Debug-Bildschirm
    games/
      domain/engine/ TrainingGame, GameDefinition, GameSession (reine Dart-Klassen)
      domain/games/  ein Spiel = eine Klasse + GameDefinition, registriert in game_catalog.dart
      data/          GameRepository (Speichern, Verlauf, schwache Checkouts)
      presentation/  Spielauswahl, Einstellungen, Spielbildschirm, ActiveGameController
    stats/
      domain/        StatsCalculator, Ziel je Dart (Abspielen der Session), Ziele (reine Berechnung)
      data/          StatsRepository
      presentation/  Statistik-Bildschirm mit Reitern (fl_chart), Ziele-Karte
    plans/           Trainingspläne: feste Pläne im Code, eigene in der Datenbank, Durchläufe
    profiles/        Profile und aktives Profil
    backup/          JSON/CSV-Export, Import, Dateidialoge
    home/ simulator/ settings/   Bildschirme
  l10n/            app_de.arb (Vorlage), app_en.arb
```

**Neues Spiel:** Klasse von `TrainingGame` ableiten, eine `GameDefinition` mit Standardwerten und
Optionen anlegen und in `GameCatalog.all` eintragen. Das Einstellungsformular entsteht aus den Optionen.
Nach Änderungen an Tabellen: `dart run build_runner build`, `schemaVersion` erhöhen und einen
Migrationsschritt in `app_database.dart` ergänzen.

**Regel:** Spiele sprechen nur mit `DartSource` (über `dartEventsProvider`), nie direkt mit Autodarts.
Ändert sich das Protokoll, wird nur `AutodartsStateMapper` bzw. `AutodartsLocalSource` angepasst.

### Design anpassen

* Farben, Abstände, Radien, Animationszeiten: `lib/core/design/tokens.dart`
* Board- und Statusfarben je Theme: `lib/core/design/dart_colors.dart`
* Typografie und Material-Theme: `lib/core/design/app_theme.dart`

### Board-Koordinaten

`BoardPoint(x, y)`: Mitte (0, 0), Radius 1.0 = Außenkante Double-Ring (170 mm), y zeigt zur 20.
Das ist die Konvention von Autodarts, am echten Board bestätigt (Board Manager 2.0.2).
