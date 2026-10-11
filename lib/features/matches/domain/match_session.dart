import '../../board/domain/board_geometry.dart';
import '../../board/domain/segment.dart';
import '../../dart_source/domain/dart_event.dart';
import 'match_format.dart';
import 'x01_match.dart';

/// Art eines Teilnehmers.
enum MatchPlayerKind { human, bot }

/// Ein Teilnehmer eines Matches.
class MatchPlayer {
  const MatchPlayer({required this.name, required this.kind, this.botAverage, this.profileId});

  const MatchPlayer.human(this.name, {this.profileId}) : kind = MatchPlayerKind.human, botAverage = null;

  const MatchPlayer.bot(this.name, {required double average})
    : kind = MatchPlayerKind.bot,
      botAverage = average,
      profileId = null;

  final String name;
  final MatchPlayerKind kind;

  /// Ziel-Average des Bots (3-Dart-Average).
  final double? botAverage;

  /// Profil, unter dem die Würfe gespeichert werden (nur Menschen; `null` =
  /// Gast, nichts wird gespeichert).
  final int? profileId;

  bool get isBot => kind == MatchPlayerKind.bot;

  Map<String, Object?> toJson() => {
    'name': name,
    'kind': kind.name,
    'botAverage': ?botAverage,
    'profileId': ?profileId,
  };

  factory MatchPlayer.fromJson(Object? json) {
    final m = json is Map ? json : const {};
    final kind = MatchPlayerKind.values.where((k) => k.name == m['kind']).firstOrNull ?? MatchPlayerKind.human;
    return MatchPlayer(
      name: m['name'] is String ? m['name'] as String : '?',
      kind: kind,
      botAverage: m['botAverage'] is num ? (m['botAverage'] as num).toDouble() : null,
      profileId: m['profileId'] is num ? (m['profileId'] as num).toInt() : null,
    );
  }
}

/// Alles, was zum Start eines Matches nötig ist.
class MatchSetup {
  const MatchSetup({required this.format, required this.players, this.firstStarter = 0, this.tournamentMatch});

  final MatchFormat format;
  final List<MatchPlayer> players;
  final int firstStarter;

  /// Gehört das Match zu einem Turnier: Kennung des Turnierspiels.
  final String? tournamentMatch;

  bool get hasBot => players.any((p) => p.isBot);

  Map<String, Object?> toJson() => {
    'format': format.toJson(),
    'players': [for (final p in players) p.toJson()],
    'firstStarter': firstStarter,
    'tournamentMatch': ?tournamentMatch,
  };

  factory MatchSetup.fromJson(Object? json) {
    final m = json is Map ? json : const {};
    final players = [for (final p in (m['players'] is List ? m['players'] as List : const [])) MatchPlayer.fromJson(p)];
    final starter = m['firstStarter'] is num ? (m['firstStarter'] as num).toInt() : 0;
    return MatchSetup(
      format: MatchFormat.fromJson(m['format']),
      players: players,
      firstStarter: players.isEmpty ? 0 : starter.clamp(0, players.length - 1),
      tournamentMatch: m['tournamentMatch'] is String ? m['tournamentMatch'] as String : null,
    );
  }
}

/// Eine Eingabe ins Match.
sealed class MatchInput {
  const MatchInput();
}

class MatchDartInput extends MatchInput {
  const MatchDartInput(this.dart);
  final DartThrow dart;
}

class MatchVisitEndInput extends MatchInput {
  const MatchVisitEndInput();
}

/// Ein Dart mit seinem Platz im Match.
class MatchDartRecord {
  const MatchDartRecord(this.dart, this.outcome);
  final DartThrow dart;
  final MatchDartOutcome outcome;

  int get player => outcome.player;
  bool get counted => outcome.counted;
  int get visitSerial => outcome.visitSerial;
  int get leg => outcome.leg;
}

/// Hält Setup und Eingaben eines Matches. Rückgängig und Korrekturen bauen
/// das Match aus den Eingaben neu auf (wie `GameSession` bei den
/// Trainingsspielen); Bot-Darts sind dabei ganz normale, feste Eingaben.
class MatchSession {
  MatchSession(this.setup) {
    _match = _fresh();
  }

  final MatchSetup setup;
  final List<MatchInput> _inputs = [];
  final List<MatchDartRecord> _records = [];
  late X01Match _match;

