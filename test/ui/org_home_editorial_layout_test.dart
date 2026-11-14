// The editorial pieces of the organization homes (D-610 – D-629): the "Needs your attention" block (the count in the
// editorial face, "n urgent", the rows on a paper card inside it), the emerald "all caught up" block, and the member
// home's sky hero with a long name and the switch — no overflow at 320 x 640 .. 1400 x 900, ar / en, text x 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/org/home/org_home_logic.dart';
import 'package:flutter_education_app/features/org/home/org_home_tasks.dart';
import 'package:flutter_education_app/features/org/org_member_dashboard.dart' show OrgMemberHero;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';

const _long = 'A request with a long title that has to wrap or ellipsize on a narrow phone at a large text size';

final _tasks = [
  for (var i = 0; i < 3; i++)
    OrgTask(
      id: 't$i',
      kind: 'complaint',
      titleAr: _long,
      titleEn: _long,
      subtitleAr: _long,
      subtitleEn: _long,
      urgency: i == 0 ? 'high' : 'low',
      createdAt: DateTime.utc(2026, 11, 1),
    ),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the attention block with a long count and long rows', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(child: OrgNeedsYouSection(tasks: _tasks, total: 1234, onSeeAll: () {}, onOpen: (_) {})),
    );
  });

  testWidgets('all caught up is one calm block', (tester) async {
    await expectNoLayoutErrors(tester, () => const SingleChildScrollView(child: OrgNeedsYouSection(tasks: [], total: 0)));
  });

  testWidgets('the member hero: a long name, two roles lines and the switch', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: OrgMemberHero(
          org: const {'name_ar': _long, 'name_en': _long, 'type': 'university'},
          subtitle: _long,
          onSwitch: () {},
        ),
      ),
    );
  });
}
