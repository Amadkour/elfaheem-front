// lib/features/org/governance/gov_forms_assign.dart — who must answer a form (spec §3 "Forms", §4 "Forms"):
//
//   showGovFormAssignSheet(context, api, formId)   people · departments · roles pickers, due date, "must answer"
//   GovFormAssignForm                              the presentational form (layout-tested)
//   GovFormAssignmentsView(formId)                 submitted / pending / waived lists, Remind all, per-person waive
//   GovAssignmentsBody                             its presentational body
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show SheetHeader, asInt, t;
import '../../admin/admin_list.dart' show AdminAvatar;
import '../org_providers.dart' show OrgSession;
import '../org_ui.dart' show memberRoleLabels;
import '../org_v3.dart' show orgCall, orgErrorText;
import 'gov_api.dart';
import 'gov_models.dart';
import 'gov_ui.dart';

class GovFormAssignForm extends StatelessWidget {
  const GovFormAssignForm({
    super.key,
    required this.people,
    required this.deptIds,
    required this.roles,
    required this.dueAt,
    required this.must,
    required this.entities,
    required this.onAddPerson,
    required this.onRemovePerson,
    required this.onDepts,
    required this.onRoles,
    required this.onDue,
    required this.onMust,
    required this.onSubmit,
    this.busy = false,
    this.error,
  });

  final List<GovUser> people;
  final List<int> deptIds;
  final List<String> roles;
  final DateTime? dueAt;
  final bool must, busy;
  final List<Entity> entities;
  final VoidCallback onAddPerson;
  final ValueChanged<GovUser> onRemovePerson;
  final ValueChanged<List<int>> onDepts;
  final ValueChanged<List<String>> onRoles;
  final ValueChanged<DateTime?> onDue;
  final ValueChanged<bool> onMust;
  final VoidCallback? onSubmit;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final any = people.isNotEmpty || deptIds.isNotEmpty || roles.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('أشخاص', 'People'), style: appText(12, c: c.textLight)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final p in people)
          InputChip(
            avatar: AdminAvatar(name: p.name, url: p.avatar, size: 22),
            label: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, w: FontWeight.w600, c: c.textDark)),
            onDeleted: () => onRemovePerson(p),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ActionChip(
          avatar: Icon(Icons.person_add_alt_1_rounded, size: 16, color: c.primary),
          label: Text(t('إضافة شخص', 'Add person'), style: appText(12, w: FontWeight.w700, c: c.primary)),
          onPressed: onAddPerson,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ]),
      if (entities.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(t('جهات (كل أعضائها)', 'Entities (every member)'), style: appText(12, c: c.textLight)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in entities)
            AppChoiceChip(
              label: e.name,
              icon: govKindIcon(e.kind),
              selected: deptIds.contains(e.id),
              onTap: () => onDepts(deptIds.contains(e.id) ? deptIds.where((x) => x != e.id).toList() : [...deptIds, e.id]),
            ),
        ]),
      ],
      const SizedBox(height: 14),
      GovChipSelect(label: t('فئات', 'Roles'), icon: Icons.groups_rounded, options: memberRoleLabels(), selected: roles, onChanged: onRoles),
      const SizedBox(height: 14),
      GovDateField(
        label: t('آخر موعد للإجابة (اختياري)', 'Answer by (optional)'),
        value: dueAt,
        withTime: true,
        icon: Icons.timer_rounded,
        onPick: () async {
          final d = await pickGovDateTime(context, initial: dueAt);
          if (d != null) onDue(d);
        },
        onClear: () => onDue(null),
      ),
      const SizedBox(height: 6),
      AppSwitchTile(
        icon: Icons.priority_high_rounded,
        title: t('الإجابة إلزامية', 'Must answer'),
        subtitle: t('يُذكَّر المتأخرون قبل الموعد بيوم ثم يومياً (حتى 5 مرات)', 'Late people are reminded a day before the due date, then daily (up to 5 times)'),
        value: must,
        onChanged: onMust,
      ),
      if (error != null) ...[const SizedBox(height: 10), AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!)],
      const SizedBox(height: 12),
      AppPrimaryButton(label: t('إسناد النموذج', 'Assign the form'), icon: Icons.send_rounded, busy: busy, onPressed: any ? onSubmit : null),
    ]);
  }
}

