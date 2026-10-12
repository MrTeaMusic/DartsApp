import 'package:flutter/material.dart';

import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../domain/tournament.dart';
import 'match_texts.dart';

/// Maße des Turnierbaums. Spiele späterer Runden sitzen mittig zwischen
/// ihren beiden Zubringern, rechts davon steht das Feld für den Sieger.
@immutable
class BracketGeometry {
  const BracketGeometry({
    required this.cardWidth,
    required this.cardHeight,
    required this.rowGap,
    required this.columnGap,
    required this.headerHeight,
    required this.championWidth,
    required this.championHeight,
    this.rounds = Tournament.roundCount,
  });

  /// Passende Maße für die verfügbare Breite: auf breiten Flächen füllt der
  /// Baum die Breite, auf dem Telefon wird er horizontal gescrollt.
  factory BracketGeometry.forWidth(double width) {
    final wide = width >= 900;
    final columnGap = wide ? 48.0 : 30.0;
    const rounds = Tournament.roundCount;
    // Breite = rounds Karten + Siegerfeld (0,85 Karten) + rounds Lücken.
    final card = ((width - rounds * columnGap) / (rounds + 0.85)).clamp(wide ? 180.0 : 172.0, 260.0);
    return BracketGeometry(
      cardWidth: card,
      cardHeight: wide ? 58 : 56,
      rowGap: wide ? 12 : 10,
      columnGap: columnGap,
      headerHeight: 52,
      championWidth: card * 0.85,
      championHeight: wide ? 104 : 96,
    );
  }

  final double cardWidth;
  final double cardHeight;

  /// Abstand zwischen zwei Spielen der ersten Runde.
  final double rowGap;

  /// Platz zwischen zwei Runden für die Verbindungslinien.
  final double columnGap;
  final double headerHeight;
  final double championWidth;
  final double championHeight;
  final int rounds;

  int get firstRoundMatches => 1 << (rounds - 1);

  /// Linke Kante einer Runde; `rounds` ist die Spalte des Siegerfelds.
  double x(int round) => round * (cardWidth + columnGap);

  /// Vertikale Mitte eines Spiels.
  double centerY(int round, int slot) {
    if (round == 0) return headerHeight + slot * (cardHeight + rowGap) + cardHeight / 2;
    return (centerY(round - 1, slot * 2) + centerY(round - 1, slot * 2 + 1)) / 2;
  }

  Rect matchRect(int round, int slot) => Rect.fromCenter(
    center: Offset(x(round) + cardWidth / 2, centerY(round, slot)),
    width: cardWidth,
    height: cardHeight,
  );

  Rect get championRect =>
      Rect.fromLTWH(x(rounds), centerY(rounds - 1, 0) - championHeight / 2, championWidth, championHeight);

  Size get size => Size(x(rounds) + championWidth, headerHeight + firstRoundMatches * (cardHeight + rowGap) - rowGap);
}

/// Der komplette Turnierbaum: Rundenköpfe, Spiele, Verbindungslinien und das
/// Siegerfeld. Feste Größe aus [geometry]; scrollen muss der Aufrufer.
class TournamentBracket extends StatelessWidget {
  const TournamentBracket({super.key, required this.tournament, required this.geometry});

  final Tournament tournament;
  final BracketGeometry geometry;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final g = geometry;
    final look = context.look;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final size = g.size;
    final current = t.currentRound;

