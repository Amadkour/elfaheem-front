// First-run onboarding: three calm pages (learn with the best teachers / study anywhere safely / try it), a page
// indicator, Skip and Next, a language switch on the first page. The last step leads to the guest search.
//
// Redesign (Stu1Auth?screen=onboard, S-A): the whole page is the home area's hero surface (the radial gradient and
// its drifting shapes); each page draws a glass disc with its mark inside two dashed orbits and three glass chips
// around it, then the gold kicker, the headline and one line in the on-hero inks; the open page's dot is gold and
// Next is the area's button (jelly press). Skip is a glass pill.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../design/app_area.dart';
import '../../design/app_hero.dart' show AppHeroSurface;
import '../../design/app_language_switch.dart';
import '../../design/app_tokens.dart';
import '../auth/auth_shell.dart' show AuthLangButton;
import '../auth/auth_widgets.dart' show AuthButton;
import 'onboarding_store.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.onLanguage, this.onFinish});

  /// Switches the app language (default: LangProvider through [switchAppLanguage]).
  final ValueChanged<String>? onLanguage;

  /// Called on Skip / the last step (default: remember it and open `/guest-search`).
  final VoidCallback? onFinish;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;

  static const _count = 3;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _finish() {
    if (widget.onFinish != null) return widget.onFinish!();
    OnboardingStore.markSeen();
    Navigator.of(context).pushReplacementNamed('/guest-search');
  }

  void _next() {
    if (_index >= _count - 1) return _finish();
    _pages.nextPage(duration: AppMotion.of(context).base, curve: AppMotion.curve);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final last = _index == _count - 1;
    final items = <_Slide>[
      _Slide(icon: null, kicker: 'sa_ob_kicker1'.tr, title: 'ob_p1_title'.tr, body: 'ob_p1_body'.tr),
      _Slide(icon: Icons.verified_user_rounded, kicker: 'sa_ob_kicker2'.tr, title: 'ob_p2_title'.tr, body: 'ob_p2_body'.tr),
      _Slide(icon: Icons.explore_rounded, kicker: 'sa_ob_kicker3'.tr, title: 'ob_p3_title'.tr, body: 'ob_p3_body'.tr),
    ];
    return AppAreaScope(
      area: AppArea.home,
      child: Scaffold(
        backgroundColor: c.kit.deep,
        body: AppHeroSurface(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: AppWidth.form.max),
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, 0),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Flexible(
                        child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Visibility(
                        visible: _index == 0,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: AuthLangButton(
                          arabic: AppConfig.lang == 'ar',
                          onHero: true,
                          onTap: () => (widget.onLanguage ?? (v) => switchAppLanguage(context, v))(AppConfig.lang == 'ar' ? 'en' : 'ar'),
                        ),
                      ),
                        ),
                      ),
                      const SizedBox(width: AppSpace.xs),
                      if (!last)
                        TextButton(
                          onPressed: _finish,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(AppTouch.min, AppTouch.min),
                            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                            foregroundColor: c.onHero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              side: BorderSide(color: c.heroGlassBorder, width: AppBorder.hairline),
                            ),
                          ),
                          child: Text('ob_skip'.tr, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.onHero)),
                        ),
                    ]),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pages,
                      itemCount: _count,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (_, i) => _SlideView(slide: items[i]),
                    ),
                  ),
                  Semantics(
                    label: 'ob_page_of'.tr.replaceAll('{n}', '${_index + 1}').replaceAll('{total}', '$_count'),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      for (var i = 0; i < _count; i++)
                        AnimatedContainer(
                          duration: AppMotion.of(context).slow,
                          curve: AppMotion.curve,
                          margin: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
                          height: AppSpace.xs,
                          width: i == _index ? AppSpace.xl : AppSpace.xs,
                          decoration: BoxDecoration(
                            color: i == _index ? c.kit.accent(AppAccent.sun).color : c.heroGlassBorder,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                        ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpace.md),
                    child: AuthButton(label: last ? 'ob_start'.tr : 'ob_next'.tr, onPressed: _next),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Slide {
  const _Slide({required this.icon, required this.kicker, required this.title, required this.body});
  final IconData? icon; // null = the app logo
  final String kicker;
  final String title;
  final String body;
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});
  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, box) {
        // the art keeps a calm square on a phone and never towers on a short window
        final art = (box.maxHeight * 0.46).clamp(AppSpace.xxxl * 2, AppSpace.xxxl * 4.5);
        final disc = (art * 0.42).clamp(AppSpace.xxxl, AppSpace.xxxl * 2);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ExcludeSemantics(
                  child: SizedBox(
                    height: art,
                    child: CustomPaint(
                      painter: _OrbitPainter(color: c.onHero.withValues(alpha: 0.28), disc: disc),
                      child: Stack(alignment: Alignment.center, children: [
                        Container(
                          width: disc,
                          height: disc,
                          decoration: BoxDecoration(
                            color: c.heroGlass,
                            borderRadius: BorderRadius.circular(AppRadius.cardWide + AppSpace.xs),
                            border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
                          ),
                          alignment: Alignment.center,
                          child: slide.icon == null
                              ? Padding(
                                  padding: EdgeInsets.all(disc * 0.22),
                                  child: Image.asset('assets/images/logo_mark.png',
                                      errorBuilder: (_, _, _) => Icon(Icons.videocam_rounded, size: AppIconSize.hero, color: c.onHero)),
                                )
                              : Icon(slide.icon, size: AppIconSize.hero, color: c.onHero),
                        ),
                        // three glass chips on the orbit (decorative)
                        Align(
                          alignment: const AlignmentDirectional(-0.75, -0.62),
                          child: _OrbitChip(icon: Icons.videocam_rounded, label: 'sa_ob_chip_live'.tr, tone: c.kit.live.color, tilt: .05),
                        ),
                        Align(
                          alignment: const AlignmentDirectional(0.8, 0.28),
                          child: _OrbitChip(icon: Icons.play_circle_rounded, label: 'sa_ob_chip_recorded'.tr, tone: c.kit.accent(AppAccent.sun).color, tilt: -.06),
                        ),
                        Align(
                          alignment: const AlignmentDirectional(-0.4, 0.9),
                          child: _OrbitChip(icon: Icons.menu_book_rounded, label: 'sa_ob_chip_book'.tr, tone: c.kit.subject('math').tone.color, tilt: .03),
                        ),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.xl),
                Text(slide.kicker,
                    textAlign: TextAlign.center, style: AppType.kicker(context).copyWith(color: c.kit.warmOnDark)),
                const SizedBox(height: AppSpace.xxs),
                Semantics(
                  header: true,
                  child: Text(slide.title, textAlign: TextAlign.center, style: AppType.headline(context).copyWith(color: c.onHero)),
                ),
                const SizedBox(height: AppSpace.sm),
                Text(slide.body,
                    textAlign: TextAlign.center, style: AppType.body(context).copyWith(height: 1.6, color: c.onHeroMuted)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A white chip on the orbit: a coloured glyph disc and a short word, a little tilted.
class _OrbitChip extends StatelessWidget {
  const _OrbitChip({required this.icon, required this.label, required this.tone, this.tilt = 0});

  final IconData icon;
  final String label;
  final Color tone;
  final double tilt;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppDashSize.courseTile * .7),
      child: Transform.rotate(
      angle: tilt,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xxs, AppSpace.xxs, AppSpace.sm, AppSpace.xxs),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: AppShadow.card(context),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: AppIconSize.xl,
            height: AppIconSize.xl,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
            child: Icon(icon, size: AppIconSize.sm, color: c.onHero),
          ),
          const SizedBox(width: AppSpace.xs),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
          ),
        ]),
      ),
      ),
    );
  }
}

/// Two dashed orbits around the disc: the page's one drawn detail, in the faint on-hero ink.
class _OrbitPainter extends CustomPainter {
  const _OrbitPainter({required this.color, required this.disc});

  final Color color;
  final double disc;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppBorder.hairline
      ..color = color;
    final centre = size.center(Offset.zero);
    for (final r in [disc * 0.5 + AppSpace.xl, disc * 0.5 + AppSpace.xxl + AppSpace.lg]) {
      const dash = AppSpace.sm;
      final n = (2 * math.pi * r / dash).floor();
      for (var k = 0; k < n; k += 2) {
        final a = 2 * math.pi * k / n, b = 2 * math.pi * (k + 1) / n;
        canvas.drawArc(Rect.fromCircle(center: centre, radius: r), a, b - a, false, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.color != color || old.disc != disc;
}
