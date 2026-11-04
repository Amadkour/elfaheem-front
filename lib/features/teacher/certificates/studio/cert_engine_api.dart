// features/teacher/certificates/studio/cert_engine_api.dart
//
// The certificate studio's server calls (D-165, docs/design_engine/ENGINE.md). Every call goes through ApiClient and
// throws only ApiException (message safe to show); a stale save throws [CertConflict].
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../../../core/api_client.dart';
import '../../../../design/export_layout/layout_model.dart';

/// `GET /certificate-designs/{id}/document`.
class CertDocLoad {
  const CertDocLoad({required this.document, required this.version, required this.converted});
  final LayoutDocument document;
  final int version;

  /// The server built the document from the legacy columns (nothing is saved yet).
  final bool converted;
}

/// 409 `design_conflict`: another tab / device saved first.
class CertConflict implements Exception {
  const CertConflict();
  @override
  String toString() => 'CertConflict: 409 design_conflict';
}

/// One starter of the gallery (`GET /exports/layout/starters?purpose=certificate`).
class CertStarter {
  const CertStarter({required this.key, required this.nameAr, required this.nameEn, required this.descAr, required this.descEn, required this.mode, required this.document});
  final String key, nameAr, nameEn, descAr, descEn, mode;
  final LayoutDocument document;

  String name(String lang) => lang == 'ar' ? (nameAr.isEmpty ? nameEn : nameAr) : (nameEn.isEmpty ? nameAr : nameEn);
  String description(String lang) => lang == 'ar' ? (descAr.isEmpty ? descEn : descAr) : (descEn.isEmpty ? descAr : descEn);

  static CertStarter? tryParse(Object? j) {
    if (j is! Map || j['document'] is! Map) return null;
    try {
      final m = j.map((k, v) => MapEntry('$k', v));
      return CertStarter(
        key: '${m['key'] ?? ''}',
        nameAr: '${m['name_ar'] ?? ''}',
        nameEn: '${m['name_en'] ?? ''}',
        descAr: '${m['description_ar'] ?? ''}',
        descEn: '${m['description_en'] ?? ''}',
        mode: '${m['mode'] ?? 'page'}',
        document: LayoutDocument.fromJson((m['document'] as Map).map((k, v) => MapEntry('$k', v))),
      );
    } catch (_) {
      return null;
    }
  }
}

class CertEngineApi {
  CertEngineApi({ApiClient? api}) : _api = api;
  final ApiClient? _api;
  ApiClient get api => _api ?? ApiClient();

  static const _base = '/api/v1/certificate-designs';

  Map<String, dynamic> _map(Object? v) => v is Map ? v.map((k, x) => MapEntry('$k', x)) : <String, dynamic>{};

  Future<CertDocLoad> load(int id) async {
    final r = _map(await api.get('$_base/$id/document'));
    return CertDocLoad(
      document: LayoutDocument.fromJson(_map(r['document'])),
      version: (r['version'] as num?)?.toInt() ?? 0,
      converted: r['converted'] == true,
    );
  }

  /// Saves [document] on top of [version]; the new version. Throws [CertConflict] when [version] is not the stored one.
  Future<int> save(int id, Map<String, dynamic> document, int version) async {
    try {
      final r = _map(await api.put('$_base/$id/document', body: {'document': document, 'version': version}));
      return (r['version'] as num?)?.toInt() ?? version + 1;
    } catch (e) {
      final x = ApiException.from(e);
      final code = x.code ?? ApiException.codedDetail(x.body).$1;
      if (x.statusCode == 409 && (code == null || code == 'design_conflict')) throw const CertConflict();
      rethrow;
    }
  }

  /// One page of the design as a PNG (never writes).
  Future<Uint8List> preview(Map<String, dynamic> document, String lang, Map<String, String> values) async {
    final r = _map(await api.post('$_base/preview-document', body: {'document': document, 'lang': lang, 'values': values}));
    var b64 = '${r['png_b64'] ?? ''}';
    if (b64.contains(',')) b64 = b64.substring(b64.indexOf(',') + 1);
    if (b64.isEmpty) throw const ApiException(statusCode: 0, message: 'empty preview');
    return base64Decode(b64);
  }

  Future<String> _upload(String path, Uint8List bytes, [Map<String, dynamic> extra = const {}]) async {
    final r = _map(await api.post(path, body: {'image_base64': base64Encode(bytes), ...extra}));
    final url = r['url'];
    if (url is! String || url.isEmpty) throw const ApiException(statusCode: 0, message: 'upload failed');
    return url;
  }

  Future<String> uploadLogo(Uint8List bytes) => _upload('$_base/logo', bytes);
  Future<String> uploadSignature(Uint8List bytes) => _upload('$_base/signature', bytes);

  Future<String> uploadBackground(Uint8List bytes, {required bool landscape, String size = 'A4', double? wMm, double? hMm}) {
    final q = StringBuffer('orientation=${landscape ? 'landscape' : 'portrait'}');
    if (size == 'Letter') q.write('&page=letter');
    if (size == 'custom' && wMm != null && hMm != null) q.write('&page=custom&w_mm=$wMm&h_mm=$hMm');
    return _upload('$_base/background?$q', bytes);
  }

  Future<List<CertStarter>> starters() async {
    final r = await api.get('/api/v1/exports/layout/starters', queryParams: {'purpose': 'certificate'});
    final items = r is List ? r : (r is Map ? (r['items'] ?? r['starters']) : null);
    return [
      if (items is List)
        for (final j in items) ?CertStarter.tryParse(j),
    ];
  }

  /// A new, empty design (the legacy create call); its id.
  Future<int> createBlank({int? orgId, String? name}) async {
    final r = _map(await api.post(_base, body: {
      'org_id': orgId,
      'name': name ?? 'Certificate',
      'orientation': 'landscape',
      'theme': {'style': 'classic'},
      'fields': <dynamic>[],
    }));
    final id = r['id'];
    if (id is! num) throw const ApiException(statusCode: 0, message: 'create failed');
    return id.toInt();
  }

  /// My editable copy of a design I can only read (an organization's); its id.
  Future<int> duplicate(int id, {int? certificateId}) async {
    final r = _map(await api.post('$_base/$id/duplicate${certificateId == null ? '' : '?certificate_id=$certificateId'}'));
    final nid = r['id'];
    if (nid is! num) throw const ApiException(statusCode: 0, message: 'copy failed');
    return nid.toInt();
  }

  Future<void> attach(int certificateId, int designId) async {
    await api.post('/api/v1/certificates/$certificateId/design', body: {'design_id': designId});
  }
}

/// The text of a failed call that is safe to show.
String certErrorText(Object e) => ApiException.from(e).message;
