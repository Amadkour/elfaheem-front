// lib/core/offline/downloads_availability.dart — where the Downloads page exists.
//
// Offline downloads (encrypted videos in OfflineVideoService, the cached attendance courses, offline exam
// sittings) are files on the device, so the Downloads page is a phone / desktop app page only. On the web there is
// no such page: every entry point checks [kDownloadsAvailable] (the profile tile, the video player's download
// button, the material tiles' badge, the offline shortcut), and the links that could still name it (`/downloads` typed
// in the address bar, an ad, a notification module, an assistant answer's deep link) are caught with
// [isDownloadsLink] — the route sends the person home instead.
library;

import 'package:flutter/foundation.dart' show kIsWeb;

/// True where the Downloads page and offline downloads exist (not on the web).
const bool kDownloadsAvailable = !kIsWeb;

/// Whether [link] (a route `/downloads?x=1`, a module `downloads`) names the Downloads page.
bool isDownloadsLink(String? link) {
  var s = (link ?? '').trim();
  final q = s.indexOf(RegExp(r'[?#]'));
  if (q >= 0) s = s.substring(0, q);
  while (s.startsWith('/')) {
    s = s.substring(1);
  }
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s == 'downloads';
}

/// A link the app may open here: false for the Downloads page on the web.
bool linkAvailableHere(String? link, {bool downloadsAvailable = kDownloadsAvailable}) =>
    downloadsAvailable || !isDownloadsLink(link);
