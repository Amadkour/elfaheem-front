// lib/features/org/org_attention_flow.dart
//
// Institutions v2, phase 5 (docs/institutions/V2_PLAN.md item 5, D-994 – D-997): the heads' and secretaries' ONE
// "Needs my attention" page.
//   GET /api/v1/org/public/governance/{org_id}/me/attention-flow
//     {new_requests: [item], votes_waiting: [{session_id, council, item_id, title, deadline}], overdue: [item],
//      assigned_to_me: [item], acting_units: [{id, name}], counts: {}, total}
//     item = {id, ref, title, status, unit, due_at?}
//
//   FlowItem · FlowVote · FlowUnit · AttentionFlow   pure, defensive parsers (tested)
//   AttentionFlowStore     one call per organization for the staff Home's entry row (in parallel with the dashboard)
//   AttentionFlowView      plain values (expectNoLayoutErrors): New requests · Votes waiting · Overdue · Assigned to me
//                          · Acting units ("Assign a head"), each row opening its item / session; the calm empty state
//   OrgAttentionFlowPage   the page (OrgPushedPage through orgPush); rows open through AppNavigator (org_work ·
//                          org_council · org_department), the same openers as a notification tap
//   attentionFlowSpecSummary  the Home row's line ("3 new · 2 votes · 1 overdue")
// Tests: test/org/institutions_v2_p5_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/in_flight.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart' show AppNavigator;

import '../admin/admin_common.dart' show asInt, asMap, asMapList, asStr, t;
import 'governance/gov_wiring.dart' show govEnabled;
import 'org_ui.dart' show orgNameOf;
import 'org_v3.dart' show orgCall, orgParseUtc;

// ═════════════════════════════════════════════════════════════════════════════
//  Pure parts
// ═════════════════════════════════════════════════════════════════════════════

/// A unit named by the server as a string, `{name_ar, name_en}` or `{name, name_en}`.
String flowUnitName(dynamic u) {
  if (u is Map) {
    final m = asMap(u);
    final n = orgNameOf(m);
    if (n.isNotEmpty) return n;
    final ar = asStr(m['name']), en = asStr(m['name_en']);
    return t(ar.isNotEmpty ? ar : en, en.isNotEmpty ? en : ar);
  }
  return u == null ? '' : '$u';
}

class FlowItem {
  const FlowItem({required this.id, this.ref = '', this.title = '', this.status = '', this.unit = '', this.dueAt, this.late = false});
  final int id;
  final String ref, title, status, unit;
  final DateTime? dueAt;

  /// The server's `overdue` flag.
  final bool late;

  static FlowItem? fromJson(dynamic raw) {
    final j = asMap(raw);
    final id = asInt(j['id']);
    if (id <= 0) return null;
    return FlowItem(
      id: id,
      ref: asStr(j['ref']),
      title: asStr(j['title']),
      status: asStr(j['status']),
      unit: flowUnitName(j['unit'] ?? j['dept']),
      dueAt: orgParseUtc(j['due_at']),
      late: j['overdue'] == true,
    );
  }
}

class FlowVote {
  const FlowVote({required this.sessionId, this.council = '', this.itemId, this.agendaItemId, this.title = '', this.deadline});
  final int sessionId;
  final int? itemId, agendaItemId;
  final String council, title;
  final DateTime? deadline;

  static FlowVote? fromJson(dynamic raw) {
    final j = asMap(raw);
    final sid = asInt(j['session_id']);
    if (sid <= 0) return null;
    return FlowVote(
      sessionId: sid,
      council: flowUnitName(j['council']),
      itemId: j['item_id'] == null ? null : asInt(j['item_id']),
      agendaItemId: j['agenda_item_id'] == null ? null : asInt(j['agenda_item_id']),
      title: asStr(j['title']),
      deadline: orgParseUtc(j['deadline']),
    );
  }
}

class FlowUnit {
  const FlowUnit(this.id, this.name);
  final int id;
  final String name;
}

class AttentionFlow {
  const AttentionFlow({
    this.newRequests = const [],
    this.votesWaiting = const [],
    this.overdue = const [],
    this.assignedToMe = const [],
    this.actingUnits = const [],
    this.counts = const {},
    int? total,
  }) : _total = total;

  final List<FlowItem> newRequests, overdue, assignedToMe;
  final List<FlowVote> votesWaiting;
  final List<FlowUnit> actingUnits;
  final Map<String, int> counts;
  final int? _total;

  /// A section's count: the server's (the lists may be cut), else the rows.
  int countOf(String key, int rows) => counts[key] ?? rows;

