// lib/features/org/org_unit_rules.dart
//
// Institutions v2, phase 1: the data rules of a unit (plan docs/institutions/V2_PLAN.md, back D-980 – D-984).
//   UnitHead · unitHeadOf      a department's head {id, name, acting}; old servers omit it (null-safe)
//   unitIsCore                 `core: true`: a core department can be renamed, never removed
//   headProblem                the form check that mirrors the server's 422 `head_required`
//   DeptImpact                 GET …/departments/{id}/impact (what archiving touches)
//   archiveBlock · archiveProblem   why archiving is refused / what the sheet still needs
//   DeptRulesApi               impact · archive (DELETE ?reassign_to=) · repair (POST …/institution/repair)
//   AssignMeChip               the one-tap "Assign me as head" chip (sends `head_self: true`)
//   UnitHeadPicker             the required head field of the unit forms: member picker (no "none") + AssignMeChip
//   UnitHeadLine · CoreUnitBadge    the head with an "Acting" chip; the lock badge of a core department
//   DeptArchiveView            plain values: impact cards, the "Move open requests to" picker, the blocked reason
//   showArchiveDepartmentSheet loads the impact, shows the view, asks appConfirm, then DELETE
//   CouncilSecretaryActingHint "The chair acts as secretary" (roster `secretary_acting: true`)
//
// The pure parts and the views are tested in test/org/institutions_v2_p1_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart' show MyAuthProvider;
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import 'org_member_form.dart' show OrgMemberPickField;
import 'org_providers.dart' show OrgSession;
import 'org_ui.dart' show orgNameOf;
import 'org_v3.dart' show OrgCall, orgCall, orgCodeText, orgErrorText;

// ═════════════════════════════════════════════════════════════════════════════
//  Pure parts
// ═════════════════════════════════════════════════════════════════════════════

/// A unit's head as the department payload carries it (`head: {id, name, acting}`). `acting` = the manager (or the
/// person who set the unit up) covers until a real head is assigned.
class UnitHead {
  const UnitHead({required this.id, required this.name, this.acting = false});
  final int id;
  final String name;
  final bool acting;
}

/// The head of a department (`head`) or of an academic department (`manager`); null when there is none.
UnitHead? unitHeadOf(Map<String, dynamic>? d) {
  final h = asMap(d?['head']).isNotEmpty ? asMap(d?['head']) : asMap(d?['manager']);
  if (h['id'] == null) return null;
  return UnitHead(id: asInt(h['id']), name: '${h['name'] ?? ''}', acting: h['acting'] == true);
}

/// A core department: created by the institution setup, can be renamed, never removed (409 `dept_core`).
bool unitIsCore(Map<String, dynamic>? d) => d?['core'] == true;

/// A unit form's server field errors (UX v3): every head field name and code lands on `head`.
FieldErrors unitHeadFieldErrors() => FieldErrors(
      aliases: const {'head_user_id': 'head', 'head_self': 'head', 'chair_user_id': 'head'},
      codes: const {'head_required': 'head', 'head_invalid': 'head'},
      actions: const {'pick_head': 'head'},
    );

/// The text of a missing head (the same words as the server's `head_required`).
String headRequiredText() => orgCodeText('head_required');

/// null when the form may be saved: a head is picked, or the caller makes themselves the head.
String? headProblem({int? head, bool self = false}) => head != null || self ? null : headRequiredText();

/// GET …/departments/{id}/impact → what archiving the department touches.
class DeptImpact {
  const DeptImpact({this.courses = 0, this.openItems = 0, this.councils = 0, this.openAgendaItems = 0, this.members = 0, this.core = false});
  final int courses, openItems, councils, openAgendaItems, members;
  final bool core;

  factory DeptImpact.fromJson(Map<String, dynamic> j) => DeptImpact(
        courses: asInt(j['courses']),
        openItems: asInt(j['open_items']),
        councils: asInt(j['councils']),
        openAgendaItems: asInt(j['open_agenda_items']),
        members: asInt(j['members']),
        core: j['core'] == true,
      );
}

/// Why the department cannot be archived at all; null = it can.
String? archiveBlock(DeptImpact i) {
  if (i.core) return orgCodeText('dept_core');
  if (i.openAgendaItems > 0) return orgCodeText('council_has_open_agenda');
  return null;
}

/// What still stops the confirm button: the block, or the missing "Move open requests to" department.
String? archiveProblem(DeptImpact i, {int? reassignTo}) {
  final b = archiveBlock(i);
  if (b != null) return b;
  if (i.openItems > 0 && reassignTo == null) {
    return t('اختر الإدارة التي تنتقل إليها الطلبات المفتوحة', 'Choose the department that takes the open requests');
  }
  return null;
}

