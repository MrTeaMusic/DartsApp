import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;

import '../../../core/app_version.dart';
import '../../../core/database/app_database.dart';
import '../domain/session_history.dart';

/// Dateiendung geteilter Matches: `Ben-vs-Bot-2026-11-05.dartlab`.
const sharedMatchExtension = 'dartlab';

/// Medientyp, unter dem die App die Datei bei Android und Apple anmeldet.
const sharedMatchMimeType = 'application/vnd.dartlab.match+json';

/// Apple-Typkennung (UTI) für die Dokumenttypen in den Info.plist-Dateien.
const sharedMatchUti = 'de.dartlab.match';

/// Kennung im JSON, an der DartLab die Datei erkennt.
const _formatId = 'dartlab-match';

/// Version des Dateiformats. Ältere Apps lehnen neuere Dateien mit einem
/// Hinweis aufs Update ab.
const sharedMatchFormatVersion = 1;

/// Haus-Elo vor und nach dem Match, wie beim Absender berechnet.
class SharedElo {
  const SharedElo({required this.before, required this.after});
  final double before;
  final double after;
  double get change => after - before;
}

/// Warum eine Datei nicht geöffnet werden konnte.
enum SharedMatchError {
  /// Keine DartLab-Datei (falsches Format oder kaputt).
  notDartLab,

  /// Mit einer neueren DartLab-Version erstellt.
  newerVersion,
}

class SharedMatchException implements Exception {
  const SharedMatchException(this.error);
  final SharedMatchError error;
  @override
  String toString() => 'SharedMatchException(${error.name})';
}

/// Ein Match (oder eine Trainings-Session) zum Weitergeben: die Session-Zeile
/// mit allen Würfen, so wie sie beim Absender gespeichert ist. Der Empfänger
/// baut daraus dieselbe Detailansicht, schreibt aber nichts in seine
/// Datenbank.
class SharedMatch {
  const SharedMatch({
    required this.player,
    required this.session,
    required this.throws,
    required this.createdAt,
    this.elo,
    this.appVersion = appVersionName,
  });

  /// Name des Absenders (der Spieler, dem die Session gehört).
  final String player;
  final SessionRow session;
  final List<ThrowRow> throws;
  final DateTime createdAt;
  final SharedElo? elo;

  /// DartLab-Version des Absenders.
  final String appVersion;

  /// Detailansicht wie in der App.
  SessionDetail toDetail() => buildSessionDetail(session, throws, playerName: player);

  /// Aus einer gespeicherten Session. Interne Nummern (Profil, Datenbank-IDs)
  /// und Rohdaten der Würfe bleiben draußen.
  factory SharedMatch.fromSession({
    required String player,
    required SessionRow session,
    required List<ThrowRow> throws,
    SharedElo? elo,
    DateTime? createdAt,
  }) {
    return SharedMatch(
      player: player,
      session: session.copyWith(id: 0, playerId: 0, deletedAt: const Value(null)),
      throws: [for (final t in throws) t.copyWith(id: 0, sessionId: 0, playerId: 0, rawJson: const Value(null))],
      elo: elo,
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  Map<String, Object?> toJson() => {
        'format': _formatId,
        'version': sharedMatchFormatVersion,
        'app': appVersion,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'player': player,
        if (elo != null) 'elo': {'before': elo!.before, 'after': elo!.after},
        'session': session.toJson(),
        'throws': [for (final t in throws) t.toJson()],
      };

  Uint8List encode() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  /// Liest eine Datei. Wirft [SharedMatchException], wenn es keine
  /// DartLab-Datei ist oder sie aus einer neueren Version stammt.
  static SharedMatch decode(List<int> bytes) {
    final Object? json;
    try {
      // BOM von Windows-Editoren überspringen.
      var start = 0;
      if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) start = 3;
      json = jsonDecode(utf8.decode(bytes.sublist(start)));
    } on FormatException {
      throw const SharedMatchException(SharedMatchError.notDartLab);
    }
    if (json is! Map<String, Object?> || json['format'] != _formatId) {
      throw const SharedMatchException(SharedMatchError.notDartLab);
    }
    final version = json['version'];
    if (version is! int) throw const SharedMatchException(SharedMatchError.notDartLab);
    if (version > sharedMatchFormatVersion) throw const SharedMatchException(SharedMatchError.newerVersion);
    try {
      final elo = json['elo'];
      return SharedMatch(
        player: json['player'] as String? ?? '',
        appVersion: json['app'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        elo: elo is Map<String, Object?>
            ? SharedElo(before: (elo['before'] as num).toDouble(), after: (elo['after'] as num).toDouble())
            : null,
        session: SessionRow.fromJson(json['session'] as Map<String, Object?>),
        throws: [for (final t in json['throws'] as List) ThrowRow.fromJson(t as Map<String, Object?>)],
      );
    } on Object {
      // Fehlende Felder, falsche Typen: dieselbe Meldung wie bei fremden Dateien.
      throw const SharedMatchException(SharedMatchError.notDartLab);
    }
  }

  /// Vorschlag für den Dateinamen, z. B. `dartlab-ben-vs-bot-60-2026-11-05.dartlab`.
  String get fileName {
    String two(int v) => v.toString().padLeft(2, '0');
    final s = session.startedAt;
    final entry = HistoryEntry(session);
    final who = [
      player,
      if (entry.hasOpponent && entry.opponents.isNotEmpty) 'vs ${entry.opponents.first}' else session.gameId,
    ].join(' ');
    final slug = who
        .toLowerCase()
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll('ß', 'ss')
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final head = slug.isEmpty ? 'dartlab' : 'dartlab-$slug';
    return '$head-${s.year}-${two(s.month)}-${two(s.day)}.$sharedMatchExtension';
  }
}
