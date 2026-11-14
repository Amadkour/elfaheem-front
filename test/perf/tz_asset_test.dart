// The web build reads the timezone data from assets/tz/latest.tzf instead of compiling `data/latest.dart` into
// main.dart.js (lib/core/tz_database_web.dart). The asset must stay byte-identical to the package's file: after a
// `timezone` upgrade copy lib/data/latest.tzf over it. Also: the asset builds the same database as the compiled-in one.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

File _packageTzf() {
  final cfg = jsonDecode(File('.dart_tool/package_config.json').readAsStringSync()) as Map<String, dynamic>;
  final p = (cfg['packages'] as List).firstWhere((e) => e['name'] == 'timezone') as Map<String, dynamic>;
  var rootUri = p['rootUri'] as String;
  if (!rootUri.endsWith('/')) rootUri += '/'; // so resolve() keeps the package folder
  final root = Uri.parse(rootUri);
  final base = root.isAbsolute ? root : Directory('.dart_tool').uri.resolveUri(root);
  return File.fromUri(base.resolve('lib/data/latest.tzf'));
}

void main() {
  test('assets/tz/latest.tzf is the package latest.tzf', () {
    expect(File('assets/tz/latest.tzf').readAsBytesSync(), _packageTzf().readAsBytesSync());
  });

  test('the asset bytes build the same database as the compiled-in one', () {
    bool known(String z) {
      try {
        tz.getLocation(z);
        return true;
      } catch (_) {
        return false;
      }
    }

    tzdata.initializeTimeZones();
    final compiled = {for (final z in AppTime.zones) z.id: known(z.id)};
    final cairo = tz.getLocation('Africa/Cairo').zones.length;
    tz.initializeDatabase(File('assets/tz/latest.tzf').readAsBytesSync());
    expect({for (final z in AppTime.zones) z.id: known(z.id)}, compiled);
    expect(tz.getLocation('Africa/Cairo').zones.length, cairo);
    expect(compiled['Africa/Cairo'], isTrue);
  });
}
