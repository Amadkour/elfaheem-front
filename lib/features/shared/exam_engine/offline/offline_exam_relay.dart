// Offline sittings over the attendance relay link (attendance/relay_transport.dart: Nearby Connections on Android —
// Bluetooth + Wi-Fi Direct, the fastest it finds — and Bluetooth LE for iPhones). GPS is never a channel.
//
// Same rule as attendance: the link is NOT trusted. A package must match its own hash (and the hash the server listed,
// when the phone saw the list), a key only counts when it opens the package, and a relayed "accepted" only counts with
// the server's receipt. Every message is base64 in parts (Nearby carries ≤ 32 KB, BLE frames far less).
//
//   client → host  {"t":"exam_hello","exam_id"?}               host → {"t":"exam_offer","items":[header + has_key],"by","role"}
//   client → host  {"t":"exam_part","exam_id","n","i"}          host → {"t":"exam_chunk","i","of","data"}
//   client → host  {"t":"exam_key","exam_id","n"}               host → {"t":"exam_keyed","key"} | error not_started / no_key / exam_ended
//   client → host  {"t":"exam_submit","id","i","of","data"}     host → {"t":"exam_ack"} … last part → {"t":"exam_receipt", …}
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../admin/admin_common.dart' show asInt, asMap, asMapList;
import '../../attendance/attendance_permissions.dart';
import '../../attendance/relay_transport.dart';
import 'offline_exam_core.dart';
import 'offline_exam_service.dart';

String _pack(Map<String, dynamic> m) => base64Encode(utf8.encode(jsonEncode(m)));
Map<String, dynamic> _unpack(String s) => asMap(jsonDecode(utf8.decode(base64Decode(s))));

Map<String, dynamic> _error(String code) => {'t': 'error', 'code': code, 'message': code};

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

  Future<RelayLink> _connect() async {
    final perm = await ensureNearbyPermissions(advertise: false);
    if (perm != PermissionOutcome.granted) throw const RelayException(RelayFailure.bluetoothOff, 'permission');
    return _relay.connect(nickname: 'exam');
  }

  /// The exam (and its key, when that phone has it and the exam has started) from the nearest phone that has it.
  Future<NearbyExam> fetch({int? examId, String? expectedHash, void Function(double done)? progress}) async {
    try {
      final link = await _connect();
      final offer = await link.request({'t': 'exam_hello', 'exam_id': ?examId});
      if (offer['t'] == 'error') return NearbyExam(code: '${offer['code']}');
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
          final r = await link.request({'t': 'exam_part', 'exam_id': head.examId, 'n': head.n, 'i': i});
          if (r['t'] != 'exam_chunk') return NearbyExam(code: '${r['code'] ?? 'bad_package'}');
          of = asInt(r['of']).clamp(1, 400);
          parts.add('${r['data']}');
          progress?.call((i + 1) / of);
        }
        try {
          pkg = OfflinePackage.fromJson(_unpack(parts.join()));
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
        final r = await link.request({'t': 'exam_key', 'exam_id': pkg.examId, 'n': pkg.n});
        if (r['t'] == 'exam_keyed') {
          keyed = await OfflineExamSync.instance.saveKeyIfValid(pkg, base64Decode('${r['key']}'));
          if (!keyed) code = 'bad_key';
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

  /// Sends a sealed bundle through a nearby phone; returns that phone's `exam_receipt` (or an error map).
  Future<Map<String, dynamic>> submit(Map<String, dynamic> bundle) async {
    try {
      final link = await _connect();
      final parts = splitParts(_pack(bundle));
      Map<String, dynamic> r = const {};
      for (var i = 0; i < parts.length; i++) {
        r = await link.request({'t': 'exam_submit', 'id': bundle['bundle_id'], 'i': i, 'of': parts.length, 'data': parts[i]},
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

  /// The teacher's phone: hands out the key at the start by its own clock and collects answers for upload.
  bool teacher = false;

  /// Bundles received from nearby phones since the app started (the teacher's "collected" counter).
  final received = ValueNotifier<int>(0);

  final Map<String, List<String>> _parts = {};         // "<exam>.<n>" → the package in parts
  final Map<String, List<String?>> _incoming = {};      // bundle id → parts received

  Future<int?> _me() async => (await _store.studentKey())?.userId ?? await cachedUserId();

  Future<Map<String, dynamic>> handle(Map<String, dynamic> req) async {
    try {
      switch (req['t']) {
        case 'exam_hello':
          final want = req['exam_id'] == null ? null : asInt(req['exam_id']);
          final now = DateTime.now();
          final items = <Map<String, dynamic>>[];
          for (final p in await _store.packages()) {
            if (want != null && p.examId != want) continue;
            if (p.endsAt != null && !now.isBefore(p.endsAt!)) continue;
            final head = Map<String, dynamic>.from(p.json)..remove('data')..remove('nonce');
            items.add({...head, 'has_key': await _store.examKey(p.examId, p.n) != null && p.openAt(now)});
          }
          return {'t': 'exam_offer', 'items': items, 'by': await _me(), 'role': teacher ? 'teacher' : 'student'};
        case 'exam_part':
          final examId = asInt(req['exam_id']), n = asInt(req['n']), i = asInt(req['i']);
          final parts = _parts['$examId.$n'] ??= await () async {
            final p = await _store.package(examId, n);
            return p == null ? const <String>[] : splitParts(_pack(p.json));
          }();
          if (parts.isEmpty) {
            _parts.remove('$examId.$n');
            return _error('no_package');
          }
          if (i < 0 || i >= parts.length) return _error('bad_package');
          return {'t': 'exam_chunk', 'i': i, 'of': parts.length, 'data': parts[i]};
        case 'exam_key':
          final p = await _store.package(asInt(req['exam_id']), asInt(req['n']));
          final key = p == null ? null : await _store.examKey(p.examId, p.n);
          if (p == null || key == null) return _error('no_key');
          final now = DateTime.now();
          if (p.startsAt != null && now.isBefore(p.startsAt!)) return _error('not_started');
          if (p.endsAt != null && !now.isBefore(p.endsAt!)) return _error('exam_ended');
          return {'t': 'exam_keyed', 'key': base64Encode(key)};
        case 'exam_submit':
          return await _receive(req);
      }
      return _error('bad_message');
    } catch (e) {
      debugPrint('offline exam host failed: $e');
      return _error('relay_failed');
    }
  }

  Future<Map<String, dynamic>> _receive(Map<String, dynamic> req) async {
    final id = '${req['id'] ?? ''}';
    final of = asInt(req['of']), i = asInt(req['i']);
    if (id.isEmpty || of < 1 || of > 200 || i < 0 || i >= of) return _error('bad_message');
    if (_incoming.length > 50 && !_incoming.containsKey(id)) _incoming.remove(_incoming.keys.first);
    final buf = _incoming.putIfAbsent(id, () => List<String?>.filled(of, null));
    if (buf.length != of) return _error('bad_message');
    buf[i] = '${req['data'] ?? ''}';
    if (buf.any((p) => p == null)) return {'t': 'exam_ack', 'i': i};
    _incoming.remove(id);
    final Map<String, dynamic> bundle;
    try {
      bundle = _unpack(buf.join());
    } catch (_) {
      return _error('bad_message');
    }
    if ('${bundle['bundle_id']}' != id) return _error('bad_message');
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
