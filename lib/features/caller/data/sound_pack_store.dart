import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/sound_pack.dart';

/// Ablage der eigenen Caller-Sounds im App-Ordner.
///
/// Beim Import werden die Dateien in den App-Ordner kopiert. So bleiben sie
/// nutzbar, auch wenn der Originalordner verschoben wird, und auf macOS/iOS
/// braucht die App keinen dauerhaften Zugriff auf fremde Ordner. Die Dateien
/// bleiben nur auf diesem Gerät.
class SoundPackStore {
  SoundPackStore({Future<Directory> Function()? baseDir}) : _baseDir = baseDir ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _baseDir;

  Future<Directory> _dir() async => Directory(p.join((await _baseDir()).path, 'caller_sounds'));

  /// Das aktuell importierte Paket (leer, wenn keins da ist).
  Future<CallerSoundPack> load() async {
    final dir = await _dir();
    if (!await dir.exists()) return CallerSoundPack.empty;
    final paths = [
      await for (final e in dir.list())
        if (e is File) e.path,
    ]..sort();
    return CallerSoundPack.fromPaths(paths);
  }

  /// Ersetzt das Paket durch die Sounds aus [sources]: Ordner (mit
  /// Unterordnern), einzelne Sounddateien oder Zip-Archive. Gibt das neue
  /// Paket zurück. Enthalten die Quellen keinen einzigen Sound, bleibt das
  /// alte Paket unverändert und das Ergebnis ist `null`.
  Future<CallerSoundPack?> import(List<String> sources) async {
    final collected = <String, ({String ext, List<int> Function() bytes})>{};
    void add(String name, List<int> Function() bytes) {
      final key = CallerSoundPack.keyFor(name);
      if (key == null || collected.containsKey(key)) return;
      collected[key] = (ext: p.extension(name).toLowerCase(), bytes: bytes);
    }

    Future<void> addFile(File f) async {
      if (p.extension(f.path).toLowerCase() == '.zip') {
        final archive = ZipDecoder().decodeBytes(await f.readAsBytes());
        for (final entry in archive.files) {
          if (!entry.isFile || entry.name.contains('__MACOSX')) continue;
          add(entry.name, () => entry.content);
        }
      } else {
        final bytes = await f.readAsBytes();
        add(f.path, () => bytes);
      }
    }

    for (final source in sources) {
      if (await FileSystemEntity.isDirectory(source)) {
        final files = [
          await for (final e in Directory(source).list(recursive: true))
            if (e is File) e,
        ]..sort((a, b) => a.path.compareTo(b.path));
        for (final f in files) {
          await addFile(f);
        }
      } else if (await FileSystemEntity.isFile(source)) {
        await addFile(File(source));
      }
    }
    if (collected.isEmpty) return null;

    final dir = await _dir();
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    for (final MapEntry(:key, value: sound) in collected.entries) {
      // Name normalisiert, Endung aus dem Original.
      await File(p.join(dir.path, '$key${sound.ext}')).writeAsBytes(sound.bytes());
    }
    return load();
  }

  /// Entfernt das Paket, danach spricht wieder die normale Stimme.
  Future<void> clear() async {
    final dir = await _dir();
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
