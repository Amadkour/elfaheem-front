// lib/features/org/governance/gov_institutions_s3.dart — Institutions S3 (D-971 – D-974) in the governance screens.
// Contract: docs/institutions/CONTRACT_S3.md.
//
//   AutoRule · AutoRouting · AutoRuleList   the department's ordered automatic routing rules (pure, unit-tested):
//                                           add · move · enable · remove · the PUT body · the first local problem
//   AutoRoutingEditor                       the rule cards (plain values, layout-tested)
//   GovAutoRoutingPage                      the entity page's "Automatic routing" tab: GET / PUT …/auto-routing
//   govS3EventText                          readable timeline lines for auto-route, skipped-rule and SLA events
//   DecisionTemplate · WriteItemDraft       the nine decision templates and the "Write an item" prefill rules
//   DecisionTemplatePicker                  the template dropdown + the suggested decision card
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show asInt, asMap, asMapList, asStr, dirArrow, t;
import '../org_institutions.dart' show orgFacultyRoleLabel;
import '../org_v3.dart' show OrgCall, orgCall, orgErrorText;
import 'gov_api.dart';
import 'gov_models.dart';
import 'gov_ui.dart' show pickGovPerson;

// ═════════════════════════════════════════════════════════════════════════════
//  Automatic routing rules (D-971)
// ═════════════════════════════════════════════════════════════════════════════

const autoRouteTargets = ['department', 'person', 'department_council', 'faculty_council'];
const autoRouteKinds = ['request', 'memo', 'custom'];

/// The server's default actions per target (the GET's `actions`, used before it arrives).
const autoRouteActions = {
  'department': ['approval', 'review', 'info'],
  'person': ['review', 'approval', 'info'],
  'department_council': ['vote'],
  'faculty_council': ['vote'],
};

String autoTargetLabel(String v) =>
    {
      'department': t('إدارة أو قسم', 'A department'),
      'person': t('شخص', 'A person'),
      'department_council': t('مجلس القسم', 'Department council'),
      'faculty_council': t('مجلس الكلية', 'Faculty council'),
    }[v] ??
    v;

String autoActionLabel(String v) =>
    {
      'approval': t('للاعتماد', 'For approval'),
      'review': t('للمراجعة', 'For review'),
      'info': t('للعلم', 'For information'),
      'vote': t('للتصويت', 'For a vote'),
    }[v] ??
    v;

/// Why the system skipped a rule (the timeline's `reason`).
String autoSkipReasonText(String v) =>
    {
      'audience': t('الجهة لا تستقبل من فئة مقدّم الطلب', 'the target does not take requests from this sender'),
      'target_invalid': t('الجهة المحددة لم تعد متاحة', 'the target is no longer available'),
      'route_not_allowed': t('قواعد المؤسسة لا تسمح بهذه الإحالة', "the organization's rules do not allow this route"),
      'not_a_member': t('الشخص لم يعد عضواً', 'the person is no longer a member'),
      'route_self': t('الشخص هو مقدّم الطلب نفسه', 'the person is the sender'),
    }[v] ??
    v;

class AutoRule {
  const AutoRule({
    this.id,
    this.categoryId,
    this.kind,
    this.target = 'department',
    this.deptId,
    this.userId,
    this.action,
    this.enabled = true,
    this.categoryName,
    this.deptName,
    this.userName,
  });

  final String? id;

  /// Exactly one of [categoryId] (a request type of the department) and [kind] (`request` · `memo` · `custom`).
  final int? categoryId;
  final String? kind;
  final String target;
  final int? deptId, userId;

  /// null = the server's default for [target].
  final String? action;
  final bool enabled;
  final String? categoryName, deptName, userName;

  /// The "when" dropdown's value: `c:<id>` · `k:<kind>` · '' (not chosen yet).
  String get whenKey => categoryId != null ? 'c:$categoryId' : (kind != null ? 'k:$kind' : '');

