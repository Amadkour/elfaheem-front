// lib/features/records/records_api.dart — "Records" (D-311): the signed-in person's own meeting recordings
// as a library, and their non-destructive edits. The pure part: models, parsing, grouping, validation, times as
// mm:ss, code → text and the API. Screens: records_page.dart; plain-values widgets: records_parts.dart.
//
//   GET    /api/v1/me/records                 → [RecordItem] newest first (each with its meeting)
//   GET    /api/v1/me/records/{rid}           → RecordItem             404 record_not_found (not mine)
//   PATCH  /api/v1/me/records/{rid}           {title} → RecordItem + drive_renamed
//   DELETE /api/v1/me/records/{rid}?drive=1   {deleted, drive_deleted} 409 record_busy · 502 cloud_delete_failed
//   POST   /api/v1/me/records/{rid}/cover     multipart `file`          DELETE …/cover
//   POST   /api/v1/me/records/{rid}/edit      {op, start?, end?, at?, speed?, height?, level?, title?, delete_source?} → 202 {items}
//   POST   /api/v1/me/records/merge           {ids, title?, delete_sources?} → 202 {items}
//   POST   /api/v1/me/records/{rid}/retry     failed → again
//   POST   /api/v1/me/records/{rid}/play      {url: /api/v1/me/records/stream/<token>, mime, expires_in}
//
// Every edit is a NEW item (the source is kept unless the person asks to delete it); a job's progress arrives as
// `job_updated{kind: recording, id, status, stage, progress}` (EventOrPoll in the page). Contract:
// ../back/FLUTTER_API_CHANGES.md "Records". Strings use t(ar, en). Tests: test/org/records_api_test.dart.
import 'dart:math' as math;

import 'dart:typed_data';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t, asMap, asMapList, asInt;
import 'package:flutter_education_app/features/live/meeting_recording.dart' show CloudProvider, RecordingQuality, parseRecordingTime, recordingSizeLabel;

/// The library's kill switch (My profile tile, the page, the deep link).
const kRecordsFeatureKey = 'profile.records';

/// The speeds the server renders (audio pitch kept with atempo).
const recordSpeeds = <double>[0.5, 0.75, 1.25, 1.5, 2.0];

/// No edit keeps or makes a piece shorter than this (the server's MIN_PART).
const recordMinPart = 1.0;

/// Up to this many items in one merge.
const recordMaxMerge = 20;

enum RecordOp {
  trim('trim'),
  split('split'),
  cut('cut'),
  speed('speed'),
  quality('quality'),
  merge('merge'),
  project('project');

  const RecordOp(this.wire);
  final String wire;

  static RecordOp? fromWire(dynamic v) {
    final s = '${v ?? ''}'.trim().toLowerCase();
    for (final o in values) {
      if (o.wire == s) return o;
    }
    return null;
  }

  String get label => switch (this) {
        RecordOp.trim => t('قص', 'Trim'),
        RecordOp.split => t('تقسيم', 'Split'),
        RecordOp.cut => t('حذف فترة', 'Cut a period'),
        RecordOp.speed => t('السرعة', 'Speed'),
        RecordOp.quality => t('الجودة والحجم', 'Quality and size'),
        RecordOp.merge => t('دمج', 'Merge'),
        RecordOp.project => t('تعديل', 'Edit'),
      };

  /// The line under an edited item: what was done to its source.
  String get madeBy => switch (this) {
        RecordOp.trim => t('مقصوص', 'Trimmed'),
        RecordOp.split => t('جزء من تقسيم', 'Split part'),
        RecordOp.cut => t('بعد حذف فترة', 'Period cut'),
        RecordOp.speed => t('سرعة معدّلة', 'Speed changed'),
        RecordOp.quality => t('جودة معدّلة', 'Quality changed'),
        RecordOp.merge => t('مدمج', 'Merged'),
        RecordOp.project => t('معدّل في الاستوديو', 'Edited in the Studio'),
      };
}

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

