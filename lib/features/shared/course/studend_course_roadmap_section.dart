// features/shared/widgets/studend_course_roadmap_section.dart
//
// Student-facing course-profile "footer" — deliberately a different,
// bolder visual language than the plain teacher-facing
// CourseRecommendationsSection: a premium "journey" card (background tinted
// from the app's own primary color, so it stays on-brand rather than an
// arbitrary color) showing the student's path — recent completed courses →
// this course → the teacher's ordered "next steps" roadmap — followed by a
// Netflix-style premium card strip for recommended + similar courses.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../student/models.dart';
import 'teacher_course_roadmap_section.dart';

const _kRoadmapGold = Color(0xFFFFD700);
const _kRoadmapGoldSoft = Color(0xFFE8C878);

/// Background derives from the app's own primary color (not an arbitrary
/// hue) so the roadmap reads as part of the course-profile page's identity
/// rather than a bolted-on component — just darkened/deepened for the
/// contrast a "premium journey" card needs against white roadmap text.
List<Color> darkRoadmapGradientColors(BuildContext context) {
  final primary = context.colors.primary;
  return [
    Color.lerp(primary, Colors.black, 0.80)!,
    Color.lerp(primary, Colors.black, 0.58)!,
    Color.lerp(primary, Colors.black, 0.32)!,
  ];
}

enum _NodeState { completed, current, next, muted }

class CourseRoadmapSection extends StatelessWidget {
  final String currentCourseName;
  final ScrollController controller = ScrollController();

  /// Most-recent-first, as returned by the backend. Displayed oldest→newest
  /// (reversed) so the path reads left-to-right chronologically.
  final List<CourseSummary> recentCompletedCourses;

  /// The teacher's ORDERED forward roadmap — step 1, step 2, …
  final List<CourseSummary> nextCourses;
  final List<CourseSummary> recommendedCourses;
  final List<CourseSummary> similarCourses;
  final ValueChanged<CourseSummary> onTapCourse;

  /// When set (and the teacher defined next steps), shows a button that opens
  /// the roadmap checkout: enrol in every course on the path and pay once.
  final VoidCallback? onEnrollRoadmap;

  CourseRoadmapSection({
    super.key,
    required this.currentCourseName,
    this.recentCompletedCourses = const [],
    required this.nextCourses,
    required this.recommendedCourses,
    required this.similarCourses,
    required this.onTapCourse,
    this.onEnrollRoadmap,
  });

