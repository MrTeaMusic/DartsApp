/// Spielstand für den zweiten Bildschirm: kompakt, ohne Abhängigkeit zu den
/// Spielen, fertig beschriftet (der Hub übersetzt), damit Tablet, Mac und die
/// Browser-Seite ihn ohne eigene Spiellogik anzeigen können.
library;

/// Version des Formats. Neue Felder sind optional; ein Viewer ignoriert, was
/// er nicht kennt.
const int screenStateVersion = 1;

/// Was am PC gerade läuft.
enum ScreenKind {
  /// Nichts: „Warte auf Spiel am PC“.
  idle,

  /// Trainingsspiel (Checkout, Around the Clock, X01 solo …).
  training,

  /// X01-Match gegen Bot oder Mitspieler, auch im Turnier.
  match,

  /// Mitschreiben der Darts vom Board (Live-Modus).
  live;

  static ScreenKind byName(Object? name) => values.where((k) => k.name == name).firstOrNull ?? idle;
}

/// Färbung einer Einblendung.
enum ScreenTone {
  positive,
  negative,
  neutral;

  static ScreenTone byName(Object? name) => values.where((k) => k.name == name).firstOrNull ?? neutral;
}

/// Ein Spieler bzw. eine Tafel.
class ScreenPlayer {
  const ScreenPlayer({
    required this.name,
    required this.score,
    this.scoreLabel = '',
    this.active = false,
    this.bot = false,
    this.winner = false,
    this.starter = false,
    this.legs,
    this.sets,
    this.average,
    this.darts,
    this.lastVisit,
  });

  final String name;

  /// Die große Zahl: Rest, Ziel („T20“) oder Punkte.
  final String score;

  /// Beschriftung der großen Zahl („Rest“, „Ziel“).
  final String scoreLabel;

  /// Am Zug.
  final bool active;
  final bool bot;
  final bool winner;

  /// Hat das laufende Leg angeworfen.
  final bool starter;

  /// Gewonnene Legs (im Satz bzw. Match) und Sätze, `null` = ohne.
  final int? legs;
  final int? sets;

  /// 3-Dart-Average, fertig formatiert („54,3“).
  final String? average;
  final int? darts;

  /// Punkte der letzten Aufnahme.
  final int? lastVisit;

  Map<String, Object?> toJson() => {
        'name': name,
        'score': score,
        if (scoreLabel.isNotEmpty) 'scoreLabel': scoreLabel,
        if (active) 'active': true,
        if (bot) 'bot': true,
        if (winner) 'winner': true,
        if (starter) 'starter': true,
        'legs': ?legs,
        'sets': ?sets,
        'average': ?average,
        'darts': ?darts,
        'lastVisit': ?lastVisit,
      };

  factory ScreenPlayer.fromJson(Object? json) {
    final m = json is Map ? json : const {};
    return ScreenPlayer(
      name: _str(m['name']) ?? '',
      score: _str(m['score']) ?? '',
      scoreLabel: _str(m['scoreLabel']) ?? '',
      active: m['active'] == true,
      bot: m['bot'] == true,
      winner: m['winner'] == true,
      starter: m['starter'] == true,
      legs: _int(m['legs']),
      sets: _int(m['sets']),
      average: _str(m['average']),
      darts: _int(m['darts']),
      lastVisit: _int(m['lastVisit']),
    );
  }
}

/// Ein Treffer auf dem Board: Feld und (falls bekannt) Position, normiert
/// wie `BoardPoint` (Mitte 0/0, Radius 1 = Double-Außenkante, y nach oben).
class ScreenHit {
  const ScreenHit(this.segment, {this.x, this.y});

  /// Kurzname wie „T20“, „25“, „BULL“, „MISS“.
  final String segment;
  final double? x;
  final double? y;

  Map<String, Object?> toJson() => {
        's': segment,
        if (x != null) 'x': _round(x!),
        if (y != null) 'y': _round(y!),
      };

  factory ScreenHit.fromJson(Object? json) {
    final m = json is Map ? json : const {};
    return ScreenHit(_str(m['s']) ?? 'MISS', x: _double(m['x']), y: _double(m['y']));
  }

  static double _round(double v) => (v * 1000).roundToDouble() / 1000;
}

/// Kennzahl unter der Tafel („Average 54,3“).
class ScreenStat {
  const ScreenStat(this.label, this.value);
  final String label;
  final String value;

  Map<String, Object?> toJson() => {'label': label, 'value': value};

  factory ScreenStat.fromJson(Object? json) {
    final m = json is Map ? json : const {};
    return ScreenStat(_str(m['label']) ?? '', _str(m['value']) ?? '');
  }
}

