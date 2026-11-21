// lib/features/org/students/student_status_sheet.dart — "Change status" and "Undo this change" (student lifecycle
// contract §6, PLAN §2.3, §3.9).
//
//   showStudentStatusSheet(context, orgId, uid, {current, name, decision, reason, source, api})
//       loads GET …/status (unless [current] carries its options), lets the caller pick ONE change from what the
//       server says they may do, asks only what that change needs (reason, decision number and date, dates, the
//       side-effect questions), previews it in one plain sentence, and saves it (POST …/status) or sends it for
//       approval (POST …/status/propose). A blocking rule shows its text; an approver may go ahead with a reason.
//       Resolves to the StatusResult, or null when closed.
//   showStatusChangeSheet(…)                   the contract's name for the same opener
//   confirmUndoStatus(context, orgId, eventId, {title, api})
//       "Undo this change?" with the reason it asks for → POST …/status-events/{eid}/undo; StatusResult or null
//   statusErrorText(e)                         a §6.3 code → its text (the rule's own text for `rule_blocks`)
//   StatusChangeView / UndoStatusView          the bodies over plain values (the layout harness pumps them)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../../help/help_info_button.dart';
import '../org_v3.dart' show orgErrorText;
import 'student_status_models.dart';
import 'students_api.dart';
import 'students_models.dart';

/// The help page of the sheet (§12).
const kStudentStatusHelpId = 'org.students.status';

