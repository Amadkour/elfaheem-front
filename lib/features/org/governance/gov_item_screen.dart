// lib/features/org/governance/gov_item_screen.dart — one work item (spec §4 `GET …/items/{id}` full):
//
//   GovItemScreen(id, {orgId, member})   loads the item (staff: GovApi(orgId).item · member: GovApi.memberItem),
//                                        runs every action (decide with the first-decision lock-out, route /
//                                        forward, escalate, assign, status, withdraw, edit, delete, answer a route,
//                                        comment) and reloads
//   GovItemBody                          the presentational page (plain values + callbacks; layout-tested):
//                                        header (who it is for, D-140) · decision banner / bar · approval chain
//                                        (current step + history, D-141) · pending route card · actions (export
//                                        this item, resubmit after a rejection) · routes chain · agenda history ·
//                                        timeline
//   GovCommentComposer                   the comment box (internal switch for staff)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_chip.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/context_switcher.dart' show ContextExitButton;
import 'package:flutter_education_app/features/auth/auth_provider.dart' show MyAuthProvider;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show SheetHeader, asMap, t;
import '../../admin/admin_list.dart' show AdminAvatar;
import '../org_page_header.dart' show OrgPageRefresh, OrgPushedPage, orgUsesDashboardHeader;
import '../org_providers.dart' show OrgSession;
import '../org_v3.dart' show orgCall, orgErrorText, orgUtc;
import 'gov_api.dart';
import 'gov_models.dart';
import 'gov_request_parts.dart';
import 'gov_route_sheet.dart';
import 'gov_ui.dart';
import 'gov_wiring.dart' show govExportHubEnabled, govExportItemIds;

// ═════════════════════════════════════════════════════════════════════════════
//  Presentational body
// ═════════════════════════════════════════════════════════════════════════════

class GovItemBody extends StatelessWidget {
  const GovItemBody({
    super.key,
    required this.item,
    this.member = false,
    this.currentUserId,
    this.busy = false,
    this.onDecide,
    this.onRoute,
    this.onEscalate,
    this.onRecall,
    this.onAssign,
    this.onStatus,
    this.onWithdraw,
    this.onEdit,
    this.onDelete,
    this.onAnswerRoute,
    this.onOpenAttachment,
    this.onResubmit,
    this.onExport,
  });

  final WorkItem item;
  final bool member, busy;
  final int? currentUserId;
  final ValueChanged<String>? onDecide;
  final VoidCallback? onRoute, onEscalate, onRecall, onAssign, onStatus, onWithdraw, onEdit, onDelete;

  /// The requester edits a rejected item and sends it again (D-141); export = this one item (D-140).
  final VoidCallback? onResubmit, onExport;
  final ValueChanged<WorkRoute>? onAnswerRoute;
  final ValueChanged<GovAttachment>? onOpenAttachment;

