// lib/features/student/reward/rewards_screen.dart — achievements (RewardsProvider; not routed from the student
// shell today). Editorial theme: the overview leads with ONE gold block (achievements are what gold is for,
// system.md §2) holding a drawn trophy and the points rolling (AppOdometer); the courses as round covers; the detail
// view's achievements, leaderboard and tips as paper cards with editorial section titles; ranks are drawn medals
// (vector), never emoji.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
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
          duration: AppMotion.of(context).base,
          switchInCurve: AppEase.out,
          switchOutCurve: AppEase.out,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero).animate(anim),
              child: child,
            ),
          ),
          child: provider.showDetail ? const _DetailView(key: ValueKey('detail')) : const _OverviewView(key: ValueKey('overview')),
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
    final courses = provider.enrolledCourses;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Column(
          children: [
            const ScreenAppBar(title: 'الإنجازات', showBack: false),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(AppSpace.md + AppSpace.xxs, AppSpace.xs, AppSpace.md + AppSpace.xxs, AppSpace.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── the trophy block: the page's one memorable element ─────────────
                    RepaintBoundary(
                      child: AppTilt(
                        radius: AppRadius.block,
                        maxTilt: 2.5,
                        glare: true,
                        child: AppBlock(
                          tone: AppBlockTone.gold,
                          hero: true,
                          onTap: provider.openDetail,
                          child: _TrophyHero(points: provider.totalPoints),
                        ),
                      ),
                    ),
                    if (courses.isNotEmpty) ...[
                      Padding(
                        padding: AppSpace.sectionHead,
                        child: Text('كورساتي', style: AppType.section(context)),
                      ),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: AppSpace.md,
                          mainAxisSpacing: AppSpace.md,
                          childAspectRatio: 0.9,
                        ),
                        itemCount: courses.length > 4 ? 4 : courses.length,
                        itemBuilder: (_, i) => _CourseCircle(course: courses[i]),
                      ),
                    ] else ...[
                      AppSpace.gapLg,
                      const AppEmpty(icon: Icons.school_outlined, title: 'سجّل في كورس لتبدأ رحلتك!', tone: AppBlockTone.gold),
                    ],
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

/// The trophy and the points: a drawn cup on a paper plate, the figure rolling to its value.
class _TrophyHero extends StatelessWidget {
  const _TrophyHero({required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = AppBlock.colorsOf(context);
    return Row(children: [
      AppTiltLayer(
        child: Container(
          width: AppTouch.min * 2,
          height: AppTouch.min * 2,
          decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.block)),
          child: Icon(Icons.emoji_events_rounded, size: AppTouch.min + AppSpace.xs, color: ink.accentInk(c.accent2)),
        ),
      ),
      AppSpace.gapLg,
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('الإنجازات', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: ink.muted)),
          const SizedBox(height: AppSpace.xxs),
          Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: AppSpace.xs, children: [
            AppOdometer('$points',
                memoryKey: 'rewards.points',
                style: AppType.figureLarge(context).copyWith(color: ink.ink, fontSize: AppType.display(context).fontSize, height: 1.1)),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: Text('نقطة', style: AppType.section(context).copyWith(color: ink.ink)),
            ),
          ]),
        ]),
      ),
      Icon(Icons.chevron_right_rounded, size: AppIconSize.lg, color: ink.muted),
    ]);
  }
}

class _CourseCircle extends StatelessWidget {
  final dynamic course;

  const _CourseCircle({required this.course});

