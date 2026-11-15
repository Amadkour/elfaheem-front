// lib/features/org/governance/gov_session_screen.dart — one council session: header, the manager's actions by
// status (draft → published → voting → closed), the agenda (order · item · status · live result · my vote ·
// voters · postpone / escalate), and the minutes (spec §3 "Councils", §5).
//
// Presentational widgets take plain values and are pumped by test/ui/gov_council_layout_test.dart:
//   SessionHeader · AgendaRow · VoteResultView · MyVoteRow · VotersList · GovMinutesView ·
//   AgendaCandidatePicker · SessionEditBody
// GovSessionScreen is the thin network page around them.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/context_switcher.dart' show ContextExitButton;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show SheetHeader, asDouble, asInt, asMap, asMapList, askText, t;
import '../org_page_header.dart' show OrgPageRefresh, OrgPushedPage, orgUsesDashboardHeader;
import '../org_v3.dart' show orgCall, orgErrorText, orgParseUtc, orgUtc;
import 'gov_api.dart';
import 'gov_council_s2.dart';
import 'gov_council_ui.dart';
import 'gov_institutions_s3.dart' show DecisionTemplate, decisionTemplatesOf;
import 'gov_models.dart';
import 'package:flutter_education_app/design/app_icons.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Vote result
// ═════════════════════════════════════════════════════════════════════════════

/// Counts + stacked bar + percentage + outcome. [compact] is the one-line form used in lists.
class VoteResultView extends StatelessWidget {
  const VoteResultView({
    super.key,
    required this.approve,
    required this.reject,
    required this.abstain,
    required this.eligible,
    this.approvePct,
    this.outcome,
    this.compact = false,
    this.live = false,
  });

  final int approve, reject, abstain, eligible;
  final double? approvePct;

  /// approved | rejected | tied | no_quorum | postponed (null or anything else = not decided yet).
  final String? outcome;
  final bool compact, live;

  int get voted => approve + reject + abstain;
  bool get decided => outcome != null && voteOutcomes.contains(outcome);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final base = eligible > voted ? eligible : voted;
    final remaining = (base - voted).clamp(0, 1 << 30);
    final pct = approvePct ?? (approve + reject == 0 ? 0.0 : approve / (approve + reject) * 100);
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: SizedBox(
        height: compact ? 8 : 12,
        child: base == 0
            ? Container(color: c.divider.withValues(alpha: 0.6))
            : Row(children: [
                if (approve > 0) Expanded(flex: approve, child: Container(color: c.success)),
                if (reject > 0) Expanded(flex: reject, child: Container(color: c.danger)),
                if (abstain > 0) Expanded(flex: abstain, child: Container(color: c.textLight)),
                if (remaining > 0) Expanded(flex: remaining, child: Container(color: c.divider.withValues(alpha: 0.6))),
              ]),
      ),
    );
    final counts = GovPillRow([
      AppBadgePill('$approve', icon: voteIcon('approve'), color: c.success),
      AppBadgePill('$reject', icon: voteIcon('reject'), color: c.danger),
      AppBadgePill('$abstain', icon: voteIcon('abstain'), color: c.textMedium),
      if (decided) AppBadgePill(voteOutcomeLabel(outcome!), color: agendaStatusColor(context, outcome!), icon: Icons.gavel_rounded),
      if (!decided && live) AppBadgePill(t('مباشر', 'Live'), color: c.warning, icon: Icons.sensors_rounded),
    ]);
    if (compact) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [bar, const SizedBox(height: AppSpace.xs), counts]);
    }
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: c.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.how_to_vote_rounded, size: AppIconSize.sm, color: c.primary),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(live && !decided ? t('النتيجة الحالية', 'Current result') : t('النتيجة', 'Result'), style: AppType.bodyStrong(context))),
          Text(t('${pct.toStringAsFixed(0)}% موافقة', '${pct.toStringAsFixed(0)}% approve'), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.primary)),
        ]),
        const SizedBox(height: AppSpace.xs),
        bar,
        const SizedBox(height: AppSpace.xs),
        counts,
        const SizedBox(height: AppSpace.xs),
        Text(
          eligible > 0 ? t('صوّت $voted من $eligible عضواً', '$voted of $eligible members voted') : t('صوّت $voted', '$voted voted'),
          style: AppType.meta(context).copyWith(color: c.textMedium),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  My vote
// ═════════════════════════════════════════════════════════════════════════════

/// Approve / Reject / Abstain with an optional note. [value] is my current vote; [enabled] only while the session
/// is voting and I may vote. Tapping a choice sends it at once ([onVote]); the note goes with the next tap.
class MyVoteRow extends StatefulWidget {
  const MyVoteRow({super.key, required this.value, required this.enabled, required this.onVote, this.busy = false, this.withNote = true, this.note});
  final String? value;
  final bool enabled, busy, withNote;
  final String? note;
  final Future<void> Function(String vote, String? note)? onVote;

  @override
  State<MyVoteRow> createState() => _MyVoteRowState();
}

class _MyVoteRowState extends State<MyVoteRow> {
  late final _note = TextEditingController(text: widget.note ?? '');
  late bool _noteOpen = (widget.note ?? '').isNotEmpty;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = widget.value;
    final title = v == null
        ? (widget.enabled ? t('صوتك', 'Your vote') : t('لم تصوّت', 'You did not vote'))
        : (widget.enabled ? t('صوّتّ: ${voteLabel(v)} — تغيير؟', 'You voted ${voteLabel(v)} — change?') : t('صوّتّ: ${voteLabel(v)}', 'You voted ${voteLabel(v)}'));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(v == null ? Icons.ballot_outlined : voteIcon(v), size: AppIconSize.sm, color: v == null ? c.textLight : voteColor(context, v)),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: Text(title, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: v == null ? c.textMedium : voteColor(context, v)))),
        if (widget.busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
      if (widget.enabled || v != null) ...[
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final opt in voteValues)
            _VoteChip(
              label: voteLabel(opt),
              icon: voteIcon(opt),
              color: voteColor(context, opt),
              selected: v == opt,
              onTap: widget.enabled && !widget.busy && widget.onVote != null
                  ? () => widget.onVote!(opt, _note.text.trim().isEmpty ? null : _note.text.trim())
                  : null,
            ),
          if (widget.withNote && widget.enabled)
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => setState(() => _noteOpen = !_noteOpen),
              icon: Icon(_noteOpen ? Icons.expand_less_rounded : Icons.notes_rounded, size: AppIconSize.md),
              label: Text(t('ملاحظة', 'Note'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.primary)),
            ),
        ]),
        if (_noteOpen && widget.withNote && widget.enabled) ...[
          const SizedBox(height: AppSpace.xs),
          AppField(controller: _note, label: t('ملاحظة مع صوتك (اختياري)', 'A note with your vote (optional)'), maxLines: 2),
          if (v != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: widget.busy || widget.onVote == null ? null : () => widget.onVote!(v, _note.text.trim().isEmpty ? null : _note.text.trim()),
                child: Text(t('حفظ الملاحظة', 'Save the note'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.primary)),
              ),
            ),
        ],
      ],
    ]);
  }
}

