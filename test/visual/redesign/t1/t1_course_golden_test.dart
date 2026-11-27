// VISUAL review renders of the redesigned T1 course page (Tea1Course: overview, draft, sessions, the new-session
// sheet, add material, captions, guest link, the upload bar, the session menu): 390x844 and 1360x900, Arabic and
// English, light, CAST demo data (test/support/redesign/t1_course_fakes.dart). Compared by eye with
// D:/platform/redesign-ref/ref/teacher/026..034_*.png. Not a CI suite.
//
//   flutter test test/visual/redesign/t1/t1_course_golden_test.dart --update-goldens [--plain-name sessions]
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_education_app/features/guest/guest_live_api.dart';
import 'package:flutter_education_app/features/sessions/teacher/components/guest_link_sheet.dart';
import 'package:flutter_education_app/features/sessions/teacher/components/session_options_sheet.dart';
import 'package:flutter_education_app/features/upload/upload_progress_footer.dart';
import 'package:flutter_education_app/features/upload/upload_task.dart';
import 'package:flutter_education_app/features/sessions/material/components/add_material_sheet.dart';
import 'package:flutter_education_app/features/sessions/material/material_guest_links_api.dart';
import 'package:flutter_education_app/features/sessions/material/material_guest_links_sheet.dart';
import 'package:flutter_education_app/features/sessions/teacher/components/session_form_sheet.dart';
import 'package:flutter_education_app/features/sessions/teacher/sessions_provider.dart';
import 'package:flutter_education_app/features/sessions/teacher/sessions_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/redesign/t1_course_fakes.dart';
import '../../../support/redesign/t2_fakes.dart';
import '../kit_golden_harness.dart';

void main() {
  late StorageService storage;
  setUp(() async => storage = await kitGoldenSetUp());

  Future<void> render(WidgetTester tester, String name, Widget Function() build, {bool draft = false, Future<void> Function(WidgetTester)? act}) async {
    await t2SetUp(t1Api(draft: draft));
    await kitRender(tester, 't1/course_$name', build, storage: storage, modes: const [false], scaffold: false, act: act);
  }

  Widget page({bool draft = false, String? tab}) => ChangeNotifierProvider(
        create: (_) => TeacherCourseScreenProvider(initialCourse: t1Course(draft: draft)),
        child: TeacherSessionsScreen(initialTab: tab),
      );

  testWidgets('t1 course overview', (t) => render(t, 'overview', () => page()));
  testWidgets('t1 course draft', (t) => render(t, 'draft', () => page(draft: true), draft: true));
  testWidgets('t1 course sessions', (t) => render(t, 'sessions', () => page(tab: 'sessions')));
  sheetTests();
}

class _GuestLinksFake implements MaterialGuestLinksApi {
  static final _links = MaterialGuestLinks(links: [
    MaterialGuestLink(
      id: 1,
      token: 'a',
      link: 'https://alfheemacademy.com/v/7K2xQ9mP',
      expiresAt: DateTime.utc(2026, 12, 2),
      views: 12,
      openedAt: DateTime.utc(2026, 11, 26),
    ),
  ]);

  @override
  Future<MaterialGuestLinks> list(int sessionId, int materialId) async => _links;

  @override
  Future<MaterialGuestLinks> create(int sessionId, int materialId, {int? expiresDays}) async => _links;

  @override
  Future<MaterialGuestLinks> revoke(int sessionId, int materialId, int linkId) async => _links;
}

