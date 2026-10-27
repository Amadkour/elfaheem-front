// lib/features/shared/live/meeting_recording.dart — meeting recordings that land in the host's Google Drive /
// OneDrive (docs/backend/live-rooms-spec.md §5). The pure part: models, parsing, code → text, the recorder
// settings a quality means, and the API. Screens are in meeting_recording_sheets.dart; the recorder itself is
// lib/features/teacher/sessions/live/widgets/room_recorder.dart (ClientRecorder, `chunkPath` / `quality`).
//
//   GET    /api/v1/me/cloud                              → [CloudAccount] per provider (available · connected)
//   POST   /api/v1/me/cloud/{provider}/connect           → auth_url (opened in the browser, then GET /me/cloud is
//                                                           polled until `connected`)
//   DELETE /api/v1/me/cloud/{provider}
//   POST   /api/v1/live/{kind}/{id}/recordings           {quality, destination} → [RecordingStart] (201)
//          409 cloud_not_connected · course_session_recording · recording_active
//   POST   /api/v1/live/recordings/{rid}/chunk           multipart (the recorder; `chunk_path` of the start answer)
//   POST   /api/v1/live/recordings/{rid}/stop            is_final without a chunk
//   GET    /api/v1/live/recordings/{rid}                 → [MeetingRecording]
//   POST   /api/v1/live/recordings/{rid}/retry           failed → uploading again
//   GET    /api/v1/live/{kind}/{id}/recordings           host: all · attendees: the done ones
//
// Course sessions keep their own flow (`record_enabled`, …/recording-chunk); this one is for `kind = meeting`.
// Strings use t(ar, en). Tests: test/org/meeting_recording_test.dart.
import '../../../core/api_client.dart';
import '../../admin/admin_common.dart' show t, asMap, asMapList, asInt;

// ─────────────────────────────────────────────────────────────────────────────
// Cloud drives
// ─────────────────────────────────────────────────────────────────────────────

enum CloudProvider {
  googleDrive('google_drive'),
  onedrive('onedrive');

  const CloudProvider(this.wire);

  /// The value the server uses (`provider` / `destination`).
  final String wire;

  static CloudProvider? fromWire(dynamic v) {
    final s = '${v ?? ''}'.trim().toLowerCase();
    for (final p in values) {
      if (p.wire == s) return p;
    }
    return null;
  }

  String get label => switch (this) {
        CloudProvider.googleDrive => 'Google Drive',
        CloudProvider.onedrive => 'OneDrive',
      };
}

/// One provider as GET /me/cloud reports it.
class CloudAccount {
  const CloudAccount({
    required this.provider,
    this.available = false,
    this.connected = false,
    this.email,
    this.connectedAt,
  });

  final CloudProvider provider;

  /// False until the server has that provider's client id / secret.
  final bool available;
  final bool connected;
  final String? email;
  final DateTime? connectedAt;

  /// The person can start a recording to this drive.
  bool get usable => available && connected;

  static CloudAccount? fromJson(Map<String, dynamic> j) {
    final p = CloudProvider.fromWire(j['provider']);
    if (p == null) return null;
    final email = '${j['email'] ?? ''}'.trim();
    return CloudAccount(
      provider: p,
      available: j['available'] == true,
      connected: j['connected'] == true,
      email: email.isEmpty ? null : email,
      connectedAt: parseRecordingTime(j['connected_at']),
    );
  }

  CloudAccount copyWith({bool? available, bool? connected, String? email}) => CloudAccount(
        provider: provider,
        available: available ?? this.available,
        connected: connected ?? this.connected,
        email: email ?? this.email,
        connectedAt: connectedAt,
      );
}

/// Parses GET /me/cloud. Every provider the app knows is listed, in the enum's order; one the server did not
/// mention is `available: false`, so an older server shows both as "not available" rather than nothing.
List<CloudAccount> cloudAccountsFrom(dynamic json) {
  final byProvider = <CloudProvider, CloudAccount>{};
  for (final j in asMapList(asMap(json)['providers'])) {
    final a = CloudAccount.fromJson(j);
    if (a != null) byProvider[a.provider] = a;
  }
  return [for (final p in CloudProvider.values) byProvider[p] ?? CloudAccount(provider: p)];
}

