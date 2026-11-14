// Visual review renders of the Account area in the Warm Editorial theme (D-610 – D-629), compared by eye like the
// other test/visual files (NOT a CI suite):
//
//   flutter test test/visual/profile_pages_golden_test.dart --update-goldens [--plain-name student]
//
// → test/visual/goldens/account_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900.
//   profile_student / profile_teacher   the Account page of each role (the hero block, the settings groups)
//   public_teacher                      a teacher's public page (@name)
//   hero_figures                        the identity header with figures, Edit and Share (D-713)
//   subscription_plans / _active        the paywall: choosing a plan, and an active subscription
//   payouts                             the teacher's earnings & payouts
//   change_password / edit_account      the two account forms
//   device_requests                     the teacher's device-switch requests
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/teacher_document_provider.dart';
import 'package:flutter_education_app/features/profile/change_password_widget.dart';
import 'package:flutter_education_app/features/profile/course_instractor_profile.dart';
import 'package:flutter_education_app/features/home/student/models.dart' show TeacherProfileData;
import 'package:flutter_education_app/features/profile/profile_hero.dart';
import 'package:flutter_education_app/features/profile/profile_provider.dart';
import 'package:flutter_education_app/features/profile/profile_screen.dart';
import 'package:flutter_education_app/features/profile/update_account_widget.dart';
import 'package:flutter_education_app/features/profile/public_profile/public_profile.dart';
import 'package:flutter_education_app/features/profile/public_profile/public_profile_view.dart';
import 'package:flutter_education_app/features/payments/subscription/subscription_screen.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_home_provider.dart';
import 'package:flutter_education_app/features/profile/teacher/payout/teacher_payouts_screen.dart';
import 'package:flutter_education_app/features/profile/teacher/switch_device_requests/teacher_device_requests_provider.dart';
import 'package:flutter_education_app/features/profile/teacher/switch_device_requests/teacher_device_requests_screen.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/profile_link_test.dart' show courseJson, teacherJson;
import '../ui/public_profile_stats_test.dart' show owner, richTeacher, studentJson;
import 'package:flutter_education_app/features/profile/public_profile/public_profile_page.dart' show ProfileOwnerPanel;
import '../support/fake_api.dart';
import '../ui/instructor_courses_section_test.dart' show teacherCourses;
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
  final cfg = jsonDecode(File('.dart_tool/package_config.json').readAsStringSync()) as Map<String, dynamic>;
  for (final p in (cfg['packages'] as List).cast<Map<String, dynamic>>()) {
    if (p['name'] != 'cupertino_icons') continue;
    final root = Uri.parse('${p['rootUri']}');
    final dir = root.isAbsolute ? root.toFilePath() : File('.dart_tool/${p['rootUri']}').absolute.path;
    final font = File('$dir/assets/CupertinoIcons.ttf');
    if (font.existsSync()) await load('packages/cupertino_icons/CupertinoIcons', [font.path]);
  }
}

final _shot = GlobalKey();
late StorageService _storage;

Map<String, FakeHandler> _routes() => {
      'GET /api/v1/subscriptions/status': (_) => {
            'required': true,
            'has_access': false,
            'platform_required': true,
            'reason': 'platform',
            'plans': [
              {'code': 'm1', 'name_ar': 'شهري', 'name_en': 'Monthly', 'price': 150, 'currency': 'EGP', 'duration_days': 30},
              {'code': 'q1', 'name_ar': 'فصل دراسي', 'name_en': 'One term', 'price': 390, 'currency': 'EGP', 'duration_days': 120},
              {'code': 'y1', 'name_ar': 'سنوي', 'name_en': 'Yearly', 'price': 1100, 'currency': 'EGP', 'duration_days': 365},
            ],
          },
      'GET /api/v1/subscriptions/transfer-details': (_) => {
            'bank_transfer_enabled': true,
            'instapay_enabled': true,
            'bank_name': 'Banque Misr',
            'account_name': 'NextBrain Education',
            'iban': 'EG380019000500000000263180002',
          },
      'GET /api/v1/teacher/payout/status': (_) => {
            'allowed': true,
            'min_amount': 200,
            'methods': [
              {'id': 'instapay', 'label_ar': 'إنستاباي', 'label_en': 'InstaPay', 'automatic': false},
              {'id': 'bank_transfer', 'label_ar': 'تحويل بنكي', 'label_en': 'Bank transfer', 'automatic': false},
            ],
            'accounts': [
              {'id': 1, 'method': 'instapay', 'label': 'My InstaPay', 'details': {'instapay_id': 'ahmed@instapay'}, 'is_default': true},
              {'id': 2, 'method': 'bank_transfer', 'label': 'CIB', 'details': {'bank_name': 'CIB', 'iban': 'EG800002000156789012345180002'}},
            ],
            'summary': {'pending_balance': 4820.5, 'withdrawn_total': 12600, 'pending_withdrawal': 1500, 'total_net': 18920.5},
          },
      'GET /api/v1/teacher/withdrawals': (_) => {
            'items': [
              {'id': 31, 'amount': 1500, 'status': 'pending', 'method': 'instapay', 'requested_at': '2026-11-08T10:12:00', 'currency': 'EGP'},
              {'id': 28, 'amount': 3000, 'status': 'paid', 'method': 'bank_transfer', 'requested_at': '2026-10-20T08:00:00', 'currency': 'EGP'},
              {'id': 22, 'amount': 900, 'status': 'rejected', 'method': 'instapay', 'requested_at': '2026-09-02T15:40:00', 'currency': 'EGP', 'rejection_reason': 'Wrong InstaPay id'},
            ],
          },
      'GET /api/v1/courses': teacherCourses(5),
      'GET /api/v1/devices/teacher/switch-requests': (_) => {
            'items': [
              {'id': 5, 'student_name': 'Mariam Adel', 'student_email': 'mariam@example.test', 'old_device': 'Samsung A54', 'new_device': 'iPhone 15', 'reason': 'My old phone broke', 'created_at': '2026-11-10T09:00:00', 'course_name': 'Algebra 2'},
              {'id': 6, 'student_name': 'Omar Khaled', 'student_email': 'omar@example.test', 'old_device': 'Redmi Note 12', 'new_device': 'Galaxy S24', 'created_at': '2026-11-09T18:30:00', 'course_name': 'Physics'},
            ],
          },
    };

