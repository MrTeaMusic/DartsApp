import 'dart:convert';
import 'dart:io';

import 'package:dartlab/features/dart_source/data/raw_message_log.dart';
import 'package:dartlab/features/dart_source/domain/dart_source.dart';
import 'package:flutter_test/flutter_test.dart';

RawMessage msg(int i) => RawMessage(timestamp: DateTime(2026, 10, 11, 12, 0, i), channel: 'ws', payload: '{"i":$i}');

void main() {
  test('Ringpuffer behält nur die neuesten Einträge', () {
    final log = RawMessageLog(capacity: 3);
    for (var i = 0; i < 5; i++) {
      log.add(msg(i));
    }
    expect(log.entries.map((m) => m.payload), ['{"i":2}', '{"i":3}', '{"i":4}']);
    final lines = log.exportJsonLines().split('\n');
    expect(lines, hasLength(3));
    expect(jsonDecode(lines.first), containsPair('channel', 'ws'));
    log.clear();
    expect(log.entries, isEmpty);
  });

  test('Mitschrift in Datei als JSON Lines', () async {
    final dir = await Directory.systemTemp.createTemp('dartlab_log');
    final log = RawMessageLog();
    final file = await log.startFileLog(dir, now: DateTime(2026, 10, 11, 9, 5, 7));
    expect(file.path, endsWith('autodarts-20261011-090507.jsonl'));
    log.add(msg(1));
    log.add(msg(2));
    await log.stopFileLog();
    final lines = await file.readAsLines();
    expect(lines, hasLength(2));
    expect(jsonDecode(lines[1]), containsPair('payload', '{"i":2}'));
    await dir.delete(recursive: true);
  });
}
