// VISUAL review renders of the reading pages (D-088) — not a CI suite (test/visual is not one of CI's folders).
//
// Privacy & terms, Terms & conditions and About over the real screens and provider, with realistic bilingual content
// answered by a fake backend, plus the settings group with the inline language switch, at 390x844 (phone) and
// 1440x900 (desktop), Arabic and English, light and dark, into test/visual/goldens/reading_*.png. A page taller than
// the window is drawn whole; `terms_scrolled` keeps the phone window and scrolls, so the pinned section chips and the
// folded "Ask" pill show; `skeleton` is the loading state.
//
//   flutter test test/visual/reading_pages_golden_test.dart --update-goldens
//   VISUAL_THEME=production flutter test test/visual/reading_pages_golden_test.dart --update-goldens   (→ *_prod.png)
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_identity.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_language_switch.dart';
import 'package:flutter_education_app/features/shared/display/display_settings_page.dart' show DisplaySettingsTile;
import 'package:flutter_education_app/features/shared/profile/about/about_and_terms_screen.dart';
import 'package:flutter_education_app/features/shared/profile/about/about_terms_parts.dart';
import 'package:flutter_education_app/features/shared/profile/about/about_terms_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

// ── fonts (the families the pubspec bundles + the SDK's Roboto / icons) ──────────────────────────────────────────

String _sdkFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return '$root/bin/cache/artifacts/material_fonts';
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll('\\', '/');
  final i = exe.indexOf('/bin/cache/');
  return '${exe.substring(0, i)}/bin/cache/artifacts/material_fonts';
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
    await loader.load();
  }

  final family = RegExp(r'^\s*- family:\s*(\S+)\s*$');
  final asset = RegExp(r'^\s*- asset:\s*(\S+)\s*$');
  final fonts = <(String, List<String>)>[];
  for (final line in const LineSplitter().convert(File('pubspec.yaml').readAsStringSync())) {
    final f = family.firstMatch(line);
    if (f != null) {
      fonts.add((f.group(1)!, <String>[]));
      continue;
    }
    final a = asset.firstMatch(line);
    if (a != null && fonts.isNotEmpty) fonts.last.$2.add(a.group(1)!);
  }
  for (final (f, paths) in fonts) {
    await load(f, paths);
  }
  final sdk = _sdkFonts();
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
  // the app bar's back arrow (CupertinoIcons.back), from the package the lock file resolved
  final config = jsonDecode(File('.dart_tool/package_config.json').readAsStringSync()) as Map<String, dynamic>;
  for (final p in (config['packages'] as List).cast<Map<String, dynamic>>()) {
    if (p['name'] != 'cupertino_icons') continue;
    final root = Uri.parse(p['rootUri'] as String).toFilePath();
    await load('packages/cupertino_icons/CupertinoIcons', ['$root/assets/CupertinoIcons.ttf']);
  }
}

// ── content ─────────────────────────────────────────────────────────────────────────────────────────────────────

Map<String, dynamic> _terms(String lang) {
  final ar = lang == 'ar';
  Map<String, dynamic> s(int id, String icon, String tAr, String tEn, String bAr, String bEn) =>
      {'id': id, 'icon_name': icon, 'title': ar ? tAr : tEn, 'body': ar ? bAr : bEn, 'order': id, 'is_active': true};
  return {
    'meta': {'id': 1, 'last_updated': ar ? '6 أكتوبر 2026' : '6 October 2026', 'version': '3.0.0'},
    'sections': [
      s(1, 'gavel', 'قبول الشروط', 'Accepting these terms',
          'باستخدامك لتطبيق NextBrain فإنك توافق على هذه الشروط والأحكام، وعلى سياسة الخصوصية المرفقة بها.\n\nإذا لم توافق على أي بند، يُرجى التوقف عن استخدام التطبيق والتواصل معنا.',
          'By using NextBrain you agree to these terms and to the privacy policy that comes with them.\n\nIf you do not agree with any part, please stop using the app and get in touch with us.'),
      s(2, 'person', 'أهلية الاستخدام', 'Who can use the app',
          'يجب أن يكون عمر المستخدم 10 سنوات أو أكثر. ما دون ذلك يستخدم التطبيق بإشراف ولي الأمر.',
          'Users must be 10 years old or older. Younger learners use the app with a parent or guardian.'),
      s(3, 'privacy_tip', 'البيانات التي نحتفظ بها', 'The data we keep',
          'نحتفظ بأقل قدر ممكن من البيانات لتقديم الخدمة:\n- الاسم والبريد الإلكتروني ورقم الهاتف\n- تقدّمك في الدورات ونتائج الاختبارات\n- معرّف الجهاز لحماية حسابك من المشاركة\n\nلا نبيع بياناتك لأي طرف ثالث.',
          'We keep as little data as we can to run the service:\n- your name, e-mail address and phone number\n- your progress in courses and your exam results\n- a device id, so your account cannot be shared\n\nWe never sell your data to anyone.'),
      s(4, 'lock', 'الحساب وكلمة المرور', 'Your account and password',
          'أنت مسؤول عن الحفاظ على سرية كلمة مرورك. فعّل التحقق بخطوتين من الإعدادات لحماية أكبر.',
          'You are responsible for keeping your password secret. Turn on two-step verification in Settings for extra protection.'),
      s(5, 'payment', 'سياسة الدفع والاسترداد', 'Payments and refunds',
          'جميع المدفوعات نهائية ما لم يُذكر خلاف ذلك. لطلب استرداد:\n1. افتح مركز المساعدة\n2. اختر الدورة ثم «طلب استرداد»\n3. سنرد عليك خلال 3 أيام عمل',
          'All payments are final unless stated otherwise. To ask for a refund:\n1. Open the Help center\n2. Pick the course, then "Ask for a refund"\n3. We answer within 3 working days'),
      s(6, 'copyright', 'حقوق الملكية الفكرية', 'Intellectual property',
          'جميع المحتويات محمية بحقوق الملكية الفكرية. لا يجوز تسجيل المحاضرات أو إعادة نشرها دون إذن كتابي.',
          'All content is protected by intellectual property rights. Lectures may not be recorded or republished without written permission.'),
      s(7, 'security', 'حماية الحساب', 'Keeping your account safe',
          'جميع البيانات محمية ومشفرة أثناء النقل والتخزين.',
          'All data is protected and encrypted in transit and at rest.'),
    ],
  };
}

