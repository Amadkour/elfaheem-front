// lib/features/shared/records/material_studio_api.dart — the Studio on a course session's VIDEO material (D-315).
// Pure: models, parsing, code → text, the API and the Studio source. Screens: material_studio_page.dart.
//
//   GET    /api/v1/sessions/{sid}/materials/{mid}/studio          → MaterialStudioOpen {source, others, drafts}
//   POST   /api/v1/sessions/{sid}/materials/{mid}/studio/play     → RecordPlay (the staff stream, no device header)
//   POST   /api/v1/sessions/{sid}/materials/{mid}/studio/frames   {n} → RecordFrames
//   POST   /api/v1/sessions/{sid}/materials/{mid}/studio/edit     {op, start?, end?, at?, speed?, height?, level?, title?} → [draft]
//   POST   /api/v1/sessions/{sid}/materials/{mid}/studio/merge    {ids: [mid, …], title?} → [draft]
//   GET    /api/v1/sessions/{sid}/studio/drafts                   → [MaterialDraft] (drafts + replaces to confirm)
//   GET    /api/v1/studio/drafts/{did}  · POST …/retry · …/play · …/publish {mode: new|replace} · …/restore ·
//          …/confirm · DELETE /api/v1/studio/drafts/{did}
//
// An edit is a DRAFT students never see (not a session material) until it is published: as a new material after
// the original, or into the original's place (its id, progress and views kept; the old file kept until "Delete the
// old file", undone by "Restore"). Job progress: `job_updated{kind: material_edit}`; the filmstrip:
// `job_updated{kind: material_frames}`. Kill switch `materials.studio`. Contract: ../back/FLUTTER_API_CHANGES.md
// "Studio on session materials + record guests by e-mail". Tests: test/org/material_studio_api_test.dart.
import 'dart:typed_data';

import '../../../core/api_client.dart';
import '../../admin/admin_common.dart' show t, asMap, asMapList, asInt;
import '../live/meeting_recording.dart' show parseRecordingTime;
import 'records_api.dart';
import 'records_share_api.dart' show RecordFrames, recordFramesCount;
import 'records_studio_parts.dart' show StudioTool;
import 'studio_source.dart';

/// The kill switch: the Studio button on a video material, the player's Open in Studio, the drafts strip.
const kMaterialsStudioFeatureKey = 'materials.studio';

/// How a draft is published.
enum MaterialPublishMode {
  /// A new material right after the original (nothing a student has changes).
  asNew('new'),

  /// Into the original's place: same material, progress / views / ratings kept, the old file kept until confirmed.
  replace('replace');

  const MaterialPublishMode(this.wire);
  final String wire;

  static MaterialPublishMode? fromWire(dynamic v) => switch ('${v ?? ''}') {
        'new' => MaterialPublishMode.asNew,
        'replace' => MaterialPublishMode.replace,
        _ => null,
      };

  String get label => switch (this) {
        MaterialPublishMode.asNew => t('مادة جديدة', 'A new material'),
        MaterialPublishMode.replace => t('استبدال الأصل', 'Replace the original'),
      };

  String get hint => switch (this) {
        MaterialPublishMode.asNew => t('تُضاف بعد الأصل في الحصة نفسها، ويبقى الأصل كما هو.',
            'Added right after the original in the same session; the original stays as it is.'),
        MaterialPublishMode.replace => t(
            'يحل الملف الجديد مكان الأصل: يبقى تقدّم الطلاب ومشاهداتهم وتقييماتهم، ومن نزّله يبقى معه القديم حتى يعيد التنزيل. يُحتفظ بالملف القديم حتى تؤكّد حذفه.',
            "The new file takes the original's place: students keep their progress, views and ratings, and a downloaded copy stays the old one until they download again. The old file is kept until you confirm deleting it."),
      };
}

/// A Studio draft of a material: the job's item (the Studio's shape) + where it is in its publish life.
class MaterialDraft {
  const MaterialDraft({
    required this.item,
    this.state = 'draft',
    this.publishMode,
    this.publishedMaterialId,
    this.sessionId = 0,
    this.sourceMaterialId,
    this.canPublish = false,
    this.canRestore = false,
    this.publishedAt,
  });

  final RecordItem item;

  /// draft · published
  final String state;
  final MaterialPublishMode? publishMode;
  final int? publishedMaterialId;
  final int sessionId;
  final int? sourceMaterialId;
  final bool canPublish;

  /// A replace whose old file is still kept: Restore / Delete the old file.
  final bool canRestore;
  final DateTime? publishedAt;

  int get id => item.id;
  bool get isDraft => state == 'draft';
  bool get pendingReplace => state == 'published' && publishMode == MaterialPublishMode.replace && canRestore;