  bool get _routedToMe {
    final pr = item.pendingRoute;
    if (pr == null) return false;
    if (pr.toUser != null) return pr.toUser!.id == currentUserId;
    return !member; // routed to an entity: its staff answer (the server checks the membership)
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final it = item;
    final can = it.can;
    final pr = it.pendingRoute;
    final actions = <Widget>[
      if (!member && can['route'] && onRoute != null && it.isOpen) AppPill(icon: Icons.alt_route_rounded, label: t('إحالة / توجيه', 'Route / forward'), onTap: busy ? null : onRoute),
      if (!member && (can['decide'] || can['route']) && onEscalate != null && it.isOpen)
        AppPill(icon: Icons.trending_up_rounded, label: t('تصعيد لمجلس الكلية', 'Escalate to faculty council'), color: c.purple, onTap: busy ? null : onEscalate),
      // sent to a council by mistake: back to its sender while the agenda is not voting yet
      if (!member && can['route'] && onRecall != null && it.status == 'in_council')
        AppPill(icon: Icons.undo_rounded, label: t('سحب من المجلس', 'Recall from council'), color: c.warning, onTap: busy ? null : onRecall),
      if (!member && can['route'] && onAssign != null && it.isOpen) AppPill(icon: Icons.person_add_alt_1_rounded, label: t('إسناد', 'Assign'), color: c.textMedium, onTap: busy ? null : onAssign),
      if (!member && (can['decide'] || can['route']) && onStatus != null) AppPill(icon: Icons.flag_rounded, label: t('الحالة', 'Status'), color: c.textMedium, onTap: busy ? null : onStatus),
      if (can['edit'] && onEdit != null) AppPill(icon: Icons.edit_rounded, label: t('تعديل', 'Edit'), color: c.textMedium, onTap: busy ? null : onEdit),
      if (can['resubmit'] && onResubmit != null) AppPill(icon: Icons.replay_rounded, label: t('تعديل وإعادة تقديم', 'Edit and resubmit'), color: c.primary, onTap: busy ? null : onResubmit),
      if (can['withdraw'] && onWithdraw != null) AppPill(icon: Icons.undo_rounded, label: t('سحب المعاملة', 'Withdraw'), color: c.warning, onTap: busy ? null : onWithdraw),
      if (!member && can['export'] && onExport != null) AppPill(icon: Icons.file_download_rounded, label: t('تصدير', 'Export'), color: c.textMedium, onTap: busy ? null : onExport),
      if (can['delete'] && onDelete != null) AppPill(icon: Icons.delete_outline_rounded, label: t('حذف', 'Delete'), color: c.danger, onTap: busy ? null : onDelete),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.lg), children: [
      _Header(item: it, member: member, onOpenAttachment: onOpenAttachment),
      if (it.decision != null) ...[const SizedBox(height: AppSpace.sm), _DecisionBanner(decision: it.decision!, status: it.status)],
      if (!member && can['decide'] && it.isDecidable && onDecide != null) ...[const SizedBox(height: AppSpace.sm), _DecisionBar(busy: busy, onDecide: onDecide!)],
      if (it.chain != null && it.chain!.steps.isNotEmpty) ...[const SizedBox(height: AppSpace.sm), GovChainCard(chain: it.chain!, itemStatus: it.status)],
      if (pr != null) ...[
        const SizedBox(height: AppSpace.sm),
        _PendingRouteCard(route: pr, canAnswer: _routedToMe && onAnswerRoute != null && pr.action != 'vote', busy: busy, onAnswer: () => onAnswerRoute?.call(pr)),
      ],
      if (actions.isNotEmpty) ...[const SizedBox(height: AppSpace.sm), Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: actions)],
      if (it.routes.isNotEmpty) ...[
        const SizedBox(height: AppSpace.md),
        AppSectionTitle(t('مسار الإحالات', 'Routing chain'), subtitle: t('${it.routes.length} إحالة', '${it.routes.length} routes')),
        GovRouteChain(routes: it.routes),
      ],
      if (it.agenda.isNotEmpty) ...[
        const SizedBox(height: AppSpace.md),
        AppSectionTitle(t('جلسات المجالس', 'Council sessions')),
        GovAgendaHistory(agenda: it.agenda),
      ],
      const SizedBox(height: AppSpace.md),
      AppSectionTitle(t('السجل', 'Timeline'), subtitle: member ? null : t('التعليقات الداخلية لا يراها مقدّم المعاملة', 'Internal comments are hidden from the submitter')),
      GovTimeline(events: it.events, onOpenAttachment: onOpenAttachment),
    ]);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.item, required this.member, this.onOpenAttachment});
  final WorkItem item;
  final bool member;
  final ValueChanged<GovAttachment>? onOpenAttachment;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final it = item;
    final source = it.anonymous
        ? t('مجهول', 'Anonymous')
        : [if (it.sourceUser != null) it.sourceUser!.name, if (it.sourceDept != null) it.sourceDept!.name].join(' · ');
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(it.ref, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textLight)),
          GovTypePill(it.type),
          GovStatusPill(it.status),
          GovPriorityPill(it.priority),
          GovDuePill(dueAt: it.dueAt, overdue: it.overdue),
          if (it.voteOutcome != null) GovOutcomePill(it.voteOutcome!),
        ]),
        const SizedBox(height: AppSpace.xs),
        Text(it.title, style: AppType.section(context).copyWith(color: c.textDark, height: 1.3)),
        if ((it.body ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          SelectableText(it.body!.trim(), style: AppType.row(context).copyWith(color: c.textDark, height: 1.55)),
        ],
        if (it.tags.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [for (final tg in it.tags) AppBadgePill('#$tg', color: c.textMedium)]),
        ],
        if (it.attachments.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          GovAttachmentChips(attachments: it.attachments, onOpen: onOpenAttachment),
        ],
        const Divider(height: 22),
        GovKV(Icons.apartment_rounded, t('لدى', 'With'), it.ownerDept?.name ?? '—'),
        GovKV(Icons.outbox_rounded, it.beneficiary == null ? t('المصدر', 'Source') : t('قدّمه', 'Filed by'), source),
        // a link only when this person may open that student (service staff, a council member: the name alone, D-290)
        if (!it.anonymous && it.sourceUser != null)
          EntityGuardedChip(EntityRef(EntityKind.student, it.sourceUser!.id, label: it.sourceUser!.name)),
        if (it.beneficiary != null) GovBeneficiaryRows(it.beneficiary!),
        if (it.chainStep != null && it.isOpen)
          GovKV(
            Icons.account_tree_rounded,
            t('المرحلة', 'Step'),
            it.chain?.currentStep == null
                ? it.chainStep!.label
                : '${it.chainStep!.index + 1}/${it.chainStep!.count} · ${it.chain!.currentStep!.label}',
          ),
        if (!member || it.assignee != null) GovKV(Icons.person_rounded, t('المسؤول', 'Assignee'), it.assignee?.name ?? t('غير مسند', 'Unassigned')),
        if (it.category != null) GovKV(Icons.label_outline_rounded, t('التصنيف', 'Category'), it.category!.name),
        if (it.dueAt != null) GovKV(Icons.timer_rounded, t('الاستحقاق', 'Due'), govWhen(it.dueAt)),
        GovKV(Icons.schedule_rounded, t('أُنشئت', 'Created'), govWhen(it.createdAt)),
        if (it.decidedAt != null) GovKV(Icons.gavel_rounded, t('صدر القرار', 'Decided'), govWhen(it.decidedAt)),
      ]),
    );
  }
}

