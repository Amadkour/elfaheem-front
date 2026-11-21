// lib/features/org/students/my_requests.dart — the student's lifecycle requests (student lifecycle phase 6, contract
// §9, PLAN §3.6): ask the organization to suspend or postpone the studies, withdraw, transfer out, re-enrol, accept
// an excuse or update a detail of the file; follow each request to its decision; withdraw one still in review.
//
//   MyRequestsPage(orgId:)         loads GET /public/{o}/my-requests, kept fresh on the live event `student_lifecycle`
//                                  through EventOrPoll (the timer is the slow fallback)
//   openMyRequests(context, orgId) pushes it
//   MyRequestsView                 plain values: my requests (open first), then "Ask for something"
//   MyRequestCard                  one request: what, where it is (submitted → in review → decided), the reason,
//                                  the dates, a rejection's reason, Withdraw
//   MyRequestForm                  the form of one request kind: reason, main reason, dates, details to change,
//                                  supporting documents (uploaded to Governance and posted on the request), and a
//                                  confirmation for withdrawal / transfer
// Every request is a Governance item (no new table): the chain, the council's vote and the notifications are its.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show t;
import '../governance/gov_models.dart' show GovAttachment;
import '../governance/gov_request_parts.dart' show uploadGovAttachment;
import 'student_requests_api.dart';
import 'student_status_models.dart' show reasonLabel, statusCodeTexts;
import 'student_status_sheet.dart' show StatusDateField;

/// Pushes the student's requests page of organization [orgId].
Future<void> openMyRequests(BuildContext context, int orgId) =>
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => MyRequestsPage(orgId: orgId)));

class MyRequestsPage extends StatefulWidget {
  const MyRequestsPage({super.key, required this.orgId, this.api});
  final int orgId;
  final StudentRequestsApi? api;

  @override
  State<MyRequestsPage> createState() => _MyRequestsPageState();
}

