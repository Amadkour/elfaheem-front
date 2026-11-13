// lib/features/org/advising/adv_requests.dart — support requests and referrals, staff side (docs/advising/PHASE7.md
// "Requests and referrals"):
//   • the list: queues All · To review (directors) · Needs information · Overdue · Filed by me with their counts, ONE
//     filter (kind / stage), a search, paging; New request picks a student and opens the composer
//     (adv_request_composer.dart);
//   • the request page: header (title, type, stage, priority, the student), THE stage tracker (AdvStageTrack), the
//     current step's due date, the information loop, the decision, the details and files, the council agenda with
//     its tallies, the chain step by step (with earlier rounds) and the stage history; the actions the server allows
//     (`can`): Edit · Submit · Delete (a draft) · Review (approve / reject / needs information) · Answer · Resubmit ·
//     Cancel · Close;
//   • every action's sheet, with its Arabic + English success and failure message. A decision someone else made first
//     (`already_decided`, `stale_version`, …) closes the sheet, says so and reloads.
//
//   AdvRequestsView · AdvRequestView · AdvReviewForm · AdvInfoAnswerForm · AdvResubmitForm · AdvNoteSheetForm
//   (plain values) · AdvRequestsPage · AdvRequestPage (load through AdvSupportApi)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../governance/gov_models.dart' show GovAttachment;
import '../governance/gov_request_parts.dart' show GovAttachmentChips, openGovAttachment, uploadGovAttachment;
import '../org_page_header.dart' show OrgPageRefresh, OrgPushedPage;
import '../org_page_kit.dart';
import '../org_v3.dart' show OrgCall, orgCall;
import 'adv_api.dart';
import 'adv_case_parts.dart' show AdvPriorityPill, AdvRailRow, AdvTypedField, AdvTypedText;
import 'adv_models.dart' show AdvPage;
import 'adv_parts.dart';
import 'adv_request_composer.dart';
import 'adv_student_page.dart' show AdvStudentPage;
import 'adv_support_api.dart';
import 'adv_support_models.dart';
import 'adv_support_parts.dart';
import 'adv_support_texts.dart';

/// The list's queue chips: '' (all) · `review` (directors) · `needs_info` · `overdue` · `mine`.
List<String> advRequestQueueChips({required bool manage}) => [
      '',
      if (manage) 'review',
      'needs_info',
      'overdue',
      'mine',
    ];

IconData _queueIcon(String q) => switch (q) {
      'review' => Icons.fact_check_outlined,
      'needs_info' => Icons.help_outline_rounded,
      'overdue' => Icons.alarm_rounded,
      'mine' => Icons.person_outline_rounded,
      _ => Icons.inbox_outlined,
    };

// ═════════════════════════════════════════════════════════════════════════════
//  The list
// ═════════════════════════════════════════════════════════════════════════════

class AdvRequestsView extends StatelessWidget {
  const AdvRequestsView({
    super.key,
    required this.load,
    required this.query,
    required this.manage,
    this.page,
    this.errorText,
    this.showStudent = true,
    this.onRetry,
    this.onQueue,
    this.onFilter,
    this.onSearch,
    this.onPage,
    this.onOpen,
    this.onNew,
  });

  final AdvLoad load;
  final AdvRequestQuery query;
  final bool manage;
  final AdvPage<AdvRequest>? page;
  final String? errorText;

  /// false on one student's list (the student is the page's title).
  final bool showStudent;
  final VoidCallback? onRetry, onNew;
  final ValueChanged<String>? onQueue, onFilter, onSearch;
  final ValueChanged<int>? onPage;
  final ValueChanged<AdvRequest>? onOpen;

  String get _queue => query.mine ? 'mine' : query.queue;

  @override
  Widget build(BuildContext context) {
    final p = page;
    final chips = advRequestQueueChips(manage: manage);
    String chipLabel(String q) {
      final n = q.isEmpty || q == 'mine' ? 0 : (p?.facet(q) ?? 0);
      return n > 0 ? '${advRequestQueueLabel(q)} · $n' : advRequestQueueLabel(q);
    }

    Widget body;
    if (load != AdvLoad.ready || p == null) {
      body = AdvPageFrame(children: [AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry, items: 4)]);
    } else if (p.items.isEmpty) {
      final filtered = query.filter.isNotEmpty || query.q.trim().isNotEmpty;
      // in a scrolling frame: under the queue chips and the toolbar, a phone at a large text size has no room left
      body = AdvPageFrame(children: [
        AppEmpty(
        icon: switch (_queue) {
          'review' || 'needs_info' || 'overdue' => Icons.task_alt_rounded,
          _ => Icons.support_outlined,
        },
        title: filtered
            ? t('لا نتائج', 'No results')
            : switch (_queue) {
                'review' => t('لا طلبات تنتظر مراجعتك', 'Nothing waits for your review'),
                'needs_info' => t('لا طلبات تنتظر معلومات', 'Nothing waits for information'),
                'overdue' => t('لا طلبات متأخرة', 'Nothing is overdue'),
                'mine' => t('لم تكتب طلبات بعد', 'You have not filed any requests yet'),
                _ => t('لا طلبات ولا إحالات بعد', 'No requests or referrals yet'),
              },
        message: filtered
            ? t('جرّب بحثاً آخر أو امسح التصفية.', 'Try another search or clear the filter.')
            : t('يكتب المرشد طلب الدعم أو الإحالة نيابة عن الطالب، ويتابع الطالب مراحله.', 'The advisor files a support request or a referral for the student, and the student follows its stages.'),
          actionLabel: onNew == null || filtered ? null : t('طلب جديد', 'New request'),
          onAction: filtered ? null : onNew,
        ),
      ]);
    } else {
      body = AdvPageFrame(fab: onNew != null, children: [
        for (final r in p.items) AdvRequestCard.staff(r, showStudent: showStudent, onTap: onOpen == null ? null : () => onOpen!(r)),
        if (p.restricted > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            child: Row(children: [
              ExcludeSemantics(child: Icon(Icons.lock_outline_rounded, size: AppIconSize.sm, color: context.colors.textMedium)),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Text(
                  countText(p.restricted,
                      ar1: 'طلب حساس واحد لا يظهر لك', ar2: 'طلبان حساسان لا يظهران لك', arFew: '${p.restricted} طلبات حساسة لا تظهر لك', arMany: '${p.restricted} طلباً حساساً لا يظهر لك',
                      en1: '1 sensitive request is hidden from you', en: '${p.restricted} sensitive requests are hidden from you'),
                  style: AppType.meta(context),
                ),
              ),
            ]),
          ),
        if (p.pages > 1 && onPage != null) ...[
          const SizedBox(height: AppSpace.sm),
          AppPagination(page: p.page, pageCount: p.pages, total: p.total, pageSize: p.size, onPage: onPage!),
        ],
      ]);
    }
    return OrgPageBody(
      primary: onNew == null ? null : OrgPrimaryAction(icon: Icons.add_rounded, label: t('طلب جديد', 'New request'), onTap: onNew!),
      search: onSearch == null ? null : OrgSearchField(hint: t('ابحث بالعنوان أو اسم الطالب', 'Search by title or student'), onChanged: onSearch!),
      filter: onFilter == null
          ? null
          : OrgFilterButton<String>(
              value: query.filter,
              defaultValue: '',
              label: t('النوع والمرحلة', 'Kind and stage'),
              options: {for (final f in advRequestFilters) f: advRequestFilterLabel(f)},
              onChanged: onFilter!,
            ),
      top: onQueue == null
          ? null
          : OrgSectionChips(
              items: [for (final q in chips) (chipLabel(q), _queueIcon(q))],
              index: chips.indexOf(_queue).clamp(0, chips.length - 1),
              onChanged: (i) => onQueue!(chips[i]),
            ),
      child: body,
    );
  }
}

