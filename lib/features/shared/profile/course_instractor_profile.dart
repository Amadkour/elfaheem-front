// ─────────────────────────────────────────────────────────────────────────────
// features/student/courses/components/course_instractor_profile.dart
// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/app_network_image.dart';
import '../../../utils/widget/base_page.dart';
import '../../../utils/widget/rating_widget.dart';
import '../../auth/teacher_document_model.dart';
import '../../auth/teacher_document_provider.dart';
import '../../student/models.dart';
import '../../teacher/courses/component/teacher_stats.dart';
import '../../teacher/home/home_screen.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

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

class _InstructorProfileScreenState extends State<InstructorProfileScreen>
    with TickerProviderStateMixin {
  late AnimationController _heroAnim;
  late AnimationController _contentAnim;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;

  @override
  void initState() {
    super.initState();
    _heroAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _contentAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeIn = CurvedAnimation(parent: _contentAnim, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(
      CurvedAnimation(parent: _contentAnim, curve: Curves.easeOutCubic),
    );

    _heroAnim.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _contentAnim.forward();
    });

    // Load approved public docs for this teacher
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TeacherDocumentProvider>().loadPublicDocuments(
        widget.teacher.id,
      );
    });
  }

  @override
  void dispose() {
    _heroAnim.dispose();
    _contentAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: BasePage( key: const ValueKey('course_instructor'), useWebCard: true, appBar: ScreenAppBar(title: widget.teacher.name),
        child: LayoutBuilder(
          builder: (ctx, constraints) => constraints.maxWidth > 800
              ? _WideLayout(
            teacher: widget.teacher,
            heroAnim: _heroAnim,
            fadeIn: _fadeIn,
            slideUp: _slideUp,
            studentView: widget.studentView,
            stats: widget.stats,
          )
              : _NarrowLayout(
            teacher: widget.teacher,
            heroAnim: _heroAnim,
            fadeIn: _fadeIn,
            slideUp: _slideUp,
            studentView: widget.studentView,
            stats: widget.stats,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NARROW LAYOUT
// ─────────────────────────────────────────────────────────────────────────────

class _NarrowLayout extends StatelessWidget {
  final TeacherProfileData teacher;
  final AnimationController heroAnim;
  final Animation<double> fadeIn;
  final Animation<Offset> slideUp;
  final bool studentView;
  final TeacherStats? stats;

  const _NarrowLayout({
    required this.teacher,
    required this.heroAnim,
    required this.fadeIn,
    required this.slideUp,
    required this.studentView,
    this.stats,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        _HeroSliverAppBar(teacher: teacher, anim: heroAnim),
        SliverToBoxAdapter(
          child: FadeTransition(
            opacity: fadeIn,
            child: SlideTransition(
              position: slideUp,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    _StatsRow(teacher: teacher),
                    const SizedBox(height: 24),
                    _BadgesRow(teacher: teacher),
                    const SizedBox(height: 24),
                    _AboutCard(teacher: teacher),
                    const SizedBox(height: 24),
                    _DocumentsSection(teacherId: teacher.id),
                    const SizedBox(height: 24),
                    _RatingSection(teacher: teacher, studentView: studentView),
                    const SizedBox(height: 24),
                    if (stats != null) ParentComponent(featureKey: 'instructor.teacher_stats', child: StatsRow(stats: stats!, isFull: true)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDE LAYOUT
// ─────────────────────────────────────────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  final TeacherProfileData teacher;
  final AnimationController heroAnim;
  final Animation<double> fadeIn;
  final Animation<Offset> slideUp;
  final bool studentView;
  final TeacherStats? stats;

  const _WideLayout({
    required this.teacher,
    required this.heroAnim,
    required this.fadeIn,
    required this.slideUp,
    required this.studentView,
    this.stats,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left sticky column
        SizedBox(
          width: 320,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 16,
              left: 24,
              right: 12,
              bottom: 40,
            ),
            child: FadeTransition(
              opacity: heroAnim,
              child: Column(
                children: [
                  _ProfileCard(teacher: teacher),
                  const SizedBox(height: 16),
                  _BadgesRow(teacher: teacher),
                ],
              ),
            ),
          ),
        ),

        // Right scrollable column
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 0, 24, 40),
            child: FadeTransition(
              opacity: fadeIn,
              child: SlideTransition(
                position: slideUp,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: MediaQuery.of(context).padding.top + 16),
                    _SectionHeader(
                      icon: Icons.info_outline_rounded,
                      title: 'about'.tr,
                    ),
                    const SizedBox(height: 12),
                    _AboutCard(teacher: teacher),
                    const SizedBox(height: 28),
                    _StatsRow(teacher: teacher),
                    const SizedBox(height: 28),
                    _DocumentsSection(teacherId: teacher.id),
                    const SizedBox(height: 28),
                    _RatingSection(teacher: teacher, studentView: studentView),
                    const SizedBox(height: 28),
                    if (stats != null) ParentComponent(featureKey: 'instructor.teacher_stats', child: StatsRow(stats: stats!, isFull: true)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HERO SLIVER APP BAR
// ─────────────────────────────────────────────────────────────────────────────

class _HeroSliverAppBar extends StatelessWidget {
  final TeacherProfileData teacher;
  final AnimationController anim;

  const _HeroSliverAppBar({required this.teacher, required this.anim});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      stretch: true,
      automaticallyImplyLeading: false,
      backgroundColor: c.cardBg,
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [
          StretchMode.zoomBackground,
          StretchMode.blurBackground,
        ],
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: [context.colors.primary, context.colors.heroEnd(context.colors.primary)],
                ),
              ),
            ),
            Positioned(
              top: -40,
              right: -40,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colors.onHero.withValues(alpha: 0.06),
                ),
              ),
            ),
            Positioned(
              bottom: 40,
              left: -60,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colors.onHero.withValues(alpha: 0.04),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      c.background.withValues(alpha: 0.9),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 50,
              left: 20,
              right: 20,
              child: FadeTransition(
                opacity: anim,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    InstructorAvatar(
                      teacher: teacher,
                      size: 80,
                      canOpen: false,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  teacher.name,
                                  style: TextStyle(
                                    color: context.colors.onHero,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.5,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                              if (teacher.isVerified) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.verified_rounded,
                                  color: context.colors.onHero,
                                  size: 18,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (AppConfig.lang == 'ar'
                                ? teacher
                                .teacherProfile
                                ?.specialization
                                ?.nameAr
                                : teacher
                                .teacherProfile
                                ?.specialization
                                ?.nameEn) ??
                                '',
                            style: TextStyle(
                              color: context.colors.onHero.withValues(alpha: 0.75),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE CARD  (wide left panel)
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final TeacherProfileData teacher;

  const _ProfileCard({required this.teacher});

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'instructor.profile_card',
    child: _featureContent(context),
  );

  Widget _featureContent(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [c.primary, c.heroEnd(c.primary)],
        ),
        borderRadius: c.brLarge,
        boxShadow: [
          BoxShadow(
            color: context.colors.primary.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          InstructorAvatar(teacher: teacher, size: 96, canOpen: false),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                teacher.name,
                style: TextStyle(
                  color: context.colors.onHero,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              if (teacher.isVerified) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.verified_rounded,
                  color: context.colors.onHero,
                  size: 18,
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: context.colors.onHero.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              teacher.teacherProfile?.teachingType.toUpperCase() ??
                  'teacher'.tr.toUpperCase(),
              style: TextStyle(
                color: context.colors.onHero,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AVATAR  (unchanged from original)
// ─────────────────────────────────────────────────────────────────────────────

class InstructorAvatar extends StatelessWidget {
  final TeacherProfileData teacher;
  final double size;
  final bool canOpen;
  final bool showTitle;
  final bool showImage;

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
      decoration: !canOpen
          ? BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: context.colors.background, width: 3),
        boxShadow: [
          BoxShadow(
            color: context.colors.heroShade.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      )
          : BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: context.colors.background, width: 1),
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
              style: TextStyle(
                fontFamily: AppFonts.family,
                color: context.colors.primary,
                fontSize: size * 0.35,
                fontWeight: FontWeight.w600,
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

  Widget _featureContent(BuildContext context) {
    final tp = teacher.teacherProfile;
    return Row(
      children: [
        _StatTile(
          icon: Icons.workspace_premium_rounded,
          value: tp != null ? '${tp.experienceYears}y' : '—',
          label: 'experience'.tr,
          color: context.colors.warning,
        ),
        const SizedBox(width: 12),
        _StatTile(
          icon: Icons.payments_outlined,
          value: tp?.paymentType.toUpperCase() ?? '—',
          label: 'pricing'.tr,
          color: context.colors.accent2,
        ),
        const SizedBox(width: 12),
        _StatTile(
          icon: Icons.calendar_today_outlined,
          value: teacher.createdAt.year.toString(),
          label: 'joined'.tr,
          color: context.colors.primary,
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: c.brMedium,
          boxShadow: c.cardShadow,
          border: Border.all(color: c.divider.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 8),
            Text(value, style: c.bodyBold.copyWith(fontSize: 15, height: 1)),
            const SizedBox(height: 3),
            Text(
              label,
              style: c.caption.copyWith(fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BADGES ROW  (unchanged from original)
// ─────────────────────────────────────────────────────────────────────────────

class _BadgesRow extends StatelessWidget {
  final TeacherProfileData teacher;

  const _BadgesRow({required this.teacher});

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'instructor.badges',
    child: _featureContent(context),
  );

  Widget _featureContent(BuildContext context) {
    final badges = <_BadgeData>[
      if (teacher.isVerified)
        _BadgeData(
          icon: Icons.verified_rounded,
          label: 'verified'.tr,
          color: context.colors.primary,
        ),
      if (teacher.isActive)
        _BadgeData(
          icon: Icons.circle,
          label: 'active'.tr,
          color: context.colors.success,
        ),
      if (teacher.teacherProfile?.paymentType == 'free')
        _BadgeData(
          icon: Icons.auto_awesome_rounded,
          label: 'free'.tr,
          color: Color.lerp(context.colors.warning, context.colors.danger, 0.5)!,
        ),
      if (teacher.teacherProfile?.teachingType == 'both')
        _BadgeData(
          icon: Icons.devices_rounded,
          label: 'live_and_recorded'.tr,
          color: context.colors.purple,
        )
      else if (teacher.teacherProfile?.teachingType == 'live')
        _BadgeData(
          icon: Icons.wifi_tethering_rounded,
          label: 'live_only'.tr,
          color: context.colors.danger,
        )
      else if (teacher.teacherProfile?.teachingType == 'recorded')
          _BadgeData(
            icon: Icons.videocam_outlined,
            label: 'record'.tr,
            color: context.colors.accent2,
          ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: badges.map((b) => _Badge(data: b)).toList(),
    );
  }
}

class _BadgeData {
  final IconData icon;
  final String label;
  final Color color;

  const _BadgeData({
    required this.icon,
    required this.label,
    required this.color,
  });
}

class _Badge extends StatelessWidget {
  final _BadgeData data;

  const _Badge({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: data.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: data.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.icon, color: data.color, size: 12),
          const SizedBox(width: 5),
          Text(
            data.label,
            style: TextStyle(
              color: data.color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ABOUT CARD  (unchanged from original)
// ─────────────────────────────────────────────────────────────────────────────

class _AboutCard extends StatefulWidget {
  final TeacherProfileData teacher;

  const _AboutCard({required this.teacher});

  @override
  State<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends State<_AboutCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'instructor.about',
    child: _featureContent(context),
  );

  Widget _featureContent(BuildContext context) {
    final c = context.colors;
    final about = widget.teacher.teacherProfile?.about;
    final hasAbout = about != null && about.isNotEmpty;
    final text = hasAbout ? about : 'no_bio_hint'.tr;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: c.brMedium,
        boxShadow: c.cardShadow,
        border: Border.all(color: c.divider.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedCrossFade(
            firstChild: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: c.body.copyWith(
                fontSize: 13,
                height: 1.7,
                color: hasAbout ? null : c.secondText,
                fontStyle: hasAbout ? null : FontStyle.italic,
              ),
            ),
            secondChild: Text(
              text,
              style: c.body.copyWith(
                fontSize: 13,
                height: 1.7,
                color: hasAbout ? null : c.secondText,
                fontStyle: hasAbout ? null : FontStyle.italic,
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
          ),
          if (text.length > 120) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Text(
                _expanded ? 'show_less'.tr : 'show_more'.tr,
                style: TextStyle(
                  color: context.colors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DOCUMENTS SECTION  ← NEW
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
          padding: EdgeInsets.symmetric(vertical: 20),
          child: AppLoadingIndicator(),
        ),
      );
    }

    if (docs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ────────────────────────────────────────────────────
        _SectionHeader(
          icon: Icons.workspace_premium_outlined,
          title: 'verified_documents'.tr,
        ),
        const SizedBox(height: 14),

        // ── Cards grid ────────────────────────────────────────────────────────
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: c.cardShadow,
        border: Border.all(color: c.divider.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Icon bubble
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        context.colors.primary.withValues(alpha: 0.15),
                        context.colors.primary.withValues(alpha: 0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    doc.isPdf
                        ? Icons.picture_as_pdf_rounded
                        : Icons.image_outlined,
                    color: context.colors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),

                // Title + verified badge
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(doc.title, style: c.bodyBold.copyWith(fontSize: 13)),
                      const SizedBox(height: 4),
                      // the real review status: the teacher (and reviewing admins) also get pending / rejected
                      // documents here; everyone else gets approved ones only
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          DocStatusBadge(status: doc.status),
                          Text(
                            _fmtDate(doc.uploadedAt),
                            style: c.caption.copyWith(fontSize: 10),
                          ),
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
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: _DocImagePreview(url: doc.fileUrl),
            ),

          // PDF chip (for pdf docs)
          if (doc.isPdf)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
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
    final c = context.colors;
    final (IconData icon, Color color, String label) = switch (status) {
      'approved' => (Icons.verified_rounded, c.success, 'verified'.tr),
      'rejected' => (Icons.cancel_outlined, c.danger, 'doc_rejected'.tr),
      _ => (Icons.hourglass_top_rounded, c.warning, 'doc_pending'.tr),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: AppFonts.display, fontSize: 10, fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tappable full-screen image preview ───────────────────────────────────────

class _DocImagePreview extends StatelessWidget {
  final String url;

  const _DocImagePreview({required this.url});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: () => _openFullscreen(context),
      child: Hero(
        tag: 'doc_$url',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            url,
            width: double.infinity,
            height: 180,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: double.infinity,
              height: 100,
              decoration: BoxDecoration(
                color: c.inputBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.broken_image_outlined,
                size: 32,
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
            iconTheme: IconThemeData(color: context.colors.onHero),
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

class _PdfChip extends StatelessWidget {
  final String fileName;
  final String fileUrl;

  const _PdfChip({required this.fileName, required this.fileUrl});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: () async {
        await launchUrl(Uri.parse(fileUrl));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: context.colors.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: context.colors.danger.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.picture_as_pdf_rounded,
              size: 16,
              color: context.colors.danger,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                fileName,
                style: c.body.copyWith(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RATING SECTION  (unchanged from original)
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          icon: Icons.star_half_rounded,
          title: 'ratings_and_reviews'.tr,
        ),
        const SizedBox(height: 12),
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

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Container(
          width: 3,
          height: 20,
          decoration: BoxDecoration(
            gradient: c.primaryGradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, color: context.colors.primary, size: 18),
        const SizedBox(width: 8),
        Text(title, style: c.h4),
      ],
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