  X01Match get match => _match;
  List<MatchInput> get inputs => List.unmodifiable(_inputs);
  List<MatchDartRecord> get records => List.unmodifiable(_records);

  X01Match _fresh() =>
      X01Match(format: setup.format, playerCount: setup.players.length, firstStarter: setup.firstStarter);

  /// Spieler am Zug (bzw. der die laufende Aufnahme wirft).
  MatchPlayer get currentPlayer => setup.players[_match.current];

  void addDart(DartThrow dart) {
    _inputs.add(MatchDartInput(dart));
    _records.add(MatchDartRecord(dart, _match.throwDart(dart)));
  }

  /// Takeout. Doppelte Enden werden zusammengefasst.
  bool endVisit() {
    if (_inputs.isEmpty || _inputs.last is MatchVisitEndInput) return false;
    if (!_match.endVisit()) return false;
    _inputs.add(const MatchVisitEndInput());
    return true;
  }

  /// Darf der letzte Dart zurückgenommen werden? Nur ein Dart eines Menschen
  /// in der laufenden Aufnahme.
  bool get canUndo {
    if (_inputs.isEmpty || _inputs.last is! MatchDartInput || _match.finished) return false;
    return !setup.players[_records.last.player].isBot;
  }

  bool undoLastDart() {
    if (!canUndo) return false;
    _inputs.removeLast();
    _replay();
    return true;
  }

  /// Ersetzt den Dart an Position [dartIndex] aller Darts (wie [records]).
  /// Nur Darts von Menschen.
  bool correctAt(int dartIndex, DartThrow dart) {
    if (dartIndex < 0 || dartIndex >= _records.length) return false;
    if (setup.players[_records[dartIndex].player].isBot) return false;
    var seen = -1;
    for (var i = 0; i < _inputs.length; i++) {
      if (_inputs[i] is MatchDartInput && ++seen == dartIndex) {
        _inputs[i] = MatchDartInput(dart);
        break;
      }
    }
    _replay();
    return true;
  }

  /// Darts der laufenden Aufnahme als Indizes in [records].
  List<int> get currentVisitIndexes {
    final n = _match.physicalDartsInVisit;
    return [for (var i = _records.length - n; i < _records.length; i++) i];
  }

  void _replay() {
    final m = _fresh();
    _records.clear();
    for (final input in _inputs) {
      switch (input) {
        case MatchDartInput(:final dart):
          _records.add(MatchDartRecord(dart, m.throwDart(dart)));
        case MatchVisitEndInput():
          m.endVisit();
      }
    }
    m.events.clear();
    _match = m;
  }

  /// Stellt ein gespeichertes Match wieder her.
  static MatchSession restore(MatchSetup setup, List<MatchInput> inputs) {
    final s = MatchSession(setup);
    for (final i in inputs) {
      switch (i) {
        case MatchDartInput(:final dart):
          s.addDart(dart);
        case MatchVisitEndInput():
          s.endVisit();
      }
    }
    s._match.events.clear();
    return s;
  }

  static Object? inputToJson(MatchInput input) => switch (input) {
    MatchDartInput(:final dart) => {
      's': dart.segment.name,
      'b': dart.segment.bed.name,
      if (dart.position != null) 'x': dart.position!.x,
      if (dart.position != null) 'y': dart.position!.y,
      't': dart.timestamp.millisecondsSinceEpoch,
      'src': dart.source.name,
    },
    MatchVisitEndInput() => 'end',
  };

  static MatchInput? inputFromJson(Object? json) {
    if (json == 'end') return const MatchVisitEndInput();
    if (json is! Map) return null;
    var segment = Segment.tryParse('${json['s']}');
    if (segment == null) return null;
    if (json['b'] == Bed.singleInner.name && segment.bed == Bed.singleOuter) {
      segment = Segment.single(segment.number, inner: true);
    }
    final x = json['x'];
    final y = json['y'];
    final t = json['t'];
    return MatchDartInput(
      DartThrow(
        segment: segment,
        position: x is num && y is num ? BoardPoint(x.toDouble(), y.toDouble()) : null,
        timestamp: t is num ? DateTime.fromMillisecondsSinceEpoch(t.toInt()) : DateTime.now(),
        source: DartSourceKind.values.where((k) => k.name == json['src']).firstOrNull ?? DartSourceKind.manual,
      ),
    );
  }
}
