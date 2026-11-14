// lib/features/org/advising/adv_draft_store.dart — advising notes written without a connection (#23,
// docs/advising/PHASE4.md "Notes"):
//
//   • a DRAFT per (user, organization, student) is kept on the device while the advisor types, and comes back when
//     the composer opens again (also after the app was closed);
//   • a note SENT offline (or whose request failed for a network reason) is QUEUED with its `client_id` and posted
//     when the phone is back online: TopRouteObserver calls [AdvDraftStore.onReconnect] next to the offline
//     attendance and exam syncs (the app's one connectivity listener), and the advising pages call [flush] when they
//     open. The `client_id` makes the POST idempotent, so a request that reached the server before the connection
//     dropped is never written twice;
//   • a definite "no" from the server (e.g. a sensitive note shown to the student) is kept with its reason and not
//     retried; the author moves it back into the composer or discards it.
//
// Storage: the platform keystore on phones and desktops (a note can be sensitive), SharedPreferences on the web (as
// token_storage.dart). Tests give their own [AdvDraftBackend], poster, user and connectivity.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../admin/admin_common.dart' show asInt, asMap, asMapList, asStr;
import 'adv_api.dart';
import 'adv_message_store.dart' show AdvMessageStore;
import 'adv_models.dart';
import 'adv_parts.dart' show advErrorText;

/// Where the store keeps its two JSON documents (the drafts, the queue).
abstract class AdvDraftBackend {
  Future<String?> read(String key);

  /// null removes the key.
  Future<void> write(String key, String? value);
}

/// The device: keystore on phones and desktops, SharedPreferences on the web.
class AdvDeviceDraftBackend implements AdvDraftBackend {
  const AdvDeviceDraftBackend();

  static const _secure = FlutterSecureStorage();

