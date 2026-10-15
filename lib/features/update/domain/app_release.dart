import 'package:flutter/foundation.dart';

/// Version und Build-Nummer einer App, z. B. 0.10.0 Build 123.
///
/// Der Release-Workflow nimmt die Version aus pubspec.yaml und die
/// Laufnummer auf GitHub als Build-Nummer. Die Build-Nummer steigt mit
/// jedem Release und entscheidet daher, was neuer ist. Build 0 steht für
/// eine selbst gebaute App ohne Nummer.
@immutable
class AppBuild implements Comparable<AppBuild> {
  const AppBuild(this.version, this.build);

  /// „0.10.0“
  final String version;

  /// Laufnummer des Release-Workflows; 0 = selbst gebaut.
  final int build;

  bool get isDevBuild => build <= 0;

  static final _tag = RegExp(r'^v?(\d+\.\d+\.\d+)(?:[+-]b?(\d+))?$');

  /// Liest Tags wie `v0.10.0-b123`, `v0.10.0+123` oder `0.10.0`.
  static AppBuild? tryParse(String? tag) {
    final m = _tag.firstMatch(tag?.trim() ?? '');
    if (m == null) return null;
    return AppBuild(m.group(1)!, int.tryParse(m.group(2) ?? '') ?? 0);
  }

  List<int> get _parts => [for (final p in version.split('.')) int.tryParse(p) ?? 0];

  /// Vergleicht nur die Versionsnummer (ohne Build).
  int compareVersion(AppBuild other) {
    final a = _parts, b = other._parts;
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  /// Sind beide Build-Nummern bekannt, zählt nur die Build-Nummer (sie steigt
  /// mit jedem Release, auch wenn die Version gleich bleibt). Sonst die
  /// Versionsnummer.
  @override
  int compareTo(AppBuild other) {
    if (!isDevBuild && !other.isDevBuild) return build.compareTo(other.build);
    final v = compareVersion(other);
    return v != 0 ? v : build.compareTo(other.build);
  }

  bool isNewerThan(AppBuild other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) => other is AppBuild && other.version == version && other.build == build;

  @override
  int get hashCode => Object.hash(version, build);

  @override
  String toString() => isDevBuild ? version : '$version+$build';
}

/// Plattform, für die ein Download angeboten wird.
enum ReleasePlatform {
  windows('windows'),
  macos('macos');

  const ReleasePlatform(this.assetKey);

  /// Teil des Dateinamens, z. B. `DartLab-windows.zip`.
  final String assetKey;
}

/// Eine Datei am Release.
@immutable
class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.url, required this.size});
  final String name;
  final Uri url;

  /// Größe in Byte (0 = unbekannt).
  final int size;

  Map<String, Object?> toJson() => {'name': name, 'browser_download_url': '$url', 'size': size};
}

/// Das neueste Release auf GitHub, aus
/// `GET /repos/MrTeaMusic/DartsApp/releases/latest`.
@immutable
class AppRelease {
  const AppRelease({
    required this.tag,
    required this.build,
    required this.title,
    required this.notes,
    required this.pageUrl,
    required this.assets,
    this.publishedAt,
  });

  final String tag;
  final AppBuild build;
  final String title;

  /// Text des Releases (Markdown, vom Workflow aus den PR-Titeln erzeugt).
  final String notes;

  /// Seite des Releases auf GitHub.
  final Uri pageUrl;
  final List<ReleaseAsset> assets;
  final DateTime? publishedAt;

  /// Liest die Antwort der GitHub-API. Liefert `null`, wenn das Tag kein
  /// Versions-Tag ist oder Pflichtfelder fehlen (z. B. Entwurf).
  static AppRelease? fromJson(Object? json) {
    if (json is! Map) return null;
    final tag = json['tag_name'];
    final build = AppBuild.tryParse(tag is String ? tag : null);
    final page = Uri.tryParse(json['html_url'] is String ? json['html_url'] as String : '');
    if (build == null || page == null || !page.hasScheme) return null;
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final assets = <ReleaseAsset>[];
    final rawAssets = json['assets'];
    if (rawAssets is List) {
      for (final a in rawAssets) {
        if (a is! Map) continue;
        final name = a['name'], url = a['browser_download_url'];
        final uri = url is String ? Uri.tryParse(url) : null;
        if (name is! String || uri == null || !uri.hasScheme) continue;
        final size = a['size'];
        assets.add(ReleaseAsset(name: name, url: uri, size: size is int ? size : 0));
      }
    }
    final name = json['name'];
    final body = json['body'];
    final published = json['published_at'];
    return AppRelease(
      tag: tag as String,
      build: build,
      title: name is String && name.trim().isNotEmpty ? name.trim() : tag,
      notes: body is String ? body.replaceAll('\r\n', '\n').trim() : '',
      pageUrl: page,
      assets: List.unmodifiable(assets),
      publishedAt: published is String ? DateTime.tryParse(published) : null,
    );
  }

  /// Für den Zwischenspeicher in den Einstellungen.
  Map<String, Object?> toJson() => {
        'tag_name': tag,
        'name': title,
        'body': notes,
        'html_url': '$pageUrl',
        'published_at': publishedAt?.toIso8601String(),
        'assets': [for (final a in assets) a.toJson()],
      };

  /// Zip-Datei für [platform], z. B. `DartLab-windows.zip`.
  ReleaseAsset? assetFor(ReleasePlatform platform) {
    final key = platform.assetKey;
    return assets
        .where((a) => a.name.toLowerCase().contains(key) && a.name.toLowerCase().endsWith('.zip'))
        .firstOrNull;
  }

  /// Bis zu [max] Zeilen der Release-Notizen ohne Markdown-Zeichen, für das
  /// Hinweisfeld auf der Startseite.
  List<String> shortNotes({int max = 3}) {
    final lines = <String>[];
    for (final raw in notes.split('\n')) {
      var line = raw.trim();
      // Überschriften, Kommentare und Zitate (Installationshinweis des
      // Workflows) gehören nicht in die Kurzfassung.
      if (line.isEmpty || line.startsWith('#') || line.startsWith('<!--') || line.startsWith('>')) continue;
      line = line.replaceFirst(RegExp(r'^([-*+]|\d+\.)\s+'), '');
      line = line.replaceAll('**', '').replaceAll('`', '');
      line = line.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m.group(1)!);
      if (line.isEmpty) continue;
      lines.add(line);
      if (lines.length == max) break;
    }
    return lines;
  }

  /// Anzahl der Notiz-Zeilen, die [shortNotes] weglässt.
  int hiddenNoteCount({int max = 3}) {
    final all = shortNotes(max: 1000).length;
    return all > max ? all - max : 0;
  }
}
