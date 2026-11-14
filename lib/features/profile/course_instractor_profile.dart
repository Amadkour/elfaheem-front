// ─────────────────────────────────────────────────────────────────────────────
// features/courses/student/components/course_instractor_profile.dart
// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/rating_widget.dart';
import 'package:flutter_education_app/features/auth/teacher_document_model.dart';
import 'package:flutter_education_app/features/auth/teacher_document_provider.dart';
import 'package:flutter_education_app/features/home/student/models.dart';
import 'package:flutter_education_app/features/courses/teacher/component/teacher_stats.dart';
import 'package:flutter_education_app/features/home/teacher/home_screen.dart';
import 'package:flutter_education_app/features/profile/instructor_courses_section.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppCountUp, AppEase, AppReveal, AppTilt;

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class InstructorProfileScreen extends StatefulWidget {
  final TeacherProfileData teacher;
  final TeacherStats? stats;
  final bool studentView;

  const InstructorProfileScreen({
    super.key,
    required this.teacher,
    this.studentView = true,
    this.stats,
  });

  @override
  State<InstructorProfileScreen> createState() =>
      _InstructorProfileScreenState();
}

class _InstructorProfileScreenState extends State<InstructorProfileScreen> {
  /// The teacher's public, personal courses (GET /courses?teacher_id=…&scope=personal), page by page.
  late final InstructorCoursesController _courses =
      InstructorCoursesController(teacherId: widget.teacher.id);

  @override
  void initState() {
    super.initState();
    _courses.load();

    // Load approved public docs for this teacher
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TeacherDocumentProvider>().loadPublicDocuments(
        widget.teacher.id,
      );
    });
  }

  @override
  void dispose() {
    _courses.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BasePage( key: const ValueKey('course_instructor'), useWebCard: true, width: AppWidth.content, appBar: ScreenAppBar(title: widget.teacher.name),
      child: LayoutBuilder(
        builder: (ctx, constraints) => constraints.maxWidth > _wideFrom
            ? _WideLayout(
          teacher: widget.teacher,
          studentView: widget.studentView,
          stats: widget.stats,
          courses: _courses,
        )
            : _NarrowLayout(
          teacher: widget.teacher,
          studentView: widget.studentView,
          stats: widget.stats,
          courses: _courses,
        ),
      ),
    );
  }

  /// From this width the profile card is a column beside the sections.
  static const double _wideFrom = 800;
}

/// ONE orchestrated entrance (system.md §6): the hero leads, the figures and the about card follow it once; the
/// sections further down are simply there.
Widget _enter(int i, Widget child) => AppReveal(index: i, group: 'instructor', child: child);

// ─────────────────────────────────────────────────────────────────────────────
// NARROW LAYOUT
// ─────────────────────────────────────────────────────────────────────────────

class _NarrowLayout extends StatelessWidget {
  final TeacherProfileData teacher;
  final bool studentView;
  final TeacherStats? stats;
  final InstructorCoursesController courses;

  const _NarrowLayout({
    required this.teacher,
    required this.studentView,
    this.stats,
    required this.courses,
  });

