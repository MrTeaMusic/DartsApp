import 'dart:math' as math;

import '../../games/domain/games/checkout/checkout_rules.dart';
import 'cpu_players.dart';
import 'dart_bot.dart';
import 'match_format.dart';
import 'x01_match.dart';

/// Vorgefertigte Turnierformate: „Best of“-Legs je Runde (Achtelfinale,
/// Viertelfinale, Halbfinale, Finale).
enum TournamentPreset {
  sprint([3, 3, 5, 7]),
  short([5, 7, 9, 11]),
  pdc([11, 13, 17, 21]);

  const TournamentPreset(this.bestOf);
  final List<int> bestOf;

  /// Passendes Preset zu einer Liste, `null` bei eigenem Format.
  static TournamentPreset? of(List<int> bestOf) => values
      .where(
        (p) =>
            p.bestOf.length == bestOf.length &&
            Iterable<int>.generate(bestOf.length).every((i) => p.bestOf[i] == bestOf[i]),
      )
      .firstOrNull;
}

/// Teilnehmer eines Turniers.
class TournamentEntrant {
  const TournamentEntrant({required this.name, required this.average, this.isHuman = false, this.profileId});

  final String name;

  /// Basis-Average (bei 100 % Stärke), bei Menschen ohne Bedeutung.
  final double average;
  final bool isHuman;
  final int? profileId;

  Map<String, Object?> toJson() => {
    'name': name,
    'average': average,
    if (isHuman) 'human': true,
    'profileId': ?profileId,
  };

  factory TournamentEntrant.fromJson(Object? json) {
    final m = json is Map ? json : const {};
    return TournamentEntrant(
      name: m['name'] is String ? m['name'] as String : '?',
      average: m['average'] is num ? (m['average'] as num).toDouble() : 60,
      isHuman: m['human'] == true,
      profileId: m['profileId'] is num ? (m['profileId'] as num).toInt() : null,
    );
  }
}

/// Ein Spiel im Turnierbaum. [a] und [b] sind Indizes in
/// [Tournament.entrants], `null` solange noch nicht feststeht, wer spielt.
class TournamentMatch {
  TournamentMatch({
    required this.round,
    required this.slot,
    this.a,
    this.b,
    this.winner,
    this.scoreA = 0,
    this.scoreB = 0,
  });

  final int round;
  final int slot;
  int? a;
  int? b;
  int? winner;
  int scoreA;
  int scoreB;

  String get id => 'r$round-m$slot';
  bool get ready => a != null && b != null;
  bool get played => winner != null;
  bool involves(int entrant) => a == entrant || b == entrant;

  Map<String, Object?> toJson() => {'a': ?a, 'b': ?b, 'winner': ?winner, 'scoreA': scoreA, 'scoreB': scoreB};

  factory TournamentMatch.fromJson(int round, int slot, Object? json) {
    final m = json is Map ? json : const {};
    int? opt(String k) => m[k] is num ? (m[k] as num).toInt() : null;
    return TournamentMatch(
      round: round,
      slot: slot,
      a: opt('a'),
      b: opt('b'),
      winner: opt('winner'),
      scoreA: opt('scoreA') ?? 0,
      scoreB: opt('scoreB') ?? 0,
    );
  }
}

/// K.-o.-Turnier mit 16 Teilnehmern: ein Mensch und 15 Computergegner.
///
/// Die Stärke der Bots folgt dem Average ihres Vorbilds, multipliziert mit
/// [difficulty]. Spiele ohne den Menschen werden Dart für Dart simuliert.
class Tournament {
  Tournament({
    required this.id,
    required this.createdAt,
    required this.entrants,
    required this.bestOf,
    required this.difficulty,
    required this.rounds,
    this.startScore = 501,
    this.outMode = OutMode.double,
  });

  static const int size = 16;
  static const int roundCount = 4;
  static const double minDifficulty = 0.3;
  static const double maxDifficulty = 1.0;

  final String id;
  final DateTime createdAt;
  final List<TournamentEntrant> entrants;

  /// „Best of“-Legs je Runde.
  final List<int> bestOf;

