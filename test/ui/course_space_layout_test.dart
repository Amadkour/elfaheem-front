// The shared course page (CourseSpace) and its parts at 320×640 and 1400×900, ar / en, textScaler 1.3.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/course/course_space/course_space.dart';
import 'package:flutter_education_app/features/shared/course/studend_course_roadmap_section.dart';
import 'package:flutter_education_app/features/shared/session/session_track_tabs.dart';
import 'package:flutter_education_app/features/student/models.dart' show sessionInstantUtc;
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart' show CourseSchedule;
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'مقدمة شاملة جداً في الذكاء الاصطناعي وتعلم الآلة للمبتدئين والمحترفين A complete introduction';

CourseSpaceHeroData _hero({double? progress}) => CourseSpaceHeroData(
  title: _long,
  subtitle: '$_long $_long',
  category: 'البرمجة وعلوم الحاسب',
  isPrivate: true,
  privateLabel: 'خاص',
  badges: const [
    CourseSpaceBadge(label: 'بث مباشر Live sessions', icon: Icons.sensors_rounded),
    CourseSpaceBadge(label: 'شهادة Certificate', icon: Icons.workspace_premium_rounded),
  ],
  teacherName: 'د. عبد الرحمن محمد عبد الله الحسيني Dr. Abdelrahman',
  onTeacher: () {},
  stats: [
    const CourseSpaceStat(icon: Icons.groups_rounded, value: '12,480', label: 'طالب Students'),
    const CourseSpaceStat(icon: Icons.play_circle_outline_rounded, value: '148', label: 'درس Lessons'),
    CourseSpaceStat(icon: Icons.schedule_rounded, value: '96.5', label: 'ساعة Hours', onTap: () {}),
  ],
  progress: progress,
);

List<CourseSpaceAction> _actions() => [
  for (final (i, l) in ['ملف المقرر', 'الحضور والغياب', 'الطلاب المسجلون', 'المواعيد', 'الدعم الفني', 'مختبر البيانات'].indexed)
    CourseSpaceAction(icon: Icons.dashboard_customize_rounded, label: '$l Course profile', badge: i == 1 ? '12' : null, onTap: () {}),
];

List<CourseSpaceTab> _tabs() => [
  CourseSpaceTab(
    id: 'live',
    label: 'مباشر Live',
    icon: Icons.sensors_rounded,
    live: true,
    builder: (_) => const SizedBox(height: 40),
  ),
  CourseSpaceTab(
    id: 'lessons',
    label: 'الدروس Lessons',
    icon: Icons.play_lesson_rounded,
    count: 148,
    builder: (_) => Column(
      children: [
        CourseSectionHeader(title: 'الدروس $_long', count: 148, trailing: FilledButton(onPressed: () {}, child: const Text('Add'))),
        for (var i = 0; i < 6; i++) Container(height: 80, margin: const EdgeInsets.all(8), color: Colors.black12),
      ],
    ),
  ),
  CourseSpaceTab(id: 'exams', label: 'الاختبارات Exams', icon: Icons.assignment_rounded, builder: (_) => const SizedBox()),
  CourseSpaceTab(id: 'about', label: 'عن الكورس About', icon: Icons.info_outline_rounded, builder: (_) => _about()),
];

Widget _about() => Padding(
  padding: const EdgeInsets.all(kCourseGutter),
  child: Column(
    children: [
      CourseInfoSection(
        title: 'المواعيد الأسبوعية $_long',
        icon: Icons.calendar_month_rounded,
        trailing: TextButton(onPressed: () {}, child: const Text('Manage schedule')),
        children: [
          CourseScheduleChips(
            schedules: [
              for (var i = 0; i < 5; i++)
                CourseSchedule(id: i, courseId: 1, day: 'wednesday', startTime: '09:00', endTime: '10:30'),
            ],
          ),
        ],
      ),
      CourseInfoSection(
        title: 'الشهادات',
        icon: Icons.workspace_premium_rounded,
        children: [
          CourseInfoRow(
            title: _long,
            subtitle: '$_long $_long',
            trailing: TextButton(onPressed: () {}, child: const Text('إدارة الشهادة Manage certificate')),
          ),
        ],
      ),
    ],
  ),
);

