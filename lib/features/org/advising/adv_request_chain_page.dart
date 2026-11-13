// lib/features/org/advising/adv_request_chain_page.dart — the approval chain of support requests (docs/advising/
// PHASE7.md "Options and the chain", #12), for the organization and for any program / department / level / cohort
// that needs its own: the steps in order (drag, or move up / down), the advising director review only first, the
// student's department council, the faculty council, any office or committee (e.g. Student Affairs). The editor
// checks what the server would refuse (no step, more than six, the director review not first, two identical steps in
// a row, an office not chosen, a faculty council the organization does not have) and warns where a council step
// would be skipped. A scope can go back to the organization's chain (Inherit); "Preview for a student" shows the
// steps a real student's request would follow.
//
//   AdvChainEditorView  (plain values)   AdvRequestChainPage  (GET / PUT …/request-chain, …/preview)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_header.dart' show OrgPageRefresh, OrgPushedPage;
import '../org_v3.dart' show orgCall;
import 'adv_api.dart';
import 'adv_models.dart' show AdvPolicyBundle, AdvPolicyOptions, advScopeTypeLabel, advScopeTypes;
import 'adv_parts.dart';
import 'adv_request_composer.dart' show AdvChainPreviewList;
import 'adv_support_api.dart';
import 'adv_support_models.dart';
import 'adv_support_parts.dart';
import 'adv_support_texts.dart';

IconData advChainKindIcon(String kind) => switch (kind) {
      'director_review' => Icons.co_present_rounded,
      'student_department_council' => Icons.groups_2_outlined,
      'faculty_council' => Icons.account_balance_outlined,
      _ => Icons.apartment_rounded,
    };

/// A scope the editor offers: `org:` or `<type>:<ref>`, with its label.
class AdvChainScopeChoice {
  const AdvChainScopeChoice({required this.type, this.ref, required this.label});
  final String type;
  final String? ref;
  final String label;
  String get key => '$type:${ref ?? ''}';
}

class AdvChainEditorView extends StatelessWidget {
  const AdvChainEditorView({
    super.key,
    required this.config,
    required this.scopes,
    required this.scope,
    required this.steps,
    this.inherit = false,
    this.dirty = false,
    this.busy = false,
    this.error,
    this.onScope,
    this.onAddScope,
    this.onInherit,
    this.onReset,
    this.onAdd,
    this.onMove,
    this.onRemove,
    this.onSave,
    this.onPreview,
  });

  final AdvChainConfig config;
  final List<AdvChainScopeChoice> scopes;
  final AdvChainScopeChoice scope;

  /// The edited steps (the organization's when [inherit]).
  final List<AdvChainStep> steps;

  /// A program / level / … scope that uses the organization's chain.
  final bool inherit;
  final bool dirty, busy;
  final String? error;
  final ValueChanged<AdvChainScopeChoice>? onScope;
  final VoidCallback? onAddScope, onReset, onSave, onPreview;
  final ValueChanged<bool>? onInherit;

