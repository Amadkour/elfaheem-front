// Track A2 polish, learning area: layout smoke tests (320x640 and 1400x900, ar + en, textScaler 1.3) for the
// presentational bodies touched by the screen-by-screen polish of student/**, teacher/** and the shared course,
// session, exam engine, live and guest widgets. Audit: docs/polish/screen-audit-learning.md.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/shared/course/course_price_tag.dart';
import 'package:flutter_education_app/features/shared/course/private_flag.dart';
import 'package:flutter_education_app/features/shared/course/topbar.dart';
import 'package:flutter_education_app/features/shared/guest/guest_state.dart';
import 'package:flutter_education_app/features/shared/session/material/components/session_exam_tile.dart';
import 'package:flutter_education_app/features/shared/session/material/components/session_progress_section.dart';
import 'package:flutter_education_app/features/shared/session/material/components/session_shared_widgets.dart';
import 'package:flutter_education_app/features/student/analysis/exam/exam_ui.dart' hide GradientButton;
import 'package:flutter_education_app/features/student/courses/details/components/about.dart';
import 'package:flutter_education_app/features/student/courses/details/course_access_sheet.dart';
import 'package:flutter_education_app/features/student/courses/details/course_detail_screen.dart';
import 'package:flutter_education_app/features/student/courses/details/session_exam_gate.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:flutter_education_app/features/teacher/certificates/certificate_requests_screen.dart';
import 'package:flutter_education_app/features/teacher/courses/component/course_progress_status_card.dart';
import 'package:flutter_education_app/features/teacher/courses/component/currency_selector.dart';
import 'package:flutter_education_app/features/teacher/courses/component/gradient_button.dart';
import 'package:flutter_education_app/features/teacher/courses/component/section_card.dart';
import 'package:flutter_education_app/features/teacher/courses/course_privacy_card.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart';
import 'package:flutter_education_app/features/teacher/sessions/components/teacher_course_parts.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_palette.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/participant_stats.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/room_screen_share.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