/// A §6.3 code → its text; `rule_blocks` keeps the rule's own words from the server.
String statusErrorText(ApiException e) {
  final c = e.code;
  if (c == 'rule_blocks' && e.message.trim().isNotEmpty) return e.message;
  return (c == null ? null : statusCodeTexts()[c]) ?? orgErrorText(e);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Openers
// ═════════════════════════════════════════════════════════════════════════════

/// Opens "Change status" for student [uid]. [current] skips the first load when it carries `options`; [decision]
/// preselects a change (the complaint flow preselects a flag), [reason] prefills the note, [source] is recorded on
/// the event (`{type: complaint, id}`), [name] is the subtitle. [api] is for tests.
Future<StatusResult?> showStudentStatusSheet(BuildContext context, int orgId, int uid,
    {StudentStatus? current, String? name, String? decision, String? reason, StatusSource? source, StudentsApi? api}) {
  return showAppSheet<StatusResult>(
    context,
    (ctx) => _StatusSheet(
      uid: uid,
      api: api ?? StudentsApi(orgId),
      current: current,
      name: name,
      decision: decision,
      reason: reason,
      source: source,
    ),
  );
}

/// The contract's name (§6.5) for [showStudentStatusSheet].
Future<StatusResult?> showStatusChangeSheet(BuildContext context, int orgId, int uid,
        {StudentStatus? current, String? name, String? decision, String? reason, StatusSource? source, StudentsApi? api}) =>
    showStudentStatusSheet(context, orgId, uid, current: current, name: name, decision: decision, reason: reason, source: source, api: api);

/// "Undo this change?" for status event [eventId] (a timeline row's `source.id`); [title] is the change's sentence.
Future<StatusResult?> confirmUndoStatus(BuildContext context, int orgId, int eventId, {String? title, StudentsApi? api}) {
  return showAppSheet<StatusResult>(context, (ctx) => _UndoSheet(eventId: eventId, title: title, api: api ?? StudentsApi(orgId)));
}

// ═════════════════════════════════════════════════════════════════════════════
//  The change sheet
// ═════════════════════════════════════════════════════════════════════════════

class _StatusSheet extends StatefulWidget {
  const _StatusSheet({required this.uid, required this.api, this.current, this.name, this.decision, this.reason, this.source});
  final int uid;
  final StudentsApi api;
  final StudentStatus? current;
  final String? name, decision, reason;
  final StatusSource? source;

  @override
  State<_StatusSheet> createState() => _StatusSheetState();
}

class _StatusSheetState extends State<_StatusSheet> {
  StudentStatus? _status;
  bool _loading = false;
  String? _loadError;
  String? _picked;
  StatusDraft? _draft;
  late final TextEditingController _note = TextEditingController(text: widget.reason ?? '');
  final TextEditingController _no = TextEditingController();
  bool _busy = false;
  String? _error, _errorCode;
  RuleBlock? _serverBlock;
  bool _forcePropose = false;

  @override
  void initState() {
    super.initState();
    final cur = widget.current;
    if (cur != null && cur.options.isNotEmpty) {
      _status = cur;
      _preselect();
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _note.dispose();
    _no.dispose();
    super.dispose();
  }

  void _preselect() {
    final d = widget.decision;
    if (d != null && _status?.option(d) != null) _pick(d, rebuild: false);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final r = await widget.api.status(widget.uid);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _status = StudentStatus.fromJson(r.map);
        _preselect();
      } else {
        _loadError = statusErrorText(r.error!);
      }
    });
  }

  void _pick(String decision, {bool rebuild = true}) {
    final o = _status?.option(decision);
    if (o == null) return;
    void apply() {
      _picked = decision;
      _draft = StatusDraft.forOption(o, current: _status, reason: _note.text, source: widget.source);
      _no.clear();
      _error = null;
      _errorCode = null;
      _serverBlock = null;
      _forcePropose = false;
    }

    rebuild ? setState(apply) : apply();
  }

  StatusOption? get _option => _picked == null ? null : _status?.option(_picked!);

  Future<void> _pickDate(String which) async {
    final d = _draft;
    if (d == null) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = switch (which) {
      'decision_date' => d.decisionDate,
      'effective_to' => d.effectiveTo,
      'access_until' => d.accessUntil,
      _ => d.effectiveFrom,
    };
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? (which == 'decision_date' || which == 'effective_from' ? today : today.add(const Duration(days: 30))),
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (picked == null || !mounted) return;
    final day = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      switch (which) {
        case 'decision_date':
          d.decisionDate = day;
        case 'effective_to':
          d.effectiveTo = day;
        case 'access_until':
          d.accessUntil = day;
        default:
          d.effectiveFrom = day;
      }
      _error = null;
    });
  }

  void _clearDate(String which) {
    final d = _draft;
    if (d == null) return;
    setState(() {
      switch (which) {
        case 'decision_date':
          d.decisionDate = null;
        case 'effective_to':
          d.effectiveTo = null;
        case 'access_until':
          d.accessUntil = null;
        default:
          d.effectiveFrom = null;
      }
    });
  }

  Future<void> _submit({bool propose = false}) async {
    final o = _option, d = _draft;
    if (o == null || d == null || _busy) return;
    d.reason = _note.text;
    d.decisionNo = _no.text;
    final why = d.problemText(o);
    if (why != null) {
      setState(() {
        _error = why;
        _errorCode = d.problem(o);
      });
      return;
    }
    final sendForApproval = propose || o.proposes || _forcePropose;
    if (o.danger && !sendForApproval) {
      final ok = await appConfirm(
        context,
        danger: true,
        confirmLabel: t('نعم، نفّذ', 'Yes, go ahead'),
        message: '${o.label}\n${statusPreview(d)}',
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _errorCode = null;
    });
    final body = d.toJson();
    final r = sendForApproval ? await widget.api.proposeStatus(widget.uid, body) : await widget.api.changeStatus(widget.uid, body);
    if (!mounted) return;
    if (!r.ok) {
      final code = r.code;
      setState(() {
        _busy = false;
        _errorCode = code;
        if (code == 'rule_blocks') {
          _serverBlock = RuleBlock.fromJson(r.detail) ?? const RuleBlock();
          _error = null;
        } else {
          if (code == 'needs_body') _forcePropose = true;
          _error = statusErrorText(r.error!);
        }
      });
      return;
    }
    final result = sendForApproval ? StatusResult.proposedFrom(r.map) : StatusResult.fromJson(r.map);
    showAppNotice(sendForApproval
        ? t('أُرسل التغيير للاعتماد', 'The change was sent for approval')
        : t('حُفظ التغيير: ${o.label}', 'Saved: ${o.label}'));
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final o = _option;
    return AppSheetContent(
      title: t('تغيير الحالة', 'Change status'),
      subtitle: widget.name,
      icon: Icons.published_with_changes_rounded,
      headerTrailing: const HelpInfoButton(pageId: kStudentStatusHelpId, autoTour: false),
      children: [
        StatusChangeView(
          status: _status,
          loading: _loading,
          loadError: _loadError,
          onRetry: _load,
          picked: _picked,
          draft: _draft,
          note: _note,
          decisionNo: _no,
          busy: _busy,
          error: _error,
          errorCode: _errorCode,
          block: _serverBlock ?? o?.blocked,
          proposes: (o?.proposes ?? false) || _forcePropose,
          onPick: _busy ? null : _pick,
          onEdit: (fn) => setState(() {
            final d = _draft;
            if (d != null) fn(d);
            _error = null;
          }),
          onPickDate: _busy ? null : _pickDate,
          onClearDate: _busy ? null : _clearDate,
          onSubmit: () => _submit(),
          onPropose: _errorCode == 'needs_body' ? () => _submit(propose: true) : null,
        ),
      ],
    );
  }
}

