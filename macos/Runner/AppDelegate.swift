import Cocoa
import FlutterMacOS

/// Gibt `.dartlab`-Dateien (geteilte Matches) an Flutter weiter. Dateien, die
/// vor dem Start der Dart-Seite ankommen (Doppelklick im Finder bei
/// geschlossener App), werden gemerkt und bei `ready` ausgeliefert.
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
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = NSApp.windows.compactMap { $0.contentViewController as? FlutterViewController }.first
    if let controller = controller {
      OpenFileBridge.shared.attach(messenger: controller.engine.binaryMessenger)
    }
    super.applicationDidFinishLaunching(notification)
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls where url.isFileURL {
      OpenFileBridge.shared.open(url)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
