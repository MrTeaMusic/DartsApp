import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_version.dart';
import '../../../core/settings/app_settings.dart';
import '../data/update_client.dart';
import '../domain/app_release.dart';

/// Was die laufende App über sich weiß. Im Test überschreibbar.
final currentBuildProvider = Provider<AppBuild>((ref) => const AppBuild(appVersionName, appBuildNumber));

final updateHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final updateClientProvider = Provider<UpdateClient>((ref) => UpdateClient(ref.watch(updateHttpClientProvider)));

/// Uhr für die 24-Stunden-Regel (Tests).
final updateClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Betriebssystem-Anbindung: Download-Ordner, Ordner und Links öffnen.
final updateHostProvider = Provider<UpdateHost>((ref) => const UpdateHost());

class UpdateHost {
  const UpdateHost();

  /// Plattform mit Zip-Download, sonst `null` (iOS, Linux, Android).
  ReleasePlatform? get platform => switch (defaultTargetPlatform) {
        TargetPlatform.windows => ReleasePlatform.windows,
        TargetPlatform.macOS => ReleasePlatform.macos,
        _ => null,
      };

  bool get isIos => defaultTargetPlatform == TargetPlatform.iOS;

  Future<Directory> downloadsDirectory() async {
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    // macOS (Sandbox): der Container-Ordner „Downloads“ verweist auf
    // ~/Downloads. Den echten Pfad anzeigen und öffnen.
    try {
      return Directory(dir.resolveSymbolicLinksSync());
    } on FileSystemException {
      return dir;
    }
  }

  Future<bool> openFolder(Directory dir) async {
    if (Platform.isWindows) {
      await Process.start('explorer.exe', [dir.path], mode: ProcessStartMode.detached);
      return true;
    }
    return launchUrl(Uri.directory(dir.path));
  }

  Future<bool> openUrl(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);
}

enum UpdateStatus {
  /// Noch nicht gesucht (oder automatische Suche still gescheitert).
  idle,
  checking,
  upToDate,

  /// Neuere Version gefunden.
  available,

  /// Selbst gebaute App: zeigt nur, was auf GitHub liegt.
  devBuild,

  /// Manuelle Suche gescheitert, siehe [UpdateState.failure].
  failed,
}

enum DownloadPhase { idle, running, done, failed }

@immutable
class UpdateState {
  const UpdateState({
    required this.current,
    this.status = UpdateStatus.idle,
    this.latest,
    this.failure,
    this.lastChecked,
    this.skippedBuild = 0,
    this.downloadPhase = DownloadPhase.idle,
    this.progress,
    this.file,
  });

  final AppBuild current;
  final UpdateStatus status;

  /// Zuletzt gefundenes Release (auch aus dem Zwischenspeicher).
  final AppRelease? latest;
  final UpdateFailure? failure;
  final DateTime? lastChecked;

  /// „Später“ gilt bis zu dieser Build-Nummer.
  final int skippedBuild;
  final DownloadPhase downloadPhase;

  /// 0…1 beim Download, `null` = Größe unbekannt.
  final double? progress;

  /// Heruntergeladene Datei.
  final File? file;

  /// Gibt es eine neuere Version als die laufende? Selbst gebaute Apps
  /// melden nie eine.
  bool get updateAvailable {
    final l = latest;
    return l != null && !current.isDevBuild && l.build.isNewerThan(current);
  }

  /// Hinweis auf der Startseite: neuere Version, nicht mit „Später“
  /// weggeklickt.
  bool get showBanner => updateAvailable && latest!.build.build > skippedBuild;

  UpdateState copyWith({
    UpdateStatus? status,
    AppRelease? latest,
    UpdateFailure? failure,
    bool clearFailure = false,
    DateTime? lastChecked,
    int? skippedBuild,
    DownloadPhase? downloadPhase,
    double? progress,
    bool clearProgress = false,
    File? file,
    bool clearFile = false,
  }) =>
      UpdateState(
        current: current,
        status: status ?? this.status,
        latest: latest ?? this.latest,
        failure: clearFailure ? null : failure ?? this.failure,
        lastChecked: lastChecked ?? this.lastChecked,
        skippedBuild: skippedBuild ?? this.skippedBuild,
        downloadPhase: downloadPhase ?? this.downloadPhase,
        progress: clearProgress ? null : progress ?? this.progress,
        file: clearFile ? null : file ?? this.file,
      );
}

final updateControllerProvider = NotifierProvider<UpdateController, UpdateState>(UpdateController.new);

/// Sucht nach neuen Versionen auf GitHub: beim Start höchstens einmal in
/// 24 Stunden (still, ohne Fehlermeldung) und auf Knopfdruck in den Optionen.
class UpdateController extends Notifier<UpdateState> {
  static const checkInterval = Duration(hours: 24);
  static const _kLastCheck = 'update.lastCheck';
  static const _kSkipped = 'update.skippedBuild';
  static const _kLatest = 'update.latest';

