// Organization mode applies the open organization's context (timezone / 12h-24h + feature offs) and clears it when
// leaving; org-admin / org-staff land on the one organization dashboard (D-103).
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('entering / switching / leaving Organization mode applies then clears the org context', () {
    final applied = <int?>[];
    AppModeController.applyContext = applied.add;
    AppConfig.orgsEnabled = true;
    final ctl = AppModeController.instance;
    final overview = {
      'items': [
        {'organization': {'id': 4, 'status': 'approved'}, 'manage': null},
        {'organization': {'id': 9, 'status': 'approved'}, 'manage': null},
      ],
      'default_org_id': 4,
    };

    ctl.debugSet(overview, mode: AppMode.individual);
    expect(applied, isEmpty); // individual mode, nothing applied before → nothing to clear

    ctl.debugSet(overview, mode: AppMode.organization);
    expect(applied, [4]);

    ctl.debugSet(overview, mode: AppMode.organization); // unrelated refresh: no re-apply
    expect(applied, [4]);

    ctl.debugSet(overview, mode: AppMode.organization, orgId: 9); // switched organization
    expect(applied, [4, 9]);

    ctl.debugSet(overview, mode: AppMode.individual); // left Organization mode → back to platform defaults
    expect(applied, [4, 9, null]);

    ctl.debugSet(overview, mode: AppMode.organization);
    ctl.applyOrgContext(); // back from the management dashboard: re-applies the member's organization
    expect(applied.last, 9);
  });

  test('org-admin / org-staff home: the organization dashboard, unless they left for their personal space (D-103)', () {
    // the old "manages nothing → /org_member" hop is gone: every non-student org role opens /org_dashboard
    expect(AppModeController.orgRoleHome('/org_dashboard'), '/org_dashboard');
    expect(AppModeController.orgRoleHome('/org_dashboard', personal: false), '/org_dashboard');
    expect(AppModeController.orgRoleHome('/org_dashboard', personal: true), '/dashboard');
    expect(AppModeController.orgKeyFor(12), 'app_mode_org.12');
  });
}
