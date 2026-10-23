import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/fullscreen_button.dart';
import '../../board/domain/board_geometry.dart';
import '../../board/domain/segment.dart';
import '../../board/presentation/dartboard_view.dart';
import '../domain/screen_state.dart';
import 'screen_viewer_controller.dart';

/// Route des zweiten Bildschirms (ohne Navigation, damit alles groß ist).
const String secondScreenRoute = '/zweiter-bildschirm';

final secondScreenGoRoute = GoRoute(path: secondScreenRoute, builder: (_, _) => const SecondScreenPage());

/// Zweiter Bildschirm: zeigt den Spielstand vom PC groß an, für Tablet, Mac
/// oder (per AirPlay/HDMI) den Fernseher. Quer zuerst, lesbar aus ein paar
/// Metern Abstand. Hält den Bildschirm wach, solange er offen ist.
class SecondScreenPage extends ConsumerStatefulWidget {
  const SecondScreenPage({super.key});

  @override
  ConsumerState<SecondScreenPage> createState() => _SecondScreenPageState();
}

class _SecondScreenPageState extends ConsumerState<SecondScreenPage> {
  late final ScreenWakelock _wakelock;

  @override
  void initState() {
    super.initState();
    _wakelock = ref.read(screenWakelockProvider);
    _wakelock.set(true);
  }

  @override
  void dispose() {
    _wakelock.set(false);
    super.dispose();
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewer = ref.watch(screenViewerProvider);
    final screen = viewer.screen;
    final showBoard = screen != null && !screen.isIdle && viewer.status != ViewerStatus.notConfigured;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.s, AppSpacing.l, AppSpacing.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(viewer: viewer, onClose: _close),
              const SizedBox(height: AppSpacing.m),
              Expanded(
                child: switch (viewer.status) {
                  ViewerStatus.notConfigured => ScreenMessage(
                      key: const Key('screen-not-configured'),
                      icon: Icons.link_off_rounded,
                      title: context.l10n.screenNotConfiguredTitle,
                      text: context.l10n.screenNotConfiguredText,
                      action: _settingsButton(context),
                    ),
                  ViewerStatus.wrongKey => ScreenMessage(
                      key: const Key('screen-wrong-key'),
                      icon: Icons.password_rounded,
                      title: context.l10n.screenWrongKeyTitle,
                      text: context.l10n.screenWrongKeyText,
                      action: _settingsButton(context),
                    ),
                  ViewerStatus.notDartLab => ScreenMessage(
                      key: const Key('screen-not-dartlab'),
                      icon: Icons.help_outline_rounded,
                      title: context.l10n.screenNotDartLabTitle,
                      text: context.l10n.screenNotDartLabText(viewer.host),
                      action: _settingsButton(context),
                    ),
                  ViewerStatus.hubTooOld => ScreenMessage(
                      key: const Key('screen-hub-old'),
                      icon: Icons.system_update_alt_rounded,
                      title: context.l10n.screenHubTooOldTitle,
                      text: context.l10n.screenHubTooOldText,
                    ),
                  ViewerStatus.lost when !showBoard => ScreenMessage(
                      key: const Key('screen-lost'),
                      icon: Icons.wifi_off_rounded,
                      title: context.l10n.screenLostTitle,
                      text: context.l10n.screenLostText,
                      action: _retryButton(context),
                    ),
                  ViewerStatus.lost => Stack(
                      fit: StackFit.expand,
                      children: [
                        Opacity(opacity: 0.25, child: ScreenScoreboard(state: screen!)),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: AppCard(
                              key: const Key('screen-lost'),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.wifi_off_rounded, size: 40, color: context.dartColors.danger),
                                  const SizedBox(height: AppSpacing.m),
                                  Text(context.l10n.screenLostTitle, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                                  const SizedBox(height: AppSpacing.s),
                                  Text(
                                    context.l10n.screenLostText,
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
                    ),
                  ViewerStatus.connecting when screen == null => ScreenMessage(
                      key: const Key('screen-connecting'),
                      icon: Icons.cast_connected_rounded,
                      title: context.l10n.screenConnecting,
                      text: viewer.host,
                      action: const SizedBox(width: 160, child: LinearProgressIndicator()),
                    ),
                  _ when screen == null || screen.isIdle => ScreenMessage(
                      key: const Key('screen-idle'),
                      icon: Icons.tv_rounded,
                      title: context.l10n.screenIdleTitle,
                      text: context.l10n.screenIdleText,
                    ),
                  _ => ScreenScoreboard(state: screen),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settingsButton(BuildContext context) => FilledButton.icon(
        key: const Key('screen-to-settings'),
        onPressed: () => context.go(Routes.settings),
        icon: const Icon(Icons.settings_rounded),
        label: Text(context.l10n.screenToSettings),
      );

  Widget _retryButton(BuildContext context) => FilledButton.icon(
        key: const Key('screen-retry'),
        onPressed: ref.read(screenViewerProvider.notifier).retryNow,
        icon: const Icon(Icons.refresh_rounded),
        label: Text(context.l10n.screenRetry),
      );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.viewer, required this.onClose});
  final ViewerState viewer;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final screen = viewer.screen;
    final live = screen != null && !screen.isIdle && viewer.status == ViewerStatus.connected;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final pill = switch (viewer.status) {
      ViewerStatus.connected => StatusPill(
          key: const Key('screen-pill-connected'),
          label: narrow || viewer.host.isEmpty ? l10n.screenPillConnectedShort : l10n.screenPillConnected(viewer.host),
          color: colors.success,
        ),
      ViewerStatus.connecting => StatusPill(label: l10n.screenPillConnecting, color: colors.warning, pulsing: true),
      ViewerStatus.notConfigured => null,
      _ => StatusPill(key: const Key('screen-pill-lost'), label: l10n.screenPillLost, color: colors.danger, pulsing: true),
    };
    final desktop = switch (defaultTargetPlatform) {
      TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux => true,
      _ => false,
    };
    return Row(
      children: [
        IconButton(
          key: const Key('screen-close'),
          tooltip: l10n.screenClose,
          icon: const Icon(Icons.close_rounded),
          onPressed: onClose,
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                live ? screen.title : l10n.screenTitle,
                key: const Key('screen-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge,
              ),
              if (live && screen.subtitle != null && screen.subtitle!.isNotEmpty)
                Text(
                  screen.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: colors.textMuted),
                ),
            ],
          ),
        ),
        if (pill != null) ...[
          const SizedBox(width: AppSpacing.m),
          ConstrainedBox(constraints: BoxConstraints(maxWidth: narrow ? 140 : 340), child: pill),
        ],
        if (desktop) const FullscreenButton(),
      ],
    );
  }
}

