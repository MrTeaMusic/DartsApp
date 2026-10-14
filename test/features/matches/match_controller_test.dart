import 'dart:math' as math;

import 'package:dartlab/core/database/app_database.dart';
import 'package:dartlab/core/settings/app_settings.dart';
import 'package:dartlab/features/dart_source/domain/dart_event.dart';
import 'package:dartlab/features/dart_source/domain/dart_source.dart';
import 'package:dartlab/features/dart_source/presentation/dart_source_providers.dart';
import 'package:dartlab/features/matches/data/match_store.dart';
import 'package:dartlab/features/matches/domain/match_format.dart';
import 'package:dartlab/features/matches/domain/match_result.dart';
import 'package:dartlab/features/matches/domain/match_session.dart';
import 'package:dartlab/features/caller/caller.dart';
import 'package:dartlab/features/matches/presentation/match_caller.dart';
import 'package:dartlab/features/matches/presentation/match_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/darts.dart';
import '../../helpers/fake_speech_engine.dart';

/// Quelle ohne eigenes Verhalten (wie Autodarts): Ereignisse kommen nur über
/// `handle`.
class _FakeBoard implements DartSource {
  @override
  DartSourceKind get kind => DartSourceKind.autodartsLocal;
  @override
  Stream<DartEvent> get events => const Stream.empty();
  @override
  Stream<SourceStatus> get statusChanges => const Stream.empty();
  @override
  SourceStatus get status => SourceStatus.ready;
  @override
  Stream<RawMessage> get rawMessages => const Stream.empty();
  @override
  bool get providesCoordinates => true;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  late ProviderContainer container;
  late AppDatabase db;
  late FakeSpeechEngine speech;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    db = AppDatabase(NativeDatabase.memory());
    speech = FakeSpeechEngine();
    container = ProviderContainer(
      overrides: [
        speechEngineProvider.overrideWithValue(speech),
        sharedPreferencesProvider.overrideWithValue(sp),
        appDatabaseProvider.overrideWithValue(db),
        dartSourceFactoryProvider.overrideWithValue((kind, host, port) => _FakeBoard()),
        botTimingProvider.overrideWithValue(
          const BotTiming(firstDart: Duration(hours: 1), betweenDarts: Duration(hours: 1), takeout: Duration(hours: 1)),
        ),
        botRandomProvider.overrideWithValue(math.Random(1)),
      ],
    );
    container.listen(matchControllerProvider, (_, _) {});
    container.listen(matchCallerProvider, (_, _) {});
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  MatchController controller() => container.read(matchControllerProvider.notifier);
  MatchState state() => container.read(matchControllerProvider)!;
  final at = DateTime(2026, 10, 11);

  const vsBot = MatchSetup(
    format: MatchFormat(startScore: 301, legsToWin: 1),
    players: [MatchPlayer.human('Ben', profileId: 1), MatchPlayer.bot('CPU', average: 50)],
  );

  test('Darts während der Bot-Aufnahme und nach voller Aufnahme zählen nicht für den Bot', () async {
    await controller().start(vsBot);
    for (final n in ['S20', 'S20', 'S20']) {
      controller().handle(DartThrown(d(n)));
    }
    expect(state().match.visitClosed, isTrue);
    expect(state().acceptsHumanDarts, isFalse);
    // Vergessener Takeout: der vierte Dart beendet nur die Aufnahme.
    controller().handle(DartThrown(d('T20')));
    expect(state().match.current, 1);
    expect(state().match.players[1].darts, 0);
    expect(state().match.players[0].remaining, 241);
    // Während der Bot dran ist, werden Darts und Takeouts ignoriert.
    controller().handle(DartThrown(d('T20')));
    controller().handle(TakeoutFinished(at));
    controller().handle(DartUndone(at));
    expect(state().match.players[1].darts, 0);
    expect(state().match.current, 1);
    expect(state().session.records, hasLength(3));
    await controller().pendingWrites;
  });

