// lib/design/master_detail/entity_viewer_actions.dart — the quick actions a viewer gets from what the server allowed
// (D-290, phase 7).
//
//   entityViewerActions(context, ref, summary)   Open course (a learner's own: Continue learning) · Message
//   showEntityMessageSheet(context, ref)         the quick message: to one student, delivered as a notification
//   showEntityMessageManySheet(context, refs)    phase 8: the same note to a list's selected students (≤ 100)
//
// The default of every panel and full page without actions of its own; a role's list adds to it (`openCourse:` keeps
// that list's own way into a course).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart';

import '../app_kit.dart';
import 'entity_detail_view.dart' show EntityPanelAction;
import 'entity_panel_controller.dart';
import 'entity_specs.dart' show mdText;

/// What [summary] lets this viewer do; nothing until it is known. [openCourse] replaces the default way into a course.
List<EntityPanelAction> entityViewerActions(BuildContext context, EntityRef ref, EntitySummary? summary,
    {EntityPanelController? controller, VoidCallback? openCourse}) {
  final s = summary;
  if (s == null) return const [];
  final open = openCourse ?? () => AppNavigator.openCourse(ref.id);
  return [
    if (s.kind == EntityKind.course && s.mine != null && s.mine!.state != 'withdrawn')
      EntityPanelAction(
        key: const ValueKey('md.continue'),
        icon: Icons.play_arrow_rounded,
        label: (s.mine!.state == 'completed' ? 'md_p7_review_course' : 'md_p7_continue').tr,
        primary: true,
        onPressed: open,
      )
    else if (s.kind == EntityKind.course && s.can.manage)
      EntityPanelAction(
        key: const ValueKey('md.open_course'),
        icon: Icons.open_in_new_rounded,
        label: 'md_p7_open_course'.tr,
        primary: true,
        onPressed: open,
      ),
    if (s.kind == EntityKind.student && s.can.message)
      EntityPanelAction(
        key: const ValueKey('md.message'),
        icon: Icons.chat_bubble_outline_rounded,
        label: 'md_p7_message'.tr,
        onPressed: () => showEntityMessageSheet(context, s.ref.withLabel(label: ref.label), courseId: controller?.focusCourseId),
      ),
  ];
}

/// Writes a short note to [student] ([courseId]: the course it is about).
Future<void> showEntityMessageSheet(BuildContext context, EntityRef student, {int? courseId}) => showAppSheet<void>(
      context,
      (ctx) => _MessageSheet(students: [student], courseId: courseId),
    );

/// The bulk send's most recipients (the server's `BULK_MAX`).
const entityMessageMax = 100;

/// The same note to [students] (a list's selection; the first [entityMessageMax] are sent).
Future<void> showEntityMessageManySheet(BuildContext context, List<EntityRef> students, {int? courseId}) =>
    students.length == 1
        ? showEntityMessageSheet(context, students.first, courseId: courseId)
        : showAppSheet<void>(
            context,
            (ctx) => _MessageSheet(students: students.take(entityMessageMax).toList(), courseId: courseId),
          );

class _MessageSheet extends StatefulWidget {
  const _MessageSheet({required this.students, this.courseId});

  final List<EntityRef> students;
  final int? courseId;

  @override
  State<_MessageSheet> createState() => _MessageSheetState();
}

class _MessageSheetState extends State<_MessageSheet> {
  static const int _max = 1000;
  final _text = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final many = widget.students;
      if (many.length == 1) {
        await EntitiesApi.instance.message(many.first.id, text, courseId: widget.courseId);
        if (!mounted) return;
        Navigator.of(context).pop();
        showAppNotice(mdText('md_p7_message_sent', {'name': many.first.name}));
        return;
      }
      final (sent, skipped) =
          await EntitiesApi.instance.messageMany([for (final r in many) r.id], text, courseId: widget.courseId);
      if (!mounted) return;
      Navigator.of(context).pop();
      showAppNotice(mdText(skipped > 0 ? 'md_p8_message_sent_skipped' : 'md_p8_message_sent_many',
          {'n': '$sent', 'skipped': '$skipped'}));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppNotice(e is ApiException && e.code == 'message_limit' ? 'md_p7_message_limit'.tr : appErrorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AppSheetContent(
        title: widget.students.length == 1
            ? mdText('md_p7_message_to', {'name': widget.students.first.name})
            : mdText('md_p8_message_to_many', {'n': '${widget.students.length}'}),
        children: [
          TextField(
            key: const ValueKey('md.message.text'),
            controller: _text,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            maxLength: _max,
            decoration: InputDecoration(hintText: 'md_p7_message_hint'.tr),
          ),
          const SizedBox(height: AppSpace.xs),
          Text('md_p7_message_note'.tr, style: AppType.meta(context)),
          const SizedBox(height: AppSpace.sm),
          AppButton.primary(
            key: const ValueKey('md.message.send'),
            label: 'md_p7_message_send'.tr,
            icon: Icons.send_rounded,
            busy: _busy,
            expand: true,
            onPressed: _send,
          ),
        ],
      );
}
