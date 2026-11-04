import 'dart:io';

import 'package:dartlab/features/history/data/history_repository.dart';
import 'package:dartlab/features/history/domain/leg_board.dart';
import 'package:dartlab/features/history/domain/session_history.dart';
import 'package:dartlab/features/history/export/session_pdf.dart';
import 'package:dartlab/l10n/gen/app_localizations_de.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../helpers/history_seed.dart';
import '../../helpers/leg_seed.dart';
import '../../helpers/sync_device.dart';

Future<pw.Font> _font(String name) async => pw.Font.ttf(ByteData.sublistView(await File('assets/fonts/$name').readAsBytes()));

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late Device a;
  setUp(() => a = Device());
  tearDown(() => a.db.close());

  Future<SessionDetail> detail(int id) async {
    final row = (await HistoryRepository(a.db).session(id))!;
    return buildSessionDetail(row, await a.games.throwsOf(id), playerName: 'Ben');
  }

  /// Baut das PDF; mit `PDF_OUT_DIR=/pfad` schreibt der Test sie dorthin.
  Future<List<int>> build(SessionDetail d, String name) async {
    final bytes = await SessionPdf.build(
      SessionPdfInput(l10n: AppLocalizationsDe(), detail: d, boards: legBoardsOf(d), createdAt: DateTime(2026, 11, 4), eloLine: '1500 → 1512 (+12)'),
      regular: await _font('Inter-Regular.ttf'),
      bold: await _font('Inter-Bold.ttf'),
    );
    final dir = Platform.environment['PDF_OUT_DIR'];
    if (dir != null) File('$dir/$name.pdf').writeAsBytesSync(bytes);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    return bytes;
  }

  test('Match mit zwei Spielern und mehreren Legs', () async {
    final id = await seedHandMadeMatch(a.games, await a.me(), DateTime(2026, 10, 1, 19));
    final bytes = await build(await detail(id), 'match');
    expect(bytes.length, greaterThan(4000));
  });

  test('Match ohne gespeicherte Gegnerwürfe (nur eigene Seite)', () async {
    final id = await seedHandMadeMatch(a.games, await a.me(), DateTime(2026, 10, 1, 19), withOpponent: false);
    await build(await detail(id), 'match-solo');
  });

  test('Training: X01, Cricket und abgebrochene Session', () async {
    final s = await seedHistory(a.games, await a.me(), DateTime(2026, 10, 20, 20));
    await build(await detail(s.x01), 'x01');
    await build(await detail(s.cricket), 'cricket');
    await build(await detail(s.aborted), 'aborted');
  });
}