/// The change sheet's body over plain values.
class StatusChangeView extends StatelessWidget {
  const StatusChangeView({
    super.key,
    this.status,
    this.loading = false,
    this.loadError,
    this.onRetry,
    this.picked,
    this.draft,
    required this.note,
    required this.decisionNo,
    this.busy = false,
    this.error,
    this.errorCode,
    this.block,
    this.proposes = false,
    this.onPick,
    this.onEdit,
    this.onPickDate,
    this.onClearDate,
    this.onSubmit,
    this.onPropose,
  });

  final StudentStatus? status;
  final bool loading;

  /// The load failed (text already made); null = no error.
  final String? loadError;
  final VoidCallback? onRetry;

  /// The chosen decision key and its form.
  final String? picked;
  final StatusDraft? draft;
  final TextEditingController note, decisionNo;
  final bool busy;
  final String? error, errorCode;

  /// The rule that stops the chosen change (the option's or the server's answer).
  final RuleBlock? block;

  /// The chosen change goes for approval.
  final bool proposes;
  final ValueChanged<String>? onPick;
  final void Function(void Function(StatusDraft d) edit)? onEdit;

  /// `decision_date`, `effective_from`, `effective_to` or `access_until`.
  final ValueChanged<String>? onPickDate, onClearDate;
  final VoidCallback? onSubmit;

  /// Shown after 403 `needs_body`: send the same change for approval.
  final VoidCallback? onPropose;

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (loading && s == null) return const AppListSkeleton(items: 3, withAvatar: false, padding: EdgeInsets.zero);
    if (loadError != null && s == null) return AppErrorState(message: loadError, onRetry: onRetry, compact: true);
    if (s == null) return const SizedBox.shrink();
    final option = picked == null ? null : s.option(picked!);
    final d = draft;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      StatusNowStrip(status: s),
      AppSpace.gapMd,
      if (s.options.isEmpty)
        AppEmpty(
          icon: Icons.lock_outline_rounded,
          title: t('لا يوجد تغيير متاح لك', 'No change is open to you'),
          message: t('دورك يتيح رؤية حالة الطالب دون تغييرها.', 'Your role lets you see this student\'s status, not change it.'),
        )
      else ...[
        AppFieldLabel(t('ما الذي يتغير؟', 'What changes?')),
        for (final dim in const ['enrolment', 'standing', 'flag'])
          if (s.optionsOf(dim).isNotEmpty) _OptionGroup(dimension: dim, options: s.optionsOf(dim), picked: picked, onPick: onPick),
        if (option != null && d != null) ...[
          AppSpace.gapSm,
          _ChangeForm(
            option: option,
            draft: d,
            status: s,
            note: note,
            decisionNo: decisionNo,
            busy: busy,
            error: error,
            errorCode: errorCode,
            block: block,
            proposes: proposes,
            onEdit: onEdit,
            onPickDate: onPickDate,
            onClearDate: onClearDate,
            onSubmit: onSubmit,
            onPropose: onPropose,
          ),
        ],
      ],
    ]);
  }
}

