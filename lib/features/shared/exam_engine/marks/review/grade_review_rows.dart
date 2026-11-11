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
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_chip.dart';

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

/// A mark's crop beside its value, and the tallest the student picker grows in its sheet.
const _cropWidth = 96.0;
const _pickerHeight = 320.0;

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
    final iconTone = switch (list) { MarkList.match => AppTone.success, MarkList.mismatch => AppTone.warning, MarkList.unreadable => AppTone.danger };
    final tone = appInk(context, appToneColor(context, iconTone));
    final status = gradeStatusText(row.status);
    final problems = row.issues.where(gradeIssueIsProblem).toList();
    final String line = switch (list) {
      MarkList.match => '${t('الورقة', 'Paper')} ${markNumberText(row.used)} · ${t('المسجّل', 'Recorded')} ${markNumberText(row.recorded)}',
      MarkList.mismatch => row.recorded == null
          ? '${t('الورقة', 'Paper')} ${markNumberText(row.used)}${row.scaled != null && row.scaled != row.used ? ' → ${markNumberText(row.scaled)}' : ''} · ${t('غير مسجّلة', 'not recorded')}'
          : '${t('الورقة', 'Paper')} ${markNumberText(row.used)}${row.scaled != null && row.scaled != row.used ? ' → ${markNumberText(row.scaled)}' : ''} ${t('مقابل', 'vs')} ${t('المسجّل', 'recorded')} ${markNumberText(row.recorded)} · ${t('الفرق', 'diff')} ${_signed(row.diff ?? (row.proposed != null ? row.proposed! - row.recorded! : null))}',
      MarkList.unreadable => problems.isEmpty ? t('تحتاج مراجعة', 'Needs a look') : problems.map((i) => gradeRowIssueText(row, i)).join(' · '),
    };
    // the open row (keyboard / wide) wears the table's "current" look: the primary tint and a start-side bar
    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? c.primaryTint : null,
          border: selected ? BorderDirectional(start: BorderSide(color: c.primary, width: AppBorder.focus)) : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Row(children: [
            Container(
              width: AppIconSize.hero,
              height: AppIconSize.hero,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tone.withValues(alpha: .12), borderRadius: AppRadius.chipAll),
              child: Icon(switch (list) { MarkList.match => Icons.check_rounded, MarkList.mismatch => Icons.compare_arrows_rounded, MarkList.unreadable => Icons.warning_amber_rounded }, color: tone, size: AppIconSize.md),
            ),
            AppSpace.gapSm,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(gradeRowName(row), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpace.xxs),
                Text(line, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(height: 1.35)),
              ]),
            ),
            if (status.isNotEmpty) ...[
              AppSpace.gapXs,
              AppStatusBadge(label: status, tone: row.status == 'applied' ? AppTone.success : AppTone.neutral, dense: true),
            ],
            Icon(Icons.chevron_right_rounded, size: AppIconSize.lg, color: c.textLight),
          ]),
        ),
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
    final danger = appInk(context, c.danger);
    // paper on a warm hairline; a reading that needs a person is edged in danger and says why
    return Container(
      padding: const EdgeInsets.all(AppSpace.xs),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: p.ok ? c.divider : danger.withValues(alpha: .6), width: AppBorder.hairline),
      ),
      child: Row(children: [
        if (_crop != null)
          SizedBox(
            width: _cropWidth,
            height: AppTouch.min,
            child: FutureBuilder<Uint8List?>(
              future: _crop,
              builder: (_, s) => s.data == null
                  ? DecoratedBox(decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll), child: Icon(Icons.image_outlined, size: AppIconSize.md, color: c.textLight))
                  : ClipRRect(borderRadius: AppRadius.chipAll, child: Image.memory(s.data!, fit: BoxFit.contain, gaplessPlayback: true)),
            ),
          ),
        if (_crop != null) AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${t('سؤال', 'Q')} ${p.questionNo ?? p.fieldId}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            Text('${markNumberText(p.value)} / ${markNumberText(p.max)}$conf',
                maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.figure(context).copyWith(color: p.ok ? c.textDark : danger)),
            if (!p.ok) Text(p.status == 'above_max' ? t('أكبر من الحد الأقصى', 'Above the maximum') : t('غير مقروءة', 'Unreadable'), style: AppType.meta(context).copyWith(color: danger)),
          ]),
        ),
        if (widget.onFix != null)
          IconButton(
            tooltip: t('تصحيح القراءة', 'Fix the reading'),
            constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
            onPressed: widget.onFix,
            icon: Icon(Icons.edit_outlined, size: AppIconSize.md, color: appInk(context, c.primary)),
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
    this.onRetake,
  });

  final MarkRow row;
  final MarkSession session;
  final Future<Uint8List?> Function(String url)? loadCrop;

  /// Null = not offered (row decided, nothing to write, or a blocking issue is open).
  final VoidCallback? onApply, onKeep, onDismiss, onAssign, onRetake;
  final void Function(MarkPart part)? onFix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sumError = row.has('paper_sum_error');
    final problems = row.issues.where(gradeIssueIsProblem).toList();
    final warning = appInk(context, c.warning);
    Widget kv(String k, String v, {Color? color}) => ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xs),
          child: Row(children: [
            Expanded(flex: 3, child: Text(k, style: AppType.meta(context))),
            AppSpace.gapXs,
            Expanded(flex: 2, child: Text(v, textAlign: TextAlign.end, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600, color: color ?? c.textDark))),
          ]),
        );
    final rows = <Widget>[
      kv(t('المجموع المكتوب', 'Written total'), markNumberText(row.written)),
      kv(t('المجموع المحسوب', 'Computed total'), markNumberText(row.computed), color: sumError ? warning : null),
      if (session.converts) kv(t('بعد التحويل', 'After conversion'), '${markNumberText(row.scaled)} / ${markNumberText(session.columnMax)}'),
      kv(t('المسجّل في الدفتر', 'Recorded in the gradebook'), row.recorded == null ? t('لا شيء', 'nothing') : markNumberText(row.recorded)),
      if (row.diff != null && row.diff != 0) kv(t('الفرق', 'Difference'), _signed(row.diff), color: warning),
    ];
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // the paper, on a block in the colour of where it stands (gradeRowTone)
      AppBlock(
        tone: gradeRowTone(row),
        padding: AppSpace.block,
        child: Builder(builder: (context) {
          final b = AppBlock.colorsOf(context);
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(gradeRowName(row), style: AppType.headline(context).copyWith(color: b.ink)),
            // the matched student opens their record where the server allows it (D-290)
            if (row.studentId != null) ...[
              const SizedBox(height: AppSpace.xxs),
              EntityGuardedChip(EntityRef(EntityKind.student, row.studentId!, label: gradeRowName(row))),
            ],
            if (row.identifierMasked.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xxs),
              Text('${t('الرقم', 'Number')}: ${row.identifierMasked}${row.identifierMethod == null ? '' : ' · ${row.identifierMethod}'}',
                  textDirection: TextDirection.ltr, style: AppType.meta(context).copyWith(color: b.muted)),
            ],
            if (row.decided) ...[
              AppSpace.gapXs,
              AppStatusBadge(label: gradeStatusText(row.status), tone: row.status == 'applied' ? AppTone.success : AppTone.neutral, dense: true),
            ],
            if (problems.isNotEmpty) ...[
              AppSpace.gapSm,
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (final i in problems) AppStatusBadge(label: gradeRowIssueText(row, i), tone: AppTone.danger, icon: Icons.error_outline_rounded, dense: true),
              ]),
            ],
          ]);
        }),
      ),
      AppSpace.gapSm,
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
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xxs),
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
            rows[i],
          ],
        ]),
      ),
      if (row.marks.isNotEmpty) ...[
        AppSpace.gapLg,
        Text(t('الدرجات المقروءة', 'Marks read'), style: AppType.section(context)),
        for (final m in row.marks)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: GradeMarkTile(part: m, loadCrop: loadCrop, onFix: (row.decided || onFix == null) ? null : () => onFix!(m)),
          ),
      ],
      if (!row.decided) ...[
        AppSpace.gapLg,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, alignment: WrapAlignment.start, children: [
          if (onApply != null)
            _Act(key: const ValueKey('gr.act.apply'), icon: Icons.check_circle_outline_rounded, label: t('تطبيق التصحيح (A)', 'Apply correction (A)'), primary: true, onTap: onApply!),
          if (onKeep != null) _Act(key: const ValueKey('gr.act.keep'), icon: Icons.lock_outline_rounded, label: t('إبقاء المسجّل (H)', 'Keep recorded (H)'), onTap: onKeep!),
          if (onAssign != null) _Act(key: const ValueKey('gr.act.assign'), icon: Icons.person_search_outlined, label: t('تحديد الطالب', 'Assign student'), onTap: onAssign!),
          if (onRetake != null) _Act(key: const ValueKey('gr.act.retake'), icon: Icons.replay_rounded, label: t('إعادة التصوير', 'Retake scan'), onTap: onRetake!),
          if (onDismiss != null) _Act(key: const ValueKey('gr.act.dismiss'), icon: Icons.close_rounded, label: t('تجاهل (D)', 'Dismiss (D)'), ghost: true, onTap: onDismiss!),
        ]),
      ],
    ]);
  }
}

