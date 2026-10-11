# DartLab (Arbeitstitel)

Darts-Trainings-App für **Windows, macOS und iOS** (iPhone und iPad) aus einer Flutter-Codebasis.
Würfe kommen live vom Autodarts-Board, aus einem Simulator oder per manueller Eingabe.

> Die Datei `index.html` im Repo-Wurzelordner ist der frühere Web-Prototyp und bleibt vorerst
> unverändert liegen. Die Flutter-App ist davon unabhängig.

## Stand: Phase 3

| Bereich | Status |
|---|---|
| Projekt-Setup (Flutter 3.47, Riverpod 3, go_router, i18n Deutsch) | fertig |
| Design-System (Farben, Abstände, Typografie, Komponenten, Dark/Light) | fertig |
| Adaptive Navigation (Seitenleiste ab 840 px, sonst Bottom-Navigation) | fertig |
| `DartSource`-Schnittstelle | fertig |
| `SimulatorSource` (klickbares Board, optionale Streuung) | fertig |
| `ManualSource` (Tastenfeld oder Board antippen) | fertig |
| `AutodartsLocalSource` (WebSocket, HTTP-Fallback, Wiederverbindung, Status) | gebaut, **nicht am echten Board getestet** |
| Debug-Bildschirm mit Live-Rohdaten und Datei-Log | fertig |
| Animiertes Dartboard (CustomPainter, Treffer, Aufleuchten, Heatmap-Overlay) | fertig |
| Spiel-Engine (Aufnahmen, Rückgängig, Korrektur, Wiederholbarkeit per Seed) | fertig |
| Checkout-Training, Around the Clock, Bullseye-Drill, T20-Training, Score-Ziel, Highscore-Jagd | fertig |
| Lokale Datenbank (drift/SQLite): Sessions und jeder einzelne Wurf | fertig |
| Cricket (Solo), 121, Bob's 27, Drei-Treffer-Runde, Around the World mit Überspringen | fertig |
| Statistiken, Export/Import, Profile | Phase 4 |

Was über das Autodarts-Protokoll bekannt und was offen ist: [docs/autodarts-protokoll.md](docs/autodarts-protokoll.md).
Regeln und Optionen der Trainingsspiele: [docs/trainingsspiele.md](docs/trainingsspiele.md).
Regeln der zwei eigenen Spiele: [docs/spielregeln.md](docs/spielregeln.md).

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

Die ausführliche Build- und Installationsanleitung für alle drei Plattformen kommt mit Phase 5.

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
    home/ simulator/ stats/ settings/   Bildschirme
  l10n/            app_de.arb (Vorlage), app_en.arb
```

**Neues Spiel:** Klasse von `TrainingGame` ableiten, eine `GameDefinition` mit Standardwerten und
Optionen anlegen und in `GameCatalog.all` eintragen. Das Einstellungsformular entsteht aus den Optionen.
Nach Änderungen an Tabellen: `dart run build_runner build`.

**Regel:** Spiele sprechen nur mit `DartSource` (über `dartEventsProvider`), nie direkt mit Autodarts.
Ändert sich das Protokoll, wird nur `AutodartsStateMapper` bzw. `AutodartsLocalSource` angepasst.

### Design anpassen

* Farben, Abstände, Radien, Animationszeiten: `lib/core/design/tokens.dart`
* Board- und Statusfarben je Theme: `lib/core/design/dart_colors.dart`
* Typografie und Material-Theme: `lib/core/design/app_theme.dart`

### Board-Koordinaten

`BoardPoint(x, y)`: Mitte (0, 0), Radius 1.0 = Außenkante Double-Ring (170 mm), y zeigt zur 20.
Das ist die Konvention, die Community-Projekte für Autodarts beschreiben (noch zu bestätigen).