void main() {
  group('student', () {
    const longAr = 'مقدمة شاملة في هندسة البرمجيات وتصميم الأنظمة الموزعة للمبتدئين والمحترفين';
    const longEn = 'A complete introduction to software engineering and distributed systems design';

    testWidgets('exam hero: back + refresh glass buttons, stats, pill, ring', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          child: ExamHero(
            child: Column(children: [
              ExamHeroBar(
                title: '$longAr $longEn',
                subtitle: longEn,
                actions: const [GlassIcon(icon: Icons.refresh_rounded, tooltip: 'refresh')],
              ),
              const SizedBox(height: 16),
              const Row(children: [
                HeroStat(icon: Icons.quiz_rounded, color: Colors.amber, value: '128', label: longAr),
                SizedBox(width: 10),
                HeroStat(icon: Icons.timer_rounded, color: Colors.amber, value: '90%', label: longEn),
                SizedBox(width: 10),
                HeroStat(icon: Icons.star_rounded, color: Colors.amber, value: '12/40', label: longAr),
              ]),
              const SizedBox(height: 12),
              const HeroPill(icon: Icons.school_rounded, text: '$longAr $longEn'),
              const SizedBox(height: 12),
              const ExamRing(value: 72, size: 96),
            ]),
          ),
        ),
      );
    });

    testWidgets('exam empty / error / banner states', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
          child: Column(children: [
            const ExamEmpty(icon: Icons.quiz_outlined, text: '$longAr $longEn'),
            ExamError(message: '$longAr $longEn', retryLabel: 'retry', onRetry: () {}),
            const ExamBanner(icon: Icons.info_outline_rounded, color: Colors.orange, text: '$longAr $longEn'),
          ]),
        ),
      );
    });

    testWidgets('course detail: first-load skeleton and instructor card', (tester) async {
      await expectNoLayoutErrors(tester, () => const CourseDetailSkeleton());
      await expectNoLayoutErrors(
        tester,
        () => const Padding(
          padding: EdgeInsets.all(20),
          child: Column(children: [
            CourseInstructorCard(name: '$longAr $longEn', category: longEn),
            SizedBox(height: 12),
            CourseInstructorCard(name: '', category: ''),
          ]),
        ),
      );
    });

    testWidgets('private-course code sheet (themed keypad)', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => const Align(
          alignment: Alignment.bottomCenter,
          child: CourseAccessSheet(courseId: 7, courseName: '$longAr $longEn'),
        ),
      );
    });

    testWidgets('list skeleton used by the exam / analytics / certificate lists', (tester) async {
      await expectNoLayoutErrors(tester, () => const AppListSkeleton());
    });
  });

  group('teacher', () {
    TeacherCourse course() => TeacherCourse.fromJson({
          'id': 7,
          'image_url': '',
          'students_count': 1234,
          'sessions_count': 18,
          'total_hours': 42.5,
          'price': 1500,
          'type': 'live',
          'schedules': [
            {'id': 1, 'day': 'saturday', 'start_time': '09:00', 'end_time': '11:30'},
            {'id': 2, 'day': 'tuesday', 'start_time': '18:00', 'end_time': '20:00'},
          ],
          'certificates': [
            {'id': 3, 'title': 'شهادة إتمام المقرر مع مرتبة الشرف — Certificate of completion with honours'},
          ],
          'tools': [
            {'id': 4, 'title': 'Visual Studio Code with a very long tool name that has to wrap on a phone'},
          ],
          'prerequisites': [
            {'id': 5, 'title': 'أساسيات البرمجة'},
          ],
        });

    group('certificate requests body', () {
      testWidgets('loading → skeleton', (t) async {
        await expectNoLayoutErrors(
          t,
          () => CertificateRequestsBody(
            loading: true,
            error: null,
            count: 0,
            onRefresh: () async {},
            itemBuilder: (_, _) => const SizedBox(),
          ),
        );
      });

      testWidgets('failed first load → retry, not "no requests"', (t) async {
        await expectNoLayoutErrors(
          t,
          () => CertificateRequestsBody(
            loading: false,
            error: 'تعذّر الاتصال بالخادم — Could not reach the server, check the connection and try again',
            count: 0,
            onRefresh: () async {},
            itemBuilder: (_, _) => const SizedBox(),
          ),
        );
      });

      testWidgets('empty and list', (t) async {
        await expectNoLayoutErrors(
          t,
          () => CertificateRequestsBody(
            loading: false,
            error: null,
            count: 0,
            onRefresh: () async {},
            itemBuilder: (_, _) => const SizedBox(),
          ),
        );
        await expectNoLayoutErrors(
          t,
          () => CertificateRequestsBody(
            loading: false,
            error: null,
            count: 12,
            onRefresh: () async {},
            itemBuilder: (_, i) => ListTile(title: Text('Student request number $i')),
          ),
        );
      });
    });

    group('course editor pieces', () {
      testWidgets('progress status card (editable, loading, read-only)', (t) async {
        for (final editable in [true, false]) {
          await expectNoLayoutErrors(
            t,
            () => SingleChildScrollView(
              child: Column(children: [
                CourseProgressStatusCard(status: CourseStatus.inProgress, onChanged: (_) {}, editable: editable),
                CourseProgressStatusCard(status: CourseStatus.completed, onChanged: (_) {}, isLoading: true),
              ]),
            ),
          );
        }
      });

      testWidgets('currency selector + gradient button', (t) async {
        await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
            child: Column(children: [
              CurrencySelector(selected: AppCurrency.egp, onChanged: (_) {}, label: 'Currency'),
              GradientButton(label: 'حفظ ونشر المقرر — Save and publish', isLoading: false, onTap: () {}),
              const GradientButton(label: 'Saving', isLoading: true),
            ]),
          ),
        );
      });

      testWidgets('section card with removable rows', (t) async {
        await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
            child: SectionCard(
              icon: Icons.build_rounded,
              title: 'الأدوات المطلوبة — Required tools',
              items: const ['Flutter SDK', 'Android Studio with a long name that wraps on small phones', 'Git'],
              onAdd: () {},
              onRemove: (_) {},
            ),
          ),
        );
      });

      testWidgets('privacy card (public / private)', (t) async {
        for (final private in [false, true]) {
          final ctrl = TextEditingController(text: 'ABC123');
          addTearDown(ctrl.dispose);
          await expectNoLayoutErrors(
            t,
            () => SingleChildScrollView(
              child: CoursePrivacyCard(isPrivate: private, onChanged: (_) {}, codeCtrl: ctrl),
            ),
          );
        }
      });
    });

    group('teacher course page sections', () {
      testWidgets('details tab (schedules via AppTime, certificates, tools)', (t) async {
        await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
            child: TeacherCourseDetails(course: course(), onManageSchedule: () {}, onManageCertificate: (_) {}),
          ),
        );
      });
    });
  });

  group('live room, guest and video', () {
    for (final (name, screen, sharing, paused) in [
      ('paused', true, true, true),
      ('screen + audio, sharing', true, true, false),
      ('audio only', false, false, false),
    ]) {
      testWidgets('recording status banner ($name) never overflows', (tester) async {
        await expectNoLayoutErrors(
          tester,
          () => ColoredBox(
            color: LivePalette.bg,
            child: Align(
              alignment: Alignment.topCenter,
              child: RecordingStatusBanner(isScreenRecording: screen, isSharing: sharing, isPaused: paused),
            ),
          ),
        );
      });
    }

    testWidgets('connection stats panel with long values fits', (tester) async {
      final audio = {for (var i = 0; i < 6; i++) 'audio key number $i': 'value ${'9' * (i * 3 + 1)} kbps'};
      final video = {for (var i = 0; i < 8; i++) 'video key number $i': '${1920 + i}×1080 @ 30 fps · VP8'};
      await expectNoLayoutErrors(
        tester,
        () => ColoredBox(
          color: LivePalette.bg,
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: ParticipantStatsPanel(audio: audio, video: video),
          ),
        ),
      );
    });

    testWidgets('guest promo card fits', (tester) async {
      await expectNoLayoutErrors(tester, () => const SingleChildScrollView(child: GuestPromoCard()));
    });

    testWidgets('guest gate shows the locked state while browsing as a guest', (tester) async {
      GuestState.instance.start();
      addTearDown(GuestState.instance.stop);
      await expectNoLayoutErrors(
        tester,
        () => const GuestGate(icon: Icons.lock_rounded, messageKey: 'guest_locked_courses', child: SizedBox()),
      );
    });

    group('shareErrorText', () {
      setUp(() => AppConfig.lang = 'en');

      test('a platform error shows its short message, never the exception dump', () {
        final e = PlatformException(code: 'denied', message: 'Permission denied');
        expect(shareErrorText(e), 'Permission denied');
        expect(shareErrorText(PlatformException(code: 'no_display')), 'no_display');
      });

      test('an API error goes through apiErrorText', () {
        final e = const ApiException(statusCode: 500, message: 'Server error');
        expect(shareErrorText(e), isNot(contains('ApiException')));
      });

      test('anything else gets a plain hint in both languages', () {
        expect(shareErrorText(StateError('boom')), 'try again');
        AppConfig.lang = 'ar';
        expect(shareErrorText(StateError('boom')), isNot(contains('boom')));
      });
    });
  });

  group('course, materials, exams and Data Lab', () {
    const longName = 'مقدمة شاملة في هندسة البرمجيات والتصميم الكائني للأنظمة الكبيرة Software Engineering';

    testWidgets('course card parts: private flag + price tag (plain and on a coloured chip)', (tester) async {
      await expectNoLayoutErrors(tester, () => ListView(padding: const EdgeInsets.all(16), children: [
            const Align(alignment: AlignmentDirectional.centerStart, child: PrivateFlag()),
            const SizedBox(height: 12),
            CoursePriceTag(originalPrice: 1200, finalPrice: 900, discountActive: true, format: (v) => '${v.toStringAsFixed(0)} EGP'),
            const SizedBox(height: 12),
            Builder(
              builder: (context) => Container(
                color: context.colors.primary,
                padding: const EdgeInsets.all(8),
                child: CoursePriceTag(
                    originalPrice: 0, finalPrice: 0, discountActive: false, onColoredBackground: true, format: (v) => '$v'),
              ),
            ),
          ]));
    });

    testWidgets('course top bar: back + refresh + share + like + settings', (tester) async {
      await expectNoLayoutErrors(tester, () => Builder(
            builder: (context) => Container(
              color: context.colors.primary,
              padding: const EdgeInsets.all(8),
              child: CourseDetailsTopBar(
                showRefresh: true,
                onBack: () {},
                onRefresh: () async {},
                onShare: () {},
                onLike: () {},
                onSetting: () {},
                isFavorite: true,
              ),
            ),
          ));
    });

    testWidgets('session material: progress (in progress / complete), action buttons, exam tile', (tester) async {
      final pending = SessionExamInfo.fromJson(const {
        'id': 1, 'name': longName, 'passing_score': 60, 'question_count': 12, 'remaining_submissions': 2,
      });
      final retried = SessionExamInfo.fromJson(const {
        'id': 2, 'name': 'Quiz', 'passing_score': 50, 'question_count': 5, 'attempted': true, 'best_percentage': 40,
        'remaining_submissions': 1,
      });
      await expectNoLayoutErrors(tester, () => ListView(padding: const EdgeInsets.all(16), children: [
            const SessionProgressSection(totalMaterial: 7, completeMaterial: 3, isTeacher: false, isFull: false),
            const SizedBox(height: 12),
            const SessionProgressSection(totalMaterial: 4, completeMaterial: 4, isTeacher: false, isFull: true),
            const SizedBox(height: 12),
            Builder(
              builder: (context) => Wrap(spacing: 8, runSpacing: 8, children: [
                SessionActionBtn(icon: Icons.edit_rounded, label: 'تعديل المحاضرة', color: context.colors.primary, filled: true, onTap: () {}),
                SessionActionBtn(icon: Icons.delete_rounded, label: 'Delete', color: context.colors.danger, outlined: true, onTap: () {}),
                SessionActionBtn(icon: Icons.upload_rounded, label: 'Upload', color: context.colors.success, loading: true),
              ]),
            ),
            const SizedBox(height: 12),
            SessionExamTile(gate: SessionExamGate([pending]), isTeacher: true),
            const SizedBox(height: 12),
            SessionExamTile(gate: SessionExamGate([retried]), isTeacher: false, onOpen: () {}),
          ]));
    });

    testWidgets('Data Lab kit hero, hero stats and choice chips keep their look', (tester) async {
      await expectNoLayoutErrors(tester, () => ListView(padding: const EdgeInsets.all(16), children: [
            const AppHero(
              title: longName,
              subtitle: 'كل تغيير محفوظ مع من قام به ومتى — Every change is kept',
              icon: Icons.science_rounded,
              stats: [
                AppHeroStat(icon: Icons.people_rounded, value: '1,240', label: 'الطلاب Students'),
                AppHeroStat(icon: Icons.task_alt_rounded, value: '87%', label: 'Completion rate'),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              AppChoiceChip(label: 'الكل', selected: true, onTap: () {}, icon: Icons.done_all_rounded),
              AppChoiceChip(label: 'Needs review', selected: false, onTap: () {}),
            ]),
            const SizedBox(height: 12),
            AppPrimaryButton(label: 'Continue', onPressed: () {}, busy: true),
          ]));
    });
  });
}