  factory AutoRule.fromJson(Map<String, dynamic> j) {
    String? name(dynamic m) {
      if (m is! Map) return null;
      final ar = asStr(m['name_ar']), en = asStr(m['name_en']), n = asStr(m['name']);
      if (ar.isEmpty && en.isEmpty) return n.isEmpty ? null : n;
      return t(ar.isEmpty ? en : ar, en.isEmpty ? ar : en);
    }

    return AutoRule(
      id: j['id']?.toString(),
      categoryId: j['category_id'] == null ? null : asInt(j['category_id']),
      kind: j['kind'] as String?,
      target: asStr(j['target'], 'department'),
      deptId: j['dept_id'] == null ? null : asInt(j['dept_id']),
      userId: j['user_id'] == null ? null : asInt(j['user_id']),
      action: j['action'] as String?,
      enabled: j['enabled'] != false,
      categoryName: name(j['category']),
      deptName: name(j['dept']),
      userName: name(j['user']),
    );
  }

  /// One rule of the PUT body: only the fields its target takes.
  Map<String, dynamic> toJson() => {
        'id': ?id,
        if (categoryId != null) 'category_id': categoryId else 'kind': ?kind,
        'target': target,
        if (target == 'department' || target == 'department_council') 'dept_id': ?deptId,
        if (target == 'person') 'user_id': ?userId,
        'action': ?action,
        'enabled': enabled,
      };

  AutoRule copyWith({
    int? categoryId,
    String? kind,
    bool clearWhen = false,
    String? target,
    int? deptId,
    bool clearDept = false,
    int? userId,
    String? userName,
    String? action,
    bool? enabled,
    String? deptName,
  }) {
    final when = clearWhen || categoryId != null || kind != null;
    final newTarget = target ?? this.target;
    final targetChanged = newTarget != this.target;
    return AutoRule(
      id: id,
      categoryId: when ? categoryId : this.categoryId,
      kind: when ? kind : this.kind,
      target: newTarget,
      deptId: clearDept || targetChanged ? deptId : (deptId ?? this.deptId),
      deptName: clearDept || targetChanged ? deptName : (deptId != null ? deptName : this.deptName),
      userId: targetChanged ? userId : (userId ?? this.userId),
      userName: targetChanged ? userName : (userId != null ? userName : this.userName),
      action: targetChanged ? (action ?? autoRouteActions[newTarget]?.first) : (action ?? this.action),
      enabled: enabled ?? this.enabled,
      categoryName: categoryName,
    );
  }

  /// The local check before the PUT (null = fine), named like the server's `field`.
  String? get problemField {
    if (categoryId == null && kind == null) return 'category_id';
    if (target == 'department' && deptId == null) return 'dept_id';
    if (target == 'person' && userId == null) return 'user_id';
    return null;
  }
}

/// The GET answer: rules + what the editor may offer.
class AutoRouting {
  const AutoRouting({
    required this.deptId,
    this.rules = const [],
    this.targets = autoRouteTargets,
    this.kinds = autoRouteKinds,
    this.actions = autoRouteActions,
    this.hasChain = false,
    this.canEdit = false,
  });

  final int deptId;
  final List<AutoRule> rules;
  final List<String> targets, kinds;
  final Map<String, List<String>> actions;
  final bool hasChain, canEdit;

  factory AutoRouting.fromJson(Map<String, dynamic> j) {
    List<String> strs(dynamic v, List<String> d) => v is List ? [for (final x in v) '$x'] : d;
    final acts = asMap(j['actions']);
    final rows = [...asMapList(j['rules'])]..sort((a, b) => asInt(a['order']).compareTo(asInt(b['order'])));
    return AutoRouting(
      deptId: asInt(j['dept_id']),
      rules: [for (final r in rows) AutoRule.fromJson(r)],
      targets: strs(j['targets'], autoRouteTargets),
      kinds: strs(j['kinds'], autoRouteKinds),
      actions: acts.isEmpty ? autoRouteActions : {for (final e in acts.entries) e.key: strs(e.value, const [])},
      hasChain: j['has_chain'] == true,
      canEdit: j['can_edit'] == true,
    );
  }
}

/// The editable ordered list. Every operation returns a new list (the editor is driven by plain values).
class AutoRuleList {
  const AutoRuleList(this.rules);
  final List<AutoRule> rules;

