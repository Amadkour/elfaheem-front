/// courses/details/course_detail_screen.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/teacher/sessions/sessions_provider.dart';
import 'package:provider/provider.dart';
import '../../../../config/theme/app_theme.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../utils/widget/app_bar.dart';
import '../../../../utils/widget/app_network_image.dart';
import '../../../../utils/widget/base_page.dart';
import '../../../../utils/widget/rating_widget.dart';
import '../../../shared/profile/compalints/complaint_provider.dart';
import '../../../shared/profile/compalints/new_complaint_screen.dart';
import '../../../teacher/sessions/components/course_hero.dart';
import '../../analysis/exam/student_exam_provider.dart';
import '../../enrollment/enrollment_provider.dart';
import '../../enrollment/enrollment_screen.dart';
import '../../models.dart';
import 'components/app_responsive.dart';
import 'components/content.dart';
import 'components/stat_chip.dart';
import 'course_detail_provider.dart';

class CourseDetailScreen extends StatefulWidget {
  const CourseDetailScreen({super.key, required this.course});

  final CourseModel course;

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  @override
  void initState() {
    context.read<CourseDetailProvider>().course = widget.course;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      context.read<CourseDetailProvider>().init(widget.course);
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    CourseDetailProvider provider = context.watch<CourseDetailProvider>();
    final isWide = context.showSidebar;

    return BasePage(
      useWebCard: true,
      maxWith: 1000,
      child: provider.isLoading
          ? Center(
              child: SizedBox(
                width: context.width / 5,
                height: context.width / 5,
                child: CircularProgressIndicator(
                  color: context.colors.primary,
                  strokeWidth: context.width / 80,
                ),
              ),
            )
          : isWide
          ? _WebDetail(provider)
          : _MobileDetail(provider),
    );
  }
}

// ── Mobile layout ─────────────────────────────────────────────────────────────

class _MobileDetail extends StatelessWidget {
  const _MobileDetail(this.provider);

  final CourseDetailProvider provider;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (BuildContext context) {
        return StudentExamProvider();
      },
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                color: context.colors.primary,
                onRefresh: () => provider.refresh(),
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: BoxBorder.all(color: Colors.black),
                        ),
                        child: CourseHero(
                          course: provider.course.toTeacherModel,
                          onBack: () => Navigator.maybePop(context),
                          onRefresh: () => provider.refresh(),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(child: _CourseMeta()),
                    if (provider.course.isEnrolled) ...[
                      SliverToBoxAdapter(child: _TabBarWidget()),
                      const SliverToBoxAdapter(child: SizedBox(height: 4)),
                      SliverToBoxAdapter(
                        child: ChangeNotifierProvider(
                          create: (BuildContext context) =>
                              TeacherCourseScreenProvider(
                                initialCourse: provider.course.toTeacherModel,
                              ),
                          child: TabContent(
                            activeTab: provider.activeTab,
                            courseId: provider.course.id,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            _EnrollButton(),
          ],
        ),
      ),
    );
  }
}

// ── Web layout: two-column ────────────────────────────────────────────────────

class _WebDetail extends StatelessWidget {
  const _WebDetail(this.provider);

