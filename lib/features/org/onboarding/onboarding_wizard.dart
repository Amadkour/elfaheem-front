// lib/features/org/onboarding/onboarding_wizard.dart — the one-person wizard of member onboarding (D-1200).
//
//   OnbWizard       steps by field group: identity → personal → academic / appointment → guardian (only when the type
//                   asks for one) → documents → review. The national ID comes first: a valid one fills the birth date
//                   and gender and shows the governorate. Fields are drawn by kind; a field with a `when` appears and
//                   disappears while the person types. Every step change saves the changed keys (POST for the first
//                   save, PATCH after), with a small "Saved" mark. `mode` is staff or applicant, so Phase C reuses it.
//   OnbWizardPage   the wizard in an OrgPushedPage
//   OnbPlaces       departments and programs for the `department` / `program` kinds
//
// The pure rules are in onboarding_rules.dart; the screen holds only state and layout.
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t, asMapList, asInt, asStr;
import '../org_page_header.dart' show OrgPushedPage;
import '../org_providers.dart' show orgBase;
import '../org_v3.dart' show OrgCall, orgCall, orgErrorText;
import 'package:flutter_education_app/core/api_client.dart';
import 'onboarding_api.dart';
import 'onboarding_models.dart';
import 'onboarding_review.dart' show showGeneratedPassword;
import 'onboarding_rules.dart';

enum OnbMode { staff, applicant }

/// Departments and programs the `department` / `program` fields choose from (id → name).
class OnbPlaces {
  const OnbPlaces({this.departments = const {}, this.programs = const {}});
  final Map<int, String> departments, programs;

  /// Loads both lists of organization [orgId]; empty maps when a call fails.
  static Future<OnbPlaces> load(int orgId) async {
    final base = '$orgBase/orgs/$orgId';
    final rs = await Future.wait([
      orgCall(() => ApiClient().get('$base/departments'), quiet: true),
      orgCall(() => ApiClient().get('$base/academic/programs'), quiet: true),
    ]);
    Map<int, String> names(OrgCall r) => r.ok
        ? {
            for (final m in asMapList(r.map['items']).where((p) => p['is_active'] != false))
              asInt(m['id']): t(asStr(m['name_ar'] ?? m['name']), asStr(m['name_en'] ?? m['name'])),
          }
        : const {};
    return OnbPlaces(departments: names(rs[0]), programs: names(rs[1]));
  }
}

/// The groups the wizard folds into one step each (contract §2 `group`).
const _stepGroups = <String, List<String>>{
  'identity': ['identity'],
  'personal': ['personal'],
  'academic': ['academic', 'appointment', 'other'],
  'guardian': ['guardian'],
};

class _WStep {
  const _WStep(this.id, this.groups);
  final String id; // identity | personal | academic | guardian | documents | review
  final List<String> groups;
}

String _stepTitle(String id) => switch (id) {
      'identity' => t('الهوية', 'Identity'),
      'personal' => t('البيانات الشخصية', 'Personal details'),
      'academic' => t('الأكاديمي والتعيين', 'Academic & appointment'),
      'guardian' => t('ولي الأمر', 'Guardian'),
      'documents' => t('المستندات', 'Documents'),
      _ => t('المراجعة', 'Review'),
    };

const _nationalities = <String, ({String ar, String en})>{
  'EG': (ar: 'مصري', en: 'Egyptian'),
  'SA': (ar: 'سعودي', en: 'Saudi'),
  'SD': (ar: 'سوداني', en: 'Sudanese'),
  'SY': (ar: 'سوري', en: 'Syrian'),
  'YE': (ar: 'يمني', en: 'Yemeni'),
  'LY': (ar: 'ليبي', en: 'Libyan'),
  'PS': (ar: 'فلسطيني', en: 'Palestinian'),
  'JO': (ar: 'أردني', en: 'Jordanian'),
  'IQ': (ar: 'عراقي', en: 'Iraqi'),
  'XX': (ar: 'أخرى', en: 'Other'),
};

class OnbWizard extends StatefulWidget {
  const OnbWizard({
    super.key,
    required this.orgId,
    required this.type,
    this.mode = OnbMode.staff,
    this.initial,
    this.api,
    this.places,
    this.canApproveNow = false,
    this.initialStep = 0,
    this.onDone,
  });

