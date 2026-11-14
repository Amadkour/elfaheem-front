import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// Release signing (Phase 9, D-026): android/key.properties (git-ignored) or the environment
// (ANDROID_KEYSTORE_PATH / _PASSWORD / ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD, for CI). Without either, a release
// build is REFUSED (S13): the release tasks fail before anything is built, so no debug-signed release can be
// produced and published by mistake. A local test of a release build on purpose passes `-PallowDebugSigning=true`
// (`flutter build apk --release --android-project-arg allowDebugSigning=true`); debug / profile builds are untouched.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun signingValue(prop: String, env: String): String? = keyProps.getProperty(prop) ?: System.getenv(env)
val releaseStoreFile = signingValue("storeFile", "ANDROID_KEYSTORE_PATH")
val allowDebugSigning = project.findProperty("allowDebugSigning")?.toString()?.let { it != "false" } ?: false

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
    namespace = "com.doubley.nextbrain"
    compileSdk = 37 // permission_handler_android 14 needs API 37 (AGP 9.1.1 supports it)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.doubley.nextbrain"
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
            // Configuration runs for EVERY build (debug too), so it never throws here: the refusal is on the release
            // tasks below. The debug config is only reached with -PallowDebugSigning=true.
            signingConfig = if (releaseStoreFile != null) signingConfigs.getByName("release") else {
                if (System.getenv("CI") != null) throw GradleException("release build in CI without a keystore (ANDROID_KEYSTORE_PATH)")
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

// S13: a release variant without a keystore stops at its first task (preReleaseBuild) and again at packaging,
// unless -PallowDebugSigning=true says the debug-signed artifact is wanted (and will not be published).
if (releaseStoreFile == null) {
    val refusal = "no release keystore (android/key.properties or ANDROID_KEYSTORE_PATH): a release build would be " +
        "signed with the DEBUG key. Configure the keystore, or pass -PallowDebugSigning=true for a local test build " +
        "that is never published."
    if (allowDebugSigning) {
        logger.warn("WARNING: -PallowDebugSigning=true — release builds are signed with the DEBUG key, do not publish them")
    } else {
        tasks.matching { it.name in setOf("preReleaseBuild", "packageRelease", "packageReleaseBundle", "signReleaseBundle") }
            .configureEach { doFirst { throw GradleException(refusal) } }
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