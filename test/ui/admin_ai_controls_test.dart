// The super admin's AI controls (D-780): the plain-values card at 320x640 and 1400x900, Arabic + English,
// textScaler 1.3; the parsing of the server's list; the feature_disabled texts per AI key (D-781).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/design/app_switch.dart' show AppSwitch;
import 'package:flutter_education_app/features/admin/admin_ai_controls.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _longOff =
    'Bubble and scanned sheet uploads and camera marking are refused with a clear message; sheets and marks already read stay, '
    'and nothing that was graded before is touched in any way at all.';

List<AiControl> _items() => [
      for (final (key, on, partial, enforced) in [
        ('exam.auto_create', true, false, 'server'),
        ('exam.auto_grade', false, false, 'server'),
        ('exam.auto_correct', true, true, 'server'),
        ('rag.app_assistant', true, false, 'server'),
        ('rag.assistant', false, false, 'server'),
        ('rag.learning', true, false, 'server'),
        ('image.background', true, false, 'app'),
      ])
        AiControl.from({
          'key': key,
          'title_ar': 'التصحيح التلقائي لأوراق التظليل والأوراق الممسوحة بالكاميرا',
          'title_en': 'Automatic correction of bubble sheets and scanned sheets by camera',
          'off_ar': 'يُرفض رفع أوراق التظليل والأوراق الممسوحة والتصحيح بالكاميرا برسالة واضحة؛ تبقى الأوراق والدرجات المقروءة.',
          'off_en': _longOff,
          'on': on,
          'partial': partial,
          'enforced': enforced,
        }),
    ];

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('the server list parses into controls', () {
    final items = _items();
    expect(items.length, 7);
    expect(items[1].on, isFalse);
    expect(items[2].partial, isTrue);
    expect(items.last.onDevice, isTrue);
    expect(items.first.onDevice, isFalse);
    expect(AiControl.from({'key': 'x'}).on, isTrue, reason: 'a missing `on` reads as on');
  });

  test('feature_disabled texts name each AI feature, in both languages', () {
    for (final lang in ['en', 'ar']) {
      AppConfig.lang = lang;
      final keys = ['exam.auto_create', 'exam.auto_grade', 'exam.auto_correct', 'rag.app_assistant', 'rag.assistant', 'rag.learning'];
      final texts = {for (final k in keys) featureDisabledText(k)};
      expect(texts.length, keys.length, reason: 'one sentence per AI feature ($lang)');
      expect(featureDisabledText(null), isNotEmpty);
      expect(texts.contains(featureDisabledText('profile.logout')), isFalse);
    }
    AppConfig.lang = 'en';
    expect(featureDisabledText('exam.auto_grade'), contains('by hand'));
  });

  testWidgets('the card: no overflow, one switch per control, OFF ones off', (tester) async {
    final toggled = <(String, bool)>[];
    await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
              child: AiControlsCard(items: _items(), busy: const {'rag.learning'}, onToggle: (c, v) => toggled.add((c.key, v))),
            ));
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(layoutHost(SingleChildScrollView(
      child: AiControlsCard(items: _items(), busy: const {'rag.learning'}, onToggle: (c, v) => toggled.add((c.key, v))),
    )));
    await tester.pump();
    final switches = tester.widgetList<AppSwitch>(find.byType(AppSwitch)).toList();
    expect(switches.length, 7);
    expect(switches.where((s) => !s.value).length, 2);
    expect(switches[5].onChanged, isNull, reason: 'a control being saved is disabled');
    await tester.tap(find.byType(AppSwitch).first);
    await tester.pump();
    expect(toggled, [('exam.auto_create', false)]);
  });
}
