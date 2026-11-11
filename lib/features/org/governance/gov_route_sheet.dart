// lib/features/org/governance/gov_route_sheet.dart — Route / Forward an item (spec §3 "Routing / forwarding").
//
//   showGovRouteSheet(context, api, item)      picks the target + action, POSTs …/items/{id}/route, returns the item
//   showGovRouteBodySheet(context, …)          the same form, returns only the body (bulk routing: POST …/items/bulk)
//   GovRouteForm                               the presentational form (plain values + callbacks; layout-tested)
//   GovEntityPickField                         an entity picker (kind icon + head name) reused by other sheets
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show SheetHeader, asMap, t;
import '../org_v3.dart' show orgCall, orgErrorText;
import 'gov_api.dart';
import 'gov_models.dart';
import 'gov_ui.dart';

/// The target of a route: exactly one of the two.
class RouteTarget {
  const RouteTarget({this.dept, this.user});
  final GovDept? dept;
  final GovUser? user;
  bool get isEmpty => dept == null && user == null;
  String get name => user?.name ?? dept?.name ?? '';
}

/// A field that opens a searchable list of entities (kind icon · name · head). [exclude] hides the item's owner.
class GovEntityPickField extends StatelessWidget {
  const GovEntityPickField({super.key, required this.label, required this.entities, required this.value, required this.onChanged, this.exclude = const {}, this.allowNone = false, this.kinds});
  final String label;
  final List<Entity> entities;
  final GovDept? value;
  final ValueChanged<GovDept?> onChanged;
  final Set<int> exclude;
  final bool allowNone;
  final List<String>? kinds;

  Future<void> _open(BuildContext context) async {
    var query = '';
    final picked = await showAppSheet<_PickedDept>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final c = ctx.colors;
          final shown = entities
              .where((e) => !exclude.contains(e.id) && (kinds == null || kinds!.contains(e.kind)))
              .where((e) => query.isEmpty || e.name.toLowerCase().contains(query.toLowerCase()) || e.dept.nameEn.toLowerCase().contains(query.toLowerCase()))
              .toList();
          return Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.md),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SheetHeader(label),
              if (entities.length > 6)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.xs),
                  child: TextField(
                    onChanged: (q) => set(() => query = q),
                    decoration: InputDecoration(hintText: t('ابحث…', 'Search…'), prefixIcon: const Icon(Icons.search_rounded), isDense: true),
                  ),
                ),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  if (allowNone)
                    ListTile(
                      onTap: () => Navigator.pop(ctx, const _PickedDept(null)),
                      leading: Icon(Icons.block_rounded, color: c.textLight),
                      title: Text(t('بدون', 'None'), style: appText(14, c: c.textMedium)),
                    ),
                  for (final e in shown)
                    Material(
                      type: MaterialType.transparency,
                      child: ListTile(
                        onTap: () => Navigator.pop(ctx, _PickedDept(e.dept)),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.control)),
                          child: Icon(govKindIcon(e.kind), color: c.primary, size: AppIconSize.md),
                        ),
                        title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: value?.id == e.id ? FontWeight.w800 : FontWeight.w600, c: c.textDark)),
                        subtitle: Text(
                          [entityKindLabel(e.kind), if (e.head != null) '${t('الرئيس', 'Head')}: ${e.head!.name}'].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: appText(12, c: c.textMedium),
                        ),
                        trailing: value?.id == e.id ? Icon(Icons.check_circle_rounded, color: c.primary) : null,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
                        tileColor: value?.id == e.id ? c.primary.withValues(alpha: 0.07) : null,
                      ),
                    ),
                  if (shown.isEmpty)
                    Padding(padding: const EdgeInsets.all(AppSpace.lg), child: Text(t('لا نتائج', 'No results'), textAlign: TextAlign.center, style: appText(13, c: c.textMedium))),
                ]),
              ),
            ]),
          );
        }));
    if (picked != null) onChanged(picked.dept);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.control),
      onTap: () => _open(context),
      child: InputDecorator(
        isEmpty: value == null,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(value == null ? Icons.apartment_rounded : govKindIcon(value!.kind), color: c.textLight),
          suffixIcon: Icon(Icons.unfold_more_rounded, color: c.textLight),
          filled: true,
          fillColor: c.inputBg,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.md),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control), borderSide: BorderSide(color: c.divider)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control), borderSide: BorderSide(color: c.divider)),
        ),
        child: Text(value?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w600, c: c.textDark)),
      ),
    );
  }
}

