// lib/core/tz_database_web.dart — web: `package:timezone/data/latest.dart` embeds every zone as a base64 string
// (about 840 KB of main.dart.js that every visitor parses before the first frame). The same data ships as an
// asset (assets/tz/latest.tzf, byte-identical to the package's lib/data/latest.tzf) and is read on first use, so
// the dates it serves are the same ones; only the download moved out of the script.
import 'package:flutter/services.dart' show rootBundle;
import 'package:timezone/timezone.dart' as tz;

const bool kTzDataIsAsync = true;

void tzInitSync() {}

Future<void> tzInitAsync() async {
  final d = await rootBundle.load('assets/tz/latest.tzf');
  tz.initializeDatabase(d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes));
}
