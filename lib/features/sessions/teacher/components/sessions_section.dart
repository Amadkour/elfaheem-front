// components/sessions_section.dart
//
// The Sessions tab of the teacher's course page: header + track tabs + the reorderable list (or the skeleton /
// the first-session call to action). It is the one part of the page that reacts to nearly everything the mega
// provider does (session CRUD, live flags, material uploads), so it does its own `watch` — the hero, actions and
// side card above it never rebuild with it.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/courses/course_space/course_space.dart';
import 'package:flutter_education_app/features/courses/course_space/course_series_block.dart' show CourseSeriesSection;
import 'package:flutter_education_app/features/sessions/material/session_material_widget.dart';
import 'package:flutter_education_app/features/sessions/teacher/sessions_provider.dart';
import 'package:flutter_education_app/features/sessions/session_track_tabs.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppElevation, AppListSkeleton, AppRadius, AppSpace;
import 'package:flutter_education_app/features/sessions/teacher/components/teacher_course_parts.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/design/app_notice.dart' show showAppNotice;
import 'package:flutter_education_app/config/app_config.dart' show AppConfig, Trans;
import 'package:flutter_education_app/features/calendar/calendar_api.dart';
import 'package:flutter_education_app/features/calendar/calendar_meeting.dart'
    show calNextSensibleSlot, showMeetingForm, startQuickMeeting;
import 'package:flutter_education_app/features/payments/points/points_api.dart' show kQuickMeetingFeatureKey;
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart' show TeacherCourse;
import 'package:flutter_education_app/features/calendar/recurrence/recurrence_rule.dart' show kRecurringFeatureKey;

/// The meeting form with [courseId] preset and a weekly repeat on, from the next full hour. True when one was made.
/// [title]: the course's name, the series' first title (D-1661).
Future<bool> openCourseRepeatingMeeting(BuildContext context, int courseId, {String? title}) async {
  final start = calNextSensibleSlot(AppTime.toZone(DateTime.now().toUtc()));
  final r = await showMeetingForm(context, api: const RemoteCalendarApi(), start: start, courseId: courseId, title: title);
  if (r != null) showAppNotice('cal_recur_course_created'.tr);
  return r != null;
}

class TeacherSessionsBody extends StatefulWidget {
  const TeacherSessionsBody({super.key, required this.onAdd});

  final VoidCallback onAdd;

  @override
  State<TeacherSessionsBody> createState() => _TeacherSessionsBodyState();
}

class _TeacherSessionsBodyState extends State<TeacherSessionsBody> {
  /// Bumped after a repeating meeting is made, so the series block reads the course's series again.
  int _seriesReload = 0;

  /// "Meet now" is creating its meeting.
  bool _starting = false;

  Future<void> _repeat(TeacherCourse course) async {
    final ar = AppConfig.lang == 'ar';
    final name = (ar ? course.titleAr : course.titleEn) ?? course.titleEn ?? course.titleAr;
    if (await openCourseRepeatingMeeting(context, course.id, title: name) && mounted) setState(() => _seriesReload++);
  }

  /// An online meeting with the course's students, now (D-1723): the server invites and tells them, then the
  /// pre-join page opens (the teacher presses Join there, D-106). Recording stays off until the teacher records.
  Future<void> _meetNow(TeacherCourse course) async {
    if (_starting) return;
    setState(() => _starting = true);
    await startQuickMeeting(context, courseId: course.id);
    if (mounted) setState(() => _starting = false);
  }

