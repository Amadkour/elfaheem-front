// lib/features/teacher/data_lab/data_lab_saver_web.dart
// Saving an exported file on the web: a real browser download (the share sheet of a desktop browser often offers
// only "Copy"). Picked by a conditional import in data_lab_api.dart.
library;

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

bool get dlCanSaveDirectly => true;

/// Starts the browser download. Returns the file name.
Future<String?> dlSaveBytes(Uint8List bytes, String name, String mime) async {
  final blob = html.Blob([bytes], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final a = html.AnchorElement(href: url)
    ..download = name
    ..style.display = 'none';
  html.document.body?.append(a);
  a.click();
  a.remove();
  Future.delayed(const Duration(seconds: 30), () => html.Url.revokeObjectUrl(url));
  return name;
}

Future<void> dlShareBytes(Uint8List bytes, String name, String mime) async {
  await SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, name: name, mimeType: mime)]));
}

Future<void> dlRevealFile(String path) async {}

Future<void> dlOpenFile(String path) async {}
