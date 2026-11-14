// lib/features/org/governance/gov_forward_sheet.dart — forwarding an APPROVED item and answering a forward (D-890).
//
//   GovForwardForm                   the presentational form (plain values + callbacks; layout-tested): where to
//                                    (higher council · outside party · person), the required actions, deadline, note
//   showGovForwardSheet(ctx, api, …) runs the form, POSTs …/items/{id}/forward, returns the item
//   GovForwardTaskCard               "Forwarded to you: review and comment · execute — due …" on the item page of the
//                                    person it was forwarded to, with the Respond button
//   showGovForwardAnswerSheet(ctx, r) picks the action and its answer (+ a comment), returns them; the caller sends
//   GovForwardDetails                the forward's lines inside the routes chain (decision carried, actions, answers)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show SheetHeader, asMap, t;
import '../org_v3.dart' show orgCall, orgErrorText;
import 'gov_api.dart';
import 'gov_models.dart';
import 'gov_ui.dart';

IconData forwardKindIcon(String k) => switch (k) {
      'council' => Icons.account_balance_rounded,
      'external' => Icons.public_rounded,
      _ => Icons.person_rounded,
    };

IconData forwardActionIcon(String a) => switch (a) {
      'info' => Icons.info_outline_rounded,
      'review' => Icons.rate_review_rounded,
      'approval' => Icons.verified_rounded,
      'vote' => Icons.how_to_vote_rounded,
      _ => Icons.task_alt_rounded,
    };

class GovForwardForm extends StatelessWidget {
  const GovForwardForm({
    super.key,
    required this.to,
    required this.person,
    required this.actions,
    required this.externalName,
    required this.externalOrg,
    required this.externalRef,
    required this.note,
    required this.dueAt,
    required this.onTo,
    required this.onPickPerson,
    required this.onToggleAction,
    required this.onDue,
    required this.onSubmit,
    this.councilName,
    this.busy = false,
    this.error,
  });

  final String to;
  final GovUser? person;
  final List<String> actions;
  final TextEditingController externalName, externalOrg, externalRef, note;
  final DateTime? dueAt;
  final ValueChanged<String> onTo;
  final VoidCallback onPickPerson;
  final ValueChanged<String> onToggleAction;
  final ValueChanged<DateTime?> onDue;
  final VoidCallback? onSubmit;

  /// The council it would go up to (the faculty council), shown under the choice.
  final String? councilName;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('إلى أين؟', 'Where to?'), style: AppType.meta(context).copyWith(color: c.textLight)),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final k in forwardKinds) AppChoiceChip(label: forwardKindLabel(k), icon: forwardKindIcon(k), selected: to == k, onTap: () => onTo(k)),
      ]),
      const SizedBox(height: AppSpace.sm),
      if (to == 'council')
        AppBanner(
          icon: Icons.account_balance_rounded,
          text: t('يُعرض على ${councilName ?? 'مجلس الكلية'} ويُفتح عليه تصويت جديد؛ يبقى قرار المجلس الحالي مرفقاً في السجل.',
              'It goes before the ${councilName ?? 'faculty council'} for a new vote; the current decision stays attached in the history.'),
        ),
      if (to == 'external') ...[
        AppField(controller: externalName, label: t('اسم الجهة الخارجية', 'Name of the outside party')),
        const SizedBox(height: AppSpace.sm),
        AppField(controller: externalOrg, label: t('الإدارة / الجهة التابعة لها (اختياري)', 'Department / organization (optional)')),
        const SizedBox(height: AppSpace.sm),
        AppField(controller: externalRef, label: t('رقم الخطاب الصادر (اختياري)', 'Outgoing letter number (optional)')),
      ],
      if (to == 'user') ...[
        GovPersonField(label: t('الشخص', 'Person'), person: person, onPick: onPickPerson),
        const SizedBox(height: AppSpace.md),
        Text(t('المطلوب منه', 'What must they do?'), style: AppType.meta(context).copyWith(color: c.textLight)),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final a in forwardActions)
            AppChoiceChip(label: forwardActionLabel(a), icon: forwardActionIcon(a), selected: actions.contains(a), onTap: () => onToggleAction(a)),
        ]),
        const SizedBox(height: AppSpace.sm),
        GovDateField(
          label: t('الموعد النهائي (اختياري)', 'Deadline (optional)'),
          value: dueAt,
          withTime: true,
          icon: Icons.timer_rounded,
          onPick: () async {
            final d = await pickGovDateTime(context, initial: dueAt);
            if (d != null) onDue(d);
          },
          onClear: () => onDue(null),
        ),
      ],
      const SizedBox(height: AppSpace.sm),
      AppField(controller: note, label: t('ملاحظة مرافقة (اختياري)', 'Covering note (optional)'), maxLines: 3),
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(label: t('إحالة', 'Forward'), icon: Icons.send_rounded, busy: busy, onPressed: onSubmit),
    ]);
  }
}