/// Returns the number of people assigned (null when dismissed).
Future<int?> showGovFormAssignSheet(BuildContext context, GovApi api, int formId, {List<Entity>? entities}) async {
  var list = entities ?? const <Entity>[];
  if (entities == null) {
    final r = await orgCall(() => api.entities(), quiet: true);
    if (r.ok) list = r.data as List<Entity>;
  }
  if (!context.mounted) return null;
  var people = <GovUser>[];
  var deptIds = <int>[];
  var roles = <String>[];
  DateTime? due;
  var must = false, busy = false;
  String? error;
  return showAppSheet<int>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetHeader(t('مَن يجب أن يجيب؟', 'Who must answer?')),
            GovFormAssignForm(
              people: people,
              deptIds: deptIds,
              roles: roles,
              dueAt: due,
              must: must,
              entities: list.where((e) => !e.isCouncil).toList(),
              busy: busy,
              error: error,
              onAddPerson: () async {
                final p = await pickGovPerson(ctx, api.orgId, title: t('إضافة شخص', 'Add person'), excludeIds: {for (final x in people) x.id});
                if (p != null) set(() => people = [...people, p]);
              },
              onRemovePerson: (p) => set(() => people = people.where((x) => x.id != p.id).toList()),
              onDepts: (v) => set(() => deptIds = v),
              onRoles: (v) => set(() => roles = v),
              onDue: (v) => set(() => due = v),
              onMust: (v) => set(() => must = v),
              onSubmit: () async {
                set(() {
                  busy = true;
                  error = null;
                });
                final r = await orgCall(
                    () => api.assignForm(formId,
                        userIds: people.isEmpty ? null : [for (final p in people) p.id], deptIds: deptIds.isEmpty ? null : deptIds, roles: roles.isEmpty ? null : roles, dueAt: due, must: must),
                    quiet: true);
                if (!ctx.mounted) return;
                if (!r.ok) {
                  set(() {
                    busy = false;
                    error = govCodeTexts()[r.code] ?? orgErrorText(r.error!);
                  });
                  return;
                }
                final n = asInt(r.map['assigned']);
                appToast(t('أُسند إلى $n', 'Assigned to $n'));
                Navigator.pop(ctx, n);
              },
            ),
          ]),
        );
      }));
}

class GovAssignmentsBody extends StatelessWidget {
  const GovAssignmentsBody({super.key, required this.submitted, required this.pending, required this.waived, this.dueAt, this.onRemindAll, this.onWaive, this.onOpenResponse, this.busy = false});
  final List<FormAssignment> submitted, pending, waived;
  final DateTime? dueAt;
  final VoidCallback? onRemindAll;
  final ValueChanged<FormAssignment>? onWaive;
  final ValueChanged<FormAssignment>? onOpenResponse;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = submitted.length + pending.length + waived.length;
    final pct = total == 0 ? 0.0 : submitted.length / total * 100;
    Widget row(FormAssignment a, Color col, {Widget? trailing, VoidCallback? onTap}) => Material(
          type: MaterialType.transparency,
          child: ListTile(
            dense: true,
            onTap: onTap,
            leading: AdminAvatar(name: a.user.name, url: a.user.avatar, size: 34),
            title: Text(a.user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
            subtitle: Text(
              [
                if (a.status == 'pending' && a.dueAt != null) '${t('قبل', 'by')} ${govWhen(a.dueAt)}',
                if (a.overdue) t('متأخر', 'Overdue'),
                if (a.remindCount > 0) t('ذُكّر ${a.remindCount}', 'Reminded ${a.remindCount}×'),
              ].join(' · '),
              style: appText(11.5, c: a.overdue ? c.danger : c.textMedium),
            ),
            trailing: trailing,
          ),
        );
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(t('${submitted.length} من $total أجابوا', '${submitted.length} of $total answered'), style: appText(14, w: FontWeight.w800, c: c.textDark))),
            Text('${pct.toStringAsFixed(0)}%', style: appText(13, w: FontWeight.w800, c: appScoreColor(context, pct))),
          ]),
          const SizedBox(height: 6),
          AppProgressBar(value: pct, max: 100),
          if (dueAt != null) ...[const SizedBox(height: 6), Text('${t('الموعد', 'Due')}: ${govWhen(dueAt)}', style: appText(12, c: c.textMedium))],
          if (onRemindAll != null && pending.isNotEmpty) ...[
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: AppPill(icon: Icons.notifications_active_rounded, label: t('تذكير الجميع (${pending.length})', 'Remind all (${pending.length})'), onTap: busy ? null : onRemindAll),
            ),
          ],
        ]),
      ),
      if (pending.isNotEmpty) ...[
        AppSectionTitle(t('لم يجيبوا بعد', 'Pending'), subtitle: '${pending.length}'),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            for (final a in pending)
              row(a, c.warning,
                  trailing: onWaive == null
                      ? null
                      : IconButton(tooltip: t('إعفاء', 'Waive'), onPressed: busy ? null : () => onWaive!(a), icon: Icon(Icons.person_off_outlined, color: c.textLight, size: 20))),
          ]),
        ),
      ],
      if (submitted.isNotEmpty) ...[
        AppSectionTitle(t('أجابوا', 'Submitted'), subtitle: '${submitted.length}'),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            for (final a in submitted) row(a, c.success, trailing: Icon(Icons.check_circle_rounded, color: c.success, size: 20), onTap: onOpenResponse == null ? null : () => onOpenResponse!(a)),
          ]),
        ),
      ],
      if (waived.isNotEmpty) ...[
        AppSectionTitle(t('مُعفَون', 'Waived'), subtitle: '${waived.length}'),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [for (final a in waived) row(a, c.textLight, trailing: Icon(Icons.remove_circle_outline_rounded, color: c.textLight, size: 20))]),
        ),
      ],
      if (total == 0) AppEmpty(icon: Icons.assignment_ind_rounded, title: t('لم يُسند النموذج لأحد بعد', 'Not assigned to anyone yet')),
    ]);
  }
}

