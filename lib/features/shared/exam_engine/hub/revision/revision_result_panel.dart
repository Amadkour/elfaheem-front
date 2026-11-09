// What the teacher sees over the frozen scan when a paper needs them: a difference (System degree against Scanned
// degree), something unreadable, or a page the reader refused. Plain values in, callbacks out; the layout harness pumps it.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../../../admin/admin_common.dart' show t;
import '../../marks/mark_sessions_api.dart';
import '../../marks/review/grade_review_capture.dart' show gradeRetakeText;
import '../../marks/review/grade_review_rows.dart';
import 'revision_choose_student.dart';
import 'revision_models.dart';
import 'revision_wizard_steps.dart' show revisionAccent;

class RevisionResultPanel extends StatelessWidget {
  const RevisionResultPanel({
    super.key,
    required this.row,
    required this.session,
    this.photo,
    this.code = '',
    this.message = '',
    this.changedTo,
    this.busy = false,
    this.behind = 0,
    this.loadCrop,
    this.onUpdate,
    this.onIgnore,
    this.onRetake,
    this.onLater,
    this.onAssign,
    this.onChoose,
    this.pendingStudentId,
    this.onFix,
  });

  /// Null: the reader refused this page ([code] / [message] say why).
  final RevisionRow? row;
  final MarkSession session;

  /// The photo of this paper, when this device took it recently.
  final Uint8List? photo;
  final String code, message;

  /// The record holds this now (a 409 `value_changed`).
  final double? changedTo;
  final bool busy;

  /// Other papers waiting after this one.
  final int behind;
  final Future<Uint8List?> Function(String url)? loadCrop;
  final VoidCallback? onUpdate, onIgnore, onRetake, onLater, onAssign;

  /// One of the offered students was chosen.
  final ValueChanged<int>? onChoose;

