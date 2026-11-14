/* web/video_protection.js
 *
 * Removes the browser's "Save video as…" / download affordances from every
 * <video> element Flutter's video_player creates on web.
 *
 * Load it in web/index.html <head>, BEFORE flutter_bootstrap.js / main.dart.js:
 *   <script src="video_protection.js"></script>
 */
(function () {
  'use strict';

  function protect(v) {
    try {
      v.setAttribute('controlsList', 'nodownload noplaybackrate noremoteplayback');
      v.setAttribute('disablePictureInPicture', '');
      v.setAttribute('disableRemotePlayback', '');
      v.setAttribute('draggable', 'false');
      v.disablePictureInPicture = true;
      v.disableRemotePlayback = true;
      v.draggable = false;
      // Let Flutter's own gesture zones (tap / double-tap / long-press) get
      // the pointer events instead of the native <video>, so the browser's
      // video context menu never has a target.
      v.style.pointerEvents = 'none';
      v.addEventListener('contextmenu', function (e) {
        e.preventDefault();
        e.stopPropagation();
      });
    } catch (e) { /* never break the app */ }
  }

  // video_player_web creates its element with document.createElement('video').
  var origCreate = Document.prototype.createElement;
  Document.prototype.createElement = function (tag, options) {
    var el = origCreate.call(this, tag, options);
    if (typeof tag === 'string' && tag.toLowerCase() === 'video') protect(el);
    return el;
  };

  // Belt and braces: block the context menu / drag on anything that is, or
  // sits on top of, a video (events cross shadow roots via composedPath).
  var BLOCK = { 'VIDEO': 1, 'FLT-PLATFORM-VIEW': 1, 'FLT-PLATFORM-VIEW-SLOT': 1 };
  function onVideoEvent(e) {
    var path = e.composedPath ? e.composedPath() : [];
    for (var i = 0; i < path.length; i++) {
      var n = path[i];
      if (n && n.tagName && BLOCK[n.tagName]) {
        e.preventDefault();
        return;
      }
    }
  }
  document.addEventListener('contextmenu', onVideoEvent, true);
  document.addEventListener('dragstart', onVideoEvent, true);
})();
