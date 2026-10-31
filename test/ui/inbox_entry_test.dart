// The homes' inbox entry (lib/features/shared/inbox/unified_inbox.dart: InboxEntry, inboxEntryCounts,
// inboxEntrySummary) — the one slim row that replaced the inbox preview block: the counts it reads (the server's,
// never fewer than the preview rows show), its one line, when a home draws it, the tap and the screen-reader label,
// and the layout at 320x640 and 1400x900, Arabic + English, textScaler 1.3 (nothing to do, a lot to do, only news),
// with the real translations.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/inbox/unified_inbox.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

InboxItem row(String key, {String segment = 'todo', Duration? due}) => InboxItem({
      'key': key,
      'kind': 'form',
      'segment': segment,
      'title': key,
      'due_at': due == null ? null : DateTime.now().toUtc().add(due).toIso8601String(),
    });

const InboxEntryCounts none = (todo: 0, overdue: 0, dueSoon: 0, news: 0, offers: 0);
const InboxEntryCounts busy = (todo: 1234, overdue: 3, dueSoon: 2, news: 5, offers: 1);
const InboxEntryCounts newsOnly = (todo: 0, overdue: 0, dueSoon: 0, news: 2, offers: 1);

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() => AppConfig.lang = 'en');

  group('counts', () {
    test('the server counts win; the preview rows are the floor (an older server sends none)', () {
      final rows = [
        row('a', due: const Duration(hours: -2)), // overdue
        row('b', due: const Duration(hours: 5)), // due soon
        row('c'),
        row('n', segment: 'news'),
        row('o', segment: 'offers'),
      ];
      expect(inboxEntryCounts(rows), (todo: 3, overdue: 1, dueSoon: 1, news: 1, offers: 1));
      expect(
        inboxEntryCounts(rows, counts: const {'todo': 9, 'overdue': 4, 'due_soon': 0, 'news': 7}),
        (todo: 9, overdue: 4, dueSoon: 1, news: 7, offers: 1),
      );
      expect(inboxEntryCounts(const []), none);
    });

    test('a home draws the entry only while the inbox holds something', () {
      expect(inboxEntryHasAny(none), isFalse);
      expect(inboxEntryHasAny(busy), isTrue);
      expect(inboxEntryHasAny(newsOnly), isTrue);
      expect(inboxEntryHasAny((todo: 0, overdue: 0, dueSoon: 0, news: 0, offers: 1)), isTrue);
    });

    test('the one line: the to-dos first, else "all caught up" and what else is new', () {
      expect(inboxEntrySummary(busy), '1234 to do · 3 overdue · 2 due soon');
      expect(inboxEntrySummary((todo: 1, overdue: 0, dueSoon: 0, news: 4, offers: 0)), '1 to do');
      expect(inboxEntrySummary(newsOnly), "You're all caught up · 2 announcements · 1 offer");
      expect(inboxEntrySummary(none), "You're all caught up");
      AppConfig.lang = 'ar';
      expect(inboxEntrySummary(newsOnly), 'لا شيء ينتظرك الآن · إعلانان · عرض واحد');
      expect(inboxEntrySummary((todo: 0, overdue: 0, dueSoon: 0, news: 11, offers: 0)), 'لا شيء ينتظرك الآن · 11 إعلانًا');
    });
  });

  group('the entry', () {
    Widget page(InboxEntryCounts counts, {VoidCallback? onTap}) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          children: [
            InboxEntry(counts: counts, onTap: onTap ?? () {}),
            const SizedBox(height: 24),
            // the dashboard's side column (320 – 400 px)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SizedBox(width: 320, child: InboxEntry(counts: counts, onTap: onTap ?? () {}, padding: EdgeInsets.zero)),
            ),
          ],
        );

    testWidgets('no overflow: nothing to do, a lot to do, only news', (tester) async {
      await expectNoLayoutErrors(tester, () => page(none));
      await expectNoLayoutErrors(tester, () => page(busy));
      await expectNoLayoutErrors(tester, () => page(newsOnly));
    });

    testWidgets('a lot to do: the count as a badge (99+), one tap opens the inbox, a 48 px target, one label', (tester) async {
      for (final lang in layoutLangs) {
        AppConfig.lang = lang;
        var taps = 0;
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(layoutHost(Center(child: InboxEntry(counts: busy, onTap: () => taps++))));
        await tester.pump();
        expect(find.text('99+'), findsOneWidget);
        expect(find.text('inbox_title'.tr), findsOneWidget);
        expect(tester.getSize(find.byType(InkWell)).height, greaterThanOrEqualTo(48));
        final label = '${'inbox_title'.tr}, ${inboxEntrySummary(busy)}';
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(
            label: label,
            hint: 'inbox_entry_hint'.tr,
            isButton: true,
            hasTapAction: true,
          ),
        );
        await tester.tap(find.byType(InboxEntry));
        expect(taps, 1);
        handle.dispose();
      }
    });

    testWidgets('nothing to do: no badge, the calm line', (tester) async {
      for (final lang in layoutLangs) {
        AppConfig.lang = lang;
        await tester.pumpWidget(layoutHost(Center(child: InboxEntry(counts: newsOnly, onTap: () {}))));
        await tester.pump();
        expect(find.text(inboxEntrySummary(newsOnly)), findsOneWidget);
        expect(find.text('0'), findsNothing);
      }
    });
  });
}