/// One item of the library.
class RecordItem {
  const RecordItem({
    required this.id,
    required this.status,
    this.kind = 'meeting',
    this.title = '',
    this.customTitle = false,
    this.stage,
    this.progress,
    this.operation,
    this.opParams = const {},
    this.sourceIds = const [],
    this.coverUrl,
    this.durationSeconds = 0,
    this.size = 0,
    this.quality = RecordingQuality.p720,
    this.destination,
    this.remoteUrl,
    this.error,
    this.retryMode,
    this.createdAt,
    this.finishedAt,
    this.meetingId = 0,
    this.meetingTitle,
    this.meetingAt,
    this.canEdit = false,
    this.canPlay = false,
    this.hasProject = false,
    this.cancelled = false,
    this.updatedAt,
  });

  final int id;

  /// `meeting` (a room recording) or `edit` (made in Records).
  final String kind;
  final String title;
  final bool customTitle;

  /// recording · assembling · uploading · done · failed
  final String status;

  /// While a job runs: downloading · processing · uploading.
  final String? stage;
  final int? progress;
  final RecordOp? operation;
  final Map<String, dynamic> opParams;
  final List<int> sourceIds;
  final String? coverUrl;
  final double durationSeconds;
  final int size;
  final RecordingQuality quality;
  final CloudProvider? destination;
  final String? remoteUrl;
  final String? error;

  /// failed: `auto` (an automatic retry is booked) · `manual` · null.
  final String? retryMode;
  final DateTime? createdAt;
  final DateTime? finishedAt;
  final int meetingId;
  final String? meetingTitle;
  final DateTime? meetingAt;
  final bool canEdit;
  final bool canPlay;

  /// Rendered from a Studio project (D-590): it can be opened again to continue its edit.
  final bool hasProject;

  /// Failed because the person stopped it (D-594).
  final bool cancelled;

  /// The job's last heartbeat (the ETA reads its pace).
  final DateTime? updatedAt;

  bool get isEdit => kind == 'edit';
  bool get isAudio => quality.audioOnly;
  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';
  bool get inProgress => status == 'recording' || status == 'assembling' || status == 'uploading';

  /// Can be picked for a merge.
  bool get mergeable => isDone && canEdit;
  bool get canOpenDrive => isDone && (remoteUrl ?? '').startsWith('https://');

  /// The library line under the title: length · size · when.
  List<String> facts() => [
        if (durationSeconds > 0) mmss(durationSeconds),
        if (size > 0) recordingSizeLabel(size),
        if (destination != null) destination!.label,
      ];

  static RecordItem? fromJson(Map<String, dynamic> j) {
    final id = asInt(j['recording_id'], asInt(j['id']));
    if (id <= 0) return null;
    final m = j['meeting'] is Map ? asMap(j['meeting']) : const <String, dynamic>{};
    String? s(dynamic v) {
      final x = '${v ?? ''}'.trim();
      return x.isEmpty || x == 'null' ? null : x;
    }

    final status = '${j['status'] ?? ''}';
    final p = j['progress'];
    return RecordItem(
      id: id,
      kind: s(j['kind']) ?? 'meeting',
      title: s(j['title']) ?? s(m['title']) ?? s(j['file_name']) ?? t('تسجيل', 'Recording'),
      customTitle: j['custom_title'] == true,
      status: const ['recording', 'assembling', 'uploading', 'done', 'failed'].contains(status) ? status : 'recording',
      stage: s(j['stage']),
      progress: p == null ? null : asInt(p).clamp(0, 100),
      operation: RecordOp.fromWire(j['operation']),
      opParams: j['op_params'] is Map ? asMap(j['op_params']) : const {},
      sourceIds: [for (final x in (j['source_ids'] is List ? j['source_ids'] as List : const [])) asInt(x)],
      coverUrl: s(j['cover_url']),
      durationSeconds: _num(j['duration_seconds']),
      size: asInt(j['size']),
      quality: RecordingQuality.fromWire(j['quality']),
      destination: CloudProvider.fromWire(j['destination']),
      remoteUrl: s(j['remote_url']),
      error: s(j['error']),
      retryMode: s(j['retry_mode']),
      createdAt: parseRecordingTime(j['created_at']),
      finishedAt: parseRecordingTime(j['finished_at']),
      meetingId: asInt(m['id'], asInt(j['ref_id'] ?? (j['recording_id'] != null ? j['id'] : 0))),
      meetingTitle: s(m['title']),
      meetingAt: parseRecordingTime(m['starts_at']),
      canEdit: j['can_edit'] == true,
      canPlay: j['can_play'] == true,
      hasProject: j['has_project'] == true,
      cancelled: j['cancelled'] == true,
      updatedAt: parseRecordingTime(j['updated_at']),
    );
  }
}

