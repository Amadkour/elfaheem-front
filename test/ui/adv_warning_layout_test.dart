// The Phase 6 early-warning views must lay out at every size and language (320×640 · 1400×900, ar · en, text scale
// 1.3): the rules page (director · advisor · a check running · a failed check · empty · loading · offline · failed ·
// server update), the kind picker, the rule editor (a GPA rule, the graduation rule with an on / off and an empty
// parameter, with a preview, a preview that needs a first check, read-only, a built-in rule, an error), the engine
// card switched off, the run history, the alerts page (alerts · filtered empty · empty · each load state ·
// graduation · graduation empty), the alert filter sheet, the 360's "Early warning" (matches · not checked yet ·
// nothing matches · checking · each load state), the graduation card in every status, the alert delivery sheet,
// the settings group (organization · a program), the advising page's links, the 360 with its new section, a rule
// flag's "Rule alerts" link, and the student's advisor card.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/org/advising/adv_alerts_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_flags.dart';
import 'package:flutter_education_app/features/org/advising/adv_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_my_advisor_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_parts.dart';
import 'package:flutter_education_app/features/org/advising/adv_rules_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_student_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_warning_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_warning_parts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/adv_case_models_test.dart';
import '../org/adv_warning_models_test.dart';
import 'layout_harness.dart';

const _err = 'The server could not be reached. Check the connection and try again.';

AdvRulesBundle _bundle({bool canEdit = true, bool running = false, bool failed = false, bool empty = false}) =>
    AdvRulesBundle.fromJson(sampleAdvRulesJson(canEdit: canEdit, running: running, failed: failed, empty: empty));

const _options = AdvPolicyOptions(
  programs: [AdvNamed(id: 4, nameAr: 'هندسة البرمجيات', nameEn: 'Software Engineering')],
  levels: ['Level 1', 'Level 2', 'Level 3'],
  cohorts: ['2023', '2024'],
);

List<AdvCategory> get _cats => [for (final m in (sampleAdvCategoriesJson()['items'] as List).cast<Map<String, dynamic>>()) AdvCategory.fromJson(m)];

Widget _sheet(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: child);

AdvRulesView _rules({AdvLoad load = AdvLoad.ready, AdvRulesBundle? bundle, bool starting = false}) => AdvRulesView(
      load: load,
      bundle: load == AdvLoad.ready ? (bundle ?? _bundle()) : null,
      options: _options,
      errorText: _err,
      busyIds: const {3},
      starting: starting,
      onRetry: () {},
      onAdd: () {},
      onOpen: (_) {},
      onToggle: (_, _) {},
      onRunNow: () {},
      onHistory: () {},
    );

AdvRuleKind _kind(String k) => _bundle().kindOf(k)!;

AdvRuleEditorView _editor(String kind, {AdvRule? rule, AdvRulePreview? preview, bool readOnly = false, String? error, String? previewError}) {
  final k = _kind(kind);
  final d = rule == null ? AdvRuleDraft.fresh(k) : AdvRuleDraft.of(rule);
  return AdvRuleEditorView(
    kind: k,
    draft: d,
    nameAr: TextEditingController(text: d.nameAr),
    nameEn: TextEditingController(text: d.nameEn),
    categories: _cats,
    options: _options,
    editing: rule != null,
    system: rule?.system ?? false,
    readOnly: readOnly,
    error: error,
    preview: preview,
    previewError: previewError,
    onParam: (_, _) {},
    onPriority: (_) {},
    onCooldown: (_) {},
    onCategory: (_) {},
    onScope: (_) {},
    onEnabled: (_) {},
    onPreview: () {},
    onSubmit: () {},
    onDelete: () {},
  );
}