  /// Adds a step of a kind (`entity` asks which office).
  final ValueChanged<String>? onAdd;
  final void Function(int from, int to)? onMove;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final org = scope.type == 'org';
    final problem = inherit ? null : advChainProblem(steps, facultyCouncil: config.facultyCouncil, entityIds: {for (final e in config.entities) e.id});
    final hasFaculty = steps.any((s) => s.kind == 'faculty_council');
    final hasDept = steps.any((s) => s.kind == 'student_department_council');
    final editable = !inherit && !busy;
    final canDirector = editable && (steps.isEmpty || steps.first.kind != 'director_review');
    return AdvPageFrame(maxWidth: AppWidth.reading.max, children: [
      AppBanner(
        icon: Icons.account_tree_outlined,
        text: t('يمر كل طلب دعم بهذه الخطوات بالترتيب، ويرى الطالب والمرشد كل خطوة. يمكن لبرنامج أو مستوى أن يكون له مسار خاص.',
            'Every support request goes through these steps in order, and the student and the advisor see each one. A program or a level can have its own chain.'),
      ),
      AdvSectionTitle(t('النطاق', 'Scope')),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final s in scopes) AppChoiceChip(label: s.label, icon: s.type == 'org' ? Icons.domain_rounded : null, selected: s.key == scope.key, onTap: busy || onScope == null ? () {} : () => onScope!(s)),
        if (onAddScope != null)
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
            onPressed: busy ? null : onAddScope,
            icon: const Icon(Icons.add_rounded, size: AppIconSize.md),
            label: Text(t('نطاق خاص', 'A scope of its own')),
          ),
      ]),
      if (!org) ...[
        const SizedBox(height: AppSpace.xs),
        AppSwitchTile(
          icon: Icons.call_merge_rounded,
          title: t('يتبع مسار المؤسسة', 'Use the organization\'s chain'),
          subtitle: t('أوقفه ليكون لهذا النطاق مسار خاص', 'Switch it off to give this scope a chain of its own'),
          value: inherit,
          onChanged: busy || onInherit == null ? null : onInherit!,
        ),
      ] else if (config.orgInherited && !dirty) ...[
        const SizedBox(height: AppSpace.xs),
        Text(t('المؤسسة تستخدم المسار الافتراضي الآن.', 'The organization uses the default chain right now.'), style: AppType.meta(context)),
      ],
      AdvSectionTitle(t('الخطوات', 'Steps'), subtitle: inherit ? t('مسار المؤسسة (للقراءة)', 'The organization\'s chain (read only)') : null),
      if (!config.facultyCouncil && hasFaculty)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: AppBanner(
            icon: Icons.warning_amber_rounded,
            color: c.danger,
            text: t('لا مجلس كلية في هذه المؤسسة — احذف خطوة مجلس الكلية أو أنشئ المجلس من الحوكمة.', 'This organization has no faculty council — remove that step or create the council under Governance.'),
          ),
        ),
      if (config.departmentCouncils == 0 && hasDept)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: AppBanner(
            icon: Icons.info_outline_rounded,
            color: c.warning,
            text: t('لا يوجد قسم علمي له مجلس بعد — تُتجاوز خطوة مجلس قسم الطالب حتى تُنشأ المجالس.',
                'No scientific department has a council yet — the student\'s department council step is skipped until they exist.'),
          ),
        ),
      if (steps.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
          child: Text(t('لا خطوات بعد — أضف خطوة.', 'No steps yet — add one.'), style: AppType.body(context)),
        )
      else
        Opacity(
          opacity: inherit ? 0.6 : 1,
          child: ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: steps.length,
            onReorderItem: (from, to) {
              if (!editable || onMove == null) return;
              onMove!(from, to);
            },
            itemBuilder: (context, i) => _StepRow(
              key: ValueKey('chain.$i.${steps[i].kind}.${steps[i].deptId}'),
              index: i,
              step: steps[i],
              entity: steps[i].kind == 'entity' ? config.entity(steps[i].deptId)?.name : null,
              last: i == steps.length - 1,
              wrong: problem != null && problem.$1 == i,
              editable: editable,
              onUp: editable && i > 0 && onMove != null ? () => onMove!(i, i - 1) : null,
              onDown: editable && i < steps.length - 1 && onMove != null ? () => onMove!(i, i + 1) : null,
              onRemove: editable && onRemove != null ? () => onRemove!(i) : null,
            ),
          ),
        ),
      if (editable && onAdd != null) ...[
        const SizedBox(height: AppSpace.xs),
        Text(t('إضافة خطوة', 'Add a step'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpace.xxs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final k in config.kinds)
            if ((k.key != 'faculty_council' || config.facultyCouncil) && (k.key != 'director_review' || canDirector))
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
                onPressed: steps.length >= advChainMaxSteps ? null : () => onAdd!(k.key),
                icon: Icon(advChainKindIcon(k.key), size: AppIconSize.md),
                label: Text(k.label),
              ),
        ]),
        if (steps.length >= advChainMaxSteps)
          Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: Text(t('الحد الأقصى $advChainMaxSteps خطوات', 'At most $advChainMaxSteps steps'), style: AppType.meta(context))),
      ],
      if (problem != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: advChainProblemText(problem.$2, index: problem.$2 == 'empty' ? null : problem.$1)),
      ],
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(icon: Icons.check_rounded, label: t('حفظ المسار', 'Save the chain'), busy: busy, onPressed: dirty && problem == null ? onSave : null),
      const SizedBox(height: AppSpace.xs),
      Wrap(alignment: WrapAlignment.center, spacing: AppSpace.xs, children: [
        if (onPreview != null) AdvSmallAction(icon: Icons.visibility_outlined, label: t('معاينة لطالب', 'Preview for a student'), onTap: busy ? null : onPreview),
        if (org && onReset != null) AdvSmallAction(icon: Icons.restart_alt_rounded, label: t('المسار الافتراضي', 'Back to the default chain'), onTap: busy ? null : onReset),
      ]),
    ]);
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({super.key, required this.index, required this.step, this.entity, required this.last, this.wrong = false, this.editable = true, this.onUp, this.onDown, this.onRemove});
  final int index;
  final AdvChainStep step;
  final String? entity;
  final bool last, wrong, editable;
  final VoidCallback? onUp, onDown, onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = step.kind == 'entity' ? (entity ?? (step.label.isEmpty ? t('اختر جهة', 'Choose an office') : step.label)) : step.label;
    final hint = advChainKindHint(step.kind);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Container(
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: wrong ? c.danger : c.divider, width: wrong ? AppBorder.strong : AppBorder.hairline),
        ),
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xs, AppSpace.xs, AppSpace.xxs, AppSpace.xs),
        child: Row(children: [
          if (editable)
            ReorderableDragStartListener(
              index: index,
              child: Semantics(
                label: t('اسحب لإعادة الترتيب', 'Drag to reorder'),
                child: SizedBox(width: AppTouch.min * 0.75, height: AppTouch.min, child: Icon(Icons.drag_indicator_rounded, color: c.textLight)),
              ),
            ),
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.primary.withValues(alpha: 0.12)),
            child: Text('${index + 1}', style: AppType.meta(context).copyWith(color: appInk(context, c.primary), fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: AppSpace.sm),
          ExcludeSemantics(child: Icon(advChainKindIcon(step.kind), size: AppIconSize.md, color: c.textMedium)),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
              Text(step.kind == 'entity' ? advChainKindLabel('entity') : hint, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ]),
          ),
          if (onUp != null || onDown != null || onRemove != null)
            PopupMenuButton<String>(
              tooltip: t('خيارات الخطوة', 'Step options'),
              icon: Icon(Icons.more_vert_rounded, color: c.textMedium),
              onSelected: (v) => switch (v) {
                'up' => onUp?.call(),
                'down' => onDown?.call(),
                _ => onRemove?.call(),
              },
              itemBuilder: (_) => [
                if (onUp != null) PopupMenuItem(value: 'up', height: AppTouch.min, child: Text(t('نقل لأعلى', 'Move up'))),
                if (onDown != null) PopupMenuItem(value: 'down', height: AppTouch.min, child: Text(t('نقل لأسفل', 'Move down'))),
                if (onRemove != null) PopupMenuItem(value: 'remove', height: AppTouch.min, child: Text(t('حذف الخطوة', 'Remove the step'))),
              ],
            ),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class AdvRequestChainPage extends StatelessWidget {
  const AdvRequestChainPage({super.key, required this.orgId});
  final int orgId;

  @override
  Widget build(BuildContext context) => OrgPushedPage(
        title: t('مسار اعتماد الطلبات', 'Request approval chain'),
        helpPageId: 'org.advising',
        maxWidth: AppWidth.reading.max,
        child: _ChainBody(orgId: orgId),
      );
}

