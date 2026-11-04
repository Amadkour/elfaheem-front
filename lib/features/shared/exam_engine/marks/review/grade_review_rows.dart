// The plain-values widgets of the review results (contract §5): a row's tile, its detail (crops, written vs computed
// total, identifier), and the three small sheets of the decisions (apply with old → new, fix a mark, assign a
// student). Callbacks out, no provider and no platform object, so the layout harness pumps them as they are.
library;


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import '../../../../admin/admin_common.dart' show t;
import '../mark_sessions_api.dart';
import 'grade_review_start.dart';

/// Why a row is where it is, in the person's words.
String gradeIssueText(String code) => switch (code) {
      'unknown_student' => t('الطالب غير معروف', 'Unknown student'),
      'student_twice' => t('الطالب ظهر أكثر من مرة', 'The student appears twice'),
      'mark_above_max' => t('درجة أكبر من الحد الأقصى', 'A mark is above its maximum'),
      'mark_unreadable' || 'unreadable_mark' => t('درجة غير مقروءة', 'A mark is unreadable'),
      'student_unreadable' => t('رقم الطالب غير مقروء', 'The student number is unreadable'),
      'student_ambiguous' => t('أكثر من طالب بهذا الرقم', 'More than one student has this number'),
      'name_unconfirmed' => t('الاسم بخط اليد: أكّد الطالب', 'Only a handwritten name: confirm the student'),
      'mark_blank' => t('خانة درجة فارغة', 'A mark box is empty'),
      'total_unreadable' => t('المجموع المكتوب غير مقروء', 'The written total is unreadable'),
      'paper_sum_error' => t('جمع الورقة خاطئ', "The paper's addition is wrong"),
      'scaled' => t('محوَّلة إلى مقياس العمود', "Converted to the column's scale"),
      'not_recorded' => t('لا توجد درجة مسجّلة', 'No recorded grade'),
      _ => code,
    };

/// The server's wording of [code] on [row] (in the app language) when it sent one, else the built-in text.
String gradeRowIssueText(MarkRow row, String code) {
  final s = row.issueTexts[code];
  final text = s == null ? '' : (AppConfig.lang == 'en' ? s.en : s.ar);
  return text.isNotEmpty ? text : gradeIssueText(code);
}

bool gradeIssueIsProblem(String code) => !MarkRow.infoIssues.contains(code);

String gradeStatusText(String status) => switch (status) {
      'applied' => t('طُبِّقت', 'Applied'),
      'kept' => t('أُبقيت', 'Kept'),
      'dismissed' => t('تم التجاهل', 'Dismissed'),
      _ => '',
    };

/// The row's headline: who, and what the paper says against the book.
String gradeRowName(MarkRow r) => (r.studentName ?? '').isNotEmpty ? r.studentName! : t('طالب غير معروف', 'Unknown student');

String _signed(double? v) => v == null ? '' : '${v > 0 ? '+' : ''}${markNumberText(v)}';

class GradeRowTile extends StatelessWidget {
  const GradeRowTile({super.key, required this.row, required this.list, this.selected = false, this.onTap});

  final MarkRow row;
  final MarkList list;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = switch (list) { MarkList.match => c.success, MarkList.mismatch => c.warning, MarkList.unreadable => c.danger };
    final status = gradeStatusText(row.status);
    final problems = row.issues.where(gradeIssueIsProblem).toList();
    final String line = switch (list) {
      MarkList.match => '${t('الورقة', 'Paper')} ${markNumberText(row.used)} · ${t('المسجّل', 'Recorded')} ${markNumberText(row.recorded)}',
      MarkList.mismatch => row.recorded == null
          ? '${t('الورقة', 'Paper')} ${markNumberText(row.used)}${row.scaled != null && row.scaled != row.used ? ' → ${markNumberText(row.scaled)}' : ''} · ${t('غير مسجّلة', 'not recorded')}'
          : '${t('الورقة', 'Paper')} ${markNumberText(row.used)}${row.scaled != null && row.scaled != row.used ? ' → ${markNumberText(row.scaled)}' : ''} ${t('مقابل', 'vs')} ${t('المسجّل', 'recorded')} ${markNumberText(row.recorded)} · ${t('الفرق', 'diff')} ${_signed(row.diff ?? (row.proposed != null ? row.proposed! - row.recorded! : null))}',
      MarkList.unreadable => problems.isEmpty ? t('تحتاج مراجعة', 'Needs a look') : problems.map((i) => gradeRowIssueText(row, i)).join(' · '),
    };
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Container(
        decoration: selected ? BoxDecoration(border: BorderDirectional(start: BorderSide(color: c.primary, width: 3))) : null,
        padding: selected ? const EdgeInsetsDirectional.only(start: AppSpace.xs) : null,
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: tone.withValues(alpha: .14), shape: BoxShape.circle),
            child: Icon(switch (list) { MarkList.match => Icons.check_rounded, MarkList.mismatch => Icons.compare_arrows_rounded, MarkList.unreadable => Icons.warning_amber_rounded }, color: tone, size: 20),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(gradeRowName(row), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14.5, w: FontWeight.w700, c: c.textDark)),
              Text(line, maxLines: 3, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium, h: 1.35)),
            ]),
          ),
          if (status.isNotEmpty) ...[
            const SizedBox(width: AppSpace.xs),
            AppTag(status, row.status == 'applied' ? c.success : c.textMedium),
          ],
          Icon(Icons.chevron_right_rounded, color: c.textLight),
        ]),
      ),
    );
  }
}

