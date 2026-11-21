// lib/features/org/students/transfer_credits_sheet.dart — transfer credit (المقاصة) of a transferred-in student
// (student lifecycle phase 6, contract §9, PLAN §1 "Gap: transfer credit"): one row per course taken elsewhere —
// source institution, course, code, grade, hours → our equivalent course and the hours it counts for here; an
// approver (academic:approve) credits it or not; the organization decides whether credited courses enter the GPA.
//
//   showTransferCreditsSheet(context, orgId, uid, {name})   the side panel; loads GET …/students/{uid}/transfer-credits
//   TransferCreditsView      plain values: the summary, the rows, the verbs `can` allows
//   TransferCreditCard       one row
//   TransferCreditForm       add / edit one row (our course comes from a search sheet)
//   TransferCreditSettingsForm   counts in GPA by default · the minimum letter (a warning only)
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../org_v3.dart' show OrgCall;
import 'student_requests_api.dart';

/// The transfer-credit panel of student [uid].
Future<void> showTransferCreditsSheet(BuildContext context, int orgId, int uid, {String? name, StudentRequestsApi? api}) =>
    showAppSheet<void>(context, (ctx) => _CreditsSheet(api: api ?? StudentRequestsApi(orgId), uid: uid, name: name), mode: AppSheetMode.side);

class _CreditsSheet extends StatefulWidget {
  const _CreditsSheet({required this.api, required this.uid, this.name});
  final StudentRequestsApi api;
  final int uid;
  final String? name;

  @override
  State<_CreditsSheet> createState() => _CreditsSheetState();
}

class _CreditsSheetState extends State<_CreditsSheet> {
  TransferCredits? _data;
  String? _error;
  final Set<int> _busy = {};

