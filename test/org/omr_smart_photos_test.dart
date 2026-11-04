// Smart photos + personalized printing on the front (the contract in the OMR client header, omr_scan.dart):
//   • models: the live hint's `blocking`, every page's `result` (each tier, missing on an older server), the batch's
//     `pages`, the print describe's `modes`, the PDF body (old server: the old body), the capture's size plan
//   • the scanner: a gentle hint is drawn softly and still lets the sheet be captured by itself; "Hold steady"
//     (moving) never does; a `retake` read keeps the shutter and offers Retake + Carry on; the improved photo is
//     loaded through the signed-image call, opened from its thumbnail, and Retake there re-arms the camera
//   • the result card for each tier, Arabic and English (Arabic count forms)
//   • the batch: the papers worth a look first, those read successfully folded, a rejected page's tips + preview with
//     "Replace this page"
//   • print: only the modes the server lists, each with its line, Pre-filled replaced by its reason; the body sent
//   • retake by replace: Retake on a paper read in part sends the next shot to …/omr/pages/{id}/replace (not a new
//     capture) and shows that answer's result; 409 page_reviewed keeps the page, says the server's sentence and sends
//     the photo as a new paper only when the teacher asks; Cancel aims the next shot at a new paper again; the batch's
//     preview offers "Replace this page" on a retake row
// Replies: test/org/fixtures/omr_smart_payloads.json (the contract's fields on top of recorded replies).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart' show FormData, RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_notice.dart' show appNoticeTopOverlay;
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_camera.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_camera_native.dart' show omrNativeVideoConstraints;
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_paper_result.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scan.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scan_widgets.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scanner_screen.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_sheets_sheet.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_upload_screen.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

final _smart = (jsonDecode(File('test/org/fixtures/omr_smart_payloads.json').readAsStringSync()) as Map)['payloads'] as Map;
final _rec = (jsonDecode(File('test/org/fixtures/omr_scan_payloads.json').readAsStringSync()) as Map)['payloads'] as Map;

Map<String, dynamic> _s(String name) => Map<String, dynamic>.from((_smart[name] as Map)['body'] as Map);
Map<String, dynamic> _r(String name) => Map<String, dynamic>.from((_rec[name] as Map)['body'] as Map);
Object? _reply(String name) {
  if (!_smart.containsKey(name)) return _r(name);
  final status = ((_smart[name] as Map)['status'] as int?) ?? 200;
  return status == 200 ? _s(name) : FakeResponse(status, _s(name));
}

const _e = '/api/v1/exam/exams/1';

/// The path the app handed to ApiClient (the base URL's own /api taken off).
String _path(RequestOptions o) => o.uri.path.replaceFirst('/api/api/', '/api/');

class _Cam implements OmrCamera {
  int photos = 0;
  @override
  Future<void> open({bool front = false}) async {}
  @override
  Widget preview() => const ColoredBox(color: Color(0xFF4A4F57));
  @override
  Future<OmrFrame?> frame({int maxSide = 640, int quality = 70}) async => OmrFrame(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1]), 540, 720);
  @override
  Future<Uint8List?> photo() async {
    photos++;
    return Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 9, photos]);
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

Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 20));
}

Future<void> _phone(WidgetTester tester, Widget w, {double width = 390}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(layoutHost(w, scale: 1, scaffold: false));
  await _frames(tester, 3);
}

/// Notices (showAppNotice) drawn in the test app's own Navigator overlay (the app's navigatorKey is not mounted here).
void _notices(WidgetTester tester) {
  appNoticeTopOverlay = () => tester.state<NavigatorState>(find.byType(Navigator).first).overlay;
  addTearDown(() => appNoticeTopOverlay = null);
}

/// The confirm dialog's Cancel (its label is a translation key the test does not load).
final _dialogCancel = find.descendant(of: find.byType(AlertDialog), matching: find.byType(OutlinedButton));

