// lib/features/org/advising/adv_message_store.dart — advising messages written without a connection (#23 "offline
// drafts for messages too", docs/advising/PHASE5.md), the conversations' twin of adv_draft_store.dart (notes):
//
//   • a DRAFT per (user, organization, thread) is kept on the device while the person types and comes back when the
//     thread opens again (also after the app was closed);
//   • a message SENT offline (or whose request failed for a network reason) is QUEUED with its `client_id` and posted
//     when the phone is back online: AdvDraftStore.onReconnect (TopRouteObserver's one connectivity listener) calls
//     [AdvMessageStore.onReconnect], and an open thread calls [flush]. The `client_id` makes the POST idempotent, so
//     a request that reached the server before the connection dropped is never written twice;
//   • a definite "no" from the server (e.g. the conversation was closed meanwhile) is kept with its reason and not
//     retried; the person moves it back into the composer or discards it.
//
// Storage: the same backend as the notes (the platform keystore on phones and desktops, SharedPreferences on the
// web), under its own keys. Tests give their own backend, poster, user and connectivity.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';

import '../../admin/admin_common.dart' show asBool, asInt, asMap, asMapList, asStr;
import 'adv_appt_models.dart';
import 'adv_comm_api.dart';
import 'adv_draft_store.dart' show AdvDeviceDraftBackend, AdvDraftBackend, AdvDraftStore, AdvSendState;
import 'adv_parts.dart' show advErrorText;

/// A message waiting to be posted.
class AdvQueuedMessage {
  const AdvQueuedMessage({required this.userId, required this.orgId, required this.threadId, required this.student, required this.draft, this.queuedAt, this.error, this.message});

  final int userId, orgId, threadId;

  /// Posted on the member base (the student's own routes).
  final bool student;

  /// Carries its `client_id`.
  final AdvMessageDraft draft;
  final DateTime? queuedAt;

  /// The code of a definite server "no" and its text; null while the message waits for a connection.
  final String? error, message;

  bool get failed => error != null;
  String get clientId => draft.clientId ?? '';

  factory AdvQueuedMessage.fromJson(Map<String, dynamic> j) => AdvQueuedMessage(
        userId: asInt(j['user_id']),
        orgId: asInt(j['org_id']),
        threadId: asInt(j['thread_id']),
        student: asBool(j['student']),
        draft: AdvMessageDraft.fromStore(asMap(j['draft'])),
        queuedAt: DateTime.tryParse(asStr(j['queued_at'])),
        error: j['error'] == null ? null : asStr(j['error']),
        message: j['message'] == null ? null : asStr(j['message']),
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'org_id': orgId,
        'thread_id': threadId,
        'student': student,
        'draft': draft.toStore(),
        'queued_at': queuedAt?.toUtc().toIso8601String(),
        'error': error,
        'message': message,
      };

  AdvQueuedMessage withDraft(AdvMessageDraft d) =>
      AdvQueuedMessage(userId: userId, orgId: orgId, threadId: threadId, student: student, draft: d, queuedAt: queuedAt, error: error, message: message);

  AdvQueuedMessage failedWith(String code, String text) =>
      AdvQueuedMessage(userId: userId, orgId: orgId, threadId: threadId, student: student, draft: draft, queuedAt: queuedAt, error: code, message: text);
}

class AdvMessageSendResult {
  const AdvMessageSendResult(this.state, {this.message, this.error});
  final AdvSendState state;

  /// The message the server made ([AdvSendState.sent]).
  final AdvMessage? message;

  /// Why the server refused it ([AdvSendState.failed]); the draft stays in the composer.
  final ApiException? error;
}

typedef AdvMessagePoster = Future<AdvMessage> Function(int orgId, int threadId, bool student, AdvMessageDraft draft);

class AdvMessageStore {
  AdvMessageStore({AdvDraftBackend? backend, AdvMessagePoster? poster, Future<int> Function()? userId, bool Function()? online})
      : _backend = backend ?? const AdvDeviceDraftBackend(),
        _poster = poster ?? ((org, thread, student, d) => AdvCommApi(org, student: student).post(thread, d)),
        _userId = userId ?? _savedUserId,
        _online = online ?? (() => AppConnectivity.instance.isOnline);

  static final AdvMessageStore instance = AdvMessageStore();

  static const kDrafts = 'adv_msg_drafts_v1';
  static const kQueue = 'adv_msg_queue_v1';

  final AdvDraftBackend _backend;
  final AdvMessagePoster _poster;
  final Future<int> Function() _userId;
  final bool Function() _online;

  /// Bumped after every change of a draft or of the queue.
  final ValueNotifier<int> changes = ValueNotifier(0);

  static Future<int> _savedUserId() async => asInt((await StorageService.getInstance()).savedUser?['id']);

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