  StudentRequestsApi get _api => widget.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.credits(widget.uid);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _data = TransferCredits.fromJson(r.map);
        _error = null;
      } else {
        _error = requestsErrorText(r.error!);
      }
    });
  }

  Future<CourseChoice?> _pickCourse() => showAppSheet<CourseChoice>(context, (ctx) => _CoursePickSheet(api: _api));

  Future<void> _edit([TransferCredit? c]) async {
    final changed = await showAppSheet<bool>(
      context,
      (ctx) => AppSheetContent(
        title: c == null ? t('أضف مقرراً من الجهة السابقة', 'Add a course from the previous place') : t('عدّل المقاصة', 'Edit the credit'),
        icon: Icons.swap_horiz_rounded,
        children: [
          TransferCreditForm(
            initial: c == null ? null : CreditDraft.of(c),
            onPickCourse: _pickCourse,
            onSave: (d) async {
              final OrgCall r = c == null ? await _api.addCredit(widget.uid, d.toJson()) : await _api.patchCredit(c.id, d.toJson());
              if (!r.ok) return requestsErrorText(r.error!);
              if (ctx.mounted) Navigator.of(ctx).pop(true);
              return null;
            },
          ),
        ],
      ),
    );
    if (changed == true && mounted) {
      showAppNotice(t('حُفظت المقاصة', 'The credit was saved'));
      _load();
    }
  }

  Future<void> _run(TransferCredit c, Future<OrgCall> Function() fn, String ok) async {
    if (_busy.contains(c.id)) return;
    setState(() => _busy.add(c.id));
    final r = await fn();
    if (!mounted) return;
    setState(() => _busy.remove(c.id));
    if (!r.ok) {
      showAppNotice(requestsErrorText(r.error!), error: true);
      return;
    }
    showAppNotice(ok);
    _load();
  }

  Future<void> _decide(TransferCredit c, String decision) => _run(c, () => _api.patchCredit(c.id, {'decision': decision}), switch (decision) {
        'credited' => t('احتُسب المقرر', 'The course was credited'),
        'not_credited' => t('سُجّل أن المقرر لا يُحتسب', 'Marked as not credited'),
        _ => t('أُعيدت المقاصة إلى قيد الدراسة', 'Back to pending'),
      });

  Future<void> _delete(TransferCredit c) async {
    final ok = await appConfirm(context,
        danger: true, confirmLabel: t('احذف', 'Delete'), message: t('حذف «${c.sourceCourse}» من المقاصة؟', 'Delete "${c.sourceCourse}" from the transfer credit?'));
    if (!ok || !mounted) return;
    await _run(c, () => _api.deleteCredit(c.id), t('حُذفت', 'Deleted'));
  }

  Future<void> _settings() async {
    final d = _data;
    if (d == null) return;
    final saved = await showAppSheet<bool>(
      context,
      (ctx) => AppSheetContent(
        title: t('قواعد المقاصة', 'Transfer credit rules'),
        icon: Icons.tune_rounded,
        children: [
          TransferCreditSettingsForm(
            initial: d.settings,
            onSave: (s) async {
              final r = await _api.saveCreditSettings(s);
              if (!r.ok) {
                return r.error!.statusCode == 403
                    ? t('لا تملك صلاحية تغيير قواعد المقاصة. تحتاج صلاحية تعديل الشؤون الأكاديمية.', 'You cannot change the transfer credit rules: it needs the right to edit academic settings.')
                    : requestsErrorText(r.error!);
              }
              if (ctx.mounted) Navigator.of(ctx).pop(true);
              return null;
            },
          ),
        ],
      ),
    );
    if (saved == true && mounted) {
      showAppNotice(t('حُفظت القواعد', 'The rules were saved'));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return AppSheetContent(
      title: t('المقاصة', 'Transfer credit'),
      subtitle: widget.name,
      icon: Icons.swap_horiz_rounded,
      children: [
        if (d == null)
          _error != null ? AppErrorState(message: _error, onRetry: _load, compact: true) : const AppListSkeleton(items: 3)
        else
          TransferCreditsView(
            data: d,
            busy: _busy,
            onAdd: d.canEdit ? () => _edit() : null,
            onEdit: d.canEdit ? _edit : null,
            onDecide: d.canDecide ? _decide : null,
            onDelete: d.canEdit ? _delete : null,
            onSettings: d.canSettings ? _settings : null,
          ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The list (plain values)
// ═════════════════════════════════════════════════════════════════════════════

class TransferCreditsView extends StatelessWidget {
  const TransferCreditsView({
    super.key,
    required this.data,
    this.busy = const {},
    this.onAdd,
    this.onEdit,
    this.onDecide,
    this.onDelete,
    this.onSettings,
  });

  final TransferCredits data;
  final Set<int> busy;
  final VoidCallback? onAdd;
  final ValueChanged<TransferCredit>? onEdit;
  final void Function(TransferCredit credit, String decision)? onDecide;
  final ValueChanged<TransferCredit>? onDelete;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final d = data;
    final c = context.colors;
    final summary = [
      countText(d.credited, ar1: 'مقرر محتسب', ar2: 'مقرران محتسبان', arFew: '{n} مقررات محتسبة', arMany: '{n} مقرراً محتسباً', en1: '1 course credited', en: '{n} courses credited'),
      t('${creditHoursText(d.creditedHours)} ساعة معتمدة', '${creditHoursText(d.creditedHours)} credit hours'),
      if (d.pending > 0)
        countText(d.pending, ar1: 'مقرر قيد الدراسة', ar2: 'مقرران قيد الدراسة', arFew: '{n} مقررات قيد الدراسة', arMany: '{n} مقرراً قيد الدراسة', en1: '1 pending', en: '{n} pending'),
    ].join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(t('المقررات التي درسها الطالب في جهته السابقة، وما يقابلها لدينا.', 'The courses the student took at the previous place, and what they match here.'),
          style: AppType.meta(context)),
      AppSpace.gapSm,
      AppCard(
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(summary, style: AppType.bodyStrong(context)),
          AppSpace.gapXs,
          Text(
            d.settings.countsInGpa
                ? t('المقررات المحتسبة تدخل المعدل افتراضياً (${creditHoursText(d.gpaHours)} ساعة الآن).', 'Credited courses enter the GPA by default (${creditHoursText(d.gpaHours)} hours now).')
                : t('المقررات المحتسبة تُحسب ساعاتها فقط ولا تدخل المعدل افتراضياً.', 'Credited courses count for their hours only and stay out of the GPA by default.'),
            style: AppType.meta(context),
          ),
          if (d.settings.minLetter != null)
            Text(t('الحد الأدنى للتقدير: ${d.settings.minLetter}', 'Minimum grade: ${d.settings.minLetter}'), style: AppType.meta(context)),
        ]),
      ),
      AppSpace.gapMd,
      if (d.items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
          child: Text(t('لم يُضف أي مقرر بعد.', 'No course was added yet.'), textAlign: TextAlign.center, style: AppType.meta(context).copyWith(color: c.textMedium)),
        ),
      for (final x in d.items)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: TransferCreditCard(
            credit: x,
            busy: busy.contains(x.id),
            onEdit: onEdit == null || (!x.pending && onDecide == null) ? null : () => onEdit!(x),
            onDecide: onDecide == null ? null : (v) => onDecide!(x, v),
            onDelete: onDelete == null || (!x.pending && onDecide == null) ? null : () => onDelete!(x),
          ),
        ),
      if (onAdd != null)
        AppButton.primary(
          key: const ValueKey('students.credits.add'),
          label: t('أضف مقرراً', 'Add a course'),
          icon: Icons.add_rounded,
          expand: true,
          onPressed: onAdd,
        ),
      if (onSettings != null) ...[
        AppSpace.gapXs,
        AppButton.ghost(
          key: const ValueKey('students.credits.settings'),
          label: t('قواعد المقاصة', 'Transfer credit rules'),
          icon: Icons.tune_rounded,
          expand: true,
          onPressed: onSettings,
        ),
      ],
    ]);
  }
}

