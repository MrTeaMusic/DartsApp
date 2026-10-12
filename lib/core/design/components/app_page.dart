import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../dart_look.dart';

/// Ab dieser Breite gilt der breite Seitenrand des Looks.
const double kWidePage = 720;

/// Scrollbare Seite mit Seitenrand und Höchstbreite des Looks. Für alle
/// Bildschirme mit einer Spalte (Optionen, Spiel-Setup, Pläne, …).
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.children,
    this.maxWidth = 720,
    this.extraBottom = 0,
    this.listKey,
  });

  final List<Widget> children;
  final double maxWidth;

  /// Zusätzlicher Platz unten, z. B. für einen schwebenden Knopf.
  final double extraBottom;
  final Key? listKey;

  @override
  Widget build(BuildContext context) {
    final look = context.look;
    return LayoutBuilder(builder: (context, c) {
      final pad = look.pagePadding(c.maxWidth >= kWidePage);
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth + 2 * pad),
          child: ListView(
            key: listKey,
            padding: EdgeInsets.fromLTRB(pad, look.page * 0.5, pad, pad + extraBottom),
            children: children,
          ),
        ),
      );
    });
  }
}

/// Abstand zwischen zwei Abschnitten einer Seite (Rhythmus des Looks).
class SectionGap extends StatelessWidget {
  const SectionGap({super.key, this.factor = 1});
  final double factor;

  @override
  Widget build(BuildContext context) => SizedBox(height: context.look.sectionGap * factor);
}

/// Kopfzeile, deren Titel bündig mit dem Inhalt einer [AppPage] steht
/// (auch wenn der Inhalt auf breiten Bildschirmen zentriert ist).
class AppPageBar extends StatelessWidget implements PreferredSizeWidget {
  const AppPageBar({
    super.key,
    this.title,
    this.actions = const [],
    this.leading,
    this.bottom,
    this.maxWidth = double.infinity,
  });

  final Widget? title;
  final List<Widget> actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;

  /// Höchstbreite des Inhalts darunter (wie bei [AppPage]).
  final double maxWidth;

  // Gleiche Höhe wie eine AppBar, damit die Toolbarhöhe des Themes gilt.
  @override
  Size get preferredSize => AppBar(bottom: bottom).preferredSize;

  /// Linker Rand des Inhalts bei gegebener Breite.
  static double contentInset(BuildContext context, double width, double maxWidth) {
    final pad = context.look.pagePadding(width >= kWidePage);
    final centered = maxWidth.isFinite ? (width - maxWidth) / 2 : 0.0;
    return centered > pad ? centered : pad;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final inset = contentInset(context, c.maxWidth, maxWidth);
      final hasLeading = leading != null || (ModalRoute.of(context)?.impliesAppBarDismissal ?? false);
      return AppBar(
        leading: leading,
        title: title,
        titleSpacing: hasLeading ? math.max(_minSpacing, inset - kToolbarHeight) : inset,
        bottom: bottom,
        actions: [
          ...actions,
          SizedBox(width: math.max(_minActionGap, inset - _actionInset)),
        ],
      );
    });
  }

  static const double _minSpacing = 8;
  static const double _actionInset = 8;
  static const double _minActionGap = 4;
}
