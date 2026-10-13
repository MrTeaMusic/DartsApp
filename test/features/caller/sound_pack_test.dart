import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dartlab/features/caller/caller.dart';
import 'package:dartlab/features/caller/data/sound_pack_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fake_sound_player.dart';
import '../../helpers/fake_speech_engine.dart';

/// So sieht Bens Beispielpaket aus: 0–180 als mp3, ohne 176, 178, 179.
CallerSoundPack bensPack() => CallerSoundPack.fromPaths([
      for (var s = 0; s <= 180; s++)
        if (![176, 178, 179].contains(s)) '/sounds/$s.mp3',
    ]);

void main() {
  group('CallerSoundPack', () {
    test('Dateinamen: Endung, Groß-/Kleinschreibung, Leerzeichen', () {
      expect(CallerSoundPack.keyFor('/x/180.mp3'), '180');
      expect(CallerSoundPack.keyFor('Game Shot-Leg.WAV'), 'game_shot_leg');
      expect(CallerSoundPack.keyFor('notes.txt'), isNull);
      expect(CallerSoundPack.keyFor('._180.mp3'), isNull);
    });

    test('Unmögliche Punkte zählen nicht als fehlend', () {
      expect(CallerSoundPack.impossibleScores, {163, 166, 169, 172, 173, 175, 176, 178, 179});
      final pack = bensPack();
      expect(pack.missingScores, isEmpty);
      expect(pack.missingExtras, ['bust', 'game_on', 'game_shot', 'you_require']);
      expect(CallerSoundPack.fromPaths(['/a/1.mp3']).missingScores, hasLength(171));
    });

    test('Rest: require_32 vor you_require + 32', () {
      final both = CallerSoundPack.fromPaths(['/s/require_32.mp3', '/s/you_require.mp3', '/s/32.mp3', '/s/40.mp3']);
      expect(both.pathsFor(const RequireCall(32)), ['/s/require_32.mp3']);
      expect(both.pathsFor(const RequireCall(40)), ['/s/you_require.mp3', '/s/40.mp3']);
      expect(bensPack().pathsFor(const RequireCall(40)), isNull);
    });

    test('Game shot: genaue Datei, sonst game_shot', () {
      final pack = CallerSoundPack.fromPaths(['/s/game_shot.mp3', '/s/game_shot_match.mp3']);
      expect(pack.pathsFor(const GameShotCall(GameShotKind.match)), ['/s/game_shot_match.mp3']);
      expect(pack.pathsFor(const GameShotCall(GameShotKind.leg)), ['/s/game_shot.mp3']);
    });
  });

  group('Caller mit eigenen Sounds', () {
    late FakeSpeechEngine engine;
    late FakeSoundPlayer player;
    late CallerSettings settings;
    late CallerSoundPack pack;
    late Caller caller;

    setUp(() {
      engine = FakeSpeechEngine();
      player = FakeSoundPlayer();
      settings = const CallerSettings(volume: 0.6);
      pack = bensPack();
      caller = Caller(engine: engine, settings: () => settings, player: player, soundPack: () => pack);
    });

    test('Punkte aus Dateien, fehlende Ansagen von der Stimme', () async {
      await caller.gameOn();
      await caller.visit(score: 140, remaining: 32);
      await caller.visit(bust: true);
      await caller.visit(score: 0);
      expect(player.played, ['/sounds/140.mp3', '/sounds/0.mp3']);
      expect(player.volumes, [0.6, 0.6]);
      expect(engine.spoken, ['Game on!', 'You require thirty-two', 'Bust']);
    });

    test('Ausgeschaltet: nur die Stimme', () async {
      settings = settings.copyWith(useSoundPack: false);
      await caller.visit(score: 180);
      expect(player.played, isEmpty);
      expect(engine.spoken, ['One hundred and eighty!']);
    });

    test('Nicht abspielbare Datei: Stimme springt ein', () async {
      player.broken.add('/sounds/60.mp3');
      await caller.visit(score: 60);
      expect(engine.spoken, ['Sixty']);
    });
  });

  group('SoundPackStore', () {
    late Directory tmp;
    late SoundPackStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('caller_sounds_test');
      store = SoundPackStore(baseDir: () async => Directory(p.join(tmp.path, 'app')));
    });

    tearDown(() => tmp.delete(recursive: true));

    test('Ordner importieren, ersetzen und entfernen', () async {
      final src = await Directory(p.join(tmp.path, 'src', 'unter')).create(recursive: true);
      await File(p.join(src.path, '180.MP3')).writeAsBytes([1, 2, 3]);
      await File(p.join(src.parent.path, 'Bust.wav')).writeAsBytes([4]);
      await File(p.join(src.parent.path, 'liesmich.txt')).writeAsString('x');

      final pack = await store.import([src.parent.path]);
      expect(pack!.files.keys.toSet(), {'180', 'bust'});
      expect(p.basename(pack.files['180']!), '180.mp3');
      expect(await File(pack.files['180']!).readAsBytes(), [1, 2, 3]);
      expect(await store.load(), pack);

      // Ohne Sounds bleibt das alte Paket.
      expect(await store.import([p.join(src.parent.path, 'liesmich.txt')]), isNull);
      expect((await store.load()).length, 2);

      await store.clear();
      expect((await store.load()).isEmpty, isTrue);
    });

    test('Zip importieren', () async {
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('Caller/60.mp3', [6, 0]))
        ..addFile(ArchiveFile.bytes('__MACOSX/Caller/._60.mp3', [9]))
        ..addFile(ArchiveFile.bytes('Caller/game_on.mp3', [1]));
      final zip = File(p.join(tmp.path, 'Caller.zip'));
      await zip.writeAsBytes(ZipEncoder().encode(archive));

      final pack = await store.import([zip.path]);
      expect(pack!.files.keys.toSet(), {'60', 'game_on'});
      expect(await File(pack.files['60']!).readAsBytes(), [6, 0]);
    });
  });
}
