// Visual review renders of the OMR review queue and results (brief Part 4), compared by eye like the other
// test/visual files (NOT a CI suite). Real engine replies (test/fixtures/payloads/omr_review/) and the real crops /
// page the engine produced in the same run (test/fixtures/omr_review/). The PNGs go OUTSIDE the repo:
//
//   OMR_RENDER_DIR=<dir> flutter test test/visual/omr_review_golden_test.dart --update-goldens [--plain-name paper]
//
// → <dir>/omrr_<scene>_<width>_<lang>_<light|dark>.png
//   multiple   the queue on "More than one answer was shaded" (crop, fills, A–D), the line of the previous fix
//   unclear    a handwritten ID with one unsure digit (Example 7): crop, digits, accept / fix / choose the student
//   form       "Model could not be confirmed" (QR B, printed A): choose the form
//   paper      the full page with the detected answers drawn over it
//   results    grades, the score distribution, per-question statistics, publish
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_results_parts.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review_parts.dart';
import 'package:flutter_test/flutter_test.dart';

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

final _shot = GlobalKey();
final _dir = (Platform.environment['OMR_RENDER_DIR'] ?? '${Directory.systemTemp.path}/omr_renders').replaceAll('\\', '/');

Map<String, dynamic> _p(String name) =>
    Map<String, dynamic>.from((jsonDecode(File('test/fixtures/payloads/omr_review/$name.json').readAsStringSync()) as Map)['payload'] as Map);
Uint8List _img(String name) => File('test/fixtures/omr_review/$name.png').readAsBytesSync();

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

Widget _scaffold(String title, Widget body) => Builder(
      builder: (context) => Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(title: Text(title), actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.history_rounded)),
          IconButton(onPressed: () {}, icon: const Icon(Icons.leaderboard_outlined)),
        ]),
        body: body,
      ),
    );


OmrFixCallbacks _all() => OmrFixCallbacks(
      onChoose: (_) {},
      onBlank: () {},
      onAccept: () {},
      onFix: (_) {},
      onAssign: (_) {},
      onSearch: (_) async => const [],
      onConfirmForm: (_) {},
      onDismiss: () {},
      onReplace: () {},
      onOpenPaper: () {},
    );

/// The queue screen as the page lays it out: the side list on wide screens, the chips + card on phones.
Widget _queue(String itemFixture, String listFixture, String crop, {OmrResolveReply? last}) {
  final item = OmrReviewItem.fromJson(_p(itemFixture));
  final list = OmrReviewList.fromJson(_p(listFixture));
  final i = list.items.indexWhere((x) => x.id == item.id);
  return _scaffold(
    t('مراجعة الأوراق الممسوحة', 'Review scanned papers'),
    LayoutBuilder(builder: (context, box) {
      final c = context.colors;
      final card = OmrReviewItemCard(item: item, crop: _img(crop), fix: _all(), position: i < 0 ? null : t('${i + 1} من ${list.items.length}', '${i + 1} of ${list.items.length}'));
      final detail = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (last != null) ...[OmrScoreBanner(reply: last), const SizedBox(height: 12)],
        card,
      ]);
      final filter = OmrKindFilter(list: list, selected: null, onPick: (_) {});
      if (box.maxWidth < 1000) {
        return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [filter, const SizedBox(height: 12), detail]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 360,
          child: DecoratedBox(
            decoration: BoxDecoration(border: BorderDirectional(end: BorderSide(color: c.divider))),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              filter,
              const SizedBox(height: 16),
              OmrQueueList(items: list.items, currentId: item.id, onTap: (_) {}),
            ]),
          ),
        ),
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 920), child: ListView(padding: const EdgeInsets.all(24), children: [detail])),
          ),
        ),
      ]);
    }),
  );
}

