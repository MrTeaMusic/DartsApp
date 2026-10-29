
import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/games/data/game_repository.dart';
import 'package:dartlab/features/profiles/data/profile_repository.dart';
import 'package:dartlab/features/stats/data/stats_repository.dart';
import 'package:dartlab/features/stats/domain/stats_calculator.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/elo_seed.dart';
import '../../helpers/history_seed.dart';

/// Haus-Elo über den echten Lade-Weg (`CalculatorLoader`, Provider): ein
/// neuer Rechner nach jeder Änderung an den Sessions, Neuberechnung nach
/// Löschen und Nachimport, keine Speicherung.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late AppDatabase db;
  late int me;
  late GameRepository games;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    me = await ProfileRepository(db).resolve(null);
    games = GameRepository(db);
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      appDatabaseProvider.overrideWithValue(db),
    ]);
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 400 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(done(), isTrue);
  }

  test('der Provider liefert das Haus-Elo und rechnet nach Löschen und Nachimport neu', () async {
    final now = DateTime.now();
    final sub = container.listen(houseEloProvider, (_, _) {});
    addTearDown(sub.close);
    // Der Rechner lädt zuerst: bis dahin gibt es noch keinen Bericht.
    expect(container.read(houseEloProvider), isNull);
    await until(() => container.read(houseEloProvider) != null);
    expect(container.read(houseEloProvider)!.isEmpty, isTrue);

    final ids = await seedEloHistory(games, me, now);
    // Training und ein abgebrochenes Match dazwischen zählen nicht.
    await seedTraining(games, me, 'x01', const {'startScore': 501, 'legs': 1}, now.subtract(const Duration(days: 2)), seed: 3);
    await seedEloMatch(games, me, now.subtract(const Duration(days: 1)), EloKind.bot, finished: false);
    await until(() => container.read(houseEloProvider)!.matches == 25);
    final full = container.read(houseEloProvider)!;
    expect(full.matches, 25);
    expect(full.hasHistory, isTrue);
    expect(full.wins + full.losses, 25);

    // Löschen (mit Markierung, wie in der App): der Verlauf rechnet ohne.
    await games.deleteSession(ids[5]);
    await until(() => container.read(houseEloProvider)!.matches == 24);
    final without = container.read(houseEloProvider)!;
    expect(without.steps.map((s) => s.sessionId), isNot(contains(ids[5])));
    expect(without.current, isNot(closeTo(full.current, 1e-6)));

    // Nachimport desselben Matches an derselben Zeit: wieder 25 Matches.
    await seedEloMatch(games, me, now.subtract(const Duration(days: 44)).copyWith(hour: 20, minute: 15), EloKind.bot,
        opponent: 'CPU 55', botAverage: 55, opponentAverage: 55, won: true, myAverage: 52, legsWon: 3, legsLost: 2);
    await until(() => container.read(houseEloProvider)!.matches == 25);
    expect(container.read(houseEloProvider)!.current, closeTo(full.current, 1e-9));
  });

  test('der Rechner liefert den Bericht auch ohne Provider; ein Lauf je Rechner', () async {
    await seedEloHistory(games, me, DateTime.now());
    final calcs = <StatsCalculator>[];
    final sub = StatsRepository(db).watchCalculator(me).listen(calcs.add);
    addTearDown(sub.cancel);
    await until(() => calcs.isNotEmpty);
    final calc = calcs.last;
    expect(calc.houseElo.matches, 25);
    expect(identical(calc.houseElo, calc.houseElo), isTrue);
    // Ein anderes Profil sieht nichts davon (der Rechner gehört zum Profil).
    final other = await ProfileRepository(db).create('Anna');
    final others = <StatsCalculator>[];
    final sub2 = StatsRepository(db).watchCalculator(other).listen(others.add);
    addTearDown(sub2.cancel);
    await until(() => others.isNotEmpty);
    expect(others.last.houseElo.isEmpty, isTrue);
  });
}