/// Forward [item] (approved) onward; returns the reloaded item, or null when cancelled.
Future<WorkItem?> showGovForwardSheet(BuildContext context, GovApi api, WorkItem item) async {
  var to = 'user';
  GovUser? person;
  var actions = <String>[];
  DateTime? due;
  String? error;
  var busy = false;
  String? councilName;
  final r0 = await orgCall(() => api.councils(), quiet: true);
  if (r0.ok) {
    for (final c in r0.data as List<Council>) {
      if (c.level == 'faculty') councilName = c.name;
    }
  }
  if (!context.mounted) return null;
  final name = TextEditingController(), org = TextEditingController(), ref = TextEditingController(), note = TextEditingController();
  return showAppSheet<WorkItem>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetHeader('${t('إحالة بعد الاعتماد', 'Forward after approval')} · ${item.ref}'),
            Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(ctx).copyWith(fontWeight: FontWeight.w600, color: ctx.colors.textMedium)),
            const SizedBox(height: AppSpace.sm),
            GovForwardForm(
              to: to,
              person: person,
              actions: actions,
              externalName: name,
              externalOrg: org,
              externalRef: ref,
              note: note,
              dueAt: due,
              councilName: councilName,
              busy: busy,
              error: error,
              onTo: (k) => set(() {
                to = k;
                error = null;
              }),
              onPickPerson: () async {
                final p = await pickGovPerson(ctx, api.orgId, title: t('إحالة إلى شخص', 'Forward to a person'), selectedId: person?.id);
                if (p != null) set(() => person = p);
              },
              onToggleAction: (a) => set(() {
                if (a == 'info') {
                  actions = actions.contains('info') ? [] : ['info'];
                } else {
                  actions = actions.contains(a) ? (actions.where((x) => x != a).toList()) : [...actions.where((x) => x != 'info'), a];
                }
                error = null;
              }),
              onDue: (d) => set(() => due = d),
              onSubmit: () async {
                final problem = forwardProblem(to: to, userId: person?.id, externalName: name.text, actions: actions);
                if (problem != null) {
                  set(() => error = problem);
                  return;
                }
                set(() {
                  busy = true;
                  error = null;
                });
                final body = forwardBody(
                    to: to,
                    userId: person?.id,
                    external: {'name': name.text, 'organization': org.text, 'reference': ref.text},
                    actions: actions,
                    note: note.text,
                    dueAt: due);
                final r = await orgCall(() => api.forward(item.id, body), quiet: true);
                if (!ctx.mounted) return;
                if (!r.ok) {
                  set(() {
                    busy = false;
                    error = govCodeTexts()[r.code] ?? orgErrorText(r.error!);
                  });
                  return;
                }
                appToast(t('أُحيل الطلب', 'Forwarded'));
                Navigator.pop(ctx, WorkItem.fromJson(asMap(r.data)));
              },
            ),
          ]),
        );
      }));
}

/// "Forwarded to you" on the item page of the person an approved item was forwarded to.
class GovForwardTaskCard extends StatelessWidget {
  const GovForwardTaskCard({super.key, required this.route, required this.busy, required this.onRespond});
  final WorkRoute route;
  final bool busy;
  final VoidCallback? onRespond;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fw = route.forward!;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.assignment_ind_rounded, size: AppIconSize.md, color: c.primary),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(t('أُحيل إليك بعد اعتماده', 'Forwarded to you after approval'), style: AppType.bodyStrong(context).copyWith(color: c.textDark))),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Text(
          [
            if (route.sourceName.isNotEmpty) '${t('من', 'From')} ${route.sourceName}',
            if (route.dueAt != null) '${t('قبل', 'by')} ${govWhen(route.dueAt)}',
          ].join(' · '),
          style: AppType.meta(context).copyWith(color: route.dueAt != null && route.dueAt!.isBefore(DateTime.now().toUtc()) ? c.danger : c.textMedium),
        ),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
          for (final a in fw.actions)
            AppBadgePill(forwardActionLabel(a), color: fw.openActions.contains(a) ? c.warning : c.success),
        ]),
        if ((route.note ?? '').isNotEmpty) ...[const SizedBox(height: AppSpace.xs), Text(route.note!, style: AppType.label(context).copyWith(color: c.textDark, height: 1.4))],
        if (onRespond != null) ...[
          const SizedBox(height: AppSpace.sm),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppPill(icon: Icons.reply_rounded, label: t('الرد', 'Respond'), color: c.primary, onTap: busy ? null : onRespond),
          ),
        ],
      ]),
    );
  }
}

