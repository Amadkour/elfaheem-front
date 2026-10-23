import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/features/shared/course/home_course_list.dart';
import 'package:flutter_education_app/features/student/home/home_provider.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart';
import '../../../config/app_config.dart' as Helpers;
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/base_page.dart';
import '../../../utils/widget/parent_component.dart';
import '../../shared/category/categories_provider.dart';
import '../../shared/category/categories_screen.dart';
import '../../shared/course/course_access.dart';
import '../../shared/guest/guest_state.dart';
import '../../teacher/home/home_screen.dart';
import '../courses/list/courses_list_screen.dart';
import '../models.dart';
import 'component/category_row.dart';
import 'component/home_section_header.dart';
import 'component/instractor_roe.dart';
import 'component/search_bar_icon.dart';
import 'component/top_bar.dart';
import '../../teacher/schedules/schedules_provider.dart';
import 'package:flutter_education_app/features/org/home_org_mix.dart';
import 'package:flutter_education_app/features/ads/ads_pages.dart';
import 'package:flutter_education_app/features/org/org_home_tab.dart' show homeTabs;
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/features/org/org_member_dashboard.dart' show AppModeSwitcher, OrgMemberHome;
import 'package:flutter_education_app/features/shared/inbox/unified_inbox.dart' show InboxPreviewCard;

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
          separatorBuilder: (_, _) => const SizedBox(width: 14),
          itemBuilder: (_, _) =>
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
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, _) =>
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
          separatorBuilder: (_, _) => const SizedBox(width: 14),
          itemBuilder: (_, _) =>
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
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, _) =>
            const Shimmer(width: 50, height: 50, radius: 25),
          ),
        ),
      ),
    ],
  );
}

