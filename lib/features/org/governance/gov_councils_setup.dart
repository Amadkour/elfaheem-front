// lib/features/org/governance/gov_councils_setup.dart
//
// Institutions v2, phase 3: the councils question (plan docs/institutions/V2_PLAN.md item 3, back D-989 – D-990).
//   GET|PUT …/governance/councils-setup   mode none · faculty · departments · both, the chosen departments,
//                                          "new departments get a council" (auto_new), the Faculty Council's people
//   CouncilsMode · CouncilsSetup · CouncilDeptRow · FacultyCouncilInfo   the payload
//   CouncilsDraft                          what the person is choosing: the answers, the PUT body, the problem
//   CouncilsChoiceView                     plain values: Q1 yes / no, Q2 which councils, the faculty people, the
//                                          department tick cards (Phase 4 embeds it as a wizard step)
//   OrgCouncilsSetupPage                   load · save (409 council_has_open_agenda names the councils)
//   openCouncilsSetup                      pushes the page on its own (from the councils list)
// Tested in test/org/institutions_v2_p3_test.dart.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import '../org_page_header.dart' show OrgPushedPage;
import '../org_page_kit.dart';
import '../org_ui.dart' show OrgAsync, OrgGrid;
import '../org_unit_rules.dart' show AssignMeChip, HeadErrorText, UnitHead, UnitHeadLine, currentPerson, unitHeadOf;
import '../org_v3.dart' show orgCall, orgCodeText, orgErrorText;
import 'gov_api.dart';
import 'gov_council_ui.dart' show govOrgId, pickOrgMember;
import 'gov_models.dart' show GovUser;

// ═════════════════════════════════════════════════════════════════════════════
//  Payload
// ═════════════════════════════════════════════════════════════════════════════

enum CouncilsMode { none, faculty, departments, both }

CouncilsMode? councilsModeOf(Object? v) => switch ('$v') {
      'none' => CouncilsMode.none,
      'faculty' => CouncilsMode.faculty,
      'departments' => CouncilsMode.departments,
      'both' => CouncilsMode.both,
      _ => null,
    };

bool modeHasFaculty(CouncilsMode? m) => m == CouncilsMode.faculty || m == CouncilsMode.both;
bool modeHasDepts(CouncilsMode? m) => m == CouncilsMode.departments || m == CouncilsMode.both;

/// One academic department of the setup.
class CouncilDeptRow {
  const CouncilDeptRow({
    required this.id,
    required this.name,
    this.head,
    this.hasCouncil = false,
    this.councilId,
    this.openAgendaItems = 0,
    this.selected = false,
  });

  final int id;
  final String name;
  final UnitHead? head;
  final bool hasCouncil, selected;
  final int? councilId;
  final int openAgendaItems;

  /// Its council has open agenda items: it cannot lose its council now (server 409 `council_has_open_agenda`).
  bool get locked => hasCouncil && openAgendaItems > 0;

  factory CouncilDeptRow.fromJson(Map<String, dynamic> j) => CouncilDeptRow(
        id: asInt(j['id']),
        name: '${j['name'] ?? ''}',
        head: unitHeadOf(j),
        hasCouncil: j['has_council'] == true,
        councilId: j['council_id'] == null ? null : asInt(j['council_id']),
        openAgendaItems: asInt(j['open_agenda_items']),
        selected: j['selected'] == true,
      );
}

/// The Faculty Council as it stands (null in the payload = there is none).
class FacultyCouncilInfo {
  const FacultyCouncilInfo({required this.id, this.chair, this.secretary, this.members = const []});
  final int id;
  final GovUser? chair, secretary;
  final List<GovUser> members;

  factory FacultyCouncilInfo.fromJson(Map<String, dynamic> j) => FacultyCouncilInfo(
        id: asInt(j['id']),
        chair: GovUser.from(j['chair']),
        secretary: GovUser.from(j['secretary']),
        members: [for (final m in asMapList(j['members'])) ?GovUser.from(m)],
      );
}

/// GET …/governance/councils-setup.
class CouncilsSetup {
  const CouncilsSetup({
    this.mode = CouncilsMode.none,
    this.deptIds = const [],
    this.autoNew = false,
    this.derived = false,
    this.faculty,
    this.departments = const [],
  });

  final CouncilsMode mode;
  final List<int> deptIds;
  final bool autoNew;

