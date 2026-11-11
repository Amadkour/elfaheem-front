/// features/attendance/offline_attendance_tab.dart
///
/// The "Attendance" tab of the Downloads screen: every subscribed course saved on this phone
/// (works with no internet). Tapping a course opens the code-entry sheet for that course.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppReveal;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'attendance_store.dart';
import 'attendance_strings.dart';
import 'attendance_widgets.dart';
import 'attendance_ui.dart';

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
          return const AppListSkeleton();
        }
        final courses = AttendanceStore.instance.cachedCourses;
        if (courses.isEmpty) {
          return AppEmpty(icon: CupertinoIcons.person_crop_circle_badge_checkmark, title: attT('att_courses_empty'));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.lg, AppSpace.md, AppSpace.xl),
          itemCount: courses.length + 1,
          separatorBuilder: (_, i) => i == 0 ? const SizedBox.shrink() : AppSpace.gapXs,
          itemBuilder: (_, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: Semantics(header: true, child: Text(attT('att_courses_title'), style: AppType.section(context))),
              );
            }
            final c = courses[i - 1];
            final name = c.nameFor(AppConfig.lang);
            // One entrance: the first rows rise in once (AppReveal caps the stagger).
            return AppReveal(
              index: i - 1,
              group: 'att_offline',
              child: AppCard(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                onTap: () => showStudentCheckInSheet(context, courseId: c.courseId, title: name),
                child: Row(children: [
                  AttIconWell(icon: CupertinoIcons.book_fill, color: primary),
                  AppSpace.gapSm,
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
                      const SizedBox(height: AppSpace.xxs / 2),
                      Text(attT('att_course_tap'), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                    ]),
                  ),
                  AppSpace.gapXs,
                  Icon(CupertinoIcons.forward, size: AppIconSize.sm, color: context.colors.textLight),
                ]),
              ),
            );
          },
        );
      },
    );
  }
}