/// Hinweis mit Symbol (leer, Fehler, Warten). Öffentlich, damit die Live-Ansicht
/// der Lite-App ihn mitnutzt. Auf großen Flächen größer,
/// damit er aus der Entfernung lesbar ist.
class ScreenMessage extends StatelessWidget {
  const ScreenMessage({super.key, required this.icon, required this.title, required this.text, this.action});
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final big = MediaQuery.sizeOf(context).shortestSide >= 600;
    final child = ComingSoon(icon: icon, title: title, text: text, action: action);
    return Center(child: big ? Transform.scale(scale: 1.3, child: child) : SingleChildScrollView(child: child));
  }
}

/// Die große Anzeigetafel. Öffentlich für Tests und Screenshots.
///
/// Die Größe der Restpunkte wird aus dem Platz berechnet (Breite der Tafel
/// und Höhe), alle Tafeln bekommen dieselbe Schriftgröße. Bleibt Platz übrig,
/// zeigt die Anzeige darin das Board.
class ScreenScoreboard extends StatelessWidget {
  const ScreenScoreboard({super.key, required this.state});
  final ScreenState state;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final gap = look.gridGap;
    return LayoutBuilder(builder: (context, c) {
      final landscape = c.maxWidth > c.maxHeight * 1.15 && c.maxWidth >= 700;
      final short = c.maxHeight < 520;
      final single = state.players.length <= 1;
      final stats = single && state.stats.isNotEmpty;
      // Seitenspalte mit kleinem Board und Kennzahlen, wenn Platz ist.
      final side = landscape && !short && c.maxWidth >= 900 ? (c.maxWidth * 0.3).clamp(280.0, 420.0) : 0.0;
      final banner = _Banner(state: state);
      final bannerHeight = state.banner == null ? 0.0 : 80.0;

      // Das Board gehört zu jedem laufenden Spiel; wo kein Platz ist, steht es
      // daneben (ein Spieler) oder darunter (scrollbar).
      final showBoard = !state.isIdle;

      // Telefon quer: Aufnahme rechts neben den Tafeln.
      if (landscape && short) {
        final height = c.maxHeight - bannerHeight;
        final sideBoard = showBoard && single ? math.min(height - 12, c.maxWidth * 0.3) : 0.0;
        final boardWidth = sideBoard >= 120 ? sideBoard : 0.0;
        final visitWidth = (c.maxWidth * 0.36).clamp(260.0, 380.0) - (boardWidth > 0 ? boardWidth * 0.6 : 0);
        final playersWidth = c.maxWidth - visitWidth - gap - (boardWidth > 0 ? boardWidth + gap : 0);
        // Die Aufnahme passt ihre Dart-Felder an die Höhe an (Kopf, Ränder und
        // Wegzeile brauchen ihren Platz), statt über den Rand zu laufen.
        final visitChipHeight = (height - AppSpacing.m * 2 - 20 - AppSpacing.s - (state.route.isNotEmpty || state.setupLabel != null ? AppSpacing.s + 22 : 0) - 4).clamp(36.0, 72.0);
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            banner,
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: playersWidth,
                    child: _Players(state: state, font: _scoreFont(context, state, playersWidth, height, compact: true), compact: true),
                  ),
                  SizedBox(width: gap),
                  Expanded(child: _VisitStrip(state: state, compact: true, chipHeight: visitChipHeight)),
                  if (boardWidth > 0) ...[
                    SizedBox(width: gap),
                    SizedBox(width: boardWidth, child: Center(child: _BoardCard(state: state))),
                  ],
                ],
              ),
            ),
          ],
        );
        if (!showBoard || boardWidth > 0) return content;
        // Zwei Spieler: das Board folgt unter den Tafeln.
        return SingleChildScrollView(
          key: const Key('screen-scroll'),
          child: Column(
            children: [
              SizedBox(height: c.maxHeight, child: content),
              SizedBox(height: gap),
              SizedBox(width: math.min(c.maxWidth, c.maxHeight * 1.1), child: _BoardCard(state: state)),
            ],
          ),
        );
      }

      final mainWidth = side == 0 ? c.maxWidth : c.maxWidth - side - gap;
      final visitHeight = short || !landscape && c.maxHeight < 700 ? 150.0 : 190.0;
      final statsHeight = stats && side == 0 ? 170.0 : 0.0;
      final forPlayers = c.maxHeight - bannerHeight - visitHeight - statsHeight - gap * 2;
      final font = _scoreFont(context, state, mainWidth, forPlayers);
      final playersHeight = _panelHeight(state, font);
      final left = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Flexibel: reicht der Platz doch nicht, werden die Tafeln kleiner.
          Flexible(child: SizedBox(height: playersHeight, child: _Players(state: state, font: font))),
          SizedBox(height: gap),
          // Übriger Platz (Tafeln durch die Breite begrenzt) macht die Darts
          // der Aufnahme größer.
          _VisitStrip(
            state: state,
            compact: visitHeight < 190,
            chipHeight: visitHeight < 190 ? null : (110 + forPlayers - playersHeight).clamp(110.0, 190.0),
          ),
          if (statsHeight > 0) ...[SizedBox(height: gap), _StatsCard(stats: state.stats, columns: landscape ? 4 : 2)],
        ],
      );

      if (side == 0) {
        // Hochkant: übrigen Platz bekommt das Board. Aufteilung nach Anteilen,
        // damit nichts überläuft, wenn die Schätzung nicht ganz stimmt. Reicht
        // der Platz auch mit kleinster Schrift nicht (Kennzahlen dazu), scrollt
        // die Anzeige: Tafeln, Aufnahme, Board, Kennzahlen.
        const boardMin = 180.0;
        final fixed = bannerHeight + visitHeight + statsHeight + gap * (showBoard ? 3 : 2);
        final avail = c.maxHeight - fixed;
        final fits = !showBoard || avail - _panelHeight(state, 64) >= boardMin;
        if (fits) {
          final shownFont = !showBoard || playersHeight <= avail - boardMin ? font : _scoreFont(context, state, mainWidth, avail - boardMin);
          final shownHeight = _panelHeight(state, shownFont);
          final rest = avail - shownHeight;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              banner,
              Expanded(flex: shownHeight.round(), child: _Players(state: state, font: shownFont)),
              SizedBox(height: gap),
              _VisitStrip(state: state, compact: visitHeight < 190),
              if (statsHeight > 0) ...[SizedBox(height: gap), _StatsCard(stats: state.stats, columns: landscape ? 4 : 2)],
              if (showBoard) ...[
                SizedBox(height: gap),
                Expanded(flex: rest.round(), child: Center(child: _BoardCard(state: state))),
              ],
            ],
          );
        }
        final scrollFont = _scoreFont(context, state, mainWidth, 250);
        return SingleChildScrollView(
          key: const Key('screen-scroll'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              banner,
              SizedBox(height: _panelHeight(state, scrollFont), child: _Players(state: state, font: scrollFont)),
              SizedBox(height: gap),
              _VisitStrip(state: state, compact: visitHeight < 190),
              SizedBox(height: gap),
              Center(child: SizedBox(width: math.min(c.maxWidth, 360.0), child: _BoardCard(state: state))),
              if (state.stats.isNotEmpty && single) ...[SizedBox(height: gap), _StatsCard(stats: state.stats, columns: landscape ? 4 : 2)],
            ],
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          banner,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: left),
                SizedBox(width: gap),
                SizedBox(
                  width: side,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _BoardCard(state: state),
                      SizedBox(height: gap),
                      if (stats) _StatsCard(stats: state.stats, columns: 2) else _LastVisitCard(state: state),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  /// Platz in einer Tafel außer der großen Zahl: Kopf, Ränder, Kennzahlen.
  static double _reserved(ScreenState state, {bool compact = false}) {
    final meta = state.players.any((p) => p.legs != null || p.sets != null || p.average != null || p.darts != null);
    return (meta ? (compact ? 120.0 : 140.0) : 84.0) + (state.progress != null ? 22 : 0);
  }

  static double _panelHeight(ScreenState state, double font) => font * 1.02 + _reserved(state);

  /// Schriftgröße der Restpunkte: so groß, dass die breiteste Zahl in ihre
  /// Tafel passt und die Tafeln in [height].
  static double _scoreFont(BuildContext context, ScreenState state, double width, double height, {bool compact = false}) {
    final n = state.players.isEmpty ? 1 : state.players.length;
    final gap = context.look.gridGap;
    final inner = (width - gap * (n - 1)) / n - 64;
    final style = ScorePanel.valueStyle(context).copyWith(fontSize: 100, height: 1.0);
    var widest = 1.0;
    for (final p in state.players) {
      final tp = TextPainter(
        text: TextSpan(text: p.score.length < 3 ? '${p.score}0' : p.score, style: style),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      if (tp.width > widest) widest = tp.width;
      tp.dispose();
    }
    final byWidth = 100 * inner / widest;
    final byHeight = (height - _reserved(state, compact: compact)) / 1.02;
    return byWidth < byHeight ? byWidth.clamp(40.0, 420.0) : byHeight.clamp(40.0, 420.0);
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.state});
  final ScreenState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.dartColors;
    final text = state.banner;
    final color = switch (state.bannerTone) {
      ScreenTone.positive => colors.success,
      ScreenTone.negative => colors.danger,
      ScreenTone.neutral => Theme.of(context).colorScheme.primary,
    };
    return AnimatedSwitcher(
      duration: AppDurations.medium,
      transitionBuilder: (child, a) => SizeTransition(sizeFactor: a, child: FadeTransition(opacity: a, child: child)),
      child: text == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              key: ValueKey(text),
              padding: EdgeInsets.only(bottom: context.look.gridGap),
              child: LookBanner(text: text, color: color, textKey: const Key('screen-banner')),
            ),
    );
  }
}

