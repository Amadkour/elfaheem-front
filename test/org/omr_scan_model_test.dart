// The scanner's pure part (D-154, D-159; brief part 3): the engine's REAL replies parsed (recorded from
// wt-back-omr's e2e_omr_scan.py / e2e_omr_review.py into test/org/fixtures/omr_scan_payloads.json, never invented),
// the auto-capture decision (streak, disarm until the sheet changes), the live-hint pacing (503 omr_busy back-off),
// the sheets body, the pick checks and the server codes in both languages.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_engine_api.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scan.dart';
import 'package:flutter_test/flutter_test.dart';

final _all = (jsonDecode(File('test/org/fixtures/omr_scan_payloads.json').readAsStringSync()) as Map)['payloads'] as Map;

Map<String, dynamic> body(String name) => Map<String, dynamic>.from((_all[name] as Map)['body'] as Map);
int status(String name) => (_all[name] as Map)['status'] as int;

/// A failed engine call as engineCall builds it from the recorded body.
EngineResult fail(String name) {
  final d = Map<String, dynamic>.from(body(name)['detail'] as Map);
  return EngineResult.fail(status(name), d['code'] as String?, '${d['message'] ?? ''}', d);
}

OmrLiveHint hint(String name, {int w = 540, int h = 720}) => OmrLiveHint.fromJson(body(name), frameW: w, frameH: h);

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('recorded replies', () {
    test('live hint: ready, moving, too dark, corners, no sheet, blurry', () {
      final first = hint('hint_ready_first');
      expect((first.ok, first.code, first.cornersFound, first.en), (true, 'ready', 4, 'Hold still…'));
      expect(first.motion, isNull, reason: 'the first frame has no prev: steadiness unknown');
      expect(first.steady, isFalse);
      expect(first.stat, startsWith('48x64:'), reason: 'the 64-px thumbnail the next frame sends back as prev');
      expect(first.corners, hasLength(4));
      expect(first.cornerQuarters, [true, true, true, true]);

      final ready = hint('hint_ready');
      expect((ready.motion, ready.steady), (0.0, true));

      final moving = hint('hint_moving');
      expect((moving.ok, moving.code, moving.en), (false, 'moving', 'Hold steady.'));
      expect(moving.motion, greaterThan(6));

      final dark = hint('hint_too_dark');
      expect((dark.code, dark.en), ('too_dark', 'Too dark, move to better light.'));
      expect(dark.ar, 'الصورة مظلمة جدًا، انتقل إلى إضاءة أفضل.');
      expect(omrHintTone(dark.code), OmrHintTone.warn);

      final corners = hint('hint_corners');
      expect((corners.code, corners.cornersFound, corners.en), ('corners', 0, 'Show all four corner marks.'));
      expect(corners.cornerQuarters, [false, false, false, false]);

      expect(hint('hint_no_sheet').en, 'Fit the whole sheet inside the frame.');
      expect(hint('hint_blurry').en, 'Too blurry, hold steady.');

      AppConfig.lang = 'ar';
      expect(dark.text, 'الصورة مظلمة جدًا، انتقل إلى إضاءة أفضل.');
    });

    test('corner quarters follow the frame, not the reading direction', () {
      const h = OmrLiveHint(ok: false, code: 'corners', en: '', ar: '', corners: [Offset(10, 10), Offset(500, 12), Offset(498, 700)], frameW: 540, frameH: 720);
      expect(h.cornerQuarters, [true, true, true, false], reason: 'bottom-left is the one missing');
    });

    test('503 omr_busy and the readiness 409s', () {
      final busy = fail('hint_busy');
      expect((busy.status, busy.code, retryAfterOf(busy)), (503, 'omr_busy', 1));
      expect(omrErrorText(busy), 'The server is checking other photos. Try again in a moment.');
      AppConfig.lang = 'ar';
      expect(omrErrorText(busy), 'الخادم مشغول بفحص صور أخرى — أعد المحاولة بعد لحظة');
      AppConfig.lang = 'en';

      final nb = fail('sheets_exam_not_bubble');
      expect((nb.status, nb.code, omrIsSetupProblem(nb.code)), (409, 'exam_not_bubble', true));
      expect(omrErrorText(nb), 'This exam does not use a bubble sheet.');
      expect(omrIsSetupProblem(fail('hint_exam_not_bubble').code), isTrue, reason: 'template_not_found');
      expect(omrIsSetupProblem(busy.code), isFalse);
    });

    test('capture: accepted, a session, a duplicate, rejected with the exact reason', () {
      final a = OmrCaptureResult.fromJson(body('capture_accepted_1_of_3'));
      expect((a.accepted, a.captured, a.expected, a.text, a.duplicate), (true, 1, 3, 'Paper 1 of 3 captured', false));
      final s1 = OmrCaptureResult.fromJson(body('capture_session_1'));
      final s2 = OmrCaptureResult.fromJson(body('capture_session_2'));
      expect((s1.batchId, s2.batchId, s2.captured, s2.expected, s2.text), (s1.batchId, s1.batchId, 2, 40, 'Paper 2 of 40 captured'));
      final dup = OmrCaptureResult.fromJson(body('capture_session_duplicate'));
      expect((dup.accepted, dup.duplicate, dup.pageId), (true, true, s2.pageId));

      final blurry = OmrCaptureResult.fromJson(body('capture_rejected_blurry'));
      expect((blurry.accepted, blurry.code, blurry.text, blurry.batchId), (false, 'blurry', 'Too blurry, hold steady.', null));
      expect(blurry.moreIssues, isEmpty);
      final mark = OmrCaptureResult.fromJson(body('capture_mark_missing'));
      expect((mark.code, mark.text), ('mark_missing_bottom_left', 'Bottom-left corner mark is not visible.'));
      AppConfig.lang = 'ar';
      expect(mark.text, 'علامة الركن السفلي الأيسر غير ظاهرة.');

      final gone = fail('capture_batch_not_found');
      AppConfig.lang = 'en';
      expect((gone.status, gone.code, omrErrorText(gone)), (404, 'batch_not_found', 'This capture session was not found.'));
    });

    test('upload and progress: Example 5 (10-page PDF, page 7 rejected) and the live events', () {
      final up = OmrUploadReply.fromJson(body('upload_pdf'));
      expect((up.omr, up.pages.length, up.duplicates), (true, 10, 0));
      final dup = OmrUploadReply.fromJson(body('upload_duplicate'));
      expect(dup.pages, isEmpty);
      expect(dup.duplicates, 1);

      final p0 = OmrBatchProgress.fromJson(body('batch_processing'));
      expect((p0.batchId, p0.total, p0.done, p0.finished, p0.text, p0.fraction), (up.batchId, 10, 0, false, '0 of 10 papers processed', 0.0));
      final p = OmrBatchProgress.fromJson(body('batch_done'));
      expect((p.total, p.done, p.graded, p.rejected, p.review, p.finished), (10, 10, 9, 1, 0, true));
      final r = p.rejectedPages.single;
      expect((r.pageNo, r.label, r.text, r.instruction), (7, '7', 'Page 7 is too blurry. Please upload a clearer image of it.', 'Too blurry, hold steady.'));
      expect(r.codes, ['blurry']);
      AppConfig.lang = 'ar';
      expect(r.text, startsWith('الصفحة 7 '));
      expect(p.text, 'تمت معالجة 10 من 10 ورقة');
      AppConfig.lang = 'en';

      final events = [for (final e in _all['events_batch'] as List) Map<String, dynamic>.from(e as Map)];
      expect(events, hasLength(10));
      expect(events.first['kind'], kOmrScanJobKind);
      var live = p0;
      for (final e in events) {
        live = live.withEvent(e);
      }
      expect((live.done, live.total, live.finished, live.text), (10, 10, true, '10 of 10 papers processed'));
      expect(p0.withEvent(events[2]).text, '3 of 10 papers processed');
      expect(live.withEvent(events[0]).done, 10, reason: 'an event that arrives late never moves the count back');

      final cam = OmrBatchProgress.fromJson(body('camera_batch_progress'));
      expect((cam.kind, cam.expected, cam.graded), ('camera', 40, 2));
      final list = [for (final b in body('batches_list')['items'] as List) OmrBatchProgress.fromJson(Map<String, dynamic>.from(b as Map))];
      expect(list.map((b) => b.rejectedPages.length), everyElement(0), reason: 'list rows carry no rejected_pages');
    });

    test('sheets info and its errors', () {
      final s = OmrSheetsInfo.fromJson(body('sheets_info'));
      expect((s.printable, s.questions, s.sheetQuestions, s.idKind), (true, 6, 50, 'shaded'));
      expect(s.forms, ['A', 'B']);
      expect(s.sheetForms, ['A', 'B', 'C', 'D']);
      final ns = fail('sheets_not_a_student');
      expect(omrErrorText(ns), 'Not a student of this exam (#999)', reason: 'no message_en: our words, with the id');
      AppConfig.lang = 'ar';
      expect(omrErrorText(ns), 'طالب ليس من طلاب هذا الاختبار', reason: 'the server\'s Arabic sentence');
      final unsupported = fail('upload_unsupported');
      expect(unsupported.code, 'unsupported_file');
    });
  });

  group('auto-capture', () {
    final t0 = DateTime(2026, 11, 2, 9);
    final ready = hint('hint_ready');
    final first = hint('hint_ready_first');

    test('captures after a steady streak spanning the minimum time, never on the first frame', () {
      final g = AutoCaptureGate(streak: 3, minSpan: const Duration(milliseconds: 700));
      expect(g.feed(first, t0), isFalse, reason: 'no motion measured yet');
      expect(g.progress, 0);
      expect(g.feed(ready, t0.add(const Duration(milliseconds: 400))), isFalse);
      expect(g.feed(ready, t0.add(const Duration(milliseconds: 800))), isFalse);
      expect(g.progress, closeTo(2 / 3, 1e-9));
      expect(g.feed(ready, t0.add(const Duration(milliseconds: 1000))), isFalse, reason: '3 in a row but only 600 ms');
      expect(g.feed(ready, t0.add(const Duration(milliseconds: 1200))), isTrue);
    });

    test('a bad frame breaks the streak', () {
      final g = AutoCaptureGate(streak: 3, minSpan: Duration.zero);
      g.feed(ready, t0);
      g.feed(ready, t0);
      expect(g.feed(hint('hint_blurry'), t0), isFalse);
      expect(g.feed(ready, t0), isFalse);
      expect(g.feed(ready, t0), isFalse);
      expect(g.feed(ready, t0), isTrue);
    });

    test('after a capture it waits for the sheet to change (not for a blurry frame of the same sheet)', () {
      final g = AutoCaptureGate(streak: 2, minSpan: Duration.zero);
      g.feed(ready, t0);
      expect(g.feed(ready, t0), isTrue);
      g.captured();
      expect(g.armed, isFalse);
      for (var i = 0; i < 5; i++) {
        expect(g.feed(ready, t0), isFalse, reason: 'the same sheet is never sent twice by itself');
      }
      g.feed(hint('hint_blurry'), t0);
      g.feed(hint('hint_too_dark'), t0);
      expect(g.armed, isFalse, reason: 'light or focus changing is not a new sheet');
      g.feed(hint('hint_moving'), t0);
      expect(g.armed, isTrue, reason: 'the camera moved: a new sheet may come');
      g.feed(ready, t0);
      expect(g.feed(ready, t0), isTrue);
    });

    test('no sheet / corners re-arm too; reset() re-arms at once', () {
      final g = AutoCaptureGate(streak: 1, minSpan: Duration.zero)..captured();
      g.feed(hint('hint_no_sheet'), t0);
      expect(g.armed, isTrue);
      g.captured();
      g.feed(hint('hint_corners'), t0);
      expect(g.armed, isTrue);
      g.captured();
      g.reset();
      expect(g.feed(ready, t0), isTrue);
    });
  });

  group('live-hint pacing', () {
    test('a modest rate: the next frame leaves the interval after the last one', () {
      final p = HintPacer(interval: const Duration(milliseconds: 400));
      expect(p.afterOk(const Duration(milliseconds: 150)), const Duration(milliseconds: 250));
      expect(p.afterOk(const Duration(milliseconds: 900)), Duration.zero);
      // ≤ 2.5 frames / s: the server allows 300 / min
      expect(60000 / 400, lessThanOrEqualTo(300));
    });

    test('503 omr_busy backs off from Retry-After, doubling, capped; an answer resets it', () {
      final p = HintPacer(maxBackoff: const Duration(seconds: 8));
      expect(p.afterBusy(1), const Duration(seconds: 1));
      expect(p.afterBusy(1), const Duration(seconds: 2));
      expect(p.afterBusy(1), const Duration(seconds: 4));
      expect(p.afterBusy(1), const Duration(seconds: 8));
      expect(p.afterBusy(1), const Duration(seconds: 8));
      expect(p.failures, 5);
      p.afterOk(Duration.zero);
      expect(p.failures, 0);
      expect(p.afterBusy(null), const Duration(seconds: 1));
      expect(p.afterBusy(3), const Duration(seconds: 6));
    });

    test('429 waits the server window (capped at 30 s); network errors back off 1, 2, 4 …', () {
      final p = HintPacer();
      expect(p.afterRateLimit(60), const Duration(seconds: 30));
      expect(p.afterRateLimit(null), const Duration(seconds: 5));
      final q = HintPacer();
      expect([q.afterError(), q.afterError(), q.afterError(), q.afterError(), q.afterError()],
          const [Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 4), Duration(seconds: 8), Duration(seconds: 8)]);
    });
  });

  group('requests and checks', () {
    test('sheets body: blank × copies, or named (no copies)', () {
      expect(omrSheetsBody(forms: ['A', 'B'], copies: 30), {'forms': ['A', 'B'], 'copies': 30});
      expect(omrSheetsBody(copies: 900), {'copies': 500});
      expect(omrSheetsBody(forms: ['B'], studentIds: [110, 111]), {'forms': ['B'], 'student_ids': [110, 111]});
      expect(omrSheetsPageCount(forms: 2, copies: 30, students: 0), 60);
      expect(omrSheetsPageCount(forms: 0, copies: 5, students: 0), 5);
      expect(omrSheetsPageCount(forms: 2, copies: 30, students: 12), 12);
    });

    test('pick checks before sending: count, type, size', () {
      final small = Uint8List(10);
      expect(omrPickProblem([('a.jpg', small), ('b.PDF', small), ('c.webp', small)]), isNull);
      expect(omrPickProblem([for (var i = 0; i < 51; i++) ('p$i.png', small)]), omrCodeText('too_many_files'));
      expect(omrPickProblem([('notes.txt', small)]), omrCodeText('unsupported_file'));
      expect(omrPickProblem([('big.pdf', Uint8List(OmrLimits.maxFileBytes + 1))]), omrCodeText('file_too_large'));
      expect(omrPickProblem([('a.pdf', Uint8List(OmrLimits.maxFileBytes)), ('b.pdf', Uint8List(OmrLimits.maxFileBytes)), ('c.jpg', small)]),
          omrCodeText('upload_too_large'));
    });

    test('a photo is named after its bytes', () {
      expect(photoNameOf(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0])), 'camera.png');
      expect(photoNameOf(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0])), 'camera.jpg');
      expect(photoNameOf(Uint8List.fromList('RIFF0000WEBPVP8 '.codeUnits)), 'camera.webp');
    });

    test('every code has words in both languages', () {
      for (final code in ['exam_not_bubble', 'template_not_found', 'omr_busy', 'too_many_requests', 'batch_not_found', 'unsupported_file', 'grading_busy']) {
        AppConfig.lang = 'en';
        final en = omrCodeText(code);
        final unknownEn = omrCodeText('nope');
        AppConfig.lang = 'ar';
        final ar = omrCodeText(code);
        expect(en, isNot(ar), reason: code);
        expect(en, isNot(unknownEn), reason: code);
        expect(ar, isNot(omrCodeText('nope')), reason: code);
      }
    });
  });
}