  int get newCount => countOf('new_requests', newRequests.length);
  int get votesCount => countOf('votes_waiting', votesWaiting.length);
  int get overdueCount => countOf('overdue', overdue.length);
  int get assignedCount => countOf('assigned_to_me', assignedToMe.length);
  int get actingCount => countOf('acting_units', actingUnits.length);

  /// The server's total; else the sections added up.
  int get total => _total ?? (newCount + votesCount + overdueCount + assignedCount + actingCount);
  bool get isEmpty => total == 0;

  factory AttentionFlow.fromJson(Map<String, dynamic> j) {
    List<FlowItem> items(String k) => [for (final x in (j[k] is List ? j[k] as List : const [])) ?FlowItem.fromJson(x)];
    final c = asMap(j['counts']);
    return AttentionFlow(
      newRequests: items('new_requests'),
      votesWaiting: [for (final x in (j['votes_waiting'] is List ? j['votes_waiting'] as List : const [])) ?FlowVote.fromJson(x)],
      overdue: items('overdue'),
      assignedToMe: items('assigned_to_me'),
      actingUnits: [
        for (final u in asMapList(j['acting_units']))
          if (asInt(u['id']) > 0) FlowUnit(asInt(u['id']), flowUnitName(u)),
      ],
      counts: {for (final e in c.entries) if (e.value is num) e.key: (e.value as num).toInt()},
      total: j['total'] is num ? (j['total'] as num).toInt() : null,
    );
  }
}

/// "3 new · 2 votes · 1 overdue" (only what counts).
String attentionFlowSummary(AttentionFlow f) => [
      if (f.newCount > 0) countText(f.newCount, ar1: 'طلب جديد', ar2: 'طلبان جديدان', arFew: '{n} طلبات جديدة', arMany: '{n} طلباً جديداً', en1: '1 new', en: '{n} new'),
      if (f.votesCount > 0) countText(f.votesCount, ar1: 'تصويت', ar2: 'تصويتان', arFew: '{n} تصويتات', arMany: '{n} تصويتاً', en1: '1 vote', en: '{n} votes'),
      if (f.overdueCount > 0) countText(f.overdueCount, ar1: 'متأخر واحد', ar2: 'متأخران', arFew: '{n} متأخرة', arMany: '{n} متأخراً', en1: '1 overdue', en: '{n} overdue'),
      if (f.assignedCount > 0) countText(f.assignedCount, ar1: 'مسند إليك', ar2: 'اثنان مسندان إليك', arFew: '{n} مسندة إليك', arMany: '{n} مسنداً إليك', en1: '1 assigned', en: '{n} assigned'),
      if (f.actingCount > 0) countText(f.actingCount, ar1: 'وحدة بلا رئيس', ar2: 'وحدتان بلا رئيس', arFew: '{n} وحدات بلا رئيس', arMany: '{n} وحدة بلا رئيس', en1: '1 unit without a head', en: '{n} units without a head'),
    ].join(' · ');

String attentionFlowTitle() => t('يحتاج انتباهي', 'Needs my attention');

// ═════════════════════════════════════════════════════════════════════════════
//  The store (the staff Home's entry row)
// ═════════════════════════════════════════════════════════════════════════════

String orgAttentionFlowPath(int orgId) => '/api/v1/org/public/governance/$orgId/me/attention-flow';

class AttentionFlowStore extends ChangeNotifier {
  AttentionFlowStore._();
  static final instance = AttentionFlowStore._();

  final Map<int, AttentionFlow> _data = {};
  final Map<int, DateTime> _asked = {};
  static const maxAge = Duration(minutes: 5);

  static bool get allowed => AppConfig.orgsEnabled && govEnabled();

  AttentionFlow? of(int? orgId) => orgId == null ? null : _data[orgId];

  /// Asks at most once per [maxAge] (the Home's open); the page reloads it when it closes.
  void ensure(int? orgId) {
    if (orgId == null || !allowed) return;
    final at = _asked[orgId];
    if (at != null && DateTime.now().difference(at) < maxAge) return;
    _asked[orgId] = DateTime.now();
    load(orgId);
  }

  /// Two callers at once (the Home's open and a page that just closed) share one request (UX v3 phase 5).
  Future<AttentionFlow?> load(int orgId) => _flights.run(orgId, () async {
        final r = await orgCall(() => ApiClient().get(orgAttentionFlowPath(orgId)), quiet: true);
        if (r.ok) {
          _data[orgId] = AttentionFlow.fromJson(r.map);
          notifyListeners();
        }
        return r.ok ? _data[orgId] : null;
      });
  final _flights = InFlight<int, AttentionFlow?>();

  @visibleForTesting
  void reset() {
    _data.clear();
    _asked.clear();
  }