/// Eine Tafel je Spieler nebeneinander (bei mehr als zwei auf schmalen
/// Bildschirmen untereinander).
class _Players extends StatelessWidget {
  const _Players({required this.state, required this.font, this.compact = false});
  final ScreenState state;
  final double font;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final gap = context.look.gridGap;
    final players = state.players;
    return LayoutBuilder(builder: (context, c) {
      final vertical = players.length > 2 && c.maxWidth < 700;
      final panels = [
        for (var i = 0; i < players.length; i++)
          Expanded(
            child: _PlayerPanel(
              key: Key('screen-player-$i'),
              player: players[i],
              state: state,
              many: players.length > 1,
              font: vertical ? font / players.length : font,
              compact: compact,
            ),
          ),
      ];
      final children = [
        for (var i = 0; i < panels.length; i++) ...[
          if (i > 0) vertical ? SizedBox(height: gap) : SizedBox(width: gap),
          panels[i],
        ],
      ];
      return vertical
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
    });
  }
}

class _PlayerPanel extends StatelessWidget {
  const _PlayerPanel({super.key, required this.player, required this.state, required this.many, required this.font, this.compact = false});
  final ScreenPlayer player;
  final ScreenState state;
  final bool many;
  final double font;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final look = context.look;
    final lit = !many || player.active || player.winner;

