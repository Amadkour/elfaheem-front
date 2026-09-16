// features/shared/widgets/course_roadmap_section.dart
//
// Student-facing course-profile "footer" — deliberately a different,
// bolder visual language than the plain teacher-facing
// CourseRecommendationsSection: a dark indigo/gold "journey" card showing
// where the student is (this course) and where they can go next, followed
// by a Netflix-style premium card strip for recommended + similar courses.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../student/models.dart';

const _kRoadmapGold = Color(0xFFFFD700);
const _kRoadmapGoldSoft = Color(0xFFE8C878);

class CourseRoadmapSection extends StatelessWidget {
  final String currentCourseName;
  final CourseSummary? nextCourse;
  final List<CourseSummary> recommendedCourses;
  final List<CourseSummary> similarCourses;
  final ValueChanged<CourseSummary> onTapCourse;

  const CourseRoadmapSection({
    super.key,
    required this.currentCourseName,
    required this.nextCourse,
    required this.recommendedCourses,
    required this.similarCourses,
    required this.onTapCourse,
  });

  List<CourseSummary> get _combined {
    final seen = <int>{if (nextCourse != null) nextCourse!.id};
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
    if (nextCourse == null && combined.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E1B4B), Color(0xFF3B2E7A), Color(0xFF4C1D95)],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4C1D95).withValues(alpha: 0.35),
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
                child: const Icon(Icons.map_rounded, size: 18, color: _kRoadmapGold),
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
            currentCourseName: currentCourseName,
            nextCourse: nextCourse,
            onTapNext: nextCourse == null ? null : () => onTapCourse(nextCourse!),
          ),
          if (combined.isNotEmpty) ...[
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
            SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: combined.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, i) => _PremiumCourseCard(
                  course: combined[i],
                  onTap: () => onTapCourse(combined[i]),
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
// The path: "you are here" → next course
// ─────────────────────────────────────────────────────────────────────────────

class _RoadmapPath extends StatelessWidget {
  final String currentCourseName;
  final CourseSummary? nextCourse;
  final VoidCallback? onTapNext;

  const _RoadmapPath({
    required this.currentCourseName,
    required this.nextCourse,
    required this.onTapNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RoadmapNode(
          label: currentCourseName,
          caption: 'roadmap_you_are_here'.tr,
          icon: Icons.check_circle_rounded,
          active: true,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 22),
          child: _RoadmapConnector(dim: nextCourse == null),
        ),
        nextCourse != null
            ? GestureDetector(
          onTap: onTapNext,
          child: _RoadmapNode(
            label: nextCourse!.name,
            caption: 'roadmap_next_up'.tr,
            icon: Icons.arrow_forward_rounded,
            active: false,
          ),
        )
            : _RoadmapNode(
          label: 'roadmap_more_coming_soon'.tr,
          caption: '',
          icon: Icons.hourglass_top_rounded,
          active: false,
          muted: true,
        ),
      ],
    );
  }
}

class _RoadmapConnector extends StatelessWidget {
  final bool dim;

  const _RoadmapConnector({required this.dim});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: context.width/4,
        child: CustomPaint(
          size:  Size(context.width/4, 2),
          painter: _DashedLinePainter(
            color: dim
                ? Colors.white.withValues(alpha: 0.15)
                : _kRoadmapGold.withValues(alpha: 0.7),
          ),
        ),
      );
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
  final bool active;
  final bool muted;

  const _RoadmapNode({
    required this.label,
    required this.caption,
    required this.icon,
    required this.active,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? _kRoadmapGold : (muted ? Colors.white38 : Colors.white);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? _kRoadmapGold.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.08),
            border: Border.all(
              color: active ? _kRoadmapGold : Colors.white24,
              width: 1.4,
            ),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(height: 8),
        if (caption.isNotEmpty)
          Text(
            caption,
            style: TextStyle(
              fontFamily: 'tajawal',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: active ? _kRoadmapGoldSoft : Colors.white54,
              letterSpacing: 0.4,
            ),
          ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'tajawal',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: muted ? Colors.white38 : Colors.white,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium (Netflix-style) course card: full-bleed image, gradient overlay,
// text/rating/price floated over the bottom.
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumCourseCard extends StatelessWidget {
  final CourseSummary course;
  final VoidCallback onTap;

  const _PremiumCourseCard({required this.course, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 152,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            course.imageUrl.isNotEmpty
                ? Image.network(
                    course.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: const Color(0xFF2D2A5C)),
                  )
                : Container(color: const Color(0xFF2D2A5C)),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.92),
                  ],
                  stops: const [0.35, 0.7, 1.0],
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, size: 12, color: _kRoadmapGold),
                    const SizedBox(width: 2),
                    Text(
                      course.averageRating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontFamily: 'tajawal',
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    course.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    course.currency.format(course.price),
                    style: const TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _kRoadmapGold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
