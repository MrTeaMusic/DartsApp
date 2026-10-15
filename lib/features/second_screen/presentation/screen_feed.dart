import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n.dart';
import '../../autodarts_live/presentation/autodarts_live_controller.dart';
import '../../board/presentation/live_visit_controller.dart';
import '../../games/presentation/active_game_controller.dart';
import '../../matches/presentation/match_controller.dart';
import '../../matches/presentation/match_texts.dart';
import '../../profiles/presentation/active_player.dart';
import '../domain/screen_state.dart';
import 'screen_snapshot.dart';

/// Hub-Seite des zweiten Bildschirms: weiß, was am PC gerade läuft, und
/// meldet Änderungen.
///
/// Hört nur zu, solange ein Viewer verbunden ist ([attach] bis [detach]),
/// und zwar „schwach“: Kein Spiel und kein Live-Modus wird dadurch gestartet
/// oder am Leben gehalten.
class ScreenFeed {
  ScreenFeed(this._ref);

  final Ref _ref;
  final List<ProviderSubscription<Object?>> _subs = [];
  VoidCallback? _liveListener;
  ValueNotifier<LiveViewState?>? _live;
  AppLocalizations? _l10n;

  AppLocalizations get _texts => _l10n ??= lookupAppLocalizations(const Locale('de'));

  bool get attached => _subs.isNotEmpty;

  /// Beginnt zuzuhören; [onChange] bei jeder Änderung eines Spiels.
  void attach(VoidCallback onChange) {
    detach();
    void changed(Object? _, Object? _) => onChange();
    _subs
      ..add(_ref.listen(matchControllerProvider, changed, weak: true))
      ..add(_ref.listen(activeGameProvider, changed, weak: true))
      ..add(_ref.listen(liveVisitProvider, changed, weak: true));
    // Live-Modus nur über den Spiegel: ein Mitlesen am Live-Provider selbst
    // würde ihn (autoDispose) beim Lesen neu starten.
    final live = _ref.read(liveViewMirrorProvider);
    _live = live;
    _liveListener = onChange;
    live.addListener(onChange);
  }

  void detach() {
    for (final s in _subs) {
      s.close();
    }
    _subs.clear();
    if (_liveListener case final l?) _live?.removeListener(l);
    _liveListener = null;
  }

  /// Der aktuelle Stand. Vorrang: Match, dann Trainingsspiel, dann Live.
  /// (`exists` ist nach dem schwachen Zuhören immer wahr; Match und Training
  /// sind ohnehin dauerhaft aktiv, ihr Lesen startet nichts.)
  ScreenState snapshot() {
    final ref = _ref;
    final l10n = _texts;
    if (ref.exists(matchControllerProvider)) {
      final match = ref.read(matchControllerProvider);
      if (match != null) return ScreenSnapshot.match(l10n, match, round: _round(l10n, match.setup.tournamentMatch));
    }
    if (ref.exists(activeGameProvider)) {
      final game = ref.read(activeGameProvider);
      if (game != null) {
        return ScreenSnapshot.training(
          l10n,
          game,
          visit: ref.read(liveVisitProvider),
          playerName: _playerName(game.playerId),
        );
      }
    }
    final live = ref.read(liveViewMirrorProvider).value;
    if (live != null && live.listening && !live.ended) {
      return ScreenSnapshot.live(l10n, live, playerName: ref.read(activePlayerProvider)?.name);
    }
    return ScreenState.idle;
  }

  String? _playerName(int id) {
    final players = _ref.read(playersProvider).value ?? const [];
    return players.where((p) => p.id == id).firstOrNull?.name;
  }

  /// Turnierspiele heißen `<Turnier>/r<Runde>-m<Spiel>`.
  static String? _round(AppLocalizations l10n, String? tournamentMatch) {
    if (tournamentMatch == null) return null;
    final round = RegExp(r'/r(\d+)-').firstMatch(tournamentMatch)?.group(1);
    return round == null ? null : l10n.tourRoundName(int.parse(round));
  }
}

final screenFeedProvider = Provider<ScreenFeed>((ref) {
  final feed = ScreenFeed(ref);
  ref.onDispose(feed.detach);
  return feed;
});
