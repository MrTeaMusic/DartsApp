/// Streuungs-Analyse: Wohin verzieht man je Zielfeld, wie stark streut es,
/// und welcher Tipp passt dazu? Reine Berechnung aus Positionen (Autodarts,
/// Simulator), ohne Datenbank und ohne Oberfläche. Siehe
/// docs/streuungs-analyse.md.
library;

import 'dart:math' as math;

import '../../../core/database/app_database.dart';
import '../../board/domain/board_geometry.dart';
import '../../board/domain/segment.dart';
import '../../games/domain/games/checkout/checkout_rules.dart';
import 'stats_models.dart';

/// Schwellen der Streuungs-Analyse (alle Längen in Millimetern).
abstract final class ScatterRules {
  /// Mindestzahl an Darts je Feld, damit es ausgewertet wird.
  static const int minDarts = 30;

  /// Darts weiter als so weit vom Feldmittelpunkt zählen nicht (Abpraller,
  /// falsches Ziel, Fehlerkennung).
  static const double outlierMm = 100;

  /// Geschätztes Bull: Dart höchstens so weit von der Mitte.
  static const double bullRadiusMm = 32;

  /// Geschätztes T20/T19: Dart mindestens so weit von der Mitte (darunter
  /// ist nicht klar, ob er dem Bull oder dem Triple galt) …
  static const double clusterMinMm = 45;

  /// … und höchstens so weit (knapp über dem Double-Ring).
  static const double clusterMaxMm = 187;

  /// In X01 ohne angezeigtes Ziel (Matches, Autodarts Live) gilt ein Dart
  /// erst ab diesem Rest als Scoring-Dart (darunter wird gestellt).
  static const int scoringRemaining = 100;

  /// Eine Abweichung unter dem größten der drei Werte gilt als „mittig“:
  /// [centeredMinMm], [centeredSigma] × Streuung, [centeredStdErr] ×
  /// Standardfehler des Mittelwerts.
  static const double centeredMinMm = 3;
  static const double centeredSigma = 0.25;
  static const double centeredStdErr = 2;

  /// Streuung (je Achse, gemittelt) bis hier gilt als eng gruppiert …
  static const double tightMm = 9;

  /// … ab hier als groß.
  static const double wideMm = 22;

  /// Eine Achse streut „vor allem“, wenn sie so viel stärker streut.
  static const double shapeRatio = 1.35;

  /// Felder bis so weit (Grad) von der 20 gelten als „oben“: Dort entspricht
  /// „hoch/tief“ im Feld auch hoch/tief an der Scheibe.
  static const double upperZoneDegrees = 45;
}

double _mm(double normalized) => normalized * BoardGeometry.boardRadiusMm;

/// Name eines Zielfelds in der Oberfläche („T20“, „D16“, „Bull“).
String scatterFieldName(Segment field) => field.isBull ? 'Bull' : field.name;

// ---------------------------------------------------------------------------
// Feld-Koordinaten
// ---------------------------------------------------------------------------

/// Achsen eines Felds, als stünde es oben (wie in der Doppel-Ansicht):
/// „hoch“ = vom Bull weg entlang der Mittellinie, „rechts“ = im
/// Uhrzeigersinn (zur nächsten Zahl). Beim Bull gelten die Achsen der
/// Scheibe, wie sie hängt.
class FieldFrame {
  const FieldFrame._(this.radial, this.tangential, this.degrees);

  factory FieldFrame.of(Segment field) {
    if (field.isBull || field.isMiss) return const FieldFrame._(BoardPoint(0, 1), BoardPoint(1, 0), 0);
    final deg = BoardGeometry.angleOf(field.number);
    final rad = deg * math.pi / 180;
    return FieldFrame._(BoardPoint(math.sin(rad), math.cos(rad)), BoardPoint(math.cos(rad), -math.sin(rad)), deg);
  }

  /// Einheitsvektor „hoch“ (nach außen) in Board-Koordinaten.
  final BoardPoint radial;

  /// Einheitsvektor „rechts“ (im Uhrzeigersinn) in Board-Koordinaten.
  final BoardPoint tangential;

  /// Winkel des Felds im Uhrzeigersinn ab der 20 (Bull: 0).
  final double degrees;

  /// Zerlegt eine Abweichung (Board-Koordinaten) in rechts/links ([t]) und
  /// hoch/tief ([r]), in denselben Einheiten.
  ({double t, double r}) decompose(BoardPoint d) =>
      (t: d.x * tangential.x + d.y * tangential.y, r: d.x * radial.x + d.y * radial.y);

