// VISUAL review renders of the sign-in module (D-072) — not a CI suite (CI lists its test folders and test/visual is
// not one of them).
//
// Login, register (the whole form, then its top with the @username field "available" and "taken + suggestions"),
// forgot password, the code screen (a reset asked by @username, so the neutral destination line shows) and the
// two-step code screen, drawn with the app's real fonts and theme at 390x844 (phone) and 1440x900 (desktop), Arabic
// and English, light and dark, into test/visual/goldens/auth_*.png. A page taller than the window is drawn whole.
//
//   flutter test test/visual/auth_screens_golden_test.dart --update-goldens
//   flutter test test/visual/auth_screens_golden_test.dart --update-goldens --plain-name login
//
// The screens are the real ones over real providers; the server is not reachable from a test, so the policy
// keeps its defaults (e-mail sign-in, e-mail verification) — the same as a first launch before the policy loads.
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
import 'package:flutter_education_app/features/auth/auth_shell.dart';
import 'package:flutter_education_app/features/auth/auth_widgets.dart';
import 'package:flutter_education_app/features/auth/biometric.dart';
import 'package:flutter_education_app/features/auth/biometric_widgets.dart';
import 'package:flutter_education_app/features/auth/forget_screen.dart';
import 'package:flutter_education_app/features/auth/login_screen.dart';
import 'package:flutter_education_app/features/auth/mfa.dart';
import 'package:flutter_education_app/features/auth/mfa_entry.dart';
import 'package:flutter_education_app/features/auth/mfa_verify_screen.dart';
import 'package:flutter_education_app/features/auth/register_screen.dart';
import 'package:flutter_education_app/features/auth/username.dart';
import 'package:flutter_education_app/features/auth/username_field.dart';
import 'package:flutter_education_app/features/auth/verified_screen.dart';
import 'package:flutter_education_app/features/shared/category/categories_provider.dart';
import 'package:flutter_education_app/features/shared/profile/about/about_terms_provider.dart';
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Fonts: the families the theme asks for, from the same files the app bundles
// ─────────────────────────────────────────────────────────────────────────────

String _sdkFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return '$root/bin/cache/artifacts/material_fonts';
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll('\\', '/');
  final i = exe.indexOf('/bin/cache/');
  return '${exe.substring(0, i)}/bin/cache/artifacts/material_fonts';
}

List<(String, List<String>)> _pubspecFonts(String yaml) {
  final out = <(String, List<String>)>[];
  final family = RegExp(r'^\s*- family:\s*(\S+)\s*$');
  final asset = RegExp(r'^\s*- asset:\s*(\S+)\s*$');
  for (final line in const LineSplitter().convert(yaml)) {
    final f = family.firstMatch(line);
    if (f != null) {
      out.add((f.group(1)!, <String>[]));
      continue;
    }
    final a = asset.firstMatch(line);
    if (a != null && out.isNotEmpty) out.last.$2.add(a.group(1)!);
  }
  return out;
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      final bytes = File(p).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  for (final (family, assets) in _pubspecFonts(File('pubspec.yaml').readAsStringSync())) {
    await load(family, assets);
  }
  final sdk = _sdkFonts();
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Host and capture
// ─────────────────────────────────────────────────────────────────────────────

const _phone = Size(390, 844);
const _desktop = Size(1440, 900);
const _maxHeight = 6000.0;
final _shot = GlobalKey();

late StorageService _storage;

// one set for the whole file: their (failing) network calls may finish after a render is torn down
late LangProvider _lang;
late ProfileProvider _profile;
late MyAuthProvider _auth;
late AboutTermsProvider _terms;
late CategoriesProvider _categories;

Widget _host(Widget child, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  _profile.darkMode = dark;
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<LangProvider>.value(value: _lang),
      ChangeNotifierProvider<ProfileProvider>.value(value: _profile),
      ChangeNotifierProvider<MyAuthProvider>.value(value: _auth),
      ChangeNotifierProvider<AboutTermsProvider>.value(value: _terms),
      ChangeNotifierProvider<CategoriesProvider>.value(value: _categories),
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

Future<void> _frames(WidgetTester tester, [int n = 16]) async {
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

/// Renders [build] at both sizes × ar / en × light / dark into `goldens/auth_<name>_<w>_<lang>_<theme>.png`.
Future<void> _renderAll(WidgetTester tester, String name, Widget Function() build) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in const [_phone, _desktop]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(), dark: dark));
          // let the logo asset decode (image codecs run outside the fake clock)
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
          await _frames(tester);
          for (var i = 0; i < 4; i++) {
            final extra = _hiddenExtent(tester);
            if (extra < 1) break;
            final h = math.min(_maxHeight, tester.view.physicalSize.height + extra);
            if (h <= tester.view.physicalSize.height) break;
            tester.view.physicalSize = Size(size.width, h);
            await _frames(tester, 6);
          }
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/auth_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
          );
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  The register form's top with a checked @username
// ─────────────────────────────────────────────────────────────────────────────

class _UsernameSample extends StatefulWidget {
  const _UsernameSample({required this.taken});

  final bool taken;

  @override
  State<_UsernameSample> createState() => _UsernameSampleState();
}