class _VoteChip extends StatelessWidget {
  const _VoteChip({required this.label, required this.icon, required this.color, required this.selected, this.onTap});
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dim = onTap == null && !selected;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
          decoration: BoxDecoration(
            color: selected ? color : c.inputBg,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: selected ? color : c.divider),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: AppIconSize.sm, color: selected ? c.onHero : (dim ? c.textLight : color)),
            const SizedBox(width: AppSpace.xs),
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: selected ? c.onHero : (dim ? c.textLight : c.textDark))),
            ),
          ]),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Voters
// ═════════════════════════════════════════════════════════════════════════════

/// Who voted what (managers live, everyone after the close).
class VotersList extends StatelessWidget {
  const VotersList({super.key, required this.votes});
  final List<CouncilVote> votes;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (votes.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t('المصوّتون (${votes.length})', 'Voters (${votes.length})'), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textMedium)),
      const SizedBox(height: AppSpace.xs),
      for (final v in votes)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppAvatar(name: v.user.name, url: v.user.avatar, size: 28),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(v.user.name, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.textDark)),
                  AppBadgePill(voteLabel(v.vote), icon: voteIcon(v.vote), color: voteColor(context, v.vote)),
                  if (v.at != null) Text(govWhen(v.at), style: AppType.meta(context).copyWith(color: c.textLight)),
                ]),
                if ((v.note ?? '').trim().isNotEmpty) Text(v.note!, style: AppType.meta(context).copyWith(color: c.textMedium)),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Session header
// ═════════════════════════════════════════════════════════════════════════════

/// Hero + the session facts: council, kind, status, times, eligible count, and the countdown while voting.
class SessionHeader extends StatelessWidget {
  const SessionHeader({super.key, required this.session, this.now});
  final CouncilSession session;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = session;
    final councilName = s.council?.name ?? '';
    final closes = s.votingClosesAt;
    final third = s.isVoting && closes != null
        ? AppHeroStat(icon: Icons.timer_rounded, value: countdownText(closes, now: now), label: t('حتى إغلاق التصويت', 'until voting closes'))
        : s.isClosed && s.closedAt != null
            ? AppHeroStat(icon: Icons.lock_clock_rounded, value: govDay(s.closedAt), label: t('أُغلقت', 'closed'))
            : AppHeroStat(icon: Icons.flag_rounded, value: sessionStatusLabel(s.status), label: t('الحالة', 'status'));
    final pending = s.agenda.where((a) => !a.decided && a.status != 'withdrawn').length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppHero(
        title: (s.title ?? '').trim().isNotEmpty ? s.title!.trim() : sessionKindLabel(s.kind),
        subtitle: [if (councilName.isNotEmpty) councilName, if (s.scheduledAt != null) govWhen(s.scheduledAt)].join(' · '),
        icon: sessionKindIcon(s.kind),
        stats: [
          AppHeroStat(icon: Icons.list_alt_rounded, value: '${s.agenda.length}', label: t('بنود', 'items')),
          AppHeroStat(icon: Icons.groups_rounded, value: '${s.eligibleCount ?? s.council?.members ?? 0}', label: t('مؤهّلون', 'eligible')),
          third,
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
        child: AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GovPillRow([
              AppBadgePill(sessionKindLabel(s.kind), icon: sessionKindIcon(s.kind), color: s.kind == 'extraordinary' ? c.purple : c.primary),
              AppBadgePill(sessionStatusLabel(s.status), color: sessionStatusColor(context, s.status), icon: Icons.circle, ),
              if (s.isVoting && closes != null) AppBadgePill(t('يُغلق بعد ${countdownText(closes, now: now)}', 'closes in ${countdownText(closes, now: now)}'), icon: Icons.timer_rounded, color: c.warning),
              if (s.isVoting && pending > 0) AppBadgePill(t('$pending بنود قيد التصويت', '$pending items being voted'), color: c.primary),
            ]),
            const SizedBox(height: AppSpace.sm),
            GovInfoLine(Icons.event_rounded, t('موعد الجلسة', 'Scheduled'), govWhen(s.scheduledAt)),
            GovInfoLine(Icons.campaign_rounded, t('نُشر جدول الأعمال', 'Agenda published'), govWhen(s.publishedAt)),
            GovInfoLine(Icons.how_to_vote_rounded, t('فُتح التصويت', 'Voting opened'), govWhen(s.votingOpensAt)),
            GovInfoLine(Icons.timer_off_rounded, t('يُغلق التصويت', 'Voting closes'), govWhen(s.votingClosesAt), color: s.isVoting ? c.warning : null),
            GovInfoLine(Icons.lock_clock_rounded, t('أُغلقت', 'Closed'), govWhen(s.closedAt)),
            GovInfoLine(Icons.groups_rounded, t('الأعضاء المؤهّلون', 'Eligible members'), s.eligibleCount == null ? '' : '${s.eligibleCount}'),
            GovInfoLine(Icons.event_note_rounded, t('موعد انتهاء المراجعة', 'Review deadline'), govWhen(s.reviewDeadline)),
            GovInfoLine(Icons.meeting_room_rounded, t('الانعقاد', 'Meeting'), s.meeting?.text ?? ''),
            GovInfoLine(Icons.notifications_active_outlined, t('آخر تذكير', 'Last reminder'), govWhen(s.manualRemindedAt)),
            if ((s.notes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: AppSpace.xs),
              Text(s.notes!, style: AppType.label(context).copyWith(color: c.textMedium)),
            ],
          ]),
        ),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Agenda row
// ═════════════════════════════════════════════════════════════════════════════

/// One agenda entry: order · item card · status · result · my vote · voters · notes · manager actions.
class AgendaRow extends StatelessWidget {
  const AgendaRow({
    super.key,
    required this.agenda,
    required this.sessionStatus,
    this.myVote,
    this.showResult = false,
    this.compactResult = false,
    this.showVoters = false,
    this.canVote = false,
    this.voteBusy = false,
    this.manager = false,
    this.canEscalate = true,
    this.onVote,
    this.onOpenItem,
    this.onRemove,
    this.onPostpone,
    this.onEscalate,
    this.dragHandle,
    this.onResults,
    this.onConflict,
  });

