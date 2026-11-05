// lib/features/org/advising/adv_wiring.dart — where the Academic Advising screens plug into the rest of the app
// (the governance module's gov_wiring.dart pattern). Phase 2: the org dashboard's Services entry. Later phases add
// the department tab, the member pill and the deep links here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';

import '../../admin/admin_common.dart' show t;
import '../org_providers.dart' show OrgSession;
import 'adv_models.dart' show advMaybeEligible;
import 'adv_setup_page.dart';

/// Kill switch of the whole module (`org.advising`, feature_catalog.py; not org-manageable). Hidden features
/// disappear.
bool advEnabled() => !AppConfig.disableList.contains('org.advising');

/// The "Services" section entries of the org dashboard: (key, label, icon, page). Org admins and holders of an
/// `advising` right (the advising director role); hidden where the organization can never offer advising.
List<(String, String, IconData, Widget)> advServiceSubs(OrgSession s) {
  final oid = s.currentId;
  if (!advEnabled() || oid == null) return const [];
  if (!(s.isOrgAdmin || s.canAny('advising'))) return const [];
  if (!advMaybeEligible(s.items, oid)) return const [];
  return [
    ('advising', t('الإرشاد الأكاديمي', 'Academic advising'), Icons.co_present_rounded, AdvSetupPage(orgId: oid)),
  ];
}