  /// The student being linked right now.
  final int? pendingStudentId;
  final void Function(MarkPart part)? onFix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = row;
    return Material(type: MaterialType.transparency, child: Stack(fit: StackFit.expand, children: [
      ColoredBox(color: c.charcoalDark),
      if (photo != null) Opacity(opacity: .35, child: Image.memory(photo!, fit: BoxFit.contain, gaplessPlayback: true, excludeFromSemantics: true, errorBuilder: (_, _, _) => const SizedBox.shrink())),
      SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Container(
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(AppRadius.sheet), boxShadow: AppElevation.of(context, 3)),
                child: switch (r) {
                  null => _rejected(context),
                  _ when r.needsStudent => RevisionChooseStudent(row: r, behind: behind, busy: busy, pendingId: pendingStudentId, loadCrop: loadCrop, onChoose: onChoose, onSearch: onAssign, onRetake: onRetake, onLater: onLater),
                  _ when r.list == MarkList.mismatch => _mismatch(context, r),
                  _ => _unreadable(context, r),
                },
              ),
            ),
          ),
        ),
      ),
    ]));
  }

  Widget _waitingNote(BuildContext context) => behind <= 0
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Text(countText(behind, ar1: 'ورقة أخرى بعد هذه', ar2: 'ورقتان أخريان بعد هذه', arFew: '$behind أوراق أخرى بعد هذه', arMany: '$behind ورقة أخرى بعد هذه', en1: '1 more after this one', en: '$behind more after this one'), key: const ValueKey('rv.behind'), style: AppType.meta(context)),
        );

  Widget _mismatch(BuildContext context, RevisionRow r) {
    final c = context.colors;
    final notRecorded = r.row.recorded == null;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _waitingNote(context),
      Text(gradeRowName(r.row), key: const ValueKey('rv.name'), style: AppType.pageTitle(context), maxLines: 2, overflow: TextOverflow.ellipsis),
      Text(notRecorded ? t('لا توجد درجة مسجّلة لهذا الطالب', 'No grade is recorded for this student yet') : t('درجة الورقة تختلف عن المسجّل', 'The paper differs from the record'), style: AppType.meta(context)),
      AppSpace.gapSm,
      if (changedTo != null) ...[
        AppBanner(key: const ValueKey('rv.changed'), icon: Icons.sync_problem_rounded, color: c.warning,
            text: t('تغيّرت الدرجة المسجّلة أثناء المراجعة وأصبحت ${markNumberText(changedTo)}. قارن من جديد ثم قرّر.', 'The recorded grade changed meanwhile and is now ${markNumberText(changedTo)}. Compare again, then decide.')),
        AppSpace.gapSm,
      ],
      Row(children: [
        Expanded(child: _Figure(key: const ValueKey('rv.system'), label: t('الدرجة في النظام', 'System degree'), value: notRecorded ? '—' : markNumberText(r.row.recorded), color: c.textMedium)),
        AppSpace.gapSm,
        Expanded(child: _Figure(key: const ValueKey('rv.scanned'), label: t('الدرجة في الورقة', 'Scanned degree'), value: markNumberText(r.row.proposed), color: revisionAccent(context), strong: true)),
      ]),
      if (session.converts) ...[
        AppSpace.gapXs,
        Text(t('قُرئت ${markNumberText(r.row.used)} من ${markNumberText(session.paperMax)} وحُوّلت إلى مقياس ${markNumberText(session.columnMax)}', 'Read as ${markNumberText(r.row.used)} of ${markNumberText(session.paperMax)}, converted to a scale of ${markNumberText(session.columnMax)}'), style: AppType.meta(context)),
      ],
      if (r.row.has('paper_sum_error')) ...[
        AppSpace.gapXs,
        Text(t('جمع الورقة خاطئ: استخدمنا مجموع الأجزاء.', "The paper's addition is wrong: the sum of the parts is used."), style: AppType.meta(context).copyWith(color: c.warning)),
      ],
      if (r.row.marks.isNotEmpty) ...[AppSpace.gapSm, _CropStrip(marks: r.row.marks, loadCrop: loadCrop)],
      AppSpace.gapMd,
      AppPrimaryButton(key: const ValueKey('rv.update'), label: t('تحديث النظام', 'Update system'), icon: Icons.check_rounded, busy: busy, onPressed: busy ? null : onUpdate),
      AppSpace.gapXs,
      Row(children: [
        Expanded(child: _Side(key: const ValueKey('rv.ignore'), icon: Icons.lock_outline_rounded, label: t('تجاهل', 'Ignore'), onTap: busy ? null : onIgnore)),
        AppSpace.gapXs,
        Expanded(child: _Side(key: const ValueKey('rv.retake'), icon: Icons.replay_rounded, label: t('إعادة التصوير', 'Retake scan'), onTap: busy ? null : onRetake)),
      ]),
      _Later(onTap: busy ? null : onLater, label: t('أقرّر لاحقًا', 'Decide later')),
    ]);
  }

  Widget _unreadable(BuildContext context, RevisionRow r) {
    final c = context.colors;
    final problems = [for (final i in r.row.issues) if (gradeIssueIsProblem(i)) gradeRowIssueText(r.row, i)];
    final bad = [for (final m in r.row.marks) if (!m.ok) m];
    final shownMarks = bad.isNotEmpty ? bad : r.row.marks;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _waitingNote(context),
      Row(children: [
        Icon(Icons.warning_amber_rounded, color: c.warning),
        AppSpace.gapXs,
        Expanded(child: Text(gradeRowName(r.row), key: const ValueKey('rv.name'), style: AppType.section(context), maxLines: 2, overflow: TextOverflow.ellipsis)),
      ]),
      if (r.row.identifierMasked.isNotEmpty) Text('${t('المقروء', 'Read')}: ${r.row.identifierMasked}', textDirection: TextDirection.ltr, style: AppType.meta(context)),
      if (problems.isNotEmpty) ...[
        AppSpace.gapXs,
        Text(problems.join(' · '), style: AppType.row(context).copyWith(color: c.textMedium)),
      ],
      if (shownMarks.isNotEmpty) ...[
        AppSpace.gapSm,
        for (final m in shownMarks)
          Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: GradeMarkTile(key: ValueKey('rv.mark.${m.fieldId}'), part: m, loadCrop: loadCrop, onFix: onFix == null || busy ? null : () => onFix!(m))),
      ],
      AppSpace.gapSm,
      _Side(key: const ValueKey('rv.retake'), icon: Icons.replay_rounded, label: t('إعادة التصوير', 'Retake scan'), onTap: busy ? null : onRetake),
      _Later(onTap: busy ? null : onLater, label: t('تخطّي الآن', 'Skip for now')),
    ]);
  }

  Widget _rejected(BuildContext context) {
    final c = context.colors;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _waitingNote(context),
      Icon(Icons.image_not_supported_outlined, color: c.danger, size: AppIconSize.xl),
      AppSpace.gapXs,
      Text(t('تعذّرت قراءة هذه الصورة', 'This photo could not be read'), textAlign: TextAlign.center, style: AppType.section(context)),
      const SizedBox(height: AppSpace.xxs),
      Text(gradeRetakeText(code, fallback: message), textAlign: TextAlign.center, style: AppType.row(context)),
      AppSpace.gapMd,
      AppPrimaryButton(key: const ValueKey('rv.retake'), label: t('إعادة التصوير', 'Retake scan'), icon: Icons.replay_rounded, onPressed: onRetake),
      _Later(onTap: onLater, label: t('تخطّي', 'Skip')),
    ]);
  }
}

