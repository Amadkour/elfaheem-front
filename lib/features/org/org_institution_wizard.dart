// lib/features/org/org_institution_wizard.dart
//
// Institutions v2, phase 4: the guided setup wizard (plan docs/institutions/V2_PLAN.md item 4, back D-991 – D-993).
//   GET|PUT …/institution/wizard   {step, done, launched_at, applicable, readiness}; Next PUTs {step, done}
//   GET|PUT …/institution/heads    every unit with its head; PUT {heads: {"<dept_id>": userId | "me"}}
//   POST    …/institution/launch   409 not_ready {items} or {launched_at}
// Six steps: basics & study system → departments (core ones ticked and locked) → heads ("me" shortcut) → councils →
// optional (links out) → review & launch. It reuses StudySystemView, DeptCatalogView and CouncilsChoiceView.
//   InstitutionWizardState · InstitutionReadiness · ReadinessItem · HeadUnit · HeadsDraft   pure (tested)
//   InstitutionWizardApi · InstitutionWizardPrefetch          the calls; the Home's parallel GET (no waterfall)
//   WizardStepStrip · WizardNavBar · HeadsStepView · OptionalStepView · ReviewStepView · LaunchedView
//   InstitutionSetupCard                                      plain values (expectNoLayoutErrors)
//   OrgInstitutionWizard · openInstitutionWizard              the page (OrgPushedPage through orgPush)
//   OrgInstitutionSetupSlot                                   the Home: the wizard card, else the old checklist
// Tested in test/org/institutions_v2_p4_test.dart.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppFill;
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show asInt, asMap, asMapList, asStr, t;
import 'governance/gov_api.dart';
import 'governance/gov_council_ui.dart' show govOrgId, pickOrgMember;
import 'governance/gov_councils_setup.dart';
import 'governance/gov_models.dart' show GovUser;
import 'org_dashboard_home.dart' show orgPush;
import 'org_dashboard_screen.dart' show OrgTabs;
import 'org_departments_page.dart' show showDepartmentWizard;
import 'org_institution_health.dart' show InstitutionHealth, InstitutionHealthCard, openInstitutionHealth;
import 'org_institution_roadmap.dart' show InstitutionRoadmapCard, institutionHealthy, institutionStagesOf, openInstitutionRoadmap;
import 'org_institutions.dart';
import 'org_page_kit.dart';
import 'org_providers.dart';
import 'org_ui.dart' show OrgAsync, OrgEmpty, OrgGrid;
import 'org_unit_rules.dart' show ActingChip, AssignMeChip, CoreUnitBadge, HeadErrorText, UnitHead, currentPerson;
import 'org_v3.dart' show OrgCall, orgCall, orgErrorText;

// ═════════════════════════════════════════════════════════════════════════════
//  Pure parts
// ═════════════════════════════════════════════════════════════════════════════

/// The server's step keys, in order.
const institutionWizardSteps = ['basics', 'departments', 'heads', 'councils', 'optional', 'review'];

String wizardStepLabel(String key) => switch (key) {
      'basics' => t('الأساسيات', 'Basics'),
      'departments' => t('الإدارات', 'Departments'),
      'heads' => t('الرؤساء', 'Heads'),
      'councils' => t('المجالس', 'Councils'),
      'optional' => t('إضافات', 'Optional'),
      _ => t('المراجعة والإطلاق', 'Review & launch'),
    };

/// The step a readiness action opens (`basics` · `departments` · `heads` · `councils` · `optional`); unknown → basics.
int wizardStepOfAction(String action) {
  final i = institutionWizardSteps.indexOf(action);
  return i < 0 ? 0 : i;
}

/// One line of the readiness list.
class ReadinessItem {
  const ReadinessItem({
    required this.key,
    this.severity = 'warn',
    this.count = 0,
    this.textAr = '',
    this.textEn = '',
    this.action = 'basics',
    this.ids = const [],
    this.fix,
  });

  final String key, severity, textAr, textEn, action;
  final int count;
  final List<int> ids;

  /// `core_missing`: the POST …/dept-catalog/apply body that creates the missing core departments in one tap.
  final Map<String, dynamic>? fix;

  bool get blocks => severity == 'block';
  String get text => t(textAr.isEmpty ? textEn : textAr, textEn.isEmpty ? textAr : textEn);

  factory ReadinessItem.fromJson(Map<String, dynamic> j) => ReadinessItem(
        key: asStr(j['key']),
        severity: asStr(j['severity'], 'warn') == 'block' ? 'block' : 'warn',
        count: asInt(j['count']),
        textAr: asStr(j['text_ar']),
        textEn: asStr(j['text_en']),
        action: asStr(j['action'], 'basics'),
        ids: [for (final v in (j['ids'] is List ? j['ids'] as List : const [])) asInt(v)],
        fix: asMap(j['fix']).isEmpty ? null : asMap(j['fix']),
      );
}

/// What still stops the launch (block) and what is worth a look (warn).
class InstitutionReadiness {
  const InstitutionReadiness({this.ok = false, this.blocking = 0, this.items = const []});
  final bool ok;
  final int blocking;
  final List<ReadinessItem> items;

  factory InstitutionReadiness.fromJson(Map<String, dynamic> j) {
    final items = [for (final x in asMapList(j['items'])) ReadinessItem.fromJson(x)];
    final blocks = items.where((x) => x.blocks).length;
    return InstitutionReadiness(
      ok: j['ok'] == true,
      blocking: j['blocking'] == null ? blocks : asInt(j['blocking']),
      items: items,
    );
  }

  /// The 409 `not_ready` answer: only the items are sent.
  factory InstitutionReadiness.fromItems(List<Map<String, dynamic>> raw) => InstitutionReadiness.fromJson({'items': raw});

  List<ReadinessItem> get blockItems => [for (final x in items) if (x.blocks) x];
  List<ReadinessItem> get warnItems => [for (final x in items) if (!x.blocks) x];

  /// Launch is allowed only with nothing blocking.
  bool get canLaunch => blocking == 0 && blockItems.isEmpty;
}

/// The institution roadmap's stages (phase 5, D-994), in order; `launch` is the wizard's review step.
const institutionStageKeys = ['basics', 'departments', 'heads', 'councils', 'launch'];

/// One stage of `stages: [{key, state: done|current|todo|warn, count_warn}]`.
class InstitutionStage {
  const InstitutionStage({required this.key, this.state = 'todo', this.countWarn = 0, this.blocking = 0});
  final String key, state;
  final int countWarn;

  /// How many of its readiness items block the launch.
  final int blocking;

  /// The wizard step it opens.
  String get wizardStep => key == 'launch' ? 'review' : key;

  static InstitutionStage? fromJson(Map<String, dynamic> j) {
    final key = asStr(j['key']);
    if (!institutionStageKeys.contains(key)) return null;
    final st = asStr(j['state'], 'todo');
    return InstitutionStage(
        key: key,
        state: const ['done', 'current', 'todo', 'warn'].contains(st) ? st : 'todo',
        countWarn: asInt(j['count_warn']),
        blocking: asInt(j['blocking']));
  }
}

/// GET …/institution/wizard.
class InstitutionWizardState {
  const InstitutionWizardState({
    this.step = 'basics',
    this.done = const {},
    this.launchedAt,
    this.applicable = false,
    this.readiness = const InstitutionReadiness(),
    this.stages = const [],
  });

