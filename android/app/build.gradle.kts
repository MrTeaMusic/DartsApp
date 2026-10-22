import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release-Signierung: Zuerst android/key.properties (lokal), sonst die
// Umgebungsvariablen ANDROID_KEYSTORE_PATH, ANDROID_KEYSTORE_PASSWORD,
// ANDROID_KEY_ALIAS und ANDROID_KEY_PASSWORD (CI). Ist nichts davon gesetzt,
// wird der Release-Build mit dem Debug-Schlüssel signiert, damit lokale Builds
// laufen. So signierte APKs dürfen nie veröffentlicht werden (siehe
// docs/android-signierung.md).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun signingValue(propertyKey: String, envKey: String): String? =
    keystoreProperties.getProperty(propertyKey)?.takeIf { it.isNotBlank() }
        ?: System.getenv(envKey)?.takeIf { it.isNotBlank() }

val releaseStorePath = signingValue("storeFile", "ANDROID_KEYSTORE_PATH")
val releaseStorePassword = signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
val releaseSigningValues =
    listOf(releaseStorePath, releaseStorePassword, releaseKeyAlias, releaseKeyPassword)
val hasReleaseSigning = releaseSigningValues.all { it != null }

if (!hasReleaseSigning && releaseSigningValues.any { it != null }) {
    // Halb eingerichtet ist fast sicher ein Fehler. Lieber abbrechen, als
    // still mit dem Debug-Schlüssel zu signieren.
    throw GradleException(
        "Release-Signierung unvollständig: storeFile, storePassword, keyAlias und " +
            "keyPassword (key.properties) bzw. ANDROID_KEYSTORE_PATH, " +
            "ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS und ANDROID_KEY_PASSWORD " +
            "müssen alle gesetzt sein."
    )
}

android {
    // Der Namespace bleibt bei de.dartlab.dartlab (Paket von MainActivity). Die
    // installierte App heißt über applicationId de.dartlab.lite.
    namespace = "de.dartlab.dartlab"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "de.dartlab.lite"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // versionCode und versionName kommen von Flutter aus pubspec.yaml bzw.
        // aus --build-number und --build-name.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                logger.lifecycle("DartLab: Release wird mit dem Release-Schlüssel signiert.")
                signingConfig = signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "DartLab: Kein Release-Schlüssel gefunden, Release wird mit dem " +
                        "Debug-Schlüssel signiert (nur für lokale Tests)."
                )
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
