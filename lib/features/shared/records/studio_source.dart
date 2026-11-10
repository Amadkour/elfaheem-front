// lib/features/shared/records/studio_source.dart — what the Studio edits (D-315): its source is pluggable. A drive
// recording of Records (D-311 / D-312, [RecordStudioSource]) or a course session's video material
// ([MaterialStudioSource] in material_studio_api.dart). The Studio page (records_studio.dart) only talks to this.
//
// Ids: the source and the merge candidates are the SOURCE's ids (a record id, a material id); the items a job makes
// (`edit` / `merge` / `render` answers, `get`, `retry`, `cancel`) are the JOB's ids (an edit record, a material draft).
//
// The premium Studio (D-590 … D-597) adds: `render` (the whole edit list in one job), the autosaved project
// (`loadProject` / `saveProject`), a finished job's project (`jobProject`, to continue it), `cancel`, `download` /
// `downloadJob` (a file to save, staff only on the server) and the overlay pictures (`uploadAsset`, `assetLinks`).
library;

import 'dart:typed_data';

import '../../../core/api_client.dart';
import '../../admin/admin_common.dart' show asMap, asInt;
import 'records_api.dart';
import 'records_share_api.dart';
import 'records_studio_parts.dart' show StudioTool;

/// A file the person may save: [url] is absolute and needs no header (the signed token is the credential).
class StudioDownload {
  const StudioDownload({required this.url, required this.fileName, this.size});
  final String url;
  final String fileName;
  final int? size;

  static StudioDownload fromJson(Map<String, dynamic> j, {required String base}) {
    final raw = '${j['url'] ?? ''}'.trim();
    final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final size = asInt(j['size']);
    return StudioDownload(
      url: raw.startsWith('/') ? '$root$raw' : raw,
      fileName: '${j['file_name'] ?? 'video.mp4'}',
      size: size > 0 ? size : null,
    );
  }
}

/// An uploaded overlay picture (a PNG on the server: an image, or a text the app drew).
class StudioAsset {
  const StudioAsset({required this.id, this.url, this.width = 0, this.height = 0});
  final String id;
  final String? url;
  final int width;
  final int height;

  static StudioAsset fromJson(Map<String, dynamic> j, {required String base}) {
    final raw = '${j['url'] ?? ''}'.trim();
    final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return StudioAsset(
      id: '${j['id'] ?? ''}',
      url: raw.isEmpty ? null : (raw.startsWith('/') ? '$root$raw' : raw),
      width: asInt(j['width']),
      height: asInt(j['height']),
    );
  }
}

/// The overlay-asset calls, the same for both sources.
mixin StudioAssetCalls {
  ApiClient get assetClient;

  String _abs(String raw) {
    final base = assetClient.baseUrl;
    final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return raw.startsWith('/') ? '$root$raw' : raw;
  }

  Future<StudioAsset> uploadAsset(Uint8List png, {String fileName = 'overlay.png'}) async => StudioAsset.fromJson(
      asMap(await assetClient.postMultipart('/api/v1/studio/assets', fields: const {}, fileBytes: png, fileName: fileName, fileField: 'file')),
      base: assetClient.baseUrl);

  Future<Map<String, String>> assetLinks(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final j = asMap(asMap(await assetClient.post('/api/v1/studio/assets/links', body: {'ids': ids}))['links']);
    return {for (final e in j.entries) e.key: _abs('${e.value}')};
  }
}

abstract class StudioSource {
  /// The tools this source offers (a material has no cover: the course page draws none).
  List<StudioTool> get tools;

  /// The job makes a DRAFT the person publishes later (a material), not a finished item (Records).
  bool get drafts;

  /// `job_updated{kind}` of the job and of the filmstrip.
  String get jobEventKind;
  String get framesEventKind;

  Future<RecordPlay> play(int sourceId);
  Future<RecordFrames> frames(int sourceId);
  Future<List<RecordItem>> edit(int sourceId, RecordEdit edit);
  Future<List<RecordItem>> merge(List<int> sourceIds, {String? title, bool deleteSources = false});
  Future<RecordItem?> get(int jobId);
  Future<RecordItem?> retry(int jobId);
  Future<RecordItem?> setCover(int sourceId, Uint8List bytes, {String fileName = 'cover.jpg'});
  Future<RecordItem?> clearCover(int sourceId);