  final CourseDetailProvider provider;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: Breakpoints.contentMax,
                ),
                child: RefreshIndicator(
                  color: context.colors.primary,
                  onRefresh: () =>
                      context.read<CourseDetailProvider>().refresh(),
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: CourseHero(
                                      course: provider.course.toTeacherModel,
                                      onBack: () => Navigator.maybePop(context),
                                      onRefresh: () => provider.refresh(),
                                      onLike: provider.toggleFavorite,
                                      isLike: provider.course.isFavorite,
                                    ),
                                  ),
                                  // Stars row
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Spacer(),

                                      Container(
                                        margin: EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          gradient:
                                              context.colors.accentGradient,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: IconButton(
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    ChangeNotifierProvider(
                                                      create: (_) =>
                                                          ComplaintProvider(),
                                                      child: NewComplaintScreen(
                                                        courseTitle: provider
                                                            .course
                                                            .title,
                                                        courseId:
                                                            provider.course.id,
                                                      ),
                                                    ),
                                              ),
                                            );
                                          },
                                          icon: Icon(
                                            Icons.headset_mic_rounded,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                    ],
                                  ),

                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      RatingWidget(
                                        type: RateType.course,
                                        sourceId: provider.course.id,
                                        canEdit: provider.course.isEnrolled,
                                      ),
                                      Spacer(),

                                      if (provider.course.category != null) ...[
                                        _HeroBadge(
                                          AppConfig.lang == 'ar'
                                              ? provider.course.category!.nameAr
                                              : provider
                                                    .course
                                                    .category!
                                                    .nameEn,
                                        ),
                                        //const SizedBox(height: 8),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // Right: sticky sidebar
                            SizedBox(width: 20),
                            SizedBox(
                              width: 260,
                              child: SingleChildScrollView(
                                child: _WebSidebar(provider: provider),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SliverToBoxAdapter(child: _CourseMeta()),
                      SliverToBoxAdapter(child: _TabBarWidget()),
                      const SliverToBoxAdapter(child: SizedBox(height: 4)),
                      SliverToBoxAdapter(
                        child: ChangeNotifierProvider(
                          create: (BuildContext context) =>
                              TeacherCourseScreenProvider(
                                initialCourse: provider.course.toTeacherModel,
                              ),
                          child: TabContent(
                            activeTab: provider.activeTab,
                            courseId: provider.course.id,
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 32)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WebSidebar extends StatelessWidget {
  final CourseDetailProvider provider;

  const _WebSidebar({required this.provider});

  @override
  Widget build(BuildContext context) {
    final c = provider.course;
    final isEnrolled = provider.course.isEnrolled;

    return Padding(
      padding: const EdgeInsets.only(left: 0, right: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Price card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.colors.cardBg,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.price == 0
                      ? 'مجاني تماماً'
                      : '\$ ${c.price.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: c.price == 0
                        ? const Color(0xFF0F6E56)
                        : context.colors.primary,
                    fontFamily: 'bahji',
                  ),
                ),
                const SizedBox(height: 16),
                isEnrolled ? Text('you_are_enrolled'.tr) : _EnrollButton(),
                const SizedBox(height: 16),
                _WebCourseFacts(course: c),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WebCourseFacts extends StatelessWidget {
  final CourseModel course;

  const _WebCourseFacts({required this.course});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Fact(
          icon: Icons.people_alt_rounded,
          label: '${course.studentsCount} طالب مسجّل',
          color: context.colors.primary,
        ),
        _Fact(
          icon: Icons.video_library_rounded,
          label: '${course.sessionsCount} محاضرة',
          color: const Color(0xFF185FA5),
        ),
        _Fact(
          icon: Icons.access_time_rounded,
          label: '${course.totalHours.toStringAsFixed(0)} ساعة إجمالية',
          color: const Color(0xFFBA7517),
        ),
        if (course.certificates.isNotEmpty)
          _Fact(
            icon: Icons.workspace_premium_rounded,
            label: 'شهادة إتمام معتمدة',
            color: context.colors.accent,
          ),
        if (course.type == 'live')
          _Fact(
            icon: Icons.sensors_rounded,
            label: 'بث مباشر',
            color: context.colors.danger,
          )
        else
          _Fact(
            icon: Icons.play_circle_outline_rounded,
            label: 'كورس مسجّل',
            color: context.colors.primary,
          ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Fact({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: context.colors.body.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _HeroBadge extends StatelessWidget {
  final String label;

  const _HeroBadge(this.label);

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      color: context.colors.textLight,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      fontFamily: 'bahji',
    ),
  );
}

class _FavButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isFav = context.watch<CourseDetailProvider>().course.isFavorite;
    return _CircleIconBtn(
      icon: isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      iconColor: isFav ? context.colors.danger : null,
      onTap: () => context.read<CourseDetailProvider>().toggleFavorite(),
    );
  }
}

class _CircleIconBtn extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final VoidCallback onTap;

  const _CircleIconBtn({
    required this.icon,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, size: 20, color: iconColor ?? context.colors.textDark),
    ),
  );
}

// ── Meta section ──────────────────────────────────────────────────────────────

class _CourseMeta extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.watch<CourseDetailProvider>().course;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 18),

          // Stat chips — 4-col grid
          SizedBox(
            height: context.height / 10,
            child: Row(
              children: [
                StatChip(
                  icon: Icons.people_alt_rounded,
                  label: '${c.studentsCount} ${'student'.tr}',
                  iconColor: context.colors.primary,
                  maxHeight: context.height / 10,
                ),
                StatChip(
                  icon: Icons.video_library_rounded,
                  label: '${c.sessionsCount} ${'session'.tr}',
                  iconColor: const Color(0xFF185FA5),
                  iconBg: const Color(0xFFE6F1FB),
                  maxHeight: context.height / 10,
                ),
                StatChip(
                  icon: Icons.access_time_rounded,
                  label: '${c.totalHours.toStringAsFixed(0)} ${'hour'.tr}',
                  iconColor: const Color(0xFFBA7517),
                  iconBg: const Color(0xFFFAEEDA),
                  maxHeight: context.height / 10,
                ),
                if (c.certificates.isNotEmpty)
                  StatChip(
                    icon: Icons.workspace_premium_rounded,
                    label: 'شهادة إتمام',
                    iconColor: context.colors.accent,
                    iconBg: Color(0xFFFAEEDA),
                    maxHeight: context.height / 10,
                  )
                else
                  StatChip(
                    icon: c.type == 'live'
                        ? Icons.sensors_rounded
                        : Icons.play_circle_outline_rounded,
                    label: c.type == 'live' ? 'مباشر' : 'مسجّل',
                    iconColor: c.type == 'live'
                        ? context.colors.danger
                        : context.colors.primary,
                    maxHeight: context.height / 10,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab bar ───────────────────────────────────────────────────────────────────

class _TabBarWidget extends StatelessWidget {
  static final _tabs = [
    (CourseDetailTab.live, 'live'.tr, Icons.sensors_rounded),
    (CourseDetailTab.lessons, 'sessions'.tr, Icons.play_lesson_rounded),
    (CourseDetailTab.exam, 'exams'.tr, Icons.assignment),
    (CourseDetailTab.about, 'course_details'.tr, Icons.info_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseDetailProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: _tabs.map((t) {
            final (tab, label, icon) = t;
            final isActive = provider.activeTab == tab;

            return Expanded(
              child: GestureDetector(
                onTap: () => context.read<CourseDetailProvider>().setTab(tab),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  margin: EdgeInsets.only(left: 3, right: 3, bottom: 8),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isActive
                            ? context.colors.primary
                            : context.colors.textLight,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 14,
                        color: isActive
                            ? context.colors.primary
                            : context.colors.textLight,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        label,
                        style: context.colors.label.copyWith(
                          color: isActive
                              ? context.colors.primary
                              : context.colors.textLight,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Enroll button ─────────────────────────────────────────────────────────────

class _EnrollButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = context.watch<CourseDetailProvider>();
    final isWide = context.showSidebar;

    if (p.course.isEnrolled) {
      return _EnrollWrap(
        isWide: isWide,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: context.colors.accent2.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: context.colors.accent2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: context.colors.accent2,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'تم الاشتراك بنجاح',
                style: TextStyle(
                  color: context.colors.accent2,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  fontFamily: 'bahji',
                ),
              ),
            ],
          ),
        ),
      );
    }

    final label = p.course.price == 0
        ? 'سجّل مجاناً الآن'
        : 'انضم الآن — \$ ${p.course.price.toStringAsFixed(2)}';

    return _EnrollWrap(
      isWide: isWide,
      child: GestureDetector(
        onTap: p.course.isEnrolled
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChangeNotifierProvider(
                    create: (_) => EnrollmentProvider(p.course),
                    child: EnrollmentScreen(course: p.course),
                  ),
                ),
              ),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            gradient: context.colors.primaryGradient,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: context.colors.primary.withValues(alpha: 0.42),
                blurRadius: 22,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Center(
            child: p.course.isEnrolled
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      fontFamily: 'bahji',
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _EnrollWrap extends StatelessWidget {
  final Widget child;
  final bool isWide;

  const _EnrollWrap({required this.child, required this.isWide});

  @override
  Widget build(BuildContext context) => isWide
      ? child
      : Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: SafeArea(top: false, child: child),
        );
}
