// lib/features/org/advising/adv_api.dart — the HTTP client of the Academic Advising module, one method per server
// route of docs/advising/PHASE2.md. Every method throws `ApiException` (wrap calls in `orgCall` from org_v3.dart
// to toast `orgErrorText`); answers are parsed into adv_models.dart. A missing route (older server) surfaces as
// `orgEndpointMissing`, and the screens then say the feature needs a server update.
library;

import '../../../core/api_client.dart';
import '../../admin/admin_common.dart' show asMap, asMapList;
import '../org_providers.dart' show orgBase;
import 'adv_models.dart';

class AdvApi {
  AdvApi(this.orgId, {ApiClient? client}) : _api = client ?? ApiClient();

  final int orgId;
  final ApiClient _api;

  String get base => '$orgBase/orgs/$orgId/advising';

  /// Eligibility, on / off, the directors, what I am and (admins / directors) the organization's counts.
  Future<AdvStatus> status() async => AdvStatus.fromJson(asMap(await _api.get('$base/status')));

  /// Org admin. [deptId] = the department that leads advising; null = the existing Academic Advising department,
  /// else a new one. Idempotent; 403 `advising_not_available` for an ineligible organization.
  Future<AdvStatus> enable({int? deptId}) async => AdvStatus.fromJson(asMap(await _api.post('$base/enable', body: {'dept_id': deptId})));

  /// Org admin. Every record is kept.
  Future<AdvStatus> disable() async => AdvStatus.fromJson(asMap(await _api.post('$base/disable')));

  /// The organization's departments the advising may be given to ([advDeptChoices]).
  Future<List<AdvDeptOption>> departmentChoices() async =>
      advDeptChoices(asMapList(asMap(await _api.get('$orgBase/orgs/$orgId/departments'))['items']));

  /// Member side: is advising on, am I a student / an advisor there, and my own advisors.
  static Future<AdvMemberStatus> memberStatus(int orgId, {ApiClient? client}) async =>
      AdvMemberStatus.fromJson(asMap(await (client ?? ApiClient()).get('$orgBase/public/$orgId/advising/status')));
}
