// Layout of the chat answer's newer blocks: no overflow at 320x640 / 1400x900, ar / en, text scale 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/rag/chat/rag_answer_extras.dart';
import 'package:flutter_education_app/features/rag/chat/rag_payload.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

final _long = 'The device linked to your account can be changed once every thirty days from the security page. ' * 6;

void main() {
  testWidgets('chunk cards: short, long (expandable), no pages, long names', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: RagChunkList(chunks: [
          const RagChunk(text: 'Short passage.', document: 'Terms and Conditions', pageFrom: 3, pageTo: 4, section: 'Devices'),
          RagChunk(text: _long, document: 'A very long document title that keeps going and going ' * 3, pageFrom: 12, section: 'Section ' * 12),
          const RagChunk(text: 'No document, no pages'),
        ]),
      ),
      act: (t) async {
        await t.tap(find.byType(TextButton).first);
        await t.pump();
      },
    );
  });

  testWidgets('tool cards: subscriptions, courses, schedule, progress, long titles', (tester) async {
    final now = DateTime.utc(2026, 11, 4);
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          RagToolCards(now: now, tool: RagTool(name: 'my_subscriptions', data: {
            'items': [
              {'plan': 'Annual plan with a very long name ' * 3, 'ends_at': '2026-11-09T00:00:00'},
              {'plan': 'Old', 'ends_at': '2026-10-01T00:00:00'},
            ]
          })),
          const SizedBox(height: 8),
          RagToolCards(now: now, tool: RagTool(name: 'my_courses', data: {
            'courses': [
              {'title': 'Mathematics ' * 8, 'progress': 40},
              {'title': 'Physics', 'progress': 100},
              {'title': 'Chemistry', 'progress': 0},
            ]
          })),
          const SizedBox(height: 8),
          RagToolCards(now: now, tool: RagTool(name: 'my_schedule', data: {
            'items': [
              {'title': 'Algebra live session ' * 4, 'starts_at': '2026-11-05T09:00:00'},
              {'title': 'Geometry', 'starts_at': '2026-11-06T14:30:00'},
            ]
          })),
          const SizedBox(height: 8),
          RagToolCards(now: now, tool: RagTool(name: 'my_progress', data: {'overall': 62, 'courses': [{'title': 'A', 'progress': 0.3}]})),
          const SizedBox(height: 8),
          const RagToolCards(tool: RagTool(name: 'refused')),
          const RagToolCards(tool: RagTool(name: 'unknown', data: {'x': 1})),
        ]),
      ),
    );
  });

  testWidgets('action row: four buttons with long labels; hidden ones are not drawn', (tester) async {
    var opened = '';
    await expectNoLayoutErrors(
      tester,
      () => Padding(
        padding: const EdgeInsets.all(12),
        child: RagActionRow(
          onOpen: (a) => opened = a.pageId,
          actions: [
            const RagAction(pageId: 'account.change_password', labelAr: 'تغيير كلمة المرور من صفحة الأمان', labelEn: 'Change the password from the security page'),
            const RagAction(pageId: 'account.subscription', labelAr: 'الاشتراك', labelEn: 'Subscription'),
            const RagAction(pageId: 'course', params: {'courseId': 12}, labelAr: 'فتح الكورس', labelEn: 'Open the course', orgId: 5),
            const RagAction(pageId: 'no.such.page', labelAr: 'x', labelEn: 'x'),
            const RagAction(pageId: 'calendar', labelAr: 'الجدول', labelEn: 'Schedule'),
            const RagAction(pageId: 'inbox', labelAr: 'الوارد', labelEn: 'Inbox'),
          ],
        ),
      ),
      act: (t) async {
        expect(find.byType(OutlinedButton), findsNWidgets(4));
        expect(find.byKey(const ValueKey('rag_action_no.such.page')), findsNothing);
        await t.tap(find.byKey(const ValueKey('rag_action_account.subscription')));
        expect(opened, 'account.subscription');
      },
    );
  });

  testWidgets('action row with nothing to show draws nothing', (tester) async {
    await expectNoLayoutErrors(tester, () => RagActionRow(actions: const [RagAction(pageId: 'nope')], onOpen: (_) {}));
  });
}