    Widget stat(String label, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Kicker(label),
            Text(value, style: look.statValue.copyWith(fontSize: compact ? 20 : 26, color: lit ? theme.colorScheme.onSurface : colors.textMuted)),
          ],
        );

    final meta = [
      if (player.sets != null) stat(l10n.matchSets, '${player.sets}'),
      if (player.legs != null) stat(l10n.matchLegs, '${player.legs}'),
      if (many && player.average != null) stat(l10n.matchAvg, player.average!),
      if (many && player.lastVisit != null) stat(l10n.matchLastVisit, '${player.lastVisit}'),
      if (!many && player.darts != null && state.kind != ScreenKind.live) stat(l10n.matchDarts, '${player.darts}'),
    ];

    final name = player.name.isNotEmpty ? player.name : player.scoreLabel;
    final panel = ScorePanel(
      label: name,
      active: many ? lit : null,
      trailing: player.name.isNotEmpty && !many ? player.scoreLabel : null,
      progress: many ? null : state.progress,
      badge: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!many && state.progressLabel != null) ...[
            Text(state.progressLabel!, style: look.kicker.copyWith(color: colors.textMuted, fontSize: 16)),
            const SizedBox(width: AppSpacing.m),
          ],
          if (player.starter) ...[
            Container(width: 10, height: 10, decoration: BoxDecoration(color: colors.highlight, shape: BoxShape.circle)),
            const SizedBox(width: AppSpacing.s),
          ],
          if (player.winner) ...[
            Icon(Icons.emoji_events_rounded, size: 20, color: colors.success),
            const SizedBox(width: AppSpacing.xs),
          ],
          if (many)
            Icon(player.bot ? Icons.smart_toy_outlined : Icons.person_rounded, size: 20, color: lit ? theme.colorScheme.onSurface : colors.textMuted),
        ],
      ),
      value: Text(
        player.score,
        key: Key('screen-score-${player.name}'),
        maxLines: 1,
        style: ScorePanel.valueStyle(context).copyWith(
          fontSize: font,
          height: 1.0,
          color: lit ? theme.colorScheme.onSurface : colors.textMuted,
        ),
      ),
      footer: meta.isEmpty ? null : Wrap(spacing: compact ? AppSpacing.l : AppSpacing.xl, runSpacing: AppSpacing.s, children: meta),
    );
    // Passt die Tafel trotz Rechnung nicht, wird sie als Ganzes kleiner.
    return LayoutBuilder(
      builder: (context, c) => c.hasBoundedHeight
          ? FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: SizedBox(width: c.maxWidth, child: panel),
            )
          : panel,
    );
  }
}