  @visibleForTesting
  void put(int orgId, AttentionFlow f) {
    _data[orgId] = f;
    _asked[orgId] = DateTime.now();
    notifyListeners();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Plain-values view
// ═════════════════════════════════════════════════════════════════════════════

class AttentionFlowView extends StatelessWidget {
  const AttentionFlowView({super.key, required this.flow, this.onOpenItem, this.onOpenVote, this.onAssignHead});
  final AttentionFlow flow;
  final void Function(FlowItem item)? onOpenItem;
  final void Function(FlowVote vote)? onOpenVote;
  final void Function(FlowUnit unit)? onAssignHead;

  @override
  Widget build(BuildContext context) {
    final f = flow;
    if (f.isEmpty) {
      return AppEmpty(
        key: const ValueKey('flow.empty'),
        icon: Icons.task_alt_rounded,
        tone: AppBlockTone.emerald,
        title: t('لا شيء ينتظرك', "You're all caught up"),
        message: t('ستظهر هنا الطلبات الجديدة والتصويتات والمتأخرات', 'New requests, votes and anything late show up here'),
      );
    }
    final c = context.colors;
    String due(DateTime d) => t('قبل ${AppTime.dateTime(d)}', 'Due ${AppTime.dateTime(d)}');
    Widget itemRow(FlowItem x, {bool late = false}) => _FlowRow(
          key: ValueKey('flow.item.${x.id}'),
          icon: late ? Icons.schedule_rounded : Icons.assignment_rounded,
          title: x.title.isEmpty ? t('طلب', 'Request') : x.title,
          meta: [if (x.ref.isNotEmpty) x.ref, if (x.unit.isNotEmpty) x.unit, if (x.dueAt != null) due(x.dueAt!)].join(' · '),
          tone: late ? c.danger : null,
          lateWord: late ? t('متأخر', 'Overdue') : null,
          onTap: onOpenItem == null ? null : () => onOpenItem!(x),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (f.overdue.isNotEmpty || f.overdueCount > 0)
        _FlowSection(id: 'overdue', icon: Icons.alarm_rounded, title: t('متأخر', 'Overdue'), count: f.overdueCount, warn: true, children: [
          for (final x in f.overdue) itemRow(x, late: true),
        ]),
      if (f.newRequests.isNotEmpty || f.newCount > 0)
        _FlowSection(id: 'new', icon: Icons.mark_email_unread_rounded, title: t('طلبات جديدة', 'New requests'), count: f.newCount, children: [
          for (final x in f.newRequests) itemRow(x, late: x.late),
        ]),
      if (f.votesWaiting.isNotEmpty || f.votesCount > 0)
        _FlowSection(id: 'votes', icon: Icons.how_to_vote_rounded, title: t('تصويتات تنتظرك', 'Votes waiting'), count: f.votesCount, children: [
          for (final v in f.votesWaiting)
            _FlowRow(
              key: ValueKey('flow.vote.${v.sessionId}.${v.agendaItemId ?? v.itemId ?? 0}'),
              icon: Icons.how_to_vote_rounded,
              title: v.title.isEmpty ? t('بند للتصويت', 'An item to vote on') : v.title,
              meta: [if (v.council.isNotEmpty) v.council, if (v.deadline != null) due(v.deadline!)].join(' · '),
              onTap: onOpenVote == null ? null : () => onOpenVote!(v),
            ),
        ]),
      if (f.assignedToMe.isNotEmpty || f.assignedCount > 0)
        _FlowSection(id: 'assigned', icon: Icons.assignment_ind_rounded, title: t('مسند إليّ', 'Assigned to me'), count: f.assignedCount, children: [
          for (final x in f.assignedToMe) itemRow(x, late: x.late),
        ]),
      if (f.actingUnits.isNotEmpty)
        _FlowSection(
          id: 'acting',
          icon: Icons.person_search_rounded,
          title: t('وحدات تديرها بالإنابة', 'Units you are acting head of'),
          subtitle: t('عيّن رئيساً لكل وحدة حتى تصل طلباتها إلى صاحبها', 'Assign each a head so its requests reach the right person'),
          count: f.actingCount,
          warn: true,
          children: [
            for (final u in f.actingUnits)
              _FlowRow(
                key: ValueKey('flow.unit.${u.id}'),
                icon: Icons.apartment_rounded,
                title: u.name,
                meta: t('أنت الرئيس بالإنابة', 'You are the acting head'),
                actionLabel: t('عيّن رئيساً', 'Assign a head'),
                onTap: onAssignHead == null ? null : () => onAssignHead!(u),
              ),
          ],
        ),
    ]);
  }
}

class _FlowSection extends StatelessWidget {
  const _FlowSection({required this.id, required this.icon, required this.title, required this.count, required this.children, this.subtitle, this.warn = false});
  final String id, title;
  final String? subtitle;
  final IconData icon;
  final int count;
  final bool warn;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final more = count - children.length;
    return Padding(
      key: ValueKey('flow.section.$id'),
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Row(children: [
            Icon(icon, size: AppIconSize.md, color: warn ? appInk(context, c.warning) : c.textMedium),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
              ),
            ),
            AppStatusBadge(label: '$count', tone: warn ? AppTone.warning : AppTone.neutral, dense: true),
          ]),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Text(subtitle!, style: AppType.meta(context)),
          ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
              children[i],
            ],
            if (children.isEmpty || more > 0)
              Padding(
                padding: const EdgeInsets.all(AppSpace.sm),
                child: Text(
                    children.isEmpty
                        ? countText(count, ar1: 'عنصر واحد', ar2: 'عنصران', arFew: '{n} عناصر', arMany: '{n} عنصراً', en1: '1 item', en: '{n} items')
                        : t('و$more غيرها', 'and $more more'),
                    style: AppType.meta(context)),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _FlowRow extends StatelessWidget {
  const _FlowRow({super.key, required this.icon, required this.title, required this.meta, this.tone, this.lateWord, this.actionLabel, this.onTap});
  final IconData icon;
  final String title, meta;
  final Color? tone;
  final String? lateWord, actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wide = MediaQuery.sizeOf(context).width >= 600;
    return Semantics(
      button: onTap != null,
      label: [title, ?lateWord, if (meta.isNotEmpty) meta, ?actionLabel].join(AppConfig.lang == 'ar' ? '، ' : ', '),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
            child: Row(children: [
              Container(
                width: AppIconSize.hero,
                height: AppIconSize.hero,
                decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll),
                child: Icon(icon, size: AppIconSize.md, color: tone == null ? c.textMedium : appInk(context, tone!)),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                  if (lateWord != null || meta.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xxs / 2),
                    Text([?lateWord, if (meta.isNotEmpty) meta].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.meta(context).copyWith(color: tone == null ? null : appInk(context, tone!))),
                  ],
                ]),
              ),
              if (actionLabel != null && wide) ...[
                const SizedBox(width: AppSpace.xs),
                Text(actionLabel!, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: appInk(context, c.primary))),
              ],
              Icon(Icons.chevron_right_rounded, size: AppIconSize.lg, color: c.textLight),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The page
