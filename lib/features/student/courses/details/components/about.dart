// features/student/courses/details/components/about.dart
//
// The About tab: my certificates · description · rating · instructor · schedule · certificates · tools ·
// prerequisites, as CourseInfoSection cards of the shared course page. [AboutTab] reads the provider and hands
// plain values to [CourseAboutView] (tested by the layout harness).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../../../../../config/app_config.dart';
import '../../../../../utils/widget/rating_widget.dart';
import '../../../../shared/course/course_space/course_space.dart';
import '../../../../shared/profile/course_instractor_profile.dart';
import '../../../../teacher/home/teacher_models.dart';
import '../course_detail_provider.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'issued_certificate.dart';
import '../growth_tr.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

class AboutTab extends StatelessWidget {
  const AboutTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseDetailProvider>();
    final c = provider.course;
    final ar = AppConfig.lang == 'ar';
    return CourseAboutView(
      description: (ar ? c.descriptionAr : c.descriptionEn) ?? '',
      teacherName: c.teacher?.name,
      category: (ar ? c.category?.nameAr : c.category?.nameEn) ?? '',
      onTeacher: c.teacher == null
          ? null
          : () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => InstructorProfileScreen(teacher: c.teacher!)),
            ),
      rating: RatingWidget(type: RateType.course, sourceId: c.id, canEdit: c.isEnrolled),
      myCertificates: provider.myCertificates,
      schedules: c.schedules,
      certificates: c.certificates,
      tools: c.tools,
      prerequisites: c.prerequisites,
    );
  }
}

/// The About tab from plain values.
class CourseAboutView extends StatelessWidget {
  const CourseAboutView({
    super.key,
    this.description = '',
    this.teacherName,
    this.category = '',
    this.onTeacher,
    this.rating,
    this.myCertificates = const [],
    this.schedules = const [],
    this.certificates = const [],
    this.tools = const [],
    this.prerequisites = const [],
  });

  final String description;
  final String? teacherName;
  final String category;
  final VoidCallback? onTeacher;

  /// The course rating (RatingWidget) — a slot, it talks to the server.
  final Widget? rating;
  final List<IssuedCertificate> myCertificates;
  final List<CourseSchedule> schedules;
  final List<CourseCertificate> certificates;
  final List<CourseTool> tools;
  final List<CoursePrerequisite> prerequisites;

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    // ONE card, its sections split by hairlines (no stack of boxes)
    return Padding(
      padding: const EdgeInsets.fromLTRB(kCourseGutter, 4, kCourseGutter, 24),
      child: CourseInfoGroup(
        children: [
          if (myCertificates.isNotEmpty)
            CourseInfoSection(
              title: 'my_certificates_title'.tr,
              icon: Icons.emoji_events_outlined,
              color: col.accent,
              children: [for (final x in myCertificates) _IssuedCertificateCard(cert: x)],
            ),
          if (description.trim().isNotEmpty)
            CourseInfoSection(
              title: gt('عن الكورس', 'About the course'),
              icon: Icons.info_outline_rounded,
              children: [_ExpandableText(text: description.trim())],
            ),
          if (teacherName != null) CourseInstructorCard(name: teacherName!, category: category, onTap: onTeacher),
          if (rating != null)
            CourseInfoSection(
              title: gt('التقييم', 'Rating'),
              icon: Icons.star_outline_rounded,
              color: col.accent2,
              children: [rating!],
            ),
          if (schedules.isNotEmpty)
            CourseInfoSection(
              title: gt('المواعيد الأسبوعية', 'Weekly schedule'),
              icon: Icons.calendar_month_outlined,
              children: [CourseScheduleChips(schedules: schedules)],
            ),
          if (certificates.isNotEmpty)
            CourseInfoSection(
              title: gt('الشهادات', 'Certificates'),
              icon: Icons.workspace_premium_outlined,
              color: col.success,
              children: [
                for (final x in certificates)
                  CourseInfoRow(icon: Icons.verified_outlined, color: col.success, title: x.title, subtitle: x.description),
              ],
            ),
          if (tools.isNotEmpty)
            CourseInfoSection(
              title: gt('الأدوات المطلوبة', 'Required tools'),
              icon: Icons.build_outlined,
              color: col.warning,
              children: [
                for (final x in tools)
                  CourseInfoRow(icon: Icons.settings_outlined, color: col.warning, title: x.name, subtitle: x.description),
              ],
            ),
          if (prerequisites.isNotEmpty)
            CourseInfoSection(
              title: gt('المتطلبات المسبقة', 'Prerequisites'),
              icon: Icons.checklist_rounded,
              color: col.accent,
              children: [
                for (final x in prerequisites)
                  CourseInfoRow(
                    icon: Icons.check_circle_outline_rounded,
                    color: col.accent,
                    title: x.title,
                    subtitle: x.description,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A long description folds to 6 lines with "Show more".
class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.text});

  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = c.body.copyWith(height: 1.75);
    return LayoutBuilder(
      builder: (context, box) {
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 6,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: box.maxWidth);
        final long = tp.didExceedMaxLines;
        tp.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              alignment: AlignmentDirectional.topStart,
              child: Text(
                widget.text,
                style: style,
                maxLines: _open || !long ? null : 6,
                overflow: _open || !long ? null : TextOverflow.fade,
              ),
            ),
            if (long)
              TextButton(
                onPressed: () => setState(() => _open = !_open),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
                child: Text(_open ? gt('عرض أقل', 'Show less') : gt('عرض المزيد', 'Show more')),
              ),
          ],
        );
      },
    );
  }
}

// ── Instructor card ───────────────────────────────────────────────────────────

/// The instructor section of the About tab: avatar · "Instructor" · name (two lines at most) · category · chevron
/// (plain values; tested by the layout harness).
class CourseInstructorCard extends StatelessWidget {
  final String name, category;
  final VoidCallback? onTap;

  const CourseInstructorCard({super.key, required this.name, required this.category, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = c.isDark ? Color.lerp(c.primary, c.textDark, 0.4)! : c.primary;
    final row = Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: name.isNotEmpty
                ? Text(
                    name.characters.first,
                    style: TextStyle(fontFamily: AppFonts.family, fontSize: 17, fontWeight: FontWeight.w600, color: ink),
                  )
                : Icon(Icons.person_outline_rounded, color: ink, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gt('المدرس', 'Instructor'),
                  style: TextStyle(fontFamily: AppFonts.family, fontSize: 11.5, color: c.textLight),
                ),
                const SizedBox(height: 2),
                Text(
                  name.isNotEmpty ? name : gt('المدرس', 'Instructor'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.family,
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: c.textDark,
                  ),
                ),
                if (category.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: AppFonts.family, fontSize: 12.5, color: c.textMedium),
                  ),
                ],
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: c.textLight, size: 20),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: onTap, child: row),
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
                              fontWeight: FontWeight.w600,
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