  final String step;
  final Set<String> done;
  final String? launchedAt;
  final bool applicable;
  final InstitutionReadiness readiness;

  /// Phase 5 (D-994): the roadmap's five stages as the server sees them; empty on an older server (the roadmap
  /// derives them, institutionStagesOf).
  final List<InstitutionStage> stages;

  factory InstitutionWizardState.fromJson(Map<String, dynamic> j) => InstitutionWizardState(
        step: asStr(j['step'], 'basics'),
        done: {for (final v in (j['done'] is List ? j['done'] as List : const [])) if (institutionWizardSteps.contains('$v')) '$v'},
        launchedAt: (j['launched_at'] == null || '${j['launched_at']}'.isEmpty) ? null : '${j['launched_at']}',
        applicable: j['applicable'] == true,
        readiness: InstitutionReadiness.fromJson(asMap(j['readiness'])),
        stages: [for (final s in asMapList(j['stages'])) ?InstitutionStage.fromJson(s)],
      );

  /// The step to open: the stored one; an unknown key → the first.
  int get stepIndex {
    final i = institutionWizardSteps.indexOf(step);
    return i < 0 ? 0 : i;
  }

  int get doneCount => done.length;
  double get progress => doneCount / institutionWizardSteps.length;
  bool get launched => launchedAt != null;

  /// The Home shows the wizard card (instead of the old checklist): a university / faculty not launched yet.
  bool get showCard => applicable && !launched;
}

/// The PUT …/institution/wizard body: the step to resume at and the steps done, in the server's order.
Map<String, dynamic> wizardPutBody(String step, Set<String> done) =>
    {'step': step, 'done': [for (final k in institutionWizardSteps) if (done.contains(k)) k]};

/// One unit of GET …/institution/heads.
class HeadUnit {
  const HeadUnit({required this.id, required this.name, this.kind = 'service', this.core = false, this.head});
  final int id;
  final String name, kind;
  final bool core;
  final UnitHead? head;

  bool get academic => kind == 'academic';
  bool get empty => head == null;
  bool get acting => head?.acting == true;

  /// `kind`: `scientific` (the server's word; `academic` from older drafts) · `service` · a custom kind (= service).
  factory HeadUnit.fromJson(Map<String, dynamic> j) {
    final h = asMap(j['head']);
    final ar = asStr(j['name_ar']), en = asStr(j['name_en']);
    final both = ar.isNotEmpty || en.isNotEmpty;
    final kind = asStr(j['kind'], 'service');
    return HeadUnit(
      id: asInt(j['id']),
      name: both ? t(ar.isEmpty ? en : ar, en.isEmpty ? ar : en) : asStr(j['name']),
      kind: kind == 'scientific' || kind == 'academic' ? 'academic' : 'service',
      core: j['core'] == true,
      head: h['id'] == null ? null : UnitHead(id: asInt(h['id']), name: asStr(h['name']), acting: h['acting'] == true),
    );
  }
}

/// `{units: [...]}` (also a bare list or `{items}`).
List<HeadUnit> headUnitsOf(Object? data) =>
    [for (final x in asMapList(data is Map ? (data['units'] ?? data['items']) : data)) HeadUnit.fromJson(x)];

/// The new head of one unit: a person, or me ([user] null).
class HeadChoice {
  const HeadChoice.person(GovUser this.user);
  const HeadChoice.me() : user = null;
  final GovUser? user;

  bool get me => user == null;
  Object get wire => user?.id ?? 'me';
}

/// The heads being chosen (only the changed units). Immutable.
class HeadsDraft {
  const HeadsDraft([this.picks = const {}]);
  final Map<int, HeadChoice> picks;

  bool get isEmpty => picks.isEmpty;
  HeadChoice? of(int id) => picks[id];

  HeadsDraft set(int id, HeadChoice? c) {
    final m = {...picks};
    if (c == null) {
      m.remove(id);
    } else {
      m[id] = c;
    }
    return HeadsDraft(m);
  }

  /// "Make me head of all empty units": every unit with no head and no choice yet.
  HeadsDraft meForAllEmpty(List<HeadUnit> rows) => HeadsDraft({
        ...picks,
        for (final r in rows)
          if (r.empty && !picks.containsKey(r.id)) r.id: const HeadChoice.me(),
      });

  /// Units still without a head after this draft.
  int emptyLeft(List<HeadUnit> rows) => rows.where((r) => r.empty && !picks.containsKey(r.id)).length;

  /// Acting heads still to replace after this draft.
  int actingLeft(List<HeadUnit> rows) => rows.where((r) => r.acting && !picks.containsKey(r.id)).length;

  Map<String, dynamic> toBody() => {
        'heads': {for (final e in picks.entries) '${e.key}': e.value.wire},
      };
}

/// The 422 `head_invalid` / `dept_invalid` answer: the units whose choice was refused.
Set<int> headInvalidIds(Map<String, dynamic> detail) =>
    {for (final v in (detail['dept_ids'] is List ? detail['dept_ids'] as List : const [])) asInt(v)};

/// The Home may draw the wizard card: organizations on and the institution kill switch off.
bool institutionWizardAllowed() => AppConfig.orgsEnabled && !AppConfig.disableList.contains(orgInstitutionFeatureKey);

// ═════════════════════════════════════════════════════════════════════════════
//  Calls
// ═════════════════════════════════════════════════════════════════════════════

class InstitutionWizardApi {
  InstitutionWizardApi(this.s);
  final OrgSession s;

  String get _b => '${s.base}/institution';

  Future<OrgCall> state() => orgCall(() => s.api.get('$_b/wizard'), quiet: true);
  Future<OrgCall> saveState(String step, Set<String> done) => orgCall(() => s.api.put('$_b/wizard', body: wizardPutBody(step, done)), quiet: true);
  Future<OrgCall> heads() => orgCall(() => s.api.get('$_b/heads'), quiet: true);
  Future<OrgCall> saveHeads(HeadsDraft d) => orgCall(() => s.api.put('$_b/heads', body: d.toBody()), quiet: true);
  Future<OrgCall> launchInstitution() => orgCall(() => s.api.post('$_b/launch'), quiet: true);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Views (plain values)
// ═════════════════════════════════════════════════════════════════════════════

/// The step strip: phones "Step 2 of 6" + a progress bar; wide windows every step, numbered, done ones ticked.
class WizardStepStrip extends StatelessWidget {
  const WizardStepStrip({super.key, required this.current, required this.done, required this.reached, required this.onTap});
  final int current, reached;
  final Set<String> done;
  final ValueChanged<int> onTap;