  final AgendaItem agenda;
  final String sessionStatus;
  final String? myVote;
  final bool showResult, compactResult, showVoters, canVote, voteBusy, manager, canEscalate;
  final Future<void> Function(String vote, String? note)? onVote;
  final VoidCallback? onOpenItem, onRemove, onPostpone, onEscalate;
  final Widget? dragHandle;

  /// D-969: opens the named results (the chip and the "Who voted?" button); [onConflict] = "I have a conflict of
  /// interest" (given only while I may declare one).
  final VoidCallback? onResults, onConflict;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = agenda;
    final it = a.item;
    final decidedElsewhere = (a.note ?? '').contains('decided_elsewhere') || (it.decision != null && it.decision!.via != 'council' && it.isDecided);
    final open = !a.decided && a.status != 'withdrawn' && sessionStatus != 'closed' && sessionStatus != 'cancelled';
    final statusCol = agendaStatusColor(context, a.status);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.xxs),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.control),
            onTap: onOpenItem,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ?dragHandle,
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: statusCol.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.chip)),
                child: Text('${a.order}', style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: statusCol)),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  GovPillRow([
                    if (it.ref.isNotEmpty) AppBadgePill(it.ref, color: c.textMedium),
                    AppBadgePill(itemTypeLabel(it.type), color: c.primary),
                    AgendaResultChip(agenda: a, onTap: onResults),
                    if (a.decisionNo != null) AppBadgePill(t('قرار رقم ${a.decisionNo}', 'Decision no. ${a.decisionNo}'), icon: Icons.tag_rounded, color: c.charcoal),
                    if (a.councilWritten) AppBadgePill(t('كتبه المجلس', 'Written by the council'), icon: Icons.edit_note_rounded, color: c.textMedium),
                  ]),
                  const SizedBox(height: AppSpace.xs),
                  Text(it.title, style: AppType.bodyStrong(context)),
                  if (it.sourceName.isNotEmpty || it.ownerDept != null)
                    Text(
                      [if (it.sourceName.isNotEmpty) t('من: ${it.sourceName}', 'From: ${it.sourceName}'), if (it.ownerDept != null) t('لدى: ${it.ownerDept!.name}', 'With: ${it.ownerDept!.name}')].join(' · '),
                      style: AppType.meta(context).copyWith(color: c.textMedium),
                    ),
                ]),
              ),
              if (onOpenItem != null) Icon(Icons.chevron_right_rounded, color: c.textLight),
            ]),
          ),
          if (showResult) ...[
            const SizedBox(height: AppSpace.sm),
            VoteResultView(
              approve: a.approve,
              reject: a.reject,
              abstain: a.abstain,
              eligible: a.eligible,
              approvePct: a.approvePct,
              outcome: a.decided ? a.status : null,
              compact: compactResult,
              live: sessionStatus == 'voting' && !a.decided,
            ),
          ],
          if (a.myCoi) ...[
            const SizedBox(height: AppSpace.sm),
            AppBanner(
              icon: Icons.front_hand_rounded,
              color: c.purple,
              text: t('أعلنت تعارض مصالح — أنت معتذر عن هذا البند، فلا تصوّت عليه ولا يُحسب النصاب بك.', 'You declared a conflict of interest — you are excused from this item: no vote, and the quorum is counted without you.'),
            ),
          ] else if (a.excluded && open) ...[
            const SizedBox(height: AppSpace.sm),
            AppBanner(
              icon: Icons.how_to_vote_outlined,
              color: c.purple,
              text: t('هذا البند من تقديمك — لا تصوّت عليه، ويُحسب النصاب من دونك.', 'You submitted this item — you do not vote on it, and the quorum is counted without you.'),
            ),
          ] else if (canVote || myVote != null) ...[
            const SizedBox(height: AppSpace.sm),
            MyVoteRow(value: myVote, enabled: canVote, busy: voteBusy, onVote: onVote),
          ],
          if (onConflict != null && open && !a.myCoi && !a.excluded) ...[
            const SizedBox(height: AppSpace.xxs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: c.purple),
                onPressed: onConflict,
                icon: const Icon(Icons.front_hand_outlined, size: AppIconSize.md),
                label: Text(t('لديّ تعارض مصالح', 'I have a conflict of interest'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.purple)),
              ),
            ),
          ],
          if (onResults != null && a.resultsVisible) ...[
            const SizedBox(height: AppSpace.xxs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: c.primary),
                onPressed: onResults,
                icon: const Icon(Icons.groups_2_outlined, size: AppIconSize.md),
                label: Text(t('من صوّت؟', 'Who voted?'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.primary)),
              ),
            ),
          ],
          if (showVoters && a.votes.isNotEmpty && a.voters == null) ...[
            const SizedBox(height: AppSpace.sm),
            VotersList(votes: a.votes),
          ],
          if ((showVoters || manager) && a.excludedUsers.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(
              t('لا يصوّت (مقدّم البند): ${a.excludedUsers.map((u) => u.name).join('، ')}', 'Does not vote (submitted the item): ${a.excludedUsers.map((u) => u.name).join(', ')}'),
              style: AppType.meta(context).copyWith(color: c.textMedium),
            ),
          ],
          if (decidedElsewhere) ...[
            const SizedBox(height: AppSpace.sm),
            AppBanner(
              icon: Icons.info_outline_rounded,
              color: c.warning,
              text: t('صدر قرار في هذه المعاملة خارج المجلس (${it.decision == null ? '' : itemStatusLabel(it.decision!.outcome)}) — نتيجة التصويت لا تغيّره.',
                  'This item was decided outside the council (${it.decision == null ? '' : itemStatusLabel(it.decision!.outcome)}) — the vote result does not change it.'),
            ),
          ],
          if (a.escalatedItemId != null) ...[
            const SizedBox(height: AppSpace.xs),
            GovPillRow([AppBadgePill(t('صُعِّد إلى مجلس الكلية', 'Escalated to the faculty council'), icon: DirIcons.northEast, color: c.purple)]),
          ],
          if ((a.note ?? '').trim().isNotEmpty && !(a.note ?? '').contains('decided_elsewhere')) ...[
            const SizedBox(height: AppSpace.xs),
            Text(a.note!, style: AppType.meta(context).copyWith(color: c.textMedium)),
          ],
          if (a.decidedAt != null) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(t('حُسم ${govWhen(a.decidedAt)}', 'Decided ${govWhen(a.decidedAt)}'), style: AppType.meta(context).copyWith(color: c.textLight)),
          ],
          if (manager && (onRemove != null || onPostpone != null || onEscalate != null) && open) ...[
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: AppSpace.xxs, children: [
              if (onRemove != null && sessionStatus == 'draft')
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: c.danger),
                  onPressed: onRemove,
                  icon: const Icon(Icons.remove_circle_outline_rounded, size: AppIconSize.md),
                  label: Text(t('إزالة', 'Remove'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.danger)),
                ),
              if (onPostpone != null)
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: c.purple),
                  onPressed: onPostpone,
                  icon: const Icon(Icons.update_rounded, size: AppIconSize.md),
                  label: Text(t('تأجيل', 'Postpone'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.purple)),
                ),
              if (onEscalate != null && canEscalate && a.escalatedItemId == null)
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: c.primary),
                  onPressed: onEscalate,
                  icon: const Icon(DirIcons.northEast, size: AppIconSize.md),
                  label: Text(t('تصعيد لمجلس الكلية', 'Escalate to the faculty council'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.primary)),
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Minutes
// ═════════════════════════════════════════════════════════════════════════════

