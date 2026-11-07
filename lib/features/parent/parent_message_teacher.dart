// lib/features/parent/parent_message_teacher.dart — "Message the teacher" (D-305): a short note from a linked parent
// to one of the child's course teachers, delivered as the teacher's notification (+ push).
//
//   showParentMessageTeacher(context, childId:, childName:, teachers:, courseId:)  → true when sent
//
// The sheet: the course (only when the child has more than one teacher), the message (1–1000), "Add my phone number"
// (off by default — the number is only sent when the parent turns it on), Send. Server: POST
// /api/v1/parent/children/{id}/message-teacher (ParentPulseApi), 3 per teacher a day (429 parent_message_limit → its
// text). Kill switch `parent.message_teacher` (the callers hide the action; the server refuses too).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';

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
  ParentPulseApi? api,
}) async {
  if (teachers.isEmpty) {
    showAppNotice('pp_msg_no_teacher'.tr, error: true);
    return false;
  }
  return await showAppSheet<bool>(
        context,
        (_) => ParentMessageTeacherSheet(childId: childId, childName: childName, teachers: teachers, courseId: courseId, api: api),
      ) ??
      false;
}

class ParentMessageTeacherSheet extends StatefulWidget {
  const ParentMessageTeacherSheet({super.key, required this.childId, required this.childName, required this.teachers, this.courseId, this.api});

  final int childId;
  final String childName;
  final List<PulseTeacher> teachers;
  final int? courseId;
  final ParentPulseApi? api;

  @override
  State<ParentMessageTeacherSheet> createState() => _ParentMessageTeacherSheetState();
}

class _ParentMessageTeacherSheetState extends State<ParentMessageTeacherSheet> {
  final _text = TextEditingController();
  late PulseTeacher _to = widget.teachers.firstWhere((t) => t.courseId == widget.courseId, orElse: () => widget.teachers.first);
  bool _sharePhone = false, _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final msg = _text.text.trim();
    if (msg.isEmpty) {
      setState(() => _error = 'pp_msg_empty'.tr);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await (widget.api ?? ParentPulseApi()).messageTeacher(widget.childId, courseId: _to.courseId, message: msg, sharePhone: _sharePhone);
      if (!mounted) return;
      showAppNotice('pp_msg_sent'.tr.replaceAll('{name}', _to.name));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = ApiException.from(e).message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppSheetContent(title: 'pp_msg_title'.tr, children: [
      // who it goes to
      Row(children: [
        AppAvatar(name: _to.name, url: _to.imageUrl.isEmpty ? null : _to.imageUrl, size: 40),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_to.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w600, c: c.textDark)),
            Text(_to.course, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, w: FontWeight.w400, c: c.textMedium)),
          ]),
        ),
      ]),
      if (widget.teachers.length > 1) ...[
        const SizedBox(height: AppSpace.sm),
        Text('pp_msg_course'.tr, style: appText(12, w: FontWeight.w600, c: c.textMedium)),
        const SizedBox(height: 6),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final t in widget.teachers)
            AppChoiceChip(
              label: t.course,
              selected: identical(t, _to),
              onTap: () {
                if (!_busy) setState(() => _to = t);
              },
            ),
        ]),
      ],
      const SizedBox(height: AppSpace.md),
      AppField(controller: _text, label: 'pp_msg_label'.tr, hint: 'pp_msg_hint'.tr, maxLines: 5),
      const SizedBox(height: AppSpace.xs),
      AppSwitchTile(
        title: 'pp_msg_phone'.tr,
        icon: Icons.call_rounded,
        value: _sharePhone,
        onChanged: _busy ? null : (v) => setState(() => _sharePhone = v),
      ),
      const SizedBox(height: AppSpace.xs),
      Text('pp_msg_note'.tr.replaceAll('{child}', widget.childName.split(' ').first),
          style: appText(11.5, w: FontWeight.w400, c: c.textLight, h: 1.4)),
      if (_error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: c.danger),
      ],
      const SizedBox(height: AppSpace.md),
      AppButton.primary(label: 'pp_msg_send'.tr, icon: Icons.send_rounded, busy: _busy, onPressed: _busy ? null : _send),
    ]);
  }
}