Map<String, dynamic> _about(String lang) {
  final ar = lang == 'ar';
  return {
    'info': {
      'id': 1,
      'name': ar ? 'مركز NextBrain' : 'NextBrain Center',
      'tagline': ar ? 'تعلّم بلا حدود' : 'Learning without limits',
      'mission': ar
          ? 'نسعى إلى تقديم تعليم عالي الجودة يصل إلى كل طالب في مكانه، بأدوات بسيطة ومعلمين يهتمون.'
          : 'We bring high-quality teaching to every student wherever they are, with simple tools and teachers who care.',
      'logo_url': null,
    },
    'stats': [
      {'id': 1, 'value': '1,000+', 'label': ar ? 'طالب مسجّل' : 'Students', 'order': 1},
      {'id': 2, 'value': '50+', 'label': ar ? 'دورة متاحة' : 'Courses', 'order': 2},
      {'id': 3, 'value': '66', 'label': ar ? 'مدرّس خبير' : 'Expert teachers', 'order': 3},
      {'id': 4, 'value': '60k', 'label': ar ? 'ساعة محتوى' : 'Hours of content', 'order': 4},
    ],
    'features': [
      {'id': 1, 'icon_name': 'play_circle', 'title': ar ? 'دروس مسجلة' : 'Recorded lessons', 'description': ar ? 'شاهد في أي وقت، حتى دون إنترنت.' : 'Watch any time, even offline.', 'order': 1},
      {'id': 2, 'icon_name': 'groups', 'title': ar ? 'حصص مباشرة' : 'Live classes', 'description': ar ? 'تفاعل مع معلمك وزملائك.' : 'Talk with your teacher and classmates.', 'order': 2},
      {'id': 3, 'icon_name': 'quiz', 'title': ar ? 'اختبارات ذكية' : 'Smart exams', 'description': ar ? 'تصحيح فوري وتقارير واضحة.' : 'Instant marking and clear reports.', 'order': 3},
    ],
    'team': [
      {'id': 1, 'name': ar ? 'أحمد حمدان' : 'Ahmed Hamdan', 'role': ar ? 'المسؤول المالي' : 'Finance lead', 'emoji': '', 'image_url': null, 'order': 1},
      {'id': 2, 'name': ar ? 'سارة علي' : 'Sara Ali', 'role': ar ? 'مديرة المحتوى' : 'Head of content', 'emoji': '', 'image_url': null, 'order': 2},
      {'id': 3, 'name': ar ? 'محمد نبيل' : 'Mohamed Nabil', 'role': ar ? 'الدعم الفني' : 'Support', 'emoji': '', 'image_url': null, 'order': 3},
    ],
    'contacts': [
      {'id': 1, 'type': 'website', 'value': 'https://nextbrain.site', 'label': ar ? 'الموقع الإلكتروني' : 'Website', 'icon_name': 'website', 'order': 1},
      {'id': 2, 'type': 'whatsapp', 'value': '+20 104 497 5073', 'label': ar ? 'واتساب' : 'WhatsApp', 'icon_name': 'whatsapp', 'order': 2},
      {'id': 3, 'type': 'email', 'value': 'support@nextbrain.site', 'label': null, 'icon_name': null, 'order': 3},
    ],
  };
}