final _connected = ValueNotifier<bool>(true);
final _stream = LiveStreamHandle(connected: _connected, bind: () {}, release: () {});

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  group('models', () {
    test('live hint: blocking false = gentle and capturable; moving never; an older server only on ready', () {
      final g = OmrLiveHint.fromJson(_s('hint_gentle'));
      expect(g.blocking, isFalse);
      expect(g.gentle, isTrue);
      expect(g.steady, isTrue, reason: 'readable, steady, four marks: may be captured although not perfect');
      expect(omrHintTone(g.code, blocking: g.blocking), OmrHintTone.gentle);
      expect(OmrLiveHint.fromJson(_s('hint_gentle_first')).steady, isFalse, reason: 'steadiness not measured yet');
      expect(OmrLiveHint.fromJson(_s('hint_gentle_moving')).steady, isFalse, reason: 'a gentle "Hold steady" is never a capture');
      final dark = OmrLiveHint.fromJson(_s('hint_blocking_dark'));
      expect((dark.blocking, dark.steady, omrHintTone(dark.code, blocking: dark.blocking)), (true, false, OmrHintTone.warn));
      // an older server: no `blocking`, the recorded replies
      final old = OmrLiveHint.fromJson({..._r('hint_too_dark'), 'motion': 0.1});
      expect((old.blocking, old.gentle, old.steady), (null, false, false));
      expect(OmrLiveHint.fromJson(_r('hint_ready')).steady, isTrue);
      expect(omrHintTone('too_dark'), OmrHintTone.warn);
      expect(omrHintTone('ready', blocking: false), OmrHintTone.good);
    });

    test('page result: every tier; missing / unknown → null; tolerant shapes', () {
      final a = OmrCaptureResult.fromJson(_s('capture_accept'));
      expect((a.accepted, a.blocks, a.result!.tier, a.result!.reviewCount), (true, false, OmrTier.accept, 0));
      expect(a.result!.previewUrl, startsWith('/api/v1/exam/omr/images/preview/4?'));
      expect(a.result!.applied, ['resize', 'shadow', 'clahe', 'perspective']);
      expect(a.result!.appliedText, 'Improved: resized · shadows evened out · contrast improved · page straightened');
      final f = OmrCaptureResult.fromJson(_s('capture_flags')).result!;
      expect((f.tier, f.reviewCount, f.title), (OmrTier.flags, 3, 'Read with 3 questions to review'));
      final r = OmrCaptureResult.fromJson(_s('capture_retake'));
      expect((r.blocks, r.result!.tier, r.result!.wantsRetake), (false, OmrTier.retake, true));
      expect(r.result!.message, 'The bottom edge of the page is cut off.');
      expect(r.result!.tipTexts, ['Fit the whole page inside the frame.']);
      final x = OmrCaptureResult.fromJson(_s('capture_reject'));
      expect((x.accepted, x.blocks, x.result!.tier, x.result!.graded, x.result!.previewUrl), (false, true, OmrTier.reject, false, null));
      // an older server's replies: no result, the old behaviour
      expect(OmrCaptureResult.fromJson(_r('capture_session_1')).result, isNull);
      expect(OmrCaptureResult.fromJson(_r('capture_session_1')).blocks, isFalse);
      expect(OmrCaptureResult.fromJson(_r('capture_rejected_blurry')).blocks, isTrue);
      expect(OmrPageResult.fromJson({'tier': 'excellent'}), isNull);
      expect(OmrPageResult.fromJson(null), isNull);
      expect(OmrPageResult.fromJson({'tier': 'flags'})!.title, 'Read with some questions to review', reason: 'no count');
      final loose = OmrPageResult.fromJson({'tier': 'reject', 'message': 'Too dark.', 'tips': ['Add light.', 7], 'review_count': -2, 'preview_url': ''})!;
      expect((loose.message, loose.reviewCount, loose.previewUrl), ('Too dark.', 0, null));
      expect(loose.tipTexts, ['Add light.']);
      expect(OmrPageResult.of({'page': {'result': _s('capture_flags')['result']}})!.tier, OmrTier.flags, reason: 'GET …/omr/pages/{id}: under page');
      expect(OmrPageResult.fromJson({'tier': 'accept', 'applied': ['direct']})!.appliedText, '', reason: 'used as it was: nothing to say');
    });

    test('titles: Arabic count forms', () {
      expect(omrResultTitle(OmrTier.flags, 1), 'Read with 1 question to review');
      expect(omrResultTitle(OmrTier.retake, 0), 'Read in part');
      expect(omrResultTitle(OmrTier.reject, 0), "Couldn't read this paper");
      AppConfig.lang = 'ar';
      // the server's phrasing (smart_message), so a batch never says one state two ways
      expect(omrResultTitle(OmrTier.accept, 0), 'تمت القراءة بنجاح');
      expect(omrResultTitle(OmrTier.flags, 1), 'تمت القراءة، وسؤال واحد للمراجعة');
      expect(omrResultTitle(OmrTier.flags, 2), 'تمت القراءة، وسؤالان للمراجعة');
      expect(omrResultTitle(OmrTier.flags, 3), 'تمت القراءة، و3 أسئلة للمراجعة');
      expect(omrResultTitle(OmrTier.flags, 11), 'تمت القراءة، و11 سؤالًا للمراجعة');
      expect(omrResultTitle(OmrTier.flags, 100), 'تمت القراءة، و100 سؤال للمراجعة');
      expect(omrResultTitle(OmrTier.retake, 11), 'تمت القراءة جزئيًا، و11 سؤالًا للمراجعة');
      expect(omrResultTitle(OmrTier.flags, 0, student: OmrStudentNeed.choose), 'تمت القراءة — اختر الطالب');
      expect(omrResultTitle(OmrTier.reject, 0), 'تعذّرت قراءة الورقة');
      expect(omrReadOkText(2), 'قُرئت ورقتان بنجاح');
      expect(omrReadOkText(12), 'قُرئت 12 ورقة بنجاح');
      AppConfig.lang = 'en';
      expect(omrReadOkText(1), '1 paper read successfully');
    });

    test('batch: pages with results, the rejected page\'s result; an older server has neither', () {
      final b = OmrBatchProgress.fromJson(_s('batch_smart'));
      expect(b.pages, hasLength(10));
      expect([for (final p in b.pages) p.result!.tier.name].join(','), 'accept,accept,flags,accept,accept,accept,reject,accept,retake,accept');
      expect(b.rejectedPages.single.result!.tipTexts, ['Rest the phone on something steady or brace your elbows.']);
      expect(b.withEvent({'done': 10}).pages, hasLength(10), reason: 'a live event keeps the pages');
      final old = OmrBatchProgress.fromJson(_r('batch_done'));
      expect(old.pages, isEmpty);
      expect(old.rejectedPages.single.result, isNull);
      expect(OmrReplaceResult.fromJson({'accepted': false, 'page_id': 3, 'result': _s('capture_reject')['result']}).result!.tier, OmrTier.reject);
    });

    test('print describe: modes (strings, maps), Pre-filled missing with a reason; an older server has none', () {
      final all = OmrSheetsInfo.fromJson(_s('sheets_info_modes'));
      expect(all.modes, [OmrPrintMode.prefilled, OmrPrintMode.named, OmrPrintMode.blank]);
      expect(all.prefilledMissing, isNull);
      expect(omrDefaultMode(all), OmrPrintMode.named);
      final no = OmrSheetsInfo.fromJson(_s('sheets_info_no_prefilled'));
      expect(no.modes, [OmrPrintMode.named, OmrPrintMode.blank]);
      expect(no.prefilledMissing, 'Pre-filled is not possible: some student numbers contain letters.');
      final maps = OmrSheetsInfo.fromJson(_s('sheets_info_modes_maps'));
      expect(maps.modes, [OmrPrintMode.named, OmrPrintMode.blank], reason: 'available: false is left out');
      expect(maps.prefilledMissing, 'Pre-filled is not available: the sheet has no student-number bubbles');
      final shaded = OmrSheetsInfo.fromJson({..._r('sheets_info'), 'modes': ['named', 'blank', 'poster']});
      expect(shaded.modes, [OmrPrintMode.named, OmrPrintMode.blank], reason: 'an unknown mode is skipped');
      expect(shaded.prefilledMissing, contains('not all digits'));
      // the server's real shape (omr_sheets.describe): a reason code under mode_detail.prefilled
      Map<String, dynamic> detail(String code) => {..._r('sheets_info'), 'id_kind': 'shaded', 'modes': ['named', 'blank'],
            'mode_detail': {'prefilled': {'available': false, 'reason': code}, 'named': {'available': true, 'reason': null}}};
      expect(OmrSheetsInfo.fromJson(detail('no_identifier')).prefilledMissing, contains('does not identify students by a number'));
      expect(OmrSheetsInfo.fromJson(detail('identifier_unknown')).prefilledMissing, contains('could not be checked'));
      expect(OmrSheetsInfo.fromJson(detail('something_new')).prefilledMissing, contains('not all digits'), reason: 'unknown code → ID-kind fallback');
      AppConfig.lang = 'ar';
      expect(OmrSheetsInfo.fromJson(detail('identifier_zone_mismatch')).prefilledMissing, contains('لا تتسع'));
      AppConfig.lang = 'en';
      final old = OmrSheetsInfo.fromJson(_r('sheets_info'));
      expect((old.modes, old.hasModes, old.prefilledMissing), (null, false, null));
      expect(omrOfferedModes(old), [OmrPrintMode.named, OmrPrintMode.blank]);
    });

    test('print body: the old one without modes; mode / order / index with them; ids as chosen', () {
      expect(omrSheetsBody(forms: ['A'], studentIds: [9, 3, 5]), {'forms': ['A'], 'student_ids': [9, 3, 5]});
      expect(omrSheetsBody(copies: 4), {'copies': 4});
      expect(omrSheetsBody(forms: ['A', 'B'], studentIds: [9, 3], mode: OmrPrintMode.prefilled, order: OmrPrintOrder.identifier, index: false),
          {'forms': ['A', 'B'], 'student_ids': [9, 3], 'mode': 'prefilled', 'order': 'identifier', 'index': false});
      expect(omrSheetsBody(studentIds: [1], mode: OmrPrintMode.named), {'student_ids': [1], 'mode': 'named', 'order': 'name', 'index': true});
      expect(omrSheetsBody(copies: 2, studentIds: [1], mode: OmrPrintMode.blank), {'copies': 2, 'mode': 'blank'}, reason: 'blank names nobody');
    });

    test('capture size: a small JPEG as it is; PNG / heavy / huge re-encoded, never upscaled', () {
      expect(omrPhotoPlan(jpeg: true, bytes: 900 * 1024, width: 1080, height: 1920).keep, isTrue);
      final png = omrPhotoPlan(jpeg: false, bytes: 3 << 20, width: 1080, height: 1920);
      expect((png.keep, png.width, png.height, png.quality), (false, 1080, 1920, 90));
      expect(omrPhotoPlan(jpeg: true, bytes: 2 << 20, width: 1080, height: 1920).keep, isFalse, reason: 'a q100 JPEG');
      final big = omrPhotoPlan(jpeg: true, bytes: 1 << 20, width: 3000, height: 4000);
      expect((big.keep, big.width, big.height), (false, 1920, 2560));
    });

    test('phone camera asks for 1080p in plain numbers (the plugin drops an {ideal: n} map and films 720p)', () {
      final v = omrNativeVideoConstraints();
      expect((v['width'], v['height'], v['frameRate'], v['facingMode']), (1920, 1080, 30, 'environment'));
      expect(v.values.whereType<Map>(), isEmpty);
      expect(omrNativeVideoConstraints(front: true)['facingMode'], 'user');
    });

    test('how long a card stays', () {
      expect(omrResultStays(null), const Duration(milliseconds: 2600));
      expect(omrResultStays(OmrCaptureResult.fromJson(_s('capture_flags')).result), const Duration(milliseconds: 4500));
      expect(omrResultStays(OmrCaptureResult.fromJson(_s('capture_retake')).result), isNull);
    });
  });

  group('hint styles', () {
    for (final lang in ['en', 'ar']) {
      testWidgets('gentle is soft (smaller, lighter, a tip icon), warn stays loud ($lang)', (tester) async {
        AppConfig.lang = lang;
        final h = OmrLiveHint.fromJson(_s('hint_gentle'));
        await _phone(tester, ScannerOverlay(message: h.text, tone: omrHintTone(h.code, blocking: h.blocking)));
        expect(find.byKey(const ValueKey('omr.hint.gentle')), findsOneWidget);
        expect(find.text(lang == 'ar' ? 'أضف قليلًا من الإضاءة.' : 'Add a little more light.'), findsOneWidget);
        expect(find.byIcon(Icons.tips_and_updates_outlined), findsOneWidget);
        final soft = tester.widget<Text>(find.text(h.text)).style!;
        expect((soft.fontSize, soft.fontWeight), (14.5, FontWeight.w600));

        final d = OmrLiveHint.fromJson(_s('hint_blocking_dark'));
        await _phone(tester, ScannerOverlay(message: d.text, tone: omrHintTone(d.code, blocking: d.blocking)));
        expect(find.byKey(const ValueKey('omr.hint.warn')), findsOneWidget);
        final loud = tester.widget<Text>(find.text(d.text)).style!;
        expect((loud.fontSize, loud.fontWeight), (16, FontWeight.w700));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('scanner', () {
    final replaces = <String>[];
    var captureCalls = 0;

    Future<(FakeApi, List<String>, _Cam)> open(WidgetTester tester, List<String> hints, List<String> captures, {List<String> replies = const []}) async {
      replaces.clear();
      captureCalls = 0;
      final rp = [...replies];
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final h = [...hints], c = [...captures];
      final images = <String>[];
      var calls = 0;
      final fake = FakeApi({
        'POST $_e/omr/live-hint': (_) {
          calls++;
          return _reply(h.length > 1 ? h.removeAt(0) : h.first);
        },
        'POST $_e/omr/capture': (RequestOptions o) {
          expect(o.data, isA<FormData>());
          captureCalls++;
          return _reply(c.length > 1 ? c.removeAt(0) : c.first);
        },
        'POST $_e/omr/pages/*': (RequestOptions o) {
          replaces.add(_path(o));
          expect((o.data as FormData).files.single.key, 'image');
          return _reply(rp.length > 1 ? rp.removeAt(0) : rp.first);
        },
        'GET /api/v1/exam/omr/images/*': (RequestOptions o) {
          images.add('${_path(o)}?${o.uri.query}');
          return 'not-a-real-image';
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      final cam = _Cam();
      await tester.pumpWidget(layoutHost(
          OmrScannerScreen(examId: 1, examTitle: 'Quiz', camera: () => cam, clock: () => DateTime(2026, 11, 3).add(Duration(milliseconds: 420 * calls))),
          scale: 1,
          scaffold: false));
      await _frames(tester, 2);
      _notices(tester);
      return (fake, images, cam);
    }

    testWidgets('a gentle hint still captures by itself; a retake read keeps the shutter and suggests Retake', (tester) async {
      final (fake, images, cam) = await open(tester, ['hint_gentle_first', 'hint_gentle'], ['capture_retake']);
      expect(find.byKey(const ValueKey('omr.hint.gentle')), findsOneWidget);
      await _frames(tester, 14);
      expect(cam.photos, 1, reason: 'readable though not perfect: captured');
      await _frames(tester, 3);
      expect(find.text('Read in part — 5 questions to review'), findsOneWidget);
      expect(find.text('The bottom edge of the page is cut off.'), findsOneWidget);
      expect(find.text('Fit the whole page inside the frame.'), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.result.suggest')), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.retake.soft')), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.keep')), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.retake')), findsNothing, reason: 'not the blocking Retake');
      expect(find.text('Finish (1)'), findsOneWidget, reason: 'non-blocking: the controls stay');
      expect(images.single, startsWith('/api/v1/exam/omr/images/preview/4?exp=1793700000&sig='), reason: 'the signed image, query kept');
      expect(find.byKey(const ValueKey('omr.preview.thumb')), findsOneWidget);

      // the card stays (a choice is waiting) — "Carry on" puts it away
      await _frames(tester, 60);
      expect(find.byKey(const ValueKey('omr.keep')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('omr.keep')));
      await _frames(tester, 2);
      expect(find.text('Read in part — 5 questions to review'), findsNothing);
      expect(fake.unmatched, isEmpty);
      expect(tester.takeException(), isNull);
      await _done(tester);
    });

    testWidgets('"Hold steady" (gentle, moving) never captures', (tester) async {
      final (_, _, cam) = await open(tester, ['hint_gentle_moving'], ['capture_accept']);
      await _frames(tester, 30);
      expect(cam.photos, 0);
      expect(find.text('Hold steady.'), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.hint.gentle')), findsOneWidget);
      await _done(tester);
    });

    testWidgets('preview from the thumbnail; Retake there re-arms the camera', (tester) async {
      final (_, images, cam) =
          await open(tester, ['hint_ready_first', 'hint_ready_smart'], ['capture_retake', 'capture_accept'], replies: ['replace_retake_accepted']);
      await _frames(tester, 17);
      expect(cam.photos, 1);
      await tester.tap(find.byKey(const ValueKey('omr.preview.thumb')));
      await _frames(tester, 6);
      expect(find.text('The improved photo'), findsOneWidget);
      expect(find.textContaining('Improved: resized · shadows evened out · contrast improved · ink sharpened · page straightened'), findsOneWidget);
      expect(images, hasLength(1), reason: 'the bytes already loaded are reused');
      final retake = find.byKey(const ValueKey('omr.preview.retake'));
      await tester.ensureVisible(retake);
      await tester.pump();
      await tester.tap(retake);
      await _frames(tester, 4);
      expect(find.text('The improved photo'), findsNothing);
      expect(find.text('Read in part — 5 questions to review'), findsNothing);
      // re-armed: the same steady sheet is captured again
      await _frames(tester, 16);
      expect(cam.photos, 2);
      expect(find.text('Read successfully'), findsOneWidget);
      expect(replaces, ['$_e/omr/pages/4/replace'], reason: 'the retake replaced the page read in part');
      expect(find.text('Page 1 replaced. It is being read now.'), findsOneWidget, reason: 'the server\'s sentence under the tier');
      expect(tester.takeException(), isNull);
      await _done(tester);
    });

    testWidgets('a rejected photo: reason + tip + the big Retake; nothing more is sent until Retake', (tester) async {
      final (_, images, cam) = await open(tester, ['hint_ready_first', 'hint_ready_smart'], ['capture_reject']);
      await _frames(tester, 17);
      expect(cam.photos, 1);
      expect(find.text("Couldn't read this paper"), findsOneWidget);
      expect(find.text('The page is too dark to read.'), findsOneWidget);
      expect(find.text('Turn on a light or move near a window.'), findsOneWidget);
      expect(find.text('Nothing was graded from this photo.'), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.retake')), findsOneWidget);
      expect(find.text('Finish (0)'), findsNothing, reason: 'the controls give way to Retake');
      expect(images, isEmpty, reason: 'no preview_url: nothing to load');
      await _frames(tester, 20);
      expect(cam.photos, 1);
      await tester.tap(find.byKey(const ValueKey('omr.retake')));
      await _frames(tester, 2);
      expect(find.text("Couldn't read this paper"), findsNothing);
      await _done(tester);
    });

    testWidgets('Retake on a paper read in part replaces that page: the next shot goes to …/replace, its result shows',
        (tester) async {
      final (fake, _, cam) =
          await open(tester, ['hint_ready_first', 'hint_ready_smart'], ['capture_retake'], replies: ['replace_retake_accepted']);
      await _frames(tester, 17);
      expect((cam.photos, captureCalls), (1, 1));
      await tester.tap(find.byKey(const ValueKey('omr.retake.soft')));
      await _frames(tester, 1);
      expect(find.byKey(const ValueKey('omr.retake.target')), findsOneWidget, reason: 'says the next photo replaces the earlier one');
      await _frames(tester, 16);
      expect(cam.photos, 2);
      expect(captureCalls, 1, reason: 'not a new capture (that would be the same student twice)');
      expect(replaces, ['$_e/omr/pages/4/replace'], reason: 'the page the capture answered with');
      expect(find.text('Read successfully'), findsOneWidget, reason: 'the replace answer\'s result');
      expect(find.text('Page 1 replaced. It is being read now.'), findsOneWidget);
      expect(find.text('1 of 40'), findsOneWidget, reason: 'the same paper: the count does not move');
      expect(find.byKey(const ValueKey('omr.retake.target')), findsNothing);

      // the next sheet is a new paper again
      await _frames(tester, 30);
      expect(replaces, hasLength(1));
      expect(fake.unmatched, isEmpty);
      expect(tester.takeException(), isNull);
      await _done(tester);
    });

    testWidgets('Retake from the preview replaces too; Cancel aims the next shot at a new paper', (tester) async {
      final (_, _, cam) = await open(tester, ['hint_ready_first', 'hint_ready_smart'], ['capture_retake', 'capture_accept'], replies: ['replace_retake_accepted']);
      await _frames(tester, 17);
      await tester.tap(find.byKey(const ValueKey('omr.preview.thumb')));
      await _frames(tester, 6);
      final retake = find.byKey(const ValueKey('omr.preview.retake'));
      await tester.ensureVisible(retake);
      await tester.pump();
      await tester.tap(retake);
      await _frames(tester, 2);
      expect(find.byKey(const ValueKey('omr.retake.target')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('omr.retake.cancel')));
      await _frames(tester, 16);
      expect(cam.photos, 2);
      expect(replaces, isEmpty, reason: 'cancelled: a new paper');
      expect(captureCalls, 2);
      await _done(tester);
    });

    for (final asNew in [false, true]) {
      testWidgets('409 page_reviewed keeps the page, says why; a new paper only when asked (${asNew ? 'yes' : 'no'})', (tester) async {
        final (_, _, cam) =
            await open(tester, ['hint_ready_first', 'hint_ready_smart'], ['capture_retake', 'capture_accept'], replies: ['replace_page_reviewed_409']);
        await _frames(tester, 17);
        await tester.tap(find.byKey(const ValueKey('omr.retake.soft')));
        await _frames(tester, 16);
        expect(cam.photos, 2);
        expect(replaces, ['$_e/omr/pages/4/replace']);
        expect(find.text('You already reviewed questions on this paper, so it is not replaced.'), findsOneWidget, reason: 'the server\'s sentence');
        expect(find.text('The earlier paper stays as it is. Send this photo as a new paper?'), findsOneWidget);
        expect(captureCalls, 1);
        final before = cam.photos;
        await _frames(tester, 10);
        expect(cam.photos, before, reason: 'nothing more is taken while the question is open');
        await tester.tap(asNew ? find.text('Send as a new paper') : _dialogCancel);
        await _frames(tester, 4);
        expect(captureCalls, asNew ? 2 : 1);
        expect(replaces, hasLength(1), reason: 'the page is kept');
        if (asNew) expect(find.text('Read successfully'), findsOneWidget);
        expect(find.byKey(const ValueKey('omr.retake.target')), findsNothing);
        await _done(tester);
      });
    }

    testWidgets('Arabic: the server\'s 409 sentence', (tester) async {
      AppConfig.lang = 'ar';
      await open(tester, ['hint_ready_first', 'hint_ready_smart'], ['capture_retake'], replies: ['replace_page_reviewed_409']);
      await _frames(tester, 17);
      await tester.tap(find.byKey(const ValueKey('omr.retake.soft')));
      await _frames(tester, 16);
      expect(find.text('راجعت أسئلة هذه الورقة من قبل، فلن تُستبدل.'), findsOneWidget);
      await tester.tap(_dialogCancel);
      await _frames(tester, 2);
      await _done(tester);
    });
  });

  group('result card per tier', () {
    for (final lang in ['en', 'ar']) {
      testWidgets('accept · flags · retake · reject ($lang)', (tester) async {
        AppConfig.lang = lang;
        final titles = {
          'capture_accept': lang == 'ar' ? 'تمت القراءة بنجاح' : 'Read successfully',
          'capture_flags': lang == 'ar' ? 'تمت القراءة، و3 أسئلة للمراجعة' : 'Read with 3 questions to review',
          'capture_retake': lang == 'ar' ? 'تمت القراءة جزئيًا، و5 أسئلة للمراجعة' : 'Read in part — 5 questions to review',
          'capture_reject': lang == 'ar' ? 'تعذّرت قراءة الورقة' : "Couldn't read this paper",
        };
        for (final MapEntry(key: name, value: title) in titles.entries) {
          final res = OmrCaptureResult.fromJson(_s(name));
          await _phone(
              tester,
              Center(
                child: CaptureResultCard(
                  accepted: res.accepted,
                  title: res.text,
                  result: res.result,
                  previewLoading: res.result!.previewUrl != null,
                  onPreview: res.result!.previewUrl == null ? null : () {},
                  onRetake: () {},
                  onDismiss: () {},
                ),
              ));
          expect(find.text(title), findsOneWidget, reason: name);
          final tier = res.result!.tier;
          expect(find.byKey(const ValueKey('omr.retake')), tier == OmrTier.reject ? findsOneWidget : findsNothing, reason: name);
          expect(find.byKey(const ValueKey('omr.retake.soft')), tier == OmrTier.retake ? findsOneWidget : findsNothing, reason: name);
          expect(find.byKey(const ValueKey('omr.preview.thumb')), res.result!.previewUrl != null ? findsOneWidget : findsNothing, reason: name);
          if (tier == OmrTier.accept || tier == OmrTier.flags) expect(find.text(res.text), findsOneWidget, reason: '$name: "Paper 1 of 40 captured"');
          expect(tester.takeException(), isNull);
        }
      });
    }
  });

  group('batch', () {
    testWidgets('papers worth a look first, the rest folded; a rejected page\'s tip and preview → Replace', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final images = <String>[];
      final replaced = <String>[];
      final fake = FakeApi({
        'GET $_e/omr/batches/*': (_) => _s('batch_smart'),
        'GET $_e/omr/issues*': (_) => {'items': [], 'counts': {}}, // the batch's issues card (none here)
        'GET /api/v1/exam/omr/images/*': (RequestOptions o) {
          images.add(_path(o));
          return 'x';
        },
        'POST $_e/omr/pages/*': (RequestOptions o) {
          replaced.add(_path(o));
          return payload('omr_review/rep_gate_rejected.json');
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await tester.pumpWidget(layoutHost(
          OmrScanProgressScreen(
            examId: 1,
            batchId: 8,
            picker: ({bool many = true}) async => [('page7.jpg', Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 7]))],
            liveBus: LiveEvents.instance,
            liveStream: _stream,
          ),
          scale: 1,
          scaffold: false));
      await _frames(tester, 6);
      expect(find.text('Papers worth a look'), findsOneWidget);
      final retake = tester.getTopLeft(find.text('Read in part — 4 questions to review'));
      final flags = tester.getTopLeft(find.text('Read with 2 questions to review'));
      expect(retake.dy, lessThan(flags.dy), reason: 'a suggested retake first');
      expect(find.text('7 papers read successfully'), findsOneWidget);
      expect(find.text('Read successfully'), findsNothing, reason: 'folded');
      await tester.ensureVisible(find.byKey(const ValueKey('omr.papers.ok')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('omr.papers.ok')));
      await _frames(tester, 2);
      expect(find.text('Read successfully'), findsNWidgets(7));

      // the rejected page: its sentence, its tip, Preview → "Replace this page"
      // with a result its message (the legacy page sentence repeats it for older apps), under "Page 7"
      expect(find.text('Too blurry, hold steady.'), findsOneWidget);
      expect(find.text('Paper 7'), findsOneWidget, reason: 'one word for a scanned sheet in the batch views');
      expect(find.text('Rest the phone on something steady or brace your elbows.'), findsOneWidget);
      final prev = find.byKey(const ValueKey('omr.paper.preview.14'));
      await tester.ensureVisible(prev);
      await tester.pump();
      await tester.tap(prev);
      await _frames(tester, 6);
      expect(images.last, '/api/v1/exam/omr/images/preview/14');
      final rep = find.byKey(const ValueKey('omr.preview.retake'));
      await tester.ensureVisible(rep);
      await tester.pump();
      expect(find.descendant(of: rep, matching: find.text('Replace this paper')), findsOneWidget);
      await tester.tap(rep);
      await _frames(tester, 6);
      expect(replaced, ['$_e/omr/pages/14/replace']);
      expect(fake.unmatched, isEmpty);
      expect(tester.takeException(), isNull);
      await _done(tester);
    });

    testWidgets('a retake row\'s preview offers "Replace this page" → …/replace; 409 says the server\'s sentence', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final replaced = <String>[];
      final fake = FakeApi({
        'GET $_e/omr/batches/*': (_) => _s('batch_smart'),
        'GET $_e/omr/issues*': (_) => {'items': [], 'counts': {}}, // the batch's issues card (none here)
        'GET /api/v1/exam/omr/images/*': (_) => 'x',
        // the new page's own state (the fallback while no event came): still being read
        'GET $_e/omr/pages/*': (_) => {'page': {'id': 5, 'status': 'processing'}},
        'POST $_e/omr/pages/*': (RequestOptions o) {
          replaced.add(_path(o));
          return _reply(replaced.length == 1 ? 'replace_page_reviewed_409' : 'replace_retake_accepted');
        },
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await tester.pumpWidget(layoutHost(
          OmrScanProgressScreen(
            examId: 1,
            batchId: 8,
            picker: ({bool many = true}) async => [('page9.jpg', Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 9]))],
            liveBus: LiveEvents.instance,
            liveStream: _stream,
          ),
          scale: 1,
          scaffold: false));
      await _frames(tester, 6);
      _notices(tester);
      final retakeRow = (_s('batch_smart')['pages'] as List).cast<Map>().firstWhere((p) => (p['result'] as Map)['tier'] == 'retake');
      final id = retakeRow['page_id'];
      Future<void> replaceFromPreview() async {
        final prev = find.byKey(ValueKey('omr.paper.preview.$id'));
        await tester.ensureVisible(prev);
        await tester.pump();
        await tester.tap(prev);
        await _frames(tester, 6);
        final rep = find.byKey(const ValueKey('omr.preview.retake'));
        await tester.ensureVisible(rep);
        await tester.pump();
        expect(find.descendant(of: rep, matching: find.text('Replace this paper')), findsOneWidget);
        await tester.tap(rep);
        await _frames(tester, 6);
      }

      await replaceFromPreview();
      expect(replaced, ['$_e/omr/pages/$id/replace']);
      expect(find.text('You already reviewed questions on this paper, so it is not replaced.'), findsOneWidget);
      expect(find.byKey(ValueKey('omr.paper.$id')), findsOneWidget, reason: 'the page is kept');

      await tester.pump(const Duration(seconds: 5)); // the notice goes
      await replaceFromPreview();
      expect(replaced, hasLength(2));
      expect(find.text('Page 1 replaced. It is being read now.'), findsOneWidget, reason: 'said: no rejected row carries it');
      expect(find.byKey(ValueKey('omr.paper.$id')), findsNothing, reason: 'superseded');
      expect(fake.unmatched, isEmpty);
      await _done(tester);
    });

    testWidgets('an older server\'s batch: no rows, no preview', (tester) async {
      final fake = FakeApi({'GET $_e/omr/batches/*': (_) => _r('batch_done')}, latency: const Duration(milliseconds: 20))..install();
      addTearDown(fake.uninstall);
      await _phone(tester, OmrScanProgressScreen(examId: 1, batchId: 8, liveBus: LiveEvents.instance, liveStream: _stream));
      await _frames(tester, 4);
      expect(find.text('10 of 10 papers processed'), findsOneWidget);
      expect(find.text('Papers worth a look'), findsNothing);
      expect(find.byKey(const ValueKey('omr.paper.preview.14')), findsNothing);
      await _done(tester);
    });
  });

  group('print options', () {
    Future<List<Map>> openSheet(WidgetTester tester, String describe) async {
      final bodies = <Map>[];
      final fake = FakeApi({
        'GET $_e/omr/sheets': (_) => _reply(describe),
        'GET $_e/omr/students': (_) => payload('omr_review/aud_all.json'),
        'POST $_e/omr/sheets': (o) {
          bodies.add((o.data is String ? jsonDecode(o.data as String) : o.data) as Map);
          return FakeResponse(422, _r('sheets_not_a_student'));
        },
      }, latency: const Duration(milliseconds: 10))
        ..install();
      addTearDown(fake.uninstall);
      await _phone(tester, const Scaffold(body: SingleChildScrollView(child: OmrSheetsSheet(examId: 1))));
      await _frames(tester, 6);
      return bodies;
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f);
      await _frames(tester, 3);
    }

    testWidgets('all three modes with their lines; Pre-filled by student number, no index → the body', (tester) async {
      final bodies = await openSheet(tester, 'sheets_info_modes');
      for (final m in OmrPrintMode.values) {
        expect(find.byKey(ValueKey('omr.sheets.mode.${m.name}')), findsOneWidget);
        expect(find.text(omrModeLine(m)), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('omr.sheets.prefilled.missing')), findsNothing);
      expect(find.text('Up to 200 sheets at a time'), findsOneWidget, reason: 'opens on Name only: the students are asked for');
      await tap(tester, find.byKey(const ValueKey('omr.sheets.mode.prefilled')));
      await tap(tester, find.byKey(const ValueKey('omr.aud.all')));
      await tap(tester, find.byKey(const ValueKey('omr.sheets.order.identifier')));
      await tap(tester, find.byKey(const ValueKey('omr.sheets.index')));
      await tap(tester, find.text('Download PDF'));
      expect(bodies.single['mode'], 'prefilled');
      expect(bodies.single['order'], 'identifier');
      expect(bodies.single['index'], false);
      expect(bodies.single['forms'], ['A', 'B']);
      expect((bodies.single['student_ids'] as List).toSet(), {21, 22, 23, 24});
      expect(bodies.single.containsKey('copies'), isFalse);

      // blank: copies, no names / order / index
      await tap(tester, find.byKey(const ValueKey('omr.sheets.mode.blank')));
      expect(find.byKey(const ValueKey('omr.sheets.index')), findsNothing);
      await tester.enterText(find.byType(TextField).last, '3');
      await tap(tester, find.text('Download PDF'));
      expect(bodies.last, {'forms': ['A', 'B'], 'copies': 3, 'mode': 'blank'});
      await _done(tester);
    });

    for (final lang in ['en', 'ar']) {
      testWidgets('Pre-filled not offered: its reason in one line ($lang)', (tester) async {
        AppConfig.lang = lang;
        await openSheet(tester, 'sheets_info_no_prefilled');
        expect(find.byKey(const ValueKey('omr.sheets.mode.prefilled')), findsNothing);
        expect(find.byKey(const ValueKey('omr.sheets.mode.prefilled.off')), findsOneWidget, reason: 'shown disabled with its reason, not hidden');
        expect(find.byKey(const ValueKey('omr.sheets.mode.named')), findsOneWidget);
        expect(find.text(lang == 'ar' ? 'لا يمكن التظليل المسبق: بعض أرقام الطلاب فيها حروف.' : 'Pre-filled is not possible: some student numbers contain letters.'),
            findsOneWidget);
        expect(find.text(lang == 'ar' ? 'بالاسم فقط' : 'Name only'), findsOneWidget);
        await _done(tester);
      });
    }

    testWidgets('an older server: the two chips, no modes', (tester) async {
      await openSheet(tester, 'sheets_info');
      expect(find.byKey(const ValueKey('omr.sheets.mode.named')), findsNothing);
      expect(find.text('A named sheet per student'), findsOneWidget);
      expect(find.byKey(const ValueKey('omr.sheets.order.name')), findsNothing);
      await _done(tester);
    });
  });
}
