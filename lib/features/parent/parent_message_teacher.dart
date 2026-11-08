// lib/features/parent/parent_message_teacher.dart — "Message the teacher" (D-305, consolidated into Messages by D-330).
//
//   showParentMessageTeacher(context, childId:, childName:, teachers:, courseId:)  → true when a chat opened
//
// One teacher: the chat opens at once. Several: a short sheet picks the course first, then the chat opens. The phone
// number is no longer offered: in a chat a person shares it by typing it. Kill switch `parent.message_teacher` (the callers
// hide the action; the server refuses too).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_shell_nav.dart' show AppShellNav;

import '../../config/app_config.dart';
import 'parent_pulse.dart';

/// The kill switch of the action (the home asks before offering it).
const kParentMessageTeacherKey = 'parent.message_teacher';

bool get parentMessageTeacherOn => !AppConfig.disableList.contains(kParentMessageTeacherKey);

Future<bool> showParentMessageTeacher(
  BuildContext context, {
  required int childId,
  required String childName,
  required List<PulseTeacher> teachers,
  int? courseId,
}) async {
  if (teachers.isEmpty) {
    showAppNotice('pp_msg_no_teacher'.tr, error: true);
    return false;
  }
  final nav = AppShellNav.navigatorFor(context);
  Future<void> open(PulseTeacher t) => nav.pushNamed('/chat', arguments: {'peer_id': t.id, 'course_id': t.courseId});
  final direct = courseId != null ? teachers.where((t) => t.courseId == courseId).firstOrNull : null;
  if (direct != null || teachers.length == 1) {
    await open(direct ?? teachers.first);
    return true;
  }
  final picked = await showAppSheet<PulseTeacher>(context, (_) => ParentMessageTeacherSheet(childName: childName, teachers: teachers));
  if (picked == null) return false;
  await open(picked);
  return true;
}

/// Which teacher: only asked when the child has more than one and none was chosen.
class ParentMessageTeacherSheet extends StatelessWidget {
  const ParentMessageTeacherSheet({super.key, required this.childName, required this.teachers, this.childId, this.courseId});

  final int? childId, courseId;
  final String childName;
  final List<PulseTeacher> teachers;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppSheetContent(title: 'pp_msg_title'.tr, children: [
      Text('pp_msg_note'.tr.replaceAll('{child}', childName.split(' ').first), style: appText(12.5, w: FontWeight.w400, c: c.textMedium, h: 1.4)),
      const SizedBox(height: AppSpace.sm),
      for (final t in teachers)
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => Navigator.of(context).pop(t),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            child: Row(children: [
              AppAvatar(name: t.name, url: t.imageUrl.isEmpty ? null : t.imageUrl, size: 44),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w600, c: c.textDark)),
                  Text(t.course, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, w: FontWeight.w400, c: c.textMedium)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
            ]),
          ),
        ),
    ]);
  }
}