  /// Stärke der Bots, 0,3–1,0 (Anteil am Average des Vorbilds).
  final double difficulty;
  final int startScore;
  final OutMode outMode;
  final List<List<TournamentMatch>> rounds;

  /// Neues Turnier. Aus [pool] werden 15 Gegner zufällig gezogen; reicht die
  /// Liste nicht, wird mit der Standardliste und notfalls „CPU n“ aufgefüllt.
  /// Die Auslosung des Turnierbaums ist ebenfalls zufällig.
  factory Tournament.create({
    required String humanName,
    int? profileId,
    required List<CpuPlayer> pool,
    required double difficulty,
    required List<int> bestOf,
    required int seed,
    int startScore = 501,
    OutMode outMode = OutMode.double,
    DateTime? now,
  }) {
    assert(bestOf.length == roundCount);
    final random = math.Random(seed);
    final names = <String>{humanName};
    final cpus = <CpuPlayer>[];
    void take(Iterable<CpuPlayer> list) {
      final shuffled = [...list]..shuffle(random);
      for (final c in shuffled) {
        if (cpus.length >= size - 1) return;
        if (names.add(c.name)) cpus.add(c);
      }
    }

    take(pool);
    take(defaultCpuPlayers);
    var n = 1;
    while (cpus.length < size - 1) {
      final name = 'CPU ${n++}';
      if (names.add(name)) cpus.add(CpuPlayer(name, 60));
    }
    final entrants = [
      TournamentEntrant(name: humanName, average: 0, isHuman: true, profileId: profileId),
      for (final c in cpus) TournamentEntrant(name: c.name, average: c.average),
    ];
    final draw = List.generate(size, (i) => i)..shuffle(random);
    final first = [
      for (var i = 0; i < size ~/ 2; i++) TournamentMatch(round: 0, slot: i, a: draw[i * 2], b: draw[i * 2 + 1]),
    ];
    final rounds = <List<TournamentMatch>>[first];
    for (var r = 1; r < roundCount; r++) {
      rounds.add([for (var i = 0; i < size >> (r + 1); i++) TournamentMatch(round: r, slot: i)]);
    }
    final created = now ?? DateTime.now();
    return Tournament(
      id: 't${created.microsecondsSinceEpoch}',
      createdAt: created,
      entrants: entrants,
      bestOf: [for (final b in bestOf) b.clamp(1, 41)],
      difficulty: difficulty.clamp(minDifficulty, maxDifficulty),
      rounds: rounds,
      startScore: startScore,
      outMode: outMode,
    );
  }

  int get humanIndex => entrants.indexWhere((e) => e.isHuman);

  /// Ziel-Average eines Bots in diesem Turnier.
  double botAverage(int entrant) => entrants[entrant].average * difficulty;

  /// Format einer Runde: X01 mit Legs „first to“.
  MatchFormat formatFor(int round) =>
      MatchFormat(startScore: startScore, outMode: outMode, legsToWin: MatchFormat.firstTo(bestOf[round]));

  TournamentMatch? matchById(String id) {
    for (final r in rounds) {
      for (final m in r) {
        if (m.id == id) return m;
      }
    }
    return null;
  }

  TournamentMatch get finalMatch => rounds.last.first;
  int? get champion => finalMatch.winner;
  bool get finished => champion != null;

  /// Erste Runde mit offenem Spiel, [roundCount] wenn fertig.
  int get currentRound {
    for (var r = 0; r < rounds.length; r++) {
      if (rounds[r].any((m) => !m.played)) return r;
    }
    return roundCount;
  }

  /// Nächstes Spiel des Menschen, sobald der Gegner feststeht.
  TournamentMatch? get humanMatch {
    final h = humanIndex;
    for (final r in rounds) {
      for (final m in r) {
        if (!m.played && m.ready && m.involves(h)) return m;
      }
    }
    return null;
  }

  /// Ausgeschieden?
  bool get humanEliminated {
    final h = humanIndex;
    return rounds.any((r) => r.any((m) => m.played && m.involves(h) && m.winner != h));
  }