  @override
  Widget build(BuildContext context) {
    final onAdd = widget.onAdd;
    final provider = context.watch<TeacherCourseScreenProvider>();
    final sessions = provider.sessions;
    final loading = sessions.isEmpty && (provider.isLoading || provider.loadingAllPage);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TeacherSessionsHeader(
          key: const ValueKey('teacher_sessions.header'),
          count: provider.sessionCount,
          // the reference's list header carries New session beside the count; the empty state keeps its own button
          onAdd: onAdd,
        ),
        // the course's online meetings (D-1725): Meet now · Repeating meeting, each behind its own kill switch
        // (a hidden one leaves no gap). This body is the teacher's course page only.
        if (!AppConfig.disableList.contains(kQuickMeetingFeatureKey) || !AppConfig.disableList.contains(kRecurringFeatureKey))
          Padding(
            padding: const EdgeInsets.fromLTRB(kCourseGutter, 0, kCourseGutter, AppSpace.sm),
            child: CourseMeetingActions(
              starting: _starting,
              onMeetNow: AppConfig.disableList.contains(kQuickMeetingFeatureKey) ? null : () => _meetNow(provider.course),
              onRepeating: AppConfig.disableList.contains(kRecurringFeatureKey) ? null : () => _repeat(provider.course),
            ),
          ),
        // its series with their coming dates (D-1660): meetings, not lessons, so above the timeline and shown even
        // while the course has no lesson yet
        CourseSeriesSection(
          key: const ValueKey('teacher_sessions.series'),
          courseId: provider.course.id,
          reload: _seriesReload,
          padding: const EdgeInsets.fromLTRB(kCourseGutter, 0, kCourseGutter, AppSpace.sm),
        ),
        if (loading)
          const AppListSkeleton(items: 3, padding: EdgeInsetsDirectional.fromSTEB(kCourseGutter, 0, kCourseGutter, 0))
        else if (sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kCourseGutter),
            child: TeacherSessionsEmpty(key: const ValueKey('teacher_sessions.empty'), onAdd: onAdd),
          )
        else ...[
          // Lectures (teacher) · Sections (assistant) — only when the course has sections
          if (provider.hasSections)
            Padding(
              padding: const EdgeInsets.fromLTRB(kCourseGutter, 0, kCourseGutter, AppSpace.sm),
              child: SessionTrackTabs(
                value: provider.trackFilter,
                lectures: sessions.where((s) => s.track != 'section').length,
                sections: sessions.where((s) => s.track == 'section').length,
                onChanged: provider.setTrackFilter,
              ),
            ),
          // ONE timeline card (the same look as the student's): live · up next · scheduled · delivered
          Padding(
            key: const ValueKey('teacher_sessions.list'),
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: CourseSessionsSurface(
              child: Builder(
                builder: (context) {
                  final shown = provider.visibleSessions;
                  final states = courseTeacherStates([
                    for (final s in shown) (live: s.isLiveActive, when: sessionUtc(s.scheduledAt), minutes: s.durationMinutes),
                  ]);
                  // re-ordering changes the course's real order → only in the "All" view
                  final reorder = provider.trackFilter == 'all';
                  final groups = courseSessionGroups([for (final s in shown) sessionUtc(s.scheduledAt)]);
                  return ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: shown.length,
                    onReorderItem: (oldIndex, newIndex) {
                      // onReorderItem already gives the final index; reorderSessions takes the old onReorder one
                      if (reorder) provider.reorderSessions(oldIndex, newIndex > oldIndex ? newIndex + 1 : newIndex);
                    },
                    // the dragged session floats: paper on the raised shadow (the one thing here that casts one)
                    proxyDecorator: (child, _, _) => DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        boxShadow: AppElevation.of(context, 2),
                      ),
                      child: Material(
                        color: context.colors.cardBg,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        child: child,
                      ),
                    ),
                    itemBuilder: (ctx, i) => KeyedSubtree(
                      key: ValueKey('session_${shown[i].id}'),
                      child: SessionMaterialCard(
                        session: shown[i],
                        sessionNumber: i + 1,
                        course: provider.course,
                        isTeacher: true,
                        state: states[i],
                        rail: courseSessionRail(states, i),
                        group: groups[i],
                        liveType: provider.course.type == 'live',
                        dragIndex: reorder ? i : null,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}
