// components/sessions_section.dart
//
// The Sessions tab of the teacher's course page: header + track tabs + the reorderable list (or the skeleton /
// the first-session call to action). It is the one part of the page that reacts to nearly everything the mega
// provider does (session CRUD, live flags, material uploads), so it does its own `watch` — the hero, actions and
// side card above it never rebuild with it.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/course/course_space/course_space.dart' show kCourseGutter;
import '../../../shared/session/material/session_material_widget.dart';
import '../sessions_provider.dart';
import 'package:flutter_education_app/features/shared/session/session_track_tabs.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton;
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
              padding: const EdgeInsets.fromLTRB(kCourseGutter, 0, kCourseGutter, 12),
              child: SessionTrackTabs(
                value: provider.trackFilter,
                lectures: sessions.where((s) => s.track != 'section').length,
                sections: sessions.where((s) => s.track == 'section').length,
                onChanged: provider.setTrackFilter,
              ),
            ),
          Padding(
            key: const ValueKey('teacher_sessions.list'),
            padding: const EdgeInsets.fromLTRB(kCourseGutter, 0, kCourseGutter, 16),
            child: ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: provider.visibleSessions.length,
              // re-ordering changes the course's real order → only in the "All" view
              onReorderItem: (oldIndex, newIndex) {
                if (provider.trackFilter == 'all') provider.reorderSessions(oldIndex, newIndex);
              },
              itemBuilder: (ctx, i) => KeyedSubtree(
                key: ValueKey('session_${provider.visibleSessions[i].id}'),
                child: SessionMaterialCard(
                  session: provider.visibleSessions[i],
                  sessionNumber: i + 1,
                  course: provider.course,
                  isTeacher: true,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
