// The grade-review camera capture (contract §5): the pure tally, the presentational HUD in every state, and the whole
// screen over a fake camera + FakeApi (a captured page goes to POST /mark-sessions/{id}/pages, a refusal holds the
// camera until acknowledged, a failed upload just lets the person shoot again).
import 'dart:typed_data';

import 'package:dio/dio.dart' show FormData;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/marks/mark_sessions_api.dart';
import 'package:flutter_education_app/features/shared/exam_engine/marks/review/grade_capture_logic.dart';
import 'package:flutter_education_app/features/shared/exam_engine/marks/review/grade_review_capture.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

const _pages = '/api/v1/exam/mark-sessions/7/pages';

MarkSession _session({int read = 0, int pending = 0}) => MarkSession.fromJson({
      'session': {'id': 7, 'course_id': 3, 'template_id': 2, 'mode': 'review', 'column_key': 'midterm', 'column_max': 20, 'paper_max': 50, 'status': 'open'},
      'counts': {'match': read, 'mismatch': 0, 'unreadable': 0, 'pending': pending, 'applied': 0, 'kept': 0},
    });

MarkPageOutcome _retake(String code) => MarkPageOutcome(MarkPageKind.retake, code: code);
const _dup = MarkPageOutcome(MarkPageKind.duplicate, code: 'page_duplicate');
const _err = MarkPageOutcome(MarkPageKind.error);

