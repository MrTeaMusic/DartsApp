import 'package:flutter/material.dart';

import '../../../features/board/domain/segment.dart';
import '../dart_colors.dart';
import '../dart_look.dart';
import '../tokens.dart';

export 'app_page.dart';
export 'event_banner.dart';
export 'hero_backdrop.dart';
export 'look_picker_tile.dart';
export 'score_panel.dart';
export 'visit_table.dart';

/// Karte mit einheitlichem Innenabstand. Rahmen, Schatten und Radius kommen
/// vom Look: TV flach, Clean mit weichem Schatten, Lab mit feiner Linie.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.color,
  });

  final Widget child;

  /// Standard: Innenabstand des Looks.
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  /// Abweichende Kartenfarbe (z. B. Scoreboard-Tafel).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(look.radiusL);
    final light = theme.brightness == Brightness.light;
    final shadow = look.card == CardTreatment.elevated && light ? look.shadow : const <BoxShadow>[];
    final side = look.card == CardTreatment.outlined ? BorderSide(color: theme.colorScheme.outline) : BorderSide.none;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: shadow),
      child: Material(
        color: color ?? theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: radius, side: side),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding ?? EdgeInsets.all(look.cardPadding), child: child),
        ),
      ),
    );
  }
}

/// Überschrift über einem Abschnitt: TV mit Akzentbalken, Clean ruhig,
/// Lab als kleine Versalien mit Linie.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final theme = Theme.of(context);
    final colors = context.dartColors;
    final style = switch (look.header) {
      HeaderTreatment.rule => look.sectionTitle.copyWith(color: colors.textMuted),
      _ => look.sectionTitle.copyWith(color: theme.colorScheme.onSurface),
    };
    final text = Text(look.caps(title), style: style, maxLines: 2, overflow: TextOverflow.ellipsis);
    return Padding(
      padding: EdgeInsets.only(
        bottom: look.header == HeaderTreatment.plain ? AppSpacing.m : AppSpacing.s + 2,
        top: AppSpacing.xs,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        // Kein LayoutBuilder: der Kopf steht auch in IntrinsicHeight-Zeilen.
        child: look.header == HeaderTreatment.rule
            ? _ruleRow(context, text)
            : Row(
                children: [
                  if (look.header == HeaderTreatment.bar) ...[
                    Container(width: 4, height: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: AppSpacing.s + 2),
                  ],
                  Expanded(child: text),
                  if (trailing != null) ...[
                    const SizedBox(width: AppSpacing.s),
                    ConstrainedBox(constraints: const BoxConstraints(maxWidth: 200), child: trailing),
                  ],
                ],
              ),
      ),
    );
  }
}

extension on SectionHeader {
  /// Lab: Linie über die ganze Breite hinter dem Titel; Titel und
  /// Zusatz decken sie mit der Farbe der Fläche darunter ab. So füllt die
  /// Linie genau den freien Platz, ohne die Breite messen zu müssen.
  Widget _ruleRow(BuildContext context, Widget text) {
    final theme = Theme.of(context);
    final background = Material.maybeOf(context)?.color ?? theme.scaffoldBackgroundColor;
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        Positioned(left: 0, right: 0, child: Container(height: 1, color: theme.colorScheme.outline)),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: ColoredBox(
                color: background,
                child: Padding(padding: const EdgeInsets.only(right: AppSpacing.m), child: text),
              ),
            ),
            if (trailing != null)
              ColoredBox(
                color: background,
                child: Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.m),
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 200), child: trailing),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Kleine Beschriftung über einer Zahl („REST“, „AUFNAHME“).
class Kicker extends StatelessWidget {
  const Kicker(this.text, {super.key, this.color, this.maxLines = 1});
  final String text;
  final Color? color;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    return Text(
      look.caps(text),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: look.kicker.copyWith(color: color ?? context.dartColors.textMuted),
    );
  }
}

/// Fortschrittsbalken mit Radius und Höhe des Looks.
class LookProgressBar extends StatelessWidget {
  const LookProgressBar({super.key, required this.value, this.color, this.height});
  final double value;
  final Color? color;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    return ClipRRect(
      borderRadius: BorderRadius.circular(look.barRadius),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1).toDouble(),
        minHeight: height ?? look.barHeight,
        backgroundColor: context.dartColors.surfaceHigh,
        color: color ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

/// Symbol in einer getönten Fläche, z. B. vor Spiel- und Plankarten.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, this.color, this.size = 44});
  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;
    final (Color bg, Color fg, BoxBorder? border) = switch (look.id) {
      DartLookId.tv => (context.dartColors.surfaceHigh, accent, null),
      DartLookId.clean => (accent.withValues(alpha: 0.12), accent, null),
      DartLookId.lab => (accent.withValues(alpha: 0.08), accent, Border.all(color: accent.withValues(alpha: 0.35))),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        border: border,
        borderRadius: BorderRadius.circular(look.id == DartLookId.clean ? size * 0.3 : look.radiusM),
      ),
      child: Icon(icon, color: fg, size: size * 0.52),
    );
  }
}

