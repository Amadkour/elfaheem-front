// "Folder" on the web (scan_sources.dart; the app build uses scan_folder_io.dart): a hidden
// `<input type=file webkitdirectory multiple>` — Chrome, Edge, Firefox and Safari on a computer hand every file under
// the chosen folder with its `webkitRelativePath` ("Scans/Class A/page2.pdf"). Phones' browsers do not honour it, so
// the sheet does not offer it there. The input is put in the page (WebKit sends no `change` to a detached input) and
// clicked inside the tap. Files are read only when their part is sent (File.arrayBuffer).
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'scan_files.dart';

typedef ScanFolder = ({String name, List<ScanSourceFile> files});

class ScanFolderError implements Exception {
  const ScanFolderError(this.code);
  final String code;
}

bool get scanFolderSupported => true;

Future<ScanFolder?> pickScanFolder({String? title}) {
  final done = Completer<ScanFolder?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = true;
  input.setAttribute('webkitdirectory', '');
  input.setAttribute('directory', '');
  input.style.display = 'none';
  web.document.body?.appendChild(input);

  void finish(ScanFolder? r) {
    input.remove();
    if (!done.isCompleted) done.complete(r);
  }

  input.addEventListener(
      'change',
      ((web.Event _) {
        final list = input.files;
        if (list == null || list.length == 0) {
          finish(null);
          return;
        }
        final files = <ScanSourceFile>[];
        String? folder;
        for (var i = 0; i < list.length && files.length <= kScanMaxPick; i++) {
          final f = list.item(i);
          if (f == null) continue;
          // "Scans/Class A/page2.pdf": the first part is the chosen folder itself
          final rel = f.webkitRelativePath.isEmpty ? f.name : f.webkitRelativePath;
          final parts = rel.split('/');
          folder ??= parts.length > 1 ? parts.first : null;
          final inside = parts.length > 1 ? parts.sublist(1).join('/') : rel;
          files.add(ScanSourceFile(
            name: f.name,
            path: inside,
            size: f.size,
            read: () async => (await f.arrayBuffer().toDart).toDart.asUint8List(),
          ));
        }
        finish((name: folder ?? '', files: files));
      }).toJS);
  input.addEventListener('cancel', ((web.Event _) => finish(null)).toJS);
  input.click();
  return done.future;
}
