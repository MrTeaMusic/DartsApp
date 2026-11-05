import Flutter
import UIKit

/// Gibt `.dartlab`-Dateien (geteilte Matches) an Flutter weiter. Dateien, die
/// vor dem Start der Dart-Seite ankommen (Kaltstart per „Öffnen mit …“),
/// werden gemerkt und bei `ready` ausgeliefert.
final class OpenFileBridge {
  static let shared = OpenFileBridge()
  private var channel: FlutterMethodChannel?
  private var dartReady = false
  private var pending: [[String: Any]] = []

  func attach(messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "de.dartlab/open_file", binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      if call.method == "ready" {
        self.dartReady = true
        result(self.pending)
        self.pending.removeAll()
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    channel = ch
  }

  func open(_ url: URL) {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let data = try? Data(contentsOf: url) else { return }
    let payload: [String: Any] = ["bytes": FlutterStandardTypedData(bytes: data)]
    if dartReady {
      channel?.invokeMethod("open", arguments: payload)
    } else {
      pending.append(payload)
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    OpenFileBridge.shared.attach(messenger: engineBridge.applicationRegistrar.messenger())
  }
}
