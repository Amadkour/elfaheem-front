// The course roadmap + recommendations UI (D-120) at 320×640 and 1400×900, ar / en, textScaler 1.3, with long
// Arabic names: the Path tab (student · teacher · empty), the editor, the home journey card + page, the profile's
// "Recommended for you" (loading · items · empty · off · failed) and the interests sheet. Plus: Reduce motion parks
// the journey card's light sweep.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_recs_page.dart';
import 'package:flutter_education_app/design/app_shine.dart';
import 'package:flutter_education_app/features/shared/roadmap/journey_page.dart';
import 'package:flutter_education_app/features/shared/roadmap/recommendations.dart';
import 'package:flutter_education_app/features/shared/roadmap/roadmap_api.dart';
import 'package:flutter_education_app/features/shared/roadmap/roadmap_editor.dart';
import 'package:flutter_education_app/features/shared/roadmap/roadmap_tab.dart';
import 'package:flutter_education_app/features/student/home/home_journey.dart';
import 'package:flutter_education_app/features/student/models.dart' show CourseSummary;
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'مقدمة شاملة جداً في الذكاء الاصطناعي وتعلم الآلة للمبتدئين والمحترفين A complete introduction to AI';

RmCourse _c(int id, {RmState? state, double progress = 0, List<RmPrereq> prereqs = const [], bool published = true, String? level = 'intermediate'}) =>
    RmCourse(
      id: id,
      nameAr: '$_long $id',
      nameEn: '$_long $id',
      level: level,
      field: const RmField(id: 7, nameAr: 'الذكاء الاصطناعي وتعلم الآلة', nameEn: 'Artificial intelligence and machine learning'),
      teacherName: 'منى عبد الرحمن',
      isPublished: published,
      finalPrice: 1499.5,
      state: state,
      progress: progress,
      prerequisites: prereqs,
      prereqsMet: prereqs.isEmpty ? null : prereqs.every((p) => p.done == true),
      order: id,
    );

const _pre = [
  RmPrereq(id: 1, nameAr: _long, nameEn: _long, done: true),
  RmPrereq(id: 2, nameAr: 'قواعد البيانات المتقدمة', nameEn: 'Advanced databases', done: false),
];

Roadmap _student() => Roadmap(
  course: _c(10, state: RmState.inProgress, progress: 42),
  previous: [_c(1, state: RmState.completed, progress: 100), _c(2, state: RmState.inProgress, progress: 30)],
  next: [_c(11, state: RmState.notStarted, prereqs: _pre), _c(12, state: RmState.completed), _c(13, state: RmState.inProgress, progress: 60)],
);

Roadmap _teacher() => Roadmap(
  course: _c(10),
  previous: [_c(1)],
  next: [_c(11, prereqs: const [RmPrereq(id: 1, nameAr: _long, nameEn: _long)]), _c(12, published: false, level: null)],
  canEdit: true,
);

final _picks = [
  for (var i = 0; i < 3; i++) CourseSummary(id: 50 + i, name: '$_long pick $i', imageUrl: '', price: 300, finalPrice: 300),
];

Journey _journey({bool steps = true}) => Journey(
  source: 'roadmap',
  field: const RmField(id: 7, nameAr: 'الذكاء الاصطناعي وتعلم الآلة', nameEn: 'Artificial intelligence and machine learning'),
  next: _c(12, state: RmState.notStarted).let((c) => RmCourse(id: c.id, nameAr: c.nameAr, nameEn: c.nameEn, kind: 'start')),
  done: 2,
  total: 5,
  steps: steps
      ? [
          _c(1, state: RmState.completed),
          _c(2, state: RmState.completed),
          RmCourse(id: 12, nameAr: '$_long 12', nameEn: '$_long 12', state: RmState.notStarted, current: true),
          _c(13, state: RmState.notStarted),
          _c(14, state: RmState.notStarted),
        ]
      : const [],
);

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

RecPage _recs() => RecPage(
  total: 9,
  items: [
    RecItem(course: _c(20), reason: 'because_completed', reasonAr: 'لأنك أكملت «$_long»', reasonEn: 'Because you completed “$_long”'),
    RecItem(course: _c(21), reason: 'same_teacher', reasonAr: 'من نفس المدرّس، منى عبد الرحمن', reasonEn: 'From the same instructor, Mona Abdelrahman'),
    RecItem(course: _c(22), reason: 'similar_students'),
  ],
);