class TransferCreditCard extends StatelessWidget {
  const TransferCreditCard({super.key, required this.credit, this.busy = false, this.onEdit, this.onDecide, this.onDelete});
  final TransferCredit credit;
  final bool busy;
  final VoidCallback? onEdit, onDelete;
  final ValueChanged<String>? onDecide;

  @override
  Widget build(BuildContext context) {
    final x = credit;
    final c = context.colors;
    final source = [
      if (x.sourceCode != null) x.sourceCode!,
      if (x.sourceGrade != null) t('التقدير ${x.sourceGrade}', 'Grade ${x.sourceGrade}'),
      if (x.sourceCredits != null) t('${creditHoursText(x.sourceCredits)} ساعة', '${creditHoursText(x.sourceCredits)} h'),
    ].join(' · ');
    final here = x.course == null
        ? t('لم يُحدَّد المقرر المعادل بعد', 'No equivalent course chosen yet')
        : '${x.course!.label} · ${t('${creditHoursText(x.hoursHere)} ساعة', '${creditHoursText(x.hoursHere)} h')}';
    final decide = onDecide;
    return AppCard(
      key: ValueKey('students.credits.row.${x.id}'),
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x.sourceCourse, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              if (x.sourceInstitution != null)
                Text(x.sourceInstitution!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              if (source.isNotEmpty) Text(source, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ]),
          ),
          AppSpace.gapXs,
          AppStatusBadge(label: creditDecisionLabel(x.decision), tone: creditDecisionTone(x.decision), dot: true, dense: true),
        ]),
        AppSpace.gapXs,
        Row(children: [
          Icon(Icons.arrow_forward_rounded, size: AppIconSize.sm, color: c.textMedium),
          AppSpace.gapXs,
          Expanded(
            child: Text(here, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: AppType.body(context).copyWith(color: x.course == null ? c.textMedium : null)),
          ),
        ]),
        if (x.decision == 'credited')
          Text(x.countsInGpa ? t('يدخل المعدل', 'Enters the GPA') : t('لا يدخل المعدل', 'Stays out of the GPA'), style: AppType.meta(context)),
        if (x.belowMin) ...[
          AppSpace.gapXs,
          AppBanner(
            icon: Icons.warning_amber_rounded,
            color: appToneColor(context, AppTone.warning),
            text: t('التقدير أقل من الحد الأدنى للمقاصة', 'The grade is below the minimum for transfer credit'),
          ),
        ],
        if ((x.note ?? '').isNotEmpty) ...[
          AppSpace.gapXs,
          Text(x.note!, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
        ],
        if (decide != null || onEdit != null || onDelete != null) ...[
          AppSpace.gapSm,
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            if (decide != null && x.pending) ...[
              AppButton.tonal(
                key: ValueKey('students.credits.credit.${x.id}'),
                label: t('احتسب', 'Credit'),
                icon: Icons.check_rounded,
                size: AppButtonSize.sm,
                busy: busy,
                onPressed: busy ? null : () => decide('credited'),
              ),
              AppButton.secondary(
                key: ValueKey('students.credits.no.${x.id}'),
                label: t('لا يُحتسب', 'Not credited'),
                size: AppButtonSize.sm,
                onPressed: busy ? null : () => decide('not_credited'),
              ),
            ],
            if (decide != null && !x.pending)
              AppButton.ghost(
                key: ValueKey('students.credits.reopen.${x.id}'),
                label: t('أعِد للدراسة', 'Back to pending'),
                icon: Icons.undo_rounded,
                size: AppButtonSize.sm,
                busy: busy,
                onPressed: busy ? null : () => decide('pending'),
              ),
            if (onEdit != null)
              AppButton.ghost(
                key: ValueKey('students.credits.edit.${x.id}'),
                label: t('تعديل', 'Edit'),
                icon: Icons.edit_outlined,
                size: AppButtonSize.sm,
                onPressed: busy ? null : onEdit,
              ),
            if (onDelete != null)
              AppButton.ghost(
                key: ValueKey('students.credits.delete.${x.id}'),
                label: t('حذف', 'Delete'),
                icon: Icons.delete_outline_rounded,
                size: AppButtonSize.sm,
                onPressed: busy ? null : onDelete,
              ),
          ]),
        ],
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Forms
// ═════════════════════════════════════════════════════════════════════════════

