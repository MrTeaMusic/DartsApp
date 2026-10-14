import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../games/domain/game_catalog.dart';
import '../../stats/domain/stats_calculator.dart';
import 'achievements.dart';
import 'daily_goal.dart';
import 'session_facts.dart';

/// Ein Challenge-Ergebnis, soweit es für Erfolge zählt.
typedef StarRecord = ({int stars, DateTime at});

/// Sammelt Sessions in zeitlicher Reihenfolge und merkt sich, wann jede
/// Stufe eines Erfolgs zum ersten Mal erreicht wurde.
///
/// Inkrementell und kopierbar: Für das laufende Spiel wird eine Kopie des
/// Stands aller abgeschlossenen Sessions um eine vorläufige Session ergänzt.
class AchievementTracker {
  AchievementTracker();

  /// Aus allen abgeschlossenen Sessions von [calc].
  factory AchievementTracker.fromCalculator(StatsCalculator calc) {
    final t = AchievementTracker();
    final sessions = [...calc.sessions]..sort((a, b) => a.endedAt!.compareTo(b.endedAt!));
    for (final s in sessions) {
      t.add(_factsOf(calc, s));
    }
    return t;
  }

  /// Eine abgeschlossene Session ändert sich nicht mehr: ihre Auswertung
  /// (die das Spiel noch einmal durchspielt) wird nur einmal berechnet, nicht
  /// nach jedem Spiel für die ganze Geschichte neu.
  static SessionFacts _factsOf(StatsCalculator calc, SessionRow s) {
    final key = '${s.id}|${s.uid}|${s.endedAt!.microsecondsSinceEpoch}|${s.dartCount}|${s.finished}|${s.resultJson.hashCode}';
    final cached = _factsCache[key];
    if (cached != null) return cached;
    if (_factsCache.length >= _factsCacheSize) _factsCache.clear();
    return _factsCache[key] = sessionFacts(calc, s);
  }

  static final Map<String, SessionFacts> _factsCache = {};
  static const int _factsCacheSize = 50000;

  /// Wertet die Sessions von [calc] vorab in kleinen Stücken aus (Erfolge
  /// und Darts je Tag fürs Tagesziel) und gibt zwischen den Stücken die
  /// Oberfläche frei. Danach sind [AchievementTracker.fromCalculator] und
  /// `dailyActivity` schnell, auch beim ersten Rechner nach dem App-Start,
  /// für den sonst jede Session am Stück noch einmal durchgespielt würde.
  /// Ändert keine Ergebnisse, nur wann sie berechnet werden.
  static Future<void> warmUp(StatsCalculator calc, {Duration slice = const Duration(milliseconds: 8)}) async {
    final watch = Stopwatch()..start();
    for (final s in calc.sessions) {
      _factsOf(calc, s);
      calc.countedPerDayOf(s);
      if (watch.elapsed >= slice) {
        await Future<void>.delayed(Duration.zero);
        watch.reset();
      }
    }
  }

  /// Leert den Zwischenspeicher der Session-Auswertungen (für Tests).
  @visibleForTesting
  static void clearCache() => _factsCache.clear();

  final Map<AchievementMetric, num> _values = {};
  final Set<String> _games = {};
  final Map<String, DateTime> _reachedAt = {};
  Duration _time = Duration.zero;

  AchievementTracker copy() => AchievementTracker()
    .._values.addAll(_values)
    .._games.addAll(_games)
    .._reachedAt.addAll(_reachedAt)
    .._time = _time;

  /// Aktueller Wert einer Kennzahl; `null`, solange es keinen gibt (z. B.
  /// noch kein gewonnenes 501-Leg).
  num? value(AchievementMetric metric) => _values[metric];

  /// Wann eine Stufe erreicht wurde (`null` = noch nicht).
  DateTime? reachedAt(String id, int tier) => _reachedAt[tierKey(id, tier)];

  /// Alle erreichten Stufen als Schlüssel (siehe [tierKey]).
  Set<String> get reached => _reachedAt.keys.toSet();

  /// Erreichte Stufe eines Erfolgs (0 = keine).
  int tierOf(AchievementDef d) => d.tierFor(_values[d.metric]);

  void _sum(AchievementMetric m, num v) {
    if (v != 0) _values[m] = (_values[m] ?? 0) + v;
  }

  void _max(AchievementMetric m, num? v) {
    if (v == null) return;
    final old = _values[m];
    if (old == null || v > old) _values[m] = v;
  }

  void _min(AchievementMetric m, num? v) {
    if (v == null) return;
    final old = _values[m];
    if (old == null || v < old) _values[m] = v;
  }

  void _set(AchievementMetric m, num v) => _values[m] = v;

  /// Nimmt eine Session auf (in zeitlicher Reihenfolge).
  void add(SessionFacts f) {
    _sum(AchievementMetric.darts, f.darts);
    _time += f.duration;
    _set(AchievementMetric.hours, _time.inMinutes ~/ 60);
    _sum(AchievementMetric.tons, f.tons);
    _sum(AchievementMetric.visits140, f.visits140);
    _sum(AchievementMetric.max180, f.max180);
    _max(AchievementMetric.bestAverage, f.average?.floor());
    if (f.highestCheckout > 0) _max(AchievementMetric.highestCheckout, f.highestCheckout);
    _sum(AchievementMetric.checkouts, f.checkouts);
    _sum(AchievementMetric.bullFinishes, f.bullFinishes);
    _min(AchievementMetric.fastest501, f.fastest501);
    if (f.fastest501 == 9) _sum(AchievementMetric.nineDarters, 1);
    _max(AchievementMetric.bobsScore, f.bobsScore);
    if (f.bobsSurvived) _sum(AchievementMetric.bobsSurvived, 1);
    _sum(AchievementMetric.doubleHits, f.doubleHits);
    _max(AchievementMetric.doubleRun, f.doubleRun);
    if (f.cpuWin) _sum(AchievementMetric.cpuWins, 1);
    if (f.tournamentWin) _sum(AchievementMetric.tournamentWins, 1);
    _sum(AchievementMetric.shanghais, f.shanghais);
    if (f.finished && GameCatalog.byId(f.gameId) != null && _games.add(f.gameId)) {
      _set(AchievementMetric.gamesPlayed, _games.length);
    }
    _mark(f.time);
  }