/// "Now: Enrolled · Carrying courses · Transferred in" — where the student stands before the change.
class StatusNowStrip extends StatelessWidget {
  const StatusNowStrip({super.key, required this.status});
  final StudentStatus status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final enrol = StudentChip('enrolment', s.enrolStatus);
    final standing = s.acadStanding;
    final until = s.enrolUntil;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t('الحالة الآن', 'Now'), style: AppType.meta(context)),
        AppSpace.gapXs,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AppStatusBadge(label: enrol.label, tone: enrol.tone, dot: true, dense: true),
          if (standing != null) AppStatusBadge(label: standingLabel(standing), tone: chipTone(StudentChip('standing', standing)), dense: true),
          for (final f in s.flags) AppStatusBadge(label: flagLabel(f.key), tone: flagTone(f.key), dense: true),
        ]),
        if (until != null && enrolPaused.contains(s.enrolStatus)) ...[
          AppSpace.gapXs,
          Text(t('يعود القيد في ${AppTime.wall(until)}', 'Enrolment resumes on ${AppTime.wall(until)}'), style: AppType.meta(context)),
        ],
      ]),
    );
  }
}

class _OptionGroup extends StatelessWidget {
  const _OptionGroup({required this.dimension, required this.options, this.picked, this.onPick});
  final String dimension;
  final List<StatusOption> options;
  final String? picked;
  final ValueChanged<String>? onPick;

  @override
  Widget build(BuildContext context) {
    final title = switch (dimension) {
      'standing' => t('الوضع الأكاديمي', 'Academic standing'),
      'flag' => t('علامات للمتابعة', 'Marks to follow up'),
      _ => t('القيد', 'Enrolment'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(header: true, child: Text(title, style: AppType.meta(context))),
        const SizedBox(height: AppSpace.xxs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final o in options)
            AppChoiceChip(
              key: ValueKey('students.status.opt.${o.decision}'),
              label: o.label,
              icon: o.blocked != null ? Icons.lock_outline_rounded : (o.proposes ? Icons.outbox_outlined : null),
              selected: o.decision == picked,
              onTap: onPick == null ? () {} : () => onPick!(o.decision),
            ),
        ]),
      ]),
    );
  }
}

class _ChangeForm extends StatelessWidget {
  const _ChangeForm({
    required this.option,
    required this.draft,
    required this.status,
    required this.note,
    required this.decisionNo,
    this.busy = false,
    this.error,
    this.errorCode,
    this.block,
    this.proposes = false,
    this.onEdit,
    this.onPickDate,
    this.onClearDate,
    this.onSubmit,
    this.onPropose,
  });

  final StatusOption option;
  final StatusDraft draft;
  final StudentStatus status;
  final TextEditingController note, decisionNo;
  final bool busy;
  final String? error, errorCode;
  final RuleBlock? block;
  final bool proposes;
  final void Function(void Function(StatusDraft d) edit)? onEdit;
  final ValueChanged<String>? onPickDate, onClearDate;
  final VoidCallback? onSubmit, onPropose;

  void _edit(void Function(StatusDraft d) fn) => onEdit?.call(fn);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = draft;
    final tgt = d.target;
    final reasons = reasonChoices(option.decision);
    final body = option.body;
    final reasonRequired = option.needsReasonText || d.override;
    final paused = enrolPaused.contains(d.enrolTo);
    final askUntil = option.needsEffectiveTo || paused;
    final b = block;
    final mayGo = b == null || d.override;
    final err = error;

