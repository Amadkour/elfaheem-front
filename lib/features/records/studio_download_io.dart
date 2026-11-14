// lib/features/records/studio_download_io.dart — the Studio's "Download" on phones and desktops (D-596): the
// file is streamed to a temporary file (with progress), then put where people look for it — Android and desktops:
// the Downloads folder; iPhone / iPad: the share sheet (Save Video, Files, AirDrop). A plain file save, not the
// encrypted in-app downloads of courses. Picked by a conditional import in studio_download.dart.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_saver/file_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Downloads [url] and saves it as [fileName]. Returns where it went (a path / a name), null when cancelled.
Future<String?> studioSaveUrl(String url, String fileName, {void Function(double)? onProgress}) async {
  final dir = await getTemporaryDirectory();
  final safe = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ');
  final path = '${dir.path}${Platform.pathSeparator}$safe';
  await Dio().download(url, path, onReceiveProgress: (done, total) {
    if (total > 0) onProgress?.call(done / total);
  });
  final dot = safe.lastIndexOf('.');
  final name = dot > 0 ? safe.substring(0, dot) : safe;
  final ext = dot > 0 ? safe.substring(dot + 1) : 'mp4';
  if (Platform.isIOS) {
    await SharePlus.instance.share(ShareParams(files: [XFile(path, mimeType: ext == 'm4a' ? 'audio/mp4' : 'video/mp4')]));
    return safe;
  }
  final out = await FileSaver.instance.saveToDownloads(
    name: name,
    filePath: path,
    fileExtension: ext,
    mimeType: MimeType.custom,
    customMimeType: ext == 'm4a' ? 'audio/mp4' : 'video/mp4',
  );
  try {
    await File(path).delete();
  } catch (_) {/* the temp folder is cleaned by the system anyway */}
  return out ?? safe;
}