  /// Tagesziel-Serie und -Tage. Ersetzt einen früheren Stand; das Datum
  /// einer Stufe ist der Tag, an dem sie erreicht wurde.
  void applyGoals(GoalStreak streak) {
    _set(AchievementMetric.goalStreak, streak.best);
    _set(AchievementMetric.goalDays, streak.reachedDays.length);
    for (final d in AchievementCatalog.all) {
      if (d.metric == AchievementMetric.goalStreak) {
        for (var tier = 1; tier <= d.maxTier; tier++) {
          final hit = streak.timeline.where((p) => p.run >= d.thresholds[tier - 1]).firstOrNull;
          if (hit != null) _reachedAt.putIfAbsent(tierKey(d.id, tier), () => _endOf(hit.day));
        }
      } else if (d.metric == AchievementMetric.goalDays) {
        for (var tier = 1; tier <= d.maxTier; tier++) {
          final n = d.thresholds[tier - 1].toInt();
          if (streak.reachedDays.length >= n) {
            _reachedAt.putIfAbsent(tierKey(d.id, tier), () => _endOf(streak.reachedDays[n - 1]));
          }
        }
      }
    }
  }

  /// Sterne aus Challenges; Datum einer Stufe ist das Ergebnis, mit dem die
  /// Summe die Schwelle erreichte.
  void applyStars(Iterable<StarRecord> results) {
    final sorted = [...results]..sort((a, b) => a.at.compareTo(b.at));
    var total = 0;
    for (final r in sorted) {
      total += r.stars;
      _set(AchievementMetric.challengeStars, total);
      _mark(r.at, only: AchievementMetric.challengeStars);
    }
  }

  static DateTime _endOf(DateTime day) => DateTime(day.year, day.month, day.day, 23, 59);

  void _mark(DateTime at, {AchievementMetric? only}) {
    for (final d in AchievementCatalog.all) {
      if (only != null && d.metric != only) continue;
      if (only == null && (d.metric == AchievementMetric.goalStreak || d.metric == AchievementMetric.goalDays)) continue;
      final tier = tierOf(d);
      for (var i = 1; i <= tier; i++) {
        _reachedAt.putIfAbsent(tierKey(d.id, i), () => at);
      }
    }
  }
}

/// Stand eines Erfolgs für die Anzeige.
class AchievementStatus {
  const AchievementStatus({required this.def, required this.tier, required this.value, this.unlockedAt});
  final AchievementDef def;

  /// Erreichte Stufe (0 = gesperrt).
  final int tier;

  /// Aktueller Wert der Kennzahl (`null` ohne Daten).
  final num? value;

  /// Wann die erreichte Stufe freigeschaltet wurde.
  final DateTime? unlockedAt;

  bool get unlocked => tier > 0;
  bool get complete => tier >= def.maxTier;

  /// Schwelle der nächsten Stufe (`null`, wenn alle erreicht).
  num? get next => complete ? null : def.thresholds[tier];

  /// Fortschritt zur nächsten Stufe, 0–1.
  double get ratio {
    final n = next;
    if (n == null) return 1;
    final v = value;
    if (v == null) return 0;
    if (def.lowerIsBetter) {
      // Ohne Startwert: je näher an der Schwelle, desto voller.
      return v <= n ? 1 : (n / v).clamp(0, 1).toDouble();
    }
    return n <= 0 ? 0 : (v / n).clamp(0, 1).toDouble();
  }
}

/// Stand aller Erfolge aus berechneten und gespeicherten Freischaltungen.
/// [stored] sind gespeicherte Stufen (Schlüssel → Datum); sie zählen auch
/// dann, wenn die Daten sie heute nicht mehr hergeben.
List<AchievementStatus> achievementStatuses(AchievementTracker tracker, Map<String, DateTime> stored) => [
      for (final d in AchievementCatalog.all)
        () {
          var tier = tracker.tierOf(d);
          for (var i = d.maxTier; i > tier; i--) {
            if (stored.containsKey(tierKey(d.id, i))) {
              tier = i;
              break;
            }
          }
          final key = tierKey(d.id, tier);
          return AchievementStatus(
            def: d,
            tier: tier,
            value: tracker.value(d.metric),
            unlockedAt: tier == 0 ? null : (stored[key] ?? tracker.reachedAt(d.id, tier)),
          );
        }(),
    ];

/// Alle Stufen, die [tracker] erreicht hat, mit Datum.
Map<String, DateTime> reachedTiers(AchievementTracker tracker) => {
      for (final d in AchievementCatalog.all)
        for (var i = 1; i <= tracker.tierOf(d); i++) tierKey(d.id, i): tracker.reachedAt(d.id, i) ?? DateTime.now(),
    };