    Widget dateRow(String which, String label, DateTime? value, {bool required = false, String? placeholder}) => StatusDateField(
          key: ValueKey('students.status.date.$which'),
          label: label,
          value: value,
          required: required,
          placeholder: placeholder,
          onPick: onPickDate == null ? null : () => onPickDate!(which),
          onClear: onClearDate == null || required ? null : () => onClearDate!(which),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppBanner(
        icon: proposes ? Icons.how_to_vote_outlined : Icons.verified_outlined,
        text: proposes
            ? (body == null
                ? t('يُرسل هذا التغيير للاعتماد، ولا يتغير شيء قبل الموافقة.', 'This change is sent for approval; nothing changes before it is accepted.')
                : t('يُرسل هذا التغيير إلى ${bodyPhrase(body)} للاعتماد، ولا يتغير شيء قبل الموافقة.',
                    'This change goes to ${bodyPhrase(body)} for approval; nothing changes before it is accepted.'))
            : (body == null
                ? t('ينفَّذ هذا التغيير فور الحفظ.', 'This change takes effect when you save it.')
                : t('يُسجَّل كقرار صادر من ${bodyPhrase(body)} وينفَّذ فور الحفظ.',
                    'It is recorded as a decision of ${bodyPhrase(body)} and takes effect when you save it.')),
      ),
      AppSpace.gapMd,
      if (tgt.dimension == 'standing' && option.decision == 'standing_override')
        AppDropdown<String>(
          key: const ValueKey('students.status.to'),
          value: d.to,
          enabled: !busy,
          decoration: InputDecoration(labelText: t('الوضع الأكاديمي الجديد', 'The new standing')),
          items: [
            for (final s in standings)
              if (s != status.acadStanding) DropdownMenuItem(value: s, child: Text(standingLabel(s))),
          ],
          onChanged: (v) => _edit((x) => x.to = v),
        ),
      if (tgt.dimension == 'standing' && option.decision == 'standing_override') AppSpace.gapSm,
      if (tgt.dimension == 'flag') ...[
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppChoiceChip(
            key: const ValueKey('students.status.flag.on'),
            label: t('إضافة العلامة', 'Add the mark'),
            icon: Icons.add_rounded,
            selected: d.flagOn == true,
            onTap: busy ? () {} : () => _edit((x) => x.flagOn = true),
          ),
          AppChoiceChip(
            key: const ValueKey('students.status.flag.off'),
            label: t('إزالة العلامة', 'Remove the mark'),
            icon: Icons.remove_rounded,
            selected: d.flagOn == false,
            onTap: busy ? () {} : () => _edit((x) => x.flagOn = false),
          ),
        ]),
        if (staffOnlyFlags.contains(tgt.flag)) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(t('علامة داخلية: لا يراها الطالب.', 'An internal mark: the student does not see it.'), style: AppType.meta(context)),
        ],
        AppSpace.gapMd,
      ],
      if (reasons.length > 1)
        AppDropdown<String>(
          key: const ValueKey('students.status.reason_code'),
          value: d.reasonCode,
          enabled: !busy,
          decoration: InputDecoration(labelText: t('السبب', 'Reason')),
          hint: Text(t('اختر السبب', 'Pick the reason')),
          items: [for (final r in reasons) DropdownMenuItem(value: r, child: Text(anyReasonLabel(r)))],
          onChanged: (v) => _edit((x) => x.reasonCode = v),
        )
      else if (reasons.length == 1)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: Text('${t('السبب', 'Reason')}: ${anyReasonLabel(reasons.first)}', style: AppType.body(context)),
        ),
      if (reasons.length > 1) AppSpace.gapSm,
      AppField(
        key: const ValueKey('students.status.note'),
        controller: note,
        label: reasonRequired ? t('اكتب السبب', 'Explain the reason') : t('ملاحظة (اختياري)', 'Note (optional)'),
        hint: t('جملة قصيرة تُحفظ في ملف الطالب', 'A short sentence kept on the student\'s file'),
        maxLines: 3,
        maxLength: 2000,
        required: reasonRequired,
        enabled: !busy,
      ),
      if (option.needsDecisionNo || option.needsField('decision_date')) ...[
        if (option.needsDecisionNo)
          AppField(
            key: const ValueKey('students.status.decision_no'),
            controller: decisionNo,
            label: t('رقم القرار', 'Decision number'),
            hint: t('كما في محضر الجلسة', 'As written in the minutes'),
            required: true,
            maxLength: 60,
            enabled: !busy,
          ),
        dateRow('decision_date', t('تاريخ القرار', 'Decision date'), d.decisionDate, required: true),
      ],
      dateRow('effective_from', t('يبدأ من', 'Takes effect on'), d.effectiveFrom, required: option.needsField('effective_from')),
      if (askUntil)
        dateRow(
          'effective_to',
          paused ? t('يعود القيد في', 'Enrolment resumes on') : t('ينتهي في', 'Ends on'),
          d.effectiveTo,
          required: option.needsEffectiveTo,
          placeholder: paused ? t('بلا موعد: يُستأنف القيد يدوياً', 'No date: resume by hand') : null,
        ),
      if (d.leavesEnrolment) ...[
        AppSwitchTile(
          key: const ValueKey('students.status.drop'),
          title: t('سحبه من مقررات هذا الفصل أيضاً', 'Also withdraw them from this term\'s courses'),
          subtitle: t('إذا لم تختر ذلك تبقى مقرراته الحالية.', 'If you leave this off, their current courses stay.'),
          value: d.dropCurrent,
          onChanged: busy ? null : (v) => _edit((x) => x.dropCurrent = v),
        ),
      ],
      if (d.isFinal)
        dateRow('access_until', t('ينتهي دخوله إلى المؤسسة في', 'Their access ends on'), d.accessUntil,
            placeholder: t('بعد المدة المحددة في الإعدادات', 'After the period set in the settings')),
      if (b != null) ...[
        AppSpace.gapXs,
        AppBanner(key: const ValueKey('students.status.block'), icon: Icons.rule_rounded, color: c.warning, text: b.text),
        if (option.canOverride) ...[
          AppSpace.gapXs,
          AppSwitchTile(
            key: const ValueKey('students.status.override'),
            title: t('المتابعة استثناءً', 'Go ahead as an exception'),
            subtitle: t('اكتب السبب؛ يُحفظ مع القرار.', 'Give the reason; it is kept with the decision.'),
            value: d.override,
            onChanged: busy ? null : (v) => _edit((x) => x.override = v),
          ),
        ],
      ],
      AppSpace.gapSm,
      StatusPreviewCard(text: statusPreview(d, proposes: proposes, body: body)),
      if (err != null) ...[
        AppSpace.gapSm,
        AppBanner(
          key: const ValueKey('students.status.error'),
          icon: Icons.error_outline_rounded,
          color: c.danger,
          text: err,
        ),
        if (onPropose != null) ...[
          AppSpace.gapXs,
          AppButton.secondary(
            key: const ValueKey('students.status.propose'),
            label: t('أرسله للاعتماد بدلاً من ذلك', 'Send it for approval instead'),
            icon: Icons.outbox_outlined,
            expand: true,
            onPressed: busy ? null : onPropose,
          ),
        ],
      ],
      AppSpace.gapMd,
      if (option.danger && !proposes)
        AppButton.danger(
          key: const ValueKey('students.status.save'),
          label: option.label,
          icon: Icons.check_rounded,
          busy: busy,
          expand: true,
          onPressed: mayGo ? onSubmit : null,
        )
      else
        AppButton.primary(
          key: const ValueKey('students.status.save'),
          label: proposes ? t('إرسال للاعتماد', 'Send for approval') : t('حفظ التغيير', 'Save the change'),
          icon: proposes ? Icons.outbox_outlined : Icons.check_rounded,
          busy: busy,
          expand: true,
          onPressed: mayGo ? onSubmit : null,
        ),
    ]);
  }
}