class _MyRequestsPageState extends State<MyRequestsPage> {
  late final StudentRequestsApi _api = widget.api ?? StudentRequestsApi(widget.orgId);
  MyRequests? _data;
  bool _loading = true;
  String? _error;
  final Set<int> _busy = {};
  EventOrPoll? _watch;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _watch = EventOrPoll(
      poll: () => _load(quiet: true),
      every: const Duration(seconds: 90),
      fallbackEvery: const Duration(minutes: 5),
      names: {LiveEvents.studentLifecycle, LiveEvents.complaints},
    )..start();
  }

  @override
  void dispose() {
    _watch?.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    final seq = ++_seq;
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final r = await _api.myRequests();
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _data = MyRequests.fromJson(r.map);
        _error = null;
      } else if (!quiet || _data == null) {
        _error = requestsErrorText(r.error!);
      }
    });
  }

  Future<void> _start(RequestOption o) async {
    final sent = await showAppSheet<bool>(
      context,
      (ctx) => AppSheetContent(
        title: o.label,
        subtitle: requestKindHint(o.request),
        icon: requestKindIcon(o.request),
        children: [
          MyRequestForm(
            option: o,
            onAddDocument: () => uploadGovAttachment(widget.orgId),
            onSubmit: (d) => _send(ctx, d),
          ),
        ],
      ),
    );
    if (sent == true && mounted) _load(quiet: true);
  }

  /// Sends [d]; null on success (the sheet closes), else the text to show in the form.
  Future<String?> _send(BuildContext sheet, RequestDraft d) async {
    final r = await _api.submit(d.toJson());
    if (!r.ok) return requestsErrorText(r.error!);
    final item = LifecycleRequest.fromJson(r.map);
    var docsOk = true;
    if (d.documents.isNotEmpty && item.id > 0) docsOk = (await _api.attach(item.id, d.documents)).ok;
    showAppNotice(docsOk
        ? t('أُرسل طلبك${item.ref.isEmpty ? '' : ' برقم ${item.ref}'}، وسنبلغك فور البت فيه', 'Your request${item.ref.isEmpty ? '' : ' ${item.ref}'} was sent; you will be told as soon as it is decided')
        : t('أُرسل طلبك، لكن تعذّر إرفاق المستندات؛ أرسلها من صفحة الطلب في الطلبات والشكاوى', 'Your request was sent, but the documents could not be attached; send them from the request in Requests & complaints'),
        error: !docsOk);
    if (sheet.mounted) Navigator.of(sheet).pop(true);
    return null;
  }

  Future<void> _withdraw(LifecycleRequest r) async {
    if (_busy.contains(r.id)) return;
    final ok = await appConfirm(context,
        danger: true,
        confirmLabel: t('اسحب الطلب', 'Withdraw the request'),
        message: t('سيتوقف النظر في «${r.label}». يمكنك تقديمه من جديد لاحقاً.', '"${r.label}" will no longer be reviewed. You can send it again later.'));
    if (!ok || !mounted) return;
    setState(() => _busy.add(r.id));
    final res = await _api.withdraw(r.id);
    if (!mounted) return;
    setState(() => _busy.remove(r.id));
    if (!res.ok) {
      showAppNotice(requestsErrorText(res.error!), error: true);
      return;
    }
    showAppNotice(t('سُحب الطلب', 'The request was withdrawn'));
    _load(quiet: true);
  }

  @override
  Widget build(BuildContext context) => BasePage(
        useWebCard: true,
        width: AppWidth.reading,
        appBar: ScreenAppBar(title: t('طلباتي', 'My requests')),
        child: MyRequestsView(
          data: _data,
          loading: _loading,
          error: _error,
          busy: _busy,
          onRetry: _load,
          onRefresh: () => _load(quiet: true),
          onStart: _start,
          onWithdraw: _withdraw,
        ),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  The page body (plain values)
// ═════════════════════════════════════════════════════════════════════════════

class MyRequestsView extends StatelessWidget {
  const MyRequestsView({
    super.key,
    this.data,
    this.loading = false,
    this.error,
    this.busy = const {},
    this.onRetry,
    this.onRefresh,
    this.onStart,
    this.onWithdraw,
  });

  final MyRequests? data;
  final bool loading;
  final String? error;
  final Set<int> busy;
  final VoidCallback? onRetry;
  final Future<void> Function()? onRefresh;
  final ValueChanged<RequestOption>? onStart;
  final ValueChanged<LifecycleRequest>? onWithdraw;

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d == null) {
      if (error != null) return AppErrorState(message: error, onRetry: onRetry);
      return const Padding(padding: EdgeInsets.all(AppSpace.md), child: AppListSkeleton(items: 4));
    }
    final open = d.open, closed = d.closed;
    final labels = {for (final f in d.option('data_update')?.fields ?? const <RequestField>[]) f.key: f.label};
    final list = ListView(
      key: const ValueKey('my_requests.list'),
      padding: const EdgeInsets.all(AppSpace.md),
      children: [
        Text(t('اطلب من مؤسستك تغييراً في دراستك أو بياناتك، وتابع الرد هنا.', 'Ask your organization for a change in your studies or your details, and follow the answer here.'),
            style: AppType.body(context).copyWith(color: context.colors.textMedium)),
        if (error != null) ...[
          AppSpace.gapSm,
          AppBanner(icon: Icons.error_outline_rounded, text: error!, color: context.colors.danger),
        ],
        if (open.isNotEmpty) ...[
          AppSectionTitle(t('قيد النظر', 'In review')),
          for (final r in open) _gap(MyRequestCard(request: r, labels: labels, busy: busy.contains(r.id), onWithdraw: onWithdraw == null ? null : () => onWithdraw!(r))),
        ],
        AppSectionTitle(t('اطلب شيئاً', 'Ask for something')),
        if (d.options.isEmpty)
          Text(t('لا توجد طلبات متاحة لك الآن.', 'No requests are open to you right now.'), style: AppType.meta(context))
        else
          for (final o in d.options) _gap(_OptionCard(option: o, onTap: o.canStart && onStart != null ? () => onStart!(o) : null)),
        if (closed.isNotEmpty) ...[
          AppSectionTitle(t('طلبات سابقة', 'Earlier requests')),
          for (final r in closed) _gap(MyRequestCard(request: r, labels: labels)),
        ],
        if (open.isEmpty && closed.isEmpty) ...[
          AppSpace.gapMd,
          Text(t('لم تقدّم أي طلب بعد.', 'You have not sent any request yet.'), style: AppType.meta(context), textAlign: TextAlign.center),
        ],
      ],
    );
    final refresh = onRefresh;
    return refresh == null ? list : AppRefresh(onRefresh: refresh, child: list);
  }

  static Widget _gap(Widget w) => Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: w);
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.option, this.onTap});
  final RequestOption option;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final o = option;
    final why = o.openItemId != null
        ? t('لديك طلب مماثل قيد النظر', 'You already have this request in review')
        : !o.allowed
            ? t('غير متاح لحالتك الآن', 'Not open to you in your current status')
            : requestKindHint(o.request);
    return Opacity(
      opacity: o.canStart ? 1 : 0.6,
      child: AppActionCard(
        key: ValueKey('my_requests.option.${o.request}'),
        icon: requestKindIcon(o.request),
        title: o.label,
        subtitle: why,
        onTap: onTap,
      ),
    );
  }
}