List<Widget> _spotlight() => [
  const SizedBox.shrink(),
  CourseSpotlightCard(
    icon: Icons.sensors_rounded,
    title: 'بث مباشر الآن: $_long',
    subtitle: _long,
    live: true,
    filled: true,
    actionLabel: 'انضم الآن Join now',
    onAction: () {},
  ),
  CourseSpotlightCard(
    icon: Icons.play_circle_fill_rounded,
    title: 'تابع التعلم Continue learning',
    subtitle: 'الدرس 14: $_long',
    progress: 0.42,
    actionLabel: 'تابع Continue',
    onAction: () {},
  ),
  CourseReadinessCard(
    items: [
      const CourseReadinessItem(label: 'صورة الغلاف Cover image', done: true),
      CourseReadinessItem(label: 'الوصف والتفاصيل Description', done: false, onTap: () {}),
      CourseReadinessItem(label: 'المواعيد الأسبوعية Weekly schedule', done: false, onTap: () {}),
      CourseReadinessItem(label: 'أضف أول درس Add the first lesson', done: false, onTap: () {}),
    ],
  ),
];

Widget _space({String active = 'lessons', double? progress}) => StatefulBuilder(
  builder: (context, setState) => CourseSpace(
    hero: _hero(progress: progress),
    onBack: () {},
    topActions: [
      CourseSpaceTopAction(icon: Icons.ios_share_rounded, tooltip: 'share', onTap: () {}),
      CourseSpaceTopAction(icon: Icons.favorite_border_rounded, tooltip: 'like', selected: false, onTap: () {}),
      CourseSpaceTopAction(icon: Icons.edit_rounded, tooltip: 'تعديل الكورس Edit course', primary: true, onTap: () {}),
      CourseSpaceTopAction(icon: Icons.refresh_rounded, tooltip: 'refresh', overflow: true, onTap: () {}),
    ],
    onRefresh: () async {},
    spotlight: _spotlight(),
    actions: _actions(),
    tabs: _tabs(),
    activeTab: active,
    onTab: (_) {},
    aside: const CourseSideCard(child: SizedBox(height: 160)),
    bottomBar: Container(height: 72, color: Colors.black12),
    footer: const SizedBox(height: 200),
  ),
);

