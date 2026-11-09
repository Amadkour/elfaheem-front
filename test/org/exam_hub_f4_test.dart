import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/correct/exam_correct_flow.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/correct/sheet_models.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/correct/sheet_review_parts.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_camera.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scan.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scan_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

const _graded = <String, dynamic>{
  'ready': true,
  'page_id': 9,
  'status': 'review',
  'batch_id': 4,
  'image_url': '/api/v1/exam/omr/images/page/9?sig=x',
  'size': [1000, 2000],
  'student': {'id': 12, 'name': 'سارة أحمد', 'identifier_masked': '••4567'},
  'total': {'score': 17.5, 'max': 20},
  'review_count': 1,
  'questions': [
    {'question_id': 2, 'n': 2, 'state': 'ok', 'max': 1, 'score': 0, 'selected': ['B'], 'correct': ['C'], 'is_correct': false, 'row_box': [100, 300, 400, 40], 'marked_boxes': [[200, 300, 40, 40]], 'correct_boxes': [[300, 300, 40, 40]]},
    {'question_id': 1, 'n': 1, 'state': 'ok', 'max': 1.5, 'score': 1.5, 'selected': ['A'], 'correct': ['A'], 'is_correct': true, 'row_box': [100, 200, 400, 40], 'marked_boxes': [[100, 200, 40, 40]], 'correct_boxes': [[100, 200, 40, 40]]},
    {'question_id': 3, 'n': 3, 'state': 'multi', 'max': 1, 'score': null, 'selected': ['A', 'B'], 'correct': ['B'], 'is_correct': null, 'row_box': null, 'marked_boxes': <List<int>>[], 'correct_boxes': <List<int>>[]},
  ],
};