/// A mark's crop with its value: the picture comes from [loadCrop] (null: no picture, text only).
class GradeMarkTile extends StatefulWidget {
  const GradeMarkTile({super.key, required this.part, this.loadCrop, this.onFix});
  final MarkPart part;
  final Future<Uint8List?> Function(String url)? loadCrop;

  /// Null once the row was decided.
  final VoidCallback? onFix;

  @override
  State<GradeMarkTile> createState() => _GradeMarkTileState();
}

class _GradeMarkTileState extends State<GradeMarkTile> {
  Future<Uint8List?>? _crop;

  @override
  void initState() {
    super.initState();
    final u = widget.part.cropUrl;
    if (u != null && u.isNotEmpty && widget.loadCrop != null) _crop = widget.loadCrop!(u);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.part;
    final conf = p.conf == null ? '' : ' · ${(p.conf! * 100).round()}%';
    return Container(
      padding: const EdgeInsets.all(AppSpace.xs),
      decoration: BoxDecoration(
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: (p.ok ? c.divider : c.danger).withValues(alpha: .6)),
      ),
      child: Row(children: [
        if (_crop != null)
          SizedBox(
            width: 96,
            height: 48,
            child: FutureBuilder<Uint8List?>(
              future: _crop,
              builder: (_, s) => s.data == null
                  ? DecoratedBox(decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(6)), child: Icon(Icons.image_outlined, color: c.textLight))
                  : ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.memory(s.data!, fit: BoxFit.contain, gaplessPlayback: true)),
            ),
          ),
        if (_crop != null) const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${t('سؤال', 'Q')} ${p.questionNo ?? p.fieldId}', maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textLight)),
            Text('${markNumberText(p.value)} / ${markNumberText(p.max)}$conf', maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: p.ok ? c.textDark : c.danger)),
            if (!p.ok) Text(p.status == 'above_max' ? t('أكبر من الحد الأقصى', 'Above the maximum') : t('غير مقروءة', 'Unreadable'), style: appText(11.5, c: c.danger)),
          ]),
        ),
        if (widget.onFix != null)
          IconButton(
            tooltip: t('تصحيح القراءة', 'Fix the reading'),
            constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
            onPressed: widget.onFix,
            icon: Icon(Icons.edit_outlined, color: c.primary),
          ),
      ]),
    );
  }
}

class GradeRowDetail extends StatelessWidget {
  const GradeRowDetail({
    super.key,
    required this.row,
    required this.session,
    this.loadCrop,
    this.onApply,
    this.onKeep,
    this.onDismiss,
    this.onAssign,
    this.onFix,
  });

  final MarkRow row;
  final MarkSession session;
  final Future<Uint8List?> Function(String url)? loadCrop;