  @override
  Widget build(BuildContext context) {
    final side = AppSpace.gutter(MediaQuery.sizeOf(context).width);
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(side, AppSpace.sm, side, AppSpace.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _enter(0, _InstructorHero(teacher: teacher)),
          const SizedBox(height: AppSpace.md),
          _enter(1, _StatsRow(teacher: teacher)),
          _enter(2, _AboutSection(teacher: teacher)),
          const SizedBox(height: AppSpace.xl),
          InstructorCoursesBlock(controller: courses),
          _DocumentsSection(teacherId: teacher.id),
          _RatingSection(teacher: teacher, studentView: studentView),
          if (stats != null) ...[
            const SizedBox(height: AppSpace.xl),
            ParentComponent(featureKey: 'instructor.teacher_stats', child: StatsRow(stats: stats!, isFull: true)),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDE LAYOUT
// ─────────────────────────────────────────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  final TeacherProfileData teacher;
  final bool studentView;
  final TeacherStats? stats;
  final InstructorCoursesController courses;

  const _WideLayout({
    required this.teacher,
    required this.studentView,
    this.stats,
    required this.courses,
  });

  /// The profile column's width.
  static const double _column = 320;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Start column: the profile card
        SizedBox(
          width: _column,
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.lg, AppSpace.md, AppSpace.sm, AppSpace.xxl),
            child: _enter(0, ParentComponent(featureKey: 'instructor.profile_card', child: _InstructorHero(teacher: teacher, column: true))),
          ),
        ),

        // The sections
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.md, AppSpace.lg, AppSpace.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _enter(1, _StatsRow(teacher: teacher)),
                _enter(2, _AboutSection(teacher: teacher)),
                const SizedBox(height: AppSpace.xl),
                InstructorCoursesBlock(controller: courses),
                _DocumentsSection(teacherId: teacher.id),
                _RatingSection(teacher: teacher, studentView: studentView),
                if (stats != null) ...[
                  const SizedBox(height: AppSpace.xl),
                  ParentComponent(featureKey: 'instructor.teacher_stats', child: StatsRow(stats: stats!, isFull: true)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HERO  (the page's one block: identity, a soft primary gradient, D-713)
// ─────────────────────────────────────────────────────────────────────────────

/// The teacher's hero block (D-622): the avatar on a paper ring, the name in the editorial face with the verified
/// mark, the specialization, and the badges as paper chips. A row on a phone, a centred card in the wide column.
class _InstructorHero extends StatelessWidget {
  final TeacherProfileData teacher;

  /// The wide page's start column (a centred stack) rather than the phone's row.
  final bool column;

  const _InstructorHero({required this.teacher, this.column = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final spec = (AppConfig.lang == 'ar'
            ? teacher.teacherProfile?.specialization?.nameAr
            : teacher.teacherProfile?.specialization?.nameEn) ??
        '';
    return RepaintBoundary(
      child: AppTilt(
        radius: AppRadius.block,
        maxTilt: 2.5,
        glare: true,
        child: AppBlock(
          tone: AppBlockTone.identity,
          hero: true,
          child: Builder(builder: (context) {
            final b = AppBlock.colorsOf(context);
            final name = Row(
              mainAxisSize: column ? MainAxisSize.min : MainAxisSize.max,
              mainAxisAlignment: column ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Flexible(
                  child: Semantics(
                    header: true,
                    child: Text(
                      teacher.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: column ? TextAlign.center : TextAlign.start,
                      style: AppType.headline(context).copyWith(color: b.ink),
                    ),
                  ),
                ),
                if (teacher.isVerified) ...[
                  const SizedBox(width: AppSpace.xs),
                  Icon(Icons.verified_rounded, color: b.accentInk(c.primary), size: AppIconSize.md),
                ],
              ],
            );
            final who = Column(
              crossAxisAlignment: column ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                name,
                if (spec.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xxs),
                  Text(spec,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.label(context).copyWith(color: b.muted)),
                ],
                const SizedBox(height: AppSpace.sm),
                _BadgesRow(teacher: teacher, center: column),
              ],
            );
            final avatar = InstructorAvatar(teacher: teacher, size: _avatar, canOpen: false);
            if (column) {
              return Column(children: [avatar, const SizedBox(height: AppSpace.md), who]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              avatar,
              const SizedBox(width: AppSpace.md),
              Expanded(child: who),
            ]);
          }),
        ),
      ),
    );
  }

  static const double _avatar = AppSettingsHeader.avatar;
}

// ─────────────────────────────────────────────────────────────────────────────
// AVATAR
// ─────────────────────────────────────────────────────────────────────────────

class InstructorAvatar extends StatelessWidget {
  final TeacherProfileData teacher;
  final double size;
  final bool canOpen;
  final bool showTitle;
  final bool showImage;

  /// The initials' size as a share of the avatar (they scale with it).
  static const double _initialsShare = 0.35;

  const InstructorAvatar({
    super.key,
    required this.teacher,
    required this.size,
    required this.canOpen,
    this.showTitle = false,
    this.showImage = true,
  });

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'instructor.avatar',
    child: _featureContent(context),
  );

  Widget _featureContent(BuildContext context) {
    Widget w = Container(
      width: size,
      height: size,
      // the profile's own avatar sits on a paper ring (no drop shadow, D-612); a small one in a list keeps a hairline
      decoration: !canOpen
          ? BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: context.colors.cardBg, width: AppSettingsHeader.ring),
      )
          : BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: context.colors.background, width: AppBorder.hairline),
      ),
      child: ClipOval(
        child: (teacher.imageUrl ?? '').isNotEmpty
            ? AppNetworkImage(
          url: teacher.imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          enableFullscreen: !canOpen,
          heroTag:
          'instructor_avatar_${teacher.id}-${DateTime.timestamp()}',
        )
            : Container(
          // opaque card well: the initials stay readable on the coloured hero (M22: dark-on-blue "DO")
          color: context.colors.cardBg,
          child: Center(
            child: Text(
              teacher.initials,
              style: AppType.display(context).copyWith(
                color: context.colors.blockAccentInk(context.colors.primary, context.colors.cardBg),
                fontSize: size * _initialsShare,
              ),
            ),
          ),
        ),
      ),
    );

    if (showTitle) {
      w = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showImage) ...[w, const SizedBox(width: 5)],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment:CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        teacher.name,
                        style: context.colors.navLabelSelected.copyWith(
                          height: 1,
                          fontSize: size / 3,
                        ),
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                    if(canOpen) Icon(Icons.open_in_new,size:12,color:context.colors.primary)
                  ],
                ),
                if (teacher.teacherProfile != null)
                  Text(
                    '${teacher.teacherProfile!.experienceYears} ${'experience'.tr}',
                    style: context.colors.navLabelUnselected.copyWith(
                      height: 1,
                      fontSize: size / 3.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.rtl,
                  ),
              ],
            ),
          ),
        ],
      );
    }

    if (canOpen) {
      return InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InstructorProfileScreen(teacher: teacher),
          ),
        ),
        child: w,
      );
    }
    return w;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATS ROW