  /// The edit list in one job ([params]: studioRenderParams + `title`, `delete_source` for Records).
  Future<List<RecordItem>> render(int sourceId, Map<String, dynamic> params);

  /// The autosaved work on this source (null: none).
  Future<Map<String, dynamic>?> loadProject(int sourceId);
  Future<void> saveProject(int sourceId, Map<String, dynamic>? doc);

  /// The project a finished job was rendered from (null: it was not a project).
  Future<Map<String, dynamic>?> jobProject(int jobId);
  Future<RecordItem?> cancel(int jobId);
  Future<StudioDownload> download(int sourceId);
  Future<StudioDownload> downloadJob(int jobId);
  Future<StudioAsset> uploadAsset(Uint8List png, {String fileName = 'overlay.png'});
  Future<Map<String, String>> assetLinks(List<String> ids);
}

/// Records: my own drive recordings (the Studio of D-312).
class RecordStudioSource with StudioAssetCalls implements StudioSource {
  RecordStudioSource({RecordsApi? api, RecordShareApi? shareApi, ApiClient? client})
      : _api = api ?? RemoteRecordsApi(),
        _share = shareApi ?? RemoteRecordShareApi(),
        _client = client ?? ApiClient();

  final RecordsApi _api;
  final RecordShareApi _share;
  final ApiClient _client;
  static const _base = '/api/v1/me/records';

  @override
  ApiClient get assetClient => _client;

  @override
  List<StudioTool> get tools => StudioTool.values;
  @override
  bool get drafts => false;
  @override
  String get jobEventKind => 'recording';
  @override
  String get framesEventKind => 'record_frames';

  @override
  Future<RecordPlay> play(int sourceId) => _api.play(sourceId);
  @override
  Future<RecordFrames> frames(int sourceId) async {
    try {
      return await _share.frames(sourceId);
    } on ApiException catch (e) {
      if (e.statusCode == 422) return _share.frames(sourceId, n: 24); // a server before D-590 takes 8–40
      rethrow;
    }
  }

  @override
  Future<List<RecordItem>> edit(int sourceId, RecordEdit edit) => _api.edit(sourceId, edit);
  @override
  Future<List<RecordItem>> merge(List<int> sourceIds, {String? title, bool deleteSources = false}) =>
      _api.merge(sourceIds, title: title, deleteSources: deleteSources);
  @override
  Future<RecordItem?> get(int jobId) => _api.get(jobId);
  @override
  Future<RecordItem?> retry(int jobId) => _api.retry(jobId);
  @override
  Future<RecordItem?> setCover(int sourceId, Uint8List bytes, {String fileName = 'cover.jpg'}) =>
      _api.setCover(sourceId, bytes, fileName: fileName);
  @override
  Future<RecordItem?> clearCover(int sourceId) => _api.clearCover(sourceId);

  @override
  Future<List<RecordItem>> render(int sourceId, Map<String, dynamic> params) async =>
      recordsFrom(await _client.post('$_base/$sourceId/render', body: params));

  @override
  Future<Map<String, dynamic>?> loadProject(int sourceId) async {
    final d = asMap(await _client.get('$_base/$sourceId/project'))['doc'];
    return d is Map ? asMap(d) : null;
  }

  @override
  Future<void> saveProject(int sourceId, Map<String, dynamic>? doc) async => _client.put('$_base/$sourceId/project', body: {'doc': doc});

  @override
  Future<Map<String, dynamic>?> jobProject(int jobId) async {
    final p = asMap(await _client.get('$_base/$jobId/edit-project'))['project'];
    return p is Map ? asMap(p) : null;
  }

  @override
  Future<RecordItem?> cancel(int jobId) async => RecordItem.fromJson(asMap(await _client.post('$_base/$jobId/cancel')));

  @override
  Future<StudioDownload> download(int sourceId) async =>
      StudioDownload.fromJson(asMap(await _client.post('$_base/$sourceId/download')), base: _client.baseUrl);

  @override
  Future<StudioDownload> downloadJob(int jobId) => download(jobId);
}
