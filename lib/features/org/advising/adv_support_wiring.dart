// lib/features/org/advising/adv_support_wiring.dart — where the Phase 7 screens plug into the rest of the app
// (docs/advising/PHASE7.md "Notices, push data, deep links"): the advising page's Requests · Request chain ·
// Accommodations links with their badges (`/status` `me.requests_*`), and the deep links of the request / plan /
// accommodation notices (push `module: advising` with `kind`, or `org_adv_request` · `org_adv_plan`), by `audience`:
// staff → the request page / the student's 360 on Support; the student → their request / their support page.
// Re-exported by adv_wiring.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import 'adv_accommodations.dart' show AdvAccommodationsPage;
import 'adv_models.dart' show AdvMe;
import 'adv_request_chain_page.dart' show AdvRequestChainPage;
import 'adv_requests.dart' show AdvRequestPage, AdvRequestsPage;
import 'adv_student_page.dart' show AdvStudentPage;
import 'adv_support_hub.dart' show AdvStudentRequestPage, AdvStudentSupportPage;
import 'adv_support_models.dart' show AdvSupportLink;

/// The advising page's Phase 7 tiles: Requests and referrals (with what waits on me), and for directors the Request
/// chain and the organization's Accommodations. [open] gets `requests` · `request_chain` · `accommodations`.
List<Widget> advSupportSetupTiles(BuildContext context, AdvMe me, ValueChanged<String> open) {
  if (!(me.leads || me.advisor)) return const [];
  final c = context.colors;
  final n = me.requests;
  final badge = (me.leads ? n.review + n.overdue : 0) + n.needsInfo;
  return [
    AppActionCard(
      icon: Icons.support_rounded,
      title: t('الطلبات والإحالات', 'Requests and referrals'),
      subtitle: n.attention > 0
          ? n.text
          : (me.leads ? t('طلبات الدعم ومسارها إلى المجالس، والإحالات', 'Support requests on their way to the councils, and referrals') : t('اكتب طلب دعم أو إحالة لطلابك وتابع مراحلها', 'File support requests and referrals for your students and follow them')),
      badge: badge,
      color: n.overdue > 0 && me.leads ? c.danger : (badge > 0 ? c.warning : c.primary),
      onTap: () => open('requests'),
    ),
    if (me.leads) ...[
      AppActionCard(
        icon: Icons.account_tree_rounded,
        title: t('مسار اعتماد الطلبات', 'Request approval chain'),
        subtitle: t('مدير الإرشاد ← مجلس القسم ← مجلس الكلية، أو مسارك', 'Advising director → department council → faculty council, or your own'),
        onTap: () => open('request_chain'),
      ),
      AppActionCard(
        icon: Icons.accessible_rounded,
        title: t('التسهيلات', 'Accommodations'),
        subtitle: t('من يحتاج ماذا في الامتحانات والتدريس، وحتى متى', 'Who needs what in exams and teaching, and until when'),
        onTap: () => open('accommodations'),
      ),
    ],
  ];
}

/// The page of one of [advSupportSetupTiles]' keys (null: not a Phase 7 key).
Widget? advSupportSetupPage(String key, int orgId, AdvMe me) => switch (key) {
      'requests' => AdvRequestsPage(
          orgId: orgId,
          manage: me.leads,
          queue: me.leads && me.requests.review > 0 ? 'review' : (me.requests.needsInfo > 0 ? 'needs_info' : ''),
        ),
      'request_chain' => AdvRequestChainPage(orgId: orgId),
      'accommodations' => AdvAccommodationsPage(orgId: orgId),
      _ => null,
    };

/// The deep link of a Phase 7 advising notice; false when [data] is not one (the caller falls back). `AppNavigator`
/// opens the organization first.
Future<bool> advOpenSupportLink(NavigatorState nav, {required int orgId, required Map<String, dynamic> data, String? module, String? kind}) async {
  final link = AdvSupportLink.parse(data, module: module, kind: kind);
  if (link == null) return false;
  final Widget page;
  if (link.student) {
    page = link.kind == 'request' ? AdvStudentRequestPage(orgId: orgId, requestId: link.requestId!) : AdvStudentSupportPage(orgId: orgId);
  } else if (link.kind == 'request') {
    page = AdvRequestPage(orgId: orgId, requestId: link.requestId!);
  } else if (link.memberId != null) {
    page = AdvStudentPage(orgId: orgId, memberId: link.memberId!, section: 'support');
  } else {
    return false;
  }
  await nav.push(MaterialPageRoute<void>(builder: (_) => page));
  return true;
}
