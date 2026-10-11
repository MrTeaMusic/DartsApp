import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/dart_colors.dart';
import '../design/dart_look.dart';
import '../design/tokens.dart';
import '../l10n.dart';
import 'fullscreen_button.dart';

/// Hülle um alle Hauptbereiche: Seitenleiste auf Desktop/iPad quer,
/// Bottom-Navigation auf schmalen Geräten.
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final destinations = [
      (Icons.home_outlined, Icons.home_rounded, l10n.navHome),
      (Icons.sports_esports_outlined, Icons.sports_esports_rounded, l10n.navGames),
      (Icons.adjust_outlined, Icons.adjust_rounded, l10n.navBoard),
      (Icons.insights_outlined, Icons.insights_rounded, l10n.navStats),
      (Icons.settings_outlined, Icons.settings_rounded, l10n.navSettings),
    ];
    final width = MediaQuery.sizeOf(context).width;

    void go(int index) => shell.goBranch(index, initialLocation: index == shell.currentIndex);

    if (width < AppBreakpoints.sidebar) {
      final look = context.look;
      return Scaffold(
        body: shell,
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: look.id == DartLookId.tv
                ? null
                : Border(top: BorderSide(color: Theme.of(context).colorScheme.outline)),
          ),
          child: NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: go,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              for (final (icon, selected, label) in destinations)
                NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
            ],
          ),
        ),
      );
    }

    final extended = width >= AppBreakpoints.sidebarExtended;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: extended,
            minExtendedWidth: context.look.id == DartLookId.lab ? 200 : 228,
            selectedIndex: shell.currentIndex,
            onDestinationSelected: go,
            labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.s, AppSpacing.l, AppSpacing.s, AppSpacing.xl),
              child: _Logo(extended: extended),
            ),
            trailing: const Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(padding: EdgeInsets.only(bottom: AppSpacing.l), child: FullscreenButton()),
              ),
            ),
            destinations: [
              for (final (icon, selected, label) in destinations)
                NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: Text(label)),
            ],
          ),
          VerticalDivider(width: 1, color: Theme.of(context).colorScheme.outline),
          Expanded(child: shell),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.extended});
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final colors = context.dartColors;
    final look = context.look;
    final theme = Theme.of(context);
    final mark = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.boardSurround,
        border: Border.all(color: look.id == DartLookId.tv ? theme.colorScheme.primary : colors.boardRed, width: 5),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(shape: BoxShape.circle, color: colors.boardGreen),
      ),
    );
    if (!extended) return mark;
    final title = context.l10n.appTitle;
    final style = switch (look.id) {
      DartLookId.tv => look.sectionTitle.copyWith(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: theme.colorScheme.onSurface),
      DartLookId.clean => theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 20),
      DartLookId.lab => theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.2),
    };
    return SizedBox(
      width: 196,
      child: Row(
        children: [
          mark,
          const SizedBox(width: AppSpacing.m),
          Flexible(
            child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(title, style: style)),
          ),
        ],
      ),
    );
  }
}
