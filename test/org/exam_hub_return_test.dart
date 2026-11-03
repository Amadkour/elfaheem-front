// Round 3 of the paper-exam e2e, the teacher's exam hub:
//   - it kept its engine exams after an exam was created from another page: the engine section now reloads when the
//     hub is the page on screen again (PageReturnAware over topRouteObserver — no timer), not after a dialog;
//   - its third tile counted the engine exams' attempts (their list had no question figure): the list now carries
//     `question_count`, and the tile is Questions again, legacy + engine.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_review_screen.dart' show EngineReviewSection;
import 'package:flutter_education_app/features/student/analysis/exam/exam_ui.dart' show HeroStat;
import 'package:flutter_education_app/features/teacher/analysis/exam/teacher_exam_hub_screen.dart';
import 'package:flutter_education_app/utils/page_return.dart';
import 'package:flutter_education_app/utils/top_route_observer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

Map<String, dynamic> _exam(int id, String title, {int questions = 3}) => {
      'id': id, 'title': title, 'status': 'published', 'duration_minutes': 30, 'attempts': const {'total': 2},
      'question_count': questions,
    };

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });

  Future<void> frames(WidgetTester tester, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  final nav = GlobalKey<NavigatorState>();

  Widget app(Widget home) => ThemeConfigScope(
        provider: ThemeConfigProvider(api: ApiClient()),
        child: MaterialApp(navigatorKey: nav, navigatorObservers: [topRouteObserver], home: home),
      );

  test('which route shows the page', () {
    final a = MaterialPageRoute<void>(builder: (_) => const SizedBox());
    final b = MaterialPageRoute<void>(builder: (_) => const SizedBox());
    expect(pageRouteShown(a, a), isTrue);
    expect(pageRouteShown(b, a), isFalse);
    expect(pageRouteShown(null, a), isFalse);
    expect(pageRouteShown(a, null), isFalse);
  });

  testWidgets('the engine section reloads when its page is on screen again, not after a dialog', (tester) async {
    var items = [_exam(1, 'Engine exam 1')];
    final fake = FakeApi({'GET /api/v1/exam/exams': (_) => {'items': items}}, latency: const Duration(milliseconds: 10))..install();
    addTearDown(fake.uninstall);
    final got = <int>[];
    await tester.pumpWidget(app(Scaffold(body: SingleChildScrollView(child: EngineReviewSection(courseId: 1, onItems: (l) => got.add(l.length))))));
    await frames(tester);
    int lists() => fake.calls.where((c) => c.path == '/api/v1/exam/exams').length;
    expect(lists(), 1);
    expect(find.text('Engine exam 2'), findsNothing);

    // a dialog above the page: never left, no reload
    showDialog<void>(context: nav.currentContext!, builder: (_) => const AlertDialog(content: Text('hello')));
    await frames(tester);
    nav.currentState!.pop();
    await frames(tester);
    expect(lists(), 1);

    // another page (where the teacher creates an exam), then back: the new exam is there
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('elsewhere'))));
    await frames(tester);
    items = [_exam(2, 'Engine exam 2'), ...items];
    expect(lists(), 1);                                    // no polling while away
    nav.currentState!.pop();
    await frames(tester);
    expect(lists(), 2);
    expect(find.text('Engine exam 2'), findsOneWidget);
    expect(got, [1, 2]);
  });

  testWidgets('the hub\'s third tile counts questions, legacy + engine, and follows a return', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var items = [_exam(1, 'Engine exam 1', questions: 3), _exam(2, 'Engine exam 2', questions: 5)];
    final fake = FakeApi({
      'GET /api/v1/exam/exams': (_) => {'items': items},
      'GET /api/v1/courses/1/exams/all': (_) => const [
            {'id': 9, 'name': 'Old', 'course_id': 1, 'created_at': '2026-01-01T00:00:00', 'questions_count': 4},
          ],
      'GET /api/v1/courses/1/sessions': (_) => const {'items': <Object>[]},
    }, latency: const Duration(milliseconds: 10))
      ..install();
    addTearDown(fake.uninstall);
    await tester.pumpWidget(app(const TeacherExamHubScreen(courseId: 1, courseTitle: 'CS101')));
    await frames(tester, 12);
    // the hero's third tile (translation keys: the test loads no translation.json)
    Finder tile(String value) => find.ancestor(of: find.text(value), matching: find.byType(HeroStat));
    expect(find.descendant(of: tile('12'), matching: find.text('btn_questions')), findsOneWidget);    // 4 legacy + 3 + 5 engine
    expect(find.text('exam_hub_attempts'), findsNothing);
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('elsewhere'))));
    await frames(tester);
    items = [_exam(3, 'Engine exam 3', questions: 6), ...items];
    nav.currentState!.pop();
    await frames(tester, 12);
    expect(find.text('Engine exam 3'), findsOneWidget);
    expect(find.descendant(of: tile('18'), matching: find.text('btn_questions')), findsOneWidget);
  });

  testWidgets('layout: the hub with question counts at every size', (tester) async {
    final fake = FakeApi({
      'GET /api/v1/exam/exams': (_) => {'items': [_exam(1, 'A long engine exam title that wraps on a narrow phone screen', questions: 40)]},
      'GET /api/v1/courses/1/exams/all': (_) => const <Object>[],
      'GET /api/v1/courses/1/sessions': (_) => const {'items': <Object>[]},
    }, latency: const Duration(milliseconds: 10))
      ..install();
    addTearDown(fake.uninstall);
    await expectNoLayoutErrors(tester, () => const TeacherExamHubScreen(courseId: 1, courseTitle: 'CS101'), frames: 8);
  });
}