class AdvRequestsPage extends StatelessWidget {
  const AdvRequestsPage({super.key, required this.orgId, required this.manage, this.memberId, this.studentName, this.queue = ''});
  final int orgId;
  final bool manage;

  /// One student's requests (the 360's "See all").
  final int? memberId;
  final String? studentName;

  /// The queue it opens on (`review` from the setup page's badge, `needs_info` for an advisor).
  final String queue;

  @override
  Widget build(BuildContext context) => OrgPushedPage(
        title: t('الطلبات والإحالات', 'Requests and referrals'),
        subtitle: studentName,
        helpPageId: 'org.advising',
        maxWidth: AppWidth.wide.max,
        child: _AdvRequestsBody(orgId: orgId, manage: manage, memberId: memberId, studentName: studentName, queue: queue),
      );
}

class _AdvRequestsBody extends StatefulWidget {
  const _AdvRequestsBody({required this.orgId, required this.manage, this.memberId, this.studentName, this.queue = ''});
  final int orgId;
  final bool manage;
  final int? memberId;
  final String? studentName;
  final String queue;

  @override
  State<_AdvRequestsBody> createState() => _AdvRequestsBodyState();
}

class _AdvRequestsBodyState extends State<_AdvRequestsBody> {
  late final AdvSupportApi _api = AdvSupportApi(widget.orgId);
  late AdvRequestQuery _query = AdvRequestQuery(memberId: widget.memberId, queue: widget.queue == 'mine' ? '' : widget.queue, mine: widget.queue == 'mine');
  OrgPageRefresh? _refresh;
  AdvPage<AdvRequest>? _page;
  AdvLoad _load = AdvLoad.loading;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _reload);
    _reload();
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final seq = ++_seq;
    final q = _query;
    final r = await orgCall(() => _api.requests(q), quiet: true);
    if (!mounted || seq != _seq) return;
    setState(() {
      if (r.ok) {
        _page = r.data as AdvPage<AdvRequest>;
        _load = AdvLoad.ready;
      } else {
        _load = advFailLoad(r);
        _error = advSupportErrorText(r.error!);
      }
    });
    if (r.ok && mounted) OrgPageRefresh.reportUpdated(context);
  }

  void _set(AdvRequestQuery q) {
    setState(() {
      _query = q;
      _load = AdvLoad.loading;
    });
    _reload();
  }

  Future<void> _open(AdvRequest r) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvRequestPage(orgId: widget.orgId, requestId: r.id, initial: r)));
    if (mounted) _reload();
  }

  Future<void> _new() async {
    var member = widget.memberId;
    var name = widget.studentName;
    if (member == null) {
      final s = await pickAdvStudent(context, AdvApi(widget.orgId), title: t('لمن الطلب؟', 'Who is the request for?'));
      if (s == null || !mounted) return;
      member = s.memberId;
      name = s.shown;
    }
    final made = await showAdvRequestComposer(context, orgId: widget.orgId, memberId: member, studentName: name);
    if (made == null || !mounted) return;
    _reload();
    await _open(made);
  }

  @override
  Widget build(BuildContext context) => AdvRequestsView(
        load: _load,
        query: _query,
        manage: widget.manage,
        page: _page,
        errorText: _error,
        showStudent: widget.memberId == null,
        onRetry: () => _set(_query),
        onQueue: (q) => _set(_query.copyWith(queue: q == 'mine' ? '' : q, mine: q == 'mine', page: 1)),
        onFilter: (f) => _set(_query.copyWith(filter: f, page: 1)),
        onSearch: (q) => _set(_query.copyWith(q: q, page: 1)),
        onPage: (p) => _set(_query.copyWith(page: p)),
        onOpen: _open,
        onNew: _new,
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  One request
// ═════════════════════════════════════════════════════════════════════════════

/// The actions of a request, the primary one first: (key, label, icon, danger).
List<(String, String, IconData, bool)> advRequestActions(AdvRequest r) {
  final c = r.can;
  return [
    if (c.review) ('review', t('مراجعة واتخاذ قرار', 'Review and decide'), Icons.fact_check_rounded, false),
    if (c.answerInfo && r.infoPending) ('answer', t('إرسال المعلومات المطلوبة', 'Send the information asked for'), Icons.reply_rounded, false),
    if (c.submit && r.draft) ('submit', r.referral ? t('إرسال الإحالة', 'Send the referral') : t('إرسال الطلب', 'Submit the request'), Icons.send_rounded, false),
    if (c.resubmit) ('resubmit', t('تعديل وإعادة الإرسال', 'Edit and resubmit'), Icons.replay_rounded, false),
    if (c.close) ('close', t('إغلاق الحالة بمتابعة', 'Close the case with a follow-up'), Icons.task_alt_rounded, false),
    if (c.edit && r.draft) ('edit', t('تعديل المسودة', 'Edit the draft'), Icons.edit_outlined, false),
    if (c.cancel) ('cancel', r.referral ? t('سحب الإحالة', 'Withdraw the referral') : t('سحب الطلب', 'Withdraw the request'), Icons.undo_rounded, true),
    if (c.delete && r.draft) ('delete', t('حذف المسودة', 'Delete the draft'), Icons.delete_outline_rounded, true),
  ];
}

class AdvRequestView extends StatelessWidget {
  const AdvRequestView({
    super.key,
    required this.load,
    this.request,
    this.errorText,
    this.busy = false,
    this.onRetry,
    this.onAction,
    this.onOpenStudent,
    this.onOpenAttachment,
  });

  final AdvLoad load;
  final AdvRequest? request;
  final String? errorText;
  final bool busy;
  final VoidCallback? onRetry, onOpenStudent;

  /// One of [advRequestActions]' keys.
  final ValueChanged<String>? onAction;
  final ValueChanged<GovAttachment>? onOpenAttachment;

  static const double wideFrom = 1000;

  @override
  Widget build(BuildContext context) {
    final r = request;
    if (load != AdvLoad.ready || r == null) {
      return AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry, items: 4);
    }
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= wideFrom;
      final header = _Header(request: r, onOpenStudent: onOpenStudent);
      final actions = advRequestActions(r);
      final actionsCard = actions.isEmpty || onAction == null ? null : _Actions(actions: actions, busy: busy, onAction: onAction!);
      final track = _TrackCard(request: r);
      final main = <Widget>[
        if (r.info != null) _InfoCard(info: r.info!, stage: r.stage),
        if (r.decided)
          AdvOutcomeCard(
            outcome: r.outcome!,
            note: r.outcomeNote,
            at: r.outcomeAt,
            accommodations: r.outcome == 'approved' ? r.accommodations : const [],
            until: r.accommodationUntil,
            closeNote: r.closeNote,
            closedAt: r.closedAt,
          ),
        _DetailsCard(request: r, onOpenAttachment: onOpenAttachment),
      ];
      final side = <Widget>[
        if (r.agenda.isNotEmpty) _AgendaCard(agenda: r.agenda),
        if (r.chain != null && r.chain!.steps.isNotEmpty) _ChainCard(chain: r.chain!, ended: r.decided || r.closed),
        if (r.history.isNotEmpty) _HistoryCard(history: r.history),
      ];
      List<Widget> spaced(List<Widget> xs) => [
            for (var i = 0; i < xs.length; i++) ...[if (i > 0) const SizedBox(height: AppSpace.sm), xs[i]],
          ];
      const pad = EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xl);
      if (!wide) {
        return ListView(padding: pad, children: spaced([header, ?actionsCard, track, ...main, ...side]));
      }
      return ListView(padding: pad, children: [
        header,
        const SizedBox(height: AppSpace.sm),
        track,
        const SizedBox(height: AppSpace.sm),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 7, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced(main))),
          const SizedBox(width: AppSpace.md),
          Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced([?actionsCard, ...side]))),
        ]),
      ]);
    });
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.request, this.onOpenStudent});
  final AdvRequest request;
  final VoidCallback? onOpenStudent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = request;
    final col = advStageColor(context, r.stage);
    final meta = [
      if (r.createdBy != null) t('كتبه ${advIso(r.createdBy!.shown)}', 'Filed by ${advIso(r.createdBy!.shown)}'),
      if (r.submittedAt != null) t('أُرسل ${advDate(r.submittedAt)}', 'submitted ${advDate(r.submittedAt)}') else if (r.createdAt != null) t('كُتب ${advDate(r.createdAt)}', 'written ${advDate(r.createdAt)}'),
      if (r.workItem != null && r.workItem!.ref.isNotEmpty) t('رقم المعاملة ${r.workItem!.ref}', 'Item ${r.workItem!.ref}'),
    ].join(' · ');
    final student = r.student;
    return AppCard(
      padding: AppSpace.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ExcludeSemantics(
            child: Container(
              width: AppTouch.min,
              height: AppTouch.min,
              decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: AppRadius.chipAll),
              child: Icon(advRequestKindIcon(r.kind), color: appInk(context, col)),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(header: true, child: Text(r.shownTitle, textDirection: advTextDirection(r.shownTitle), style: AppType.section(context))),
              const SizedBox(height: AppSpace.xxs),
              Text(r.typeLabel, style: AppType.meta(context)),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
          AdvStagePill(stage: r.stage, postponed: r.postponed),
          AdvPriorityPill(priority: r.priority),
          if (r.category != null) AppBadgePill(r.category!.name, color: c.textMedium, icon: r.sensitive ? Icons.lock_outline_rounded : Icons.label_outline_rounded),
          if (r.escalated && !r.decided) AppBadgePill(t('صُعّد للمديرين', 'Escalated to the directors'), color: c.danger, icon: Icons.trending_up_rounded),
        ]),
        if (student != null) ...[
          const SizedBox(height: AppSpace.sm),
          Material(
            color: c.inputBg,
            borderRadius: AppRadius.chipAll,
            child: InkWell(
              borderRadius: AppRadius.chipAll,
              onTap: onOpenStudent,
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.xs),
                child: Row(children: [
                  ExcludeSemantics(child: AppAvatar(name: student.shown, size: 32)),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(student.shown, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                      Text([t('الطالب', 'Student'), if (student.code != null) advIso(student.code!)].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                    ]),
                  ),
                  if (onOpenStudent != null) ExcludeSemantics(child: Icon(Icons.chevron_right_rounded, color: c.textMedium)),
                ]),
              ),
            ),
          ),
        ],
        if (meta.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Text(meta, style: AppType.meta(context)),
        ],
      ]),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.actions, required this.busy, required this.onAction});
  final List<(String, String, IconData, bool)> actions;
  final bool busy;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final first = actions.first;
    final rest = actions.skip(1).toList();
    return AppCard(
      padding: AppSpace.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!first.$4)
          AppPrimaryButton(icon: first.$3, label: first.$2, busy: busy, onPressed: () => onAction(first.$1))
        else
          AdvSmallAction(icon: first.$3, label: first.$2, danger: true, onTap: busy ? null : () => onAction(first.$1)),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Wrap(alignment: WrapAlignment.center, spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
            for (final a in rest) AdvSmallAction(icon: a.$3, label: a.$2, danger: a.$4, onTap: busy ? null : () => onAction(a.$1)),
          ]),
        ],
      ]),
    );
  }
}

