// Visual review renders of the bubble-sheet scanner (D-159; brief part 3), compared by eye like the other
// test/visual files (NOT a CI suite). The PNGs go OUTSIDE the repo:
//
//   OMR_RENDER_DIR=<dir> flutter test test/visual/omr_scan_golden_test.dart --update-goldens [--plain-name accepted]
//
// → <dir>/omrscan_<scene>_<width>_<lang>_<light|dark>.png
//   hint       the real scanner screen over a (painted) photo of a sheet: "Hold steady." (the server's moving hint), the four corner marks found
//   accepted   the real screen after an automatic capture: "Paper 1 of 40 captured"
//   rejected   the real screen after a refused photo: "Bottom-left corner mark is not visible." + Retake
//   blocked    the camera blocked: the fix and "Upload images or PDFs instead"
//   progress   Example 5 done: "10 of 10 papers processed", page 7 rejected with its sentence + Replace
//   tools      the exam's bubble-sheet entries + the print options
// The screen's replies are the recorded ones (test/org/fixtures/omr_scan_payloads.json).
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_camera.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scan.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scan_widgets.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scanner_screen.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_sheets_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'home_screens_golden_test.dart' show pubspecFonts;

String _sdkFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return '$root/bin/cache/artifacts/material_fonts';
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll('\\', '/');
  return '${exe.substring(0, exe.indexOf('/bin/cache/'))}/bin/cache/artifacts/material_fonts';
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
    await loader.load();
  }

  for (final (family, assets) in pubspecFonts(File('pubspec.yaml').readAsStringSync())) {
    await load(family, assets);
  }
  final sdk = _sdkFonts();
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

final _all = (jsonDecode(File('test/org/fixtures/omr_scan_payloads.json').readAsStringSync()) as Map)['payloads'] as Map;
Map<String, dynamic> _body(String name) => Map<String, dynamic>.from((_all[name] as Map)['body'] as Map);
Object? _reply(String name) {
  final p = _all[name] as Map;
  return p['status'] == 200 ? p['body'] : FakeResponse(p['status'] as int, p['body']);
}

final _shot = GlobalKey();
final _dir = (Platform.environment['OMR_RENDER_DIR'] ?? '${Directory.systemTemp.path}/omr_renders').replaceAll('\\', '/');

Widget _host(Widget child, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => RepaintBoundary(
        key: _shot,
        child: Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      ),
      home: child,
    ),
  );
}

