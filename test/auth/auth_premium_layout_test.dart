// The auth design language (D-072): the page layout (hero + card on a phone, brand panel + card on a wide window)
// and every shared piece — fields, the gradient button in its three states, code boxes, password meter and
// checklist, terms row, switches, the embedded two-step form — at 320x640 and 1400x900, Arabic and English,
// textScaler 1.3 (layout harness). Then the behaviour the pieces promise: the button only fires when it can,
// the focus ring survives the border animation, the icon buttons carry screen-reader labels.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/auth/auth_shell.dart';
import 'package:flutter_education_app/features/auth/auth_widgets.dart';
import 'package:flutter_education_app/features/auth/mfa_verify_screen.dart';
import 'package:flutter_education_app/features/auth/register_screen.dart' show AuthTermsRow;
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

const _longAr = 'نص عربي طويل جداً لاختبار الالتفاف على الشاشات الصغيرة مع تكبير الخط إلى مئة وثلاثين بالمئة';
const _longEn = 'A very long English line that has to wrap on a 320 px phone with the text scaled to 130 percent';

Widget _actions(bool onHero) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AuthLangButton(arabic: AppConfig.lang == 'ar', onHero: onHero, onTap: () {}),
        AuthThemeButton(dark: false, onHero: onHero, onTap: () {}),
      ],
    );

class _Form extends StatefulWidget {
  const _Form();

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _id = TextEditingController(text: 'someone.with.a.long.address@example-domain.com');
  final _pw = TextEditingController(text: 'Secret123');
  final _mail = TextEditingController(text: 'not-an-email');

