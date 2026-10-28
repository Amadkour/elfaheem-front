import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart' as Helpers;
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../config/theme/theme_config_provider.dart';
import 'rewards_provider.dart';

class RewardsScreen extends StatelessWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Consumer<RewardsProvider>(
        builder: (_, provider, _) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child:   SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.04, 0),
                end:   Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: provider.showDetail
              ? const _DetailView(key: ValueKey('detail'))
              : const _OverviewView(key: ValueKey('overview')),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OVERVIEW VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _OverviewView extends StatelessWidget {
  const _OverviewView({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RewardsProvider>();
    final courses  = provider.enrolledCourses;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Column(
          children: [
            const ScreenAppBar(title: 'الإنجازات', showBack: false),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Column(
                  children: [
                    // ── Trophy ───────────────────────────────────────────────
                    GestureDetector(
                      onTap: provider.openDetail,
                      child: Container(
                        width:  double.infinity,
                        height: 220,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [context.colors.primaryLight, context.colors.primaryLight],
                            begin:  Alignment.topLeft,
                            end:    Alignment.bottomRight,
                          ),
                          borderRadius:
                              BorderRadius.circular(context.colors.radiusLarge),
                          boxShadow: context.colors.primaryShadow,
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Decorative circles
                            Positioned(
                              top:   -30,
                              right: -30,
                              child: Container(
                                width:  140,
                                height: 140,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: context.colors.onHero.withValues(alpha: 0.08),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: -20,
                              left:   -20,
                              child: Container(
                                width:  100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: context.colors.onHero.withValues(alpha: 0.06),
                                ),
                              ),
                            ),
                            Icon(Icons.emoji_events_rounded,
                                size: 100, color: context.colors.warning),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    // ── Enrolled courses grid ─────────────────────────────────
                    if (courses.isNotEmpty) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text('كورساتي', style: context.colors.h2),
                      ),
                      const SizedBox(height: 16),
                      GridView.builder(
                        shrinkWrap: true,
                        physics:    const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount:   2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing:  16,
                          childAspectRatio: 0.9,
                        ),
                        itemCount: courses.length > 4 ? 4 : courses.length,
                        itemBuilder: (_, i) =>
                            _CourseCircle(course: courses[i]),
                      ),
                    ] else
                      Column(
                        children: [
                           Icon(Icons.school_outlined,
                              size: 64, color: context.colors.textLight),
                          const SizedBox(height: 12),
                          Text('سجّل في كورس لتبدأ رحلتك!',
                              style: context.colors.body),
                        ],
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

class _CourseCircle extends StatelessWidget {
  final dynamic course;

  const _CourseCircle({required this.course});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width:  120,
          height: 120,
          decoration: BoxDecoration(
            shape:     BoxShape.circle,
            boxShadow: context.colors.cardShadow,
          ),
          child: ClipOval(
            child: AppNetworkImage(
              url: course.imageUrl as String,
              fit: BoxFit.cover,
              heroTag: "reward-screen-${course.id}",

            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          course.name as String,
          style:     context.colors.label.copyWith(color: context.colors.textDark),
          textAlign: TextAlign.center,
          maxLines:  2,
          overflow:  TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DETAIL VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _DetailView extends StatelessWidget {
  const _DetailView({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RewardsProvider>();

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Column(
          children: [
            ScreenAppBar(title: 'إنجازاتي'),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Avatar + laurel + points ───────────────────────────
                    _UserTrophy(provider: provider),
                    const SizedBox(height: 24),
                    // ── Achievements ─────────────────────────────────────────
                    _Section(
                      title:    'الإنجازات 🏆',
                      color:    context.colors.primary,
                      children: provider.achievements
                          .map((a) => _AchievementRow(item: a))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    // ── Leaderboard ──────────────────────────────────────────
                    _Section(
                      title:    'لوحة المتصدرين 🥇',
                      color:    context.colors.accent,
                      children: provider.leaderboard
                          .map((e) => _LeaderRow(entry: e))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    // ── Tips ─────────────────────────────────────────────────
                    _Section(
                      title:    'هل تريد أن تصبح الطالب المتفوق؟ 🔥',
                      color:    context.colors.danger,
                      children: provider.tips
                          .map((a) => _AchievementRow(item: a))
                          .toList(),
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

class _UserTrophy extends StatelessWidget {
  final RewardsProvider provider;

  const _UserTrophy({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomCenter,
          children: [
            // Laurel icon background
            Container(
              width:  110,
              height: 110,
              decoration: BoxDecoration(
                shape:     BoxShape.circle,
                color:     context.colors.accent.withValues(alpha: 0.1),
                border: Border.all(
                    color: context.colors.accent.withValues(alpha: 0.3), width: 3),
              ),
              child:  Icon(Icons.person_rounded,
                  size: 60, color: context.colors.accent),
            ),
            // Ribbon
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color:        context.colors.accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'أحمد محمد',
                style: TextStyle(
                  color:      context.colors.onHero,
                  fontWeight: FontWeight.w800,
                  fontSize:   13,
                  fontFamily: 'bahji',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '${provider.totalPoints} نقطة',
          style: context.colors.h2.copyWith(color: context.colors.primary),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String       title;
  final Color        color;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.color,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        context.colors.cardBg,
        borderRadius: BorderRadius.circular(context.colors.radiusMedium),
        boxShadow:    context.colors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color:        color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(context.colors.radiusMedium),
                topLeft:  Radius.circular(context.colors.radiusMedium),
              ),
            ),
            child: Text(title,
                style: context.colors.h3.copyWith(color: color, fontSize: 14)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _AchievementRow extends StatelessWidget {
  final dynamic item; // AchievementModel

  const _AchievementRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final earned = item.earned as bool;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.title as String,
              style: context.colors.label.copyWith(
                color:      earned ? context.colors.textDark : context.colors.textLight,
                decoration: earned ? null : TextDecoration.lineThrough,
              ),
            ),
          ),
          Icon(
            earned ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            color: earned ? context.colors.success : context.colors.textLight,
            size:  20,
          ),
        ],
      ),
    );
  }
}

class _LeaderRow extends StatelessWidget {
  final LeaderboardEntry entry;

  const _LeaderRow({required this.entry});

  static const _medals = ['🥇', '🥈', '🥉'];

  @override
  Widget build(BuildContext context) {
    final medal =
        entry.rank <= 3 ? _medals[entry.rank - 1] : '${entry.rank}.';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(entry.name,
              style: context.colors.label.copyWith(color: context.colors.textDark)),
          const Spacer(),
          Text(medal,
              style: const TextStyle(fontSize: 18)),
        ],
      ),
    );
  }
}
