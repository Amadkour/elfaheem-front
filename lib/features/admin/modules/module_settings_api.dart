// lib/features/admin/modules/module_settings_api.dart
//
// The super admin's module switches (learning hub phase 6, CONTRACT §6, D-1348): rule flags per module, edited per
// scope (platform · a country · an organization), and the per-country student tab switches.
//
//   GET|PUT /api/v1/admin/module-settings/{module}?scope=&scope_key=   → ModuleView (PUT body = the values; {} = delete)
//   PUT     /api/v1/admin/edu/countries/{code}/features {disabled}      the country kill-switch list
//   GET     /api/v1/admin/edu/countries                                 countries (with `disabled_features`)
//   GET     /api/v1/admin/orgs?status=all                               organizations for the org scope
//
// Plain models with tolerant readers. Every call goes through orgCall(quiet: true) and never throws; the page shows
// [moduleErrorText] for a refusal.
library;

import 'package:flutter_education_app/core/api_client.dart';

import '../../org/org_v3.dart' show OrgCall, orgCall;
import '../admin_common.dart' show asMap, asMapList, t;

/// Kill switch of the page (super admin only).
const kAdminModulesFeatureKey = 'admin.modules';

/// The modules the page edits, in page order.
const kModuleKeys = ['store', 'games', 'quran'];

/// The student tab keys a country can switch off (`edu_countries.disabled_features`).
const kCountryTabKeys = ['student_tab_store', 'student_tab_games', 'student_tab_quran', 'student_tab_nahw'];

const kModuleScopes = ['platform', 'country', 'org'];

/// One field of a module, typed from the server registry.
class ModuleField {
  const ModuleField({required this.key, required this.type, this.dflt, this.choices = const []});

  final String key;

  /// `bool` | `int` | `str`.
  final String type;
  final dynamic dflt;
  final List<String> choices;

  static ModuleField from(Map<String, dynamic> m) {
    final d = m['default'];
    final type = '${m['type'] ?? (d is bool ? 'bool' : d is int ? 'int' : 'str')}';
    return ModuleField(
      key: '${m['key'] ?? ''}',
      type: type,
      dflt: d,
      choices: [for (final c in (m['choices'] as List? ?? const [])) '$c'],
    );
  }
}

/// Where a value comes from at the scope being edited.
enum ModuleSource { here, platform, defaults }

/// The admin GET answer for one module at one scope.
class ModuleView {
  const ModuleView({
    required this.module,
    required this.scope,
    this.scopeKey = '',
    this.values = const {},
    this.effective = const {},
    this.defaults = const {},
    this.fields = const [],
    this.platformValues = const {},
    this.overrideCount = 0,
    this.updatedAt,
  });

  final String module;
  final String scope;
  final String scopeKey;

  /// This scope's own partial values.
  final Map<String, dynamic> values;
  final Map<String, dynamic> effective;
  final Map<String, dynamic> defaults;
  final List<ModuleField> fields;

  /// The platform row's partial values (from `rows`): what a country / org inherits before the defaults.
  final Map<String, dynamic> platformValues;

  /// How many country / org rows exist for this module (shown on the platform scope).
  final int overrideCount;
  final DateTime? updatedAt;

  static ModuleView from(Map<String, dynamic> m) {
    final rows = asMapList(m['rows']);
    Map<String, dynamic> platform = const {};
    var overrides = 0;
    for (final r in rows) {
      if (r['scope'] == 'platform') {
        platform = Map<String, dynamic>.from(asMap(r['values']));
      } else {
        overrides++;
      }
    }
    return ModuleView(
      module: '${m['module'] ?? ''}',
      scope: '${m['scope'] ?? 'platform'}',
      scopeKey: '${m['scope_key'] ?? ''}',
      values: Map<String, dynamic>.from(asMap(m['values'])),
      effective: Map<String, dynamic>.from(asMap(m['effective'])),
      defaults: Map<String, dynamic>.from(asMap(m['defaults'])),
      fields: [for (final f in asMapList(m['fields'])) ModuleField.from(f)],
      platformValues: platform,
      overrideCount: overrides,
      updatedAt: DateTime.tryParse('${m['updated_at'] ?? ''}'),
    );
  }

  /// The value this scope inherits when it sets nothing itself.
  dynamic inherited(String key) {
    if (scope != 'platform' && platformValues.containsKey(key)) return platformValues[key];
    return defaults[key];
  }

  /// The source of [key] when [draft] is this scope's (edited) values.
  ModuleSource sourceOf(String key, Map<String, dynamic> draft) {
    if (draft.containsKey(key)) return ModuleSource.here;
    if (scope != 'platform' && platformValues.containsKey(key)) return ModuleSource.platform;
    return ModuleSource.defaults;
  }

  /// The value in force at this scope with [draft] applied.
  dynamic shown(String key, Map<String, dynamic> draft) => draft.containsKey(key) ? draft[key] : inherited(key);
}

/// A country for the country scope, with its switched-off feature keys.
class ModuleCountry {
  const ModuleCountry({required this.code, required this.nameAr, required this.nameEn, this.disabled = const []});

  final String code;
  final String nameAr;
  final String nameEn;
  final List<String> disabled;

  String get name => t(nameAr.isEmpty ? code : nameAr, nameEn.isEmpty ? code : nameEn);

