// A material card's title: the server's "<session> — تسجيل الحصة" recording name reads "Session recording" (N9).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/sessions/material/components/material_title.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });
  tearDownAll(() => translation = {});
  setUp(() => AppConfig.lang = 'ar');

  test('a server recording name drops the session name and the suffix', () {
    expect(materialTitle('نن — تسجيل الحصة', recorded: true), 'تسجيل الحصة');
    expect(materialTitle('مقدمة في البرمجة — تسجيل الحصة (لقاء 2)', recorded: true), 'تسجيل الحصة · لقاء 2');
    AppConfig.lang = 'en';
    expect(materialTitle('Intro — تسجيل الحصة', recorded: true), 'Session recording');
    expect(materialTitle('Intro — تسجيل الحصة (لقاء 3)', recorded: true), 'Session recording · round 3');
  });

  test('any other name is kept as written', () {
    expect(materialTitle('Week 1 recap', recorded: true), 'Week 1 recap');
    expect(materialTitle('نن — تسجيل الحصة', recorded: false), 'نن — تسجيل الحصة');
    expect(materialTitle('ملخص الفصل الأول.pdf', recorded: false), 'ملخص الفصل الأول.pdf');
  });
}
