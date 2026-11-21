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
import 'package:flutter_education_app/features/sessions/material/session_material_widget.dart';
import 'package:flutter_education_app/features/sessions/teacher/sessions_provider.dart';
import 'package:flutter_education_app/features/sessions/session_track_tabs.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppElevation, AppListSkeleton, AppRadius, AppSpace;
import 'package:flutter_education_app/features/sessions/teacher/components/teacher_course_parts.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/design/app_notice.dart' show showAppNotice;
import 'package:flutter_education_app/config/app_config.dart' show Trans;
import 'package:flutter_education_app/features/calendar/calendar_api.dart';
import 'package:flutter_education_app/features/calendar/calendar_meeting.dart' show showMeetingForm;
import 'package:flutter_education_app/features/calendar/recurrence/recurrence_rule.dart' show kRecurringFeatureKey;
import 'package:flutter_education_app/utils/widget/parent_component.dart';

/// The meeting form with [courseId] preset and a weekly repeat on, from the next full hour.
Future<void> openCourseRepeatingMeeting(BuildContext context, int courseId) async {
  final n = AppTime.toZone(DateTime.now().toUtc());
  final start = DateTime(n.year, n.month, n.day, n.hour + 1);
  final r = await showMeetingForm(context, api: const RemoteCalendarApi(), start: start, courseId: courseId);
  if (r != null) showAppNotice('cal_recur_course_created'.tr);
}

class TeacherSessionsBody extends StatelessWidget {
  const TeacherSessionsBody({super.key, required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TeacherCourseScreenProvider>();
    final sessions = provider.sessions;
    final loading = sessions.isEmpty && (provider.isLoading || provider.loadingAllPage);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TeacherSessionsHeader(
          key: const ValueKey('teacher_sessions.header'),
          count: provider.sessionCount,
          // New session is the page header's (D-943); the empty state below keeps its own first-session button
        ),
        // the course's repeating meeting (D-1575): this body is the teacher's course page only
        ParentComponent(
          featureKey: kRecurringFeatureKey,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(kCourseGutter, 0, kCourseGutter, AppSpace.sm),
            child: CourseRepeatingMeetingEntry(onTap: () => openCourseRepeatingMeeting(context, provider.course.id)),
          ),
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
