// web/firebase-messaging-sw.js
//
// Required for Firebase Cloud Messaging to work on the web platform.
// Must live at exactly this path: web/firebase-messaging-sw.js
// (Firebase's JS SDK looks for it there by default — do not rename or move it.)
//
// Notes:
//   - Web Push only works over HTTPS or http://localhost. It will silently
//     fail on plain HTTP hosting.
//   - The config below matches lib/firebase_options.dart (DefaultFirebaseOptions.web, project alfaheem-d3c8f, A-006).
//     If you ever rotate/regenerate Firebase config, update both places together.

importScripts("https://www.gstatic.com/firebasejs/10.13.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.13.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyDUAAYG9xBIOsL0WAY-Or4iPXAuug1ZZ60",
  appId: "1:887854198161:web:27ee2572fb6035000afe30",
  messagingSenderId: "887854198161",
  projectId: "alfaheem-d3c8f",
  authDomain: "alfaheem-d3c8f.firebaseapp.com",
  storageBucket: "alfaheem-d3c8f.firebasestorage.app",
});

const messaging = firebase.messaging();

// Handles messages that arrive while the site/tab is NOT focused (or closed).
// Foreground messages (tab open & focused) are instead handled in Dart via
// FirebaseMessaging.onMessage in notification_service.dart.
//
// To view these logs: open DevTools → Application tab → Service Workers,
// or DevTools → Console with "Show messages from other contexts" enabled —
// a background/inactive tab's default console view will NOT show them.
messaging.onBackgroundMessage((payload) => {
  console.log("[FCM][background]", {
    title: payload.notification?.title,
    body: payload.notification?.body,
    data: payload.data,
  });

  // Every open tab gets the data (a hidden tab has no onMessage and no live stream):
  // notification_service.dart listens for this message and feeds it to LiveEvents.
  const data = payload.data || {};
  self.clients
    .matchAll({ type: "window", includeUncontrolled: true })
    .then((clients) => {
      for (const client of clients) client.postMessage({ source: "fcm", data });
    })
    .catch((e) => console.log("[FCM][background] postMessage failed", e));

  // A data-only push (silent event) shows nothing.
  if (!payload.notification) return;

  const title = payload.notification.title || "Alfaheem";
  const body = payload.notification.body || "";

  self.registration.showNotification(title, {
    body,
    icon: "/icons/Icon-192.png", // adjust path if your web icons live elsewhere
    data,
  });
});