  static const _wideFrom = 720.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = institutionWizardSteps.length;
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < _wideFrom) {
        return Semantics(
          key: const ValueKey('wizard.strip.compact'),
          label: t('الخطوة ${current + 1} من $n: ${wizardStepLabel(institutionWizardSteps[current])}',
              'Step ${current + 1} of $n: ${wizardStepLabel(institutionWizardSteps[current])}'),
          excludeSemantics: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(t('الخطوة ${current + 1} من $n', 'Step ${current + 1} of $n'), style: AppType.label(context).copyWith(color: c.primary)),
              AppSpace.gapXs,
              Expanded(
                child: Text(wizardStepLabel(institutionWizardSteps[current]),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
              ),
            ]),
            AppSpace.gapXs,
            AppFill(
              value: (current + 1) / n,
              builder: (context, v) => ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(value: v, minHeight: AppSpace.xxs, backgroundColor: c.divider, color: c.primary),
              ),
            ),
          ]),
        );
      }
      return Row(key: const ValueKey('wizard.strip.full'), crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < n; i++)
          Expanded(child: _StripStep(index: i, current: current, done: done.contains(institutionWizardSteps[i]), enabled: i <= reached, onTap: () => onTap(i))),
      ]);
    });
  }
}

class _StripStep extends StatelessWidget {
  const _StripStep({required this.index, required this.current, required this.done, required this.enabled, required this.onTap});
  final int index, current;
  final bool done, enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = institutionWizardSteps.length;
    final now = index == current;
    final mark = now ? c.primary : (done ? c.success : c.cardBg);
    final ink = now || done ? Theme.of(context).colorScheme.onPrimary : c.textMedium;
    Widget line(bool show, bool lit) => Expanded(
          child: show ? Container(height: AppBorder.strong, color: lit ? c.primaryLight : c.divider) : const SizedBox.shrink(),
        );
    return Semantics(
      button: true,
      selected: now,
      enabled: enabled,
      label: '${index + 1}. ${wizardStepLabel(institutionWizardSteps[index])}',
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('wizard.strip.$index'),
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: enabled && !now ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
          child: Column(children: [
            Row(children: [
              line(index > 0, index <= current),
              AnimatedContainer(
                duration: AppMotion.of(context).base,
                width: AppIconSize.xl,
                height: AppIconSize.xl,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: mark,
                  shape: BoxShape.circle,
                  border: Border.all(color: now ? c.primary : (done ? c.success : c.divider), width: AppBorder.strong),
                ),
                child: done && !now
                    ? Icon(Icons.check_rounded, size: AppIconSize.sm, color: ink)
                    : Text('${index + 1}', style: AppType.label(context).copyWith(color: ink)),
              ),
              line(index < n - 1, index < current),
            ]),
            const SizedBox(height: AppSpace.xxs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
              child: Text(wizardStepLabel(institutionWizardSteps[index]),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: (now ? AppType.bodyStrong(context) : AppType.meta(context)).copyWith(color: now ? c.textDark : c.textMedium)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Back / Next, fixed at the bottom. [onNext] null = disabled (Launch while something blocks).
class WizardNavBar extends StatelessWidget {
  const WizardNavBar({super.key, required this.nextLabel, required this.onNext, this.onBack, this.busy = false, this.nextIcon = Icons.arrow_forward_rounded});
  final String nextLabel;
  final VoidCallback? onNext, onBack;
  final bool busy;
  final IconData nextIcon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider, width: AppBorder.hairline))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
          child: LayoutBuilder(builder: (context, box) {
            // phones: Back keeps its size, Next takes the rest; wide: both at their size, Next at the end
            final narrow = box.maxWidth < AppWidth.form.max;
            final next = AppButton.primary(
                key: const ValueKey('wizard.next'), label: nextLabel, trailingIcon: nextIcon, busy: busy, expand: narrow, onPressed: busy ? null : onNext);
            return Row(children: [
              if (onBack != null) ...[
                AppButton.secondary(
                    key: const ValueKey('wizard.back'),
                    label: t('السابق', 'Back'),
                    icon: narrow ? null : Icons.arrow_back_rounded,
                    onPressed: busy ? null : onBack),
                AppSpace.gapSm,
              ],
              if (narrow) Expanded(child: next) else ...[const Spacer(), next],
            ]);
          }),
        ),
      ),
    );
  }
}

/// The departments step's opening lines: what academic and service units are, and that core ones are always made.
class DeptKindsIntro extends StatelessWidget {
  const DeptKindsIntro({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget row(IconData icon, String title, String text) => Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: AppIconSize.md, color: c.primary),
            AppSpace.gapSm,
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '$title  ', style: AppType.bodyStrong(context)),
                TextSpan(text: text, style: AppType.body(context).copyWith(color: c.textMedium)),
              ])),
            ),
          ]),
        );
    return Padding(
      key: const ValueKey('wizard.dept.intro'),
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('نوعان من الوحدات', 'Two kinds of units'), style: AppType.section(context)),
          row(Icons.menu_book_rounded, t('العلمية:', 'Academic:'), t('أقسام لها مقررات ومجلس قسم.', 'departments that own courses and a department council.')),
          row(Icons.support_agent_rounded, t('الخدمية:', 'Service:'),
              t('إدارات تقدّم الخدمات وتستقبل الطلبات والشكاوى.', 'offices that provide services and receive requests and complaints.')),
          row(Icons.lock_rounded, t('الأساسية:', 'Core:'), t('محددة مسبقاً وتُنشأ دائماً.', 'ticked for you and always created.')),
        ]),
      ),
    );
  }
}

/// Step 3: every unit with its head, "Assign me" per row and "Make me head of all empty units".
class HeadsStepView extends StatelessWidget {
  const HeadsStepView({
    super.key,
    required this.rows,
    required this.draft,
    required this.onChanged,
    this.onPick,
    this.meName = '',
    this.errors = const {},
  });

  final List<HeadUnit> rows;
  final HeadsDraft draft;
  final ValueChanged<HeadsDraft> onChanged;

  /// Picks a person for one unit; null = read-only.
  final Future<GovUser?> Function(HeadUnit unit)? onPick;
  final String meName;
  final Set<int> errors;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final empty = draft.emptyLeft(rows), acting = draft.actingLeft(rows);
    final academic = [for (final r in rows) if (r.academic) r];
    final service = [for (final r in rows) if (!r.academic) r];
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpace.xl),
      children: [
        OrgSectionHeading(t('من يرأس كل وحدة؟', 'Who heads each unit?'),
            subtitle: t('لكل وحدة رئيس يستقبل طلباتها. يمكنك أن تكون الرئيس الآن وتسلّمها لاحقاً.',
                'Every unit needs a head who receives its requests. You can take it now and hand it over later.')),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: AppBanner(
                icon: Icons.info_outline_rounded,
                text: t('لا وحدات بعد — أنشئها في خطوة «الإدارات».', 'No units yet: create them in the Departments step.')),
          ),
        if (empty > 0 || acting > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
            child: AppCard(
              key: const ValueKey('heads.summary'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.person_off_rounded, color: c.warning, size: AppIconSize.lg),
                  AppSpace.gapSm,
                  Expanded(
                    child: Text(
                        [
                          if (empty > 0)
                            countText(empty,
                                ar1: 'وحدة واحدة بلا رئيس', ar2: 'وحدتان بلا رئيس', arFew: '{n} وحدات بلا رئيس', arMany: '{n} وحدة بلا رئيس',
                                en1: 'One unit has no head', en: '{n} units have no head'),
                          if (acting > 0)
                            countText(acting,
                                ar1: 'رئيس واحد بالإنابة يحتاج بديلاً', ar2: 'رئيسان بالإنابة يحتاجان بديلاً', arFew: '{n} رؤساء بالإنابة يحتاجون بديلاً',
                                arMany: '{n} رئيساً بالإنابة يحتاجون بديلاً', en1: 'One acting head to replace', en: '{n} acting heads to replace'),
                        ].join(' · '),
                        style: AppType.bodyStrong(context)),
                  ),
                ]),
                if (empty > 0) ...[
                  AppSpace.gapSm,
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AppButton.tonal(
                        key: const ValueKey('heads.all_me'),
                        icon: Icons.person_pin_rounded,
                        label: t('اجعلني رئيساً لكل الوحدات الفارغة', 'Make me head of all empty units'),
                        onPressed: () => onChanged(draft.meForAllEmpty(rows))),
                  ),
                ],
              ]),
            ),
          ),
        if (academic.isNotEmpty) ...[
          OrgSectionHeading(t('الأقسام العلمية', 'Academic departments')),
          for (final r in academic) _row(r),
        ],
        if (service.isNotEmpty) ...[
          OrgSectionHeading(t('الإدارات الخدمية', 'Service departments')),
          for (final r in service) _row(r),
        ],
      ],
    );
  }

  Widget _row(HeadUnit r) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.xxs),
        child: HeadUnitCard(
          key: ValueKey('heads.row.${r.id}'),
          unit: r,
          choice: draft.of(r.id),
          meName: meName,
          error: errors.contains(r.id),
          onPick: onPick == null
              ? null
              : () async {
                  final u = await onPick!(r);
                  if (u != null) onChanged(draft.set(r.id, HeadChoice.person(u)));
                },
          onMe: () => onChanged(draft.set(r.id, draft.of(r.id)?.me == true ? null : const HeadChoice.me())),
          onUndo: draft.of(r.id) == null ? null : () => onChanged(draft.set(r.id, null)),
        ),
      );
}