  /// Liegt das Feld oben auf der Scheibe (hoch/tief wie an der Scheibe)?
  bool get upper {
    final off = degrees > 180 ? 360 - degrees : degrees;
    return off <= ScatterRules.upperZoneDegrees;
  }

  /// Verläuft „rechts/links“ des Felds an der Scheibe eher waagerecht (Felder
  /// oben und unten) als senkrecht (Felder an den Seiten)?
  bool get tangentialIsHorizontal => tangential.x.abs() >= tangential.y.abs();
}

/// Nachbarzahl im Uhrzeigersinn („rechts“) bzw. dagegen („links“); `null`
/// beim Bull.
int? neighbourOf(Segment field, {required bool right}) {
  if (field.isBull || field.isMiss) return null;
  final i = BoardGeometry.numbers.indexOf(field.number);
  return BoardGeometry.numbers[(i + (right ? 1 : 19)) % 20];
}

// ---------------------------------------------------------------------------
// Ziel je Dart
// ---------------------------------------------------------------------------

/// Was über das Ziel eines Darts bekannt ist.
sealed class DartAim {
  const DartAim();
}

/// Ziele, die das Trainingsspiel in dem Moment vorgab (nachgespielt).
class TargetsAim extends DartAim {
  const TargetsAim(this.targets);
  final Set<Segment> targets;
}

/// Aus Regeln geschätztes Ziel, z. B. das Finish-Doppel bei Rest 32 in einem
/// Match ohne angezeigtes Ziel.
class RuleAim extends DartAim {
  const RuleAim(this.field);
  final Segment field;
}

/// Scoring-Dart ohne angezeigtes Ziel (X01-Rest hoch): T20 oder T19 schätzen.
class ScoringAim extends DartAim {
  const ScoringAim();
}

/// Nichts bekannt (Autodarts Live ohne X01): T20, T19 oder Bull schätzen.
class UnknownAim extends DartAim {
  const UnknownAim();
}

/// Ein Dart mit Position und (bekanntem oder geschätztem) Zielfeld.
class ScatterDart {
  const ScatterDart({required this.field, required this.position, required this.hit, required this.exact});
  final Segment field;
  final BoardPoint position;

  /// Zielfeld getroffen (beim Bull: 25 oder 50).
  final bool hit;

  /// Ziel vom Spiel angezeigt; sonst geschätzt.
  final bool exact;
}

/// Zielfeld aus den Zielen des Spiels, wenn sie genau ein Feld meinen: ein
/// Double, ein Triple oder das Bull (auch „25 oder 50“). Singles zählen
/// nicht: Ob innen oder außen gezielt wurde, ist offen.
Segment? aimFieldOf(Set<Segment> targets) {
  if (targets.isEmpty) return null;
  if (targets.every((t) => t.isBull)) return Segment.bull;
  if (targets.length != 1) return null;
  final t = targets.first;
  return t.isDouble || t.isTriple ? t : null;
}

final Segment _t20 = Segment.triple(20);
final Segment _t19 = Segment.triple(19);
const Set<int> _sector20 = {20, 1, 5};
const Set<int> _sector19 = {19, 7, 3};

/// Geschätztes Zielfeld eines Darts an [p]: Bull (nah an der Mitte), T20
/// (Sektoren 20/1/5) oder T19 (19/7/3), nur wenn das Feld in [allowed]
/// vorkommt. Sonst `null`.
Segment? inferCluster(BoardPoint p, {required bool t20, required bool t19, required bool bull}) {
  final r = _mm(p.distance);
  if (r <= ScatterRules.bullRadiusMm) return bull ? Segment.bull : null;
  if (r < ScatterRules.clusterMinMm || r > ScatterRules.clusterMaxMm) return null;
  final n = BoardGeometry.numberAtAngle(p.angleDegrees);
  if (t20 && _sector20.contains(n)) return _t20;
  if (t19 && _sector19.contains(n)) return _t19;
  return null;
}

