# DartLab (Arbeitstitel)

Darts-Trainings-App für **Windows, macOS und iOS** (iPhone und iPad) aus einer Flutter-Codebasis.
Würfe kommen live vom Autodarts-Board, aus einem Simulator oder per manueller Eingabe.

> Die Datei `index.html` im Repo-Wurzelordner ist der frühere Web-Prototyp und bleibt vorerst
> unverändert liegen. Die Flutter-App ist davon unabhängig.

## Stand: Phase 1

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
| Spiele, Datenbank, Statistiken | Phase 2 bis 4 |

Was über das Autodarts-Protokoll bekannt und was offen ist: [docs/autodarts-protokoll.md](docs/autodarts-protokoll.md).
Geplante Regeln der zwei eigenen Spiele: [docs/spielregeln.md](docs/spielregeln.md).

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
    home/ games/ simulator/ stats/ settings/   Bildschirme
  l10n/            app_de.arb (Vorlage), app_en.arb
```

**Regel:** Spiele sprechen nur mit `DartSource` (über `dartEventsProvider`), nie direkt mit Autodarts.
Ändert sich das Protokoll, wird nur `AutodartsStateMapper` bzw. `AutodartsLocalSource` angepasst.

### Design anpassen

* Farben, Abstände, Radien, Animationszeiten: `lib/core/design/tokens.dart`
* Board- und Statusfarben je Theme: `lib/core/design/dart_colors.dart`
* Typografie und Material-Theme: `lib/core/design/app_theme.dart`

### Board-Koordinaten

`BoardPoint(x, y)`: Mitte (0, 0), Radius 1.0 = Außenkante Double-Ring (170 mm), y zeigt zur 20.
Das ist die Konvention, die Community-Projekte für Autodarts beschreiben (noch zu bestätigen).
