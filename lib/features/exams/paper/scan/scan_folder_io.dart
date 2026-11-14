// "Folder" on the app (scan_sources.dart): a document scanner's output folder, every file under it.
//   • Windows / macOS / Linux: the system folder dialog (file_picker getDirectoryPath → a path), then dart:io walks it.
//   • Android: a path is no use (scoped storage hides another app's PDFs from dart:io), so the folder goes through
//     the Storage Access Framework on the app's own channel (android/…/ScanFolderChannel.kt): the system picker grants
//     read access to the tree, which is listed and read through DocumentsContract — no storage permission.
//   • iOS: no folder access for an app's upload; the sheet offers Files instead (scan_sources.dart).
// The web build uses scan_folder_web.dart instead.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import 'package:flutter_education_app/features/exams/paper/scan/scan_files.dart';

const _channel = MethodChannel('com.doubley.alfaheem/scan_folder');

/// A folder that was picked: its name and its files (not read yet).
typedef ScanFolder = ({String name, List<ScanSourceFile> files});

/// Thrown when the folder could not be opened or listed (the reason is shown, the sheet stays usable).
class ScanFolderError implements Exception {
  const ScanFolderError(this.code);
  final String code;
}

/// Whether this build can pick a folder at all.
bool get scanFolderSupported => Platform.isAndroid || Platform.isWindows || Platform.isMacOS || Platform.isLinux;

Future<ScanFolder?> pickScanFolder({String? title}) async {
  if (Platform.isAndroid) return _android();
  final dir = await FilePicker.getDirectoryPath(dialogTitle: title);
  if (dir == null) return null;
  return listScanFolder(Directory(dir));
}

/// Every file under [root] (sub-folders included, links not followed), with its path relative to [root] (`/`
/// separators). At most [kScanMaxPick] + 1 files are listed: one more than the limit is enough to say "too many".
Future<ScanFolder> listScanFolder(Directory root) async {
  final base = root.absolute.path;
  final sep = Platform.pathSeparator;
  final name = base.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).lastOrNull ?? base;
  final files = <ScanSourceFile>[];
  try {
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      var rel = e.absolute.path;
      if (rel.startsWith(base)) rel = rel.substring(base.length);
      while (rel.startsWith(sep) || rel.startsWith('/')) {
        rel = rel.substring(1);
      }
      rel = rel.replaceAll('\\', '/');
      int? size;
      try {
        size = await e.length();
      } catch (_) {}
      files.add(ScanSourceFile(name: rel.split('/').last, path: rel, size: size, read: e.readAsBytes));
      if (files.length > kScanMaxPick) break;
    }
  } on FileSystemException {
    if (files.isEmpty) throw const ScanFolderError('list');
  }
  return (name: name, files: files);
}

Future<ScanFolder?> _android() async {
  try {
    final tree = await _channel.invokeMapMethod<String, Object?>('pickTree');
    if (tree == null) return null;
    final uri = '${tree['uri']}';
    final rows = await _channel.invokeListMethod<Object?>('list', {'uri': uri}) ?? const [];
    final files = <ScanSourceFile>[];
    for (final r in rows) {
      if (r is! Map) continue;
      final doc = '${r['uri']}';
      final size = r['size'];
      files.add(ScanSourceFile(
        name: '${r['name']}',
        path: '${r['path']}',
        size: size is int ? size : null,
        read: () async {
          final b = await _channel.invokeMethod<Uint8List>('read', {'uri': doc});
          if (b == null) throw const ScanPrepareError('read');
          return b;
        },
      ));
    }
    return (name: '${tree['name'] ?? ''}', files: files);
  } on MissingPluginException {
    throw const ScanFolderError('unsupported');
  } on PlatformException {
    throw const ScanFolderError('list');
  }
}