/// One unit: its name (core lock), its head now (Acting = replace), the new choice, Choose / Assign me / Undo.
class HeadUnitCard extends StatelessWidget {
  const HeadUnitCard({super.key, required this.unit, required this.choice, required this.onMe, this.onPick, this.onUndo, this.meName = '', this.error = false});
  final HeadUnit unit;
  final HeadChoice? choice;
  final VoidCallback onMe;
  final VoidCallback? onPick, onUndo;
  final String meName;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final h = unit.head;
    final ch = choice;
    final needs = ch == null && (h == null || h.acting);
    final who = meName.isEmpty ? t('أنت', 'You') : meName;
    return Material(
      color: c.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardAll,
        side: BorderSide(color: error ? c.danger : (needs ? c.warning : c.divider), width: error ? AppBorder.strong : AppBorder.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(unit.academic ? Icons.menu_book_rounded : Icons.apartment_rounded, color: c.primary, size: AppIconSize.md),
            AppSpace.gapSm,
            Expanded(child: Text(unit.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context))),
            if (unit.core) ...[AppSpace.gapXs, const CoreUnitBadge()],
          ]),
          const SizedBox(height: AppSpace.xs),
          if (ch != null)
            Row(children: [
              Icon(Icons.check_circle_rounded, size: AppIconSize.sm, color: c.success),
              const SizedBox(width: AppSpace.xxs),
              Expanded(
                child: Text(
                    ch.me ? t('الرئيس الجديد: $who (أنت)', 'New head: $who (you)') : t('الرئيس الجديد: ${ch.user!.name}', 'New head: ${ch.user!.name}'),
                    key: ValueKey('heads.choice.${unit.id}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.meta(context).copyWith(color: c.textDark)),
              ),
            ])
          else if (h == null)
            Text(t('لم يُعيَّن رئيس بعد', 'No head yet'), style: AppType.meta(context).copyWith(color: c.warning))
          else
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(t('الرئيس: ${h.name}', 'Head: ${h.name}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              if (h.acting) ...[
                const ActingChip(),
                AppBadgePill(t('استبدله', 'Replace'), color: c.warning, icon: Icons.swap_horiz_rounded),
              ],
            ]),
          const SizedBox(height: AppSpace.sm),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (onPick != null)
              AppButton.secondary(
                  key: const ValueKey('heads.pick'),
                  size: AppButtonSize.sm,
                  icon: Icons.person_search_rounded,
                  label: h == null ? t('اختر رئيساً', 'Choose a head') : t('تغيير', 'Change'),
                  onPressed: onPick),
            AssignMeChip(selected: ch?.me == true, meName: meName, label: t('عيّنّي', 'Assign me'), onTap: onMe),
            if (onUndo != null) AppButton.ghost(key: const ValueKey('heads.undo'), size: AppButtonSize.sm, label: t('تراجع', 'Undo'), onPressed: onUndo),
          ]),
          if (error) HeadErrorText(t('تعذّر تعيين هذا الرئيس — اختر عضواً آخر', 'This head could not be assigned: pick another member')),
        ]),
      ),
    );
  }
}

/// Step 5: the optional pages, each opened on its own (all skippable).
class OptionalStepView extends StatelessWidget {
  const OptionalStepView({super.key, required this.onOpen});
  final ValueChanged<String> onOpen;

  static const keys = ['members', 'routing', 'meetings', 'deadlines'];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    (IconData, String, String) info(String k) => switch (k) {
          'members' => (Icons.groups_rounded, t('فريق العمل', 'Team members'), t('ادعُ الوكلاء والرؤساء والموظفين.', 'Invite vice deans, heads and staff.')),
          'routing' => (Icons.alt_route_rounded, t('مسارات الإحالة', 'Routing rules'), t('أين تذهب الطلبات بين الجهات.', 'Where requests may travel between units.')),
          'meetings' => (Icons.event_repeat_rounded, t('أيام الاجتماعات', 'Meeting days'), t('جلسات المجالس ومواعيدها.', 'When the councils hold their sessions.')),
          _ => (Icons.timer_outlined, t('مهل المراجعة', 'Review deadlines'), t('كم ساعة قبل التذكير والتصعيد.', 'How long before a reminder and escalation.')),
        };
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpace.xl),
      children: [
        OrgSectionHeading(t('إضافات اختيارية', 'Optional extras'),
            subtitle: t('كلها اختيارية ويمكن تركها الآن — الإعدادات الافتراضية تعمل جيداً.',
                'All of these can wait: the defaults work well. Open any of them, or just continue.')),
        OrgGrid(minTile: 280, children: [
          for (final k in keys)
            Material(
              key: ValueKey('optional.$k'),
              color: c.cardBg,
              shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: BorderSide(color: c.divider, width: AppBorder.hairline)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onOpen(k),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: AppTouch.min,
                      height: AppTouch.min,
                      decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.control)),
                      child: Icon(info(k).$1, color: c.primary, size: AppIconSize.lg),
                    ),
                    AppSpace.gapSm,
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(info(k).$2, style: AppType.section(context)),
                        const SizedBox(height: AppSpace.xxs),
                        Text(info(k).$3, style: AppType.body(context).copyWith(color: c.textMedium)),
                      ]),
                    ),
                    AppSpace.gapXs,
                    Icon(Icons.open_in_new_rounded, size: AppIconSize.md, color: c.textLight),
                  ]),
                ),
              ),
            ),
        ]),
      ],
    );
  }
}

/// Step 6: the readiness list grouped Block / Warn; each item's button jumps to its step.
class ReviewStepView extends StatelessWidget {
  const ReviewStepView({super.key, required this.readiness, required this.onJump, this.onQuickFix, this.fixing = false});
  final InstitutionReadiness readiness;
  final ValueChanged<String> onJump;