  @override
  UpdateState build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final current = ref.watch(currentBuildProvider);
    final last = prefs.getInt(_kLastCheck);
    AppRelease? cached;
    final raw = prefs.getString(_kLatest);
    if (raw != null) {
      try {
        cached = AppRelease.fromJson(jsonDecode(raw));
      } on FormatException {
        cached = null;
      }
    }
    final initial = UpdateState(
      current: current,
      latest: cached,
      lastChecked: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
      skippedBuild: prefs.getInt(_kSkipped) ?? 0,
    );
    if (_autoCheckDue(initial)) Future.microtask(() => check(manual: false));
    return initial;
  }

  bool _autoCheckDue(UpdateState s) {
    if (s.current.isDevBuild) return false;
    final last = s.lastChecked;
    return last == null || ref.read(updateClockProvider)().difference(last) >= checkInterval;
  }

  /// Fragt GitHub. [manual]: Fehler werden angezeigt; sonst bleibt alles
  /// still.
  Future<void> check({bool manual = true}) async {
    if (state.status == UpdateStatus.checking) return;
    final before = state.status;
    state = state.copyWith(status: UpdateStatus.checking, clearFailure: true);
    try {
      final release = await ref.read(updateClientProvider).fetchLatest();
      if (!ref.mounted) return;
      final now = ref.read(updateClockProvider)();
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setInt(_kLastCheck, now.millisecondsSinceEpoch);
      await prefs.setString(_kLatest, jsonEncode(release.toJson()));
      if (!ref.mounted) return;
      final next = state.copyWith(latest: release, lastChecked: now);
      state = next.copyWith(
        status: next.current.isDevBuild
            ? UpdateStatus.devBuild
            : (next.updateAvailable ? UpdateStatus.available : UpdateStatus.upToDate),
      );
    } on UpdateException catch (e) {
      if (!ref.mounted) return;
      state = manual
          ? state.copyWith(status: UpdateStatus.failed, failure: e.failure)
          : state.copyWith(status: before);
    } catch (e) {
      if (!ref.mounted) return;
      debugPrint('Update-Suche: $e');
      state = manual
          ? state.copyWith(status: UpdateStatus.failed, failure: UpdateFailure.other)
          : state.copyWith(status: UpdateStatus.idle);
    }
  }

  /// „Später“: Hinweis ausblenden, bis es eine noch neuere Version gibt.
  Future<void> later() async {
    final build = state.latest?.build.build;
    if (build == null) return;
    state = state.copyWith(skippedBuild: build);
    await ref.read(sharedPreferencesProvider).setInt(_kSkipped, build);
  }

  /// Lädt die Zip der eigenen Plattform in den Download-Ordner. Ohne
  /// passende Datei öffnet sich die Release-Seite im Browser.
  Future<void> download() async {
    final release = state.latest;
    if (release == null || state.downloadPhase == DownloadPhase.running) return;
    final host = ref.read(updateHostProvider);
    final platform = host.platform;
    final asset = platform == null ? null : release.assetFor(platform);
    if (platform == null || asset == null) {
      await openReleasePage();
      return;
    }
    state = state.copyWith(downloadPhase: DownloadPhase.running, progress: 0, clearFile: true);
    try {
      final dir = await host.downloadsDirectory();
      final b = release.build;
      final target = File(p.join(dir.path, 'DartLab-${platform.assetKey}-${b.version}-b${b.build}.zip'));
      var shown = -1;
      final file = await ref.read(updateClientProvider).download(asset, target, onProgress: (v) {
        // Nur ganze Prozent weitergeben, sonst baut die Karte bei jedem
        // Datenpaket neu.
        final pct = v == null ? -2 : (v * 100).floor();
        if (pct == shown || !ref.mounted) return;
        shown = pct;
        state = state.copyWith(progress: v, clearProgress: v == null);
      });
      if (!ref.mounted) return;
      state = state.copyWith(downloadPhase: DownloadPhase.done, file: file, progress: 1);
    } catch (e) {
      if (!ref.mounted) return;
      debugPrint('Update-Download: $e');
      state = state.copyWith(downloadPhase: DownloadPhase.failed, clearProgress: true);
    }
  }

  Future<void> openDownloadFolder() async {
    final file = state.file;
    if (file == null) return;
    try {
      await ref.read(updateHostProvider).openFolder(file.parent);
    } catch (e) {
      debugPrint('Ordner öffnen: $e');
    }
  }

  Future<void> openReleasePage() async {
    try {
      await ref.read(updateHostProvider).openUrl(state.latest?.pageUrl ?? UpdateClient.releasesPage);
    } catch (e) {
      debugPrint('Release-Seite öffnen: $e');
    }
  }
}
