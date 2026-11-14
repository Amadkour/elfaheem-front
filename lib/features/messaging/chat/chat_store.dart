// lib/features/messaging/chat/chat_store.dart — Alfaheem Messages (D-330, D-375): the one state behind every chat screen.
//
//   ChatHub.instance        the chat list, the real-time events (chat_* on LiveEvents), delivered acks, drafts, the outbox,
//                           and ONE ChatThreadController per conversation (`acquire` / `release`, reference counted)
//   ChatThreadController    one chat: its messages, the composer's state, typing, sending, retry
//
// Real time: `start()` (topRouteObserver, on every route) subscribes LiveEvents once. A `chat_message` event carries the
// message itself, so an open chat needs no fetch; `EventOrPoll` keeps a slow poll only for when the stream is down. Events
// can be replayed (a fresh stream replays the last ten minutes, D-375), so every counter here is idempotent by message id.
// Sending: a message gets a client id and shows at once. One message of a chat is in flight at a time, oldest first, so the
// server's order is the order typed. While offline it waits in the persisted outbox and goes out on reconnect; a resend with
// the same client id is one message on the server. Nothing typed is ever dropped: what the server refused stays on screen
// as failed (tap to retry, or delete) and survives closing the app. Files of a message are uploaded once.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/core/live/live_events_client.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/utils/live_events.dart';

import 'package:flutter_education_app/features/messaging/chat/chat_api.dart';
import 'package:flutter_education_app/features/messaging/chat/chat_models.dart';

/// Pure: a page merged into the messages shown, newest first, no duplicates (a pending message is replaced by its stored self).
List<ChatMessage> chatMergeMessages(List<ChatMessage> shown, List<ChatMessage> incoming) {
  final byClient = <String, ChatMessage>{for (final m in shown) m.clientId: m};
  for (final m in incoming) {
    final mine = byClient[m.clientId];
    if (mine != null && mine.sendState != ChatSendState.sent && mine.id == null) {
      mine
        ..id = m.id
        ..kind = m.kind
        ..body = m.body
        ..attachments = m.attachments
        ..replyTo = m.replyTo ?? mine.replyTo
        ..local = const []
        ..uploaded = const []
        ..createdAt = m.createdAt
        ..error = null
        ..sendState = ChatSendState.sent;
    } else if (mine == null || mine.id == null) {
      byClient[m.clientId] = m;
    }
  }
  final out = byClient.values.toList()
    ..sort((a, b) {
      // sent messages by id; the ones still going out stay on top
      if ((a.id == null) != (b.id == null)) return a.id == null ? -1 : 1;
      if (a.id != null) return b.id!.compareTo(a.id!);
      return b.createdAt.compareTo(a.createdAt);
    });
  return out;
}

/// Pure: the status a sent message draws from the other side's marks.
ChatTick chatTickFor(ChatMessage m, {int? peerReadId, int? peerDeliveredId}) {
  if (m.sendState == ChatSendState.sending) return ChatTick.sending;
  if (m.sendState == ChatSendState.queued) return ChatTick.queued;
  if (m.sendState == ChatSendState.failed) return ChatTick.failed;
  final id = m.id ?? 0;
  if (peerReadId != null && peerReadId >= id) return ChatTick.read;
  if (peerDeliveredId != null && peerDeliveredId >= id) return ChatTick.delivered;
  return ChatTick.sent;
}

enum ChatTick { sending, queued, failed, sent, delivered, read }

class ChatHub extends ChangeNotifier {
  ChatHub._();
  static final ChatHub instance = ChatHub._();

  /// A hub of its own, for tests (the app has the one [instance]).
  @visibleForTesting
  factory ChatHub.forTest() = ChatHub._;

  ChatApi api = ChatApi();
  SharedPreferences? _prefs;
  int? _myId;
  bool _started = false;
  StreamSubscription<LiveEvent>? _sub;
  bool _streamWasUp = false;

  /// Every conversation's one controller, least recently used first.
  final LinkedHashMap<int, ChatThreadController> _threads = LinkedHashMap();

  /// Threads kept (and kept current) after their screen closed, so reopening one paints at once.
  static const _keepIdle = 8;

  final List<ChatConversation> conversations = [];
  bool loading = false, hasMore = false;
  bool _loadingMore = false;
  int _loadSeq = 0;
  String? error;
  int? selectedId;

  // the list's current filters
  String filter = 'all';
  int? courseId;
  String? role;
  String search = '';
  List<ChatCourse> filterCourses = const [];
  List<String> filterRoles = const [];
  final Map<int, String> typing = {};

  // message requests waiting on me (D-370): the count from the list, the rows when the section is opened
  int requestCount = 0;
  List<ChatConversation> requests = const [];
  bool requestsLoading = false;

  /// Message ids already counted since the list was last loaded (a replayed event must not count twice).
  final LinkedHashSet<int> _counted = LinkedHashSet();
  void _noteCounted(int id) {
    _counted.add(id);
    if (_counted.length > 500) _counted.remove(_counted.first);
  }

