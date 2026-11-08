// lib/features/shared/roadmap/roadmap_tab.dart
//
// The course page's "Path" tab (D-120) for the student's course details and the teacher's studio — personal
// accounts on personal courses only (the caller decides whether the tab exists, the server answers 403 otherwise):
//
//   student   the path (what they took before · You are here · the next courses in order with their
//             prerequisites) · "Enroll in the whole path" · the teacher's own picks, as a list of their own
//   teacher   "Edit path" (roadmap_editor.dart) · the same path with drafts marked · an empty state that invites
//             them to add the next courses
//
// Loaded when the tab is first built (GET /api/v1/roadmap/courses/{id}); [RoadmapTabContent] draws plain values.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/theme/theme_config_provider.dart';
import '../../../design/app_kit.dart';
import '../../../design/app_share_sheet.dart';
import '../../../utils/widget/parent_component.dart';
import '../../admin/admin_common.dart' show t;
import '../../auth/auth_provider.dart' show MyAuthProvider;
import '../../student/models.dart' show CourseSummary;
import '../course/course_price_tag.dart' show coursePriceLabel;
import '../course/course_space/course_space.dart';
import 'roadmap_api.dart';
import 'roadmap_editor.dart';
import 'roadmap_path.dart';

/// The signed-in account may have a roadmap (not an organization account; the server checks again).
bool roadmapAllowedHere(BuildContext context) {
  String? role;
  try {
    role = Provider.of<MyAuthProvider>(context, listen: false).currentUser?.role;
  } catch (_) {}
  return !roadmapOrgAccount(role);
}

/// The tab, or null when the path is switched off.
CourseSpaceTab? courseRoadmapTab({
  required int courseId,
  required bool staff,
  required ValueChanged<RmCourse> onOpenCourse,
  VoidCallback? onEnrollAll,
  List<CourseSummary> teacherPicks = const [],
  ValueChanged<CourseSummary>? onOpenPick,
}) {
  if (roadmapOff(kRoadmapPathKey)) return null;
  return CourseSpaceTab(
    id: kRoadmapTab,
    label: t('المسار', 'Path'),
    icon: Icons.route_rounded,
    builder: (_) => CourseRoadmapBody(
      courseId: courseId,
      staff: staff,
      onOpenCourse: onOpenCourse,
      onEnrollAll: onEnrollAll,
      teacherPicks: teacherPicks,
      onOpenPick: onOpenPick,
    ),
  );
}

class CourseRoadmapBody extends StatefulWidget {
  const CourseRoadmapBody({
    super.key,
    required this.courseId,
    required this.staff,
    required this.onOpenCourse,
    this.onEnrollAll,
    this.teacherPicks = const [],
    this.onOpenPick,
    this.api = const RoadmapApi(),
  });

  final int courseId;
  final bool staff;
  final ValueChanged<RmCourse> onOpenCourse;
  final VoidCallback? onEnrollAll;
  final List<CourseSummary> teacherPicks;
  final ValueChanged<CourseSummary>? onOpenPick;
  final RoadmapApi api;

  @override
  State<CourseRoadmapBody> createState() => _CourseRoadmapBodyState();
}

class _CourseRoadmapBodyState extends State<CourseRoadmapBody> {
  Roadmap? _r;
  String? _error;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await widget.api.roadmap(widget.courseId);
      if (mounted) setState(() => _r = r);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hidden = roadmapHiddenError(e);
        _error = _hidden ? null : t('تعذّر تحميل المسار', 'Could not load the path');
      });
    }
  }

  Future<void> _edit() async {
    final r = _r;
    if (r == null) return;
    final saved = await showRoadmapEditor(context, courseId: widget.courseId, roadmap: r, api: widget.api);
    if (saved != null && mounted) setState(() => _r = saved);
  }

  @override
  Widget build(BuildContext context) {
    final Widget child;
    final r = _r;
    if (_hidden) {
      child = AppEmpty(
        icon: Icons.route_rounded,
        title: t('المسار للحسابات الشخصية', 'Paths are for personal accounts'),
        message: t('لا يظهر المسار في حسابات المؤسسات ولا في مقرراتها.', 'Organization accounts and courses have no path.'),
      );
    } else if (r != null) {
      child = RoadmapTabContent(
        roadmap: r,
        // the owner opening the public page (a share link) still gets the owner's path: their words, drafts, Edit
        staff: widget.staff || r.canEdit,
        onEdit: r.canEdit ? _edit : null,
        onShare: () => shareAppLink(context, AppLink.roadmap(widget.courseId),
            title: r.course.name, subtitle: t('مسار تعلم', 'Learning path')),
        onOpenCourse: widget.onOpenCourse,
        onEnrollAll: widget.onEnrollAll,
        teacherPicks: widget.teacherPicks,
        onOpenPick: widget.onOpenPick,
      );
    } else if (_error != null) {
      child = AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load);
    } else {
      child = const SizedBox(height: 320, child: AppListSkeleton(items: 4));
    }
    return Padding(padding: const EdgeInsets.fromLTRB(kCourseGutter, 8, kCourseGutter, 16), child: child);
  }
}

