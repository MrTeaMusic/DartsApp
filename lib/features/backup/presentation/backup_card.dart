import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components/components.dart';
import '../../../core/l10n.dart';
import '../../profiles/presentation/active_player.dart';
import '../data/backup_files.dart';
import '../data/backup_service.dart';

/// Export und Import in den Optionen.
class BackupCard extends ConsumerStatefulWidget {
  const BackupCard({super.key});

  @override
  ConsumerState<BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends ConsumerState<BackupCard> {
  bool _busy = false;

  String get _stamp {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)}';
  }

  /// Neue Meldung ersetzt die alte, statt sich hinten anzustellen.
  void _show(ScaffoldMessengerState messenger, String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(Future<String?> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      final message = await action();
      if (message != null) _show(messenger, message);
    } on BackupFormatException catch (e) {
      _show(messenger, l10n.backupInvalid(e.message));
    } on Exception catch (e) {
      _show(messenger, l10n.backupFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _export(String kind) async {
    final l10n = context.l10n;
    final service = ref.read(backupServiceProvider);
    final files = ref.read(backupFilesProvider);
    final (content, ext, mime) = switch (kind) {
      'json' => (await service.exportJson(), 'json', 'application/json'),
      'throws' => (await service.exportThrowsCsv(), 'csv', 'text/csv'),
      _ => (await service.exportSessionsCsv(), 'csv', 'text/csv'),
    };
    final name = switch (kind) {
      'json' => 'dartlab-backup-$_stamp.json',
      'throws' => 'dartlab-wuerfe-$_stamp.csv',
      _ => 'dartlab-sessions-$_stamp.csv',
    };
    final path = await files.save(name, content, mimeType: mime, extension: ext);
    return path == null ? null : l10n.backupSaved(path);
  }

  Future<String?> _import() async {
    final l10n = context.l10n;
    final text = await ref.read(backupFilesProvider).openJson();
    if (text == null) return null;
    final r = await ref.read(backupServiceProvider).importJson(text);
    ref.invalidate(playersProvider);
    return l10n.backupImported(r.sessions, r.throws, r.players, r.skipped);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            key: const Key('export-json'),
            enabled: !_busy,
            leading: const Icon(Icons.save_alt_rounded),
            title: Text(l10n.backupExportJson),
            subtitle: Text(l10n.backupExportJsonHint),
            onTap: () => _run(() => _export('json')),
          ),
          ListTile(
            key: const Key('export-throws'),
            enabled: !_busy,
            leading: const Icon(Icons.table_chart_rounded),
            title: Text(l10n.backupExportThrows),
            subtitle: Text(l10n.backupCsvHint),
            onTap: () => _run(() => _export('throws')),
          ),
          ListTile(
            key: const Key('export-sessions'),
            enabled: !_busy,
            leading: const Icon(Icons.view_list_rounded),
            title: Text(l10n.backupExportSessions),
            subtitle: Text(l10n.backupCsvHint),
            onTap: () => _run(() => _export('sessions')),
          ),
          ListTile(
            key: const Key('import-json'),
            enabled: !_busy,
            leading: const Icon(Icons.upload_file_rounded),
            title: Text(l10n.backupImport),
            subtitle: Text(l10n.backupImportHint),
            onTap: () => _run(_import),
          ),
        ],
      ),
    );
  }
}
