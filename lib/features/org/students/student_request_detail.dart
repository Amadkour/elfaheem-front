// lib/features/org/students/student_request_detail.dart — one student lifecycle request for the reviewer (student
// lifecycle phase 6, contract §9, PLAN §3.6): what the student asks and why, where it is, and the three verbs the
// server allows (`can`): Accept (the decision number and date when the matrix asks for them), Reject with a reason the
// student reads, Send to the council (a Governance vote; the council's close applies the change).
//
//   openStudentRequest(context, orgId, id)   the sheet; resolves true when the request changed (reload the inbox)
//   StudentRequestDetailView                 plain values + callbacks (the layout harness pumps it)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../../help/help_info_button.dart';
import '../org_v3.dart' show OrgCall;
import 'my_requests.dart' show requestDatesLine;
import 'student_asks_models.dart' show kStudentRequestsHelpId;
import 'student_requests_api.dart';
import 'student_status_models.dart' show bodyLabel, reasonLabel, statusCodeTexts;
import 'student_status_sheet.dart' show StatusDateField;

/// Opens request [id] of organization [orgId]; true when it was accepted, rejected or sent to a council.
Future<bool?> openStudentRequest(BuildContext context, int orgId, int id, {StudentRequestsApi? api}) =>
    showAppSheet<bool>(context, (ctx) => _RequestSheet(api: api ?? StudentRequestsApi(orgId), id: id));

class _RequestSheet extends StatefulWidget {
  const _RequestSheet({required this.api, required this.id});
  final StudentRequestsApi api;
  final int id;

  @override
  State<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends State<_RequestSheet> {
  LifecycleRequest? _r;
  String? _loadError;
  String? _error;
  String? _busy;
  bool _canOverride = false;
  List<RequestCouncil>? _councils;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.api.detail(widget.id);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _r = LifecycleRequest.fromJson(r.map);
        _loadError = null;
      } else {
        _loadError = requestsErrorText(r.error!);
      }
    });
  }

  Future<bool> _done(Future<OrgCall> call, String action, String ok) async {
    setState(() {
      _busy = action;
      _error = null;
    });
    final r = await call;
    if (!mounted) return false;
    if (!r.ok) {
      setState(() {
        _busy = null;
        _error = requestsErrorText(r.error!);
        if (r.code == 'rule_blocks') _canOverride = r.detail['override_allowed'] != false;
        if (r.code == 'no_council') _councils = councilsOfError(r);
      });
      return false;
    }
    showAppNotice(ok);
    Navigator.of(context).pop(true);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return AppSheetContent(
      title: r?.label ?? t('طلب طالب', 'A student request'),
      subtitle: r == null ? null : [if (r.studentName.isNotEmpty) r.studentName, if (r.ref.isNotEmpty) r.ref].join(' · '),
      icon: r == null ? Icons.description_outlined : requestKindIcon(r.request),
      headerTrailing: const HelpInfoButton(pageId: kStudentRequestsHelpId, autoTour: false),
      children: [
        if (r == null)
          _loadError != null ? AppErrorState(message: _loadError, onRetry: _load, compact: true) : const AppListSkeleton(items: 2)
        else
          StudentRequestDetailView(
            request: r,
            busy: _busy,
            error: _error,
            canOverride: _canOverride,
            councils: _councils,
            onAccept: (d) => _done(widget.api.accept(r.id, d.toJson()), 'accept',
                r.isDataUpdate ? t('حُدّثت بيانات الطالب وأُبلغ', 'The details were updated; the student is told') : t('قُبل الطلب ونُفّذ، وأُبلغ الطالب', 'Accepted and applied; the student is told')),
            onReject: (note) => _done(widget.api.reject(r.id, note), 'reject', t('رُفض الطلب وأُبلغ الطالب بالسبب', 'Rejected; the student reads the reason')),
            onCouncil: (dept, note) => _done(widget.api.toCouncil(r.id, councilDeptId: dept, note: note), 'council',
                t('أُرسل الطلب إلى المجلس للتصويت', 'Sent to the council for its vote')),
          ),
      ],
    );
  }
}