/// The departments that may take the open requests: every other active, non-archived one.
List<Map<String, dynamic>> reassignTargets(List<Map<String, dynamic>> all, int deptId) =>
    [for (final d in all) if (asInt(d['id']) != deptId && d['is_active'] != false && d['archived'] != true) d];

/// The calls of the unit rules, next to the department calls (`${s.base}/departments…`).
class DeptRulesApi {
  DeptRulesApi(this.s);
  final OrgSession s;

  Future<OrgCall> impact(int deptId) => orgCall(() => s.api.get('${s.base}/departments/$deptId/impact'), quiet: true);

  /// Archives (the default); with open requests [reassignTo] is required (409 `dept_has_open_items` otherwise).
  Future<OrgCall> archive(int deptId, {int? reassignTo}) => orgCall(
      () => s.api.delete('${s.base}/departments/$deptId', queryParams: {'reassign_to': ?reassignTo}),
      quiet: true);

  /// Managers: gives every headless unit an acting head and marks the core units → `{fixed: n}`.
  Future<OrgCall> repair() => orgCall(() => s.api.post('${s.base}/institution/repair'), quiet: true);
}

/// The signed-in person (id, name); empty outside the app (tests without an auth provider).
(int?, String) currentPerson(BuildContext context) {
  try {
    final u = context.read<MyAuthProvider>().currentUser;
    return (u?.id, (u?.name ?? '').trim());
  } catch (_) {
    return (null, '');
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Head field
// ═════════════════════════════════════════════════════════════════════════════

/// "Assign me as head": selected, it shows my name as the chosen head.
class AssignMeChip extends StatelessWidget {
  const AssignMeChip({super.key, required this.selected, required this.onTap, this.meName = '', this.label});
  final bool selected;
  final VoidCallback onTap;
  final String meName;

  /// Another word for the role ("Assign me as chair").
  final String? label;

  @override
  Widget build(BuildContext context) {
    final who = meName.isEmpty ? t('أنت', 'You') : meName;
    return AppChoiceChip(
      key: const ValueKey('unit.head.me'),
      icon: selected ? Icons.check_circle_rounded : Icons.person_pin_rounded,
      label: selected ? t('الرئيس: $who (أنت)', 'Head: $who (you)') : (label ?? t('عيّنّي رئيساً', 'Assign me as head')),
      selected: selected,
      onTap: onTap,
    );
  }
}

/// The head under the field: the error line of a missing head.
class HeadErrorText extends StatelessWidget {
  const HeadErrorText(this.error, {super.key});
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (error == null) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xxs),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.error_outline_rounded, size: AppIconSize.sm, color: c.danger),
        const SizedBox(width: AppSpace.xxs),
        Expanded(child: Text(error!, style: AppType.label(context).copyWith(color: c.danger))),
      ]),
    );
  }
}

/// The required head of a unit form: the member picker without "none", the "Assign me as head" chip, the error.
/// [self] true = the caller becomes the head (`head_self: true`); picking someone clears it.
class UnitHeadPicker extends StatelessWidget {
  const UnitHeadPicker({
    super.key,
    required this.label,
    required this.value,
    required this.self,
    required this.roles,
    required this.onChanged,
    this.initialName,
    this.error,
  });

  final String label;
  final int? value;
  final bool self;
  final List<String> roles;
  final String? initialName, error;

  /// (picked user id, self).
  final void Function(int? head, bool self) onChanged;

  @override
  Widget build(BuildContext context) {
    final me = currentPerson(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!self)
          OrgMemberPickField(
            label: '$label *',
            value: value,
            initialName: initialName,
            roles: roles,
            allowNone: false,
            onChanged: (v) => onChanged(v, false),
          ),
        AssignMeChip(selected: self, meName: me.$2, onTap: () => onChanged(self ? value : null, !self)),
        HeadErrorText(error),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Badges
// ═════════════════════════════════════════════════════════════════════════════

/// "Head: name" (or "No head yet") with an "Acting" chip when [head] only covers.
class UnitHeadLine extends StatelessWidget {
  const UnitHeadLine({super.key, required this.head, this.manager = false, this.style});
  final UnitHead? head;

  /// An academic department says "Manager".
  final bool manager;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final h = head;
    final st = style ?? AppType.meta(context);
    if (h == null) {
      return Text(manager ? t('لم يُعيَّن مدير بعد', 'No manager yet') : t('لم يُعيَّن رئيس بعد', 'No head yet'),
          maxLines: 1, overflow: TextOverflow.ellipsis, style: st.copyWith(color: c.warning));
    }
    return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text(manager ? t('المدير: ${h.name}', 'Manager: ${h.name}') : t('الرئيس: ${h.name}', 'Head: ${h.name}'),
          maxLines: 1, overflow: TextOverflow.ellipsis, style: st),
      if (h.acting) ActingChip(key: const ValueKey('unit.head.acting')),
    ]);
  }
}

