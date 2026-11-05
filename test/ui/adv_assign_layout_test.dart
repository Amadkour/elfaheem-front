// The Phase 3 advising pages must lay out at every size and language (320×640 · 1400×900, ar · en, text scale 1.3):
// every presentational view in every state — settings (loading · failed · server update · organization · a scope ·
// a new scope · invalid), the add-scope form, advisors (list · empty · failed), the profile sheet (manage · own),
// my profile, distribution (setup per mode · preview · nothing to change · stale · applied · busy · runs), students
// (manage · advisor · empty), the student sheet (single · multi with "assign anyway" · read only), the conflict form,
// handovers, and the advising page's links.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppActionCard;
import 'package:flutter_education_app/features/org/advising/adv_advisors_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_config_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_distribute_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_handovers_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_parts.dart';
import 'package:flutter_education_app/features/org/advising/adv_setup_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_students_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/adv_assign_models_test.dart';
import '../org/adv_models_test.dart' show sampleAdvStatusJson;
import 'layout_harness.dart';

const _err = 'The server could not be reached. Check the connection and try again.';

AdvPolicyBundle get _bundle => AdvPolicyBundle.fromJson(sampleAdvPolicyJson());
AdvPage<AdvAdvisor> get _advisors => AdvPage.fromJson(sampleAdvAdvisorsJson(), AdvAdvisor.fromJson);
AdvPage<AdvStudent> get _students => AdvPage.fromJson(sampleAdvStudentsJson(), AdvStudent.fromJson);
List<AdvConflict> get _conflicts => AdvPage.fromJson(sampleAdvConflictsJson(), AdvConflict.fromJson).items;
List<AdvHistoryEntry> get _history =>
    [for (final m in (sampleAdvHistoryJson()['items'] as List).cast<Map<String, dynamic>>()) AdvHistoryEntry.fromJson(m)];

