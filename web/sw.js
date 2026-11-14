// web/sw.js — Alfaheem's own service worker, registered by web/flutter_bootstrap.js at scope "/".
//
// Why it exists: a worker that handles navigations keeps the site installable on every Chrome / Edge version,
// and an installed app should show a branded "you're offline" page instead of the browser's error page.
//
// Why it does so little (on purpose):
//   - It intercepts ONLY top-level navigations (request.mode === 'navigate'), network first, and falls
//     back to the cached offline.html only when the network fails. Every other request (main.dart.js,
//     canvaskit, assets, /api, /releases/*, video, LiveKit, Firebase) is not touched, so a deploy is
//     picked up on the next load exactly as before and nothing stale can be served.
//   - It precaches offline.html alone (its logo is inline), under a versioned cache name; bump
//     CACHE_VERSION when offline.html changes. Old caches of ours (prefix "nb-offline-") are deleted on
//     activate; other caches are left alone.
//   - It coexists with web/firebase-messaging-sw.js, which lives at its own scope
//     (/firebase-cloud-messaging-push-scope) and handles push; this worker has no push handler.
//   - Flutter's flutter_service_worker.js is NOT used (the bootstrap passes no serviceWorkerSettings):
//     in Flutter 3.47 it is a cleanup worker that unregisters the registration at "/". Registering this
//     file at "/" replaces an old Flutter worker left over from earlier builds.
'use strict';

const CACHE_VERSION = 'v1';
const CACHE_PREFIX = 'nb-offline-';
const CACHE_NAME = CACHE_PREFIX + CACHE_VERSION;
const OFFLINE_URL = 'offline.html';
// offline.html carries its logo inline: the worker serves nothing but this one file.
const PRECACHE = [OFFLINE_URL];

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE_NAME);
      // cache: 'reload' skips the HTTP cache so a new version never stores an old copy.
      await cache.addAll(PRECACHE.map((u) => new Request(u, { cache: 'reload' })));
      await self.skipWaiting();
    })()
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys
          .filter((k) => k.startsWith(CACHE_PREFIX) && k !== CACHE_NAME)
          .map((k) => caches.delete(k))
      );
      if (self.registration.navigationPreload) {
        try {
          await self.registration.navigationPreload.enable();
        } catch (e) {
          // Not supported here: the plain fetch below is used.
        }
      }
      await self.clients.claim();
    })()
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  // Navigations only. Returning without respondWith lets the browser handle the request normally.
  if (request.mode !== 'navigate' || request.method !== 'GET') return;
  // downloads (APKs, desktop packages, stored files) and the API go straight to the network, never through this worker
  const path = new URL(request.url).pathname;
  if (path.startsWith('/releases/') || path.startsWith('/api/') || path.startsWith('/storage/')) return;
  event.respondWith(
    (async () => {
      try {
        const preloaded = await event.preloadResponse;
        if (preloaded) return preloaded;
        return await fetch(request);
      } catch (e) {
        const cache = await caches.open(CACHE_NAME);
        const offline = await cache.match(OFFLINE_URL);
        return offline || Response.error();
      }
    })()
  );
});