    return Semantics(
      container: true,
      label: context.l10n.tourBracketLabel,
      child: SizedBox(
        key: const Key('tournament-bracket'),
        width: size.width,
        height: size.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                key: const Key('tournament-bracket-lines'),
                painter: BracketConnectorPainter(
                  tournament: t,
                  geometry: g,
                  style: BracketLineStyle.of(look, theme, colors),
                ),
              ),
            ),
            for (var r = 0; r <= t.rounds.length; r++)
              Positioned(
                left: g.x(r),
                top: 0,
                width: r < t.rounds.length ? g.cardWidth : g.championWidth,
                height: g.headerHeight - AppSpacing.s,
                child: _RoundHeader(tournament: t, round: r, current: r == current),
              ),
            for (var r = 0; r < t.rounds.length; r++)
              for (final m in t.rounds[r])
                Positioned.fromRect(
                  rect: g.matchRect(r, m.slot),
                  child: _BracketMatch(tournament: t, match: m),
                ),
            Positioned.fromRect(
              rect: g.championRect,
              child: _ChampionSlot(tournament: t),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundHeader extends StatelessWidget {
  const _RoundHeader({required this.tournament, required this.round, required this.current});
  final Tournament tournament;
  final int round;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final look = context.look;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final champion = round >= tournament.rounds.length;
    final title = champion ? l10n.tourChampionLabel : l10n.tourRoundName(round);
    final sub = champion ? null : l10n.tourBestOf(tournament.bestOf[round]);
    final titleStyle = look.sectionTitle.copyWith(
      color: look.header == HeaderTreatment.rule ? colors.textMuted : theme.colorScheme.onSurface,
      fontSize: look.id == DartLookId.clean ? 15 : null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Row(
          children: [
            if (look.header == HeaderTreatment.bar) ...[
              Container(width: 4, height: 16, color: current ? theme.colorScheme.primary : colors.textMuted),
              const SizedBox(width: AppSpacing.s),
            ],
            Expanded(
              child: Text(look.caps(title), maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle),
            ),
          ],
        ),
        // Leere Zeile beim Siegerfeld, damit alle Köpfe auf einer Linie stehen.
        ...[
          const SizedBox(height: AppSpacing.xxs),
          Padding(
            padding: EdgeInsets.only(left: look.header == HeaderTreatment.bar ? 4 + AppSpacing.s : 0),
            child: Text(
              look.caps(sub ?? ' '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: look.kicker.copyWith(
                fontSize: (look.kicker.fontSize ?? 12) - 1,
                color: current ? theme.colorScheme.primary : colors.textMuted,
              ),
            ),
          ),
        ],
        if (look.header == HeaderTreatment.rule) ...[
          const SizedBox(height: AppSpacing.xs),
          Container(height: 1, color: current ? theme.colorScheme.primary : theme.colorScheme.outline),
        ],
      ],
    );
  }
}

/// Ein Spiel im Baum: zwei Zeilen mit Namen und Legs, der Sieger fett.
class _BracketMatch extends StatelessWidget {
  const _BracketMatch({required this.tournament, required this.match});
  final Tournament tournament;
  final TournamentMatch match;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final look = context.look;
    final scheme = theme.colorScheme;
    final h = tournament.humanIndex;
    final mine = match.involves(h);
    final next = identical(match, tournament.humanMatch);
    final light = theme.brightness == Brightness.light;
    final tv = look.id == DartLookId.tv;
    final radius = BorderRadius.circular(look.radiusM);

    Widget line(int? entrant, int score) {
      final name = entrant == null ? l10n.tourTbd : tournament.entrants[entrant].name;
      final winner = match.played && match.winner == entrant;
      final loser = match.played && !winner;
      final human = entrant == h;
      final nameStyle = TextStyle(
        fontFamily: tv ? look.displayFamily : look.bodyFamily,
        fontSize: tv ? 17 : 13.5,
        height: 1.1,
        letterSpacing: tv ? 0.2 : -0.1,
        fontWeight: winner ? FontWeight.w800 : (human ? FontWeight.w700 : FontWeight.w500),
        color: entrant == null || loser
            ? colors.textMuted
            : human
            ? scheme.primary
            : scheme.onSurface,
      );
      // Leg-Feld rechts: Sieger invertiert wie eine TV-Bauchbinde.
      final boxColor = winner ? (human ? scheme.primary : scheme.onSurface) : colors.surfaceHigh;
      final scoreColor = winner ? (human ? scheme.onPrimary : scheme.surface) : colors.textMuted;
      return Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: AppSpacing.m - 2, right: AppSpacing.s),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: BracketName(
                    name,
                    upperCase: tv,
                    textKey: winner ? Key('tournament-winner-${match.id}') : null,
                    style: nameStyle,
                  ),
                ),
              ),
            ),
            Container(
              width: tv ? 30 : 32,
              alignment: Alignment.center,
              color: boxColor,
              child: match.played
                  ? Text(
                      '$score',
                      style: look.chipNumber.copyWith(fontSize: tv ? 19 : 14, color: scoreColor, height: 1),
                    )
                  : null,
            ),
          ],
        ),
      );
    }

    final borderColor = next
        ? scheme.primary
        : look.card == CardTreatment.outlined || (look.id == DartLookId.clean && !light)
        ? scheme.outline
        : light
        ? scheme.outline
        : Colors.transparent;

    return DecoratedBox(
      key: Key('tournament-match-${match.id}'),
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: look.card == CardTreatment.elevated && light ? look.shadow : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: borderColor, width: next ? 1.5 : 1),
          ),
          child: ColoredBox(
            color: scheme.surface,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Eigene Spiele mit Akzentkante.
                Container(width: 3, color: mine ? scheme.primary : Colors.transparent),
                Expanded(
                  child: Column(
                    children: [
                      line(match.a, match.scoreA),
                      Container(height: 1, color: light ? scheme.outline : colors.surfaceHigh),
                      line(match.b, match.scoreB),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kurzform eines Namens für enge Felder: „Michael van Gerwen“ wird zu
/// „M. van Gerwen“. Einteilige Namen bleiben, wie sie sind.
String shortPlayerName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length < 2 || parts.first.isEmpty) return name;
  return '${parts.first.characters.first}. ${parts.skip(1).join(' ')}';
}

/// Spielername in einem Feld fester Breite. Passt der volle Name nicht,
/// steht dort die Kurzform (der volle Name als Tooltip); reicht auch die
/// nicht, wird mit „…“ gekürzt.
class BracketName extends StatelessWidget {
  const BracketName(this.name, {super.key, required this.style, this.upperCase = false, this.textKey, this.textAlign});

  final String name;
  final TextStyle style;
  final bool upperCase;
  final Key? textKey;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        String shown(String s) => upperCase ? s.toUpperCase() : s;
        final full = shown(name);
        final painter = TextPainter(
          text: TextSpan(text: full, style: DefaultTextStyle.of(context).style.merge(style)),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final fits = painter.width <= c.maxWidth;
        painter.dispose();
        final text = Text(
          fits ? full : shown(shortPlayerName(name)),
          key: textKey,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: style,
        );
        return fits ? text : Tooltip(message: name, child: text);
      },
    );
  }
}

