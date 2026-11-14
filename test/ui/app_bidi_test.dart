import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_bidi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('contentDirection: the first strong letter decides', () {
    expect(contentDirection('Conference leave, 12–15 December'), TextDirection.ltr);
    expect(contentDirection('طلب إجازة لحضور مؤتمر'), TextDirection.rtl);
    expect(contentDirection('12–15 ديسمبر'), TextDirection.rtl); //   digits are weak: the letter after them counts
    expect(contentDirection('«Budget» memo'), TextDirection.ltr);
    expect(contentDirection('ﻻ'), TextDirection.rtl); //               presentation form
    expect(contentDirection('Élan'), TextDirection.ltr);
    expect(contentDirection('2026 — 15%'), isNull);
    expect(contentDirection(''), isNull);
  });

  Future<Text> pump(WidgetTester tester, String s, TextDirection page) async {
    await tester.pumpWidget(Directionality(textDirection: page, child: AutoDirText(s)));
    return tester.widget<Text>(find.byType(Text));
  }

  testWidgets('AutoDirText: own direction, aligned to the page start', (tester) async {
    var t = await pump(tester, 'Conference leave', TextDirection.rtl);
    expect(t.textDirection, TextDirection.ltr);
    expect(t.textAlign, TextAlign.end); // the right edge, like the Arabic rows around it

    t = await pump(tester, 'طلب إجازة', TextDirection.rtl);
    expect(t.textDirection, TextDirection.rtl);
    expect(t.textAlign, TextAlign.start);

    t = await pump(tester, '2026', TextDirection.ltr);
    expect(t.textDirection, TextDirection.ltr);
    expect(t.textAlign, TextAlign.start);
  });
}