Widget _scroll(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

void main() {
  setUp(() {
    AppConfig.lang = 'ar';
    AppConfig.disableList = [];
  });

  testWidgets('Path tab: student path with states, prerequisites, enroll-all and teacher picks', (t) async {
    await expectNoLayoutErrors(
      t,
      () => _scroll(RoadmapTabContent(roadmap: _student(), staff: false, onOpenCourse: (_) {}, onEnrollAll: () {}, teacherPicks: _picks, onOpenPick: (_) {})),
    );
    expect(find.text(AppConfig.lang == 'ar' ? 'أنت هنا' : 'You are here'), findsNothing, reason: 'harness pumps an empty box last');
  });

  testWidgets('Path tab: "You are here", the order and a prerequisite are on screen', (t) async {
    AppConfig.lang = 'en';
    final sem = t.ensureSemantics();
    await t.pumpWidget(layoutHost(_scroll(RoadmapTabContent(roadmap: _student(), staff: false, onOpenCourse: (_) {}, onEnrollAll: () {}))));
    await t.pump();
    expect(find.text('You are here'), findsOneWidget);
    expect(find.text('Step 1'), findsOneWidget);
    expect(find.text('Step 2 · Completed'), findsOneWidget);
    expect(find.text('Needs'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Advanced databases: not done yet')), findsOneWidget, reason: 'read as part of the card');
    expect(find.text('Enroll in the whole path'), findsOneWidget);
    AppConfig.disableList = ['course.enroll_roadmap'];
    await t.pumpWidget(layoutHost(_scroll(RoadmapTabContent(roadmap: _student(), staff: false, onOpenCourse: (_) {}, onEnrollAll: () {}))));
    expect(find.text('Enroll in the whole path'), findsNothing, reason: 'its kill switch hides it');
    sem.dispose();
  });

  testWidgets('Path tab: teacher view (drafts, Edit) and the empty path', (t) async {
    await expectNoLayoutErrors(t, () => _scroll(RoadmapTabContent(roadmap: _teacher(), staff: true, onEdit: () {}, onOpenCourse: (_) {})));
    await expectNoLayoutErrors(
      t,
      () => _scroll(RoadmapTabContent(roadmap: Roadmap(course: _c(10), canEdit: true), staff: true, onEdit: () {}, onOpenCourse: (_) {})),
    );
    await expectNoLayoutErrors(t, () => _scroll(RoadmapTabContent(roadmap: Roadmap(course: _c(10)), staff: false, onOpenCourse: (_) {})));
  });

  testWidgets('Editor: next courses, prerequisites, level, topic words', (t) async {
    await expectNoLayoutErrors(
      t,
      () => RoadmapEditorForm(
        draft: RoadmapDraft(
          next: [_c(11), _c(12, published: false), _c(13)],
          prereqs: [_c(1)],
          level: 'beginner',
          tags: ['الذكاء الاصطناعي', 'Machine learning', 'Python'],
        ),
        onAddNext: () {},
        onAddPrereq: () {},
        onChanged: () {},
      ),
    );
    await expectNoLayoutErrors(t, () => RoadmapEditorForm(draft: RoadmapDraft(), onAddNext: () {}, onAddPrereq: () {}, onChanged: () {}, canAdd: false));
  });

  testWidgets('Home journey card + the journey page', (t) async {
    await expectNoLayoutErrors(t, () => _scroll(HomeJourneyCard(journey: _journey(), onTap: () {})));
    await expectNoLayoutErrors(t, () => _scroll(HomeJourneyCard(journey: _journey(), onTap: () {}, onContinue: () {})));
    await expectNoLayoutErrors(t, () => _scroll(HomeJourneyCard(journey: _journey(steps: false), onContinue: () {})));
    await expectNoLayoutErrors(t, () => _scroll(HomeJourneyInvite(onPick: () {})));
    await expectNoLayoutErrors(t, () => _scroll(JourneyContent(journey: _journey(), onOpenCourse: (_) {}, onPickInterests: () {}, onMoreForYou: () {})));
    await expectNoLayoutErrors(t, () => _scroll(JourneyContent(journey: _journey(), onOpenCourse: (_) {})));
    await expectNoLayoutErrors(t, () => _scroll(JourneyContent(journey: _journey(steps: false), onOpenCourse: (_) {})));
  });

  testWidgets('Editor: a next course moves from its ⋮ menu (no drag needed)', (t) async {
    AppConfig.lang = 'en';
    final d = RoadmapDraft(next: [_c(11), _c(12), _c(13)]);
    await t.pumpWidget(layoutHost(StatefulBuilder(
      builder: (context, set) => RoadmapEditorForm(draft: d, onAddNext: () {}, onAddPrereq: () {}, onChanged: () => set(() {})),
    )));
    await t.tap(find.byTooltip('Options').at(2));
    await t.pumpAndSettle();
    await t.tap(find.text('Move up'));
    await t.pumpAndSettle();
    expect(d.next.map((c) => c.id), [11, 13, 12]);
    await t.tap(find.byTooltip('Options').first);
    await t.pumpAndSettle();
    final up = t.widget<PopupMenuItem<String>>(find.widgetWithText(PopupMenuItem<String>, 'Move up'));
    expect(up.enabled, isFalse, reason: 'the first one cannot move up');
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(d.next.map((c) => c.id), [13, 12]);
  });

  testWidgets('Admin: numbers per reason and the weights', (t) async {
    final stats = RecStats.fromJson({
      'days': 30,
      'students': 1240,
      'total': {'shown': 18420, 'opened': 2210, 'dismissed': 190, 'enrolled': 412},
      'by_reason': [
        for (final r in ['because_completed', 'similar_students', 'same_teacher', 'popular'])
          {'reason': r, 'shown': 4000, 'opened': 520, 'dismissed': 40, 'enrolled': 96, 'open_rate': 0.13, 'enroll_rate': 0.024},
      ],
      'weights': {'similar_students': 0.35, 'content': 0.3, 'same_teacher': 0.25, 'popularity': 0.1},
      'defaults': {'similar_students': 0.35, 'content': 0.3, 'same_teacher': 0.25, 'popularity': 0.1},
    });
    await expectNoLayoutErrors(
      t,
      () => _scroll(RecsAdminView(stats: stats, days: 30, weights: stats.weights, onDays: (_) {}, onWeight: (_, _) {}, onReset: () {}, onSave: () {})),
    );
    await expectNoLayoutErrors(
      t,
      () => _scroll(RecsAdminView(stats: const RecStats(), days: 7, weights: const {}, onDays: (_) {}, onWeight: (_, _) {}, onReset: () {}, onSave: () {})),
    );
  });

  testWidgets('Reduce motion parks the card\'s light sweep; otherwise it crosses and rests', (t) async {
    Widget card(bool still) => MediaQuery(
      data: MediaQueryData(disableAnimations: still),
      child: layoutHost(_scroll(HomeJourneyCard(journey: _journey(), onTap: () {}))),
    );
    await t.pumpWidget(card(true));
    await t.pump(const Duration(milliseconds: 600));
    final band = find.descendant(of: find.byType(AppShineBand), matching: find.byType(Transform));
    expect(band, findsNothing, reason: 'Reduce motion: no band');
    await t.pumpWidget(card(false));
    await t.pump(const Duration(milliseconds: 600));
    expect(band, findsOneWidget, reason: 'the band crosses in the first part of the cycle');
    await t.pump(const Duration(milliseconds: 1400));
    expect(band, findsNothing, reason: 'then rests out of sight for the rest of the 6 s');
    expect(t.binding.hasScheduledFrame, isFalse, reason: 'resting costs no frames (a timer starts the next pass)');
    await t.pump(const Duration(milliseconds: 4300));
    await t.pump(const Duration(milliseconds: 300));
    expect(band, findsOneWidget, reason: 'the next pass starts by itself');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Recommended for you: items with reasons, loading, empty, off, failed', (t) async {
    for (final view in [
      RecommendationsSectionView(page: _recs(), onOpen: (_) {}, onDismiss: (_) {}, onInterests: () {}, onSeeAll: () {}),
      RecommendationsSectionView(page: null, onOpen: (_) {}, onDismiss: (_) {}, onInterests: () {}),
      RecommendationsSectionView(page: const RecPage(), onOpen: (_) {}, onDismiss: (_) {}, onInterests: () {}),
      RecommendationsSectionView(page: const RecPage(hidden: true), onOpen: (_) {}, onDismiss: (_) {}, onInterests: () {}),
      RecommendationsSectionView(page: null, failed: true, onRetry: () {}, onOpen: (_) {}, onDismiss: (_) {}, onInterests: () {}),
    ]) {
      await expectNoLayoutErrors(t, () => _scroll(view));
    }
  });

  testWidgets('Recommended for you: a reason under each course, "See all" with the total', (t) async {
    AppConfig.lang = 'en';
    await t.pumpWidget(layoutHost(_scroll(RecommendationsSectionView(page: _recs(), onOpen: (_) {}, onDismiss: (_) {}, onInterests: () {}, onSeeAll: () {}))));
    expect(find.text('From the same instructor, Mona Abdelrahman'), findsOneWidget);
    expect(find.text('Students like you took this'), findsOneWidget);
    expect(find.text('See all (9)'), findsOneWidget);
    expect(find.byTooltip('Not interested'), findsNWidgets(3));
  });

  testWidgets('Interests sheet body', (t) async {
    final fields = [
      for (var i = 0; i < 14; i++) RmField(id: i, nameAr: i.isEven ? 'الذكاء الاصطناعي وتعلم الآلة $i' : 'تصميم $i', nameEn: 'Field number $i with a long name'),
    ];
    await expectNoLayoutErrors(
      t,
      () => InterestsForm(fields: fields, picked: {1, 4, 9}, show: true, inferred: true, onToggle: (_) {}, onShow: (_) {}),
    );
    final grouped = [
      for (var i = 0; i < 4; i++) ...[
        RmField(id: 100 + i, nameAr: 'المجال الرئيسي رقم $i', nameEn: 'Top field number $i'),
        for (var k = 0; k < 5; k++) RmField(id: 200 + i * 10 + k, nameAr: 'فرع طويل الاسم $k', nameEn: 'A sub-field with a long name $k', parentId: 100 + i),
      ],
    ];
    await expectNoLayoutErrors(
      t,
      () => InterestsForm(fields: grouped, picked: {100, 211}, show: true, hidden: 3, onShowHidden: () {}, onToggle: (_) {}, onShow: (_) {}),
    );
    await expectNoLayoutErrors(t, () => InterestsForm(fields: const [], picked: const {}, show: false, onToggle: (_) {}, onShow: (_) {}));
  });

  testWidgets('the owner opening the public page (a share link) gets the owner path', (t) async {
    AppConfig.lang = 'en';
    await t.pumpWidget(layoutHost(_scroll(CourseRoadmapBody(courseId: 10, staff: false, onOpenCourse: (_) {}, onEnrollAll: () {}, api: _OwnerApi()))));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('This course’s path'), findsOneWidget);
    expect(find.text('Edit path'), findsOneWidget);
    expect(find.text('Enroll in the whole path'), findsNothing);
    expect(find.text('Step 2 · Draft'), findsOneWidget, reason: 'drafts are marked for the owner');
  });

  testWidgets('the tab is not offered when the path is switched off', (t) async {
    AppConfig.disableList = ['roadmap'];
    expect(courseRoadmapTab(courseId: 1, staff: true, onOpenCourse: (_) {}), isNull);
    AppConfig.disableList = ['roadmap.path'];
    expect(courseRoadmapTab(courseId: 1, staff: true, onOpenCourse: (_) {}), isNull);
    AppConfig.disableList = [];
    expect(courseRoadmapTab(courseId: 1, staff: true, onOpenCourse: (_) {})?.id, kRoadmapTab);
  });
}

class _OwnerApi extends RoadmapApi {
  _OwnerApi();

  @override
  Future<Roadmap> roadmap(int courseId) async => _teacher();
}

// The same plain values for test/ui/roadmap_a11y_test.dart.
Roadmap rmStudentRoadmap() => _student();
Roadmap rmTeacherRoadmap() => _teacher();
Journey rmJourney() => _journey();
RecPage rmRecs() => _recs();
RmCourse rmCourse(int id, {bool published = true}) => _c(id, published: published);
List<CourseSummary> rmPicks() => _picks;
