// Offline sittings over the attendance relay link (attendance/relay_transport.dart: Nearby Connections on Android —
// Bluetooth + Wi-Fi Direct, the fastest it finds — and Bluetooth LE for iPhones). GPS is never a channel.
//
// Nothing readable crosses the air:
//   • every exam message is encrypted for this link ([ExamLink]: X25519 between fresh keys, HKDF, AES-GCM); each
//     request carries the client's public key, the host's comes back in the offer;
//   • the exam itself is the server's ciphertext, and the answers are sealed with the student's own key;
//   • the exam key travels as the server's per-student wrap table — only each entry's owner can open it — and only for
//     an exam without a course roster as the bare key, inside the encrypted link.
// The link is still not trusted: a package must match its hash (and the hash the server listed, when known), a key
// only counts when it opens the package, and a relayed "accepted" only counts with the server's receipt.
//
//   client → host  {"t":"exam_hello","pub","exam_id"?}             host → {"t":"exam_offer","pub","box"→{items,by,role}}
//   client → host  {"t":"exam_part","pub","exam_id","n","i"}        host → {"t":"exam_chunk","i","of","box"}
//   client → host  {"t":"exam_key","pub","exam_id","n"}             host → {"t":"exam_keyed","box"→{wraps}|{key}} | error
//   client → host  {"t":"exam_submit","pub","id","i","of","box"}    host → {"t":"exam_ack"} … last part → {"t":"exam_receipt", …}
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../admin/admin_common.dart' show asInt, asMap, asMapList;
import '../../attendance/attendance_permissions.dart';
import '../../attendance/relay_transport.dart';
import 'offline_exam_core.dart';
import 'offline_exam_service.dart';

Map<String, dynamic> _error(String code) => {'t': 'error', 'code': code, 'message': code};

/// The package as it travels: the server's fields only (never this phone's notes or the wrap table).
Map<String, dynamic> _public(Map<String, dynamic> pkg) => {for (final e in pkg.entries) if (!e.key.startsWith('_')) e.key: e.value};

class NearbyExam {
  const NearbyExam({this.package, this.keyed = false, this.by, this.role, this.code});
  final OfflinePackage? package;
  final bool keyed;
  final int? by;
  final String? role;
  final String? code;
}

String relayFailureCode(RelayException e) => switch (e.kind) {
      RelayFailure.bluetoothOff => 'bluetooth_off',
      RelayFailure.noRelay => 'no_relay',
      _ => 'no_relay',
    };

class OfflineExamRelayClient {
  final _relay = RelayClient();
  final _store = OfflineExamStore.instance;

  Future<(RelayLink, ExamLink, String, Map<String, dynamic>)> _open({int? examId}) async {
    final perm = await ensureNearbyPermissions(advertise: false);
    if (perm != PermissionOutcome.granted) throw const RelayException(RelayFailure.bluetoothOff, 'permission');
    final link = await _relay.connect(nickname: 'exam');
    final me = await ExamLink.create();
    final offer = await link.request({'t': 'exam_hello', 'pub': me.pub, 'exam_id': ?examId});
    if (offer['t'] != 'exam_offer' || offer['pub'] is! String) return (link, me, '', offer);
    final hostPub = offer['pub'] as String;
    return (link, me, hostPub, asMap(jsonDecode(await me.open(hostPub, '${offer['box']}'))));
  }

