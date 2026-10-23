// Organization mode applies the open organization's context (timezone / 12h-24h + feature offs) and clears it when
// leaving; org-staff cold-start routing uses the cached "manages nothing" answer.
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

  test('org-staff home: live answer when loaded, else the cached one, else the management dashboard', () {
    expect(AppModeController.orgStaffHome(loaded: true, managesNothing: true), '/org_member');
    expect(AppModeController.orgStaffHome(loaded: true, managesNothing: false, cached: true), '/org_dashboard');
    expect(AppModeController.orgStaffHome(loaded: false, managesNothing: false, cached: true), '/org_member');
    expect(AppModeController.orgStaffHome(loaded: false, managesNothing: false, cached: false), '/org_dashboard');
    expect(AppModeController.orgStaffHome(loaded: false, managesNothing: false), '/org_dashboard');
    expect(AppModeController.managesNothingKey(12), 'org_manages_nothing.12');
  });
}