String _nameOf(dynamic v) {
  if (v is Map) {
    final ar = '${v['name_ar'] ?? v['title_ar'] ?? ''}', en = '${v['name_en'] ?? v['title_en'] ?? ''}';
    if (ar.isNotEmpty || en.isNotEmpty) return t(ar.isNotEmpty ? ar : en, en.isNotEmpty ? en : ar);
    return '${v['name'] ?? v['title'] ?? v['text'] ?? v['note'] ?? ''}';
  }
  return v == null ? '' : '$v';
}

/// The minutes as a readable document (council · session · date · present · every item with counts, outcome and
/// decision) from the server's `minutes` JSON, with a button that copies the server's plain text.
class GovMinutesView extends StatelessWidget {
  const GovMinutesView({super.key, required this.minutes, this.textAr, this.textEn, this.title});
  final Map<String, dynamic> minutes;
  final String? textAr, textEn, title;

  String get copyText => t(textAr ?? textEn ?? '', textEn ?? textAr ?? '');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = minutes;
    final council = _nameOf(m['council']);
    final session = _nameOf(m['session']);
    final when = orgParseUtc(m['date'] ?? m['scheduled_at'] ?? asMap(m['session'])['scheduled_at']);
    final generated = orgParseUtc(m['generated_at']);
    final present = [for (final p in (m['present'] as List? ?? const [])) _nameOf(p)].where((x) => x.isNotEmpty).toList();
    final items = asMapList(m['items']);
    final summary = m['summary'];
    final summaryText = summary is Map
        ? [for (final e in summary.entries) '${voteOutcomeLabel('${e.key}')}: ${e.value}'].join(' · ')
        : _nameOf(summary);
    Widget line(String label, String value) => value.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs / 2),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '$label: ', style: AppType.label(context).copyWith(color: c.textMedium)),
              TextSpan(text: value, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.textDark)),
            ])),
          );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.description_rounded, color: c.primary),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: Text(title ?? t('محضر الجلسة', 'Session minutes'), style: AppType.section(context))),
        if (copyText.isNotEmpty)
          IconButton(
            tooltip: t('نسخ النص', 'Copy the text'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: copyText));
              appToast(t('نُسخ المحضر', 'Minutes copied'));
            },
            icon: Icon(Icons.copy_rounded, color: c.primary),
          ),
      ]),
      const SizedBox(height: AppSpace.xs),
      AppCard(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          line(t('المجلس', 'Council'), council),
          line(t('الجلسة', 'Session'), session),
          line(t('التاريخ', 'Date'), govWhen(when)),
          line(t('الحضور (صوّتوا)', 'Present (voted)'), present.isEmpty ? '' : t('${present.length}: ${present.join('، ')}', '${present.length}: ${present.join(', ')}')),
          line(t('الملخص', 'Summary'), summaryText),
          line(t('أُنشئ', 'Generated'), govWhen(generated)),
        ]),
      ),
      if (items.isEmpty && summaryText.isEmpty && copyText.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        AppCard(child: SelectableText(copyText, style: AppType.label(context).copyWith(color: context.colors.textDark))),
      ],
      for (var i = 0; i < items.length; i++) ...[
        const SizedBox(height: AppSpace.xs),
        Builder(builder: (context) {
          final x = items[i];
          final it = x['item'] is Map ? asMap(x['item']) : x;
          final votes = x['votes'] is Map ? asMap(x['votes']) : x;
          final outcome = '${x['outcome'] ?? x['status'] ?? votes['outcome'] ?? ''}';
          final decision = x['decision'] is Map ? asMap(x['decision']) : null;
          final decisionText = decision == null ? _nameOf(x['decision'] ?? x['decision_text']) : '${decision['text'] ?? decision['note'] ?? (decision['outcome'] == null ? '' : itemStatusLabel('${decision['outcome']}'))}';
          return AppCard(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GovPillRow([
                AppBadgePill('${x['order'] ?? i + 1}', color: c.textMedium),
                if ('${it['ref'] ?? ''}'.isNotEmpty) AppBadgePill('${it['ref']}', color: c.textMedium),
                if (outcome.isNotEmpty) AppBadgePill(voteOutcomeLabel(outcome), color: agendaStatusColor(context, outcome), icon: Icons.gavel_rounded),
              ]),
              const SizedBox(height: AppSpace.xs),
              Text('${it['title'] ?? x['title'] ?? ''}', style: AppType.bodyStrong(context)),
              const SizedBox(height: AppSpace.xs),
              VoteResultView(
                approve: asInt(votes['approve'] ?? votes['approve_count']),
                reject: asInt(votes['reject'] ?? votes['reject_count']),
                abstain: asInt(votes['abstain'] ?? votes['abstain_count']),
                eligible: asInt(votes['eligible'] ?? votes['eligible_count']),
                approvePct: votes['approve_pct'] == null ? null : asDouble(votes['approve_pct']),
                outcome: outcome.isEmpty ? null : outcome,
                compact: true,
              ),
              if (decisionText.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xs),
                Text(t('القرار: $decisionText', 'Decision: $decisionText'), style: AppType.label(context).copyWith(color: c.textMedium)),
              ],
            ]),
          );
        }),
      ],
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Candidate items · session edit
// ═════════════════════════════════════════════════════════════════════════════

/// Items a council may put on an agenda: those sitting with the council entity and with its parent department
/// (`GET …/items?dept_id=&status=in_council,pending_approval,open`), minus [exclude].
Future<List<WorkItem>> fetchAgendaCandidates(GovApi api, Council council, {Set<int> exclude = const {}}) async {
  final seen = <int>{};
  final out = <WorkItem>[];
  for (final dept in [council.dept, ?council.parentDept]) {
    final r = await orgCall(() => api.items({'dept_id': dept.id, 'status': 'in_council,pending_approval,open', 'size': 100}), quiet: true);
    if (!r.ok) continue;
    for (final it in (r.data as GovPage<WorkItem>).items) {
      if (seen.add(it.id) && !exclude.contains(it.id)) out.add(it);
    }
  }
  return out;
}