  /// An item with a ready-made `fix` (the missing core departments): one tap applies it.
  final ValueChanged<ReadinessItem>? onQuickFix;
  final bool fixing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final blocks = readiness.blockItems, warns = readiness.warnItems;
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpace.xl),
      children: [
        OrgSectionHeading(t('المراجعة والإطلاق', 'Review & launch'),
            subtitle: t('الإطلاق يجعل مؤسستك تعمل: الإدارات والرؤساء والمجالس تبدأ في استقبال الطلبات.',
                'Launching puts your institution to work: departments, heads and councils start receiving requests.')),
        if (readiness.canLaunch)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: AppBlock(
              key: const ValueKey('review.ready'),
              tone: AppBlockTone.emerald,
              child: Builder(builder: (context) {
                final b = AppBlock.colorsOf(context);
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.verified_rounded, color: b.accentInk(c.success), size: AppIconSize.xl),
                  AppSpace.gapMd,
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t('كل شيء جاهز', 'Everything is ready'), style: AppType.headline(context).copyWith(color: b.ink)),
                      const SizedBox(height: AppSpace.xxs),
                      Text(
                          warns.isEmpty
                              ? t('لا شيء ينقص. اضغط «إطلاق» حين تكون مستعداً.', 'Nothing is missing. Press Launch when you are ready.')
                              : t('يمكنك الإطلاق الآن، والنقاط أدناه تستحق نظرة لاحقاً.', 'You can launch now; the points below are worth a look later.'),
                          style: AppType.body(context).copyWith(color: b.muted)),
                    ]),
                  ),
                ]);
              }),
            ),
          ),
        if (blocks.isNotEmpty) ...[
          OrgSectionHeading(t('يجب إكماله قبل الإطلاق', 'Needed before launch'),
              subtitle: t('يُفتح زر الإطلاق حين تكتمل هذه القائمة.', 'Launch unlocks once this list is clear.')),
          for (final x in blocks) _item(x),
        ],
        if (warns.isNotEmpty) ...[
          OrgSectionHeading(t('يستحق نظرة', 'Worth a look'), subtitle: t('لا يمنع الإطلاق.', 'These do not stop the launch.')),
          for (final x in warns) _item(x),
        ],
      ],
    );
  }

  Widget _item(ReadinessItem x) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.xxs),
        child: ReadinessRow(
            key: ValueKey('review.item.${x.key}'),
            item: x,
            onFix: () => onJump(x.action),
            fixing: fixing,
            onQuickFix: x.fix != null && onQuickFix != null ? () => onQuickFix!(x) : null),
      );
}

class ReadinessRow extends StatelessWidget {
  const ReadinessRow({super.key, required this.item, required this.onFix, this.onQuickFix, this.fixing = false});
  final ReadinessItem item;
  final VoidCallback onFix;
  final VoidCallback? onQuickFix;
  final bool fixing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = item.blocks ? c.danger : c.warning;
    return Material(
      color: c.cardBg,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: BorderSide(color: c.divider, width: AppBorder.hairline)),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.sm),
        child: Row(children: [
          Icon(item.blocks ? Icons.error_outline_rounded : Icons.info_outline_rounded, color: tone, size: AppIconSize.lg),
          AppSpace.gapSm,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.text, style: AppType.row(context)),
              const SizedBox(height: AppSpace.xxs),
              Text(wizardStepLabel(institutionWizardSteps[wizardStepOfAction(item.action)]), style: AppType.meta(context).copyWith(color: c.textMedium)),
              if (onQuickFix != null) ...[
                AppSpace.gapXs,
                AppButton.tonal(
                    key: const ValueKey('review.quick_fix'),
                    size: AppButtonSize.sm,
                    icon: Icons.add_task_rounded,
                    busy: fixing,
                    label: t('أنشئ الإدارات الأساسية', 'Create core departments'),
                    onPressed: fixing ? null : onQuickFix),
              ],
            ]),
          ),
          if (item.count > 0) ...[AppSpace.gapXs, AppBadgePill('${item.count}', color: tone)],
          AppSpace.gapXs,
          AppButton.ghost(key: const ValueKey('review.fix'), size: AppButtonSize.sm, label: t('إصلاح', 'Fix'), onPressed: onFix),
        ]),
      ),
    );
  }
}

/// After the launch: calm, one clear way on.
class LaunchedView extends StatelessWidget {
  const LaunchedView({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget next(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: AppSpace.sm),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: AppIconSize.md, color: c.primary),
            AppSpace.gapSm,
            Expanded(child: Text(text, style: AppType.body(context))),
          ]),
        );
    return ListView(
      key: const ValueKey('wizard.launched'),
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.lg, AppSpace.md, AppSpace.xl),
      children: [
        AppBlock(
          tone: AppBlockTone.emerald,
          hero: true,
          wash: true,
          child: Builder(builder: (context) {
            final b = AppBlock.colorsOf(context);
            return Column(children: [
              Icon(Icons.celebration_rounded, size: AppIconSize.hero, color: b.accentInk(c.success)),
              AppSpace.gapMd,
              Text(t('مؤسستك تعمل الآن', 'Your institution is live'), textAlign: TextAlign.center, style: AppType.display(context).copyWith(color: b.ink)),
              AppSpace.gapXs,
              Text(t('الإدارات والرؤساء والمجالس جاهزة لاستقبال الطلبات.', 'Departments, heads and councils are ready to receive requests.'),
                  textAlign: TextAlign.center, style: AppType.body(context).copyWith(color: b.muted)),
            ]);
          }),
        ),
        AppSpace.gapLg,
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('ما التالي؟', 'What next?'), style: AppType.section(context)),
            next(Icons.person_add_alt_1_rounded, t('ادعُ الأعضاء أو شارك كود الانضمام.', 'Invite members, or share the join code.')),
            next(Icons.inbox_rounded, t('تابع الطلبات من الصفحة الرئيسية.', 'Follow requests from the Home.')),
            next(Icons.tune_rounded, t('كل خطوة قابلة للتعديل لاحقاً من الإعدادات.', 'Every step can be changed later from Settings.')),
          ]),
        ),
        AppSpace.gapLg,
        Center(child: AppButton.primary(key: const ValueKey('wizard.done'), label: t('العودة إلى الرئيسية', 'Back to Home'), onPressed: onDone)),
      ],
    );
  }
}

/// The Home's "Set up your institution" card: progress n / 6, the next step, Continue.
class InstitutionSetupCard extends StatelessWidget {
  const InstitutionSetupCard({super.key, required this.state, required this.onContinue, this.onRoadmap});
  final InstitutionWizardState state;
  final VoidCallback onContinue;

  /// Opens the institution roadmap (phase 5); null = no button.
  final VoidCallback? onRoadmap;