AdvAlertsView _alerts({String tab = 'alerts', AdvLoad load = AdvLoad.ready, bool empty = false, AdvAlertQuery query = const AdvAlertQuery(), String? student}) => AdvAlertsView(
      tab: tab,
      manage: true,
      alertsLoad: load,
      alerts: load == AdvLoad.ready ? AdvPage.fromJson(sampleAdvAlertsJson(empty: empty), AdvAlert.fromJson) : null,
      alertQuery: query,
      alertsError: _err,
      gradLoad: load,
      graduation: load == AdvLoad.ready ? AdvPage.fromJson(sampleAdvGraduationJson(empty: empty), AdvGraduationItem.fromJson) : null,
      gradError: _err,
      studentName: student,
      onTab: (_) {},
      onRetry: () {},
      onFilters: () {},
      onClearFilters: () {},
      onAlertsPage: (_) {},
      onOpenStudent: (_) {},
      onPropose: (_) {},
      onGradStatus: (_) {},
      onGradSearch: (_) {},
      onGradPage: (_) {},
      onOpenGrad: (_) {},
    );

AdvWarningView _warning({AdvLoad load = AdvLoad.ready, bool evaluated = true, bool hits = true, bool evaluating = false, String graduation = 'delayed'}) => AdvWarningView(
      load: load,
      warning: load == AdvLoad.ready ? AdvWarning.fromJson(sampleAdvWarningJson(evaluated: evaluated, hits: hits, graduation: graduation)) : null,
      errorText: _err,
      evaluating: evaluating,
      onRetry: () {},
      onEvaluate: () {},
      onOpenFlag: (_) {},
    );

AdvPolicyBundle get _policy => AdvPolicyBundle.fromJson({
      'effective': {'digest': 'daily', 'digest_hour': 7, 'digest_weekday': 6, 'nudge_after_days': 21, 'nudge_advisors': true, 'nudge_students': true},
      'defaults': {'digest': 'off', 'digest_hour': 7, 'digest_weekday': 6, 'nudge_after_days': 21, 'nudge_advisors': true, 'nudge_students': true},
      'org': {'id': 1, 'settings': {'digest': 'daily', 'nudge_after_days': 28}},
      'scopes': [
        {'id': 5, 'scope_type': 'program', 'scope_ref': '4', 'label': 'هندسة البرمجيات', 'settings': {'nudge_students': false}},
      ],
    });