  static MaterialDraft? fromJson(Map<String, dynamic> j) {
    final item = RecordItem.fromJson(j);
    if (item == null) return null;
    final src = asInt(j['source_material_id']);
    final pub = asInt(j['published_material_id']);
    return MaterialDraft(
      item: item,
      state: '${j['state'] ?? 'draft'}',
      publishMode: MaterialPublishMode.fromWire(j['publish_mode']),
      publishedMaterialId: pub > 0 ? pub : null,
      sessionId: asInt(j['session_id']),
      sourceMaterialId: src > 0 ? src : null,
      canPublish: j['can_publish'] == true,
      canRestore: j['can_restore'] == true,
      publishedAt: parseRecordingTime(j['published_at']),
    );
  }

  /// The strip's second line.
  String status() {
    if (pendingReplace) return t('استُبدل الأصل — الملف القديم محفوظ', 'Replaced the original — the old file is kept');
    if (item.inProgress) return '${recordStatusLabel(item)}${item.progress == null ? '' : ' · ${item.progress}%'}';
    if (item.isFailed) return item.error ?? t('تعذّر إكمال التعديل', 'The edit could not finish');
    return t('مسودة — لا يراها الطلاب حتى تنشرها', "Draft — students don't see it until you publish it");
  }
}

List<MaterialDraft> materialDraftsFrom(dynamic json) => [
      for (final j in (json is List ? asMapList(json) : asMapList(asMap(json)['items']))) ?MaterialDraft.fromJson(j),
    ];

/// GET …/studio: the material as a Studio source, the course's other videos (merge), its drafts.
class MaterialStudioOpen {
  const MaterialStudioOpen({required this.source, this.others = const [], this.drafts = const []});
  final RecordItem source;
  final List<RecordItem> others;
  final List<MaterialDraft> drafts;

  static MaterialStudioOpen? fromJson(Map<String, dynamic> j) {
    final src = RecordItem.fromJson(asMap(j['source']));
    if (src == null) return null;
    return MaterialStudioOpen(
      source: src,
      others: [for (final o in asMapList(j['others'])) ?RecordItem.fromJson(o)],
      drafts: materialDraftsFrom(j['drafts']),
    );
  }
}

String materialStudioErrorText(Object e) {
  final ex = ApiException.from(e);
  return switch (ex.code) {
    'material_not_video' => t('الاستوديو يعمل على مواد الفيديو فقط', 'The Studio works on video materials only'),
    'material_draft_not_found' => t('هذه المسودة لم تعد موجودة', 'This draft is not there any more'),
    'material_draft_not_ready' => t('المسودة ليست جاهزة بعد', 'The draft is not ready yet'),
    'material_draft_published' => t('نُشرت هذه المسودة بالفعل', 'This draft is already published'),
    'material_source_missing' => t('المادة الأصلية لم تعد موجودة — انشرها مادة جديدة', 'The original material is gone — publish it as a new one'),
    'material_replace_pending' => t('أكّد حذف الملف القديم أو استرجعه من الاستبدال السابق أولاً',
        'Confirm or restore the previous replace of this material first'),
    'material_nothing_to_restore' => t('لا يوجد ملف قديم', 'There is no old file'),
    'course_archived' => t('المقرر مؤرشف — المحتوى للقراءة فقط', 'The course is archived — read only'),
    'feature_disabled' => t('الاستوديو متوقف حالياً', 'The Studio is switched off right now'),
    _ => ex.statusCode == 403 ? t('لا يمكنك تعديل هذه المادة', "You can't edit this material") : recordsErrorText(e),
  };
}

abstract class MaterialStudioApi {
  Future<MaterialStudioOpen?> open(int sessionId, int materialId);
  Future<RecordPlay> playSource(int sessionId, int materialId);
  Future<RecordFrames> frames(int sessionId, int materialId, {int n = recordFramesCount});
  Future<List<MaterialDraft>> edit(int sessionId, int materialId, RecordEdit edit);
  Future<List<MaterialDraft>> merge(int sessionId, int materialId, List<int> ids, {String? title});
  Future<List<MaterialDraft>> sessionDrafts(int sessionId);
  Future<MaterialDraft?> draft(int draftId);
  Future<MaterialDraft?> retry(int draftId);
  Future<RecordPlay> playDraft(int draftId);
  Future<(MaterialDraft?, int)> publish(int draftId, MaterialPublishMode mode);
  Future<MaterialDraft?> restore(int draftId);
  Future<MaterialDraft?> confirm(int draftId);
  Future<bool> discard(int draftId);
}

class RemoteMaterialStudioApi implements MaterialStudioApi {
  RemoteMaterialStudioApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;

  String _m(int sid, int mid) => '/api/v1/sessions/$sid/materials/$mid/studio';
  static const _d = '/api/v1/studio/drafts';