class _PickedDept {
  const _PickedDept(this.dept);
  final GovDept? dept;
}

/// The route form: target (entity OR person), action with its explanation, note, due date, submit.
class GovRouteForm extends StatelessWidget {
  const GovRouteForm({
    super.key,
    required this.entities,
    required this.target,
    required this.toPerson,
    required this.action,
    required this.note,
    required this.dueAt,
    required this.onTargetDept,
    required this.onPickPerson,
    required this.onToPerson,
    required this.onAction,
    required this.onDue,
    required this.onSubmit,
    this.excludeDeptId,
    this.busy = false,
    this.error,
    this.submitLabel,
    this.actions = routeActions,
  });

  final List<Entity> entities;
  final RouteTarget target;
  final bool toPerson;
  final String action;
  final TextEditingController note;
  final DateTime? dueAt;
  final ValueChanged<GovDept?> onTargetDept;
  final VoidCallback onPickPerson;
  final ValueChanged<bool> onToPerson;
  final ValueChanged<String> onAction;
  final ValueChanged<DateTime?> onDue;
  final VoidCallback? onSubmit;
  final int? excludeDeptId;
  final bool busy;
  final String? error, submitLabel;
  final List<String> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('إلى مَن؟', 'To whom?'), style: appText(12, c: c.textLight)),
      const SizedBox(height: AppSpace.xs),
      Row(children: [
        Expanded(child: AppChoiceChip(label: t('جهة', 'An entity'), icon: Icons.apartment_rounded, selected: !toPerson, onTap: () => onToPerson(false))),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: AppChoiceChip(label: t('شخص', 'A person'), icon: Icons.person_rounded, selected: toPerson, onTap: () => onToPerson(true))),
      ]),
      const SizedBox(height: AppSpace.sm),
      if (toPerson)
        GovPersonField(label: t('الشخص', 'Person'), person: target.user, onPick: onPickPerson)
      else
        GovEntityPickField(
          label: t('الجهة', 'Entity'),
          entities: entities,
          value: target.dept,
          exclude: {?excludeDeptId},
          onChanged: onTargetDept,
        ),
      const SizedBox(height: AppSpace.md),
      Text(t('ماذا تطلب؟', 'What do you ask for?'), style: appText(12, c: c.textLight)),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final a in actions) AppChoiceChip(label: routeActionLabel(a), icon: govActionIcon(a), selected: action == a, onTap: () => onAction(a)),
      ]),
      const SizedBox(height: AppSpace.xs),
      AppBanner(icon: govActionIcon(action), text: routeActionHelp(action)),
      const SizedBox(height: AppSpace.sm),
      AppField(controller: note, label: t('ملاحظة للمستلم (اختياري)', 'Note for the target (optional)'), maxLines: 3),
      const SizedBox(height: AppSpace.sm),
      GovDateField(
        label: t('مطلوب الرد قبل (اختياري)', 'Answer needed by (optional)'),
        value: dueAt,
        withTime: true,
        icon: Icons.timer_rounded,
        onPick: () async {
          final d = await pickGovDateTime(context, initial: dueAt);
          if (d != null) onDue(d);
        },
        onClear: () => onDue(null),
      ),
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(label: submitLabel ?? t('إحالة', 'Route'), icon: Icons.send_rounded, busy: busy, onPressed: target.isEmpty ? null : onSubmit),
    ]);
  }
}