Uint8List _rgba(int w, int h, int Function(int x, int y) f) {
  final b = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = f(x, y), i = (y * w + x) * 4;
      b[i] = v;
      b[i + 1] = v;
      b[i + 2] = v;
      b[i + 3] = 255;
    }
  }
  return b;
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('the sheet payload', () {
    test('reads a graded sheet, sorted by question number', () {
      final v = SheetView.fromJson(_graded);
      expect(v.ready, isTrue);
      expect(v.source, const Size(1000, 2000));
      expect(v.studentName, 'سارة أحمد');
      expect(v.score, 17.5);
      expect(v.questions.map((q) => q.n), [1, 2, 3]);
      expect(v.questions.first.tone, SheetTone.right);
      expect(v.questions[1].tone, SheetTone.wrong);
      expect(v.questions[2].tone, SheetTone.open);
      expect(v.questions.first.degreeText, '1.5/1.5');
      expect(v.questions[2].degreeText, '–/1');
      expect((v.rightCount, v.wrongCount, v.openCount), (1, 1, 1));
      expect(v.canDraw, isTrue);
    });

    test('a page still being read carries only its id and status', () {
      final v = SheetView.fromJson({'ready': false, 'page_id': 3, 'status': 'processing'});
      expect((v.ready, v.dead, v.canDraw, v.source), (false, false, false, null));
      expect(SheetView.fromJson({'ready': false, 'page_id': 3, 'status': 'rejected'}).dead, isTrue);
    });

    test('no boxes or no size: the marks go in the list', () {
      final noBoxes = SheetView.fromJson({
        ..._graded,
        'questions': [
          {'question_id': 1, 'n': 1, 'max': 1, 'score': 1, 'selected': ['A'], 'correct': ['A'], 'is_correct': true, 'row_box': null, 'marked_boxes': <List<int>>[], 'correct_boxes': <List<int>>[]},
        ],
      });
      expect(noBoxes.canDraw, isFalse);
      expect(SheetView.fromJson({..._graded, 'size': null}).canDraw, isFalse);
    });

    test('malformed boxes are dropped, not fatal', () {
      expect(sheetRectOf([1, 2, 3]), isNull);
      expect(sheetRectOf([1, 2, 0, 4]), isNull);
      expect(sheetRectOf('x'), isNull);
      expect(sheetRectOf([1, 2, 3, 4]), const Rect.fromLTWH(1, 2, 3, 4));
    });
  });

  group('source pixels to the fitted photo', () {
    test('contain: a tall page in a wide box is centred by height', () {
      expect(sheetFitRect(const Size(1000, 500), const Size(100, 200)), const Rect.fromLTWH(375, 0, 250, 500));
      expect(sheetFitRect(const Size(100, 1000), const Size(100, 200)), const Rect.fromLTWH(0, 400, 100, 200));
      expect(sheetFitRect(Size.zero, const Size(100, 200)), Rect.zero);
    });

    test('a box lands where the fit says, and comes back', () {
      const source = Size(1000, 2000);
      final photo = sheetFitRect(const Size(500, 1000), source);
      final s = sheetToScreen(const Rect.fromLTWH(100, 200, 40, 80), source, photo);
      expect(s, const Rect.fromLTWH(50, 100, 20, 40));
      expect(sheetToSource(s.topLeft, source, photo), const Offset(100, 200));
    });

    test('a letterboxed fit shifts by the bars', () {
      const source = Size(1000, 2000);
      final photo = sheetFitRect(const Size(1000, 1000), source); // 500 wide, 250 from each side
      final s = sheetToScreen(const Rect.fromLTWH(0, 0, 1000, 2000), source, photo);
      expect(s, const Rect.fromLTWH(250, 0, 500, 1000));
    });

    test('a tap finds the question under it, through the fit', () {
      final v = SheetView.fromJson(_graded);
      const box = Size(500, 1000); // scale .5
      expect(sheetHitQuestion(const Offset(120, 110), v, box), 1); // row 1 is 100..500, 200..240 in source
      expect(sheetHitQuestion(const Offset(120, 160), v, box), 2);
      expect(sheetHitQuestion(const Offset(10, 900), v, box), isNull);
    });
  });

  group('walking the batch', () {
    test('Next opens the camera on the last paper only', () {
      expect(sheetNextOpensCamera(0, 3), isFalse);
      expect(sheetNextOpensCamera(2, 3), isTrue);
      expect(sheetNextOpensCamera(0, 0), isTrue);
    });

    test('a page not listed yet falls to the first row', () {
      const rows = [SheetRow(pageId: 5), SheetRow(pageId: 9)];
      expect(sheetIndexOf(rows, 9), 1);
      expect(sheetIndexOf(rows, 77), 0);
      expect(sheetIndexOf(const [], 9), -1);
    });

    test('only a final page state is worth a read', () {
      expect(sheetEventIsFinal('processed'), isTrue);
      expect(sheetEventIsFinal('review'), isTrue);
      expect(sheetEventIsFinal('rejected'), isTrue);
      expect(sheetEventIsFinal('processing'), isFalse);
    });
  });

  group('what the exam can do', () {
    test('a non-bubble exam, or scanning switched off, is the written flow', () {
      expect(correctionRouteOf(isBubble: false, ownSheet: false, omrOff: false), CorrectionRoute.written);
      expect(correctionRouteOf(isBubble: true, ownSheet: false, omrOff: true), CorrectionRoute.written);
    });

    test('an own sheet has no live camera', () {
      expect(correctionRouteOf(isBubble: true, ownSheet: true, omrOff: false), CorrectionRoute.uploadOnly);
      expect(correctionRouteOf(isBubble: true, ownSheet: false, omrOff: false), CorrectionRoute.cameraAndUpload);
    });

    test('totals add up over batches', () {
      final t = CorrectionTotals.of([
        OmrBatchProgress.fromJson({'batch_id': 1, 'total': 10, 'done': 8, 'graded': 6, 'review': 1, 'rejected': 1, 'pending': 2, 'en': '', 'ar': ''}),
        OmrBatchProgress.fromJson({'batch_id': 2, 'total': 5, 'done': 5, 'graded': 5, 'en': '', 'ar': ''}),
      ]);
      expect((t.total, t.done, t.graded, t.review, t.rejected, t.pending), (15, 13, 11, 1, 1, 2));
      expect(t.any, isTrue);
    });
  });

  group('the on-device gate', () {
    const rules = OmrFrameRules();
    OmrFrameStats sharpBright() => omrAnalyzeRgba(_rgba(640, 360, (x, y) => (x ~/ 6 + y ~/ 6).isEven ? 235 : 60), 640, 360);

    test('a dark frame is held; a sharp lit one passes', () {
      final dark = omrAnalyzeRgba(_rgba(640, 360, (x, y) => 10), 640, 360);
      expect(rules.issueOf(dark, sheetSeen: true), OmrLocalIssue.tooDark);
      expect(rules.issueOf(sharpBright(), sheetSeen: true), isNull);
      expect(sharpBright().sharp, greaterThan(rules.minSharp));
    });

    test('a burnt-out frame is held', () {
      final b = omrAnalyzeRgba(_rgba(640, 360, (x, y) => 255), 640, 360);
      expect(b.clipped, 1);
      expect(rules.issueOf(b), OmrLocalIssue.tooBright);
    });

    test('blur only counts once a sheet was seen: an empty desk gets the server\'s sentence', () {
      final soft = omrAnalyzeRgba(_rgba(640, 360, (x, y) => 150), 640, 360);
      expect(rules.issueOf(soft, sheetSeen: true), OmrLocalIssue.blurry);
      expect(rules.issueOf(soft, sheetSeen: false), isNull);
    });

    test('a swinging camera is held, a still one is not', () {
      final a = sharpBright();
      final b = omrAnalyzeRgba(_rgba(640, 360, (x, y) => (x ~/ 6 + y ~/ 6).isEven ? 60 : 235), 640, 360);
      expect(omrThumbMotion(a, a), 0);
      expect(rules.issueOf(b, prev: a, sheetSeen: true), OmrLocalIssue.moving);
      expect(rules.issueOf(a, prev: a, sheetSeen: true), isNull);
    });

    test('nothing measured never holds a frame', () {
      expect(rules.issueOf(omrAnalyzeRgba(Uint8List(0), 0, 0)), isNull);
    });

    test('the frame scale reaches the server\'s reference (long side about 360)', () {
      final s = omrAnalyzeRgba(_rgba(1280, 720, (x, y) => 120), 1280, 720);
      expect(s.thumbW, lessThanOrEqualTo(kOmrThumbSide));
      expect(s.mean, closeTo(120 * 256 / 256 - 1, 2));
    });
  });

  group('the resolution ladder', () {
    test('steps down only after several slow or empty frames in a row', () {
      final p = OmrRungPlan();
      expect(p.current, (2560, 1440));
      expect(p.feed(const Duration(seconds: 2)), isFalse);
      expect(p.feed(const Duration(milliseconds: 100)), isFalse); // the run is broken
      expect(p.feed(null), isFalse);
      expect(p.feed(const Duration(seconds: 2)), isFalse);
      expect(p.feed(const Duration(seconds: 2)), isTrue);
      p.stepDown();
      expect(p.current, (1920, 1080));
    });

    test('never past the bottom rung', () {
      final p = OmrRungPlan()
        ..stepDown()
        ..stepDown()
        ..stepDown();
      expect(p.current, (1280, 720));
      expect(p.canStepDown, isFalse);
      expect(p.feed(null), isFalse);
    });

    test('zoom cycles through its steps', () {
      expect(omrNextZoom(1), 1.5);
      expect(omrNextZoom(1.5), 2);
      expect(omrNextZoom(2), 1);
    });

    test('a tap on a cover-fitted preview maps to the frame', () {
      // a 16:9 frame, portrait view: the sides are cropped
      final mid = omrCoverPoint(const Offset(200, 400), const Size(400, 800), const Size(1600, 900));
      expect(mid.dx, closeTo(.5, 1e-9));
      expect(mid.dy, closeTo(.5, 1e-9));
      final left = omrCoverPoint(Offset.zero, const Size(400, 800), const Size(1600, 900));
      expect(left.dx, greaterThan(.3)); // the crop hides the left of the frame
      expect(left.dy, 0);
    });
  });

  group('no overflow', () {
    final png = Uint8List.fromList(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00,
      0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
      0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);

    Widget sheet({SheetView? view, bool camera = true}) => SheetReviewView(
          waitingName: 'A student with a rather long name indeed for a phone',
          view: view,
          photo: png,
          position: 'Paper 3 of 12',
          nextIsCamera: camera,
          onBack: () {},
          onPrev: () {},
          onNext: () {},
          onFinish: () {},
          onQuestion: (_) {},
          onReview: () {},
          onRetake: () {},
        );

    testWidgets('a graded paper', (tester) => expectNoLayoutErrors(tester, () => sheet(view: SheetView.fromJson(_graded)), scaffold: true));

    testWidgets('a paper still being read', (tester) => expectNoLayoutErrors(tester, () => sheet(view: SheetView.fromJson(const {'ready': false, 'page_id': 3, 'status': 'processing'})), scaffold: true));

    testWidgets('a paper with no boxes', (tester) => expectNoLayoutErrors(tester, () => sheet(view: SheetView.fromJson({..._graded, 'size': null})), scaffold: true));

    testWidgets('a paper refused by the reader', (tester) => expectNoLayoutErrors(tester, () => sheet(view: SheetView.fromJson(const {'ready': false, 'page_id': 3, 'status': 'rejected'})), scaffold: true));

    testWidgets('not a bubble exam', (tester) => expectNoLayoutErrors(tester, () => const SheetReviewView(waitingName: 'x', notBubble: true), scaffold: true));

    testWidgets('the start: nothing yet', (tester) => expectNoLayoutErrors(tester, () => CorrectionStartView(title: 'Mid-term', batches: const [], onImport: () {}, onScan: () {}), scaffold: true));

    testWidgets('the start: own sheet, with batches', (tester) {
      final b = OmrBatchProgress.fromJson({'batch_id': 1, 'kind': 'camera', 'total': 40, 'done': 30, 'graded': 28, 'review': 2, 'rejected': 1, 'pending': 10, 'status': 'processing', 'en': '30 of 40 papers processed', 'ar': 'تمت معالجة 30 من 40 ورقة'});
      return expectNoLayoutErrors(tester, () => CorrectionStartView(title: 'Mid-term of the second semester, class of 2026', batches: [b], ownSheet: true, onImport: () {}, onBatch: (_) {}, onReview: () {}, onResults: () {}), scaffold: true);
    });

    testWidgets('the scanner controls with zoom', (tester) => expectNoLayoutErrors(tester, () => Stack(children: [
          Positioned(left: 0, right: 0, bottom: 0, child: ScannerControls(onShutter: () {}, onAuto: (_) {}, zoomLabel: '1.5×', onZoom: () {}, onFinish: () {}, finishLabel: 'Finish (12)', onSwitch: () {})),
          Positioned(left: 0, right: 0, top: 0, child: ScannerTopBar(title: 'Exam', onClose: () {}, countLabel: '12 of 40', onCount: () {}, onTorch: () {}, torchSuggested: true, showEachOn: true, onShowEach: () {})),
        ]), scaffold: true));

    testWidgets('the guide with its checks', (tester) => expectNoLayoutErrors(tester, () => const ScannerOverlay(message: 'Hold steady.', checks: [
          OmrGuideCheck('Edges 3/4', Icons.crop_free_rounded, false),
          OmrGuideCheck('Light', Icons.wb_sunny_outlined, true),
          OmrGuideCheck('Sharp', Icons.center_focus_strong_outlined, true),
          OmrGuideCheck('Steady', Icons.back_hand_outlined, null),
        ]), scaffold: true));
  });

  testWidgets('tapping a row asks to correct that question', (tester) async {
    int? got;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(layoutHost(SizedBox(width: 500, height: 800, child: SheetPhotoStage(view: SheetView.fromJson(_graded), onQuestion: (n) => got = n)), scale: 1));
    await tester.pump();
    final box = tester.renderObject<RenderBox>(find.byKey(const ValueKey('sheet.photo')));
    // the fit: 400 × 800 centred in a 500 × 800 box. Row 1 is source 100..500 × 200..240, screen 90..250 × 80..96
    final p = box.localToGlobal(const Offset(150, 88));
    await tester.tapAt(p);
    await tester.pump();
    expect(got, 1);
  });
}
