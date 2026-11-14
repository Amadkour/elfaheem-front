// Phase 9 (docs/advising/PHASE9.md, app items 1 and 2):
//   * the workspace selection (AdvSelection): toggle, the page check box, the 5 000 limit, the explicit audience
//   * the workspace view: a long press starts selecting, a tap then toggles, "Message selected" sends the chosen ones,
//     and nobody may select without the outreach right
//   * a student's outreach push opens that message's sheet over the list, looking through the pages
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/org/advising/adv_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_outreach.dart';
import 'package:flutter_education_app/features/org/advising/adv_parts.dart' show AdvLoad;
import 'package:flutter_education_app/features/org/advising/adv_workspace_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'adv_case_models_test.dart';

AdvPage<AdvCaseItem> get _work => AdvPage.fromJson(sampleAdvWorkspaceJson(), AdvCaseItem.fromJson);

AdvCaseItem _item(int id) => AdvCaseItem.fromJson({'member_id': id, 'name': 'Student $id'});

Widget _host(Widget child) {
  final theme = ThemeConfigProvider(api: ApiClient());
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(theme: theme.materialTheme(dark: false), home: child),
  );
}

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  group('AdvSelection', () {
    test('toggle adds and removes; the audience is exactly the chosen ids, sorted', () {
      var s = const AdvSelection().toggle(_item(9)).toggle(_item(4)).toggle(_item(7));
      expect(s.count, 3);
      s = s.toggle(_item(7));
      expect(s.memberIds, [4, 9]);
      expect(s.audience.toJson(), {'metric': 'all', 'member_ids': [4, 9]});
    });

    test('the page check box: none · some · all, and toggling the page', () {
      final page = [_item(1), _item(2), _item(3)];
      var s = const AdvSelection();
      expect(s.pageState(page), isFalse);
      s = s.toggle(_item(2));
      expect(s.pageState(page), isNull);
      s = s.togglePage(page);
      expect(s.pageState(page), isTrue);
      expect(s.memberIds, [1, 2, 3]);
      // a student chosen on another page stays when this page is cleared
      s = s.toggle(_item(50)).togglePage(page);
      expect(s.memberIds, [50]);
      expect(s.pageState(page), isFalse);
    });

    test('never more than the limit', () {
      var s = const AdvSelection({}, 2).toggle(_item(1)).toggle(_item(2));
      expect(s.full, isTrue);
      expect(identical(s.toggle(_item(3)), s), isTrue);
      s = const AdvSelection({}, 2).togglePage([_item(1), _item(2), _item(3)]);
      expect(s.memberIds, [1, 2]);
      expect(s.toggle(_item(1)).memberIds, [2]);
    });

    test('the count text follows the plural forms', () {
      expect(advSelectedText(1), '1 student selected');
      expect(advSelectedText(12), '12 students selected');
      AppConfig.lang = 'ar';
      expect(advSelectedText(2), 'طالبان مختاران');
      expect(advSelectedText(5), '5 طلاب مختارون');
      expect(advSelectedText(11), '11 طالباً مختاراً');
    });

    test('the outreach kill switch (and the module one) turn selecting off', () {
      expect(advOutreachOn(), isTrue);
      AppConfig.disableList = ['org.advising.outreach'];
      expect(advOutreachOn(), isFalse);
      AppConfig.disableList = ['org.advising'];
      expect(advOutreachOn(), isFalse);
    });
  });

  group('workspace view', () {
    testWidgets('long press starts, a tap toggles, the action sends the chosen students', (tester) async {
      final page = _work;
      AdvSelection? sel;
      AdvCaseItem? opened;
      var messaged = 0;
      late StateSetter set;
      await tester.pumpWidget(_host(Scaffold(
        body: StatefulBuilder(builder: (context, s) {
          set = s;
          return AdvWorkspaceView(
            load: AdvLoad.ready,
            manage: true,
            query: const AdvWorkspaceQuery(),
            page: page,
            now: advCaseNow,
            onOpen: (x) => opened = x,
            selection: sel,
            onSelectStart: (first) => set(() => sel = first == null ? const AdvSelection() : const AdvSelection().toggle(first)),
            onToggle: (x) => set(() => sel = sel!.toggle(x)),
            onTogglePage: () => set(() => sel = sel!.togglePage(page.items)),
            onSelectDone: () => set(() => sel = null),
            onMessageSelected: () => messaged++,
          );
        }),
      )));
      await tester.pumpAndSettle();
      final first = page.items[0], second = page.items[1];
      expect(find.byKey(const ValueKey('adv.workspace.select.message')), findsNothing);

      await tester.longPress(find.text(first.shown));
      await tester.pumpAndSettle();
      expect(sel!.memberIds, [first.memberId]);
      expect(opened, isNull);
      expect(find.text('1 student selected'), findsOneWidget);

      await tester.tap(find.text(second.shown));
      await tester.pumpAndSettle();
      expect(sel!.count, 2);
      expect(opened, isNull, reason: 'a tap while selecting chooses, it does not open the 360');
      expect(find.text('Message 2 selected students'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('adv.workspace.select.message')));
      expect(messaged, 1);

      await tester.tap(find.byKey(const ValueKey('adv.workspace.select.page')));
      await tester.pumpAndSettle();
      expect(sel!.count, page.items.length);

      await tester.tap(find.byKey(const ValueKey('adv.workspace.select.done')));
      await tester.pumpAndSettle();
      expect(sel, isNull);
      await tester.tap(find.text(first.shown));
      expect(opened?.memberId, first.memberId);
    });

    testWidgets('without the outreach right a long press only opens the student, as a tap does', (tester) async {
      AdvCaseItem? opened;
      await tester.pumpWidget(_host(Scaffold(
        body: AdvWorkspaceView(load: AdvLoad.ready, manage: false, query: const AdvWorkspaceQuery(), page: _work, now: advCaseNow, onOpen: (x) => opened = x),
      )));
      await tester.pumpAndSettle();
      await tester.longPress(find.text(_work.items[0].shown));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('adv.workspace.select.done')), findsNothing);
      expect(opened?.memberId, _work.items[0].memberId);
    });
  });

  group('student outreach deep link', () {
    late FakeApi fake;
    final read = <String>[];
    Map<String, dynamic> msg(int id) => {'id': id, 'subject': 'Subject $id', 'body': 'Body of message $id', 'sender_name': 'Dr. Huda', 'sent_at': '2026-11-05T09:00:00'};

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins();
      read.clear();
      fake = FakeApi({
        'GET /api/v1/org/public/3/advising/outreach': (o) {
          final page = int.parse('${o.queryParameters['page'] ?? 1}');
          return {
            'items': page == 1 ? [for (var i = 30; i > 10; i--) msg(i)] : [msg(7), msg(5)],
            'total': 22,
            'page': page,
            'size': 20,
            'pages': 2,
            'unread': 22,
          };
        },
        'POST /api/v1/org/public/3/advising/outreach/*': (o) {
          read.add(o.path);
          return {'id': 7, 'read_at': '2026-11-06T10:00:00'};
        },
      }, latency: const Duration(milliseconds: 5))
        ..install();
    });
    tearDown(() => fake.uninstall());

    testWidgets('the named message opens over the list, found on the second page, and is marked read', (tester) async {
      await tester.pumpWidget(_host(const AdvStudentMessagesPage(orgId: 3, openId: 7)));
      await tester.pumpAndSettle();
      expect(find.text('Body of message 7'), findsOneWidget);
      expect(read, ['/api/v1/org/public/3/advising/outreach/7/read']);
      // closing the sheet leaves the list
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Body of message 7'), findsNothing);
      expect(find.text('Subject 30'), findsOneWidget);
    });

    testWidgets('a message no longer there: the list stays, nothing opens', (tester) async {
      await tester.pumpWidget(_host(const AdvStudentMessagesPage(orgId: 3, openId: 999)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Body of message'), findsNothing);
      expect(find.text('Subject 30'), findsOneWidget);
      expect(read, isEmpty);
    });
  });
}
