{{flutter_js}}
{{flutter_build_config}}

// Flutter's own loader, deliberately WITHOUT serviceWorkerSettings: since 3.x the generated
// flutter_service_worker.js is only a cleanup worker that unregisters whatever owns scope "/".
_flutter.loader.load();

// The app's own worker (web/sw.js): an offline fallback page for navigations, nothing else.
// It is what makes the site installable as an app; it never caches app code, API calls or media.
// Registered after the page has loaded so it never competes with the app's first download.
(function () {
  try {
    if (!('serviceWorker' in navigator)) return;
    var register = function () {
      try {
        navigator.serviceWorker.register('sw.js', { scope: './' }).catch(function (e) {
          console.warn('[pwa] service worker registration failed', e);
        });
      } catch (e) {
        console.warn('[pwa] service worker registration failed', e);
      }
    };
    if (document.readyState === 'complete') {
      register();
    } else {
      window.addEventListener('load', register, { once: true });
    }
  } catch (e) {
    console.warn('[pwa] service worker unavailable', e);
  }
})();