  List<CourseSummary> get _combined {
    final seen = <int>{for (final c in nextCourses) c.id};
    final result = <CourseSummary>[];
    for (final c in [...recommendedCourses, ...similarCourses]) {
      if (seen.contains(c.id)) continue;
      seen.add(c.id);
      result.add(c);
      if (result.length >= 8) break;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final combined = _combined;
    if (nextCourses.isEmpty &&
        combined.isEmpty &&
        recentCompletedCourses.isEmpty) {
      return const SizedBox.shrink();
    }

    final gradientColors = darkRoadmapGradientColors(context);

    return ParentComponent(
      key: ValueKey('roadmap'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(0, 8, 0, 8),
        padding: const EdgeInsets.symmetric(vertical: 20,horizontal: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: context.colors.primary.withValues(alpha: 0.35),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _kRoadmapGold.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.map_rounded,
                    size: 18,
                    color: _kRoadmapGold,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'learning_roadmap_title'.tr,
                  style: const TextStyle(
                    fontFamily: 'tajawal',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _RoadmapPath(
              completedCourses: recentCompletedCourses,
              currentCourseName: currentCourseName,
              nextCourses: nextCourses,
              onTapCourse: onTapCourse,
            ),
            if (onEnrollRoadmap != null && nextCourses.isNotEmpty) ParentComponent(featureKey: 'course.enroll_roadmap', child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 18),
              _EnrollRoadmapButton(
                label: 'roadmap_enroll_all'.tr,
                onTap: onEnrollRoadmap!,
              ),
            ])),
            if (combined.isNotEmpty) ParentComponent(featureKey: 'roadmap.explore_more', child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 24),
              Row(
                children: [
                  Container(width: 3, height: 15, color: _kRoadmapGold),
                  const SizedBox(width: 8),
                  Text(
                    'roadmap_explore_more_title'.tr,
                    style: const TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Scrollbar(
                controller: controller,
                thumbVisibility: true,
                trackVisibility: true,
                child: SizedBox(
                  height: 220,
                  child: ListView.separated(
                    controller: controller,
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    itemCount: combined.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 7),
                    itemBuilder: (_, i) =>
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: RecommendCourseCard(
                            course:  combined[i],
                            onTap: () => onTapCourse(combined[i]),
                            badgeText: 'suggested_badge'.tr,
                            badgeColor: context.colors.primary,
                            badgeBg: context.colors.cardBg,
                            badgeIcon: Icons.auto_awesome_rounded,
                            isDark: true,
                          ),
                        ),

                  ),
                ),
              ),
            ])),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The path: completed course(s) → you are here → ordered next-step roadmap
// ─────────────────────────────────────────────────────────────────────────────

class _RoadmapPath extends StatelessWidget {
  final List<CourseSummary> completedCourses; // most-recent-first
  final String currentCourseName;
  final List<CourseSummary> nextCourses; // ordered
  final ValueChanged<CourseSummary> onTapCourse;

  const _RoadmapPath({
    required this.completedCourses,
    required this.currentCourseName,
    required this.nextCourses,
    required this.onTapCourse,
  });

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'roadmap.path',
    child: _featureContent(context),
  );

  Widget _featureContent(BuildContext context) {
    final completedOldestFirst = completedCourses.reversed.toList();

    final children = <Widget>[];

    for (final c in completedOldestFirst) {
      children.add(
        _RoadmapNode(
          label: c.name,
          caption: 'roadmap_completed_label'.tr,
          icon: Icons.check_circle_rounded,
          state: _NodeState.completed,
        ),
      );
      children.add(const _RoadmapConnector(state: _NodeState.completed));
    }

    children.add(
      _RoadmapNode(
        label: currentCourseName,
        caption: 'roadmap_you_are_here'.tr,
        icon: Icons.play_circle_fill_rounded,
        state: _NodeState.current,
      ),
    );

    if (nextCourses.isEmpty) {
      children.add(const _RoadmapConnector(state: _NodeState.muted));
      children.add(
        _RoadmapNode(
          label: 'roadmap_more_coming_soon'.tr,
          caption: '',
          icon: Icons.hourglass_top_rounded,
          state: _NodeState.muted,
        ),
      );
    } else {
      for (final c in nextCourses) {
        children.add(const _RoadmapConnector(state: _NodeState.next));
        children.add(
          GestureDetector(
            onTap: () => onTapCourse(c),
            child: _RoadmapNode(
              label: c.name,
              caption: 'roadmap_next_up'.tr,
              icon: Icons.arrow_forward_rounded,
              state: _NodeState.next,
            ),
          ),
        );
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _RoadmapConnector extends StatelessWidget {
  final _NodeState state;

  const _RoadmapConnector({required this.state});

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _NodeState.completed => _kRoadmapGold.withValues(alpha: 0.7),
      _NodeState.next => _kRoadmapGold.withValues(alpha: 0.55),
      _ => Colors.white.withValues(alpha: 0.15),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: SizedBox(
        width: 50,
        child: CustomPaint(
          size: const Size(50, 2),
          painter: _DashedLinePainter(color: color),
        ),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;

  const _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    const dashWidth = 4.0;
    const dashSpace = 3.0;
    double x = 0;
    final y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + dashWidth, y), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _RoadmapNode extends StatelessWidget {
  final String label;
  final String caption;
  final IconData icon;
  final _NodeState state;

  const _RoadmapNode({
    required this.label,
    required this.caption,
    required this.icon,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrent = state == _NodeState.current;
    final isCompleted = state == _NodeState.completed;
    final isMuted = state == _NodeState.muted;

    final accent = isMuted ? Colors.white38 : _kRoadmapGold;
    final iconColor = isMuted
        ? Colors.white38
        : (isCurrent ? Colors.white : accent);

    return SizedBox(
      width: 40,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCurrent
                  ? _kRoadmapGold
                  : (isCompleted
                  ? _kRoadmapGold.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.08)),
              border: Border.all(
                color: isMuted ? Colors.white24 : _kRoadmapGold,
                width: 1.4,
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: isCurrent ? context.colors.primaryDark : iconColor,
            ),
          ),
          const SizedBox(height: 8),
          if (caption.isNotEmpty)
            Text(
              caption,
              style: TextStyle(
                fontFamily: 'tajawal',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isMuted ? Colors.white38 : _kRoadmapGoldSoft,
                letterSpacing: 0.4,
              ),
            ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.visible,
            style: TextStyle(
              fontFamily: 'tajawal',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isMuted ? Colors.white38 : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _EnrollRoadmapButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _EnrollRoadmapButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.primaryDark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_kRoadmapGold, _kRoadmapGoldSoft]),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.rocket_launch_rounded, size: 18, color: ink),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'tajawal',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}