  /// Not saved yet: worked out from the councils that exist.
  final bool derived;
  final FacultyCouncilInfo? faculty;
  final List<CouncilDeptRow> departments;

  factory CouncilsSetup.fromJson(Map<String, dynamic> j) => CouncilsSetup(
        mode: councilsModeOf(j['mode']) ?? CouncilsMode.none,
        deptIds: [for (final v in (j['dept_ids'] is List ? j['dept_ids'] as List : const [])) asInt(v)],
        autoNew: j['auto_new'] == true,
        derived: j['derived'] == true,
        faculty: asMap(j['faculty']).isEmpty ? null : FacultyCouncilInfo.fromJson(asMap(j['faculty'])),
        departments: [for (final d in asMapList(j['departments'])) CouncilDeptRow.fromJson(d)],
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Draft
// ═════════════════════════════════════════════════════════════════════════════

/// The answers being given. Immutable: every change returns a new draft.
class CouncilsDraft {
  const CouncilsDraft({
    this.want,
    this.mode,
    this.deptIds = const {},
    this.autoNew = false,
    this.chair,
    this.chairSelf = false,
    this.secretary,
    this.members = const [],
  });

  /// Q1: null = not answered yet.
  final bool? want;

  /// Q2 (when [want]): null = not answered yet.
  final CouncilsMode? mode;
  final Set<int> deptIds;
  final bool autoNew;
  final GovUser? chair, secretary;

  /// The caller chairs the Faculty Council (`head_self: true`).
  final bool chairSelf;
  final List<GovUser> members;

  /// A saved setup is answered; a derived one with no council asks Q1 again.
  factory CouncilsDraft.from(CouncilsSetup s) {
    final f = s.faculty;
    return CouncilsDraft(
      want: s.mode != CouncilsMode.none ? true : (s.derived ? null : false),
      mode: s.mode == CouncilsMode.none ? null : s.mode,
      deptIds: {...s.deptIds, for (final d in s.departments) if (d.selected) d.id},
      autoNew: s.autoNew,
      chair: f?.chair,
      secretary: f?.secretary,
      members: [for (final m in f?.members ?? const <GovUser>[]) if (m.id != f?.chair?.id) m],
    );
  }

  CouncilsDraft copyWith({
    bool? want,
    CouncilsMode? mode,
    Set<int>? deptIds,
    bool? autoNew,
    GovUser? chair,
    bool clearChair = false,
    bool? chairSelf,
    GovUser? secretary,
    bool clearSecretary = false,
    List<GovUser>? members,
  }) =>
      CouncilsDraft(
        want: want ?? this.want,
        mode: mode ?? this.mode,
        deptIds: deptIds ?? this.deptIds,
        autoNew: autoNew ?? this.autoNew,
        chair: clearChair ? null : (chair ?? this.chair),
        chairSelf: chairSelf ?? this.chairSelf,
        secretary: clearSecretary ? null : (secretary ?? this.secretary),
        members: members ?? this.members,
      );

  /// The mode the PUT sends; null while a question is open.
  CouncilsMode? get effectiveMode => want == false ? CouncilsMode.none : (want == true ? mode : null);

  CouncilsDraft answer(bool yes) => copyWith(want: yes);

  /// Picks Q2. The first time department councils are chosen with nothing ticked, every department is ticked.
  CouncilsDraft pick(CouncilsMode m, List<CouncilDeptRow> rows) {
    final ids = modeHasDepts(m) && deptIds.isEmpty ? {for (final d in rows) d.id} : deptIds;
    return copyWith(want: true, mode: m, deptIds: ids);
  }

  /// Ticks / unticks one department; a locked one that has its council stays ticked.
  CouncilsDraft toggle(CouncilDeptRow d) {
    if (deptIds.contains(d.id)) {
      if (d.locked) return this;
      return copyWith(deptIds: {...deptIds}..remove(d.id));
    }
    return copyWith(deptIds: {...deptIds, d.id});
  }

  /// Select all / clear: clearing keeps the locked departments.
  CouncilsDraft selectAll(List<CouncilDeptRow> rows, bool on) =>
      copyWith(deptIds: on ? {for (final d in rows) d.id} : {for (final d in rows) if (d.locked) d.id});

  bool allSelected(List<CouncilDeptRow> rows) => rows.isNotEmpty && rows.every((d) => deptIds.contains(d.id));

  /// The departments that would lose a council with open agenda items (only a mode without department councils).
  List<CouncilDeptRow> lockedOut(List<CouncilDeptRow> rows) {
    final m = effectiveMode;
    if (m == null) return const [];
    final keep = modeHasDepts(m) ? deptIds : const <int>{};
    return [for (final d in rows) if (d.locked && !keep.contains(d.id)) d];
  }

  /// The chair line under the faculty fields; null = fine.
  String? get chairProblem => modeHasFaculty(effectiveMode) && chair == null && !chairSelf ? chairRequiredText() : null;

  /// What still stops Save; null = it may be sent.
  String? problem(List<CouncilDeptRow> rows) {
    if (want == null) return t('أجب أولاً: هل تريد مجالس؟', 'Answer first: do you want councils?');
    final m = effectiveMode;
    if (m == null) return t('اختر نوع المجالس', 'Choose which councils');
    final out = lockedOut(rows);
    if (out.isNotEmpty) return '${orgCodeText('council_has_open_agenda')}: ${out.map((d) => d.name).join('، ')}';
    final c = chairProblem;
    if (c != null) return c;
    if (modeHasDepts(m) && deptIds.isEmpty) return t('اختر قسماً واحداً على الأقل', 'Pick at least one department');
    return null;
  }

  /// The PUT body.
  Map<String, dynamic> toBody() {
    final m = effectiveMode ?? CouncilsMode.none;
    final depts = modeHasDepts(m);
    return {
      'mode': m.name,
      'dept_ids': depts ? (deptIds.toList()..sort()) : <int>[],
      'auto_new': depts && autoNew,
      if (modeHasFaculty(m))
        'faculty': {
          if (chairSelf) 'head_self': true else 'chair_user_id': ?chair?.id,
          'secretary_user_id': ?secretary?.id,
          // the secretary is a council member: picked apart, sent inside the list (UX v3 secretary bug)
          'member_ids': [for (final u in members) u.id, if (secretary != null && !members.any((u) => u.id == secretary!.id)) secretary!.id],
        },
    };
  }
}

/// The faculty council's server field errors (UX v3): the chair, the secretary and the members pickers.
FieldErrors councilsFieldErrors() => FieldErrors(
      aliases: const {'chair_user_id': 'chair', 'head_self': 'chair', 'secretary_user_id': 'secretary', 'member_ids': 'members', 'members': 'members'},
      codes: const {'head_required': 'chair', 'secretary_not_member': 'secretary'},
      actions: const {'pick_head': 'chair'},
    );

/// The faculty chair is missing (the local check of 422 `head_required`).
String chairRequiredText() =>
    t('اختر رئيس مجلس الكلية (العميد)، أو عيّن نفسك.', 'Choose the Faculty Council\'s chair (the dean), or assign yourself.');

/// "3 open items" (an agenda's open items).
String openItemsText(int n) => countText(n,
    ar1: 'بند مفتوح واحد', ar2: 'بندان مفتوحان', arFew: '{n} بنود مفتوحة', arMany: '{n} بنداً مفتوحاً', en1: '1 open item', en: '{n} open items');

/// The 409 `council_has_open_agenda` answer: the code's text and each council with its open items.
String councilsOpenAgendaText(Map<String, dynamic> detail) {
  final rows = asMapList(detail['councils']);
  final base = orgCodeText('council_has_open_agenda');
  if (rows.isEmpty) return base;
  final list = [
    for (final r in rows)
      '${r['name'] ?? ''} (${openItemsText(asInt(r['open_agenda_items']))})',
  ];
  return '$base: ${list.join('، ')}';
}

// ═════════════════════════════════════════════════════════════════════════════
//  The view (plain values)
// ═════════════════════════════════════════════════════════════════════════════

/// Picks one person (the page wires [pickOrgMember]); [exclude] = already chosen.
typedef CouncilPersonPicker = Future<GovUser?> Function(String title, Set<int> exclude);

/// Q1 "Do you want councils?", Q2 "Which councils?", the Faculty Council's people and the department tick cards.
class CouncilsChoiceView extends StatelessWidget {
  const CouncilsChoiceView({
    super.key,
    required this.setup,
    required this.draft,
    required this.onChanged,
    this.pickPerson,
    this.meName = '',
    this.chairError,
    this.errors,
    this.onSave,
    this.busy = false,
    this.dirty = false,
  });

  /// The last save's field errors ([councilsFieldErrors]): `chair`, `secretary`, `members`.
  final FieldErrors? errors;

  final CouncilsSetup setup;
  final CouncilsDraft draft;
  final ValueChanged<CouncilsDraft> onChanged;

  /// null = the people fields are read-only.
  final CouncilPersonPicker? pickPerson;
  final String meName;
  final String? chairError;

  /// null = no Save action (a wizard step saves on Next).
  final VoidCallback? onSave;
  final bool busy, dirty;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = setup.departments;
    final m = draft.effectiveMode;
    final out = draft.lockedOut(rows);
    final save = onSave;
    return OrgPageBody(
      primary: save != null && (dirty || setup.derived)
          ? OrgPrimaryAction(id: 'save_councils_setup', icon: Icons.check_rounded, label: t('حفظ', 'Save'), onTap: busy ? () {} : save)
          : null,
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpace.xxl + AppTouch.primary),
        children: [
          OrgSectionHeading(t('هل تريد مجالس؟', 'Do you want councils?'),
              subtitle: t('المجالس تناقش الطلبات وتصوّت عليها في جلسات وتكتب المحاضر.',
                  'Councils discuss requests, vote on them in sessions and keep the minutes.')),
          OrgGrid(minTile: 280, children: [
            CouncilChoiceCard(
                key: const ValueKey('councils.want.yes'),
                icon: Icons.account_balance_rounded,
                title: t('نعم', 'Yes'),
                sentence: t('مجلس للكلية أو للأقسام أو لكليهما.', 'A council for the faculty, the departments, or both.'),
                selected: draft.want == true,
                onTap: () => onChanged(draft.answer(true))),
            CouncilChoiceCard(
                key: const ValueKey('councils.want.no'),
                icon: Icons.do_not_disturb_on_outlined,
                title: t('لا', 'No'),
                sentence: t('بدون مجالس الآن.', 'No councils for now.'),
                selected: draft.want == false,
                onTap: () => onChanged(draft.answer(false))),
          ]),
          if (draft.want == false)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
              child: Text(t('يمكنك إضافة المجالس لاحقاً من الإعدادات.', 'You can add councils later from Settings.'),
                  key: const ValueKey('councils.later'), style: AppType.body(context).copyWith(color: c.textMedium)),
            ),
          if (out.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
              child: AppBanner(
                  key: const ValueKey('councils.locked_out'),
                  icon: Icons.lock_clock_rounded,
                  color: c.warning,
                  text: '${orgCodeText('council_has_open_agenda')}: ${out.map((d) => d.name).join('، ')}'),
            ),
          if (draft.want == true) ...[
            OrgSectionHeading(t('مجلس الكلية، أم مجالس الأقسام، أم كلاهما؟', 'Faculty council, department councils, or both?')),
            OrgGrid(minTile: 240, children: [
              for (final mode in const [CouncilsMode.faculty, CouncilsMode.departments, CouncilsMode.both])
                CouncilChoiceCard(
                    key: ValueKey('councils.mode.${mode.name}'),
                    icon: switch (mode) {
                      CouncilsMode.faculty => Icons.account_balance_rounded,
                      CouncilsMode.departments => Icons.groups_2_rounded,
                      _ => Icons.account_tree_rounded,
                    },
                    title: councilsModeLabel(mode),
                    sentence: councilsModeSentence(mode),
                    selected: draft.mode == mode,
                    onTap: () => onChanged(draft.pick(mode, rows))),
            ]),
          ],
          if (modeHasFaculty(m)) _faculty(context),
          if (modeHasDepts(m)) ..._departments(context, rows),
        ],
      ),
    );
  }

  Widget _faculty(BuildContext context) {
    final pick = pickPerson;
    final taken = {?draft.chair?.id, ?draft.secretary?.id, for (final u in draft.members) u.id};
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, 0),
      child: AppCard(
        key: const ValueKey('councils.faculty'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('مجلس الكلية', 'Faculty council'), style: AppType.section(context)),
          const SizedBox(height: AppSpace.sm),
          if (!draft.chairSelf)
            KeyedSubtree(
              key: errors?.keyFor('chair'),
              child: _PersonField(
                key: const ValueKey('councils.chair'),
                label: t('رئيس المجلس (العميد) *', 'Chair (the dean) *'),
                person: draft.chair,
                onTap: pick == null
                    ? null
                    : () async {
                        final u = await pick(t('رئيس مجلس الكلية', 'Faculty Council chair'), taken);
                        if (u != null) onChanged(draft.copyWith(chair: u, chairSelf: false, members: [for (final x in draft.members) if (x.id != u.id) x]));
                      }),
            ),
          const SizedBox(height: AppSpace.xs),
          AssignMeChip(
              selected: draft.chairSelf,
              meName: meName,
              label: t('عيّنّي رئيساً للمجلس', 'Assign me as chair'),
              onTap: () => onChanged(draft.copyWith(chairSelf: !draft.chairSelf))),
          HeadErrorText(chairError ?? errors?.errorFor('chair')),
          const SizedBox(height: AppSpace.sm),
          KeyedSubtree(
            key: errors?.keyFor('secretary'),
            child: _PersonField(
              key: const ValueKey('councils.secretary'),
              label: t('أمين المجلس (اختياري)', 'Secretary (optional)'),
              person: draft.secretary,
              errorText: errors?.errorFor('secretary'),
              onClear: draft.secretary == null ? null : () => onChanged(draft.copyWith(clearSecretary: true)),
              onTap: pick == null
                  ? null
                  : () async {
                      final u = await pick(t('أمين المجلس', 'Council secretary'), taken);
                      if (u != null) onChanged(draft.copyWith(secretary: u));
                    }),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(t('الأعضاء', 'Members'), style: AppType.bodyStrong(context)),
          const SizedBox(height: AppSpace.xxs),
          Wrap(key: errors?.keyFor('members'), spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final u in draft.members)
              InputChip(
                  key: ValueKey('councils.member.${u.id}'),
                  label: Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onDeleted: () => onChanged(draft.copyWith(members: [for (final x in draft.members) if (x.id != u.id) x])),
                  deleteButtonTooltipMessage: t('إزالة', 'Remove')),
            if (pick != null)
              TextButton.icon(
                  key: const ValueKey('councils.member.add'),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: Text(t('إضافة عضو', 'Add member')),
                  onPressed: () async {
                    final u = await pick(t('عضو في مجلس الكلية', 'Faculty Council member'), taken);
                    if (u != null) onChanged(draft.copyWith(members: [...draft.members, u]));
                  }),
          ]),
          HeadErrorText(errors?.errorFor('members')),
          const SizedBox(height: AppSpace.xxs),
          Text(t('رؤساء الأقسام أعضاء في مجلس الكلية تلقائياً.', 'Department heads sit on the Faculty Council by default.'),
              style: AppType.meta(context).copyWith(color: context.colors.textMedium)),
        ]),
      ),
    );
  }

  List<Widget> _departments(BuildContext context, List<CouncilDeptRow> rows) {
    final all = draft.allSelected(rows);
    return [
      OrgSectionHeading(
        t('مجالس الأقسام', 'Department councils'),
        subtitle: t('يرأس كل مجلس رئيس القسم.', 'Each department head chairs its council.'),
        action: rows.isEmpty
            ? null
            : TextButton(
                key: const ValueKey('councils.select_all'),
                onPressed: () => onChanged(draft.selectAll(rows, !all)),
                child: Text(all ? t('إلغاء الكل', 'Clear') : t('تحديد الكل', 'Select all'))),
      ),
      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          child: AppBanner(
              icon: Icons.info_outline_rounded,
              text: t('لا أقسام علمية بعد — أضفها من «دليل الإدارات».', 'No academic departments yet: add them from the Department catalog.')),
        ),
      for (final d in rows)
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.xxs),
          child: CouncilDeptCard(dept: d, selected: draft.deptIds.contains(d.id), onTap: () => onChanged(draft.toggle(d))),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
        child: AppCard(
          child: AppSwitchTile(
              key: const ValueKey('councils.auto_new'),
              icon: Icons.auto_awesome_rounded,
              title: t('امنح الأقسام الجديدة مجلساً أيضاً', 'Also give new departments a council'),
              subtitle: t('يُنشأ المجلس مع القسم الجديد.', 'The council is created with the new department.'),
              value: draft.autoNew,
              onChanged: (v) => onChanged(draft.copyWith(autoNew: v))),
        ),
      ),
    ];
  }
}

