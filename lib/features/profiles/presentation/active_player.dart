import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/settings/app_settings.dart';
import '../data/profile_repository.dart';

final playersProvider = StreamProvider<List<Player>>((ref) => ref.watch(profileRepositoryProvider).watchPlayers());

/// Gewähltes Profil (ID), gemerkt in den Einstellungen. `null` = Standard.
class ActivePlayerId extends Notifier<int?> {
  static const _key = 'profile.active';

  @override
  int? build() => ref.watch(sharedPreferencesProvider).getInt(_key);

  Future<void> select(int id) async {
    state = id;
    await ref.read(sharedPreferencesProvider).setInt(_key, id);
  }
}

final activePlayerIdProvider = NotifierProvider<ActivePlayerId, int?>(ActivePlayerId.new);

/// Das aktive Profil. Ist die gemerkte ID ungültig (gelöscht), gilt das
/// Standardprofil.
final activePlayerProvider = Provider<Player?>((ref) {
  final players = ref.watch(playersProvider).value;
  if (players == null || players.isEmpty) return null;
  final id = ref.watch(activePlayerIdProvider);
  return players.where((p) => p.id == id).firstOrNull ??
      players.where((p) => p.isDefault).firstOrNull ??
      players.first;
});