/// Kennzahl mit großer Zahl, z. B. "3-Dart-Average 54,3".
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.footer,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;

  /// Zusätzliche Zeile unter dem Wert (z. B. Veränderung).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final look = context.look;
    final colors = context.dartColors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: look.id == DartLookId.lab ? 14 : 16, color: colors.textMuted),
                const SizedBox(width: AppSpacing.xs + 2),
              ],
              Expanded(child: Kicker(label, maxLines: 2)),
            ],
          ),
          SizedBox(height: look.id == DartLookId.lab ? AppSpacing.s : AppSpacing.m),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: look.statValue.copyWith(color: theme.colorScheme.onSurface)),
          ),
          ?footer,
          if (caption != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(caption!, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

/// Kleines Statusschild mit farbigem Punkt.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.pulsing = false,
    this.onTap,
  });

  final String label;
  final Color color;
  final bool pulsing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final radius = BorderRadius.circular(look.id == DartLookId.clean ? AppRadii.pill : look.radiusS);
    final style = look.id == DartLookId.tv
        ? look.kicker.copyWith(color: color, fontSize: 14, letterSpacing: 0.8)
        : Theme.of(context).textTheme.labelMedium?.copyWith(color: color, letterSpacing: look.id == DartLookId.lab ? 0.4 : 0);
    return Material(
      color: color.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: look.id == DartLookId.lab ? BorderSide(color: color.withValues(alpha: 0.4)) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.xs + 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Dot(color: color, pulsing: pulsing),
              const SizedBox(width: AppSpacing.s),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  const _Dot({required this.color, required this.pulsing});
  final Color color;
  final bool pulsing;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Dot old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.pulsing && _c.isAnimating) {
      _c
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final square = context.look.id != DartLookId.clean;
    return FadeTransition(
      opacity: widget.pulsing ? Tween(begin: 0.35, end: 1.0).animate(_c) : const AlwaysStoppedAnimation(1),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: square ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: square ? BorderRadius.circular(context.look.id == DartLookId.tv ? 1 : 2) : null,
        ),
      ),
    );
  }
}

/// Farbe für ein Feld nach Multiplikator: Triple lila, Double grün.
Color segmentColor(BuildContext context, Segment s) {
  final colors = context.dartColors;
  if (s.isMiss) return colors.textMuted;
  if (s.isTriple) return colors.tripleHit;
  if (s.isDouble) return colors.doubleHit;
  return Theme.of(context).colorScheme.onSurface;
}

/// Anzeige eines geworfenen Felds, eingefärbt nach Multiplikator.
///
/// Ist noch kein Dart geworfen, kann [planned] den empfohlenen Wurf zeigen
/// (gelb, z. B. der Checkout-Weg).
class DartChip extends StatelessWidget {
  const DartChip({
    super.key,
    this.segment,
    this.planned,
    this.plannedColor,
    this.large = false,
    this.onTap,
    this.label,
    this.edited = false,
    this.editedTooltip,
  });

  /// `null` = noch nicht geworfen (Platzhalter).
  final Segment? segment;

  /// Empfohlenes Feld für einen noch nicht geworfenen Dart.
  final Segment? planned;

  /// Farbe der Empfehlung; Standard ist Gelb (Checkout-Weg).
  final Color? plannedColor;
  final bool large;

  /// Antippen, z. B. zum Korrigieren. Zeigt oben rechts einen dezenten Stift
  /// (gesetzter Dart) bzw. ein Plus (freier Platz, z. B. zum Ergänzen).
  final VoidCallback? onTap;

  /// Kleine Beschriftung oben links, z. B. „1“.
  final String? label;

  /// Von Hand gesetzt oder korrigiert: kleiner Stift in der Akzentfarbe.
  final bool edited;

  /// Text zum Stift bei [edited] (Tooltip und Screenreader).
  final String? editedTooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.dartColors;
    final look = context.look;
    final theme = Theme.of(context);
    final s = segment;
    final p = s == null ? planned : null;
    final Color accent = s != null ? segmentColor(context, s) : (p != null ? (plannedColor ?? colors.highlight) : colors.textMuted);
    final size = large ? 92.0 : 64.0;
    final text = s?.name ?? p?.name ?? '–';
    final radius = BorderRadius.circular(switch (look.id) {
      DartLookId.tv => look.radiusM,
      DartLookId.clean => large ? 20 : 14,
      DartLookId.lab => look.radiusM,
    });
    final neutral = s != null && !s.isTriple && !s.isDouble && !s.isMiss;

