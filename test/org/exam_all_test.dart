// "All exams" (D-300): the filters and counts, the one-call loader (and its fallback on an older engine), "New exam"
// places, the Google Forms start of a new exam, and every piece under the layout harness.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/exams/exam_all.dart';
import 'package:flutter_education_app/features/exams/exam_all_screen.dart';
import 'package:flutter_education_app/features/exams/exam_forms_import.dart';
import 'package:flutter_education_app/features/exams/exam_quick.dart';
import 'package:flutter_education_app/features/exams/exam_quick_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

Map<String, dynamic> _exam(int id, String title, {String status = 'draft', int? org, int? course, Map<String, dynamic>? settings, String? created}) => {
      'id': id,
      'title': title,
      'status': status,
      'org_id': org,
      'course_id': course,
      'settings': settings,
      'created_at': created ?? '2026-11-0${id % 9 + 1}T10:00:00',
      'question_count': id,
      'attempts': {'total': id * 2, 'by_state': {}},
    };

AllExamsData _data() => AllExamsData(
      exams: [
        AllExam(_exam(1, 'Algebra quiz', course: 10)),
        AllExam(_exam(2, 'Midterm — Physics, the long title of a midterm that keeps going past the width', status: 'published', org: 5, course: 20, settings: {'mode': 'offline'})),
        AllExam(_exam(3, 'Final file', status: 'closed', org: 5, course: 20, settings: {'paper_file': {'name': 'f.pdf'}})),
        AllExam(_exam(4, 'Old one', status: 'archived', course: 10)),
        AllExam(_exam(5, '', status: 'published')),
      ],
      courseNames: const {10: 'Mathematics', 20: 'Physics for the second year of secondary school'},
      courseOrgs: const {10: null, 20: 5},
      orgNames: const {5: 'Nile Academy'},
    );

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });
  setUp(() => AppConfig.lang = 'en');

  group('filters', () {
    test('status tabs, course, type and words', () {
      final d = _data();
      List<int> ids(AllExamsFilter f) => [for (final e in filterAllExams(d, f)) e.id];
      expect(ids(const AllExamsFilter()), isNot(contains(4)), reason: 'All leaves the archive out');
      expect(ids(const AllExamsFilter(status: 'archived')), [4]);
      expect(ids(const AllExamsFilter(status: 'published')).toSet(), {2, 5});
      expect(ids(const AllExamsFilter(courseId: 20)).toSet(), {2, 3});
      expect(ids(const AllExamsFilter(courseId: AllExamsFilter.noCourse)), [5]);
      expect(ids(const AllExamsFilter(type: AllExamType.paper)), [2]);
      expect(ids(const AllExamsFilter(type: AllExamType.file)), [3]);
      expect(ids(const AllExamsFilter(query: 'nile final')), [3], reason: 'every word, over title, course and organization');
      expect(ids(const AllExamsFilter(query: 'mathematics')), [1]);
      final counts = allExamCounts(d, const AllExamsFilter(courseId: 20));
      expect(counts[null], 2);
      expect(counts['closed'], 1);
      expect(counts['draft'], 0);
    });

    test('copyWith clears with null and keeps what is not named', () {
      const f = AllExamsFilter(query: 'x', status: 'draft', courseId: 3, type: AllExamType.online);
      final g = f.copyWith(courseId: null);
      expect(g.courseId, isNull);
      expect(g.status, 'draft');
      expect(g.type, AllExamType.online);
      expect(f.copyWith(status: null).status, isNull);
    });

    test('the course filter lists the courses with exams by name; New exam offers them, then no course', () {
      final d = _data();
      expect([for (final c in d.coursesWithExams) c.$2], ['Mathematics', 'Physics for the second year of secondary school']);
      final places = newExamPlaces(d);
      expect(places.first.courseId, 10);
      expect(places[1].orgId, 5);
      expect(places.last.courseId, isNull);
      expect(allExamMenu(d.exams.first), contains(AllExamAction.publish));
      expect(allExamMenu(d.exams[2]), isNot(contains(AllExamAction.paper)), reason: 'an uploaded exam file has no printable paper');
      expect(allExamMainAction(d.exams[1]), AllExamAction.results);
    });
  });

  group('loader', () {
    Future<FakeApi> backend(Map<String, FakeHandler> routes) async {
      final api = FakeApi(routes, latency: const Duration(milliseconds: 1))..install();
      addTearDown(api.uninstall);
      await ApiClient().primeSession();
      return api;
    }

    test('one engine call with the organizations and the taught courses; names of untaught org courses come after', () async {
      Map<String, dynamic>? mineQuery;
      final api = await backend({
        'GET /api/v1/my-courses': (o) => {
              'items': [
                {'id': 10, 'name_en': 'Mathematics', 'name_ar': 'الرياضيات'},
                {'id': 20, 'name_en': 'Physics', 'org': {'id': 5}},
              ],
            },
        'GET /api/v1/exam/exams/mine': (o) {
          mineQuery = o.queryParameters;
          return {
            'items': [_exam(1, 'A', course: 10), _exam(2, 'B', org: 5, course: 20), _exam(3, 'C', org: 5, course: 30)],
          };
        },
        'GET /api/v1/org/orgs/5/courses': (o) => {
              'items': [
                {'id': 30, 'name_en': 'Chemistry', 'name_ar': 'الكيمياء'},
              ],
            },
      });
      final d = await loadAllExams(orgs: const {5: 'Nile Academy', 2: 'Delta'});
      expect(mineQuery, containsPair('org_ids', '2,5'));
      expect(mineQuery, containsPair('course_ids', '10,20'));
      expect(d.fallback, isFalse);
      expect(d.exams.length, 3);
      expect(d.courseName(d.exams[2]), 'Chemistry');
      expect(d.orgName(d.exams[1]), 'Nile Academy');
      expect(d.courseOrgs[20], 5);
      expect(api.calls.where((c) => c.path.contains('/exams/mine')).length, 1);
    });

    test('an older engine (422 on /exams/mine) falls back to the per-space lists, without duplicates', () async {
      await backend({
        'GET /api/v1/my-courses': (o) => const FakeResponse(403, {'detail': 'teachers only'}),
        'GET /api/v1/exam/exams/mine': (o) => const FakeResponse(422, {'detail': [{'loc': ['path', 'exam_id']}]}),
        'GET /api/v1/exam/exams': (o) => o.queryParameters['org_id'] == null
            ? {'items': [_exam(1, 'mine')]}
            : {'items': [_exam(2, 'org'), _exam(1, 'mine')]},
      });
      final d = await loadAllExams(orgs: const {5: 'Nile'});
      expect(d.fallback, isTrue);
      expect([for (final e in d.exams) e.id], [1, 2]);
    });
  });

  test('a form becomes the new exam: its title, online, no questions yet', () async {
    final q = QuickExam(kind: QuickKind.quiz, courseId: 4, title: 'Quiz — Maths');
    const p = FormPreview(title: '  Chapter 3 quiz ', isQuiz: true, rows: [], skipped: []);
    expect(formExamTitle(p, q.title), 'Chapter 3 quiz');
    expect(formExamTitle(const FormPreview(title: '', isQuiz: true, rows: [], skipped: []), 'Quiz — Maths'), 'Quiz — Maths');
    expect(formExamTitle(const FormPreview(title: '', isQuiz: true, rows: [], skipped: []), ''), 'Google Forms exam');
  });

  group('layout', () {
    testWidgets('the body: loading, error, empty, cards and the dense list', (t) async {
      for (final body in [
        AllExamsBody(data: null, filter: const AllExamsFilter(), onFilter: (_) {}, onAction: (_, _) {}, onRetry: () {}, onNew: () {}),
        AllExamsBody(data: null, error: 'Could not reach the server', filter: const AllExamsFilter(), onFilter: (_) {}, onAction: (_, _) {}, onRetry: () {}, onNew: () {}),
        AllExamsBody(data: const AllExamsData(exams: []), filter: const AllExamsFilter(), onFilter: (_) {}, onAction: (_, _) {}, onRetry: () {}, onNew: () {}),
        AllExamsBody(data: _data(), filter: const AllExamsFilter(query: 'nothing at all'), onFilter: (_) {}, onAction: (_, _) {}, onRetry: () {}, onNew: () {}),
        AllExamsBody(data: _data(), filter: const AllExamsFilter(), busy: const {1}, onFilter: (_) {}, onAction: (_, _) {}, onRetry: () {}, onNew: () {}),
      ]) {
        await expectNoLayoutErrors(t, () => body);
      }
    });

    testWidgets('New exam: the course list', (t) async {
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: NewExamPlaceList(places: newExamPlaces(_data()), onPick: (_) {})));
    });

    testWidgets('the start chooser offers Google Forms only when asked', (t) async {
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: QuickStartChooser(onPick: (_) {}, canGenerate: true, canImportForms: true)),
          act: (t) async => expect(find.byKey(const ValueKey('exam.quick.forms')), findsOneWidget));
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: QuickStartChooser(onPick: (_) {}, canGenerate: true)),
          act: (t) async => expect(find.byKey(const ValueKey('exam.quick.forms')), findsNothing));
    });

    test('the kill switch hides the Google Forms start', () {
      final before = AppConfig.disableList;
      AppConfig.disableList = ['exam.google_forms_import'];
      addTearDown(() => AppConfig.disableList = before);
      expect(quickFormsAvailable, isFalse);
    });

    testWidgets('the Forms sheet in "new exam" mode', (t) async {
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
                child: GoogleFormsImportBody(
                  creating: true,
                  loading: false,
                  connected: true,
                  waiting: false,
                  preview: const FormPreview(title: 'Chapter 3', isQuiz: true, rows: [{'type': 'essay'}], skipped: []),
                  sections: const [],
                  sectionId: null,
                  onSection: (_) {},
                  report: null,
                  busy: false,
                  error: null,
                  onConnect: () {},
                  onPick: () {},
                  onImport: () {},
                  onDone: () {},
                ),
              ),
          act: (t) async => expect(find.text(AppConfig.lang == 'ar' ? 'إنشاء الاختبار' : 'Create the exam'), findsOneWidget));
    });
  });
}
