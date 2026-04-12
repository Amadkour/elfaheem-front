
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:provider/provider.dart';

import '../../../../../config/app_theme.dart';
import '../course_detail_provider.dart';
import '../course_detail_screen.dart';

class AboutTab extends StatelessWidget {
  const AboutTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CourseDetailProvider>().course;
    return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Instructor
          _InstructorCard(
              name: c.teacherName ?? '', subtitle: c.categoryName ?? ''),
          const SizedBox(height: 20),
          if ((c.description ?? '').isNotEmpty) ...[
            const SectionHdr(title: 'عن الكورس'),
            const SizedBox(height: 10),
            Text(c.description!, style: AppTheme.body),
            const SizedBox(height: 20)
          ],
          if (c.schedules.isNotEmpty) ...[
            const SectionHdr(
                title: 'المواعيد الأسبوعية',
                icon: Icons.calendar_month_rounded),
            const SizedBox(height: 10),
            ...c.schedules.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ScheduleChip(schedule: s))),
            const SizedBox(height: 16)
          ],
          if (c.certificates.isNotEmpty) ...[
            const SectionHdr(
                title: 'الشهادات',
                icon: Icons.workspace_premium_rounded,
                iconColor: AppTheme.accent),
            const SizedBox(height: 10),
            ...c.certificates.map((x) => _InfoCard(
                icon: Icons.verified_rounded,
                iconBg: AppTheme.accent.withValues(alpha: 0.1),
                iconColor: AppTheme.accent,
                title: x.title,
                subtitle: x.description)),
            const SizedBox(height: 16)
          ],
          if (c.tools.isNotEmpty) ...[
            const SectionHdr(
                title: 'الأدوات المطلوبة', icon: Icons.build_rounded),
            const SizedBox(height: 10),
            ...c.tools.map((x) => _InfoCard(
                icon: Icons.settings_rounded,
                iconBg: AppTheme.primary.withValues(alpha: 0.1),
                iconColor: AppTheme.primary,
                title: x.title,
                subtitle: x.description)),
            const SizedBox(height: 16)
          ],
          if (c.prerequisites.isNotEmpty) ...[
            const SectionHdr(
                title: 'المتطلبات المسبقة',
                icon: Icons.checklist_rounded,
                iconColor: AppTheme.success),
            const SizedBox(height: 10),
            ...c.prerequisites.map((x) => _InfoCard(
                icon: Icons.check_circle_outline_rounded,
                iconBg: AppTheme.success.withValues(alpha: 0.1),
                iconColor: AppTheme.success,
                title: x.title,
                subtitle: x.description))
          ],
        ]));
  }
}
class _InstructorCard extends StatelessWidget {
  final String name, subtitle;

  const _InstructorCard({required this.name, required this.subtitle});

  @override
  Widget build(BuildContext ctx) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          boxShadow: AppTheme.cardShadow),
      child: Row(children: [
        Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.3), width: 2)),
            child: const Icon(Icons.person_rounded,
                color: AppTheme.primary, size: 28)),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name.isNotEmpty ? name : 'المدرس', style: AppTheme.h3),
          Text(subtitle.isNotEmpty ? subtitle : '', style: AppTheme.caption)
        ])
      ]));
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg, iconColor;
  final String title;
  final String? subtitle;

  const _InfoCard(
      {required this.icon,
        required this.iconBg,
        required this.iconColor,
        required this.title,
        this.subtitle});

  @override
  Widget build(BuildContext ctx) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: AppTheme.cardBg,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              boxShadow: AppTheme.cardShadow),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: iconBg, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: iconColor, size: 20)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: AppTheme.label
                              .copyWith(color: AppTheme.textDark, fontSize: 14)),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(subtitle!, style: AppTheme.caption)
                      ]
                    ]))
          ])));
}
