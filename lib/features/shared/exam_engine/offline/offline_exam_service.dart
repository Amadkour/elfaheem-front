// Offline sittings — server calls, the phone's encrypted store, and the sync that keeps the phone ready and settles
// finished sittings when a connection comes back (the AttendanceOfflineSync pattern).
//
// On the phone:  packages  <support dir>/offline_exams/pkg_<exam>_<n>.json   (the server's ciphertext, safe at rest)
//                sittings  …/sit_<exam>_<student>.bin  AES-GCM with a per-install key kept in secure storage
//                held      …/held_<bundle>.json  sealed bundles of OTHER students this phone carries (relay / teacher)
//                keys      secure storage: the student's sealing key, each exam key once released
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../admin/admin_common.dart' show asInt, asMap, asMapList;
import '../exam_engine_api.dart';
import 'offline_exam_core.dart';

/// Students sit offline on phones only (the web has no nearby link and no safe local store); teachers manage anywhere.
bool get offlineExamsSupported => !kIsWeb;

class OfflineExamApi {
  OfflineExamApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const base = '/api/v1/exam';

  Future<EngineResult> key() => engineCall(() => _api.get('$base/offline/key'));
  Future<EngineResult> package(int examId) => engineCall(() => _api.get('$base/exams/$examId/offline/package'));
  Future<EngineResult> submit(List<Map<String, dynamic>> bundles) => engineCall(() => _api.post('$base/offline/submissions', body: {'bundles': bundles}));
  Future<EngineResult> overview(int examId) => engineCall(() => _api.get('$base/exams/$examId/offline'));
  Future<EngineResult> setEnabled(int examId, bool on) => engineCall(() => _api.put('$base/exams/$examId/offline', body: {'enabled': on}));
  Future<EngineResult> grade(int examId) => engineCall(() => _api.post('$base/exams/$examId/offline/grade'));
}

class StudentSealKey {
  const StudentSealKey(this.userId, this.key);
  final int userId;
  final String key;
}

class OfflineExamStore {
  OfflineExamStore._();
  static final OfflineExamStore instance = OfflineExamStore._();

  static const _kStudent = 'offline_exam_student_key_v1';
  static const _kLocal = 'offline_exam_local_key_v1';
  final _secure = const FlutterSecureStorage();
  final _aes = AesGcm.with256bits();
  Directory? _dir;

