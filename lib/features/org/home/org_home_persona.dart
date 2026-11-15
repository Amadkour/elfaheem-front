// lib/features/org/home/org_home_persona.dart
//
// UX v3 phase 4: role-based homes. Each person inside an institution sees only what matters for who they are.
//   orgHomePersona        THE decision (pure, tested): who am I here → the persona the home opens with and every
//                         persona I hold (a department head who also teaches holds both)
//   orgPersonaSections    each persona's home, top to bottom (≤ 4 blocks, "what needs me now" first, More last)
//   orgPersonaMore        what each persona keeps under More (consolidated, never deleted: every page stays a tap
//                         away, the navigation and the command palette still carry them)
//   orgFlowPicks          the "what needs me now" preview rows of a teacher / staff member, from the attention flow
//                         already loaded for the home (no request of its own)
//   OrgPersonaStore       the chosen persona per user + organization on this device (SharedPreferences)
//   OrgPersonaSwitcher    the chips under the home's header, only for a person with more than one persona
//   OrgHomeLinksSection   a calm section of link rows (councils · my courses · More), plain values
//   showOrgQuickReply     3–5 canned bilingual replies on an assigned request (POST …/items/{id}/comments)
// Tests: test/org/ux_v3_p4_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/home_kit.dart' show HomeSection, HomeShowAllRow;
import 'package:shared_preferences/shared_preferences.dart';

import '../../admin/admin_common.dart' show SheetHeader, t;
import '../governance/gov_api.dart' show GovApi;
import '../org_attention_flow.dart' show AttentionFlow, FlowItem;
import '../org_dashboard_home.dart' show OrgAttentionSpec;
import 'org_home_tasks.dart' show OrgAlertRow, OrgRowsCard;

// ═════════════════════════════════════════════════════════════════════════════
//  Who am I here
// ═════════════════════════════════════════════════════════════════════════════

/// Highest responsibility first: the order of [orgHomePersona]'s `held` and of the switcher's chips.
enum OrgPersona { admin, dean, head, staff, teacher, student }

String orgPersonaLabel(OrgPersona p) => switch (p) {
      OrgPersona.admin => t('إدارة المؤسسة', 'Institution admin'),
      OrgPersona.dean => t('العمادة', 'Dean'),
      OrgPersona.head => t('رئيس القسم', 'Department head'),
      OrgPersona.staff => t('إداري', 'Administrative staff'),
      OrgPersona.teacher => t('هيئة التدريس', 'Teaching'),
      OrgPersona.student => t('طالب', 'Student'),
    };

IconData orgPersonaIcon(OrgPersona p) => switch (p) {
      OrgPersona.admin => Icons.admin_panel_settings_rounded,
      OrgPersona.dean => Icons.account_balance_rounded,
      OrgPersona.head => Icons.supervisor_account_rounded,
      OrgPersona.staff => Icons.badge_rounded,
      OrgPersona.teacher => Icons.school_rounded,
      OrgPersona.student => Icons.backpack_rounded,
    };

const _adminRoles = {'org_admin', 'platform_admin'};
const _teachingRoles = {'teacher', 'teacher_assistant'};

/// The persona the home opens with and every persona the person holds, highest responsibility first.
///
/// Decision table (the signals are what GET /org/mine?members=1 and GET …/dashboard already return):
///
/// | persona | held when                                                                                       |
/// |---------|-------------------------------------------------------------------------------------------------|
/// | admin   | `access == 'admin'`, or `my_role` is org_admin / platform_admin                                  |
/// | dean    | `can_faculty_overview` (server: an institution + org-wide workflow.approve + councils.view —     |
/// |         | the dean and vice deans, D-979) and not admin                                                    |
/// | head    | [headUnitIds] non-empty when the server sends it (it does not yet); else [deptApprover]: the     |
/// |         | right to approve requests (`workflow.approve`) inside a department, which a unit's head holds    |
/// | teacher | `member_role` (or `my_role`) is teacher / teacher_assistant                                      |
/// | staff   | `member_role` (or `my_role`) is admin_assistant; also the fallback for any non-student person    |
/// |         | nothing above matched (a member without rights)                                                  |
/// | student | `member_role` is student and nothing above matched (the member dashboard, not this one)          |
///
/// `primary` = the first of `held` (the highest responsibility); [OrgPersonaStore] may remember another one.
({OrgPersona primary, List<OrgPersona> held}) orgHomePersona({
  String access = '',
  String myRole = '',
  String? memberRole,
  bool facultyOverview = false,
  List<int>? headUnitIds,
  bool deptApprover = false,
}) {
  final role = memberRole ?? '';
  final admin = access == 'admin' || _adminRoles.contains(myRole);
  final held = <OrgPersona>[
    if (admin) OrgPersona.admin,
    if (facultyOverview && !admin) OrgPersona.dean,
    if (headUnitIds != null ? headUnitIds.isNotEmpty : deptApprover) OrgPersona.head,
    if (role == 'admin_assistant' || myRole == 'admin_assistant') OrgPersona.staff,
    if (_teachingRoles.contains(role) || _teachingRoles.contains(myRole)) OrgPersona.teacher,
  ];
  if (held.isEmpty) held.add(role == 'student' || myRole == 'student' ? OrgPersona.student : OrgPersona.staff);
  held.sort((a, b) => a.index.compareTo(b.index));
  return (primary: held.first, held: List.unmodifiable(held));
}

