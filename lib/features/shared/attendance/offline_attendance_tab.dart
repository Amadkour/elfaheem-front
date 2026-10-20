/// features/attendance/offline_attendance_tab.dart
///
/// The "Attendance" tab of the Downloads screen: every subscribed course saved on this phone
/// (works with no internet). Tapping a course opens the code-entry sheet for that course.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'attendance_models.dart';
import 'attendance_store.dart';
import 'attendance_strings.dart';
import 'attendance_widgets.dart';

class OfflineAttendanceTab extends StatefulWidget {
  const OfflineAttendanceTab({super.key});
  @override
  State<OfflineAttendanceTab> createState() => _OfflineAttendanceTabState();
}

class _OfflineAttendanceTabState extends State<OfflineAttendanceTab> {
  late Future<void> _future;

  @override
  void initState() {
    super.initState();
    _future = AttendanceStore.instance.preload();
  }

  @override
  Widget build(BuildContext context) {
    final primary = context.colors.primary;
    return FutureBuilder<void>(
      future: _future,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: AppLoadingIndicator(size: 56));
        }
        final courses = AttendanceStore.instance.cachedCourses;
        if (courses.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(CupertinoIcons.person_crop_circle_badge_checkmark,
                    size: 56, color: primary.withValues(alpha: 0.5)),
                const SizedBox(height: 14),
                Text(attT('att_courses_empty'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'tajawal', color: context.colors.textMedium, height: 1.5)),
              ]),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          itemCount: courses.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(attT('att_courses_title'),
                    style: const TextStyle(
                        fontFamily: 'tajawal', fontSize: 15, fontWeight: FontWeight.w800)),
              );
            }
            final c = courses[i - 1];
            final name = c.nameFor(AppConfig.lang);
            return Material(
              color: primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => showStudentCheckInSheet(context, courseId: c.courseId, title: name),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    CircleAvatar(
                      backgroundColor: primary.withValues(alpha: 0.14),
                      child: Icon(CupertinoIcons.book_fill, color: primary, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontFamily: 'tajawal', fontWeight: FontWeight.w800, fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(attT('att_course_tap'),
                            style: TextStyle(
                                fontFamily: 'tajawal', fontSize: 11.5, color: context.colors.textMedium)),
                      ]),
                    ),
                    const Icon(CupertinoIcons.chevron_forward, size: 16),
                  ]),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