  /// Null = not offered (row decided, nothing to write, or a blocking issue is open).
  final VoidCallback? onApply, onKeep, onDismiss, onAssign;
  final void Function(MarkPart part)? onFix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = appText(12, c: c.textLight);
    final sumError = row.has('paper_sum_error');
    Widget kv(String k, String v, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(k, style: label)),
            const SizedBox(width: AppSpace.xs),
            Flexible(child: Text(v, textAlign: TextAlign.end, style: appText(13.5, w: FontWeight.w700, c: color ?? c.textDark))),
          ]),
        );
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(gradeRowName(row), style: appText(17, w: FontWeight.w800, c: c.textDark)),
      if (row.identifierMasked.isNotEmpty)
        Text('${t('الرقم', 'Number')}: ${row.identifierMasked}${row.identifierMethod == null ? '' : ' · ${row.identifierMethod}'}', textDirection: TextDirection.ltr, style: appText(12.5, c: c.textMedium)),
      if (row.decided) ...[
        const SizedBox(height: AppSpace.xs),
        Align(alignment: AlignmentDirectional.centerStart, child: AppTag(gradeStatusText(row.status), row.status == 'applied' ? c.success : c.textMedium)),
      ],
      const SizedBox(height: AppSpace.sm),
      if (sumError)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppBanner(
            key: const ValueKey('gr.sumerror'),
            icon: Icons.calculate_outlined,
            color: c.warning,
            text: t('جمع الورقة خاطئ: المكتوب ${markNumberText(row.written)} بينما مجموع الأجزاء ${markNumberText(row.computed)}. نستخدم المجموع المحسوب.',
                "The paper's addition is wrong: written ${markNumberText(row.written)}, but the parts add up to ${markNumberText(row.computed)}. The computed total is used."),
          ),
        ),
      AppCard(
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Column(children: [
          kv(t('المجموع المكتوب', 'Written total'), markNumberText(row.written)),
          kv(t('المجموع المحسوب', 'Computed total'), markNumberText(row.computed), color: sumError ? c.warning : null),
          if (session.converts) kv(t('بعد التحويل', 'After conversion'), '${markNumberText(row.scaled)} / ${markNumberText(session.columnMax)}'),
          kv(t('المسجّل في الدفتر', 'Recorded in the gradebook'), row.recorded == null ? t('لا شيء', 'nothing') : markNumberText(row.recorded)),
          if (row.diff != null && row.diff != 0) kv(t('الفرق', 'Difference'), _signed(row.diff), color: c.warning),
        ]),
      ),
      if (row.issues.any(gradeIssueIsProblem)) ...[
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final i in row.issues.where(gradeIssueIsProblem)) AppTag(gradeRowIssueText(row, i), c.danger, icon: Icons.error_outline_rounded),
        ]),
      ],
      if (row.marks.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        AppSectionTitle(t('الدرجات المقروءة', 'Marks read')),
        for (final m in row.marks)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: GradeMarkTile(part: m, loadCrop: loadCrop, onFix: (row.decided || onFix == null) ? null : () => onFix!(m)),
          ),
      ],
      if (!row.decided) ...[
        const SizedBox(height: AppSpace.md),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, alignment: WrapAlignment.start, children: [
          if (onApply != null)
            _Act(key: const ValueKey('gr.act.apply'), icon: Icons.check_circle_outline_rounded, label: t('تطبيق التصحيح (A)', 'Apply correction (A)'), primary: true, onTap: onApply!),
          if (onKeep != null) _Act(key: const ValueKey('gr.act.keep'), icon: Icons.lock_outline_rounded, label: t('إبقاء المسجّل (H)', 'Keep recorded (H)'), onTap: onKeep!),
          if (onAssign != null) _Act(key: const ValueKey('gr.act.assign'), icon: Icons.person_search_outlined, label: t('تحديد الطالب', 'Assign student'), onTap: onAssign!),
          if (onDismiss != null) _Act(key: const ValueKey('gr.act.dismiss'), icon: Icons.close_rounded, label: t('تجاهل (D)', 'Dismiss (D)'), onTap: onDismiss!),
        ]),
      ],
    ]);
  }
}

class _Act extends StatelessWidget {
  const _Act({super.key, required this.icon, required this.label, required this.onTap, this.primary = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(AppTouch.min, AppTouch.min)));
    return primary
        ? FilledButton.icon(style: style, onPressed: onTap, icon: Icon(icon, size: 18), label: Text(label))
        : OutlinedButton.icon(style: style, onPressed: onTap, icon: Icon(icon, size: 18, color: c.primary), label: Text(label));
  }
}

/// Apply: the old and the new value side by side, an optional reason, and the confirmation. The grade is written only
/// when this is confirmed (D-173: the system never changes a grade by itself).
class GradeApplySheet extends StatefulWidget {
  const GradeApplySheet({super.key, required this.row, required this.columnLabel, required this.onConfirm});
  final MarkRow row;
  final String columnLabel;
  final void Function(String reason) onConfirm;

  @override
  State<GradeApplySheet> createState() => _GradeApplySheetState();
}