/// Der komplette Stand, wie er an die Viewer geht.
class ScreenState {
  const ScreenState({
    this.kind = ScreenKind.idle,
    this.title = '',
    this.subtitle,
    this.status,
    this.players = const [],
    this.visit = const [],
    this.visitScore,
    this.bust = false,
    this.lastVisit = const [],
    this.lastVisitScore,
    this.route = const [],
    this.setup = const [],
    this.setupLabel,
    this.stats = const [],
    this.hits = const [],
    this.hitSerial = 0,
    this.banner,
    this.bannerTone = ScreenTone.neutral,
    this.progress,
    this.progressLabel,
    this.finished = false,
  });

  static const ScreenState idle = ScreenState();

  final ScreenKind kind;

  /// Name des Spiels („501 Match“, „Checkout-Training“).
  final String title;

  /// Zweite Zeile, z. B. „Satz 1 · Leg 3 · Halbfinale“.
  final String? subtitle;

  /// Wer gerade wirft bzw. worauf gewartet wird („Ben ist dran“).
  final String? status;
  final List<ScreenPlayer> players;

  /// Darts der laufenden Aufnahme (Kurznamen, 0–3).
  final List<String> visit;
  final int? visitScore;

  /// Laufende Aufnahme überworfen.
  final bool bust;

  /// Zuletzt abgeschlossene Aufnahme.
  final List<String> lastVisit;
  final int? lastVisitScore;

  /// Checkout-Weg für die restlichen Darts.
  final List<String> route;

  /// Stell-Vorschlag, wenn kein Finish geht, mit Beschriftung
  /// („Stellen auf 32“).
  final List<String> setup;
  final String? setupLabel;
  final List<ScreenStat> stats;

  /// Treffer für das kleine Board: laufende Aufnahme, sonst die letzte.
  final List<ScreenHit> hits;

  /// Zählt die Darts; steigt der Wert, ist ein neuer Treffer dazugekommen.
  final int hitSerial;

  /// Einblendung („Bust“, „Leg an Ben – 81 gecheckt“).
  final String? banner;
  final ScreenTone bannerTone;

  /// Fortschritt 0–1 (Trainingsspiele) und Beschriftung („7/21“).
  final double? progress;
  final String? progressLabel;

  /// Spiel vorbei, Endstand.
  final bool finished;

  bool get isIdle => kind == ScreenKind.idle;

  Map<String, Object?> toJson() => {
        'v': screenStateVersion,
        'kind': kind.name,
        if (title.isNotEmpty) 'title': title,
        'subtitle': ?subtitle,
        'status': ?status,
        if (players.isNotEmpty) 'players': [for (final p in players) p.toJson()],
        if (visit.isNotEmpty) 'visit': visit,
        'visitScore': ?visitScore,
        if (bust) 'bust': true,
        if (lastVisit.isNotEmpty) 'lastVisit': lastVisit,
        'lastVisitScore': ?lastVisitScore,
        if (route.isNotEmpty) 'route': route,
        if (setup.isNotEmpty) 'setup': setup,
        'setupLabel': ?setupLabel,
        if (stats.isNotEmpty) 'stats': [for (final s in stats) s.toJson()],
        if (hits.isNotEmpty) 'hits': [for (final h in hits) h.toJson()],
        if (hitSerial != 0) 'hitSerial': hitSerial,
        'banner': ?banner,
        if (banner != null) 'bannerTone': bannerTone.name,
        'progress': ?progress,
        'progressLabel': ?progressLabel,
        if (finished) 'finished': true,
      };

  factory ScreenState.fromJson(Object? json) {
    final m = json is Map ? json : const {};
    final progress = _double(m['progress']);
    return ScreenState(
      kind: ScreenKind.byName(m['kind']),
      title: _str(m['title']) ?? '',
      subtitle: _str(m['subtitle']),
      status: _str(m['status']),
      players: [for (final p in _list(m['players'])) ScreenPlayer.fromJson(p)],
      visit: _strings(m['visit']),
      visitScore: _int(m['visitScore']),
      bust: m['bust'] == true,
      lastVisit: _strings(m['lastVisit']),
      lastVisitScore: _int(m['lastVisitScore']),
      route: _strings(m['route']),
      setup: _strings(m['setup']),
      setupLabel: _str(m['setupLabel']),
      stats: [for (final s in _list(m['stats'])) ScreenStat.fromJson(s)],
      hits: [for (final h in _list(m['hits'])) ScreenHit.fromJson(h)],
      hitSerial: _int(m['hitSerial']) ?? 0,
      banner: _str(m['banner']),
      bannerTone: ScreenTone.byName(m['bannerTone']),
      progress: progress?.clamp(0.0, 1.0),
      progressLabel: _str(m['progressLabel']),
      finished: m['finished'] == true,
    );
  }
}

String? _str(Object? v) => v is String ? v : null;
int? _int(Object? v) => v is num ? v.toInt() : null;
double? _double(Object? v) => v is num ? v.toDouble() : null;
List<Object?> _list(Object? v) => v is List ? v : const [];
List<String> _strings(Object? v) => [for (final s in _list(v)) if (s is String) s];