/// The tab's content from plain values.
class RoadmapTabContent extends StatelessWidget {
  const RoadmapTabContent({
    super.key,
    required this.roadmap,
    required this.staff,
    required this.onOpenCourse,
    this.onEdit,
    this.onShare,
    this.onEnrollAll,
    this.teacherPicks = const [],
    this.onOpenPick,
  });

  final Roadmap roadmap;
  final bool staff;
  final VoidCallback? onEdit;

  /// Share the path's link (D-307, `/s/roadmap/<courseId>`); null hides the button.
  final VoidCallback? onShare;
  final ValueChanged<RmCourse> onOpenCourse;
  final VoidCallback? onEnrollAll;
  final List<CourseSummary> teacherPicks;
  final ValueChanged<CourseSummary>? onOpenPick;

  @override
  Widget build(BuildContext context) {
    final r = roadmap;
    final c = context.colors;
    final empty = r.next.isEmpty;
    final picks = staff || roadmapOff(kRoadmapTeacherPicksKey)
        ? const <CourseSummary>[]
        : [for (final p in teacherPicks) if (!r.next.any((n) => n.id == p.id) && !r.previous.any((n) => n.id == p.id)) p];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                staff ? t('مسار هذا الكورس', 'This course’s path') : t('رحلتك في هذا المسار', 'Your way through this path'),
                style: appText(16, w: FontWeight.w600, c: c.textDark),
              ),
            ),
            if (onShare != null && !roadmapOff(kShareLinksKey))
              IconButton(
                key: const ValueKey('roadmap.share'),
                tooltip: t('مشاركة المسار', 'Share the path'),
                onPressed: onShare,
                icon: Icon(Icons.ios_share_rounded, color: c.textMedium),
              ),
            if (onEdit != null)
              OutlinedButton.icon(
                onPressed: onEdit,
                style: OutlinedButton.styleFrom(minimumSize: const Size(48, 44)),
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: Text(t('تعديل المسار', 'Edit path')),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          staff
              ? t('ما يدرسه الطالب بعد هذا الكورس، بالترتيب.', 'What a student takes after this course, in order.')
              : t('ما درسته قبله، وأين أنت، وما يأتي بعده.', 'What you took before, where you are, and what comes next.'),
          style: appText(13, w: FontWeight.w400, c: c.textMedium),
        ),
        const SizedBox(height: 16),
        RoadmapPathView(stops: roadmapStops(r), staff: staff, onTap: onOpenCourse),
        if (empty) ...[
          const SizedBox(height: 12),
          if (staff)
            AppBanner(
              icon: Icons.add_road_rounded,
              text: t('أضف الكورسات التي تأتي بعد هذا الكورس ليرى طلابك طريقهم.', 'Add the courses that come after this one so your students see their way.'),
              action: onEdit == null ? null : TextButton(onPressed: onEdit, child: Text(t('إضافة', 'Add'))),
            )
          else
            Text(t('لم يحدد المدرّس الخطوة التالية بعد.', 'The instructor has not set the next step yet.'),
                textAlign: TextAlign.center, style: appText(13, w: FontWeight.w400, c: c.textLight)),
        ],
        if (staff && onEdit != null && !empty && (r.course.level == null || r.course.tags.isEmpty)) ...[
          const SizedBox(height: 12),
          AppBanner(
            icon: Icons.sell_outlined,
            text: t('أضف مستوى الكورس وكلماته المفتاحية ليُقترح على الطلاب المناسبين.', 'Add the course’s level and topic words so it is suggested to the right students.'),
            action: TextButton(onPressed: onEdit, child: Text(t('إضافة', 'Add'))),
          ),
        ],
        if (!staff && onEnrollAll != null && r.hasNotTaken && !roadmapOff(kRoadmapEnrollKey)) ...[
          const SizedBox(height: 16),
          AppPrimaryButton(label: t('اشترك في المسار كاملاً', 'Enroll in the whole path'), icon: Icons.route_rounded, onPressed: onEnrollAll!),
        ],
        if (picks.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(t('اختيارات المدرّس', 'Picked by your instructor'), style: appText(16, w: FontWeight.w600, c: c.textDark)),
          const SizedBox(height: 8),
          for (final p in picks.take(4)) _PickRow(course: p, onTap: onOpenPick == null ? null : () => onOpenPick!(p)),
        ],
      ],
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({required this.course, this.onTap});

  final CourseSummary course;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ParentComponent(
      featureKey: 'roadmap.course_card',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: c.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.divider)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 18, color: appInk(context, c.primary)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(course.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w500, c: c.textDark)),
                    ),
                    const SizedBox(width: 8),
                    Text(coursePriceLabel(course.currency, course.finalPrice), style: appText(12.5, w: FontWeight.w500, c: c.textMedium)),
                    Icon(Icons.chevron_right_rounded, size: 20, color: c.textLight),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
