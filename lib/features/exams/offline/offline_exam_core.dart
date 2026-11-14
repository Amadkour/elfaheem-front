// Offline sittings (no internet in the hall) — the pure parts the unit tests cover. Nothing here touches the network,
// the disk or the widget tree.
//
// Server contract: ../../../../../../back/exam_engine/services/offline.py
//   package  AES-256-GCM(K_exam, content), AAD "pkg|<exam>|<n>". Anyone in the course may carry the ciphertext; the key
//            comes from the server only inside the exam window (or from a nearby phone that already has it).
//   bundle   AES-256-GCM(K_student, payload), AAD "<bundle>|<exam>|<student>". A relay can neither read nor change it.
//   receipt  HMAC-SHA256(K_student, "exr|<bundle>|<attempt>"): the only proof that the server really took the answers.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as dc;
import 'package:cryptography/cryptography.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMap, asMapList, t;

/// Where a sitting is, in the student's words: downloaded → in progress (saved on the phone) → waiting to sync → submitted.
enum OfflineStage { downloaded, inProgress, waitingToSync, submitted, rejected }

OfflineStage offlineStageOf(String? s) => OfflineStage.values.firstWhere((e) => e.name == s, orElse: () => OfflineStage.downloaded);

String offlineStageText(OfflineStage s, {bool hasKey = false}) => switch (s) {
      OfflineStage.downloaded => hasKey ? t('جاهز للبدء', 'Ready to start') : t('تم التنزيل — يُفتح عند بدء الاختبار', 'Downloaded — opens when the exam starts'),
      OfflineStage.inProgress => t('قيد الحل — محفوظ على هذا الجهاز', 'In progress — saved on this phone'),
      OfflineStage.waitingToSync => t('بانتظار الإرسال', 'Waiting to sync'),
      OfflineStage.submitted => t('تم التسليم', 'Submitted'),
      OfflineStage.rejected => t('لم يُقبل', 'Not accepted'),
    };

/// Bilingual texts for the offline codes (server and relay).
String offlineCodeText(String? code) => switch (code) {
      'offline_disabled' => t('المعلم لم يفعّل الاختبار دون اتصال', 'The teacher has not allowed this exam offline'),
      'not_a_student' => t('هذا الاختبار ليس لك', 'This exam is not for you'),
      'exam_not_open' => t('الاختبار غير متاح الآن', 'The exam is not open now'),
      'not_started' => t('لم يبدأ الاختبار بعد — حاول عند البدء', 'The exam has not started yet — try at the start'),
      'exam_ended' => t('انتهى وقت الاختبار', 'The exam has ended'),
      'no_key' => t('الجهاز القريب لا يملك مفتاح الاختبار بعد', 'The nearby phone does not have the exam key yet'),
      'no_package' => t('الجهاز القريب لا يملك هذا الاختبار', 'The nearby phone does not have this exam'),
      'bad_package' => t('وصلت نسخة تالفة — حاول مع جهاز آخر', 'A damaged copy arrived — try another phone'),
      'bad_key' => t('المفتاح لا يفتح هذا الاختبار', 'The key does not open this exam'),
      'bad_seal' => t('تعذر التحقق من ختم الإجابات', 'The answers\' seal could not be verified'),
      'seal_required' => t('هذه الإجابات تُرسل من جهاز الطالب أو المعلم فقط', 'These answers can only be sent from the student\'s or the teacher\'s phone'),
      'unknown_package' => t('نسخة الاختبار غير معروفة للخادم', 'The server does not know this copy of the exam'),
      'no_attempts_left' => t('استُهلكت المحاولات — اطلب من المعلم محاولة إضافية', 'No attempts left — ask the teacher for another attempt'),
      'bundle_conflict' => t('هذه الإجابات مسجلة لطالب آخر', 'These answers belong to another student'),
      'forbidden' => t('لا يمكنك رفع هذه الإجابات', 'You cannot upload these answers'),
      'held' => t('حُفظت على جهاز قريب وسيرسلها عند اتصاله', 'Kept on a nearby phone; it sends them when it is online'),
      'no_relay' => t('لا يوجد جهاز قريب — اقترب من زميل أو من المعلم', 'No phone nearby — move closer to a classmate or the teacher'),
      'bluetooth_off' => t('شغّل البلوتوث والموقع ثم أعد المحاولة', 'Turn on Bluetooth and Location, then try again'),
      _ => code ?? '',
    };