/// Where a paper stands, as a block (system.md §5): something to sort out = paper with the problems on it, the book
/// already agrees or the correction was written = emerald, a difference to decide = peach.
AppBlockTone gradeRowTone(MarkRow row) {
  if (row.status == 'applied') return AppBlockTone.emerald;
  if (row.issues.any(gradeIssueIsProblem)) return AppBlockTone.paper;
  final diff = row.diff ?? (row.proposed != null && row.recorded != null ? row.proposed! - row.recorded! : null);
  if (row.recorded != null && (diff == null || diff == 0)) return AppBlockTone.emerald;
  return AppBlockTone.peach;
}

class _Act extends StatelessWidget {
  const _Act({super.key, required this.icon, required this.label, required this.onTap, this.primary = false, this.ghost = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary, ghost;

  @override
  Widget build(BuildContext context) {
    if (primary) return AppButton.primary(label: label, icon: icon, onPressed: onTap);
    if (ghost) return AppButton.ghost(label: label, icon: icon, onPressed: onTap);
    return AppButton.secondary(label: label, icon: icon, onPressed: onTap);
  }
}

/// Apply: the old and the new value side by side, an optional reason, and the confirmation. The grade is written only
/// when this is confirmed (D-243: the system never changes a grade by itself).
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
    final r = widget.row;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${gradeRowName(r)} · ${widget.columnLabel}', style: AppType.bodyStrong(context)),
      AppSpace.gapSm,
      // the change itself, on the block of work to decide: the book's value struck through, the paper's in emerald
      AppBlock(
        tone: AppBlockTone.peach,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
        child: Builder(builder: (context) {
          final b = AppBlock.colorsOf(context);
          final figure = AppType.figureLarge(context);
          return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(
              child: Text(r.recorded == null ? t('لا شيء', 'nothing') : markNumberText(r.recorded),
                  key: const ValueKey('gr.apply.old'),
                  style: figure.copyWith(color: b.muted, decoration: TextDecoration.lineThrough, decorationColor: b.muted)),
            ),
            Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.md), child: Icon(Icons.arrow_forward_rounded, size: AppIconSize.lg, color: b.muted)),
            Flexible(child: Text(markNumberText(r.proposed), key: const ValueKey('gr.apply.new'), style: figure.copyWith(color: b.accentInk(context.colors.primary)))),
          ]);
        }),
      ),
      AppSpace.gapMd,
      AppField(controller: _reason, label: t('السبب (اختياري)', 'Reason (optional)'), maxLines: 2),
      AppSpace.gapLg,
      AppButton.primary(label: t('تأكيد التطبيق', 'Confirm and write'), icon: Icons.check_rounded, expand: true, onPressed: () => widget.onConfirm(_reason.text)),
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
      Text('${t('سؤال', 'Q')} ${widget.part.questionNo ?? widget.part.fieldId} · ${t('الحد الأقصى', 'max')} ${markNumberText(widget.part.max)}', style: AppType.body(context)),
      const SizedBox(height: AppSpace.sm),
      Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: AppNumberField(controller: _ctl, label: t('الدرجة الصحيحة', 'The right mark'), min: 0, max: widget.part.max, step: 0.5, decimals: 2, onSubmitted: (_) => _save(), onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        })),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: Text(_error!, key: const ValueKey('gr.fix.error'), style: AppType.meta(context).copyWith(color: appInk(context, c.danger)))),
      const SizedBox(height: AppSpace.md),
      AppButton.primary(label: t('حفظ وإعادة الحساب', 'Save and recompute'), icon: Icons.check_rounded, expand: true, onPressed: _save),
    ]);
  }
}

/// Searches the course's students (from the Data Lab grid) and answers the chosen one.
class GradeAssignSheet extends StatefulWidget {
  const GradeAssignSheet({super.key, required this.students, required this.onPick, this.taken = const {}});
  final List<GradeStudent> students;

  /// Students who already have a paper here: marked, still choosable.
  final Set<int> taken;
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
        Padding(padding: const EdgeInsets.all(AppSpace.md), child: Text(t('لا نتائج', 'No matches'), textAlign: TextAlign.center, style: AppType.body(context)))
      else
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: _pickerHeight),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: shown.length,
            itemBuilder: (_, i) => ListTile(
              key: ValueKey('gr.student.${shown[i].id}'),
              minTileHeight: AppTouch.min,
              leading: Icon(Icons.person_outline_rounded, color: c.primary),
              title: Text(shown[i].name, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: widget.taken.contains(shown[i].id) ? Text(t('له ورقة أخرى في هذه المراجعة', 'Already has a paper in this revision'), style: AppType.meta(context).copyWith(color: appInk(context, c.warning))) : null,
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