  int get myId => _myId ?? 0;

  bool get plainList => filter == 'all' && search.isEmpty && role == null && courseId == null;

  @visibleForTesting
  void debugSetMyId(int? id) => _myId = id;

  Future<void> ensureUser() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString('current_user');
    int? id;
    if (raw != null) {
      try {
        id = (jsonDecode(raw) as Map)['id'] as int?;
      } catch (_) {}
    }
    if (id != _myId) {
      // another account on this device: nothing of the last one may stay, least of all its outbox
      _forgetAccount();
      _myId = id;
      _loadDrafts();
      _loadOutbox();
      notifyListeners();
    }
  }

  void _forgetAccount() {
    for (final t in _threads.values.toList()) {
      t.dispose();
    }
    _threads.clear();
    conversations.clear();
    requests = const [];
    requestCount = 0;
    hasMore = false;
    error = null;
    typing.clear();
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    _typingTimers.clear();
    _deliveredTimer?.cancel();
    _deliveredTimer = null;
    _pendingDelivered.clear();
    selectedId = null;
    drafts.clear();
    _outbox.clear();
    _counted.clear();
    _loadSeq++; // an answer still in flight belongs to the old account
  }

  /// Signing out: what was typed and not sent is plain text on this device, so it goes with the session.
  Future<void> signedOut() async {
    _forgetAccount();
    _myId = null;
    notifyListeners();
    try {
      final p = _prefs ??= await SharedPreferences.getInstance();
      for (final k in p.getKeys().where((k) => k.startsWith('chat_outbox_') || k.startsWith('chat_drafts_')).toList()) {
        await p.remove(k);
      }
    } catch (_) {
      // nothing else to do: the keys stay until the next sign-out
    }
  }

  /// Once per app run (topRouteObserver calls it on every route; after a sign-in it follows the new account).
  void start() {
    if (_started) {
      ensureUser();
      return;
    }
    _started = true;
    _sub = LiveEvents.instance.listen(
      {LiveEvents.chatMessage, LiveEvents.chatReceipt, LiveEvents.chatTyping, LiveEvents.chatPresence, LiveEvents.chatConversation, LiveEvents.connectivity},
      _onEvent,
    );
    _streamWasUp = LiveEventsClient.instance.connected.value;
    LiveEventsClient.instance.connected.addListener(_onStream);
    ensureUser().then((_) => flushOutbox());
  }

  void stopForTest() {
    _sub?.cancel();
    _sub = null;
    _started = false;
    LiveEventsClient.instance.connected.removeListener(_onStream);
  }

  /// The stream came back (a redeploy, the token's end, a tunnel): what is older than its replay window is fetched.
  void _onStream() {
    final up = LiveEventsClient.instance.connected.value;
    if (up && !_streamWasUp) _onBackOnline();
    _streamWasUp = up;
  }

  void _onEvent(LiveEvent e) {
    switch (e.type) {
      case LiveEvents.chatMessage:
        onMessageEvent(e.data);
      case LiveEvents.chatReceipt:
        _onReceipt(e.data);
      case LiveEvents.chatTyping:
        _onTyping(e.data);
      case LiveEvents.chatPresence:
        _onPresence(e.data);
      case LiveEvents.chatConversation:
        _onConversation(e.data);
      case LiveEvents.connectivity:
        if (AppConnectivity.instance.isOnline) _onBackOnline();
    }
  }

  /// Back online: send what waited, and catch up on anything older than the stream's replay window.
  void _onBackOnline() {
    flushOutbox();
    for (final t in _threads.values) {
      if (t.visible) t.catchUp();
    }
    if (conversations.isNotEmpty) load(silent: true);
  }

  @visibleForTesting
  void onMessageEvent(Map<String, dynamic> d) => _onMessage(d);

  /// The server took my message: the list row says so now. Its echo on the stream is late or lost when the stream
  /// is still reconnecting (the moment a queued message goes out); arriving later it changes nothing.
  void noteSent(int conv, ChatMessage msg) {
    final row = conversations.where((c) => c.id == conv).firstOrNull;
    final id = msg.id;
    if (row == null || id == null || (row.last != null && id < row.last!.id)) return;
    row
      ..last = ChatLastMessage(id: id, kind: msg.kind, body: msg.body ?? '', senderId: msg.senderId, senderName: msg.senderName, createdAt: msg.createdAt)
      ..lastAt = msg.createdAt;
    _sortRows();
    notifyListeners();
  }

  void _onMessage(Map<String, dynamic> d) {
    final raw = d['message'];
    final conv = int.tryParse('${d['conversation_id'] ?? ''}');
    if (raw is! Map || conv == null) return;
    final msg = ChatMessage.fromJson(Map<String, dynamic>.from(raw));
    final isGroup = '${d['kind'] ?? ''}' == 'course_group';
    final mine = msg.senderId == myId;
    final thread = _threads[conv];
    thread?.onIncoming(msg);
    if (!mine && typing.remove(conv) != null) {
      // the message is what the dots were announcing
      _typingTimers.remove(conv)?.cancel();
      thread?.onTyping(null);
    }
    final reading = thread?.reading ?? false;
    final row = conversations.where((c) => c.id == conv).firstOrNull;
    final id = msg.id ?? 0;
    // new to this device: newer than what the list already counted, and not seen in this run (a replay is both)
    final fresh = id > (row?.loadedLastId ?? 0) && !_counted.contains(id);
    if (fresh) _noteCounted(id);
    if (row == null) {
      if (plainList) load(silent: true);
    } else {
      if (row.last == null || id >= row.last!.id) {
        row
          ..last = ChatLastMessage(id: id, kind: msg.kind, body: msg.body ?? '', senderId: msg.senderId, senderName: msg.senderName, createdAt: msg.createdAt)
          ..lastAt = msg.createdAt;
      }
      if (!mine && !reading && fresh) row.unread += 1;
      _sortRows();
      notifyListeners();
    }
    if (!mine && fresh) {
      if (!reading) _queueDelivered(conv, msg.id);
      if (isGroup && !reading) {
        // a group sends no attention_changed (hundreds of re-reads per message): the badge is counted here
        if (!(row?.muted ?? false)) AttentionService.instance.bumpLocal(AttentionTabs.chat, 1);
      }
    }
  }

  final Map<int, int> _pendingDelivered = {};
  Timer? _deliveredTimer;

  void _queueDelivered(int conv, int? id) {
    if (id == null) return;
    final was = _pendingDelivered[conv];
    if (was == null || id > was) _pendingDelivered[conv] = id;
    _deliveredTimer ??= Timer(const Duration(milliseconds: 600), () {
      _deliveredTimer = null;
      final items = [for (final e in _pendingDelivered.entries) {'conversation_id': e.key, 'message_id': e.value}];
      _pendingDelivered.clear();
      if (items.isNotEmpty) api.delivered(items).catchError((_) {});
    });
  }

  static int? _maxOf(int? a, int? b) => a == null ? b : (b == null || a >= b ? a : b);

  void _onReceipt(Map<String, dynamic> d) {
    final conv = int.tryParse('${d['conversation_id'] ?? ''}');
    if (conv == null) return;
    final read = int.tryParse('${d['read_id'] ?? ''}');
    final delivered = int.tryParse('${d['delivered_id'] ?? ''}');
    _threads[conv]?.onReceipt(read: read, delivered: delivered);
    final row = conversations.where((c) => c.id == conv).firstOrNull;
    if (row != null) {
      row
        ..peerReadId = _maxOf(row.peerReadId, read)
        ..peerDeliveredId = _maxOf(row.peerDeliveredId, delivered);
      notifyListeners();
    }
  }

  void _onTyping(Map<String, dynamic> d) {
    final conv = int.tryParse('${d['conversation_id'] ?? ''}');
    if (conv == null || int.tryParse('${d['user_id'] ?? ''}') == myId) return;
    final name = '${d['name'] ?? ''}';
    final on = d['typing'] != false;
    if (on) {
      typing[conv] = name;
    } else {
      typing.remove(conv);
    }
    _threads[conv]?.onTyping(on ? name : null);
    notifyListeners();
    _typingTimers.remove(conv)?.cancel();
    if (on) {
      _typingTimers[conv] = Timer(const Duration(seconds: 6), () {
        _typingTimers.remove(conv);
        typing.remove(conv);
        _threads[conv]?.onTyping(null);
        notifyListeners();
      });
    }
  }

  final Map<int, Timer> _typingTimers = {};

  void _onPresence(Map<String, dynamic> d) {
    final user = int.tryParse('${d['user_id'] ?? ''}');
    final on = d['online'] == true;
    for (final c in conversations) {
      if (c.peer?.id == user) c.online = on;
    }
    for (final t in _threads.values) {
      if (t.conversation?.peer?.id == user) t.onPresence(on);
    }
    notifyListeners();
  }

  void _onConversation(Map<String, dynamic> d) {
    final action = '${d['action'] ?? ''}';
    final conv = int.tryParse('${d['conversation_id'] ?? ''}');
    final peer = int.tryParse('${d['peer_id'] ?? ''}');
    if (action == 'state') {
      for (final t in _threads.values) {
        if (conv == t.conversationId || (peer != null && t.conversation?.peer?.id == peer)) t.reloadHeader();
      }
      if (conversations.isNotEmpty) load(silent: true);
    } else if (action == 'read' && conv != null) {
      final row = conversations.where((c) => c.id == conv).firstOrNull;
      if (row != null) {
        row.unread = int.tryParse('${d['unread'] ?? ''}') ?? 0;     // read on another device (older servers say nothing: all read)
        row.lastReadId = _maxOf(row.lastReadId, int.tryParse('${d['last_read_id'] ?? ''}'));
        notifyListeners();
      }
    } else if (action == 'request') {
      load(silent: true);
      if (requests.isNotEmpty) loadRequests();
    } else {
      load(silent: true);
    }
  }

  void _sortRows() {
    conversations.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.lastAt.compareTo(a.lastAt);
    });
  }

  Future<void> load({bool silent = false}) async {
    await ensureUser();
    final seq = ++_loadSeq;
    if (!silent) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      final p = await api.conversations(filter: filter, courseId: courseId, role: role, q: search);
      if (seq != _loadSeq) return;     // a newer load (a filter tapped, the search typed on) owns the list
      conversations
        ..clear()
        ..addAll(p.items);
      _counted.clear();
      hasMore = p.hasMore;
      filterCourses = p.courses;
      filterRoles = p.roles;
      requestCount = p.requestCount;
      error = null;
      // the list arrived: everything in it has reached this device
      final ack = [for (final c in p.items) if (c.unread > 0 && c.last != null) {'conversation_id': c.id, 'message_id': c.last!.id}];
      if (ack.isNotEmpty) api.delivered(ack.take(100).toList()).catchError((_) {});
    } catch (e) {
      if (seq != _loadSeq) return;
      error = ApiException.from(e).message;
    }
    loading = false;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (!hasMore || loading || _loadingMore) return;
    _loadingMore = true;
    try {
      final p = await api.conversations(filter: filter, courseId: courseId, role: role, q: search, offset: conversations.length);
      final have = {for (final c in conversations) c.id};
      conversations.addAll(p.items.where((c) => have.add(c.id)));
      hasMore = p.hasMore;
      notifyListeners();
    } catch (_) {
      // the next scroll asks again
    } finally {
      _loadingMore = false;
    }
  }

  void applyFilters({String? filter, int? courseId, bool clearCourse = false, String? role, bool clearRole = false, String? search}) {
    if (filter != null) this.filter = filter;
    if (courseId != null || clearCourse) this.courseId = courseId;
    if (role != null || clearRole) this.role = role;
    if (search != null) this.search = search;
    load();
  }

  void markLocallyRead(int conv) {
    final row = conversations.where((c) => c.id == conv).firstOrNull;
    if (row != null && row.unread != 0) {
      row.unread = 0;
      notifyListeners();
    }
  }

  Future<void> togglePin(ChatConversation c) async {
    c.pinned = !c.pinned;
    _sortRows();
    notifyListeners();
    try {
      await api.prefs(c.id, pinned: c.pinned);
    } catch (_) {
      c.pinned = !c.pinned;
      notifyListeners();
    }
  }

  Future<void> setMute(ChatConversation c, String mode) async {
    final was = c.muted;
    c.muted = mode != 'off';
    notifyListeners();
    try {
      await api.prefs(c.id, mute: mode);
      AttentionService.instance.refresh();
    } catch (_) {
      c.muted = was;
      notifyListeners();
    }
  }

  // ── message requests ───────────────────────────────────────────────────────────────────────────────────────

  Future<void> loadRequests() async {
    requestsLoading = true;
    notifyListeners();
    try {
      final (items, more) = await api.requests();
      requests = items;
      if (!more) requestCount = items.length;
    } catch (_) {
      // the section says nothing new; the count from the list stays
    }
    requestsLoading = false;
    notifyListeners();
  }

  /// Accepted: the chat is an ordinary one and goes on the list. The caller opens it.
  Future<ChatConversation> acceptRequest(int id) async {
    final c = await api.acceptRequest(id);
    _dropRequest(id);
    load(silent: true);
    _threads[id]?.reloadHeader();
    return c;
  }

  Future<void> declineRequest(int id) async {
    await api.declineRequest(id);
    _dropRequest(id);
  }

  Future<void> blockRequest(int id) async {
    await api.blockRequest(id);
    _dropRequest(id);
  }

  void _dropRequest(int id) {
    requests = [for (final r in requests) if (r.id != id) r];
    if (requestCount > 0) requestCount -= 1;
    notifyListeners();
  }

  // ── threads ────────────────────────────────────────────────────────────────────────────────────────────────

  /// True while this conversation is on screen (a push for it stays quiet).
  bool selectedOrOpen(int? conv) => conv != null && (_threads[conv]?.visible ?? false);

  /// The one controller of this conversation, for a screen showing it. [release] when the screen is gone.
  ChatThreadController acquire(int conv) {
    final t = _threads.remove(conv) ?? ChatThreadController(conv, hub: this);
    _threads[conv] = t;     // newest in the LRU order
    t.refs += 1;
    return t;
  }

  void release(ChatThreadController t) {
    if (!identical(_threads[t.conversationId], t)) return;
    t.refs = t.refs > 0 ? t.refs - 1 : 0;
    if (t.refs > 0) return;
    t.pause();
    final idle = [for (final x in _threads.values) if (x.refs == 0 && !x.busy) x];
    for (final x in idle.take(idle.length > _keepIdle ? idle.length - _keepIdle : 0)) {
      _threads.remove(x.conversationId);
      x.dispose();
    }
  }

  void registerThread(ChatThreadController t) => _threads[t.conversationId] = t;

  void unregisterThread(ChatThreadController t) {
    if (identical(_threads[t.conversationId], t)) _threads.remove(t.conversationId);
  }

  // ── drafts ─────────────────────────────────────────────────────────────────────────────────────────────────
  final Map<int, String> drafts = {};
  String get _draftKey => 'chat_drafts_$myId';

  void _loadDrafts() {
    final raw = _prefs?.getString(_draftKey);
    if (raw == null) return;
    try {
      (jsonDecode(raw) as Map).forEach((k, v) => drafts[int.parse('$k')] = '$v');
    } catch (_) {}
  }

  void setDraft(int conv, String text) {
    if (_myId == null) return; // signed out: a closing screen must not write its text back
    final t = text.trim();
    if (t.isEmpty) {
      if (drafts.remove(conv) == null) return;
    } else {
      if (drafts[conv] == text) return;
      drafts[conv] = text;
    }
    _prefs?.setString(_draftKey, jsonEncode(drafts.map((k, v) => MapEntry('$k', v))));
    notifyListeners();
  }

  // ── the outbox: what still has to go out, persisted ─────────────────────────────────────────────────────────
  final Map<String, Map<String, dynamic>> _outbox = {};
  String get _outboxKey => 'chat_outbox_$myId';
  bool _flushing = false;

  void _loadOutbox() {
    final raw = _prefs?.getString(_outboxKey);
    if (raw == null) return;
    try {
      for (final e in (jsonDecode(raw) as List)) {
        final m = Map<String, dynamic>.from(e as Map);
        _outbox['${m['client_id']}'] = m;
      }
    } catch (_) {}
  }

  void _saveOutbox() {
    _prefs?.setString(_outboxKey, jsonEncode(_outbox.values.toList()));
  }

  /// Refuses a message of an account that is no longer this device's.
  void outboxAdd(ChatMessage m) {
    if (_myId == null || m.senderId != _myId) return;
    _outbox[m.clientId] = {
      'client_id': m.clientId,
      'conversation_id': m.conversationId,
      'body': m.body,
      'created_at': m.createdAt.toIso8601String(),
      'files': [for (final f in m.local) f.toJson()],
      'uploaded': m.uploaded,
      if (m.replyTo != null) 'reply_to': m.replyTo!.toJson(),
      'failed': m.sendState == ChatSendState.failed,
      'auto': m.autoRetry,
      'error': m.error,
    };
    _saveOutbox();
  }

  void outboxRemove(String clientId) {
    if (_outbox.remove(clientId) != null) _saveOutbox();
  }

  /// What waits to go out in this chat, as messages for the screen. A file whose bytes died with the last page can not
  /// be resent: it shows as failed instead of quietly going out without its attachment.
  List<ChatMessage> pendingFor(int conv) {
    final out = <ChatMessage>[];
    for (final m in _outbox.values) {
      if ('${m['conversation_id']}' != '$conv') continue;
      final files = [for (final f in (m['files'] as List? ?? const [])) if (f is Map) ChatLocalFile.fromJson(f)];
      final uploaded = [for (final v in (m['uploaded'] as List? ?? const [])) ?int.tryParse('$v')];
      final lost = _hasLostFile(files, uploaded);
      final failed = m['failed'] == true || lost;
      out.add(ChatMessage(
        clientId: '${m['client_id']}',
        conversationId: conv,
        body: m['body'] as String?,
        senderId: myId,
        createdAt: chatUtc(m['created_at']),
        local: files,
        uploaded: uploaded,
        sendState: failed ? ChatSendState.failed : ChatSendState.queued,
        autoRetry: m['auto'] == true,
        error: lost ? ChatMessage.lostFileError : m['error'] as String?,
        replyTo: ChatReplyRef.fromJson(m['reply_to']),
      ));
    }
    return out;
  }

  static bool _hasLostFile(List<ChatLocalFile> files, List<int> uploaded) {
    for (var i = uploaded.length; i < files.length; i++) {
      if (!files[i].readable) return true;
    }
    return false;
  }

  /// Sends everything waiting, oldest first; stops on the first network failure. A chat with a live controller sends its own.
  Future<void> flushOutbox() async {
    if (_flushing || _outbox.isEmpty) return;
    _flushing = true;
    final owner = _myId;
    try {
      final items = _outbox.values.toList()..sort((a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'));
      final kicked = <int>{};
      for (final m in items) {
        if (_myId != owner) return; // the account changed under this loop: nothing more goes out under the new token
        final conv = int.tryParse('${m['conversation_id']}') ?? 0;
        final thread = _threads[conv];
        if (thread != null) {
          if (kicked.add(conv) && thread.loaded) thread.resumeQueued();
          continue;
        }
        if (m['failed'] == true && m['auto'] != true) continue;
        final clientId = '${m['client_id']}';
        try {
          final files = [for (final f in (m['files'] as List? ?? const [])) if (f is Map) ChatLocalFile.fromJson(f)];
          final ids = [for (final v in (m['uploaded'] as List? ?? const [])) ?int.tryParse('$v')];
          if (_hasLostFile(files, ids)) {
            _markOutboxFailed(clientId, ChatMessage.lostFileError);
            continue;
          }
          for (var i = ids.length; i < files.length; i++) {
            final uploaded = await api.upload(conv, files[i]);
            if (_myId != owner) return;
            ids.add(uploaded.id);
            m['uploaded'] = ids;
            _saveOutbox();
          }
          final sent = await api.send(conv, clientId: clientId, body: m['body'] as String?, attachmentIds: ids, replyToId: ChatReplyRef.fromJson(m['reply_to'])?.id);
          if (_myId != owner) return;
          outboxRemove(clientId);
          noteSent(conv, sent);
        } catch (e) {
          if (_myId != owner) return;
          if (chatIsNetworkError(e)) break;
          _markOutboxFailed(clientId, ApiException.from(e).message);
        }
      }
    } finally {
      _flushing = false;
    }
  }

  void _markOutboxFailed(String clientId, String error) {
    final m = _outbox[clientId];
    if (m == null) return;
    m
      ..['failed'] = true
      ..['auto'] = false
      ..['error'] = error;
    _saveOutbox();
  }

  @visibleForTesting
  Map<String, Map<String, dynamic>> get debugOutbox => _outbox;

  @visibleForTesting
  Future<void> outboxAddAndSettle(ChatMessage m) async {
    _prefs ??= await SharedPreferences.getInstance();
    outboxAdd(m);
  }

  @visibleForTesting
  void debugResetForTest() {
    _myId = null;
    conversations.clear();
    drafts.clear();
    _outbox.clear();
    _threads.clear();
    typing.clear();
    _counted.clear();
    requests = const [];
    requestCount = 0;
  }
}

/// Did this fail because the server was not reached (or broke), as opposed to the server saying no?
bool chatIsNetworkError(Object e) {
  final x = ApiException.from(e);
  return x.statusCode == 0 || x.statusCode >= 500;
}

class ChatThreadController extends ChangeNotifier {
  ChatThreadController(this.conversationId, {ChatHub? hub, this.pollEvery = const Duration(seconds: 15)}) : hub = hub ?? ChatHub.instance;

  final int conversationId;
  final ChatHub hub;
  final Duration pollEvery;

  ChatConversation? conversation;
  List<ChatMessage> messages = [];
  bool loading = true, hasMore = false, loadingOlder = false;
  String? error, typingName;
  bool visible = false;

  /// Screens showing this thread (the hub's reference count).
  int refs = 0;

  /// The list sits at the newest message. Scrolled up, nothing is read and new messages are counted instead.
  bool atLatest = true;

  /// Messages from the others that came in while the person was scrolled up.
  int newBelow = 0;

  /// Where the "new messages" line goes: the first message not read when the chat was opened.
  String? firstUnreadKey;

  bool loaded = false;
  int? _syncedThrough;
  int _readSent = 0;
  EventOrPoll? _fallback;
  Timer? _typingStop;
  bool _typingOn = false;
  DateTime _lastTyping = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;
  bool _pumping = false;

  ChatApi get _api => hub.api;

  /// The person can see the newest message right now.
  bool get reading => visible && atLatest;

  /// Something is still on its way out: this controller must stay alive for it.
  bool get busy => _pumping || messages.any((m) => m.sendState == ChatSendState.sending);

  /// A screen is showing this chat. Safe to call again on a thread that was already loaded: it only catches up.
  Future<void> open() async {
    hub.registerThread(this);
    visible = true;
    await hub.ensureUser();
    if (_gone) return;
    if (loaded) {
      _placeUnread(); // the line is about this visit
      unawaited(reloadHeader());
      _syncNewest();
      _startFallback();
      _markRead();
      return;
    }
    await reloadHeader();
    if (_disposed) return;
    final pending = hub.pendingFor(conversationId);
    try {
      // enough to hold what is unread, so the "new messages" line lands where it should
      final p = await _api.messages(conversationId, limit: ((conversation?.unread ?? 0) + 12).clamp(30, 60));
      messages = chatMergeMessages([...messages, ...pending], p.items);
      for (final m in pending) {
        if (m.id != null) hub.outboxRemove(m.clientId);   // the server had it already (the app closed before the answer)
      }
      hasMore = p.hasMore;
      _syncedThrough = _newestStoredId ?? 0;
      _placeUnread();
      loaded = true;
      error = null;
    } catch (e) {
      messages = chatMergeMessages(messages, pending);
      error = ApiException.from(e).message;
    }
    loading = false;
    _notify();
    if (_gone) return; // the screen closed during the load: what arrived is kept, nothing keeps running for it
    _markRead();
    resumeQueued();
    _startFallback();
  }

  bool get _gone => _disposed || refs == 0;

  void _startFallback() {
    _fallback ??= EventOrPoll(
      poll: _syncNewest,
      every: pollEvery,
      fallbackEvery: const Duration(minutes: 3),
      names: const {LiveEvents.chatMessage},
      match: (_) => false, // every event already carries its message; only the timer runs this
    )..start();
  }

  /// The screen closed: no more polling or typing, but the thread stays current and whatever is going out still goes.
  void pause() {
    visible = false;
    _fallback?.stop();
    _fallback = null;
    _stopTyping();
  }

  @visibleForTesting
  void debugSynced(int? through) => _syncedThrough = through;

  @visibleForTesting
  bool get debugPolling => _fallback != null;

  int? get _newestStoredId => messages.where((m) => m.id != null).firstOrNull?.id;

  /// Many unread messages: the screen opens on the first of them (D-544). `atLatest` goes false before the read mark
  /// would go out, so opening a long backlog does not mark it read: reaching the end does.
  void _placeUnread() {
    firstUnreadKey = _firstUnread();
    atLatest = !startsAtUnread;
    newBelow = 0;
  }

  /// Enough unread messages that the chat opens on the first of them instead of at the end.
  bool get startsAtUnread {
    final key = firstUnreadKey;
    return key != null && messages.indexWhere((m) => m.clientId == key) >= 10;
  }

  String? _firstUnread() {
    final read = conversation?.lastReadId ?? 0;
    final unread = messages.where((m) => m.id != null && m.id! > read && m.senderId != hub.myId).toList();
    return unread.isEmpty ? null : unread.last.clientId;
  }

  Future<void> reloadHeader() async {
    try {
      conversation = await _api.thread(conversationId);
      _notify();
    } catch (e) {
      error = ApiException.from(e).message;
      _notify();
    }
  }

  void setVisible(bool v) {
    visible = v;
    if (v) _markRead();
  }

  /// The list reached (or left) the newest message.
  void setAtLatest(bool v) {
    if (atLatest == v) return;
    atLatest = v;
    if (v) {
      newBelow = 0;
      _markRead();
    }
    _notify();
  }

  void onIncoming(ChatMessage m) {
    final isNew = !messages.any((x) => x.clientId == m.clientId);
    messages = chatMergeMessages(messages, [m]);
    if (m.senderId != hub.myId) {
      if (isNew && visible && !atLatest) newBelow += 1;
      _markRead();
    }
    _notify();
  }

  void onReceipt({int? read, int? delivered}) {
    final c = conversation;
    if (c == null) return;
    if (read != null && read > (c.peerReadId ?? 0)) c.peerReadId = read;
    if (delivered != null && delivered > (c.peerDeliveredId ?? 0)) c.peerDeliveredId = delivered;
    _notify();
  }

  void onTyping(String? name) {
    typingName = name;
    _notify();
  }

  void onPresence(bool on) {
    conversation?.online = on;
    _notify();
  }

  /// Reconnected: fetch what was missed and send what was waiting in this chat.
  void catchUp() {
    _syncNewest();
    resumeQueued();
  }

  /// Everything since the last fetch, not since the newest message on screen: a live event can arrive ahead of a gap,
  /// and the gap has to be filled too.
  Future<void> _syncNewest() async {
    if (!loaded) return;
    var after = _syncedThrough ?? 0;
    try {
      for (var page = 0; page < 8; page++) {
        final p = await _api.messages(conversationId, after: after, limit: 60);
        if (p.items.isNotEmpty) {
          messages = chatMergeMessages(messages, p.items);
          after = p.items.first.id ?? after;
          _syncedThrough = after;
          _notify();
        }
        if (!p.hasMore) break;
      }
      _markRead();
    } catch (_) {}
  }

  Future<void> loadOlder() async {
    if (!hasMore || loadingOlder) return;
    final oldest = messages.where((m) => m.id != null).lastOrNull?.id;
    if (oldest == null) return;
    loadingOlder = true;
    _notify();
    try {
      final p = await _api.messages(conversationId, before: oldest);
      messages = chatMergeMessages(messages, p.items);
      hasMore = p.hasMore;
    } catch (_) {}
    loadingOlder = false;
    _notify();
  }

  void _markRead() {
    if (!reading) return;
    final top = messages.where((m) => m.id != null && m.senderId != hub.myId).firstOrNull;
    if (top == null) return;
    final done = conversation?.lastReadId ?? 0;
    if (top.id! <= done || top.id! <= _readSent) return;
    _readSent = top.id!;
    conversation?.lastReadId = top.id;
    hub.markLocallyRead(conversationId);
    _api.read(conversationId, top.id!).then((_) => AttentionService.instance.refresh(quiet: true), onError: (_) {});
  }

  void typingChanged(bool hasText) {
    if (!(conversation?.composer == ChatComposerState.open)) return;
    if (!hasText) {
      _stopTyping();
      return;
    }
    if (DateTime.now().difference(_lastTyping) > const Duration(seconds: 4)) {
      _lastTyping = DateTime.now();
      _typingOn = true;
      _api.typing(conversationId, true).catchError((_) {});
    }
    _typingStop?.cancel();
    _typingStop = Timer(const Duration(seconds: 5), _stopTyping);
  }

  void _stopTyping() {
    _typingStop?.cancel();
    _typingStop = null;
    _lastTyping = DateTime.fromMillisecondsSinceEpoch(0);
    if (_typingOn) {
      _typingOn = false;
      _api.typing(conversationId, false).catchError((_) {});
    }
  }

  /// Show the message now, then send; offline it waits in the outbox.
  Future<void> send(String text, {List<ChatLocalFile> files = const [], ChatReplyRef? replyTo}) async {
    final t = text.trim();
    if (t.isEmpty && files.isEmpty) return;
    hub.setDraft(conversationId, '');
    _stopTyping();
    firstUnreadKey = null;
    final m = ChatMessage(
      clientId: chatNewClientId(),
      conversationId: conversationId,
      kind: files.isEmpty ? 'text' : 'file',
      body: t.isEmpty ? null : t,
      senderId: hub.myId,
      local: files,
      createdAt: DateTime.now().toUtc(),
      sendState: AppConnectivity.instance.isOnline ? ChatSendState.sending : ChatSendState.queued,
      replyTo: replyTo,
    );
    messages = chatMergeMessages(messages, [m]);
    _notify();
    hub.outboxAdd(m);
    await _pump();
  }

  Future<void> retry(ChatMessage m) async {
    m
      ..sendState = AppConnectivity.instance.isOnline ? ChatSendState.sending : ChatSendState.queued
      ..autoRetry = false
      ..error = null;
    _notify();
    hub.outboxAdd(m);
    await _pump();
  }

  /// A failed message the person gives up on.
  void discard(ChatMessage m) {
    hub.outboxRemove(m.clientId);
    messages = [for (final x in messages) if (x.clientId != m.clientId) x];
    _notify();
  }

  /// Back online (or the chat opened): what waited, and what failed only for lack of a network, goes again.
  Future<void> resumeQueued() async {
    if (!AppConnectivity.instance.isOnline) return;
    var any = false;
    for (final m in messages) {
      if (m.sendState == ChatSendState.queued || (m.sendState == ChatSendState.failed && m.autoRetry)) {
        m
          ..sendState = ChatSendState.sending
          ..autoRetry = false
          ..error = null;
        any = true;
      }
    }
    if (any) _notify();
    await _pump();
  }

  /// One at a time, oldest first: what was typed first is first on the server.
  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (true) {
        final next = messages.where((m) => m.sendState == ChatSendState.sending).lastOrNull;
        if (next == null || _disposed || next.senderId != hub.myId) break;
        await _deliver(next);
      }
    } finally {
      _pumping = false;
    }
  }

  /// Always moves [m] off `sending`.
  Future<void> _deliver(ChatMessage m) async {
    try {
      final lost = !_filesReadable(m);
      if (lost) {
        _fail(m, ChatMessage.lostFileError, auto: false);
        return;
      }
      final ids = [...m.uploaded];
      for (var i = ids.length; i < m.local.length; i++) {
        final uploaded = await _api.upload(conversationId, m.local[i]);
        if (_stale(m)) return;
        ids.add(uploaded.id);
        m.uploaded = [...ids];
        hub.outboxAdd(m);
      }
      if (_stale(m)) return;
      final sent = await _api.send(conversationId, clientId: m.clientId, body: m.body, attachmentIds: ids, replyToId: m.replyTo?.id);
      if (_stale(m)) return;
      hub.outboxRemove(m.clientId);
      messages = chatMergeMessages(messages, [sent]);
      hub.noteSent(conversationId, sent);
      _notify();
    } catch (e) {
      if (_stale(m)) return;
      final x = ApiException.from(e);
      if (chatIsNetworkError(e)) {
        if (!AppConnectivity.instance.isOnline) {
          // the outbox holds it; reconnecting sends it, and everything behind it waits the same way
          for (final w in messages.where((w) => w.sendState == ChatSendState.sending)) {
            w.sendState = ChatSendState.queued;
            hub.outboxAdd(w);
          }
          _notify();
          return;
        }
        // the device says online but the server did not answer: the person can retry now, a reconnect retries by itself
        _fail(m, null, auto: true);
        return;
      }
      _fail(m, x.message, auto: false);
      if (conversation != null && (x.code ?? '').startsWith('chat_')) reloadHeader();
    }
  }

  /// This controller is gone or the account changed: this message must not go out under the token now in use.
  bool _stale(ChatMessage m) => _disposed || m.senderId != hub.myId;

  bool _filesReadable(ChatMessage m) {
    for (var i = m.uploaded.length; i < m.local.length; i++) {
      if (!m.local[i].readable) return false;
    }
    return true;
  }

  void _fail(ChatMessage m, String? message, {required bool auto}) {
    m
      ..sendState = ChatSendState.failed
      ..autoRetry = auto
      ..error = message;
    hub.outboxAdd(m);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _fallback?.stop();
    _typingStop?.cancel();
    hub.unregisterThread(this);
    super.dispose();
  }
}
