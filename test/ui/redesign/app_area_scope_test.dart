// AppAreaScope (KIT_SPEC §2.5): the nearest scope's set, roles, playful, and the role mapping.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_area.dart';
import 'package:flutter_education_app/design/app_subject_colors.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'redesign_harness.dart';

void main() {
  Future<BuildContext> pumpAt(WidgetTester tester, Widget Function(Widget probe) wrap) async {
    late BuildContext seen;
    await tester.pumpWidget(kitHost(wrap(Builder(builder: (c) {
      seen = c;
      return const SizedBox();
    }))));
    return seen;
  }

  testWidgets('no scope = the home set, not playful', (tester) async {
    final c = await pumpAt(tester, (p) => p);
    expect(AppAreaScope.of(c), c.colors.kit.area(AppArea.home));
    expect(AppAreaScope.areaOf(c), isNull);
    expect(AppAreaScope.playful(c), isFalse);
  });

  testWidgets('nested scopes: the nearest wins', (tester) async {
    final c = await pumpAt(
        tester, (p) => AppAreaScope(area: AppArea.learn, child: AppAreaScope(area: AppArea.games, child: p)));
    expect(AppAreaScope.of(c), c.colors.kit.area(AppArea.games));
    expect(AppAreaScope.areaOf(c), AppArea.games);
    expect(AppAreaScope.playful(c), isTrue);
  });

  testWidgets('.role: the role set, not playful', (tester) async {
    final c = await pumpAt(tester, (p) => AppAreaScope.role(role: AppRoleAccent.parent, child: p));
    expect(AppAreaScope.of(c), c.colors.kit.role(AppRoleAccent.parent));
    expect(AppAreaScope.areaOf(c), isNull);
    expect(AppAreaScope.playful(c), isFalse);
  });

  test('appRoleAccentFor', () {
    expect(appRoleAccentFor('teacher'), AppRoleAccent.teacher);
    expect(appRoleAccentFor('parent'), AppRoleAccent.parent);
    for (final r in ['admin', 'org-admin', 'org-staff']) {
      expect(appRoleAccentFor(r), AppRoleAccent.admin);
    }
    expect(appRoleAccentFor('super-admin'), AppRoleAccent.superAdmin);
    expect(appRoleAccentFor('developer'), AppRoleAccent.superAdmin);
    expect(appRoleAccentFor('student'), isNull);
    expect(appRoleAccentFor(null), isNull);
  });

  test('subjectKeyFor', () {
    expect(subjectKeyFor(' Math '), 'math');
    expect(subjectKeyFor('الفيزياء'), 'physics');
    expect(subjectKeyFor('Astronomy'), 'other');
    expect(subjectKeyFor(null), 'other');
    expect(subjectKeyFor('Astronomy', colorKey: 'code'), 'code');
  });
}