/// The "Acting" chip of a head who only covers.
class ActingChip extends StatelessWidget {
  const ActingChip({super.key});

  @override
  Widget build(BuildContext context) =>
      AppBadgePill(t('بالإنابة', 'Acting'), color: context.colors.warning, icon: Icons.hourglass_top_rounded);
}

/// The lock of a core department. [long] adds the sentence "can be renamed, not removed".
class CoreUnitBadge extends StatelessWidget {
  const CoreUnitBadge({super.key, this.long = false});
  final bool long;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pill = AppBadgePill(t('إدارة أساسية', 'Core'), color: c.purple, icon: Icons.lock_rounded);
    if (!long) return Tooltip(message: coreUnitText(), child: pill);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.lock_rounded, size: AppIconSize.sm, color: c.purple),
      const SizedBox(width: AppSpace.xs),
      Expanded(child: Text(coreUnitText(), style: AppType.meta(context).copyWith(color: c.textMedium))),
    ]);
  }
}

String coreUnitText() => t('إدارة أساسية: يمكن تغيير اسمها ولا يمكن حذفها', 'Core department: can be renamed, not removed');

/// The departments without a head (an older organization, D-984): one banner with "Fix now" → POST …/repair.
class HeadlessUnitsBanner extends StatelessWidget {
  const HeadlessUnitsBanner({super.key, required this.count, required this.onFix, this.busy = false});
  final int count;
  final VoidCallback onFix;
  final bool busy;

  @override
  Widget build(BuildContext context) => AppBanner(
        key: const ValueKey('dept.headless'),
        icon: Icons.person_off_rounded,
        color: context.colors.warning,
        text: '${countText(count, ar1: 'إدارة واحدة بلا رئيس', ar2: 'إدارتان بلا رئيس', arFew: '{n} إدارات بلا رئيس', arMany: '{n} إدارة بلا رئيس', en1: 'One department has no head', en: '{n} departments have no head')}. '
            '${t('الإصلاح يجعل المدير رئيساً بالإنابة حتى تعيّن رئيساً.', 'Fixing makes the manager the acting head until you assign one.')}',
        action: TextButton(onPressed: busy ? null : onFix, child: Text(t('إصلاح الآن', 'Fix now'))),
      );
}

/// Roster hint when the council has no secretary and its chair covers (`secretary_acting: true`).
class CouncilSecretaryActingHint extends StatelessWidget {
  const CouncilSecretaryActingHint({super.key});