  @override
  Widget build(BuildContext context) {
    final n = institutionWizardSteps.length;
    final started = state.doneCount > 0 || state.stepIndex > 0;
    return AppBlock(
      key: const ValueKey('inst.wizard.card'),
      tone: AppBlockTone.sky,
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.md),
      child: Builder(builder: (context) {
        final b = AppBlock.colorsOf(context);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('جهّز مؤسستك التعليمية', 'Set up your institution'), style: AppType.headline(context).copyWith(color: b.ink)),
          const SizedBox(height: AppSpace.xxs),
          Text(t('${state.doneCount} من $n خطوات مكتملة · التالي: ${wizardStepLabel(institutionWizardSteps[state.stepIndex])}',
                  '${state.doneCount} of $n steps done · Next: ${wizardStepLabel(institutionWizardSteps[state.stepIndex])}'),
              style: AppType.meta(context).copyWith(color: b.muted)),
          AppSpace.gapSm,
          AppFill(
            value: state.progress,
            builder: (context, v) => ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                key: const ValueKey('inst.wizard.progress'),
                value: v,
                minHeight: AppSpace.xxs,
                backgroundColor: context.colors.cardBg,
                color: context.colors.success,
              ),
            ),
          ),
          AppSpace.gapSm,
          Text(t('الأقسام والرؤساء والمجالس في دقائق، خطوة بخطوة. يمكنك التوقف والعودة في أي وقت.',
                  'Departments, heads and councils in a few minutes, step by step. Stop and come back any time.'),
              style: AppType.body(context).copyWith(color: b.ink)),
          AppSpace.gapMd,
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            AppButton.primary(
                key: const ValueKey('inst.wizard.continue'),
                label: started ? t('متابعة', 'Continue') : t('ابدأ', 'Start'),
                trailingIcon: Icons.arrow_forward_rounded,
                onPressed: onContinue),
            // Phase 5 (D-994): the five stages with their warnings and the next-best action
            if (onRoadmap != null)
              AppButton.ghost(key: const ValueKey('inst.roadmap.open'), label: t('عرض الخريطة', 'See the roadmap'), icon: Icons.route_rounded, onPressed: onRoadmap),
          ]),
        ]);
      }),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The page
// ═════════════════════════════════════════════════════════════════════════════

String institutionWizardTitle() => t('معالج إعداد المؤسسة', 'Setup wizard');

/// Pushes the wizard with the dashboard's header (the Home card, the roadmap and the Settings entry); [step] opens it
/// on that step (the roadmap's next-best action) instead of the stored one.
Future<void> openInstitutionWizard(BuildContext context, {String? step}) =>
    orgPush(context, institutionWizardTitle(), OrgInstitutionWizard(initialStep: step), width: AppWidth.content, helpPageId: 'org.settings');

class OrgInstitutionWizard extends StatefulWidget {
  const OrgInstitutionWizard({super.key, this.onLaunched, this.initialStep});

  /// Opens on this step (`basics` … `review`) instead of the stored one; unknown → the stored one.
  final String? initialStep;

  /// After a launch, "Back to Home" (default: pop).
  final VoidCallback? onLaunched;

  @override
  State<OrgInstitutionWizard> createState() => _OrgInstitutionWizardState();
}

class _OrgInstitutionWizardState extends State<OrgInstitutionWizard> {
  bool _loading = true, _failed = false, _missing = false, _busy = false;
  int _index = 0, _reached = 0;
  Set<String> _done = {};
  String? _launchedAt;
  InstitutionReadiness? _readiness;

  // per step
  bool _stepLoading = false, _stepFailed = false;
  StudySystemInfo? _study;
  StudySystem? _pick;
  bool _graduate = false;
  DeptCatalog? _catalog;
  CatalogSelection _sel = CatalogSelection();
  bool _academic = false;
  final _nameAr = TextEditingController(), _nameEn = TextEditingController();
  List<HeadUnit>? _heads;
  HeadsDraft _headsDraft = const HeadsDraft();
  Set<int> _headErrors = {};
  CouncilsSetup? _councils;
  CouncilsDraft _councilsDraft = const CouncilsDraft();
  String _councilsSaved = '';
  String? _chairError;

