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
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: TopBar()),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              const SliverToBoxAdapter(child: SearchBarIcon()),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'categories'.tr,
                  actionLabel: 'show_more'.tr,
                  onAction: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CategoriesScreen()),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
              const SliverToBoxAdapter(child: CategoriesRow()),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
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
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
              const SliverToBoxAdapter(child: CoursesRow()),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'best_teachers'.tr,
                  actionLabel: 'show_more'.tr,
                  onAction: () {},
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
              SliverToBoxAdapter(child: InstructorsRow()),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
              // Real upcoming session banner
              const SliverToBoxAdapter(child: _UpcomingBanner()),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Real upcoming banner — fetches /student/schedules
//  then counts down to the next session every second
// ─────────────────────────────────────────────

class _UpcomingBanner extends StatefulWidget {
  const _UpcomingBanner();

  @override
  State<_UpcomingBanner> createState() => _UpcomingBannerState();
}

class _UpcomingBannerState extends State<_UpcomingBanner>
    with SingleTickerProviderStateMixin {
  // ── Bell animation ───────────────────────────
  late AnimationController _bellCtrl;
  late Animation<double> _bellAnim;

  // ── Schedule data ────────────────────────────
  final StudentSchedulesProvider _schedProv = StudentSchedulesProvider();
  Timer? _tickTimer;
  int _secondsLeft = 0; // live countdown

  @override
  void initState() {
    super.initState();
    if(_schedProv!=null) {
      _schedProv.fetch().then((_) => _startTick());
    }else{
      _startTick();
    }
    //
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
        setState(() => _secondsLeft-=60);
      } else {
        // Re-fetch when a session is about to start/end
        _schedProv.fetch().then((_) => _recalcSeconds());
      }
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
    if (h > 0)
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _schedProv,
      builder: (_, __) {
        final next = _schedProv.nextSlot;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              gradient: next != null && next.isOngoing
                  ? const LinearGradient(
                      colors: [Color(0xFFD32F2F), Color(0xFFE57373)],
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft)
                  : AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              boxShadow: AppTheme.primaryShadow,
            ),
            child: Row(children: [
              Expanded(
                child: next == null
                    // ── No upcoming session today ──────────────────
                    ? const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('لا توجد حصص اليوم',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  fontFamily: 'Cairo')),
                          SizedBox(height: 4),
                          Text('تحقق من جدولك الأسبوعي',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontFamily: 'Cairo')),
                        ],
                      )
                    // ── Upcoming / ongoing session ─────────────────
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            next.isOngoing ? '🔴 جارية الآن' : 'الحصة القادمة',
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            next.courseName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                fontFamily: 'Cairo'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${next.startTime} — ${next.endTime}',
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontFamily: 'Cairo'),
                          ),
                          if (_countdownText.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text(
                                next.isOngoing
                                    ? 'تنتهي بعد $_countdownText'
                                    : 'تبدأ بعد $_countdownText',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Cairo'),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
              const SizedBox(width: 12),
              // Animated bell
              Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.notifications_active_rounded,
                      color: Colors.white, size: 30),
                ),
            ]),
          ),
        );
      },
    );
  }
}