/// Die Darts der laufenden Aufnahme mit Checkout-Weg und Status.
class _VisitStrip extends StatelessWidget {
  const _VisitStrip({required this.state, required this.compact, this.chipHeight});
  final ScreenState state;
  final bool compact;

  /// Höhe der Dart-Felder; Standard je nach [compact].
  final double? chipHeight;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final look = context.look;
    final darts = [for (final n in state.visit) Segment.tryParse(n) ?? Segment.miss];
    final hasRoute = state.route.isNotEmpty;
    final plan = [for (final n in hasRoute ? state.route : state.setup) ?Segment.tryParse(n)];
    final planColor = hasRoute ? colors.highlight : colors.setupHint;
    final planText = hasRoute
        ? '${look.caps(l10n.screenCheckout)}  ${state.route.join(' · ')}'
        : state.setupLabel != null
            ? look.caps(state.setupLabel!)
            : null;
    final score = state.bust ? 'BUST' : (state.visitScore == null ? '' : '${state.visitScore}');
    final header = state.finished ? l10n.screenFinished : (state.status ?? l10n.statVisitScore);

    return AppCard(
      padding: EdgeInsets.all(compact ? AppSpacing.m : AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  look.caps(header),
                  key: const Key('screen-status'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: look.kicker.copyWith(fontSize: compact ? 15 : 20, color: theme.colorScheme.primary),
                ),
              ),
              if (planText != null && !compact)
                Flexible(
                  child: Text(
                    planText,
                    key: const Key('screen-route'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: look.chipNumber.copyWith(fontSize: 22, color: planColor),
                  ),
                ),
            ],
          ),
          SizedBox(height: compact ? AppSpacing.s : AppSpacing.m),
          SizedBox(
            height: chipHeight ?? (compact ? 72 : 110),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < 3; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                      child: FittedBox(
                        child: DartChip(
                          key: Key('screen-dart-$i'),
                          segment: i < darts.length ? darts[i] : null,
                          planned: i >= darts.length && i - darts.length < plan.length ? plan[i - darts.length] : null,
                          plannedColor: planColor,
                          large: true,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
                      child: Text(
                        score,
                        key: const Key('screen-visit-score'),
                        style: look.scoreLarge.copyWith(color: state.bust ? colors.danger : theme.colorScheme.onSurface),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (planText != null && compact) ...[
            const SizedBox(height: AppSpacing.s),
            Text(planText, key: const Key('screen-route'), maxLines: 1, overflow: TextOverflow.ellipsis, style: look.chipNumber.copyWith(fontSize: 16, color: planColor)),
          ],
        ],
      ),
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.state});
  final ScreenState state;

