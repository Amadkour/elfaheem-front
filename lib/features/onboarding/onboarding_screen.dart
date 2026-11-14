// First-run onboarding: three calm pages (learn with the best teachers / study anywhere safely / try free), a page
// indicator, Skip and Next, a language switch on the first page. The last step leads to the guest search.
//
// Warm Editorial (D-610 – D-629): each page is ONE tinted block (peach · sky · peach) holding its mark on a paper
// disc inside two quiet hairline orbits, then the editorial headline and the body on the warm canvas, start-aligned
// like a magazine page. The emerald is only the Next / Start button and the open page's dot.
library;

import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../design/app_blocks.dart';
import '../../design/app_language_switch.dart';
import '../../design/app_tokens.dart';
import '../../utils/widget/primary_button.dart';
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
      _Slide(icon: null, tone: AppBlockTone.peach, title: 'ob_p1_title'.tr, body: 'ob_p1_body'.tr),
      _Slide(icon: Icons.verified_user_rounded, tone: AppBlockTone.sky, title: 'ob_p2_title'.tr, body: 'ob_p2_body'.tr),
      _Slide(icon: Icons.explore_rounded, tone: AppBlockTone.peach, title: 'ob_p3_title'.tr, body: 'ob_p3_body'.tr),
    ];
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: AppWidth.form.max),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, 0),
                child: Row(children: [
                  Visibility(
                    visible: _index == 0,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: AppLanguageSegmented(
                      current: AppConfig.lang,
                      onChanged: (l) => (widget.onLanguage ?? (v) => switchAppLanguage(context, v))(l),
                    ),
                  ),
                  const Spacer(),
                  if (!last)
                    TextButton(
                      onPressed: _finish,
                      style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
                      child: Text('ob_skip'.tr, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600)),
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
                      width: i == _index ? AppSpace.lg : AppSpace.xs,
                      decoration: BoxDecoration(
                        color: i == _index ? c.primary : c.divider,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: PrimaryButton(
                  isLoading: false,
                  label: last ? 'ob_start'.tr : 'ob_next'.tr,
                  onPressed: _next,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Slide {
  const _Slide({required this.icon, required this.tone, required this.title, required this.body});
  final IconData? icon; // null = the app logo
  final AppBlockTone tone;
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
        // the block keeps a calm landscape on a phone and never towers on a short window
        final art = (box.maxHeight * 0.42).clamp(AppSpace.xxxl * 2, AppSpace.xxxl * 4);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppBlock(
                  tone: slide.tone,
                  padding: EdgeInsets.zero,
                  child: SizedBox(
                    height: art,
                    child: Builder(builder: (context) {
                      final ink = AppBlock.colorsOf(context);
                      final disc = (art * 0.5).clamp(AppSpace.xxxl, AppSpace.xxxl * 2);
                      return CustomPaint(
                        painter: _OrbitPainter(color: ink.faint.withValues(alpha: 0.35), disc: disc),
                        child: Center(
                          child: Container(
                            width: disc,
                            height: disc,
                            decoration: BoxDecoration(
                              color: c.cardBg,
                              shape: BoxShape.circle,
                              border: Border.all(color: ink.border ?? c.divider, width: AppBorder.hairline),
                            ),
                            alignment: Alignment.center,
                            child: slide.icon == null
                                ? Padding(
                                    padding: EdgeInsets.all(disc * 0.2),
                                    child: Image.asset('assets/images/logo_mark.png',
                                        errorBuilder: (_, _, _) => Icon(Icons.school_rounded, size: AppIconSize.hero, color: ink.ink)),
                                  )
                                : Icon(slide.icon, size: AppIconSize.hero, color: ink.ink),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: AppSpace.xl),
                Semantics(
                  header: true,
                  child: Text(slide.title, style: AppType.display(context)),
                ),
                const SizedBox(height: AppSpace.sm),
                Text(slide.body, style: AppType.body(context).copyWith(height: 1.6)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Two quiet hairline orbits around the disc: the page's one drawn detail, in the block's faint ink.
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
    canvas.drawCircle(centre, disc * 0.5 + AppSpace.lg, paint);
    canvas.drawCircle(centre, disc * 0.5 + AppSpace.xxl + AppSpace.xs, paint..color = color.withValues(alpha: color.a * 0.6));
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.color != color || old.disc != disc;
}