void main() {
  setUp(() => AppConfig.lang = 'ar');

  testWidgets('CourseSpace: every tab, enrolled and not', (t) async {
    for (final tab in ['lessons', 'about', 'live']) {
      await expectNoLayoutErrors(t, () => _space(active: tab, progress: tab == 'lessons' ? 0.64 : null));
    }
  });

  testWidgets('CourseSpace: scrolled with the tab bar pinned', (t) async {
    await expectNoLayoutErrors(
      t,
      () => _space(),
      act: (t) async {
        await t.drag(find.byType(CustomScrollView).first, const Offset(0, -900));
      },
    );
  });

  testWidgets('CourseSpace: a single tab draws no tab bar, no actions / spotlight', (t) async {
    await expectNoLayoutErrors(
      t,
      () => CourseSpace(
        hero: const CourseSpaceHeroData(title: 'X'),
        tabs: [CourseSpaceTab(id: 'a', label: 'A', icon: Icons.abc, builder: (_) => const Text('body'))],
        activeTab: 'a',
        onTab: (_) {},
      ),
    );
    expect(find.byType(CourseSpaceTabBar), findsNothing);
  });

  testWidgets('CourseReadinessCard hides itself when every step is done', (t) async {
    await t.pumpWidget(
      layoutHost(const CourseReadinessCard(items: [CourseReadinessItem(label: 'a', done: true)])),
    );
    expect(find.text('a'), findsNothing);
  });

  testWidgets('CourseSpaceSkeleton', (t) async {
    await expectNoLayoutErrors(t, () => const CourseSpaceSkeleton());
  });

  // ── the session timeline (shared by the student and the teacher) ──

  List<CourseSessionState> studentStates() => courseStudentStates([
    for (var i = 0; i < 10; i++) (live: i == 6, locked: i >= 8, done: i < 5, when: null),
  ]);

  Widget timeline({bool teacher = false}) {
    final states = studentStates();
    final fold = teacher ? 0 : courseSessionFoldCount(states);
    return SingleChildScrollView(
      child: CourseSessionsTimeline(
        itemCount: states.length,
        foldCount: fold,
        itemBuilder: (_, i) => CourseSessionTile(
          data: CourseSessionView(
            number: i + 1,
            title: '$_long ${i + 1}',
            subtitle: _long,
            kind: CourseSessionKind.values[i % 3],
            state: states[i],
            when: i == 7 ? DateTime.utc(2026, 11, 2, 15) : (i == 8 ? DateTime.utc(2026, 12, 2, 15) : null),
            durationMinutes: 95,
            materials: 12,
            materialsDone: i == 5 ? 4 : 0,
            showProgress: !teacher,
            hint: teacher && i == 9 ? 'لا مواد بعد No materials yet' : null,
          ),
          rail: courseSessionRail(states, i),
          group: i == 7 ? 'نوفمبر 2026 November' : (i == 8 ? 'ديسمبر 2026 December' : null),
          wide: true,
          onTap: () {},
          trailing: teacher
              ? const SizedBox(width: 40, height: 44, child: Icon(Icons.more_vert_rounded))
              : const CourseSessionChevron(open: false),
          below: states[i] == CourseSessionState.live
              ? Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    CourseSessionAction(label: 'دخول الغرفة Enter room', icon: Icons.videocam_rounded, filled: true, onTap: () {}),
                    CourseSessionAction(label: 'إنهاء End', loading: true, onTap: () {}),
                  ],
                )
              : null,
          panel: i == 5 ? const CourseSessionPanel(action: Text('Add'), footer: Text(_long), child: SizedBox(height: 60)) : null,
        ),
      ),
    );
  }

  testWidgets('hero top bar: inline actions in one capsule, the rest behind ⋮, every target 48 px', (t) async {
    await t.pumpWidget(layoutHost(SizedBox(height: 900, child: _space())));
    await t.pump();
    expect(find.byTooltip('refresh'), findsNothing); // overflow → the menu
    expect(find.byIcon(Icons.more_vert_rounded), findsWidgets);
    for (final tip in ['share', 'like']) {
      final size = t.getSize(find.descendant(of: find.byTooltip(tip), matching: find.byType(InkWell)).first);
      expect(size.width >= 48 && size.height >= 48, isTrue, reason: tip);
    }
  });

  test('month headers only when the dated sessions span two months', () {
    final a = DateTime.utc(2026, 10, 5, 12), b = DateTime.utc(2026, 10, 20, 12), c = DateTime.utc(2026, 11, 3, 12);
    String label(DateTime d) => '${d.month}';
    expect(courseSessionGroups([a, b, null], label: label), [null, null, null]);
    expect(courseSessionGroups([a, null, b, c, null], label: label), ['10', null, null, '11', null]);
    expect(courseSessionGroups([null, null], label: label), [null, null]);
  });

  testWidgets('session timeline: student (folded) and teacher rows', (t) async {
    await expectNoLayoutErrors(t, () => timeline());
    await expectNoLayoutErrors(t, () => timeline(teacher: true));
  });

  test('student states: live · locked · done, then ONE next', () {
    final s = studentStates();
    expect(s.sublist(0, 5).every((e) => e == CourseSessionState.done), isTrue);
    expect(s[5], CourseSessionState.next);
    expect(s[6], CourseSessionState.live);
    expect(s[7], CourseSessionState.open);
    expect(s.where((e) => e == CourseSessionState.next).length, 1);
    expect(s[8], CourseSessionState.locked);
  });

  test('teacher states: delivered · live · the soonest future is next', () {
    final now = DateTime.utc(2026, 10, 30, 12);
    final s = courseTeacherStates([
      (live: false, when: now.subtract(const Duration(days: 2)), minutes: 60),
      (live: true, when: null, minutes: 60),
      (live: false, when: now.add(const Duration(days: 5)), minutes: 60),
      (live: false, when: now.add(const Duration(days: 1)), minutes: 60),
      (live: false, when: null, minutes: 0),
    ], now: now);
    expect(s, [
      CourseSessionState.done,
      CourseSessionState.live,
      CourseSessionState.scheduled,
      CourseSessionState.next,
      CourseSessionState.open,
    ]);
  });

  test('rail and fold', () {
    final s = studentStates();
    expect(courseSessionRail(s, 0).top, isNull);
    expect(courseSessionRail(s, 0).bottom, CourseRailTone.done);
    expect(courseSessionRail(s, 5).top, CourseRailTone.done);
    expect(courseSessionRail(s, 5).bottom, CourseRailTone.plain);
    expect(courseSessionRail(s, 9).bottom, isNull);
    expect(courseSessionFoldCount(s), 5);
    expect(courseSessionFoldCount(s.sublist(0, 6)), 0); // short list
    expect(courseSessionFoldCount(List.filled(9, CourseSessionState.done)), 0); // nothing would be left
  });

  // N1: a session the server calls "complete" because it has nothing in it is not done ahead of time
  group('student session done', () {
    final now = DateTime.utc(2026, 10, 30, 12);
    bool done({required int materials, int completed = 0, bool server = true, DateTime? when, int minutes = 60}) =>
        courseStudentSessionDone(
          serverDone: server,
          materials: materials,
          materialsDone: completed,
          when: when,
          minutes: minutes,
          now: now,
        );

    test('a future session with no materials is not done', () {
      expect(done(materials: 0, when: now.add(const Duration(days: 3))), isFalse);
      // nor one with every file finished early: a future session is never done
      expect(done(materials: 2, completed: 2, when: now.add(const Duration(days: 3))), isFalse);
    });

    test('a past session with no materials is done only once it ended (and the server agrees)', () {
      expect(done(materials: 0, when: now.subtract(const Duration(days: 2))), isTrue);
      expect(done(materials: 0, when: now.subtract(const Duration(minutes: 30))), isFalse); // still running
      expect(done(materials: 0, server: false, when: now.subtract(const Duration(days: 2))), isFalse);
      expect(done(materials: 0, when: null), isFalse); // no date: it has not happened
    });

    test('partly done is not done', () {
      expect(done(materials: 4, completed: 2, server: false, when: now.subtract(const Duration(days: 1))), isFalse);
      expect(done(materials: 4, completed: 0, when: null), isFalse); // the server's flag alone is not enough
    });

    test('every file completed is done', () {
      expect(done(materials: 3, completed: 3, when: now.subtract(const Duration(days: 1))), isTrue);
      expect(done(materials: 3, completed: 3, when: null), isTrue);
      // the session's exam not passed yet: the server says not complete
      expect(done(materials: 3, completed: 3, server: false, when: null), isFalse);
    });

    test('32 future empty sessions: none done, none "next", nothing folds', () {
      final rows = [
        for (var i = 0; i < 32; i++)
          (
            live: false,
            locked: false,
            done: done(materials: 0, when: now.add(Duration(days: i + 1))),
            when: now.add(Duration(days: i + 1)),
          ),
      ];
      final states = courseStudentStates(rows, now: now);
      expect(states.every((e) => e == CourseSessionState.scheduled), isTrue);
      expect(courseSessionFoldCount(states), 0);
      // a stale "done" for a future row is still drawn as scheduled
      final stale = courseStudentStates([(live: false, locked: false, done: true, when: now.add(const Duration(days: 1)))], now: now);
      expect(stale.single, CourseSessionState.scheduled);
    });
  });

  test('hero stat nouns follow the number (L2)', () {
    final prev = translation;
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    addTearDown(() => translation = prev);
    AppConfig.lang = 'ar';
    expect(courseStatNoun(1, 'course_hero_students'), 'طالب');
    expect(courseStatNoun(4, 'course_hero_students'), 'طلاب');
    expect(courseStatNoun(32, 'course_hero_students'), 'طالب');
    expect(courseStatNoun(4, 'course_hero_lessons'), 'جلسات');
    expect(courseStatNoun(2.5, 'course_hero_hours'), 'ساعة');
    AppConfig.lang = 'en';
    expect(courseStatNoun(1, 'course_hero_students'), 'Student');
    expect(courseStatNoun(4, 'course_hero_students'), 'Students');
    expect(courseStatNoun(0, 'course_hero_students'), 'Students');
  });

  // H7: "Sessi… 4" — a label that does not fit beside its icon moves under it instead of being cut
  testWidgets('tab bar: real labels stay whole at phone widths', (t) async {
    addTearDown(() => t.binding.setSurfaceSize(null));
    for (final lang in ['en', 'ar']) {
      AppConfig.lang = lang;
      final en = lang == 'en';
      // (the test font draws every glyph a full em wide, so 320 is left to the harness and the renders)
      for (final w in [360.0, 390.0]) {
        await t.binding.setSurfaceSize(Size(w, 700));
        await t.pumpWidget(layoutHost(
          scale: 1.0,
          CourseSpaceTabBar(
            tabs: [
              CourseSpaceTab(id: 's', label: en ? 'Sessions' : 'الجلسات', icon: Icons.play_lesson_rounded, count: 4, builder: (_) => const SizedBox()),
              CourseSpaceTab(id: 'e', label: en ? 'Exams' : 'الاختبارات', icon: Icons.assignment_rounded, builder: (_) => const SizedBox()),
              CourseSpaceTab(id: 'a', label: en ? 'About' : 'عن الكورس', icon: Icons.info_outline_rounded, builder: (_) => const SizedBox()),
            ],
            active: 's',
            onTab: (_) {},
          ),
        ));
        final label = t.renderObject<RenderParagraph>(find.text(en ? 'Sessions' : 'الجلسات'));
        expect(label.didExceedMaxLines, isFalse, reason: '$lang @ $w');
        expect(find.text('4'), findsOneWidget, reason: 'the count stays on screen ($lang @ $w)');
      }
    }
  });

  List<CourseSpaceTab> teacherTabs() => [
        for (final (id, label, icon) in [
          ('s', 'Sessions', Icons.play_lesson_rounded),
          ('n', 'Announcements', Icons.campaign_rounded),
          ('t', 'Attendance', Icons.fact_check_rounded),
          ('m', 'Team', Icons.group_rounded),
          ('a', 'About', Icons.info_outline_rounded),
        ])
          CourseSpaceTab(id: id, label: label, icon: icon, builder: (_) => const SizedBox()),
      ];

  // Web QA round 7: five teacher tabs at 390 px drew "Announc…" / "Attenda…" under their icons
  testWidgets('tab bar: a label that does not fit under its icon scrolls the row instead of being cut', (t) async {
    addTearDown(() => t.binding.setSurfaceSize(null));
    AppConfig.lang = 'en';
    await t.binding.setSurfaceSize(const Size(390, 700));
    await t.pumpWidget(layoutHost(scale: 1.0, CourseSpaceTabBar(tabs: teacherTabs(), active: 's', onTab: (_) {})));
    for (final l in ['Announcements', 'Attendance']) {
      expect(t.renderObject<RenderParagraph>(find.text(l)).didExceedMaxLines, isFalse, reason: l);
    }
  });

  // Web QA round 7: picking the last tab scrolled the row to its end, the edge fade went away and took the row's
  // scroll position with it, so the picked tab was drawn off-screen
  testWidgets('tab bar: the last tab, once picked, stays in view', (t) async {
    addTearDown(() => t.binding.setSurfaceSize(null));
    AppConfig.lang = 'en';
    await t.binding.setSurfaceSize(const Size(390, 700));
    final student = [
      for (final (id, label) in [('l', 'Live'), ('s', 'Sessions'), ('e', 'Exams'), ('n', 'Announcements'), ('p', 'Progress'), ('a', 'About')])
        CourseSpaceTab(id: id, label: label, icon: Icons.info_outline_rounded, builder: (_) => const SizedBox()),
    ];
    Widget bar(String active) => layoutHost(scale: 1.0, CourseSpaceTabBar(tabs: student, active: active, onTab: (_) {}));
    await t.pumpWidget(bar('s'));
    await t.pumpAndSettle();
    await t.pumpWidget(bar('a'));
    await t.pumpAndSettle();
    await t.pumpWidget(bar('a')); // the pinned header rebuilds
    await t.pumpAndSettle();
    final about = t.getRect(find.text('About'));
    expect(about.left, greaterThanOrEqualTo(0));
    expect(about.right, lessThanOrEqualTo(390));
  });

  test('session length', () {
    AppConfig.lang = 'en';
    expect(courseSessionLength(0), '');
    expect(courseSessionLength(45), '45 min');
    expect(courseSessionLength(120), '2 h');
    expect(courseSessionLength(95), '1 h 35 min');
  });

  testWidgets('rating stars are icons, never glyphs', (t) async {
    await expectNoLayoutErrors(t, () => const CourseRatingStars(value: 3.5, count: 1200));
    await t.pumpWidget(layoutHost(const CourseRatingStars(value: 3.5, count: 1200)));
    expect(find.byIcon(Icons.star_half_rounded), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(3));
  });

  testWidgets('quick actions: more than fit → the row ends with "More", never cut at the edge', (t) async {
    await expectNoLayoutErrors(t, () => ListView(children: [CourseActionStrip(actions: [..._actions(), ..._actions()])]));
    await t.binding.setSurfaceSize(const Size(390, 844));
    await t.pumpWidget(layoutHost(ListView(children: [CourseActionStrip(actions: [..._actions(), ..._actions()])])));
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    await t.binding.setSurfaceSize(null);
  });

  testWidgets('roadmap: a course name keeps whole words (wide stops)', (t) async {
    await expectNoLayoutErrors(
      t,
      () => ListView(children: [
        CourseRoadmapSection(
          currentCourseName: 'أساسيات الخط العربي للمبتدئين Arabic calligraphy basics',
          nextCourses: const [],
          recommendedCourses: const [],
          similarCourses: const [],
          onTapCourse: (_) {},
        ),
      ]),
    );
  });

  testWidgets('session track tabs: labels and counts stay whole', (t) async {
    await expectNoLayoutErrors(
      t,
      () => SessionTrackTabs(value: 'lecture', lectures: 16, sections: 16, onChanged: (_) {}),
    );
  });

  test('a session time from the server is the real UTC instant (naive = UTC, H2)', () {
    expect(sessionInstantUtc('2026-11-08T06:30:00'), DateTime.utc(2026, 11, 8, 6, 30));
    expect(sessionInstantUtc('2026-11-08T06:30:00Z'), DateTime.utc(2026, 11, 8, 6, 30));
    expect(sessionInstantUtc('2026-11-08T08:30:00+02:00'), DateTime.utc(2026, 11, 8, 6, 30));
    expect(sessionInstantUtc(null), isNull);
    expect(sessionInstantUtc(''), isNull);
  });
}