/// Ordnet einem gespeicherten Dart sein Zielfeld zu; `null`, wenn er nicht
/// zählt (ohne Position, manuell eingegeben, Ziel unklar, Ausreißer).
ScatterDart? scatterDartOf(ThrowRow row, Segment landed, DartAim aim) {
  final x = row.x, y = row.y;
  if (x == null || y == null || row.source == 'manual') return null;
  final p = BoardPoint(x, y);
  Segment? field;
  var exact = false;
  switch (aim) {
    case TargetsAim(:final targets):
      field = aimFieldOf(targets);
      exact = field != null;
      if (field == null) {
        // Mehrere Ziele (Cricket, Shanghai …) oder keins: nur die klaren
        // Scoring-Felder schätzen, und nur, wenn das Spiel sie erlaubt.
        final any = targets.isEmpty;
        field = inferCluster(
          p,
          t20: any || targets.contains(_t20),
          t19: any || targets.contains(_t19),
          bull: any || targets.any((t) => t.isBull),
        );
      }
    case RuleAim(field: final f):
      field = f;
    case ScoringAim():
      field = inferCluster(p, t20: true, t19: true, bull: false);
    case UnknownAim():
      field = inferCluster(p, t20: true, t19: true, bull: true);
  }
  if (field == null) return null;
  final c = BoardGeometry.centerOf(field);
  final d = BoardPoint(p.x - c.x, p.y - c.y);
  if (_mm(d.distance) > ScatterRules.outlierMm) return null;
  return ScatterDart(
    field: field,
    position: p,
    hit: field.isBull ? landed.isBull : landed.sameField(field),
    exact: exact,
  );
}

/// Ziel je gezähltem Dart einer X01-Session ohne angezeigtes Ziel (Match):
/// Die Würfe werden mit Rest und Bust-Regel nachgerechnet. Ein Dart, dessen
/// Checkout-Weg genau ein Doppel ist, zielte (vermutlich) auf dieses Doppel;
/// ab [ScatterRules.scoringRemaining] Rest ist er ein Scoring-Dart.
///
/// [legEnds]: Aufnahme-Index, mit dem ein Leg endete (auch verlorene Legs,
/// deren Würfe des Gegners nicht gespeichert sind), aufsteigend.
List<DartAim?> x01AimsOf(
  List<ThrowRow> counted, {
  required int startScore,
  required OutMode out,
  bool doubleIn = false,
  List<int> legEnds = const [],
}) {
  final aims = <DartAim?>[];
  var remaining = startScore;
  var opened = !doubleIn;
  var leg = 0;
  int? visit;
  var visitStart = remaining;
  var inVisit = 0;
  var visitDone = false;
  for (final t in counted) {
    if (t.visitIndex != visit) {
      // Neues Leg, wenn das vorige mit einer früheren Aufnahme endete.
      while (leg < legEnds.length && t.visitIndex > legEnds[leg]) {
        leg++;
        if (remaining != startScore) {
          remaining = startScore;
          opened = !doubleIn;
        }
      }
      visit = t.visitIndex;
      visitStart = remaining;
      inVisit = 0;
      visitDone = false;
    }
    if (visitDone || inVisit >= 3) {
      aims.add(null);
      continue;
    }
    final dartsLeft = 3 - inVisit;
    inVisit++;
    DartAim? aim;
    if (!opened) {
      aim = null;
    } else if (out != OutMode.straight && remaining <= 50) {
      final path = CheckoutRules.suggest(remaining, darts: dartsLeft, out: out);
      if (path != null && path.length == 1 && path.first.isDouble) {
        aim = RuleAim(path.first.isBull ? Segment.bull : path.first);
      }
    } else if (remaining >= ScatterRules.scoringRemaining) {
      aim = const ScoringAim();
    }
    aims.add(aim);
    final seg = Segment.tryParse(t.segment) ?? Segment.miss;
    if (!opened) {
      if (seg.isDouble) {
        opened = true;
      } else {
        continue;
      }
    }
    if (CheckoutRules.isBust(remaining, seg, out)) {
      remaining = visitStart;
      visitDone = true;
      continue;
    }
    remaining -= seg.score;
    if (remaining == 0) {
      remaining = startScore;
      opened = !doubleIn;
      visitDone = true;
    }
  }
  return aims;
}

// ---------------------------------------------------------------------------
// Auswertung je Feld
// ---------------------------------------------------------------------------

/// Richtung einer mittleren Abweichung (im Feld, siehe [FieldFrame]).
enum ScatterDirection {
  center,
  up,
  upRight,
  right,
  downRight,
  down,
  downLeft,
  left,
  upLeft;

