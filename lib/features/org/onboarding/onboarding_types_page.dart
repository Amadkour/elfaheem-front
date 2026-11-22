// lib/features/org/onboarding/onboarding_types_page.dart — the types of member onboarding (D-1200), for whoever holds
// `onboarding:update` (kill switch `org.onboarding`).
//
//   OnbTypesPage    every type with its active switch; tap → the editor; "Apply a preset" (apply or replace, with a
//                   confirm: replacing drops the custom types)
//   OnbTypeEditor   one type: name, the entry policy, auto-activation, the fields (label and level), the documents
//                   (level, accepted types, size, "can be brought later") and the chain of approval steps. Saving
//                   sends the WHOLE type (the server replaces the object). Plain values + callbacks, so the layout
//                   harness pumps it.
//   OnbEntryPolicyPicker  the plain "How do students join?" picker (contract §7.2, plan 4.2a): direct · after review
//                   · by invitation · by a link or code, and for the reviewed ones "Who decides?": whoever holds the
//                   approve right · a named person (`need.user_ids`) · a council or committee (`need.council_id`; its
//                   approval records a decision number and date). Choosing a person or a body makes the chain that
//                   one step; it writes `settings.entry_policy` and the chain, nothing else.
//   OnbChoiceCard   the selectable card both pickers (and the Add student sheet) draw.
//
// Fields that map to case columns (`system`) can change label and level but are never removed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import '../../admin/admin_common.dart' show t, asMapList;
import '../governance/gov_api.dart' show GovApi;
import '../governance/gov_council_ui.dart' show pickOrgMember;
import '../org_page_header.dart' show OrgPushedPage;
import '../org_v3.dart' show orgErrorText;
import 'onboarding_api.dart';
import 'onboarding_import.dart' show onboardingIntakeKey;
import 'onboarding_intake.dart';
import 'onboarding_models.dart';

const _acceptChoices = ['jpg', 'png', 'pdf'];

class OnbTypesPage extends StatefulWidget {
  const OnbTypesPage({super.key, required this.orgId, this.api});
  final int orgId;
  final OnboardingApi? api;

  @override
  State<OnbTypesPage> createState() => _OnbTypesPageState();
}

class _OnbTypesPageState extends State<OnbTypesPage> {
  late final OnboardingApi _api = widget.api ?? OnboardingApi();
  List<OnbType> _types = const [];
  List<OnbPreset> _presets = const [];
  bool _loading = true;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final rs = await Future.wait([_api.types(widget.orgId), _api.presets(widget.orgId)]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!rs[0].ok) {
        _error = rs[0].error;
        return;
      }
      _types = asMapList(rs[0].data is List ? rs[0].data : rs[0].map['items']).map(OnbType.fromJson).toList();
      _presets = rs[1].ok ? asMapList(rs[1].data is List ? rs[1].data : rs[1].map['items']).map(OnbPreset.fromJson).toList() : const [];
    });
  }

  Future<void> _toggle(OnbType ty, bool on) async {
    final r = await _api.saveType(widget.orgId, ty.key, ty.copyWith(active: on).toJson());
    if (!mounted) return;
    if (!r.ok) {
      showAppNotice(orgErrorText(r.error!), error: true);
      return;
    }
    setState(() => _types = [for (final x in _types) x.key == ty.key ? OnbType.fromJson(r.map).copyWith() : x]);
  }

  Future<void> _edit(OnbType ty) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => OnbTypeEditorPage(orgId: widget.orgId, type: ty, api: _api)));
    if (saved == true && mounted) _load();
  }

  Future<void> _preset() async {
    final r = await showOnbPresetSheet(context, _presets);
    if (r == null || !mounted) return;
    if (r.replace && !await appConfirm(context, danger: true, message: t('استبدال الأنواع الحالية بالقالب؟ تُحذف الأنواع المخصصة.', 'Replace the current types with the preset? Custom types are removed.'))) return;
    final res = await _api.applyPreset(widget.orgId, r.key, replace: r.replace);
    if (!mounted) return;
    if (!res.ok) {
      showAppNotice(orgErrorText(res.error!), error: true);
      return;
    }
    showAppNotice(t('طُبّق القالب', 'Preset applied'));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return ParentComponent(
      featureKey: onboardingFeatureKey,
      child: OrgPushedPage(
        title: t('أنواع الالتحاق والتعيين', 'Admission & appointment types'),
        subtitle: t('الحقول والمستندات ومراحل الاعتماد', 'Fields, documents and approval steps'),
        helpPageId: 'org.onboarding.types',
        width: AppWidth.content,
        primaryAction: AppButton.tonal(key: const ValueKey('onb.types.preset'), label: t('تطبيق قالب', 'Apply a preset'), icon: Icons.auto_awesome_motion_outlined, size: AppButtonSize.sm, onPressed: _presets.isEmpty ? null : _preset),
        child: OnbTypesList(types: _types, loading: _loading, error: _error, onRetry: _load, onToggle: _toggle, onOpen: _edit),
      ),
    );
  }
}