class _ChainBody extends StatefulWidget {
  const _ChainBody({required this.orgId});
  final int orgId;

  @override
  State<_ChainBody> createState() => _ChainBodyState();
}

class _ChainBodyState extends State<_ChainBody> {
  late final AdvSupportApi _api = AdvSupportApi(widget.orgId);
  OrgPageRefresh? _refresh;
  AdvChainConfig? _config;
  AdvPolicyOptions _options = const AdvPolicyOptions();
  AdvLoad _load = AdvLoad.loading;
  String? _error, _saveError;
  bool _busy = false, _dirty = false, _inherit = false;
  AdvChainScopeChoice _scope = AdvChainScopeChoice(type: 'org', label: t('المؤسسة', 'Organization'));

  /// Scopes added in this session that are not saved yet.
  final List<AdvChainScopeChoice> _added = [];
  List<AdvChainStep> _steps = const [];

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _reload);
    _reload();
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final cCall = orgCall(() => _api.chain(), quiet: true);
    final pCall = orgCall(() => AdvApi(widget.orgId).policy(), quiet: true);
    final r = await cCall;
    final p = await pCall;
    if (!mounted) return;
    setState(() {
      if (p.ok) _options = (p.data as AdvPolicyBundle).options;
      if (r.ok) {
        _config = r.data as AdvChainConfig;
        _load = AdvLoad.ready;
        _show(_scope);
      } else {
        _load = advFailLoad(r);
        _error = advSupportErrorText(r.error!);
      }
    });
    if (r.ok && mounted) OrgPageRefresh.reportUpdated(context);
  }

  List<AdvChainScopeChoice> get _scopes {
    final c = _config;
    final list = [AdvChainScopeChoice(type: 'org', label: t('المؤسسة', 'Organization'))];
    for (final s in c?.scopes ?? const <AdvChainScope>[]) {
      list.add(AdvChainScopeChoice(type: s.scopeType, ref: s.scopeRef, label: '${advScopeTypeLabel(s.scopeType)}: ${s.label}'));
    }
    for (final a in _added) {
      if (!list.any((x) => x.key == a.key)) list.add(a);
    }
    return list;
  }

  /// Shows [s]'s steps (no setState: the callers wrap it).
  void _show(AdvChainScopeChoice s) {
    final c = _config;
    if (c == null) return;
    _scope = s;
    _dirty = false;
    _saveError = null;
    final own = c.stepsOf(s.type, s.ref);
    if (s.type == 'org') {
      _inherit = false;
      _steps = [...(own == null || own.isEmpty ? c.defaults : own)];
    } else if (own == null) {
      // a new scope starts as a copy of the organization's chain, switched to its own
      final added = _added.any((a) => a.key == s.key);
      _inherit = !added;
      _steps = [...(c.orgSteps.isEmpty ? c.defaults : c.orgSteps)];
      _dirty = added;
    } else {
      _inherit = false;
      _steps = [...own];
    }
  }

  Future<bool> _discard() async {
    if (!_dirty) return true;
    return appConfirm(context, danger: true, confirmLabel: t('تجاهل', 'Discard'), message: t('تجاهل التغييرات غير المحفوظة؟', 'Discard the unsaved changes?'));
  }

  Future<void> _pickScope(AdvChainScopeChoice s) async {
    if (s.key == _scope.key || !await _discard() || !mounted) return;
    setState(() => _show(s));
  }

  Future<void> _addScope() async {
    if (!await _discard() || !mounted) return;
    var type = advScopeTypes.first;
    String? ref;
    final picked = await showAppSheet<AdvChainScopeChoice>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final refs = _options.refs(type);
          return AppSheetContent(
            title: t('مسار خاص لنطاق', 'A chain for one scope'),
            children: [
              AdvFieldLabel(t('النوع', 'Kind')),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (final ty in advScopeTypes)
                  AppChoiceChip(
                    label: advScopeTypeLabel(ty),
                    selected: ty == type,
                    onTap: () => set(() {
                      type = ty;
                      ref = null;
                    }),
                  ),
              ]),
              const SizedBox(height: AppSpace.md),
              if (refs.isEmpty)
                Text(t('لا قيم لهذا النوع في المؤسسة.', 'The organization has no values of this kind.'), style: AppType.body(ctx))
              else
                AppDropdown<String>(
                  value: ref,
                  decoration: InputDecoration(labelText: advScopeTypeLabel(type)),
                  items: [for (final (v, l) in refs) DropdownMenuItem(value: v, child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => set(() => ref = v),
                ),
              const SizedBox(height: AppSpace.md),
              AppPrimaryButton(
                icon: Icons.add_rounded,
                label: t('إضافة', 'Add'),
                onPressed: ref == null
                    ? null
                    : () {
                        final label = refs.where((x) => x.$1 == ref).firstOrNull?.$2 ?? ref!;
                        Navigator.pop(ctx, AdvChainScopeChoice(type: type, ref: ref, label: '${advScopeTypeLabel(type)}: $label'));
                      },
              ),
            ],
          );
        }));
    if (picked == null || !mounted) return;
    setState(() {
      if (!_added.any((a) => a.key == picked.key)) _added.add(picked);
      _show(picked);
    });
  }

  Future<void> _add(String kind) async {
    final c = _config;
    if (c == null) return;
    AdvChainStep step;
    if (kind == 'entity') {
      final e = await showAppSheet<AdvSupportEntity>(context, (ctx) => AppSheetContent(
            title: t('اختر الإدارة أو اللجنة', 'Choose the office or committee'),
            children: [
              if (c.entities.isEmpty)
                Text(t('لا إدارات أو لجان نشطة — أضفها من الحوكمة ← الجهات.', 'There are no active offices or committees — add them under Governance → Entities.'), style: AppType.body(ctx))
              else
                for (final x in c.entities)
                  AdvRowCard(
                    title: x.name,
                    subtitle: advPresetLabel(x.preset).isEmpty ? null : advPresetLabel(x.preset),
                    leading: Icon(Icons.apartment_rounded, color: ctx.colors.primary),
                    onTap: () => Navigator.pop(ctx, x),
                  ),
            ],
          ));
      if (e == null || !mounted) return;
      step = AdvChainStep(kind: 'entity', deptId: e.id, labelAr: e.nameAr, labelEn: e.nameEn);
    } else {
      step = AdvChainStep(kind: kind);
    }
    setState(() {
      _steps = kind == 'director_review' ? [step, ..._steps] : [..._steps, step];
      _dirty = true;
      _saveError = null;
    });
  }

  void _move(int from, int to) {
    if (from == to || from < 0 || to < 0 || from >= _steps.length || to >= _steps.length) return;
    setState(() {
      final l = [..._steps];
      final s = l.removeAt(from);
      l.insert(to, s);
      _steps = l;
      _dirty = true;
      _saveError = null;
    });
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _saveError = null;
    });
    final s = _scope;
    final r = await orgCall(() => _api.saveChain(scopeType: s.type, scopeRef: s.ref, steps: _inherit ? null : _steps), quiet: true);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!r.ok) {
        _saveError = advSupportErrorText(r.error!);
        return;
      }
      _config = r.data as AdvChainConfig;
      _added.removeWhere((a) => a.key == s.key);
      _show(_inherit ? AdvChainScopeChoice(type: 'org', label: t('المؤسسة', 'Organization')) : s);
    });
    if (r.ok) showAppNotice(t('حُفظ مسار الاعتماد', 'Approval chain saved'));
  }

  Future<void> _preview() async {
    final st = await pickAdvStudent(context, AdvApi(widget.orgId), title: t('معاينة المسار لطالب', 'Preview the chain for a student'));
    if (st == null || !mounted) return;
    AdvChainPreview? p;
    String? err;
    var started = false;
    await showAppSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          if (!started) {
            started = true;
            orgCall(() => _api.previewChain(st.memberId), quiet: true).then((r) {
              if (!ctx.mounted) return;
              set(() {
                if (r.ok) {
                  p = r.data as AdvChainPreview;
                } else {
                  err = advSupportErrorText(r.error!);
                }
              });
            });
          }
          return AppSheetContent(
            title: t('مسار طلب ${st.shown}', 'The chain for ${st.shown}'),
            children: [
              Text(t('المسار المحفوظ الذي يتبعه طلب هذا الطالب الآن.', 'The saved chain this student\'s request follows now.'), style: AppType.meta(ctx)),
              const SizedBox(height: AppSpace.sm),
              if (err != null)
                AppBanner(icon: Icons.error_outline_rounded, color: ctx.colors.danger, text: err!)
              else if (p == null)
                const AppListSkeleton(items: 3, withAvatar: false, padding: EdgeInsets.zero)
              else
                AdvChainPreviewList(steps: p!.steps, advisingDept: p!.advisingDept?.name),
            ],
          );
        }));
  }

  @override
  Widget build(BuildContext context) {
    final c = _config;
    if (_load != AdvLoad.ready || c == null) {
      return AdvLoadState(
          state: _load == AdvLoad.ready ? AdvLoad.loading : _load,
          errorText: _error,
          onRetry: () {
            setState(() => _load = AdvLoad.loading);
            _reload();
          });
    }
    return AdvChainEditorView(
      config: c,
      scopes: _scopes,
      scope: _scope,
      steps: _inherit ? (c.orgSteps.isEmpty ? c.defaults : c.orgSteps) : _steps,
      inherit: _inherit,
      dirty: _dirty,
      busy: _busy,
      error: _saveError,
      onScope: _pickScope,
      onAddScope: _addScope,
      onInherit: (v) => setState(() {
        _inherit = v;
        if (!v && _steps.isEmpty) _steps = [...(c.orgSteps.isEmpty ? c.defaults : c.orgSteps)];
        // switching an own chain back to the organization's is saved like any change; a never-saved scope is simply
        // left
        _dirty = c.stepsOf(_scope.type, _scope.ref) != null || !v;
      }),
      onReset: () => setState(() {
        _steps = [...c.defaults];
        _dirty = true;
      }),
      onAdd: _add,
      onMove: _move,
      onRemove: (i) => setState(() {
        _steps = [..._steps]..removeAt(i);
        _dirty = true;
      }),
      onSave: _save,
      onPreview: _preview,
    );
  }
}
