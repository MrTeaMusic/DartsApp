import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

bool get _isDesktop => switch (defaultTargetPlatform) {
      TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux => !kIsWeb,
      _ => false,
    };

/// Plattform-Zugriff, in Tests austauschbar.
abstract class FullscreenPlatform {
  Future<void> set(bool fullscreen);
  Future<bool> get current;
}

class NativeFullscreen implements FullscreenPlatform {
  const NativeFullscreen();

  @override
  Future<void> set(bool fullscreen) async {
    if (_isDesktop) {
      await windowManager.setFullScreen(fullscreen);
    } else {
      // iPhone/iPad: Statusleiste und Home-Indikator ausblenden.
      await SystemChrome.setEnabledSystemUIMode(fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    }
  }

  @override
  Future<bool> get current async => _isDesktop ? windowManager.isFullScreen() : false;
}

/// Vor `runApp` aufrufen (nur Desktop nötig).
Future<void> initFullscreenSupport() async {
  if (_isDesktop) await windowManager.ensureInitialized();
}

final fullscreenPlatformProvider = Provider<FullscreenPlatform>((ref) => const NativeFullscreen());

/// Vollbild an/aus. F11 schaltet um, Esc beendet.
class FullscreenController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> set(bool value) async {
    if (value == state) return;
    state = value;
    try {
      await ref.read(fullscreenPlatformProvider).set(value);
    } on Exception catch (e) {
      debugPrint('Vollbild nicht möglich: $e');
      state = !value;
    }
  }

  Future<void> toggle() => set(!state);
}

final fullscreenProvider = NotifierProvider<FullscreenController, bool>(FullscreenController.new);
