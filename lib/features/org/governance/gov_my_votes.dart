// lib/features/org/governance/gov_my_votes.dart — the agenda items waiting for MY vote across every council of the
// organization (`GET …/governance/me/votes`, or the member route `GET /public/governance/me/votes`), grouped by
// session with its deadline, voted inline (optimistic) and opened into the session (spec §5, §6; attention key
// `council_votes`).
//
//   MyVoteEntry · MyVoteGroup · groupMyVotes   pure (test/org/gov_council_models_test.dart)
//   MyVoteGroupCard                             presentational (test/ui/gov_council_layout_test.dart)
//   GovMyVotesPage                              the page
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/context_switcher.dart' show ContextExitButton;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import '../org_page_header.dart' show OrgPageRefresh, OrgPushedPage, orgUsesDashboardHeader;
import '../org_ui.dart' show orgText;
import '../org_v3.dart' show orgCall, orgParseUtc;
import 'gov_api.dart';
import 'gov_council_ui.dart';
import 'gov_models.dart';
import 'gov_session_screen.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Pure
// ═════════════════════════════════════════════════════════════════════════════

/// One row of `/me/votes`: the agenda item plus whatever the server says about its session (`session: {...}`
/// or flat `session_id` / `voting_closes_at` / `council` keys — both shapes are read).
class MyVoteEntry {
  const MyVoteEntry({
    required this.agenda,
    this.sessionId,
    this.sessionTitle,
    this.sessionKind = 'regular',
    this.sessionStatus = 'voting',
    this.scheduledAt,
    this.closesAt,
    this.council,
    this.orgId,
  });

  final AgendaItem agenda;
  final int? sessionId, orgId;
  final String? sessionTitle;
  final String sessionKind, sessionStatus;
  final DateTime? scheduledAt, closesAt;
  final GovDept? council;

  factory MyVoteEntry.fromJson(Map<String, dynamic> j) {
    final s = asMap(j['session']);
    final rawCouncil = s['council'] ?? j['council'];
    final councilMap = rawCouncil is Map ? Map<String, dynamic>.from(rawCouncil) : const <String, dynamic>{};
    final council = councilMap['dept'] is Map ? GovDept.from(councilMap['dept']) : GovDept.from(councilMap);
    return MyVoteEntry(
      agenda: AgendaItem.fromJson(j),
      sessionId: (s['id'] ?? j['session_id']) == null ? null : asInt(s['id'] ?? j['session_id']),
      sessionTitle: (s['title'] ?? j['session_title']) as String?,
      sessionKind: '${s['kind'] ?? j['session_kind'] ?? 'regular'}',
      sessionStatus: '${s['status'] ?? j['session_status'] ?? 'voting'}',
      scheduledAt: orgParseUtc(s['scheduled_at'] ?? j['scheduled_at']),
      closesAt: orgParseUtc(s['voting_closes_at'] ?? j['voting_closes_at']),
      council: council,
      orgId: (s['org_id'] ?? j['org_id']) == null ? null : asInt(s['org_id'] ?? j['org_id']),
    );
  }

  String get sessionLabel => (sessionTitle ?? '').trim().isNotEmpty ? sessionTitle!.trim() : sessionKindLabel(sessionKind);
}

/// The entries of one session (null session id = "other").
class MyVoteGroup {
  const MyVoteGroup({required this.sessionId, required this.entries});
  final int? sessionId;
  final List<MyVoteEntry> entries;

  MyVoteEntry get head => entries.first;
  DateTime? get closesAt => head.closesAt;
  int get pending => entries.where((e) => e.agenda.myVote == null).length;
}