class TransferCreditForm extends StatefulWidget {
  const TransferCreditForm({super.key, this.initial, this.onPickCourse, this.onSave});
  final CreditDraft? initial;
  final Future<CourseChoice?> Function()? onPickCourse;

  /// Resolves to null on success, else the error text.
  final Future<String?> Function(CreditDraft draft)? onSave;

  @override
  State<TransferCreditForm> createState() => _TransferCreditFormState();
}

class _TransferCreditFormState extends State<TransferCreditForm> {
  late final CreditDraft _d = widget.initial ?? CreditDraft();
  late final _inst = TextEditingController(text: _d.sourceInstitution);
  late final _course = TextEditingController(text: _d.sourceCourse);
  late final _code = TextEditingController(text: _d.sourceCode);
  late final _grade = TextEditingController(text: _d.sourceGrade);
  late final _credits = TextEditingController(text: _d.sourceCredits);
  late final _hours = TextEditingController(text: _d.creditedHours);
  late final _note = TextEditingController(text: _d.note);
  bool _busy = false;
  String? _error;
  String? _bad;

  @override
  void dispose() {
    for (final c in [_inst, _course, _code, _grade, _credits, _hours, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    final p = widget.onPickCourse;
    if (p == null) return;
    final c = await p();
    if (c == null || !mounted) return;
    setState(() => _d.course = c);
  }

  Future<void> _save() async {
    if (_busy) return;
    _d
      ..sourceInstitution = _inst.text
      ..sourceCourse = _course.text
      ..sourceCode = _code.text
      ..sourceGrade = _grade.text
      ..sourceCredits = _credits.text
      ..creditedHours = _hours.text
      ..note = _note.text;
    final bad = _d.check();
    if (bad != null) {
      setState(() => _bad = bad);
      return;
    }
    final save = widget.onSave;
    if (save == null) return;
    setState(() {
      _busy = true;
      _bad = null;
      _error = null;
    });
    final err = await save(_d);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hoursErr = t('اكتب رقماً من 0 إلى 60', 'Write a number from 0 to 60');
    final course = _d.course;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppSectionTitle(t('في الجهة السابقة', 'At the previous place')),
      AppField(key: const ValueKey('students.credits.f.institution'), controller: _inst, label: t('الجامعة أو الكلية', 'University or faculty'), enabled: !_busy, maxLength: 200),
      AppSpace.gapSm,
      AppField(
        key: const ValueKey('students.credits.f.course'),
        controller: _course,
        label: t('اسم المقرر', 'Course name'),
        required: true,
        enabled: !_busy,
        maxLength: 200,
        errorText: _bad == 'source_course' ? t('اكتب اسم المقرر', 'Write the course name') : null,
      ),
      AppSpace.gapSm,
      AppField(key: const ValueKey('students.credits.f.code'), controller: _code, label: t('الكود', 'Code'), ltr: true, enabled: !_busy, maxLength: 40),
      AppSpace.gapSm,
      AppField(key: const ValueKey('students.credits.f.grade'), controller: _grade, label: t('التقدير', 'Grade'), hint: t('مثل B+ أو جيد جداً', 'e.g. B+ or Very good'), enabled: !_busy, maxLength: 20),
      AppSpace.gapSm,
      AppField(
        key: const ValueKey('students.credits.f.credits'),
        controller: _credits,
        label: t('الساعات هناك', 'Hours there'),
        keyboard: const TextInputType.numberWithOptions(decimal: true),
        ltr: true,
        enabled: !_busy,
        errorText: _bad == 'source_credits' ? hoursErr : null,
      ),
      AppSectionTitle(t('لدينا', 'Here')),
      AppFieldLabel(t('المقرر المعادل', 'The equivalent course')),
      AppCard(
        key: const ValueKey('students.credits.f.pick'),
        padding: const EdgeInsets.all(AppSpace.sm),
        onTap: _busy || widget.onPickCourse == null ? null : _pick,
        child: Row(children: [
          Icon(Icons.menu_book_outlined, size: AppIconSize.md, color: c.textMedium),
          AppSpace.gapSm,
          Expanded(
            child: Text(course?.label ?? t('اختر المقرر (يلزم قبل الاحتساب)', 'Choose the course (needed before crediting)'),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: course == null ? c.textMedium : null)),
          ),
          if (course != null && !_busy)
            IconButton(
              tooltip: t('مسح', 'Clear'),
              icon: Icon(Icons.close_rounded, size: AppIconSize.md, color: c.textLight),
              onPressed: () => setState(() => _d.course = null),
            )
          else
            Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
        ]),
      ),
      AppSpace.gapSm,
      AppField(
        key: const ValueKey('students.credits.f.hours'),
        controller: _hours,
        label: t('الساعات المحتسبة هنا', 'Hours counted here'),
        hint: course?.creditHours == null ? null : t('فارغ = ${creditHoursText(course!.creditHours)} ساعات المقرر', 'Empty = the course\'s ${creditHoursText(course.creditHours)} hours'),
        keyboard: const TextInputType.numberWithOptions(decimal: true),
        ltr: true,
        enabled: !_busy,
        errorText: _bad == 'credited_hours' ? hoursErr : null,
      ),
      AppSpace.gapSm,
      AppSwitchTile(
        key: const ValueKey('students.credits.f.gpa'),
        title: t('يدخل المعدل', 'Enters the GPA'),
        subtitle: _d.countsInGpa == null ? t('حسب قواعد المقاصة', 'As the transfer credit rules say') : null,
        value: _d.countsInGpa ?? false,
        onChanged: _busy ? null : (v) => setState(() => _d.countsInGpa = v),
      ),
      AppSpace.gapSm,
      AppField(key: const ValueKey('students.credits.f.note'), controller: _note, label: t('ملاحظة (اختياري)', 'Note (optional)'), maxLines: 2, maxLength: 4000, enabled: !_busy),
      if (_error != null) ...[
        AppSpace.gapSm,
        AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: c.danger),
      ],
      AppSpace.gapMd,
      AppButton.primary(
        key: const ValueKey('students.credits.f.save'),
        label: t('احفظ', 'Save'),
        expand: true,
        busy: _busy,
        onPressed: _busy || widget.onSave == null ? null : _save,
      ),
    ]);
  }
}

