/// courses/details/course_detail_screen.dart
/// Student course detail — 3 tabs:
///   الدروس  (sessions list, default)
///   نبذة عن (about, schedule, certificates, tools, prerequisites)
///   البث    (live session join)
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../config/app_theme.dart';
import '../../../../utils/widget/app_network_image.dart';
import '../../enrollment/enrollment_provider.dart';
import '../../enrollment/enrollment_screen.dart';
import '../../models.dart';
import 'components/about.dart';
import 'components/content.dart';
import 'course_detail_provider.dart';
import 'components/stat_chip.dart';

class CourseDetailScreen extends StatelessWidget {
  const CourseDetailScreen({super.key, required this.course});
  final CourseModel course;
  @override
  Widget build(BuildContext context) {
    context.read<CourseDetailProvider>().init(course);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
            child: Column(children: [
          Expanded(
            child: RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: () => context.read<CourseDetailProvider>().refresh(),
              child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _CourseHeader()),
                    SliverToBoxAdapter(child: _CourseMeta()),
                    const SliverToBoxAdapter(child: SizedBox(height: 8)),
                    SliverToBoxAdapter(child: _TabBar()),
                    const SliverToBoxAdapter(child: TabContent()),
                  ]),
            ),
          ),
          _EnrollButton(),
        ])),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _CourseHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final course = context.watch<CourseDetailProvider>().course;
    final isFav = course.isFavorite;
    return Stack(children: [
      AppNetworkImage(
          url: course.imageUrl,
          width: double.infinity,
          height: 220,
          borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(28),
              bottomRight: Radius.circular(28))),
      Positioned.fill(
          child: DecoratedBox(
              decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(28),
                      bottomRight: Radius.circular(28)),
                  gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.45),
                        Colors.transparent
                      ])))),
      Positioned(
          top: 14,
          right: 16,
          left: 16,
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _CircleBtn(
                icon: isFav
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                iconColor: isFav ? Colors.red : null,
                onTap: () =>
                    context.read<CourseDetailProvider>().toggleFavorite()),
            _CircleBtn(
                icon: Icons.arrow_forward_rounded,
                onTap: () => Navigator.of(context).maybePop()),
          ])),
    ]);
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final VoidCallback onTap;

  const _CircleBtn({required this.icon, required this.onTap, this.iconColor});

  @override
  Widget build(BuildContext ctx) => GestureDetector(
      onTap: onTap,
      child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              shape: BoxShape.circle,
              boxShadow: AppTheme.cardShadow),
          child: Icon(icon, size: 20, color: iconColor ?? AppTheme.textDark)));
}

// ── Meta ──────────────────────────────────────────────────────────────────────

class _CourseMeta extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.watch<CourseDetailProvider>().course;
    return Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.name, style: AppTheme.h1),
          const SizedBox(height: 8),
          Row(children: [
            if (c.categoryName != null) ...[
              _Badge(c.categoryName!),
              const SizedBox(width: 10)
            ],
            const Icon(Icons.star_rounded, color: AppTheme.accent, size: 18),
            const SizedBox(width: 4),
            Text(
                '${c.averageRating.toStringAsFixed(1)} (${c.studentsCount} طالب)',
                style: AppTheme.label),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            StatChip(
                icon: Icons.people_alt_rounded,
                label: '${c.studentsCount} طالب'),
            const SizedBox(width: 10),
            StatChip(
                icon: Icons.video_library_rounded,
                label: '${c.sessionsCount} محاضرة'),
            const SizedBox(width: 10),
            StatChip(
                icon: Icons.access_time_rounded,
                label: '${c.totalHours.toStringAsFixed(1)} ساعه'),
            if (c.certificates.isNotEmpty) ...[
              const SizedBox(width: 10),
              const StatChip(
                  icon: Icons.workspace_premium_rounded,
                  label: 'شهادة',
                  iconColor: AppTheme.accent),
            ],
          ]),
        ]));
  }
}

class _Badge extends StatelessWidget {
  final String label;

  const _Badge(this.label);

  @override
  Widget build(BuildContext ctx) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8)),
      child:
          Text(label, style: AppTheme.label.copyWith(color: AppTheme.primary)));
}

// ── Tab Bar ───────────────────────────────────────────────────────────────────

class _TabBar extends StatelessWidget {
  static const _tabs = [
    (CourseDetailTab.lessons, 'الدروس'),
    (CourseDetailTab.about, 'نبذة عن'),
    (CourseDetailTab.live, 'البث المباشر'),
  ];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseDetailProvider>();
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
            children: _tabs.map((t) {
          final (tab, label) = t;
          final isActive = provider.activeTab == tab;
          return Expanded(
              child: GestureDetector(
                  onTap: () => context.read<CourseDetailProvider>().setTab(tab),
                  child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                          border: Border(
                              bottom: BorderSide(
                                  color: isActive
                                      ? AppTheme.primary
                                      : Colors.transparent,
                                  width: 2.5))),
                      child: Text(label,
                          textAlign: TextAlign.center,
                          style: AppTheme.label.copyWith(
                              color: isActive
                                  ? AppTheme.primary
                                  : AppTheme.textMedium,
                              fontWeight:
                                  isActive ? FontWeight.w700 : FontWeight.w500,
                              fontSize: 13)))));
        }).toList()));
  }
}

// ── Enroll Button ─────────────────────────────────────────────────────────────

class _EnrollButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = context.watch<CourseDetailProvider>();
    if (p.isEnrolled) {
      return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Container(
              height: 54,
              decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: AppTheme.success)),
              child: const Center(
                  child: Text('تم الاشتراك ✓',
                      style: TextStyle(
                          color: AppTheme.success,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          fontFamily: 'Cairo')))));
    }
    final label = p.course.price == 0
        ? 'سجّل مجاناً'
        : 'الانضمام الآن — \$ ${p.course.price.toStringAsFixed(2)}';
    return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: GestureDetector(
            onTap: p.isEnrolling
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider(
                        create: (_) => EnrollmentProvider(p.course),
                        child: const EnrollmentScreen()))),
            child: Container(
                height: 54,
                decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: AppTheme.primaryShadow),
                child: Center(
                    child: p.isEnrolling
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : Text(label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                fontFamily: 'Cairo'))))));
  }
}

class SectionHdr extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Color? iconColor;

  const SectionHdr({required this.title, this.icon, this.iconColor});

  @override
  Widget build(BuildContext ctx) => Row(children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: iconColor ?? AppTheme.primary),
          const SizedBox(width: 8)
        ],
        Text(title, style: AppTheme.h3)
      ]);
}

class ScheduleChip extends StatelessWidget {
  final CourseSchedule schedule;

  const ScheduleChip({required this.schedule});

  @override
  Widget build(BuildContext ctx) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2))),
      child: Row(children: [
        const Icon(Icons.access_time_filled_rounded,
            color: AppTheme.primary, size: 18),
        const SizedBox(width: 10),
        Text(schedule.dayLabel,
            style: AppTheme.label.copyWith(
                color: AppTheme.primary, fontWeight: FontWeight.w700)),
        const Spacer(),
        Text('${schedule.startTime}  —  ${schedule.endTime}',
            style: AppTheme.label.copyWith(color: AppTheme.textDark))
      ]));
}