/// One request and its verbs. The mode (view · accept · reject · council) is kept inside.
class StudentRequestDetailView extends StatefulWidget {
  const StudentRequestDetailView({
    super.key,
    required this.request,
    this.busy,
    this.error,
    this.canOverride = false,
    this.councils,
    this.initialMode = 'view',
    this.onAccept,
    this.onReject,
    this.onCouncil,
  });

  final LifecycleRequest request;

  /// The action running now (accept · reject · council), null = idle.
  final String? busy;
  final String? error;

  /// A rule stopped the change and an approver may apply it anyway.
  final bool canOverride;

  /// The councils a `no_council` answer listed (else the request's own).
  final List<RequestCouncil>? councils;
  final String initialMode;
  final Future<bool> Function(AcceptDraft draft)? onAccept;
  final Future<bool> Function(String note)? onReject;
  final Future<bool> Function(int? councilDeptId, String note)? onCouncil;

  @override
  State<StudentRequestDetailView> createState() => _StudentRequestDetailViewState();
}

class _StudentRequestDetailViewState extends State<StudentRequestDetailView> {
  late String _mode = widget.initialMode;
  final _decisionNo = TextEditingController();
  final _note = TextEditingController();
  final AcceptDraft _accept = AcceptDraft();
  int? _council;
  String? _local;

  @override
  void dispose() {
    _decisionNo.dispose();
    _note.dispose();
    super.dispose();
  }

  LifecycleRequest get _r => widget.request;
  bool get _busy => widget.busy != null;

  void _go(String mode) => setState(() {
        _mode = mode;
        _local = null;
        _note.clear();
      });

