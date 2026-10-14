import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components/components.dart';
import '../../../core/design/dart_colors.dart';
import '../../../core/design/dart_look.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n.dart';
import '../../../core/settings/app_settings.dart';
import '../domain/board_geometry.dart';
import '../domain/segment.dart';
import 'dartboard_view.dart';

/// Welches Doppel gerade gezoomt wird, oder null.
///
/// Mit Checkout-Weg ([route], nächster Dart zuerst): wenn der nächste Dart
/// ein Doppel ist, das Bull nur als letzter Dart. Ohne Weg: wenn das Spiel
/// genau ein Doppel als Ziel hat (Doppel-Training, Golf, JDC Teil 2 …).
Segment? doubleZoomTarget({List<Segment>? route, Set<Segment> targets = const {}}) {
  if (route != null) {
    if (route.isEmpty) return null;
    final next = route.first;
    return next.isDouble && (!next.isBull || route.length == 1) ? next : null;
  }
  return targets.length == 1 && targets.first.isDouble ? targets.first : null;
}

/// Eigene Karte neben der großen Scheibe: zeigt das Doppel, auf das geworfen
/// werden muss, stark vergrößert. Erscheint nur, wenn [target] gesetzt und der
/// Zoom in den Optionen an ist.
class DoubleZoomCard extends ConsumerStatefulWidget {
  const DoubleZoomCard({
    super.key,
    required this.target,
    this.hits = const [],
    this.lastSegment,
    this.hitSerial = 0,
    this.onTap,
    this.spacing = AppSpacing.m,
    this.compact = false,
  });

  /// Flacher Streifen fürs Telefon, damit die Scheibe darunter sichtbar bleibt.
  final bool compact;

  final Segment? target;
  final List<BoardPoint> hits;
  final Segment? lastSegment;
  final int hitSerial;
  final void Function(BoardPoint point, Segment segment)? onTap;

  /// Abstand unter der Karte, solange sie sichtbar ist.
  final double spacing;

  @override
  ConsumerState<DoubleZoomCard> createState() => _DoubleZoomCardState();
}

class _DoubleZoomCardState extends ConsumerState<DoubleZoomCard> {
  /// Zählt Wechsel des angezeigten Ziels. Wechselt es schneller, als die
  /// Überblendung dauert (z. B. D16 → keins → D16), bekäme der neue Inhalt
  /// sonst denselben Schlüssel wie der noch ausblendende.
  int _switches = 0;
  Segment? _shown;

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(settingsProvider.select((s) => s.doubleZoom));
    final target = enabled ? widget.target : null;
    if (target != _shown) {
      _shown = target;
      _switches++;
    }
    final hits = widget.hits;
    final lastSegment = widget.lastSegment;
    final hitSerial = widget.hitSerial;
    final onTap = widget.onTap;
    final compact = widget.compact;
    final spacing = widget.spacing;
    return AnimatedSize(
      duration: AppDurations.medium,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: AppDurations.medium,
        child: target == null
            ? SizedBox(key: ValueKey((_switches, null)), width: double.infinity)
            : Padding(
                key: ValueKey((_switches, target)),
                padding: EdgeInsets.only(bottom: spacing),
                child: _ZoomCard(
                  target: target,
                  hits: hits,
                  lastSegment: lastSegment,
                  hitSerial: hitSerial,
                  onTap: onTap,
                  compact: compact,
                ),
              ),
      ),
    );
  }
}

class _ZoomCard extends StatelessWidget {
  const _ZoomCard({
    required this.target,
    required this.hits,
    required this.lastSegment,
    required this.hitSerial,
    required this.onTap,
    required this.compact,
  });

  final bool compact;
  final Segment target;
  final List<BoardPoint> hits;
  final Segment? lastSegment;
  final int hitSerial;
  final void Function(BoardPoint point, Segment segment)? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final look = context.look;
    final colors = context.dartColors;
    return AppCard(
      key: const Key('double-zoom'),
      padding: const EdgeInsets.all(AppSpacing.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xxs, AppSpacing.xs, AppSpacing.s),
            child: Row(
              children: [
                Kicker(l10n.doubleZoomLabel),
                const Spacer(),
                Text(
                  target.name,
                  key: const Key('double-zoom-target'),
                  style: look.chipNumber.copyWith(color: colors.highlight),
                ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(look.radiusM),
            child: ColoredBox(
              color: colors.boardSurround,
              child: DartboardView(
                key: const Key('double-zoom-board'),
                semanticsLabel: l10n.doubleZoomLabel,
                focus: target,
                focusWidth: target.isBull ? 0.5 : (compact ? 1.0 : 0.9),
                aspectRatio: compact ? 2.4 : 1.55,
                hits: hits,
                lastSegment: lastSegment,
                hitSerial: hitSerial,
                highlighted: {target},
                onTap: onTap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
