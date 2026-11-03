// Visual review renders of the OMR fix round of 2026-11-03 (a UI check of the real web app), compared by eye like the
// other test/visual files (NOT a CI suite). The PNGs go OUTSIDE the repo:
//
//   OMR_RENDER_DIR=<dir> flutter test test/visual/omr_ui_fix_golden_test.dart --update-goldens [--plain-name batch]
//
// → <dir>/omrfix_<scene>_<width>_<lang>_<light|dark>.png, from test/org/fixtures/omr_smart_payloads.json:
//   batch        the batch page over the round-3 contract: one count per card, each sentence once, Replace on the paper
//                read in part, the rejected page's message + tip, "read" not "graded"
//   batch_old    the same over an older server (identity counted in review_count): the server's sentence as the title
//   id_blank     an ID with nothing read: "No number could be read", the students listed first
//   id_proposed  the QR's student proposed first
//   dup          "This student already has a graded sheet": the student, the graded page, "Use this sheet for …"
//   conflict     the QR and the shaded ID name two students, both by name and masked ID
//   quality      an image-quality item with Replace this page
//   bubble       the answer buttons A → D in the sheet's order (Arabic too)
//   queue        the review list: page · file · time per entry
//   review_page  the real review page over the fake backend (the phone's short title)
//   print_block  the print options of a block-fit exam: blank and pre-filled disabled with their reasons
// Final polish round (same day):
//   batch_names  the batch page with the names the server sends now (every photo page 1 of itself, `page_label` the
//                name, a PDF's page): "Paper N" on every card, "PDF page 2 of scan.pdf"
//   batches      the scan page's batches: the latest five + "Show all batches"; all of them + "Show older batches"
//   queue_names  the review list with long file names at the desktop side list's width: the time whole
//   quality_names an image-quality item of a photo named by its label ("Page 3 · wa01.jpg", not "Page 1")
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/shared/exam_engine/paper/omr_counts.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_results_screen.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review_page.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review_parts.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_paper_result.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scan.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scan_widgets.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_sheets_sheet.dart';
import 'package:flutter_education_app/utils/live_events.dart';
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

final _smart = (jsonDecode(File('test/org/fixtures/omr_smart_payloads.json').readAsStringSync()) as Map)['payloads'] as Map;
Map<String, dynamic> _s(String name) => Map<String, dynamic>.from((_smart[name] as Map)['body'] as Map);
OmrReviewItem _item(String name) => OmrReviewItem.fromJson(_s(name));

final _shot = GlobalKey();
final _dir = (Platform.environment['OMR_RENDER_DIR'] ?? '${Directory.systemTemp.path}/omr_renders').replaceAll('\\', '/');
final _connected = ValueNotifier<bool>(true);
final _stream = LiveStreamHandle(connected: _connected, bind: () {}, release: () {});

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

Widget _page(String title, Widget body, {double maxWidth = 760}) => Builder(
      builder: (context) => Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(title: Text(title)),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: ListView(padding: const EdgeInsets.all(16), children: [body])),
        ),
      ),
    );

