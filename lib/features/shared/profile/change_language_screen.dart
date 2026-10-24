import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart' show LangProvider, Trans, AppConfig;
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/base_page.dart';

/// Marks every element in the app as dirty so the whole UI is rebuilt and every
/// `'key'.tr` / `t(ar, en)` / `pageDirection` is evaluated again with the new
/// language — including `const` widgets, widgets that do not watch
/// LangProvider and pages that are still in the navigator stack.
///
/// Called right after the language changed, so the user never has to restart
/// the app or re-open a screen to see the new language.
void refreshWholeUi() {
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
}

class ChangeLanguageScreen extends StatelessWidget {
  const ChangeLanguageScreen({super.key});

  Future<void> _select(BuildContext context, LangProvider provider, String l) async {
    final nav = Navigator.of(context);
    if (AppConfig.lang != l) {
      await provider.changeLang(l);
    }
    nav.pop();
    // After the pop frame, rebuild the whole app with the new language.
    WidgetsBinding.instance.addPostFrameCallback((_) => refreshWholeUi());
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LangProvider>();
    return BasePage(
      useWebCard: true,
      child: SafeArea(
        child: Column(children: [
          ScreenAppBar(title: 'change_language'.tr),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: Column(
              children: provider.languages.map((l) {
                final isSelected = AppConfig.lang == l;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GestureDetector(
                    onTap: () => _select(context, provider, l),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.colors.cardBg,
                        borderRadius: BorderRadius.circular(context.colors.radiusMedium),
                        border: Border.all(
                            color: isSelected ? context.colors.primary : context.colors.divider,
                            width: isSelected ? 2 : 1),
                        boxShadow: context.colors.cardShadow,
                      ),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(l.tr,
                                style: context.colors.label.copyWith(
                                    color: isSelected
                                        ? context.colors.primary
                                        : context.colors.textDark,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15)),
                            if (isSelected)
                              Icon(Icons.check_circle_rounded,
                                  color: context.colors.primary, size: 22),
                          ]),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ]),
      ),
    );
  }
}