/// "What will happen": the plain preview of a change.
class StatusPreviewCard extends StatelessWidget {
  const StatusPreviewCard({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Container(
      key: const ValueKey('students.status.preview'),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: appTintOn(context, c.primary),
        borderRadius: AppRadius.cardAll,
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.visibility_outlined, size: AppIconSize.md, color: appToneInk(context, AppTone.brand)),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('ما الذي سيحدث', 'What will happen'), style: AppType.label(context)),
            const SizedBox(height: AppSpace.xxs),
            Text(text, style: AppType.body(context)),
          ]),
        ),
      ]),
    );
  }
}

/// A tappable well showing a picked calendar date (or a placeholder), with a clear button when it may be emptied.
class StatusDateField extends StatelessWidget {
  const StatusDateField({super.key, required this.label, this.value, this.onPick, this.onClear, this.required = false, this.placeholder});
  final String label;
  final DateTime? value;
  final VoidCallback? onPick, onClear;
  final bool required;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = value;
    final text = v == null ? '' : AppTime.wall(v);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppFieldLabel(label, required: required),
        Semantics(
          button: true,
          label: '$label: ${text.isEmpty ? (placeholder ?? t('لم يُحدَّد', 'not set')) : text}',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: AppRadius.controlAll,
            onTap: onPick,
            child: InputDecorator(
              isEmpty: text.isEmpty,
              decoration: appFieldDecoration(
                context,
                hint: placeholder ?? t('اختر التاريخ', 'Pick a date'),
                icon: Icons.event_rounded,
                enabled: onPick != null,
                suffix: v == null || onClear == null
                    ? null
                    : IconButton(
                        tooltip: t('مسح', 'Clear'),
                        icon: Icon(Icons.close_rounded, size: AppIconSize.md, color: c.textLight),
                        onPressed: onClear,
                      ),
              ),
              child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: appFieldTextStyle(context)),
            ),
          ),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Undo