  OrgSession get _s => context.read<OrgSession>();
  InstitutionWizardApi get _api => InstitutionWizardApi(_s);
  String get _key => institutionWizardSteps[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nameAr.dispose();
    _nameEn.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final r = await _api.state();
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _loading = false;
        _failed = true;
        _missing = r.endpointMissing;
      });
      return;
    }
    final w = InstitutionWizardState.fromJson(r.map);
    setState(() {
      _loading = false;
      final asked = institutionWizardSteps.indexOf(widget.initialStep ?? '');
      _index = asked >= 0 ? asked : w.stepIndex;
      _done = {...w.done};
      _launchedAt = w.launchedAt;
      _readiness = w.readiness;
      _reached = _reachOf(_index);
    });
    _enter(_index);
  }

  /// The furthest step the strip lets one tap: the current one, and one past every step done.
  int _reachOf(int i) {
    var r = i;
    for (var k = 0; k < institutionWizardSteps.length; k++) {
      if (_done.contains(institutionWizardSteps[k]) && k + 1 > r) r = k + 1;
    }
    return r.clamp(0, institutionWizardSteps.length - 1);
  }

  /// Loads what the step shows. Heads, councils and the review follow the earlier steps, so they load on every visit.
  Future<void> _enter(int i) async {
    final key = institutionWizardSteps[i];
    final need = switch (key) {
      'basics' => _study == null,
      'departments' => _catalog == null,
      'heads' || 'councils' || 'review' => true,
      _ => false,
    };
    if (!need) {
      setState(() => _stepFailed = false);
      return;
    }
    setState(() {
      _stepLoading = true;
      _stepFailed = false;
    });
    final s = _s;
    final OrgCall r = switch (key) {
      'basics' => await orgCall(() => s.api.get('${s.base}/study-system'), quiet: true),
      'departments' => await orgCall(() => s.api.get('${s.base}/dept-catalog'), quiet: true),
      'heads' => await _api.heads(),
      'councils' => await _councilsCall(),
      _ => await _api.state(),
    };
    if (!mounted || _key != key) return;
    setState(() {
      _stepLoading = false;
      if (!r.ok) {
        _stepFailed = true;
        return;
      }
      switch (key) {
        case 'basics':
          final info = StudySystemInfo.fromJson(r.map);
          _study = info;
          _pick = info.stored ?? info.effective;
          _graduate = info.hasGraduatePrograms;
        case 'departments':
          _takeCatalog(DeptCatalog.fromJson(r.map));
        case 'heads':
          _heads = headUnitsOf(r.data);
          _headsDraft = const HeadsDraft();
          _headErrors = {};
        case 'councils':
          _takeCouncils(CouncilsSetup.fromJson(r.map));
        case 'review':
          final w = InstitutionWizardState.fromJson(r.map);
          _readiness = w.readiness;
          _launchedAt = w.launchedAt;
      }
    });
  }

  Future<OrgCall> _councilsCall() {
    final id = govOrgId(context) ?? _s.currentId ?? 0;
    return orgCall(() => GovApi(id).councilsSetup(), quiet: true);
  }

  void _takeCatalog(DeptCatalog c) {
    _catalog = c;
    _sel = CatalogSelection.initial(c);
    _nameAr.clear();
    _nameEn.clear();
  }

  void _takeCouncils(CouncilsSetup s) {
    _councils = s;
    var d = CouncilsDraft.from(s);
    _councilsSaved = jsonEncode(d.toBody());
    // safe default while unanswered: department councils when there are academic departments, else none for now
    if (d.want == null) d = s.departments.isNotEmpty ? d.pick(CouncilsMode.departments, s.departments) : d.answer(false);
    _councilsDraft = d;
    _chairError = null;
  }

  // ── saving each step ─────────────────────────────────────────────────────

  /// Saves what the step changed; false = stay on it (the reason was shown).
  Future<bool> _saveStep() async {
    final s = _s;
    switch (_key) {
      case 'basics':
        final i = _study;
        if (i == null) return true;
        if (_pick == i.stored && _graduate == i.hasGraduatePrograms) return true;
        final r = await orgCall(() => s.api.put('${s.base}/study-system', body: studySystemBody(_pick, graduate: _graduate)), quiet: true);
        if (!r.ok) return _fail(r);
        final info = StudySystemInfo.fromJson(r.map);
        _study = info;
        _pick = info.stored ?? info.effective;
        _graduate = info.hasGraduatePrograms;
        _catalog = null; // the minimum set follows the study system
        return true;
      case 'departments':
        final c = _catalog;
        if (c == null || _sel.isEmpty || !c.canApply) return true;
        _sel
          ..academicNameAr = _nameAr.text
          ..academicNameEn = _nameEn.text;
        final why = _sel.problem();
        if (why != null) {
          showAppNotice(why, error: true);
          return false;
        }
        final r = await orgCall(() => s.api.post('${s.base}/dept-catalog/apply', body: _sel.toApplyBody(c)), quiet: true);
        if (!r.ok) return _fail(r);
        if (asMap(r.map['catalog']).isNotEmpty) _takeCatalog(DeptCatalog.fromJson(asMap(r.map['catalog'])));
        final made = asMapList(r.map['created']).length;
        if (made > 0) showAppNotice(t('أُنشئت $made من الإدارات', '$made departments created'));
        return true;
      case 'heads':
        if (_headsDraft.isEmpty) return true;
        final r = await _api.saveHeads(_headsDraft);
        if (!r.ok) {
          if (r.code == 'head_invalid' || r.code == 'dept_invalid') setState(() => _headErrors = headInvalidIds(r.detail));
          return _fail(r);
        }
        _heads = headUnitsOf(r.data);
        _headsDraft = const HeadsDraft();
        _headErrors = {};
        return true;
      case 'councils':
        final st = _councils;
        final id = govOrgId(context);
        if (st == null || id == null) return true;
        final why = _councilsDraft.problem(st.departments);
        if (why != null) {
          setState(() => _chairError = _councilsDraft.chairProblem);
          showAppNotice(why, error: true);
          return false;
        }
        if (!st.derived && jsonEncode(_councilsDraft.toBody()) == _councilsSaved) return true;
        final r = await orgCall(() => GovApi(id).saveCouncilsSetup(_councilsDraft.toBody()), quiet: true);
        if (!r.ok) {
          if (r.code == 'head_required') setState(() => _chairError = chairRequiredText());
          showAppNotice(r.code == 'council_has_open_agenda' ? councilsOpenAgendaText(r.detail) : orgErrorText(r.error!), error: true);
          return false;
        }
        _takeCouncils(CouncilsSetup.fromJson(r.map));
        return true;
      default:
        return true;
    }
  }

  bool _fail(OrgCall r) {
    showAppNotice(orgErrorText(r.error!), error: true);
    return false;
  }

  Future<void> _next() async {
    if (_key == 'review') return _launch();
    setState(() => _busy = true);
    final ok = await _saveStep();
    if (!mounted) return;
    if (!ok) {
      setState(() => _busy = false);
      return;
    }
    final done = {..._done, _key};
    final to = _index + 1;
    // the resume point; a failed PUT only costs the resume, never the step
    await _api.saveState(institutionWizardSteps[to], done);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _done = done;
      _index = to;
      _reached = _reachOf(to);
    });
    _enter(to);
  }

  void _go(int i) {
    if (i == _index || _busy) return;
    setState(() {
      _index = i;
      _reached = _reachOf(i) > _reached ? _reachOf(i) : _reached;
    });
    _enter(i);
  }

  Future<void> _launch() async {
    final rd = _readiness;
    if (rd == null || !rd.canLaunch) return;
    final sure = await appConfirm(context,
        confirmLabel: t('إطلاق', 'Launch'),
        message: t('إطلاق المؤسسة الآن؟ يمكنك تعديل كل شيء لاحقاً من الإعدادات.', 'Launch the institution now? You can change everything later from Settings.'));
    if (!sure || !mounted) return;
    setState(() => _busy = true);
    final r = await _api.launchInstitution();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _launchedAt = asStr(r.map['launched_at'], DateTime.now().toUtc().toIso8601String());
        _done = {...institutionWizardSteps};
      } else if (r.code == 'not_ready') {
        _readiness = InstitutionReadiness.fromItems(asMapList(r.detail['items']));
      }
    });
    if (!r.ok) showAppNotice(orgErrorText(r.error!), error: true);
  }

  bool _fixing = false;

  /// `core_missing`: POST its `fix` to dept-catalog/apply, then read the readiness again.
  Future<void> _quickFix(ReadinessItem x) async {
    final s = _s;
    setState(() => _fixing = true);
    final r = await orgCall(() => s.api.post('${s.base}/dept-catalog/apply', body: x.fix), quiet: true);
    if (!mounted) return;
    setState(() => _fixing = false);
    if (!r.ok) {
      _fail(r);
      return;
    }
    _catalog = null; // the departments step shows them created
    showAppNotice(t('أُنشئت الإدارات الأساسية', 'Core departments created'));
    _enter(_index);
  }

  // ── optional pages ───────────────────────────────────────────────────────

  void _openOptional(String key) {
    final (section, sub) = switch (key) {
      'members' => ('people', 'members'),
      'meetings' => ('services', 'councils'),
      _ => ('services', 'gov_settings'), // routing rules and the review deadlines (SLA) live on one page
    };
    OrgTabs? tabs;
    try {
      tabs = context.read<OrgTabs>();
    } catch (_) {}
    final x = tabs?.subOf(section, sub);
    if (x == null) {
      showAppNotice(t('هذه الصفحة غير متاحة لك هنا', 'This page is not available here'), error: true);
      return;
    }
    orgPush(context, x.$2, x.$4);
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading || _failed) {
      if (_failed && _missing) {
        return OrgEmpty(
            icon: Icons.cloud_off_rounded,
            title: t('يحتاج تحديثاً للخادم', 'Needs a server update'),
            message: t('معالج الإعداد غير متاح على هذا الخادم بعد.', 'The setup wizard is not on this server yet.'));
      }
      return OrgAsync(loading: _loading, failed: _failed, onRetry: _load, child: const SizedBox.shrink());
    }
    if (_launchedAt != null && _key == 'review') {
      return LaunchedView(onDone: widget.onLaunched ?? () => Navigator.of(context).maybePop());
    }
    final rd = _readiness;
    final review = _key == 'review';
    final nextLabel = switch (_key) {
      'review' => t('إطلاق المؤسسة', 'Launch institution'),
      'optional' => t('متابعة', 'Continue'),
      'departments' when _catalog != null && _catalog!.canApply && _sel.count > 0 => t('إنشاء ${_sel.count} ومتابعة', 'Create ${_sel.count} and continue'),
      _ => t('حفظ ومتابعة', 'Save and continue'),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxs),
        child: WizardStepStrip(current: _index, done: _done, reached: _reached, onTap: _go),
      ),
      Expanded(child: _stepBody()),
      WizardNavBar(
        nextLabel: nextLabel,
        nextIcon: review ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded,
        busy: _busy,
        onBack: _index == 0 ? null : () => _go(_index - 1),
        onNext: _stepLoading || _stepFailed || (review && (rd == null || !rd.canLaunch)) ? null : _next,
      ),
    ]);
  }

  Widget _stepBody() {
    if (_stepLoading || _stepFailed) {
      return OrgAsync(loading: _stepLoading, failed: _stepFailed, onRetry: () => _enter(_index), child: const SizedBox.shrink());
    }
    switch (_key) {
      case 'basics':
        final i = _study;
        if (i == null) return const SizedBox.shrink();
        return StudySystemView(
          info: i,
          selected: _pick,
          graduate: _graduate,
          onPick: (v) => setState(() => _pick = v),
          onGraduate: (v) => setState(() => _graduate = v),
          onSave: () {},
        );
      case 'departments':
        final c = _catalog;
        if (c == null) return const SizedBox.shrink();
        return DeptCatalogView(
          catalog: c,
          selection: _sel,
          academic: _academic,
          embedded: true,
          intro: const DeptKindsIntro(),
          nameAr: _nameAr,
          nameEn: _nameEn,
          onGroup: (v) => setState(() => _academic = v),
          onToggle: (x) => setState(() => _sel.toggle(x)),
          onToggleType: (x, k) => setState(() => _sel.toggleType(x, k)),
          onCreate: _next,
          onCustom: () async {
            if (await showDepartmentWizard(context)) {
              setState(() => _catalog = null);
              _enter(_index);
            }
          },
        );
      case 'heads':
        final oid = govOrgId(context);
        return HeadsStepView(
          rows: _heads ?? const [],
          draft: _headsDraft,
          meName: currentPerson(context).$2,
          errors: _headErrors,
          onChanged: (d) => setState(() => _headsDraft = d),
          onPick: oid == null ? null : (u) => pickOrgMember(context, oid, title: t('رئيس ${u.name}', 'Head of ${u.name}')),
        );
      case 'councils':
        final st = _councils;
        if (st == null) return const SizedBox.shrink();
        final oid = govOrgId(context);
        return CouncilsChoiceView(
          setup: st,
          draft: _councilsDraft,
          meName: currentPerson(context).$2,
          chairError: _chairError,
          onChanged: (d) => setState(() {
            _councilsDraft = d;
            if (_chairError != null) _chairError = d.chairProblem;
          }),
          pickPerson: oid == null ? null : (title, exclude) => pickOrgMember(context, oid, title: title, exclude: exclude),
        );
      case 'optional':
        return OptionalStepView(onOpen: _openOptional);
      default:
        return ReviewStepView(
            readiness: _readiness ?? const InstitutionReadiness(),
            onJump: (a) => _go(wizardStepOfAction(a)),
            onQuickFix: _quickFix,
            fixing: _fixing);
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The Home card
// ═════════════════════════════════════════════════════════════════════════════

/// The Home's wizard card. The old checklist draws it in its place when GET …/setup says `wizard: {applicable: true,
/// launched: false}` (so no other organization pays a request); this asks GET …/institution/wizard for the progress.
/// A failed call or a launched wizard draws nothing.
class OrgInstitutionSetupCard extends StatefulWidget {
  const OrgInstitutionSetupCard({super.key, required this.orgId, required this.onOpen, this.fallback, this.roadmap = true});

  /// Drawn when the card draws nothing (a failed call, a healthy launched institution): the old checklist.
  final Widget? fallback;

  /// The "See the roadmap" button (phase 5).
  final bool roadmap;
  final int orgId;

  /// Opens the wizard; the card asks again when it returns.
  final Future<void> Function() onOpen;

  @override
  State<OrgInstitutionSetupCard> createState() => _OrgInstitutionSetupCardState();
}

class _OrgInstitutionSetupCardState extends State<OrgInstitutionSetupCard> {
  InstitutionWizardState? _state;
  InstitutionHealth? _health;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OrgInstitutionSetupCard old) {
    super.didUpdateWidget(old);
    if (old.orgId != widget.orgId) {
      _state = null;
      _health = null;
      _loaded = false;
      _load();
    }
  }

  Future<void> _load() async {
    final id = widget.orgId;
    final r = await orgCall(() => ApiClient().get('/api/v1/org/orgs/$id/institution/wizard'), quiet: true);
    if (!mounted || id != widget.orgId) return;
    final st = r.ok ? InstitutionWizardState.fromJson(r.map) : null;
    // phase 6: a launched institution asks for its health (score + top issue); an older server → the roadmap card
    InstitutionHealth? health;
    if (st != null && st.applicable && st.launched && institutionWizardAllowed()) {
      final h = await orgCall(() => ApiClient().get('/api/v1/org/orgs/$id/institution/health'), quiet: true);
      if (!mounted || id != widget.orgId) return;
      health = h.ok ? InstitutionHealth.fromJson(h.map) : null;
    }
    setState(() {
      _loaded = true;
      _state = st;
      _health = health;
    });
  }

  Future<void> _openHealth(InstitutionHealth h) async {
    await openInstitutionHealth(context, widget.orgId, initial: h);
    if (mounted) _load();
  }

  Future<void> _open() async {
    await widget.onOpen();
    if (mounted) _load();
  }

  Future<void> _openStage(InstitutionStage s) async {
    await openInstitutionWizard(context, step: s.wizardStep);
    if (mounted) _load();
  }

  Future<void> _openRoadmap(InstitutionWizardState st) async {
    // the page starts from THIS answer: no second request on open
    await openInstitutionRoadmap(context, widget.orgId, initial: st);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final st = _state;
    if (!_loaded) return const SizedBox.shrink();
    if (st == null) return widget.fallback ?? const SizedBox.shrink();
    // after the launch (phase 5): the institution's health while a stage warns, else the caller's fallback
    if (st.applicable && st.launched) {
      final h = _health;
      if (h != null) {
        // the health answer leads (phase 6): calm → the caller's fallback, else the score and the top issue
        if (h.calm) return widget.fallback ?? const SizedBox.shrink();
        return ParentComponent(
          featureKey: orgInstitutionFeatureKey,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.lg),
            child: InstitutionHealthCard(health: h, onOpen: () => _openHealth(h)),
          ),
        );
      }
      final stages = institutionStagesOf(st);
      if (institutionHealthy(stages) || !institutionWizardAllowed()) return widget.fallback ?? const SizedBox.shrink();
      return ParentComponent(
        featureKey: orgInstitutionFeatureKey,
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.lg),
          child: InstitutionRoadmapCard(state: st, onOpenStage: _openStage, onOpenPage: () => _openRoadmap(st)),
        ),
      );
    }
    if (!st.showCard) return widget.fallback ?? const SizedBox.shrink();
    return ParentComponent(
      featureKey: orgInstitutionFeatureKey,
      child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.lg),
          child: InstitutionSetupCard(state: st, onContinue: _open, onRoadmap: widget.roadmap ? () => _openRoadmap(st) : null)),
    );
  }
}
