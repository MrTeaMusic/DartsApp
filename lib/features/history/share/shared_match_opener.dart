import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n.dart';
import '../../../core/router/app_router.dart';
import 'shared_match.dart';
import 'windows_file_type.dart';

/// Das gerade geöffnete geteilte Match. Lebt nur im Speicher: Nichts davon
/// landet in der Datenbank, im Abgleich oder in der Statistik.
final openedSharedMatchProvider = NotifierProvider<OpenedSharedMatch, SharedMatch?>(OpenedSharedMatch.new);

class OpenedSharedMatch extends Notifier<SharedMatch?> {
  @override
  SharedMatch? build() => null;
  void set(SharedMatch? m) => state = m;
}

/// Dateien, mit denen die App gestartet wurde (Doppelklick auf eine
/// `.dartlab`-Datei unter Windows/Linux). `main` setzt das.
final launchFilesProvider = Provider<List<String>>((ref) => const []);

/// Pfade aus den Startargumenten, die nach einer DartLab-Datei aussehen.
List<String> sharedMatchArgs(List<String> args) =>
    [for (final a in args) if (a.toLowerCase().endsWith('.$sharedMatchExtension')) a];

/// Öffnet Dateien, die das Betriebssystem an DartLab übergibt:
///
/// * Windows/Linux: Pfad in den Startargumenten ([launchFilesProvider]).
/// * macOS, iOS, Android: über den Kanal `de.dartlab/open_file`. Die native
///   Seite merkt sich Dateien, die vor dem Start von Flutter ankamen, und
///   gibt sie auf `ready` zurück; spätere kommen als `open`.
final sharedMatchOpenerProvider = Provider<SharedMatchOpener>((ref) {
  final opener = SharedMatchOpener(ref);
  opener.start();
  ref.onDispose(opener.dispose);
  return opener;
});

class SharedMatchOpener {
  SharedMatchOpener(this.ref);
  final Ref ref;

  static const channel = MethodChannel('de.dartlab/open_file');

  void start() {
    // Windows: Dateizuordnung für .dartlab eintragen (im Hintergrund).
    unawaited(registerWindowsFileType());
    for (final path in ref.read(launchFilesProvider)) {
      // Erst nach dem ersten Bild, damit Router und Navigator stehen.
      WidgetsBinding.instance.addPostFrameCallback((_) => openPath(path));
    }
    if (kIsWeb || !(Platform.isMacOS || Platform.isIOS || Platform.isAndroid)) return;
    channel.setMethodCallHandler(_handle);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final pending = await channel.invokeListMethod<Object?>('ready');
        for (final f in pending ?? const []) {
          await _openPayload(f);
        }
      } on MissingPluginException {
        // Ältere native Seite ohne Kanal (z. B. in Tests).
      } on PlatformException {
        // Nichts zu öffnen.
      }
    });
  }

  void dispose() {
    if (!kIsWeb && (Platform.isMacOS || Platform.isIOS || Platform.isAndroid)) channel.setMethodCallHandler(null);
  }

  Future<Object?> _handle(MethodCall call) async {
    if (call.method == 'open') await _openPayload(call.arguments);
    return null;
  }

  /// `{path: …}` (Apple, Windows) oder `{bytes: …}` (Android liest die
  /// Datei selbst, weil WhatsApp & Co. nur einen content://-Link geben).
  Future<void> _openPayload(Object? payload) async {
    if (payload is! Map) return;
    final bytes = payload['bytes'];
    final path = payload['path'];
    if (bytes is Uint8List) {
      openBytes(bytes);
    } else if (path is String) {
      await openPath(path);
    }
  }

  Future<void> openPath(String path) async {
    try {
      openBytes(await File(path).readAsBytes());
    } on FileSystemException {
      _showError(SharedMatchError.notDartLab);
    }
  }

  /// Liest die Datei und zeigt das Match. Bei einer fremden oder zu neuen
  /// Datei erscheint ein Hinweis, sonst passiert nichts.
  void openBytes(List<int> bytes) {
    final SharedMatch match;
    try {
      match = SharedMatch.decode(bytes);
    } on SharedMatchException catch (e) {
      _showError(e.error);
      return;
    }
    ref.read(openedSharedMatchProvider.notifier).set(match);
    ref.read(routerProvider).push(Routes.shared);
  }

  void _showError(SharedMatchError error) {
    final context = ref.read(rootNavigatorKeyProvider).currentContext;
    if (context == null) return;
    showSharedMatchError(context, error);
  }
}

/// Hinweis, wenn eine Datei nicht geöffnet werden kann.
Future<void> showSharedMatchError(BuildContext context, SharedMatchError error) {
  final l10n = context.l10n;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('shared-match-error'),
      icon: Icon(error == SharedMatchError.newerVersion ? Icons.system_update_rounded : Icons.error_outline_rounded),
      title: Text(error == SharedMatchError.newerVersion ? l10n.sharedMatchNewerTitle : l10n.sharedMatchInvalidTitle),
      content: Text(error == SharedMatchError.newerVersion ? l10n.sharedMatchNewerText : l10n.sharedMatchInvalidText),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(l10n.sharedMatchOk))],
    ),
  );
}

/// „Geteilte Datei öffnen“ im Verlauf: Auswahl-Dialog, falls Doppelklick
/// oder Teilen-Menü nicht greifen.
Future<void> pickSharedMatchFile(WidgetRef ref) async {
  final file = await openFile(acceptedTypeGroups: const [
    XTypeGroup(
      label: 'DartLab',
      extensions: [sharedMatchExtension],
      uniformTypeIdentifiers: [sharedMatchUti, 'public.json', 'public.data'],
      mimeTypes: [sharedMatchMimeType, 'application/json', 'application/octet-stream'],
    ),
  ]);
  if (file == null) return;
  ref.read(sharedMatchOpenerProvider).openBytes(await file.readAsBytes());
}