Future<void> _render(WidgetTester tester, String name, Widget Function() build,
    {int frames = 8, double phoneH = 844, double deskH = 900, void Function()? before}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in [Size(390, phoneH), Size(1440, deskH)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
          before?.call();
          await tester.pumpWidget(_host(build(), dark: dark));
          for (var i = 0; i < frames; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile(Uri.file('$_dir/omrfix_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png')),
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

Widget _batch(String name, [Map<String, dynamic>? body]) {
  final b = OmrBatchProgress.fromJson(body ?? _s(name));
  // as omr_upload_screen.dart builds them: "Paper N" by the page's name in the batch, "PDF page 2 of scan.pdf"
  final rows = [
    for (final (i, p) in b.pages.indexed)
      if (p.result != null && p.result!.tier != OmrTier.reject)
        OmrPaperRow(
            pageId: p.pageId, label: omrPaperText(p.label.isEmpty ? '${i + 1}' : p.label), fileName: omrFilePlace(p.fileName, p.pageFilePage), result: p.result!),
  ];
  return _page(
      t('معالجة الأوراق', 'Processing papers'),
      ScanProgressView(
        headline: b.text,
        done: b.done,
        total: b.total,
        finished: b.finished,
        graded: b.graded,
        review: b.review,
        rejected: b.rejected,
        rejectedPages: [
          for (final r in b.rejectedPages)
            RejectedPageRow(
                pageId: r.pageId,
                label: omrPaperText(r.label.isEmpty ? '${r.pageNo}' : r.label),
                text: r.text,
                instruction: r.instruction,
                fileName: omrFilePlace(r.fileName, r.pageFilePage),
                result: r.result),
        ],
        papers: rows,
        onReplace: (_) {},
        onPreview: (_, _) {},
        onReview: () {},
        onResults: () {},
        onMore: () {},
      ));
}

/// batch_v3 as the server sends it now: every photo is page 1 of its own file, named by `page_label`; page 104 is page
/// 2 of a PDF uploaded with the photos.
Map<String, dynamic> _realBatch() {
  final b = jsonDecode(jsonEncode(_s('batch_v3'))) as Map<String, dynamic>;
  for (final p in [...(b['pages'] as List), ...(b['rejected_pages'] as List)].cast<Map>()) {
    p['page_no'] = 1;
    if (p['page_id'] == 104) {
      p['file_name'] = 'scan.pdf';
      p['page_no'] = 2;
      p['page_file_page'] = 2;
    }
  }
  return b;
}

Map<String, dynamic> _batchRow(int id, {int review = 1, int rejected = 0}) => {
      'batch_id': id, 'exam_id': 1, 'kind': id.isEven ? 'camera' : 'omr', 'total': 2 + rejected, 'done': 2 + rejected, 'graded': 1,
      'review': review, 'rejected': rejected, 'failed': 0, 'pending': 0, 'status': 'done', 'expected': null,
      'created_at': '2026-11-0${1 + id % 3}T0${id % 10}:15:00', 'en': '${2 + rejected} of ${2 + rejected} papers processed',
      'ar': 'تمت معالجة ${2 + rejected} من ${2 + rejected} أوراق',
    };

Widget _batches() {
  final rows = [for (var i = 9; i > 0; i--) OmrBatchProgress.fromJson(_batchRow(i, rejected: i % 3 == 0 ? 1 : 0))];
  return _page(
      t('أوراق التظليل', 'Bubble sheet'),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        OmrBatchesPanel(batches: rows, onOpen: (_) {}, onShowAll: () {}),
        const SizedBox(height: 24),
        OmrBatchesPanel(batches: rows, expanded: true, hasMore: true, onOpen: (_) {}, onMore: () {}),
      ]));
}

OmrReviewItem _named(Map<String, dynamic> m) {
  final x = jsonDecode(jsonEncode(m)) as Map<String, dynamic>;
  x['page_label'] = '${x['page_no'] ?? 1}';
  x['page_no'] = 1;
  return OmrReviewItem.fromJson(x);
}

const _audience = [
  OmrStudent(21, 'Mona Adel', identifier: '••••••0121'),
  OmrStudent(22, 'Omar Adel', identifier: '••••••0122'),
  OmrStudent(24, 'Sara Nabil'),
];

Widget _card(OmrReviewItem it) => _page(
    t('مراجعة الأوراق الممسوحة', 'Review scanned papers'),
    OmrReviewItemCard(
      item: it,
      crop: null,
      position: t('1 من 5', '1 of 5'),
      fix: OmrFixCallbacks(
        onChoose: (_) {},
        onBlank: () {},
        onAccept: () {},
        onFix: (_) {},
        onAssign: (_) {},
        onSearch: (_) async => _audience,
        onDismiss: () {},
        onReplace: () {},
        onReplacePage: () {},
        onOpenPaper: () {},
      ),
    ),
    maxWidth: 920);

void main() {
  setUpAll(_loadFonts);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.disableList = [];
  });

  testWidgets('batch', (t0) => _render(t0, 'batch', () => _batch('batch_v3'), phoneH: 2300, deskH: 1700));
  testWidgets('batch_old', (t0) => _render(t0, 'batch_old', () => _batch('batch_old_identity'), phoneH: 1300, deskH: 1000));
  testWidgets('id_blank', (t0) => _render(t0, 'id_blank', () => _card(_item('review_item_v3_blank')), phoneH: 1500, deskH: 1100));
  testWidgets('id_old', (t0) => _render(t0, 'id_old', () => _card(_item('review_item_old_qq')), phoneH: 1500, deskH: 1100));
  testWidgets('id_proposed', (t0) => _render(t0, 'id_proposed', () => _card(_item('review_item_v3_proposed')), phoneH: 1500, deskH: 1100));
  testWidgets('dup', (t0) => _render(t0, 'dup', () => _card(_item('review_item_v3_duplicate')), phoneH: 1100));
  testWidgets('conflict', (t0) => _render(t0, 'conflict', () => _card(_item('review_item_v3_conflict')), phoneH: 1300, deskH: 1000));
  testWidgets('quality', (t0) => _render(t0, 'quality', () => _card(_item('review_item_v3_quality'))));
  testWidgets('bubble', (t0) {
    final it = OmrReviewList.fromJson(_s('review_items_v3')).items.firstWhere((i) => i.kind == 'bubble');
    return _render(t0, 'bubble', () => _card(it));
  });
  testWidgets('queue', (t0) {
    final list = OmrReviewList.fromJson(_s('review_items_v3'));
    return _render(t0, 'queue', () => _page(t('قائمة المراجعة', 'Review queue'), OmrQueueList(items: list.items, currentId: 31, onTap: (_) {}), maxWidth: 360));
  });
  testWidgets('review_page', (t0) async {
    FakeApi? fake;
    try {
      await _render(t0, 'review_page', () => OmrReviewPage(examId: 1, initialItemId: 31, liveStream: _stream, liveBus: LiveEvents.instance, meId: 10),
          frames: 12, before: () {
        fake?.uninstall();
        fake = FakeApi({
          'GET /api/v1/exam/exams/1/review-items': (_) => _s('review_items_v3'),
          'GET /api/v1/exam/exams/1/review-items/31': (_) => _s('review_item_v3_blank'),
          'GET /api/v1/exam/exams/1/review-items/32': (_) => _s('review_item_v3_proposed'),
          'GET /api/v1/exam/exams/1/omr/students': (_) => payload('omr_review/aud_all.json'),
        }, latency: const Duration(milliseconds: 10))
          ..install();
      });
    } finally {
      fake?.uninstall();
    }
  });
  testWidgets('results_stats', (t0) async {
    // the exam's results page: the three numbers on one line on a phone, at the cards' gutter
    FakeApi? fake;
    try {
      await _render(t0, 'results_stats', () => const ExamResultsScreen(examId: 1, examTitle: 'Phone test — bubble'), frames: 10, before: () {
        fake?.uninstall();
        fake = FakeApi({
          'GET /api/v1/exam/exams/1': (_) => {
                'id': 1, 'org_id': null, 'course_id': 9, 'title': 'Phone test — bubble', 'status': 'published', 'allowed_platforms': ['web'],
                'max_attempts': 1, 'results_policy': 'when_published', 'version': 1, 'settings': {}, 'sections': [], 'max_score': 5,
              },
          'GET /api/v1/exam/exams/1/attempts': (_) => {'items': []},
          'GET /api/v1/exam/exams/1/setup': (_) => {'delivery': 'paper', 'paper_format': 'bubble'},
          'GET /api/v1/exam/exams/1/scans': (_) => {'items': []},
          'GET /api/v1/exam/exams/1/omr/batches': (_) => {'items': []},
        }, latency: const Duration(milliseconds: 10))
          ..install();
      });
    } finally {
      fake?.uninstall();
    }
  });
  testWidgets('batch_names', (t0) => _render(t0, 'batch_names', () => _batch('batch_v3', _realBatch()), phoneH: 2300, deskH: 1700));
  testWidgets('batches', (t0) => _render(t0, 'batches', _batches, phoneH: 2600, deskH: 2000));
  testWidgets('queue_names', (t0) {
    final items = [
      for (final i in (_s('review_items_v3')['items'] as List).cast<Map<String, dynamic>>()) _named(i),
      _named({'id': 90, 'kind': 'quality', 'code': 'mark_missing_top_right', 'status': 'open', 'page_no': 1, 'file_name': 'scaled_1000237462.jpg',
        'batch_created_at': '2026-11-03T01:18:00', 'en': 'Page 1 has its top-right corner mark hidden. Please upload a clearer image of it.',
        'ar': 'الصفحة 1 علامة ركنها العلوي الأيمن غير ظاهرة. يرجى رفع صورة أوضح لها.'}),
      _named({'id': 91, 'kind': 'quality', 'code': 'blurry', 'status': 'open', 'page_no': 14, 'page_file_page': 3, 'file_name': 'scan_of_the_whole_class_morning_group.pdf',
        'batch_created_at': '2026-11-02T09:05:00', 'en': 'Page 14 (scan_of_the_whole_class_morning_group.pdf, page 3) is too blurry. Please upload a clearer image of it.',
        'ar': 'الصفحة 14 (scan_of_the_whole_class_morning_group.pdf، الصفحة 3) غير واضحة (مهزوزة). يرجى رفع صورة أوضح لها.'}),
    ];
    return _render(t0, 'queue_names', () => _page(t('قائمة المراجعة', 'Review queue'), OmrQueueList(items: items, currentId: 34, onTap: (_) {}), maxWidth: 340),
        phoneH: 1300, deskH: 1300);
  });
  testWidgets('quality_names', (t0) => _render(t0, 'quality_names', () => _card(_named(_s('review_item_v3_quality')))));
  testWidgets('print_block', (t0) {
    final copies = TextEditingController(text: '1');
    return _render(
        t0,
        'print_block',
        () => _page(
            t('طباعة أوراق التظليل', 'Print bubble sheets'),
            OmrSheetsOptionsView(
              info: OmrSheetsInfo.fromJson(_s('sheets_info_block')),
              mode: OmrPrintMode.named,
              onMode: (_) {},
              forms: const {'A'},
              onForm: (_) {},
              copiesController: copies,
              students: const SizedBox(height: 8),
              onDownload: () {},
              onShare: () {},
            )),
        phoneH: 1100);
  });
}