  /// The exam (and its key, once the exam has started) from the nearest phone that has it.
  Future<NearbyExam> fetch({int? examId, String? expectedHash, void Function(double done)? progress}) async {
    try {
      final (link, me, hostPub, offer) = await _open(examId: examId);
      if (hostPub.isEmpty) return NearbyExam(code: '${offer['code'] ?? 'no_package'}');
      final items = asMapList(offer['items']).where((i) => examId == null || asInt(i['exam_id']) == examId).toList();
      if (items.isEmpty) return const NearbyExam(code: 'no_package');
      final head = OfflinePackage.fromJson(items.first);
      final by = offer['by'] == null ? null : asInt(offer['by']);
      final role = '${offer['role'] ?? 'student'}';

      var pkg = await _store.package(head.examId, head.n);
      if (pkg == null || pkg.hash != head.hash) {
        final parts = <String>[];
        var of = 1;
        for (var i = 0; i < of; i++) {
          final r = await link.request({'t': 'exam_part', 'pub': me.pub, 'exam_id': head.examId, 'n': head.n, 'i': i});
          if (r['t'] != 'exam_chunk') return NearbyExam(code: '${r['code'] ?? 'bad_package'}');
          of = asInt(r['of']).clamp(1, 400);
          parts.add('${r['box']}');
          progress?.call((i + 1) / of);
        }
        try {
          pkg = OfflinePackage.fromJson(asMap(jsonDecode(await openParts(me, hostPub, parts))));
        } catch (_) {
          return const NearbyExam(code: 'bad_package');
        }
        if (!pkg.intact || pkg.hash != head.hash || (expectedHash != null && expectedHash.isNotEmpty && pkg.hash != expectedHash)) {
          return const NearbyExam(code: 'bad_package');
        }
        await _store.savePackage(pkg);
      }

      var keyed = await _store.examKey(pkg.examId, pkg.n) != null;
      String? code;
      if (!keyed && items.first['has_key'] == true) {
        final r = await link.request({'t': 'exam_key', 'pub': me.pub, 'exam_id': pkg.examId, 'n': pkg.n});
        if (r['t'] == 'exam_keyed') {
          final got = asMap(jsonDecode(await me.open(hostPub, '${r['box']}')));
          keyed = await _takeKey(pkg, got);
          if (!keyed) code = 'no_key';
        } else {
          code = '${r['code'] ?? 'no_key'}';
        }
      } else if (!keyed) {
        code = 'no_key';
      }
      return NearbyExam(package: pkg, keyed: keyed, by: by, role: role, code: code);
    } on RelayException catch (e) {
      return NearbyExam(code: relayFailureCode(e));
    } catch (e) {
      debugPrint('offline exam fetch failed: $e');
      return const NearbyExam(code: 'no_relay');
    } finally {
      await _relay.stop();
    }
  }

  /// The wrap table: this student's own entry opens with their own key; the table is kept to pass on. A bare key
  /// (an exam without a course roster) came inside the encrypted link. Either counts only when it opens the package.
  Future<bool> _takeKey(OfflinePackage pkg, Map<String, dynamic> got) async {
    final sync = OfflineExamSync.instance;
    if (got['wraps'] is Map) {
      final wraps = Map<String, dynamic>.from(got['wraps'] as Map);
      final me = await _store.studentKey();
      final mine = me == null ? null : wraps['${me.userId}'];
      final key = mine is String
          ? await openWrap(wrap: mine, examId: pkg.examId, n: pkg.n, studentId: me!.userId, studentKeyHex: me.key)
          : null;
      if (key == null || !await sync.saveKeyIfValid(pkg, key)) return false;
      pkg.json['_wraps'] = wraps;
      await _store.savePackage(pkg);
      return true;
    }
    final k = got['key'];
    return k is String && await sync.saveKeyIfValid(pkg, base64Decode(k));
  }

  /// Sends a sealed bundle through a nearby phone; returns that phone's `exam_receipt` (or an error map). Unsealed
  /// answers never go over the air: they wait for a connection or the answers file.
  Future<Map<String, dynamic>> submit(Map<String, dynamic> bundle) async {
    if (bundle['enc'] != 'k1') return _error('seal_required');
    try {
      final (link, me, hostPub, offer) = await _open();
      if (hostPub.isEmpty) return offer['t'] == 'error' ? offer : _error('no_relay');
      final parts = splitParts(await me.seal(hostPub, jsonEncode(bundle)));
      Map<String, dynamic> r = const {};
      for (var i = 0; i < parts.length; i++) {
        r = await link.request({'t': 'exam_submit', 'pub': me.pub, 'id': bundle['bundle_id'], 'i': i, 'of': parts.length, 'box': parts[i]},
            timeout: Duration(seconds: i == parts.length - 1 ? 40 : 25));
        if (r['t'] == 'error') return r;
      }
      return r;
    } on RelayException catch (e) {
      return _error(relayFailureCode(e));
    } catch (e) {
      debugPrint('offline exam relay submit failed: $e');
      return _error('no_relay');
    } finally {
      await _relay.stop();
    }
  }
}

/// What this phone answers while it is visible to classmates (RelayHostProvider forwards every `exam_*` request here).
class OfflineExamHost {
  OfflineExamHost._();
  static final OfflineExamHost instance = OfflineExamHost._();

  final _store = OfflineExamStore.instance;
  final _sync = OfflineExamSync.instance;
  Future<ExamLink>? _link;                            // this phone's link key for the app run

  /// The teacher's phone: hands out the key at the start by its own clock and collects answers for upload.
  bool teacher = false;

  /// Bundles received from nearby phones since the app started (the teacher's "collected" counter).
  final received = ValueNotifier<int>(0);

  final Map<String, List<String>> _parts = {};         // "<exam>.<n>|<client>" → the package, encrypted for that client
  final Map<String, List<String?>> _incoming = {};      // bundle id → encrypted parts received

  Future<int?> _me() => offlineStudentId();