class _TrackCard extends StatelessWidget {
  const _TrackCard({required this.request});
  final AdvRequest request;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = request;
    final step = r.step;
    final due = !r.decided && !r.draft ? step?.dueAt : null;
    final overdue = step?.overdue ?? false;
    final hint = advStageHint(r.stage, postponed: r.postponed);
    return AdvBlockCard(
      icon: Icons.route_rounded,
      title: t('أين وصل الطلب', 'Where it is now'),
      trailing: step != null && step.count > 1 && !r.decided && !r.draft
          ? Text(t('الخطوة ${step.index + 1} من ${step.count}', 'Step ${step.index + 1} of ${step.count}'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600))
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AdvStageTrack(points: r.track),
        if (hint.isNotEmpty || due != null) ...[
          Divider(height: AppSpace.lg, color: c.divider),
          if (hint.isNotEmpty) Text(hint, style: AppType.body(context).copyWith(color: c.textDark)),
          if (due != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xxs),
              child: Row(children: [
                ExcludeSemantics(child: Icon(overdue ? Icons.alarm_rounded : Icons.schedule_rounded, size: AppIconSize.sm, color: overdue ? appInk(context, c.danger) : c.textMedium)),
                const SizedBox(width: AppSpace.xxs),
                Expanded(
                  child: Text(
                    overdue
                        ? t('تجاوزت هذه الخطوة وقتها — كانت مستحقة ${AppTime.dateTime(due)}', 'This step is past its time — it was due ${AppTime.dateTime(due)}')
                        : t('القرار في هذه الخطوة مستحق ${AppTime.dateTime(due)}', 'A decision at this step is due ${AppTime.dateTime(due)}'),
                    style: AppType.meta(context).copyWith(color: overdue ? appInk(context, c.danger) : null, fontWeight: overdue ? FontWeight.w600 : null),
                  ),
                ),
              ]),
            ),
        ],
      ]),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.info, required this.stage});
  final AdvRequestInfo info;
  final String stage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pending = info.pending && stage == 'needs_info';
    final col = pending ? c.warning : c.textMedium;
    return Container(
      padding: AppSpace.card,
      decoration: BoxDecoration(color: col.withValues(alpha: 0.07), borderRadius: AppRadius.cardAll, border: Border.all(color: col.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          ExcludeSemantics(child: Icon(Icons.help_outline_rounded, color: appInk(context, col))),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(pending ? t('مطلوب معلومات إضافية', 'More information is needed') : t('طُلبت معلومات إضافية', 'More information was asked for'),
                  style: AppType.bodyStrong(context).copyWith(color: appInk(context, col))),
            ),
          ),
        ]),
        const SizedBox(height: AppSpace.xs),
        if (info.note.isNotEmpty) AdvTypedText(info.note),
        Text(
          [if (info.by != null) advIso(info.by!.shown), if (info.requestedAt != null) advDate(info.requestedAt)].join(' · '),
          style: AppType.meta(context),
        ),
        if (info.answer != null) ...[
          Divider(height: AppSpace.lg, color: col.withValues(alpha: 0.2)),
          Text(info.answeredAt == null ? t('الرد', 'The answer') : t('الرد · ${advDate(info.answeredAt)}', 'The answer · ${advDate(info.answeredAt)}'),
              style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpace.xxs),
          AdvTypedText(info.answer!),
        ],
      ]),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.request, this.onOpenAttachment});
  final AdvRequest request;
  final ValueChanged<GovAttachment>? onOpenAttachment;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = request;
    return AdvBlockCard(
      icon: Icons.notes_rounded,
      title: t('التفاصيل', 'Details'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (r.body.trim().isEmpty) Text(t('لا تفاصيل مكتوبة.', 'No details written.'), style: AppType.body(context)) else AdvTypedText(r.body.trim()),
        if (r.referral && r.targetDept != null) ...[
          const SizedBox(height: AppSpace.sm),
          AppInfoRow(Icons.alt_route_rounded, t('محالة إلى ${r.targetDept!.name}', 'Referred to ${r.targetDept!.name}')),
        ],
        if (!r.referral && r.accommodations.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Text(
            r.accommodationUntil == null
                ? t('التسهيلات المطلوبة', 'Accommodations requested')
                : t('التسهيلات المطلوبة حتى ${advDate(r.accommodationUntil, dateOnly: true)}', 'Accommodations requested until ${advDate(r.accommodationUntil, dateOnly: true)}'),
            style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpace.xxs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
            for (final a in r.accommodations) AppBadgePill(a.label, color: c.primary, icon: Icons.accessible_rounded),
          ]),
        ],
        if (r.attachments.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          GovAttachmentChips(attachments: r.attachments, onOpen: onOpenAttachment),
        ],
      ]),
    );
  }
}

