import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart' show LangProvider, pageDirection, Trans, AppConfig;
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/base_page.dart';

class ChangeLanguageScreen extends StatelessWidget {
  const ChangeLanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LangProvider>();
    return BasePage(
      useWebCard:true,
      child:
    SafeArea(
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
                      onTap: () async {
                        await provider.changeLang(l);
                        Navigator.pop(context);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.colors.cardBg,
                          borderRadius: BorderRadius.circular(
                              context.colors.radiusMedium),
                          border: Border.all(
                              color: isSelected
                                  ? context.colors.primaryBlue
                                  : context.colors.divider,
                              width: isSelected ? 2 : 1),
                          boxShadow: context.colors.cardShadow,
                        ),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(l.tr,
                                  style: context.colors.label.copyWith(
                                      color: isSelected
                                          ? context.colors.primaryBlue
                                          : context.colors.textDark,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                              if (isSelected)
                                Icon(Icons.check_circle_rounded,
                                    color: context.colors.primaryBlue,
                                    size: 22),
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
