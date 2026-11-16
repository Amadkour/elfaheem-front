// lib/features/org/org_fix_actions.dart
//
// UX v3 phase 6: the organization's one-tap fixes for a server `fix_action`, registered once app-wide
// (AppFixActions, lib/design/app_errors.dart) so every AppErrorBox / showAppError / non-quiet orgCall that carries
// one gets a working button:
//   open_members     a council roster refusal (detail `council_id`) → that council's Members tab; else the
//                    organization's Members page (where staff are added first)
//   open_agenda      the council named in the detail (`council_id`, or the first of `councils`) → its Sessions tab
//                    (the agendas); none named → the councils list
//   setup_councils   Settings → Councils setup
//   pick_reassign    screen-local only (the unit archive sheet's AppFixScope focuses its picker): no app-wide fix
//
//   orgFixOf(e)              the pure decision (tested in test/org/ux_v3_p6_test.dart)
//   registerOrgFixActions()  idempotent; called by OrgSession's constructor
// The pages load through the deferred governance wiring, so the eager start-up code stays small.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_errors.dart' show AppFixActions;
import 'package:flutter_education_app/main.dart' show navigatorKey;

import '../admin/admin_common.dart' show asInt, asMap, t;
import 'governance/gov_wiring.dart' deferred as gov;

/// Where an organization fix goes.
enum OrgFix { members, councilRoster, councilAgenda, councilsList, councilsSetup }

/// The fix actions the organization handles app-wide.
const orgFixActions = ['open_members', 'open_agenda', 'setup_councils'];

/// The screen-local fix of the archive sheet (no app-wide handler).
const orgPickReassignAction = 'pick_reassign';

/// The decision for [e]: where its fix goes and the council it names (null = this error has no org fix).
({OrgFix fix, int? councilId})? orgFixOf(ApiException e) {
  final d = e.detail;
  int? council() {
    final id = asInt(d['council_id']);
    if (id > 0) return id;
    final list = d['councils'];
    if (list is List && list.isNotEmpty) {
      final first = asInt(asMap(list.first)['id']);
      if (first > 0) return first;
    }
    return null;
  }

  switch (e.fixAction) {
    case 'open_members':
      final id = council();
      return id != null ? (fix: OrgFix.councilRoster, councilId: id) : (fix: OrgFix.members, councilId: null);
    case 'open_agenda':
      final id = council();
      return id != null ? (fix: OrgFix.councilAgenda, councilId: id) : (fix: OrgFix.councilsList, councilId: null);
    case 'setup_councils':
      return (fix: OrgFix.councilsSetup, councilId: null);
    default:
      return null;
  }
}

/// The button label of a fix.
String orgFixLabel(OrgFix f) => switch (f) {
      OrgFix.members => t('افتح صفحة الأعضاء', 'Open Members'),
      OrgFix.councilRoster => t('افتح أعضاء المجلس', 'Open the council members'),
      OrgFix.councilAgenda => t('افتح جدول أعمال المجلس', "Open the council's agenda"),
      OrgFix.councilsList => t('افتح المجالس', 'Open the councils'),
      OrgFix.councilsSetup => t('افتح إعداد المجالس', 'Open the councils setup'),
    };

/// The label of the archive sheet's `pick_reassign` fix.
String orgPickReassignLabel() => t('اختر الوحدة', 'Choose the unit');

/// Opens [fix] from [context] (the screen's when still mounted, else the root navigator).
Future<void> runOrgFix(BuildContext? context, ({OrgFix fix, int? councilId}) fix) async {
  final ctx = context != null && context.mounted ? context : navigatorKey.currentContext;
  if (ctx == null) return;
  final nav = Navigator.of(ctx);
  await gov.loadLibrary();
  if (!ctx.mounted) return;
  final orgId = gov.govOrgIdOf(ctx);
  switch (fix.fix) {
    case OrgFix.members:
      await gov.govOpenMembers(nav);
    case OrgFix.councilRoster:
      await gov.govOpenCouncilTab(nav, fix.councilId!, orgId: orgId, tab: 1);
    case OrgFix.councilAgenda:
      await gov.govOpenCouncilTab(nav, fix.councilId!, orgId: orgId);
    case OrgFix.councilsList:
      await gov.govOpenCouncilsList(nav, orgId: orgId);
    case OrgFix.councilsSetup:
      await gov.govOpenCouncilsSetup(ctx, orgId: orgId);
  }
}

/// Registers the organization's fixes with [AppFixActions] (idempotent).
void registerOrgFixActions() {
  for (final a in orgFixActions) {
    if (AppFixActions.has(a)) continue;
    AppFixActions.register(a, (e, context, _) {
      final f = orgFixOf(e);
      if (f == null) return null;
      return (() => runOrgFix(context, f), orgFixLabel(f.fix));
    });
  }
}
