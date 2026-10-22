import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/settings/app_settings.dart';
import '../../profiles/data/profile_repository.dart';
import '../../profiles/presentation/active_player.dart';
import '../../sync/data/cloud_api.dart';
import '../../sync/data/cloud_crypto.dart';
import '../../sync/data/cloud_remote.dart';
import '../../sync/data/sync_client.dart';
import '../../sync/data/sync_store.dart';
import '../../sync/domain/sync_role.dart';
import '../../sync/presentation/sync_controller.dart';

enum LiteSetupPhase {
  /// Warten auf Eingaben.
  idle,

  /// Adresse und Tresor werden geprüft.
  checking,

  /// Der erste Abgleich holt die Daten.
  loading,

  /// Gescheitert, siehe [LiteSetupState.failure].
  failed,
}

@immutable
class LiteSetupState {
  const LiteSetupState({this.phase = LiteSetupPhase.idle, this.failure, this.detail});
  final LiteSetupPhase phase;
  final SyncFailure? failure;
  final String? detail;

  bool get busy => phase == LiteSetupPhase.checking || phase == LiteSetupPhase.loading;
}

final liteSetupProvider = NotifierProvider<LiteSetupController, LiteSetupState>(LiteSetupController.new);

/// Richtet die Verbindung zum Cloud-Speicher ein: prüft Adresse und Tresor
/// (es wird nie ein neuer Tresor angelegt), holt mit dem ersten Abgleich alle
/// Daten und speichert erst danach die Einstellungen. Scheitert etwas,
/// bleibt nichts gespeichert und die Einrichtung fragt weiter.
class LiteSetupController extends Notifier<LiteSetupState> {
  @override
  LiteSetupState build() => const LiteSetupState();

  /// `true`, wenn die Verbindung steht und gespeichert ist.
  Future<bool> connect(String urlText, String secretText) async {
    if (state.busy) return false;
    final url = CloudApi.tryParseUrl(urlText);
    final secret = CloudSecret.tryParse(secretText);
    if (url == null || secret == null) return false;
    // Ohne Schrägstrich am Ende speichern.
    final address = '${url.path == '/' ? url.replace(path: '') : url}';
    state = const LiteSetupState(phase: LiteSetupPhase.checking);
    try {
      final keys = await secret.keys();
      final newClient = ref.read(cloudHttpClientProvider);
      final api = CloudApi(address, keys.token, client: newClient());
      try {
        await api.hello();
        if (await CloudRemote(api, keys).vaultExists() == false) throw const SyncException(SyncFailure.noVault);
      } finally {
        api.close();
      }
      state = const LiteSetupState(phase: LiteSetupPhase.loading);
      await _prepareLocalProfile();
      await SyncClient.remote(
        ref.read(syncStoreProvider),
        () => CloudRemote(CloudApi(address, keys.token, client: newClient()), keys),
      ).sync();
      await _selectMainProfile();
      // Erst jetzt speichern: Das öffnet die Statistik, und der laufende
      // Abgleich der App übernimmt von hier an.
      await ref
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(syncRole: SyncRole.cloud, syncCloudUrl: address, syncCloudSecret: secret.text));
      state = const LiteSetupState();
      return true;
    } on SyncException catch (e) {
      state = LiteSetupState(phase: LiteSetupPhase.failed, failure: e.kind, detail: e.detail);
    } on Exception catch (e) {
      state = LiteSetupState(phase: LiteSetupPhase.failed, failure: SyncFailure.server, detail: '$e');
    }
    return false;
  }

  /// Vergisst Fehlermeldungen, sobald wieder getippt wird.
  void clearFailure() {
    if (state.phase == LiteSetupPhase.failed) state = const LiteSetupState();
  }

  /// Die leere Datenbank dieses Geräts hat ein eigenes Profil „Ich“ mit der
  /// festen uid des Hauptprofils. Der Abgleich führt beide zusammen, nimmt
  /// aber nur einen neueren Namen an. Damit Bens Name gewinnt, gilt das leere
  /// Profil als uralt.
  Future<void> _prepareLocalProfile() async {
    final db = ref.read(appDatabaseProvider);
    final count = db.sessions.id.count();
    final sessions = await (db.selectOnly(db.sessions)..addColumns([count])).map((r) => r.read(count) ?? 0).getSingle();
    if (sessions > 0) return;
    await (db.update(db.players)..where((p) => p.uid.equals(defaultPlayerUid) & p.updatedAt.isNull()))
        .write(PlayersCompanion(createdAt: Value(DateTime.utc(2000))));
  }

  /// Gezeigt wird das Standardprofil. Hat es keine einzige Session, hat Ben
  /// seine Daten unter einem anderen Profil: Dann gilt das mit den meisten.
  Future<void> _selectMainProfile() async {
    final db = ref.read(appDatabaseProvider);
    final players = await ref.read(profileRepositoryProvider).players();
    if (players.length < 2) return;
    final count = db.sessions.id.count();
    final rows = await (db.selectOnly(db.sessions)
          ..addColumns([db.sessions.playerId, count])
          ..where(db.sessions.deletedAt.isNull())
          ..groupBy([db.sessions.playerId]))
        .get();
    final sessions = {for (final r in rows) r.read(db.sessions.playerId)!: r.read(count) ?? 0};
    final main = players.where((p) => p.isDefault).firstOrNull ?? players.first;
    if ((sessions[main.id] ?? 0) > 0) return;
    final best = players.fold<Player?>(null, (a, p) => (sessions[p.id] ?? 0) > (a == null ? 0 : sessions[a.id] ?? 0) ? p : a);
    if (best != null) await ref.read(activePlayerIdProvider.notifier).select(best.id);
  }
}