// ═════════════════════════════════════════════════════════════════════════════

class OrgAttentionFlowPage extends StatefulWidget {
  const OrgAttentionFlowPage({super.key, required this.orgId, this.initial, this.onAssignHead});
  final int orgId;

  /// What the Home already has (no second request on open); the page asks again on pull-to-refresh / after a row.
  final AttentionFlow? initial;

  /// "Assign a head" (default: the unit's department page through AppNavigator).
  final void Function(BuildContext context, FlowUnit unit)? onAssignHead;

  @override
  State<OrgAttentionFlowPage> createState() => _OrgAttentionFlowPageState();
}

class _OrgAttentionFlowPageState extends State<OrgAttentionFlowPage> {
  AttentionFlow? _flow;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _flow = widget.initial;
    if (_flow == null) _load();
  }

  Future<void> _load() async {
    final f = await AttentionFlowStore.instance.load(widget.orgId);
    if (!mounted) return;
    setState(() {
      if (f != null) _flow = f;
      _failed = f == null && _flow == null;
    });
  }

  Future<void> _then(Future<void> open) async {
    await open;
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final f = _flow;
    final Widget body = f == null
        ? (_failed
            ? AppErrorState(onRetry: _load)
            : const AppListSkeleton(items: 4))
        : AttentionFlowView(
            flow: f,
            onOpenItem: (x) => _then(AppNavigator.openModule('org_work', targetId: x.id, orgId: widget.orgId)),
            onOpenVote: (v) => _then(AppNavigator.openModule('org_council', targetId: v.sessionId, orgId: widget.orgId)),
            onAssignHead: (u) => widget.onAssignHead != null
                ? widget.onAssignHead!(context, u)
                : _then(AppNavigator.openModule('org_department', targetId: u.id, orgId: widget.orgId)),
          );
    return AppRefresh(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xl),
        children: [
          // the width is the push's (orgPush … width: AppWidth.reading)
          AnimatedSwitcher(duration: AppMotion.of(context).base, child: KeyedSubtree(key: ValueKey(f == null ? 'wait' : 'flow'), child: body)),
        ],
      ),
    );
  }
}