// ─────────────────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final TeacherProfileData teacher;

  const _StatsRow({required this.teacher});

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'instructor.stats',
    child: _featureContent(context),
  );

  /// A server word ("free", "paid") as a figure: its first letter capitalised, never all caps.
  static String _sentence(String s) => s.isEmpty ? s : s.characters.first.toUpperCase() + s.characters.skip(1).string;

  Widget _featureContent(BuildContext context) {
    final c = context.colors;
    final tp = teacher.teacherProfile;
    // one paper card parted by hairlines: years of experience lead (gold marks an achievement), the rest is ink
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.md, horizontal: AppSpace.xs),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _StatTile(
              icon: Icons.workspace_premium_rounded,
              value: tp != null ? '${tp.experienceYears}y' : '—',
              label: 'experience'.tr,
              color: c.accent2,
              count: true,
            ),
            VerticalDivider(width: AppSpace.md, thickness: AppBorder.hairline, color: c.divider),
            _StatTile(
              icon: Icons.payments_rounded,
              value: tp == null ? '—' : _sentence(tp.paymentType),
              label: 'pricing'.tr,
              color: c.textMedium,
            ),
            VerticalDivider(width: AppSpace.md, thickness: AppBorder.hairline, color: c.divider),
            _StatTile(
              icon: Icons.calendar_today_rounded,
              value: teacher.createdAt.year.toString(),
              label: 'joined'.tr,
              color: c.textMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  /// Counts up once (a number); a word is simply shown.
  final bool count;

  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.count = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = AppType.figure(context);
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: c.blockAccentInk(color, c.cardBg), size: AppIconSize.md),
          const SizedBox(height: AppSpace.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: count ? AppCountUp(value, style: style) : Text(value, maxLines: 1, style: style),
          ),
          const SizedBox(height: AppSpace.xxs / 2),
          Text(
            label,
            style: AppType.meta(context),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BADGES ROW
// ─────────────────────────────────────────────────────────────────────────────

class _BadgesRow extends StatelessWidget {
  final TeacherProfileData teacher;

  /// Centred (the wide column's card) or from the start (the phone's row).
  final bool center;

  const _BadgesRow({required this.teacher, this.center = false});

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'instructor.badges',
    child: _featureContent(context),
  );

  Widget _featureContent(BuildContext context) {
    final badges = <_BadgeData>[
      if (teacher.isVerified)
        _BadgeData(icon: Icons.verified_rounded, label: 'verified'.tr, tone: AppTone.brand),
      if (teacher.isActive)
        _BadgeData(icon: Icons.circle, label: 'active'.tr, tone: AppTone.success),
      if (teacher.teacherProfile?.paymentType == 'free')
        _BadgeData(icon: Icons.auto_awesome_rounded, label: 'free'.tr, tone: AppTone.neutral),
      if (teacher.teacherProfile?.teachingType == 'both')
        _BadgeData(icon: Icons.devices_rounded, label: 'live_and_recorded'.tr, tone: AppTone.neutral)
      else if (teacher.teacherProfile?.teachingType == 'live')
        _BadgeData(icon: Icons.wifi_tethering_rounded, label: 'live_only'.tr, tone: AppTone.neutral)
      else if (teacher.teacherProfile?.teachingType == 'recorded')
        _BadgeData(icon: Icons.videocam_rounded, label: 'record'.tr, tone: AppTone.neutral),
    ];

    return Wrap(
      alignment: center ? WrapAlignment.center : WrapAlignment.start,
      spacing: AppSpace.xs,
      runSpacing: AppSpace.xs,
      children: badges.map((b) => _Badge(data: b)).toList(),
    );
  }
}

