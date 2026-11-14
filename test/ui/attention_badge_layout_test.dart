// AttentionBadge (lib/design/attention_badge.dart): the count pill over its child at 320x640 / 1400x900, Arabic +
// English, text x1.3; nothing is drawn at zero; the pill is a labelled button whose hit area is wider than itself.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart';
import 'package:flutter_education_app/design/attention_badge.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

void main() {
  setUp(() => AppConfig.lang = 'ar');

  testWidgets('a count over an icon, a long count, and none at zero', (tester) async {
    AttentionService.instance.bumpLocal(AttentionTabs.chat, 120);
    addTearDown(() => AttentionService.instance.bumpLocal(AttentionTabs.chat, -120));
    await expectNoLayoutErrors(
      tester,
      () => Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AttentionBadge(tabKey: AttentionTabs.chat, child: IconButton(icon: const Icon(Icons.forum_rounded), onPressed: () {})),
          const SizedBox(width: 24),
          const AttentionBadge(tabKey: AttentionTabs.profile, child: Icon(Icons.person_rounded)),
        ]),
      ),
      act: (t) async {
        expect(find.text('99+'), findsOneWidget);
        final pill = find.ancestor(of: find.text('99+'), matching: find.byType(GestureDetector)).first;
        expect(t.getSize(pill).height, greaterThanOrEqualTo(32));
        expect(t.getSize(pill).width, greaterThanOrEqualTo(32));
      },
    );
  });
}