  /// Ergebnis eintragen und den Sieger in die nächste Runde setzen.
  void record(TournamentMatch match, {required int winner, required int scoreA, required int scoreB}) {
    assert(match.ready && match.involves(winner));
    match
      ..winner = winner
      ..scoreA = scoreA
      ..scoreB = scoreB;
    if (match.round + 1 >= rounds.length) return;
    final next = rounds[match.round + 1][match.slot ~/ 2];
    if (match.slot.isEven) {
      next.a = winner;
    } else {
      next.b = winner;
    }
  }

  /// Simuliert alle spielbereiten Spiele ohne den Menschen in der aktuellen
  /// Runde. Gibt die Zahl der simulierten Spiele zurück.
  int simulateRound(math.Random random) {
    final r = currentRound;
    if (r >= rounds.length) return 0;
    var count = 0;
    final h = humanIndex;
    for (final m in rounds[r]) {
      if (m.played || !m.ready || m.involves(h)) continue;
      final starter = random.nextInt(2);
      final (sa, sb) = simulateMatch(formatFor(r), botAverage(m.a!), botAverage(m.b!), random, firstStarter: starter);
      record(m, winner: sa > sb ? m.a! : m.b!, scoreA: sa, scoreB: sb);
      count++;
    }
    return count;
  }

  /// Spielt ein Match zweier Bots Dart für Dart und liefert die Legs.
  static (int, int) simulateMatch(
    MatchFormat format,
    double avgA,
    double avgB,
    math.Random random, {
    int firstStarter = 0,
  }) {
    final bots = [DartBot.forAverage(avgA, random: random), DartBot.forAverage(avgB, random: random)];
    final m = X01Match(format: format, playerCount: 2, firstStarter: firstStarter);
    final at = DateTime(2026);
    var guard = 0;
    while (!m.finished && guard++ < 200000) {
      if (m.visitClosed) {
        m.endVisit();
        continue;
      }
      m.throwDart(bots[m.current].next(m, at: at));
    }
    return (m.players[0].totalLegs, m.players[1].totalLegs);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'entrants': [for (final e in entrants) e.toJson()],
    'bestOf': bestOf,
    'difficulty': difficulty,
    'startScore': startScore,
    'outMode': outMode.name,
    'rounds': [
      for (final r in rounds) [for (final m in r) m.toJson()],
    ],
  };

  /// `null`, wenn die Daten nicht zu einem Turnier passen.
  static Tournament? fromJson(Object? json) {
    if (json is! Map) return null;
    final entrants = [
      for (final e in (json['entrants'] is List ? json['entrants'] as List : const [])) TournamentEntrant.fromJson(e),
    ];
    final bestOf = [
      for (final b in (json['bestOf'] is List ? json['bestOf'] as List : const []))
        if (b is num) b.toInt(),
    ];
    final rawRounds = json['rounds'] is List ? json['rounds'] as List : const [];
    if (entrants.length != size || bestOf.length != roundCount || rawRounds.length != roundCount) return null;
    if (entrants.where((e) => e.isHuman).length != 1) return null;
    final rounds = <List<TournamentMatch>>[];
    for (var r = 0; r < roundCount; r++) {
      final list = rawRounds[r] is List ? rawRounds[r] as List : const [];
      if (list.length != size >> (r + 1)) return null;
      rounds.add([for (var i = 0; i < list.length; i++) TournamentMatch.fromJson(r, i, list[i])]);
    }
    final created = json['createdAt'];
    return Tournament(
      id: json['id'] is String ? json['id'] as String : 't0',
      createdAt: created is num ? DateTime.fromMillisecondsSinceEpoch(created.toInt()) : DateTime.now(),
      entrants: entrants,
      bestOf: bestOf,
      difficulty: json['difficulty'] is num ? (json['difficulty'] as num).toDouble() : 0.6,
      rounds: rounds,
      startScore: json['startScore'] is num ? (json['startScore'] as num).toInt() : 501,
      outMode: OutMode.values.where((m) => m.name == json['outMode']).firstOrNull ?? OutMode.double,
    );
  }
}