  static const max = 50;

  bool get canAdd => rules.length < max;

  AutoRuleList add([AutoRule rule = const AutoRule(kind: 'request', action: 'approval')]) =>
      canAdd ? AutoRuleList([...rules, rule]) : this;

  AutoRuleList replace(int i, AutoRule rule) => AutoRuleList([for (var k = 0; k < rules.length; k++) k == i ? rule : rules[k]]);

  AutoRuleList remove(int i) => AutoRuleList([for (var k = 0; k < rules.length; k++) if (k != i) rules[k]]);

  AutoRuleList toggle(int i, bool on) => replace(i, rules[i].copyWith(enabled: on));

  /// Moves rule [i] by [delta] (−1 = up); out of range = unchanged.
  AutoRuleList move(int i, int delta) {
    final j = i + delta;
    if (i < 0 || i >= rules.length || j < 0 || j >= rules.length) return this;
    final out = [...rules];
    final r = out.removeAt(i);
    out.insert(j, r);
    return AutoRuleList(out);
  }

  /// The first rule the server would refuse, as (index, field); null = send it.
  (int, String)? get problem {
    for (var i = 0; i < rules.length; i++) {
      final f = rules[i].problemField;
      if (f != null) return (i, f);
    }
    return null;
  }

  List<Map<String, dynamic>> toBody() => [for (final r in rules) r.toJson()];
}

/// What one invalid field asks the person to do.
String autoRuleFieldText(String field) =>
    {
      'category_id': t('اختر نوع الطلب', 'Pick the request type'),
      'kind': t('اختر نوع الطلب', 'Pick the request type'),
      'dept_id': t('اختر الجهة', 'Pick the department'),
      'user_id': t('اختر الشخص', 'Pick the person'),
      'target': t('اختر إلى أين يُرسل', 'Pick where it goes'),
      'action': t('اختر نوع الإحالة', 'Pick the action'),
      'rules': t('عدد القواعد كبير — الحد 50', 'Too many rules — the limit is 50'),
    }[field] ??
    field;

/// The rule cards: when → send to → (department / person) → action, with enable, up / down and delete.
class AutoRoutingEditor extends StatelessWidget {
  const AutoRoutingEditor({
    super.key,
    required this.rules,
    required this.onChanged,
    this.categories = const [],
    this.departments = const [],
    this.councilDepartments = const [],
    this.kinds = autoRouteKinds,
    this.targets = autoRouteTargets,
    this.actions = autoRouteActions,
    this.canEdit = true,
    this.errorIndex,
    this.errorField,
    this.onPickPerson,
  });

  final AutoRuleList rules;
  final ValueChanged<AutoRuleList> onChanged;

  /// The department's request types (complaint types are left out by the caller).
  final List<Category> categories;

