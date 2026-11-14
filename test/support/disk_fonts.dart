// test/support/disk_fonts.dart — the export font catalog reads its files from disk in plain tests (rootBundle needs
// a binding). Call useDiskFonts() in main() / setUpAll.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_education_app/design/export/export_fonts.dart';

void useDiskFonts() {
  ExportFonts.loader = (asset) async => ByteData.sublistView(File(asset).readAsBytesSync());
}