/// One of my requests.
class MyRequestCard extends StatelessWidget {
  const MyRequestCard({super.key, required this.request, this.labels = const {}, this.busy = false, this.onWithdraw});
  final LifecycleRequest request;

  /// The names of a data update's details (key → label).
  final Map<String, String> labels;
  final bool busy;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final c = context.colors;
    final dates = requestDatesLine(r);
    final created = r.createdAt, decided = r.decidedAt;
    return AppCard(
      key: ValueKey('my_requests.item.${r.id}'),
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(requestKindIcon(r.request), size: AppIconSize.md, color: appToneInk(context, AppTone.brand)),
          AppSpace.gapSm,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              if (r.ref.isNotEmpty || created != null)
                Text([if (r.ref.isNotEmpty) r.ref, if (created != null) AppTime.date(created)].join(' · '),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              const SizedBox(height: AppSpace.xxs),
              AppStatusBadge(label: requestStageLabel(r.stage), tone: requestStageTone(r.stage), dense: true, dot: true),
            ]),
          ),
        ]),
        if (r.stage != 'withdrawn') ...[
          AppSpace.gapSm,
          AppStatusPath.request(
            reached: requestPathReached(r.stage),
            times: [created == null ? null : AppTime.date(created), null, decided == null ? null : AppTime.date(decided)],
          ),
        ],
        if (r.stage == 'council') ...[
          AppSpace.gapXs,
          Text(t('يُعرض طلبك على المجلس في جلسته القادمة.', 'Your request goes before the council at its next meeting.'), style: AppType.meta(context)),
        ],
        if (r.reasonCode != null || (r.reason ?? '').isNotEmpty) ...[
          AppSpace.gapSm,
          Text(
            [if (r.reasonCode != null) reasonLabel(r.reasonCode!), if ((r.reason ?? '').isNotEmpty) r.reason!].join(' — '),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: AppType.body(context),
          ),
        ],
        if (dates.isNotEmpty) ...[
          AppSpace.gapXs,
          Text(dates, style: AppType.meta(context)),
        ],
        for (final e in r.changes.entries)
          Text('${labels[e.key] ?? e.key}: ${e.value}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
        if (r.stage == 'rejected' && (r.note ?? '').isNotEmpty) ...[
          AppSpace.gapSm,
          AppBanner(icon: Icons.info_outline_rounded, text: t('السبب: ${r.note}', 'The reason: ${r.note}'), color: c.danger),
        ],
        if (r.stage == 'approved' && r.decisionNo != null) ...[
          AppSpace.gapXs,
          Text(t('رقم القرار: ${r.decisionNo}', 'Decision number: ${r.decisionNo}'), style: AppType.meta(context)),
        ],
        if (r.canWithdraw && onWithdraw != null) ...[
          AppSpace.gapSm,
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppButton.ghost(
              key: ValueKey('my_requests.withdraw.${r.id}'),
              label: t('اسحب الطلب', 'Withdraw'),
              icon: Icons.undo_rounded,
              busy: busy,
              onPressed: busy ? null : onWithdraw,
            ),
          ),
        ],
      ]),
    );
  }
}