class _DecisionBanner extends StatelessWidget {
  const _DecisionBanner({required this.decision, required this.status});
  final Decision decision;
  final String status;

  @override
  Widget build(BuildContext context) {
    final d = decision;
    final via = switch (d.via) {
      'council' => t('بقرار المجلس', 'by council vote'),
      'delegate' => t('بالتفويض', 'by a delegate'),
      _ => t('من رئيس الجهة', 'by the entity head'),
    };
    final who = d.by == null ? '' : ' · ${d.by!.name}';
    final text = '${itemStatusLabel(d.outcome)} $via$who${d.at == null ? '' : ' · ${govWhen(d.at)}'}${(d.note ?? '').isEmpty ? '' : '\n${d.note}'}';
    return AppBanner(
      icon: d.outcome == 'approved' ? Icons.verified_rounded : (d.outcome == 'rejected' ? Icons.cancel_rounded : Icons.pause_circle_rounded),
      color: govStatusColor(context, d.outcome == 'postponed' ? 'postponed' : d.outcome),
      text: text.isEmpty ? itemStatusLabel(status) : text,
    );
  }
}

class _DecisionBar extends StatelessWidget {
  const _DecisionBar({required this.busy, required this.onDecide});
  final bool busy;
  final ValueChanged<String> onDecide;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget btn(String outcome, IconData icon, Color col, String label) => FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: col, minimumSize: const Size.fromHeight(46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control))),
          onPressed: busy ? null : () => onDecide(outcome),
          icon: Icon(icon, color: c.onHero, size: AppIconSize.md),
          label: Text(label, style: AppType.bodyStrong(context).copyWith(color: c.onHero)),
        );
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.gavel_rounded, size: AppIconSize.md, color: c.primary),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(t('القرار بيدك', 'Your decision'), style: AppType.bodyStrong(context).copyWith(color: c.textDark))),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Text(t('أول قرار يُغلق المعاملة أمام بقية المخوّلين', 'The first decision locks the item for every other decider'), style: AppType.meta(context).copyWith(color: c.textMedium)),
        const SizedBox(height: AppSpace.sm),
        LayoutBuilder(builder: (context, box) {
          final a = btn('approved', Icons.check_rounded, c.success, t('اعتماد', 'Approve'));
          final r = btn('rejected', Icons.close_rounded, c.danger, t('رفض', 'Reject'));
          if (box.maxWidth < 340) return Column(children: [a, const SizedBox(height: AppSpace.xs), r]);
          return Row(children: [Expanded(child: a), const SizedBox(width: AppSpace.sm), Expanded(child: r)]);
        }),
      ]),
    );
  }
}

class _PendingRouteCard extends StatelessWidget {
  const _PendingRouteCard({required this.route, required this.canAnswer, required this.busy, required this.onAnswer});
  final WorkRoute route;
  final bool canAnswer, busy;
  final VoidCallback onAnswer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = route;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.warning.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(govActionIcon(r.action), size: AppIconSize.md, color: c.warning),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text('${t('بانتظار', 'Waiting')}: ${routeActionLabel(r.action)} · ${r.targetName}', style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
          ),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Text(
          [
            if (r.sourceName.isNotEmpty) '${t('من', 'From')} ${r.sourceName}',
            if (r.createdAt != null) govWhen(r.createdAt),
            if (r.dueAt != null) '${t('قبل', 'by')} ${govWhen(r.dueAt)}',
          ].join(' · '),
          style: AppType.meta(context).copyWith(color: c.textMedium),
        ),
        if ((r.note ?? '').isNotEmpty) ...[const SizedBox(height: AppSpace.xs), Text(r.note!, style: AppType.label(context).copyWith(color: c.textDark, height: 1.4))],
        if (canAnswer) ...[
          const SizedBox(height: AppSpace.sm),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppPill(icon: Icons.reply_rounded, label: t('الرد على الإحالة', 'Answer'), color: c.warning, onTap: busy ? null : onAnswer),
          ),
        ],
      ]),
    );
  }
}