class _BadgeData {
  final IconData icon;
  final String label;
  final AppTone tone;

  const _BadgeData({
    required this.icon,
    required this.label,
    required this.tone,
  });
}

/// A badge on the hero block: a paper pill on a warm hairline, the glyph in its meaning's ink, the label in ink.
class _Badge extends StatelessWidget {
  final _BadgeData data;

  const _Badge({required this.data});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minHeight: AppIconSize.xl),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.icon, color: appToneInk(context, data.tone), size: AppIconSize.xs),
          const SizedBox(width: AppSpace.xxs),
          Flexible(
            child: Text(
              data.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.label(context).copyWith(color: c.textDark),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ABOUT
// ─────────────────────────────────────────────────────────────────────────────

/// "About" in the editorial rhythm: the heading, then the card.
class _AboutSection extends StatelessWidget {
  final TeacherProfileData teacher;

  const _AboutSection({required this.teacher});

  @override
  Widget build(BuildContext context) => ParentComponent(
        featureKey: 'instructor.about',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _SectionHeader(icon: Icons.info_rounded, title: 'about'.tr),
          _AboutCard(teacher: teacher),
        ]),
      );
}

class _AboutCard extends StatefulWidget {
  final TeacherProfileData teacher;

  const _AboutCard({required this.teacher});

  @override
  State<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends State<_AboutCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final about = widget.teacher.teacherProfile?.about;
    final hasAbout = about != null && about.isNotEmpty;
    final text = hasAbout ? about : 'no_bio_hint'.tr;
    final style = AppType.body(context).copyWith(
      height: 1.7,
      color: hasAbout ? c.textDark : c.textMedium,
      fontStyle: hasAbout ? null : FontStyle.italic,
    );

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // the card grows from where it is to the whole text and back (interruptible)
          AnimatedSize(
            duration: AppMotion.of(context).slow,
            curve: AppEase.out,
            alignment: AlignmentDirectional.topStart,
            child: Text(
              text,
              maxLines: _expanded ? null : 3,
              overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (text.length > 120) ...[
            const SizedBox(height: AppSpace.xs),
            AppButton.ghost(
              size: AppButtonSize.sm,
              label: _expanded ? 'show_less'.tr : 'show_more'.tr,
              trailingIcon: _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DOCUMENTS SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _DocumentsSection extends StatelessWidget {
  final int teacherId;

  const _DocumentsSection({required this.teacherId});

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'instructor.documents',
    child: _featureContent(context),
  );

  Widget _featureContent(BuildContext context) {
    final provider = context.watch<TeacherDocumentProvider>();
    final docs = provider.publicDocs;

    if (provider.isLoadingPublic) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpace.lg),
          child: AppLoadingIndicator(),
        ),
      );
    }

    if (docs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Section header ────────────────────────────────────────────────────
        _SectionHeader(
          icon: Icons.workspace_premium_rounded,
          title: 'verified_documents'.tr,
        ),

        // ── Cards ─────────────────────────────────────────────────────────────
        ...docs.map((doc) => _DocumentCard(doc: doc)),
      ],
    );
  }
}

class _DocumentCard extends StatelessWidget {
  final TeacherDocumentModel doc;