/// Naive-UTC or ISO timestamps → UTC instant (null when missing).
DateTime? parseRecordingTime(dynamic v) {
  final s = '${v ?? ''}'.trim();
  if (s.isEmpty || s == 'null') return null;
  final zoned = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  return DateTime.tryParse(zoned ? s : '${s}Z')?.toUtc();
}

// ─────────────────────────────────────────────────────────────────────────────
// Quality
// ─────────────────────────────────────────────────────────────────────────────

enum RecordingQuality {
  p1080('1080p', maxHeight: 1080, videoBitsPerSecond: 5000000),
  p720('720p', maxHeight: 720, videoBitsPerSecond: 3000000),
  p480('480p', maxHeight: 480, videoBitsPerSecond: 1500000),
  audio('audio', maxHeight: 0, videoBitsPerSecond: 0);

  const RecordingQuality(this.wire, {required this.maxHeight, required this.videoBitsPerSecond});

  /// The value the server takes (`quality`).
  final String wire;

  /// The recorder's target: the longest side is scaled down to this many pixels (0 = no video).
  final int maxHeight;

  /// The encoder bitrate the recorder asks for (0 = no video track worth bits).
  final int videoBitsPerSecond;

  bool get audioOnly => this == RecordingQuality.audio;

  static RecordingQuality fromWire(dynamic v, {RecordingQuality fallback = RecordingQuality.p720}) {
    final s = '${v ?? ''}'.trim().toLowerCase();
    for (final q in values) {
      if (q.wire == s) return q;
    }
    return fallback;
  }

  String get label => switch (this) {
        RecordingQuality.p1080 => t('1080p — دقة عالية', '1080p — Full HD'),
        RecordingQuality.p720 => t('720p — موصى به', '720p — recommended'),
        RecordingQuality.p480 => t('480p — حجم أصغر', '480p — smaller file'),
        RecordingQuality.audio => t('صوت فقط', 'Audio only'),
      };
}

/// What the recorder is configured with for a quality: the native encoders take a bitrate and a height cap, the
/// web compositor a bitrate. Audio-only is a REAL audio capture on every platform — no canvas / MediaProjection
/// surface / RPScreenRecorder, only the mixed audio (web: MediaRecorder on the audio stream, opus in webm;
/// Android: MediaRecorder AAC in an MP4 container; iOS: AVAssetWriter with audio tracks only), so
/// `videoBitsPerSecond` / `maxHeight` are 0 and the server assembles one `.m4a`.
class RecorderSettings {
  const RecorderSettings({required this.videoBitsPerSecond, required this.maxHeight, required this.audioOnly});

  final int videoBitsPerSecond;
  final int maxHeight;
  final bool audioOnly;

  factory RecorderSettings.of(RecordingQuality q) => RecorderSettings(
        videoBitsPerSecond: q.audioOnly ? 0 : q.videoBitsPerSecond,
        maxHeight: q.audioOnly ? 0 : q.maxHeight,
        audioOnly: q.audioOnly,
      );