  /// Richtung aus rechts/links [t] und hoch/tief [r]; unter [threshold]
  /// (gleiche Einheit) „mittig“.
  static ScatterDirection of(double t, double r, double threshold) {
    if (math.sqrt(t * t + r * r) < threshold) return center;
    final deg = math.atan2(t, r) * 180 / math.pi;
    final i = (((deg + 22.5) % 360 + 360) % 360) ~/ 45;
    return values[1 + i % 8];
  }
}

/// Größe, ab der eine Abweichung zählt (mm), siehe [ScatterRules].
double scatterThreshold(double sigmaMm, int n) => math.max(
      ScatterRules.centeredMinMm,
      math.max(ScatterRules.centeredSigma * sigmaMm, n <= 0 ? 0 : ScatterRules.centeredStdErr * sigmaMm / math.sqrt(n)),
    );

/// Kurzform einer Feld-Auswertung für die Tipps (alles in mm, Feld-Achsen).
class ScatterShape {
  const ScatterShape({
    required this.field,
    required this.offsetT,
    required this.offsetR,
    required this.sdT,
    required this.sdR,
    required this.darts,
  });

  final Segment field;

  /// Mittlere Abweichung rechts (+) / links (−) und hoch (+) / tief (−).
  final double offsetT;
  final double offsetR;

  /// Standardabweichung seitlich und in der Höhe (Feld-Achsen).
  final double sdT;
  final double sdR;
  final int darts;

  /// Streuung je Achse, gemittelt.
  double get sigma => math.sqrt((sdT * sdT + sdR * sdR) / 2);
  double get offset => math.sqrt(offsetT * offsetT + offsetR * offsetR);
  double get threshold => scatterThreshold(sigma, darts);
  bool get centered => offset < threshold;
  ScatterDirection get direction => ScatterDirection.of(offsetT, offsetR, threshold);
}

/// Art eines Tipps; der Text steht in der Oberfläche.
enum ScatterTipKind {
  /// Mittig und eng: so weitermachen.
  steady,

  /// Eng gruppiert, aber daneben: Zielpunkt/Stand verschieben.
  shiftAim,

  /// Mittig, Streuung normal: Gruppierung enger bekommen.
  tighten,

  /// Feld oben, Darts zu tief: Wurf evtl. zu flach.
  tooFlat,

  /// Feld oben, Darts zu hoch: evtl. zu viel Kraft / zu spät gelöst.
  tooSteep,

  /// Darts eher Richtung Bull (Feld nicht oben).
  inside,

  /// Darts eher nach außen (Feld nicht oben).
  outside,

  /// Seitliche Tendenz ([ScatterTip.toward] = Nachbarzahl, beim Bull `null`
  /// und [ScatterTip.right] gibt die Seite an).
  drift,

  /// Streut vor allem waagerecht an der Scheibe.
  wideSideways,

  /// Streut vor allem senkrecht an der Scheibe.
  wideHeight,

  /// Streut insgesamt stark.
  wideOverall,
}

class ScatterTip {
  const ScatterTip(this.kind, {this.toward, this.right = false});
  final ScatterTipKind kind;

  /// Nachbarzahl, in deren Richtung es zieht ([ScatterTipKind.drift]).
  final int? toward;

  /// Seitliche Tendenz nach rechts (sonst links).
  final bool right;

  @override
  bool operator ==(Object other) => other is ScatterTip && other.kind == kind && other.toward == toward && other.right == right;

  @override
  int get hashCode => Object.hash(kind, toward, right);

  @override
  String toString() => 'ScatterTip(${kind.name}${toward == null ? '' : ' → $toward'})';
}

/// Höchstens so viele Tipps je Feld.
const int maxScatterTips = 2;

