// lib/features/data_lab/data_lab_saver_web.dart
// Saving an exported file on the web: a real browser download (the share sheet of a desktop browser often offers
// only "Copy"). Picked by a conditional import in data_lab_api.dart.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';
import 'package:web/web.dart' as web;

bool get dlCanSaveDirectly => true;

/// Starts the browser download. Returns the file name.
Future<String?> dlSaveBytes(Uint8List bytes, String name, String mime) async {
  final blob = web.Blob(<JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = name;
  a.style.display = 'none';
  web.document.body?.append(a);
  a.click();
  a.remove();
  Future.delayed(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  return name;
}

Future<void> dlShareBytes(Uint8List bytes, String name, String mime) async {
  await SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, name: name, mimeType: mime)]));
}

Future<void> dlRevealFile(String path) async {}

Future<void> dlOpenFile(String path) async {}