class _Figure extends StatelessWidget {
  const _Figure({super.key, required this.label, required this.value, required this.color, this.strong = false});
  final String label, value;
  final Color color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.sm),
      decoration: BoxDecoration(
        color: strong ? color.withValues(alpha: .1) : c.background,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: strong ? color.withValues(alpha: .45) : c.divider),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
        const SizedBox(height: AppSpace.xxs),
        SizedBox(
          height: 56,
          child: FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: AppType.figureLarge(context).copyWith(fontSize: 44, color: color, fontWeight: FontWeight.w800))),
        ),
      ]),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(AppTouch.min, AppTouch.min))),
        onPressed: onTap,
        icon: Icon(icon, size: AppIconSize.xs),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
}

class _Later extends StatelessWidget {
  const _Later({required this.onTap, required this.label});
  final VoidCallback? onTap;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.xxs),
        child: TextButton(key: const ValueKey('rv.later'), style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(AppTouch.min, AppTouch.min))), onPressed: onTap, child: Text(label)),
      );
}

/// The small pictures of the marks that were read, with the value under each.
class _CropStrip extends StatelessWidget {
  const _CropStrip({required this.marks, this.loadCrop});
  final List<MarkPart> marks;
  final Future<Uint8List?> Function(String url)? loadCrop;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('ما قرأناه من الورقة', 'What was read from the paper'), style: AppType.meta(context)),
      const SizedBox(height: AppSpace.xxs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [for (final m in marks) _Crop(key: ValueKey('rv.crop.${m.fieldId}'), part: m, loadCrop: loadCrop)]),
    ]);
  }
}

class _Crop extends StatefulWidget {
  const _Crop({super.key, required this.part, this.loadCrop});
  final MarkPart part;
  final Future<Uint8List?> Function(String url)? loadCrop;

  @override
  State<_Crop> createState() => _CropState();
}

class _CropState extends State<_Crop> {
  Future<Uint8List?>? _f;

  @override
  void initState() {
    super.initState();
    final u = widget.part.cropUrl;
    if (u != null && u.isNotEmpty && widget.loadCrop != null) _f = widget.loadCrop!(u);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.part;
    return Container(
      width: 84,
      padding: const EdgeInsets.all(AppSpace.xxs),
      decoration: BoxDecoration(borderRadius: AppRadius.cardAll, border: Border.all(color: (p.ok ? c.divider : c.danger).withValues(alpha: .6))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: 36,
          width: double.infinity,
          child: _f == null
              ? ColoredBox(color: c.background)
              : FutureBuilder<Uint8List?>(
                  future: _f,
                  builder: (_, s) => s.data == null ? ColoredBox(color: c.background) : Image.memory(s.data!, fit: BoxFit.contain, gaplessPlayback: true),
                ),
        ),
        Text('${t('سؤال', 'Q')} ${p.questionNo ?? p.fieldId}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
        Text(markNumberText(p.value), maxLines: 1, style: AppType.bodyStrong(context).copyWith(color: p.ok ? null : c.danger)),
      ]),
    );
  }
}
