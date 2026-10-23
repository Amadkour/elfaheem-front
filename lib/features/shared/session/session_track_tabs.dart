// lib/features/shared/session/session_track_tabs.dart
//
// "All · Lectures · Sections" — a course's lectures (teacher) and sections / labs (assistant) side by side.
// Shown only when the course actually has sections; each tab carries its count.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

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
    Widget tab(String key, IconData icon, String label, int? n, Color tone) {
      final on = value == key;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: on ? c.cardBg : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              boxShadow: on ? c.cardShadow : null,
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 18, color: on ? tone : c.textLight),
              const SizedBox(width: 6),
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'tajawal', fontWeight: on ? FontWeight.w800 : FontWeight.w600, color: on ? c.textDark : c.textMedium))),
              if (n != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(color: (on ? tone : c.textLight).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                  child: Text('$n', style: TextStyle(fontFamily: 'tajawal', fontSize: 11.5, fontWeight: FontWeight.w800, color: on ? tone : c.textMedium)),
                ),
              ],
            ]),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: c.divider)),
      child: Row(children: [
        if (showAll) tab('all', Icons.view_agenda_rounded, _t('الكل', 'All'), null, c.primary),
        tab('lecture', Icons.co_present_rounded, _t('المحاضرات', 'Lectures'), lectures, c.primary),
        tab('section', Icons.science_rounded, _t('السكاشن', 'Sections'), sections, c.purple),
      ]),
    );
  }
}