    // Fläche und Rahmen je Look; Bedeutung der Farben bleibt gleich.
    final Color fill;
    final Color borderColor;
    final double borderWidth;
    switch (look.id) {
      case DartLookId.tv:
        fill = s != null
            ? (neutral ? colors.surfaceHigh : accent.withValues(alpha: 0.18))
            : p != null
                ? accent.withValues(alpha: 0.10)
                : colors.panel;
        borderColor = p != null ? accent.withValues(alpha: 0.85) : (s == null ? theme.colorScheme.outline : Colors.transparent);
        borderWidth = p != null ? 2 : 1;
      case DartLookId.clean:
        fill = s != null
            ? (neutral ? colors.surfaceHigh : accent.withValues(alpha: 0.13))
            : p != null
                ? accent.withValues(alpha: 0.14)
                : colors.surfaceHigh.withValues(alpha: 0.6);
        borderColor = Colors.transparent;
        borderWidth = 0;
      case DartLookId.lab:
        fill = s != null
            ? accent.withValues(alpha: neutral ? 0.05 : 0.10)
            : p != null
                ? accent.withValues(alpha: 0.07)
                : theme.scaffoldBackgroundColor;
        borderColor = s != null
            ? accent.withValues(alpha: neutral ? 0.35 : 0.6)
            : p != null
                ? accent.withValues(alpha: 0.7)
                : theme.colorScheme.outline;
        borderWidth = 1;
    }
    final numberStyle = large ? look.scoreMedium : look.chipNumber;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: AppDurations.medium,
          curve: Curves.easeOutCubic,
          width: size * 1.35,
          height: size,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: radius,
            border: borderWidth == 0 ? null : Border.all(color: borderColor, width: borderWidth),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              children: [
                // TV: farbige Unterkante wie ein Scoreboard-Feld.
                if (look.id == DartLookId.tv && s != null && !s.isMiss)
                  Positioned(left: 0, right: 0, bottom: 0, height: large ? 5 : 3, child: ColoredBox(color: neutral ? theme.colorScheme.primary : accent)),
                if (label != null)
                  Positioned(
                    left: large ? 10 : 8,
                    top: large ? 8 : 6,
                    child: Text(label!, style: look.kicker.copyWith(color: colors.textMuted, fontSize: look.kicker.fontSize! - 1)),
                  ),
                if (edited && s != null)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Tooltip(
                      message: editedTooltip ?? '',
                      excludeFromSemantics: editedTooltip == null,
                      child: Container(
                        padding: EdgeInsets.all(large ? 3 : 2),
                        decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
                        child: Icon(Icons.edit_rounded, size: large ? 11 : 9, color: theme.colorScheme.onPrimary),
                      ),
                    ),
                  )
                else if (onTap != null)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Icon(
                      s != null ? Icons.edit_rounded : Icons.add_rounded,
                      size: large ? 14 : 12,
                      color: colors.textMuted.withValues(alpha: 0.7),
                    ),
                  ),
                Center(
                  child: AnimatedSwitcher(
                    duration: AppDurations.medium,
                    transitionBuilder: (child, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: child)),
                    child: Text(
                      text,
                      key: ValueKey('${s == null ? 'p' : 's'}$text'),
                      style: numberStyle.copyWith(
                        color: s == null && p == null ? colors.textMuted : accent,
                        fontWeight: p != null && look.id != DartLookId.tv ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Leerer Zustand bzw. Hinweis für Funktionen ohne Inhalt.
class ComingSoon extends StatelessWidget {
  const ComingSoon({super.key, required this.title, required this.text, this.icon = Icons.construction_rounded, this.action});

  final String title;
  final String text;
  final IconData icon;

  /// Optionaler Knopf unter dem Text.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final look = context.look;
    final accent = theme.colorScheme.primary;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: look.id == DartLookId.tv ? 0.16 : 0.10),
                  shape: look.id == DartLookId.clean ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: look.id == DartLookId.clean ? null : BorderRadius.circular(look.radiusL),
                  border: look.id == DartLookId.lab ? Border.all(color: accent.withValues(alpha: 0.35)) : null,
                ),
                child: Icon(icon, size: 34, color: accent),
              ),
              const SizedBox(height: AppSpacing.l),
              Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.s),
              Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: context.dartColors.textMuted), textAlign: TextAlign.center),
              if (action != null) ...[
                const SizedBox(height: AppSpacing.l),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