  /// Targets of `department` (active, non-council, not this one) and of `department_council` (scientific with a
  /// council), as (id, name).
  final List<({int id, String name})> departments, councilDepartments;
  final List<String> kinds, targets;
  final Map<String, List<String>> actions;
  final bool canEdit;
  final int? errorIndex;
  final String? errorField;
  final void Function(int index)? onPickPerson;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = rules.rules;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (list.isEmpty)
        AppCard(
          child: Text(t('لا قواعد بعد — تبقى الطلبات الجديدة عند هذه الجهة حتى يحيلها رئيسها.', 'No rules yet — new requests stay with this department until its head routes them.'),
              style: AppType.label(context).copyWith(color: c.textMedium)),
        ),
      for (var i = 0; i < list.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: _RuleCard(
            index: i,
            count: list.length,
            rule: list[i],
            editor: this,
            error: errorIndex == i ? autoRuleFieldText(errorField ?? '') : null,
          ),
        ),
      if (canEdit && rules.canAdd)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppPill(icon: Icons.add_rounded, label: t('إضافة قاعدة', 'Add a rule'), onTap: () => onChanged(rules.add())),
        ),
    ]);
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.index, required this.count, required this.rule, required this.editor, this.error});
  final int index, count;
  final AutoRule rule;
  final AutoRoutingEditor editor;
  final String? error;

  void _set(AutoRule r) => editor.onChanged(editor.rules.replace(index, r));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = editor;
    final edit = e.canEdit;
    final whenItems = <DropdownMenuItem<String>>[
      if (rule.whenKey.isEmpty) DropdownMenuItem(value: '', child: Text(t('اختر…', 'Pick…'))),
      for (final k in e.kinds) DropdownMenuItem(value: 'k:$k', child: Text('${t('أي', 'Any')} ${itemTypeLabel(k)}', maxLines: 1, overflow: TextOverflow.ellipsis)),
      for (final cat in e.categories) DropdownMenuItem(value: 'c:${cat.id}', child: Text(cat.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      // a rule whose request type is no longer listed keeps its value
      if (rule.categoryId != null && !e.categories.any((x) => x.id == rule.categoryId))
        DropdownMenuItem(value: rule.whenKey, child: Text(rule.categoryName ?? '#${rule.categoryId}', maxLines: 1, overflow: TextOverflow.ellipsis)),
    ];
    final acts = e.actions[rule.target] ?? autoRouteActions[rule.target] ?? const <String>[];
    final action = rule.action ?? (acts.isEmpty ? null : acts.first);
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          AppBadgePill('${index + 1}', color: rule.enabled ? c.primary : c.textLight),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(rule.enabled ? t('مفعّلة', 'On') : t('موقوفة', 'Off'),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
          ),
          AppSwitch(value: rule.enabled, semanticLabel: t('تفعيل القاعدة ${index + 1}', 'Rule ${index + 1} on'), onChanged: edit ? (v) => e.onChanged(e.rules.toggle(index, v)) : null),
          if (edit) ...[
            IconButton(
              tooltip: t('أعلى', 'Move up'),
              onPressed: index == 0 ? null : () => e.onChanged(e.rules.move(index, -1)),
              icon: const Icon(Icons.arrow_upward_rounded, size: AppIconSize.md),
            ),
            IconButton(
              tooltip: t('أسفل', 'Move down'),
              onPressed: index == count - 1 ? null : () => e.onChanged(e.rules.move(index, 1)),
              icon: const Icon(Icons.arrow_downward_rounded, size: AppIconSize.md),
            ),
            IconButton(
              tooltip: t('حذف القاعدة', 'Delete the rule'),
              onPressed: () => e.onChanged(e.rules.remove(index)),
              icon: Icon(Icons.delete_outline_rounded, size: AppIconSize.md, color: c.danger),
            ),
          ],
        ]),
        const SizedBox(height: AppSpace.xs),
        AppDropdown<String>(
          value: rule.whenKey,
          enabled: edit,
          decoration: InputDecoration(labelText: t('عندما يصل', 'When this arrives'), prefixIcon: const Icon(Icons.inbox_rounded)),
          items: whenItems,
          onChanged: (v) {
            if (v == null || v.isEmpty) return;
            final id = v.substring(2);
            _set(v.startsWith('c:') ? rule.copyWith(categoryId: int.tryParse(id)) : rule.copyWith(kind: id));
          },
        ),
        const SizedBox(height: AppSpace.sm),
        AppDropdown<String>(
          value: rule.target,
          enabled: edit,
          decoration: InputDecoration(labelText: t('أرسله إلى', 'Send it to'), prefixIcon: const Icon(Icons.alt_route_rounded)),
          items: [for (final x in e.targets) DropdownMenuItem(value: x, child: Text(autoTargetLabel(x), maxLines: 1, overflow: TextOverflow.ellipsis))],
          onChanged: (v) {
            if (v != null && v != rule.target) _set(rule.copyWith(target: v, action: (e.actions[v] ?? autoRouteActions[v] ?? const ['review']).first));
          },
        ),
        if (rule.target == 'department') ...[
          const SizedBox(height: AppSpace.sm),
          AppDropdown<int>(
            value: rule.deptId ?? 0,
            enabled: edit,
            decoration: InputDecoration(labelText: t('الجهة', 'Department'), prefixIcon: const Icon(Icons.apartment_rounded)),
            items: [
              if (rule.deptId == null) DropdownMenuItem(value: 0, child: Text(t('اختر الجهة…', 'Pick the department…'))),
              for (final d in e.departments) DropdownMenuItem(value: d.id, child: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (rule.deptId != null && !e.departments.any((d) => d.id == rule.deptId))
                DropdownMenuItem(value: rule.deptId!, child: Text(rule.deptName ?? '#${rule.deptId}', maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              if (v != null && v != 0) _set(rule.copyWith(deptId: v, deptName: e.departments.where((d) => d.id == v).map((d) => d.name).firstOrNull));
            },
          ),
        ],
        if (rule.target == 'department_council') ...[
          const SizedBox(height: AppSpace.sm),
          AppDropdown<int>(
            value: rule.deptId ?? 0,
            enabled: edit,
            decoration: InputDecoration(labelText: t('مجلس أي قسم', "Which department's council"), prefixIcon: const Icon(Icons.groups_rounded)),
            items: [
              DropdownMenuItem(value: 0, child: Text(t('مجلس هذا القسم', "This department's council"))),
              for (final d in e.councilDepartments) DropdownMenuItem(value: d.id, child: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (rule.deptId != null && !e.councilDepartments.any((d) => d.id == rule.deptId))
                DropdownMenuItem(value: rule.deptId!, child: Text(rule.deptName ?? '#${rule.deptId}', maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              if (v == null) return;
              _set(v == 0 ? rule.copyWith(clearDept: true) : rule.copyWith(deptId: v, deptName: e.councilDepartments.where((d) => d.id == v).map((d) => d.name).firstOrNull));
            },
          ),
        ],
        if (rule.target == 'person') ...[
          const SizedBox(height: AppSpace.sm),
          OutlinedButton.icon(
            onPressed: edit && e.onPickPerson != null ? () => e.onPickPerson!(index) : null,
            icon: const Icon(Icons.person_search_rounded, size: AppIconSize.sm),
            label: Text(rule.userId == null ? t('اختر الشخص…', 'Pick the person…') : (rule.userName ?? '#${rule.userId}'), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
        if (acts.length > 1) ...[
          const SizedBox(height: AppSpace.sm),
          AppDropdown<String>(
            value: action,
            enabled: edit,
            decoration: InputDecoration(labelText: t('نوع الإحالة', 'Action'), prefixIcon: const Icon(Icons.task_alt_rounded)),
            items: [for (final a in acts) DropdownMenuItem(value: a, child: Text(autoActionLabel(a)))],
            onChanged: (v) {
              if (v != null) _set(rule.copyWith(action: v));
            },
          ),
        ] else if (action != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text(autoActionLabel(action), style: AppType.meta(context).copyWith(color: c.textMedium)),
        ],
        if (error != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text(error!, style: AppType.meta(context).copyWith(color: c.danger)),
        ],
      ]),
    );
  }
}

/// The plain explanation above the rules (and, with [hasChain], why they are not used right now).
class AutoRoutingIntro extends StatelessWidget {
  const AutoRoutingIntro({super.key, required this.deptName, this.hasChain = false});
  final String deptName;
  final bool hasChain;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
          t('عندما يصل طلب جديد إلى «$deptName» تُجرَّب القواعد بالترتيب، وأول قاعدة مفعّلة تطابقه ترسله تلقائياً. القاعدة التي لا يستطيع مقدّم الطلب الوصول إلى جهتها تُتخطّى.',
              'When a new request reaches “$deptName”, the rules are tried in order and the first enabled one that matches sends it on by itself. A rule whose target the sender cannot reach is skipped.'),
          style: AppType.label(context).copyWith(color: c.textMedium, height: 1.5)),
      const SizedBox(height: AppSpace.xs),
      Text(t('تعمل القواعد فقط عندما لا تكون للجهة سلسلة اعتماد، ولا تُطبَّق أبداً على الشكاوى.', 'Rules work only when the department has no approval chain, and never apply to complaints.'),
          style: AppType.meta(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w600)),
      if (hasChain) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(
            icon: Icons.info_outline_rounded,
            text: t('لهذه الجهة سلسلة اعتماد، فالطلبات تتبعها ولا تُستخدم هذه القواعد الآن.', 'This department has an approval chain, so requests follow it and these rules are not used now.')),
      ],
    ]);
  }
}

