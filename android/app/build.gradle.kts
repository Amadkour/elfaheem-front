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
        // One-ABI APKs for direct downloads (D-137, scripts/release/publish_release.py): `--target-platform
        // android-arm64` limits Flutter's own libraries only, and the Flutter plugin resets abiFilters to every ABI,
        // so the plugins' native libraries (WebRTC, ML Kit) came along for all three. With
        // `-P disable-abi-filtering=true` the Flutter plugin leaves abiFilters alone and they follow --target-platform.
        // Every other build (flutter run, appbundle, a plain apk) is unchanged.
        if (project.findProperty("disable-abi-filtering")?.toString() == "true") {
            val abiOf = mapOf("android-arm" to "armeabi-v7a", "android-arm64" to "arm64-v8a", "android-x64" to "x86_64")
            val abis = (project.findProperty("target-platform") as String?)?.split(",")?.mapNotNull { abiOf[it.trim()] }
            ndk { abiFilters += (if (abis.isNullOrEmpty()) abiOf.values.toList() else abis) }
        }
    }

    // Native libraries are stored COMPRESSED in the APK (direct downloads, D-137): the APKs are fetched from our own
    // site, often on mobile data, and the .so files (Flutter, the app, WebRTC, ML Kit) shrink by more than half. The
    // cost is that Android extracts them once at install (a little more storage). A Play App Bundle is unaffected:
    // Play builds its own splits.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
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