/// The routes as a vertical stepper: from → to · action · status · answer · dates.
class GovRouteChain extends StatelessWidget {
  const GovRouteChain({super.key, required this.routes});
  final List<WorkRoute> routes;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Color col(WorkRoute r) => switch (r.status) {
          'pending' => c.warning,
          'answered' => r.answer == 'rejected' ? c.danger : c.success,
          'superseded' => c.textLight,
          _ => c.textMedium,
        };
    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, AppSpace.sm, AppSpace.xxs),
      child: Column(children: [
        for (var i = 0; i < routes.length; i++)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 28,
                child: Column(children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(color: col(routes[i]).withValues(alpha: 0.14), shape: BoxShape.circle),
                    child: Icon(govActionIcon(routes[i].action), size: AppIconSize.xs, color: col(routes[i])),
                  ),
                  if (i < routes.length - 1) Expanded(child: Container(width: 2, color: c.divider)),
                ]),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text('${routes[i].sourceName.isEmpty ? '—' : routes[i].sourceName} → ${routes[i].targetName}', style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
                      AppBadgePill(routeActionLabel(routes[i].action), color: c.textMedium),
                      AppBadgePill(routes[i].answer != null ? routeAnswerLabel(routes[i].answer!) : routeStatusLabel(routes[i].status), color: col(routes[i])),
                    ]),
                    Text(
                      [
                        if (routes[i].createdAt != null) govWhen(routes[i].createdAt),
                        if (routes[i].createdBy != null) '${t('بواسطة', 'by')} ${routes[i].createdBy!.name}',
                        if (routes[i].dueAt != null) '${t('قبل', 'due')} ${govWhen(routes[i].dueAt)}',
                      ].join(' · '),
                      style: AppType.meta(context).copyWith(color: c.textLight),
                    ),
                    if ((routes[i].note ?? '').isNotEmpty) Text(routes[i].note!, style: AppType.label(context).copyWith(color: c.textDark, height: 1.4)),
                    if (routes[i].answeredAt != null)
                      Text(
                        '${t('الرد', 'Answer')}: ${routes[i].answeredBy?.name ?? ''} · ${govWhen(routes[i].answeredAt)}${(routes[i].answerNote ?? '').isEmpty ? '' : ' — ${routes[i].answerNote}'}',
                        style: AppType.meta(context).copyWith(color: c.textMedium, height: 1.4),
                      ),
                  ]),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// Council sessions the item was on, with counts and the outcome.
class GovAgendaHistory extends StatelessWidget {
  const GovAgendaHistory({super.key, required this.agenda, this.onOpenSession});
  final List<AgendaRef> agenda;
  final ValueChanged<int>? onOpenSession;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(children: [
      for (final a in agenda)
        AppCard(
          margin: const EdgeInsets.only(bottom: AppSpace.xs),
          padding: const EdgeInsets.all(AppSpace.sm),
          onTap: onOpenSession == null ? null : () => onOpenSession!(a.sessionId),
          child: Row(children: [
            Icon(Icons.how_to_vote_rounded, color: govOutcomeColor(context, a.status), size: AppIconSize.lg),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.council?.name ?? t('المجلس', 'Council'), style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
                Text(
                  [
                    if (a.scheduledAt != null) govWhen(a.scheduledAt),
                    '✓ ${a.approve} · ✗ ${a.reject} · − ${a.abstain} / ${a.eligible}',
                    if (a.approvePct != null) '${a.approvePct!.toStringAsFixed(0)}%',
                  ].join(' · '),
                  style: AppType.meta(context).copyWith(color: c.textMedium),
                ),
              ]),
            ),
            const SizedBox(width: AppSpace.xs),
            AppBadgePill(agendaStatusLabel(a.status), color: govOutcomeColor(context, a.status)),
          ]),
        ),
    ]);
  }
}