/// Groups by session, the soonest deadline first (no deadline last), items in agenda order.
List<MyVoteGroup> groupMyVotes(List<MyVoteEntry> entries) {
  final by = <int?, List<MyVoteEntry>>{};
  for (final e in entries) {
    (by[e.sessionId] ??= []).add(e);
  }
  final groups = [
    for (final e in by.entries) MyVoteGroup(sessionId: e.key, entries: [...e.value]..sort((a, b) => a.agenda.order.compareTo(b.agenda.order))),
  ];
  groups.sort((a, b) {
    final x = a.closesAt, y = b.closesAt;
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return x.compareTo(y);
  });
  return groups;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Card
// ═════════════════════════════════════════════════════════════════════════════

/// One session's items waiting for my vote: header (council · session · deadline countdown · pending count), then
/// each item with its inline vote row. [votes] overrides the entries' `myVote` (optimistic state).
class MyVoteGroupCard extends StatelessWidget {
  const MyVoteGroupCard({
    super.key,
    required this.group,
    this.now,
    this.votes = const {},
    this.busy = const {},
    this.onVote,
    this.onOpenSession,
    this.onOpenItem,
  });

  final MyVoteGroup group;
  final DateTime? now;
  final Map<int, String> votes;
  final Set<int> busy;
  final Future<void> Function(MyVoteEntry entry, String vote, String? note)? onVote;
  final VoidCallback? onOpenSession;
  final void Function(WorkItem item)? onOpenItem;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = group;
    final h = g.head;
    final closes = g.closesAt;
    final ended = closes != null && (now ?? DateTime.now()).isAfter(closes);
    final pending = g.entries.where((e) => (votes[e.agenda.id] ?? e.agenda.myVote) == null).length;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onOpenSession,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: c.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
              child: Icon(sessionKindIcon(h.sessionKind), color: c.warning),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(h.council?.name ?? t('المجلس', 'Council'), style: orgText(context, size: 14.5, w: FontWeight.w800)),
                Text(h.sessionLabel + (h.scheduledAt == null ? '' : ' · ${govDay(h.scheduledAt)}'), style: orgText(context, size: 12, color: c.textMedium)),
                const SizedBox(height: 6),
                GovPillRow([
                  if (closes != null)
                    AppBadgePill(
                      ended ? t('انتهى التصويت', 'Voting ended') : t('يُغلق بعد ${countdownText(closes, now: now)}', 'closes in ${countdownText(closes, now: now)}'),
                      icon: Icons.timer_rounded,
                      color: ended ? c.textMedium : c.warning,
                    ),
                  AppBadgePill(
                    pending == 0 ? t('صوّتّ على كل البنود', 'You voted on every item') : t('$pending بانتظار صوتك', '$pending waiting for your vote'),
                    color: pending == 0 ? c.success : c.danger,
                    icon: Icons.how_to_vote_rounded,
                  ),
                ]),
              ]),
            ),
            if (onOpenSession != null) Icon(Icons.chevron_right_rounded, color: c.textLight),
          ]),
        ),
        for (final e in g.entries) ...[
          const SizedBox(height: 10),
          Divider(color: c.divider, height: 1),
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onOpenItem == null ? null : () => onOpenItem!(e.agenda.item),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GovPillRow([
                AppBadgePill('${e.agenda.order}', color: c.textMedium),
                if (e.agenda.item.ref.isNotEmpty) AppBadgePill(e.agenda.item.ref, color: c.textMedium),
                AppBadgePill(itemTypeLabel(e.agenda.item.type), color: c.primary),
              ]),
              const SizedBox(height: 4),
              Text(e.agenda.item.title, style: orgText(context, size: 13.5, w: FontWeight.w800)),
              if (e.agenda.item.sourceName.isNotEmpty) Text(t('من: ${e.agenda.item.sourceName}', 'From: ${e.agenda.item.sourceName}'), style: orgText(context, size: 12, color: c.textMedium)),
            ]),
          ),
          const SizedBox(height: 8),
          MyVoteRow(
            value: votes[e.agenda.id] ?? e.agenda.myVote,
            enabled: !ended && onVote != null,
            busy: busy.contains(e.agenda.id),
            onVote: onVote == null ? null : (v, note) => onVote!(e, v, note),
          ),
        ],
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

/// [member] uses the member routes (no organization in the path — the personal dashboard); otherwise the staff
/// route of the open organization ([orgId] only when no `OrgSession` sits above the page).
class GovMyVotesPage extends StatefulWidget {
  const GovMyVotesPage({super.key, this.member = false, this.orgId, this.onOpenItem, this.embedded = false});
  final bool member, embedded;
  final int? orgId;
  final void Function(WorkItem item)? onOpenItem;

  @override
  State<GovMyVotesPage> createState() => _GovMyVotesPageState();
}

class _GovMyVotesPageState extends State<GovMyVotesPage> {
  List<MyVoteEntry>? _rows;
  bool _failed = false, _missing = false;
  final Map<int, String> _votes = {};
  final Set<int> _busy = {};

  int? get _orgId => widget.member ? widget.orgId : govOrgId(context, widget.orgId);