class _AgendaCard extends StatelessWidget {
  const _AgendaCard({required this.agenda});
  final List<AdvAgendaEntry> agenda;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AdvBlockCard(
      icon: Icons.how_to_vote_rounded,
      color: c.purple,
      title: t('جدول أعمال المجالس', 'Council agenda'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < agenda.length; i++) ...[
          if (i > 0) Divider(height: AppSpace.lg, color: c.divider),
          _AgendaRow(entry: agenda[i]),
        ],
      ]),
    );
  }
}

class _AgendaRow extends StatelessWidget {
  const _AgendaRow({required this.entry});
  final AdvAgendaEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = entry;
    final total = e.eligible > 0 ? e.eligible : e.voted;
    Widget part(int n, Color col) => n <= 0 || total <= 0 ? const SizedBox.shrink() : Expanded(flex: n, child: Container(height: 8, color: col));
    final rest = total - e.voted;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(e.council, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
      Text(
        [
          if (e.scheduledAt != null) AppTime.dateTime(e.scheduledAt!),
          e.closed ? t('أُغلقت الجلسة', 'Session closed') : (e.status == 'open' ? t('التصويت مفتوح', 'Voting open') : t('مجدولة', 'Scheduled')),
        ].join(' · '),
        style: AppType.meta(context),
      ),
      if (total > 0) ...[
        const SizedBox(height: AppSpace.xs),
        Semantics(
          label: t('موافق ${e.approve}، رافض ${e.reject}، ممتنع ${e.abstain} من ${e.eligible}', 'Approve ${e.approve}, reject ${e.reject}, abstain ${e.abstain} of ${e.eligible}'),
          excludeSemantics: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ClipRRect(
              borderRadius: AppRadius.chipAll,
              child: Row(children: [
                part(e.approve, c.success),
                part(e.reject, c.danger),
                part(e.abstain, c.textLight),
                if (rest > 0) Expanded(flex: rest, child: Container(height: 8, color: c.inputBg)),
              ]),
            ),
            const SizedBox(height: AppSpace.xxs),
            Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, children: [
              _Legend(color: c.success, text: t('موافق ${e.approve}', 'Approve ${e.approve}')),
              _Legend(color: c.danger, text: t('رافض ${e.reject}', 'Reject ${e.reject}')),
              _Legend(color: c.textLight, text: t('ممتنع ${e.abstain}', 'Abstain ${e.abstain}')),
              if (e.eligible > 0) Text(t('من ${e.eligible} عضواً', 'of ${e.eligible} members'), style: AppType.meta(context)),
            ]),
          ]),
        ),
      ],
    ]);
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: AppSpace.xxs),
        Text(text, style: AppType.meta(context)),
      ]);
}

