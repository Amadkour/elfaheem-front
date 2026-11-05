// The Academic Advising page (Phase 2) must lay out at every size and language (320×640 · 1400×900, ar · en, text
// scale 1.3): every AdvSetupView state (loading · failed · not available · off for the admin and for a director ·
// on for the admin, a director and an advisor without counts · busy) and the Enable sheet's department picker.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/advising/adv_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_setup_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/adv_models_test.dart' show sampleAdvStatusJson;
import 'layout_harness.dart';

AdvStatus _status(Map<String, dynamic> j) => AdvStatus.fromJson(j);

Widget _view(AdvSetupState state, {AdvStatus? status, bool busy = false, String? dept}) => AdvSetupView(
      state: state,
      status: status,
      deptName: dept,
      errorText: 'The server could not be reached. Check the connection and try again.',
      busy: busy,
      onRetry: () {},
      onEnable: () {},
      onDisable: () {},
    );

void main() {
  const longDept = 'Academic Advising and Student Success Office of the Faculty of Engineering';

  testWidgets('AdvSetupView: loading · failed · not available', (tester) async {
    for (final w in [
      () => _view(AdvSetupState.loading),
      () => _view(AdvSetupState.failed),
      () => _view(AdvSetupState.unavailable, status: _status({'eligible': false, 'reason': 'org_type', 'enabled': false})),
    ]) {
      await expectNoLayoutErrors(tester, w);
    }
  });

  testWidgets('AdvSetupView: off (admin with Enable, director without)', (tester) async {
    await expectNoLayoutErrors(tester, () => _view(AdvSetupState.off, status: _status(sampleAdvStatusJson(enabled: false))));
    await expectNoLayoutErrors(
        tester, () => _view(AdvSetupState.off, status: _status(sampleAdvStatusJson(enabled: false, admin: false, director: true))));
    await expectNoLayoutErrors(tester, () => _view(AdvSetupState.off, busy: true, status: _status(sampleAdvStatusJson(enabled: false))));
  });

  testWidgets('AdvSetupView: on (admin · director advisor · advisor without counts · no directors)', (tester) async {
    await expectNoLayoutErrors(tester, () => _view(AdvSetupState.on, dept: longDept, status: _status(sampleAdvStatusJson())));
    await expectNoLayoutErrors(tester,
        () => _view(AdvSetupState.on, status: _status(sampleAdvStatusJson(admin: false, director: true, advisor: true))));
    await expectNoLayoutErrors(tester,
        () => _view(AdvSetupState.on, status: _status(sampleAdvStatusJson(admin: false, advisor: true, counts: false))));
    await expectNoLayoutErrors(
      tester,
      () => _view(AdvSetupState.on, busy: true, status: _status({
        ...sampleAdvStatusJson(),
        'directors': [],
        'counts': {'students': 0, 'assigned': 0, 'unassigned': 0, 'advisors': 0},
      })),
    );
  });

  testWidgets('AdvSetupView: More opens Turn off', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _view(AdvSetupState.on, dept: longDept, status: _status(sampleAdvStatusJson())),
      act: (tester) async => tester.tap(find.byIcon(Icons.more_horiz_rounded).first, warnIfMissed: false),
    );
  });

  testWidgets('AdvEnableForm: loading · with an advising department · create one · busy', (tester) async {
    final choices = advDeptChoices([
      {'id': 3, 'name_ar': 'الإرشاد الأكاديمي', 'name_en': 'Academic Advising', 'kind': 'service', 'preset': 'academic_advising'},
      {'id': 1, 'name_ar': 'شؤون الطلاب ورعاية الشباب والأنشطة الطلابية', 'name_en': longDept, 'kind': 'service'},
    ]);
    final others = advDeptChoices([
      {'id': 1, 'name_ar': 'شؤون الطلاب', 'name_en': 'Student Affairs', 'kind': 'service'},
    ]);
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          AdvEnableForm(choices: const [], loading: true, selected: null, onSelect: (_) {}, onSubmit: () {}),
          const SizedBox(height: 24),
          AdvEnableForm(choices: choices, selected: 3, onSelect: (_) {}, onSubmit: () {}),
          const SizedBox(height: 24),
          AdvEnableForm(choices: others, selected: null, onSelect: (_) {}, onSubmit: () {}),
          const SizedBox(height: 24),
          AdvEnableForm(choices: others, selected: 1, busy: true, onSelect: (_) {}, onSubmit: () {}),
        ]),
      ),
    );
  });

  testWidgets('AdvEnableForm: "create one" is offered only without an advising department', (tester) async {
    AppConfig.lang = 'en';
    int? picked = -1;
    await tester.pumpWidget(layoutHost(AdvEnableForm(
      choices: advDeptChoices([{'id': 1, 'name_ar': 'شؤون الطلاب', 'name_en': 'Student Affairs', 'kind': 'service'}]),
      selected: 1,
      onSelect: (v) => picked = v,
      onSubmit: () {},
    )));
    await tester.tap(find.text('Create a new department'));
    expect(picked, isNull);
    await tester.pumpWidget(layoutHost(AdvEnableForm(
      choices: advDeptChoices([{'id': 3, 'name_ar': 'الإرشاد', 'name_en': 'Advising', 'kind': 'service', 'preset': 'academic_advising'}]),
      selected: 3,
      onSelect: (_) {},
      onSubmit: () {},
    )));
    expect(find.text('Create a new department'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
