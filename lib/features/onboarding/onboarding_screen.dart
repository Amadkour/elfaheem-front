// First-run onboarding: three calm pages (learn with the best teachers / study anywhere safely / try free), a page
// indicator, Skip and Next, a language switch on the first page. The last step leads to the guest search.
library;

import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../design/app_kit.dart' show appText;
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
      _Slide(icon: null, title: 'ob_p1_title'.tr, body: 'ob_p1_body'.tr),
      _Slide(icon: Icons.verified_user_outlined, title: 'ob_p2_title'.tr, body: 'ob_p2_body'.tr),
      _Slide(icon: Icons.explore_outlined, title: 'ob_p3_title'.tr, body: 'ob_p3_body'.tr),
    ];
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
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
                      child: Text('ob_skip'.tr, style: appText(14, w: FontWeight.w500, c: c.textMedium)),
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
                      duration: AppMotion.of(context).base,
                      margin: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
                      height: 8,
                      width: i == _index ? 24 : 8,
                      decoration: BoxDecoration(
                        color: i == _index ? c.primary : c.divider,
                        borderRadius: BorderRadius.circular(8),
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
  const _Slide({required this.icon, required this.title, required this.body});
  final IconData? icon; // null = the app logo
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
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(color: c.primaryTint, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: slide.icon == null
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpace.lg),
                      child: Image.asset('assets/images/logo_mark.png',
                          errorBuilder: (_, _, _) => Icon(Icons.school_outlined, size: 56, color: c.primary)),
                    )
                  : Icon(slide.icon, size: 56, color: c.primary),
            ),
            const SizedBox(height: AppSpace.xl),
            Text(slide.title, textAlign: TextAlign.center, style: AppType.pageTitle(context).copyWith(fontSize: 24)),
            const SizedBox(height: AppSpace.sm),
            Text(slide.body,
                textAlign: TextAlign.center,
                style: AppType.row(context).copyWith(color: c.textMedium, height: 1.6, fontWeight: FontWeight.w400)),
          ]),
        ),
      ),
    );
  }
}