Widget _paper() {
  final page = OmrPageView.fromJson(_p('bubble_page_1'));
  final bytes = _img('page_bubble_1');
  return _scaffold(
    t('الورقة · صفحة 1', 'Paper · page 1'),
    LayoutBuilder(builder: (context, box) {
      final overlay = OmrPaperOverlay(page: page, bytes: bytes, focusN: 4);
      final side = ListView(children: [
        Text(t('الأسئلة كما قُرئت', 'The questions as read'), style: appText(14, w: FontWeight.w700, c: context.colors.textDark)),
        const SizedBox(height: 8),
        OmrPageAnswers(page: page, onItem: (_) {}),
        const SizedBox(height: 12),
        Text(t('رقم الطالب: ${page.identifierValue}', 'Student ID: ${page.identifierValue}'), style: appText(13, c: context.colors.textMedium)),
      ]);
      if (box.maxWidth >= 1000) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(flex: 3, child: overlay), const SizedBox(width: 24), Expanded(flex: 2, child: side)]),
        );
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(flex: 3, child: overlay), const SizedBox(height: 12), Expanded(flex: 2, child: side)]),
      );
    }),
  );
}

Widget _results() {
  final r = OmrResults.fromJson(_p('scan_results'));
  return _scaffold(
    r.title,
    LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 1000;
      final pad = box.maxWidth < 600 ? 16.0 : 24.0;
      return ListView(padding: EdgeInsets.fromLTRB(pad, 16, pad, 32), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              OmrResultsSummary(results: r, onReview: () {}),
              const SizedBox(height: 12),
              AppBanner(
                icon: Icons.rate_review_rounded,
                color: context.colors.warning,
                text: t('${r.openReviewItems} عنصر ينتظر قرارك — لا تُحسب الدرجة قبل مراجعته', '${r.openReviewItems} items wait for your decision — a paper is not scored until they are resolved'),
                action: TextButton(onPressed: () {}, child: Text(t('مراجعة', 'Review'))),
              ),
              const SizedBox(height: 16),
              OmrPublishCard(results: r, onPublish: () {}),
              const SizedBox(height: 16),
              OmrDistributionCard(results: r),
              const SizedBox(height: 24),
              AppSectionTitle(t('الدرجات', 'Grades'), subtitle: t('${r.students.length} ورقة', '${r.students.length} papers')),
              const SizedBox(height: 8),
              OmrGradesView(results: r, wide: wide),
              const SizedBox(height: 24),
              AppSectionTitle(t('إحصاءات الأسئلة', 'Question statistics'), subtitle: t('الصعوبة = نسبة من أجابوا صحيحًا', 'Difficulty = the share who answered right')),
              const SizedBox(height: 8),
              OmrQuestionStatsView(questions: r.questions, wide: wide),
            ]),
          ),
        ),
      ]);
    }),
  );
}

Future<void> _render(WidgetTester tester, String name, Widget Function() build) async {
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
          await tester.pumpWidget(_host(build(), dark: dark));
          await tester.pump();
          await tester.runAsync(() async {
            for (final e in find.byType(Image).evaluate()) {
              await precacheImage((e.widget as Image).image, e);
            }
          });
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile(Uri.file('$_dir/omrr_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png')),
          );
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  setUpAll(_loadFonts);
  setUp(() => AppConfig.disableList = []);

  testWidgets('multiple', (t0) => _render(t0, 'multiple',
      () => _queue('bubble_item_2_multiple', 'bubble_items_open', 'crop_bubble_multiple', last: OmrResolveReply.fromJson(_p('bubble_resolve_4_uncertain')))));
  testWidgets('unclear', (t0) => _render(t0, 'unclear', () => _queue('unclear_item_8', 'unclear_items_open', 'crop_identifier_digits')));
  testWidgets('form', (t0) => _render(t0, 'form', () => _queue('scan_item_1_form_unconfirmed', 'scan_items_open_end', 'crop_form')));
  testWidgets('paper', (t0) => _render(t0, 'paper', _paper));
  testWidgets('results', (t0) => _render(t0, 'results', _results));
}
