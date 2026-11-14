// lib/features/data_lab/data_lab_saver_io.dart
// Saving an exported file on Android / iOS / Windows / macOS / Linux (picked by a conditional import in
// data_lab_api.dart; the web uses data_lab_saver_web.dart).
//   desktop → written to the user's Downloads folder (a free name is chosen) and can be shown in the folder
//   phones  → the system share sheet (it holds "Save to Files" / "Save to device", Drive, mail …)
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// true on Windows / macOS / Linux: the file can be written straight to Downloads.
bool get dlCanSaveDirectly => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Saves [bytes]. Returns the full path on desktop, or null when the share sheet was used (phones).
Future<String?> dlSaveBytes(Uint8List bytes, String name, String mime) async {
  if (!dlCanSaveDirectly) {
    await dlShareBytes(bytes, name, mime);
    return null;
  }
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.current.path;
  var dir = Directory('$home${Platform.pathSeparator}Downloads');
  if (!await dir.exists()) dir = Directory(home);
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name, ext = dot > 0 ? name.substring(dot) : '';
  var file = File('${dir.path}${Platform.pathSeparator}$name');
  for (var i = 2; await file.exists(); i++) {
    file = File('${dir.path}${Platform.pathSeparator}$base ($i)$ext');
  }
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// Opens the system share sheet with the file.
Future<void> dlShareBytes(Uint8List bytes, String name, String mime) async {
  await SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, name: name, mimeType: mime)]));
}

/// Shows a saved file in its folder (desktop only).
Future<void> dlRevealFile(String path) async {
  try {
    if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [File(path).parent.path]);
    }
  } catch (_) {}
}

/// Opens a saved file with its default app (desktop only).
Future<void> dlOpenFile(String path) async {
  try {
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [path]);
    }
  } catch (_) {}
}