/// A photo-like picture of an answer sheet on a desk, placed where the guide is (the fake camera's preview).
class _SheetPhoto extends CustomPainter {
  _SheetPhoto({this.coverBottomLeft = false});
  final bool coverBottomLeft;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size,
        Paint()..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF5B5148), Color(0xFF3A332D)]).createShader(Offset.zero & size));
    final g = scannerGuideRect(size).deflate(10);
    if (g.isEmpty) return;
    canvas.save();
    canvas.translate(g.center.dx, g.center.dy);
    canvas.rotate(-1.6 * math.pi / 180);
    canvas.translate(-g.center.dx, -g.center.dy);
    canvas.drawRect(g.shift(const Offset(4, 6)), Paint()..color = const Color(0x55000000));
    canvas.drawRect(g, Paint()..color = const Color(0xFFEDEBE4));
    final ink = Paint()..color = const Color(0xFF26262A);
    final m = g.width * .055;
    for (final (i, o) in [g.topLeft, g.topRight - Offset(m, 0), g.bottomRight - Offset(m, m), g.bottomLeft - Offset(0, m)].indexed) {
      if (coverBottomLeft && i == 3) continue;
      canvas.drawRect((o + Offset(m * .5, m * .5) * (i == 0 ? 1 : 0)) & Size(m, m), ink);
    }
    final line = Paint()
      ..color = const Color(0xFF8D8A84)
      ..strokeWidth = 1.2;
    canvas.drawLine(g.topLeft + Offset(g.width * .2, g.height * .06), g.topLeft + Offset(g.width * .8, g.height * .06), line..strokeWidth = 2.4);
    canvas.drawLine(g.topLeft + Offset(g.width * .3, g.height * .1), g.topLeft + Offset(g.width * .7, g.height * .1), line..strokeWidth = 1.2);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF6E6B66);
    final r = g.width * .018;
    final rnd = math.Random(7);
    for (var col = 0; col < 2; col++) {
      for (var row = 0; row < 18; row++) {
        final y = g.top + g.height * (.2 + row * .042);
        final x0 = g.left + g.width * (.14 + col * .44);
        final pick = rnd.nextInt(4);
        for (var k = 0; k < 4; k++) {
          final c = Offset(x0 + k * r * 3.2, y);
          canvas.drawCircle(c, r, k == pick ? ink : ring);
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SheetPhoto old) => old.coverBottomLeft != coverBottomLeft;
}

class _PhotoCamera implements OmrCamera {
  _PhotoCamera({this.issue, this.coverBottomLeft = false});
  final OmrCameraIssue? issue;
  final bool coverBottomLeft;

  @override
  Future<void> open({bool front = false}) async {
    if (issue != null) throw OmrCameraException(issue!);
  }

  @override
  Widget preview() => CustomPaint(painter: _SheetPhoto(coverBottomLeft: coverBottomLeft), child: const SizedBox.expand());
  @override
  Future<OmrFrame?> frame({int maxSide = 640, int quality = 70}) async => OmrFrame(Uint8List.fromList([0xFF, 0xD8, 1]), 540, 720);
  @override
  Future<Uint8List?> photo() async => Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 2]);
  @override
  bool get canTorch => true;
  @override
  bool get torchOn => false;
  @override
  Future<void> setTorch(bool on) async {}
  @override
  bool get canSwitch => true;
  @override
  Future<void> switchCamera() async {}
  @override
  Future<void> dispose() async {}
}

FakeApi? _fake;

/// The scanner screen over the fake backend, after [pump] of real time.
Widget _scanner(List<String> hints, List<String> captures, {OmrCameraIssue? issue, bool cover = false}) {
  final h = [...hints], c = [...captures];
  var calls = 0;
  _fake?.uninstall();
  _fake = FakeApi({
    'POST /api/v1/exam/exams/1/omr/live-hint': (_) {
      calls++;
      return _reply(h.length > 1 ? h.removeAt(0) : h.first);
    },
    'POST /api/v1/exam/exams/1/omr/capture': (_) => _reply(c.length > 1 ? c.removeAt(0) : c.first),
  }, latency: const Duration(milliseconds: 20))
    ..install();
  return OmrScannerScreen(
    examId: 1,
    examTitle: t('اختبار الفيزياء — الفصل 10 ب', 'Physics quiz — class 10B'),
    camera: () => _PhotoCamera(issue: issue, coverBottomLeft: cover),
    clock: () => DateTime(2026, 11, 2).add(Duration(milliseconds: 420 * calls)),
  );
}

Widget _page(String title, Widget body) => Builder(
      builder: (context) => Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(title: Text(title)),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: ListView(padding: const EdgeInsets.all(16), children: [body])),
        ),
      ),
    );

