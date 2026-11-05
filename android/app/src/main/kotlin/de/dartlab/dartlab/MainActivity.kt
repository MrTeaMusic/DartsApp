package de.dartlab.dartlab

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Nimmt `.dartlab`-Dateien an (Öffnen mit …, Teilen). WhatsApp & Co. geben
/// nur einen content://-Link, deshalb liest die Activity die Datei selbst und
/// schickt die Bytes an Flutter. Dateien, die vor dem Start der Dart-Seite
/// ankommen, werden gemerkt und bei `ready` ausgeliefert.
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var dartReady = false
    private val pending = mutableListOf<Map<String, Any>>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "de.dartlab/open_file")
        ch.setMethodCallHandler { call, result ->
            if (call.method == "ready") {
                dartReady = true
                result.success(ArrayList(pending))
                pending.clear()
            } else {
                result.notImplemented()
            }
        }
        channel = ch
        handle(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent?) {
        if (intent == null) return
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        }
        if (uri == null) return
        val bytes = try {
            contentResolver.openInputStream(uri)?.use { it.readBytes() }
        } catch (e: Exception) {
            null
        } ?: return
        // Dasselbe Intent nicht noch einmal verarbeiten (Drehen, Zurückkehren).
        intent.action = null
        val payload = mapOf<String, Any>("bytes" to bytes)
        if (dartReady) channel?.invokeMethod("open", payload) else pending.add(payload)
    }
}
