// features/student/courses/details/components/about.dart
//
// The About tab: my certificates · description · rating · instructor · schedule · certificates · tools ·
// prerequisites, as CourseInfoSection cards of the shared course page. [AboutTab] reads the provider and hands
// plain values to [CourseAboutView] (tested by the layout harness).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppEase, AppTilt;
import 'package:provider/provider.dart';

import '../../../../../config/app_config.dart';
import '../../../../../utils/widget/rating_widget.dart';
import '../../../../shared/course/course_space/course_space.dart';
import '../../../../shared/public_profile/public_profile_page.dart' show openPersonProfile;
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
    final ar = AppConfig.lang == 'ar';
    return CourseAboutView(
      description: (ar ? c.descriptionAr : c.descriptionEn) ?? '',
      teacherName: c.teacher?.name,
      category: (ar ? c.category?.nameAr : c.category?.nameEn) ?? '',
      onTeacher: c.teacher == null
          ? null
          : () => openPersonProfile(context, c.teacher!), // the one profile page when public (D-853)
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
    // ONE card, its sections split by hairlines (no stack of boxes). Colour only where it means something: gold for
    // what the student earned (their certificates, the rating), emerald for the certificate the course gives; every
    // other section keeps the quiet ink.
    return Padding(
      padding: const EdgeInsets.fromLTRB(kCourseGutter, AppSpace.xxs, kCourseGutter, AppSpace.lg),
      child: CourseInfoGroup(
        children: [
          if (myCertificates.isNotEmpty)
            CourseInfoSection(
              title: 'my_certificates_title'.tr,
              icon: Icons.emoji_events_outlined,
              color: col.accent2,
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
              children: [
                for (final x in tools)
                  CourseInfoRow(icon: Icons.settings_outlined, color: col.textMedium, title: x.name, subtitle: x.description),
              ],
            ),
          if (prerequisites.isNotEmpty)
            CourseInfoSection(
              title: gt('المتطلبات المسبقة', 'Prerequisites'),
              icon: Icons.checklist_rounded,
              children: [
                for (final x in prerequisites)
                  CourseInfoRow(
                    icon: Icons.check_circle_outline_rounded,
                    color: col.textMedium,
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
    // a reading measure: body ink, a generous line for long Arabic paragraphs
    final style = AppType.body(context).copyWith(color: context.colors.textDark, height: 1.75);
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
              duration: AppMotion.of(context).base,
              curve: AppEase.out,
              alignment: AlignmentDirectional.topStart,
              child: Text(
                widget.text,
                style: style,
                maxLines: _open || !long ? null : 6,
                overflow: _open || !long ? null : TextOverflow.fade,
              ),
            ),
            if (long)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs),
                child: AppButton.ghost(
                  label: _open ? gt('عرض أقل', 'Show less') : gt('عرض المزيد', 'Show more'),
                  trailingIcon: _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: AppButtonSize.sm,
                  onPressed: () => setState(() => _open = !_open),
                ),
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

  /// The portrait's side.
  static const double _avatar = AppTouch.primary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // the teacher's monogram on their own block tone (the same tone wherever this teacher appears)
    final b = AppBlockColors.of(context, AppBlockTone.forKey('teacher:$name'));
    final row = Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Row(
        children: [
          Container(
            width: _avatar,
            height: _avatar,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: b.surface, borderRadius: AppRadius.cardAll),
            child: name.isNotEmpty
                ? ExcludeSemantics(child: Text(name.characters.first, style: AppType.headline(context).copyWith(color: b.ink)))
                : Icon(Icons.person_outline_rounded, color: b.ink, size: AppIconSize.lg),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(gt('المدرس', 'Instructor'), style: AppType.meta(context)),
                const SizedBox(height: AppSpace.xxs / 2),
                Text(
                  name.isNotEmpty ? name : gt('المدرس', 'Instructor'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.section(context),
                ),
                if (category.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xxs / 2),
                  Text(category, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                ],
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: AppSpace.xs),
            Icon(Icons.chevron_right_rounded, color: c.textLight, size: AppIconSize.md),
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

    // an earned certificate is an image card worth lingering on: it leans a little under the pointer (D-620)
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppTilt.subtle(
        radius: AppRadius.card,
        child: Material(
          color: c.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.cardAll,
            side: BorderSide(color: c.divider, width: AppBorder.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => _CertificateViewer(cert: cert),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 1600 / 1131,
                  child: _CertificateImage(url: cert.urlFor(isAr)),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Row(
                    children: [
                      // gold: an achievement, as an icon fill only
                      Icon(Icons.verified_rounded, color: c.accent2, size: AppIconSize.lg),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cert.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.row(context).copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (date.isNotEmpty)
                              Text('${'certificate_issued_on'.tr} $date', style: AppType.meta(context)),
                          ],
                        ),
                      ),
                      Icon(Icons.zoom_out_map_rounded, color: c.textMedium, size: AppIconSize.md),
                    ],
                  ),
                ),
              ],
            ),
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
        size: AppIconSize.xl,
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
      // a dark viewing room: the certificate is the only bright thing on screen
      backgroundColor: context.colors.heroShade,
      insetPadding: const EdgeInsets.all(AppSpace.sm),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xs, AppSpace.xxs, AppSpace.xxs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    cert.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.section(context).copyWith(color: context.colors.onHero),
                  ),
                ),
                if (cert.hasArabic) ...[
                  _LangChip(
                    label: 'العربية',
                    selected: _arabic,
                    onTap: () => setState(() => _arabic = true),
                  ),
                  const SizedBox(width: AppSpace.xxs),
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
          const SizedBox(height: AppSpace.xs),
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
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // a 48 px target around the pill
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        child: Center(
          widthFactor: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs + 2),
            decoration: BoxDecoration(
              color: selected ? context.colors.onHero : context.colors.heroGlass,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              label,
              style: AppType.meta(context).copyWith(
                color: selected ? context.colors.charcoalDark : context.colors.onHeroMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
