import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/category/categories_provider.dart';
import 'package:flutter_education_app/features/category/categories_screen.dart';
import 'package:flutter_education_app/features/student/courses/details/course_detail_screen.dart';
import 'package:flutter_education_app/features/student/home/home_provider.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart';
import '../../../config/app_config.dart' as Helpers;
import '../../../config/theme/app_theme.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/base_page.dart';
import '../../teacher/home/home_screen.dart';
import '../courses/list/courses_list_screen.dart';
import '../models.dart';
import 'component/category_row.dart';
import 'component/course_row.dart';
import 'component/home_section_header.dart';
import 'component/instractor_roe.dart';
import 'component/search_bar_icon.dart';
import 'component/top_bar.dart';
import '../../teacher/schedules/schedules_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _CoursesShimmer extends StatelessWidget {
  const _CoursesShimmer();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: Shimmer(width: context.width, height: 50, radius: 10),
      ),
      const SizedBox(height: 20),
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: Shimmer(width: context.width, height: 150, radius: 20),
      ),
      Expanded(
        flex: 1,
        child: ListView.separated(
          scrollDirection: Axis.vertical,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: 3,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (_, __) =>
          const Shimmer(width: 50, height: 50, radius: 25),
        ),
      ),
      Expanded(
        flex: 3,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: 3,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, __) =>
                Shimmer(width: context.width / 5, height: context.height / 5),
          ),
        ),
      ),
      const SizedBox(height: 20),
      Expanded(
        flex: 3,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: 3,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (_, __) =>
              Shimmer(width: context.width / 5, height: context.height / 5),
        ),
      ),
      Expanded(
        flex: 1,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: ListView.separated(
            scrollDirection: Axis.vertical,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: 3,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, __) =>
            const Shimmer(width: 50, height: 50, radius: 25),
          ),
        ),
      ),
    ],
  );
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<HomeProvider>().init(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeProvider>(builder: (context, provider, child) {
      return BasePage(
        useWebCard: true,
        child: SafeArea(
          child: Center(
            child: provider.isLoading
                ? const _CoursesShimmer()
                : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // ── Top bar ──────────────────────────────────────────
                  SliverToBoxAdapter(child: TopBar()),

                  // ── Search bar ───────────────────────────────────────
                  SliverToBoxAdapter(
                      child: SearchBarIcon(
                        courses: provider.otherCourses,
                      )),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: 24)),

                  // ── Upcoming session banner ──────────────────────────
                  const SliverToBoxAdapter(
                      child: _UpcomingBanner()),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: 28)),

                  // ── Categories ───────────────────────────────────────
                  if (context
                      .read<CategoriesProvider>()
                      .categories
                      .length >
                      5)
                    SliverToBoxAdapter(
                      child: SectionHeader(
                        title: 'categories'.tr,
                        actionLabel: 'show_more'.tr,
                        onAction: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) =>
                              const CategoriesScreen()),
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: 16)),
                  const SliverToBoxAdapter(child: CategoriesRow()),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: 28)),

                  // ── My Courses ───────────────────────────────────────
                  if (provider.myCourses.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: SectionHeader(
                        title: 'my_courses'.tr,
                        actionLabel: 'show_more'.tr,
                        onAction: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => CoursesListScreen(
                                homeCourses: provider.myCourses,
                                forMyCourses: true,
                              )),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(
                        child: SizedBox(height: 16)),
                    SliverToBoxAdapter(
                      child: CoursesRow(
                        courses: provider.myCourses,
                        pageName: 'home-my-courses',
                        isTeacher: false,
                        onTap: (CourseModel c) {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      CourseDetailScreen(course: c)));
                        },
                      ),
                    ),
                  ],

                  // ── Other Courses ────────────────────────────────────
                  if (provider.otherCourses.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                        child: SizedBox(height: 28)),
                    SliverToBoxAdapter(
                      child: SectionHeader(
                        title: 'other_courses'.tr,
                        actionLabel: 'show_more'.tr,
                        onAction: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => CoursesListScreen(
                                homeCourses: provider.otherCourses,
                                forMyCourses: false,
                              )),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(
                        child: SizedBox(height: 16)),
                    SliverToBoxAdapter(
                        child: CoursesRow(
                          pageName: 'home-other-courses',
                          courses: provider.otherCourses,
                          isTeacher: false,
                          onTap: (CourseModel c) {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        CourseDetailScreen(course: c)));
                          },
                        )),
                  ],
                  const SliverToBoxAdapter(
                      child: SizedBox(height: 28)),

                  // ── Best teachers ────────────────────────────────────
                  SliverToBoxAdapter(
                    child: SectionHeader(
                      title: 'best_teachers'.tr,
                      actionLabel: 'show_more'.tr,
                      onAction: () {},
                    ),
                  ),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: 16)),
                  SliverToBoxAdapter(child: InstructorsRow()),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: 40)),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Upcoming session banner — redesigned premium
