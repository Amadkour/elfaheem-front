// The path the web app is served under: the document's `<base href>` path (`/app/` for the build made with
// `--base-href /app/`, `/` at a site root). Everywhere but the web it is `/`. Conditional import: the web side
// reads `document.baseURI` through package:web. Always starts and ends with a slash.
export 'web_base_path_stub.dart' if (dart.library.js_interop) 'web_base_path_web.dart';
