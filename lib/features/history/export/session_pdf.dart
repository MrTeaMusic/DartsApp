/// PDF mit der ausführlichen Auswertung einer einzelnen Session, so wie die
/// Detailansicht sie zeigt: Kopf, Ergebnis beider Spieler, Doppel, jedes Leg
/// mit Verlauf und Aufnahmen-Tabelle, Punkte je Aufnahme und Wurfbild.
/// Reine Dart-Logik ohne Widgets, die Zahlen kommen fertig aus
/// [SessionDetail] und [LegBoards], die Texte aus [AppLocalizations].
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../l10n/gen/app_localizations.dart';
import '../../board/domain/board_geometry.dart';
import '../../games/domain/engine/game_display.dart';
import '../../games/presentation/game_texts.dart';
import '../../matches/domain/match_format.dart';
import '../domain/leg_board.dart';
import '../domain/session_history.dart';

/// Alles, was ins PDF kommt.
class SessionPdfInput {
  const SessionPdfInput({
    required this.l10n,
    required this.detail,
    required this.createdAt,
    this.boards,
    this.eloLine,
  });

  final AppLocalizations l10n;
  final SessionDetail detail;

  /// Legs mit beiden Spielern (X01-Match, -Training, Import), sonst `null`.
  final LegBoards? boards;

  /// „Haus-Elo 1500 → 1512 (+12)“, falls das Match gewertet wird.
  final String? eloLine;
  final DateTime createdAt;
}

abstract final class SessionPdf {
  static const _ink = PdfColor.fromInt(0xFF14161C);
  static const _muted = PdfColor.fromInt(0xFF6B7280);
  static const _line = PdfColor.fromInt(0xFFE5E7EB);
  static const _tint = PdfColor.fromInt(0xFFF3F4F6);
  static const _accent = PdfColor.fromInt(0xFF7C3AED);
  static const _teal = PdfColor.fromInt(0xFF0E9F8E);
  static const _good = PdfColor.fromInt(0xFF16A34A);
  static const _bad = PdfColor.fromInt(0xFFDC2626);
  static const _gold = PdfColor.fromInt(0xFFB45309);
  static const _goodTint = PdfColor.fromInt(0xFFDCFCE7);
  static const _badTint = PdfColor.fromInt(0xFFFEE2E2);
  static const _goldTint = PdfColor.fromInt(0xFFFEF3C7);