class TransferCreditSettingsForm extends StatefulWidget {
  const TransferCreditSettingsForm({super.key, required this.initial, this.onSave});
  final TransferCreditSettings initial;
  final Future<String?> Function(TransferCreditSettings settings)? onSave;

  @override
  State<TransferCreditSettingsForm> createState() => _TransferCreditSettingsFormState();
}

class _TransferCreditSettingsFormState extends State<TransferCreditSettingsForm> {
  late bool _gpa = widget.initial.countsInGpa;
  late final _letter = TextEditingController(text: widget.initial.minLetter ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _letter.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final save = widget.onSave;
    if (save == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final l = _letter.text.trim();
    final err = await save(TransferCreditSettings(countsInGpa: _gpa, minLetter: l.isEmpty ? null : l));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppSwitchTile(
          key: const ValueKey('students.credits.s.gpa'),
          title: t('المقررات المحتسبة تدخل المعدل', 'Credited courses enter the GPA'),
          subtitle: t('في أغلب اللوائح تُحسب الساعات فقط. يمكن تغييره لكل مقرر.', 'Most bylaws count the hours only. It can be changed per course.'),
          value: _gpa,
          onChanged: _busy ? null : (v) => setState(() => _gpa = v),
        ),
        AppSpace.gapSm,
        AppField(
          key: const ValueKey('students.credits.s.letter'),
          controller: _letter,
          label: t('أقل تقدير يُحتسب (اختياري)', 'The lowest grade that counts (optional)'),
          hint: t('حرف من سلّم التقديرات، مثل C', 'A letter of the grade scale, e.g. C'),
          helper: t('تنبيه فقط: القرار للجهة المختصة.', 'A warning only: the deciding body still decides.'),
          ltr: true,
          enabled: !_busy,
          maxLength: 4,
        ),
        if (_error != null) ...[
          AppSpace.gapSm,
          AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: context.colors.danger),
        ],
        AppSpace.gapMd,
        AppButton.primary(
          key: const ValueKey('students.credits.s.save'),
          label: t('احفظ', 'Save'),
          expand: true,
          busy: _busy,
          onPressed: _busy || widget.onSave == null ? null : _save,
        ),
      ]);
}

