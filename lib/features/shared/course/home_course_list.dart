import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/student/models.dart';
import '../../../config/app_config.dart';
import '../../../config/app_theme.dart';
import '../../../utils/widget/app_network_image.dart';
import '../../student/courses/details/components/app_responsive.dart';
import '../profile/course_instractor_profile.dart';

class HomeCourseList extends StatelessWidget {
  const HomeCourseList({super.key,required this.hasMore, required this.courses, required this.onTap, required this.isTeacher});
  final List<CourseModel> courses;
  final bool hasMore;
  final void Function(CourseModel course) onTap;
  final bool isTeacher;

  @override
  Widget build(BuildContext context) {
    final w = context.screenW;
    final cols = w >= 1100 ? 3 : (w >= 700 ? 2 : 1);
    final isGrid = cols > 1;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: Breakpoints.contentMax),
        // child: isGrid
        child: isGrid
            ? GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          physics: const BouncingScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 2.3,
          ),
          itemCount:courses.length + (hasMore ? 1 : 0),
          itemBuilder: (_, i) {
            if (i >= courses.length) {
              return Center(
                child: CircularProgressIndicator(
                  valueColor:
                  AlwaysStoppedAnimation(context.colors.primary),
                  strokeWidth: 2,
                ),
              );
            }
            return _CourseCard(course: courses[i],onTap: onTap,);
          },
        )
            : ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          physics: const BouncingScrollPhysics(),
          itemCount:
         courses.length + (hasMore ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            if (i ==courses.length) {
              return Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(
                        context.colors.primary),
                    strokeWidth: 2,
                  ),
                ),
              );
            }
            return _CourseCard(course:courses[i],onTap: onTap,);
          },
        ),
      ),
    );
  }
}

// ── Course card ───────────────────────────────────────────────────────────────

class _CourseCard extends StatelessWidget {
  final CourseModel course;
  final void Function(CourseModel course) onTap;

  const _CourseCard({required this.course, required this.onTap});

  void _open(BuildContext ctx) => onTap.call(course);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _open(context),
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              // Thumbnail column
              SizedBox(
                width: 104,
                height: context.height / 7,
                child: Stack(
                  fit: StackFit.passthrough,
                  children: [
                    AppNetworkImage(
                      url: course.imageUrl,
                      width: 104,
                      height: double.infinity,
                      heroTag: "course-list-${course.id}",

                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.32),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      right: 0,
                      left: 0,
                      child: Center(
                        child: _PricePill(price: course.price),
                      ),
                    ),
                  ],
                ),
              ),

              // Info
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(children: [
                        _TypeTag(type: course.type),
                        if (course.categoryName != null) ...[
                          const SizedBox(width: 6),
                          _CatTag(label: course.categoryName!),
                        ],
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        course.title,
                        style: context.colors.h3.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if(course.teacher!=Null)
                        InstructorAvatar(teacher: course.teacher!, size: 50, canOpen: true,),

                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          _MetaItem(
                            Icons.star_rounded,
                            course.rate?.toStringAsFixed(1) ?? '–',
                            color: context.colors.accent,
                          ),
                          _MetaItem(Icons.people_rounded,
                              '${course.studentsCount} طالب'),
                          if (course.sessions.isNotEmpty)
                            _MetaItem(Icons.video_library_rounded,
                                '${course.sessions.length} محاضرة'),
                          if (course.hoursCount > 0)
                            _MetaItem(Icons.access_time_rounded,
                                '${course.hoursCount} ساعة'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.chevron_left_rounded,
                    color: context.colors.textLight, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PricePill extends StatelessWidget {
  final num price;

  const _PricePill({required this.price});

  @override
  Widget build(BuildContext context) {
    final isFree = price == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isFree ? const Color(0xFF0F6E56) : context.colors.primary,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: (isFree ? const Color(0xFF0F6E56) : context.colors.primary)
                .withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        isFree ? 'مجاني' : '\$${price.toStringAsFixed(0)}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          fontFamily: 'bahji',
        ),
      ),
    );
  }
}

class _TypeTag extends StatelessWidget {
  final String type;

  const _TypeTag({required this.type});

  @override
  Widget build(BuildContext context) {
    final isLive = type == 'live';
    final c = isLive ? context.colors.danger : context.colors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLive ? Icons.sensors_rounded : Icons.play_arrow_rounded,
            size: 10,
            color: c,
          ),
          const SizedBox(width: 3),
          Text(
            isLive ? 'مباشر' : 'مسجّل',
            style: context.colors.caption
                .copyWith(color: c, fontWeight: FontWeight.w700, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _CatTag extends StatelessWidget {
  final String label;

  const _CatTag({required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: context.colors.primaryLight.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      label,
      style: context.colors.caption.copyWith(
          color: context.colors.primary,
          fontWeight: FontWeight.w700,
          fontSize: 10),
    ),
  );
}

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _MetaItem(this.icon, this.label, {this.color});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: color ?? context.colors.textLight),
      const SizedBox(width: 3),
      Text(label, style: context.colors.caption.copyWith(fontSize: 11)),
    ],
  );
}