/// Feld rechts vom Finale: Pokal und Name des Siegers oder „offen“.
class _ChampionSlot extends StatelessWidget {
  const _ChampionSlot({required this.tournament});
  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.dartColors;
    final look = context.look;
    final light = theme.brightness == Brightness.light;
    final champion = tournament.champion;
    final human = champion != null && champion == tournament.humanIndex;
    final decided = champion != null;
    final radius = BorderRadius.circular(look.radiusL);
    final accent = human ? scheme.primary : colors.record;
    final name = decided ? tournament.entrants[champion].name : l10n.tourTbd;

    return DecoratedBox(
      key: const Key('tournament-champion-slot'),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: radius,
        boxShadow: look.card == CardTreatment.elevated && light ? look.shadow : null,
        border: Border.all(
          color: decided
              ? accent
              : (light || look.card == CardTreatment.outlined ? scheme.outline : colors.surfaceHigh),
          width: decided ? 2 : 1,
        ),
        gradient: decided
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accent.withValues(alpha: light ? 0.12 : 0.18),
                  scheme.surface,
                ],
              )
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.s),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.emoji_events_rounded,
              size: 34,
              color: decided ? accent : colors.textMuted.withValues(alpha: 0.6),
            ),
            const SizedBox(height: AppSpacing.s),
            BracketName(
              name,
              upperCase: look.id == DartLookId.tv,
              textKey: const Key('tournament-champion-name'),
              textAlign: TextAlign.center,
              style: look.sectionTitle.copyWith(
                fontSize: look.id == DartLookId.tv ? 22 : 16,
                letterSpacing: look.id == DartLookId.tv ? 0.6 : -0.2,
                fontWeight: FontWeight.w800,
                color: decided ? (human ? scheme.primary : scheme.onSurface) : colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Farben und Strichstärken der Verbindungslinien je Look.
@immutable
class BracketLineStyle {
  const BracketLineStyle({
    required this.open,
    required this.played,
    required this.human,
    required this.openWidth,
    required this.playedWidth,
    required this.humanWidth,
    required this.corner,
  });

  factory BracketLineStyle.of(DartLook look, ThemeData theme, DartColors colors) {
    final light = theme.brightness == Brightness.light;
    final base = switch (look.id) {
      DartLookId.tv => 2.0,
      DartLookId.clean => 1.5,
      DartLookId.lab => 1.0,
    };
    return BracketLineStyle(
      open: colors.textMuted.withValues(alpha: light ? 0.35 : 0.3),
      played: theme.colorScheme.onSurface.withValues(alpha: light ? 0.55 : 0.6),
      human: theme.colorScheme.primary,
      openWidth: base,
      playedWidth: base + 0.5,
      humanWidth: base + 1,
      corner: switch (look.id) {
        DartLookId.tv => 0,
        DartLookId.clean => 8,
        DartLookId.lab => 2,
      },
    );
  }

  final Color open;
  final Color played;
  final Color human;
  final double openWidth;
  final double playedWidth;
  final double humanWidth;

  /// Radius der Ecken, an denen eine Linie nach oben oder unten abbiegt.
  final double corner;
}

/// Stufen der Linien, in Zeichenreihenfolge: offen, gespielt, eigener Weg.
enum BracketLineTier { open, played, human }

/// Ein Linienzug des Baums mit seiner Stufe.
class BracketSegment {
  const BracketSegment(this.points, this.tier);
  final List<Offset> points;
  final BracketLineTier tier;
}

/// Zeichnet die Verbindungslinien: waagerecht aus jedem Spiel, senkrecht
/// zum Treffpunkt, waagerecht ins nächste Spiel. Der Weg des Menschen ist in
/// der Akzentfarbe, Siegerwege gespielter Spiele kräftiger als offene.
class BracketConnectorPainter extends CustomPainter {
  BracketConnectorPainter({required this.tournament, required this.geometry, required this.style});

  final Tournament tournament;
  final BracketGeometry geometry;
  final BracketLineStyle style;

  /// Alle Linienzüge, geordnet nach Stufe (offene zuerst).
  List<BracketSegment> segments() {
    final t = tournament;
    final g = geometry;
    final h = t.humanIndex;
    final out = <BracketSegment>[];
    BracketLineTier from(TournamentMatch m) => !m.played
        ? BracketLineTier.open
        : m.winner == h
        ? BracketLineTier.human
        : BracketLineTier.played;

    for (var r = 1; r < t.rounds.length; r++) {
      for (final target in t.rounds[r]) {
        final f0 = t.rounds[r - 1][target.slot * 2];
        final f1 = t.rounds[r - 1][target.slot * 2 + 1];
        final x0 = g.x(r - 1) + g.cardWidth;
        final xm = x0 + g.columnGap / 2;
        final xt = g.x(r);
        final yt = g.centerY(r, target.slot);
        out
          ..add(
            BracketSegment([
              Offset(x0, g.centerY(r - 1, f0.slot)),
              Offset(xm, g.centerY(r - 1, f0.slot)),
              Offset(xm, yt),
            ], from(f0)),
          )
          ..add(
            BracketSegment([
              Offset(x0, g.centerY(r - 1, f1.slot)),
              Offset(xm, g.centerY(r - 1, f1.slot)),
              Offset(xm, yt),
            ], from(f1)),
          )
          ..add(
            BracketSegment(
              [Offset(xm, yt), Offset(xt, yt)],
              target.involves(h)
                  ? BracketLineTier.human
                  : f0.played || f1.played
                  ? BracketLineTier.played
                  : BracketLineTier.open,
            ),
          );
      }
    }
    final last = t.rounds.length - 1;
    final yf = g.centerY(last, 0);
    out.add(BracketSegment([Offset(g.x(last) + g.cardWidth, yf), Offset(g.x(last + 1), yf)], from(t.finalMatch)));
    out.sort((a, b) => a.tier.index.compareTo(b.tier.index));
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in segments()) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.miter
        ..strokeCap = style.corner > 0 ? StrokeCap.round : StrokeCap.square
        ..color = switch (s.tier) {
          BracketLineTier.open => style.open,
          BracketLineTier.played => style.played,
          BracketLineTier.human => style.human,
        }
        ..strokeWidth = switch (s.tier) {
          BracketLineTier.open => style.openWidth,
          BracketLineTier.played => style.playedWidth,
          BracketLineTier.human => style.humanWidth,
        };
      canvas.drawPath(_path(s.points), paint);
    }
  }

  /// Linienzug mit abgerundeten Ecken (Radius aus dem Look).
  Path _path(List<Offset> p) {
    final path = Path()..moveTo(p.first.dx, p.first.dy);
    for (var i = 1; i < p.length; i++) {
      final corner = i < p.length - 1 ? p[i] : null;
      if (corner == null || style.corner <= 0) {
        path.lineTo(p[i].dx, p[i].dy);
        continue;
      }
      final inDir = corner - p[i - 1];
      final outDir = p[i + 1] - corner;
      final r = [style.corner, inDir.distance / 2, outDir.distance / 2].reduce((a, b) => a < b ? a : b);
      if (r <= 0.5) {
        path.lineTo(corner.dx, corner.dy);
        continue;
      }
      final a = corner - inDir / inDir.distance * r;
      final b = corner + outDir / outDir.distance * r;
      path
        ..lineTo(a.dx, a.dy)
        ..quadraticBezierTo(corner.dx, corner.dy, b.dx, b.dy);
    }
    return path;
  }

  // Das Turnier wird an Ort und Stelle geändert, daher immer neu zeichnen.
  @override
  bool shouldRepaint(BracketConnectorPainter oldDelegate) => true;
}
