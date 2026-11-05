import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  // Kaltstart: Die App wurde mit einer Datei gestartet („Öffnen mit …“, AirDrop).
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for context in connectionOptions.urlContexts where context.url.isFileURL {
      OpenFileBridge.shared.open(context.url)
    }
  }

  // Die App läuft schon und bekommt eine Datei.
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    for context in URLContexts where context.url.isFileURL {
      OpenFileBridge.shared.open(context.url)
    }
  }
}