/// Multi-select of candidate items with a search box; [onConfirm] gets the chosen ids.
class AgendaCandidatePicker extends StatefulWidget {
  const AgendaCandidatePicker({super.key, required this.items, required this.onConfirm, this.busy = false, this.initial = const {}, this.confirmLabel});
  final List<WorkItem> items;
  final void Function(List<int> ids) onConfirm;
  final bool busy;
  final Set<int> initial;
  final String? confirmLabel;

  @override
  State<AgendaCandidatePicker> createState() => _AgendaCandidatePickerState();
}

class _AgendaCandidatePickerState extends State<AgendaCandidatePicker> {
  late final Set<int> _picked = {...widget.initial};
  var _q = '';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = _q.trim().toLowerCase();
    final shown = [
      for (final it in widget.items)
        if (q.isEmpty || it.title.toLowerCase().contains(q) || it.ref.toLowerCase().contains(q)) it,
    ];
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.items.isEmpty)
        Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Text(t('لا معاملات بانتظار المجلس حالياً', 'No items are waiting for the council right now'), textAlign: TextAlign.center, style: AppType.row(context).copyWith(color: c.textMedium)),
        )
      else ...[
        if (widget.items.length > 6)
          TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: t('ابحث بالعنوان أو الرقم…', 'Search by title or reference…'), isDense: true),
          ),
        Flexible(
          child: ListView(shrinkWrap: true, children: [
            for (final it in shown)
              CheckboxListTile(
                value: _picked.contains(it.id),
                onChanged: (v) => setState(() => v == true ? _picked.add(it.id) : _picked.remove(it.id)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(it.title, style: AppType.bodyStrong(context)),
                subtitle: Text([it.ref, itemTypeLabel(it.type), itemStatusLabel(it.status), if (it.sourceName.isNotEmpty) it.sourceName].where((x) => x.isNotEmpty).join(' · '),
                    style: AppType.meta(context).copyWith(color: c.textMedium)),
              ),
          ]),
        ),
        const SizedBox(height: AppSpace.xs),
        AppPrimaryButton(
          label: widget.confirmLabel ?? t('إضافة ${_picked.length} إلى جدول الأعمال', 'Add ${_picked.length} to the agenda'),
          icon: Icons.playlist_add_rounded,
          busy: widget.busy,
          onPressed: _picked.isEmpty || widget.busy ? null : () => widget.onConfirm(_picked.toList()),
        ),
      ],
    ]);
  }
}

/// Title · date & time · notes of a session (PATCH …/sessions/{sid}).
class SessionEditBody extends StatefulWidget {
  const SessionEditBody({super.key, required this.onSave, this.title, this.scheduledAt, this.notes, this.busy = false, this.kind = 'regular'});
  final String? title, notes, kind;
  final DateTime? scheduledAt;
  final bool busy;
  final void Function({String? title, DateTime? scheduledAt, String? notes}) onSave;

  @override
  State<SessionEditBody> createState() => _SessionEditBodyState();
}