// ─────────────────────────────────────────────────────────────────────────────

class _UpcomingBanner extends StatefulWidget {
  const _UpcomingBanner();

  @override
  State<_UpcomingBanner> createState() => _UpcomingBannerState();
}

class _UpcomingBannerState extends State<_UpcomingBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _bellCtrl;
  late Animation<double> _bellAnim;

  final StudentSchedulesProvider _schedProv = StudentSchedulesProvider();
  Timer? _tickTimer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    _bellCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _bellAnim = Tween<double>(begin: -200, end: 200).animate(
      CurvedAnimation(parent: _bellCtrl, curve: Curves.elasticIn),
    );
    _schedProv.fetch().then((_) => _startTick());
  }

  @override
  void dispose() {
    _bellCtrl.dispose();
    _tickTimer?.cancel();
    _schedProv.dispose();
    super.dispose();
  }

  void _startTick() {
    _recalcSeconds();
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_secondsLeft > 0) {
        if (mounted) setState(() => _secondsLeft -= 60);
      } else {
        _schedProv.fetch().then((_) => _recalcSeconds());
      }
    });
    Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _bellCtrl.forward(from: 0);
    });
  }

  void _recalcSeconds() {
    final next = _schedProv.nextSlot;
    if (next == null) {
      if (mounted) setState(() => _secondsLeft = 0);
      return;
    }
    if (next.isOngoing) {
      if (mounted)
        setState(() => _secondsLeft = (next.minutesUntilEnd ?? 0) * 60);
    } else {
      final mu = next.minutesUntilStart ?? 0;
      if (mounted) setState(() => _secondsLeft = mu > 0 ? mu * 60 : 0);
    }
  }

  String get _countdownText {
    if (_secondsLeft <= 0) return '';
    final h = _secondsLeft ~/ 3600;
    final m = (_secondsLeft % 3600) ~/ 60;
    final s = _secondsLeft % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _schedProv,
      builder: (_, __) {
        final next = _schedProv.nextSlot;
        final isOngoing = next?.isOngoing ?? false;

        final gradient = isOngoing
            ? context.themeConfig.linearDanger
            : next != null
            ? context.themeConfig.linearPrimary
            : context.themeConfig.linearSuccess;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius:
              BorderRadius.circular(context.colors.radiusXL),
              boxShadow: [
                BoxShadow(
                  color: (isOngoing
                      ? context.themeConfig.danger
                      : context.themeConfig.primary)
                      .withValues(alpha: 0.38),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Decorative circles
                Positioned(
                  right: -22, top: -22,
                  child: Container(
                    width: 110, height: 110,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  right: 36, bottom: -34,
                  child: Container(
                    width: 75, height: 75,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  left: -16, top: -16,
                  child: Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),

                // Content row
                Row(
                  children: [
                    Expanded(
                      child: next == null
                          ? _BannerContent(
                        tag: 'today'.tr,
                        title: 'no_sessions_today_title'.tr,
                        subtitle: 'check_weekly_schedule'.tr,
                      )
                          : _BannerContent(
                        tag: next.isOngoing
                            ? 'session_ongoing_tag'.tr
                            : 'upcoming_session_tag'.tr,
                        title: next.courseName,
                        subtitle:
                        '${next.startTime} — ${next.endTime}',
                        countdown: _countdownText.isNotEmpty
                            ? (next.isOngoing
                            ? 'ends_after_countdown'.tr
                            .replaceAll('{t}', _countdownText)
                            : 'starts_after_countdown'.tr
                            .replaceAll('{t}', _countdownText))
                            : null,
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Animated bell
                    AnimatedBuilder(
                      animation: _bellAnim,
                      builder: (_, child) => Transform.rotate(
                          angle: _bellAnim.value, child: child),
                      child: Container(
                        width: 58, height: 58,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: const Icon(
                          Icons.notifications_active_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Inner content for the banner
class _BannerContent extends StatelessWidget {
  final String tag;
  final String title;
  final String subtitle;
  final String? countdown;

  const _BannerContent({
    required this.tag,
    required this.title,
    required this.subtitle,
    this.countdown,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tag pill
        Row(
          children: [
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                tag,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontFamily: 'bahji',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Icon(Icons.access_time_rounded,
                color: Colors.white.withValues(alpha: 0.75), size: 13),
            const SizedBox(width: 5),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.80),
                fontSize: 12,
                fontFamily: 'bahji',
              ),
            ),
          ],
        ),

        const SizedBox(height: 5),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 16,
            fontFamily: 'bahji',
            letterSpacing: -0.3,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        if (countdown != null) ...[
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: Text(
              countdown!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                fontFamily: 'bahji',
              ),
            ),
          ),
        ],
      ],
    );
  }
}