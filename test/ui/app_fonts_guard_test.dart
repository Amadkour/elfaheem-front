// The UI font is the person's choice (AppFonts, D-072): no TextStyle in lib/ may name a family by hand.
// Documents keep their own embedded fonts through variables (export designer, certificates, PDF writers), which
// this check does not see.
import 'dart:io';

import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("no hand-written UI font family in lib/ (use AppFonts.family / appText)", () {
    final literal = RegExp(r"fontFamily:\s*'(tajawal|bahji|uiPlexArabic|uiInter|uiEditorial)'");
    final problems = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final s = f.readAsStringSync();
      for (final m in literal.allMatches(s)) {
        problems.add('${f.path}:${'\n'.allMatches(s.substring(0, m.start)).length + 1} ${m.group(0)}');
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('every catalog font file exists and the defaults are pubspec fonts', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final f in AppFonts.catalog) {
      for (final path in f.weights.values) {
        expect(File(path).existsSync(), isTrue, reason: path);
        expect(pubspec.contains(path) || pubspec.contains('${File(path).parent.path.replaceAll(r'\', '/')}/'), isTrue,
            reason: '$path is neither a pubspec font nor in a pubspec asset folder');
      }
      if (f.bundled) expect(pubspec.contains('family: ${f.family}'), isTrue, reason: f.family);
    }
  });
}