// ═══════════════════════════════════════════ the package ═════════════════════════════════════════════════════

/// The server's `package` map: the header in clear, the content encrypted.
class OfflinePackage {
  OfflinePackage(this.json);
  final Map<String, dynamic> json;

  static OfflinePackage fromJson(Map<String, dynamic> j) => OfflinePackage(Map<String, dynamic>.from(j));

  int get examId => asInt(json['exam_id']);
  int get n => asInt(json['n']);
  String get packageId => '${json['package_id'] ?? '$examId.$n'}';
  String get hash => '${json['hash'] ?? ''}';
  int? get courseId => json['course_id'] == null ? null : asInt(json['course_id']);
  String get title => '${json['title'] ?? ''}';
  int? get durationMinutes => json['duration_minutes'] == null ? null : asInt(json['duration_minutes']);
  int get questions => asInt(json['questions']);
  DateTime? get startsAt => _utc(json['starts_at']);
  DateTime? get endsAt => _utc(json['ends_at']);
  String get aad => 'pkg|$examId|$n';

  /// The ciphertext really is what the header names (a relay cannot swap it for another package unnoticed).
  bool get intact {
    try {
      return dc.sha256.convert(base64Decode('${json['data']}')).toString() == hash;
    } catch (_) {
      return false;
    }
  }

  /// Open for the student at [now] by the phone's clock (the key may already be on the phone before the start).
  bool openAt(DateTime now) => (startsAt == null || !now.isBefore(startsAt!)) && (endsAt == null || now.isBefore(endsAt!));
}

DateTime? _utc(dynamic s) {
  if (s == null || '$s'.isEmpty) return null;
  final v = '$s';
  return DateTime.tryParse(v.endsWith('Z') || v.contains('+') ? v : '${v}Z');
}

final _aes = AesGcm.with256bits();

/// Decrypts the package with the exam key; throws when the key or the bytes are wrong (the GCM tag is checked).
Future<Map<String, dynamic>> openPackage(OfflinePackage p, List<int> key) async {
  final ct = base64Decode('${p.json['data']}');
  const macBytes = 16;
  final box = SecretBox(ct.sublist(0, ct.length - macBytes), nonce: base64Decode('${p.json['nonce']}'), mac: Mac(ct.sublist(ct.length - macBytes)));
  final plain = await _aes.decrypt(box, secretKey: SecretKey(key), aad: utf8.encode(p.aad));
  return asMap(jsonDecode(utf8.decode(plain)));
}

/// The question images of an opened package. They travel INSIDE the ciphertext (`media` {id: base64}) and so rest on the
/// phone encrypted, in the package file, and are only ever decoded in memory here. `omitted`: ids the server left out
/// (over its size cap or missing from its store); the screen shows their alt text instead.
class PackageMedia {
  const PackageMedia(this.bytes, this.omitted);
  static const none = PackageMedia({}, {});
  final Map<String, Uint8List> bytes;
  final Set<String> omitted;

  /// An older package, or one without images, gives [none]. A damaged entry is treated as omitted.
  factory PackageMedia.fromContent(Map<String, dynamic> content) {
    final out = <String, Uint8List>{};
    final omitted = <String>{if (content['media_omitted'] is List) for (final x in content['media_omitted'] as List) '$x'};
    final raw = content['media'];
    if (raw is Map) {
      raw.forEach((k, v) {
        try {
          out['$k'] = base64Decode('$v');
        } catch (_) {
          omitted.add('$k');
        }
      });
    }
    return PackageMedia(out, omitted);
  }

  Uint8List? of(String id) => bytes[id];
  bool isOmitted(String id) => !bytes.containsKey(id);
}

// ═══════════════════════════════════════════ one copy, a paper per student ════════════════════════════════════

