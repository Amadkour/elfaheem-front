// lib/features/org/advising/adv_wiring.dart — where the Academic Advising screens plug into the rest of the app
// (the governance module's gov_wiring.dart pattern). Phase 2: the org dashboard's Services entry; Phase 4: the same
// entry for advisors (the `advising` key of `/org/mine`). Later phases add the department tab, the member pill and
// the deep links here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';

import '../../admin/admin_common.dart' show t;
import '../org_providers.dart' show OrgSession;
import 'adv_models.dart' show AdvMineInfo, advMaybeEligible;
import 'adv_setup_page.dart';
import 'adv_student_page.dart' show AdvStudentPage;
import '../org_v3.dart' show orgCall, orgParseUtc;
import 'adv_alerts_page.dart' show AdvAlertsPage;
import 'adv_api.dart' show AdvApi;
import 'adv_models.dart' show AdvStatus;
import 'adv_my_advisor_page.dart' show AdvMyAdvisorPage;
import 'adv_warning_parts.dart' show advWarningOn;
import 'adv_workspace_page.dart' show AdvWorkspacePage;

/// Kill switch of the whole module (`org.advising`, feature_catalog.py; not org-manageable). Hidden features
/// disappear.
bool advEnabled() => !AppConfig.disableList.contains('org.advising');

/// Does `/org/mine` name me as an advising director, or an advisor with students, in [item]?
bool advAdvisesIn(Map<String, dynamic>? item) {
  final mine = AdvMineInfo.of(item);
  return mine != null && (mine.director || mine.advisees > 0);
}

/// The "Services" section entries of the org dashboard: (key, label, icon, page). Org admins, holders of an
/// `advising` right (the advising director role) and anyone `/org/mine` names as a director or an advisor with
/// students there ([advAdvisesIn]); hidden where the organization can never offer advising.
List<(String, String, IconData, Widget)> advServiceSubs(OrgSession s) {
  final oid = s.currentId;
  if (!advEnabled() || oid == null) return const [];
  if (!(s.isOrgAdmin || s.canAny('advising') || advAdvisesIn(s.current))) return const [];
  if (!advMaybeEligible(s.items, oid)) return const [];
  return [
    ('advising', t('الإرشاد الأكاديمي', 'Academic advising'), Icons.co_present_rounded, AdvSetupPage(orgId: oid)),
  ];
}

/// Deep link of the advising notices that name a student (an urgent flag, an escalation, a review due: push data
/// `module: advising` with `member_id` / `flag_id`): that student's 360. `AppNavigator` opens the organization first.
Future<void> advOpenStudentLink(NavigatorState nav, {required int orgId, required int memberId}) =>
    nav.push(MaterialPageRoute<void>(builder: (_) => AdvStudentPage(orgId: orgId, memberId: memberId)));

/// Phase 6: the early-warning notices that name a screen (push data `module: advising` with `screen`, or a
/// `warning_alert` with `action: propose_meeting`). `alerts` → the alerts (since the digest's `since`) · `workspace`
/// → My students by last contact · `advisor` → the student's advising card · `propose_meeting` + `member_id` → the
/// 360 ready to log a contact. False when [data] names none of them (the caller opens the 360 or the notifications).
Future<bool> advOpenScreenLink(NavigatorState nav, {required int orgId, required Map<String, dynamic> data}) async {
  if (!advWarningOn()) return false;
  final screen = '${data['screen'] ?? ''}';
  final member = int.tryParse('${data['member_id'] ?? ''}');
  if (data['action'] == 'propose_meeting' && member != null) {
    await nav.push(MaterialPageRoute<void>(builder: (_) => AdvStudentPage(orgId: orgId, memberId: member, section: 'notes', logContact: true)));
    return true;
  }
  if (screen == 'advisor') {
    await nav.push(MaterialPageRoute<void>(builder: (_) => AdvMyAdvisorPage(orgId: orgId)));
    return true;
  }
  if (screen != 'alerts' && screen != 'workspace') return false;
  // a director sees the whole organization, an advisor their own students
  final st = await orgCall(() => AdvApi(orgId).status(), quiet: true);
  final lead = st.ok && (st.data as AdvStatus).me.leads;
  await nav.push(MaterialPageRoute<void>(
    builder: (_) => screen == 'alerts'
        ? AdvAlertsPage(orgId: orgId, manage: lead, since: orgParseUtc(data['since']))
        : AdvWorkspacePage(orgId: orgId, manage: lead, sort: '${data['sort'] ?? 'contact'}'),
  ));
  return true;
}
