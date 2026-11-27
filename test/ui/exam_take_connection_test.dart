// Taking an exam through a lost connection (D-1135): the real ExamTakingScreen over FakeApi.
//
// Saves fail while the network is down, so the answer stays in the queue and on the device, and submit refuses to
// finalise with unsaved answers. Once saves recover, a submit that drops on its way tells the student and leaves the
// exam open. A second submit then goes through exactly once, and a tap while it is on its way sends nothing.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/exams/exam_result_screen.dart';
import 'package:flutter_education_app/features/exams/exam_taking_screen.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

Map<String, dynamic> _start() => {
      'exam_session': 's1',
      'attempt': {
        'id': 7, 'state': 'in_progress', 'remaining_seconds': 1800, 'locked': false,
        'paper': {
          'sections': [
            {
              'section_id': 1, 'title': 'Part 1', 'mode': 'online', 'navigation': 'free',
              'questions': [
                {'question_id': 1, 'type': 'true_false', 'points': 1, 'answer': null, 'body': {'prompt': 'Water is a polar molecule.'}},
              ],
            },
          ],
        },
      },
    };

Never _drop(RequestOptions o) => throw DioException.connectionError(requestOptions: o, reason: 'offline');

void main() {
  setUpAll(() {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.disableList = [];
    AppConfig.lang = 'en';
  });

  testWidgets('answers survive a dropped connection and the exam is submitted exactly once', (tester) async {
    var online = false, submitOnline = false;
    var saves = 0, submits = 0;
    final fake = FakeApi({
      'PUT /api/v1/exam/attempts/7/answers': (o) {
        saves++;
        if (!online) _drop(o);
        final items = (o.data is Map ? (o.data as Map)['items'] : null) as List? ?? const [];
        return {'saved': [for (final i in items) (i as Map)['question_id']], 'ignored': [], 'rejected': [], 'remaining_seconds': 1700};
      },
      'POST /api/v1/exam/attempts/7/submit': (o) {
        submits++;
        if (!submitOnline) _drop(o);
        return {'result': {'visible': false, 'attempt_id': 7, 'state': 'submitted'}};
      },
      'POST /api/v1/exam/attempts/7/events': (o) => {'actions': [], 'state': 'in_progress'},
      'GET /api/v1/exam/attempts/7': (o) => {'remaining_seconds': 1700},
      'POST /api/v1/exam/attempts/7/session': (o) => {'exam_session': 's2'},
    }, latency: const Duration(milliseconds: 20))
      ..install();
    addTearDown(fake.uninstall);
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final theme = ThemeConfigProvider(api: ApiClient());
    await tester.pumpWidget(ThemeConfigScope(
      provider: theme,
      child: MaterialApp(navigatorKey: navigatorKey, theme: theme.materialTheme(dark: false), home: ExamTakingScreen(examTitle: 'Chemistry', startReply: _start(), deviceId: 'd1', examId: 3)),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    // 1 · offline: the answer is taken, the save fails, the answer is kept on the device
    await tester.tap(find.text('True'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 5));                  // the autosave tick
    expect(saves, greaterThan(0));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('exam.pending.7'), isNotNull, reason: 'the unsaved answer must survive on the device');

    // 2 · submit while saves still fail: refused, nothing sent to submit
    await tester.tap(find.byKey(const ValueKey('exam.submit')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));                // the hand-in sheet rises (M14)
    await tester.tap(find.byKey(const ValueKey('exam.submit.confirm')));   // the hand-in sheet
    await tester.pump(const Duration(seconds: 1));
    expect(submits, 0, reason: 'never finalise with unsaved answers');
    expect(find.byType(ExamTakingScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));                  // the toast goes

    // 3 · saves are back, the submit itself drops: the student is told, the exam stays open
    online = true;
    await tester.pump(const Duration(seconds: 5));
    expect(prefs.getString('exam.pending.7'), isNull, reason: 'saved on the server: the device copy is cleared');
    await tester.tap(find.byKey(const ValueKey('exam.submit')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));                // the hand-in sheet rises (M14)
    await tester.tap(find.byKey(const ValueKey('exam.submit.confirm')));
    await tester.pump(const Duration(seconds: 1));
    expect(submits, 1);
    expect(find.textContaining('The connection dropped before the exam was submitted'), findsOneWidget);
    expect(find.byType(ExamTakingScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));

    // 4 · back online: one submit goes through; a second tap while it is on its way sends nothing
    submitOnline = true;
    await tester.tap(find.byKey(const ValueKey('exam.submit')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));                // the hand-in sheet rises (M14)
    await tester.tap(find.byKey(const ValueKey('exam.submit.confirm')));
    await tester.pump(const Duration(milliseconds: 5));
    final bar = find.byKey(const ValueKey('exam.submit'));
    if (bar.evaluate().isNotEmpty) await tester.tap(bar.last, warnIfMissed: false);
    await tester.pump(const Duration(seconds: 2));
    expect(submits, 2, reason: 'one failed submit + exactly one that went through');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(ExamResultScreen), findsOneWidget);
    expect(find.byType(ExamTakingScreen), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