/// A deterministic stream of 48-bit numbers: HMAC-SHA256("exam-offline-shuffle-v1", "<seed>|<label>|<i>")[:6] — the
/// server's `offline._draws`, byte for byte (48 bits stay exact on the web too).
Iterable<int> _draws(String seed, String label) sync* {
  final mac = dc.Hmac(dc.sha256, utf8.encode('exam-offline-shuffle-v1'));
  for (var i = 0;; i++) {
    final d = mac.convert(utf8.encode('$seed|$label|$i')).bytes;
    var v = 0;
    for (var k = 0; k < 6; k++) {
      v = v * 256 + d[k];
    }
    yield v;
  }
}

/// Fisher–Yates from the last index down, j = draw mod (i + 1) — the server's `offline.shuffled`.
List<T> seededShuffle<T>(List<T> items, String seed, String label) {
  final out = List<T>.of(items);
  final g = _draws(seed, label).iterator;
  for (var i = out.length - 1; i > 0; i--) {
    g.moveNext();
    final j = g.current % (i + 1);
    final x = out[i];
    out[i] = out[j];
    out[j] = x;
  }
  return out;
}

String _optionId(dynamic o) => '${o is Map ? o['id'] : o}';

/// This student's paper from the package's whole sections (the server's `offline.student_paper`): the pool drawn with
/// the required questions always in, then question and option order shuffled when the section says so.
Map<String, dynamic> studentPaper(Map<String, dynamic> paper, String packageId, int studentId) {
  final seed = '$packageId|$studentId';
  final sections = <Map<String, dynamic>>[];
  for (final sec in asMapList(paper['sections'])) {
    final sid = sec['section_id'];
    var qs = asMapList(sec['questions']);
    final size = sec['pool_size'] == null ? 0 : asInt(sec['pool_size']);
    if (size > 0 && size < qs.length) {
      final required = [for (final q in qs) if (q['required'] == true) asInt(q['question_id'])];
      final others = [for (final q in qs) if (q['required'] != true) asInt(q['question_id'])];
      final keep = {...required, ...seededShuffle(others, seed, 'pool|$sid').take(max(0, size - required.length))};
      qs = qs.where((q) => keep.contains(asInt(q['question_id']))).toList();
    }
    if (sec['shuffle_questions'] == true) qs = seededShuffle(qs, seed, 'q|$sid');
    final out = <Map<String, dynamic>>[];
    for (final q in qs) {
      final body = Map<String, dynamic>.from(asMap(q['body']));
      final opts = body['options'] is List ? List<dynamic>.from(body['options'] as List) : const <dynamic>[];
      if (sec['shuffle_options'] == true && opts.isNotEmpty) {
        final byId = {for (final o in opts) _optionId(o): o};
        body['options'] = [for (final id in seededShuffle([for (final o in opts) _optionId(o)], seed, 'o|${q['question_id']}')) byId[id]];
      }
      out.add({...q, 'body': body});
    }
    sections.add({...sec, 'questions': out});
  }
  return {'sections': sections};
}

/// Opens this student's entry of the wrap table (the exam key sealed for them alone); null when it is not theirs.
Future<List<int>?> openWrap({required String wrap, required int examId, required int n, required int studentId, required String studentKeyHex}) async {
  try {
    final raw = base64Decode(wrap);
    final box = SecretBox(raw.sublist(12, raw.length - 16), nonce: raw.sublist(0, 12), mac: Mac(raw.sublist(raw.length - 16)));
    return await _aes.decrypt(box, secretKey: SecretKey(hexBytes(studentKeyHex)), aad: utf8.encode('wrap|$examId|$n|$studentId'));
  } catch (_) {
    return null;
  }
}

// ═══════════════════════════════════════════ the encrypted link ══════════════════════════════════════════════

/// Everything exam-related between two phones is encrypted: X25519 between a fresh key of each side, HKDF-SHA256,
/// AES-256-GCM. Someone listening to the Bluetooth / Wi-Fi traffic reads nothing; the exam key itself never travels
/// readable even inside it when the per-student wrap table exists.
class ExamLink {
  ExamLink._(this._pair, this.pub);
  final SimpleKeyPair _pair;
  final String pub;
  final Map<String, SecretKey> _sessions = {};
  static final _x = X25519();
  static final _kdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static Future<ExamLink> create() async {
    final pair = await _x.newKeyPair();
    return ExamLink._(pair, base64Encode((await pair.extractPublicKey()).bytes));
  }