/// Do I approve requests inside at least one department (`dept_permissions[dept].workflow` holds `approve`)?
bool orgDeptApprover(dynamic deptPermissions) {
  if (deptPermissions is! Map) return false;
  for (final m in deptPermissions.values) {
    if (m is Map && m['workflow'] is List && (m['workflow'] as List).contains('approve')) return true;
  }
  return false;
}

/// The units I head, when the server names them (`head_unit_ids: [3]` or `head_units: [{id}]`); null = not sent.
List<int>? orgHeadUnitIds(Map<String, dynamic>? m) {
  final raw = m?['head_unit_ids'] ?? m?['head_units'];
  if (raw is! List) return null;
  return [
    for (final x in raw)
      if ((x is Map ? int.tryParse('${x['id']}') : int.tryParse('$x')) case final int id when id > 0) id,
  ];
}

/// A university / faculty (the server's `is_institution`: those types or a study system): the institution pages
/// (wizard, health) apply.
bool orgIsInstitutionItem(Map<String, dynamic>? o) =>
    const {'university', 'faculty'}.contains('${o?['type'] ?? ''}') || (o?['study_system'] != null && '${o?['study_system']}'.isNotEmpty);

// ═════════════════════════════════════════════════════════════════════════════
//  Each persona's home
// ═════════════════════════════════════════════════════════════════════════════

/// The home's blocks. [team] and [queue] are both the department cards (a head's team, a staff member's queue).
enum OrgHomeBlock { needsMe, setup, insights, faculty, councils, team, queue, myCourses, journey, myRequests, more }

/// Top to bottom: what needs me now, the persona's main work, then More. The student's order is the member
/// dashboard's (org_member_dashboard.dart: My journey first).
List<OrgHomeBlock> orgPersonaSections(OrgPersona p) => switch (p) {
      OrgPersona.admin => const [OrgHomeBlock.needsMe, OrgHomeBlock.setup, OrgHomeBlock.insights, OrgHomeBlock.more],
      OrgPersona.dean => const [OrgHomeBlock.needsMe, OrgHomeBlock.faculty, OrgHomeBlock.councils, OrgHomeBlock.more],
      OrgPersona.head => const [OrgHomeBlock.needsMe, OrgHomeBlock.team, OrgHomeBlock.councils, OrgHomeBlock.more],
      OrgPersona.staff => const [OrgHomeBlock.needsMe, OrgHomeBlock.queue, OrgHomeBlock.more],
      OrgPersona.teacher => const [OrgHomeBlock.needsMe, OrgHomeBlock.myCourses, OrgHomeBlock.more],
      OrgPersona.student => const [OrgHomeBlock.journey, OrgHomeBlock.myCourses, OrgHomeBlock.myRequests, OrgHomeBlock.more],
    };

/// What each persona keeps under More, in order (a link the person cannot open is left out by the home).
/// Keys: needs_action · insights · faculty · health · wizard · departments · members · requests · forms ·
/// complaints · councils · votes · courses · timetable · settings.
List<String> orgPersonaMore(OrgPersona p) => switch (p) {
      OrgPersona.admin => const ['needs_action', 'departments', 'members', 'health', 'wizard', 'faculty', 'requests', 'settings'],
      OrgPersona.dean => const ['needs_action', 'insights', 'health', 'departments', 'members', 'requests', 'settings'],
      OrgPersona.head => const ['needs_action', 'insights', 'faculty', 'members', 'requests', 'timetable', 'settings'],
      OrgPersona.staff => const ['needs_action', 'requests', 'forms', 'complaints', 'members', 'insights', 'settings'],
      OrgPersona.teacher => const ['needs_action', 'councils', 'votes', 'timetable', 'requests', 'insights', 'settings'],
      OrgPersona.student => const ['requests', 'complaints', 'settings'],
    };

