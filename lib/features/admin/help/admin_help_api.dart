// The Super Admin's Help management calls (`/api/v1/admin/help/...`, super admin only). Injectable: the pages take an
// [AdminHelpApi] so the layout tests run over a fake.
library;

import 'dart:typed_data';

import '../../../core/api_client.dart';
import '../../shared/help/help_models.dart';

/// One row of `GET /admin/help/pages`.
class HelpPageRow {
  const HelpPageRow({required this.pageId, required this.role, required this.title, this.updatedAt});
  final String pageId, role;
  final HelpText title;
  final String? updatedAt;

  factory HelpPageRow.fromJson(Map j) => HelpPageRow(
        pageId: '${j['page_id'] ?? ''}',
        role: '${j['role'] ?? ''}',
        title: HelpText.from(j['title']),
        updatedAt: j['updated_at']?.toString(),
      );
}

/// The body of `POST /admin/help/export`.
class HelpExportRequest {
  const HelpExportRequest({required this.what, this.ids = const [], this.role, this.format = 'docx', this.lang = 'ar', this.asJson = false});

  /// `page` | `flow` | `role` | `all`.
  final String what;
  final List<String> ids;
  final String? role;

  /// `docx` (user guide) | `video_script`.
  final String format;

  /// `ar` | `en` | `both`.
  final String lang;

  /// A video script as JSON instead of Word.
  final bool asJson;

  Map<String, dynamic> toBody() => {
        'what': what,
        if (ids.isNotEmpty) 'ids': ids,
        'role': ?role,
        'format': format,
        'lang': lang,
        'as': asJson && format == 'video_script' ? 'json' : 'docx',
      };

  String get extension => format == 'video_script' && asJson ? 'json' : 'docx';
}

class AdminHelpApi {
  const AdminHelpApi();

  static const _base = '/api/v1/admin/help';

  Future<List<HelpPageRow>> pages({String? role}) async {
    final r = await ApiClient().get('$_base/pages', queryParams: {'role': ?role});
    return [for (final e in (r is List ? r : const [])) if (e is Map) HelpPageRow.fromJson(e)];
  }

  Future<HelpEntry> page(String pageId, String role) async {
    final r = await ApiClient().get('$_base/pages/${Uri.encodeComponent(pageId)}/$role');
    return HelpEntry.fromJson(r is Map ? r : const {});
  }

  Future<HelpEntry> savePage(String pageId, String role, HelpEntry e) async {
    final r = await ApiClient().put('$_base/pages/${Uri.encodeComponent(pageId)}/$role', body: e.toBody());
    return HelpEntry.fromJson(r is Map ? r : const {});
  }

  Future<void> deletePage(String pageId, String role) async {
    await ApiClient().delete('$_base/pages/${Uri.encodeComponent(pageId)}/$role');
  }

  Future<List<HelpFlow>> flows({String? role}) async {
    final r = await ApiClient().get('$_base/flows', queryParams: {'role': ?role});
    return [for (final e in (r is List ? r : const [])) if (e is Map) HelpFlow.fromJson(e)];
  }

  Future<void> saveFlow(String role, String key, HelpFlow f) async {
    await ApiClient().put('$_base/flows/$role/${Uri.encodeComponent(key)}', body: f.toBody());
  }

  Future<void> deleteFlow(String role, String key) async {
    await ApiClient().delete('$_base/flows/$role/${Uri.encodeComponent(key)}');
  }

  Future<List<String>> pageIds() async {
    final r = await ApiClient().get('$_base/page-ids');
    return [for (final e in (r is List ? r : const [])) '$e'];
  }

  /// The generated file's bytes (Word, or JSON for a video script).
  Future<Uint8List> export(HelpExportRequest req) => ApiClient().postForBytes('$_base/export', body: req.toBody());
}

/// The label of a help role.
String helpRoleLabel(String role, bool ar) => switch (role) {
      'super_admin' => ar ? 'المشرف العام' : 'Super admin',
      'org_admin' => ar ? 'مدير مؤسسة' : 'Organization admin',
      'org_member' => ar ? 'عضو مؤسسة' : 'Organization member',
      'teacher' => ar ? 'مدرس' : 'Teacher',
      'student' => ar ? 'طالب' : 'Student',
      'parent' => ar ? 'ولي أمر' : 'Parent',
      _ => role,
    };