/// The entity page's "Automatic routing" tab.
class GovAutoRoutingPage extends StatefulWidget {
  const GovAutoRoutingPage({super.key, required this.orgId, required this.entity});
  final int orgId;
  final Entity entity;

  @override
  State<GovAutoRoutingPage> createState() => _GovAutoRoutingPageState();
}

class _GovAutoRoutingPageState extends State<GovAutoRoutingPage> {
  late final _api = GovApi(widget.orgId);
  AutoRouting? _info;
  AutoRuleList _rules = const AutoRuleList([]);
  List<Category> _cats = const [];
  List<Entity> _entities = const [];
  bool _failed = false, _busy = false, _dirty = false;
  int? _errorIndex;
  String? _errorField;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final results = await Future.wait([
      orgCall(() => _api.autoRouting(widget.entity.id), quiet: true),
      orgCall(() => _api.categories(widget.entity.id), quiet: true),
      orgCall(() => _api.entities(), quiet: true),
    ]);
    if (!mounted) return;
    final r = results[0];
    setState(() {
      _failed = !r.ok;
      if (r.ok) {
        _info = AutoRouting.fromJson(asMap(r.data));
        _rules = AutoRuleList(_info!.rules);
        _dirty = false;
      }
      if (results[1].ok) _cats = [for (final c in results[1].data as List<Category>) if (c.kind != 'complaint' && c.isActive) c];
      if (results[2].ok) _entities = results[2].data as List<Entity>;
    });
  }

  void _change(AutoRuleList v) => setState(() {
        _rules = v;
        _dirty = true;
        _errorIndex = null;
        _errorField = null;
      });

  Future<void> _pickPerson(int i) async {
    final p = await pickGovPerson(context, widget.orgId, title: t('أرسله إلى شخص', 'Send it to a person'), selectedId: _rules.rules[i].userId);
    if (p == null || !mounted) return;
    _change(_rules.replace(i, _rules.rules[i].copyWith(userId: p.id, userName: p.name)));
  }

  Future<void> _save() async {
    final local = _rules.problem;
    if (local != null) {
      setState(() {
        _errorIndex = local.$1;
        _errorField = local.$2;
      });
      showAppNotice(autoRuleFieldText(local.$2), error: true);
      return;
    }
    setState(() => _busy = true);
    final r = await orgCall(() => _api.saveAutoRouting(widget.entity.id, _rules.toBody()), quiet: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      final d = r.detail;
      setState(() {
        _errorIndex = d['index'] == null ? null : asInt(d['index']);
        _errorField = d['field']?.toString();
      });
      showAppNotice(_codeText(r), error: true);
      return;
    }
    setState(() {
      _info = AutoRouting.fromJson(asMap(r.data));
      _rules = AutoRuleList(_info!.rules);
      _dirty = false;
    });
    showAppNotice(t('حُفظت القواعد — تُطبَّق على الطلبات الجديدة', 'Saved — new requests follow these rules'));
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null && !_failed) return const AppListSkeleton(items: 3);
    if (info == null) return AppEmpty(icon: Icons.cloud_off_rounded, title: t('تعذّر التحميل', 'Could not load'), actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load);
    final self = widget.entity;
    final depts = [
      for (final x in _entities)
        if (x.id != self.id && !x.isCouncil && x.isActive) (id: x.id, name: x.name),
    ];
    final councils = [
      for (final x in _entities)
        if (x.id != self.id && x.isScientific && x.councilId != null && x.isActive) (id: x.id, name: x.name),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AutoRoutingIntro(deptName: self.name, hasChain: info.hasChain),
        const SizedBox(height: AppSpace.md),
        AutoRoutingEditor(
          rules: _rules,
          onChanged: _change,
          categories: _cats,
          departments: depts,
          councilDepartments: councils,
          kinds: info.kinds,
          targets: info.targets,
          actions: info.actions,
          canEdit: info.canEdit,
          errorIndex: _errorIndex,
          errorField: _errorField,
          onPickPerson: _pickPerson,
        ),
        if (info.canEdit) ...[
          const SizedBox(height: AppSpace.md),
          AppPrimaryButton(label: t('حفظ القواعد', 'Save the rules'), icon: Icons.save_rounded, busy: _busy, onPressed: _busy || !_dirty ? null : _save),
        ] else ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(icon: Icons.lock_outline_rounded, text: t('يعدّل القواعد رئيس الجهة أو مدير المؤسسة', "The department's head or the organization admin edits the rules")),
        ],
      ]),
    );
  }
}