/// Does this persona's home show the figures (the stat row, the members card)? Only the people who run it.
bool orgPersonaShowsFigures(OrgPersona p) => p == OrgPersona.admin || p == OrgPersona.dean;

/// The flow's "Needs my attention" row opens NeedsMyActionPage (cross-role, searchable) for these personas; heads
/// and deans keep their per-organization attention flow page (new requests · votes · overdue · acting units).
bool orgPersonaOpensActionInbox(OrgPersona p) => p == OrgPersona.staff || p == OrgPersona.teacher;

// ═════════════════════════════════════════════════════════════════════════════
//  "What needs me now": preview rows from the attention flow (no request of their own)
// ═════════════════════════════════════════════════════════════════════════════

class OrgFlowPick {
  const OrgFlowPick({required this.vote, required this.id, required this.title, this.place = '', this.late = false});

  /// A council vote (id = the session) or a request (id = the work item).
  final bool vote;
  final int id;
  final String title, place;
  final bool late;

  /// Only requests take a quick reply.
  bool get replyable => !vote;
}

/// A teacher sees the votes waiting first, then what is assigned to them; staff see what is assigned to them, the
/// overdue, then the new requests. Each item once, at most [max].
List<OrgFlowPick> orgFlowPicks(AttentionFlow? f, OrgPersona p, {int max = 3}) {
  if (f == null || !orgPersonaOpensActionInbox(p)) return const [];
  final votes = [
    for (final v in f.votesWaiting)
      OrgFlowPick(vote: true, id: v.sessionId, title: v.title.isEmpty ? t('تصويت في مجلس', 'A council vote') : v.title, place: v.council),
  ];
  OrgFlowPick item(FlowItem x) =>
      OrgFlowPick(vote: false, id: x.id, title: x.ref.isEmpty ? x.title : '${x.ref} · ${x.title}', place: x.unit, late: x.late);
  final items = [
    for (final x in f.assignedToMe) item(x),
    if (p == OrgPersona.staff) ...[for (final x in f.overdue) item(x), for (final x in f.newRequests) item(x)],
  ];
  final seen = <String>{};
  return [
    for (final x in p == OrgPersona.teacher ? [...votes, ...items] : items)
      if (seen.add('${x.vote}:${x.id}')) x,
  ].take(max).toList();
}

// ═════════════════════════════════════════════════════════════════════════════
//  The remembered choice
// ═════════════════════════════════════════════════════════════════════════════

/// The stored persona when the person still holds it, else the highest responsibility.
OrgPersona orgPersonaDefault(List<OrgPersona> held, String? stored) {
  for (final p in held) {
    if (p.name == stored) return p;
  }
  return held.isEmpty ? OrgPersona.staff : held.first;
}

/// The persona chosen per user + organization on this device (`org_home_persona.<user>.<org>`).
class OrgPersonaStore extends ChangeNotifier {
  OrgPersonaStore._();
  static final instance = OrgPersonaStore._();

  static const prefix = 'org_home_persona.';
  static String keyFor(int? userId, int? orgId) => '$prefix${userId ?? 0}.${orgId ?? 0}';

  final Map<String, String> _chosen = {};
  SharedPreferences? _prefs;
  bool _asked = false;

  Future<void> ensureLoaded() async {
    if (_asked) return;
    _asked = true;
    try {
      final p = await SharedPreferences.getInstance();
      _prefs = p;
      for (final k in p.getKeys()) {
        if (k.startsWith(prefix)) _chosen[k] = p.getString(k) ?? '';
      }
      notifyListeners();
    } catch (_) {}
  }

  OrgPersona pick(int? userId, int? orgId, List<OrgPersona> held) => orgPersonaDefault(held, _chosen[keyFor(userId, orgId)]);

  Future<void> choose(int? userId, int? orgId, OrgPersona p) async {
    final k = keyFor(userId, orgId);
    if (_chosen[k] == p.name) return;
    _chosen[k] = p.name;
    notifyListeners();
    try {
      await (_prefs ?? await SharedPreferences.getInstance()).setString(k, p.name);
    } catch (_) {}
  }