  Future<List<AdvQueuedMessage>> _readQueue() async {
    final raw = await _backend.read(kQueue);
    if (raw == null || raw.isEmpty) return [];
    try {
      return [for (final m in asMapList(jsonDecode(raw))) AdvQueuedMessage.fromJson(m)];
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeDrafts(Map<String, dynamic> all) => _backend.write(kDrafts, all.isEmpty ? null : jsonEncode(all));

  Future<void> _writeQueue(List<AdvQueuedMessage> q) => _backend.write(kQueue, q.isEmpty ? null : jsonEncode([for (final x in q) x.toJson()]));

  void _changed() => changes.value++;

  static String _key(int uid, int orgId, int threadId) => '$uid:$orgId:$threadId';

  // ── drafts ─────────────────────────────────────────────────────────────────

  Future<AdvMessageDraft?> draft(int orgId, int threadId) async {
    final uid = await _userId();
    final j = (await _readDrafts())[_key(uid, orgId, threadId)];
    return j is Map ? AdvMessageDraft.fromStore(asMap(j)) : null;
  }

  /// Keeps [d] for this thread (an empty one removes the draft).
  Future<void> saveDraft(int orgId, int threadId, AdvMessageDraft d) async {
    final uid = await _userId();
    await _locked(() async {
      final all = await _readDrafts();
      final k = _key(uid, orgId, threadId);
      if (d.worthKeeping) {
        all[k] = d.toStore();
      } else {
        all.remove(k);
      }
      await _writeDrafts(all);
    });
  }

  Future<void> clearDraft(int orgId, int threadId) => saveDraft(orgId, threadId, const AdvMessageDraft());

  // ── queue ──────────────────────────────────────────────────────────────────

  /// This thread's messages waiting to be posted (or refused), oldest first.
  Future<List<AdvQueuedMessage>> queued(int orgId, int threadId) async {
    final uid = await _userId();
    return [for (final q in await _readQueue()) if (q.userId == uid && q.orgId == orgId && q.threadId == threadId) q];
  }

  Future<AdvMessage> _post(AdvQueuedMessage q, {required void Function(AdvMessageDraft fresh) onNewId}) async {
    try {
      return await _poster(q.orgId, q.threadId, q.student, q.draft);
    } catch (e) {
      if (ApiException.from(e).code != 'advising_client_id_conflict') rethrow;
      final fresh = q.draft.copyWith(clientId: () => AdvDraftStore.newClientId());
      onNewId(fresh);
      return _poster(q.orgId, q.threadId, q.student, fresh);
    }
  }

  static bool _shouldWait(ApiException e) => e.isRetryable || e.isUnauthorized || e.statusCode == 429;

  /// Posts [d] now when online; offline (or on a network failure) it is queued with its `client_id` and posted on
  /// reconnect. The draft is cleared unless the server refused the message.
  Future<AdvMessageSendResult> send(int orgId, int threadId, AdvMessageDraft d, {required bool student}) async {
    var draft = d.clientId == null ? d.copyWith(clientId: () => AdvDraftStore.newClientId()) : d;
    final uid = await _userId();
    var item = AdvQueuedMessage(userId: uid, orgId: orgId, threadId: threadId, student: student, draft: draft, queuedAt: DateTime.now().toUtc());
    if (_online()) {
      try {
        final made = await _post(item, onNewId: (fresh) => item = item.withDraft(fresh));
        await clearDraft(orgId, threadId);
        _changed();
        return AdvMessageSendResult(AdvSendState.sent, message: made);
      } catch (e) {
        final err = ApiException.from(e);
        if (!_shouldWait(err)) return AdvMessageSendResult(AdvSendState.failed, error: err);
      }
    }
    draft = item.draft;
    await _locked(() async {
      final q = await _readQueue();
      if (!q.any((x) => x.clientId == draft.clientId)) {
        q.add(item);
        await _writeQueue(q);
      }
    });
    await clearDraft(orgId, threadId);
    _changed();
    return const AdvMessageSendResult(AdvSendState.queued);
  }

  bool _flushing = false;

  /// Posts the signed-in user's waiting messages, oldest first; stops at the first one that must wait.
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
          await _post(q, onNewId: (fresh) => current = q.withDraft(fresh));
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

  Future<void> _update(String clientId, AdvQueuedMessage? next) => _locked(() async {
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

  Future<void> discard(AdvQueuedMessage q) async {
    await _update(q.clientId, null);
    _changed();
  }

  /// Takes a refused message back into the composer (the next send gets a new id).
  Future<AdvMessageDraft> reopen(AdvQueuedMessage q) async {
    final d = q.draft.copyWith(clientId: () => null);
    await _update(q.clientId, null);
    await saveDraft(q.orgId, q.threadId, d);
    _changed();
    return d;
  }

  /// The phone got its connection back.
  Future<void> onReconnect() async {
    try {
      final n = await flush();
      if (n > 0) debugPrint('advising: posted $n message(s) written offline');
    } catch (e) {
      debugPrint('advising messages reconnect sync failed: $e');
    }
  }
}
