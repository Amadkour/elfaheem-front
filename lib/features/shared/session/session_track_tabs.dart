// lib/features/shared/session/session_track_tabs.dart
//
// "All · Lectures · Sections" — a course's lectures (teacher) and sections / labs (assistant) side by side.
// Shown only when the course actually has sections; each tab carries its count.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

class SessionTrackTabs extends StatelessWidget {
  const SessionTrackTabs({super.key, required this.value, this.lectures, this.sections, required this.onChanged, this.showAll = true});
  final String value;               // all · lecture · section
  final int? lectures, sections;    // null = no count badge (e.g. in the session form)
  final bool showAll;               // false when choosing what ONE session is
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    return LayoutBuilder(builder: (context, box) {
    // narrow segments drop the icon so the label and its count stay whole (M14: "المحاضر…")
    final perTab = (box.maxWidth - AppSpace.xs) / (showAll ? 3 : 2);
    final icons = perTab >= 130;
    // the kit's pill track (AppTabs): the input well, the chosen pill solid primary with the on-hero ink
    Widget tab(String key, IconData icon, String label, int? n) {
      final on = value == key;
      final ink = on ? c.onHero : c.textMedium;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: () => onChanged(key),
            child: AnimatedContainer(
              duration: motion.base,
              curve: AppMotion.curve,
              constraints: const BoxConstraints(minHeight: AppSpace.xl + AppSpace.xs),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
              decoration: BoxDecoration(
                color: on ? c.primary : c.inputBg.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icons) ...[
                  Icon(icon, size: AppIconSize.sm, color: ink),
                  const SizedBox(width: AppSpace.xs - 2),
                ],
                Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.label(context).copyWith(fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: ink))),
                if (n != null) ...[
                  const SizedBox(width: AppSpace.xs - 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs - 1, vertical: 1),
                    decoration: BoxDecoration(
                        color: on ? c.heroGlass : c.cardBg, borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Text('$n',
                        style: AppType.overline(context)
                            .copyWith(color: ink, fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                ],
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpace.xxs),
      decoration: BoxDecoration(
          color: c.inputBg,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: c.divider, width: AppBorder.hairline)),
      child: Row(children: [
        if (showAll) tab('all', Icons.view_agenda_rounded, _t('الكل', 'All'), null),
        tab('lecture', Icons.co_present_rounded, _t('المحاضرات', 'Lectures'), lectures),
        tab('section', Icons.science_rounded, _t('السكاشن', 'Sections'), sections),
      ]),
    );
    });
  }
}