  @override
  void dispose() {
    _id.dispose();
    _pw.dispose();
    _mail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const ProgressBar(currentStep: 1, totalSteps: 3),
          const SizedBox(height: 16),
          IconTextField(controller: _id, label: _longAr, icon: Icons.person_outline),
          const SizedBox(height: 16),
          IconPasswordField(controller: _pw, label: _longEn),
          const SizedBox(height: 16),
          AuthEmailField(controller: _mail, label: _longEn),
          const SizedBox(height: 12),
          const AuthPasswordStrength(strength: 3, label: _longAr, color: Colors.green, title: _longEn),
          const AuthRequirement(met: true, label: _longAr),
          const AuthRequirement(met: false, label: _longEn),
          const SizedBox(height: 12),
          const AuthInfoBanner(text: _longAr),
          const SizedBox(height: 12),
          AuthTermsRow(accepted: false, onReadTap: () {}, onCheckChanged: (_) {}),
          const SizedBox(height: 8),
          AuthTermsRow(accepted: true, onReadTap: () {}, onCheckChanged: (_) {}),
          const SizedBox(height: 16),
          AuthButton(label: _longEn, icon: Icons.arrow_forward_rounded, onPressed: () {}),
          const SizedBox(height: 8),
          const AuthButton(label: _longAr, onPressed: null, enabled: false),
          const SizedBox(height: 8),
          AuthButton(label: _longAr, loading: true, onPressed: () {}),
          const SizedBox(height: 16),
          const AuthOrDivider(label: _longAr),
          LinkRow(message: _longAr, linkText: _longEn, onTap: () {}),
          Wrap(spacing: 8, runSpacing: 8, children: [
            AuthTextAction(icon: Icons.domain_add_rounded, label: _longEn, onTap: () {}),
            AuthTextAction(icon: Icons.explore_outlined, label: _longAr, onTap: () {}),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            for (final s in const [(false, false, false), (true, false, false), (false, true, false), (false, true, true)])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: AuthOtpBox(focused: s.$1, filled: s.$2, error: s.$3, child: const Center(child: Text('7'))),
                ),
              ),
          ]),
        ],
      );
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('AuthLayout', () {
    testWidgets('hero + card / brand panel + card, with a long form', (t) async {
      await expectNoLayoutErrors(
        t,
        () => AuthLayout(
          title: _longAr,
          subtitle: _longEn,
          showBack: true,
          actions: _actions,
          body: (context, wide) => const _Form(),
        ),
      );
    });

    testWidgets('no header, no back, no actions', (t) async {
      await expectNoLayoutErrors(
        t,
        () => AuthLayout(title: 'x', header: false, showBack: false, body: (context, wide) => const Text(_longEn)),
      );
    });

    testWidgets('the embedded two-step form inside the page', (t) async {
      final ctl = TextEditingController();
      addTearDown(ctl.dispose);
      for (final recovery in [false, true]) {
        await expectNoLayoutErrors(
          t,
          () => AuthLayout(
            title: _longEn,
            subtitle: _longAr,
            actions: _actions,
            body: (context, wide) => MfaCodeForm(
              embedded: true,
              controller: ctl,
              useRecovery: recovery,
              error: _longAr,
              attemptsLeft: 2,
              onSubmit: () {},
              onToggleRecovery: () {},
            ),
          ),
        );
      }
    });
  });

  group('pieces', () {
    testWidgets('the brand panel alone (password page keeps using it in a Row)', (t) async {
      await expectNoLayoutErrors(t, () => const Row(children: [AuthSidebar(), Expanded(child: SizedBox())]));
    });

    testWidgets('header, top bar, screen icon', (t) async {
      await expectNoLayoutErrors(
        t,
        () => const SingleChildScrollView(
          child: Column(children: [
            AuthHeader(title: _longAr, subtitle: _longEn),
            AuthTopBar(),
            ScreenIcon(icon: Icons.lock_rounded),
          ]),
        ),
      );
    });
  });

  group('behaviour', () {
    testWidgets('the button fires only when enabled and not loading', (t) async {
      var taps = 0;
      Future<void> pump(AuthButton b) async {
        await t.pumpWidget(layoutHost(Center(child: SizedBox(width: 300, child: b)), scale: 1));
        await t.pump(const Duration(milliseconds: 300));
      }

      await pump(AuthButton(label: 'Go', onPressed: () => taps++));
      await t.tap(find.text('Go'));
      expect(taps, 1);
      await pump(AuthButton(label: 'Go', enabled: false, onPressed: () => taps++));
      await t.tap(find.text('Go'), warnIfMissed: false);
      expect(taps, 1, reason: 'disabled');
      await pump(AuthButton(label: 'Go', loading: true, onPressed: () => taps++));
      expect(find.text('Go'), findsNothing, reason: 'a spinner replaces the label');
      await t.tap(find.byType(AuthButton), warnIfMissed: false);
      expect(taps, 1, reason: 'busy');
      // it is a FilledButton underneath, so the keyboard support finds it as the form's button
      expect(find.byType(FilledButton), findsOneWidget);
    });

    test('the focus ring survives the border animation', () {
      const a = AuthFieldBorder(borderSide: BorderSide(width: 1));
      const b = AuthFieldBorder(borderSide: BorderSide(width: 2), ring: Colors.blue, ringWidth: 4);
      final mid = ShapeBorder.lerp(a, b, 0.5);
      expect(mid, isA<AuthFieldBorder>());
      expect((mid as AuthFieldBorder).ringWidth, 2);
      expect(b.copyWith(), b);
      expect(a == b, isFalse);
    });

    testWidgets('icon buttons carry screen-reader labels', (t) async {
      final handle = t.ensureSemantics();
      AppConfig.lang = 'en';
      await t.pumpWidget(layoutHost(
        AuthLayout(title: 'Welcome', showBack: true, actions: _actions, body: (context, wide) => const SizedBox()),
        scale: 1,
      ));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.bySemanticsLabel('Back'), findsOneWidget);
      expect(find.bySemanticsLabel('Switch to Arabic'), findsNothing);
      expect(find.bySemanticsLabel('التبديل إلى العربية'), findsOneWidget);
      expect(find.bySemanticsLabel('Dark mode'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('reduced motion: no entrance animation, the card is there on the first frame', (t) async {
      await t.pumpWidget(layoutHost(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true, size: Size(400, 800)),
          child: AuthLayout(title: 'Welcome', body: (context, wide) => const Text('form')),
        ),
        scale: 1,
      ));
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
      expect(find.text('form'), findsOneWidget);
    });
  });
}