class OnbTypesList extends StatelessWidget {
  const OnbTypesList({super.key, required this.types, required this.loading, this.error, this.onRetry, this.onToggle, this.onOpen});
  final List<OnbType> types;
  final bool loading;
  final Object? error;
  final VoidCallback? onRetry;
  final void Function(OnbType, bool)? onToggle;
  final void Function(OnbType)? onOpen;

  @override
  Widget build(BuildContext context) {
    return AppStateView<List<OnbType>>(
      loading: loading,
      error: error,
      data: loading || error != null ? null : types,
      onRetry: onRetry,
      isEmpty: (l) => l.isEmpty,
      empty: AppEmpty(icon: Icons.rule_folder_outlined, title: t('لا أنواع بعد', 'No types yet'), message: t('طبّق قالباً جاهزاً للبدء.', 'Apply a ready preset to start.')),
      builder: (context, list) => ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xxxl),
        children: [
          for (final ty in list)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: AppCard(
                key: ValueKey('onb.type.${ty.key}'),
                onTap: onOpen == null ? null : () => onOpen!(ty),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(ty.label.isEmpty ? ty.key : ty.label, style: AppType.bodyStrong(context)),
                      AppSpace.gapXs,
                      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                        AppStatusBadge(label: onbModuleLabel(ty.module), tone: AppTone.brand, dense: true),
                        AppStatusBadge(label: onbEntryPolicyLabel(ty.settings.entryPolicy), tone: AppTone.info, dense: true),
                        AppStatusBadge(label: t('${ty.fields.length} حقل', '${ty.fields.length} fields'), tone: AppTone.neutral, dense: true),
                        AppStatusBadge(label: t('${ty.documents.length} مستند', '${ty.documents.length} documents'), tone: AppTone.neutral, dense: true),
                        AppStatusBadge(label: t('${ty.chain.length} مرحلة', '${ty.chain.length} steps'), tone: AppTone.neutral, dense: true),
                      ]),
                    ]),
                  ),
                  AppSwitch(key: ValueKey('onb.type.active.${ty.key}'), value: ty.active, onChanged: onToggle == null ? null : (v) => onToggle!(ty, v)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Editor
// ═════════════════════════════════════════════════════════════════════════════

class OnbTypeEditorPage extends StatefulWidget {
  const OnbTypeEditorPage({super.key, required this.orgId, required this.type, this.api});
  final int orgId;
  final OnbType type;
  final OnboardingApi? api;

  @override
  State<OnbTypeEditorPage> createState() => _OnbTypeEditorPageState();
}

class _OnbTypeEditorPageState extends State<OnbTypeEditorPage> {
  late final OnboardingApi _api = widget.api ?? OnboardingApi();
  bool _busy = false;

  Future<void> _save(OnbType ty) async {
    setState(() => _busy = true);
    final r = await _api.saveType(widget.orgId, ty.key, ty.toJson());
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showAppNotice(orgErrorText(r.error!), error: true);
      return;
    }
    showAppNotice(t('حُفظ النوع', 'Type saved'));
    Navigator.of(context).pop(true);
  }

  Future<OnbPick?> _pickPerson(Set<int> exclude) async {
    final u = await pickOrgMember(context, widget.orgId, title: t('من يراجع الملفات؟', 'Who reviews the files?'), exclude: exclude);
    return u == null ? null : OnbPick(u.id, u.name);
  }

  Future<OnbPick?> _pickCouncil() async {
    List<OnbPick> bodies;
    try {
      bodies = [for (final c in await GovApi(widget.orgId).councils()) OnbPick(c.id, c.name.isEmpty ? '#${c.id}' : c.name)];
    } catch (e) {
      if (mounted) showAppNotice(ApiException.from(e).message, error: true);
      return null;
    }
    if (!mounted) return null;
    if (bodies.isEmpty) {
      showAppNotice(t('لا توجد مجالس بعد. أنشئ المجلس من صفحة الحوكمة أولاً.', 'There are no councils yet. Create one on the Governance page first.'), error: true);
      return null;
    }
    return showAppSheet<OnbPick>(
      context,
      (ctx) => AppSheetContent(title: t('أي مجلس يعتمد؟', 'Which council approves?'), icon: Icons.groups_2_outlined, children: [
        for (final b in bodies)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: OnbChoiceCard(
              key: ValueKey('onb.council.${b.id}'),
              icon: Icons.groups_2_outlined,
              title: b.name,
              onTap: () => Navigator.of(ctx).pop(b),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OrgPushedPage(
      title: widget.type.label.isEmpty ? widget.type.key : widget.type.label,
      subtitle: t('تعديل النوع', 'Edit the type'),
      helpPageId: 'org.onboarding.types',
      width: AppWidth.reading,
      child: OnbTypeEditor(
        type: widget.type,
        busy: _busy,
        onSave: _save,
        onPickPerson: _pickPerson,
        onPickCouncil: _pickCouncil,
        footer: AppConfig.disableList.contains(onboardingIntakeKey) ? null : OnbIntakePanel(orgId: widget.orgId, type: widget.type, api: _api),
      ),
    );
  }
}

class OnbTypeEditor extends StatefulWidget {
  const OnbTypeEditor({super.key, required this.type, required this.onSave, this.busy = false, this.footer, this.onPickPerson, this.onPickCouncil});
  final OnbType type;
  final bool busy;
  final void Function(OnbType) onSave;

  /// Extra panels after the approval steps (the intake link).
  final Widget? footer;

  /// Picks a member of the organization (not one of the given ids) for a named-person step; null = the option is off.
  final Future<OnbPick?> Function(Set<int> exclude)? onPickPerson;

  /// Picks a council for a body step; null = the option is off.
  final Future<OnbPick?> Function()? onPickCouncil;

  @override
  State<OnbTypeEditor> createState() => _OnbTypeEditorState();
}

class _OnbTypeEditorState extends State<OnbTypeEditor> {
  late OnbType _type = widget.type;
  late final _ar = TextEditingController(text: widget.type.labelAr), _en = TextEditingController(text: widget.type.labelEn);

  @override
  void dispose() {
    _ar.dispose();
    _en.dispose();
    super.dispose();
  }

  void _field(int i, OnbField f) => setState(() => _type = _type.copyWith(fields: [..._type.fields]..[i] = f));
  void _doc(int i, OnbDocReq d) => setState(() => _type = _type.copyWith(documents: [..._type.documents]..[i] = d));

  Future<void> _editField(int i) async {
    final f = await showOnbFieldSheet(context, _type.fields[i]);
    if (f != null) _field(i, f);
  }

  Future<void> _editDoc(int i) async {
    final d = await showOnbDocSheet(context, _type.documents[i]);
    if (d != null) _doc(i, d);
  }

  // ── entry policy ───────────────────────────────────────────────────────────

  void _setPolicy(String p) => setState(() =>
      _type = _type.copyWith(settings: _type.settings.copyWith(entryPolicy: p, autoActivate: p == 'direct' ? true : null)));

  void _setChain(List<OnbChainStep> chain) => setState(() => _type = _type.copyWith(chain: chain));

  Future<void> _setDecider(OnbDecider d) async {
    switch (d) {
      case OnbDecider.right:
        if (onbDeciderOf(_type.chain) != OnbDecider.right) {
          _setChain([OnbChainStep(key: 'approve', labelAr: 'الاعتماد', labelEn: 'Approval', need: {'module': _type.module, 'action': 'approve'})]);
        }
      case OnbDecider.people:
        final p = await widget.onPickPerson?.call(const {});
        if (p == null || !mounted) return;
        _setChain([OnbChainStep(key: 'person', labelAr: p.name, labelEn: p.name, need: {'user_ids': [p.id]})]);
      case OnbDecider.council:
        final b = await widget.onPickCouncil?.call();
        if (b == null || !mounted) return;
        _setChain([OnbChainStep(key: 'council', labelAr: b.name, labelEn: b.name, need: {'council_id': b.id})]);
    }
  }

  /// Adds one more named person to the people step.
  Future<void> _addPerson() async {
    final i = _type.chain.indexWhere((s) => s.kind == 'people');
    if (i < 0) return;
    final s = _type.chain[i];
    final p = await widget.onPickPerson?.call(s.userIds.toSet());
    if (p == null || !mounted) return;
    final names = [s.labelAr, p.name].where((x) => x.isNotEmpty).join('، ');
    final namesEn = [s.labelEn, p.name].where((x) => x.isNotEmpty).join(', ');
    _setChain([..._type.chain]..[i] = s.copyWith(labelAr: names, labelEn: namesEn, need: {'user_ids': [...s.userIds, p.id]}));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.md), children: [
          AppField(key: const ValueKey('onb.editor.ar'), controller: _ar, label: t('الاسم بالعربية', 'Name in Arabic'), required: true),
          AppField(key: const ValueKey('onb.editor.en'), controller: _en, label: t('الاسم بالإنجليزية', 'Name in English'), ltr: true),
          AppSwitchTile(
            key: const ValueKey('onb.editor.active'),
            title: t('النوع مفعّل', 'Type is active'),
            subtitle: t('الأنواع غير المفعّلة لا تظهر عند الإضافة.', 'Inactive types are not offered when adding.'),
            value: _type.active,
            onChanged: (v) => setState(() => _type = _type.copyWith(active: v)),
          ),
          AppSpace.gapSm,
          OnbEntryPolicyPicker(
            key: const ValueKey('onb.editor.policy'),
            policy: _type.settings.entryPolicy,
            chain: _type.chain,
            onPolicy: _setPolicy,
            onDecider: _setDecider,
            peopleOn: widget.onPickPerson != null,
            councilOn: widget.onPickCouncil != null,
            onAddPerson: widget.onPickPerson == null ? null : _addPerson,
          ),
          AppSpace.gapSm,
          AppSwitchTile(
            key: const ValueKey('onb.editor.auto'),
            title: t('تفعيل العضوية فور القبول', 'Activate the membership on approval'),
            subtitle: t('عند الإيقاف يُفعِّل المسؤول العضوية يدوياً بعد القبول.', 'When off, staff activate the membership by hand after approval.'),
            value: _type.settings.autoActivate,
            onChanged: (v) => setState(() => _type = _type.copyWith(settings: _type.settings.copyWith(autoActivate: v))),
          ),
          AppSpace.gapSm,
          AppSectionTitle(t('الحقول', 'Fields')),
          for (var i = 0; i < _type.fields.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: AppCard(
                key: ValueKey('onb.editor.field.${_type.fields[i].key}'),
                padding: const EdgeInsets.all(AppSpace.sm),
                onTap: () => _editField(i),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_type.fields[i].label.isEmpty ? _type.fields[i].key : _type.fields[i].label, style: AppType.bodyStrong(context)),
                      Text(onbGroupLabel(_type.fields[i].group), style: AppType.meta(context)),
                    ]),
                  ),
                  AppSpace.gapXs,
                  _LevelChip(level: _type.fields[i].required, conditionalOk: _type.fields[i].when != null),
                ]),
              ),
            ),
          AppSpace.gapSm,
          AppSectionTitle(t('المستندات', 'Documents')),
          for (var i = 0; i < _type.documents.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: AppCard(
                key: ValueKey('onb.editor.doc.${_type.documents[i].key}'),
                padding: const EdgeInsets.all(AppSpace.sm),
                onTap: () => _editDoc(i),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(_type.documents[i].label.isEmpty ? _type.documents[i].key : _type.documents[i].label, style: AppType.bodyStrong(context))),
                    AppSpace.gapXs,
                    _LevelChip(level: _type.documents[i].required, conditionalOk: _type.documents[i].when != null),
                  ]),
                  AppSpace.gapXs,
                  Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                    for (final a in _type.documents[i].accept) AppStatusBadge(label: a.toUpperCase(), tone: AppTone.neutral, dense: true),
                    AppStatusBadge(label: t('${_type.documents[i].maxMb} ميجابايت', '${_type.documents[i].maxMb} MB'), tone: AppTone.neutral, dense: true),
                    if (_type.documents[i].allowLater) AppStatusBadge(label: t('يمكن لاحقاً', 'Can be later'), tone: AppTone.info, dense: true),
                  ]),
                ]),
              ),
            ),
          AppSpace.gapSm,
          AppSectionTitle(t('مراحل الاعتماد', 'Approval steps')),
          if (_type.chain.isEmpty) Text(t('لا مراحل: يُقبل الطلب بصلاحية الوحدة.', 'No steps: the module permission approves.'), style: AppType.meta(context)),
          for (var i = 0; i < _type.chain.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: AppCard(
                key: ValueKey('onb.editor.step.$i'),
                padding: const EdgeInsets.all(AppSpace.sm),
                child: Row(children: [
                  CircleAvatar(radius: AppSpace.sm, backgroundColor: c.primaryTint, child: Text('${i + 1}', style: AppType.meta(context).copyWith(color: c.primary))),
                  AppSpace.gapSm,
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_type.chain[i].label.isEmpty ? _type.chain[i].key : _type.chain[i].label, style: AppType.bodyStrong(context)),
                      Text(_type.chain[i].needText, style: AppType.meta(context)),
                    ]),
                  ),
                ]),
              ),
            ),
          if (widget.footer != null) ...[AppSpace.gapSm, widget.footer!],
        ]),
      ),
      Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: AppButton.primary(
          key: const ValueKey('onb.editor.save'),
          label: t('حفظ', 'Save'),
          expand: true,
          busy: widget.busy,
          onPressed: widget.busy ? null : () => widget.onSave(_type.copyWith(labelAr: _ar.text.trim(), labelEn: _en.text.trim())),
        ),
      ),
    ]);
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.level, this.conditionalOk = false});
  final String level;
  final bool conditionalOk;

  @override
  Widget build(BuildContext context) => AppStatusBadge(
      label: onbRequiredLabel(level), tone: level == 'mandatory' ? AppTone.warning : (level == 'conditional' ? AppTone.info : AppTone.neutral), dense: true);
}

