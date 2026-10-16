import org.jetbrains.kotlin.gradle.dsl.JvmTarget

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

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
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