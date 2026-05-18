import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/category/categories_provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart';
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_network_image.dart';
import '../../../utils/widget/rating_widget.dart';
import '../../student/models.dart';
import '../../teacher/courses/component/teacher_stats.dart';
import '../../teacher/home/home_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class InstructorProfileScreen extends StatefulWidget {
  final TeacherProfileData teacher;
  final TeacherStats? stats;
  final bool studentView;

  const InstructorProfileScreen(
      {super.key, required this.teacher, this.studentView = true, this.stats});

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
        vsync: this, duration: const Duration(milliseconds: 700));
    _contentAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));

    _fadeIn = CurvedAnimation(parent: _contentAnim, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _contentAnim, curve: Curves.easeOutCubic));

    _heroAnim.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _contentAnim.forward();
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
      child: BasePage(
        useWebCard: true,
        appBar: ScreenAppBar(title: widget.teacher.name),
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            return constraints.maxWidth > 800
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
                  );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NARROW LAYOUT (Mobile)
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
                    _ContactCard(teacher: teacher),
                    const SizedBox(height: 24),
                    _AboutCard(teacher: teacher),
                    const SizedBox(height: 24),
                    _RatingSection(
                      teacher: teacher,
                      studentView: studentView,
                    ),
                    const SizedBox(height: 24),
                    if (stats != null)
                      StatsRow(
                        stats: stats!,
                        isFull: true,
                      ),
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
// WIDE LAYOUT (Web / Tablet)
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
        // Left: sticky profile card
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
                  const SizedBox(height: 16),
                  _ContactCard(teacher: teacher),
                ],
              ),
            ),
          ),
        ),

        // Right: scrollable content
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
                    _RatingSection(
                      teacher: teacher,
                      studentView: studentView,
                    ),
                    const SizedBox(height: 28),
                    StatsRow(stats: stats!, isFull: true)
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
// HERO SLIVER APP BAR  (mobile)
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
            // Background — mesh gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.primary,
                    AppTheme.primary.withValues(alpha: 0.7),
                    AppTheme.accent,
                  ],
                ),
              ),
            ),
            // Decorative circles
            Positioned(
              top: -40,
              right: -40,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
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
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),
            // Bottom gradient fade
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
            // Avatar + name
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
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                              if (teacher.isVerified) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.verified_rounded,
                                    color: Colors.white, size: 18),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (teacher.teacherProfile?.specialization?.name??''),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
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
// PROFILE CARD (wide layout left panel)
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final TeacherProfileData teacher;

  const _ProfileCard({required this.teacher});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primary, AppTheme.accent],
        ),
        borderRadius: c.brLarge,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          InstructorAvatar(
            teacher: teacher,
            size: 96,
            canOpen: false,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                teacher.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              if (teacher.isVerified) ...[
                const SizedBox(width: 6),
                const Icon(Icons.verified_rounded,
                    color: Colors.white, size: 18),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              teacher.teacherProfile?.teachingType.toUpperCase() ??
                  'teacher'.tr.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
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
// AVATAR
// ─────────────────────────────────────────────────────────────────────────────

class InstructorAvatar extends StatelessWidget {
  final TeacherProfileData teacher;
  final double size;
  final bool canOpen;
  final bool showTitle;

  const InstructorAvatar(
      {super.key,
      required this.teacher,
      required this.size,
      required this.canOpen,
      this.showTitle = false});

  @override
  Widget build(BuildContext context) {
    Widget w = Container(
      width: size,
      height: size,
      decoration: !canOpen
          ? BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: context.colors.background, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
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
        child: teacher.imageUrl != null
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
                color: AppTheme.primary.withValues(alpha: 0.2),
                child: Center(
                  child: Text(
                    teacher.initials,
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontSize: size * 0.35,
                      fontWeight: FontWeight.w800,
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
          w,
          SizedBox(
            width: 5,
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  teacher.name,
                  style: context.colors.navLabelSelected
                      .copyWith(height: 1, fontSize: size / 3),
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                ),
                Text(
                  '${teacher.teacherProfile!.experienceYears} ${'experience'.tr}',
                  style: context.colors.navLabelUnselected
                      .copyWith(height: 1, fontSize: size / 3.5),
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
          )
        ],
      );
    }
    if (canOpen) {
      return InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InstructorProfileScreen(
                teacher: teacher,
              ),
            ),
          );
        },
        child: w,
      );
    } else {
      return w;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATS ROW
// ─────────────────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final TeacherProfileData teacher;

  const _StatsRow({required this.teacher});

  @override
  Widget build(BuildContext context) {
    final tp = teacher.teacherProfile;
    final joinYear = teacher.createdAt.year.toString();
    final exp = tp != null ? '${tp.experienceYears}y' : '—';

    return Row(
      children: [
        _StatTile(
          icon: Icons.workspace_premium_rounded,
          value: exp,
          label: 'experience'.tr,
          color: const Color(0xFFFFB830),
        ),
        const SizedBox(width: 12),
        _StatTile(
          icon: Icons.payments_outlined,
          value: tp?.paymentType.toUpperCase() ?? '—',
          label: 'pricing'.tr,
          color: const Color(0xFF00D4AA),
        ),
        const SizedBox(width: 12),
        _StatTile(
          icon: Icons.calendar_today_outlined,
          value: joinYear,
          label: 'joined'.tr,
          color: AppTheme.primary,
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
            Text(
              value,
              style: c.bodyBold.copyWith(fontSize: 15, height: 1),
            ),
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
// BADGES ROW
// ─────────────────────────────────────────────────────────────────────────────

class _BadgesRow extends StatelessWidget {
  final TeacherProfileData teacher;

  const _BadgesRow({required this.teacher});

  @override
  Widget build(BuildContext context) {
    final badges = <_BadgeData>[
      if (teacher.isVerified)
        _BadgeData(
          icon: Icons.verified_rounded,
          label: 'verified'.tr,
          color: const Color(0xFF3B82F6),
        ),
      if (teacher.isActive)
        _BadgeData(
          icon: Icons.circle,
          label: 'active'.tr,
          color: const Color(0xFF22C55E),
        ),
      if (teacher.teacherProfile?.paymentType == 'free')
        _BadgeData(
          icon: Icons.auto_awesome_rounded,
          label: 'free'.tr,
          color: const Color(0xFFFF6B35),
        ),
      if (teacher.teacherProfile?.teachingType == 'both')
        _BadgeData(
          icon: Icons.devices_rounded,
          label: 'live_and_recorded'.tr,
          color: const Color(0xFF8B5CF6),
        )
      else if (teacher.teacherProfile?.teachingType == 'live')
        _BadgeData(
          icon: Icons.wifi_tethering_rounded,
          label: 'live_only'.tr,
          color: const Color(0xFFEF4444),
        )
      else if (teacher.teacherProfile?.teachingType == 'recorded')
        _BadgeData(
          icon: Icons.videocam_outlined,
          label: 'record'.tr,
          color: const Color(0xFF06B6D4),
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

  const _BadgeData(
      {required this.icon, required this.label, required this.color});
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
// CONTACT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _ContactCard extends StatelessWidget {
  final TeacherProfileData teacher;

  const _ContactCard({required this.teacher});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: c.brMedium,
        boxShadow: c.cardShadow,
        border: Border.all(color: c.divider.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          _ContactRow(
            icon: Icons.email_outlined,
            label: 'email_label'.tr,
            value: teacher.gmail,
            color: AppTheme.primary,
          ),
          if (teacher.phone != null) ...[
            Divider(height: 1, color: c.divider),
            _ContactRow(
              icon: Icons.phone_outlined,
              label: 'phone_label'.tr,
              value: teacher.phone!,
              color: const Color(0xFF22C55E),
            ),
          ],
          if (teacher.country != null) ...[
            Divider(height: 1, color: c.divider),
            _ContactRow(
              icon: Icons.location_on_outlined,
              label: 'country'.tr,
              value: teacher.country!,
              color: const Color(0xFFFF6B35),
            ),
          ],
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 15),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: c.caption.copyWith(fontSize: 10, letterSpacing: 0.5)),
              const SizedBox(height: 1),
              Text(value,
                  style: c.body
                      .copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ABOUT CARD
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
  Widget build(BuildContext context) {
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
              onTap: () {
                if (mounted) setState(() => _expanded = !_expanded);
              },
              child: Text(
                _expanded ? 'show_less'.tr : 'show_more'.tr,
                style: TextStyle(
                  color: AppTheme.accent,
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
// RATING SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _RatingSection extends StatelessWidget {
  final TeacherProfileData teacher;
  final bool studentView;

  const _RatingSection({required this.teacher, required this.studentView});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          icon: Icons.star_half_rounded,
          title: 'ratings_and_reviews'.tr,
        ),
        const SizedBox(height: 12),
        if(studentView)
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
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, color: AppTheme.primary, size: 18),
        const SizedBox(width: 8),
        Text(title, style: c.h4),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOADING SKELETON
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
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
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
      builder: (_, __) {
        final color = Color.lerp(c.divider, c.inputBg, _shimmer.value)!;
        return SingleChildScrollView(
          child: Column(
            children: [
              Container(
                height: 300,
                decoration: BoxDecoration(color: color),
              ),
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
                      decoration:
                          BoxDecoration(color: color, borderRadius: c.brMedium),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      height: 180,
                      decoration:
                          BoxDecoration(color: color, borderRadius: c.brMedium),
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
