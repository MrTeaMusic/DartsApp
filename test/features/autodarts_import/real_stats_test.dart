import 'dart:convert';
import 'dart:io';

import 'package:dartlab/features/autodarts_import/domain/autodarts_match_mapping.dart';
import 'package:dartlab/features/autodarts_import/domain/import_plan.dart';
import 'package:flutter_test/flutter_test.dart';

// Nur lokal: DARTLAB_REAL_STATS=<Pfad zu einer echten /stats-Antwort>
// DARTLAB_REAL_ME=<eigener Autodarts-Name> (nur als Umgebungsvariable, nie im Code). Ohne die Variablen wird der Test
// übersprungen. Die echte Datei gehört NICHT ins Repository; es werden keine
// Namen ausgegeben.
void main() {
  final path = Platform.environment['DARTLAB_REAL_STATS'];
  final me = Platform.environment['DARTLAB_REAL_ME'] ?? '';
  test('echte /stats-Antwort lässt sich importieren und stimmt mit matchStats überein', () {
    final raw = jsonDecode(File(path!).readAsStringSync()) as Map<String, Object?>;
    final m = parseAutodartsMatch(raw);
    final idx = identifyMe(m, me);
    // ignore: avoid_print
    print('players=${m.players.length} legs=${m.legs.length} finished=${m.finished} warnings=${m.warnings} me=$idx '
        'out=${m.outMode} start=${m.startScore} id==${m.id == raw['id']}');
    expect(idx, isNotNull);
    final plan = buildImportPlan(m, me: idx!, now: DateTime.utc(2026, 10, 23));
    final stats = (raw['matchStats']! as List).cast<Map<String, Object?>>();
    final players = (raw['players']! as List).cast<Map<String, Object?>>();
    for (final (i, p) in players.indexed) {
      final s = stats.firstWhere((x) => x['playerId'] == p['id']);
      final darts = m.legs.expand((l) => l.turns).where((t) => t.player == i).fold<int>(0, (a, t) => a + t.darts.length);
      // ignore: avoid_print
      print('player $i: darts=$darts stats.dartsThrown=${s['dartsThrown']} avg=${s['average']}');
      expect(darts, s['dartsThrown']);
    }
    // ignore: avoid_print
    print('plan: ${plan.legsMe}:${plan.legsOpponent} won=${plan.won} visits=${plan.ownVisits} darts=${plan.darts.length} '
        'positions=${plan.darts.where((d) => d.position != null).length} warnings=${plan.warnings} '
        'metrics=${plan.result.metrics}');
    expect(plan.warnings, isEmpty);
    expect(plan.darts, isNotEmpty);
    final radii = [for (final d in plan.darts) if (d.segment.isDouble && d.position != null) d.position!.distance]..sort();
    // ignore: avoid_print
    print('double radii median=${radii.isEmpty ? null : radii[radii.length ~/ 2]} n=${radii.length}');
  }, skip: path == null ? 'DARTLAB_REAL_STATS nicht gesetzt' : false);
}
