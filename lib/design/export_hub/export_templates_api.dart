// lib/design/export_hub/export_templates_api.dart
//
// The saved designs of an organization: `GET/POST …/governance/export/templates`, `PUT/DELETE …/{id}`,
// `POST …/{id}/default`, `POST …/{id}/share` (docs/backend/governance-spec.md §4, "Export Hub"), plus the dataset
// call `GET …/governance/export/data`. Every call goes through `orgCall`, so a failure toasts `orgErrorText` and
// the method answers null / false; `endpointMissing` tells an older server apart from an empty list.
library;

import 'package:flutter_education_app/core/api_client.dart';

import '../../features/admin/admin_common.dart' show asMapList;
import '../../features/org/governance/gov_models.dart' show ExportTemplate;
import '../../features/org/org_providers.dart' show orgBase;
import '../../features/org/org_v3.dart' show OrgCall, orgCall;
import 'export_design.dart';

class ExportTemplatesApi {
  ExportTemplatesApi(this.orgId, {ApiClient? api}) : api = api ?? ApiClient();

  final int orgId;
  final ApiClient api;

  String get base => '$orgBase/orgs/$orgId/governance/export';

  /// The templates the caller may use for [module] + [lang]: own department, shared, organization-wide.
  Future<OrgCall> listRaw({String? module, String? lang, int? deptId}) => orgCall(
        () => api.get('$base/templates', queryParams: {
          'module': ?module,
          'lang': ?lang,
          'dept_id': ?deptId,
        }),
        quiet: true,
      );

  /// null when the call failed (the error was toasted) or the server lacks the route.
  Future<List<ExportTemplate>?> list({String? module, String? lang, int? deptId}) async {
    final r = await listRaw(module: module, lang: lang, deptId: deptId);
    if (!r.ok) return null;
    return [for (final j in asMapList(r.map['items'])) ExportTemplate.fromJson(j)];
  }

  Future<ExportTemplate?> create({required String module, required String lang, required String name, required ExportDesign design, int? deptId, bool isDefault = false, bool shared = false}) async {
    final r = await orgCall(() => api.post('$base/templates', body: {
          'module': module,
          'lang': lang,
          'name': name.trim(),
          'design': design.toJson(),
          'dept_id': deptId,
          'is_default': isDefault,
          'shared': shared,
        }));
    return r.ok ? ExportTemplate.fromJson(r.map) : null;
  }

  Future<ExportTemplate?> update(int id, {String? name, ExportDesign? design, bool? isDefault, bool? shared}) async {
    final r = await orgCall(() => api.put('$base/templates/$id', body: {
          'name': ?name?.trim(),
          'design': ?design?.toJson(),
          'is_default': ?isDefault,
          'shared': ?shared,
        }));
    return r.ok ? ExportTemplate.fromJson(r.map) : null;
  }

  Future<bool> delete(int id) async => (await orgCall(() => api.delete('$base/templates/$id'))).ok;

  Future<bool> setDefault(int id) async => (await orgCall(() => api.post('$base/templates/$id/default', body: const {}))).ok;

  Future<bool> share(int id, {required bool shared}) async => (await orgCall(() => api.post('$base/templates/$id/share', body: {'shared': shared}))).ok;

  /// `GET …/export/data` — the caller's filters as [query] (module, item filters, session_id, include_* flags,
  /// lang). null when the call failed (toasted) — a 403 `export_forbidden` means vote results were asked for
  /// without `councils.export`.
  Future<ExportDataset?> data(String module, Map<String, dynamic> query) async {
    final r = await orgCall(() => api.get('$base/data', queryParams: {'module': module, ...query}));
    return r.ok ? ExportDataset.fromJson(r.map) : null;
  }
}

/// `GET …/governance/export/data` for [orgId] (see [ExportTemplatesApi.data]).
Future<ExportDataset?> fetchExportDataset(int orgId, String module, Map<String, dynamic> query) => ExportTemplatesApi(orgId).data(module, query);