String councilsModeLabel(CouncilsMode m) => switch (m) {
      CouncilsMode.faculty => t('مجلس الكلية', 'Faculty council'),
      CouncilsMode.departments => t('مجالس الأقسام', 'Department councils'),
      CouncilsMode.both => t('كلاهما', 'Both'),
      CouncilsMode.none => t('بدون مجالس', 'No councils'),
    };

String councilsModeSentence(CouncilsMode m) => switch (m) {
      CouncilsMode.faculty => t('مجلس واحد يرأسه العميد.', 'One council, chaired by the dean.'),
      CouncilsMode.departments => t('مجلس لكل قسم يرأسه رئيس القسم.', 'A council for each department, chaired by its head.'),
      CouncilsMode.both => t('مجالس الأقسام تُصعِّد إلى مجلس الكلية.', 'Department councils escalate to the Faculty Council.'),
      CouncilsMode.none => t('يمكن إضافتها لاحقاً.', 'They can be added later.'),
    };

/// A big choice card: icon, title, one sentence, the radio mark.
class CouncilChoiceCard extends StatelessWidget {
  const CouncilChoiceCard({super.key, required this.icon, required this.title, required this.sentence, required this.selected, required this.onTap});
  final IconData icon;
  final String title, sentence;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.primaryWash : c.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: BorderSide(color: selected ? c.primary : c.divider, width: selected ? AppBorder.focus : AppBorder.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: AppTouch.min,
                height: AppTouch.min,
                decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.control)),
                child: Icon(icon, color: c.primary, size: AppIconSize.lg),
              ),
              AppSpace.gapSm,
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: AppType.section(context)),
                  const SizedBox(height: AppSpace.xxs),
                  Text(sentence, style: AppType.body(context).copyWith(color: c.textMedium)),
                ]),
              ),
              AppSpace.gapXs,
              Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? c.primary : c.textLight, size: AppIconSize.lg),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One academic department: the tick, its name, its head (or "No head yet"), its council and open agenda items.
