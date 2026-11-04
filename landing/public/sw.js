// Cleanup service worker. Browsers that registered the app's old root-scope /sw.js (before the Flutter
// app moved to /app/) fetch this file on their next update check: it removes itself and its caches.
// No fetch handler and no client reload on purpose. The landing never registers a service worker.
self.addEventListener('install', () => {
  self.skipWaiting();
});
self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      try {
        const keys = await caches.keys();
        await Promise.all(keys.filter((k) => k.startsWith('nb-offline-')).map((k) => caches.delete(k)));
      } catch (e) {
        /* nothing to clean */
      }
      await self.registration.unregister();
    })(),
  );
});
