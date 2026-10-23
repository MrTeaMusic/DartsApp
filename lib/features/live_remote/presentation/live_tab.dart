import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../second_screen/domain/screen_state.dart';
import '../../second_screen/presentation/screen_viewer_controller.dart' show screenWakelockProvider, ScreenWakelock;
import '../../second_screen/presentation/second_screen_page.dart';
import 'live_viewer_controller.dart';

/// Reiter „Live“ der Lite-App: Bens Spiel, wie der zweite Bildschirm es zeigt,
/// nur aus dem Cloud-Speicher statt aus dem Heimnetz. Nur lesen.
///
/// Abgefragt wird nur, solange der Reiter offen und die App im Vordergrund
/// ist; dann bleibt auch der Bildschirm an.
class LiveTab extends ConsumerStatefulWidget {
  const LiveTab({super.key});

  @override
  ConsumerState<LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends ConsumerState<LiveTab> with WidgetsBindingObserver {
  late final ScreenWakelock _wakelock;
  AppLifecycleState? _lifecycle;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    _wakelock = ref.read(screenWakelockProvider);
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_active) {
      _active = false;
      _wakelock.set(false);
      // Der Controller gibt sich selbst frei, sobald dieser Reiter weg ist.
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  /// Der Reiter ist offen, wenn sein Zweig im Router der aktive ist (die
  /// Zweige bleiben sonst im Hintergrund erhalten, ihre Animationen sind dann
  /// abgeschaltet: `TickerMode`).
  void _sync() {
    final visible = TickerMode.valuesOf(context).enabled;
    final foreground = _lifecycle == null || _lifecycle == AppLifecycleState.resumed;
    final active = visible && foreground;
    if (active == _active) return;
    _active = active;
    ref.read(liveViewerProvider.notifier).setActive(active);
    _wakelock.set(active);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.dartColors;
    final live = ref.watch(liveViewerProvider);
    final pad = context.look.pagePadding(false);
    final pill = switch (live.status) {
      LiveViewStatus.playing => StatusPill(key: const Key('live-pill-live'), label: l10n.livePillLive, color: colors.success, pulsing: true),
      LiveViewStatus.lost => StatusPill(key: const Key('live-pill-lost'), label: l10n.livePillLost, color: colors.danger, pulsing: true),
      LiveViewStatus.connecting => StatusPill(label: l10n.liveConnecting, color: colors.warning, pulsing: true),
      _ => null,
    };
    // Läuft ein Spiel, steht sein Titel in der Kopfzeile (das spart eine Zeile
    // für die Anzeigetafel); sonst "Live".
    final playingTitle = live.status == LiveViewStatus.playing ? live.screen?.title : null;
    return Scaffold(
      appBar: AppPageBar(
        title: Text(playingTitle ?? l10n.liveTitle, key: const Key('live-bar-title'), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [?pill],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad, AppSpacing.s, pad, pad),
          child: KeyedSubtree(key: const Key('live-tab'), child: _body(context, live)),
        ),
      ),
    );
  }

  static bool _short(BuildContext context) => MediaQuery.sizeOf(context).height < 520;

  Widget _body(BuildContext context, LiveViewState live) {
    final l10n = context.l10n;
    final screen = live.screen;
    switch (live.status) {
      case LiveViewStatus.connecting:
        return ScreenMessage(
          key: const Key('live-connecting'),
          icon: Icons.cast_connected_rounded,
          title: l10n.liveConnecting,
          text: '',
          action: const SizedBox(width: 160, child: LinearProgressIndicator()),
        );
      case LiveViewStatus.playing when screen != null:
        return _Playing(key: const Key('live-playing'), state: screen, short: _short(context));
      case LiveViewStatus.playing:
      case LiveViewStatus.notPlaying:
        return ScreenMessage(key: const Key('live-idle'), icon: Icons.tv_off_rounded, title: l10n.liveIdleTitle, text: l10n.liveIdleText);
      case LiveViewStatus.lost when screen != null:
        return Stack(
          key: const Key('live-lost'),
          fit: StackFit.expand,
          children: [
            Opacity(opacity: 0.25, child: IgnorePointer(child: ScreenScoreboard(state: screen))),
            Center(
              // Bei sehr niedrigen Bildschirmen (Handy quer) scrollt die Karte.
              child: SingleChildScrollView(
                child: AppCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off_rounded, size: 40, color: context.dartColors.danger),
                      const SizedBox(height: AppSpacing.m),
                      Text(l10n.liveLostTitle, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                      const SizedBox(height: AppSpacing.s),
                      Text(
                        l10n.liveLostText,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.dartColors.textMuted),
                      ),
                      const SizedBox(height: AppSpacing.l),
                      _retryButton(context),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      case LiveViewStatus.lost:
        return ScreenMessage(
          key: const Key('live-lost'),
          icon: Icons.wifi_off_rounded,
          title: l10n.liveLostTitle,
          text: l10n.liveLostText,
          action: _retryButton(context),
        );
      case LiveViewStatus.workerTooOld:
        return ScreenMessage(
          key: const Key('live-old-worker'),
          icon: Icons.system_update_alt_rounded,
          title: l10n.liveOldWorkerTitle,
          text: l10n.liveOldWorkerText,
        );
      case LiveViewStatus.wrongSecret:
        return ScreenMessage(
          key: const Key('live-wrong-secret'),
          icon: Icons.password_rounded,
          title: l10n.liveWrongSecretTitle,
          text: l10n.liveWrongSecretText,
          action: FilledButton.icon(
            key: const Key('live-to-settings'),
            onPressed: () => context.go(Routes.settings),
            icon: const Icon(Icons.settings_rounded),
            label: Text(l10n.liveToSettings),
          ),
        );
    }
  }

  Widget _retryButton(BuildContext context) => FilledButton.icon(
        key: const Key('live-retry'),
        onPressed: ref.read(liveViewerProvider.notifier).retryNow,
        icon: const Icon(Icons.refresh_rounded),
        label: Text(context.l10n.liveRetry),
      );
}

/// Untertitel des Spiels (Format, Leg, Runde) über der Anzeigetafel. Auf
/// niedrigen Bildschirmen (Handy quer) entfällt die Zeile, damit die Tafel
/// Platz hat.
class _Playing extends StatelessWidget {
  const _Playing({super.key, required this.state, required this.short});
  final ScreenState state;
  final bool short;

  @override
  Widget build(BuildContext context) {
    final subtitle = state.subtitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!short && subtitle != null && subtitle.isNotEmpty) ...[
          Text(
            subtitle,
            key: const Key('live-subtitle'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.dartColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.s),
        ],
        Expanded(child: ScreenScoreboard(state: state)),
      ],
    );
  }
}