/// "From 1 Dec 2026 until 30 Jan 2027" (plain calendar dates, never shifted by a zone).
String requestDatesLine(LifecycleRequest r) {
  final f = r.effectiveFrom, to = r.effectiveTo;
  if (f == null && to == null) return '';
  if (f != null && to != null) return t('من ${AppTime.wall(f)} حتى ${AppTime.wall(to)}', 'From ${AppTime.wall(f)} until ${AppTime.wall(to)}');
  if (to != null) return t('حتى ${AppTime.wall(to)}', 'Until ${AppTime.wall(to)}');
  return t('ابتداءً من ${AppTime.wall(f!)}', 'Starting ${AppTime.wall(f)}');
}

// ═════════════════════════════════════════════════════════════════════════════
//  The form of one request
// ═════════════════════════════════════════════════════════════════════════════

class MyRequestForm extends StatefulWidget {
  const MyRequestForm({super.key, required this.option, this.onSubmit, this.onAddDocument});
  final RequestOption option;

  /// Sends the draft; resolves to null on success, else the error text to show.
  final Future<String?> Function(RequestDraft draft)? onSubmit;

  /// Picks and uploads one file; null when cancelled or refused.
  final Future<GovAttachment?> Function()? onAddDocument;

  @override
  State<MyRequestForm> createState() => _MyRequestFormState();
}

class _MyRequestFormState extends State<MyRequestForm> {
  late final RequestDraft _d = RequestDraft(widget.option.request);
  final _reason = TextEditingController();
  late final Map<String, TextEditingController> _fields = {for (final f in widget.option.fields) f.key: TextEditingController()};
  bool _confirmed = false;
  bool _busy = false;
  bool _uploading = false;
  String? _error;

  RequestOption get _o => widget.option;
  bool get _serious => lifecycleRequestsSerious.contains(_o.request);