/// Tipps zu einem Feld, wichtigster zuerst (höchstens [maxScatterTips]).
///
/// Die Regeln sind bewusst einfach und als Hinweise formuliert: Eine
/// Abweichung allein sagt nicht sicher, woran es liegt.
List<ScatterTip> scatterTips(ScatterShape s) {
  final frame = FieldFrame.of(s.field);
  final thr = s.threshold;
  final sigma = s.sigma;
  if (sigma <= ScatterRules.tightMm) {
    return [ScatterTip(s.centered ? ScatterTipKind.steady : ScatterTipKind.shiftAim)];
  }
  final tips = <ScatterTip>[];
  if (sigma >= ScatterRules.wideMm) tips.add(const ScatterTip(ScatterTipKind.wideOverall));

  // Abweichung: die größere Komponente zuerst.
  final offsets = <(double, ScatterTip)>[
    if (s.offsetR.abs() >= thr)
      (
        s.offsetR.abs(),
        ScatterTip(frame.upper
            ? (s.offsetR < 0 ? ScatterTipKind.tooFlat : ScatterTipKind.tooSteep)
            : (s.offsetR < 0 ? ScatterTipKind.inside : ScatterTipKind.outside)),
      ),
    if (s.offsetT.abs() >= thr)
      (
        s.offsetT.abs(),
        ScatterTip(ScatterTipKind.drift, toward: neighbourOf(s.field, right: s.offsetT > 0), right: s.offsetT > 0),
      ),
  ]..sort((a, b) => b.$1.compareTo(a.$1));
  tips.addAll(offsets.map((o) => o.$2));

  // Form der Streuung, übersetzt in die Achsen der Scheibe.
  final horizontal = frame.tangentialIsHorizontal ? s.sdT : s.sdR;
  final vertical = frame.tangentialIsHorizontal ? s.sdR : s.sdT;
  if (horizontal >= ScatterRules.shapeRatio * vertical) {
    tips.add(const ScatterTip(ScatterTipKind.wideSideways));
  } else if (vertical >= ScatterRules.shapeRatio * horizontal) {
    tips.add(const ScatterTip(ScatterTipKind.wideHeight));
  }
  if (tips.isEmpty) tips.add(const ScatterTip(ScatterTipKind.tighten));
  return tips.take(maxScatterTips).toList();
}

/// 1-Sigma-Ellipse in Board-Koordinaten: Halbachsen (normiert) und Winkel der
/// großen Achse (Radiant, gegen den Uhrzeigersinn ab +x, y nach oben).
typedef ScatterEllipse = ({double major, double minor, double angle});

/// Auswertung eines Zielfelds.
class FieldScatter {
  FieldScatter._({
    required this.field,
    required this.darts,
    required this.exactDarts,
    required this.hits,
    required this.mean,
    required this.cxx,
    required this.cyy,
    required this.cxy,
    required this.points,
  });

  /// Wertet die Darts eines Felds aus (mindestens zwei).
  factory FieldScatter.of(Segment field, List<ScatterDart> darts) {
    final n = darts.length;
    var sx = 0.0, sy = 0.0;
    var hits = 0, exact = 0;
    for (final d in darts) {
      sx += d.position.x;
      sy += d.position.y;
      if (d.hit) hits++;
      if (d.exact) exact++;
    }
    final mx = sx / n, my = sy / n;
    var xx = 0.0, yy = 0.0, xy = 0.0;
    for (final d in darts) {
      final dx = d.position.x - mx, dy = d.position.y - my;
      xx += dx * dx;
      yy += dy * dy;
      xy += dx * dy;
    }
    final div = n > 1 ? n - 1 : 1;
    return FieldScatter._(
      field: field,
      darts: n,
      exactDarts: exact,
      hits: HitCount(n, hits),
      mean: BoardPoint(mx, my),
      cxx: xx / div,
      cyy: yy / div,
      cxy: xy / div,
      points: darts,
    );
  }

  final Segment field;
  final int darts;

  /// Davon mit angezeigtem Ziel.
  final int exactDarts;
  final HitCount hits;

  /// Mittlere Position (Board-Koordinaten).
  final BoardPoint mean;

  /// Kovarianz der Positionen (Board-Koordinaten, normiert²).
  final double cxx, cyy, cxy;

  /// Die ausgewerteten Darts.
  final List<ScatterDart> points;

  /// Alle Darts mit angezeigtem Ziel; sonst „geschätzt“.
  bool get exact => exactDarts == darts;

  BoardPoint get center => BoardGeometry.centerOf(field);
  FieldFrame get frame => FieldFrame.of(field);

  /// Mittlere Abweichung in mm: rechts (+) / links (−), hoch (+) / tief (−).
  ({double t, double r}) get offset {
    final c = center;
    final o = frame.decompose(BoardPoint(mean.x - c.x, mean.y - c.y));
    return (t: _mm(o.t), r: _mm(o.r));
  }

  double _variance(BoardPoint u) => u.x * u.x * cxx + 2 * u.x * u.y * cxy + u.y * u.y * cyy;

  /// Standardabweichung seitlich (rechts/links) und in der Höhe, in mm.
  double get sdT => _mm(math.sqrt(math.max(0, _variance(frame.tangential))));
  double get sdR => _mm(math.sqrt(math.max(0, _variance(frame.radial))));