Widget _sheet(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

AdvConfigView _config({AdvLoad load = AdvLoad.ready, AdvSettingsDraft? draft, bool busy = false}) {
  final b = _bundle;
  return AdvConfigView(
    load: load,
    bundle: load == AdvLoad.ready ? b : null,
    draft: load == AdvLoad.ready ? (draft ?? AdvSettingsDraft.of(b, 'org', null)) : null,
    errorText: _err,
    busy: busy,
    onRetry: () {},
    onScope: (_) {},
    onField: (_, _) {},
    onReset: (_) {},
    onSave: () {},
    onAddScope: () {},
    onRemoveScope: () {},
    onInheritAll: () {},
  );
}

AdvDistributeView _dist({
  AdvPlanRequest request = const AdvPlanRequest(),
  AdvPlan? plan,
  bool current = true,
  bool stale = false,
  AdvApplyResult? applied,
  AdvDistBusy busy = AdvDistBusy.none,
  bool options = true,
  bool force = false,
}) =>
    AdvDistributeView(
      request: request,
      options: options ? _bundle.options : null,
      settingsStrategy: 'balanced',
      plan: plan,
      planCurrent: current,
      stale: stale,
      applied: applied,
      busy: busy,
      runs: AdvPage.fromJson(sampleAdvRunsJson(), AdvRun.fromJson),
      force: force,
      forceReason: TextEditingController(text: 'No other advisors in the program this term'),
      onForce: (_) {},
      onRequest: (_) {},
      onPickFrom: () {},
      onPickTo: () {},
      onPreview: () {},
      onApply: () {},
      onRunsPage: (_) {},
    );

void main() {
  final note = TextEditingController(text: 'Office hours: Sunday and Tuesday 10:00–12:00, or by e-mail any day of the week');
  final empty = TextEditingController();

  testWidgets('AdvConfigView: loading · failed · server update', (tester) async {
    for (final l in [AdvLoad.loading, AdvLoad.failed, AdvLoad.missing]) {
      await expectNoLayoutErrors(tester, () => _config(load: l));
    }
  });

  testWidgets('AdvConfigView: organization · a scope · a new scope · invalid and busy', (tester) async {
    final b = _bundle;
    await expectNoLayoutErrors(tester, () => _config());
    await expectNoLayoutErrors(tester, () => _config(draft: AdvSettingsDraft.of(b, 'dept', '21').set('eligible_ranks', ['professor', 'associate_professor'])));
    await expectNoLayoutErrors(tester, () => _config(draft: const AdvSettingsDraft(scopeType: 'cohort', scopeRef: '2025', fresh: true)));
    await expectNoLayoutErrors(tester, () => _config(busy: true, draft: AdvSettingsDraft.of(b, 'org', null).set('eligible_roles', <String>[]).set('mode', 'multi')));
  });

  testWidgets('AdvConfigView: More opens the scope actions', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _config(draft: AdvSettingsDraft.of(_bundle, 'dept', '21')),
      act: (tester) async => tester.tap(find.byIcon(Icons.more_horiz_rounded).first, warnIfMissed: false),
    );
  });

  testWidgets('AdvScopeForm: choices · none left', (tester) async {
    final o = _bundle.options;
    await expectNoLayoutErrors(
      tester,
      () => _sheet(Column(children: [
        AdvScopeForm(options: o, type: 'dept', ref: '22', taken: const {'dept:21'}, onType: (_) {}, onRef: (_) {}, onSubmit: () {}),
        const SizedBox(height: 24),
        AdvScopeForm(options: o, type: 'program', ref: null, taken: const {'program:4'}, onType: (_) {}, onRef: (_) {}, onSubmit: () {}),
        const SizedBox(height: 24),
        AdvScopeForm(options: const AdvPolicyOptions(), type: 'level', ref: null, taken: const {}, onType: (_) {}, onRef: (_) {}, onSubmit: () {}),
      ])),
    );
  });

  testWidgets('AdvAdvisorsView: list · loading · failed · empty', (tester) async {
    Widget view(AdvLoad load, AdvPage<AdvAdvisor>? page, {String status = 'all'}) => AdvAdvisorsView(
          load: load,
          page: page,
          status: status,
          errorText: _err,
          onRetry: () {},
          onSearch: (_) {},
          onStatus: (_) {},
          onSort: (_) {},
          onPage: (_) {},
          onOpen: (_) {},
          onDistribute: () {},
        );
    await expectNoLayoutErrors(tester, () => view(AdvLoad.ready, _advisors));
    await expectNoLayoutErrors(tester, () => view(AdvLoad.ready, AdvPage.fromJson({...sampleAdvAdvisorsJson(), 'pages': 3}, AdvAdvisor.fromJson), status: 'over'));
    await expectNoLayoutErrors(tester, () => view(AdvLoad.loading, null));
    await expectNoLayoutErrors(tester, () => view(AdvLoad.failed, null));
    await expectNoLayoutErrors(tester, () => view(AdvLoad.ready, const AdvPage(), status: 'away'));
  });

  testWidgets('AdvProfileForm: manage (on leave, own maximum, conflicts) · loading conflicts · the advisor themself', (tester) async {
    final leila = _advisors.items[2];
    final huda = _advisors.items.first;
    await expectNoLayoutErrors(
      tester,
      () => _sheet(Column(children: [
        AdvProfileForm(
          advisor: leila,
          draft: AdvProfileDraft.of(leila).copyWith(maxLoadOverride: () => 25),
          manage: true,
          office: note,
          contact: note,
          bio: empty,
          conflicts: _conflicts,
          error: _err,
          onDraft: (_) {},
          onSubmit: () {},
          onPickFrom: () {},
          onPickUntil: () {},
          onReassign: () {},
          onAddConflict: () {},
          onRemoveConflict: (_) {},
        ),
        const SizedBox(height: 24),
        AdvProfileForm(advisor: huda, draft: AdvProfileDraft.of(huda), manage: true, busy: true, office: empty, contact: empty, bio: empty, onDraft: (_) {}, onSubmit: () {}, onAddConflict: () {}),
        const SizedBox(height: 24),
        AdvProfileForm(advisor: huda, draft: AdvProfileDraft.of(huda), manage: false, office: note, contact: empty, bio: note, onDraft: (_) {}, onSubmit: () {}),
      ])),
    );
  });

  testWidgets('AdvMyProfileView: loading · mine · on leave', (tester) async {
    await expectNoLayoutErrors(tester, () => const AdvMyProfileView(load: AdvLoad.loading));
    await expectNoLayoutErrors(tester, () => AdvMyProfileView(load: AdvLoad.ready, me: _advisors.items.first, onEdit: () {}));
    await expectNoLayoutErrors(tester, () => AdvMyProfileView(load: AdvLoad.ready, me: _advisors.items[2], onEdit: () {}));
  });

  testWidgets('AdvDistributeView: setup per mode (with and without the settings\' choices)', (tester) async {
    await expectNoLayoutErrors(tester, () => _dist());
    await expectNoLayoutErrors(tester, () => _dist(request: const AdvPlanRequest(mode: 'rebalance', strategy: 'round_robin', deptId: 21, level: '2'), options: false));
    await expectNoLayoutErrors(tester, () => _dist(request: const AdvPlanRequest(mode: 'reassign')));
    await expectNoLayoutErrors(
      tester,
      () => _dist(request: const AdvPlanRequest(mode: 'reassign', from: AdvRef(userId: 33, name: 'د. ليلى منصور عبد الحميد الشافعي'), to: AdvRef(userId: 32, name: 'Prof. Omar Khaled'), memberIds: [502])),
    );
  });

  testWidgets('AdvDistributeView: preview · outdated · stale · nothing to change · applied · busy', (tester) async {
    final plan = AdvPlan.fromJson(sampleAdvPlanJson());
    await expectNoLayoutErrors(tester, () => _dist(plan: plan));
    await expectNoLayoutErrors(tester, () => _dist(plan: plan, force: true));
    await expectNoLayoutErrors(tester, () => _dist(plan: plan, current: false));
    await expectNoLayoutErrors(tester, () => _dist(plan: plan, stale: true));
    await expectNoLayoutErrors(tester, () => _dist(plan: AdvPlan.fromJson(sampleAdvPlanJson(empty: true))));
    await expectNoLayoutErrors(
      tester,
      () => _dist(applied: AdvApplyResult.fromJson(const {'run_id': 12, 'assigned': 74, 'moved': 3, 'handovers': 3, 'notified_students': 77, 'notified_advisors': 6})),
    );
    await expectNoLayoutErrors(tester, () => _dist(plan: plan, busy: AdvDistBusy.apply));
  });

  testWidgets('AdvStudentsView: manage · advisor · loading · empty', (tester) async {
    Widget view(AdvLoad load, AdvPage<AdvStudent>? page, {bool manage = true, String filter = 'all'}) => AdvStudentsView(
          load: load,
          manage: manage,
          page: page,
          filter: filter,
          errorText: _err,
          onRetry: () {},
          onSearch: (_) {},
          onFilter: (_) {},
          onPage: (_) {},
          onOpen: (_) {},
          onDistribute: () {},
        );
    await expectNoLayoutErrors(tester, () => view(AdvLoad.ready, _students));
    await expectNoLayoutErrors(tester, () => view(AdvLoad.ready, _students, manage: false, filter: 'away'));
    await expectNoLayoutErrors(tester, () => view(AdvLoad.loading, null));
    await expectNoLayoutErrors(tester, () => view(AdvLoad.ready, const AdvPage(), filter: 'unassigned'));
  });

  testWidgets('AdvStudentForm: single · multi with "assign anyway" · read only · loading', (tester) async {
    final s = _students.items;
    await expectNoLayoutErrors(
      tester,
      () => _sheet(Column(children: [
        AdvStudentForm(student: s[1], draft: AdvAdvisorsDraft.of(s[1]), multi: false, manage: true, reason: empty, history: _history, conflicts: _conflicts,
            onPickPrimary: () {}, onClearPrimary: () {}, onLocked: (_) {}, onSubmit: () {}, onAddConflict: () {}, onRemoveConflict: (_) {}),
        const SizedBox(height: 24),
        AdvStudentForm(
          student: s[3],
          draft: AdvAdvisorsDraft.of(s[3]).addOther(const AdvRef(userId: 32, name: 'Prof. Omar Khaled'), 'support').copyWith(force: true, locked: true),
          multi: true,
          manage: true,
          reason: note,
          overCapacity: true,
          error: _err,
          onPickPrimary: () {},
          onClearPrimary: () {},
          onLocked: (_) {},
          onAddOther: (_) {},
          onRemoveOther: (_) {},
          onForce: (_) {},
          onSubmit: () {},
          onAddConflict: () {},
        ),
        const SizedBox(height: 24),
        AdvStudentForm(student: s[2], draft: AdvAdvisorsDraft.of(s[2]), multi: true, manage: true, reason: empty, onPickPrimary: () {}, onSubmit: () {}),
        const SizedBox(height: 24),
        AdvStudentForm(student: s[1], draft: AdvAdvisorsDraft.of(s[1]), multi: true, manage: false, reason: empty, history: _history),
      ])),
    );
  });

  testWidgets('AdvConflictForm: of an advisor · of a student with an error', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _sheet(Column(children: [
        AdvConflictForm(ofAdvisor: true, otherName: null, reason: 'relative', note: empty, onPick: () {}, onReason: (_) {}, onSubmit: () {}),
        const SizedBox(height: 24),
        AdvConflictForm(ofAdvisor: false, otherName: 'د. هدى سالم', reason: 'disciplinary', note: note, busy: true, error: _err, onPick: () {}, onReason: (_) {}, onSubmit: () {}),
      ])),
    );
  });

  testWidgets('AdvHandoversView: pending with Acknowledge · all · empty · loading', (tester) async {
    final p = AdvPage.fromJson(sampleAdvHandoversJson(), AdvHandover.fromJson);
    await expectNoLayoutErrors(tester, () => AdvHandoversView(load: AdvLoad.ready, page: p, me: 32, onPending: (_) {}, onAck: (_) {}));
    await expectNoLayoutErrors(tester, () => AdvHandoversView(load: AdvLoad.ready, page: p, me: 32, pendingOnly: false, acking: const {70}, onPending: (_) {}, onAck: (_) {}));
    await expectNoLayoutErrors(tester, () => AdvHandoversView(load: AdvLoad.ready, page: const AdvPage(), onPending: (_) {}));
    await expectNoLayoutErrors(tester, () => const AdvHandoversView(load: AdvLoad.loading));
  });

  testWidgets('AdvSetupView: the Phase 3 links (director-advisor with away / over counts · plain advisor)', (tester) async {
    final lead = AdvStatus.fromJson({
      ...sampleAdvStatusJson(admin: false, director: true, advisor: true),
      'me': {'admin': false, 'director': true, 'advisor': true, 'advisees': 12, 'handovers_pending': 3},
      'counts': {'students': 480, 'assigned': 402, 'unassigned': 78, 'advisors': 14, 'away': 22, 'over': 1},
    });
    final advisor = AdvStatus.fromJson(sampleAdvStatusJson(admin: false, advisor: true, counts: false));
    await expectNoLayoutErrors(tester, () => AdvSetupView(state: AdvSetupState.on, status: lead, onOpen: (_) {}, onDisable: () {}));
    await expectNoLayoutErrors(tester, () => AdvSetupView(state: AdvSetupState.on, status: advisor, onOpen: (_) {}));
  });

  testWidgets('the setup links open the right pages and the banners their actions', (tester) async {
    AppConfig.lang = 'en';
    final opened = <String>[];
    final status = AdvStatus.fromJson({
      ...sampleAdvStatusJson(),
      'counts': {'students': 480, 'assigned': 402, 'unassigned': 78, 'advisors': 14, 'away': 22, 'over': 1},
    });
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(layoutHost(AdvSetupView(state: AdvSetupState.on, status: status, onOpen: opened.add), scale: 1));
    await tester.pump();
    for (final label in ['Settings', 'Advisors', 'Students']) {
      await tester.tap(find.descendant(of: find.byType(AppActionCard), matching: find.text(label)));
    }
    for (final label in ['Rebalance', 'View']) {
      await tester.tap(find.widgetWithText(TextButton, label));
    }
    expect(opened, ['settings', 'advisors', 'students', 'rebalance', 'students_away']);
    expect(find.text('My advisor profile'), findsNothing, reason: 'an admin who advises nobody');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('AdvLoadBar and AdvStepper: semantics and limits', (tester) async {
    AppConfig.lang = 'en';
    int? changed;
    await tester.pumpWidget(layoutHost(Column(children: [
      const AdvLoadBar(load: 38, max: 35, over: true),
      AdvStepper(label: 'Maximum', value: 1000, max: 1000, step: 5, onChanged: (v) => changed = v),
    ])));
    expect(find.bySemanticsLabel(RegExp('Load 38 of 35, over the maximum')), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add_rounded));
    expect(changed, isNull, reason: 'already at the maximum');
    await tester.tap(find.byIcon(Icons.remove_rounded));
    expect(changed, 995);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