/// GET /me/records (or an edit's `items`), newest first.
List<RecordItem> recordsFrom(dynamic json) {
  final items = json is List ? asMapList(json) : asMapList(asMap(json)['items']);
  final out = <RecordItem>[];
  for (final j in items) {
    final r = RecordItem.fromJson(j);
    if (r != null) out.add(r);
  }
  return out..sort(_newestFirst);
}

int _newestFirst(RecordItem a, RecordItem b) {
  final ca = a.createdAt, cb = b.createdAt;
  if (ca != null && cb != null && ca != cb) return cb.compareTo(ca);
  return b.id.compareTo(a.id);
}

/// The items of one meeting (an edit lives with the meeting of its first source).
class RecordGroup {
  const RecordGroup({required this.meetingId, required this.title, required this.items, this.at});

  final int meetingId;
  final String title;
  final DateTime? at;
  final List<RecordItem> items;
}

/// [items] (newest first) grouped by meeting, the group of the newest item first; inside a group newest first.
List<RecordGroup> groupRecords(List<RecordItem> items) {
  final order = <int>[];
  final by = <int, List<RecordItem>>{};
  for (final r in items) {
    final k = r.meetingId;
    if (!by.containsKey(k)) order.add(k);
    (by[k] ??= []).add(r);
  }
  return [
    for (final k in order)
      RecordGroup(
        meetingId: k,
        title: by[k]!.map((r) => r.meetingTitle).firstWhere((x) => (x ?? '').isNotEmpty, orElse: () => null) ??
            t('اجتماع', 'Meeting'),
        at: by[k]!.map((r) => r.meetingAt).firstWhere((x) => x != null, orElse: () => null) ??
            by[k]!.last.createdAt,
        items: by[k]!,
      ),
  ];
}

/// [items] with [fresh] put in place of the item with the same id (or added on top), newest first again.
List<RecordItem> mergeRecordItems(List<RecordItem> items, List<RecordItem> fresh) {
  final ids = {for (final f in fresh) f.id};
  return [...fresh, ...items.where((r) => !ids.contains(r.id))]..sort(_newestFirst);
}

/// [items] without the ones whose id is in [ids].
List<RecordItem> withoutRecords(List<RecordItem> items, Set<int> ids) => [for (final r in items) if (!ids.contains(r.id)) r];

// ─────────────────────────────────────────────────────────────────────────────
// Text
// ─────────────────────────────────────────────────────────────────────────────

