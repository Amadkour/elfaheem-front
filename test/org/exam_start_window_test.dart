// Round 3 of the paper-exam e2e: an online exam opening in two days showed "Start exam" (`can_start: true`) and the
// tap answered 409 `exam_not_started` with nothing on screen. The list now carries the start's own refusal
// (`start_block`, `opens_at`): the card says "Opens Thu 5 Nov, 11:00 AM" instead of Start, a tap says why, and a start
// the server still refuses shows its words (examRefusalText) — never a silent tap.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/exams/engine_exams_section.dart';
import 'package:flutter_education_app/features/exams/exam_taking.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

Map<String, dynamic> _exam(int id, String title, {bool canStart = true, Map<String, dynamic>? block, String? startsAt, bool withBlockKey = true}) => {
      'id': id, 'title': title, 'status': 'published', 'duration_minutes': 30, 'attempts_used': 0, 'attempts_allowed': 1,
      'can_start': canStart, 'paper_only': false, 'open_attempt_id': null, 'results': const [], 'starts_at': startsAt,
      if (withBlockKey) 'start_block': block,
      if (withBlockKey) 'opens_at': block?['opens_at'],
    };

const _notStarted = {
  'code': 'exam_not_started', 'message': 'لم يبدأ الاختبار بعد', 'message_en': 'The exam has not started yet.',
  'opens_at': '2026-11-05T09:00:00',
};

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });

  final before = DateTime.utc(2026, 11, 3, 12);

  test('when an exam opens: from start_block, or an older server\'s starts_at against the clock', () {
    final later = _exam(1, 'Quiz', canStart: false, block: _notStarted, startsAt: '2026-11-05T09:00:00');
    expect(examOpensAt(later), DateTime.utc(2026, 11, 5, 9));
    expect(engineExamStartable(later), isFalse);
    // a new server with no block: open, whatever starts_at says
    expect(examOpensAt(_exam(2, 'Open', startsAt: '2026-11-05T09:00:00')), isNull);
    // an older server (no start_block key) still said can_start true before the window: judged by starts_at
    final old = _exam(3, 'Old', startsAt: '2026-11-05T09:00:00', withBlockKey: false);
    expect(examOpensAt(old, now: before), DateTime.utc(2026, 11, 5, 9));
    expect(engineExamStartable(old, now: before), isFalse);
    expect(engineExamStartable(old, now: DateTime.utc(2026, 11, 5, 10)), isTrue);
    // other refusals are not an opening time
    expect(examOpensAt(_exam(4, 'Ended', canStart: false, block: const {'code': 'exam_ended', 'message': 'انتهى وقت الاختبار'})), isNull);
    expect(examParseUtc('2026-11-05T09:00:00Z'), DateTime.utc(2026, 11, 5, 9));
    expect(examParseUtc('2026-11-05T11:00:00+02:00'), DateTime.utc(2026, 11, 5, 9));
    expect(examParseUtc(null), isNull);
    expect(examParseUtc('nope'), isNull);
  });

  test('a refused start always says something, in the app\'s language', () {
    expect(examRefusalText('exam_not_started', 'لم يبدأ الاختبار بعد', const {'opens_at': '2026-11-05T09:00:00'}), startsWith('Opens Thu 5 Nov, '));
    expect(examRefusalText('exam_not_started', 'x', const {'starts_at': '2026-11-05T09:00:00'}), startsWith('Opens Thu 5 Nov, '));
    expect(examRefusalText('exam_ended', 'انتهى وقت الاختبار'), 'The exam has ended');
    // an unknown code: the server's words, its English ones in English
    expect(examRefusalText('brand_new', 'رسالة', const {'message_en': 'A new refusal.'}), 'A new refusal.');
    expect(examRefusalText('brand_new', 'رسالة'), 'رسالة');
    expect(examRefusalText(null, ''), 'The exam cannot be started now');
    expect(examStartBlockText(_exam(5, 'Used', canStart: false, block: const {'code': 'no_attempts_left', 'message': 'm'})), 'You have used all your attempts');
    expect(examStartBlockText(_exam(6, 'Open')), isNull);
    AppConfig.lang = 'ar';
    expect(examRefusalText('exam_not_started', 'x', const {'opens_at': '2026-11-05T09:00:00'}), startsWith('يفتح '));
    expect(examRefusalText('brand_new', 'رسالة', const {'message_en': 'A new refusal.'}), 'رسالة');
  });

  testWidgets('the card says when it opens instead of Start', (tester) async {
    await tester.pumpWidget(layoutHost(EngineExamCard(exam: _exam(1, 'CS101 Quiz 1 (online)', canStart: false, block: _notStarted), onOpen: () {})));
    expect(find.textContaining('Opens Thu 5 Nov'), findsOneWidget);
    expect(find.text('Start exam'), findsNothing);
    // an older server's can_start: true before the window: no Start either
    await tester.pumpWidget(layoutHost(EngineExamCard(exam: _exam(2, 'Old', startsAt: '2026-11-05T09:00:00', withBlockKey: false), onOpen: () {}, now: before)));
    expect(find.textContaining('Opens Thu 5 Nov'), findsOneWidget);
    expect(find.text('Start exam'), findsNothing);
    await tester.pumpWidget(layoutHost(EngineExamCard(exam: _exam(3, 'Used', canStart: false, block: const {'code': 'no_attempts_left', 'message': 'm'}), onOpen: () {})));
    expect(find.text('No attempts left'), findsOneWidget);
    await tester.pumpWidget(layoutHost(EngineExamCard(exam: _exam(4, 'Open'), onOpen: () {})));
    expect(find.text('Start exam'), findsOneWidget);
    await expectNoLayoutErrors(tester, () => EngineExamCard(exam: _exam(5, 'A very long midterm examination title that wraps on narrow phones', canStart: false, block: _notStarted), onOpen: () {}));
  });

  Future<FakeApi> section(WidgetTester tester, Map<String, dynamic> exam, {FakeHandler? start}) async {
    final fake = FakeApi({
      'GET /api/v1/exam/student/exams': (_) => {'items': [exam], 'server_time': '2026-11-03T12:00:00'},
      'POST /api/v1/exam/exams/${exam['id']}/attempts': ?start,
    }, latency: const Duration(milliseconds: 10))
      ..install();
    addTearDown(fake.uninstall);
    await tester.pumpWidget(ThemeConfigScope(
      provider: ThemeConfigProvider(api: ApiClient()),
      child: MaterialApp(navigatorKey: navigatorKey, home: const Scaffold(body: SingleChildScrollView(child: EngineExamsSection(courseId: 1)))),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return fake;
  }

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a tap on an exam that has not opened says when it opens and starts nothing', (tester) async {
    final fake = await section(tester, _exam(1, 'CS101 Quiz 1 (online)', canStart: false, block: _notStarted));
    await tester.tap(find.text('CS101 Quiz 1 (online)'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('Opens Thu 5 Nov'), findsNWidgets(2));          // the card's pill + the notice
    expect(fake.calls.where((c) => c.method == 'POST'), isEmpty);
    await drain(tester);
  });

  testWidgets('a start the server still refuses shows its reason', (tester) async {
    await section(tester, _exam(1, 'CS101 Quiz 1 (online)'),
        start: (_) => const FakeResponse(409, {'detail': {'code': 'exam_ended', 'message': 'انتهى وقت الاختبار', 'message_en': 'The exam has ended.'}}));
    await tester.tap(find.text('CS101 Quiz 1 (online)'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('The exam has ended'), findsOneWidget);
    await drain(tester);
  });
}