/// The chain step by step for staff: who decided, when, their note, why a step was skipped; earlier rounds folded.
class _ChainCard extends StatelessWidget {
  const _ChainCard({required this.chain, required this.ended});
  final AdvRequestChain chain;
  final bool ended;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AdvBlockCard(
      icon: Icons.account_tree_rounded,
      title: t('مسار الاعتماد', 'Approval chain'),
      trailing: chain.round > 1 ? AppBadgePill(t('الجولة ${chain.round}', 'Round ${chain.round}'), color: c.purple, icon: Icons.replay_rounded) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AdvChainStepsList(steps: chain.steps, ended: ended),
        if (chain.rounds.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                countText(chain.rounds.length, ar1: 'جولة سابقة', ar2: 'جولتان سابقتان', arFew: '${chain.rounds.length} جولات سابقة', arMany: '${chain.rounds.length} جولة سابقة', en1: '1 earlier round', en: '${chain.rounds.length} earlier rounds'),
                style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600),
              ),
              children: [
                for (final (n, steps) in chain.rounds) ...[
                  Align(alignment: AlignmentDirectional.centerStart, child: Text(t('الجولة $n', 'Round $n'), style: AppType.meta(context))),
                  const SizedBox(height: AppSpace.xxs),
                  AdvChainStepsList(steps: steps, ended: true),
                ],
              ],
            ),
          ),
      ]),
    );
  }
}

class AdvChainStepsList extends StatelessWidget {
  const AdvChainStepsList({super.key, required this.steps, this.ended = false});
  final List<AdvRequestStep> steps;

  /// The request was decided or closed: an open step was never reached.
  final bool ended;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < steps.length; i++)
        Builder(builder: (context) {
          final s = steps[i];
          final (IconData icon, Color col, String state) = switch (s.status) {
            'approved' => (Icons.check_rounded, c.success, t('اعتُمدت', 'Approved')),
            'rejected' => (Icons.close_rounded, c.danger, t('رُفضت', 'Rejected')),
            'skipped' => (Icons.redo_rounded, c.textLight, t('تُجووزت', 'Skipped')),
            'current' when ended => (Icons.remove_rounded, c.textMedium, t('توقّفت هنا', 'Stopped here')),
            'current' => (Icons.radio_button_checked_rounded, c.primary, t('الخطوة الحالية', 'Current step')),
            _ when ended => (Icons.remove_rounded, c.textLight, t('لم تُبلغ', 'Not reached')),
            _ => (Icons.more_horiz_rounded, c.textLight, t('بالانتظار', 'Waiting')),
          };
          final who = [if (s.by != null) advIso(s.by!.shown), if (s.at != null && s.status != 'current' && s.status != 'waiting') advDate(s.at)].join(' · ');
          return AdvRailRow(
            last: i == steps.length - 1,
            icon: icon,
            color: col,
            child: MergeSemantics(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: AppSpace.xxs),
                Wrap(spacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('${i + 1}. ${s.label}', style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                  Text(state, style: AppType.meta(context).copyWith(color: appInk(context, col), fontWeight: FontWeight.w600)),
                ]),
                if (who.isNotEmpty) Text(who, style: AppType.meta(context)),
                if (s.status == 'skipped' && s.skipReason != null) Text(advSkipReasonText(s.skipReason), style: AppType.meta(context)),
                if (s.note != null && s.status != 'skipped') ...[
                  const SizedBox(height: AppSpace.xxs),
                  AdvTypedText(s.note!, style: AppType.body(context).copyWith(color: s.status == 'rejected' ? appInk(context, c.danger) : c.textDark)),
                ],
              ]),
            ),
          );
        }),
    ]);
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.history});
  final List<AdvStagePoint> history;

  @override
  Widget build(BuildContext context) => AdvBlockCard(
        icon: Icons.history_rounded,
        title: t('سجل المراحل', 'Stage history'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = history.length - 1; i >= 0; i--)
            AdvRailRow(
              last: i == 0,
              color: i == history.length - 1 ? advStageColor(context, history[i].stage) : null,
              child: MergeSemantics(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(history[i].label, style: AppType.row(context)),
                  if (history[i].at != null) Text(AppTime.dateTime(history[i].at!), style: AppType.meta(context)),
                ]),
              ),
            ),
        ]),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Action forms (plain values)
// ═════════════════════════════════════════════════════════════════════════════

const advReviewDecisions = ['approve', 'needs_info', 'reject'];

class AdvReviewForm extends StatelessWidget {
  const AdvReviewForm({super.key, required this.request, required this.note, this.decision, this.busy = false, this.error, this.onDecision, this.onSubmit});
  final AdvRequest request;
  final TextEditingController note;
  final String? decision;
  final bool busy;
  final String? error;
  final ValueChanged<String>? onDecision;
  final VoidCallback? onSubmit;

  /// The label of the step after the current one (null: the current one is the last).
  static String? nextStep(AdvRequest r) {
    final steps = r.chain?.steps ?? const <AdvRequestStep>[];
    final i = r.chain?.current ?? r.step?.index;
    if (i == null) return null;
    for (var j = i + 1; j < steps.length; j++) {
      if (steps[j].status != 'skipped') return steps[j].label;
    }
    if (steps.isEmpty && r.step != null && r.step!.index < r.step!.count - 1) return t('الخطوة التالية', 'the next step');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final next = nextStep(request);
    final d = decision;
    final needsNote = d == 'reject' || d == 'needs_info';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(request.shownTitle, textDirection: advTextDirection(request.shownTitle), style: AppType.section(context)),
      Text([request.typeLabel, request.studentName].join(' · '), style: AppType.meta(context)),
      const SizedBox(height: AppSpace.md),
      AdvChoiceCard(
        title: next == null ? t('موافقة نهائية', 'Approve — final') : t('موافقة وإحالة إلى $next', 'Approve and send on to $next'),
        hint: next == null ? t('يصل القرار إلى الطالب والمرشد', 'The decision reaches the student and the advisor') : t('ينتقل الطلب إلى الخطوة التالية', 'The request moves to the next step'),
        selected: d == 'approve',
        color: c.success,
        icon: Icons.check_circle_outline_rounded,
        onTap: busy || onDecision == null ? null : () => onDecision!('approve'),
      ),
      AdvChoiceCard(
        title: t('طلب معلومات من المرشد', 'Ask the advisor for more information'),
        hint: t('يعود الطلب إلى المرشد ويتوقف وقت هذه الخطوة', 'It goes back to the advisor and this step\'s clock pauses'),
        selected: d == 'needs_info',
        color: c.warning,
        icon: Icons.help_outline_rounded,
        onTap: busy || onDecision == null ? null : () => onDecision!('needs_info'),
      ),
      AdvChoiceCard(
        title: t('رفض', 'Reject'),
        hint: t('يصل القرار وسببه إلى الطالب والمرشد، ويمكن للمرشد إعادة الإرسال', 'The decision and its reason reach the student and the advisor; the advisor may resubmit'),
        selected: d == 'reject',
        color: c.danger,
        icon: Icons.cancel_outlined,
        onTap: busy || onDecision == null ? null : () => onDecision!('reject'),
      ),
      const SizedBox(height: AppSpace.xs),
      AdvTypedField(
        controller: note,
        label: switch (d) {
          'reject' => t('سبب الرفض (مطلوب)', 'Why it is rejected (required)'),
          'needs_info' => t('ما المعلومات المطلوبة؟ (مطلوب)', 'What information is needed? (required)'),
          _ => t('ملاحظة (اختيارية)', 'Note (optional)'),
        },
        hint: d == 'reject' ? t('يقرأ الطالب هذا السبب', 'The student reads this reason') : null,
        minLines: 2,
        maxLength: 5000,
        enabled: !busy,
      ),
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.md),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: note,
        builder: (context, v, _) => AppPrimaryButton(
          icon: Icons.check_rounded,
          label: t('تأكيد القرار', 'Confirm the decision'),
          busy: busy,
          onPressed: d == null || (needsNote && v.text.trim().length < 3) ? null : onSubmit,
        ),
      ),
    ]);
  }
}

