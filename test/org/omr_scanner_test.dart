// The camera scanner and the upload progress over the fake backend (D-159; brief 3.1 – 3.4, Example 5), with a fake
// camera (no platform object). Every reply is a recorded one (test/org/fixtures/omr_scan_payloads.json):
//   • auto-capture: steady "ready" hints → the photo goes to /omr/capture → "Paper 1 of 40 captured" + the count;
//     the same sheet is not sent again until the scene changes; the second photo carries the session's batch_id
//   • rejected: the exact reason + Retake, the live hints wait; Retake resumes; the manual shutter works too
//   • 503 omr_busy: the hint loop backs off (far fewer frames) and says the server is busy
//   • a blocked camera: the fix and "Upload images or PDFs instead", no dead end
//   • upload → "X of N papers processed" from the live job_updated events → done with page 7 rejected → Replace
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart' show FormData, RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_camera.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scanner_screen.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_upload_screen.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

final _all = (jsonDecode(File('test/org/fixtures/omr_scan_payloads.json').readAsStringSync()) as Map)['payloads'] as Map;

Object? _reply(String name) {
  final p = _all[name] as Map;
  final status = p['status'] as int;
  return status == 200 ? p['body'] : FakeResponse(status, p['body']);
}

Map<String, dynamic> _body(String name) => Map<String, dynamic>.from((_all[name] as Map)['body'] as Map);

class FakeCamera implements OmrCamera {
  FakeCamera({this.issue});
  final OmrCameraIssue? issue;
  int frames = 0, photos = 0;

  @override
  Future<void> open({bool front = false}) async {
    if (issue != null) throw OmrCameraException(issue!);
  }

  @override
  Widget preview() => const ColoredBox(color: Color(0xFF4A4F57));

  @override
  Future<OmrFrame?> frame({int maxSide = 640, int quality = 70}) async {
    frames++;
    return OmrFrame(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]), 540, 720);
  }

  @override
  Future<Uint8List?> photo() async {
    photos++;
    return Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 9, 9, 9, photos]);
  }

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

/// The scanner's backend: hints and captures answered from queues (the last answer repeats).
class _Scanner {
  final hints = <String>[];
  final captures = <String>[];
  final captureFields = <Map<String, String>>[];
  var hintCalls = 0;

  Object? _next(List<String> q) => _reply(q.length > 1 ? q.removeAt(0) : q.first);

  FakeApi fake() => FakeApi({
        'POST /api/v1/exam/exams/1/omr/live-hint': (_) {
          hintCalls++;
          return _next(hints);
        },
        'POST /api/v1/exam/exams/1/omr/capture': (RequestOptions o) {
          final form = o.data as FormData;
          captureFields.add({for (final f in form.fields) f.key: f.value});
          return _next(captures);
        },
      }, latency: const Duration(milliseconds: 20));
}

Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<FakeApi> _openScanner(WidgetTester tester, _Scanner s, FakeCamera cam) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  final fake = s.fake()..install();
  addTearDown(fake.uninstall);
  await tester.pumpWidget(layoutHost(
      OmrScannerScreen(
        examId: 1,
        examTitle: 'Outcomes quiz',
        camera: () => cam,
        // the steady run's time follows the frames sent (the fake clock does not move DateTime.now)
        clock: () => DateTime(2026, 11, 2).add(Duration(milliseconds: 420 * s.hintCalls)),
      ),
      scale: 1,
      scaffold: false));
  await _frames(tester, 2);
  return fake;
}

Future<void> _done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