/// Ticked and locked (open agenda items) = it cannot be unticked, with the reason.
class CouncilDeptCard extends StatelessWidget {
  const CouncilDeptCard({super.key, required this.dept, required this.selected, required this.onTap});
  final CouncilDeptRow dept;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = dept;
    final frozen = selected && d.locked;
    return Semantics(
      checked: selected,
      enabled: !frozen,
      child: Material(
        key: ValueKey('councils.dept.${d.id}'),
        color: selected ? c.primaryWash : c.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: BorderSide(color: selected ? c.primary : c.divider, width: AppBorder.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: frozen ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                  color: frozen ? c.textLight : (selected ? c.primary : c.textLight), size: AppIconSize.lg),
              AppSpace.gapSm,
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
                  const SizedBox(height: AppSpace.xxs),
                  UnitHeadLine(head: d.head),
                  if (d.hasCouncil || d.openAgendaItems > 0) ...[
                    const SizedBox(height: AppSpace.xxs),
                    Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                      if (d.hasCouncil) AppBadgePill(t('له مجلس', 'Has a council'), color: c.success, icon: Icons.groups_2_rounded),
                      if (d.openAgendaItems > 0)
                        AppBadgePill(
                            openItemsText(d.openAgendaItems),
                            color: c.warning,
                            icon: Icons.event_note_rounded),
                    ]),
                  ],
                  if (frozen) ...[
                    const SizedBox(height: AppSpace.xxs),
                    Text(t('لا يمكن إلغاء مجلسه قبل إنهاء بنوده المفتوحة أو نقلها.', 'Its council stays until its open agenda items are closed or moved.'),
                        key: ValueKey('councils.dept.${d.id}.locked'), style: AppType.meta(context).copyWith(color: c.warning)),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A tap-to-pick person field (the same look as the Faculty Council's chair field in the councils list).
class _PersonField extends StatelessWidget {
  const _PersonField({super.key, required this.label, required this.person, this.onTap, this.onClear, this.errorText});
  final String label;
  final String? errorText;
  final GovUser? person;
  final VoidCallback? onTap, onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.control),
      onTap: onTap,
      child: InputDecorator(
        isEmpty: person == null,
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          errorMaxLines: 3,
          prefixIcon: Icon(Icons.person_search_rounded, color: c.textLight),
          suffixIcon: onClear == null
              ? null
              : IconButton(tooltip: t('إزالة', 'Remove'), icon: const Icon(Icons.close_rounded), onPressed: onClear),
        ),
        child: Text(person?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The page
// ═════════════════════════════════════════════════════════════════════════════

/// Loads the setup, shows [CouncilsChoiceView], saves with PUT. Opened from Settings (orgPush wraps it) or from the
/// councils list ([openCouncilsSetup]).
class OrgCouncilsSetupPage extends StatefulWidget {
  const OrgCouncilsSetupPage({super.key, this.orgId});
  final int? orgId;

  @override
  State<OrgCouncilsSetupPage> createState() => _OrgCouncilsSetupPageState();
}

class _OrgCouncilsSetupPageState extends State<OrgCouncilsSetupPage> {
  CouncilsSetup? _setup;
  CouncilsDraft _draft = const CouncilsDraft();
  String _saved = '';
  String? _chairError;
  bool _failed = false, _busy = false;
  final _errors = councilsFieldErrors();

  @override
  void dispose() {
    _errors.dispose();
    super.dispose();
  }

  GovApi? get _api {
    final id = govOrgId(context, widget.orgId);
    return id == null ? null : GovApi(id);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _take(CouncilsSetup s) {
    _setup = s;
    _draft = CouncilsDraft.from(s);
    _saved = jsonEncode(_draft.toBody());
    _chairError = null;
  }

  Future<void> _load() async {
    final api = _api;
    if (api == null) {
      setState(() => _failed = true);
      return;
    }
    setState(() => _failed = false);
    final r = await orgCall(() => api.councilsSetup(), quiet: true);
    if (!mounted) return;
    setState(() => r.ok ? _take(CouncilsSetup.fromJson(r.map)) : _failed = true);
  }

  bool get _dirty => _setup != null && jsonEncode(_draft.toBody()) != _saved;

  Future<void> _save() async {
    final s = _setup, api = _api;
    if (s == null || api == null) return;
    final why = _draft.problem(s.departments);
    if (why != null) {
      setState(() => _chairError = _draft.chairProblem);
      showAppNotice(why, error: true);
      return;
    }
    setState(() => _busy = true);
    final r = await orgCall(() => api.saveCouncilsSetup(_draft.toBody()), quiet: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      if (r.code == 'head_required') setState(() => _chairError = chairRequiredText());
      if (_errors.take(r.error!, text: orgErrorText(r.error!))) {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) => _errors.revealFirst());
      }
      showAppError(context, r.error!, text: r.code == 'council_has_open_agenda' ? councilsOpenAgendaText(r.detail) : orgErrorText(r.error!));
      return;
    }
    _errors.clear();
    setState(() => _take(CouncilsSetup.fromJson(r.map)));
    showAppNotice(t('تم حفظ إعداد المجالس', 'Councils setup saved'));
  }

  @override
  Widget build(BuildContext context) {
    final s = _setup;
    if (s == null) return OrgAsync(loading: !_failed, failed: _failed, onRetry: _load, child: const SizedBox.shrink());
    final oid = govOrgId(context, widget.orgId);
    return CouncilsChoiceView(
      setup: s,
      draft: _draft,
      meName: currentPerson(context).$2,
      chairError: _chairError,
      errors: _errors,
      busy: _busy,
      dirty: _dirty,
      onChanged: (d) => setState(() {
        _draft = d;
        _errors.clear();
        if (_chairError != null) _chairError = d.chairProblem;
      }),
      pickPerson: oid == null ? null : (title, exclude) => pickOrgMember(context, oid, title: title, exclude: exclude),
      onSave: _save,
    );
  }
}

/// The page's title (Settings tile, councils list, pushed header).
String councilsSetupTitle() => t('إعداد المجالس', 'Councils setup');

/// Pushes the page on its own, with the dashboard's header (the councils list's entry).
Future<void> openCouncilsSetup(BuildContext context, {int? orgId}) => Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => OrgPushedPage(helpPageId: 'org.governance', title: councilsSetupTitle(), child: OrgCouncilsSetupPage(orgId: orgId))));
