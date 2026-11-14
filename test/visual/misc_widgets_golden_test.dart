// VISUAL review renders of the older shared widgets in the Warm Editorial theme (lib/utils/widget and the ads
// pieces): the home ad as a tinted block, the rating card, the request-queue pieces, the paging strip and the
// refresh pill — at 390x844 and 1440x900, ar / en, light / dark, into test/visual/goldens/misc_widgets_*.png.
// Not a CI suite; compared by eye.
//
//   flutter test test/visual/misc_widgets_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/ads/ads_pages.dart' show AdCard;
import 'package:flutter_education_app/utils/widget/paged_progress.dart';
import 'package:flutter_education_app/utils/widget/rating_widget.dart';
import 'package:flutter_education_app/utils/widget/swipe_request_card.dart';
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
String _tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

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
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: RepaintBoundary(
        key: _shot,
        child: Builder(builder: (context) => Scaffold(backgroundColor: context.colors.background, body: child)),
      ),
    ),
  );
}

Future<void> _frames(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

RateResponse _rate(int id, int value) =>
    RateResponse(id: id, studentId: id, sourceId: 1, type: RateType.course, value: value, review: null, createdAt: DateTime(2026, 11, 1));

Widget _gallery() {
  final summary = RatingSummary(ratings: [for (var i = 0; i < 37; i++) _rate(i, i % 7 == 0 ? 2 : 3 + i % 3)], total: 37, average: 4.1);
  final ctl = SwipeCardController(busy: false, approve: () async {}, reject: () async {});
  return LayoutBuilder(builder: (context, box) {
    final ratio = box.maxWidth > 700 ? 16 / 5.6 : 16 / 8.5;
    return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
      AppWidthBox(
        width: AppWidth.content,
        gutters: false,
        child: Column(children: [
          AspectRatio(
            aspectRatio: ratio,
            child: AdCard(
              ad: {
                'id': 3,
                'title': _tr('دورة المراجعة النهائية للفيزياء', 'Final physics revision course'),
                'body': _tr('عشر جلسات مباشرة قبل الامتحان', 'Ten live sessions before the exam'),
                'target_type': 'course',
                'likes': 24,
                'my_reaction': 1,
              },
              onTap: () {},
              onReact: (_) {},
            ),
          ),
          AppSpace.gapMd,
          AspectRatio(
            aspectRatio: ratio,
            child: AdCard(
              ad: {'id': 12, 'title': _tr('شاهد كيف تحضّر للامتحان', 'How to prepare for the exam'), 'media_type': 'video', 'target_type': 'none'},
              onTap: () {},
              onReact: (_) {},
            ),
          ),
          AppSpace.gapMd,
          Row(children: [
            for (final id in [1, 2, 5])
              Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
                child: SizedBox(
                  width: 96,
                  child: AspectRatio(aspectRatio: 16 / 9, child: AdCard(ad: {'id': id, 'title': 'x', 'media_type': id == 2 ? 'video' : 'image'}, compact: true)),
                ),
              ),
          ]),
          AppSpace.gapLg,
          RatingWidget(type: RateType.course, sourceId: '1', canEdit: true, compact: false, rateSummary: summary),
          AppSpace.gapMd,
          Align(alignment: AlignmentDirectional.centerStart, child: RatingWidget(type: RateType.course, sourceId: '2', canEdit: false, rateSummary: summary)),
          AppSpace.gapLg,
          const SwipeHintBanner(count: 4),
          RequestCardShell(
            child: Column(children: [
              Row(children: [
                const RequestAvatar(name: 'Mona Adel'),
                AppSpace.gapSm,
                Expanded(child: Text(_tr('منى عادل', 'Mona Adel'), style: AppType.section(context))),
              ]),
              AppSpace.gapSm,
              RequestInfoRow(icon: Icons.payments_rounded, label: _tr('المبلغ', 'Amount'), value: '450 EGP'),
              AppSpace.gapXs,
              RequestInfoRow(icon: Icons.tag_rounded, label: _tr('رقم التحويل', 'Transfer number'), value: '0193 4421 88', copyable: true),
              AppSpace.gapMd,
              RequestActionButtons(ctl: ctl, approveLabel: _tr('قبول', 'Accept'), rejectLabel: _tr('رفض', 'Reject')),
            ]),
          ),
          AppSpace.gapLg,
          const PagedCountCard(loaded: 40, total: 134, loadingMore: false, done: false),
        ]),
      ),
    ]);
  });
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('misc widgets gallery', (tester) async {
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
            await tester.pumpWidget(_host(_gallery(), dark: dark));
            await _frames(tester);
            for (var i = 0; i < 4; i++) {
              var extra = 0.0;
              for (final e in find.byType(Scrollable).evaluate()) {
                final s = (e as StatefulElement).state as ScrollableState;
                if (s.position.axis == Axis.vertical && s.position.hasContentDimensions) {
                  extra = math.max(extra, s.position.maxScrollExtent);
                }
              }
              if (extra < 1) break;
              tester.view.physicalSize = Size(size.width, math.min(6000, tester.view.physicalSize.height + extra));
              await _frames(tester, 6);
            }
            final e = tester.takeException();
            expect(e, isNull, reason: '${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
            await expectLater(
              find.byKey(_shot),
              matchesGoldenFile('goldens/misc_widgets_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
            );
          }
        }
      }
    } finally {
      AppConfig.lang = prevLang;
      debugDisableShadows = true;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
