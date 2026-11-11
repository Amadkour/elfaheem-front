// components/sessions_section.dart
//
// The Sessions tab of the teacher's course page: header + track tabs + the reorderable list (or the skeleton /
// the first-session call to action). It is the one part of the page that reacts to nearly everything the mega
// provider does (session CRUD, live flags, material uploads), so it does its own `watch` — the hero, actions and
// side card above it never rebuild with it.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../config/theme/theme_config_provider.dart';
import '../../../shared/course/course_space/course_space.dart';
import '../../../shared/session/material/session_material_widget.dart';
import '../sessions_provider.dart';
import 'package:flutter_education_app/features/shared/session/session_track_tabs.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppElevation, AppListSkeleton, AppRadius, AppSpace;
import 'teacher_course_parts.dart';

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
          onAdd: onAdd,
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