/// Opens the route form and returns the POST body (`routeBody`) — nothing is sent. Used for bulk routing.
Future<Map<String, dynamic>?> showGovRouteBodySheet(
  BuildContext context, {
  required int orgId,
  required List<Entity> entities,
  int? excludeDeptId,
  String? title,
  String? submitLabel,
  List<String> actions = routeActions,
}) {
  var target = const RouteTarget();
  var toPerson = false;
  var action = actions.contains('review') ? 'review' : actions.first;
  DateTime? due;
  final note = TextEditingController();
  return showAppSheet<Map<String, dynamic>>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetHeader(title ?? t('إحالة / توجيه', 'Route / forward')),
            GovRouteForm(
              entities: entities,
              target: target,
              toPerson: toPerson,
              action: action,
              note: note,
              dueAt: due,
              excludeDeptId: excludeDeptId,
              submitLabel: submitLabel,
              actions: actions,
              onTargetDept: (d) => set(() => target = RouteTarget(dept: d)),
              onPickPerson: () async {
                final p = await pickGovPerson(ctx, orgId, title: t('إحالة إلى شخص', 'Route to a person'), selectedId: target.user?.id);
                if (p != null) set(() => target = RouteTarget(user: p));
              },
              onToPerson: (v) => set(() {
                toPerson = v;
                target = const RouteTarget();
              }),
              onAction: (a) => set(() => action = a),
              onDue: (d) => set(() => due = d),
              onSubmit: () => Navigator.pop(ctx, routeBody(toDeptId: target.dept?.id, toUserId: target.user?.id, action: action, note: note.text, dueAt: due)),
            ),
          ]),
        );
      }));
}

/// Opens the route form for [item], POSTs the route and returns the updated item (null when dismissed or failed —
/// the server error is shown inside the sheet, so the person can correct the target).
Future<WorkItem?> showGovRouteSheet(BuildContext context, GovApi api, WorkItem item, {List<Entity>? entities, String? title}) async {
  final list = entities ?? await _loadEntities(api);
  if (!context.mounted) return null;
  var target = const RouteTarget();
  var toPerson = false;
  var action = 'review';
  DateTime? due;
  String? error;
  var busy = false;
  final note = TextEditingController();
  return showAppSheet<WorkItem>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetHeader(title ?? '${t('إحالة', 'Route')} · ${item.ref}'),
            Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w700, c: ctx.colors.textMedium)),
            const SizedBox(height: AppSpace.sm),
            GovRouteForm(
              entities: list,
              target: target,
              toPerson: toPerson,
              action: action,
              note: note,
              dueAt: due,
              busy: busy,
              error: error,
              excludeDeptId: item.ownerDept?.id,
              onTargetDept: (d) => set(() {
                target = RouteTarget(dept: d);
                error = null;
              }),
              onPickPerson: () async {
                final p = await pickGovPerson(ctx, api.orgId, title: t('إحالة إلى شخص', 'Route to a person'), selectedId: target.user?.id);
                if (p != null) {
                  set(() {
                    target = RouteTarget(user: p);
                    error = null;
                  });
                }
              },
              onToPerson: (v) => set(() {
                toPerson = v;
                target = const RouteTarget();
                error = null;
              }),
              onAction: (a) => set(() => action = a),
              onDue: (d) => set(() => due = d),
              onSubmit: () async {
                if (target.isEmpty) {
                  set(() => error = govCodeTexts()['route_target_required']);
                  return;
                }
                if (target.dept != null && target.dept!.id == item.ownerDept?.id) {
                  set(() => error = govCodeTexts()['route_self']);
                  return;
                }
                set(() {
                  busy = true;
                  error = null;
                });
                final r = await orgCall(
                    () => api.route(item.id, routeBody(toDeptId: target.dept?.id, toUserId: target.user?.id, action: action, note: note.text, dueAt: due)),
                    quiet: true);
                if (!ctx.mounted) return;
                if (!r.ok) {
                  set(() {
                    busy = false;
                    error = govCodeTexts()[r.code] ?? orgErrorText(r.error!);
                  });
                  return;
                }
                appToast(t('تمت الإحالة', 'Routed'));
                Navigator.pop(ctx, WorkItem.fromJson(asMap(r.data)));
              },
            ),
          ]),
        );
      }));
}

Future<List<Entity>> _loadEntities(GovApi api) async {
  final r = await orgCall(() => api.entities(), quiet: true);
  return r.ok ? (r.data as List<Entity>) : const [];
}