  @visibleForTesting
  void reset() {
    _chosen.clear();
    _prefs = null;
    _asked = false;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Widgets (plain values)
// ═════════════════════════════════════════════════════════════════════════════

/// "View as" chips under the home's header; nothing for a person with one persona.
class OrgPersonaSwitcher extends StatelessWidget {
  const OrgPersonaSwitcher({super.key, required this.held, required this.current, required this.onChanged});
  final List<OrgPersona> held;
  final OrgPersona current;
  final ValueChanged<OrgPersona> onChanged;

  @override
  Widget build(BuildContext context) {
    if (held.length < 2) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      child: Wrap(
        spacing: AppSpace.xs,
        runSpacing: AppSpace.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(t('أعرض بصفتي', 'View as'), style: AppType.meta(context).copyWith(color: c.textMedium)),
          for (final p in held)
            AppChoiceChip(
              key: ValueKey('org.persona.${p.name}'),
              icon: orgPersonaIcon(p),
              label: orgPersonaLabel(p),
              selected: p == current,
              onTap: () => onChanged(p),
            ),
        ],
      ),
    );
  }
}

/// A section of link rows (councils · my courses · More). Nothing when [links] is empty. [max] rows, then
/// "Show all (n)" unfolds the rest in place.
class OrgHomeLinksSection extends StatefulWidget {
  const OrgHomeLinksSection({super.key, required this.id, required this.title, required this.links, this.max = 0, this.subtitle});
  final String id, title;
  final String? subtitle;
  final List<OrgAttentionSpec> links;

  /// 0 = every row.
  final int max;

  @override
  State<OrgHomeLinksSection> createState() => _OrgHomeLinksSectionState();
}

class _OrgHomeLinksSectionState extends State<OrgHomeLinksSection> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final links = widget.links;
    if (links.isEmpty) return const SizedBox.shrink();
    final cut = widget.max > 0 && links.length > widget.max && !_all;
    final shown = cut ? links.take(widget.max).toList() : links;
    return HomeSection(
      id: widget.id,
      title: widget.title,
      subtitle: widget.subtitle,
      titlePadding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, 0, AppSpace.xs, AppSpace.xs),
      child: OrgRowsCard(children: [
        for (final x in shown) OrgAlertRow(spec: x),
        if (widget.max > 0 && links.length > widget.max)
          HomeShowAllRow(expanded: _all, count: links.length, onTap: () => setState(() => _all = !_all)),
      ]),
    );
  }
}

/// A link row of a links section.
OrgAttentionSpec orgLinkRow(IconData icon, String title, VoidCallback onTap, {String subtitle = '', int count = 0}) =>
    OrgAttentionSpec(icon: icon, severity: 'info', title: title, subtitle: subtitle, action: t('فتح', 'Open'), count: count, onTap: onTap);

// ═════════════════════════════════════════════════════════════════════════════
//  Quick replies
// ═════════════════════════════════════════════════════════════════════════════

/// The canned replies (Arabic, English).
const orgQuickReplies = <(String, String)>[
  ('تم استلام طلبك وجارٍ العمل عليه.', 'We received your request and are working on it.'),
  ('نحتاج مستنداً إضافياً لاستكمال طلبك.', 'We need one more document to complete your request.'),
  ('أُحيل طلبك إلى الجهة المختصة.', 'Your request was forwarded to the right office.'),
  ('تم إنجاز طلبك. شكراً لصبرك.', 'Your request is done. Thank you for your patience.'),
];

/// Picks a canned reply and posts it as a comment on the request (the same call as the request page's comment
/// box). True when it was sent.
Future<bool> showOrgQuickReply(BuildContext context, {required int orgId, required int itemId, GovApi? api}) async {
  final text = await showAppSheet<String>(context, (ctx) {
    final c = ctx.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        SheetHeader(t('رد سريع', 'Quick reply'), icon: Icons.quickreply_rounded),
        Text(t('يصل الرد لصاحب الطلب كتعليق عليه.', 'The person sees it as a comment on their request.'),
            style: AppType.meta(ctx).copyWith(color: c.textMedium)),
        AppSpace.gapSm,
        OrgRowsCard(margin: EdgeInsets.zero, children: [
          for (final (ar, en) in orgQuickReplies)
            OrgAlertRow(
              spec: OrgAttentionSpec(
                icon: Icons.chat_bubble_outline_rounded,
                severity: 'info',
                title: t(ar, en),
                subtitle: '',
                action: t('إرسال', 'Send'),
                onTap: () => Navigator.pop(ctx, t(ar, en)),
              ),
            ),
        ]),
      ]),
    );
  });
  if (text == null) return false;
  try {
    await (api ?? GovApi(orgId)).comment(itemId, text);
    showAppNotice(t('أُرسل الرد', 'Reply sent'));
    return true;
  } catch (e) {
    showAppNotice(ApiException.from(e).message, error: true);
    return false;
  }
}
