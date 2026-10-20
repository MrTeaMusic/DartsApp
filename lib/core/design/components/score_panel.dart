import 'package:flutter/material.dart';

import '../dart_colors.dart';
import '../dart_look.dart';
import '../tokens.dart';
import 'components.dart';

/// Große Anzeige für Restpunkte, Aufnahme oder Ergebnis.
///
/// * TV: Scoreboard-Tafel mit rotem Beschriftungsfeld wie eine Bauchbinde.
/// * Clean: ruhige Karte, Beschriftung klein darüber.
/// * Lab: Kopfzeile mit Linie, technische Ziffern.
class ScorePanel extends StatelessWidget {
  const ScorePanel({
    super.key,
    required this.label,
    required this.value,
    this.trailing,
    this.progress,
    this.badge,
    this.footer,
    this.active,
    this.compact = false,
    this.pinFooter = false,
  });

  /// Beschriftung („Rest“, „Aufnahme“).
  final String label;

  /// Die Zahl; Stil über [ScorePanel.valueStyle].
  final Widget value;

  /// Text rechts in der Kopfzeile, z. B. „3/10“.
  final String? trailing;

  /// Fortschritt 0–1 unter der Zahl.
  final double? progress;

  /// Zusätzliches Element rechts in der Kopfzeile (z. B. Statusschild).
  final Widget? badge;

  /// Inhalt unter der Zahl, z. B. die drei Darts der Aufnahme.
  final Widget? footer;

  /// Mehrere Tafeln nebeneinander (Spieler im Match): `true` hebt die
  /// Tafel hervor (Beschriftung in Akzentfarbe), `false` lässt sie
  /// zurücktreten (TV ohne rote Leiste). `null` = einzelne Tafel.
  final bool? active;

  /// Schmale Tafel (mehrere Spieler auf dem Telefon): engere Innenabstände,
  /// damit Zahl, Kennzahlen und Tabelle genug Breite haben.
  final bool compact;

  /// Der Inhalt unter der Zahl sitzt am unteren Rand der Tafel. Nur in einer
  /// Zeile mit gleich hohen Tafeln (z. B. `IntrinsicHeight`): so stehen
  /// Kennzahlen und Tabellen nebeneinander auf einer Höhe, auch wenn die
  /// Zahlen unterschiedlich breit und damit unterschiedlich hoch sind.
  final bool pinFooter;

  /// Stil der großen Zahl im aktuellen Look.
  ///
  /// [compact] für schmale Bildschirme: etwa drei Viertel der großen Zahl,
  /// damit Darts und Board auf dem Telefon sichtbar bleiben.
  static TextStyle valueStyle(BuildContext context, {bool hero = true, bool compact = false}) {
    final look = context.look;
    final base = hero ? look.scoreHero : look.scoreLarge;
    final style = base.copyWith(color: Theme.of(context).colorScheme.onSurface);
    return compact ? style.copyWith(fontSize: (base.fontSize ?? 96) * 0.7) : style;
  }

