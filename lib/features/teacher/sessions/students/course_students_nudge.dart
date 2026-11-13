// course_students_nudge.dart
//
// The nudge composer of a course's students page (D-873): one sheet for one student, a selection or every
// low-progress student. A short message from a friendly bilingual template (`{name}` and `{course}` are filled per
// student by the server), a live preview of what one student reads, and "Also notify the parent" that names only how
// many have a linked parent. Students nudged in the last 24 h are named as skipped before sending.
// [NudgeComposer] takes plain values (the layout harness pumps it); [openNudgeSheet] wires it to the provider.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../../admin/admin_common.dart' show t;
import 'course_student_provider.dart';

/// Opens the composer for [targets] (one or a selection) or, with [allLow], every low-progress student the server
/// may nudge now. Shows the outcome as a notice.
Future<void> openNudgeSheet(
  BuildContext context,
  EnrolledStudentsProvider provider, {
  required String courseName,
  List<EnrolledStudent> targets = const [],
  bool allLow = false,
}) async {
  final ready = allLow ? const <EnrolledStudent>[] : [for (final s in targets) if (s.canNudge) s];
  final count = allLow ? provider.summary.lowNudgeable : ready.length;
  if (count == 0) {
    showAppNotice(t('تم تذكيرهم خلال آخر 24 ساعة. يمكنك التذكير مرة أخرى لاحقًا.', 'Already nudged in the last 24 h. You can nudge again later.'));
    return;
  }
  final withParent = allLow ? provider.summary.lowWithParent : ready.where((s) => s.parentCount > 0).length;
  await showAppSheet<void>(
    context,
    (ctx) => NudgeComposer(
      students: count,
      withParent: withParent,
      skipped: allLow ? 0 : targets.length - ready.length,
      previewName: allLow || ready.isEmpty ? t('سارة', 'Sara') : ready.first.name,
      singleName: !allLow && ready.length == 1 ? ready.first.name : null,
      courseName: courseName,
      cooldownHours: provider.cooldownHours,
      onSend: (message, parents) async {
        try {
          final r = await provider.nudge(ids: [for (final s in ready) s.id], allLow: allLow, message: message, parents: parents);
          showAppNotice(nudgeResultText(r));
          return true;
        } catch (e) {
          final ex = ApiException.from(e);
          showAppNotice(
              ex.code == 'nudged_recently'
                  ? t('تم تذكيرهم خلال آخر 24 ساعة. يمكنك التذكير مرة أخرى لاحقًا.', 'Already nudged in the last 24 h. You can nudge again later.')
                  : ex.message,
              error: true);
          return false;
        }
      },
    ),
  );
}

/// The composer's sheet body from plain values. [onSend] gets the message and the parents choice and returns true
/// when the sheet may close.
class NudgeComposer extends StatefulWidget {
  const NudgeComposer({
    super.key,
    required this.students,
    required this.withParent,
    required this.courseName,
    required this.onSend,
    this.skipped = 0,
    this.previewName = '',
    this.singleName,
    this.cooldownHours = 24,
  });

  /// How many will be nudged.
  final int students;

  /// How many of them have an active linked parent.
  final int withParent;

  /// How many of the chosen were nudged in the last [cooldownHours] and will be skipped.
  final int skipped;
  final String previewName;

  /// The one student's name when the nudge is for one (the title names them).
  final String? singleName;
  final String courseName;
  final int cooldownHours;
  final Future<bool> Function(String message, bool parents) onSend;

  @override
  State<NudgeComposer> createState() => _NudgeComposerState();
}