class GovFormAssignmentsView extends StatefulWidget {
  const GovFormAssignmentsView(this.formId, {super.key, this.orgId, this.onOpenResponse});
  final int formId;
  final int? orgId;
  final ValueChanged<int>? onOpenResponse;

  @override
  State<GovFormAssignmentsView> createState() => _GovFormAssignmentsViewState();
}

class _GovFormAssignmentsViewState extends State<GovFormAssignmentsView> {
  late GovApi _api;
  Map<String, List<FormAssignment>>? _rows;
  bool _failed = false, _missing = false, _busy = false;

  int get _orgId => widget.orgId ?? context.read<OrgSession>().currentId ?? 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _api = GovApi(_orgId);
      _load();
    });
  }

  Future<void> _load() async {
    final r = await orgCall(() => _api.formAssignments(widget.formId), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _rows = r.data as Map<String, List<FormAssignment>>;
        _failed = false;
      } else {
        _failed = _rows == null;
        _missing = r.endpointMissing;
      }
    });
  }

  Future<void> _remindAll() async {
    setState(() => _busy = true);
    final r = await orgCall(() => _api.remindForm(widget.formId), quiet: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      appToast(t('ذُكّر ${asInt(r.map['reminded'])}', 'Reminded ${asInt(r.map['reminded'])}'));
      _load();
    } else {
      appToast(orgErrorText(r.error!), error: true);
    }
  }

  Future<void> _waive(FormAssignment a) async {
    if (!await appConfirm(context, message: t('إعفاء ${a.user.name} من الإجابة؟', 'Waive ${a.user.name}?'))) return;
    setState(() => _busy = true);
    final r = await orgCall(() => _api.waiveAssignment(widget.formId, a.user.id), ok: t('تم الإعفاء', 'Waived'));
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_rows == null && !_failed) return const AppListSkeleton(items: 4);
    if (_missing) return const GovNeedsServer();
    if (_rows == null) return AppEmpty(icon: Icons.cloud_off_rounded, title: t('تعذّر التحميل', 'Could not load'), actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load);
    final pending = _rows!['pending'] ?? const [];
    final due = pending.map((a) => a.dueAt).whereType<DateTime>().firstOrNull;
    return RefreshIndicator(
      onRefresh: _load,
      child: GovAssignmentsBody(
        submitted: _rows!['submitted'] ?? const [],
        pending: pending,
        waived: _rows!['waived'] ?? const [],
        dueAt: due,
        busy: _busy,
        onRemindAll: _remindAll,
        onWaive: _waive,
        onOpenResponse: widget.onOpenResponse == null ? null : (a) => a.responseId == null ? null : widget.onOpenResponse!(a.responseId!),
      ),
    );
  }
}