class AdvInfoAnswerForm extends StatelessWidget {
  const AdvInfoAnswerForm({
    super.key,
    required this.info,
    required this.answer,
    this.attachments = const [],
    this.uploading = false,
    this.busy = false,
    this.error,
    this.onAttach,
    this.onRemoveAttachment,
    this.onSubmit,
  });
  final AdvRequestInfo info;
  final TextEditingController answer;
  final List<GovAttachment> attachments;
  final bool uploading, busy;
  final String? error;
  final VoidCallback? onAttach, onSubmit;
  final ValueChanged<GovAttachment>? onRemoveAttachment;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(color: c.warning.withValues(alpha: 0.07), borderRadius: AppRadius.chipAll),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('طلب مدير الإرشاد', 'The advising director asked'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpace.xxs),
          AdvTypedText(info.note.isEmpty ? '—' : info.note),
        ]),
      ),
      const SizedBox(height: AppSpace.md),
      AdvTypedField(controller: answer, label: t('ردّك', 'Your answer'), minLines: 3, maxLength: 5000, enabled: !busy),
      const SizedBox(height: AppSpace.xs),
      if (attachments.isNotEmpty) GovAttachmentChips(attachments: attachments, onRemove: busy ? null : onRemoveAttachment),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
          onPressed: busy || uploading || onAttach == null ? null : onAttach,
          icon: uploading ? const SizedBox.square(dimension: AppIconSize.sm, child: CircularProgressIndicator(strokeWidth: AppBorder.focus)) : const Icon(Icons.attach_file_rounded, size: AppIconSize.md),
          label: Text(uploading ? t('جارٍ الرفع…', 'Uploading…') : t('إرفاق مستند', 'Attach a document')),
        ),
      ),
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.md),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: answer,
        builder: (context, v, _) => AppPrimaryButton(icon: Icons.reply_rounded, label: t('إرسال الرد', 'Send the answer'), busy: busy, onPressed: v.text.trim().isEmpty ? null : onSubmit),
      ),
    ]);
  }
}

class AdvResubmitForm extends StatelessWidget {
  const AdvResubmitForm({
    super.key,
    required this.title,
    required this.body,
    required this.note,
    this.reason,
    this.attachments = const [],
    this.uploading = false,
    this.busy = false,
    this.error,
    this.onAttach,
    this.onRemoveAttachment,
    this.onSubmit,
  });
  final TextEditingController title, body, note;

  /// Why it was rejected.
  final String? reason;
  final List<GovAttachment> attachments;
  final bool uploading, busy;
  final String? error;
  final VoidCallback? onAttach, onSubmit;
  final ValueChanged<GovAttachment>? onRemoveAttachment;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (reason != null && reason!.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(color: c.danger.withValues(alpha: 0.06), borderRadius: AppRadius.chipAll),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('سبب الرفض', 'Why it was rejected'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpace.xxs),
            AdvTypedText(reason!),
          ]),
        ),
        const SizedBox(height: AppSpace.md),
      ],
      AdvTypedField(controller: title, label: t('العنوان', 'Title'), minLines: 1, maxLines: 2, maxLength: advRequestTitleMax, enabled: !busy),
      const SizedBox(height: AppSpace.sm),
      AdvTypedField(controller: body, label: t('التفاصيل', 'Details'), minLines: 4, maxLines: 12, maxLength: advRequestBodyMax, enabled: !busy),
      const SizedBox(height: AppSpace.sm),
      AdvTypedField(controller: note, label: t('ما الذي تغيّر؟ (للمقررين)', 'What changed? (for the deciders)'), minLines: 2, maxLength: 2000, enabled: !busy),
      const SizedBox(height: AppSpace.xs),
      if (attachments.isNotEmpty) GovAttachmentChips(attachments: attachments, onRemove: busy ? null : onRemoveAttachment),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
          onPressed: busy || uploading || onAttach == null || attachments.length >= advRequestMaxAttachments ? null : onAttach,
          icon: uploading ? const SizedBox.square(dimension: AppIconSize.sm, child: CircularProgressIndicator(strokeWidth: AppBorder.focus)) : const Icon(Icons.attach_file_rounded, size: AppIconSize.md),
          label: Text(uploading ? t('جارٍ الرفع…', 'Uploading…') : t('إرفاق ملف', 'Attach a file')),
        ),
      ),
      const SizedBox(height: AppSpace.xs),
      AppBanner(icon: Icons.replay_rounded, text: t('يبدأ الطلب جولة جديدة من الخطوة الأولى.', 'The request starts a new round from the first step.')),
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.md),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: title,
        builder: (context, v, _) => AppPrimaryButton(icon: Icons.send_rounded, label: t('إعادة الإرسال', 'Resubmit'), busy: busy, onPressed: v.text.trim().isEmpty ? null : onSubmit),
      ),
    ]);
  }
}

