import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import '../domain/dart_source.dart';

/// Ringpuffer für rohe Nachrichten, optional zusätzlich als JSON-Lines-Datei.
///
/// Die Datei ist dafür da, Mitschnitte vom echten Board zu sammeln, mit denen
/// das Mapping nachgeschärft werden kann.
class RawMessageLog {
  RawMessageLog({this.capacity = 2000});

  final int capacity;
  final _entries = ListQueue<RawMessage>();
  IOSink? _sink;
  File? _file;

  List<RawMessage> get entries => List.unmodifiable(_entries);
  File? get file => _file;

  void add(RawMessage message) {
    _entries.addLast(message);
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
    _sink?.writeln(jsonEncode(toJson(message)));
  }

  void clear() => _entries.clear();

  /// Startet die Mitschrift in eine neue Datei im Ordner [directory].
  Future<File> startFileLog(Directory directory, {DateTime? now}) async {
    await stopFileLog();
    final t = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name = 'autodarts-${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}.jsonl';
    await directory.create(recursive: true);
    final file = File('${directory.path}${Platform.pathSeparator}$name');
    _file = file;
    _sink = file.openWrite(mode: FileMode.append);
    return file;
  }

  Future<void> stopFileLog() async {
    final sink = _sink;
    _sink = null;
    if (sink != null) {
      await sink.flush();
      await sink.close();
    }
  }

  /// Alle Einträge als JSON Lines, z. B. zum Kopieren in die Zwischenablage.
  String exportJsonLines() => _entries.map((m) => jsonEncode(toJson(m))).join('\n');

  static Map<String, Object?> toJson(RawMessage m) => {
        'ts': m.timestamp.toIso8601String(),
        'dir': m.incoming ? 'in' : 'out',
        'channel': m.channel,
        'payload': m.payload,
      };
}
