import 'dart:math' as math;

import 'quiz_answer.dart';
import 'quiz_config.dart';

/// Gedächtnis zu einer Frage (Rest + Darts) aus allen bisherigen Antworten.
///
/// Gleitende Mittel statt Summen: Die letzten Antworten zählen am meisten,
/// eine früher oft falsche Frage wird nach ein paar richtigen Antworten
/// wieder seltener.
class QuizItemStats {
  int attempts = 0;

  /// Anteil falscher Antworten, gleitend (0–1).
  double wrong = 0;

  /// Antwortzeit in Millisekunden, gleitend.
  double ms = 0;
  bool lastWrong = false;

  static const double _alpha = 0.4;

  void add(QuizAnswer a) {
    final w = a.correct ? 0.0 : 1.0;
    if (attempts == 0) {
      wrong = w;
      ms = a.ms.toDouble();
    } else {
      wrong = wrong * (1 - _alpha) + w * _alpha;
      ms = ms * (1 - _alpha) + a.ms * _alpha;
    }
    attempts++;
    lastWrong = !a.correct;
  }

  /// Ab dieser Antwortzeit gilt eine Frage als langsam.
  static const double slowMs = 5000;

  /// Sicher: mehrmals richtig und schnell.
  bool get mastered => attempts >= 3 && wrong < 0.1 && ms < 4000;

  /// Gewicht für die Auswahl: falsch und langsam beantwortete Fragen
  /// kommen öfter, sichere seltener.
  double get weight {
    if (mastered) return 0.4;
    final slow = ((ms - slowMs) / slowMs).clamp(0.0, 2.0);
    return 1 + 3 * wrong + slow + (lastWrong ? 1.5 : 0);
  }
}

/// Wählt die nächste Frage: zufällig, aber schwache Reste (oft falsch oder
/// langsam) kommen häufiger dran. Das Gedächtnis kommt aus dem Verlauf
/// (gespeicherte Quiz-Sessions) und wächst mit jeder Antwort.
///
/// Dazu im Durchgang: Eine falsch beantwortete Frage kommt nach
/// [retryAfter] anderen Fragen noch einmal, und die letzten [avoidRecent]
/// Fragen werden nicht sofort wiederholt.
class QuizScheduler {
  QuizScheduler({required List<QuizKey> pool, Iterable<QuizAnswer> history = const [], math.Random? random})
      : pool = List.unmodifiable(pool),
        _random = random ?? math.Random() {
    for (final a in history) {
      _stats.putIfAbsent(a.key, QuizItemStats.new).add(a);
    }
  }

  final List<QuizKey> pool;
  final math.Random _random;
  final Map<QuizKey, QuizItemStats> _stats = {};
  final List<QuizKey> _recent = [];

  /// Falsch beantwortete Fragen mit der Zahl der Fragen bis zur Wiederholung.
  final List<(QuizKey, int)> _retry = [];

  static const int retryAfter = 3;
  static const int avoidRecent = 4;

  /// Gewicht einer noch nie gestellten Frage: etwas über dem Durchschnitt,
  /// damit Neues drankommt.
  static const double unseenWeight = 1.2;

  QuizItemStats? statsOf(QuizKey key) => _stats[key];

  double weightOf(QuizKey key) => _stats[key]?.weight ?? unseenWeight;

  /// Die schwächsten Fragen des Pools (höchstes Gewicht, mindestens einmal
  /// gestellt), schwächste zuerst.
  List<QuizKey> weakest([int limit = 6]) {
    final seen = [
      for (final k in pool)
        if (_stats[k] case final s? when !s.mastered && (s.wrong > 0.2 || s.ms > QuizItemStats.slowMs)) k,
    ]..sort((a, b) => weightOf(b).compareTo(weightOf(a)));
    return seen.take(limit).toList();
  }

  /// Nächste Frage; `null` bei leerem Pool.
  QuizKey? next() {
    if (pool.isEmpty) return null;
    for (var i = 0; i < _retry.length; i++) {
      final (key, due) = _retry[i];
      if (due <= 0 && !_recent.take(1).contains(key)) {
        _retry.removeAt(i);
        return _remember(key);
      }
    }
    final avoid = _recent.length < pool.length ? _recent.toSet() : <QuizKey>{};
    final candidates = [for (final k in pool) if (!avoid.contains(k)) k];
    final list = candidates.isEmpty ? pool : candidates;
    var total = 0.0;
    for (final k in list) {
      total += weightOf(k);
    }
    var r = _random.nextDouble() * total;
    for (final k in list) {
      r -= weightOf(k);
      if (r <= 0) return _remember(k);
    }
    return _remember(list.last);
  }

  QuizKey _remember(QuizKey key) {
    _recent.insert(0, key);
    final keep = math.min(avoidRecent, pool.length - 1);
    while (_recent.length > math.max(keep, 0)) {
      _recent.removeLast();
    }
    return key;
  }

  /// Nimmt eine Antwort auf (Gedächtnis und Wiederholung im Durchgang).
  void record(QuizAnswer a) {
    _stats.putIfAbsent(a.key, QuizItemStats.new).add(a);
    for (var i = 0; i < _retry.length; i++) {
      _retry[i] = (_retry[i].$1, _retry[i].$2 - 1);
    }
    _retry.removeWhere((r) => r.$1 == a.key);
    if (!a.correct) _retry.add((a.key, retryAfter));
  }
}