class _NudgeComposerState extends State<NudgeComposer> {
  late final TextEditingController _text = TextEditingController(text: nudgeTemplate());
  bool _parents = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await widget.onSend(_text.text.trim(), _parents && widget.withParent > 0);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).maybePop();
  }

  String get _title {
    final one = widget.singleName;
    if (one != null) return t('تذكير $one', 'Nudge $one');
    final n = countText(widget.students,
        ar1: 'طالب واحد', ar2: 'طالبين', arFew: '{n} طلاب', arMany: '{n} طالبًا', en1: '1 student', en: '{n} students');
    return t('تذكير $n', 'Nudge $n');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final message = _text.text.trim();
    final parentsLine = widget.withParent == 0
        ? t('لا يوجد ولي أمر مرتبط', 'No linked parent')
        : widget.students == 1
            ? t('لديه ولي أمر مرتبط', 'Has a linked parent')
            : t('${widget.withParent} من ${widget.students} لديهم ولي أمر مرتبط', '${widget.withParent} of ${widget.students} have a linked parent');
    return AppSheetContent(
      title: _title,
      icon: Icons.notifications_active_outlined,
      subtitle: t('يصلهم إشعار داخل التطبيق وتنبيه على الهاتف. تذكير واحد لكل طالب كل ${widget.cooldownHours} ساعة.',
          'They get an in-app notification and a push. One nudge per student every ${widget.cooldownHours} h.'),
      children: [
        if (widget.skipped > 0) ...[
          AppBanner(
            icon: Icons.schedule_rounded,
            color: c.warning,
            text: countText(widget.skipped,
                ar1: 'سيتم تخطي طالب واحد تم تذكيره مؤخرًا.', ar2: 'سيتم تخطي طالبين تم تذكيرهما مؤخرًا.',
                arFew: 'سيتم تخطي {n} طلاب تم تذكيرهم مؤخرًا.', arMany: 'سيتم تخطي {n} طالبًا تم تذكيرهم مؤخرًا.',
                en1: '1 student nudged recently will be skipped.', en: '{n} students nudged recently will be skipped.'),
          ),
          AppSpace.gapSm,
        ],
        AppField(
          key: const ValueKey('nudge.message'),
          controller: _text,
          label: t('الرسالة', 'Message'),
          maxLines: 4,
          maxLength: 500,
          helper: t('{name} و{course} يُستبدلان باسم كل طالب واسم المقرر.', '{name} and {course} become each student\'s name and the course.'),
        ),
        AppSpace.gapSm,
        // what one student reads
        Container(
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.controlAll),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('معاينة', 'Preview'), style: AppType.meta(context).copyWith(color: c.textLight)),
            const SizedBox(height: AppSpace.xxs),
            Text(
              message.isEmpty
                  ? nudgePreview(nudgeTemplate(), name: widget.previewName, course: widget.courseName)
                  : nudgePreview(message, name: widget.previewName, course: widget.courseName),
              style: AppType.body(context),
            ),
          ]),
        ),
        AppSpace.gapSm,
        Row(children: [
          Expanded(
            child: AppButton.ghost(
              key: const ValueKey('nudge.reset'),
              label: t('استعادة النص المقترح', 'Use the suggested text'),
              icon: Icons.auto_awesome_outlined,
              size: AppButtonSize.sm,
              onPressed: message == nudgeTemplate().trim() ? null : () => _text.text = nudgeTemplate(),
            ),
          ),
        ]),
        Material(
          type: MaterialType.transparency,
          child: CheckboxListTile(
            key: const ValueKey('nudge.parents'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _parents && widget.withParent > 0,
            onChanged: widget.withParent == 0 ? null : (v) => setState(() => _parents = v ?? false),
            title: Text(t('أبلغ ولي الأمر أيضًا', 'Also notify the parent'), style: AppType.row(context)),
            subtitle: Text(parentsLine, style: AppType.meta(context)),
          ),
        ),
        AppSpace.gapMd,
        Row(children: [
          Expanded(
            child: AppButton.secondary(
              label: t('إلغاء', 'Cancel'),
              expand: true,
              onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
            ),
          ),
          AppSpace.gapSm,
          Expanded(
            child: AppButton.primary(
              key: const ValueKey('nudge.send'),
              label: t('إرسال التذكير', 'Send nudge'),
              icon: Icons.send_rounded,
              expand: true,
              busy: _busy,
              onPressed: _send,
            ),
          ),
        ]),
      ],
    );
  }
}
