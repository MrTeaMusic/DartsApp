import 'package:dartlab/features/caller/data/sound_player.dart';

/// Schreibt mit, welche Sounddateien der Caller abspielen würde.
class FakeSoundPlayer implements SoundPlayer {
  final List<String> played = [];
  final List<double> volumes = [];

  /// Pfade, die „kaputt“ sind und `false` liefern.
  final Set<String> broken = {};
  int stops = 0;

  @override
  Future<bool> play(String path, double volume) async {
    if (broken.contains(path)) return false;
    played.add(path);
    volumes.add(volume);
    return true;
  }

  @override
  Future<void> stop() async => stops++;
}
