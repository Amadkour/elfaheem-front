// lib/design/app_language_switch.dart — the app language as an inline switch, not a page (D-088).
//
//   AppLanguageSegmented(current:, onChanged:)
//       plain values: a pill track with the two languages ("عربي" · "EN", the login toggle's labels) and a sliding
//       emerald thumb under the current one. The track is the input surface with a warm hairline, the thumb the
//       primary with the kit's faint lift (it is the one thing in the row that moves). Each segment is a 48 dp tall
//       hit area around the 38 dp track, a button with a selected state for screen readers; the slide takes the
//       kit's base motion and is skipped under Reduce motion.
//   AppLanguageTile(color:)
//       the settings row every role's Settings / More / Profile page shows (kill switch `profile.change_language`):
//       icon · "Language" · the segmented switch. Switching goes through LangProvider (saved, notified) and then
//       rebuilds the whole tree once ([refreshWholeUi]), so const widgets and pages under the current one follow.
//   refreshWholeUi()
//       marks every element dirty (moved here from the old ChangeLanguageScreen, which this replaces).
//
// Layout test: test/ui/app_language_switch_layout_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart' show AppConfig, LangProvider, Trans;
import '../config/theme/theme_config_provider.dart';
import '../core/display/app_fonts.dart';
import 'app_settings.dart';
import 'app_tokens.dart';

/// Marks every element in the app as dirty so the whole UI is rebuilt and every `'key'.tr` / `t(ar, en)` /
/// `pageDirection` is evaluated again with the new language — including `const` widgets, widgets that do not watch
/// LangProvider and pages that are still in the navigator stack. Called right after the language changed, so the
/// person never has to restart the app or re-open a screen to see the new language.
void refreshWholeUi() {
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
}

/// Switches the app to [lang] through [LangProvider] and rebuilds the whole tree after the frame.
Future<void> switchAppLanguage(BuildContext context, String lang) async {
  if (AppConfig.lang == lang) return;
  await context.read<LangProvider>().changeLang(lang);
  WidgetsBinding.instance.addPostFrameCallback((_) => refreshWholeUi());
}

/// The two languages as a segmented pill: plain values, so the layout harness can pump it.
class AppLanguageSegmented extends StatelessWidget {
  const AppLanguageSegmented({super.key, required this.current, required this.onChanged});

  /// 'ar' or 'en'.
  final String current;
  final ValueChanged<String> onChanged;

  /// One language's segment, the track under both and the hit area around the track.
  static const double segment = 56;
  static const double track = 38;
  static const double hit = AppTouch.min;

  /// The thumb's inset inside the track.
  static const double _inset = 3;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    // the thumb's position follows the reading direction: Arabic is the first segment
    const langs = ['ar', 'en'];
    final index = current == 'en' ? 1 : 0;

    Widget segmentOf(String lang) {
      final selected = lang == current;
      final label = lang == 'ar' ? 'عربي' : 'EN';
      return Semantics(
        button: true,
        selected: selected,
        label: lang == 'ar' ? 'العربية' : 'English',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: selected ? null : () => onChanged(lang),
          child: SizedBox(
            width: segment,
            height: hit,
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: motion.base,
                curve: AppMotion.curve,
                // "عربي" inside English UI: the other language's font draws it
                style: AppType.label(context).copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected ? c.onHero : c.textMedium,
                  height: 1.1,
                  fontFamilyFallback: AppFonts.fallback,
                ),
                child: Text(label, textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: segment * 2 + _inset * 2,
      height: hit,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // the track
          Container(
            height: track,
            decoration: BoxDecoration(
              color: c.inputBg,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: c.divider, width: AppBorder.hairline),
            ),
          ),
          // the thumb under the current language
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(_inset),
              child: AnimatedAlign(
                duration: motion.base,
                curve: AppMotion.curve,
                alignment: index == 0 ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
                child: Container(
                  width: segment,
                  height: track - _inset * 2,
                  decoration: BoxDecoration(
                    color: c.primary,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    boxShadow: AppElevation.of(context, 1),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _inset),
            child: Row(mainAxisSize: MainAxisSize.min, children: [for (final l in langs) segmentOf(l)]),
          ),
        ],
      ),
    );
  }
}

/// The "Language" row of a settings / More / Profile page: the segmented switch right in the row.
class AppLanguageTile extends StatelessWidget implements AppSettingsSearchable {
  const AppLanguageTile({super.key, this.color});

  /// Icon colour; default the primary.
  final Color? color;

  @override
  String get searchText => '${'app_language'.tr} language arabic english لغة اللغة عربي انجليزي';

  @override
  Widget build(BuildContext context) {
    context.watch<LangProvider>();
    return AppSettingsTile(
      featureKey: 'profile.change_language',
      icon: Icons.translate_rounded,
      color: color ?? context.colors.primary,
      label: 'app_language'.tr,
      keywords: 'language arabic english لغة عربي انجليزي',
      trailing: AppLanguageSegmented(
        current: AppConfig.lang == 'en' ? 'en' : 'ar',
        onChanged: (l) => switchAppLanguage(context, l),
      ),
    );
  }
}