/// Shown when the dashboard could not be loaded (offline / server error): message + Retry
/// button. It is scrollable, so pull-to-refresh works here too.
class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: box.maxWidth,
            minHeight: box.maxHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: c.primaryTint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.wifi_off_rounded,
                    size: 38,
                    color: c.primary,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'no_network_banner'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontSize: 15,
                    height: 1.5,
                    color: c.textMedium,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(backgroundColor: c.primary),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(
                    'retry'.tr,
                    style: const TextStyle(
                      fontFamily: 'tajawal',
                      fontWeight: FontWeight.w700,
                    ),
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

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    AppConnectivity.instance.online.addListener(_onConnectivity);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<HomeProvider>().init(context);
    });
  }

  @override
  void dispose() {
    AppConnectivity.instance.online.removeListener(_onConnectivity);
    super.dispose();
  }

  /// Back online → load the page again if the last load failed (or brought nothing).
  /// AppConnectivity only says "online" after the server answered.
  void _onConnectivity() {
    if (!mounted || !AppConnectivity.instance.isOnline) return;
    final p = context.read<HomeProvider>();
    if (p.isLoading) return;
    if (p.loadFailed || !p.hasData) p.init(context);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeProvider>(
      builder: (context, provider, child) {
        return BasePage(
          key: const ValueKey('student_home'),
          useWebCard: true,
          child: SafeArea(
            child: RefreshIndicator(
              color: context.colors.primary,
              onRefresh: () => context.read<HomeProvider>().init(context),
              child: Center(
                child: provider.isLoading
                    ? const _CoursesShimmer()
                    : (provider.loadFailed && !provider.hasData)
                    ? _LoadFailed(
                  onRetry: () => context.read<HomeProvider>().init(context),
                )
                    : ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListenableBuilder(
                    listenable: Listenable.merge([homeTabs, AppModeController.instance]),
                    builder: (context, _) => CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      // ── Top bar ──────────────────────────────────────────
                      SliverToBoxAdapter(
                        child: ParentComponent(
                          child: TopBar(
                            key: const ValueKey('student_home.top_bar'),
                          ),
                        ),
                      ),

                      // ── Search bar ───────────────────────────────────────
                      SliverToBoxAdapter(
                        child: ParentComponent(
                          key: const ValueKey('student_home.search'),
                          child: SearchBarIcon(
                            courses: provider.otherCourses,
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(
                        child: ParentComponent(
                          key: ValueKey('student_home.upcoming_banner'),
                          child: SizedBox(height: 24),
                        ),
                      ),

                      // ── My courses | My organization (members only) ──
                      // ── Individual | Organization mode (members only, org switch on) ──
                      const SliverToBoxAdapter(child: AppModeSwitcher()),
                      if (AppModeController.instance.isOrg)
                        const SliverToBoxAdapter(child: OrgMemberHome())
                      else ...[
                      // ── Upcoming session banner ──────────────────────────
                      const SliverToBoxAdapter(
                        child: ParentComponent(
                          key: ValueKey('student_home.upcoming_banner'),
                          child: _UpcomingBanner(),
                        ),
                      ),
                      const SliverToBoxAdapter(
                        child: ParentComponent(
                          key: ValueKey('student_home.upcoming_banner'),
                          child: SizedBox(height: 28),
                        ),
                      ),

                      // ── Featured (ads) — after personal content, never above the greeting ──
                      const SliverToBoxAdapter(child: HomeAdsSlider()),
                      // ── Inbox: forms / requests / news / offers in one prioritized place ──
                      if (!GuestState.active)
                        const SliverToBoxAdapter(
                          child: ParentComponent(key: ValueKey('student_home.inbox'), child: InboxPreviewCard()),
                        ),
                      // ── Organizations (join a university / faculty) ──────
                      if (!GuestState.active)
                        const SliverToBoxAdapter(
                          child: ParentComponent(
                            key: ValueKey('student_home.org'),
                            child: HomeOrgMix(),
                          ),
                        ),

                      // ── Categories ───────────────────────────────────────
                      if (context
                          .read<CategoriesProvider>()
                          .categories
                          .length >
                          5)
                        SliverToBoxAdapter(
                          child: ParentComponent(
                            key: const ValueKey('student_home.category'),
                            child: SectionHeader(
                              title: 'categories'.tr,
                              actionLabel: 'show_more'.tr,
                              onAction: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                  const CategoriesScreen(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 16),
                      ),
                      const SliverToBoxAdapter(
                        child: ParentComponent(
                          key: ValueKey('student_home.category'),
                          child: CategoriesRow(),
                        ),
                      ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 28),
                      ),

                      // ── My Courses ───────────────────────────────────────
                      if (provider.myCourses.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: ParentComponent(
                            key: const ValueKey('student_home.courses'),
                            child: SectionHeader(
                              title: 'my_courses'.tr,
                              actionLabel: 'show_more'.tr,
                              onAction: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CoursesListScreen(
                                    homeCourses: provider.myCourses,
                                    forMyCourses: true,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(
                          child: SizedBox(height: 16),
                        ),
                        SliverToBoxAdapter(
                          key: const ValueKey('student_home.courses'),
                          child: ParentComponent(
                            child: HomeCourseList(
                              courses: provider.myCourses,
                              pageName: 'home-my-courses',
                              isTeacher: false,
                              onTap: (CourseModel c) =>
                                  openCourse(context, c, provider.api),

                              hasMore: false,
                            ),
                          ),
                        ),
                      ],

                      // ── Other Courses ────────────────────────────────────
                      if (provider.otherCourses.isNotEmpty) ...[
                        const SliverToBoxAdapter(
                          child: SizedBox(height: 28),
                        ),
                        SliverToBoxAdapter(
                          child: ParentComponent(
                            key: const ValueKey(
                              'student_home.other_courses',
                            ),
                            child: SectionHeader(
                              title: 'other_courses'.tr,
                              actionLabel: 'show_more'.tr,
                              onAction: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CoursesListScreen(
                                    homeCourses: provider.otherCourses,
                                    forMyCourses: false,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(
                          child: SizedBox(height: 16),
                        ),
                        SliverToBoxAdapter(
                          child: ParentComponent(
                            key: const ValueKey(
                              'student_home.other_courses',
                            ),
                            child: HomeCourseList(
                              pageName: 'home-other-courses',
                              courses: provider.otherCourses,
                              isTeacher: false,
                              // Private courses ask for the access code first.
                              onTap: (CourseModel c) =>
                                  openCourse(context, c, provider.api),
                              hasMore: false,
                            ),
                          ),
                        ),
                      ],
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 28),
                      ),

                      // ── Best teachers ────────────────────────────────────
                      SliverToBoxAdapter(
                        child: ParentComponent(
                          key: const ValueKey(
                            'student_home.best_teachers',
                          ),
                          child: SectionHeader(
                            title: 'best_teachers'.tr,
                            actionLabel: 'show_more'.tr,
                            onAction: () {},
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 16),
                      ),
                      SliverToBoxAdapter(
                        child: ParentComponent(
                          key: const ValueKey(
                            'student_home.best_teachers',
                          ),
                          child: InstructorsRow(),
                        ),
                      ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 40),
                      ),
                      ],
                    ],
                  ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
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
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _bellAnim = Tween<double>(
      begin: -200,
      end: 200,
    ).animate(CurvedAnimation(parent: _bellCtrl, curve: Curves.elasticIn));
    // Guest: no schedule (needs an account) → no request, no bell timer.
    if (!GuestState.active) _schedProv.fetch().then((_) => _startTick());
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
    // _tickTimer?.cancel();
    // _tickTimer = Timer.periodic(const Duration(minutes: 1), (_) {
    //   if(context.read<AuthProvider>().isAuthenticated){
    //     _tickTimer?.cancel();
    //     return;
    //   }
    //   if (_secondsLeft > 0) {
    //     if (mounted) setState(() => _secondsLeft -= 60);
    //   } else {
    //     _schedProv.fetch().then((_) => _recalcSeconds());
    //   }
    // });
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
      if (mounted) {
        setState(() => _secondsLeft = (next.minutesUntilEnd ?? 0) * 60);
      }
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
    if (GuestState.active) return const GuestPromoCard();
    return ListenableBuilder(
      listenable: _schedProv,
      builder: (_, _) {
        final next = _schedProv.nextSlot;
        final isOngoing = next?.isOngoing ?? false;

        final gradient = isOngoing
            ? context.colors.dangerGradient
            : next != null
            ? context.colors.primaryGradient
            : context.colors.successGradient;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(context.colors.radiusXL),
              boxShadow: [
                BoxShadow(
                  color:
                  (isOngoing
                      ? context.colors.danger
                      : context.colors.primary)
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
                  right: -22,
                  top: -22,
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  right: 36,
                  bottom: -34,
                  child: Container(
                    width: 75,
                    height: 75,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  left: -16,
                  top: -16,
                  child: Container(
                    width: 60,
                    height: 60,
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
                        subtitle: '${next.startTime} — ${next.endTime}',
                        countdown: _countdownText.isNotEmpty
                            ? (next.isOngoing
                            ? 'ends_after_countdown'.tr.replaceAll(
                          '{t}',
                          _countdownText,
                        )
                            : 'starts_after_countdown'.tr
                            .replaceAll(
                          '{t}',
                          _countdownText,
                        ))
                            : null,
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Animated bell
                    AnimatedBuilder(
                      animation: _bellAnim,
                      builder: (_, child) => Transform.rotate(
                        angle: _bellAnim.value,
                        child: child,
                      ),
                      child: Container(
                        width: 58,
                        height: 58,
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
            Icon(
              Icons.access_time_rounded,
              color: Colors.white.withValues(alpha: 0.75),
              size: 13,
            ),
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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