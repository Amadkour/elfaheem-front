import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../../../../../config/app_config.dart';
import '../../../../shared/profile/course_instractor_profile.dart';
import '../../../../teacher/home/teacher_models.dart';
import '../course_detail_provider.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'issued_certificate.dart';
import '../growth_tr.dart';

class AboutTab extends StatelessWidget {
  const AboutTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseDetailProvider>();
    final c = provider.course;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (provider.myCertificates.isNotEmpty) ...[
            _SectionTitle(
              title: 'my_certificates_title'.tr,
              icon: Icons.emoji_events_rounded,
              color: context.colors.accent,
            ),
            const SizedBox(height: 12),
            ...provider.myCertificates.map(
              (x) => _IssuedCertificateCard(cert: x),
            ),
            const SizedBox(height: 22),
          ],
          if (c.teacher != null) ...[   // was `!= Null` (the Type) — always true, then `c.teacher!` threw
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        InstructorProfileScreen(teacher: c.teacher!),
                  ),
                );
              },
              child: CourseInstructorCard(
                name: c.teacher?.name??'' ,
                category: (AppConfig.lang == 'ar'
                    ? c.category?.nameAr
                    : c.category?.nameEn) ?? '',
              ),
            ),
            const SizedBox(height: 26),
          ],
          if (((AppConfig.lang=='ar'? c.descriptionAr:c.descriptionEn)?? '').isNotEmpty) ...[
            _SectionTitle(
              title: gt('عن الكورس', 'About the course'),
              icon: Icons.info_outline_rounded,
            ),
            const SizedBox(height: 10),
            Text(
              (AppConfig.lang == 'ar' ? c.descriptionAr : c.descriptionEn) ??
                  '',
              style: context.colors.body.copyWith(height: 1.75),
            ),
            const SizedBox(height: 26),
          ],
          if (c.schedules.isNotEmpty) ...[
            _SectionTitle(
              title: gt('المواعيد الأسبوعية', 'Weekly schedule'),
              icon: Icons.calendar_month_rounded,
              color: context.colors.primary,
            ),
            const SizedBox(height: 12),
            ...c.schedules.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ScheduleChip(schedule: s),
              ),
            ),
            const SizedBox(height: 22),
          ],
          if (c.certificates.isNotEmpty) ...[
            _SectionTitle(
              title: gt('الشهادات', 'Certificates'),
              icon: Icons.workspace_premium_rounded,
              color: context.colors.accent,
            ),
            const SizedBox(height: 12),
            ...c.certificates.map(
              (x) => _InfoCard(
                icon: Icons.verified_rounded,
                iconBg: context.colors.accentTint,
                iconColor: context.colors.accent,
                title: x.title,
                subtitle: x.description,
              ),
            ),
            const SizedBox(height: 22),
          ],
          if (c.tools.isNotEmpty) ...[
            _SectionTitle(title: gt('الأدوات المطلوبة', 'Required tools'), icon: Icons.build_rounded),
            const SizedBox(height: 12),
            ...c.tools.map(
              (x) => _InfoCard(
                icon: Icons.settings_rounded,
                iconBg: context.colors.primaryTint,
                iconColor: context.colors.primary,
                title: x.name,
                subtitle: x.description,
              ),
            ),
            const SizedBox(height: 22),
          ],
          if (c.prerequisites.isNotEmpty) ...[
            _SectionTitle(
              title: gt('المتطلبات المسبقة', 'Prerequisites'),
              icon: Icons.checklist_rounded,
              color: context.colors.accent2,
            ),
            const SizedBox(height: 12),
            ...c.prerequisites.map(
              (x) => _InfoCard(
                icon: Icons.check_circle_outline_rounded,
                iconBg: context.colors.successTint,
                iconColor: context.colors.accent2,
                title: x.title,
                subtitle: x.description,
              ),
            ),
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

  const _SectionTitle({required this.title, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.primary;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: c),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: context.colors.h3.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
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
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    decoration: BoxDecoration(
      color: context.colors.primaryLight.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.colors.primary.withValues(alpha: 0.2)),
    ),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: context.colors.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.access_time_filled_rounded,
            color: context.colors.primary,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          schedule.dayLabel,
          style: context.colors.label.copyWith(
            color: context.colors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: context.colors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${schedule.startTime} — ${schedule.endTime}',
            style: context.colors.label.copyWith(
              color: context.colors.textDark,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

// ── Instructor card ───────────────────────────────────────────────────────────

/// The instructor strip of the About tab (plain values; tested by the layout harness).
class CourseInstructorCard extends StatelessWidget {
  final String name, category;

  const CourseInstructorCard({super.key, required this.name, required this.category});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: context.colors.primaryGradient,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: context.colors.primary.withValues(alpha: 0.36),
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
            color: context.colors.onHero.withValues(alpha: 0.2),
            shape: BoxShape.circle,
            border: Border.all(
              color: context.colors.onHero.withValues(alpha: 0.4),
              width: 2,
            ),
          ),
          alignment: Alignment.center,
          child: name.isNotEmpty
              ? Text(
                  name[0],
                  style: TextStyle(
                    color: context.colors.onHero,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'bahji',
                  ),
                )
              : Icon(Icons.person_rounded, color: context.colors.onHero, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isNotEmpty ? name : gt('المدرس', 'Instructor'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.colors.h3.copyWith(
                  color: context.colors.onHero,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (category.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.colors.caption.copyWith(color: context.colors.onHeroMuted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(child: Container(   // the badge gives way on a narrow phone instead of overflowing
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: context.colors.onHero.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.colors.onHero.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_rounded, color: context.colors.onHero, size: 13),
              const SizedBox(width: 5),
              Flexible(child: Text(
                gt('مدرس', 'Instructor'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.colors.onHero,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'bahji',
                ),
              )),
            ],
          ),
        )),
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
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: context.colors.heroShade.withValues(alpha: 0.05),
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
                  style: context.colors.label.copyWith(
                    color: context.colors.textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: context.colors.caption),
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

  const SectionHdr({super.key, required this.title, this.icon, this.iconColor});

  @override
  Widget build(BuildContext context) {
    final c = iconColor ?? context.colors.primary;
    return Row(
      children: [
        if (icon != null) ...[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: c),
          ),
          const SizedBox(width: 10),
        ],
        Text(
          title,
          style: context.colors.h3.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

// ── Issued certificate (student's own) ───────────────────────────────────────

String _fmtIssued(DateTime? d) =>
    d == null ? '' : '${d.day}/${d.month}/${d.year}';

class _IssuedCertificateCard extends StatelessWidget {
  final IssuedCertificate cert;

  const _IssuedCertificateCard({required this.cert});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isAr = AppConfig.lang == 'ar';
    final date = _fmtIssued(cert.issuedAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => _CertificateViewer(cert: cert),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.accent.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: c.heroShade.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1600 / 1131,
                child: _CertificateImage(url: cert.urlFor(isAr)),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.verified_rounded, color: c.accent, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cert.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: c.label.copyWith(
                              color: c.textDark,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (date.isNotEmpty)
                            Text(
                              '${'certificate_issued_on'.tr} $date',
                              style: c.caption,
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.zoom_out_map_rounded,
                      color: c.textMedium,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CertificateImage extends StatelessWidget {
  final String url;
  final BoxFit fit;

  const _CertificateImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) => Image.network(
    url,
    fit: fit,
    loadingBuilder: (_, child, progress) => progress == null
        ? child
        : AppShimmer(child: ColoredBox(color: context.colors.divider.withValues(alpha: 0.7), child: const SizedBox.expand())),
    errorBuilder: (_, _, _) => Container(
      color: context.colors.primaryLight.withValues(alpha: 0.2),
      alignment: Alignment.center,
      child: Icon(
        Icons.broken_image_outlined,
        color: context.colors.textMedium,
        size: 32,
      ),
    ),
  );
}

/// Full-screen, pinch-to-zoom viewer with an Arabic / English switch.
class _CertificateViewer extends StatefulWidget {
  final IssuedCertificate cert;

  const _CertificateViewer({required this.cert});

  @override
  State<_CertificateViewer> createState() => _CertificateViewerState();
}

class _CertificateViewerState extends State<_CertificateViewer> {
  late bool _arabic = AppConfig.lang == 'ar' && widget.cert.hasArabic;

  @override
  Widget build(BuildContext context) {
    final cert = widget.cert;
    return Dialog(
      backgroundColor: context.colors.heroShade,
      insetPadding: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    cert.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.onHero,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (cert.hasArabic) ...[
                  _LangChip(
                    label: 'العربية',
                    selected: _arabic,
                    onTap: () => setState(() => _arabic = true),
                  ),
                  const SizedBox(width: 6),
                  _LangChip(
                    label: 'English',
                    selected: !_arabic,
                    onTap: () => setState(() => _arabic = false),
                  ),
                ],
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  icon: Icon(Icons.close_rounded, color: context.colors.onHero),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Flexible(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: AspectRatio(
                aspectRatio: 1600 / 1131,
                child: _CertificateImage(
                  key: ValueKey(_arabic),
                  url: cert.urlFor(_arabic),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LangChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? context.colors.accent2 : context.colors.heroGlass,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? context.colors.charcoalDark : context.colors.onHeroMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