  Widget _footerSlot(Widget child) => pinFooter ? Expanded(child: Align(alignment: Alignment.bottomCenter, child: child)) : child;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    final colors = context.dartColors;
    final theme = Theme.of(context);
    final number = FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: value);
    final bar = progress == null
        ? null
        : TweenAnimationBuilder<double>(
            tween: Tween(end: progress!.clamp(0, 1).toDouble()),
            duration: AppDurations.medium,
            builder: (context, v, _) => LookProgressBar(value: v),
          );

    switch (look.id) {
      case DartLookId.tv:
        final headerStyle = look.kicker.copyWith(color: active == false ? colors.textMuted : colors.onPanelHeader, fontSize: 16);
        return ClipRRect(
          borderRadius: BorderRadius.circular(look.radiusL),
          child: ColoredBox(
            color: colors.panel,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 36,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(
                        // Schmale Tafel: der Name bekommt den größeren Teil der Kopfzeile.
                        flex: compact ? 3 : 1,
                        child: Container(
                          color: active == false ? colors.surfaceHigh : colors.panelHeader,
                          padding: EdgeInsets.symmetric(horizontal: compact ? AppSpacing.s - 1 : AppSpacing.m + 2),
                          alignment: Alignment.centerLeft,
                          child: Text(look.caps(label), style: headerStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      Expanded(
                        flex: compact ? 2 : 1,
                        child: Container(
                          color: colors.surfaceHigh,
                          padding: EdgeInsets.symmetric(horizontal: compact ? AppSpacing.s - 1 : AppSpacing.m + 2),
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (badge != null)
                                Flexible(child: compact ? FittedBox(fit: BoxFit.scaleDown, child: badge!) : badge!),
                              if (badge != null && trailing != null) const SizedBox(width: AppSpacing.s),
                              if (trailing != null)
                                Flexible(
                                  child: Text(
                                    trailing!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: headerStyle.copyWith(color: theme.colorScheme.onSurface),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: compact
                      ? const EdgeInsets.fromLTRB(AppSpacing.m, AppSpacing.s, AppSpacing.m, AppSpacing.s)
                      : const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.m, AppSpacing.l, AppSpacing.m),
                  child: number,
                ),
                if (footer != null)
                  _footerSlot(
                    Padding(
                      padding: compact
                          ? const EdgeInsets.fromLTRB(AppSpacing.s, 0, AppSpacing.s, AppSpacing.s)
                          : const EdgeInsets.fromLTRB(AppSpacing.m, 0, AppSpacing.m, AppSpacing.m),
                      child: footer,
                    ),
                  ),
                if (progress != null)
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: progress!.clamp(0, 1).toDouble()),
                    duration: AppDurations.medium,
                    builder: (context, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 6,
                      color: theme.colorScheme.primary,
                      backgroundColor: colors.surfaceHigh,
                    ),
                  ),
              ],
            ),
          ),
        );
      case DartLookId.clean:
        return AppCard(
          padding: compact
              ? const EdgeInsets.fromLTRB(AppSpacing.m, AppSpacing.m + 2, AppSpacing.m, AppSpacing.l)
              : const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.l + 2, AppSpacing.xl, AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: active == true ? theme.colorScheme.primary : colors.textMuted,
                      ),
                    ),
                  ),
                  ?badge,
                  if (trailing != null)
                    Text(trailing!, style: theme.textTheme.titleMedium?.copyWith(color: colors.textMuted)),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              number,
              if (footer != null) _footerSlot(Padding(padding: const EdgeInsets.only(top: AppSpacing.m), child: footer)),
              if (bar != null) ...[const SizedBox(height: AppSpacing.m), bar],
            ],
          ),
        );
      case DartLookId.lab:
        final inset = compact ? AppSpacing.s + 2 : look.cardPadding;
        return AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: colors.panelHeader,
                padding: EdgeInsets.symmetric(horizontal: look.cardPadding, vertical: AppSpacing.s + 1),
                child: Row(
                  children: [
                    Expanded(child: Kicker(label, color: active == true ? theme.colorScheme.primary : null)),
                    ?badge,
                    if (trailing != null)
                      Text(
                        trailing!,
                        style: look.chipNumber.copyWith(fontSize: 13, color: theme.colorScheme.onSurface),
                      ),
                  ],
                ),
              ),
              Container(height: 1, color: theme.colorScheme.outline),
              Padding(
                padding: EdgeInsets.fromLTRB(inset, AppSpacing.s, inset, AppSpacing.m),
                child: number,
              ),
              if (footer != null) _footerSlot(Padding(padding: EdgeInsets.fromLTRB(inset, 0, inset, inset), child: footer)),
              if (bar != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(look.cardPadding, 0, look.cardPadding, look.cardPadding),
                  child: bar,
                ),
            ],
          ),
        );
    }
  }
}