/// A one-note sheet's content: withdraw (a reason, optional) or close the case (a follow-up note, required).
class AdvNoteSheetForm extends StatelessWidget {
  const AdvNoteSheetForm({
    super.key,
    required this.note,
    required this.label,
    required this.action,
    this.intro,
    this.required = false,
    this.danger = false,
    this.icon = Icons.check_rounded,
    this.busy = false,
    this.error,
    this.onSubmit,
  });
  final TextEditingController note;
  final String label, action;
  final String? intro;
  final bool required, danger;
  final IconData icon;
  final bool busy;
  final String? error;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (intro != null) ...[
        AppBanner(icon: danger ? Icons.warning_amber_rounded : Icons.info_outline_rounded, color: danger ? c.warning : null, text: intro!),
        const SizedBox(height: AppSpace.md),
      ],
      AdvTypedField(controller: note, label: label, minLines: 3, maxLength: 2000, enabled: !busy),
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.md),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: note,
        builder: (context, v, _) => AppPrimaryButton(icon: icon, label: action, busy: busy, onPressed: required && v.text.trim().length < 3 ? null : onSubmit),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Sheets
// ═════════════════════════════════════════════════════════════════════════════

/// The outcome of an action sheet: the request it answered, or [stale] (someone moved it first: reload).
class AdvActionResult {
  const AdvActionResult({this.request, this.stale = false});
  final AdvRequest? request;
  final bool stale;
}

/// Runs one write of a sheet: busy / error in the sheet, a stale answer closes it.
Future<void> _write(
  BuildContext ctx,
  void Function(void Function()) set,
  Future<AdvRequest> Function() call, {
  required String ok,
  required void Function(bool) setBusy,
  required void Function(String?) setError,
}) async {
  set(() {
    setBusy(true);
    setError(null);
  });
  final OrgCall r = await orgCall(call, quiet: true);
  if (!ctx.mounted) return;
  if (!r.ok && advSupportStaleCodes.contains(r.code)) {
    showAppNotice(advSupportErrorText(r.error!), error: true);
    Navigator.pop(ctx, const AdvActionResult(stale: true));
    return;
  }
  if (!r.ok) {
    set(() {
      setBusy(false);
      setError(advSupportErrorText(r.error!));
    });
    return;
  }
  showAppNotice(ok);
  Navigator.pop(ctx, AdvActionResult(request: r.data as AdvRequest));
}

Future<AdvActionResult?> showAdvReviewSheet(BuildContext context, AdvSupportApi api, AdvRequest request) {
  final note = TextEditingController();
  String? decision;
  var busy = false;
  String? error;
  return showAppSheet<AdvActionResult>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> submit() async {
          final d = decision;
          if (d == null) return;
          final next = AdvReviewForm.nextStep(request);
          await _write(
            ctx,
            set,
            () => api.review(request.id, decision: d, note: note.text, version: request.workItem?.version ?? request.version),
            ok: switch (d) {
              'approve' => next == null ? t('اعتُمد الطلب — أُبلغ الطالب والمرشد', 'Request approved — the student and the advisor are told') : t('اعتُمدت هذه الخطوة وانتقل الطلب إلى $next', 'Step approved — the request moved on to $next'),
              'needs_info' => t('أُعيد الطلب إلى المرشد لطلب معلومات', 'Returned to the advisor for more information'),
              _ => t('رُفض الطلب — أُبلغ الطالب والمرشد', 'Request rejected — the student and the advisor are told'),
            },
            setBusy: (v) => busy = v,
            setError: (v) => error = v,
          );
        }

        return AppSheetContent(
          title: t('مراجعة الطلب', 'Review the request'),
          children: [
            AdvReviewForm(
              request: request,
              note: note,
              decision: decision,
              busy: busy,
              error: error,
              onDecision: (v) => set(() => decision = v),
              onSubmit: submit,
            ),
          ],
        );
      }));
}

Future<AdvActionResult?> showAdvInfoAnswerSheet(BuildContext context, AdvSupportApi api, AdvRequest request) {
  final answer = TextEditingController();
  final files = <GovAttachment>[];
  var busy = false, uploading = false;
  String? error;
  return showAppSheet<AdvActionResult>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> attach() async {
          set(() => uploading = true);
          final a = await uploadGovAttachment(api.orgId);
          if (!ctx.mounted) return;
          set(() {
            uploading = false;
            if (a != null) files.add(a);
          });
        }

        return AppSheetContent(
          title: t('الرد على طلب المعلومات', 'Answer the information request'),
          children: [
            AdvInfoAnswerForm(
              info: request.info ?? const AdvRequestInfo(),
              answer: answer,
              attachments: files,
              uploading: uploading,
              busy: busy,
              error: error,
              onAttach: attach,
              onRemoveAttachment: (a) => set(() => files.remove(a)),
              onSubmit: () => _write(
                ctx,
                set,
                () => api.answerInfo(request.id, answer: answer.text, attachments: files),
                ok: t('أُرسلت المعلومات إلى مدير الإرشاد', 'Information sent to the advising director'),
                setBusy: (v) => busy = v,
                setError: (v) => error = v,
              ),
            ),
          ],
        );
      }));
}

Future<AdvActionResult?> showAdvResubmitSheet(BuildContext context, AdvSupportApi api, AdvRequest request) {
  final title = TextEditingController(text: request.title);
  final body = TextEditingController(text: request.body);
  final note = TextEditingController();
  final files = [...request.attachments];
  var busy = false, uploading = false;
  String? error;
  return showAppSheet<AdvActionResult>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> attach() async {
          set(() => uploading = true);
          final a = await uploadGovAttachment(api.orgId);
          if (!ctx.mounted) return;
          set(() {
            uploading = false;
            if (a != null) files.add(a);
          });
        }

        return AppSheetContent(
          title: t('إعادة إرسال الطلب', 'Resubmit the request'),
          children: [
            AdvResubmitForm(
              title: title,
              body: body,
              note: note,
              reason: request.outcomeNote,
              attachments: files,
              uploading: uploading,
              busy: busy,
              error: error,
              onAttach: attach,
              onRemoveAttachment: (a) => set(() => files.remove(a)),
              onSubmit: () => _write(
                ctx,
                set,
                () => api.resubmit(request.id, title: title.text, body: body.text, attachments: files, note: note.text),
                ok: t('أُعيد إرسال الطلب في جولة جديدة', 'Request resubmitted in a new round'),
                setBusy: (v) => busy = v,
                setError: (v) => error = v,
              ),
            ),
          ],
        );
      }));
}