/// Seconds → "mm:ss" ("h:mm:ss" from an hour on); tenths are dropped, never rounded up past the end.
String mmss(double seconds) {
  final total = seconds.isFinite && seconds > 0 ? seconds.floor() : 0;
  final h = total ~/ 3600, m = (total % 3600) ~/ 60, s = total % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// "mm:ss" / "h:mm:ss" / plain seconds → seconds (null when it is not a time).
double? parseMmss(String text) {
  final s = text.trim();
  if (s.isEmpty) return null;
  final parts = s.split(':');
  if (parts.length > 3) return null;
  var total = 0.0;
  for (var i = 0; i < parts.length; i++) {
    final v = double.tryParse(parts[i]);
    if (v == null || v < 0) return null;
    if (i > 0 && v >= 60) return null;
    total = total * 60 + v;
  }
  return total;
}

String speedLabel(double s) => '×${s == s.roundToDouble() ? s.toInt() : s}';

String recordStatusLabel(RecordItem r) => switch (r.status) {
      'recording' => t('يسجّل الآن', 'Recording'),
      'assembling' => switch (r.stage) {
          'queued' => t('في الانتظار — يبدأ قريباً', 'Waiting its turn'),
          'downloading' => t('يجلب الملف', 'Fetching the file'),
          'processing' => t('يجري التعديل', 'Editing'),
          _ => r.isEdit ? t('يجري التعديل', 'Editing') : t('يجمع التسجيل', 'Assembling'),
        },
      'uploading' => t('يحفظ في السحابة', 'Saving to the drive'),
      'done' => t('جاهز', 'Ready'),
      'failed' => r.cancelled ? t('أوقفته', 'Stopped') : (r.retryMode == 'auto' ? t('ستُعاد المحاولة', 'Retrying soon') : t('فشل', 'Failed')),
      _ => r.status,
    };

/// What a job's new item will be called by default (the person can change it in the sheet).
String defaultEditTitle(String source, RecordOp op, {double? speed, int? height}) => switch (op) {
      RecordOp.speed => '$source · ${speedLabel(speed ?? 1)}',
      RecordOp.quality when height != null => '$source · ${height}p',
      RecordOp.split => source,
      _ => '$source · ${op.madeBy}',
    };

const recordsCodes = <String, (String, String)>{
  'record_not_found': ('هذا التسجيل غير موجود', 'This recording is not there any more'),
  'record_not_ready': ('التسجيل ليس جاهزاً بعد', 'The recording is not ready yet'),
  'record_busy': ('انتظر حتى ينتهي العمل على هذا التسجيل', 'Wait until the work on this recording is finished'),
  'records_busy': ('لديك تعديلات جارية — انتظر حتى ينتهي بعضها', 'You have edits running — wait for some to finish'),
  'record_source_missing': ('التسجيل الأصلي لم يعد موجوداً', 'The original recording is gone'),
  'bad_range': ('الفترة المختارة غير صالحة', 'The chosen period is not valid'),
  'bad_speed': ('سرعة غير مدعومة', 'That speed is not supported'),
  'bad_quality': ('اختيار الجودة غير صالح', 'That quality is not supported'),
  'bad_merge': ('اختر تسجيلين مختلفين على الأقل', 'Pick at least two different recordings'),
  'bad_title': ('اكتب اسماً للتسجيل', 'Type a name for the recording'),
  'cloud_not_connected': ('اربط حساب السحابة أولاً من الإعدادات → السحابات المتصلة',
      'Connect the drive first (Settings → Connected drives)'),
  'cloud_delete_failed': ('تعذّر حذف الملف من السحابة — لم يُحذف شيء', "The drive refused to delete the file — nothing was deleted"),
  'stream_expired': ('انتهت صلاحية رابط التشغيل — افتح التسجيل من جديد', 'The play link expired — open the recording again'),
  'not_failed': ('هذا التسجيل لم يفشل', 'This recording did not fail'),
};

String recordsErrorText(Object e) {
  final ex = ApiException.from(e);
  final pair = recordsCodes[ex.code ?? ''];
  if (pair != null) return t(pair.$1, pair.$2);
  if (ex.statusCode == 404 || ex.statusCode == 405) return t('هذه الميزة تحتاج تحديث الخادم', 'This feature needs a server update');
  return ex.message;
}

// ─────────────────────────────────────────────────────────────────────────────
// Quality and size (the server's records_edit.py: the same heights, levels and bitrate ceilings)
// ─────────────────────────────────────────────────────────────────────────────

const studioQualityHeights = <int>[1080, 720, 480];

enum StudioQualityLevel {
  small('small'),
  balanced('balanced'),
  best('best');

  const StudioQualityLevel(this.wire);
  final String wire;

  String get label => switch (this) {
        StudioQualityLevel.small => t('ملف أصغر', 'Smaller file'),
        StudioQualityLevel.balanced => t('متوازن', 'Balanced'),
        StudioQualityLevel.best => t('أعلى جودة', 'Best quality'),
      };
}

const _qualityCeilingKbps = <int, Map<StudioQualityLevel, int>>{
  1080: {StudioQualityLevel.small: 1800, StudioQualityLevel.balanced: 3000, StudioQualityLevel.best: 5500},
  720: {StudioQualityLevel.small: 900, StudioQualityLevel.balanced: 1500, StudioQualityLevel.best: 2800},
  480: {StudioQualityLevel.small: 500, StudioQualityLevel.balanced: 800, StudioQualityLevel.best: 1400},
  1440: {StudioQualityLevel.small: 3500, StudioQualityLevel.balanced: 6000, StudioQualityLevel.best: 9000},
  2160: {StudioQualityLevel.small: 6000, StudioQualityLevel.balanced: 10000, StudioQualityLevel.best: 16000},
};

/// The most a file of [seconds] can weigh at this size and level (bytes): the server caps the bitrate, so this is a
/// ceiling; a quiet video such as a whiteboard comes out well under it. [sourceHeight] stands in when [height] is null.
int studioQualityCeilingBytes(double seconds, {int? height, required StudioQualityLevel level, required int sourceHeight}) {
  final h = height ??
      (sourceHeight >= 1800 ? 2160 : (sourceHeight >= 1300 ? 1440 : (sourceHeight >= 1000 ? 1080 : (sourceHeight >= 700 ? 720 : 480))));
  return ((_qualityCeilingKbps[h]![level]! + 128) * 1000 / 8 * math.max(0, seconds)).round();
}

// ─────────────────────────────────────────────────────────────────────────────
// Edits
// ─────────────────────────────────────────────────────────────────────────────

/// One edit request on one item (merge has its own call).
class RecordEdit {
  const RecordEdit({required this.op, this.start, this.end, this.at, this.speed, this.height, this.level, this.title, this.deleteSource = false});

  final RecordOp op;
  final double? start;
  final double? end;
  final double? at;
  final double? speed;

  /// Quality and size: the short side in pixels (null: as it is) and how much of the file goes on detail.
  final int? height;
  final StudioQualityLevel? level;
  final String? title;
  final bool deleteSource;

  Map<String, dynamic> toJson() {
    double r3(double v) => (v * 1000).roundToDouble() / 1000;
    return {
      'op': op.wire,
      if ((op == RecordOp.trim || op == RecordOp.cut) && start != null) 'start': r3(start!),
      if ((op == RecordOp.trim || op == RecordOp.cut) && end != null) 'end': r3(end!),
      if (op == RecordOp.split && at != null) 'at': r3(at!),
      if (op == RecordOp.speed && speed != null) 'speed': speed,
      if (op == RecordOp.quality && height != null) 'height': height,
      if (op == RecordOp.quality && level != null) 'level': level!.wire,
      if ((title ?? '').trim().isNotEmpty) 'title': title!.trim(),
      if (deleteSource) 'delete_source': true,
    };
  }
}

/// Why [e] cannot run on an item of [duration] seconds (the server's rules), or null when it can.
String? editProblem(RecordEdit e, double duration) {
  final d = duration > 0 ? duration : double.infinity;
  switch (e.op) {
    case RecordOp.trim:
    case RecordOp.cut:
      final a = e.start ?? -1, b = e.end ?? -1;
      if (a < 0 || b <= a) return t('حدّد بداية ونهاية الفترة', 'Set the start and the end');
      if (b - a < recordMinPart) return t('الفترة قصيرة جداً', 'The period is too short');
      if (e.op == RecordOp.cut && d.isFinite && d - (b.clamp(0, d) - a) < recordMinPart) {
        return t('لا يمكن حذف التسجيل كله — احذفه من القائمة', "You can't cut the whole recording — delete it instead");
      }
      if (e.op == RecordOp.trim && a >= d) return t('الفترة خارج التسجيل', 'The period is outside the recording');
      return null;
    case RecordOp.split:
      final at = e.at ?? -1;
      if (at < recordMinPart || (d.isFinite && at > d - recordMinPart)) {
        return t('ضع نقطة التقسيم داخل التسجيل', 'Put the split point inside the recording');
      }
      return null;
    case RecordOp.speed:
      return recordSpeeds.contains(e.speed) ? null : t('اختر سرعة', 'Pick a speed');
    case RecordOp.quality:
      return null;
    case RecordOp.merge:
    case RecordOp.project:
      return null;
  }
}

/// What the new item(s) will last: one value, two for a split.
List<double> editResultDurations(RecordEdit e, double duration) {
  switch (e.op) {
    case RecordOp.trim:
      return [((e.end ?? duration).clamp(0, duration) - (e.start ?? 0)).clamp(0, duration).toDouble()];
    case RecordOp.cut:
      final cut = (e.end ?? 0).clamp(0, duration) - (e.start ?? 0);
      return [(duration - cut).clamp(0, duration).toDouble()];
    case RecordOp.split:
      final at = (e.at ?? 0).clamp(0, duration).toDouble();
      return [at, duration - at];
    case RecordOp.speed:
      return [duration / (e.speed ?? 1)];
    case RecordOp.quality:
      return [duration];
    case RecordOp.merge:
    case RecordOp.project:
      return [duration];
  }
}

/// The merge's length: the sum of its parts.
double mergedDuration(List<RecordItem> items) => items.fold(0.0, (s, r) => s + r.durationSeconds);

// ─────────────────────────────────────────────────────────────────────────────
// API
// ─────────────────────────────────────────────────────────────────────────────

/// The answer of POST …/play: [url] is absolute (the API's base prepended).
class RecordPlay {
  const RecordPlay({required this.url, this.mime = 'video/mp4', this.expiresIn = 0});

  final String url;
  final String mime;
  final int expiresIn;

  bool get audio => mime.startsWith('audio/');

  static RecordPlay fromJson(Map<String, dynamic> j, {required String base}) {
    final raw = '${j['url'] ?? ''}'.trim();
    final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return RecordPlay(
      url: raw.startsWith('/') ? '$root$raw' : raw,
      mime: '${j['mime'] ?? 'video/mp4'}',
      expiresIn: asInt(j['expires_in']),
    );
  }
}

abstract class RecordsApi {
  Future<List<RecordItem>> list();
  Future<RecordItem?> get(int id);
  Future<(RecordItem?, bool)> rename(int id, String title);
  Future<bool> delete(int id, {bool drive = false});
  Future<RecordItem?> setCover(int id, Uint8List bytes, {String fileName = 'cover.jpg'});
  Future<RecordItem?> clearCover(int id);
  Future<List<RecordItem>> edit(int id, RecordEdit edit);
  Future<List<RecordItem>> merge(List<int> ids, {String? title, bool deleteSources = false});
  Future<RecordItem?> retry(int id);
  Future<RecordPlay> play(int id);
}

class RemoteRecordsApi implements RecordsApi {
  RemoteRecordsApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;

  static const _base = '/api/v1/me/records';

  @override
  Future<List<RecordItem>> list() async => recordsFrom(await _api.get(_base));

  @override
  Future<RecordItem?> get(int id) async => RecordItem.fromJson(asMap(await _api.get('$_base/$id')));

  @override
  Future<(RecordItem?, bool)> rename(int id, String title) async {
    final j = asMap(await _api.patch('$_base/$id', body: {'title': title}));
    return (RecordItem.fromJson(j), j['drive_renamed'] == true);
  }

  @override
  Future<bool> delete(int id, {bool drive = false}) async {
    final j = asMap(await _api.delete('$_base/$id', queryParams: drive ? const {'drive': 1} : null));
    return j['drive_deleted'] == true;
  }

  @override
  Future<RecordItem?> setCover(int id, Uint8List bytes, {String fileName = 'cover.jpg'}) async =>
      RecordItem.fromJson(asMap(await _api.postMultipart('$_base/$id/cover',
          fields: const {}, fileField: 'file', fileName: fileName, fileBytes: bytes)));

  @override
  Future<RecordItem?> clearCover(int id) async => RecordItem.fromJson(asMap(await _api.delete('$_base/$id/cover')));

  @override
  Future<List<RecordItem>> edit(int id, RecordEdit edit) async =>
      recordsFrom(await _api.post('$_base/$id/edit', body: edit.toJson()));

  @override
  Future<List<RecordItem>> merge(List<int> ids, {String? title, bool deleteSources = false}) async =>
      recordsFrom(await _api.post('$_base/merge', body: {
        'ids': ids,
        if ((title ?? '').trim().isNotEmpty) 'title': title!.trim(),
        if (deleteSources) 'delete_sources': true,
      }));

  @override
  Future<RecordItem?> retry(int id) async => RecordItem.fromJson(asMap(await _api.post('$_base/$id/retry')));

  @override
  Future<RecordPlay> play(int id) async =>
      RecordPlay.fromJson(asMap(await _api.post('$_base/$id/play')), base: _api.baseUrl);
}