  @override
  void dispose() {
    _reason.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(String which) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = which == 'to' ? _d.effectiveTo : _d.effectiveFrom;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? (which == 'to' ? today.add(const Duration(days: 120)) : today),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 6, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final day = DateTime(picked.year, picked.month, picked.day);
      which == 'to' ? _d.effectiveTo = day : _d.effectiveFrom = day;
      _error = null;
    });
  }

  Future<void> _addDocument() async {
    final add = widget.onAddDocument;
    if (add == null || _uploading) return;
    setState(() => _uploading = true);
    final f = await add();
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (f != null) _d.documents.add(f);
    });
  }

  String _codeText(String code) => requestsCodeTexts()[code] ?? statusCodeTexts()[code] ?? code;

  Future<void> _submit() async {
    if (_busy) return;
    _d.reason = _reason.text;
    _d.changes
      ..clear()
      ..addAll({for (final e in _fields.entries) e.key: e.value.text});
    final bad = _d.check(_o);
    if (bad != null) {
      setState(() => _error = bad == 'reason_required'
          ? t('اكتب السبب في سطر أو أكثر', 'Write the reason in a line or more')
          : bad == 'dates_required'
              ? t('حدّد حتى متى', 'Pick until when')
              : _codeText(bad));
      return;
    }
    if (_serious && !_confirmed) {
      setState(() => _error = t('أكّد أنك فهمت ما يترتب على الطلب', 'Confirm that you understand what the request means'));
      return;
    }
    final send = widget.onSubmit;
    if (send == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await send(_d);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    final c = context.colors;
    final codes = o.reasonCodes;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (o.isDataUpdate) ...[
        Text(t('اكتب القيمة الجديدة لما تريد تصحيحه فقط، واترك الباقي فارغاً.', 'Write the new value only for what you want corrected; leave the rest empty.'),
            style: AppType.meta(context)),
        AppSpace.gapSm,
        if (o.fields.isEmpty)
          Text(t('لا توجد بيانات يمكن طلب تعديلها.', 'There are no details you can ask to change.'), style: AppType.meta(context)),
        for (final f in o.fields)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AppField(
              key: ValueKey('my_requests.field.${f.key}'),
              controller: _fields[f.key]!,
              label: f.label,
              enabled: !_busy,
              maxLength: 500,
              keyboard: f.kind == 'number' ? TextInputType.number : null,
            ),
          ),
        AppField(
          key: const ValueKey('my_requests.reason'),
          controller: _reason,
          label: t('ملاحظة (اختياري)', 'A note (optional)'),
          enabled: !_busy,
          maxLines: 3,
          maxLength: 4000,
        ),
      ] else ...[
        if (_serious) ...[
          AppBanner(
            icon: Icons.warning_amber_rounded,
            color: appToneColor(context, AppTone.warning),
            text: o.request == 'withdraw'
                ? t('بعد الموافقة تنتهي دراستك في هذه المؤسسة ويُسلَّم لك ملفك.', 'Once approved, your studies here end and your file is handed to you.')
                : t('بعد الموافقة ينتقل ملفك إلى الجهة الجديدة وتنتهي دراستك هنا.', 'Once approved, your file moves to the new place and your studies here end.'),
          ),
          AppSpace.gapMd,
        ],
        if (codes.isNotEmpty) ...[
          AppPicker<String>(
            key: const ValueKey('my_requests.reason_code'),
            label: t('السبب الرئيسي', 'The main reason'),
            value: _d.reasonCode,
            allowNone: true,
            noneLabel: t('بدون تحديد', 'Not chosen'),
            enabled: !_busy,
            options: {for (final r in codes) r: reasonLabel(r)},
            onChanged: (v) => setState(() => _d.reasonCode = v),
          ),
          AppSpace.gapSm,
        ],
        AppField(
          key: const ValueKey('my_requests.reason'),
          controller: _reason,
          label: t('اشرح سبب الطلب', 'Explain why you are asking'),
          hint: t('بضع كلمات تكفي', 'A few words are enough'),
          required: true,
          enabled: !_busy,
          maxLines: 4,
          maxLength: 4000,
        ),
        AppSpace.gapSm,
        if (o.needsUntil) ...[
          StatusDateField(
            key: const ValueKey('my_requests.from'),
            label: t('من تاريخ', 'From'),
            value: _d.effectiveFrom,
            placeholder: t('من اليوم', 'From today'),
            onPick: _busy ? null : () => _pickDate('from'),
            onClear: _busy ? null : () => setState(() => _d.effectiveFrom = null),
          ),
          StatusDateField(
            key: const ValueKey('my_requests.to'),
            label: t('حتى تاريخ', 'Until'),
            value: _d.effectiveTo,
            required: true,
            onPick: _busy ? null : () => _pickDate('to'),
          ),
        ],
      ],
      AppFieldLabel(t('مستندات مؤيدة (اختياري)', 'Supporting documents (optional)')),
      for (var i = 0; i < _d.documents.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xxs),
          child: Row(children: [
            Icon(Icons.attach_file_rounded, size: AppIconSize.sm, color: c.textMedium),
            AppSpace.gapXs,
            Expanded(child: Text(_d.documents[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body(context))),
            IconButton(
              tooltip: t('إزالة', 'Remove'),
              icon: Icon(Icons.close_rounded, size: AppIconSize.md, color: c.textLight),
              onPressed: _busy ? null : () => setState(() => _d.documents.removeAt(i)),
            ),
          ]),
        ),
      if (widget.onAddDocument != null && _d.documents.length < 10)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton.tonal(
            key: const ValueKey('my_requests.add_document'),
            label: t('أرفق ملفاً', 'Attach a file'),
            icon: Icons.upload_file_rounded,
            busy: _uploading,
            onPressed: _busy || _uploading ? null : _addDocument,
          ),
        ),
      if (_serious) ...[
        AppSpace.gapSm,
        AppSwitchTile(
          key: const ValueKey('my_requests.confirm'),
          title: t('فهمت ما يترتب على هذا الطلب', 'I understand what this request means'),
          value: _confirmed,
          onChanged: _busy ? null : (v) => setState(() => _confirmed = v),
        ),
      ],
      if (_error != null) ...[
        AppSpace.gapSm,
        AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: c.danger),
      ],
      AppSpace.gapMd,
      Text(t('يصل طلبك إلى شؤون الطلاب، ولا يتغير شيء قبل الموافقة.', 'Your request goes to Student Affairs; nothing changes before it is approved.'),
          style: AppType.meta(context)),
      AppSpace.gapSm,
      AppButton.primary(
        key: const ValueKey('my_requests.send'),
        label: t('أرسل الطلب', 'Send the request'),
        icon: Icons.send_rounded,
        expand: true,
        busy: _busy,
        onPressed: _busy || widget.onSubmit == null ? null : _submit,
      ),
    ]);
  }
}