/// `VISUAL_THEME=production` paints with the production theme (test/visual/fixtures/theme_production.json); the files
/// then end in `_prod`.
final _prodTheme = Platform.environment['VISUAL_THEME'] == 'production';

Widget _host(Widget child, {required bool dark, String role = 'student'}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  if (_prodTheme) {
    theme.debugUseColors(
        jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map<String, dynamic>);
  }
  final rtl = AppConfig.lang == 'ar';
  final auth = MyAuthProvider(storage: _storage)..loadCachedUser();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<MyAuthProvider>.value(value: auth),
      ChangeNotifierProvider(create: (_) => ProfileProvider(storage: _storage)),
      ChangeNotifierProvider(create: (_) => TeacherHomeProvider()),
      ChangeNotifierProvider(create: (_) => TeacherDeviceRequestsProvider()),
      ChangeNotifierProvider(create: (_) => TeacherDocumentProvider()),
      ChangeNotifierProvider.value(value: theme),
      ChangeNotifierProvider(create: (_) => LangProvider(storage: _storage)),
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

double _hiddenExtent(WidgetTester tester) {
  var extra = 0.0;
  for (final e in find.byType(Scrollable).evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis != Axis.vertical || !s.position.hasContentDimensions) continue;
    extra = math.max(extra, s.position.maxScrollExtent);
  }
  return extra;
}