class _GradeApplySheetState extends State<GradeApplySheet> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = widget.row;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${gradeRowName(r)} · ${widget.columnLabel}', style: appText(14, w: FontWeight.w700, c: c.textDark)),
      const SizedBox(height: AppSpace.sm),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Flexible(child: Text(r.recorded == null ? t('لا شيء', 'nothing') : markNumberText(r.recorded), key: const ValueKey('gr.apply.old'), style: appText(26, w: FontWeight.w800, c: c.textLight))),
        const Padding(padding: EdgeInsets.symmetric(horizontal: AppSpace.sm), child: Icon(Icons.arrow_forward_rounded)),
        Flexible(child: Text(markNumberText(r.proposed), key: const ValueKey('gr.apply.new'), style: appText(26, w: FontWeight.w800, c: c.primary))),
      ]),
      const SizedBox(height: AppSpace.sm),
      AppField(controller: _reason, label: t('السبب (اختياري)', 'Reason (optional)'), maxLines: 2),
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(label: t('تأكيد التطبيق', 'Confirm and write'), icon: Icons.check_rounded, onPressed: () => widget.onConfirm(_reason.text)),
    ]);
  }
}

/// A misread mark corrected by hand: a number between 0 and the field's maximum.
class GradeFixMarkSheet extends StatefulWidget {
  const GradeFixMarkSheet({super.key, required this.part, required this.onSave});
  final MarkPart part;
  final void Function(double value) onSave;

  @override
  State<GradeFixMarkSheet> createState() => _GradeFixMarkSheetState();
}

class _GradeFixMarkSheetState extends State<GradeFixMarkSheet> {
  late final _ctl = TextEditingController(text: widget.part.value == null ? '' : markNumberText(widget.part.value));
  String? _error;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _save() {
    final v = double.tryParse(_ctl.text.trim().replaceAll(',', '.').replaceAll('٫', '.'));
    final max = widget.part.max;
    if (v == null || v < 0 || (max != null && v > max)) {
      setState(() => _error = max == null ? t('أدخل رقمًا صحيحًا', 'Enter a valid number') : t('أدخل رقمًا بين 0 و ${markNumberText(max)}', 'Enter a number from 0 to ${markNumberText(max)}'));
      return;
    }
    widget.onSave(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${t('سؤال', 'Q')} ${widget.part.questionNo ?? widget.part.fieldId} · ${t('الحد الأقصى', 'max')} ${markNumberText(widget.part.max)}', style: appText(13.5, c: c.textMedium)),
      const SizedBox(height: AppSpace.sm),
      AppField(
        controller: _ctl,
        label: t('الدرجة الصحيحة', 'The right mark'),
        keyboard: const TextInputType.numberWithOptions(decimal: true),
        ltr: true,
        onSubmitted: (_) => _save(),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
      ),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: Text(_error!, key: const ValueKey('gr.fix.error'), style: appText(12.5, c: c.danger))),
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(label: t('حفظ وإعادة الحساب', 'Save and recompute'), icon: Icons.check_rounded, onPressed: _save),
    ]);
  }
}

/// Searches the course's students (from the Data Lab grid) and answers the chosen one.
class GradeAssignSheet extends StatefulWidget {
  const GradeAssignSheet({super.key, required this.students, required this.onPick});
  final List<GradeStudent> students;
  final void Function(GradeStudent s) onPick;

  @override
  State<GradeAssignSheet> createState() => _GradeAssignSheetState();
}

class _GradeAssignSheetState extends State<GradeAssignSheet> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = _q.text.trim().toLowerCase();
    final shown = [for (final s in widget.students) if (q.isEmpty || s.name.toLowerCase().contains(q)) s].take(60).toList();
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppField(controller: _q, label: t('ابحث عن طالب', 'Search a student'), onChanged: (_) => setState(() {})),
      const SizedBox(height: AppSpace.xs),
      if (shown.isEmpty)
        Padding(padding: const EdgeInsets.all(AppSpace.md), child: Text(t('لا نتائج', 'No matches'), textAlign: TextAlign.center, style: appText(13, c: c.textMedium)))
      else
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: shown.length,
            itemBuilder: (_, i) => ListTile(
              key: ValueKey('gr.student.${shown[i].id}'),
              minTileHeight: AppTouch.min,
              leading: Icon(Icons.person_outline_rounded, color: c.primary),
              title: Text(shown[i].name, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => widget.onPick(shown[i]),
            ),
          ),
        ),
    ]);
  }
}

/// The one-line shortcut help drawn on wide screens.
String gradeShortcutsText() => t('J التالي · K السابق · Enter فتح · A تطبيق · H إبقاء · D تجاهل', 'J next · K previous · Enter open · A apply · H keep · D dismiss');

/// Keys of the results list (desktop / web).
const gradeKeyNext = LogicalKeyboardKey.keyJ;
const gradeKeyPrev = LogicalKeyboardKey.keyK;
const gradeKeyApply = LogicalKeyboardKey.keyA;
const gradeKeyKeep = LogicalKeyboardKey.keyH;
const gradeKeyDismiss = LogicalKeyboardKey.keyD;