  /// The pushed page's Refresh (dashboard header) reloads the list; "Updated" is when it answered.
  final _refresh = OrgPageRefresh();

  @override
  void initState() {
    super.initState();
    _refresh.attach(_load);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final String path;
    if (widget.member) {
      path = '${GovApi.memberBase}/me/votes';
    } else {
      final oid = _orgId;
      if (oid == null) {
        setState(() => _failed = true);
        return;
      }
      path = '${GovApi(oid).base}/me/votes';
    }
    final r = await orgCall(() => ApiClient().get(path), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _rows = [for (final x in asMapList(r.map['items'])) MyVoteEntry.fromJson(x)];
        _votes.clear();
        _failed = false;
      } else {
        _failed = _rows == null;
        _missing = r.endpointMissing;
      }
    });
    if (r.ok) _refresh.markUpdated();
  }

  Future<void> _vote(MyVoteEntry e, String vote, String? note) async {
    final aid = e.agenda.id;
    final before = _votes[aid] ?? e.agenda.myVote;
    setState(() {
      _votes[aid] = vote;
      _busy.add(aid);
    });
    final oid = e.orgId ?? _orgId;
    final r = await orgCall(
        () => widget.member || oid == null ? GovApi.memberVote(aid, vote, note: note) : GovApi(oid).vote(aid, vote, note: note),
        ok: t('سُجّل صوتك', 'Your vote is recorded'));
    if (!mounted) return;
    setState(() {
      _busy.remove(aid);
      if (!r.ok) {
        if (before == null) {
          _votes.remove(aid);
        } else {
          _votes[aid] = before;
        }
      }
    });
  }

  Future<void> _openSession(MyVoteGroup g) async {
    final sid = g.sessionId;
    if (sid == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GovSessionScreen(sid, orgId: g.head.orgId ?? _orgId, member: widget.member, onOpenItem: widget.onOpenItem)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final Widget body;
    if (_missing) {
      body = const GovNeedsServer();
    } else if (rows == null) {
      body = _failed
          ? AppEmpty(icon: Icons.error_outline_rounded, title: t('تعذّر التحميل', 'Could not load'), actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
          : const AppListSkeleton(items: 3, withAvatar: false);
    } else {
      final groups = groupMyVotes(rows);
      final pending = rows.where((e) => (_votes[e.agenda.id] ?? e.agenda.myVote) == null).length;
      body = AppRefresh(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          AppHero(
            title: t('تصويتاتي', 'My votes'),
            subtitle: t('بنود جداول الأعمال التي تنتظر صوتك في كل المجالس', 'Agenda items waiting for your vote across every council'),
            icon: Icons.how_to_vote_rounded,
            stats: [
              AppHeroStat(icon: Icons.pending_actions_rounded, value: '$pending', label: t('بانتظار صوتي', 'waiting')),
              AppHeroStat(icon: Icons.event_note_rounded, value: '${groups.length}', label: t('جلسات', 'sessions')),
            ],
          ),
          if (groups.isEmpty)
            AppEmpty(
              icon: Icons.how_to_vote_rounded,
              title: t('لا تصويتات بانتظارك', 'Nothing is waiting for your vote'),
              message: t('عندما يُفتح التصويت في جلسة أنت عضو فيها تظهر بنودها هنا', 'When voting opens in a session of a council you sit on, its items appear here'),
            ),
          for (final g in groups)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: MyVoteGroupCard(
                group: g,
                votes: _votes,
                busy: _busy,
                onVote: _vote,
                onOpenSession: g.sessionId == null ? null : () => _openSession(g),
                onOpenItem: widget.onOpenItem,
              ),
            ),
        ]),
      );
    }
    if (widget.embedded) return body;
    // staff of this organization: the dashboard's header (Back · title · Refresh · switcher); a student / a member
    // page elsewhere keeps the screen's own app bar
    if (orgUsesDashboardHeader(context, _orgId)) {
      return OrgPushedPage(helpPageId: 'org.governance', title: t('تصويتاتي', 'My votes'), refresh: _refresh, child: body);
    }
    return BasePage(
      useWebCard: true,
      maxWith: 1000,
      appBar: ScreenAppBar(title: t('تصويتاتي', 'My votes'), actions: [
        if (!widget.member) const ContextExitButton(),
        if (rows != null) IconButton(tooltip: t('تحديث', 'Refresh'), onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ]),
      child: body,
    );
  }
}
