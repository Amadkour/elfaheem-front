// VISUAL review renders (not a CI suite): the student's own pages around the home in the Warm Editorial theme — the
// points wallet (the balance block with its rolling figure, the plan, top-ups, history), the live-meeting plan sheet,
// the card top-up's outcome, and My certificates (the gold "earned" block, the certificate cards) — at 390x844 and
// 1440x900, ar / en, light / dark, into test/visual/goldens/student_<page>_*.png. Compared by eye.
//
//   flutter test test/visual/student_rewards_golden_test.dart --update-goldens [--plain-name wallet]
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/payments/points/live_plan_sheet.dart';
import 'package:flutter_education_app/features/payments/points/points_api.dart';
import 'package:flutter_education_app/features/payments/points/points_card_checkout.dart';
import 'package:flutter_education_app/features/payments/points/points_wallet_page.dart';
import 'package:flutter_education_app/features/student/certificates/my_certificate_model.dart';
import 'package:flutter_education_app/features/student/certificates/my_certificates_provider.dart';
import 'package:flutter_education_app/features/student/certificates/my_certificates_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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
  await load('MaterialIcons', ['${_sdkFonts()}/materialicons-regular.otf']);
}

final _shot = GlobalKey();
final _now = DateTime.now().toUtc();
String _tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;
String _iso(DateTime d) => d.toUtc().toIso8601String().replaceAll('Z', '');

PointsWallet _wallet() => PointsWallet.fromJson({
      'balance': 1240,
      'price_per_point': 0.5,
      'currency': 'EGP',
      'topup_min': 50,
      'methods': ['card', 'bank_transfer', 'instapay'],
      'topups': [
        {'id': 3, 'points': 500, 'amount': 250, 'currency': 'EGP', 'method': 'instapay', 'status': 'pending', 'created_at': _iso(_now.subtract(const Duration(hours: 3)))},
        {'id': 2, 'points': 1000, 'amount': 500, 'currency': 'EGP', 'method': 'card', 'status': 'approved', 'created_at': _iso(_now.subtract(const Duration(days: 6)))},
      ],
      'history': [
        {'id': 5, 'delta': -300, 'balance_after': 1240, 'kind': 'spend', 'ref_type': 'live_meeting', 'created_at': _iso(_now.subtract(const Duration(days: 1)))},
        {'id': 4, 'delta': 1000, 'balance_after': 1540, 'kind': 'topup', 'created_at': _iso(_now.subtract(const Duration(days: 6)))},
        {'id': 3, 'delta': 40, 'balance_after': 540, 'kind': 'grant', 'note': _tr('مكافأة الحضور', 'Attendance bonus'), 'by_user': {'name': _tr('إدارة المنصة', 'Platform admin')}, 'created_at': _iso(_now.subtract(const Duration(days: 12)))},
        {'id': 2, 'delta': -500, 'balance_after': 500, 'kind': 'spend', 'ref_type': 'live_meeting', 'created_at': _iso(_now.subtract(const Duration(days: 30)))},
      ],
    });

LivePlan _plan({bool active = false}) => LivePlan(
    active: active,
    endsAt: active ? _now.add(const Duration(days: 23)) : null,
    pricePoints: 300,
    days: 30,
    freeMinutes: 15,
    balance: 1240,
    dailyFreeMinutes: 45,
    dailyFreeLeft: 20,
    autoRenew: active);

MyCertificatesProvider _certs() => MyCertificatesProvider()
  ..items = [
    for (final j in [
      {
        'certificate_id': 1, 'course_id': 11, 'course_name_ar': 'أساسيات بايثون', 'course_name_en': 'Python fundamentals',
        'title': _tr('شهادة إتمام أساسيات بايثون', 'Python fundamentals — certificate of completion'),
        'teacher_name': _tr('د. منى عادل', 'Dr. Mona Adel'), 'progress': 64, 'state': 'available', 'can_request': true,
      },
      {
        'certificate_id': 2, 'course_id': 12, 'course_name_ar': 'التصميم الجرافيكي', 'course_name_en': 'Graphic design',
        'title': _tr('شهادة التصميم الجرافيكي', 'Graphic design certificate'), 'teacher_name': _tr('أ. كريم سامي', 'Karim Samy'),
        'progress': 100, 'state': 'pending',
      },
      {
        'certificate_id': 3, 'course_id': 13, 'course_name_ar': 'اللغة الإنجليزية للأعمال', 'course_name_en': 'Business English',
        'title': _tr('شهادة الإنجليزية للأعمال', 'Business English certificate'), 'progress': 80, 'state': 'rejected',
        'rejection_reason': _tr('أكمل الاختبار النهائي أولاً', 'Finish the final exam first'),
      },
    ])
      MyCertificate.fromJson(j),
  ];

Future<void> _render(WidgetTester tester, String name, Widget Function(BuildContext context) page) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          final theme = ThemeConfigProvider(api: ApiClient());
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(ThemeConfigScope(
            provider: theme,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme.materialTheme(dark: false),
              darkTheme: theme.materialTheme(dark: true),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              builder: (context, w) => Directionality(
                  textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
                  child: DefaultTextStyle.merge(style: TextStyle(fontFamilyFallback: AppFonts.fallback), child: w!)),
              home: RepaintBoundary(
                key: _shot,
                child: Builder(builder: (context) => Scaffold(backgroundColor: context.colors.background, body: SafeArea(child: page(context)))),
              ),
            ),
          ));
          for (var i = 0; i < 14; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          tester.takeException(); // network pictures fail in a test: their error builders draw
          await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/student_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

/// A bottom sheet's paper, as showAppSheet draws it, at the bottom of the window.
Widget _sheet(BuildContext context, Widget child) => Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: AppWidth.form.max),
        child: Material(
          color: context.colors.cardBg,
          borderRadius: AppRadius.sheetTop,
          child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.lg, AppSpace.md, AppSpace.lg), child: child),
        ),
      ),
    );

void main() {
  setUpAll(() async {
    await _loadFonts();
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });

  testWidgets('wallet', (tester) async {
    await _render(tester, 'wallet', (_) => PointsWalletView(wallet: _wallet(), plan: _plan(), nowUtc: _now, onBuy: () {}, onOpenPlan: () {}));
  });

  testWidgets('plan sheet', (tester) async {
    await _render(
        tester,
        'plan',
        (context) => _sheet(
            context,
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppSheetHeader(_tr('باقة الاجتماعات المباشرة', 'Live-meeting plan')),
              LivePlanView(plan: _plan(), nowUtc: _now, onSubscribe: () {}, onWallet: () {}, onAutoRenew: (_) {}),
            ])));
  });

  testWidgets('card outcome', (tester) async {
    await _render(
        tester,
        'card_paid',
        (context) => _sheet(context,
            CardTopupStatusView(phase: CardTopupPhase.approved, points: 1000, amountText: '500 EGP', onClose: () {})));
  });

  testWidgets('certificates', (tester) async {
    await _render(tester, 'certificates',
        (_) => ChangeNotifierProvider<MyCertificatesProvider>.value(value: _certs(), child: const MyCertificatesView(embedded: true)));
  });
}