class _UsernameSampleState extends State<_UsernameSample> {
  final _name = TextEditingController(text: 'Ahmed Hamdy');
  final _mail = TextEditingController(text: 'ahmed.hamdy@example.com');
  late final _user = TextEditingController(text: widget.taken ? 'ahmed' : 'ahmed.hamdy');
  final _pw = TextEditingController(text: 'Nextbrain2026');

  @override
  void dispose() {
    _name.dispose();
    _mail.dispose();
    _user.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<UsernameCheck> _check(String u) async => widget.taken
      ? UsernameCheck(username: u, available: false, suggestions: const ['ahmed_23', 'ahmed.hamdy', 'ahmed.h'])
      : UsernameCheck(username: u, available: true);

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'auth_register_title'.tr,
      subtitle: 'auth_register_sub'.tr,
      builder: (context, wide) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ProgressBar(currentStep: 0, totalSteps: 3),
          const SizedBox(height: 24),
          IconTextField(controller: _name, label: 'full_name'.tr, icon: Icons.person_outline_rounded),
          const SizedBox(height: 16),
          AuthEmailField(controller: _mail, label: 'email'.tr),
          const SizedBox(height: 16),
          UsernameField(controller: _user, checker: _check, debounce: Duration.zero),
          const SizedBox(height: 16),
          IconPasswordField(controller: _pw, label: 'password'.tr),
          const SizedBox(height: 12),
          AuthPasswordStrength(
            strength: 4,
            color: context.colors.success,
            label: 'pw_strength_very_strong'.tr,
            title: 'pw_strength_title'.tr,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    _storage = await StorageService.getInstance();
    _lang = LangProvider(storage: _storage);
    _profile = ProfileProvider(storage: _storage);
    _auth = MyAuthProvider(storage: _storage);
    _terms = AboutTermsProvider();
    _categories = CategoriesProvider();
  });
  setUp(() => AppConfig.disableList = []);

  testWidgets('login', (tester) async {
    await _renderAll(tester, 'login', () => const LoginScreen());
  });

  testWidgets('register', (tester) async {
    await _renderAll(tester, 'register', () => const RegisterScreen());
  });

  testWidgets('register username available', (tester) async {
    await _renderAll(tester, 'register_username_available', () => const _UsernameSample(taken: false));
  });

  testWidgets('register username taken', (tester) async {
    await _renderAll(tester, 'register_username_taken', () => const _UsernameSample(taken: true));
  });

  testWidgets('forgot password', (tester) async {
    await _renderAll(tester, 'forgot', () => const ForgetScreen());
  });

  testWidgets('otp', (tester) async {
    await _renderAll(
      tester,
      'otp',
      () => const OtpVerificationScreen(email: 'ahmed', flow: OtpFlowEnum.forget, role: 'student'),
    );
  });

  testWidgets('mfa', (tester) async {
    await _renderAll(tester, 'mfa', () => const MfaVerifyScreen());
  });

  // ── Fingerprint / Face ID sign-in (D-082) ──────────────────────────────────
  group('biometric', () {
    const rec = BiometricRecord(
      credentialId: 'c-1',
      seed: 's',
      userId: 7,
      name: 'Ahmed Hamdy',
      identifier: 'ahmed.hamdy@example.com',
    );
    tearDown(BiometricAuth.instance.debugReset);

    testWidgets('login remembered', (tester) async {
      BiometricAuth.instance.debugSet(supported: true, record: rec);
      await _renderAll(tester, 'login_biometric', () => const LoginScreen());
    });

    testWidgets('login remembered face', (tester) async {
      BiometricAuth.instance.debugSet(supported: true, kind: BiometricKind.face, record: rec);
      await _renderAll(tester, 'login_biometric_face', () => const LoginScreen());
    });

    testWidgets('offer sheet', (tester) async {
      await _renderAll(tester, 'biometric_offer', () => const _SheetPreview(kind: BiometricKind.fingerprint));
    });

    testWidgets('security group', (tester) async {
      await _renderAll(tester, 'biometric_security', () => const _SecurityPreview());
    });
  });
}

/// The offer as the app shows it: over the dimmed login screen, in the app sheet's rounded surface.
class _SheetPreview extends StatelessWidget {
  const _SheetPreview({required this.kind});

  final BiometricKind kind;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Stack(
      children: [
        const LoginScreen(),
        const Positioned.fill(child: ColoredBox(color: Color(0x8A000000))),
        Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Material(
              color: c.cardBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: c.divider, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(height: 8),
                  BiometricOfferSheetBody(kind: kind, onEnable: () {}, onLater: () {}),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The profile's Security group with the switch on (and the MFA row), and a phone with the switch off.
class _SecurityPreview extends StatelessWidget {
  const _SecurityPreview();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  MfaSecurityGroup(
                    status: const MfaStatus(allowed: true, enabled: true),
                    onTap: () {},
                    biometric: const BiometricRowState(kind: BiometricKind.fingerprint, on: true),
                    onBiometricChanged: (_) {},
                  ),
                  const SizedBox(height: 24),
                  MfaSecurityGroup(
                    biometric: const BiometricRowState(kind: BiometricKind.face, on: false),
                    onBiometricChanged: (_) {},
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