  @override
  Widget build(BuildContext context) {
    // the cover takes the room the grid cell leaves above the name (a phone's narrow cell never overflows)
    return Column(
      children: [
        Expanded(
          child: AspectRatio(
          aspectRatio: 1,
          child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: context.colors.divider, width: AppBorder.hairline),
          ),
          child: ClipOval(
            child: AppNetworkImage(
              url: course.imageUrl as String,
              fit: BoxFit.cover,
              heroTag: "reward-screen-${course.id}",
            ),
          ),
        ),
        ),
        ),
        AppSpace.gapXs,
        Text(
          course.name as String,
          style: AppType.row(context),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
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
            const ScreenAppBar(title: 'إنجازاتي'),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(AppSpace.md + AppSpace.xxs, 0, AppSpace.md + AppSpace.xxs, AppSpace.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _UserTrophy(provider: provider),
                    _Section(
                      title: 'الإنجازات',
                      icon: Icons.emoji_events_rounded,
                      children: provider.achievements.map((a) => _AchievementRow(item: a)).toList(),
                    ),
                    _Section(
                      title: 'لوحة المتصدرين',
                      icon: Icons.leaderboard_rounded,
                      children: provider.leaderboard.map((e) => _LeaderRow(entry: e)).toList(),
                    ),
                    _Section(
                      title: 'هل تريد أن تصبح الطالب المتفوق؟',
                      icon: Icons.tips_and_updates_rounded,
                      children: provider.tips.map((a) => _AchievementRow(item: a)).toList(),
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
    return AppBlock(
      tone: AppBlockTone.gold,
      child: Builder(builder: (context) {
        final c = context.colors;
        final ink = AppBlock.colorsOf(context);
        return Row(children: [
          Container(
            width: AppTouch.primary,
            height: AppTouch.primary,
            decoration: BoxDecoration(color: c.cardBg, shape: BoxShape.circle),
            child: Icon(Icons.person_rounded, size: AppIconSize.xl, color: ink.accentInk(c.accent2)),
          ),
          AppSpace.gapMd,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('أحمد محمد', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: ink.ink)),
              const SizedBox(height: AppSpace.xxs),
              AppOdometer('${provider.totalPoints} نقطة', memoryKey: 'rewards.points.detail', style: AppType.figure(context).copyWith(color: ink.ink)),
            ]),
          ),
        ]);
      }),
    );
  }
}

/// A group of rows on a paper card under an editorial heading with a quiet glyph.
class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _Section({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: AppSpace.sectionHead,
        child: Row(children: [
          Icon(icon, size: AppIconSize.md, color: c.textMedium),
          AppSpace.gapXs,
          Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context))),
        ]),
      ),
      AppCard(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider, indent: AppSpace.md, endIndent: AppSpace.md),
            children[i],
          ],
        ]),
      ),
    ]);
  }
}

class _AchievementRow extends StatelessWidget {
  final dynamic item; // AchievementModel

  const _AchievementRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final earned = item.earned as bool;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTouch.min),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
        child: Row(
          children: [
            Expanded(
              child: Text(
                item.title as String,
                style: AppType.row(context).copyWith(color: earned ? c.textDark : c.textLight),
              ),
            ),
            AppSpace.gapXs,
            Icon(
              earned ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: earned ? appInk(context, c.success) : c.textLight,
              size: AppIconSize.md,
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderRow extends StatelessWidget {
  final LeaderboardEntry entry;

  const _LeaderRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTouch.min),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
        child: Row(
          children: [
            _Medal(rank: entry.rank),
            AppSpace.gapSm,
            Expanded(child: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
            Text('${entry.points}', style: AppType.figure(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
      ),
    );
  }
}

/// A drawn medal: the top three on the gold tint (top marks are what gold is for), the rest a quiet numbered disc.
class _Medal extends StatelessWidget {
  const _Medal({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = rank <= 3;
    return Container(
      width: AppIconSize.xl,
      height: AppIconSize.xl,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: top ? c.blockGold : c.inputBg,
        shape: BoxShape.circle,
        border: Border.all(color: top ? c.blockAccentInk(c.accent2, c.blockGold) : c.divider, width: AppBorder.strong),
      ),
      child: Text('$rank',
          style: AppType.label(context).copyWith(
              fontWeight: FontWeight.w600, color: top ? c.blockAccentInk(c.accent2, c.blockGold) : c.textMedium)),
    );
  }
}