/// The events with icons; internal comments carry a lock badge.
class GovTimeline extends StatelessWidget {
  const GovTimeline({super.key, required this.events, this.onOpenAttachment});
  final List<WorkEvent> events;
  final ValueChanged<GovAttachment>? onOpenAttachment;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (events.isEmpty) {
      return AppCard(child: Text(t('لا أحداث بعد', 'No events yet'), textAlign: TextAlign.center, style: AppType.label(context).copyWith(color: c.textMedium)));
    }
    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, AppSpace.sm, AppSpace.xxs),
      child: Column(children: [
        for (final e in events)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (e.kind == 'comment' && e.actor != null)
                AdminAvatar(name: e.actor!.name, url: e.actor!.avatar, size: 30)
              else
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: (e.kind == 'decided' ? c.success : c.primary).withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(govEventIcon(e.kind), size: AppIconSize.xs, color: e.kind == 'decided' ? c.success : c.primary),
                ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs / 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(e.actor?.name ?? t('النظام', 'System'), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
                    Text(eventKindLabel(e.kind), style: AppType.meta(context).copyWith(color: c.textMedium)),
                    if (e.internal) AppBadgePill(t('داخلي', 'Internal'), color: c.warning, icon: Icons.lock_outline_rounded),
                    if (e.createdAt != null) Text(govWhen(e.createdAt), style: AppType.meta(context).copyWith(color: c.textLight)),
                  ]),
                  if ((e.body ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xxs),
                    Container(
                      width: double.infinity,
                      padding: e.kind == 'comment' ? const EdgeInsets.all(AppSpace.sm) : EdgeInsets.zero,
                      decoration: e.kind == 'comment' ? BoxDecoration(color: (e.internal ? c.warning : c.primary).withValues(alpha: 0.06), borderRadius: BorderRadius.circular(AppRadius.control)) : null,
                      child: Text(e.body!.trim(), style: AppType.label(context).copyWith(color: c.textDark, height: 1.5)),
                    ),
                  ],
                  if (_summary(e).isNotEmpty) Text(_summary(e), style: AppType.meta(context).copyWith(color: c.textMedium, height: 1.4)),
                  for (final a in _attachments(e))
                    TextButton.icon(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      onPressed: onOpenAttachment == null ? null : () => onOpenAttachment!(a),
                      icon: const Icon(Icons.attach_file_rounded, size: AppIconSize.sm),
                      label: Text(a.name.isEmpty ? t('مرفق', 'Attachment') : a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }

  List<GovAttachment> _attachments(WorkEvent e) {
    final list = e.data['attachments'];
    if (list is! List) return const [];
    return [for (final a in list) if (a is Map) GovAttachment.fromJson(Map<String, dynamic>.from(a))];
  }

  /// A short line from `data` (outcome, status, target, assignee) for non-comment events.
  String _summary(WorkEvent e) {
    final d = e.data;
    final parts = <String>[];
    if (d['outcome'] != null) parts.add(itemStatusLabel('${d['outcome']}'));
    if (d['status'] != null) parts.add(itemStatusLabel('${d['status']}'));
    if (d['action'] != null) parts.add(routeActionLabel('${d['action']}'));
    final to = d['to'];
    if (to is Map) parts.add('→ ${to['name'] ?? to['name_ar'] ?? to['name_en'] ?? ''}');
    if (d['to_name'] != null) parts.add('→ ${d['to_name']}');
    if (d['note'] != null && '${d['note']}'.isNotEmpty) parts.add('${d['note']}');
    if (d['sla'] == true) parts.add(t('تجاوز المهلة', 'SLA passed'));
    return parts.join(' · ');
  }
}

/// The comment box: text + internal switch (staff) + send.
class GovCommentComposer extends StatefulWidget {
  const GovCommentComposer({super.key, required this.onSend, this.allowInternal = false, this.busy = false});
  final Future<bool> Function(String body, bool internal) onSend;
  final bool allowInternal, busy;

  @override
  State<GovCommentComposer> createState() => _GovCommentComposerState();
}

class _GovCommentComposerState extends State<GovCommentComposer> {
  final _ctrl = TextEditingController();
  bool _internal = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _ctrl.text.trim();
    if (body.isEmpty) return;
    if (await widget.onSend(body, _internal)) _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xs, AppSpace.sm, AppSpace.sm),
      decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider))),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.allowInternal)
            AppSwitchTile(
              dense: true,
              padding: EdgeInsets.zero,
              icon: Icons.lock_outline_rounded,
              title: t('تعليق داخلي (لا يراه مقدّم المعاملة)', 'Internal comment (hidden from the submitter)'),
              value: _internal,
              onChanged: (v) => setState(() => _internal = v),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 4,
                style: AppType.row(context).copyWith(color: c.textDark),
                decoration: InputDecoration(
                  hintText: _internal ? t('ملاحظة داخلية…', 'Internal note…') : t('اكتب تعليقاً…', 'Write a comment…'),
                  isDense: true,
                  filled: true,
                  fillColor: _internal ? c.warning.withValues(alpha: 0.08) : c.inputBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control), borderSide: BorderSide(color: c.divider)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control), borderSide: BorderSide(color: c.divider)),
                ),
              ),
            ),
            const SizedBox(width: AppSpace.xs),
            IconButton.filled(tooltip: t('إرسال', 'Send'), 
              style: IconButton.styleFrom(backgroundColor: c.primary, minimumSize: const Size(46, 46)),
              onPressed: widget.busy ? null : _send,
              icon: widget.busy
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.onHero))
                  : Icon(Icons.send_rounded, color: c.onHero),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Screen (network)
// ═════════════════════════════════════════════════════════════════════════════

class GovItemScreen extends StatefulWidget {
  const GovItemScreen(this.id, {super.key, this.orgId, this.member = false});
  final int id;
  final int? orgId;

  /// The submitter's / recipient's view through the public routes (no organization in the path).
  final bool member;

  @override
  State<GovItemScreen> createState() => _GovItemScreenState();
}

class _GovItemScreenState extends State<GovItemScreen> {
  WorkItem? _item;
  bool _failed = false, _missing = false, _busy = false;
  GovApi? _api;

  int? get _orgId {
    if (widget.orgId != null) return widget.orgId;
    try {
      return context.read<OrgSession>().currentId;
    } catch (_) {
      return null;
    }
  }