Future<void> _render(WidgetTester tester, String name, Widget Function() build, {int frames = 8}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpWidget(_host(build(), dark: dark));
          for (var i = 0; i < frames; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile(Uri.file('$_dir/omrscan_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png')),
          );
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  setUpAll(_loadFonts);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.disableList = [];
  });

  testWidgets('hint', (t0) => _render(t0, 'hint', () => _scanner(['hint_moving'], ['capture_session_1']), frames: 6));
  testWidgets('accepted',
      (t0) => _render(t0, 'accepted', () => _scanner(['hint_ready_first', 'hint_ready'], ['capture_session_1']), frames: 15));
  testWidgets('rejected',
      (t0) => _render(t0, 'rejected', () => _scanner(['hint_ready_first', 'hint_ready'], ['capture_mark_missing'], cover: true), frames: 15));
  testWidgets('blocked', (t0) => _render(t0, 'blocked', () => _scanner(['hint_ready'], ['capture_session_1'], issue: OmrCameraIssue.blocked)));

  testWidgets('progress', (t0) => _render(t0, 'progress', () {
        final p = OmrBatchProgress.fromJson(_body('batch_done'));
        return _page(
            t('معالجة الأوراق', 'Processing papers'),
            ScanProgressView(
              headline: p.text,
              done: p.done,
              total: p.total,
              finished: p.finished,
              graded: p.graded,
              review: p.review,
              rejected: p.rejected,
              rejectedPages: [
                for (final r in p.rejectedPages) RejectedPageRow(pageId: r.pageId, text: r.text, instruction: r.instruction, fileName: r.fileName),
              ],
              onReplace: (_) {},
              onResults: () {},
              onMore: () {},
            ));
      }));

  // "Replace this page" on e2e_omr_replace.py's own replies: the batch with page 2 rejected, the gate refusing the
  // first photo with its exact reason (test/fixtures/payloads/omr_review/rep_*)
  testWidgets('replace', (t0) => _render(t0, 'replace', () {
        Map<String, dynamic> rep(String n) => Map<String, dynamic>.from(
            (jsonDecode(File('test/fixtures/payloads/omr_review/$n.json').readAsStringSync()) as Map)['payload'] as Map);
        final p = OmrBatchProgress.fromJson(rep('rep_batch_before'));
        final no = OmrReplaceResult.fromJson(rep('rep_gate_rejected'));
        return _page(
            t('معالجة الأوراق', 'Processing papers'),
            ScanProgressView(
              headline: p.text,
              done: p.done,
              total: p.total,
              finished: p.finished,
              graded: p.graded,
              review: p.review,
              rejected: p.rejected,
              rejectedPages: [
                for (final r in p.rejectedPages)
                  RejectedPageRow(
                      pageId: r.pageId, text: r.text, instruction: r.instruction, fileName: r.fileName, replacement: 'refused', replacementText: no.refusal),
              ],
              onReplace: (_) {},
              onResults: () {},
              onMore: () {},
            ));
      }));

  testWidgets('tools', (t0) => _render(t0, 'tools', () {
        final info = OmrSheetsInfo.fromJson(_body('sheets_info'));
        final copies = TextEditingController(text: '20');
        return _page(
            t('الأوراق الممسوحة', 'Scanned pages'),
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              OmrToolsPanel(entries: [
                OmrToolEntry(id: 'print', icon: Icons.print_outlined, title: t('طباعة أوراق التظليل', 'Print bubble sheets'),
                    subtitle: t('PDF لكل نموذج، أو ورقة باسم كل طالب', 'A PDF per model, or a named sheet per student'), onTap: () {}),
                OmrToolEntry(id: 'camera', icon: Icons.document_scanner_outlined, title: t('التصوير بالكاميرا', 'Scan with camera'),
                    subtitle: t('التقاط تلقائي عند ثبات الورقة ووضوحها', 'Captures by itself when the sheet is steady and sharp'), onTap: () {}),
                OmrToolEntry(id: 'upload', icon: Icons.upload_file_rounded, title: t('رفع صور أو PDF', 'Upload images / PDF'),
                    subtitle: t('عدة صور أو ملفات PDF دفعة واحدة', 'Many images or PDFs at once'), onTap: () {}),
                OmrToolEntry(id: 'review', icon: Icons.rate_review_outlined, title: t('المراجعة', 'Review'), subtitle: '', note: t('تتوفر قريبًا', 'Available soon')),
                OmrToolEntry(id: 'results', icon: Icons.leaderboard_outlined, title: t('النتائج', 'Results'), subtitle: '', note: t('تتوفر قريبًا', 'Available soon')),
              ]),
              const SizedBox(height: 16),
              OmrSheetsOptionsView(
                info: info,
                named: false,
                onNamed: (_) {},
                forms: {...info.forms},
                onForm: (_) {},
                copiesController: copies,
                students: const SizedBox.shrink(),
                onDownload: () {},
                onShare: () {},
              ),
            ]));
      }));
}
