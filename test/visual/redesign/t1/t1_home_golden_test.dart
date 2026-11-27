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
import 'package:flutter_education_app/features/home/teacher/go_live_sheet.dart' show GoLiveSheetView;
import 'package:flutter_education_app/features/home/teacher/go_live.dart' show GoLiveCourse, GoLiveSuggestion;
import 'package:flutter_education_app/config/app_config.dart' show AppConfig, Trans;
import 'package:flutter_education_app/features/home/teacher/todo/teacher_todo_page.dart';
import 'package:flutter_education_app/features/live/meeting_links_page.dart';
import 'package:flutter_education_app/features/messaging/inbox/inbox_page.dart';
import 'package:flutter_education_app/features/messaging/notification/notifications_provider.dart';
import 'package:flutter_education_app/features/payments/enrollment_request/teacher_transfers_provider.dart';
import 'package:flutter_education_app/features/payments/enrollment_request/teacher_transfers_screen.dart';
import 'package:flutter_education_app/features/home/teacher/todo/teacher_todo_models.dart' show TodoMenu;
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

  testWidgets('t1 golive', (t) async {
    final title = TextEditingController();
    await render(
      t,
      'golive',
      () {
        final ar = AppConfig.lang == 'ar';
        return Material(
          child: GoLiveSheetView(
            courses: [
              GoLiveCourse(id: 1, title: ar ? 'الرياضيات ٣ ثانوي، أ' : 'Maths 3 S, A', students: 8),
              GoLiveCourse(id: 2, title: ar ? 'الفيزياء ٢ ثانوي' : 'Physics 2 S', students: 9),
              GoLiveCourse(id: 3, title: ar ? 'قدرات كمي' : 'Qudurat quantitative', students: 10),
            ],
            courseId: 2,
            onCourse: (_) {},
            title: title,
            titleHint: ar ? 'العنوان (اختياري)' : 'Title (optional)',
            suggestion: GoLiveSuggestion(
                sessionId: 9, title: ar ? 'مراجعة الفصل الثالث' : 'Chapter 3 revision', startsAt: DateTime.now().toUtc().add(const Duration(minutes: 12)), minutes: 50),
            useSuggestion: true,
            onUseSuggestion: (_) {},
            record: true,
            onRecord: (_) {},
            onCamera: (_) {},
            onMic: (_) {},
            onGo: () {},
            onClose: () {},
            onMeetNow: () {},
          ),
        );
      },
      scaffold: true,
    );
  });
  testWidgets(
    't1 reject',
    (t) => render(
      t,
      'reject',
      () => Material(
        child: TransferRejectBody(
          title: 'rejection_reason_title'.tr,
          hint: 'rejection_reason_hint'.tr,
          studentName: 'راكان الحربي',
          quickReasons: ['transfer_reason_unclear_receipt'.tr, 'transfer_reason_amount_mismatch'.tr, 'transfer_reason_invalid_details'.tr],
        ),
      ),
      scaffold: true,
    ),
  );
  testWidgets(
    't1 todo menu',
    (t) => render(
      t,
      'todo_menu',
      () => TeacherTodoView(list: t1TodoPage(), onRefresh: () async {}, onOpen: (_) {}, onMenu: (_, _) {}, onRestore: (_) {}),
      scaffold: true,
      act: (t) async {
        await t.tap(find.text('t1_hm_more'.tr).first.evaluate().isEmpty ? find.byType(PopupMenuButton<TodoMenu>).first : find.text('t1_hm_more'.tr).first);
        await t.pump(const Duration(milliseconds: 400));
      },
    ),
  );
}