  ScatterShape get shape {
    final o = offset;
    return ScatterShape(field: field, offsetT: o.t, offsetR: o.r, sdT: sdT, sdR: sdR, darts: darts);
  }

  ScatterDirection get direction => shape.direction;
  List<ScatterTip> get tips => scatterTips(shape);

  /// 1-Sigma-Ellipse (enthält bei Normalverteilung etwa 39 % der Darts).
  ScatterEllipse get ellipse {
    final a = cxx, b = cxy, c = cyy;
    final mid = (a + c) / 2;
    final diff = math.sqrt(((a - c) / 2) * ((a - c) / 2) + b * b);
    return (
      major: math.sqrt(math.max(0, mid + diff)),
      minor: math.sqrt(math.max(0, mid - diff)),
      angle: 0.5 * math.atan2(2 * b, a - c),
    );
  }
}

/// Tendenz über alle ausgewerteten Felder (Feld-Achsen, nach Darts gewichtet).
class ScatterOverall {
  const ScatterOverall({required this.darts, required this.offsetT, required this.offsetR, required this.sigma});
  final int darts;
  final double offsetT;
  final double offsetR;

  /// Streuung je Achse (quadratisch gemittelt), mm.
  final double sigma;

  double get offset => math.sqrt(offsetT * offsetT + offsetR * offsetR);
  double get threshold => scatterThreshold(sigma, darts);
  ScatterDirection get direction => ScatterDirection.of(offsetT, offsetR, threshold);
}

/// Streuungs-Analyse eines Zeitraums.
class ScatterReport {
  ScatterReport._({required this.fields, required this.pending, required this.positioned, required this.overall});

  /// Fasst [darts] je Feld zusammen. Reichen die Darts mit angezeigtem Ziel
  /// für ein Feld ([ScatterRules.minDarts]), zählen nur sie; sonst alle
  /// (das Feld gilt dann als geschätzt). [positioned]: Darts mit Position im
  /// Zeitraum (auch ohne Zielfeld).
  factory ScatterReport.build(Iterable<ScatterDart> darts, {int positioned = 0, int minDarts = ScatterRules.minDarts}) {
    final byField = <Segment, List<ScatterDart>>{};
    for (final d in darts) {
      byField.putIfAbsent(d.field, () => []).add(d);
    }
    final fields = <FieldScatter>[];
    final pending = <({Segment field, int darts})>[];
    for (final e in byField.entries) {
      final exact = [for (final d in e.value) if (d.exact) d];
      final use = exact.length >= minDarts ? exact : e.value;
      if (use.length >= minDarts) {
        fields.add(FieldScatter.of(e.key, use));
      } else {
        pending.add((field: e.key, darts: use.length));
      }
    }
    fields.sort((a, b) => b.darts.compareTo(a.darts));
    pending.sort((a, b) => b.darts.compareTo(a.darts));
    ScatterOverall? overall;
    if (fields.isNotEmpty) {
      var n = 0;
      var t = 0.0, r = 0.0, v = 0.0;
      for (final f in fields) {
        final o = f.offset;
        n += f.darts;
        t += o.t * f.darts;
        r += o.r * f.darts;
        final s = f.shape.sigma;
        v += s * s * f.darts;
      }
      overall = ScatterOverall(darts: n, offsetT: t / n, offsetR: r / n, sigma: math.sqrt(v / n));
    }
    return ScatterReport._(fields: fields, pending: pending, positioned: positioned, overall: overall);
  }

  /// Felder mit genug Darts, meiste Darts zuerst.
  final List<FieldScatter> fields;

  /// Felder mit zu wenig Darts, meiste zuerst.
  final List<({Segment field, int darts})> pending;

  /// Darts mit Position (Autodarts, Simulator) im Zeitraum.
  final int positioned;
  final ScatterOverall? overall;

  bool get isEmpty => fields.isEmpty;

  /// Darts, die einem Feld zugeordnet wurden (auch in [pending]).
  int get assigned => fields.fold(0, (a, f) => a + f.darts) + pending.fold(0, (a, p) => a + p.darts);

  FieldScatter? operator [](Segment field) {
    for (final f in fields) {
      if (f.field == field) return f;
    }
    return null;
  }
}

/// Welche Sessions die Streuungs-Analyse betrachtet.
enum ScatterScope { all, training, match }