  Future<void> _pickDecisionDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _accept.decisionDate ?? DateTime(now.year, now.month, now.day),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() => _accept.decisionDate = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _confirm() async {
    switch (_mode) {
      case 'accept':
        _accept
          ..decisionNo = _decisionNo.text
          ..note = _note.text;
        final bad = _accept.check(_r);
        if (bad != null) {
          setState(() => _local = statusCodeTexts()[bad] ?? bad);
          return;
        }
        setState(() => _local = null);
        await widget.onAccept?.call(_accept);
      case 'reject':
        final note = _note.text.trim();
        if (note.length < 3) {
          setState(() => _local = t('اكتب سبب الرفض؛ يصل إلى الطالب', 'Write the reason; the student will read it'));
          return;
        }
        setState(() => _local = null);
        await widget.onReject?.call(note);
      case 'council':
        setState(() => _local = null);
        await widget.onCouncil?.call(_council, _note.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final c = context.colors;
    final dates = requestDatesLine(r);
    final created = r.createdAt, decided = r.decidedAt;
    final err = _local ?? widget.error;
    final councils = widget.councils ?? r.councils;

    final facts = <(String, String)>[
      if (r.origin != null) (t('قدّمه', 'Started by'), r.origin == 'student' ? t('الطالب', 'The student') : t('الموظفون', 'Staff')),
      if (r.reasonCode != null) (t('السبب الرئيسي', 'Main reason'), reasonLabel(r.reasonCode!)),
      if (dates.isNotEmpty) (t('المدة', 'Dates'), dates),
      if (r.bodyKey != null) (t('جهة القرار', 'Decided by'), bodyLabel(r.bodyKey!)),
      if (r.decisionNo != null) (t('رقم القرار', 'Decision number'), r.decisionNo!),
      for (final e in r.changes.entries) (r.changeLabel(e.key), e.value),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        AppStatusBadge(label: requestStageLabel(r.stage), tone: requestStageTone(r.stage), dot: true, dense: true),
        if (r.applied) AppStatusBadge(label: t('نُفّذ التغيير', 'Change applied'), tone: AppTone.success, dense: true),
      ]),
      if (r.stage != 'withdrawn') ...[
        AppSpace.gapSm,
        AppStatusPath.request(
          reached: requestPathReached(r.stage),
          times: [created == null ? null : AppTime.date(created), null, decided == null ? null : AppTime.date(decided)],
        ),
      ],
      if ((r.reason ?? '').isNotEmpty) ...[
        AppSpace.gapMd,
        AppFieldLabel(r.isDataUpdate ? t('ملاحظة الطالب', 'The student\'s note') : t('السبب كما كتبه', 'The reason, as written')),
        Text(r.reason!, style: AppType.body(context)),
      ],
      if (facts.isNotEmpty) ...[
        AppSpace.gapMd,
        for (final f in facts)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xxs),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${f.$1}: ', style: AppType.meta(context)),
                TextSpan(text: f.$2, style: AppType.body(context)),
              ]),
            ),
          ),
      ],
      if (r.stage == 'rejected' && (r.note ?? '').isNotEmpty) ...[
        AppSpace.gapSm,
        AppBanner(icon: Icons.info_outline_rounded, text: t('سبب الرفض: ${r.note}', 'Reason given: ${r.note}'), color: c.danger),
      ],
      AppSpace.gapMd,
      ..._actions(context, councils),
      if (err != null) ...[
        AppSpace.gapSm,
        AppBanner(icon: Icons.error_outline_rounded, text: err, color: c.danger),
      ],
    ]);
  }

  List<Widget> _actions(BuildContext context, List<RequestCouncil> councils) {
    final r = _r;
    final can = r.can;
    if (!r.isOpen) {
      return [Text(t('لا يحتاج هذا الطلب إجراءً الآن.', 'This request needs nothing now.'), style: AppType.meta(context))];
    }
    if (!can.any) {
      return [
        AppBanner(
          icon: Icons.lock_outline_rounded,
          text: r.stage == 'council'
              ? t('الطلب معروض على المجلس؛ يُنفَّذ القرار عند إغلاق الجلسة.', 'The request is before the council; the decision applies when the session closes.')
              : t('القرار في هذا الطلب لجهة أخرى حسب مصفوفة القرارات.', 'The decision matrix gives this request to another body.'),
        ),
      ];
    }
    final busy = _busy;
    switch (_mode) {
      case 'accept':
        return [
          if (!r.isDataUpdate)
            AppBanner(icon: Icons.verified_outlined, text: t('يُنفَّذ التغيير على حالة الطالب فور القبول.', 'The change applies to the student\'s status as soon as you accept.')),
          AppSpace.gapSm,
          if (r.needsDecisionNo || !r.isDataUpdate) ...[
            AppField(
              key: const ValueKey('students.request.decision_no'),
              controller: _decisionNo,
              label: t('رقم القرار', 'Decision number'),
              required: r.needsDecisionNo,
              enabled: !busy,
              maxLength: 60,
            ),
            AppSpace.gapSm,
            StatusDateField(
              key: const ValueKey('students.request.decision_date'),
              label: t('تاريخ القرار', 'Decision date'),
              value: _accept.decisionDate,
              required: r.needsDecisionNo,
              onPick: busy ? null : _pickDecisionDate,
              onClear: busy || r.needsDecisionNo ? null : () => setState(() => _accept.decisionDate = null),
            ),
          ],
          AppField(
            key: const ValueKey('students.request.note'),
            controller: _note,
            label: t('ملاحظة (اختياري)', 'Note (optional)'),
            enabled: !busy,
            maxLines: 2,
            maxLength: 4000,
          ),
          if (widget.canOverride) ...[
            AppSpace.gapSm,
            AppSwitchTile(
              key: const ValueKey('students.request.override'),
              title: t('نفّذ رغم القاعدة', 'Apply despite the rule'),
              subtitle: t('يُسجَّل الاستثناء باسمك في السجل.', 'The exception is recorded under your name.'),
              value: _accept.override,
              onChanged: busy ? null : (v) => setState(() => _accept.override = v),
            ),
          ],
          AppSpace.gapMd,
          ..._confirmRow(AppButton.primary(
            key: const ValueKey('students.request.confirm'),
            label: r.isDataUpdate ? t('اقبل وحدّث البيانات', 'Accept and update') : t('اقبل ونفّذ', 'Accept and apply'),
            icon: Icons.check_rounded,
            expand: true,
            busy: widget.busy == 'accept',
            onPressed: busy ? null : _confirm,
          )),
        ];
      case 'reject':
        return [
          AppField(
            key: const ValueKey('students.request.note'),
            controller: _note,
            label: t('سبب الرفض (يقرؤه الطالب)', 'The reason (the student reads it)'),
            required: true,
            enabled: !busy,
            maxLines: 3,
            maxLength: 4000,
            autofocus: true,
          ),
          AppSpace.gapMd,
          ..._confirmRow(AppButton.danger(
            key: const ValueKey('students.request.confirm'),
            label: t('ارفض الطلب', 'Reject the request'),
            expand: true,
            busy: widget.busy == 'reject',
            onPressed: busy ? null : _confirm,
          )),
        ];
      case 'council':
        return [
          Text(t('يُعرض الطلب على المجلس للتصويت، ويُنفَّذ القرار عند إغلاق الجلسة برقم قرارها.',
                  'The request goes to the council for a vote; the decision applies with the session\'s decision number when it closes.'),
              style: AppType.meta(context)),
          AppSpace.gapSm,
          if (councils.isNotEmpty) ...[
            AppPicker<int>(
              key: const ValueKey('students.request.council'),
              label: t('المجلس', 'The council'),
              value: _council,
              allowNone: true,
              noneLabel: t('المجلس المختص تلقائياً', 'The competent council (automatic)'),
              enabled: !busy,
              options: {for (final x in councils) x.deptId: x.name},
              onChanged: (v) => setState(() => _council = v),
            ),
            AppSpace.gapSm,
          ],
          AppField(
            key: const ValueKey('students.request.note'),
            controller: _note,
            label: t('ملاحظة للمجلس (اختياري)', 'A note for the council (optional)'),
            enabled: !busy,
            maxLines: 2,
            maxLength: 2000,
          ),
          AppSpace.gapMd,
          ..._confirmRow(AppButton.primary(
            key: const ValueKey('students.request.confirm'),
            label: t('أرسل إلى المجلس', 'Send to the council'),
            icon: Icons.how_to_vote_outlined,
            expand: true,
            busy: widget.busy == 'council',
            onPressed: busy ? null : _confirm,
          )),
        ];
      default:
        return [
          if (can.accept)
            AppButton.primary(
              key: const ValueKey('students.request.accept'),
              label: t('اقبل', 'Accept'),
              icon: Icons.check_rounded,
              expand: true,
              onPressed: busy ? null : () => _go('accept'),
            ),
          if (can.council) ...[
            AppSpace.gapSm,
            AppButton.tonal(
              key: const ValueKey('students.request.to_council'),
              label: t('اعرضه على المجلس', 'Send to the council'),
              icon: Icons.how_to_vote_outlined,
              expand: true,
              onPressed: busy ? null : () => _go('council'),
            ),
          ],
          if (can.reject) ...[
            AppSpace.gapSm,
            AppButton.ghost(
              key: const ValueKey('students.request.reject'),
              label: t('ارفض مع ذكر السبب', 'Reject with a reason'),
              icon: Icons.block_rounded,
              expand: true,
              onPressed: busy ? null : () => _go('reject'),
            ),
          ],
        ];
    }
  }

  List<Widget> _confirmRow(Widget primary) => [
        primary,
        AppSpace.gapXs,
        AppButton.ghost(
          key: const ValueKey('students.request.back'),
          label: t('رجوع', 'Back'),
          expand: true,
          onPressed: _busy ? null : () => _go('view'),
        ),
      ];
}