/// Picks one open action of [route] and its answer; a review needs a comment, a rejection a reason.
Future<(String, String, String)?> showGovForwardAnswerSheet(BuildContext context, WorkRoute route) {
  final open = route.forward?.openActions ?? const <String>[];
  if (open.isEmpty) return Future.value(null);
  var action = open.first;
  var answer = forwardAnswers[action]!.first;
  String? error;
  final note = TextEditingController();
  return showAppSheet<(String, String, String)>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        final needsNote = action == 'review' || answer == 'rejected';
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetHeader(t('الرد على الإحالة', 'Respond to the forward')),
            if (open.length > 1) ...[
              Text(t('الإجراء', 'Action'), style: AppType.meta(ctx).copyWith(color: c.textLight)),
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (final a in open)
                  AppChoiceChip(
                      label: forwardActionLabel(a),
                      icon: forwardActionIcon(a),
                      selected: action == a,
                      onTap: () => set(() {
                            action = a;
                            answer = forwardAnswers[a]!.first;
                            error = null;
                          })),
              ]),
              const SizedBox(height: AppSpace.sm),
            ],
            Text(t('ردك', 'Your answer'), style: AppType.meta(ctx).copyWith(color: c.textLight)),
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final a in forwardAnswers[action]!) AppChoiceChip(label: routeAnswerLabel(a), selected: answer == a, onTap: () => set(() => answer = a)),
            ]),
            const SizedBox(height: AppSpace.sm),
            AppField(controller: note, label: needsNote ? t('التعليق (مطلوب)', 'Comment (required)') : t('ملاحظة (اختياري)', 'Note (optional)'), maxLines: 3),
            if (error != null) ...[const SizedBox(height: AppSpace.sm), AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!)],
            const SizedBox(height: AppSpace.sm),
            AppPrimaryButton(
              label: t('إرسال الرد', 'Send answer'),
              icon: Icons.reply_rounded,
              onPressed: () {
                if (needsNote && note.text.trim().length < 3) {
                  set(() => error = govCodeTexts()[action == 'review' ? 'comment_required' : 'reason_required']);
                  return;
                }
                Navigator.pop(ctx, (action, answer, note.text.trim()));
              },
            ),
          ]),
        );
      }));
}

/// The forward's lines inside the routes chain: the decision it carried, the actions and the answers.
class GovForwardDetails extends StatelessWidget {
  const GovForwardDetails({super.key, required this.forward});
  final RouteForward forward;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fw = forward;
    final d = fw.decision;
    final tally = asMap(d['tally']);
    final lines = <String>[
      forwardKindLabel(fw.kind),
      if (fw.kind == 'external' && (fw.external['reference'] ?? '').toString().isNotEmpty) '${t('رقم الخطاب', 'Letter no.')} ${fw.external['reference']}',
      if (d['outcome'] != null)
        '${t('مرفق القرار', 'Decision attached')}: ${itemStatusLabel('${d['outcome']}')}${d['via'] == 'council' ? ' · ${t('بقرار المجلس', 'by council vote')}' : ''}'
            '${tally.isEmpty ? '' : ' (${tally['approve'] ?? 0}/${tally['eligible'] ?? 0})'}',
      if (fw.actions.isNotEmpty) '${t('المطلوب', 'Required')}: ${fw.actions.map(forwardActionLabel).join(' · ')}',
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final l in lines) Text(l, style: AppType.meta(context).copyWith(color: c.textMedium, height: 1.4)),
      for (final r in fw.responses)
        Text(
          '${forwardActionLabel(r.action)}: ${routeAnswerLabel(r.answer)} · ${r.by?.name ?? ''}${r.at == null ? '' : ' · ${govWhen(r.at)}'}${(r.note ?? '').isEmpty ? '' : ' — ${r.note}'}',
          style: AppType.meta(context).copyWith(color: c.textDark, height: 1.4),
        ),
    ]);
  }
}
