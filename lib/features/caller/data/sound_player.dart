import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Spielt eigene Sounddateien des Callers ab. In Tests ein Fake.
abstract interface class SoundPlayer {
  /// Spielt die Datei [path] mit Lautstärke [volume] (0–1). Das Future
  /// endet, wenn die Datei zu Ende ist. Gibt `false` zurück, wenn die
  /// Datei nicht abspielbar war (dann spricht die Stimme).
  Future<bool> play(String path, double volume);

  /// Bricht die laufende Wiedergabe ab.
  Future<void> stop();
}

/// Wiedergabe über das Paket `audioplayers` (AVPlayer auf macOS/iOS,
/// Media Foundation auf Windows).
class AudioplayersSoundPlayer implements SoundPlayer {
  AudioPlayer? _player;
  Completer<void>? _done;

  /// Längste Wartezeit pro Datei, falls das Ende nie gemeldet wird.
  static const _timeout = Duration(seconds: 8);

  AudioPlayer _ready() {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer(playerId: 'caller');
    player.setReleaseMode(ReleaseMode.stop);
    player.onPlayerComplete.listen((_) => _finish());
    return _player = player;
  }

  void _finish() {
    final done = _done;
    _done = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  @override
  Future<bool> play(String path, double volume) async {
    try {
      final player = _ready();
      _finish();
      final done = _done = Completer<void>();
      await player.setVolume(volume);
      await player.play(DeviceFileSource(path));
      await done.future.timeout(_timeout, onTimeout: () {});
      return true;
    } catch (e) {
      debugPrint('Caller: Sounddatei nicht abspielbar ($path): $e');
      _finish();
      return false;
    }
  }

  @override
  Future<void> stop() async {
    _finish();
    try {
      await _player?.stop();
    } catch (_) {}
  }
}

/// Spielt nichts ab (Tests, Plattformen ohne Audio).
class SilentSoundPlayer implements SoundPlayer {
  const SilentSoundPlayer();

  @override
  Future<bool> play(String path, double volume) async => false;

  @override
  Future<void> stop() async {}
}