  static ModuleCountry from(Map<String, dynamic> m) => ModuleCountry(
        code: '${m['code'] ?? ''}',
        nameAr: '${m['name_ar'] ?? ''}',
        nameEn: '${m['name_en'] ?? ''}',
        disabled: [for (final k in (m['disabled_features'] as List? ?? const [])) '$k'],
      );

  ModuleCountry withDisabled(List<String> d) => ModuleCountry(code: code, nameAr: nameAr, nameEn: nameEn, disabled: d);
}

/// An organization for the org scope.
class ModuleOrg {
  const ModuleOrg({required this.id, required this.nameAr, required this.nameEn});

  final int id;
  final String nameAr;
  final String nameEn;

  String get name {
    final s = t(nameAr.isEmpty ? nameEn : nameAr, nameEn.isEmpty ? nameAr : nameEn);
    return s.isEmpty ? '#$id' : s;
  }

  static ModuleOrg from(Map<String, dynamic> m) =>
      ModuleOrg(id: (m['id'] as num?)?.toInt() ?? 0, nameAr: '${m['name_ar'] ?? ''}', nameEn: '${m['name_en'] ?? ''}');
}

/// A call's answer: the value, or the refusal's text.
class ModuleResult<T> {
  const ModuleResult(this.value, [this.error]);
  final T? value;
  final String? error;
  bool get ok => error == null;
}

/// Bilingual text for a refusal of these routes.
String moduleErrorText(OrgCall r) {
  final code = r.code ?? '';
  final detail = r.detail;
  switch (code) {
    case 'module_setting_bad_value':
      final choices = (detail['choices'] as List?)?.join(' / ');
      return t('قيمة غير صالحة للإعداد ${detail['key'] ?? ''}${choices == null ? '' : ' ($choices)'}',
          'Not a valid value for ${detail['key'] ?? 'this setting'}${choices == null ? '' : ' ($choices)'}');
    case 'module_setting_unknown_key':
      return t('هذا الإعداد غير معروف للخادم: ${detail['key'] ?? ''}', 'The server does not know this setting: ${detail['key'] ?? ''}');
    case 'module_setting_bad_scope':
      return t('اختر الدولة أو المؤسسة أولاً', 'Pick the country or the organization first');
    case 'module_unknown':
      return t('هذه الوحدة غير متاحة على الخادم', 'This module is not available on the server');
    case 'edu_country_not_found':
      return t('الدولة غير موجودة', 'The country was not found');
    case 'org_not_found':
      return t('المؤسسة غير موجودة', 'The organization was not found');
    case 'admin_required':
      return t('هذه الصفحة لمدير المنصة الأعلى فقط', 'Only the platform super admin can use this page');
    case 'feature_disabled':
      return t('هذه الصفحة متوقفة حالياً', 'This page is switched off right now');
  }
  return r.error?.message ?? t('تعذر الاتصال بالخادم', 'Could not reach the server');
}

class ModuleSettingsApi {
  const ModuleSettingsApi();

  Map<String, dynamic> _query(String scope, String? scopeKey) =>
      {'scope': scope, if (scope != 'platform' && (scopeKey ?? '').isNotEmpty) 'scope_key': scopeKey};

  Future<ModuleResult<ModuleView>> load(String module, String scope, String? scopeKey) async {
    final r = await orgCall(
        () => ApiClient().get('/api/v1/admin/module-settings/$module', queryParams: _query(scope, scopeKey)),
        quiet: true);
    return r.ok ? ModuleResult(ModuleView.from(r.map)) : ModuleResult(null, moduleErrorText(r));
  }

  /// Replaces this scope's values; an empty map deletes the row.
  Future<ModuleResult<ModuleView>> save(String module, String scope, String? scopeKey, Map<String, dynamic> values) async {
    final r = await orgCall(
        () => ApiClient().put('/api/v1/admin/module-settings/$module', queryParams: _query(scope, scopeKey), body: values),
        quiet: true);
    return r.ok ? ModuleResult(ModuleView.from(r.map)) : ModuleResult(null, moduleErrorText(r));
  }

  Future<ModuleResult<List<ModuleCountry>>> countries() async {
    final r = await orgCall(() => ApiClient().get('/api/v1/admin/edu/countries'), quiet: true);
    if (!r.ok) return ModuleResult(null, moduleErrorText(r));
    return ModuleResult([for (final c in asMapList(r.data)) ModuleCountry.from(c)]);
  }

  Future<ModuleResult<List<ModuleOrg>>> orgs() async {
    final r = await orgCall(
        () => ApiClient().get('/api/v1/admin/orgs', queryParams: {'status': 'all', 'size': 100}),
        quiet: true);
    if (!r.ok) return ModuleResult(null, moduleErrorText(r));
    return ModuleResult([for (final o in asMapList(r.map['items'])) ModuleOrg.from(o)]);
  }

  Future<ModuleResult<List<String>>> setCountryFeatures(String code, List<String> disabled) async {
    final r = await orgCall(
        () => ApiClient().put('/api/v1/admin/edu/countries/$code/features', body: {'disabled': disabled}),
        quiet: true);
    if (!r.ok) return ModuleResult(null, moduleErrorText(r));
    final d = r.map['disabled_features'];
    return ModuleResult(d is List ? [for (final k in d) '$k'] : disabled);
  }
}
