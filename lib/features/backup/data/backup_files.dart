import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Dateien speichern und öffnen. In Tests ersetzbar.
abstract class BackupFiles {
  /// Speichert [content] und gibt den Pfad zurück, `null` bei Abbruch.
  Future<String?> save(String fileName, String content, {required String mimeType, required String extension});

  /// Lässt eine JSON-Datei auswählen und gibt ihren Text zurück, `null`
  /// bei Abbruch.
  Future<String?> openJson();
}

/// Windows/macOS: Speichern-Dialog. iOS: Ablage im Dokumente-Ordner der App
/// (in der Dateien-App unter „Auf meinem iPhone › DartLab“ sichtbar).
class SystemBackupFiles implements BackupFiles {
  @override
  Future<String?> save(String fileName, String content, {required String mimeType, required String extension}) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android) {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, fileName));
      await file.writeAsBytes(bytes);
      return file.path;
    }
    final location = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: [XTypeGroup(label: extension.toUpperCase(), extensions: [extension])],
    );
    if (location == null) return null;
    var path = location.path;
    if (p.extension(path).isEmpty) path = '$path.$extension';
    await XFile.fromData(bytes, mimeType: mimeType, name: fileName).saveTo(path);
    return path;
  }

  @override
  Future<String?> openJson() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'JSON', extensions: ['json'], uniformTypeIdentifiers: ['public.json']),
    ]);
    return file?.readAsString();
  }
}

final backupFilesProvider = Provider<BackupFiles>((ref) => SystemBackupFiles());