  static PdfColor _sideColor(int index) => index == 0 ? _accent : _teal;
  static String _date(DateTime d) => '${d.day}.${d.month}.${d.year}';
  static String _time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Baut das Dokument. [regular] und [bold] müssen Umlaute und „Ø“ können
  /// (die mitgelieferte Inter).
  static Future<Uint8List> build(SessionPdfInput input, {required pw.Font regular, required pw.Font bold}) {
    final l10n = input.l10n;
    final d = input.detail;
    final e = d.entry;
    final doc = pw.Document(
      title: _title(l10n, d),
      author: 'DartLab',
      theme: pw.ThemeData.withFont(base: regular, bold: bold, italic: regular, boldItalic: bold),
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 42),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('DartLab · ${_date(input.createdAt)}', style: const pw.TextStyle(fontSize: 8, color: _muted)),
            pw.Text(l10n.histPdfPage(ctx.pageNumber, ctx.pagesCount), style: const pw.TextStyle(fontSize: 8, color: _muted)),
          ],
        ),
        build: (ctx) => [
          _head(input),
          if (e.hasOpponent) ..._result(input) else ..._summary(input),
          if (input.boards case final boards?) ..._legs(input, boards) else ..._visits(input),
          ..._scoreChart(input),
          ..._heat(input),
        ],
      ),
    );
    return doc.save();
  }

  static String _title(AppLocalizations l10n, SessionDetail d) {
    final e = d.entry;
    return e.hasOpponent && e.opponents.isNotEmpty ? l10n.histVs(e.opponents.join(', ')) : l10n.gameTitle(e.gameId);
  }

  // -------------------------------------------------------------------------
  // Bausteine
  // -------------------------------------------------------------------------

  static pw.Widget _heading(String text, {String? trailing}) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 18, bottom: 8),
        child: pw.Row(children: [
          pw.Container(width: 3, height: 12, color: _accent),
          pw.SizedBox(width: 6),
          pw.Text(text, style: const pw.TextStyle(fontSize: 13, color: _ink)),
          if (trailing != null) ...[
            pw.SizedBox(width: 8),
            pw.Text(trailing, style: const pw.TextStyle(fontSize: 9, color: _muted)),
          ],
        ]),
      );

  static pw.Widget _note(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(text, style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
      );

  static pw.Widget _cell(String text, {bool right = false, bool bold = false, PdfColor color = _ink, double size = 9}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: pw.Text(
          text,
          textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
          style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color),
        ),
      );

  static const _rowBorder = pw.TableBorder(
    horizontalInside: pw.BorderSide(color: _line, width: 0.5),
    bottom: pw.BorderSide(color: _line, width: 0.5),
  );

  // -- Kopf ---------------------------------------------------------------------

  static pw.Widget _head(SessionPdfInput i) {
    final l10n = i.l10n;
    final d = i.detail;
    final e = d.entry;
    final minutes = e.duration?.inMinutes;
    final won = e.won;
    final status = e.hasOpponent && won != null
        ? (won ? l10n.histWon : l10n.histLost)
        : e.finished
            ? l10n.histFinished
            : l10n.histAborted;
    final format = e.hasOpponent ? MatchFormat.fromJson(e.details['format'] ?? e.config) : null;
    final me = d.players.isEmpty ? null : d.players[d.me].name;
    final facts = [
      status,
      if (e.tournament) l10n.histTournament,
      if (format != null)
        '${format.startScore} · ${format.usesSets ? l10n.matchFormatSets(format.setsToWin, format.legsToWin) : l10n.matchFormatLegs(format.legsToWin, format.bestOf)}',
      l10n.sessionAmount(e.gameId, e.darts, e.metrics),
      if (minutes != null) '${minutes < 1 ? 1 : minutes} min',
      if (me != null && me.isNotEmpty) me,
    ].join('   ·   ');
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: pw.BoxDecoration(color: _ink, borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '${_date(e.startedAt)} · ${_time(e.startedAt)}'.toUpperCase(),
            style: const pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFF9CA3AF), letterSpacing: 0.8),
          ),
          pw.SizedBox(height: 4),
          pw.Text(_title(l10n, d), style: const pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
          pw.SizedBox(height: 6),
          pw.Text(facts, style: const pw.TextStyle(fontSize: 9.5, color: PdfColor.fromInt(0xFFD1D5DB))),
        ],
      ),
    );
  }

  // -- Ergebnis (Match) -------------------------------------------------------

  static List<pw.Widget> _result(SessionPdfInput i) {
    final l10n = i.l10n;
    final d = i.detail;
    final e = d.entry;
    final players = d.players;
    final format = MatchFormat.fromJson(e.details['format'] ?? e.config);
    final sets = format.usesSets;
    final known = players.every((p) => p.stats.isNotEmpty);
    final String score = known && players.length > 1
        ? players.map((p) => '${(sets ? p.stats['sets'] : p.stats['legs'])?.round() ?? 0}').join(' : ')
        : '${e.legsWon} : ${e.legsLost}';
    String v(MatchPlayerResult p, String key, String Function(num) f) {
      final x = p.stats[key];
      return x == null ? '–' : f(x);
    }

    final rows = <(String, List<String>)>[
      if (sets) (l10n.matchStatSets, [for (final p in players) v(p, 'sets', (x) => '${x.round()}')]),
      (l10n.matchStatLegs, [for (final p in players) v(p, 'legs', (x) => '${x.round()}')]),
      (l10n.matchStatAverage, [for (final p in players) v(p, 'average', formatDecimal)]),
      (l10n.matchStatFirst9, [for (final p in players) v(p, 'first9', formatDecimal)]),
      (l10n.matchStatCheckout, [for (final p in players) v(p, 'checkoutRate', formatPercent)]),
      (l10n.matchStatHighFinish, [for (final p in players) v(p, 'highestFinish', (x) => x == 0 ? '–' : '${x.round()}')]),
      (l10n.matchStatBestLeg, [for (final p in players) v(p, 'bestLegDarts', (x) => '${x.round()}')]),
      (
        l10n.matchStatScores,
        [
          for (final p in players)
            p.stats.isEmpty
                ? '–'
                : '${v(p, 'count100', (x) => '${x.round()}')} / ${v(p, 'count140', (x) => '${x.round()}')} / ${v(p, 'count180', (x) => '${x.round()}')}',
        ],
      ),
      (l10n.matchStatDarts, [for (final p in players) v(p, 'darts', (x) => '${x.round()}')]),
    ];
    final won = e.won;
    final scoreColor = won == null ? _ink : (won ? _good : _bad);
    return [
      _heading(l10n.matchResultTitle),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Text(score, style: pw.TextStyle(fontSize: 34, fontWeight: pw.FontWeight.bold, color: scoreColor)),
        pw.SizedBox(width: 8),
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 5),
          child: pw.Text(sets ? l10n.matchSets : l10n.matchLegs, style: const pw.TextStyle(fontSize: 10, color: _muted)),
        ),
      ]),
      pw.SizedBox(height: 8),
      pw.Table(
        border: _rowBorder,
        columnWidths: {0: const pw.FlexColumnWidth(1.6), for (var k = 0; k < players.length; k++) k + 1: const pw.FlexColumnWidth(1)},
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _tint),
            children: [
              _cell(''),
              for (final (k, p) in players.indexed) _cell(p.name, right: true, bold: true, color: _sideColor(k == d.me ? 0 : 1)),
            ],
          ),
          for (final (label, values) in rows)
            pw.TableRow(children: [
              _cell(label, color: _muted, size: 8.5),
              for (final value in values) _cell(value, right: true, bold: true),
            ]),
        ],
      ),
      if (i.eloLine != null) ...[
        pw.SizedBox(height: 8),
        pw.Text('${l10n.eloHistoryLabel}: ${i.eloLine}', style: const pw.TextStyle(fontSize: 9.5, color: _ink)),
      ],
      if (!known) ...[
        pw.SizedBox(height: 6),
        _note(l10n.histOpponentsUnknown),
      ],
    ];
  }

  // -- Kennzahlen (Training) --------------------------------------------------

  static List<pw.Widget> _summary(SessionPdfInput i) {
    final l10n = i.l10n;
    final stats = i.detail.summary.take(8).toList();
    if (stats.isEmpty) return const [];
    return [
      _heading(l10n.histKeyMetrics),
      pw.Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in stats)
          pw.Container(
            width: 118,
            padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: pw.BoxDecoration(color: _tint, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(l10n.statLabel(s.key).toUpperCase(), style: const pw.TextStyle(fontSize: 7, color: _muted, letterSpacing: 0.6)),
              pw.SizedBox(height: 3),
              pw.Text(s.value, style: const pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _ink)),
            ]),
          ),
      ]),
    ];
  }

  // -- Legs ---------------------------------------------------------------------

  static List<pw.Widget> _legs(SessionPdfInput i, LegBoards boards) {
    final l10n = i.l10n;
    final d = i.detail;
    final legs = boards.legs;
    final out = <pw.Widget>[];
    if (boards.anyDoubles) {
      out
        ..add(_heading(l10n.histDoubles))
        ..add(_doublesSummary(l10n, boards))
        ..add(pw.SizedBox(height: 4))
        ..add(_note(l10n.histDoubleHint));
    }
    out.add(_heading(l10n.histLegs, trailing: legs.length > 1 ? l10n.histLegsCount(legs.length) : l10n.histVisitsCount(legs.first.sides.first.visits.length)));
    if (d.entry.isImported) {
      out.add(_note(l10n.impVisitsNote));
    } else if (d.entry.isMatch && !boards.hasOpponent) {
      out.add(_note(l10n.histLegNoOpponent));
    }
    for (final (k, board) in legs.indexed) {
      out
        ..add(pw.SizedBox(height: k == 0 ? 2 : 16))
        ..add(_legHead(i, board))
        ..add(_legTable(l10n, board));
    }
    out
      ..add(pw.SizedBox(height: 8))
      ..add(_legend(l10n, boards));
    return out;
  }

  static pw.Widget _doublesSummary(AppLocalizations l10n, LegBoards boards) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          for (final (k, p) in boards.players.indexed) ...[
            if (k > 0) pw.SizedBox(height: 8),
            () {
              final tally = boards.doublesOf(p.player);
              final rate = tally.total.rate;
              return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                if (p.name.isNotEmpty)
                  pw.Row(children: [
                    pw.Container(width: 8, height: 8, decoration: pw.BoxDecoration(color: _sideColor(k), shape: pw.BoxShape.circle)),
                    pw.SizedBox(width: 5),
                    pw.Text(p.name, style: const pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
                  ]),
                pw.SizedBox(height: 3),
                if (tally.isEmpty)
                  pw.Text(l10n.histDoubleNone, style: const pw.TextStyle(fontSize: 9, color: _muted))
                else ...[
                  pw.Text(
                    '${l10n.histDoubleRate(tally.hits, tally.attempts)}${rate == null ? '' : ' · ${formatPercent(rate)}'}',
                    style: const pw.TextStyle(fontSize: 9.5, color: _ink),
                  ),
                  if (tally.perDouble.isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    pw.Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: pw.WrapCrossAlignment.center, children: [
                      pw.Text(l10n.histDoubleThrownAt, style: const pw.TextStyle(fontSize: 8, color: _muted)),
                      for (final en in tally.ranked)
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: pw.BoxDecoration(color: en.value.hits > 0 ? _goodTint : _badTint, borderRadius: pw.BorderRadius.circular(8)),
                          child: pw.Text(
                            l10n.histDoubleChip(doubleName(en.key), en.value.hits, en.value.attempts),
                            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: en.value.hits > 0 ? _good : _bad),
                          ),
                        ),
                    ]),
                  ],
                ],
              ]);
            }(),
          ],
        ],
      );

  /// „Leg 2“ mit Sieger und Checkout, darunter der Verlauf des Rests.
  static pw.Widget _legHead(SessionPdfInput i, LegBoard board) {
    final l10n = i.l10n;
    final d = i.detail;
    final leg = board.leg;
    final format = d.entry.hasOpponent ? MatchFormat.fromJson(d.entry.details['format'] ?? d.entry.config) : null;
    final title = format != null && format.usesSets ? l10n.matchLegSetNumber(leg.set, leg.number) : l10n.matchLegNumber(leg.number);
    final w = leg.winner;
    final mine = w == null ? null : w == d.me || !d.entry.hasOpponent;
    final name = w == null || d.players.length <= w ? null : d.players[w].name;
    final String info;
    if (w == null) {
      info = l10n.histLegOpen;
    } else if (name != null && leg.checkout != null && leg.winnerDarts != null) {
      info = l10n.histLegWon(name, leg.checkout!, leg.winnerDarts!);
    } else {
      info = name ?? '';
    }
    final color = mine == null ? _muted : (mine ? _good : _bad);
    final named = board.sides.any((s) => s.name.isNotEmpty);
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      if (board.number > 0)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Row(children: [
            pw.Container(width: 4, height: 16, color: color),
            pw.SizedBox(width: 6),
            pw.Text(title, style: const pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _ink)),
            pw.SizedBox(width: 10),
            pw.Expanded(child: pw.Text(info, style: pw.TextStyle(fontSize: 9, color: color))),
          ]),
        ),
      if (board.rows > 0) _restChart(board, named),
      pw.SizedBox(height: 6),
    ]);
  }

  static pw.Widget _restChart(LegBoard board, bool named) {
    final rows = board.rows;
    final start = board.startScore;
    final step = start >= 301 ? 100 : 50;
    final top = ((start / step).ceil() * step).toDouble();
    final yTicks = <double>[for (var v = 0.0; v <= top + 1e-9; v += step) v];
    final every = (rows / 8).ceil().clamp(1, 1000);
    final xTicks = <double>[for (var k = 0; k <= rows; k += every) k.toDouble()];
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 4),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(6)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        if (named)
          pw.Row(children: [
            for (final (k, s) in board.sides.indexed) ...[
              pw.Container(width: 12, height: 3, color: _sideColor(k)),
              pw.SizedBox(width: 4),
              pw.Text(s.name, style: const pw.TextStyle(fontSize: 8, color: _ink)),
              pw.SizedBox(width: 12),
            ],
          ]),
        pw.SizedBox(height: 4),
        pw.SizedBox(
          height: 120,
          child: pw.Chart(
            grid: pw.CartesianGrid(
              xAxis: pw.FixedAxis(xTicks, format: (v) => '${v.toInt()}', textStyle: const pw.TextStyle(fontSize: 7, color: _muted), margin: 6),
              yAxis: pw.FixedAxis(
                yTicks,
                format: (v) => '${v.round()}',
                textStyle: const pw.TextStyle(fontSize: 7, color: _muted),
                divisions: true,
                divisionsDashed: true,
                margin: 6,
              ),
            ),
            datasets: [
              for (final (k, s) in board.sides.indexed)
                pw.LineDataSet(
                  data: [for (final (x, r) in s.rests.indexed) pw.PointChartValue(x.toDouble(), r.toDouble())],
                  color: _sideColor(k),
                  lineWidth: 1.6,
                  drawPoints: false,
                ),
            ],
          ),
        ),
      ]),
    );
  }

  /// Die Aufnahmen eines Legs: links die Nummer, je Spieler Punkte, Wurfbild
  /// und Rest danach. 100 und mehr sind getönt, der Checkout grün, ein Bust rot.
  static pw.Widget _legTable(AppLocalizations l10n, LegBoard board) {
    final sides = board.sides;
    final footer = sides.any((s) => !s.doubles.isEmpty);
    return pw.Table(
      columnWidths: {0: const pw.FixedColumnWidth(20), for (var k = 0; k < sides.length; k++) k + 1: const pw.FlexColumnWidth(1)},
      children: [
        pw.TableRow(children: [
          pw.SizedBox(),
          for (final (k, s) in sides.indexed)
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(2, 0, 2, 4),
              child: pw.Row(children: [
                pw.Container(width: 7, height: 7, decoration: pw.BoxDecoration(color: _sideColor(k), shape: pw.BoxShape.circle)),
                pw.SizedBox(width: 4),
                pw.Expanded(
                  child: pw.Text(
                    s.name.isEmpty ? l10n.histLegStart : s.name,
                    maxLines: 1,
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: board.leg.winner == s.player ? _good : _ink),
                  ),
                ),
                pw.Text('${s.startScore}', style: const pw.TextStyle(fontSize: 8, color: _muted)),
              ]),
            ),
        ]),
        for (var r = 0; r < board.rows; r++)
          pw.TableRow(
            verticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: [
              pw.Center(child: pw.Text('${r + 1}', style: const pw.TextStyle(fontSize: 8, color: _muted))),
              for (final s in sides)
                r < s.visits.length
                    ? _visitCell(
                        l10n,
                        s.visits[r],
                        s.rests[r + 1],
                        lastOfWinner: board.leg.winner == s.player && r == s.visits.length - 1 && s.finished,
                      )
                    : pw.SizedBox(),
            ],
          ),
        if (footer)
          pw.TableRow(children: [
            pw.SizedBox(),
            for (final s in sides)
              pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(3, 5, 3, 0),
                child: s.doubles.isEmpty
                    ? pw.SizedBox()
                    : pw.Text(l10n.histLegDoublesShort(s.doubles.hits, s.doubles.attempts), style: const pw.TextStyle(fontSize: 8, color: _muted)),
              ),
          ]),
      ],
    );
  }

  static pw.Widget _visitCell(AppLocalizations l10n, HistoryVisit v, int rest, {required bool lastOfWinner}) {
    final big = !v.bust && v.score >= 100;
    final PdfColor? tint = v.checkout ? _goodTint : (v.bust ? _badTint : (big ? _goldTint : null));
    final misses = <String, int>{};
    for (final m in missedDoublesOf(v)) {
      misses[m.label] = (misses[m.label] ?? 0) + 1;
    }
    final missText = misses.entries.map((m) => m.value > 1 ? '${m.key} ×${m.value}' : m.key).join(' ');
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1.5),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: pw.BoxDecoration(
        color: tint,
        borderRadius: pw.BorderRadius.circular(4),
        border: lastOfWinner ? pw.Border.all(color: _good, width: 0.8) : pw.Border.all(color: _line, width: 0.4),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Row(children: [
          pw.SizedBox(
            width: 30,
            child: pw.Text(
              v.bust ? l10n.histBust : '${v.score}',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: v.bust ? _bad : (big ? _gold : _ink)),
            ),
          ),
          pw.Expanded(
            child: missText.isEmpty
                ? pw.SizedBox()
                : pw.Text(missText, textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 7.5, color: _bad)),
          ),
          pw.SizedBox(width: 6),
          pw.Text(v.checkout ? '0' : '$rest', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: v.checkout ? _good : (v.bust ? _muted : _ink))),
        ]),
        pw.SizedBox(height: 1.5),
        _darts(v),
      ]),
    );
  }

  /// „T20 S20 S20“: verpasste Doppel rot, das Finish grün, nicht gezählte
  /// Darts durchgestrichen.
  static pw.Widget _darts(HistoryVisit v) => pw.RichText(
        text: pw.TextSpan(children: [
          for (final (k, dart) in v.darts.take(4).indexed) ...[
            if (k > 0) const pw.TextSpan(text: ' '),
            pw.TextSpan(
              text: dart.segment.name,
              style: !dart.counted
                  ? const pw.TextStyle(fontSize: 8, color: _muted, decoration: pw.TextDecoration.lineThrough)
                  : dart.finishAttempt
                      ? pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: dart.hit ? _good : _bad)
                      : const pw.TextStyle(fontSize: 8, color: _muted),
            ),
          ],
        ]),
      );

  static pw.Widget _legend(AppLocalizations l10n, LegBoards boards) {
    pw.Widget swatch(PdfColor c, String text) => pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
          pw.Container(width: 8, height: 8, decoration: pw.BoxDecoration(color: c, borderRadius: pw.BorderRadius.circular(2))),
          pw.SizedBox(width: 4),
          pw.Text(text, style: const pw.TextStyle(fontSize: 8, color: _muted)),
        ]);
    return pw.Wrap(spacing: 14, runSpacing: 4, children: [
      swatch(_goldTint, l10n.histLegendHundred),
      swatch(_goodTint, l10n.histLegendFinishHit),
      if (boards.anyDoubles) swatch(_badTint, l10n.histLegendDoubleMissed),
    ]);
  }

  // -- Aufnahmenliste ohne Rest (andere Spiele, ältere Matches) -------------------

  static List<pw.Widget> _visits(SessionPdfInput i) {
    final l10n = i.l10n;
    final d = i.detail;
    if (d.visits.isEmpty) return [_heading(l10n.histVisits), _note(l10n.histNoThrows)];
    final attempts = d.finishAttempts;
    final out = <pw.Widget>[
      _heading(l10n.histVisits, trailing: l10n.histVisitsCount(d.visits.length)),
      if (attempts > 0) _note(l10n.histFinishAttempts(d.finishHits, attempts)),
      if (d.entry.isImported)
        _note(l10n.impVisitsNote)
      else if (d.entry.isMatch)
        _note(d.legsKnown ? l10n.histOwnThrowsOnly : '${l10n.histOwnThrowsOnly} ${l10n.histLegsUnknown}'),
    ];
    for (final (k, leg) in d.legs.indexed) {
      out.add(pw.SizedBox(height: k == 0 ? 2 : 12));
      if (leg.number > 0 && d.legs.length > 1) {
        out.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Text(l10n.matchLegNumber(leg.number), style: const pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _ink)),
        ));
      }
      out.add(
        pw.Table(
          border: _rowBorder,
          columnWidths: const {0: pw.FixedColumnWidth(26), 1: pw.FlexColumnWidth(3), 2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(1)},
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _tint),
              children: [
                _cell('#', bold: true, color: _muted, size: 8),
                _cell('Darts', bold: true, color: _muted, size: 8),
                _cell(_valueLabel(l10n, d), right: true, bold: true, color: _muted, size: 8),
                _cell(d.afterKey == null ? '' : l10n.statLabel(d.afterKey!), right: true, bold: true, color: _muted, size: 8),
              ],
            ),
            for (final v in leg.visits)
              pw.TableRow(children: [
                _cell('${v.number}', color: _muted, size: 8),
                pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4), child: _darts(v)),
                _cell(v.bust ? l10n.histBust : '${v.valueOf(d.value)}', right: true, bold: true, color: v.bust ? _bad : (v.checkout ? _good : _ink)),
                _cell(v.after ?? '', right: true, color: _muted),
              ]),
          ],
        ),
      );
    }
    return out;
  }

  static String _valueLabel(AppLocalizations l10n, SessionDetail d) => switch (d.value) {
        VisitValue.points => l10n.statPoints,
        VisitValue.hits => l10n.statHitsOnTarget,
        VisitValue.marks => l10n.statsMetricMarks,
      };

  // -- Punkte je Aufnahme ----------------------------------------------------------

  static List<pw.Widget> _scoreChart(SessionPdfInput i) {
    final l10n = i.l10n;
    final d = i.detail;
    final values = d.chartValues;
    if (values.length < 2 || values.any((v) => v.isNaN)) return const [];
    final title = switch (d.chart) {
      VisitChart.score => l10n.histChartScore,
      VisitChart.total => l10n.histChartTotal,
      VisitChart.hits => l10n.histChartHits,
      VisitChart.marks => l10n.histChartMarks,
    };
    final top = values.reduce(math.max);
    final lowest = values.reduce(math.min);
    final step = top - math.min(0, lowest) > 120 ? 60.0 : (top > 12 ? 20.0 : 1.0);
    final yMin = (math.min(0, lowest) / step).floor() * step;
    final yMax = ((top <= 0 ? 1 : top) / step).ceil() * step;
    final yTicks = <double>[for (var v = yMin; v <= yMax + 1e-9; v += step) v];
    final every = (values.length / 10).ceil().clamp(1, 1000);
    // Eine Stelle Luft links und rechts, damit die äußeren Balken nicht am Rand abgeschnitten werden.
    final xTicks = <double>[-1, for (var k = 0; k < values.length; k += every) k.toDouble(), values.length.toDouble()];
    final average = d.chart == VisitChart.score ? d.visits.fold<int>(0, (a, v) => a + v.score) / d.visits.length : null;
    final line = d.chart == VisitChart.total;
    return [
      _heading(title, trailing: average == null ? null : l10n.histChartAverage(formatDecimal(average))),
      pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(10, 10, 10, 4),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(6)),
        height: 150,
        child: pw.Chart(
          grid: pw.CartesianGrid(
            xAxis: pw.FixedAxis(xTicks, format: (v) => v < 0 || v >= values.length ? '' : '${v.toInt() + 1}', textStyle: const pw.TextStyle(fontSize: 7, color: _muted), margin: 6),
            yAxis: pw.FixedAxis(
              yTicks,
              format: (v) => '${v.round()}',
              textStyle: const pw.TextStyle(fontSize: 7, color: _muted),
              divisions: true,
              divisionsDashed: true,
              margin: 6,
            ),
          ),
          datasets: [
            if (line)
              pw.LineDataSet(
                data: [for (final (k, v) in values.indexed) pw.PointChartValue(k.toDouble(), v)],
                color: _accent,
                lineWidth: 1.6,
                drawPoints: false,
              )
            else
              pw.BarDataSet(
                data: [for (final (k, v) in values.indexed) pw.PointChartValue(k.toDouble(), v)],
                color: _accent,
                width: math.max(2, math.min(14, 440 / values.length * 0.6)),
                drawBorder: false,
              ),
          ],
        ),
      ),
    ];
  }

  // -- Wurfbild --------------------------------------------------------------------

  static List<pw.Widget> _heat(SessionPdfInput i) {
    final points = i.detail.positions;
    if (points.isEmpty) return const [];
    const size = 220.0;
    return [
      _heading(i.l10n.statsHeatmap),
      pw.Center(
        child: pw.SizedBox(
          width: size,
          height: size,
          child: pw.CustomPaint(
            size: const PdfPoint(size, size),
            painter: (canvas, s) {
              const c = size / 2;
              const r = c - 4;
              canvas
                ..setStrokeColor(_line)
                ..setLineWidth(0.6);
              for (final ring in [
                BoardGeometry.doubleOuterR,
                BoardGeometry.doubleInnerR,
                BoardGeometry.tripleOuterR,
                BoardGeometry.tripleInnerR,
                BoardGeometry.outerBullR,
                BoardGeometry.innerBullR,
              ]) {
                canvas
                  ..drawEllipse(c, c, r * ring, r * ring)
                  ..strokePath();
              }
              for (var k = 0; k < 20; k++) {
                final a = (k * 18 + 9) * math.pi / 180;
                canvas
                  ..drawLine(c + r * BoardGeometry.outerBullR * math.sin(a), c + r * BoardGeometry.outerBullR * math.cos(a), c + r * math.sin(a), c + r * math.cos(a))
                  ..strokePath();
              }
              canvas.saveContext();
              canvas.setGraphicState(const PdfGraphicState(opacity: 0.55));
              canvas.setFillColor(_accent);
              for (final p in points) {
                canvas
                  ..drawEllipse(c + p.x * r, c + p.y * r, 2.2, 2.2)
                  ..fillPath();
              }
              canvas.restoreContext();
            },
          ),
        ),
      ),
    ];
  }
}