  Future<Directory> _root() async {
    final d = _dir ??= Directory('${(await getApplicationSupportDirectory()).path}/offline_exams');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _file(String name) async => File('${(await _root()).path}/$name');

  // ── keys ──
  Future<StudentSealKey?> studentKey() async {
    try {
      final raw = await _secure.read(key: _kStudent);
      if (raw == null) return null;
      final j = asMap(jsonDecode(raw));
      return StudentSealKey(asInt(j['user_id']), '${j['key']}');
    } catch (_) {
      return null;
    }
  }

  Future<void> saveStudentKey(int userId, String key) async {
    try {
      await _secure.write(key: _kStudent, value: jsonEncode({'user_id': userId, 'key': key}));
    } catch (_) {}
  }

  Future<List<int>?> examKey(int examId, int n) async {
    try {
      final v = await _secure.read(key: 'offline_exam_key_${examId}_$n');
      return v == null ? null : base64Decode(v);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveExamKey(int examId, int n, List<int> key) async {
    try {
      await _secure.write(key: 'offline_exam_key_${examId}_$n', value: base64Encode(key));
    } catch (_) {}
  }

  Future<SecretKey> _localKey() async {
    var v = await _secure.read(key: _kLocal);
    if (v == null) {
      v = base64Encode(await (await _aes.newSecretKey()).extractBytes());
      await _secure.write(key: _kLocal, value: v);
    }
    return SecretKey(base64Decode(v));
  }

  // ── packages ──
  Future<void> savePackage(OfflinePackage p) async => (await _file('pkg_${p.examId}_${p.n}.json')).writeAsString(jsonEncode(p.json), flush: true);

  Future<OfflinePackage?> package(int examId, int n) async {
    try {
      final f = await _file('pkg_${examId}_$n.json');
      if (!await f.exists()) return null;
      return OfflinePackage.fromJson(asMap(jsonDecode(await f.readAsString())));
    } catch (_) {
      return null;
    }
  }

  /// Every package on the phone, newest copy per exam.
  Future<List<OfflinePackage>> packages() async {
    final best = <int, OfflinePackage>{};
    try {
      await for (final f in (await _root()).list()) {
        final name = f.uri.pathSegments.last;
        if (f is! File || !name.startsWith('pkg_')) continue;
        try {
          final p = OfflinePackage.fromJson(asMap(jsonDecode(await f.readAsString())));
          if ((best[p.examId]?.n ?? -1) < p.n) best[p.examId] = p;
        } catch (_) {}
      }
    } catch (_) {}
    return best.values.toList()..sort((a, b) => (a.startsAt ?? DateTime(2100)).compareTo(b.startsAt ?? DateTime(2100)));
  }

  Future<OfflinePackage?> latestPackage(int examId) async {
    for (final p in await packages()) {
      if (p.examId == examId) return p;
    }
    return null;
  }

  // ── sittings (encrypted at rest) ──
  Future<void> saveSitting(OfflineSitting s) async {
    final box = await _aes.encrypt(utf8.encode(jsonEncode(s.toJson())), secretKey: await _localKey(), nonce: _aes.newNonce());
    final f = await _file('sit_${s.examId}_${s.studentId}.bin');
    await f.writeAsString(jsonEncode({'n': base64Encode(box.nonce), 'd': base64Encode([...box.cipherText, ...box.mac.bytes])}), flush: true);
  }

  Future<OfflineSitting?> _readSitting(File f) async {
    try {
      final j = asMap(jsonDecode(await f.readAsString()));
      final all = base64Decode('${j['d']}');
      final box = SecretBox(all.sublist(0, all.length - 16), nonce: base64Decode('${j['n']}'), mac: Mac(all.sublist(all.length - 16)));
      return OfflineSitting.fromJson(asMap(jsonDecode(utf8.decode(await _aes.decrypt(box, secretKey: await _localKey())))));
    } catch (_) {
      return null;                                   // another install's key or a damaged file: ignored
    }
  }

  Future<List<OfflineSitting>> sittings() async {
    final out = <OfflineSitting>[];
    try {
      await for (final f in (await _root()).list()) {
        if (f is File && f.uri.pathSegments.last.startsWith('sit_')) {
          final s = await _readSitting(f);
          if (s != null) out.add(s);
        }
      }
    } catch (_) {}
    return out;
  }

  Future<OfflineSitting?> sitting(int examId, int studentId) async {
    final f = await _file('sit_${examId}_$studentId.bin');
    return await f.exists() ? _readSitting(f) : null;
  }

  // ── bundles carried for other students ──
  Future<void> hold(Map<String, dynamic> bundle) async =>
      (await _file('held_${'${bundle['bundle_id']}'.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '')}.json')).writeAsString(jsonEncode(bundle), flush: true);

  Future<List<Map<String, dynamic>>> held() async {
    final out = <Map<String, dynamic>>[];
    try {
      await for (final f in (await _root()).list()) {
        if (f is File && f.uri.pathSegments.last.startsWith('held_')) {
          try {
            out.add(asMap(jsonDecode(await f.readAsString())));
          } catch (_) {}
        }
      }
    } catch (_) {}
    return out;
  }

  Future<void> release(String bundleId) async {
    final f = await _file('held_${bundleId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '')}.json');
    if (await f.exists()) await f.delete();
  }
}

/// The signed-in user's id when the sealing key was never fetched (the cached user of the login).
Future<int?> cachedUserId() async {
  try {
    final raw = (await SharedPreferences.getInstance()).getString('current_user');
    if (raw == null) return null;
    final id = asMap(jsonDecode(raw))['id'];
    return id == null ? null : asInt(id);
  } catch (_) {
    return null;
  }
}

/// Who sits on this phone: the owner of the sealing key, else the cached login.
Future<int?> offlineStudentId() async => (await OfflineExamStore.instance.studentKey())?.userId ?? await cachedUserId();

class OfflineSendResult {
  const OfflineSendResult(this.sent, [this.code]);
  final bool sent;                                   // the server has it (verified receipt or a direct answer)
  final String? code;
}

class OfflineExamSync {
  OfflineExamSync._();
  static final OfflineExamSync instance = OfflineExamSync._();

  final api = OfflineExamApi();
  final store = OfflineExamStore.instance;
  bool _flushing = false;

  /// Online: the student's sealing key (same idea as the attendance key).
  Future<StudentSealKey?> warmKey() async {
    if (!offlineExamsSupported) return null;
    final r = await api.key();
    if (r.ok) await store.saveStudentKey(asInt(r.map['user_id']), '${r.map['key']}');
    return store.studentKey();
  }

  /// Online, from the student's exam list: keep the package — and its key once the exam opens — on the phone.
  Future<OfflinePackage?> warmExam(Map<String, dynamic> exam) async {
    if (!offlineExamsSupported || exam['offline'] != true) return null;
    final examId = asInt(exam['id']);
    final listed = asMap(exam['offline_package']);
    final have = await store.latestPackage(examId);
    final fresh = have != null && (listed['hash'] == null || listed['hash'] == have.hash);
    if (fresh && (await store.examKey(examId, have.n) != null || !have.openAt(DateTime.now()))) return have;
    final r = await api.package(examId);
    if (!r.ok) return have;
    return savePackageReply(r.map, from: 'server');
  }

  /// Stores the server's (or a teacher's) `{package, key}` reply; a key is kept only when it really opens the package.
  Future<OfflinePackage?> savePackageReply(Map<String, dynamic> reply, {required String from}) async {
    final p = OfflinePackage.fromJson(asMap(reply['package']));
    if (!p.intact) return null;
    p.json['_from'] = {'from': from};                // where it came from: a step of the delivery chain
    // the per-student wrap table: this phone passes it on at the start; only each entry's owner can open it
    if (reply['keys'] is Map) p.json['_wraps'] = Map<String, dynamic>.from(reply['keys'] as Map);
    final k = reply['key'];
    if (k is String && k.isNotEmpty && await saveKeyIfValid(p, base64Decode(k))) p.json['_key_from'] = {'from': from};
    await store.savePackage(p);
    return p;
  }

  Future<bool> saveKeyIfValid(OfflinePackage p, List<int> key) async {
    try {
      await openPackage(p, key);
    } catch (_) {
      return false;
    }
    await store.saveExamKey(p.examId, p.n, key);
    return true;
  }

  /// Send one finished sitting straight to the server.
  Future<OfflineSendResult> sendOwn(OfflineSitting s) async {
    final b = s.bundle;
    if (b == null) return const OfflineSendResult(false, 'not_finished');
    s.lastTry = DateTime.now();
    final r = await api.submit([b]);
    if (!r.ok) {
      await store.saveSitting(s);
      return OfflineSendResult(false, r.status == 0 ? 'network' : (r.code ?? 'server_${r.status}'));
    }
    final res = asMapList(r.map['results']).firstOrNull ?? const {};
    await applyResult(s, res, direct: true);
    return OfflineSendResult(s.stage == OfflineStage.submitted, s.code);
  }

  /// A server answer for this sitting, direct or through a relay. Through a relay only a receipt that verifies counts,
  /// and a refusal never ends the retries (a relay could invent one).
  Future<void> applyResult(OfflineSitting s, Map<String, dynamic> res, {required bool direct}) async {
    final status = '${res['status']}';
    if (status == 'accepted' || status == 'duplicate') {
      final key = await store.studentKey();
      final aid = asInt(res['attempt_id']);
      final sealed = s.bundle?['enc'] == 'k1' && key != null && key.userId == s.studentId;
      final ok = sealed
          ? verifyReceipt(studentKeyHex: key.key, bundleId: s.bundleId, attemptId: aid, receipt: '${res['receipt'] ?? ''}')
          : direct;
      if (ok) {
        s.stage = OfflineStage.submitted;
        s.attemptId = aid;
        s.code = null;
      } else {
        s.code = 'bad_receipt';
      }
    } else if (status == 'rejected' && direct) {
      s.stage = OfflineStage.rejected;
      s.code = '${res['code'] ?? 'rejected'}';
    } else {
      s.code = '${res['code'] ?? res['status'] ?? 'retry'}';
    }
    await store.saveSitting(s);
  }

  /// Re-sends every finished sitting and every bundle this phone carries for others. Returns how many reached the server.
  Future<int> flush() async {
    if (!offlineExamsSupported || _flushing) return 0;
    _flushing = true;
    var done = 0;
    try {
      for (final s in await store.sittings()) {
        if (s.stage != OfflineStage.waitingToSync) continue;
        final r = await sendOwn(s);
        if (r.code == 'network') return done;          // still offline: the rest waits as well
        if (r.sent) done++;
      }
      final held = await store.held();
      for (var i = 0; i < held.length; i += 50) {
        final batch = held.sublist(i, i + 50 > held.length ? held.length : i + 50);
        final r = await api.submit(batch);
        if (!r.ok) return done;
        for (final res in asMapList(r.map['results'])) {
          if (res['status'] == 'retry') continue;
          await store.release('${res['bundle_id']}');   // accepted, duplicate or a definite refusal: no longer ours to carry
          if (res['status'] != 'rejected') done++;
        }
      }
    } catch (e) {
      debugPrint('offline exams: flush failed: $e');
    } finally {
      _flushing = false;
    }
    return done;
  }

  bool _warmed = false;

  /// Once per app run when an exam list loads online: the sealing key, and whatever finished sitting still waits.
  Future<void> warmOnce() async {
    if (_warmed) return;
    _warmed = true;
    await onReconnect();
  }

  /// The phone just got its connection back.
  Future<void> onReconnect() async {
    if (!offlineExamsSupported) return;
    try {
      await warmKey();
      final n = await flush();
      if (n > 0) debugPrint('offline exams: settled $n bundle(s)');
    } catch (e) {
      debugPrint('offline exams reconnect sync failed: $e');
    }
  }
}
