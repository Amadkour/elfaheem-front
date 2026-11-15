// lib/features/org/governance/gov_wiring.dart — where the governance screens plug into the rest of the app:
// the org dashboard's section entries, the member dashboard's pills, the deep links a notification tap opens
// (`AppNavigator`: org_work · org_council · org_delegations · org_assignments) and the Export Hub callbacks
// (items list · entity items · council session). Everything else of the module stays in its own files.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/notif_link.dart' show NotifLink;
import 'package:provider/provider.dart';

import '../../../design/app_kit.dart' show showAppSheet;
import '../../../design/export_hub/export_hub.dart';
import '../../admin/admin_common.dart' show asInt, t;
import '../org_providers.dart' show OrgSession;
import '../org_v3.dart' show orgCall;
import 'gov_api.dart';
import 'gov_councils_page.dart';
import 'gov_delegations_page.dart';
import 'gov_entities_page.dart';
import 'gov_filter.dart';
import 'gov_item_screen.dart';
import 'gov_link_pages.dart';
import 'gov_items_page.dart';
import 'gov_member_pages.dart';
import 'gov_models.dart';
import 'gov_my_votes.dart';
import 'gov_session_screen.dart';
import 'gov_settings_page.dart';

/// Kill switch of the whole module (`org.governance`, feature_catalog.py). Hidden features disappear.
bool govEnabled() => !AppConfig.disableList.contains('org.governance');

bool govExportHubEnabled() => govEnabled() && !AppConfig.disableList.contains('org.governance.export_hub');

// ═════════════════════════════════════════════════════════════════════════════
//  Export Hub callbacks
// ═════════════════════════════════════════════════════════════════════════════

/// The unified item list (or one entity's list) → `GET …/export/data?module=items` → the hub.
Future<void> govExportItems(BuildContext context, int orgId, ItemFilter filter, {int? deptId}) async {
  final q = <String, dynamic>{...filter.toQuery(), 'export': true, 'dept_id': ?deptId};
  final ds = await fetchExportDataset(orgId, 'items', q);
  if (ds == null || !context.mounted) return;
  await exportHub(context, ds, orgId: orgId, deptId: deptId, canVotes: false);
}

/// One item or the selected ones → `GET …/export/data?module=items&ids=…` (the server checks every id, 403
/// `export_forbidden` naming the refused ones) → the hub (D-140).
Future<void> govExportItemIds(BuildContext context, int orgId, List<int> ids, {int? deptId}) async {
  if (ids.isEmpty) return;
  final ds = await fetchExportDataset(orgId, 'items', {'ids': ids.join(','), 'include_decisions': true, 'include_notes': true});
  if (ds == null || !context.mounted) return;
  await exportHub(context, ds, orgId: orgId, deptId: deptId, canVotes: false);
}

/// A council session → the hub. A closed session asks first: the session report (`module=council`) or the
/// minutes (`module=minutes`, the Minutes preset); vote results only with `councils.export` (the server refuses
/// otherwise).
Future<void> govExportSession(BuildContext context, int orgId, CouncilSession session) async {
  final canVotes = session.can['export_votes'] || session.can['manage'];
  var module = 'council';
  if (session.isClosed) {
    final pick = await showAppSheet<String>(
      context,
      (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.summarize_rounded), title: Text(t('تقرير الجلسة', 'Session report')),
            subtitle: Text(t('البنود مع نتيجة التصويت بجانب كل بند', 'Every item with its vote result')), onTap: () => Navigator.pop(ctx, 'council')),
        ListTile(leading: const Icon(Icons.history_edu_rounded), title: Text(t('محضر الجلسة', 'Minutes of the session')),
            subtitle: Text(t('الحاضرون والبنود والقرارات بصيغة محضر', 'Present members, items and decisions as minutes')), onTap: () => Navigator.pop(ctx, 'minutes')),
      ]),
    );
    if (pick == null) return;
    module = pick;
  }
  final ds = await fetchExportDataset(orgId, module, {
    'session_id': session.id,
    'include_votes': canVotes,
    'include_decisions': true,
    'include_notes': true,
  });
  if (ds == null || !context.mounted) return;
  await exportHub(context, ds, orgId: orgId, deptId: session.council?.dept.id, canVotes: canVotes);
}

/// Opens an item from an agenda row (council screens take a callback so they never import the item screen).
void govOpenItem(BuildContext context, WorkItem item, {int? orgId}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => GovItemScreen(item.id, orgId: orgId)));

// ═════════════════════════════════════════════════════════════════════════════
//  Org dashboard (staff) · member dashboard
// ═════════════════════════════════════════════════════════════════════════════

/// The "Services" section entries of the org dashboard: (key, label, icon, page). Keys `governance` and `votes`
/// are the attention sub-sections (`work_pending` / `council_votes`).
List<(String, String, IconData, Widget)> govServiceSubs(OrgSession s) {
  if (!govEnabled() || s.currentId == null) return const [];
  final oid = s.currentId!;
  final staff = s.isOrgAdmin || s.canAny('workflow') || s.canAny('councils');
  if (!staff) return const [];
  return [
    ('governance', t('المعاملات', 'Items'), Icons.account_tree_rounded,
        Builder(builder: (ctx) => GovItemsPage(embedded: true, orgId: oid, onExport: govExportHubEnabled() ? (f) => govExportItems(ctx, oid, f) : null,
            onExportIds: govExportHubEnabled() ? (ids) => govExportItemIds(ctx, oid, ids) : null))),
    ('entities', t('الجهات', 'Entities'), Icons.apartment_rounded, GovEntitiesPage(embedded: true, orgId: oid)),
    if (s.isOrgAdmin || s.canAny('councils'))
      ('councils', t('المجالس', 'Councils'), Icons.gavel_rounded,
          Builder(builder: (ctx) => GovCouncilsPage(orgId: oid, onOpenItem: (it) => govOpenItem(ctx, it, orgId: oid), onExport: govExportHubEnabled() ? (ses) => govExportSession(ctx, oid, ses) : null))),
    ('votes', t('تصويتاتي', 'My votes'), Icons.how_to_vote_rounded,
        Builder(builder: (ctx) => GovMyVotesPage(orgId: oid, embedded: true, onOpenItem: (it) => govOpenItem(ctx, it, orgId: oid)))),
    if (s.isOrgAdmin) ('gov_settings', t('إعدادات الإحالات', 'Routing settings'), Icons.tune_rounded, GovSettingsPage(orgId: oid, embedded: true)),
  ];
}

