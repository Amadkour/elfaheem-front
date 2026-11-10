// lib/features/shared/records/studio_download_web.dart — the Studio's "Download" on the web (D-596): the browser
// downloads the server's link itself (the response says `Content-Disposition: attachment` with the file's name), so a
// large video is never held in memory. Picked by a conditional import in studio_download.dart.
library;

import 'package:web/web.dart' as web;

/// Starts the browser download. [onProgress] is not called: the browser shows its own.
Future<String?> studioSaveUrl(String url, String fileName, {void Function(double)? onProgress}) async {
  final a = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName
    ..rel = 'noopener';
  a.style.display = 'none';
  web.document.body?.append(a);
  a.click();
  a.remove();
  return fileName;
}