// ── host and capture ────────────────────────────────────────────────────────────────────────────────────────────

const _phone = Size(390, 844);
const _desktop = Size(1440, 900);
final _shot = GlobalKey();
final _prodTheme = Platform.environment['VISUAL_THEME'] == 'production';

late StorageService _storage;
late LangProvider _lang;
late FakeApi _api;

Widget _host(Widget child, {required bool dark, required AboutTermsProvider terms}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  if (_prodTheme) {
    theme.debugUseColors(
        jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map<String, dynamic>);
  }
  final rtl = AppConfig.lang == 'ar';
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<LangProvider>.value(value: _lang),
      ChangeNotifierProvider<AboutTermsProvider>.value(value: terms),
    ],
    child: ThemeConfigScope(
      provider: theme,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.materialTheme(dark: false),
        darkTheme: theme.materialTheme(dark: true),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
        home: RepaintBoundary(key: _shot, child: child),
      ),
    ),
  );
}

Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

double _hiddenExtent(WidgetTester tester) {
  var extra = 0.0;
  for (final e in find.byType(Scrollable).evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis != Axis.vertical || !s.position.hasContentDimensions) continue;
    extra = math.max(extra, s.position.maxScrollExtent);
  }
  return extra;
}

Future<void> _renderAll(
  WidgetTester tester,
  String name,
  Widget Function() build, {
  bool grow = true,
  List<Size> sizes = const [_phone, _desktop],
  Future<void> Function(WidgetTester tester)? act,
}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in sizes) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(), dark: dark, terms: AboutTermsProvider()));
          await _frames(tester);
          if (grow) {
            for (var i = 0; i < 4; i++) {
              final extra = _hiddenExtent(tester);
              if (extra < 1) break;
              tester.view.physicalSize = Size(size.width, math.min(6000, tester.view.physicalSize.height + extra));
              await _frames(tester, 4);
            }
          }
          if (act != null) await act(tester);
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile(
                'goldens/reading_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}${_prodTheme ? '_prod' : ''}.png'),
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

/// The settings group the way every role's settings page shows it, with the inline language switch.
class _SettingsSample extends StatelessWidget {
  const _SettingsSample();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: AppSettingsGroup(
                title: 'settings'.tr,
                icon: Icons.settings_rounded,
                children: [
                  AppSettingsTile(
                    icon: Icons.notifications_active_rounded,
                    color: c.success,
                    label: 'notifications'.tr,
                    trailing: AppSwitch(value: true, onChanged: (_) {}),
                  ),
                  const AppLanguageTile(),
                  const DisplaySettingsTile(),
                  AppSettingsTile(
                    icon: Icons.dark_mode_rounded,
                    color: c.textDark,
                    label: 'dark_mode'.tr,
                    trailing: AppSwitch(value: c.isDark, onChanged: (_) {}),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    _storage = await StorageService.getInstance();
    _lang = LangProvider(storage: _storage);
    AppIdentity.instance
      ..installedVersion = '2.4.0'
      ..installedBuild = '41';
    String lang(RequestOptions o) => o.uri.queryParameters['lang'] ?? 'ar';
    _api = FakeApi({
      'GET /api/v1/app-content/terms': (o) => _terms(lang(o)),
      'GET /api/v1/app-content/about': (o) => _about(lang(o)),
    }, latency: const Duration(milliseconds: 10), fallback: (_) => const <String, dynamic>{})
      ..install();
  });
  tearDownAll(() => _api.uninstall());
  setUp(() => AppConfig.disableList = []);

  testWidgets('privacy', (tester) async {
    await _renderAll(tester, 'privacy', () => const TermsScreen(privacy: true, canAsk: true));
  });

  testWidgets('terms', (tester) async {
    await _renderAll(tester, 'terms', () => const TermsScreen(canAsk: true));
  });

  testWidgets('terms scrolled', (tester) async {
    await _renderAll(tester, 'terms_scrolled', () => const TermsScreen(canAsk: true), grow: false, sizes: const [_phone],
        act: (tester) async {
      await tester.dragFrom(const Offset(195, 700), const Offset(0, -900));
      await _frames(tester, 8);
    });
  });

  testWidgets('about', (tester) async {
    await _renderAll(tester, 'about', () => const AboutScreen(canAsk: true));
  });

  testWidgets('skeleton', (tester) async {
    await _renderAll(
      tester,
      'skeleton',
      () => const Scaffold(body: SafeArea(child: ReadingSkeleton())),
      grow: false,
      sizes: const [_phone],
    );
  });

  testWidgets('settings language', (tester) async {
    await _renderAll(tester, 'settings_language', () => const _SettingsSample(), grow: false);
  });
}
