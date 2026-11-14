import 'package:web/web.dart' as web;

/// The path of the document's `<base href>`, normalised to start and end with `/`.
String get webBasePath {
  try {
    var p = Uri.parse(web.document.baseURI).path;
    if (!p.startsWith('/')) p = '/$p';
    if (!p.endsWith('/')) p = '$p/';
    return p;
  } catch (_) {
    return '/';
  }
}