final _connected = ValueNotifier<bool>(true);
final _stream = LiveStreamHandle(connected: _connected, bind: () {}, release: () {});

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  testWidgets('auto-capture: steady hints → "Paper 1 of 40 captured"; the same sheet is not sent twice; the session continues',
      (tester) async {
    final s = _Scanner()
      ..hints.addAll(['hint_ready_first', 'hint_ready'])
      ..captures.addAll(['capture_session_1', 'capture_session_2']);
    final cam = FakeCamera();
    final fake = await _openScanner(tester, s, cam);
    expect(find.text('Hold still…'), findsOneWidget, reason: 'the server\'s own sentence');
    await _frames(tester, 14);
    expect(cam.photos, 1, reason: 'captured by itself after the steady run');
    expect(find.text('Paper 1 of 40 captured'), findsOneWidget);
    expect(find.text('1 of 40'), findsOneWidget, reason: 'the count in the top bar');
    expect(s.captureFields.single.containsKey('batch_id'), isFalse, reason: 'the first photo opens the session');

    // the sheet is still there and still "ready": nothing more is sent
    await _frames(tester, 30);
    expect(cam.photos, 1);
    expect(find.text('Take the paper away and place the next one'), findsOneWidget);

    // the next sheet: the camera moves, then steady again
    s.hints
      ..clear()
      ..addAll(['hint_moving', 'hint_ready_first', 'hint_ready']);
    await _frames(tester, 24);
    expect(cam.photos, 2);
    expect(find.text('Paper 2 of 40 captured'), findsOneWidget);
    expect(find.text('2 of 40'), findsOneWidget);
    expect(s.captureFields.last['batch_id'], '${_body('capture_session_1')['batch_id']}', reason: 'the same camera session');
    expect(find.text('Finish (2)'), findsOneWidget);
    expect(fake.unmatched, isEmpty);
    expect(tester.takeException(), isNull);
    await _done(tester);
  });

  testWidgets('rejected: the exact reason + Retake, nothing more is sent until Retake; the manual shutter', (tester) async {
    final s = _Scanner()
      ..hints.addAll(['hint_ready_first', 'hint_ready'])
      ..captures.addAll(['capture_rejected_blurry']);
    final cam = FakeCamera();
    await _openScanner(tester, s, cam);
    await _frames(tester, 14);
    expect(cam.photos, 1);
    expect(find.text('Too blurry, hold steady.'), findsOneWidget);
    expect(find.text('Nothing was saved or graded. Take it again.'), findsOneWidget);
    expect(find.byKey(const ValueKey('omr.retake')), findsOneWidget);
    expect(find.text('Finish (0)'), findsNothing, reason: 'the controls give way to Retake');
    final before = s.hintCalls;
    await _frames(tester, 20);
    expect(s.hintCalls, before, reason: 'the live hints wait while the reason is shown');

    await tester.tap(find.byKey(const ValueKey('omr.retake')));
    await _frames(tester, 3);
    expect(find.text('Too blurry, hold steady.'), findsNothing);
    expect(s.hintCalls, greaterThan(before), reason: 'Retake resumes the guidance');

    // the manual shutter, a covered corner mark
    s.captures
      ..clear()
      ..add('capture_mark_missing');
    s.hints
      ..clear()
      ..add('hint_corners');
    await _frames(tester, 3);
    await tester.tap(find.bySemanticsLabel('Capture the paper'));
    await _frames(tester, 4);
    expect(find.text('Bottom-left corner mark is not visible.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _done(tester);
  });

  testWidgets('503 omr_busy: the hint loop backs off and says so', (tester) async {
    final s = _Scanner()..hints.add('hint_busy');
    await _openScanner(tester, s, FakeCamera());
    await _frames(tester, 100); // 10 s
    // 1 s, 2 s, 4 s, 8 s apart: at most 5 frames in 10 s (the steady rate would be ~24)
    expect(s.hintCalls, inInclusiveRange(3, 5));
    expect(find.text('The server is checking other photos. Try again in a moment.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _done(tester);
  });

  testWidgets('a blocked camera shows the fix and a way out', (tester) async {
    final s = _Scanner()..hints.add('hint_ready');
    await _openScanner(tester, s, FakeCamera(issue: OmrCameraIssue.blocked));
    await _frames(tester, 2);
    expect(find.text('The camera is blocked'), findsOneWidget);
    expect(find.text('Upload images or PDFs instead'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(s.hintCalls, 0);
    AppConfig.lang = 'ar';
    await tester.pumpWidget(const SizedBox());
    await _openScanner(tester, s, FakeCamera(issue: OmrCameraIssue.noCamera));
    await _frames(tester, 2);
    expect(find.text('لا توجد كاميرا'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _done(tester);
  });

  testWidgets('upload: X of N from the live events, page 7 rejected with its sentence, "Replace this page"', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    var done = false;
    final batchGets = <String>[];
    final uploads = <List<String>>[];
    final fake = FakeApi({
      'POST /api/v1/exam/exams/1/scans': (o) {
        uploads.add([for (final f in (o.data as FormData).files) f.value.filename ?? '']);
        return uploads.length == 1 ? _reply('upload_pdf') : _reply('upload_single');
      },
      'GET /api/v1/exam/exams/1/omr/batches/*': (o) {
        batchGets.add(o.uri.pathSegments.last);
        if (o.uri.pathSegments.last == '${_body('upload_single')['batch_id']}') {
          // the list row of that very batch (a single GET adds only rejected_pages: [])
          final items = (_body('batches_list')['items'] as List).cast<Map>();
          return {...items.firstWhere((b) => b['batch_id'] == _body('upload_single')['batch_id']), 'rejected_pages': const []};
        }
        return done ? _reply('batch_done') : _reply('batch_processing');
      },
    }, latency: const Duration(milliseconds: 20))
      ..install();
    addTearDown(fake.uninstall);
    final pdf = Uint8List.fromList(utf8.encode('%PDF-1.4 ten pages'));
    await tester.pumpWidget(layoutHost(
        OmrScanProgressScreen(
          examId: 1,
          files: [('batch.pdf', pdf)],
          picker: ({bool many = true}) async => [('page7-again.jpg', Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 7]))],
          liveBus: LiveEvents.instance,
          liveStream: _stream,
        ),
        scale: 1,
        scaffold: false));
    await _frames(tester, 3);
    expect(uploads.single, ['batch.pdf']);
    expect(find.text('0 of 10 papers processed'), findsOneWidget);

    final events = [for (final e in _all['events_batch'] as List) Map<String, dynamic>.from(e as Map)];
    LiveEvents.instance.emit(LiveEvents.jobUpdated, {...events[2], 'id': '999'}); // another batch: ignored
    await _frames(tester, 2);
    expect(find.text('0 of 10 papers processed'), findsOneWidget);
    final gets = batchGets.length;
    LiveEvents.instance.emit(LiveEvents.jobUpdated, events[2]);
    await _frames(tester, 1);
    expect(find.text('3 of 10 papers processed'), findsOneWidget, reason: 'the event\'s own numbers at once');
    expect(batchGets.length, greaterThan(gets), reason: 'and a fetch on the event, not on a timer');

    done = true;
    LiveEvents.instance.emit(LiveEvents.jobUpdated, events.last);
    await _frames(tester, 3);
    expect(find.text('10 of 10 papers processed'), findsOneWidget);
    expect(find.text('Processing finished'), findsOneWidget);
    expect(find.text('Page 7 is too blurry. Please upload a clearer image of it.'), findsOneWidget);
    expect(find.text('Too blurry, hold steady.'), findsOneWidget);

    // finished: no more fetches on the slow cadence
    final settled = batchGets.length;
    await tester.pump(const Duration(seconds: 40));
    expect(batchGets.length, settled);

    // "Replace this page" is POST …/omr/pages/{id}/replace now (never a new upload batch): followed end to end with
    // that run's own replies in omr_review_written_test.dart ("replace a rejected page")
    final replace = find.byKey(ValueKey('omr.replace.${(_body('batch_done')['rejected_pages'] as List).first['page_id']}'));
    await tester.ensureVisible(replace);
    expect(replace, findsOneWidget);
    expect(uploads, hasLength(1), reason: 'nothing else was uploaded');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 20));
  });

  testWidgets('layout: the scanner at every size and language', (tester) async {
    final s = _Scanner()
      ..hints.add('hint_too_dark')
      ..captures.add('capture_rejected_blurry');
    final fake = s.fake()..install();
    addTearDown(fake.uninstall);
    await expectNoLayoutErrors(tester, () => OmrScannerScreen(examId: 1, examTitle: 'Outcomes quiz — mid-term paper', camera: FakeCamera.new),
        scaffold: false, frames: 8);
    await tester.pump(const Duration(seconds: 10));
  });
}
