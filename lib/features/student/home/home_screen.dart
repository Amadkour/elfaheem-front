import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/category/categories_screen.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/app_config.dart' as Helpers;
import '../../../config/app_theme.dart';
import '../../category/categories_provider.dart';
import '../courses/list/courses_list_screen.dart';
import '../courses/list/courses_provider.dart';
import 'component/category_row.dart';
import 'component/course_row.dart';
import 'component/home_section_header.dart';
import 'component/instractor_roe.dart';
import 'component/search_bar_icon.dart';
import 'component/top_bar.dart';
import '../../teacher/schedules/schedules_provider.dart';

const double _kContentMax = 900;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.value([
        context.read<CategoriesProvider>().fetchCategories(),
        context.read<CoursesProvider>().fetchCourses(),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kContentMax),
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // ── Top bar ──────────────────────────────────────────────
                  SliverToBoxAdapter(child: TopBar()),
                  const SliverToBoxAdapter(child: SizedBox(height: 18)),

                  // ── Search bar ───────────────────────────────────────────
                  const SliverToBoxAdapter(child: SearchBarIcon()),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),

                  // ── Upcoming session banner ──────────────────────────────
                  const SliverToBoxAdapter(child: _UpcomingBanner()),
                  const SliverToBoxAdapter(child: SizedBox(height: 28)),

                  // ── Categories ───────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: SectionHeader(
                      title: 'categories'.tr,
                      actionLabel: 'show_more'.tr,
                      onAction: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const CategoriesScreen()),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  const SliverToBoxAdapter(child: CategoriesRow()),
                  const SliverToBoxAdapter(child: SizedBox(height: 28)),

                  // ── Courses ──────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: SectionHeader(
                      title: 'courses'.tr,
                      actionLabel: 'show_more'.tr,
                      onAction: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const CoursesListScreen()),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  const SliverToBoxAdapter(child: CoursesRow()),
                  const SliverToBoxAdapter(child: SizedBox(height: 28)),

                  // ── Best teachers ────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: SectionHeader(
                      title: 'best_teachers'.tr,
                      actionLabel: 'show_more'.tr,
                      onAction: () {},
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  SliverToBoxAdapter(child: InstructorsRow()),
                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              ),
            ),
          ),
        ),
      ),
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
        vsync: this, duration: const Duration(milliseconds: 400));
    _bellAnim = Tween<double>(begin: -0.06, end: 0.06).animate(
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
        setState(() => _secondsLeft -= 60);
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
      setState(() => _secondsLeft = 0);
      return;
    }
    if (next.isOngoing) {
      setState(() => _secondsLeft = (next.minutesUntilEnd ?? 0) * 60);
    } else {
      final mu = next.minutesUntilStart ?? 0;
      setState(() => _secondsLeft = mu > 0 ? mu * 60 : 0);
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

        // Ongoing = red gradient, upcoming = primary, no session = softer purple
        final gradient = isOngoing
            ? const LinearGradient(
          colors: [Color(0xFFC0392B), Color(0xFFE57373)],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        )
            : next != null
            ? AppTheme.primaryGradient
            : const LinearGradient(
          colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusXL),
              boxShadow: [
                BoxShadow(
                  color: (isOngoing
                      ? const Color(0xFFC0392B)
                      : AppTheme.primary)
                      .withValues(alpha:0.38),
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
                      color: Colors.white.withValues(alpha:0.08),
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
                      color: Colors.white.withValues(alpha:0.06),
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
                      color: Colors.white.withValues(alpha:0.05),
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
                        tag: 'اليوم',
                        title: 'لا توجد حصص اليوم',
                        subtitle: 'تحقق من جدولك الأسبوعي',
                      )
                          : _BannerContent(
                        tag: next.isOngoing
                            ? '🔴 جارية الآن'
                            : 'الحصة القادمة',
                        title: next.courseName,
                        subtitle:
                        '${next.startTime} — ${next.endTime}',
                        countdown: _countdownText.isNotEmpty
                            ? (next.isOngoing
                            ? 'تنتهي بعد $_countdownText'
                            : 'تبدأ بعد $_countdownText')
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
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha:0.20),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha:0.3),
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
        Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha:0.22),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            tag,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 9),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 16,
            fontFamily: 'Cairo',
            letterSpacing: -0.3,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Icon(Icons.access_time_rounded,
                color: Colors.white.withValues(alpha:0.75), size: 13),
            const SizedBox(width: 5),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha:0.80),
                fontSize: 12,
                fontFamily: 'Cairo',
              ),
            ),
          ],
        ),
        if (countdown != null) ...[
          const SizedBox(height: 12),
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha:0.22),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha:0.3),
                width: 0.5,
              ),
            ),
            child: Text(
              countdown!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                fontFamily: 'Cairo',
              ),
            ),
          ),
        ],
      ],
    );
  }
}