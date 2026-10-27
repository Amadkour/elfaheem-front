// The app features guide page (lib/features/admin/admin_feature_guide.dart): filters, steps, state texts, and the
// tile / editor at every screen size.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_feature_guide.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

GuideFeature feature(String key,
        {List<String> roles = const ['student'],
        String state = 'shown',
        bool rag = true,
        bool? inAssistant,
        List<String> hiddenOn = const [],
        String source = 'seed',
        bool edited = false}) =>
    GuideFeature({
      'key': key,
      'group': 'learning',
      'roles': roles,
      'title_ar': 'تنزيل المحاضرات لمشاهدتها دون إنترنت',
      'title_en': 'Download lectures to watch offline',
      'summary_ar': 'احفظ المحاضرة على هاتفك مرة واحدة وشاهدها لاحقاً دون اتصال بالإنترنت، مع بقائها مشفّرة.',
      'summary_en': 'Save a lecture on your phone once and watch it later without an internet connection; it stays encrypted.',
      'where_ar': 'الملف الشخصي › التنزيلات',
      'where_en': 'Profile › Downloads',
      'steps_ar': ['افتح المحاضرة', 'اضغط زر التنزيل'],
      'steps_en': ['Open the lecture', 'Tap the download button'],
      'switch_keys': state == 'none' ? <String>[] : ['profile.downloads'],
      'app_state': state,
      'hidden_on': hiddenOn,
      'rag_enabled': rag,
      'in_assistant': inAssistant ?? (rag && state != 'hidden'),
      'source': source,
      'edited': edited,
      'resettable': source == 'seed' && edited,
    });

const roles = {
  'everyone': 'Everyone',
  'student': 'Students',
  'teacher': 'Teachers',
  'parent': 'Parents',
  'org_member': 'Organization members',
  'org_staff': 'Organization staff',
  'org_admin': 'Organization admins',
  'admin': 'Platform admins',
  'super_admin': 'Super admin',
};

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('filters: role (everyone matches all), group, search in both languages, where it shows', () {
    final a = feature('downloads');
    final all = feature('notifications', roles: ['everyone']);
    final hidden = feature('payouts', roles: ['teacher'], state: 'hidden');
    final off = feature('tips', rag: false);
    expect(guideMatches(a, role: 'student'), isTrue);
    expect(guideMatches(a, role: 'teacher'), isFalse);
    expect(guideMatches(all, role: 'parent'), isTrue);
    expect(guideMatches(a, group: 'live'), isFalse);
    expect(guideMatches(a, q: 'دون إنترنت'), isTrue);
    expect(guideMatches(a, q: 'PROFILE › down'), isTrue);
    expect(guideMatches(a, q: 'downloads'), isTrue); // the key
    expect(guideMatches(a, q: 'zzz'), isFalse);
    expect([a, all, hidden, off].where((f) => guideMatches(f, show: GuideShow.inAssistant)).map((f) => f.key), ['downloads', 'notifications']);
    expect([a, all, hidden, off].where((f) => guideMatches(f, show: GuideShow.notInAssistant)).map((f) => f.key), ['payouts', 'tips']);
    expect([a, all, hidden, off].where((f) => guideMatches(f, show: GuideShow.hiddenInApp)).map((f) => f.key), ['payouts']);
  });

  test('steps: one per line, blanks dropped; state texts in both languages', () {
    expect(guideSteps(' Open it \n\n  Tap save\n '), ['Open it', 'Tap save']);
    expect(guideAppStateText(feature('a')), '');
    expect(guideAppStateText(feature('a', state: 'partial', hiddenOn: ['ios', 'web'])), 'Hidden on: iOS, Web');
    expect(guideAppStateText(feature('a', state: 'none')), 'Not linked to an app switch');
    AppConfig.lang = 'ar';
    expect(guideAppStateText(feature('a', state: 'hidden')), 'مخفية في التطبيق');
    expect(feature('a').title, 'تنزيل المحاضرات لمشاهدتها دون إنترنت');
  });

  group('layout', () {
    testWidgets('tiles in every state', (tester) async {
      await expectNoLayoutErrors(
          tester,
          () => ListView(children: [
                GuideFeatureTile(feature: feature('downloads', roles: roles.keys.toList()), roleNames: roles, onApp: (_) {}, onRag: (_) {}),
                GuideFeatureTile(feature: feature('partial', state: 'partial', hiddenOn: ['android', 'ios', 'web']), roleNames: roles),
                GuideFeatureTile(feature: feature('hidden', state: 'hidden', edited: true), roleNames: roles),
                GuideFeatureTile(feature: feature('custom', state: 'none', rag: false, source: 'custom'), roleNames: roles),
              ]));
    });

    for (final (name, f, ro) in [('new', null, false), ('edit', feature('downloads', edited: true), false), ('read-only', feature('downloads'), true)]) {
      testWidgets('editor: $name', (tester) async {
        await expectNoLayoutErrors(
            tester,
            () => GuideFeatureEditor(
                  feature: f,
                  groups: const {'learning': 'Courses and learning', 'live': 'Live sessions'},
                  roles: roles,
                  switches: const {'profile.downloads': 'Downloads', 'live_sessions': 'Live sessions screen'},
                  readOnly: ro,
                  onSave: (_) async => true,
                  onReset: f?.resettable == true ? () async => true : null,
                  onDelete: f == null ? null : () async => true,
                ));
      });
    }
  });
}