/// Search the organization's courses and pick one.
class _CoursePickSheet extends StatefulWidget {
  const _CoursePickSheet({required this.api});
  final StudentRequestsApi api;

  @override
  State<_CoursePickSheet> createState() => _CoursePickSheetState();
}

class _CoursePickSheetState extends State<_CoursePickSheet> {
  final _q = TextEditingController();
  List<CourseChoice>? _items;
  String? _error;
  Timer? _debounce;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final seq = ++_seq;
    final r = await widget.api.courses(search: _q.text);
    if (!mounted || seq != _seq) return;
    setState(() {
      if (r.ok) {
        _items = courseChoicesOf(r.map);
        _error = null;
      } else {
        _error = requestsErrorText(r.error!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return AppSheetContent(
      title: t('اختر المقرر المعادل', 'Choose the equivalent course'),
      icon: Icons.menu_book_outlined,
      children: [
        AppField(
          key: const ValueKey('students.credits.course_search'),
          controller: _q,
          label: t('ابحث بالاسم', 'Search by name'),
          icon: Icons.search_rounded,
          autofocus: true,
          onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 350), _search);
          },
        ),
        AppSpace.gapSm,
        if (_error != null)
          AppErrorState(message: _error, onRetry: _search, compact: true)
        else if (items == null)
          const AppListSkeleton(items: 3)
        else if (items.isEmpty)
          Text(t('لا توجد مقررات بهذا الاسم.', 'No course has this name.'), style: AppType.meta(context))
        else
          for (final c in items)
            ListTile(
              key: ValueKey('students.credits.course.${c.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(c.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.body(context)),
              onTap: () => Navigator.of(context).pop(c),
            ),
      ],
    );
  }
}