  @override
  Future<MaterialStudioOpen?> open(int sessionId, int materialId) async =>
      MaterialStudioOpen.fromJson(asMap(await _api.get(_m(sessionId, materialId))));

  @override
  Future<RecordPlay> playSource(int sessionId, int materialId) async =>
      RecordPlay.fromJson(asMap(await _api.post('${_m(sessionId, materialId)}/play')), base: _api.baseUrl);

  @override
  Future<RecordFrames> frames(int sessionId, int materialId, {int n = recordFramesCount}) async =>
      RecordFrames.fromJson(asMap(await _api.post('${_m(sessionId, materialId)}/frames', body: {'n': n})), base: _api.baseUrl);

  @override
  Future<List<MaterialDraft>> edit(int sessionId, int materialId, RecordEdit edit) async =>
      materialDraftsFrom(await _api.post('${_m(sessionId, materialId)}/edit', body: edit.toJson()..remove('delete_source')));

  @override
  Future<List<MaterialDraft>> merge(int sessionId, int materialId, List<int> ids, {String? title}) async =>
      materialDraftsFrom(await _api.post('${_m(sessionId, materialId)}/merge', body: {
        'ids': ids,
        if ((title ?? '').trim().isNotEmpty) 'title': title!.trim(),
      }));

  @override
  Future<List<MaterialDraft>> sessionDrafts(int sessionId) async =>
      materialDraftsFrom(await _api.get('/api/v1/sessions/$sessionId/studio/drafts'));

  @override
  Future<MaterialDraft?> draft(int draftId) async => MaterialDraft.fromJson(asMap(await _api.get('$_d/$draftId')));

  @override
  Future<MaterialDraft?> retry(int draftId) async => MaterialDraft.fromJson(asMap(await _api.post('$_d/$draftId/retry')));

  @override
  Future<RecordPlay> playDraft(int draftId) async =>
      RecordPlay.fromJson(asMap(await _api.post('$_d/$draftId/play')), base: _api.baseUrl);

  @override
  Future<(MaterialDraft?, int)> publish(int draftId, MaterialPublishMode mode) async {
    final j = asMap(await _api.post('$_d/$draftId/publish', body: {'mode': mode.wire}));
    return (MaterialDraft.fromJson(asMap(j['draft'])), asInt(j['material_id']));
  }

  @override
  Future<MaterialDraft?> restore(int draftId) async =>
      MaterialDraft.fromJson(asMap(asMap(await _api.post('$_d/$draftId/restore'))['draft']));

  @override
  Future<MaterialDraft?> confirm(int draftId) async =>
      MaterialDraft.fromJson(asMap(asMap(await _api.post('$_d/$draftId/confirm'))['draft']));

  @override
  Future<bool> discard(int draftId) async => asMap(await _api.delete('$_d/$draftId'))['deleted'] == true;
}

/// The Studio's source for a material: edits become drafts ([latest] keeps the latest of each, for the job card's
/// Publish).
class MaterialStudioSource implements StudioSource {
  MaterialStudioSource({required this.sessionId, required this.materialId, MaterialStudioApi? api})
      : api = api ?? RemoteMaterialStudioApi();

  final int sessionId;
  final int materialId;
  final MaterialStudioApi api;
  final latest = <int, MaterialDraft>{};

  List<RecordItem> _keep(Iterable<MaterialDraft> ds) => [
        for (final d in ds) (latest[d.id] = d).item,
      ];

  RecordItem? _one(MaterialDraft? d) => d == null ? null : _keep([d]).first;

  @override
  List<StudioTool> get tools => const [StudioTool.trim, StudioTool.cut, StudioTool.split, StudioTool.speed, StudioTool.quality, StudioTool.merge];
  @override
  bool get drafts => true;
  @override
  String get jobEventKind => 'material_edit';
  @override
  String get framesEventKind => 'material_frames';

  @override
  Future<RecordPlay> play(int sourceId) => api.playSource(sessionId, sourceId);
  @override
  Future<RecordFrames> frames(int sourceId) => api.frames(sessionId, sourceId);
  @override
  Future<List<RecordItem>> edit(int sourceId, RecordEdit edit) async => _keep(await api.edit(sessionId, sourceId, edit));
  @override
  Future<List<RecordItem>> merge(List<int> sourceIds, {String? title, bool deleteSources = false}) async =>
      _keep(await api.merge(sessionId, materialId, sourceIds, title: title));
  @override
  Future<RecordItem?> get(int jobId) async => _one(await api.draft(jobId));
  @override
  Future<RecordItem?> retry(int jobId) async => _one(await api.retry(jobId));
  @override
  Future<RecordItem?> setCover(int sourceId, Uint8List bytes, {String fileName = 'cover.jpg'}) async => null;
  @override
  Future<RecordItem?> clearCover(int sourceId) async => null;
}
