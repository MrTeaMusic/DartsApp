import 'dart:math' as math;

import '../../../board/domain/segment.dart';
import '../../../dart_source/domain/dart_event.dart';
import 'game_display.dart';

/// Basisklasse aller Trainingsspiele. Reine Dart-Klasse ohne UI.
///
/// Ein Spiel ist eine deterministische Funktion aus Config, Zufallsstartwert
/// und der Folge der Eingaben (Darts und Aufnahme-Enden). Rückgängig und
/// Korrekturen funktionieren deshalb durch erneutes Abspielen
/// (siehe `GameSession`), Spiele brauchen dafür keinen eigenen Code.
///
/// Ein neues Spiel überschreibt mindestens [handleDart], [targets],
/// [display] und [result].
abstract class TrainingGame {
  TrainingGame({required this.seed}) : random = math.Random(seed);

  final int seed;

  /// Für zufällige Ziele. Nur hierüber würfeln, damit das Abspielen
  /// identische Ergebnisse liefert.
  final math.Random random;

  static const int dartsPerVisit = 3;

  /// Aufnahmen beginnen bei 0.
  int visitIndex = 0;

  /// Gezählte Darts der laufenden Aufnahme.
  final List<DartThrow> visit = [];

  /// Alle gezählten Darts des Spiels.
  final List<DartThrow> darts = [];

  /// Darts, die nach einem vorzeitigen Aufnahme-Ende (z. B. Bust) noch
  /// geworfen wurden und nicht zählen.
  int ignoredDarts = 0;

  int _physicalInVisit = 0;
  bool _visitClosed = false;
  bool _needNewVisit = false;
  bool _started = false;
  bool finished = false;

  /// Ereignisse des letzten Darts bzw. Aufnahme-Endes, z. B. für Banner.
  final List<GameEvent> events = [];

  int get dartsThrown => darts.length;

  /// Körperlich geworfene Darts der laufenden Aufnahme (inkl. ignorierter).
  int get physicalDartsInVisit => _needNewVisit ? 0 : _physicalInVisit;
  bool get visitClosed => _visitClosed;

  /// Darts, die in der laufenden Aufnahme noch geworfen werden können
  /// (nach einem vorzeitigen Ende zählt die nächste, volle Aufnahme).
  int get dartsLeftInVisit => _visitClosed ? dartsPerVisit : dartsPerVisit - visit.length;

  /// Wird der nächste Dart gezählt?
  bool get acceptsDarts =>
      !finished && (!_visitClosed || _needNewVisit || _physicalInVisit >= dartsPerVisit);

  /// Ein Dart kommt an.
  void throwDart(DartThrow dart) {
    _ensureStarted();
    events.clear();
    if (finished) {
      ignoredDarts++;
      return;
    }
    if (_needNewVisit || _physicalInVisit >= dartsPerVisit) _startVisit();
    _physicalInVisit++;
    if (_visitClosed) {
      ignoredDarts++;
      return;
    }
    visit.add(dart);
    darts.add(dart);
    handleDart(dart);
    if (!finished && !_visitClosed && visit.length >= dartsPerVisit) closeVisit();
  }

  /// Aufnahme ist vorbei (Takeout, "Weiter"). Weitere Darts beginnen eine
  /// neue Aufnahme.
  void endVisit() {
    _ensureStarted();
    if (_physicalInVisit == 0 && visit.isEmpty) return;
    events.clear();
    closeVisit();
    _needNewVisit = true;
  }

  /// Schließt die laufende Aufnahme, auch vorzeitig (Bust, Checkout).
  /// Restliche Darts dieser Aufnahme werden ignoriert.
  void closeVisit() {
    if (_visitClosed) return;
    _visitClosed = true;
    handleVisitEnd(List.unmodifiable(visit));
  }

  void _startVisit() {
    if (!_visitClosed) closeVisit();
    if (finished) return;
    visitIndex++;
    visit.clear();
    _physicalInVisit = 0;
    _visitClosed = false;
    _needNewVisit = false;
    onVisitStart();
  }

  void _ensureStarted() {
    if (_started) return;
    _started = true;
    onStart();
  }

  /// Spiel beenden (z. B. letzte Aufgabe erledigt).
  void finish() {
    finished = true;
    events.add(const GameEvent(GameEventType.finished));
  }

  /// Einmal vor der ersten Eingabe.
  void onStart() {}

  /// Zu Beginn jeder Aufnahme ab der zweiten.
  void onVisitStart() {}

  /// Ein gezählter Dart. [visit] enthält ihn bereits.
  void handleDart(DartThrow dart);

  /// Die Aufnahme ist abgeschlossen (3 Darts, vorzeitig oder durch Takeout).
  void handleVisitEnd(List<DartThrow> visitDarts) {}

  /// Felder, die auf dem Board hervorgehoben werden.
  Set<Segment> get targets;

  /// Was die Spielansicht zeigt.
  GameDisplay get display;

  /// Ergebnis für Speicherung und Zusammenfassung. Auch während des Spiels
  /// abrufbar (Zwischenstand).
  GameResult get result;

  /// Hilfsfunktion: Zustand initialisieren, bevor [targets] o. ä. abgefragt
  /// werden.
  void prepare() => _ensureStarted();
}
