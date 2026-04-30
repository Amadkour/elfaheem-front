import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/models.dart';
import 'package:provider/provider.dart';

import '../../../../../config/app_theme.dart';
import '../../../../teacher/home/teacher_models.dart';
import '../course_detail_provider.dart';

class AboutTab extends StatelessWidget {
  const AboutTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CourseDetailProvider>().course;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InstructorCard(
              name: c.teacherName ?? '', category: c.categoryName ?? ''),
          const SizedBox(height: 26),

          if ((c.description ?? '').isNotEmpty) ...[
            const _SectionTitle(title: 'عن الكورس', icon: Icons.info_outline_rounded),
            const SizedBox(height: 10),
            Text(c.description!,
                style: AppTheme.body.copyWith(height: 1.75)),
            const SizedBox(height: 26),
          ],

          if (c.schedules.isNotEmpty) ...[
            _SectionTitle(
                title: 'المواعيد الأسبوعية',
                icon: Icons.calendar_month_rounded,
                color: AppTheme.primary),
            const SizedBox(height: 12),
            ...c.schedules.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ScheduleChip(schedule: s),
            )),
            const SizedBox(height: 22),
          ],

          if (c.certificates.isNotEmpty) ...[
            _SectionTitle(
                title: 'الشهادات',
                icon: Icons.workspace_premium_rounded,
                color: AppTheme.accent),
            const SizedBox(height: 12),
            ...c.certificates.map((x) => _InfoCard(
              icon: Icons.verified_rounded,
              iconBg: const Color(0xFFFAEEDA),
              iconColor: AppTheme.accent,
              title: x.title,
              subtitle: x.description,
            )),
            const SizedBox(height: 22),
          ],

          if (c.tools.isNotEmpty) ...[
            _SectionTitle(
                title: 'الأدوات المطلوبة',
                icon: Icons.build_rounded),
            const SizedBox(height: 12),
            ...c.tools.map((x) => _InfoCard(
              icon: Icons.settings_rounded,
              iconBg: const Color(0xFFEEEDFE),
              iconColor: AppTheme.primary,
              title: x.title,
              subtitle: x.description,
            )),
            const SizedBox(height: 22),
          ],

          if (c.prerequisites.isNotEmpty) ...[
            _SectionTitle(
                title: 'المتطلبات المسبقة',
                icon: Icons.checklist_rounded,
                color: AppTheme.accent2),
            const SizedBox(height: 12),
            ...c.prerequisites.map((x) => _InfoCard(
              icon: Icons.check_circle_outline_rounded,
              iconBg: const Color(0xFFE1F5EE),
              iconColor: AppTheme.accent2,
              title: x.title,
              subtitle: x.description,
            )),
          ],
        ],
      ),
    );
  }
}

// ── Section title ─────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? color;

  const _SectionTitle(
      {required this.title, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.primary;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: c.withValues(alpha:0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: c),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: AppTheme.h3.copyWith(
                fontSize: 15, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

// ── Shared schedule chip ──────────────────────────────────────────────────────

class ScheduleChip extends StatelessWidget {
  final CourseSchedule schedule;
  const ScheduleChip({super.key, required this.schedule});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
        horizontal: 16, vertical: 13),
    decoration: BoxDecoration(
      color: AppTheme.primaryLight.withValues(alpha:0.12),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
          color: AppTheme.primary.withValues(alpha:0.2)),
    ),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha:0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.access_time_filled_rounded,
              color: AppTheme.primary, size: 18),
        ),
        const SizedBox(width: 12),
        Text(
          schedule.dayLabel,
          style: AppTheme.label.copyWith(
              color: AppTheme.primary, fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha:0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${schedule.startTime} — ${schedule.endTime}',
            style: AppTheme.label.copyWith(
                color: AppTheme.textDark, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

// ── Instructor card ───────────────────────────────────────────────────────────

class _InstructorCard extends StatelessWidget {
  final String name, category;
  const _InstructorCard({required this.name, required this.category});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: AppTheme.primaryGradient,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: AppTheme.primary.withValues(alpha:0.36),
          blurRadius: 22,
          offset: const Offset(0, 7),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha:0.2),
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withValues(alpha:0.4), width: 2),
          ),
          alignment: Alignment.center,
          child: name.isNotEmpty
              ? Text(
            name[0],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              fontFamily: 'Cairo',
            ),
          )
              : const Icon(Icons.person_rounded,
              color: Colors.white, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isNotEmpty ? name : 'المدرس',
                style: AppTheme.h3.copyWith(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900),
              ),
              if (category.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(category,
                    style: AppTheme.caption
                        .copyWith(color: Colors.white70)),
              ],
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha:0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: Colors.white.withValues(alpha:0.3)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_rounded,
                  color: Colors.white, size: 13),
              SizedBox(width: 5),
              Text(
                'مدرس',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ── Info card ─────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg, iconColor;
  final String title;
  final String? subtitle;

  const _InfoCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.label.copyWith(
                      color: AppTheme.textDark,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: AppTheme.caption),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// ── Shared section header (exported) ─────────────────────────────────────────

class SectionHdr extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Color? iconColor;

  const SectionHdr(
      {super.key, required this.title, this.icon, this.iconColor});

  @override
  Widget build(BuildContext context) {
    final c = iconColor ?? AppTheme.primary;
    return Row(
      children: [
        if (icon != null) ...[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: c.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: c),
          ),
          const SizedBox(width: 10),
        ],
        Text(title,
            style: AppTheme.h3
                .copyWith(fontWeight: FontWeight.w800, fontSize: 15)),
      ],
    );
  }
}