void main() {
  group('rules', () {
    testWidgets('director: engine, rules by kind', (t) => expectNoLayoutErrors(t, () => _rules()));
    testWidgets('advisor: read-only', (t) => expectNoLayoutErrors(t, () => _rules(bundle: _bundle(canEdit: false))));
    testWidgets('a check running', (t) => expectNoLayoutErrors(t, () => _rules(bundle: _bundle(running: true))));
    testWidgets('Run now pressed', (t) => expectNoLayoutErrors(t, () => _rules(starting: true)));
    testWidgets('the last check failed', (t) => expectNoLayoutErrors(t, () => _rules(bundle: _bundle(failed: true))));
    testWidgets('no rules', (t) => expectNoLayoutErrors(t, () => _rules(bundle: _bundle(empty: true))));
    for (final load in [AdvLoad.loading, AdvLoad.offline, AdvLoad.failed, AdvLoad.missing]) {
      testWidgets('state ${load.name}', (t) => expectNoLayoutErrors(t, () => _rules(load: load)));
    }
    testWidgets('the kind picker', (t) => expectNoLayoutErrors(t, () => _sheet(AdvKindPicker(kinds: _bundle().kinds, onPick: (_) {}))));
    testWidgets('the engine switched off, never run', (t) => expectNoLayoutErrors(t, () => _sheet(const AdvRunCard(engine: AdvEngine(), onRunNow: null))));
    testWidgets('the run history', (t) => expectNoLayoutErrors(t, () {
          final runs = [
            AdvWarningRun.fromJson(sampleAdvRunJson(id: 3, status: 'running', trigger: 'manual')),
            AdvWarningRun.fromJson(sampleAdvRunJson(id: 2, kind: 'digest')),
            AdvWarningRun.fromJson(sampleAdvRunJson(id: 1, status: 'failed', error: 'stale')),
          ];
          return _sheet(Column(children: [for (var i = 0; i < runs.length; i++) AdvRunRow(run: runs[i], last: i == runs.length - 1)]));
        }));
  });

  group('rule editor', () {
    testWidgets('a new GPA rule', (t) => expectNoLayoutErrors(t, () => _sheet(_editor('gpa_below'))));
    testWidgets('the graduation rule (on / off, empty value) with a preview',
        (t) => expectNoLayoutErrors(t, () => _sheet(_editor('graduation_delay', rule: _bundle().rules[4], preview: AdvRulePreview.fromJson(sampleAdvPreviewJson())))));
    testWidgets('a preview that needs a first check', (t) => expectNoLayoutErrors(t, () => _sheet(_editor('absence_pct', preview: AdvRulePreview.fromJson(sampleAdvPreviewJson(needsRun: true))))));
    testWidgets('read-only (an advisor)', (t) => expectNoLayoutErrors(t, () => _sheet(_editor('gpa_below', rule: _bundle().rules[1], readOnly: true))));
    testWidgets('a built-in rule with an error', (t) => expectNoLayoutErrors(t, () => _sheet(_editor('midterm_fail', rule: _bundle().rules[5], error: _err, previewError: _err))));
    testWidgets('a rule card on its own (custom, urgent, scoped)', (t) => expectNoLayoutErrors(t, () {
          final b = _bundle();
          return _sheet(Column(children: [
            AdvRuleCard(rule: b.rules[1], kind: b.kindOf('gpa_below'), onToggle: (_) {}, onTap: () {}),
            AdvRuleCard(rule: b.rules[4], kind: b.kindOf('graduation_delay'), scopeText: 'Software Engineering · Level 3 · 2023', onTap: () {}),
          ]));
        }));
  });

  group('alerts', () {
    testWidgets('alerts', (t) => expectNoLayoutErrors(t, () => _alerts()));
    testWidgets('one student\'s alerts', (t) => expectNoLayoutErrors(t, () => _alerts(student: 'ريم عبدالله القحطاني', query: const AdvAlertQuery(memberId: 31))));
    testWidgets('nothing matches the filters', (t) => expectNoLayoutErrors(t, () => _alerts(empty: true, query: const AdvAlertQuery(priority: 'urgent'))));
    testWidgets('no alerts yet', (t) => expectNoLayoutErrors(t, () => _alerts(empty: true)));
    for (final load in [AdvLoad.loading, AdvLoad.offline, AdvLoad.failed, AdvLoad.missing]) {
      testWidgets('state ${load.name}', (t) => expectNoLayoutErrors(t, () => _alerts(load: load)));
    }
    testWidgets('graduation', (t) => expectNoLayoutErrors(t, () => _alerts(tab: 'graduation')));
    testWidgets('graduation: nobody delayed', (t) => expectNoLayoutErrors(t, () => _alerts(tab: 'graduation', empty: true)));
    testWidgets('graduation loading', (t) => expectNoLayoutErrors(t, () => _alerts(tab: 'graduation', load: AdvLoad.loading)));
    testWidgets('the filter sheet', (t) => expectNoLayoutErrors(t, () {
          return _sheet(AdvAlertFilterForm(
            query: AdvAlertQuery(priority: 'high', ruleId: 2, flag: 'open', since: DateTime.now().subtract(const Duration(days: 7))),
            rules: _bundle().rules,
            onChanged: (_) {},
            onApply: () {},
          ));
        }));
  });

  group('the 360', () {
    testWidgets('early warning: matches, graduation, recent', (t) => expectNoLayoutErrors(t, () => _sheet(_warning())));
    testWidgets('not checked yet', (t) => expectNoLayoutErrors(t, () => _sheet(_warning(evaluated: false, graduation: 'unknown'))));
    testWidgets('nothing matches, on track', (t) => expectNoLayoutErrors(t, () => _sheet(_warning(hits: false, graduation: 'on_track'))));
    testWidgets('checking now, a level program', (t) => expectNoLayoutErrors(t, () => _sheet(_warning(evaluating: true, graduation: 'levels'))));
    for (final load in [AdvLoad.loading, AdvLoad.failed, AdvLoad.offline, AdvLoad.missing]) {
      testWidgets('state ${load.name}', (t) => expectNoLayoutErrors(t, () => _sheet(_warning(load: load))));
    }
    testWidgets('the graduation card in every status', (t) => expectNoLayoutErrors(t, () {
          return _sheet(Column(children: [
            for (final s in ['delayed', 'at_risk', 'on_track', 'levels', 'unknown', 'graduated'])
              Padding(padding: const EdgeInsets.only(bottom: 8), child: AdvGraduationCard(graduation: AdvGraduation.fromJson(sampleAdvGraduationBlock(s)))),
          ]));
        }));
    for (final s in ['warning', 'flags']) {
      testWidgets('the 360 on $s, with the early warning', (t) => expectNoLayoutErrors(t, () {
            return AdvStudentView(
              load: AdvLoad.ready,
              profile: AdvCaseProfile.fromJson(sampleAdvProfileJson()),
              section: s,
              now: advCaseNow,
              onSection: (_) {},
              flags: AdvFlagsPane(
                load: AdvLoad.ready,
                page: AdvPage.fromJson(sampleAdvFlagsJson(), AdvFlag.fromJson),
                view: 'all',
                onView: (_) {},
                canChange: (_) => true,
                canEdit: (_) => true,
                onStatus: (_) {},
                onEdit: (_) {},
                onHistory: (_) {},
                onAlerts: (_) {},
              ),
              warning: _warning(),
            );
          }));
    }
  });

  group('delivery and settings', () {
    testWidgets('alert delivery', (t) => expectNoLayoutErrors(t, () => _sheet(AdvAlertPrefsView(prefs: AdvAlertPrefs.fromJson(sampleAdvPrefsJson()), chosen: 'weekly', onChoose: (_) {}, onSave: () {}))));
    testWidgets('alert delivery saving with an error',
        (t) => expectNoLayoutErrors(t, () => _sheet(AdvAlertPrefsView(prefs: AdvAlertPrefs.fromJson(sampleAdvPrefsJson(digest: 'daily')), chosen: 'off', busy: true, error: _err))));
    testWidgets('settings: the organization', (t) => expectNoLayoutErrors(t, () {
          final b = _policy;
          return _sheet(AdvAlertSettingsGroup(bundle: b, draft: AdvSettingsDraft.of(b, 'org', null), onField: (_, _) {}, onReset: (_) {}));
        }));
    testWidgets('settings: a program', (t) => expectNoLayoutErrors(t, () {
          final b = _policy;
          return _sheet(AdvAlertSettingsGroup(bundle: b, draft: AdvSettingsDraft.of(b, 'program', '4'), onField: (_, _) {}, onReset: (_) {}));
        }));
    testWidgets('the advising page\'s links', (t) => expectNoLayoutErrors(t, () {
          return _sheet(Builder(builder: (context) => Column(children: advWarningSetupTiles(context, leads: true, advisor: true, open: (_) {}))));
        }));
    testWidgets('the student\'s advisor card', (t) => expectNoLayoutErrors(t, () {
          final s = AdvMemberStatus.fromJson({
            'enabled': true,
            'role': 'student',
            'advisors': [
              {'user_id': 7, 'name': 'د. سلمى الحربي', 'type': 'primary', 'office_location': 'مبنى 4، مكتب 212', 'contact_note': 'Office hours Sunday and Tuesday 10–12; e-mail first please.'},
              {'user_id': 8, 'name': 'Dr. Hani Saleh', 'type': 'co'},
            ],
          });
          return AdvMyAdvisorView(load: AdvLoad.ready, status: s);
        }));
    testWidgets('no advisor yet', (t) => expectNoLayoutErrors(t, () => const AdvMyAdvisorView(load: AdvLoad.ready, status: AdvMemberStatus(enabled: true, role: 'student'))));
  });
}