/// A sheet's content on a dimmed page, as the bottom sheet shows it (the Navigator's overlay is outside the shot).
Widget _sheet(Widget child) => Builder(builder: (context) {
      final c = context.colors;
      return ColoredBox(
        color: c.textDark.withValues(alpha: 0.45),
        child: Align(
          alignment: AlignmentDirectional.bottomCenter,
          child: Material(
            color: c.cardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
      );
    });

/// The sheets of the course page.
void sheetTests() {
  late StorageService storage;
  setUp(() async => storage = await kitGoldenSetUp());

  Future<void> render(WidgetTester tester, String name, Widget Function() build) async {
    await t2SetUp(t1Api());
    await kitRender(tester, 't1/course_$name', () => _sheet(build()), storage: storage, modes: const [false], scaffold: false, grow: false);
  }

  Widget withProvider(Widget Function(TeacherCourseScreenProvider p) b) {
    final p = TeacherCourseScreenProvider(initialCourse: t1Course());
    return ChangeNotifierProvider.value(value: p, child: b(p));
  }

  testWidgets('t1 course sform', (t) => render(t, 'sform', () => withProvider((p) => SessionFormSheet(provider: p, existing: null))));
  testWidgets('t1 course material', (t) => render(t, 'material', () => withProvider((p) => const AddMaterialSheet(sessionId: 100, isWide: false))));
  testWidgets(
    't1 course captions',
    (t) => render(
      t,
      'captions',
      () => Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            MaterialCaptionsPanel(state: MaterialCaptionsState.ready, onUpload: () {}, onGenerate: () {}, onRemove: () {}),
            const SizedBox(height: AppSpace.md),
            MaterialGuestLinksBody(links: _GuestLinksFake._links.links, onExpiry: (_) {}, onCreate: () {}, onCopy: (_) {}, onRevoke: (_) {}),
          ]),
        ),
      ),
    ),
  );

  testWidgets(
    't1 course guest',
    (t) => render(
      t,
      'guest',
      () => SingleChildScrollView(
        child: GuestLinkBody(
          loading: false,
          busy: false,
          error: null,
          link: const GuestLink(
            url: 'https://alfheemacademy.com/g/ra3-7KQ2x',
            token: 'ra3',
            canPublish: true,
            maxGuests: 10,
            guestsJoined: 2,
            hasPin: true,
          ),
          canPublish: true,
          maxGuestsController: TextEditingController(text: '10'),
          pinController: TextEditingController(),
          editing: true,
          showQr: false,
          joinsOpen: true,
          joins: [GuestJoinRecord(identity: 'g1', name: 'خالد الحربي', joinedAt: DateTime.utc(2026, 11, 24, 16, 34), ipMasked: '41.33.0.xx')],
          joinsTotal: 2,
          onRetry: () {},
          onCanPublishChanged: (_) {},
          onCreate: () {},
          onCopy: () {},
          onShare: () {},
          onToggleQr: () {},
          onToggleSettings: () {},
          onSaveSettings: () {},
          onRemovePin: () {},
          onRotate: () {},
          onRevoke: () {},
          onToggleJoins: () {},
          onRefreshJoins: () {},
        ),
      ),
    ),
  );

  testWidgets(
    't1 course options',
    (t) => render(
      t,
      'options',
      () => SessionOptionsBody(
        title: 'المتتابعات الهندسية',
        onPick: (_) {},
        options: const [
          SessionOption(id: 'live', icon: Icons.videocam_rounded, label: 'ابدأ البث', good: true),
          SessionOption(id: 'guest', icon: Icons.link_rounded, label: 'رابط الضيوف'),
          SessionOption(id: 'attendance', icon: Icons.how_to_reg_rounded, label: 'الحضور'),
          SessionOption(id: 'exams', icon: Icons.quiz_outlined, label: 'الامتحانات'),
          SessionOption(id: 'material', icon: Icons.attach_file_rounded, label: 'إضافة مرفق'),
          SessionOption(id: 'edit', icon: Icons.tune_rounded, label: 'تعديل الحصة'),
          SessionOption(id: 'delete', icon: Icons.delete_outline_rounded, label: 'حذف الحصة', danger: true),
        ],
      ),
    ),
  );

  testWidgets('t1 course uploads', (t) {
    UploadTask task(String name, int sent, int total, UploadStatus st) => UploadTask(
          sessionId: 100,
          fileName: name,
          cancelToken: CancelToken(),
          dio: Dio(),
          path: '/x',
          endpoint: '/x',
          fields: const {},
        )
          ..sentBytes = sent
          ..totalBytes = total
          ..status = st;
    return render(
      t,
      'uploads',
      () => Align(
        alignment: AlignmentDirectional.bottomCenter,
        child: UploadProgressFooterView(
          tasks: [
            task('شرائح المتتابعات الهندسية.pdf', 62, 100, UploadStatus.uploading),
            task('حل المسائل.mp4', 30, 100, UploadStatus.uploading),
          ],
          expanded: true,
          overallProgress: 0.46,
          activeCount: 2,
          onToggle: () {},
          onCancel: (_) {},
          onRetry: (_) {},
          onDismiss: (_) {},
        ),
      ),
    );
  });
}
