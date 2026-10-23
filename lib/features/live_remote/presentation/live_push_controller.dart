import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/lite.dart';
import '../../../core/settings/app_settings.dart';
import '../../second_screen/presentation/screen_feed.dart';
import '../../sync/data/cloud_api.dart';
import '../../sync/data/cloud_crypto.dart';
import '../../sync/domain/sync_role.dart';
import '../../sync/presentation/sync_controller.dart' show cloudHttpClientProvider;
import '../data/live_pusher.dart';
import '../data/live_sink.dart';

/// Baut das Ziel, an das der Pusher sendet. In Tests ersetzbar.
typedef LiveSinkFactory = Future<LiveSink?> Function(String url, String secret);

final liveSinkFactoryProvider = Provider<LiveSinkFactory>((ref) {
  final newClient = ref.read(cloudHttpClientProvider);
  return (url, secret) => CloudLiveSink.create(url, secret, client: newClient());
});

/// Ist „Live übers Internet zeigen“ wirksam? Nur mit Cloud-Rolle, Schalter an
/// und ausgefüllter Verbindung; die Lite-Variante schickt nie etwas.
bool liveShareWanted(AppSettings s) => s.syncRole == SyncRole.cloud && s.liveShare;

/// Hält den [LivePusher] am Leben, solange der Schalter an ist, und zeigt
/// seinen Zustand. Ist der Schalter aus (der Normalfall), passiert hier
/// nichts: kein Zuhören bei den Spielen, kein Zeitgeber, keine Anfrage.
///
/// Die Cloud-Rolle schließt die Hub-Rolle aus; der Feed der Spiele gehört
/// dann niemand anderem (beim Hub hängt ihn der zweite Bildschirm bei einem
/// Zuschauer an). Der Pusher nutzt dieselbe Stand-Funktion wie der Hub.
class LivePushController extends Notifier<LivePushInfo> {
  LivePusher? _pusher;
  ScreenFeed? _feed;
  bool _disposed = false;

  /// Zählt die Aufbauten; ein Start, der in der Zwischenzeit überholt wurde, gibt auf.
  int _generation = 0;

  @override
  LivePushInfo build() {
    _disposed = false;
    final generation = ++_generation;
    ref.onDispose(_teardown);
    if (ref.watch(liteProvider)) return LivePushInfo.off;
    final (wanted, url, secret) = ref.watch(settingsProvider.select((s) => (liveShareWanted(s), s.syncCloudUrl.trim(), s.syncCloudSecret)));
    if (!wanted) return LivePushInfo.off;
    if (url.isEmpty || CloudApi.tryParseUrl(url) == null || CloudSecret.tryParse(secret) == null) {
      return const LivePushInfo(LivePushStatus.notConfigured);
    }
    Future.microtask(() => _start(generation, url, secret));
    return const LivePushInfo(LivePushStatus.starting);
  }

  Future<void> _start(int generation, String url, String secret) async {
    bool stale() => _disposed || generation != _generation;
    if (stale()) return;
    final LiveSink? sink;
    try {
      sink = await ref.read(liveSinkFactoryProvider)(url, secret);
    } on Object {
      if (!stale()) state = const LivePushInfo(LivePushStatus.notConfigured);
      return;
    }
    if (sink == null || stale()) {
      sink?.close();
      if (sink == null && !stale()) state = const LivePushInfo(LivePushStatus.notConfigured);
      return;
    }
    final feed = ref.read(screenFeedProvider);
    final pusher = LivePusher(
      snapshot: feed.snapshot,
      sink: sink,
      onStatus: (info) {
        if (!stale()) state = info;
      },
    );
    _pusher = pusher;
    _feed = feed;
    feed.attach(pusher.markDirty);
    pusher.start();
  }

  void _teardown() {
    _disposed = true;
    _feed?.detach();
    _feed = null;
    // Läuft gerade ein Spiel auf dem Schirm der Zuschauer, bekommen sie noch
    // ein „idle“.
    _pusher?.stop(sendIdle: true);
    _pusher = null;
  }
}

final livePushControllerProvider = NotifierProvider<LivePushController, LivePushInfo>(LivePushController.new);