/// Withdraw ([close] false) or close the case with a follow-up note ([close] true).
Future<AdvActionResult?> showAdvRequestNoteSheet(BuildContext context, AdvSupportApi api, AdvRequest request, {required bool close}) {
  final note = TextEditingController();
  var busy = false;
  String? error;
  return showAppSheet<AdvActionResult>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        return AppSheetContent(
          title: close ? t('إغلاق الحالة', 'Close the case') : (request.referral ? t('سحب الإحالة', 'Withdraw the referral') : t('سحب الطلب', 'Withdraw the request')),
          children: [
            AdvNoteSheetForm(
              note: note,
              intro: close
                  ? t('يبقى القرار كما هو، وتُسجَّل متابعتك في ملف الطالب.', 'The decision stays as it is; your follow-up is recorded on the student\'s record.')
                  : t('يتوقف الطلب عند خطوته الحالية ويُبلَّغ الطالب. لا يمكن التراجع.', 'The request stops at its current step and the student is told. This cannot be undone.'),
              label: close ? t('ملاحظة المتابعة (مطلوبة)', 'Follow-up note (required)') : t('السبب (مطلوب)', 'Why (required)'),
              action: close ? t('إغلاق الحالة', 'Close the case') : t('سحب', 'Withdraw'),
              icon: close ? Icons.task_alt_rounded : Icons.undo_rounded,
              required: true,
              danger: !close,
              busy: busy,
              error: error,
              onSubmit: () => _write(
                ctx,
                set,
                () => close ? api.close(request.id, note: note.text) : api.cancel(request.id, reason: note.text),
                ok: close ? t('أُغلقت الحالة', 'Case closed') : (request.referral ? t('سُحبت الإحالة', 'Referral withdrawn') : t('سُحب الطلب', 'Request withdrawn')),
                setBusy: (v) => busy = v,
                setError: (v) => error = v,
              ),
            ),
          ],
        );
      }));
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class AdvRequestPage extends StatelessWidget {
  const AdvRequestPage({super.key, required this.orgId, required this.requestId, this.initial});
  final int orgId, requestId;

  /// The list's row, drawn until the detail loads.
  final AdvRequest? initial;

  @override
  Widget build(BuildContext context) => OrgPushedPage(
        title: initial?.referral ?? false ? t('إحالة', 'Referral') : t('طلب دعم', 'Support request'),
        subtitle: initial?.studentName,
        helpPageId: 'org.advising',
        maxWidth: AppWidth.content.max,
        child: _AdvRequestBody(orgId: orgId, requestId: requestId, initial: initial),
      );
}

class _AdvRequestBody extends StatefulWidget {
  const _AdvRequestBody({required this.orgId, required this.requestId, this.initial});
  final int orgId, requestId;
  final AdvRequest? initial;

  @override
  State<_AdvRequestBody> createState() => _AdvRequestBodyState();
}

class _AdvRequestBodyState extends State<_AdvRequestBody> {
  late final AdvSupportApi _api = AdvSupportApi(widget.orgId);
  OrgPageRefresh? _refresh;
  late AdvRequest? _request = widget.initial;
  late AdvLoad _load = widget.initial == null ? AdvLoad.loading : AdvLoad.ready;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _reload);
    _reload();
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final r = await orgCall(() => _api.request(widget.requestId), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _request = r.data as AdvRequest;
        _load = AdvLoad.ready;
      } else if (_request == null || r.code == 'advising_not_found') {
        _request = null;
        _load = advFailLoad(r);
        _error = advSupportErrorText(r.error!);
      } else {
        showAppNotice(advSupportErrorText(r.error!), error: true);
      }
    });
    if (r.ok && mounted) OrgPageRefresh.reportUpdated(context);
  }

  /// A sheet answered: the detail is read again (chain, history and agenda move with every action).
  void _after(AdvActionResult? res) {
    if (res == null || !mounted) return;
    if (res.request != null) setState(() => _request = res.request);
    _reload();
  }

  Future<void> _action(String key) async {
    final r = _request;
    if (r == null) return;
    switch (key) {
      case 'review':
        _after(await showAdvReviewSheet(context, _api, r));
      case 'answer':
        _after(await showAdvInfoAnswerSheet(context, _api, r));
      case 'resubmit':
        _after(await showAdvResubmitSheet(context, _api, r));
      case 'cancel':
        _after(await showAdvRequestNoteSheet(context, _api, r, close: false));
      case 'close':
        _after(await showAdvRequestNoteSheet(context, _api, r, close: true));
      case 'edit':
        final saved = await showAdvRequestComposer(context, orgId: widget.orgId, memberId: r.memberId, studentName: r.studentName, editing: r);
        if (saved != null) _after(AdvActionResult(request: saved));
      case 'submit':
        final first = r.track.length > 1 ? r.track[1].label : null;
        final yes = await appConfirm(
          context,
          confirmLabel: t('إرسال', 'Send'),
          message: r.referral
              ? t('إرسال الإحالة إلى ${r.targetDept?.name ?? 'الجهة'}؟', 'Send the referral to ${r.targetDept?.name ?? 'the department'}?')
              : (first == null ? t('إرسال الطلب إلى مسار الاعتماد؟', 'Submit the request to the approval chain?') : t('إرسال الطلب؟ يبدأ عند: $first', 'Submit the request? It starts at: $first')),
        );
        if (!yes || !mounted) return;
        setState(() => _busy = true);
        final res = await orgCall(() => _api.submit(r.id, version: r.version), quiet: true);
        if (!mounted) return;
        setState(() => _busy = false);
        if (!res.ok) {
          showAppNotice(advSupportErrorText(res.error!), error: true);
          if (advSupportStaleCodes.contains(res.code)) _reload();
          return;
        }
        final made = res.data as AdvRequest;
        showAppNotice(made.referral ? t('أُرسلت الإحالة', 'Referral sent') : t('أُرسل الطلب إلى مسار الاعتماد', 'Request submitted to the approval chain'));
        _after(AdvActionResult(request: made));
      case 'delete':
        final yes = await appConfirm(context, danger: true, confirmLabel: t('حذف', 'Delete'), message: t('حذف هذه المسودة؟', 'Delete this draft?'));
        if (!yes || !mounted) return;
        setState(() => _busy = true);
        final res = await orgCall(() => _api.delete(r.id), quiet: true);
        if (!mounted) return;
        setState(() => _busy = false);
        if (!res.ok) {
          showAppNotice(advSupportErrorText(res.error!), error: true);
          return;
        }
        showAppNotice(t('حُذفت المسودة', 'Draft deleted'));
        Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) => AdvRequestView(
        load: _load,
        request: _request,
        errorText: _error,
        busy: _busy,
        onRetry: () {
          setState(() => _load = AdvLoad.loading);
          _reload();
        },
        onAction: _action,
        onOpenStudent: _request == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvStudentPage(orgId: widget.orgId, memberId: _request!.memberId, name: _request!.studentName))),
        onOpenAttachment: (a) => openGovAttachment(context, a),
      );
}