// ═════════════════════════════════════════════════════════════════════════════

class _UndoSheet extends StatefulWidget {
  const _UndoSheet({required this.eventId, required this.api, this.title});
  final int eventId;
  final StudentsApi api;
  final String? title;

  @override
  State<_UndoSheet> createState() => _UndoSheetState();
}

class _UndoSheetState extends State<_UndoSheet> {
  final TextEditingController _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final why = _reason.text.trim();
    if (why.isEmpty) {
      setState(() => _error = statusCodeTexts()['reason_required']);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await widget.api.undoStatus(widget.eventId, why);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = false;
        _error = statusErrorText(r.error!);
      });
      return;
    }
    showAppNotice(t('تم التراجع عن التغيير', 'The change was undone'));
    Navigator.of(context).pop(StatusResult.fromJson(r.map));
  }

  @override
  Widget build(BuildContext context) => AppSheetContent(
        title: t('التراجع عن هذا التغيير؟', 'Undo this change?'),
        icon: Icons.undo_rounded,
        tone: AppTone.warning,
        children: [
          UndoStatusView(title: widget.title, reason: _reason, busy: _busy, error: _error, onSubmit: _submit),
        ],
      );
}

/// The undo confirm's body over plain values.
class UndoStatusView extends StatelessWidget {
  const UndoStatusView({super.key, this.title, required this.reason, this.busy = false, this.error, this.onSubmit});
  final String? title;
  final TextEditingController reason;
  final bool busy;
  final String? error;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tt = title?.trim() ?? '';
    final err = error;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (tt.isNotEmpty) ...[
        AppCard(padding: const EdgeInsets.all(AppSpace.sm), child: Text(tt, style: AppType.bodyStrong(context))),
        AppSpace.gapSm,
      ],
      Text(
        t('تعود الحالة إلى ما كانت عليه قبل هذا التغيير، ويبقى السطران في السجل: التغيير ثم التراجع عنه.',
            'The status goes back to what it was before this change. Both lines stay on the record: the change, then the undo.'),
        style: AppType.body(context),
      ),
      AppSpace.gapMd,
      AppField(
        key: const ValueKey('students.undo.reason'),
        controller: reason,
        label: t('سبب التراجع', 'Why undo it?'),
        hint: t('مثال: صدر القرار بالخطأ', 'For example: the decision was entered by mistake'),
        maxLines: 3,
        maxLength: 2000,
        required: true,
        enabled: !busy,
      ),
      if (err != null) ...[
        AppBanner(key: const ValueKey('students.undo.error'), icon: Icons.error_outline_rounded, color: c.danger, text: err),
        AppSpace.gapSm,
      ],
      AppSpace.gapXs,
      AppButton.danger(
        key: const ValueKey('students.undo.save'),
        label: t('تراجع', 'Undo'),
        icon: Icons.undo_rounded,
        busy: busy,
        expand: true,
        onPressed: onSubmit,
      ),
    ]);
  }
}