String _codeText(OrgCall r) => govCodeTexts()[r.code] ?? orgErrorText(r.error!);

// ═════════════════════════════════════════════════════════════════════════════
//  Timeline lines (auto-route · skipped rule · SLA escalation)
// ═════════════════════════════════════════════════════════════════════════════

/// Who an SLA step goes to (`target_role`).
String slaTargetRoleLabel(String? role) => switch (role) {
      'head' => t('رئيس الجهة', 'The head'),
      'org_admin' => t('مدير المؤسسة', 'The organization admin'),
      null => t('لا أحد', 'Nobody'),
      _ => orgFacultyRoleLabel(role) ?? role,
    };

/// A readable line for the S3 events, or null for every other event (the timeline then builds its usual summary).
/// [routes] gives the target's name of an applied rule or an escalation (`route_id`).
String? govS3EventText(WorkEvent e, {List<WorkRoute> routes = const []}) {
  final d = e.data;
  String? routeName() {
    final id = d['route_id'];
    if (id == null) return null;
    final r = routes.where((x) => x.id == asInt(id)).firstOrNull;
    return r?.toDept?.name ?? r?.toUser?.name;
  }

  if (e.kind == 'routed' && d['auto_skipped'] == true) {
    return t('تخطّى النظام قاعدة تلقائية (${autoTargetLabel('${d['target']}')}): ${autoSkipReasonText('${d['reason']}')}',
        'An automatic rule was skipped (${autoTargetLabel('${d['target']}')}): ${autoSkipReasonText('${d['reason']}')}');
  }
  if (e.kind == 'routed' && d['auto'] == true && d['rule_id'] != null) {
    final to = routeName() ?? autoTargetLabel('${d['target']}');
    final act = d['action'] == null ? '' : ' · ${autoActionLabel('${d['action']}')}';
    return t('أُحيل تلقائياً بقاعدة الجهة $dirArrow $to$act', "Routed automatically by the department's rule $dirArrow $to$act");
  }
  if (e.kind == 'escalated' && d['sla'] == true) {
    if (d['no_target'] == true) {
      return t('تجاوز المهلة — لا يوجد وكيل أو عميد أو مدير لتصعيده إليه', 'Past its deadline — no vice dean, dean or admin to escalate it to');
    }
    final who = [slaTargetRoleLabel(d['target_role'] as String?), ?routeName()].join(' · ');
    return t('تجاوز المهلة — صُعّد تلقائياً إلى $who للمراجعة', 'Past its deadline — escalated automatically to $who for review');
  }
  return null;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Decision templates (D-973)
// ═════════════════════════════════════════════════════════════════════════════

class DecisionTemplate {
  const DecisionTemplate({
    required this.key,
    this.group = '',
    this.groupAr = '',
    this.groupEn = '',
    this.titleAr = '',
    this.titleEn = '',
    this.bodyAr = '',
    this.bodyEn = '',
    this.decisionAr = '',
    this.decisionEn = '',
  });

  final String key, group, groupAr, groupEn, titleAr, titleEn, bodyAr, bodyEn, decisionAr, decisionEn;

  static String _pick(String ar, String en) => t(ar.isEmpty ? en : ar, en.isEmpty ? ar : en);
  String get groupName => _pick(groupAr, groupEn);
  String get title => _pick(titleAr, titleEn);
  String get body => _pick(bodyAr, bodyEn);
  String get decision => _pick(decisionAr, decisionEn);

  factory DecisionTemplate.fromJson(Map<String, dynamic> j) => DecisionTemplate(
        key: asStr(j['key']),
        group: asStr(j['group']),
        groupAr: asStr(j['group_ar']),
        groupEn: asStr(j['group_en']),
        titleAr: asStr(j['title_ar']),
        titleEn: asStr(j['title_en']),
        bodyAr: asStr(j['body_ar']),
        bodyEn: asStr(j['body_en']),
        decisionAr: asStr(j['decision_ar']),
        decisionEn: asStr(j['decision_en']),
      );
}

List<DecisionTemplate> decisionTemplatesOf(List<Map<String, dynamic>> rows) =>
    [for (final r in rows) if (asStr(r['key']).isNotEmpty) DecisionTemplate.fromJson(r)];

/// The title / body of "Write an item" and the chosen template. Picking a template fills a field that is empty or
/// still holds the previous template's text; what the person typed is kept.
class WriteItemDraft {
  const WriteItemDraft({this.title = '', this.body = '', this.template});
  final String title, body;
  final DecisionTemplate? template;

  WriteItemDraft pick(DecisionTemplate? tpl) {
    final prev = template;
    bool untouched(String v, String? prevText) => v.trim().isEmpty || (prevText != null && v == prevText);
    if (tpl == null) {
      return WriteItemDraft(
        title: prev != null && title == prev.title ? '' : title,
        body: prev != null && body == prev.body ? '' : body,
      );
    }
    return WriteItemDraft(
      title: untouched(title, prev?.title) ? tpl.title : title,
      body: untouched(body, prev?.body) ? tpl.body : body,
      template: tpl,
    );
  }

  /// The server takes the title from the template when it is missing.
  bool get canSave => title.trim().isNotEmpty || template != null;

  /// The fields of `POST …/agenda/write`.
  ({String? title, String? body, String? templateKey, String? lang}) toRequest() => (
        title: title.trim().isEmpty ? null : title.trim(),
        body: body.trim().isEmpty ? null : body.trim(),
        templateKey: template?.key,
        lang: template == null ? null : (AppConfig.lang == 'en' ? 'en' : 'ar'),
      );
}

/// The template dropdown (grouped labels) and, once one is chosen, its suggested decision.
class DecisionTemplatePicker extends StatelessWidget {
  const DecisionTemplatePicker({super.key, required this.templates, required this.selected, required this.onChanged, this.enabled = true});
  final List<DecisionTemplate> templates;
  final DecisionTemplate? selected;
  final ValueChanged<DecisionTemplate?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (templates.isEmpty) return const SizedBox.shrink();
    final s = selected;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppDropdown<String>(
        value: s?.key ?? '',
        enabled: enabled,
        decoration: InputDecoration(labelText: t('قالب قرار (اختياري)', 'Decision template (optional)'), prefixIcon: const Icon(Icons.gavel_rounded)),
        items: [
          DropdownMenuItem(value: '', child: Text(t('بدون قالب', 'No template'))),
          for (final x in templates)
            DropdownMenuItem(value: x.key, child: Text(x.groupName.isEmpty ? x.title : '${x.groupName} · ${x.title}', maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => onChanged(v == null || v.isEmpty ? null : templates.where((x) => x.key == v).firstOrNull),
      ),
      if (s != null && s.decision.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xs),
        Container(
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(AppRadius.control)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('القرار المقترح', 'Suggested decision'), style: AppType.meta(context).copyWith(color: c.primary, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpace.xxs),
            Text(s.decision, style: AppType.label(context).copyWith(color: c.textDark, height: 1.5)),
          ]),
        ),
      ],
      const SizedBox(height: AppSpace.xs),
      if (s != null)
        Text(t('أكمل الفراغات المكتوبة «…» قبل الإضافة.', 'Fill the blanks written «…» before adding it.'), style: AppType.meta(context).copyWith(color: c.textMedium)),
    ]);
  }
}