  @override
  Widget build(BuildContext context) => AppBanner(
        key: const ValueKey('council.secretary.acting'),
        icon: Icons.info_outline_rounded,
        color: context.colors.warning,
        text: t('رئيس المجلس يقوم بعمل الأمين حتى يُعيَّن أمين.', 'The chair acts as secretary until one is chosen.'),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Archive
// ═════════════════════════════════════════════════════════════════════════════

/// The archive sheet's body, plain values: what archiving touches, the "Move open requests to" picker when open
/// requests exist, and the confirm button (disabled with the reason while [archiveProblem] has one).
class DeptArchiveView extends StatelessWidget {
  const DeptArchiveView({
    super.key,
    required this.name,
    required this.impact,
    required this.targets,
    required this.reassignTo,
    required this.onReassign,
    required this.onArchive,
    this.busy = false,
    this.error,
  });

  final String name;
  final DeptImpact impact;
  final List<Map<String, dynamic>> targets;
  final int? reassignTo;
  final ValueChanged<int?> onReassign;
  final VoidCallback onArchive;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final i = impact;
    final block = archiveBlock(i);
    final problem = archiveProblem(i, reassignTo: reassignTo);
    final figures = <(IconData, String, int, Color)>[
      (Icons.menu_book_rounded, t('مقررات', 'Courses'), i.courses, c.accent),
      (Icons.inbox_rounded, t('طلبات مفتوحة', 'Open requests'), i.openItems, i.openItems > 0 ? c.warning : c.success),
      (Icons.groups_2_rounded, t('مجالس', 'Councils'), i.councils, c.purple),
      (Icons.gavel_rounded, t('بنود مجلس مفتوحة', 'Open agenda items'), i.openAgendaItems, i.openAgendaItems > 0 ? c.danger : c.success),
      (Icons.groups_rounded, t('أعضاء', 'Members'), i.members, c.primary),
    ];
    return AppSheetContent(
      title: t('أرشفة الإدارة', 'Archive department'),
      subtitle: name,
      icon: Icons.archive_rounded,
      tone: AppTone.warning,
      children: [
        Text(
            t('تختفي الإدارة من القوائم والنماذج، وتبقى سجلاتها محفوظة. هذا ما يتأثر:',
                'The department leaves the lists and forms; its records are kept. This is what it touches:'),
            style: AppType.meta(context).copyWith(color: c.textMedium)),
        const SizedBox(height: AppSpace.sm),
        LayoutBuilder(builder: (context, box) {
          const gap = AppSpace.xs;
          final cols = (box.maxWidth / 150).floor().clamp(1, 5);
          final w = (box.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(spacing: gap, runSpacing: gap, children: [
            for (final f in figures)
              SizedBox(width: w, child: _ImpactTile(icon: f.$1, label: f.$2, value: f.$3, color: f.$4)),
          ]);
        }),
        const SizedBox(height: AppSpace.md),
        if (block != null)
          AppBanner(key: const ValueKey('dept.archive.blocked'), icon: Icons.block_rounded, color: c.danger, text: block)
        else if (i.openItems > 0) ...[
          AppDropdown<int>(
            key: const ValueKey('dept.archive.reassign'),
            value: reassignTo,
            decoration: InputDecoration(
              labelText: t('نقل الطلبات المفتوحة إلى *', 'Move open requests to *'),
              prefixIcon: const Icon(Icons.move_up_rounded),
            ),
            items: [
              for (final d in targets)
                DropdownMenuItem(value: asInt(d['id']), child: Text(orgNameOf(d), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: onReassign,
          ),
          if (targets.isEmpty)
            HeadErrorText(t('لا توجد إدارة أخرى تستقبل الطلبات — أنشئ واحدة أولاً', 'No other department can take the requests — create one first')),
          const SizedBox(height: AppSpace.xs),
        ],
        if (error != null) ...[
          HeadErrorText(error),
          const SizedBox(height: AppSpace.xs),
        ],
        if (block == null && problem != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Text(problem, style: AppType.meta(context).copyWith(color: c.textMedium)),
          ),
        AppPrimaryButton(
          key: const ValueKey('dept.archive.go'),
          label: t('أرشفة الإدارة', 'Archive department'),
          icon: Icons.archive_rounded,
          busy: busy,
          onPressed: problem != null || busy ? null : onArchive,
        ),
      ],
    );
  }
}

class _ImpactTile extends StatelessWidget {
  const _ImpactTile({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.control), border: Border.all(color: c.divider)),
      child: Row(children: [
        Icon(icon, size: AppIconSize.md, color: color),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$value', style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
            Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
          ]),
        ),
      ]),
    );
  }
}

/// Who may archive: the `departments.delete` right, and never a core department.
bool canArchiveDept(OrgSession s, Map<String, dynamic>? d) => !unitIsCore(d) && s.can('departments', 'delete');

/// Loads the impact, shows [DeptArchiveView], confirms, then DELETE (with `reassign_to` when needed). True when
/// archived.
Future<bool> showArchiveDepartmentSheet(BuildContext context, Map<String, dynamic> dept) async {
  final s = context.read<OrgSession>();
  final api = DeptRulesApi(s);
  final id = asInt(dept['id']);
  final r = await api.impact(id);
  if (!context.mounted) return false;
  if (!r.ok) {
    showAppNotice(orgErrorText(r.error!), error: true);
    return false;
  }
  final impact = DeptImpact.fromJson(r.map);
  var targets = const <Map<String, dynamic>>[];
  if (impact.openItems > 0) {
    final all = await orgCall(() => s.api.get('${s.base}/departments'), quiet: true);
    targets = reassignTargets(asMapList(all.map['items']), id);
    if (!context.mounted) return false;
  }
  int? reassign;
  String? error;
  var busy = false, done = false;
  await showAppSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        return DeptArchiveView(
          name: orgNameOf(dept),
          impact: impact,
          targets: targets,
          reassignTo: reassign,
          busy: busy,
          error: error,
          onReassign: (v) => set(() => reassign = v),
          onArchive: () async {
            final ok = await appConfirm(ctx,
                danger: true,
                confirmLabel: t('أرشفة', 'Archive'),
                message: impact.openItems > 0
                    ? t('أرشفة "${orgNameOf(dept)}" ونقل طلباتها المفتوحة؟', 'Archive "${orgNameOf(dept)}" and move its open requests?')
                    : t('أرشفة "${orgNameOf(dept)}"؟', 'Archive "${orgNameOf(dept)}"?'));
            if (!ok || !ctx.mounted) return;
            set(() {
              busy = true;
              error = null;
            });
            final res = await api.archive(id, reassignTo: impact.openItems > 0 ? reassign : null);
            if (!ctx.mounted) return;
            if (res.ok) {
              done = true;
              Navigator.pop(ctx);
              showAppNotice(t('أُرشفت الإدارة', 'Department archived'));
              return;
            }
            set(() {
              busy = false;
              error = orgErrorText(res.error!);
            });
          },
        );
      }));
  return done;
}
