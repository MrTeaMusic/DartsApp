import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/l10n.dart';
import '../../backup/data/backup_files.dart';
import '../../games/data/game_repository.dart';
import '../../stats/data/stats_repository.dart';
import '../data/history_repository.dart';
import '../domain/session_history.dart';
import '../share/shared_match.dart';

/// Baut die Datei zum Weitergeben aus der gespeicherten Session.
Future<SharedMatch> buildSharedMatch(WidgetRef ref, SessionDetail detail) async {
  final row = detail.entry.session;
  final throws = await ref.read(gameRepositoryProvider).throwsOf(row.id);
  final player = await ref.read(historyRepositoryProvider).playerName(row.playerId);
  final step = ref.read(houseEloProvider)?.stepOf(row.id);
  return SharedMatch.fromSession(
    player: player,
    session: row,
    throws: throws,
    elo: step == null ? null : SharedElo(before: step.before, after: step.after),
  );
}

/// Gibt die Session als `.dartlab`-Datei weiter: auf iPhone, iPad und Android
/// über das Teilen-Menü (WhatsApp, Mail, AirDrop …), am PC und Mac über den
/// Speichern-Dialog. [origin] ist der Knopf, an dem das Teilen-Menü auf dem
/// iPad hängt.
Future<void> shareSessionFile(BuildContext context, WidgetRef ref, SessionDetail detail, {Rect? origin}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  void show(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
  try {
    final match = await buildSharedMatch(ref, detail);
    final bytes = match.encode();
    final mobile = defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android;
    if (!mobile) {
      final path = await ref
          .read(backupFilesProvider)
          .saveBytes(match.fileName, bytes, mimeType: sharedMatchMimeType, extension: sharedMatchExtension);
      if (path != null) show(l10n.sharedMatchSaved(path));
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, match.fileName));
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: sharedMatchMimeType, name: match.fileName)],
      subject: l10n.sharedMatchShareSubject,
      sharePositionOrigin: origin,
    ));
  } on Exception catch (e) {
    show(l10n.backupFailed('$e'));
  }
}
