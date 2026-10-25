import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// Release signing (Phase 9, D-026): android/key.properties (git-ignored) or the environment
// (ANDROID_KEYSTORE_PATH / _PASSWORD / ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD, for CI). Without either, release
// builds fall back to the debug key and say so — such a build must never be published.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun signingValue(prop: String, env: String): String? = keyProps.getProperty(prop) ?: System.getenv(env)
val releaseStoreFile = signingValue("storeFile", "ANDROID_KEYSTORE_PATH")

plugins {
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("com.android.application")
    // AGP 9 built-in Kotlin is switched OFF (android.builtInKotlin=false) because
    // several plugins (floating, ...) still apply kotlin-android themselves.
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.firebase.crashlytics")          // ← NEW: Crashlytics
}
android {
    namespace = "com.example.flutter_education_app"
    compileSdk = 37 // permission_handler_android 14 needs API 37 (AGP 9.1.1 supports it)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.example.flutter_education_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseStoreFile != null) {
            create("release") {
                storeFile = file(releaseStoreFile)
                storePassword = signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // R8 stays off: LiveKit / WebRTC / screen-recording plugins use reflection and JNI; turning it on needs a
            // device test pass of live sessions first (D-026). Dart code IS obfuscated (scripts/build_release.sh).
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = if (releaseStoreFile != null) signingConfigs.getByName("release") else {
                // in CI a release without a keystore is an error, never a silently debug-signed artifact
                if (System.getenv("CI") != null) throw GradleException("release build in CI without a keystore (ANDROID_KEYSTORE_PATH)")
                logger.warn("WARNING: no release keystore (android/key.properties or ANDROID_KEYSTORE_PATH) — release build signed with the DEBUG key, do not publish it")
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                    getDefaultProguardFile("proguard-android-optimize.txt"),
                    "proguard-rules.pro"
            )

            // ── Crashlytics ───────────────────────────────────────────────────
            // Uploads mapping file so Crashlytics can deobfuscate stack traces.
            // Set to false during development to speed up builds.
            firebaseCrashlytics {
                mappingFileUploadEnabled = true
                nativeSymbolUploadEnabled = false   // enable if you use C/C++ NDK
            }
        }
        debug {
            firebaseCrashlytics {
                mappingFileUploadEnabled = false
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.fromTarget("17")
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.multidex:multidex:2.0.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}