  /// What goes over the method channel / into the web compositor's meta.
  Map<String, Object> toMap() => {
        'videoBitrate': videoBitsPerSecond,
        'maxHeight': maxHeight,
        'audioOnly': audioOnly,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Recordings
// ─────────────────────────────────────────────────────────────────────────────

/// The answer of POST /live/{kind}/{id}/recordings.
class RecordingStart {
  const RecordingStart({
    required this.recordingId,
    required this.chunkPath,
    this.status = 'recording',
    this.quality = RecordingQuality.p720,
  });

  final int recordingId;

  /// Where the recorder posts its chunks (`/api/v1/live/recordings/{rid}/chunk`).
  final String chunkPath;
  final String status;

  /// What the person picked (the setup sheet fills it in; the server's answer does not carry it).
  final RecordingQuality quality;

  /// The matching stop route (is_final without a chunk).
  String get stopPath => recordingStopPath(recordingId);

  RecordingStart copyWith({RecordingQuality? quality}) =>
      RecordingStart(recordingId: recordingId, chunkPath: chunkPath, status: status, quality: quality ?? this.quality);

  factory RecordingStart.fromJson(Map<String, dynamic> j) {
    final id = asInt(j['recording_id'], asInt(j['id']));
    final path = '${j['chunk_path'] ?? ''}'.trim();
    return RecordingStart(
      recordingId: id,
      chunkPath: path.isEmpty ? recordingChunkPath(id) : path,
      status: '${j['status'] ?? 'recording'}',
    );
  }
}

String recordingChunkPath(int rid) => '/api/v1/live/recordings/$rid/chunk';
String recordingStopPath(int rid) => '/api/v1/live/recordings/$rid/stop';

/// Statuses the server reports (`status`).
const recordingStatuses = ['recording', 'assembling', 'uploading', 'done', 'failed'];

class MeetingRecording {
  const MeetingRecording({
    required this.id,
    required this.status,
    this.kind = 'meeting',
    this.refId = 0,
    this.quality = RecordingQuality.p720,
    this.destination,
    this.size = 0,
    this.durationSeconds = 0,
    this.remoteUrl,
    this.error,
    this.createdAt,
    this.finishedAt,
  });

  final int id;
  final String kind;
  final int refId;
  final String status;
  final RecordingQuality quality;
  final CloudProvider? destination;
  final int size;
  final int durationSeconds;
  final String? remoteUrl;
  final String? error;
  final DateTime? createdAt;
  final DateTime? finishedAt;

  bool get isRecording => status == 'recording';

  /// Still being worked on (recording, assembling or uploading): the card keeps polling.
  bool get inProgress => status == 'recording' || status == 'assembling' || status == 'uploading';
  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';

  /// A drive link to open.
  bool get canOpen => isDone && (remoteUrl ?? '').startsWith('https://');

  static MeetingRecording? fromJson(Map<String, dynamic> j) {
    final id = asInt(j['recording_id'], asInt(j['id']));
    if (id <= 0) return null;
    final url = '${j['remote_url'] ?? ''}'.trim();
    final err = '${j['error'] ?? ''}'.trim();
    return MeetingRecording(
      id: id,
      kind: '${j['kind'] ?? 'meeting'}',
      // GET …/recordings/{rid} answers `recording_id` + `id` (the room's id); the table row has `ref_id`.
      refId: asInt(j['ref_id'] ?? (j['recording_id'] != null ? j['id'] : 0)),
      status: recordingStatuses.contains('${j['status']}') ? '${j['status']}' : 'recording',
      quality: RecordingQuality.fromWire(j['quality']),
      destination: CloudProvider.fromWire(j['destination']),
      size: asInt(j['size']),
      durationSeconds: asInt(j['duration_seconds']),
      remoteUrl: url.isEmpty ? null : url,
      error: err.isEmpty ? null : err,
      createdAt: parseRecordingTime(j['created_at']),
      finishedAt: parseRecordingTime(j['finished_at']),
    );
  }

  /// `recording` of the meeting detail, or null when there is none.
  static MeetingRecording? latestOf(Map<String, dynamic> detail) {
    final r = detail['recording'];
    return r is Map ? fromJson(asMap(r)) : null;
  }
}

/// Newest first (created_at, then id).
List<MeetingRecording> recordingsFrom(dynamic json) {
  final items = json is List ? asMapList(json) : asMapList(asMap(json)['items'] ?? asMap(json)['recordings']);
  final out = <MeetingRecording>[];
  for (final j in items) {
    final r = MeetingRecording.fromJson(j);
    if (r != null) out.add(r);
  }
  out.sort((a, b) {
    final ca = a.createdAt, cb = b.createdAt;
    if (ca != null && cb != null && ca != cb) return cb.compareTo(ca);
    return b.id.compareTo(a.id);
  });
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Text
// ─────────────────────────────────────────────────────────────────────────────

String recordingStatusLabel(String status) => switch (status) {
      'recording' => t('يسجّل الآن', 'Recording'),
      'assembling' => t('يجمع التسجيل', 'Assembling'),
      'uploading' => t('يرفع إلى السحابة', 'Uploading to the drive'),
      'done' => t('جاهز', 'Ready'),
      'failed' => t('فشل الرفع', 'Upload failed'),
      _ => status,
    };

String recordingSizeLabel(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

String recordingDurationLabel(int seconds) {
  if (seconds <= 0) return '';
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// Server codes of this feature → bilingual text; anything else falls back to the exception's own message.
const meetingRecordingCodes = <String, (String, String)>{
  'cloud_not_connected': ('اربط Google Drive أو OneDrive أولاً من الإعدادات → السحابات المتصلة',
      'Connect Google Drive or OneDrive first (Settings → Connected drives)'),
  'course_session_recording': ('جلسات الدورات تُسجَّل بطريقتها الخاصة، وليس إلى السحابة',
      'Course sessions record their own way, not to a drive'),
  'recording_active': ('هناك تسجيل جارٍ لهذا الاجتماع بالفعل', 'A recording of this meeting is already running'),
  'cloud_provider_unavailable': ('هذه الخدمة غير مهيأة على الخادم بعد', 'This drive is not set up on the server yet'),
  'cloud_auth_failed': ('تعذّر ربط الحساب، حاول مرة أخرى', 'Connecting the account failed, try again'),
  'recording_not_found': ('التسجيل غير موجود', 'Recording not found'),
  'not_host': ('المنظّم فقط يستطيع تسجيل الاجتماع', 'Only the organizer can record the meeting'),
  'orgs_disabled': ('المنظمات متوقفة حالياً', 'Organizations are switched off right now'),
};

String meetingRecordingErrorText(Object e) {
  final ex = ApiException.from(e);
  final pair = meetingRecordingCodes[ex.code ?? ''];
  if (pair != null) return t(pair.$1, pair.$2);
  if (ex.statusCode == 404 || ex.statusCode == 405) {
    return t('هذه الميزة تحتاج تحديث الخادم', 'This feature needs a server update');
  }
  return ex.message;
}

// ─────────────────────────────────────────────────────────────────────────────
// API
// ─────────────────────────────────────────────────────────────────────────────

abstract class MeetingRecordingApi {
  Future<List<CloudAccount>> cloud();
  Future<String> connect(CloudProvider p);
  Future<void> disconnect(CloudProvider p);
  Future<RecordingStart> start(String kind, int id, {required RecordingQuality quality, required CloudProvider destination});
  Future<void> stop(int rid);
  Future<MeetingRecording?> get(int rid);
  Future<MeetingRecording?> retry(int rid);
  Future<List<MeetingRecording>> list(String kind, int id);
}

class RemoteMeetingRecordingApi implements MeetingRecordingApi {
  RemoteMeetingRecordingApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;

  static const _base = '/api/v1';

  @override
  Future<List<CloudAccount>> cloud() async => cloudAccountsFrom(await _api.get('$_base/me/cloud'));

  @override
  Future<String> connect(CloudProvider p) async {
    final r = asMap(await _api.post('$_base/me/cloud/${p.wire}/connect'));
    return '${r['auth_url'] ?? ''}'.trim();
  }

  @override
  Future<void> disconnect(CloudProvider p) => _api.delete('$_base/me/cloud/${p.wire}');

  @override
  Future<RecordingStart> start(String kind, int id,
          {required RecordingQuality quality, required CloudProvider destination}) async =>
      RecordingStart.fromJson(asMap(await _api.post('$_base/live/$kind/$id/recordings',
          body: {'quality': quality.wire, 'destination': destination.wire})));

  @override
  Future<void> stop(int rid) => _api.post('$_base/live/recordings/$rid/stop');

  @override
  Future<MeetingRecording?> get(int rid) async => MeetingRecording.fromJson(asMap(await _api.get('$_base/live/recordings/$rid')));

  @override
  Future<MeetingRecording?> retry(int rid) async =>
      MeetingRecording.fromJson(asMap(await _api.post('$_base/live/recordings/$rid/retry')));

  @override
  Future<List<MeetingRecording>> list(String kind, int id) async => recordingsFrom(await _api.get('$_base/live/$kind/$id/recordings'));
}