  final int orgId;
  final OnbType type;
  final OnbMode mode;

  /// An existing case to continue (a draft, or one that needs correction).
  final OnbCase? initial;
  final OnboardingApi? api;

  /// null: loaded from the server.
  final OnbPlaces? places;

  /// Staff who may approve: the last step also offers "Approve and activate now" (the case exists since the first save, so it is submit + approve; D-1203).
  final bool canApproveNow;
  final int initialStep;

  /// Called with the latest case when the wizard closes (submitted, or saved as a draft).
  final void Function(OnbCase? saved)? onDone;

  @override
  State<OnbWizard> createState() => _OnbWizardState();
}

class _OnbWizardState extends State<OnbWizard> {
  late final OnboardingApi _api = widget.api ?? OnboardingApi();
  final _values = <String, dynamic>{};
  final _ctrls = <String, TextEditingController>{};
  final _dirty = <String>{};
  final _errors = <String, String>{};
  final _later = <String>{};
  final _uploading = <String>{};
  late int _step = widget.initialStep;
  OnbCase? _case;
  List<OnbDocRecord> _docs = const [];
  OnbPlaces _places = const OnbPlaces();
  String _maskedNid = '';
  bool _saving = false, _saved = false, _busy = false;
  String? _banner;

  OnbType get _type => widget.type;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    if (c != null) {
      _case = c;
      _docs = c.documents;
      _values.addAll(c.values);
      _maskedNid = c.nidMasked;
      _saved = true;
    } else {
      _values['nationality'] = 'EG';
    }
    if (widget.places != null) {
      _places = widget.places!;
    } else {
      OnbPlaces.load(widget.orgId).then((p) {
        if (mounted) setState(() => _places = p);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── steps ──────────────────────────────────────────────────────────────────

  bool _hasVisible(List<String> groups) => _type.fields.any((f) => groups.contains(f.group) && fieldVisible(f, _values));

  List<_WStep> get _steps {
    final out = <_WStep>[];
    for (final e in _stepGroups.entries) {
      if (_hasVisible(e.value)) out.add(_WStep(e.key, e.value));
    }
    if (_type.documents.any((d) => docVisible(d, _values))) out.add(const _WStep('documents', []));
    out.add(const _WStep('review', []));
    return out;
  }

  List<OnbField> _fieldsOf(_WStep s) => [for (final f in _type.fields) if (s.groups.contains(f.group) && fieldVisible(f, _values)) f];

  TextEditingController _ctrl(String key) => _ctrls.putIfAbsent(key, () {
        final v = _values[key];
        return TextEditingController(text: v == null ? '' : '$v');
      });

  void _set(String key, Object? v, {bool dirty = true}) {
    _values[key] = v;
    if (dirty) _dirty.add(key);
    _errors.remove(key);
    _saved = false;
  }

  // ── the national ID drives the form ────────────────────────────────────────

  void _onNid(String key, String raw) {
    final clean = cleanNid(raw);
    setState(() {
      _set(key, clean);
      if (key == 'national_id') {
        _values['nid_kind'] = 'national_id';
        if (clean.length == 14) {
          final r = parseEgyptianNid(clean);
          if (r.ok) {
            final i = r.info!;
            _set('birth_date', i.birthIso);
            _set('gender', i.gender);
            _values['governorate'] = i.governorate;
            _ctrls['birth_date']?.text = i.birthIso;
          } else {
            final m = nidErrorText(r.error!);
            _errors[key] = t(m.ar, m.en);
            _values.remove('governorate');
          }
        } else {
          _values.remove('governorate');
        }
      } else {
        _values['nid_kind'] = 'passport';
      }
    });
  }

  // ── validation of one step ─────────────────────────────────────────────────

  bool _validate(List<OnbField> fields) {
    final err = <String, String>{};
    for (final f in fields) {
      final raw = _values[f.key];
      final text = raw is String ? raw.trim() : '';
      final need = onbIsRequired(f.required, f.when, _values) || (f.required == 'mandatory');
      if (need && !hasValue(raw)) {
        err[f.key] = t('هذا الحقل مطلوب', 'This field is required');
        continue;
      }
      if (text.isEmpty) continue;
      if (f.key == 'national_id' && text != _maskedNid) {
        final r = parseEgyptianNid(text);
        if (!r.ok) {
          final m = nidErrorText(r.error!);
          err[f.key] = t(m.ar, m.en);
        } else {
          final i = r.info!;
          final b = '${_values['birth_date'] ?? ''}', g = '${_values['gender'] ?? ''}';
          if ((b.isNotEmpty && b != i.birthIso) || (g.isNotEmpty && g != i.gender)) {
            err[f.key] = t('الرقم القومي لا يطابق تاريخ الميلاد أو النوع المُدخل', 'The national ID does not match the birth date or gender entered');
          }
        }
      } else if (f.key == 'passport_no' && !validPassport(text)) {
        err[f.key] = t('رقم الجواز من 5 إلى 20 حرفاً أو رقماً', 'A passport number has 5 to 20 letters or digits');
      } else if (f.kind == 'email' && !validEmail(text)) {
        err[f.key] = t('بريد إلكتروني غير صالح', 'Not a valid e-mail address');
      } else if (f.kind == 'phone' && normalizeContactPhone(text) == null) {
        err[f.key] = t('رقم هاتف غير صالح', 'Not a valid phone number');
      }
    }
    setState(() => _errors
      ..removeWhere((k, _) => fields.any((f) => f.key == k))
      ..addAll(err));
    return err.isEmpty;
  }

  // ── saving ─────────────────────────────────────────────────────────────────

  Object? _wire(String key) {
    final v = _values[key];
    final f = _type.field(key);
    if (v is String) {
      if (key == 'national_id' || key == 'passport_no') return key == 'national_id' ? cleanNid(v) : v.trim();
      if (f?.kind == 'phone') return normalizeContactPhone(v) ?? v.trim();
      return v.trim();
    }
    return v;
  }

  Map<String, dynamic> _payload() {
    final keys = [..._dirty];
    if (keys.contains('national_id') && _values['national_id'] == _maskedNid) keys.remove('national_id');
    final out = <String, dynamic>{for (final k in keys) if (k != 'governorate') k: _wire(k)};
    if (out.containsKey('national_id') || out.containsKey('passport_no')) out['nid_kind'] = out.containsKey('national_id') ? 'national_id' : 'passport';
    return out;
  }

  /// Saves what changed. Returns false (and shows why) when the server refuses.
  Future<bool> _save() async {
    final body = _payload();
    if (_case != null && body.isEmpty) return true;
    if (_case == null && body.isEmpty) return true;
    setState(() {
      _saving = true;
      _banner = null;
    });
    final r = _case == null
        ? await _api.createCase(widget.orgId, typeKey: _type.key, fields: body)
        : await _api.patchCase(widget.orgId, _case!.id, body);
    if (!mounted) return false;
    if (!r.ok) {
      setState(() {
        _saving = false;
        _banner = orgErrorText(r.error!);
      });
      return false;
    }
    final c = OnbCase.fromJson(r.map);
    setState(() {
      _saving = false;
      _saved = true;
      _case = c;
      _dirty.clear();
      if (c.documents.isNotEmpty) _docs = c.documents;
      if (c.nidMasked.isNotEmpty) _maskedNid = c.nidMasked;
      for (final w in c.warnings) {
        final txt = t(asStr(w['ar']), asStr(w['en']));
        if (txt.isNotEmpty) _banner = txt;
      }
    });
    return true;
  }

  Future<void> _next() async {
    final steps = _steps;
    final s = steps[_step.clamp(0, steps.length - 1)];
    if (s.groups.isNotEmpty && !_validate(_fieldsOf(s))) return;
    if (!await _save()) return;
    if (!mounted) return;
    setState(() => _step = (_step + 1).clamp(0, _steps.length - 1));
  }

  Future<void> _back() async {
    final steps = _steps;
    final s = steps[_step.clamp(0, steps.length - 1)];
    if (s.groups.isNotEmpty) await _save();
    if (!mounted) return;
    setState(() => _step = (_step - 1).clamp(0, _steps.length - 1));
  }

  Future<void> _saveAndClose() async {
    setState(() => _busy = true);
    final ok = await _save();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      showAppNotice(t('حُفظت المسودة', 'Draft saved'));
      widget.onDone?.call(_case);
    }
  }

  Future<void> _submit({bool approve = false}) async {
    final fields = _type.fields.where((f) => fieldVisible(f, _values)).toList();
    if (!_validate(fields)) {
      setState(() => _banner = t('أكمل الحقول المطلوبة أولاً', 'Complete the required fields first'));
      return;
    }
    setState(() => _busy = true);
    if (!await _save()) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    var r = await _api.submit(widget.orgId, _case!.id);
    if (r.ok && approve) r = await _api.approve(widget.orgId, _case!.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      setState(() => _banner = orgErrorText(r.error!));
      return;
    }
    final c = OnbCase.fromJson(r.map);
    showAppNotice(approve ? t('قُدِّم الطلب وفُعِّل', 'Approved and activated') : t('قُدِّم الطلب', 'Submitted'));
    if (c.generatedPassword != null) await showGeneratedPassword(context, c.generatedPassword!, name: c.fullName);
    if (mounted) widget.onDone?.call(c);
  }

  // ── documents ──────────────────────────────────────────────────────────────

  Future<void> _upload(OnbDocReq d) async {
    if (_case == null && !await _save()) return;
    if (_case == null) {
      setState(() => _banner = t('أدخل الاسم أو الرقم القومي أولاً', 'Enter the name or the national ID first'));
      return;
    }
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: [...d.accept, if (d.accept.contains('jpg')) 'jpeg']);
    if (f == null || !mounted) return;
    final size = f.lengthSync() ?? await f.length() ?? 0;
    if (!mounted) return;
    if (d.maxMb > 0 && size > d.maxMb * 1024 * 1024) {
      showAppNotice(t('الملف أكبر من ${d.maxMb} ميجابايت', 'The file is larger than ${d.maxMb} MB'), error: true);
      return;
    }
    setState(() => _uploading.add(d.key));
    final r = await _api.uploadDocument(widget.orgId, _case!.id,
        reqKey: d.key, fileName: f.name, path: kIsWeb ? null : f.path, bytes: kIsWeb ? await f.readAsBytes() : null);
    if (!mounted) return;
    setState(() => _uploading.remove(d.key));
    if (!r.ok) {
      showAppNotice(orgErrorText(r.error!), error: true);
      return;
    }
    final rec = OnbDocRecord.fromJson(r.map);
    setState(() {
      _docs = [..._docs.where((x) => x.reqKey != d.key), rec];
      _later.remove(d.key);
    });
    final w = asMapList(r.map['warnings']);
    if (w.isNotEmpty) showAppNotice(t(asStr(w.first['ar']), asStr(w.first['en'])));
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final i = _step.clamp(0, steps.length - 1);
    final s = steps[i];
    final c = context.colors;
    final last = i == steps.length - 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xs),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(t('الخطوة ${i + 1} من ${steps.length}', 'Step ${i + 1} of ${steps.length}'),
                  key: const ValueKey('onb.wizard.progress'), style: AppType.meta(context)),
            ),
            _SavedMark(saving: _saving, saved: _saved && _case != null),
          ]),
          AppSpace.gapXs,
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(value: (i + 1) / steps.length, minHeight: AppSpace.xxs, backgroundColor: c.divider),
          ),
          AppSpace.gapXs,
          Text(_stepTitle(s.id), style: AppType.section(context)),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.md),
          children: [
            if (_banner != null) ...[
              AppBanner(icon: Icons.info_outline_rounded, color: c.warning, text: _banner!),
              AppSpace.gapSm,
            ],
            if (s.id == 'documents')
              ..._documentsStep()
            else if (s.id == 'review')
              ..._reviewStep()
            else
              for (final f in _fieldsOf(s)) _fieldWidget(f),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xs,
          children: [
            if (i > 0) AppButton.secondary(key: const ValueKey('onb.wizard.back'), label: t('السابق', 'Back'), onPressed: _busy ? null : _back),
            if (!last) AppButton.primary(key: const ValueKey('onb.wizard.next'), label: t('التالي', 'Next'), busy: _saving, onPressed: _busy ? null : _next),
          ],
        ),
      ),
    ]);
  }

  // ── fields ─────────────────────────────────────────────────────────────────

  Widget _fieldWidget(OnbField f) {
    final locked = widget.mode == OnbMode.applicant && (_case?.lockedFields.contains(f.key) ?? false);
    final required = f.required == 'mandatory' || onbIsRequired(f.required, f.when, _values);
    final err = _errors[f.key];
    final help = f.help.isEmpty ? null : f.help;
    final label = f.label.isEmpty ? f.key : f.label;
    switch (f.kind) {
      case 'checkbox':
        return AppSwitchTile(
          key: ValueKey('onb.field.${f.key}'),
          title: label,
          subtitle: help,
          value: _values[f.key] == true,
          onChanged: locked ? null : (v) => setState(() => _set(f.key, v)),
        );
      case 'select':
      case 'nationality':
      case 'department':
      case 'program':
        final opts = _optionsOf(f);
        final cur = '${_values[f.key] ?? ''}';
        return _Labeled(
          label: label,
          required: required,
          error: err,
          help: help,
          child: AppDropdown<String>(
            key: ValueKey('onb.field.${f.key}'),
            value: opts.containsKey(cur) ? cur : null,
            hint: Text(t('اختر', 'Choose')),
            enabled: !locked,
            items: [for (final e in opts.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() {
              if (f.kind == 'department' || f.kind == 'program') {
                _set(f.key, v == null ? null : int.tryParse(v));
              } else {
                _set(f.key, v);
              }
            }),
          ),
        );
      case 'multiselect':
        final sel = <String>{for (final x in (_values[f.key] is List ? _values[f.key] as List : const [])) '$x'};
        return _Labeled(
          label: label,
          required: required,
          error: err,
          help: help,
          child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final o in f.options)
              FilterChip(
                label: Text(o.label),
                selected: sel.contains(o.value),
                onSelected: locked
                    ? null
                    : (v) => setState(() {
                          final n = {...sel};
                          v ? n.add(o.value) : n.remove(o.value);
                          _set(f.key, n.toList());
                        }),
              ),
          ]),
        );
      case 'date':
        final iso = '${_values[f.key] ?? ''}';
        final day = parseIsoDay(iso);
        return _Labeled(
          label: label,
          required: required,
          error: err,
          help: help,
          child: OutlinedButton.icon(
            key: ValueKey('onb.field.${f.key}'),
            onPressed: locked ? null : () => _pickDate(f),
            icon: const Icon(Icons.event_rounded),
            label: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(day == null ? t('اختر التاريخ', 'Pick a date') : AppTime.date(DateTime.utc(day.year, day.month, day.day, 12)), overflow: TextOverflow.ellipsis),
            ),
          ),
        );
      default:
        return _textField(f, label: label, required: required, error: err, help: help, locked: locked);
    }
  }

  Map<String, String> _optionsOf(OnbField f) {
    switch (f.kind) {
      case 'nationality':
        return {for (final e in _nationalities.entries) e.key: t(e.value.ar, e.value.en)};
      case 'department':
        return {for (final e in _places.departments.entries) '${e.key}': e.value};
      case 'program':
        return {for (final e in _places.programs.entries) '${e.key}': e.value};
      default:
        if (f.options.isEmpty && f.key == 'gender') return {'m': t('ذكر', 'Male'), 'f': t('أنثى', 'Female')};
        return {for (final o in f.options) o.value: o.label};
    }
  }

  Future<void> _pickDate(OnbField f) async {
    final now = DateTime.now();
    final cur = parseIsoDay(_values[f.key]);
    final picked = await showDatePicker(
      context: context,
      initialDate: cur ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null && mounted) setState(() => _set(f.key, isoDate(picked)));
  }

  Widget _textField(OnbField f, {required String label, required bool required, String? error, String? help, required bool locked}) {
    final isNid = f.kind == 'national_id' || f.key == 'national_id';
    final isPassport = f.key == 'passport_no';
    final numeric = isNid || f.kind == 'number' || f.kind == 'level';
    final extra = isNid && _values['governorate'] != null ? _governorateLine('${_values['governorate']}') : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppField(
        key: ValueKey('onb.field.${f.key}'),
        controller: _ctrl(f.key),
        label: label,
        required: required,
        helper: help,
        errorText: error,
        enabled: !locked,
        ltr: isNid || isPassport || f.kind == 'email' || f.kind == 'phone' || numeric,
        maxLines: f.kind == 'textarea' ? 3 : 1,
        maxLength: isNid ? 20 : null,
        keyboard: f.kind == 'email'
            ? TextInputType.emailAddress
            : f.kind == 'phone'
                ? TextInputType.phone
                : numeric
                    ? TextInputType.number
                    : (f.kind == 'textarea' ? TextInputType.multiline : TextInputType.text),
        inputFormatters: numeric && !isNid ? [FilteringTextInputFormatter.digitsOnly] : null,
        onChanged: (v) => (isNid || isPassport) ? _onNid(f.key, v) : setState(() => _set(f.key, v)),
      ),
      if (extra != null) Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: extra),
    ]);
  }

  Widget? _governorateLine(String code) {
    final g = egyptGovernorates[code];
    if (g == null) return null;
    final born = parseIsoDay(_values['birth_date']);
    return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
      AppStatusBadge(key: const ValueKey('onb.nid.governorate'), label: t(g.ar, g.en), tone: AppTone.info, icon: Icons.place_outlined, dense: true),
      if (born != null) AppStatusBadge(label: AppTime.date(DateTime.utc(born.year, born.month, born.day, 12)), tone: AppTone.neutral, icon: Icons.cake_outlined, dense: true),
      if ('${_values['gender'] ?? ''}'.isNotEmpty)
        AppStatusBadge(label: _values['gender'] == 'm' ? t('ذكر', 'Male') : t('أنثى', 'Female'), tone: AppTone.neutral, dense: true),
    ]);
  }

  // ── documents step ─────────────────────────────────────────────────────────

  List<Widget> _documentsStep() {
    final byKey = <String, OnbDocRecord>{for (final d in _docs) d.reqKey: d};
    final docs = _type.documents.where((d) => docVisible(d, _values)).toList();
    return [
      Text(t('ارفع صورة واضحة من كل مستند. يمكن إكمال بعضها لاحقاً إن أتاح النوع ذلك.', 'Upload a clear copy of each document. Some can be brought later when the type allows it.'),
          style: AppType.body(context).copyWith(color: context.colors.textMedium)),
      AppSpace.gapSm,
      for (final d in docs)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: OnbDocTile(
            key: ValueKey('onb.doc.${d.key}'),
            req: d,
            record: byKey[d.key],
            required: onbIsRequired(d.required, d.when, _values) || d.required == 'mandatory',
            later: _later.contains(d.key),
            busy: _uploading.contains(d.key),
            onUpload: () => _upload(d),
            onLater: d.allowLater && byKey[d.key] == null ? () => setState(() => _later.contains(d.key) ? _later.remove(d.key) : _later.add(d.key)) : null,
          ),
        ),
    ];
  }

  // ── review step ────────────────────────────────────────────────────────────

  List<Widget> _reviewStep() {
    final miss = computeMissing(_type, _values, _docs, laterKeys: _later);
    final ok = miss.canSubmit;
    final c = context.colors;
    String fieldLabel(String k) => _type.field(k)?.label ?? k;
    String docLabel(String k) => _type.doc(k)?.label ?? k;
    final shown = [for (final f in _type.fields) if (fieldVisible(f, _values) && hasValue(_values[f.key]) && f.kind != 'checkbox') f];
    return [
      AppBanner(
        key: const ValueKey('onb.review.status'),
        icon: ok ? Icons.check_circle_outline_rounded : Icons.report_gmailerrorred_rounded,
        color: ok ? c.success : c.warning,
        text: ok ? t('كل البيانات المطلوبة مكتملة.', 'Everything required is complete.') : t('ما زال ينقص بعض البيانات.', 'Some required items are still missing.'),
      ),
      AppSpace.gapSm,
      if (!ok)
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('الناقص', 'Missing'), style: AppType.bodyStrong(context)),
            AppSpace.gapXs,
            for (final k in miss.fields) _missingRow(Icons.edit_note_rounded, fieldLabel(k), t('حقل', 'Field')),
            for (final k in miss.documents)
              _missingRow(Icons.description_outlined, docLabel(k), _later.contains(k) ? t('سيُحضر لاحقاً', 'Will bring later') : (miss.later.contains(k) ? t('يمكن لاحقاً', 'Can be later') : t('مستند', 'Document'))),
          ]),
        ),
      if (!ok) AppSpace.gapSm,
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('البيانات المُدخلة', 'Entered details'), style: AppType.bodyStrong(context)),
          AppSpace.gapXs,
          for (final f in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xxs),
              child: Wrap(spacing: AppSpace.xs, children: [
                Text('${f.label.isEmpty ? f.key : f.label}:', style: AppType.meta(context)),
                Text(_displayValue(f), style: AppType.row(context), textDirection: f.kind == 'national_id' || f.kind == 'phone' || f.kind == 'email' ? TextDirection.ltr : null),
              ]),
            ),
        ]),
      ),
      AppSpace.gapMd,
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, alignment: WrapAlignment.end, children: [
        AppButton.secondary(key: const ValueKey('onb.review.draft'), label: t('حفظ كمسودة', 'Save as draft'), busy: _busy, onPressed: _busy ? null : _saveAndClose),
        if (widget.mode == OnbMode.staff && widget.canApproveNow)
          AppButton.tonal(key: const ValueKey('onb.review.approve'), label: t('اعتماد وتفعيل الآن', 'Approve and activate now'), onPressed: ok && !_busy ? () => _submit(approve: true) : null),
        AppButton.primary(
            key: const ValueKey('onb.review.submit'), label: t('تقديم', 'Submit'), busy: _busy, onPressed: ok && !_busy ? _submit : null),
      ]),
    ];
  }

  Widget _missingRow(IconData icon, String text, String tag) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.xxs),
        child: Row(children: [
          Icon(icon, size: AppIconSize.sm, color: context.colors.warning),
          AppSpace.gapXs,
          Expanded(child: Text(text, style: AppType.row(context))),
          AppStatusBadge(label: tag, tone: AppTone.warning, dense: true),
        ]),
      );

  String _displayValue(OnbField f) {
    final v = _values[f.key];
    if (v is bool) return v ? t('نعم', 'Yes') : t('لا', 'No');
    if (f.kind == 'date') {
      final d = parseIsoDay(v);
      return d == null ? '$v' : AppTime.date(DateTime.utc(d.year, d.month, d.day, 12));
    }
    if (f.kind == 'select' || f.kind == 'nationality' || f.kind == 'department' || f.kind == 'program') {
      return _optionsOf(f)['$v'] ?? '$v';
    }
    if (f.kind == 'multiselect' && v is List) {
      final o = {for (final x in f.options) x.value: x.label};
      return v.map((e) => o['$e'] ?? '$e').join('، ');
    }
    return '$v';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Pieces
// ═════════════════════════════════════════════════════════════════════════════

class _SavedMark extends StatelessWidget {
  const _SavedMark({required this.saving, required this.saved});
  final bool saving, saved;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (!saving && !saved) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, key: const ValueKey('onb.wizard.saved'), children: [
      Icon(saving ? Icons.sync_rounded : Icons.check_rounded, size: AppIconSize.xs, color: saving ? c.textMedium : c.success),
      AppSpace.gapXs,
      Text(saving ? t('جارٍ الحفظ…', 'Saving…') : t('تم الحفظ', 'Saved'), style: AppType.meta(context)),
    ]);
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child, this.required = false, this.error, this.help});
  final String label;
  final Widget child;
  final bool required;
  final String? error, help;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppFieldLabel(label, required: required),
        child,
        if (help != null && error == null) Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: Text(help!, style: AppType.meta(context))),
        if (error != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: Text(error!, style: AppType.meta(context).copyWith(color: c.danger))),
      ]),
    );
  }
}

