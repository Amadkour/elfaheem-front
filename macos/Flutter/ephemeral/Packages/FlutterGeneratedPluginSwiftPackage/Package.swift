// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// Generated file. Do not edit.
//

import PackageDescription

let package = Package(
    name: "FlutterGeneratedPluginSwiftPackage",
    platforms: [
        .macOS("10.15")
    ],
    products: [
        .library(name: "FlutterGeneratedPluginSwiftPackage", type: .static, targets: ["FlutterGeneratedPluginSwiftPackage"])
    ],
    dependencies: [
        .package(name: "webview_flutter_wkwebview", path: "../.packages/webview_flutter_wkwebview-3.25.1"),
        .package(name: "wakelock_plus", path: "../.packages/wakelock_plus-1.5.2"),
        .package(name: "package_info_plus", path: "../.packages/package_info_plus-9.0.1"),
        .package(name: "video_player_avfoundation", path: "../.packages/video_player_avfoundation-2.9.7"),
        .package(name: "url_launcher_macos", path: "../.packages/url_launcher_macos-3.2.5"),
        .package(name: "shared_preferences_foundation", path: "../.packages/shared_preferences_foundation-2.5.6"),
        .package(name: "device_info_plus", path: "../.packages/device_info_plus-12.3.0"),
        .package(name: "connectivity_plus", path: "../.packages/connectivity_plus-7.0.0"),
        .package(name: "file_selector_macos", path: "../.packages/file_selector_macos-0.9.5"),
        .package(name: "firebase_remote_config", path: "../.packages/firebase_remote_config-6.5.1"),
        .package(name: "firebase_core", path: "../.packages/firebase_core-4.9.0"),
        .package(name: "firebase_messaging", path: "../.packages/firebase_messaging-16.2.2"),
        .package(name: "firebase_crashlytics", path: "../.packages/firebase_crashlytics-5.2.2"),
        .package(name: "file_picker", path: "../.packages/file_picker-11.0.2"),
        .package(name: "sqflite_darwin", path: "../.packages/sqflite_darwin-2.4.2"),
        .package(name: "FlutterFramework", path: "../.packages/FlutterFramework")
    ],
    targets: [
        .target(
            name: "FlutterGeneratedPluginSwiftPackage",
            dependencies: [
                .product(name: "webview-flutter-wkwebview", package: "webview_flutter_wkwebview"),
                .product(name: "wakelock-plus", package: "wakelock_plus"),
                .product(name: "package-info-plus", package: "package_info_plus"),
                .product(name: "video-player-avfoundation", package: "video_player_avfoundation"),
                .product(name: "url-launcher-macos", package: "url_launcher_macos"),
                .product(name: "shared-preferences-foundation", package: "shared_preferences_foundation"),
                .product(name: "device-info-plus", package: "device_info_plus"),
                .product(name: "connectivity-plus", package: "connectivity_plus"),
                .product(name: "file-selector-macos", package: "file_selector_macos"),
                .product(name: "firebase-remote-config", package: "firebase_remote_config"),
                .product(name: "firebase-core", package: "firebase_core"),
                .product(name: "firebase-messaging", package: "firebase_messaging"),
                .product(name: "firebase-crashlytics", package: "firebase_crashlytics"),
                .product(name: "file-picker", package: "file_picker"),
                .product(name: "sqflite-darwin", package: "sqflite_darwin"),
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
