import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dart_source/domain/dart_event.dart';
import '../../dart_source/presentation/dart_source_providers.dart';

/// Zustand der laufenden Aufnahme und der zuletzt geworfenen Darts,
/// unabhängig von der Quelle.
@immutable
class LiveVisitState {
  const LiveVisitState({
    this.visit = const [],
    this.history = const [],
    this.takeoutInProgress = false,
    this.lastEventAt,
  });

  /// Darts der aktuellen Aufnahme (0–3).
  final List<DartThrow> visit;

  /// Alle Darts dieser Sitzung, neueste zuletzt (begrenzt).
  final List<DartThrow> history;
  final bool takeoutInProgress;
  final DateTime? lastEventAt;

  int get visitScore => visit.fold(0, (sum, d) => sum + d.score);

  DartThrow? get lastDart => visit.isEmpty ? null : visit.last;

  LiveVisitState copyWith({
    List<DartThrow>? visit,
    List<DartThrow>? history,
    bool? takeoutInProgress,
    DateTime? lastEventAt,
  }) =>
      LiveVisitState(
        visit: visit ?? this.visit,
        history: history ?? this.history,
        takeoutInProgress: takeoutInProgress ?? this.takeoutInProgress,
        lastEventAt: lastEventAt ?? this.lastEventAt,
      );
}

final liveVisitProvider = NotifierProvider<LiveVisitController, LiveVisitState>(LiveVisitController.new);

class LiveVisitController extends Notifier<LiveVisitState> {
  static const int historyLimit = 500;

  @override
  LiveVisitState build() {
    ref.listen(dartEventsProvider, (_, next) {
      final event = next.value;
      if (event != null) apply(event);
    });
    return const LiveVisitState();
  }

  @visibleForTesting
  void apply(DartEvent event) {
    final s = state;
    state = switch (event) {
      DartThrown(:final dart) => s.copyWith(
          visit: [...(s.visit.length >= 3 ? const <DartThrow>[] : s.visit), dart],
          history: _limit([...s.history, dart]),
          takeoutInProgress: false,
          lastEventAt: event.timestamp,
        ),
      DartCorrected(:final index, :final dart) when index < s.visit.length => s.copyWith(
          visit: [...s.visit]..[index] = dart,
          history: _replaceLast(s.history, s.visit[index], dart),
          lastEventAt: event.timestamp,
        ),
      DartCorrected() => s,
      DartUndone() when s.visit.isNotEmpty => s.copyWith(
          visit: s.visit.sublist(0, s.visit.length - 1),
          history: _removeLast(s.history, s.visit.last),
          lastEventAt: event.timestamp,
        ),
      DartUndone() => s,
      TakeoutStarted() => s.copyWith(takeoutInProgress: true, lastEventAt: event.timestamp),
      TakeoutFinished() || TurnReset() => s.copyWith(
          visit: const [],
          takeoutInProgress: false,
          lastEventAt: event.timestamp,
        ),
    };
  }

  void clearHistory() => state = const LiveVisitState();

  static List<DartThrow> _limit(List<DartThrow> list) =>
      list.length > historyLimit ? list.sublist(list.length - historyLimit) : list;

  static List<DartThrow> _replaceLast(List<DartThrow> list, DartThrow old, DartThrow next) {
    final i = list.lastIndexOf(old);
    if (i < 0) return list;
    return [...list]..[i] = next;
  }

  static List<DartThrow> _removeLast(List<DartThrow> list, DartThrow old) {
    final i = list.lastIndexOf(old);
    if (i < 0) return list;
    return [...list]..removeAt(i);
  }
}