Future<void> _render(WidgetTester tester, String name, Widget Function() build,
    {String role = 'student', bool grow = true, Future<void> Function(WidgetTester t)? act}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  await _storage.saveUser({
    'id': 7,
    'name': role == 'teacher' ? 'Ahmed Hamdy' : 'Mariam Adel',
    'gmail': role == 'teacher' ? 'ahmed@nextbrain.site' : 'mariam.adel@example.test',
    'role': role,
    'username': role == 'teacher' ? 'ahmed' : 'mariam',
    'username_confirmed': true,
  });
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(), dark: dark, role: role));
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          if (act != null) await act(tester);
          for (var i = 0; grow && i < 4; i++) {
            final extra = _hiddenExtent(tester);
            if (extra < 1) break;
            tester.view.physicalSize = Size(size.width, math.min(4000, tester.view.physicalSize.height + extra));
            for (var j = 0; j < 4; j++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile(
                'goldens/account_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}${_prodTheme ? '_prod' : ''}.png'),
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

PublicProfileResult _teacher() {
  final j = teacherJson()
    ..['name'] = 'Ahmed Hamdy'
    ..['image_url'] = null
    ..['bio'] = 'I have taught secondary maths since 2014: algebra, calculus and exam practice, one clear step at a time.'
    ..['courses_count'] = 4
    ..['courses'] = [
      for (var i = 1; i <= 4; i++) {...courseJson(i, name: i.isEven ? 'Algebra 2' : 'Calculus basics', students: i * 640), 'image_url': null},
    ];
  return PublicProfileResult(PublicProfileStatus.found, profile: PublicProfile.fromJson(j));
}

TeacherProfileData _instructor() => TeacherProfileData.fromJson({
      'id': 42,
      'name': 'Dr. Omar Hassan',
      'is_verified': true,
      'is_active': true,
      'created_at': '2023-09-01T10:00:00',
      'teacher_profile': {
        'id': 3,
        'user_id': 42,
        'experience_years': 12,
        'specialization': {'id': 1, 'name_ar': 'الرياضيات', 'name_en': 'Mathematics'},
        'teaching_type': 'both',
        'payment_type': 'paid',
        'about': 'I teach secondary maths and physics, from first principles to exam practice. Every lesson ends with '
            'a short set of problems and a worked solution, and my students can ask questions in the live sessions '
            'every week. I have prepared students for the national exam since 2013.',
        'created_at': '2023-09-01T10:00:00',
      },
    });

void main() {
  late FakeApi api;
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() async {
    AppConfig.disableList = [];
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    _storage = await StorageService.getInstance();
    api = FakeApi(_routes());
    api.install();
    addTearDown(api.uninstall);
  });

  testWidgets('profile student', (t) => _render(t, 'profile_student', () => const ProfileScreen()));
  testWidgets('profile teacher', (t) => _render(t, 'profile_teacher', () => const ProfileScreen(), role: 'teacher'));
  // the identity header with the teacher's figures and both actions (D-713)
  testWidgets('hero figures', (t) => _render(t, 'hero_figures', () => BasePage(
        enableFooterWidget: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ProfileHero(
            name: 'Ahmed Hamdy',
            role: 'teacher',
            email: 'ahmed@nextbrain.site',
            username: 'ahmed',
            onEdit: () {},
            onShare: () {},
            stats: const [
              ProfileHeroStat(icon: Icons.menu_book_rounded, value: '12', label: 'Courses'),
              ProfileHeroStat(icon: Icons.groups_rounded, value: '1240', label: 'Students'),
              ProfileHeroStat(icon: Icons.star_rounded, value: '4.8', label: 'Rating'),
            ],
          ),
        ),
      ), grow: false));
  testWidgets('public teacher', (t) => _render(t, 'public_teacher',
      () => BasePage(enableFooterWidget: false, child: PublicProfileView(result: _teacher(), onOpenCourse: (_) {}))));
  // the ONE profile page (D-850 – D-855): a teacher's figures + growth + most joined with the guest's join card, a
  // student's opt-in summary, and the owner's panel over the same page
  testWidgets('public teacher stats', (t) => _render(t, 'public_teacher_stats', () => BasePage(
      enableFooterWidget: false,
      child: PublicProfileView(
        result: PublicProfileResult(PublicProfileStatus.found,
            profile: PublicProfile.fromJson(richTeacher()..['name'] = 'Ahmed Hamdy'..['image_url'] = null..['courses'] = [])),
        onOpenCourse: (_) {},
        onOpenCourseId: (_) {},
        joinCard: ProfileJoinCard(name: 'Ahmed Hamdy', teacher: true, onJoin: () {}, onSignIn: () {}),
      ))));
  testWidgets('public student', (t) => _render(t, 'public_student', () => BasePage(
      enableFooterWidget: false,
      child: PublicProfileView(
        result: PublicProfileResult(PublicProfileStatus.found,
            profile: PublicProfile.fromJson(studentJson()..['name'] = 'Mariam Adel')),
        onOpenCourse: (_) {},
        onOpenCourseId: (_) {},
      ))));
  testWidgets('my profile owner', (t) => _render(t, 'my_profile_owner', () => BasePage(
      enableFooterWidget: false,
      child: PublicProfileView(
        result: PublicProfileResult(PublicProfileStatus.found,
            profile: PublicProfile.fromJson(richTeacher()..['name'] = 'Ahmed Hamdy'..['image_url'] = null..['courses'] = [])),
        onOpenCourse: (_) {},
        ownerPanel: ProfileOwnerPanel(
            mine: owner(), onPublic: (_) {}, onField: (_, _) {}, onEdit: () {}, onShare: () {}, onAccount: () {}, onDocuments: () {}),
      )), role: 'teacher'));
  testWidgets('subscription plans', (t) => _render(t, 'subscription_plans', () => const SubscriptionScreen(), act: (t) async {
        final plan = find.text(AppConfig.lang == 'ar' ? 'فصل دراسي' : 'One term');
        if (plan.evaluate().isNotEmpty) {
          await t.tap(plan.first);
          for (var i = 0; i < 6; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
        }
      }));
  testWidgets('instructor', (t) => _render(t, 'instructor', () => InstructorProfileScreen(teacher: _instructor())));
  testWidgets('payouts', (t) => _render(t, 'payouts', () => const TeacherPayoutsScreen(), role: 'teacher'));
  testWidgets('change password', (t) => _render(t, 'change_password', () => const ChangePasswordScreen()));
  testWidgets('edit account', (t) => _render(t, 'edit_account', () => const EditAccountScreen(isTeacher: false)));
  testWidgets('device requests', (t) => _render(t, 'device_requests', () => const TeacherDeviceRequestsScreen(), role: 'teacher'));
}