  const _DocumentCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final well = appTintOn(context, c.primary, surface: c.cardBg);

    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Row(
              children: [
                // Icon well
                Container(
                  width: AppTouch.min - AppSpace.xxs,
                  height: AppTouch.min - AppSpace.xxs,
                  decoration: BoxDecoration(color: well, borderRadius: AppRadius.chipAll),
                  child: Icon(
                    doc.isPdf
                        ? Icons.picture_as_pdf_rounded
                        : Icons.image_rounded,
                    color: appInkOn(context, c.primary, well),
                    size: AppIconSize.md,
                  ),
                ),
                const SizedBox(width: AppSpace.sm),

                // Title + status
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(doc.title, style: AppType.bodyStrong(context)),
                      const SizedBox(height: AppSpace.xxs),
                      // the real review status: the teacher (and reviewing admins) also get pending / rejected
                      // documents here; everyone else gets approved ones only
                      Wrap(
                        spacing: AppSpace.xs,
                        runSpacing: AppSpace.xxs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          DocStatusBadge(status: doc.status),
                          Text(_fmtDate(doc.uploadedAt), style: AppType.meta(context)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Image preview (for image docs)
          if (doc.isImage)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
              child: _DocImagePreview(url: doc.fileUrl),
            ),

          // PDF chip (for pdf docs)
          if (doc.isPdf)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
              child: _PdfChip(
                fileName: doc.fileName ?? 'document.pdf',
                fileUrl: doc.fileUrl,
              ),
            ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) => AppTime.date(d);
}

/// A teacher document's review status as a small pill: approved → "Verified", pending → "Pending review",
/// rejected → "Rejected". Unknown values show as pending (never as verified).
class DocStatusBadge extends StatelessWidget {
  const DocStatusBadge({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, AppTone tone, String label) = switch (status) {
      'approved' => (Icons.verified_rounded, AppTone.success, 'verified'.tr),
      'rejected' => (Icons.cancel_rounded, AppTone.danger, 'doc_rejected'.tr),
      _ => (Icons.hourglass_top_rounded, AppTone.warning, 'doc_pending'.tr),
    };
    return AppStatusBadge(label: label, tone: tone, icon: icon, dense: true);
  }
}

// ── Tappable full-screen image preview ───────────────────────────────────────

class _DocImagePreview extends StatelessWidget {
  final String url;

  const _DocImagePreview({required this.url});

  /// The preview's height, and the broken-image placeholder's.
  static const double _height = 180, _brokenHeight = 100;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: () => _openFullscreen(context),
      child: Hero(
        tag: 'doc_$url',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: Image.network(
            url,
            width: double.infinity,
            height: _height,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: double.infinity,
              height: _brokenHeight,
              decoration: BoxDecoration(
                color: c.inputBg,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Icon(
                Icons.broken_image_rounded,
                size: AppIconSize.xl,
                color: c.textLight,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openFullscreen(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: context.colors.heroShade,
          appBar: AppBar(
            backgroundColor: context.colors.heroShade,
            automaticallyImplyLeading: false,
            leading: const AppBackButton(onHero: true),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Hero(
                tag: 'doc_$url',
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A PDF document: a paper chip on a hairline, the file glyph in the danger tone made legible, opens the file.
class _PdfChip extends StatelessWidget {
  final String fileName;
  final String fileUrl;

  const _PdfChip({required this.fileName, required this.fileUrl});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        side: BorderSide(color: c.divider, width: AppBorder.hairline),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        onTap: () async {
          await launchUrl(Uri.parse(fileUrl));
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.picture_as_pdf_rounded, size: AppIconSize.sm, color: c.blockAccentInk(c.danger, c.cardBg)),
                const SizedBox(width: AppSpace.xs),
                Flexible(
                  child: Text(fileName, style: AppType.label(context).copyWith(color: c.textDark), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RATING SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _RatingSection extends StatelessWidget {
  final TeacherProfileData teacher;
  final bool studentView;

  const _RatingSection({required this.teacher, required this.studentView});

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'instructor.rating',
    child: _featureContent(context),
  );

  Widget _featureContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          icon: Icons.star_half_rounded,
          title: 'ratings_and_reviews'.tr,
        ),
        if (studentView)
          RatingWidget(
            type: RateType.doctor,
            sourceId: teacher.id.toString(),
            canEdit: studentView,
            compact: studentView,
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION HEADER
// ─────────────────────────────────────────────────────────────────────────────

/// A section heading in the editorial rhythm (32 above, 12 under): the section face in ink after a quiet glyph —
/// no accent bar.
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(top: AppSpace.sectionHead.top, bottom: AppSpace.sectionHead.bottom),
      child: Row(
        children: [
          Icon(icon, color: c.textMedium, size: AppIconSize.md),
          const SizedBox(width: AppSpace.xs),
          Flexible(
            child: Semantics(
              header: true,
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOADING SKELETON  (unchanged from original)
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingSkeleton extends StatefulWidget {
  @override
  State<_LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<_LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _shimmer = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (_, _) {
        final color = Color.lerp(c.divider, c.inputBg, _shimmer.value)!;
        return SingleChildScrollView(
          child: Column(
            children: [
              Container(height: 300, decoration: BoxDecoration(color: color)),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: List.generate(
                        3,
                            (_) => Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            height: 80,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: c.brMedium,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      height: 100,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: c.brMedium,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      height: 180,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: c.brMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
