// VISUAL review renders of the teacher's T1 Home screens (Tea1Home: home, calm, first, todo, inbox, transfers, meeting
// links, the go-live sheet): 390x844 and 1360x900, Arabic and English, light, CAST demo data
// (test/support/redesign/t1_home_fakes.dart). Compared by eye with D:/platform/redesign-ref/ref/teacher/00*.png.
// Not a CI suite.
//
//   flutter test test/visual/redesign/t1/t1_home_golden_test.dart --update-goldens [--plain-name calm]
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/home/teacher/todo/teacher_todo_page.dart';
import 'package:flutter_education_app/features/live/meeting_links_page.dart';
import 'package:flutter_education_app/features/messaging/inbox/inbox_page.dart';
import 'package:flutter_education_app/features/messaging/notification/notifications_provider.dart';
import 'package:flutter_education_app/features/payments/enrollment_request/teacher_transfers_provider.dart';
import 'package:flutter_education_app/features/payments/enrollment_request/teacher_transfers_screen.dart';
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/redesign/t1_home_fakes.dart';
import '../kit_golden_harness.dart';

void main() {
  late StorageService storage;
  setUp(() async => storage = await kitGoldenSetUp());

  Future<void> render(WidgetTester tester, String name, Widget Function() build, {Future<void> Function(WidgetTester)? act, bool scaffold = false}) async {
    await t1HomeSetUp(t1HomeApi());
    await kitRender(
      tester,
      't1/home_$name',
      () => MultiProvider(
        providers: [
          ChangeNotifierProvider<TeacherTransfersProvider>(create: (_) => TeacherTransfersProvider()),
          ChangeNotifierProvider<NotificationsProvider>(create: (_) => NotificationsProvider()),
        ],
        child: build(),
      ),
      storage: storage,
      modes: const [false],
      scaffold: scaffold,
      act: act,
    );
  }

  Widget home(T1HomeState s) => T2Scope(child: SingleChildScrollView(child: t1HomeBody(s)));

  testWidgets('t1 home', (t) => render(t, 'home', () => home(T1HomeState.busy), scaffold: true));
  testWidgets('t1 calm', (t) => render(t, 'calm', () => home(T1HomeState.calm), scaffold: true));
  testWidgets('t1 first', (t) => render(t, 'first', () => home(T1HomeState.first), scaffold: true));
  testWidgets(
    't1 todo',
    (t) => render(
      t,
      'todo',
      () => TeacherTodoView(list: t1TodoPage(), onRefresh: () async {}, onOpen: (_) {}, onMenu: (_, _) {}, onRestore: (_) {}),
    ),
  );
  testWidgets('t1 inbox', (t) => render(t, 'inbox', () => const InboxPage()));
  testWidgets('t1 transfers', (t) => render(t, 'transfers', () => const TeacherTransfersScreen()));
  testWidgets('t1 meetings', (t) => render(t, 'meetings', () => const MeetingLinksPage(api: T1FakeLinksApi())));
}