  Future<SecretKey> _session(String remotePub) async => _sessions[remotePub] ??= await () async {
        final shared = await _x.sharedSecretKey(keyPair: _pair, remotePublicKey: SimplePublicKey(base64Decode(remotePub), type: KeyPairType.x25519));
        return _kdf.deriveKey(secretKey: shared, nonce: utf8.encode('nb-exam-link-v1'), info: utf8.encode('exam-link'));
      }();

  Future<String> seal(String remotePub, String plain) async {
    final box = await _aes.encrypt(utf8.encode(plain), secretKey: await _session(remotePub), nonce: _aes.newNonce());
    return base64Encode([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  /// Throws when the box was not made for this link (or was changed on the way).
  Future<String> open(String remotePub, String box) async {
    final raw = base64Decode(box);
    final b = SecretBox(raw.sublist(12, raw.length - 16), nonce: raw.sublist(0, 12), mac: Mac(raw.sublist(raw.length - 16)));
    return utf8.decode(await _aes.decrypt(b, secretKey: await _session(remotePub)));
  }
}

// ═══════════════════════════════════════════ the timer ═══════════════════════════════════════════════════════

/// The offline timer. Time counts with the phone's MONOTONIC clock while the app runs (changing the date/time does not
/// move it); while the app was closed only the wall clock can tell, so a forward gap counts and a backward one is
/// reported as `clock_changed` (the server sends that attempt to integrity review). Where the phone's clock disagrees
/// with the monotonic one by more than [tolerance], that is reported too.
class OfflineClock {
  OfflineClock({required this.startedWallMs, this.elapsedMs = 0, int? lastWallMs}) : lastWallMs = lastWallMs ?? startedWallMs;
  final int startedWallMs;
  int elapsedMs;
  int lastWallMs;
  static const tolerance = Duration(minutes: 2);

  /// One running tick: [monoDeltaMs] from a Stopwatch since the previous tick. Returns a `clock_changed` event or null.
  Map<String, dynamic>? tick({required int monoDeltaMs, required int wallNowMs}) {
    final wallDelta = wallNowMs - lastWallMs;
    elapsedMs += max(0, monoDeltaMs);
    lastWallMs = wallNowMs;
    final drift = wallDelta - monoDeltaMs;
    return drift.abs() > tolerance.inMilliseconds ? _changed(drift, wallNowMs) : null;
  }

  /// The app was closed and opened again: the closed time counts when the wall clock moved forward.
  Map<String, dynamic>? resume({required int wallNowMs}) {
    final gap = wallNowMs - lastWallMs;
    lastWallMs = wallNowMs;
    if (gap < -const Duration(minutes: 1).inMilliseconds) return _changed(gap, wallNowMs);
    elapsedMs += max(0, gap);
    return null;
  }

  Map<String, dynamic> _changed(int byMs, int at) => {
        'kind': 'clock_changed',
        'at': DateTime.fromMillisecondsSinceEpoch(at, isUtc: true).toIso8601String(),
        'meta': {'by_seconds': byMs ~/ 1000},
      };

  int get elapsedSeconds => elapsedMs ~/ 1000;

  /// Seconds left: the paper's duration against the counted time, and the exam's end against the phone's clock.
  int? remainingSeconds({int? durationMinutes, DateTime? endsAt, required DateTime wallNow}) {
    int? left;
    if (durationMinutes != null && durationMinutes > 0) left = durationMinutes * 60 - elapsedSeconds;
    if (endsAt != null) {
      final toEnd = endsAt.difference(wallNow).inSeconds;
      left = left == null ? toEnd : min(left, toEnd);
    }
    return left == null ? null : max(0, left);
  }

  Map<String, dynamic> toJson() => {'started': startedWallMs, 'elapsed': elapsedMs, 'last': lastWallMs};
  static OfflineClock fromJson(Map<String, dynamic> j) =>
      OfflineClock(startedWallMs: asInt(j['started']), elapsedMs: asInt(j['elapsed']), lastWallMs: asInt(j['last']));
}

// ═══════════════════════════════════════════ the sitting ═════════════════════════════════════════════════════

/// One student's offline sitting of one exam, as kept (encrypted) on the phone.
class OfflineSitting {
  OfflineSitting({required this.examId, required this.n, required this.packageHash, required this.studentId, required this.bundleId,
      this.stage = OfflineStage.downloaded, Map<int, Map<String, dynamic>>? answers, Map<int, int>? seq, this.clock,
      List<Map<String, dynamic>>? events, List<Map<String, dynamic>>? delivery, this.finishedReason, this.finishedAt, this.bundle,
      this.attemptId, this.code, this.lastTry})
      : answers = answers ?? {},
        seq = seq ?? {},
        events = events ?? [],
        delivery = delivery ?? [];

  final int examId;
  final int n;
  final String packageHash;
  final int studentId;
  final String bundleId;
  OfflineStage stage;
  final Map<int, Map<String, dynamic>> answers;
  final Map<int, int> seq;
  OfflineClock? clock;
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> delivery;
  String? finishedReason;
  DateTime? finishedAt;
  Map<String, dynamic>? bundle;            // sealed once finished; sent as is, any number of times
  int? attemptId;
  String? code;                             // the last server / relay answer that was not a success
  DateTime? lastTry;

  static const maxEvents = 200;

  void put(int questionId, Map<String, dynamic> answer) {
    answers[questionId] = answer;
    seq[questionId] = (seq[questionId] ?? 0) + 1;
  }

  void event(String kind, {Map<String, dynamic>? meta, DateTime? at}) {
    if (events.length >= maxEvents) return;
    events.add({'kind': kind, 'at': (at ?? DateTime.now()).toUtc().toIso8601String(), if (meta != null && meta.isNotEmpty) 'meta': meta});
  }

  /// A step of the delivery chain (where the package / key came from, start, finish): sealed into the bundle.
  void step(String step, {String? from, int? by, String? note, DateTime? at}) {
    if (delivery.length >= 20) return;
    delivery.add({'step': step, 'from': ?from, 'by': ?by, 'note': ?note, 'at': (at ?? DateTime.now()).toUtc().toIso8601String()});
  }

  /// What is sealed with the student's key.
  Map<String, dynamic> payload() => {
        'package_n': n,
        'package_hash': packageHash,
        'answers': [for (final e in answers.entries) {'question_id': e.key, 'answer': e.value, 'seq': seq[e.key] ?? 1}],
        'started_at': clock == null ? null : DateTime.fromMillisecondsSinceEpoch(clock!.startedWallMs, isUtc: true).toIso8601String(),
        'finished_at': finishedAt?.toUtc().toIso8601String(),
        'elapsed_seconds': clock?.elapsedSeconds ?? 0,
        'finished_reason': finishedReason,
        'events': events,
        'delivery': delivery,
      };

  Map<String, dynamic> toJson() => {
        'exam_id': examId, 'n': n, 'hash': packageHash, 'student_id': studentId, 'bundle_id': bundleId, 'stage': stage.name,
        'answers': {for (final e in answers.entries) '${e.key}': e.value},
        'seq': {for (final e in seq.entries) '${e.key}': e.value},
        'clock': clock?.toJson(), 'events': events, 'delivery': delivery, 'finished_reason': finishedReason,
        'finished_at': finishedAt?.toUtc().toIso8601String(), 'bundle': bundle, 'attempt_id': attemptId, 'code': code,
        'last_try': lastTry?.toUtc().toIso8601String(),
      };

  static OfflineSitting fromJson(Map<String, dynamic> j) => OfflineSitting(
        examId: asInt(j['exam_id']), n: asInt(j['n']), packageHash: '${j['hash'] ?? ''}', studentId: asInt(j['student_id']),
        bundleId: '${j['bundle_id']}', stage: offlineStageOf(j['stage'] as String?),
        answers: {for (final e in asMap(j['answers']).entries) int.parse(e.key): asMap(e.value)},
        seq: {for (final e in asMap(j['seq']).entries) int.parse(e.key): asInt(e.value)},
        clock: j['clock'] == null ? null : OfflineClock.fromJson(asMap(j['clock'])),
        events: asMapList(j['events']), delivery: asMapList(j['delivery']), finishedReason: j['finished_reason'] as String?,
        finishedAt: _utc(j['finished_at']), bundle: j['bundle'] == null ? null : asMap(j['bundle']),
        attemptId: j['attempt_id'] == null ? null : asInt(j['attempt_id']), code: j['code'] as String?, lastTry: _utc(j['last_try']),
      );
}

/// 32 hex chars from a CSPRNG (the server accepts 8–64 of [A-Za-z0-9_-]).
String newBundleId() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

List<int> hexBytes(String hex) => [for (var i = 0; i + 1 < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];

/// Seals [payload] with the student's key: `enc: k1` + nonce + data. Without a key (never online since the feature
/// arrived) the bundle goes unsealed — the server then takes it only from the student's own login or the teacher.
Future<Map<String, dynamic>> sealBundle({required String bundleId, required int examId, required int studentId, required int n,
    required Map<String, dynamic> payload, String? studentKeyHex}) async {
  final base = {'v': 1, 'bundle_id': bundleId, 'exam_id': examId, 'student_id': studentId, 'package_n': n};
  if (studentKeyHex == null || studentKeyHex.length != 64) return {...base, 'enc': 'none', 'payload': payload};
  final box = await _aes.encrypt(utf8.encode(jsonEncode(payload)), secretKey: SecretKey(hexBytes(studentKeyHex)),
      nonce: _aes.newNonce(), aad: utf8.encode('$bundleId|$examId|$studentId'));
  return {...base, 'enc': 'k1', 'nonce': base64Encode(box.nonce), 'data': base64Encode([...box.cipherText, ...box.mac.bytes])};
}

/// The server's receipt is genuine (a relay cannot fake "accepted").
bool verifyReceipt({required String studentKeyHex, required String bundleId, required int attemptId, required String receipt}) {
  final want = dc.Hmac(dc.sha256, hexBytes(studentKeyHex)).convert(utf8.encode('exr|$bundleId|$attemptId')).toString();
  if (want.length != receipt.length) return false;
  var diff = 0;
  for (var i = 0; i < want.length; i++) {
    diff |= want.codeUnitAt(i) ^ receipt.codeUnitAt(i);
  }
  return diff == 0;
}

// ═══════════════════════════════════════════ transfer ════════════════════════════════════════════════════════

/// Nearby Connections carries at most 32 KB per message and BLE far less, so a package travels in parts.
const kExamPartChars = 12000;

List<String> splitParts(String s, {int size = kExamPartChars}) =>
    [for (var i = 0; i < s.length; i += size) s.substring(i, min(i + size, s.length))];

/// The other side of `splitParts(await link.seal(…))`: ONE box was split, so the parts are joined before it is opened
/// (a part on its own is no box and never opens).
Future<String> openParts(ExamLink me, String remotePub, List<String> parts) => me.open(remotePub, parts.join());

/// The answers file a student can share (any app) and the teacher uploads in bulk.
const kAnswersFileExt = 'nbexam';

String answersFile(List<Map<String, dynamic>> bundles) => jsonEncode({'nextbrain_offline_exam': 1, 'bundles': bundles});

/// Bundles found in an answers file (also accepts a bare bundle or a list); empty when it is not one.
List<Map<String, dynamic>> bundlesInFile(String text) {
  try {
    final d = jsonDecode(text);
    if (d is Map && d['bundles'] is List) return asMapList(d['bundles']).where(_looksLikeBundle).toList();
    if (d is Map && _looksLikeBundle(asMap(d))) return [asMap(d)];
    if (d is List) return asMapList(d).where(_looksLikeBundle).toList();
  } catch (_) {}
  return const [];
}

bool _looksLikeBundle(Map<String, dynamic> b) => b['bundle_id'] != null && b['exam_id'] != null && b['student_id'] != null;