  test('Rückgängig und Korrektur der eigenen Darts werden gespeichert', () async {
    await controller().start(vsBot);
    controller().handle(DartThrown(d('T20')));
    controller().handle(DartThrown(d('S5')));
    controller().handle(DartUndone(at));
    expect(state().match.players[0].remaining, 241);
    controller().handle(DartCorrected(0, d('T19')));
    expect(state().match.players[0].remaining, 244);
    expect(controller().correct(0, d('S1').segment), isTrue);
    expect(state().match.players[0].remaining, 300);
    await controller().pendingWrites;
    final throws = await db.select(db.throws).get();
    expect(throws.map((t) => t.segment), ['S1']);
    expect(throws.single.gameId, matchGameId);
  });

  test('Caller: Game on, Aufnahme angesagt, still bei Rückgängig und Korrektur', () async {
    await controller().start(vsBot);
    await pumpEventQueue();
    expect(speech.spoken, ['Game on!']);
    controller().handle(DartThrown(d('T20')));
    controller().handle(DartThrown(d('S5')));
    controller().handle(DartUndone(at));
    controller().handle(DartCorrected(0, d('T19')));
    await pumpEventQueue();
    expect(speech.spoken, ['Game on!'], reason: 'nichts während der Aufnahme und bei Korrekturen');
    controller().handle(DartThrown(d('S5')));
    controller().handle(DartThrown(d('S5')));
    await pumpEventQueue();
    expect(speech.spoken, ['Game on!', const EnglishCallerPhrases().score(67).text]);
    // Korrektur nach der Aufnahme: neu gerechnet, aber nicht noch einmal angesagt.
    expect(controller().correct(0, d('S1').segment), isTrue);
    await pumpEventQueue();
    expect(speech.spoken, hasLength(2));
    await controller().pendingWrites;
  });

  test('Freund mit Profil: Würfe getrennt je Profil, Gast ohne Speicherung', () async {
    final friend = await db.into(db.players).insert(PlayersCompanion.insert(name: 'Tom', createdAt: at));
    await controller().start(
      MatchSetup(
        format: const MatchFormat(startScore: 101, legsToWin: 1),
        players: [
          const MatchPlayer.human('Ben', profileId: 1),
          MatchPlayer.human('Tom', profileId: friend),
        ],
      ),
    );
    for (final n in ['S20', 'S20', 'S20']) {
      controller().handle(DartThrown(d(n)));
    }
    controller().handle(TakeoutFinished(at));
    expect(state().match.current, 1);
    for (final n in ['T20', 'S9', 'D16']) {
      controller().handle(DartThrown(d(n)));
    }
    expect(state().ended, isTrue);
    expect(state().match.winner, 1);
    await controller().pendingWrites;
    final sessions = await db.select(db.sessions).get();
    expect(sessions, hasLength(2));
    expect({for (final s in sessions) s.playerId: s.dartCount}, {1: 3, friend: 3});
    expect(sessions.every((s) => s.finished), isTrue);
    expect(container.read(matchStoreProvider).currentMatch(), isNull);
  });

  test('Abbrechen speichert eine unvollständige Session, Fortsetzen ersetzt sie', () async {
    await controller().start(vsBot.copyWithTournament('t1/r0-m0'));
    controller().handle(DartThrown(d('T20')));
    await controller().close(keepForResume: true);
    await controller().pendingWrites;
    final saved = container.read(matchStoreProvider).currentMatch()!;
    expect(saved.inputs, hasLength(1));
    expect((await db.select(db.sessions).get()).single.finished, isFalse);

    await controller().start(saved.setup, resume: saved);
    expect(state().match.players[0].remaining, 241);
    await controller().pendingWrites;
    final sessions = await (db.select(db.sessions)..where((s) => s.deletedAt.isNull())).get();
    expect(sessions, hasLength(1), reason: 'alte Teil-Session ersetzt');
    expect(await (db.select(db.sessions)..where((s) => s.deletedAt.isNotNull())).get(), hasLength(1),
        reason: 'als gelöscht markiert, damit der Abgleich sie nicht zurückbringt');
    expect((await db.select(db.throws).get()).single.sessionId, sessions.single.id);
  });
}

extension on MatchSetup {
  MatchSetup copyWithTournament(String id) =>
      MatchSetup(format: format, players: players, firstStarter: firstStarter, tournamentMatch: id);
}