  @override
  Future<String?> read(String key) async {
    try {
      if (kIsWeb) return (await SharedPreferences.getInstance()).getString(key);
      return await _secure.read(key: key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String? value) async {
    try {
      if (kIsWeb) {
        final p = await SharedPreferences.getInstance();
        value == null ? await p.remove(key) : await p.setString(key, value);
        return;
      }
      value == null ? await _secure.delete(key: key) : await _secure.write(key: key, value: value);
    } catch (_) {
      // a locked keystore: the note stays in the composer, nothing is lost by failing here
    }
  }
}

/// A note waiting to be posted.
class AdvQueuedNote {
  const AdvQueuedNote({required this.userId, required this.orgId, required this.memberId, required this.draft, this.queuedAt, this.error, this.message});

  final int userId, orgId, memberId;

  /// Carries its `client_id`.
  final AdvNoteDraft draft;
  final DateTime? queuedAt;

  /// The code of a definite server "no" and its text; null while the note waits for a connection.
  final String? error, message;

  bool get failed => error != null;
  String get clientId => draft.clientId ?? '';

  factory AdvQueuedNote.fromJson(Map<String, dynamic> j) => AdvQueuedNote(
        userId: asInt(j['user_id']),
        orgId: asInt(j['org_id']),
        memberId: asInt(j['member_id']),
        draft: AdvNoteDraft.fromStore(asMap(j['draft'])),
        queuedAt: DateTime.tryParse(asStr(j['queued_at'])),
        error: j['error'] == null ? null : asStr(j['error']),
        message: j['message'] == null ? null : asStr(j['message']),
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'org_id': orgId,
        'member_id': memberId,
        'draft': draft.toStore(),
        'queued_at': queuedAt?.toUtc().toIso8601String(),
        'error': error,
        'message': message,
      };

  /// The same note under another `client_id`.
  AdvQueuedNote withDraft(AdvNoteDraft d) =>
      AdvQueuedNote(userId: userId, orgId: orgId, memberId: memberId, draft: d, queuedAt: queuedAt, error: error, message: message);

  AdvQueuedNote failedWith(String code, String text) =>
      AdvQueuedNote(userId: userId, orgId: orgId, memberId: memberId, draft: draft, queuedAt: queuedAt, error: code, message: text);
}

enum AdvSendState { sent, queued, failed }

class AdvSendResult {
  const AdvSendResult(this.state, {this.note, this.error});
  final AdvSendState state;

  /// The note the server made ([AdvSendState.sent]).
  final AdvNote? note;

  /// Why the server refused it ([AdvSendState.failed]); the draft stays in the composer.
  final ApiException? error;
}

typedef AdvNotePoster = Future<AdvNote> Function(int orgId, int memberId, AdvNoteDraft draft);

class AdvDraftStore {
  AdvDraftStore({AdvDraftBackend? backend, AdvNotePoster? poster, Future<int> Function()? userId, bool Function()? online})
      : _backend = backend ?? const AdvDeviceDraftBackend(),
        _poster = poster ?? ((org, member, d) => AdvApi(org).addNote(member, d)),
        _userId = userId ?? _savedUserId,
        _online = online ?? (() => AppConnectivity.instance.isOnline);

  static final AdvDraftStore instance = AdvDraftStore();

  static const kDrafts = 'adv_note_drafts_v1';
  static const kQueue = 'adv_note_queue_v1';

  final AdvDraftBackend _backend;
  final AdvNotePoster _poster;
  final Future<int> Function() _userId;
  final bool Function() _online;

  /// Bumped after every change of a draft or of the queue (an open composer re-reads its state).
  final ValueNotifier<int> changes = ValueNotifier(0);

  static Future<int> _savedUserId() async => asInt((await StorageService.getInstance()).savedUser?['id']);

  /// A fresh id for one note (≤ 40 characters, the server's limit).
  static String newClientId() {
    final r = Random.secure();
    final rand = List.generate(10, (_) => r.nextInt(36).toRadixString(36)).join();
    return 'n${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}$rand';
  }

  // ── one writer at a time: every change is read-modify-write of one document ──
  Future<void> _tail = Future.value();

  Future<T> _locked<T>(Future<T> Function() fn) {
    final done = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        done.complete(await fn());
      } catch (e, s) {
        done.completeError(e, s);
      }
    });
    return done.future;
  }

  Future<Map<String, dynamic>> _readDrafts() async {
    final raw = await _backend.read(kDrafts);
    if (raw == null || raw.isEmpty) return {};
    try {
      return asMap(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  Future<List<AdvQueuedNote>> _readQueue() async {
    final raw = await _backend.read(kQueue);
    if (raw == null || raw.isEmpty) return [];
    try {
      return [for (final m in asMapList(jsonDecode(raw))) AdvQueuedNote.fromJson(m)];
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeDrafts(Map<String, dynamic> all) => _backend.write(kDrafts, all.isEmpty ? null : jsonEncode(all));

  Future<void> _writeQueue(List<AdvQueuedNote> q) => _backend.write(kQueue, q.isEmpty ? null : jsonEncode([for (final x in q) x.toJson()]));

  void _changed() => changes.value++;

  static String _key(int uid, int orgId, int memberId) => '$uid:$orgId:$memberId';

  // ── drafts ─────────────────────────────────────────────────────────────────

  /// The draft kept for this student, null when there is none.
  Future<AdvNoteDraft?> draft(int orgId, int memberId) async {
    final uid = await _userId();
    final j = (await _readDrafts())[_key(uid, orgId, memberId)];
    return j is Map ? AdvNoteDraft.fromStore(asMap(j)) : null;
  }

  /// Keeps [d] for this student (an empty note removes the draft).
  Future<void> saveDraft(int orgId, int memberId, AdvNoteDraft d) async {
    final uid = await _userId();
    await _locked(() async {
      final all = await _readDrafts();
      final k = _key(uid, orgId, memberId);
      if (d.worthKeeping) {
        all[k] = d.toStore();
      } else {
        all.remove(k);
      }
      await _writeDrafts(all);
    });
  }

  Future<void> clearDraft(int orgId, int memberId) => saveDraft(orgId, memberId, const AdvNoteDraft());

  // ── queue ──────────────────────────────────────────────────────────────────

  /// This student's notes waiting to be posted (or refused), oldest first.
  Future<List<AdvQueuedNote>> queued(int orgId, int memberId) async {
    final uid = await _userId();
    return [for (final q in await _readQueue()) if (q.userId == uid && q.orgId == orgId && q.memberId == memberId) q];
  }

  /// Posts [d]. A `client_id` the server holds for another student (409 `advising_client_id_conflict`) is dropped for
  /// a fresh one ([onNewId] keeps the caller in step) and the same text is posted again, once.
  Future<AdvNote> _post(int orgId, int memberId, AdvNoteDraft d, {required void Function(AdvNoteDraft fresh) onNewId}) async {
    try {
      return await _poster(orgId, memberId, d);
    } catch (e) {
      if (ApiException.from(e).code != 'advising_client_id_conflict') rethrow;
      final fresh = d.copyWith(clientId: () => newClientId());
      onNewId(fresh);
      return _poster(orgId, memberId, fresh);
    }
  }

  /// A connection problem, a busy server or a sign-in to renew: the note waits; anything else is a definite "no".
  static bool _shouldWait(ApiException e) =>
      e.isRetryable || e.isUnauthorized || e.statusCode == 429;

  /// Posts [d] now when online; offline (or on a network failure) it is queued with its `client_id` and posted on
  /// reconnect. The draft is cleared unless the server refused the note.
  Future<AdvSendResult> send(int orgId, int memberId, AdvNoteDraft d) async {
    var note = d.clientId == null ? d.copyWith(clientId: () => newClientId()) : d;
    if (_online()) {
      try {
        final made = await _post(orgId, memberId, note, onNewId: (fresh) => note = fresh);
        await clearDraft(orgId, memberId);
        _changed();
        return AdvSendResult(AdvSendState.sent, note: made);
      } catch (e) {
        final err = ApiException.from(e);
        if (!_shouldWait(err)) return AdvSendResult(AdvSendState.failed, error: err);
      }
    }
    final uid = await _userId();
    await _locked(() async {
      final q = await _readQueue();
      if (!q.any((x) => x.clientId == note.clientId)) {
        q.add(AdvQueuedNote(userId: uid, orgId: orgId, memberId: memberId, draft: note, queuedAt: DateTime.now().toUtc()));
        await _writeQueue(q);
      }
    });
    await clearDraft(orgId, memberId);
    _changed();
    return const AdvSendResult(AdvSendState.queued);
  }

  bool _flushing = false;

  /// Posts the signed-in user's waiting notes, oldest first; stops at the first one that must wait (still offline).
  /// Returns how many were posted.
  Future<int> flush() async {
    if (_flushing || !_online()) return 0;
    _flushing = true;
    var sent = 0;
    try {
      final uid = await _userId();
      final waiting = [for (final q in await _readQueue()) if (q.userId == uid && !q.failed) q];
      for (final q in waiting) {
        var current = q;
        try {
          await _post(q.orgId, q.memberId, q.draft, onNewId: (fresh) => current = q.withDraft(fresh));
          await _update(q.clientId, null);
          sent++;
        } catch (e) {
          final err = ApiException.from(e);
          if (_shouldWait(err)) {
            if (current.clientId != q.clientId) await _update(q.clientId, current);
            break;
          }
          await _update(q.clientId, current.failedWith(err.code ?? 'http_${err.statusCode}', advErrorText(err)));
        }
      }
    } finally {
      _flushing = false;
    }
    if (sent > 0) _changed();
    return sent;
  }

  /// Replaces the queued note with [clientId] by [next] (null: removes it).
  Future<void> _update(String clientId, AdvQueuedNote? next) => _locked(() async {
        final q = await _readQueue();
        final i = q.indexWhere((x) => x.clientId == clientId);
        if (i < 0) return;
        if (next == null) {
          q.removeAt(i);
        } else {
          q[i] = next;
        }
        await _writeQueue(q);
        if (next != null) _changed();
      });

  /// Drops a queued note.
  Future<void> discard(AdvQueuedNote q) async {
    await _update(q.clientId, null);
    _changed();
  }

  /// Takes a refused note back into the composer (it replaces the draft; the next send gets a new id).
  Future<AdvNoteDraft> reopen(AdvQueuedNote q) async {
    final d = q.draft.copyWith(clientId: () => null);
    await _update(q.clientId, null);
    await saveDraft(q.orgId, q.memberId, d);
    _changed();
    return d;
  }

  /// The phone got its connection back (TopRouteObserver): the notes, then the messages (Phase 5).
  Future<void> onReconnect() async {
    unawaited(AdvMessageStore.instance.onReconnect());
    try {
      final n = await flush();
      if (n > 0) debugPrint('advising: posted $n note(s) written offline');
    } catch (e) {
      debugPrint('advising notes reconnect sync failed: $e');
    }
  }
}