  int? get _me {
    try {
      return Provider.of<MyAuthProvider>(context, listen: false).currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// The dashboard header's Refresh reloads the item (staff in this organization); "Updated" is when it answered.
  final _refresh = OrgPageRefresh();

  @override
  void initState() {
    super.initState();
    _refresh.attach(_load);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.member) _api = GovApi(_orgId ?? 0);
      _load();
    });
  }

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await orgCall(() => widget.member ? GovApi.memberItem(widget.id) : _api!.item(widget.id), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _item = r.data as WorkItem;
        _failed = false;
      } else {
        _failed = _item == null;
        _missing = r.endpointMissing;
        if (_item != null) appToast(orgErrorText(r.error!), error: true);
      }
    });
    if (r.ok) _refresh.markUpdated();
  }

  /// Runs a mutation, shows the error unless handled, reloads on success.
  Future<bool> _do(Future<dynamic> Function() fn, {String? ok}) async {
    setState(() => _busy = true);
    final r = await orgCall(fn, ok: ok, quiet: true);
    if (!mounted) return false;
    setState(() => _busy = false);
    if (!r.ok) {
      if (r.code == 'already_decided') {
        final d = Decision.from(r.detail['decision']);
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.block)),
            title: Text(t('صدر القرار بالفعل', 'Already decided'), style: AppType.section(ctx)),
            content: Text(
              d == null
                  ? govCodeTexts()['already_decided']!
                  : '${d.by?.name ?? t('شخص آخر', 'Someone else')} ${d.outcome == 'approved' ? t('اعتمد', 'approved') : t('رفض', 'rejected')} ${t('المعاملة', 'the item')}${d.at == null ? '' : ' · ${govWhen(d.at)}'}${(d.note ?? '').isEmpty ? '' : '\n${d.note}'}',
              style: AppType.row(ctx).copyWith(height: 1.5),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('حسناً', 'OK')))],
          ),
        );
      } else if (r.code == 'stale_version') {
        appToast(govCodeTexts()['stale_version']!, error: true);
      } else {
        appToast(govCodeTexts()[r.code] ?? orgErrorText(r.error!), error: true);
      }
      await _load();
      return false;
    }
    if (r.data is Map && asMap(r.data)['id'] != null && asMap(r.data)['ref'] != null) {
      setState(() => _item = WorkItem.fromJson(asMap(r.data)));
    } else {
      await _load();
    }
    return true;
  }

  Future<void> _decide(String outcome) async {
    final it = _item!;
    final reject = outcome == 'rejected';
    final step = it.chain?.currentStep;
    final more = !reject && it.chain != null && it.chain!.current != null && it.chain!.current! < it.chain!.steps.length - 1;
    final note = await askGovNote(
      context,
      title: outcome == 'approved' ? t('اعتماد ${it.ref}', 'Approve ${it.ref}') : t('رفض ${it.ref}', 'Reject ${it.ref}'),
      hint: reject
          ? t('سبب الرفض (مطلوب — يصل إلى مقدّم الطلب)', 'Reason for rejecting (required — the requester sees it)')
          : (more ? t('ملاحظة (اختياري) — ينتقل الطلب بعدها إلى «${it.chain!.steps[it.chain!.current! + 1].label}»', 'Note (optional) — then it moves to “${it.chain!.steps[it.chain!.current! + 1].label}”') : null),
      confirmLabel: outcome == 'approved' ? (step != null && more ? t('اعتماد الخطوة', 'Approve this step') : t('اعتماد', 'Approve')) : t('رفض', 'Reject'),
      danger: reject,
      required: reject,
      minLength: reject ? 3 : 0,
      tooShort: govCodeTexts()['reason_required'],
    );
    if (note == null) return;
    await _do(() => _api!.decide(it.id, outcome: outcome, note: note.isEmpty ? null : note, version: it.version), ok: t('صدر القرار', 'Decision recorded'));
  }

  Future<void> _route() async {
    final r = await showGovRouteSheet(context, _api!, _item!);
    if (r != null && mounted) setState(() => _item = r);
  }

  Future<void> _recall() async {
    final note = await askGovNote(context, title: t('سحب المعاملة من المجلس', 'Recall the item from the council'), confirmLabel: t('سحب', 'Recall'));
    if (note == null) return;
    await _do(() => _api!.recall(_item!.id, note: note.isEmpty ? null : note), ok: t('سُحبت المعاملة', 'Recalled'));
  }

  Future<void> _escalate() async {
    final note = await askGovNote(context, title: t('تصعيد إلى مجلس الكلية', 'Escalate to the faculty council'), confirmLabel: t('تصعيد', 'Escalate'));
    if (note == null) return;
    await _do(() => _api!.escalate(_item!.id, note: note.isEmpty ? null : note), ok: t('صُعّدت المعاملة', 'Escalated'));
  }

  Future<void> _assign() async {
    final it = _item!;
    final choice = await showAppSheet<String>(context, (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
          SheetHeader(t('إسناد', 'Assign')),
          ListTile(leading: const Icon(Icons.person_search_rounded), title: Text(t('اختيار شخص…', 'Pick a person…')), onTap: () => Navigator.pop(ctx, 'pick')),
          if (it.assignee != null)
            ListTile(leading: const Icon(Icons.person_off_rounded), title: Text(t('إلغاء الإسناد (${it.assignee!.name})', 'Unassign (${it.assignee!.name})')), onTap: () => Navigator.pop(ctx, 'none')),
          const SizedBox(height: AppSpace.sm),
        ]));
    if (choice == null || !mounted) return;
    if (choice == 'none') {
      await _do(() => _api!.assign(it.id, null), ok: t('أُلغي الإسناد', 'Unassigned'));
      return;
    }
    final p = await pickGovPerson(context, _api!.orgId, title: t('إسناد إلى', 'Assign to'), selectedId: it.assignee?.id);
    if (p == null) return;
    await _do(() => _api!.assign(it.id, p.id), ok: t('أُسندت إلى ${p.name}', 'Assigned to ${p.name}'));
  }

  Future<void> _status() async {
    final it = _item!;
    final options = {
      'in_review': (t('قيد المراجعة', 'In review'), Icons.rate_review_rounded),
      'postponed': (t('تأجيل', 'Postpone'), Icons.pause_circle_rounded),
      'closed': (t('إغلاق', 'Close'), Icons.check_circle_rounded),
      'reopened': (t('إعادة فتح', 'Reopen'), Icons.refresh_rounded),
    };
    final pick = await showAppSheet<String>(context, (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
          SheetHeader(t('تغيير الحالة', 'Change status')),
          for (final e in options.entries)
            if (!(e.key == 'reopened' && it.isOpen) && !(e.key != 'reopened' && e.key == it.status))
              ListTile(leading: Icon(e.value.$2), title: Text(e.value.$1), onTap: () => Navigator.pop(ctx, e.key)),
          const SizedBox(height: AppSpace.sm),
        ]));
    if (pick == null || !mounted) return;
    final note = await askGovNote(context, title: options[pick]!.$1, confirmLabel: options[pick]!.$1);
    if (note == null) return;
    await _do(() => _api!.setStatus(it.id, pick, note: note.isEmpty ? null : note), ok: t('تم', 'Done'));
  }

  Future<void> _resubmit() async {
    final r = await showGovResubmitSheet(context, _item!);
    if (r != null && mounted) setState(() => _item = r);
  }

  Future<void> _export() async {
    final oid = _orgId;
    if (oid == null) return;
    await govExportItemIds(context, oid, [_item!.id], deptId: _item!.ownerDept?.id);
  }

  Future<void> _withdraw() async {
    if (!await appConfirm(context, message: t('سحب المعاملة؟ لن تُراجع بعد ذلك.', 'Withdraw the item? It will no longer be reviewed.'), danger: true)) return;
    await _do(() => GovApi.memberWithdraw(_item!.id), ok: t('سُحبت المعاملة', 'Withdrawn'));
  }

  Future<void> _delete() async {
    if (!await appConfirm(context, message: t('حذف المعاملة ${_item!.ref}؟', 'Delete item ${_item!.ref}?'), danger: true)) return;
    setState(() => _busy = true);
    final r = await orgCall(() => _api!.deleteItem(_item!.id), ok: t('حُذفت', 'Deleted'));
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) Navigator.of(context).pop();
  }

  Future<void> _answerRoute(WorkRoute r) async {
    final it = _item!;
    final answers = switch (r.action) {
      'info' => ['noted'],
      'review' => ['reviewed'],
      'approval' => ['approved', 'rejected'],
      _ => ['noted', 'reviewed'],
    };
    var answer = answers.first;
    final note = TextEditingController();
    final body = await showAppSheet<(String, String)>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          return Padding(
            padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, 16 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SheetHeader('${t('الرد على الإحالة', 'Answer the route')} · ${routeActionLabel(r.action)}'),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (final a in answers) AppChoiceChip(label: routeAnswerLabel(a), selected: answer == a, onTap: () => set(() => answer = a)),
              ]),
              const SizedBox(height: AppSpace.sm),
              AppField(controller: note, label: t('ملاحظة (اختياري)', 'Note (optional)'), maxLines: 3),
              const SizedBox(height: AppSpace.sm),
              AppPrimaryButton(label: t('إرسال الرد', 'Send answer'), icon: Icons.reply_rounded, onPressed: () => Navigator.pop(ctx, (answer, note.text.trim()))),
            ]),
          );
        }));
    if (body == null || !mounted) return;
    await _do(() => _api!.answerRoute(it.id, r.id, answer: body.$1, note: body.$2.isEmpty ? null : body.$2), ok: t('أُرسل الرد', 'Answer sent'));
  }

  Future<void> _edit() async {
    final it = _item!;
    final title = TextEditingController(text: it.title), body = TextEditingController(text: it.body ?? ''), tags = TextEditingController(text: it.tags.join(', '));
    var priority = it.priority;
    DateTime? due = it.dueAt;
    int? category = it.category?.id;
    List<Category> cats = const [];
    if (it.ownerDept != null) {
      final r = await orgCall(() => _api!.categories(it.ownerDept!.id), quiet: true);
      if (r.ok) cats = r.data as List<Category>;
    }
    if (!mounted) return;
    final saved = await showAppSheet<bool>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final c = ctx.colors;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, 16 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SheetHeader('${t('تعديل', 'Edit')} ${it.ref}'),
              AppField(controller: title, label: t('العنوان', 'Title')),
              const SizedBox(height: AppSpace.sm),
              AppField(controller: body, label: t('التفاصيل', 'Details'), maxLines: 5),
              const SizedBox(height: AppSpace.sm),
              if (cats.isNotEmpty) ...[
                AppDropdown<int>(
                  value: category ?? 0,
                  decoration: InputDecoration(labelText: t('التصنيف', 'Category'), prefixIcon: const Icon(Icons.label_outline_rounded)),
                  items: [
                    DropdownMenuItem(value: 0, child: Text(t('بدون تصنيف', 'No category'))),
                    for (final x in cats) DropdownMenuItem(value: x.id, child: Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => set(() => category = v == 0 ? null : v),
                ),
                const SizedBox(height: AppSpace.sm),
              ],
              Text(t('الأولوية', 'Priority'), style: AppType.meta(ctx).copyWith(color: c.textLight)),
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (final p in priorities) AppChoiceChip(label: priorityLabelOf(p), selected: priority == p, onTap: () => set(() => priority = p)),
              ]),
              const SizedBox(height: AppSpace.sm),
              GovDateField(
                label: t('الاستحقاق', 'Due'),
                value: due,
                withTime: true,
                icon: Icons.timer_rounded,
                onPick: () async {
                  final d = await pickGovDateTime(ctx, initial: due);
                  if (d != null) set(() => due = d);
                },
                onClear: () => set(() => due = null),
              ),
              const SizedBox(height: AppSpace.sm),
              AppField(controller: tags, label: t('وسوم (مفصولة بفواصل)', 'Tags (comma separated)')),
              const SizedBox(height: AppSpace.md),
              AppPrimaryButton(label: t('حفظ', 'Save'), icon: Icons.save_rounded, onPressed: () => Navigator.pop(ctx, true)),
            ]),
          );
        }));
    if (saved != true || !mounted) return;
    await _do(
      () => _api!.patchItem(it.id, {
        'title': title.text.trim(),
        'body': body.text.trim(),
        'category_id': category,
        'priority': priority,
        'due_at': orgUtc(due),
        'tags': tags.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
        'version': it.version,
      }),
      ok: t('تم الحفظ', 'Saved'),
    );
  }

  Future<bool> _comment(String body, bool internal) async {
    setState(() => _busy = true);
    final r = await orgCall(() => widget.member ? GovApi.memberComment(_item!.id, body) : _api!.comment(_item!.id, body, internal: internal));
    if (!mounted) return false;
    setState(() => _busy = false);
    if (r.ok) await _load();
    return r.ok;
  }

  @override
  Widget build(BuildContext context) {
    final it = _item;
    final title = it == null ? t('المعاملة', 'Item') : it.ref;
    Widget child;
    if (it == null && !_failed) {
      child = const AppListSkeleton(items: 5);
    } else if (_missing) {
      child = const GovNeedsServer();
    } else if (it == null) {
      child = AppEmpty(icon: Icons.cloud_off_rounded, title: t('تعذّر التحميل', 'Could not load'), actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load);
    } else {
      child = Column(children: [
        Expanded(
          child: AppRefresh(
            onRefresh: _load,
            child: GovItemBody(
              item: it,
              member: widget.member,
              currentUserId: _me,
              busy: _busy,
              onDecide: widget.member ? null : _decide,
              onRoute: widget.member ? null : _route,
              onEscalate: widget.member ? null : _escalate,
              onRecall: widget.member ? null : _recall,
              onAssign: widget.member ? null : _assign,
              onStatus: widget.member ? null : _status,
              onWithdraw: widget.member ? _withdraw : null,
              onEdit: widget.member ? null : _edit,
              onDelete: widget.member ? null : _delete,
              onAnswerRoute: widget.member ? null : _answerRoute,
              onOpenAttachment: (a) => openGovAttachment(context, a),
              onResubmit: widget.member ? _resubmit : null,
              onExport: !widget.member && govExportHubEnabled() ? _export : null,
            ),
          ),
        ),
        if (it.can['comment'] && it.status != 'withdrawn') GovCommentComposer(onSend: _comment, allowInternal: !widget.member, busy: _busy),
      ]);
    }
    // staff of this organization: the dashboard's header (Back · ref · type, status and owner · Refresh · switcher);
    // a member (submitter / recipient), a deep link before the organization loaded: the screen's own app bar
    if (orgUsesDashboardHeader(context, _orgId)) {
      return OrgPushedPage(helpPageId: 'org.governance', 
        title: title,
        subtitle: it == null ? null : [itemTypeLabel(it.type), itemStatusLabel(it.status), if (it.ownerDept != null) it.ownerDept!.name].join(' · '),
        refresh: _refresh,
        maxWidth: 900,
        child: child,
      );
    }
    return BasePage(
      useWebCard: true,
      maxWith: 900,
      appBar: ScreenAppBar(title: title, actions: [
        if (it != null) IconButton(tooltip: t('تحديث', 'Refresh'), onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        if (!widget.member) const ContextExitButton(),
      ]),
      child: child,
    );
  }
}