class _Cam implements OmrCamera {
  int photos = 0;
  @override
  Future<void> open({bool front = false}) async {}
  @override
  Widget preview() => const ColoredBox(color: Color(0xFF4A4F57));
  @override
  Future<OmrFrame?> frame({int maxSide = 640, int quality = 70}) async => null;
  @override
  Future<Uint8List?> photo() async => Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 9, 9, 9, ++photos]);
  @override
  bool get canTorch => false;
  @override
  bool get torchOn => false;
  @override
  Future<void> setTorch(bool on) async {}
  @override
  bool get canSwitch => false;
  @override
  Future<void> switchCamera() async {}
  @override
  Future<void> dispose() async {}
}

Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _hud({int sheets = 0, int read = 0, int waiting = 0, MarkPageOutcome? problem, bool checking = false}) => Padding(
      padding: const EdgeInsets.all(8),
      child: GradeCaptureHud(sheets: sheets, read: read, waiting: waiting, problem: problem, checking: checking, onRetake: () {}, onDismiss: () {}),
    );

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  group('GradeCaptureTally', () {
    test('starts from the session counts: sheets = read + waiting', () {
      final t = GradeCaptureTally(read: 9, waiting: 2);
      expect((t.sent, t.read, t.waiting, t.capturing), (11, 9, 2, false));
      expect(t.problem, isNull);
      expect(t.stage, GradeCaptureStage.idle);
    });

    test('a queued photo counts as a sheet and as waiting, and clears a problem', () {
      final t = GradeCaptureTally(read: 1)
        ..capturing = true
        ..problem = _retake('blurry');
      expect(t.stage, GradeCaptureStage.retake);
      t.queued();
      expect((t.sent, t.read, t.waiting, t.capturing), (2, 1, 1, false));
      expect(t.problem, isNull);
    });

    test('a refusal holds the camera; a plain error does not', () {
      final t = GradeCaptureTally()..capturing = true;
      expect(t.stage, GradeCaptureStage.checking);
      t.refused(_retake('too_dark'));
      expect(t.stage, GradeCaptureStage.retakeLight);
      expect(t.capturing, isFalse);
      t.problem = null;
      t.refused(_retake('blurry'));
      expect(t.stage, GradeCaptureStage.retake);
      t.refused(_dup);
      expect(t.stage, GradeCaptureStage.duplicate);
      t.refused(_err);
      expect(t.problem, isNull, reason: 'a network / 5xx error leaves no card: shoot again');
      expect(t.stage, GradeCaptureStage.idle);
      expect(t.sent, 0, reason: 'nothing was stored');
    });

    test('the server counts follow, and never lower the sheets sent', () {
      final t = GradeCaptureTally()
        ..queued()
        ..queued()
        ..queued();
      t.synced(1, 1);
      expect((t.sent, t.read, t.waiting), (3, 1, 1));
      t.synced(2, 3);
      expect((t.sent, t.read, t.waiting), (5, 2, 3), reason: 'another phone added sheets');
    });
  });

  group('texts', () {
    test('every refusal code has a sentence in both languages', () {
      for (final code in ['blurry', 'too_dark', 'too_bright', 'glare', 'page_not_found', 'not_this_sheet', 'something_else']) {
        for (final lang in ['ar', 'en']) {
          AppConfig.lang = lang;
          expect(gradeRetakeText(code), isNotEmpty, reason: '$code/$lang');
        }
      }
      AppConfig.lang = 'en';
      expect(gradeRetakeText('blurry'), contains('blurry'));
      expect(gradeRetakeText('too_dark'), contains('dark'));
      expect(gradeRetakeText('x', fallback: 'server says'), 'server says');
    });

    test('the counter reads "12 sheets · 9 read · 2 waiting" and has an Arabic form', () {
      expect(gradeCounterText(12, 9, 2), '12 sheets · 9 read · 2 waiting');
      expect(gradeCounterText(1, 0, 1), '1 sheet · 0 read · 1 waiting');
      AppConfig.lang = 'ar';
      expect(gradeCounterText(2, 1, 1), contains('ورقتان'));
    });
  });

  group('GradeCaptureHud states (no overflow at any size, language, text scale)', () {
    final states = <String, Widget Function()>{
      'idle': () => _hud(),
      'capturing': () => _hud(sheets: 3, read: 2, waiting: 1, checking: true),
      'rejected blurry': () => _hud(sheets: 3, read: 2, waiting: 1, problem: _retake('blurry')),
      'rejected dark': () => _hud(sheets: 3, read: 2, waiting: 1, problem: _retake('too_dark')),
      'duplicate': () => _hud(sheets: 3, read: 2, waiting: 1, problem: _dup),
      'uploading 14': () => _hud(sheets: 140, read: 126, waiting: 14),
      'done': () => _hud(sheets: 12, read: 12, waiting: 0),
    };
    for (final e in states.entries) {
      testWidgets(e.key, (tester) async {
        await expectNoLayoutErrors(tester, e.value);
      });
    }

    testWidgets('a refusal shows its reason and a Retake button; a duplicate shows a way out', (tester) async {
      var retakes = 0, dismissed = 0;
      Widget host(MarkPageOutcome p) =>
          layoutHost(GradeCaptureHud(sheets: 1, read: 0, waiting: 1, problem: p, onRetake: () => retakes++, onDismiss: () => dismissed++), scale: 1);
      await tester.pumpWidget(host(_retake('blurry')));
      expect(find.text(gradeRetakeText('blurry')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('omr.retake')));
      expect(retakes, 1);
      await tester.pumpWidget(host(_dup));
      expect(find.text('This sheet was already scanned'), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.retake')), findsNothing);
      await tester.tap(find.byTooltip('Hide'));
      expect(dismissed, 1, reason: 'the already-scanned card used to have no button at all');
    });

    testWidgets('targets are at least 48 and labelled', (tester) async {
      final h = tester.ensureSemantics();
      await tester.pumpWidget(layoutHost(_hud(sheets: 1, waiting: 1, problem: _retake('blurry'))));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.pumpWidget(layoutHost(_hud(sheets: 1, waiting: 1, problem: _dup)));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      h.dispose();
    });
  });

  group('GradeCaptureScreen over a fake camera and FakeApi', () {
    final replies = <Object>[];
    final forms = <FormData>[];
    FakeApi fake() => FakeApi({
          'POST $_pages': (o) {
            forms.add(o.data as FormData);
            return replies.length > 1 ? replies.removeAt(0) : replies.first;
          },
          'GET /api/v1/exam/mark-sessions/7': (_) => {
                'session': {'id': 7},
                'counts': {'pending': 0},
              },
        }, latency: const Duration(milliseconds: 20));

    setUp(() {
      replies.clear();
      forms.clear();
    });

    Future<FakeApi> open(WidgetTester tester, {MarkSession? session}) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final f = fake()..install();
      addTearDown(f.uninstall);
      await tester.pumpWidget(layoutHost(GradeCaptureScreen(session: session ?? _session(), camera: _Cam.new), scale: 1, scaffold: false));
      await _frames(tester, 3);
      return f;
    }

    Future<void> shoot(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel('Capture the paper'));
      await _frames(tester, 6);
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }

    testWidgets('a captured page is uploaded to .../pages as a camera image and counted as waiting', (tester) async {
      replies.add(const FakeResponse(202, {'page_id': 41, 'status': 'queued'}));
      final f = await open(tester);
      expect(find.text('no sheets · 0 read · 0 waiting'), findsOneWidget);
      await shoot(tester);
      expect(f.calls.where((c) => c.method == 'POST' && c.path == _pages), hasLength(1));
      expect(forms.single.fields.singleWhere((x) => x.key == 'source').value, 'camera');
      expect(forms.single.files.single.key, 'image');
      expect(find.text('1 sheet · 0 read · 1 waiting'), findsOneWidget);
      expect(find.text('Results (1)'), findsOneWidget);
      await close(tester);
    });

    testWidgets('a blurry photo shows the reason, holds the camera, and the Retake sends the next one', (tester) async {
      replies
        ..add(const FakeResponse(422, {
          'detail': {'code': 'blurry', 'message': 'x', 'message_en': 'The photo is blurry'}
        }))
        ..add(const FakeResponse(202, {'page_id': 42}));
      await open(tester);
      await shoot(tester);
      expect(find.byKey(const ValueKey('gr.problem.retake')), findsOneWidget);
      expect(find.text(gradeRetakeText('blurry')), findsOneWidget, reason: 'the app own sentence for the code wins over the server text');
      expect(find.bySemanticsLabel('Capture the paper'), findsNothing, reason: 'the shutter waits for the person');
      await tester.tap(find.byKey(const ValueKey('omr.retake')));
      await _frames(tester, 2);
      expect(find.byKey(const ValueKey('gr.problem.retake')), findsNothing);
      await shoot(tester);
      expect(forms, hasLength(2));
      expect(find.text('1 sheet · 0 read · 1 waiting'), findsOneWidget);
      await close(tester);
    });

    testWidgets('an already scanned sheet can be dismissed and the camera goes on', (tester) async {
      replies.add(const FakeResponse(409, {
        'detail': {'code': 'page_duplicate', 'message': 'dup'}
      }));
      await open(tester);
      await shoot(tester);
      expect(find.byKey(const ValueKey('gr.problem.duplicate')), findsOneWidget);
      await tester.tap(find.byTooltip('Hide'));
      await _frames(tester, 2);
      expect(find.byKey(const ValueKey('gr.problem.duplicate')), findsNothing);
      expect(find.bySemanticsLabel('Capture the paper'), findsOneWidget);
      await close(tester);
    });

    testWidgets('a failed upload (500) counts nothing and the next shot goes through', (tester) async {
      replies
        ..add(const FakeResponse(500, {'detail': 'boom'}))
        ..add(const FakeResponse(202, {'page_id': 43}));
      await open(tester, session: _session(read: 3, pending: 1));
      expect(find.text('4 sheets · 3 read · 1 waiting'), findsOneWidget);
      await shoot(tester);
      expect(find.text('4 sheets · 3 read · 1 waiting'), findsOneWidget);
      expect(find.byKey(const ValueKey('gr.problem.error')), findsNothing);
      await shoot(tester);
      expect(forms, hasLength(2));
      expect(find.text('5 sheets · 3 read · 2 waiting'), findsOneWidget);
      await close(tester);
    });

    testWidgets('no overflow on any size', (tester) async {
      replies.add(const FakeResponse(202, {'page_id': 1}));
      final f = fake()..install();
      addTearDown(f.uninstall);
      await expectNoLayoutErrors(tester, () => GradeCaptureScreen(session: _session(read: 12, pending: 3), camera: _Cam.new), scaffold: false);
      await close(tester);
    });
  });
}
