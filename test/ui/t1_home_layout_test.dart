// The teacher's T1 Home screens (Tea1Home) at 320x640 and 1400x900, Arabic + English, textScaler 1.3: the home in its
// three states, the to-do page, the inbox, the transfers, the meeting links.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart' show translation;
import 'package:flutter_education_app/features/home/teacher/todo/teacher_todo_page.dart';
import 'package:flutter_education_app/features/live/meeting_links_page.dart';
import 'package:flutter_education_app/features/messaging/inbox/inbox_page.dart';
import 'package:flutter_education_app/features/messaging/notification/notifications_provider.dart';
import 'package:flutter_education_app/features/payments/enrollment_request/teacher_transfers_provider.dart';
import 'package:flutter_education_app/features/payments/enrollment_request/teacher_transfers_screen.dart';
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/redesign/t1_home_fakes.dart';
import 'layout_harness.dart';

void main() {
  setUp(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    for (final f in Directory('docs/redesign/strings').listSync().whereType<File>()) {
      if (f.path.endsWith('.json')) translation.addAll(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
    }
    await t1HomeSetUp(t1HomeApi());
  });

  Widget providers(Widget child) => MultiProvider(providers: [
        ChangeNotifierProvider<TeacherTransfersProvider>(create: (_) => TeacherTransfersProvider()),
        ChangeNotifierProvider<NotificationsProvider>(create: (_) => NotificationsProvider()),
      ], child: child);

  for (final s in T1HomeState.values) {
    testWidgets('home ${s.name}', (t) => expectNoLayoutErrors(t, () => T2Scope(child: SingleChildScrollView(child: t1HomeBody(s)))));
  }
  testWidgets('home loading and error', (t) async {
    await expectNoLayoutErrors(t, () => T2Scope(child: SingleChildScrollView(child: t1HomeBody(T1HomeState.busy, loading: true))));
    await expectNoLayoutErrors(t, () => T2Scope(child: SingleChildScrollView(child: t1HomeBody(T1HomeState.busy, error: 'x'))));
  });
  testWidgets('todo page', (t) => expectNoLayoutErrors(t, () => TeacherTodoView(list: t1TodoPage(), onRefresh: () async {}, onOpen: (_) {}, onMenu: (_, _) {}, onRestore: (_) {})));
  testWidgets('inbox', (t) => expectNoLayoutErrors(t, () => providers(const InboxPage()), scaffold: false, frames: 8));
  testWidgets('transfers', (t) => expectNoLayoutErrors(t, () => providers(const TeacherTransfersScreen()), scaffold: false, frames: 8));
  testWidgets('meeting links', (t) => expectNoLayoutErrors(t, () => const MeetingLinksPage(api: T1FakeLinksApi()), scaffold: false, frames: 8));
}