/// One document requirement of the documents step: the label, its level, accepted types and size, the state of the
/// file on record, and the upload / "bring it later" buttons. Plain values, so the layout harness pumps it.
class OnbDocTile extends StatelessWidget {
  const OnbDocTile({super.key, required this.req, this.record, this.required = false, this.later = false, this.busy = false, this.onUpload, this.onLater});
  final OnbDocReq req;
  final OnbDocRecord? record;
  final bool required, later, busy;
  final VoidCallback? onUpload, onLater;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final tone = r == null
        ? (later ? AppTone.info : (required ? AppTone.warning : AppTone.neutral))
        : switch (r.status) {
            'verified' => AppTone.success,
            'rejected' => AppTone.danger,
            _ => AppTone.brand,
          };
    final status = r == null ? (later ? t('سيُحضر لاحقاً', 'Will bring later') : onbDocStatusLabel('missing')) : onbDocStatusLabel(r.status);
    final rules = [
      req.accept.map((e) => e.toUpperCase()).join(' · '),
      t('حتى ${req.maxMb} ميجابايت', 'up to ${req.maxMb} MB'),
      if (req.photoMinPx != null) t('${req.photoMinPx} بكسل على الأقل', 'at least ${req.photoMinPx} px'),
    ].where((e) => e.isNotEmpty).join(' · ');
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(r == null ? Icons.description_outlined : Icons.task_alt_rounded, size: AppIconSize.md, color: context.colors.textMedium),
          AppSpace.gapSm,
          Expanded(child: Text(req.label.isEmpty ? req.key : req.label, style: AppType.bodyStrong(context))),
        ]),
        AppSpace.gapXs,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AppStatusBadge(label: onbRequiredLabel(required ? (req.required == 'conditional' ? 'conditional' : 'mandatory') : 'optional'), tone: required ? AppTone.warning : AppTone.neutral, dense: true),
          AppStatusBadge(key: ValueKey('onb.doc.status.${req.key}'), label: status, tone: tone, dense: true),
          if (req.originalNeeded) AppStatusBadge(label: t('الأصل مطلوب', 'Original needed'), tone: AppTone.info, dense: true),
        ]),
        AppSpace.gapXs,
        Text(rules, style: AppType.meta(context)),
        if (r != null && r.fileName.isNotEmpty) Text('${r.fileName}${r.size > 0 ? ' · ${fileSizeLabel(r.size)}' : ''}', style: AppType.meta(context), maxLines: 1, overflow: TextOverflow.ellipsis),
        if (r != null && r.status == 'rejected' && r.note.isNotEmpty) Text(r.note, style: AppType.meta(context).copyWith(color: context.colors.danger)),
        AppSpace.gapXs,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          if (onUpload != null)
            AppButton.tonal(
                key: ValueKey('onb.doc.upload.${req.key}'),
                label: r == null ? t('رفع', 'Upload') : t('استبدال', 'Replace'),
                icon: Icons.upload_file_rounded,
                size: AppButtonSize.sm,
                busy: busy,
                onPressed: busy ? null : onUpload),
          if (onLater != null)
            AppButton.ghost(
                key: ValueKey('onb.doc.later.${req.key}'),
                label: later ? t('إلغاء "لاحقاً"', 'Undo "later"') : t('سأحضره لاحقاً', 'I will bring it later'),
                size: AppButtonSize.sm,
                onPressed: onLater),
        ]),
      ]),
    );
  }
}

/// The wizard in a pushed org page (`/org/<o>/onboarding/new`). Pops with the saved case.
class OnbWizardPage extends StatelessWidget {
  const OnbWizardPage({super.key, required this.orgId, required this.type, this.initial, this.api, this.places, this.canApproveNow = false, this.mode = OnbMode.staff});
  final int orgId;
  final OnbType type;
  final OnbCase? initial;
  final OnboardingApi? api;
  final OnbPlaces? places;
  final bool canApproveNow;
  final OnbMode mode;

  @override
  Widget build(BuildContext context) {
    return OrgPushedPage(
      title: initial == null ? t('إضافة ${type.label}', 'Add: ${type.label}') : (initial!.fullName.isEmpty ? type.label : initial!.fullName),
      subtitle: t('الالتحاق والتعيين', 'Admissions & appointments'),
      helpPageId: 'org.onboarding',
      width: AppWidth.form,
      child: OnbWizard(
        orgId: orgId,
        type: type,
        initial: initial,
        api: api,
        places: places,
        canApproveNow: canApproveNow,
        mode: mode,
        onDone: (c) => Navigator.of(context).maybePop(c),
      ),
    );
  }
}
