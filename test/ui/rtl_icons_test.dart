// Arabic (RTL) icon direction guard, by reading lib/:
//
//  * arrow_back / forward, chevron_left / right, arrow_*_ios, navigate_*, keyboard_backspace … mirror by
//    themselves (IconData.matchTextDirection). Picking one of them by language / direction flips it TWICE.
//  * logout / login / exit_to_app / subdirectory_arrow_* / north_east / arrow_outward and Cupertino's
//    chevron_forward / chevron_back do NOT mirror: use DirIcons (lib/design/app_icons.dart) or
//    CupertinoIcons.back / forward.
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_icons.dart';
import 'package:flutter_test/flutter_test.dart';

const _selfMirroring = r'(arrow_back|arrow_forward|arrow_back_ios|arrow_back_ios_new|arrow_forward_ios|chevron_left|'
    r'chevron_right|navigate_before|navigate_next|first_page|last_page|keyboard_backspace|arrow_left|arrow_right|'
    r'arrow_right_alt|send|reply|undo|redo|open_in_new|launch)(_rounded|_outlined|_sharp)?';

final _doubleFlip = RegExp(
    r'(rtl|isAr|lang|Directionality|TextDirection)[^;?\n]{0,80}\?\s*(?:const\s+)?(?:Icon\()?Icons\.' + _selfMirroring +
        r'\b[^:;]{0,60}:\s*(?:const\s+)?(?:Icon\()?Icons\.' + _selfMirroring + r'\b');

final _notMirroring = RegExp(r'\b(Icons\.(logout|login|exit_to_app|subdirectory_arrow_left|subdirectory_arrow_right|north_east|'
    r'arrow_outward)(_rounded|_outlined|_sharp)?|CupertinoIcons\.(chevron_forward|chevron_back))\b');

void main() {
  test('the DirIcons glyphs mirror and match their Material originals', () {
    for (final (dir, original) in [
      (DirIcons.logout, Icons.logout_rounded),
      (DirIcons.login, Icons.login_rounded),
      (DirIcons.exitToApp, Icons.exit_to_app_rounded),
      (DirIcons.subArrowLeft, Icons.subdirectory_arrow_left_rounded),
      (DirIcons.subArrowRight, Icons.subdirectory_arrow_right_rounded),
      (DirIcons.northEast, Icons.north_east_rounded),
      (DirIcons.arrowOutward, Icons.arrow_outward_rounded),
    ]) {
      expect(dir.matchTextDirection, isTrue);
      expect(dir.codePoint, original.codePoint);
      expect(dir.fontFamily, original.fontFamily);
    }
    expect(CupertinoIcons.forward.matchTextDirection, isTrue);
    expect(CupertinoIcons.back.matchTextDirection, isTrue);
  });

  test('no icon in lib/ points the wrong way in Arabic', () {
    final problems = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final s = f.readAsStringSync();
      final path = f.path.replaceAll(r'\', '/');
      int line(int offset) => '\n'.allMatches(s.substring(0, offset)).length + 1;
      for (final m in _doubleFlip.allMatches(s)) {
        problems.add('$path:${line(m.start)} picks a self-mirroring icon by direction (flips twice): ${m.group(0)!.split('\n').first}');
      }
      if (path.endsWith('design/app_icons.dart')) continue;
      for (final m in _notMirroring.allMatches(s)) {
        problems.add('$path:${line(m.start)} ${m.group(0)} does not mirror in Arabic: use DirIcons / CupertinoIcons.back|forward');
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
