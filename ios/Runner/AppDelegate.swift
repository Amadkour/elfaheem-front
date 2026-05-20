import Flutter
import UIKit
import Firebase                    // ← NEW: imports FirebaseCore, Crashlytics, Messaging

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // ── Firebase ─────────────────────────────────────────────────────────────
    // Must be called BEFORE any other Firebase service.
    FirebaseApp.configure()        // ← NEW

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // ── APNs token forwarding to FCM ──────────────────────────────────────────
  // Required for FCM on iOS — forwards APNs device token to Firebase.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken  // ← NEW
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }
}