  Future<Map<String, dynamic>> handle(Map<String, dynamic> req) async {
    try {
      final pub = req['pub'];
      if (pub is! String || pub.isEmpty) return _error('bad_message');     // every exam message is encrypted
      final link = await (_link ??= ExamLink.create());
      switch (req['t']) {
        case 'exam_hello':
          final want = req['exam_id'] == null ? null : asInt(req['exam_id']);
          final now = DateTime.now();
          final items = <Map<String, dynamic>>[];
          for (final p in await _store.packages()) {
            if (want != null && p.examId != want) continue;
            if (p.endsAt != null && !now.isBefore(p.endsAt!)) continue;
            final head = _public(p.json)..remove('data')..remove('nonce');
            items.add({...head, 'has_key': p.openAt(now) && (p.json['_wraps'] is Map || await _store.examKey(p.examId, p.n) != null)});
          }
          final body = jsonEncode({'items': items, 'by': await _me(), 'role': teacher ? 'teacher' : 'student'});
          return {'t': 'exam_offer', 'pub': link.pub, 'box': await link.seal(pub, body)};
        case 'exam_part':
          final examId = asInt(req['exam_id']), n = asInt(req['n']), i = asInt(req['i']);
          final cacheKey = '$examId.$n|$pub';
          if (_parts.length > 20 && !_parts.containsKey(cacheKey)) _parts.remove(_parts.keys.first);
          final parts = _parts[cacheKey] ??= await () async {
            final p = await _store.package(examId, n);
            return p == null ? const <String>[] : splitParts(await link.seal(pub, jsonEncode(_public(p.json))));
          }();
          if (parts.isEmpty) {
            _parts.remove(cacheKey);
            return _error('no_package');
          }
          if (i < 0 || i >= parts.length) return _error('bad_package');
          return {'t': 'exam_chunk', 'i': i, 'of': parts.length, 'box': parts[i]};
        case 'exam_key':
          final p = await _store.package(asInt(req['exam_id']), asInt(req['n']));
          if (p == null) return _error('no_key');
          final now = DateTime.now();
          if (p.startsAt != null && now.isBefore(p.startsAt!)) return _error('not_started');
          if (p.endsAt != null && !now.isBefore(p.endsAt!)) return _error('exam_ended');
          if (p.json['_wraps'] is Map) {
            // never the bare key: the table, where each student opens only their own entry
            return {'t': 'exam_keyed', 'box': await link.seal(pub, jsonEncode({'wraps': p.json['_wraps']}))};
          }
          final key = await _store.examKey(p.examId, p.n);
          if (key == null) return _error('no_key');
          return {'t': 'exam_keyed', 'box': await link.seal(pub, jsonEncode({'key': base64Encode(key)}))};
        case 'exam_submit':
          return await _receive(req, link, pub);
      }
      return _error('bad_message');
    } catch (e) {
      debugPrint('offline exam host failed: $e');
      return _error('relay_failed');
    }
  }

  Future<Map<String, dynamic>> _receive(Map<String, dynamic> req, ExamLink link, String pub) async {
    final id = '${req['id'] ?? ''}';
    final of = asInt(req['of']), i = asInt(req['i']);
    if (id.isEmpty || of < 1 || of > 200 || i < 0 || i >= of) return _error('bad_message');
    if (_incoming.length > 50 && !_incoming.containsKey(id)) _incoming.remove(_incoming.keys.first);
    final buf = _incoming.putIfAbsent(id, () => List<String?>.filled(of, null));
    if (buf.length != of) return _error('bad_message');
    buf[i] = '${req['box'] ?? ''}';
    if (buf.any((p) => p == null)) return {'t': 'exam_ack', 'i': i};
    _incoming.remove(id);
    final Map<String, dynamic> bundle;
    try {
      bundle = asMap(jsonDecode(await openParts(link, pub, buf.cast<String>())));
    } catch (_) {
      return _error('bad_message');
    }
    if ('${bundle['bundle_id']}' != id || bundle['enc'] != 'k1') return _error('seal_required');
    bundle['hops'] = [
      ...asMapList(bundle['hops']).take(10),
      {'step': 'relayed', 'by': await _me(), 'via': teacher ? 'teacher' : 'classmate', 'at': DateTime.now().toUtc().toIso8601String()},
    ];
    received.value++;
    final r = await _sync.api.submit([bundle]);
    final res = r.ok ? (asMapList(r.map['results']).firstOrNull ?? const {}) : const <String, dynamic>{};
    if (!r.ok || res['status'] == 'retry') {
      await _store.hold(bundle);                      // this phone is offline too: it carries the answers until it is online
      return {'t': 'exam_receipt', 'status': 'held', 'code': 'held'};
    }
    return {'t': 'exam_receipt', ...res};
  }
}
