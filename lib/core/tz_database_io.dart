// lib/core/tz_database_io.dart — phone / desktop / tests: the timezone database is compiled into the app
// (package:timezone's `latest` set) and ready synchronously. Web uses tz_database_web.dart instead.
import 'package:timezone/data/latest.dart' as tzdata;

/// True when the data arrives asynchronously (web) and not at once.
const bool kTzDataIsAsync = false;

void tzInitSync() => tzdata.initializeTimeZones();

Future<void> tzInitAsync() async {}