  @override
  Widget build(BuildContext context) {
    final hits = [
      for (final h in state.hits)
        if (h.x != null && h.y != null) BoardPoint(h.x!, h.y!),
    ];
    final last = state.hits.isEmpty ? null : Segment.tryParse(state.hits.last.segment);
    final target = state.route.isEmpty ? null : Segment.tryParse(state.route.first);
    // Ohne Koordinaten (manuelle Eingabe) gibt es keinen Punkt auf der Scheibe:
    // dann bleibt das zuletzt getroffene Feld sichtbar hervorgehoben.
    final lastWithoutPoint = state.hits.isNotEmpty && (state.hits.last.x == null || state.hits.last.y == null) && last != null && !last.isMiss;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: AspectRatio(
        aspectRatio: 1,
        child: DartboardView(
          key: const Key('screen-board'),
          hits: hits,
          lastSegment: last,
          hitSerial: state.hitSerial,
          highlighted: {?target, if (lastWithoutPoint) last},
        ),
      ),
    );
  }
}

class _LastVisitCard extends StatelessWidget {
  const _LastVisitCard({required this.state});
  final ScreenState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final look = context.look;
    final theme = Theme.of(context);
    if (state.lastVisit.isEmpty) return const SizedBox.shrink();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Kicker(l10n.liveVisitLast),
          const SizedBox(height: AppSpacing.s),
          Row(
            children: [
              Expanded(
                child: Text(
                  state.lastVisit.join('  '),
                  key: const Key('screen-last-visit'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: look.chipNumber.copyWith(fontSize: 22, color: theme.colorScheme.onSurface),
                ),
              ),
              if (state.lastVisitScore != null)
                Text('${state.lastVisitScore}', style: look.statValue.copyWith(color: theme.colorScheme.onSurface)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats, required this.columns});
  final List<ScreenStat> stats;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final theme = Theme.of(context);
    final shown = stats.take(columns * 3).toList();
    return AppCard(
      key: const Key('screen-stats'),
      child: LayoutBuilder(builder: (context, c) {
        final width = (c.maxWidth - (columns - 1) * AppSpacing.l) / columns;
        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Wrap(
            spacing: AppSpacing.l,
            runSpacing: AppSpacing.l,
            children: [
              for (final s in shown)
                SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Kicker(s.label, maxLines: 2),
                      const SizedBox(height: AppSpacing.xxs),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(s.value, style: look.statValue.copyWith(color: theme.colorScheme.onSurface)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}