class _SessionEditBodyState extends State<SessionEditBody> {
  late final _title = TextEditingController(text: widget.title ?? '');
  late final _notes = TextEditingController(text: widget.notes ?? '');
  late DateTime? _at = widget.scheduledAt;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final base = _at ?? DateTime.now().add(const Duration(days: 1));
    final d = await showDatePicker(context: context, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime(2100), initialDate: base.isBefore(DateTime.now().subtract(const Duration(days: 1))) ? DateTime.now() : base);
    if (d == null || !mounted) return;
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (tm == null || !mounted) return;
    setState(() => _at = DateTime(d.year, d.month, d.day, tm.hour, tm.minute));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppField(controller: _title, label: t('عنوان الجلسة (اختياري)', 'Session title (optional)')),
      InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: _pick,
        child: InputDecorator(
          isEmpty: _at == null,
          decoration: InputDecoration(labelText: t('موعد الجلسة', 'Session date & time'), prefixIcon: Icon(Icons.event_rounded, color: c.textLight), suffixIcon: Icon(Icons.edit_calendar_rounded, color: c.textLight, size: AppIconSize.md)),
          child: Text(_at == null ? '' : govWhen(_at), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
        ),
      ),
      const SizedBox(height: AppSpace.sm),
      AppField(controller: _notes, label: t('ملاحظات', 'Notes'), maxLines: 3),
      AppPrimaryButton(
        label: t('حفظ', 'Save'),
        icon: Icons.save_rounded,
        busy: widget.busy,
        onPressed: widget.busy || _at == null ? null : () => widget.onSave(title: _title.text.trim().isEmpty ? null : _title.text.trim(), scheduledAt: _at, notes: _notes.text.trim()),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The page
// ═════════════════════════════════════════════════════════════════════════════

/// One session. [onOpenItem] opens the work item (the coordinator wires the item screen); [onExport] opens the
/// Export Hub for a closed session (the coordinator wires it; hidden when null). [member] sends votes through the
/// member route (`/public/governance/agenda/{aid}/vote`). [orgId] is only needed without an `OrgSession` above.
class GovSessionScreen extends StatefulWidget {
  const GovSessionScreen(this.sessionId, {super.key, this.onOpenItem, this.onExport, this.orgId, this.member = false});
  final int sessionId;
  final void Function(WorkItem item)? onOpenItem;
  final void Function(CouncilSession session)? onExport;
  final int? orgId;
  final bool member;

  @override
  State<GovSessionScreen> createState() => _GovSessionScreenState();
}

class _GovSessionScreenState extends State<GovSessionScreen> {
  CouncilSession? _s;
  bool _failed = false, _missing = false, _busy = false;
  final Map<int, String> _optimistic = {};
  final Set<int> _voteBusy = {};
  Timer? _tick;
  DateTime _now = DateTime.now();
  List<AgendaItem>? _reordered;

  int? get _orgId => govOrgId(context, widget.orgId);
  GovApi? get _api => _orgId == null ? null : GovApi(_orgId!);

  /// The dashboard header's Refresh reloads the session (staff in this organization); "Updated" is when it answered.
  final _refresh = OrgPageRefresh();

  @override
  void initState() {
    super.initState();
    _refresh.attach(_load);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _refresh.dispose();
    super.dispose();
  }

  void _syncTimer() {
    final s = _s;
    final want = s != null && s.isVoting && s.votingClosesAt != null;
    if (want && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _now = DateTime.now());
        final closes = _s?.votingClosesAt;
        if (closes != null && _now.isAfter(closes.add(const Duration(seconds: 30)))) {
          // the deadline passed: reload ONCE (the server's tick may have closed it) and stop counting
          _tick?.cancel();
          _tick = null;
          _load();
        }
      });
    } else if (!want && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  Future<void> _load() async {
    final api = _api;
    if (api == null) {
      setState(() => _failed = true);
      return;
    }
    final r = await orgCall(() => api.session(widget.sessionId), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _s = r.data as CouncilSession;
        _failed = false;
        _optimistic.clear();
        _reordered = null;
      } else {
        _failed = _s == null;
        _missing = r.endpointMissing;
      }
    });
    if (!r.ok && _s != null) appToast(r.error!.message, error: true);
    if (r.ok) _refresh.markUpdated();
    _syncTimer();
  }

  Future<void> _act(Future<dynamic> Function() fn, {String? ok}) async {
    setState(() => _busy = true);
    final r = await orgCall(fn, ok: ok);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok || r.code == 'stale_version' || r.code == 'session_state') await _load();
  }

  Future<void> _vote(AgendaItem a, String vote, String? note) async {
    final api = _api;
    if (api == null) return;
    final before = _optimistic[a.id] ?? a.myVote ?? _s?.myVotes[a.id];
    setState(() {
      _optimistic[a.id] = vote;
      _voteBusy.add(a.id);
    });
    final r = await orgCall(() => widget.member ? GovApi.memberVote(a.id, vote, note: note) : api.vote(a.id, vote, note: note), ok: t('سُجّل صوتك', 'Your vote is recorded'));
    if (!mounted) return;
    setState(() {
      _voteBusy.remove(a.id);
      if (!r.ok) {
        if (before == null) {
          _optimistic.remove(a.id);
        } else {
          _optimistic[a.id] = before;
        }
      }
    });
    if (r.ok) _load();
  }

  Future<void> _results(AgendaItem a) async {
    final api = _api;
    await showAgendaResultsSheet(context, a, fetch: api == null || widget.member ? null : () async {
      final r = await orgCall(() => api.agendaResults(a.id), quiet: true);
      return r.ok ? r.data as AgendaItem : null;
    });
  }

  Future<void> _conflict(AgendaItem a) async {
    final api = _api;
    if (api == null) return;
    final yes = await appConfirm(context,
        message: t('هل لديك تعارض مصالح في «${a.item.title}»؟ تُعفى من التصويت عليه ولا يُحسب النصاب بك، ويُسحب صوتك إن كنت صوّتّ. لا يمكن التراجع.',
            'Do you have a conflict of interest in "${a.item.title}"? You are excused from its vote and its quorum, and a vote you cast is withdrawn. This cannot be undone.'),
        confirmLabel: t('نعم، أعلن التعارض', 'Yes, declare it'));
    if (!yes || !mounted) return;
    await _act(() => widget.member ? GovApi.memberDeclareConflict(a.id) : api.declareConflict(a.id), ok: t('سُجّل تعارض المصالح — أنت معتذر عن هذا البند', 'Conflict declared — you are excused from this item'));
  }

  Future<void> _writeItem() async {
    final api = _api, s = _s;
    if (api == null || s == null) return;
    var busy = false;
    // S3 (D-973): the nine decision templates; an older server (or a failure) just offers none
    final tr = await orgCall(() => api.decisionTemplates(), quiet: true);
    if (!mounted) return;
    final templates = tr.ok ? decisionTemplatesOf(tr.data as List<Map<String, dynamic>>) : const <DecisionTemplate>[];
    await showAppSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.md),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SheetHeader(t('كتابة بند', 'Write an item')),
                WriteAgendaItemBody(
                  busy: busy,
                  templates: templates,
                  onSave: (draft) async {
                    set(() => busy = true);
                    final q = draft.toRequest();
                    final r = await orgCall(() => api.writeAgendaItem(s.id, title: q.title, body: q.body, templateKey: q.templateKey, lang: q.lang), ok: t('أُضيف البند إلى جدول الأعمال', 'The item joined the agenda'));
                    if (!ctx.mounted) return;
                    set(() => busy = false);
                    if (r.ok) Navigator.pop(ctx);
                  },
                ),
              ]),
            ),
          );
        }));
    _load();
  }

  Future<void> _remind() async {
    final api = _api, s = _s;
    if (api == null || s == null) return;
    final wait = remindWait(s.manualRemindedAt);
    if (wait != null) {
      showAppNotice(remindWaitText(wait), error: true);
      return;
    }
    setState(() => _busy = true);
    final r = await orgCall(() => api.remindNonVoters(s.id), quiet: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      showAppNotice(remindDoneText(asInt(r.map['reminded'])));
      _load();
    } else if (r.code == 'remind_too_soon') {
      final secs = asInt(r.detail['retry_after']);
      showAppNotice(secs > 0 ? remindWaitText(Duration(seconds: secs)) : orgErrorText(r.error!), error: true);
    } else {
      showAppNotice(orgErrorText(r.error!), error: true);
      if (r.code == 'session_state') _load();
    }
  }

  Future<void> _reviewDeadline() async {
    final api = _api, s = _s;
    if (api == null || s == null) return;
    final now = DateTime.now();
    final base = s.reviewDeadline ?? now.add(const Duration(days: 3));
    final d = await showDatePicker(context: context, firstDate: now, lastDate: DateTime(2100), initialDate: base.isBefore(now) ? now : base,
        helpText: t('موعد انتهاء المراجعة', 'Review deadline'));
    if (d == null || !mounted) return;
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (tm == null || !mounted) return;
    final at = DateTime(d.year, d.month, d.day, tm.hour, tm.minute);
    if (!at.isAfter(DateTime.now())) {
      showAppNotice(t('اختر موعداً في المستقبل', 'Choose a time in the future'), error: true);
      return;
    }
    await _act(() => api.patchSession(s.id, {'review_deadline': orgUtc(at), 'version': s.version}), ok: t('حُدّد موعد انتهاء المراجعة', 'Review deadline set'));
  }

  Future<void> _addItems() async {
    final api = _api, s = _s;
    if (api == null || s == null || s.council == null) return;
    final items = await fetchAgendaCandidates(api, s.council!, exclude: {for (final a in s.agenda) a.item.id});
    if (!mounted) return;
    var busy = false;
    await showAppSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.md),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SheetHeader(t('إضافة بنود', 'Add items')),
              Flexible(
                child: AgendaCandidatePicker(
                  items: items,
                  busy: busy,
                  onConfirm: (ids) async {
                    set(() => busy = true);
                    final r = await orgCall(() => api.addToAgenda(s.id, ids), ok: t('أُضيفت البنود', 'Items added'));
                    if (!ctx.mounted) return;
                    set(() => busy = false);
                    if (r.ok) Navigator.pop(ctx);
                  },
                ),
              ),
            ]),
          );
        }));
    _load();
  }

  Future<void> _edit() async {
    final api = _api, s = _s;
    if (api == null || s == null) return;
    var busy = false;
    await showAppSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.md),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SheetHeader(t('تعديل الجلسة', 'Edit the session')),
                SessionEditBody(
                  title: s.title,
                  scheduledAt: s.scheduledAt,
                  notes: s.notes,
                  kind: s.kind,
                  busy: busy,
                  onSave: ({title, scheduledAt, notes}) async {
                    set(() => busy = true);
                    final r = await orgCall(
                        () => api.patchSession(s.id, {'title': title, 'scheduled_at': orgUtc(scheduledAt), 'notes': notes, 'version': s.version}),
                        ok: t('تم الحفظ', 'Saved'));
                    if (!ctx.mounted) return;
                    set(() => busy = false);
                    if (r.ok) Navigator.pop(ctx);
                  },
                ),
              ]),
            ),
          );
        }));
    _load();
  }

  Future<void> _showMinutes() async {
    final api = _api, s = _s;
    if (api == null || s == null) return;
    final r = await orgCall(() => api.minutes(s.id));
    if (!mounted || !r.ok) return;
    final m = r.map;
    final minutes = m['minutes'] is Map ? asMap(m['minutes']) : (s.minutes ?? const <String, dynamic>{});
    await showAppSheet<void>(context, (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.md),
          child: SingleChildScrollView(
            child: GovMinutesView(
              minutes: minutes,
              textAr: m['text_ar'] as String?,
              textEn: m['text_en'] as String?,
              title: s.isClosed ? null : t('مسودة المحضر', 'Draft minutes'),
            ),
          ),
        ));
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final api = _api, s = _s;
    if (api == null || s == null) return;
    final list = [...(_reordered ?? s.agenda)];
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    setState(() => _reordered = list);
    final r = await orgCall(() => api.reorderAgenda(s.id, [for (final a in list) a.id]));
    if (!mounted) return;
    if (!r.ok) setState(() => _reordered = null);
    _load();
  }

  Widget _actions(CouncilSession s) {
    final c = context.colors;
    final api = _api!;
    final manager = s.can['manage'];
    final pills = <Widget>[];
    if (manager) {
      switch (s.status) {
        case 'draft':
          pills.addAll([
            AppPill(icon: Icons.playlist_add_rounded, label: t('إضافة بنود', 'Add items'), onTap: _busy ? null : _addItems),
            AppPill(icon: Icons.edit_calendar_rounded, label: t('تعديل', 'Edit'), onTap: _busy ? null : _edit),
            AppPill(
              icon: Icons.campaign_rounded,
              label: t('نشر جدول الأعمال', 'Publish'),
              color: c.success,
              onTap: _busy || s.agenda.isEmpty
                  ? null
                  : () async {
                      if (await appConfirm(context, message: t('نشر جدول الأعمال؟ يصل إلى كل أعضاء المجلس.', 'Publish the agenda? Every council member is notified.'))) {
                        _act(() => api.publishSession(s.id), ok: t('نُشر جدول الأعمال', 'Agenda published'));
                      }
                    },
            ),
          ]);
        case 'published':
          pills.addAll([
            AppPill(icon: Icons.playlist_add_rounded, label: t('إضافة بنود', 'Add items'), onTap: _busy ? null : _addItems),
            AppPill(icon: Icons.edit_calendar_rounded, label: t('تعديل', 'Edit'), onTap: _busy ? null : _edit),
            AppPill(
              icon: Icons.how_to_vote_rounded,
              label: t('فتح التصويت', 'Open voting'),
              color: c.success,
              onTap: _busy
                  ? null
                  : () async {
                      if (await appConfirm(context, message: t('فتح التصويت الآن؟ يُغلق تلقائياً بعد المهلة أو عند إغلاقك له.', 'Open voting now? It closes by itself after the deadline, or when you close it.'))) {
                        _act(() => api.openVoting(s.id), ok: t('فُتح التصويت', 'Voting opened'));
                      }
                    },
            ),
          ]);
        case 'voting':
          pills.add(AppPill(
            icon: Icons.lock_clock_rounded,
            label: t('إغلاق التصويت واحتساب النتائج', 'Close voting & tally'),
            color: c.warning,
            onTap: _busy
                ? null
                : () async {
                    if (await appConfirm(context, message: t('إغلاق التصويت الآن؟ تُحتسب النتائج ويُنشأ المحضر ولا يمكن التصويت بعدها.', 'Close voting now? Results are tallied, the minutes generated, and no more votes are taken.'), danger: true, confirmLabel: t('إغلاق', 'Close'))) {
                      _act(() => api.closeSession(s.id, s.version), ok: t('أُغلقت الجلسة', 'Session closed'));
                    }
                  },
          ));
        case 'closed':
          pills.add(AppPill(icon: Icons.description_rounded, label: t('المحضر', 'Minutes'), onTap: _showMinutes));
          if (widget.onExport != null) pills.add(AppPill(icon: Icons.ios_share_rounded, label: t('تصدير', 'Export'), onTap: () => widget.onExport!(s)));
      }
      if (s.status == 'draft' || s.status == 'published' || s.status == 'voting') {
        pills.add(AppPill(
          icon: Icons.cancel_outlined,
          label: t('إلغاء الجلسة', 'Cancel session'),
          color: c.danger,
          onTap: _busy
              ? null
              : () async {
                  final note = await askText(context, title: t('سبب الإلغاء', 'Reason for cancelling'), multiline: true);
                  if (note == null || !mounted) return;
                  _act(() => api.cancelSession(s.id, note: note), ok: t('أُلغيت الجلسة', 'Session cancelled'));
                },
        ));
        if (s.status != 'draft') pills.add(AppPill(icon: Icons.description_outlined, label: t('مسودة المحضر', 'Draft minutes'), onTap: _showMinutes));
      }
    } else if (s.isClosed) {
      pills.add(AppPill(icon: Icons.description_rounded, label: t('المحضر', 'Minutes'), onTap: _showMinutes));
      if (widget.onExport != null && s.can['export_votes']) pills.add(AppPill(icon: Icons.ios_share_rounded, label: t('تصدير', 'Export'), onTap: () => widget.onExport!(s)));
    }
    // Institutions S2: what the server's flags allow (chair, secretary, admin…), never a guess from role names
    if (s.can['write_item']) pills.add(AppPill(icon: Icons.edit_note_rounded, label: t('كتابة بند', 'Write an item'), onTap: _busy ? null : _writeItem));
    if (manager && (s.status == 'draft' || s.status == 'published' || s.status == 'voting')) {
      pills.add(AppPill(
          icon: Icons.event_note_rounded,
          label: s.reviewDeadline == null ? t('موعد انتهاء المراجعة', 'Review deadline') : t('تعديل موعد المراجعة', 'Change the review deadline'),
          onTap: _busy ? null : _reviewDeadline));
    }
    if (s.can['remind']) pills.add(AppPill(icon: Icons.notifications_active_rounded, label: t('تذكير من لم يصوّت', 'Remind non-voters'), color: c.warning, onTap: _busy ? null : _remind));
    if (pills.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
      child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: pills),
    );
  }

  Widget _row(CouncilSession s, AgendaItem a, {Widget? handle}) {
    final api = _api!;
    final manager = s.can['manage'];
    final myVote = _optimistic[a.id] ?? a.myVote ?? s.myVotes[a.id];
    final canVote = s.isVoting && s.can['vote'] && !a.decided && a.status != 'withdrawn' && !a.excluded && !a.myCoi;
    final showResult = manager || s.resultsVisible || s.isClosed;
    return AgendaRow(
      key: ValueKey('agenda.${a.id}'),
      agenda: a,
      sessionStatus: s.status,
      myVote: myVote,
      canVote: canVote,
      voteBusy: _voteBusy.contains(a.id),
      showResult: showResult && (s.isVoting || s.isClosed || a.decided),
      showVoters: a.votes.isNotEmpty && (manager || s.isClosed),
      manager: manager,
      canEscalate: s.council?.level != 'faculty',
      dragHandle: handle,
      onVote: canVote ? (v, note) => _vote(a, v, note) : null,
      onOpenItem: widget.onOpenItem == null ? null : () => widget.onOpenItem!(a.item),
      onResults: a.resultsVisible ? () => _results(a) : null,
      onConflict: s.can['declare_conflict'] && !a.decided && !a.myCoi && !a.excluded ? () => _conflict(a) : null,
      onRemove: manager && s.status == 'draft'
          ? () async {
              if (await appConfirm(context, message: t('إزالة البند من جدول الأعمال؟', 'Remove this item from the agenda?'), danger: true)) {
                _act(() => api.removeFromAgenda(s.id, a.id), ok: t('أُزيل البند', 'Item removed'));
              }
            }
          : null,
      onPostpone: manager && !s.isClosed
          ? () async {
              if (await appConfirm(context, message: t('تأجيل البند إلى الجلسة الدورية التالية؟', 'Postpone this item to the next regular session?'))) {
                _act(() => api.postponeAgenda(s.id, a.id), ok: t('أُجّل البند', 'Item postponed'));
              }
            }
          : null,
      onEscalate: manager && !s.isClosed
          ? () async {
              if (await appConfirm(context, message: t('تصعيد البند إلى مجلس الكلية؟ يُدرج في جلسته المفتوحة أو القادمة.', "Escalate this item to the faculty council? It joins the council's open or next session."))) {
                _act(() => api.escalateAgenda(a.id), ok: t('صُعّد البند', 'Item escalated'));
              }
            }
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = _s;
    final Widget body;
    if (_missing) {
      body = const GovNeedsServer();
    } else if (s == null) {
      body = _failed
          ? AppEmpty(icon: Icons.error_outline_rounded, title: t('تعذّر تحميل الجلسة', 'Could not load the session'), actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
          : const AppListSkeleton(items: 5, withAvatar: false);
    } else {
      final agenda = _reordered ?? s.agenda;
      final reorderable = s.can['manage'] && s.status == 'draft' && agenda.length > 1;
      body = AppRefresh(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.only(bottom: AppSpace.xl), children: [
          SessionHeader(session: s, now: _now),
          _actions(s),
          if (s.status == 'cancelled')
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
              child: AppBanner(icon: Icons.cancel_rounded, color: c.danger, text: t('أُلغيت هذه الجلسة', 'This session was cancelled')),
            ),
          if (s.isVoting && s.can['vote'] && s.pendingMyVotes > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
              child: AppBanner(icon: Icons.how_to_vote_rounded, color: c.warning, text: t('${s.pendingMyVotes} بنود بانتظار صوتك', '${s.pendingMyVotes} items are waiting for your vote')),
            ),
          AppSectionTitle(t('جدول الأعمال', 'Agenda'), subtitle: reorderable ? t('اسحب المقبض لإعادة الترتيب', 'Drag the handle to reorder') : null),
          if (agenda.isEmpty)
            AppEmpty(
              icon: Icons.list_alt_rounded,
              title: t('لا بنود بعد', 'No items yet'),
              message: s.can['manage'] && s.status == 'draft' ? t('أضف المعاملات التي تنتظر تصويت المجلس', 'Add the items waiting for the council') : null,
              actionLabel: s.can['manage'] && s.status == 'draft' ? t('إضافة بنود', 'Add items') : null,
              onAction: s.can['manage'] && s.status == 'draft' ? _addItems : null,
            )
          else if (reorderable)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: agenda.length,
              onReorderItem: _reorder,
              itemBuilder: (_, i) => _row(
                s,
                agenda[i],
                handle: ReorderableDragStartListener(
                  key: ValueKey('handle.${agenda[i].id}'),
                  index: i,
                  child: Padding(padding: const EdgeInsetsDirectional.only(end: AppSpace.xs, top: AppSpace.xxs), child: Icon(Icons.drag_indicator_rounded, color: c.textLight)),
                ),
              ),
            )
          else
            for (final a in agenda) _row(s, a),
        ]),
      );
    }
    final title = s == null ? t('الجلسة', 'Session') : (s.council?.name ?? sessionKindLabel(s.kind));
    // staff of this organization: the dashboard's header (Back · council · kind and status · Refresh · switcher);
    // a member, a deep link before the organization loaded: the screen's own app bar
    if (orgUsesDashboardHeader(context, _orgId)) {
      return OrgPushedPage(helpPageId: 'org.governance', 
        title: title,
        subtitle: s == null ? null : [if (s.council != null) sessionKindLabel(s.kind), sessionStatusLabel(s.status)].join(' · '),
        refresh: _refresh,
        maxWidth: AppWidth.reading.max,
        child: body,
      );
    }
    return BasePage(
      useWebCard: true,
      maxWith: 1000,
      appBar: ScreenAppBar(title: title, actions: [
        const ContextExitButton(),
        if (s != null) IconButton(tooltip: t('تحديث', 'Refresh'), onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ]),
      child: body,
    );
  }
}