/// The three levels as a segmented choice.
class _LevelPicker extends StatelessWidget {
  const _LevelPicker({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => AppTabs(
        expand: true,
        index: onbRequiredLevels.indexOf(value).clamp(0, 2),
        items: [for (final l in onbRequiredLevels) AppTabItem(onbRequiredLabel(l))],
        onChanged: (i) => onChanged(onbRequiredLevels[i]),
      );
}

/// Label (both languages) and level of a field. A system field keeps its key and cannot be dropped.
Future<OnbField?> showOnbFieldSheet(BuildContext context, OnbField f) {
  final ar = TextEditingController(text: f.labelAr), en = TextEditingController(text: f.labelEn);
  var level = f.required;
  return showAppSheet<OnbField>(context, (ctx) {
    return StatefulBuilder(
      builder: (ctx, set) => AppSheetContent(title: f.label.isEmpty ? f.key : f.label, children: [
        AppField(controller: ar, label: t('الاسم بالعربية', 'Name in Arabic')),
        AppField(controller: en, label: t('الاسم بالإنجليزية', 'Name in English'), ltr: true),
        AppFieldLabel(t('المستوى', 'Level')),
        _LevelPicker(value: level, onChanged: (v) => set(() => level = v)),
        if (level == 'conditional' && f.when == null)
          Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text(t('الحقل المشروط يلزم له شرط (النوع أو السن…) يضعه القالب.', 'A conditional field needs a condition (gender, age, …) that the preset sets.'), style: AppType.meta(ctx))),
        AppSpace.gapSm,
        AppButton.primary(label: t('تطبيق', 'Apply'), expand: true, onPressed: () => Navigator.of(ctx).pop(f.copyWith(labelAr: ar.text.trim(), labelEn: en.text.trim(), required: level))),
      ]),
    );
  }).whenComplete(() {
    ar.dispose();
    en.dispose();
  });
}

/// Label, level, accepted file types, size limit and "can be brought later" of a document.
Future<OnbDocReq?> showOnbDocSheet(BuildContext context, OnbDocReq d) {
  final ar = TextEditingController(text: d.labelAr), en = TextEditingController(text: d.labelEn);
  var level = d.required, mb = d.maxMb, later = d.allowLater, original = d.originalNeeded;
  final accept = {...d.accept};
  return showAppSheet<OnbDocReq>(context, (ctx) {
    return StatefulBuilder(
      builder: (ctx, set) => AppSheetContent(title: d.label.isEmpty ? d.key : d.label, children: [
        AppField(controller: ar, label: t('الاسم بالعربية', 'Name in Arabic')),
        AppField(controller: en, label: t('الاسم بالإنجليزية', 'Name in English'), ltr: true),
        AppFieldLabel(t('المستوى', 'Level')),
        _LevelPicker(value: level, onChanged: (v) => set(() => level = v)),
        AppSpace.gapSm,
        AppFieldLabel(t('أنواع الملفات', 'File types')),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final a in _acceptChoices)
            FilterChip(
              label: Text(a.toUpperCase()),
              selected: accept.contains(a),
              onSelected: (v) => set(() {
                if (v) {
                  accept.add(a);
                } else if (accept.length > 1) {
                  accept.remove(a);
                }
              }),
            ),
        ]),
        AppSpace.gapSm,
        AppNumberField(label: t('الحد الأقصى (ميجابايت)', 'Max size (MB)'), initialValue: mb, min: 1, max: 20, onChanged: (v) => mb = (v ?? mb).toInt()),
        AppSwitchTile(title: t('يمكن إحضاره لاحقاً', 'Can be brought later'), value: later, onChanged: (v) => set(() => later = v)),
        AppSwitchTile(title: t('الأصل مطلوب', 'Original needed'), value: original, onChanged: (v) => set(() => original = v)),
        AppSpace.gapSm,
        AppButton.primary(
          label: t('تطبيق', 'Apply'),
          expand: true,
          onPressed: () => Navigator.of(ctx).pop(d.copyWith(labelAr: ar.text.trim(), labelEn: en.text.trim(), required: level, accept: accept.toList(), maxMb: mb, allowLater: later, originalNeeded: original)),
        ),
      ]),
    );
  }).whenComplete(() {
    ar.dispose();
    en.dispose();
  });
}

