// VISUAL review renders of the student study profile (D-790 – D-796) and the super admin's AI controls (D-780): the
// sign-up step, Profile > Study details, the home card, the admin settings page and the Features page's AI section,
// at 390x844 and 1440x900, Arabic and English, light and dark, into test/visual/goldens/study_*.png. Not a CI suite;
// compared by eye.
//
//   flutter test test/visual/study_profile_golden_test.dart --update-goldens
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
import 'package:flutter_education_app/features/admin/admin_ai_controls.dart';
import 'package:flutter_education_app/features/admin/admin_study_profile_settings_page.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/profile/profile_provider.dart';
import 'package:flutter_education_app/features/profile/study_profile/study_profile_model.dart';
import 'package:flutter_education_app/features/profile/study_profile/study_profile_pages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/fake_api.dart';
import '../ui/admin_ds/cfg_support.dart';
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

final _prodColors =
    jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map<String, dynamic>;

Widget _host(Widget child, Widget Function(Widget) providers, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient())..debugUseColors(_prodColors);
  theme.isDark = dark;
  final rtl = AppConfig.lang == 'ar';
  return providers(ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: dark),
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: RepaintBoundary(key: _shot, child: child),
    ),
  ));
}

Future<void> _frames(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

List<Map<String, dynamic>> _aiItems() => [
      for (final (key, ar, en, on, partial, enforced) in [
        ('exam.auto_create', 'إنشاء الأسئلة بالذكاء الاصطناعي', 'AI question generation', true, false, 'server'),
        ('exam.auto_grade', 'تصحيح الإجابات المكتوبة بالذكاء الاصطناعي', 'AI grading of written answers', false, false, 'server'),
        ('exam.auto_correct', 'التصحيح التلقائي لأوراق التظليل', 'Automatic bubble-sheet correction', false, true, 'server'),
        ('rag.app_assistant', 'مساعد التطبيق', 'App assistant', true, false, 'server'),
        ('image.background', 'إزالة خلفية الصور', 'Image background removal', true, false, 'app'),
      ])
        {
          'key': key,
          'title_ar': ar,
          'title_en': en,
          'off_ar': 'يتوقف هذا على المنصة كلها؛ لا يُحذف شيء.',
          'off_en': 'This stops on the whole platform; nothing is deleted.',
          'on': on,
          'partial': partial,
          'enforced': enforced,
        },
    ];

void main() {
  setUpAll(() async {
    await _loadFonts();
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });

  testWidgets('study profile and AI controls', (tester) async {
    final prevLang = AppConfig.lang;
    debugDisableShadows = false;
    final busy = ValueNotifier<bool>(false);
    final pages = <String, Widget Function()>{
      'step': () => StudyProfileStepPage(
            initial: const StudyProfile(stage: 'secondary', grade: 2),
            settings: const StudySettings(),
            busy: busy,
            onSubmit: (_) async {},
          ),
      'page': () => const StudyProfilePage(),
      'card': () => Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topCenter,
                child: StudyPromptCard(onOpen: () {}, onDismiss: () {}),
              ),
            ),
          ),
      'settings': () => const AdminStudyProfileSettingsPage(),
      'ai': () => Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: AiControlsCard(
                items: [for (final m in _aiItems()) AiControl.from(m)],
                onToggle: (_, _) {},
              ),
            ),
          ),
    };
    try {
      final api = FakeApi({
        ...cfgRoutes(),
        'GET /api/v1/me/study-profile': (_) => {
              'profile': {
                'stage': 'secondary',
                'grade': 3,
                'track': 'science',
                'school_name': 'مدرسة السعيدية الثانوية',
                'governorate': 'giza',
                'parent_phone': '+201012345678',
                'dob': '2008-04-01',
              },
              'settings': {'signup_step': true, 'home_prompt': true, 'required': ['school_name']},
              'missing': [],
            },
        'GET /api/v1/admin/study-profile/settings': (_) =>
            {'signup_step': true, 'home_prompt': false, 'required': ['school_name', 'governorate']},
      }, latency: const Duration(milliseconds: 20));
      final auth = await cfgSetUp(api);
      final profile = ProfileProvider(storage: await StorageService.getInstance());
      for (final entry in pages.entries) {
        for (final (size, lang, dark) in const [
          (Size(390, 844), 'ar', false),
          (Size(390, 844), 'en', true),
          (Size(1440, 900), 'ar', true),
          (Size(1440, 900), 'en', false),
        ]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(
              entry.value(),
              (c) => cfgProviders(auth, ChangeNotifierProvider<ProfileProvider>.value(value: profile, child: c)),
              dark: dark));
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
          expect(e, isNull, reason: '${entry.key} ${size.width.toInt()} $lang: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile(
                'goldens/study_${entry.key}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
          );
        }
      }
    } finally {
      AppConfig.lang = prevLang;
      busy.dispose();
      await tester.pumpWidget(const SizedBox());
      debugDisableShadows = true;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