/// Quick pills on the member dashboard (every member: submit · my items · my votes · forms to answer).
List<Widget> govMemberPills(BuildContext context, int orgId, Widget Function({required IconData icon, required String label, required VoidCallback onTap}) pill) {
  if (!govEnabled()) return const [];
  void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
  return [
    pill(icon: Icons.add_task_rounded, label: t('طلب أو شكوى جديدة', 'New request / complaint'), onTap: () => push(GovSubmitPage(orgId))),
    pill(icon: Icons.account_tree_rounded, label: t('معاملاتي', 'My items'), onTap: () => push(GovMyItemsPage(orgId: orgId))),
    pill(icon: Icons.how_to_vote_rounded, label: t('تصويتاتي', 'My votes'), onTap: () => push(GovMyVotesPage(member: true, orgId: orgId))),
    pill(icon: Icons.assignment_turned_in_rounded, label: t('نماذج مطلوبة مني', 'Forms to answer'), onTap: () => push(const GovMyAssignmentsPage())),
  ];
}

// ═════════════════════════════════════════════════════════════════════════════
//  Deep links (AppNavigator)
// ═════════════════════════════════════════════════════════════════════════════

/// Staff view when the person manages that organization (it is in `OrgSession.items`), else the member view.
bool _manages(BuildContext ctx, int? orgId) {
  if (orgId == null) return false;
  try {
    return ctx.read<OrgSession>().items.any((o) => asInt(o['id']) == orgId);
  } catch (_) {
    return false;
  }
}

/// `org_work` → the item (notification `related_type` org_work_item carries the item id).
/// [link] (UX v3 phase 2): the action banner, the part to scroll to and the fields to change.
Future<void> govOpenItemLink(NavigatorState nav, BuildContext ctx, int id, {int? orgId, NotifLink? link}) =>
    nav.push(MaterialPageRoute(builder: (_) => GovItemScreen(id, orgId: orgId, member: !_manages(ctx, orgId), link: link)));

/// `org_council` → the session (agenda published · voting opened · closing · results).
Future<void> govOpenSessionLink(NavigatorState nav, BuildContext ctx, int sessionId, {int? orgId, NotifLink? link}) => nav.push(MaterialPageRoute(
    builder: (_) => GovSessionScreen(sessionId, orgId: orgId, member: !_manages(ctx, orgId), link: link, onOpenItem: (it) => govOpenItem(ctx, it, orgId: orgId))));

/// `org_delegations` → the delegations of the entity when known, else what is delegated to me.
Future<void> govOpenDelegationLink(NavigatorState nav, BuildContext ctx, int? deptId, {int? orgId}) => nav.push(MaterialPageRoute(
    builder: (_) => deptId != null && _manages(ctx, orgId) ? GovDelegationsPage(deptId, orgId: orgId) : GovMyItemsPage(orgId: orgId)));

/// `org_assignments` → the forms I must answer.
Future<void> govOpenAssignmentsLink(NavigatorState nav) => nav.push(MaterialPageRoute(builder: (_) => const GovMyAssignmentsPage()));

/// `org_delegation` (UX v3 phase 2, id = the delegation) → that delegation, or "no longer exists".
Future<void> govOpenDelegationById(NavigatorState nav, int id, {int? orgId, NotifLink? link}) =>
    nav.push(MaterialPageRoute(builder: (_) => GovLinkedDelegationPage(id, orgId: orgId, link: link)));

/// `org_form_assignment` (id = the assignment) → its fill screen while pending, else "already handled".
Future<void> govOpenAssignmentById(NavigatorState nav, int id, {NotifLink? link}) =>
    nav.push(MaterialPageRoute(builder: (_) => GovLinkedAssignmentPage(id, link: link)));

/// Department dashboard: the Items tab body of an entity.
Widget govDeptItemsTab(BuildContext context, int orgId, int deptId) =>
    GovItemsPage(deptId: deptId, embedded: true, orgId: orgId, onExport: govExportHubEnabled() ? (f) => govExportItems(context, orgId, f, deptId: deptId) : null,
        onExportIds: govExportHubEnabled() ? (ids) => govExportItemIds(context, orgId, ids, deptId: deptId) : null);

/// Department dashboard quick action: the council of a scientific department (by its council ENTITY id).
Future<void> govOpenCouncilOfDept(BuildContext context, int orgId, int councilDeptId) async {
  final r = await orgCall(() => GovApi(orgId).councils());
  if (!context.mounted) return;
  final c = (r.data is List<Council> ? r.data as List<Council> : const <Council>[]).where((c) => c.dept.id == councilDeptId).firstOrNull;
  if (c == null) return;
  Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GovCouncilPage(c.id, orgId: orgId, onOpenItem: (it) => govOpenItem(context, it, orgId: orgId), onExport: govExportHubEnabled() ? (ses) => govExportSession(context, orgId, ses) : null)));
}
