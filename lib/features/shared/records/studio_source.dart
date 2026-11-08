// lib/features/shared/records/studio_source.dart — what the Studio edits (D-315): its source is pluggable. A drive
// recording of Records (D-311 / D-312, [RecordStudioSource]) or a course session's video material
// ([MaterialStudioSource] in material_studio_api.dart). The Studio page (records_studio.dart) only talks to this.
//
// Ids: the source and the merge candidates are the SOURCE's ids (a record id, a material id); the items a job makes
// (`edit` / `merge` answers, `get`, `retry`) are the JOB's ids (an edit record, a material draft).
library;

import 'dart:typed_data';

import 'records_api.dart';
import 'records_share_api.dart';
import 'records_studio_parts.dart' show StudioTool;

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
}

/// Records: my own drive recordings (the Studio of D-312).
class RecordStudioSource implements StudioSource {
  RecordStudioSource({RecordsApi? api, RecordShareApi? shareApi})
      : _api = api ?? RemoteRecordsApi(),
        _share = shareApi ?? RemoteRecordShareApi();

  final RecordsApi _api;
  final RecordShareApi _share;

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
  Future<RecordFrames> frames(int sourceId) => _share.frames(sourceId);
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
}