/// The preset picked in [showOnbPresetSheet].
class OnbPresetPick {
  const OnbPresetPick(this.key, this.replace);
  final String key;
  final bool replace;
}

/// Pick a preset and whether it replaces the current types (default: only adds what is missing).
Future<OnbPresetPick?> showOnbPresetSheet(BuildContext context, List<OnbPreset> presets) {
  String? key = presets.isEmpty ? null : presets.first.key;
  var replace = false;
  return showAppSheet<OnbPresetPick>(context, (ctx) {
    return StatefulBuilder(builder: (ctx, set) {
      final cur = presets.where((p) => p.key == key).firstOrNull;
      return AppSheetContent(title: t('تطبيق قالب', 'Apply a preset'), children: [
        AppFieldLabel(t('القالب', 'Preset')),
        AppDropdown<String>(
          key: const ValueKey('onb.preset.pick'),
          value: key,
          items: [for (final p in presets) DropdownMenuItem(value: p.key, child: Text(p.label.isEmpty ? p.key : p.label, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => set(() => key = v),
        ),
        if (cur != null && cur.types.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text(cur.types.join(' · '), style: AppType.meta(ctx))),
        AppSwitchTile(
          key: const ValueKey('onb.preset.replace'),
          title: t('استبدال الأنواع الحالية', 'Replace the current types'),
          subtitle: t('وإلا تُضاف الأنواع الناقصة فقط.', 'Otherwise only the missing types are added.'),
          value: replace,
          onChanged: (v) => set(() => replace = v),
        ),
        AppSpace.gapSm,
        AppButton.primary(key: const ValueKey('onb.preset.apply'), label: t('تطبيق', 'Apply'), expand: true, onPressed: key == null ? null : () => Navigator.of(ctx).pop(OnbPresetPick(key!, replace))),
      ]);
    });
  });
}

// ═════════════════════════════════════════════════════════════════════════════
//  Entry policy
// ═════════════════════════════════════════════════════════════════════════════

/// A picked person or council: its id and the name shown.
class OnbPick {
  const OnbPick(this.id, this.name);
  final int id;
  final String name;
}

/// Who decides a reviewed file.
enum OnbDecider { right, people, council }

/// The decider a chain stands for: a body step wins, then named people, else the approve right (or a role).
OnbDecider onbDeciderOf(List<OnbChainStep> chain) {
  if (chain.any((s) => s.kind == 'council')) return OnbDecider.council;
  if (chain.any((s) => s.kind == 'people')) return OnbDecider.people;
  return OnbDecider.right;
}

IconData onbEntryPolicyIcon(String p) => switch (p) {
      'direct' => Icons.bolt_rounded,
      'invitation' => Icons.forward_to_inbox_outlined,
      'code' => Icons.qr_code_2_rounded,
      _ => Icons.fact_check_outlined,
    };

/// "How do students join?" over plain values: four policy cards, then (except for a direct entry) "Who decides?".
class OnbEntryPolicyPicker extends StatelessWidget {
  const OnbEntryPolicyPicker({
    super.key,
    required this.policy,
    required this.chain,
    required this.onPolicy,
    this.onDecider,
    this.onAddPerson,
    this.peopleOn = true,
    this.councilOn = true,
  });

  final String policy;
  final List<OnbChainStep> chain;
  final ValueChanged<String> onPolicy;
  final ValueChanged<OnbDecider>? onDecider;

  /// "Add another person" under a named-person step; null = hidden.
  final VoidCallback? onAddPerson;
  final bool peopleOn, councilOn;

  String _note(String p) => switch (p) {
        'direct' => t('يكفي أن يؤكد الموظف الذي يملك صلاحية القبول، فيصبح الطالب مقيداً فوراً.',
            'A staff member who may approve confirms, and the student is enrolled at once.'),
        'invitation' => t('أدخل البيانات الأساسية واختر "حفظ ودعوة": يكمل الطالب ملفه بنفسه.',
            'Enter the basics and choose "Save and invite": the student completes the file.'),
        'code' => t('فعّل رابط التقديم في أسفل الصفحة وشاركه أو اطبع رمز QR.',
            'Turn on the intake link at the bottom of this page and share it or print its QR code.'),
        _ => t('يدخل الموظف الملف كاملاً ثم يمر بخطوة الاعتماد.', 'Staff enter the full file, then it goes through approval.'),
      };

  String _deciderTitle(OnbDecider d) => switch (d) {
        OnbDecider.right => t('من يملك صلاحية القبول', 'Whoever holds the approve right'),
        OnbDecider.people => t('شخص محدد بالاسم', 'A named person'),
        OnbDecider.council => t('مجلس أو لجنة', 'A council or committee'),
      };

  IconData _deciderIcon(OnbDecider d) => switch (d) {
        OnbDecider.right => Icons.verified_user_outlined,
        OnbDecider.people => Icons.person_search_outlined,
        OnbDecider.council => Icons.groups_2_outlined,
      };

  String _deciderText(OnbDecider d, OnbDecider current, OnbChainStep? people, OnbChainStep? body) {
    switch (d) {
      case OnbDecider.right:
        return t('أي موظف لديه الصلاحية يراجع ويقبل.', 'Any staff member with the right reviews and approves.');
      case OnbDecider.people:
        if (current == d && people != null && people.label.isNotEmpty) return people.label;
        return t('تصل الملفات إليه وحده ليراجعها.', 'Files go to that person alone for review.');
      case OnbDecider.council:
        if (current == d && body != null && body.label.isNotEmpty) {
          return '${body.label} · ${t('يُسجَّل رقم القرار وتاريخه', 'the decision number and date are recorded')}';
        }
        return t('يُعتمد الملف بقرار له رقم وتاريخ.', 'A file is approved by a decision with a number and a date.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final decider = onbDeciderOf(chain);
    final people = chain.where((s) => s.kind == 'people').firstOrNull;
    final body = chain.where((s) => s.kind == 'council').firstOrNull;
    bool off(OnbDecider d) => onDecider == null || (d == OnbDecider.people && !peopleOn) || (d == OnbDecider.council && !councilOn);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionTitle(t('كيف يلتحق الطلاب؟', 'How do students join?')),
      Text(t('اختر طريقة واحدة، ويمكن تغييرها في أي وقت.', 'Pick one way. You can change it at any time.'),
          style: AppType.meta(context).copyWith(color: c.textMedium)),
      AppSpace.gapXs,
      for (final p in onbEntryPolicies)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: OnbChoiceCard(
            key: ValueKey('onb.policy.$p'),
            icon: onbEntryPolicyIcon(p),
            title: onbEntryPolicyLabel(p),
            subtitle: onbEntryPolicyHint(p),
            selected: policy == p,
            onTap: () => onPolicy(p),
          ),
        ),
      AppBanner(icon: Icons.lightbulb_outline_rounded, color: c.primary, text: _note(policy)),
      if (policy != 'direct') ...[
        AppSpace.gapSm,
        AppFieldLabel(t('من يقرر قبول الملف؟', 'Who decides on a file?')),
        for (final d in OnbDecider.values)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: OnbChoiceCard(
              key: ValueKey('onb.decider.${d.name}'),
              dense: true,
              icon: _deciderIcon(d),
              title: _deciderTitle(d),
              subtitle: _deciderText(d, decider, people, body),
              selected: decider == d,
              onTap: off(d) ? null : () => onDecider!(d),
            ),
          ),
        if (decider == OnbDecider.people && onAddPerson != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.ghost(
              key: const ValueKey('onb.decider.add'),
              label: t('إضافة شخص آخر', 'Add another person'),
              icon: Icons.person_add_alt_rounded,
              size: AppButtonSize.sm,
              onPressed: onAddPerson,
            ),
          ),
      ],
    ]);
  }
}

/// A selectable card: a tinted icon, a title that wraps, one or two sentences and (when [selected] is not null) a
/// round mark. The selected one wears the primary edge and tint; a card without [onTap] is dimmed.
class OnbChoiceCard extends StatelessWidget {
  const OnbChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.selected,
    this.onTap,
    this.badge,
    this.dense = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// null = not a choice (a chevron instead of the mark).
  final bool? selected;
  final VoidCallback? onTap;

  /// A short pill after the title ("Recommended").
  final String? badge;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = selected == true;
    final motion = AppMotion.of(context);
    final enabled = onTap != null;
    final box = dense ? AppIconSize.xl : AppTouch.min - AppSpace.xxs;
    final sub = subtitle;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: Opacity(
        opacity: enabled || on ? 1 : 0.55,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.cardAll,
            child: AnimatedContainer(
              duration: motion.fast,
              curve: AppMotion.curve,
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              padding: EdgeInsets.all(dense ? AppSpace.xs : AppSpace.sm),
              decoration: BoxDecoration(
                color: on ? Color.alphaBlend(c.primaryTint, c.cardBg) : c.cardBg,
                borderRadius: AppRadius.cardAll,
                border: Border.all(color: on ? c.primary : c.cardEdge, width: on ? AppBorder.strong : AppBorder.hairline),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: box,
                  height: box,
                  decoration: BoxDecoration(color: appTintOn(context, c.primary), borderRadius: AppRadius.chipAll),
                  child: Icon(icon, size: dense ? AppIconSize.sm : AppIconSize.md, color: c.primary),
                ),
                AppSpace.gapSm,
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(title, style: AppType.bodyStrong(context)),
                      if (badge != null) AppStatusBadge(label: badge!, tone: AppTone.success, dense: true),
                    ]),
                    if (sub != null && sub.isNotEmpty) ...[
                      const SizedBox(height: AppSpace.xxs / 2),
                      Text(sub, style: AppType.meta(context).copyWith(color: c.textMedium)),
                    ],
                  ]),
                ),
                AppSpace.gapXs,
                if (selected == null)
                  Icon(Icons.chevron_right_rounded, color: c.textMedium, size: AppIconSize.md)
                else
                  Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                      color: on ? c.primary : c.textMedium, size: AppIconSize.md),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
