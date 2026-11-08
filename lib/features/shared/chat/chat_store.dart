// lib/features/shared/chat/chat_store.dart — NextBrain Messages (D-330): the one state behind every chat screen.
//
//   ChatHub.instance        the chat list, the real-time events (chat_* on LiveEvents), delivered acks, drafts, the outbox
//   ChatThreadController    one open chat: its messages, the composer's state, typing, sending, retry
//
// Real time: `start()` (called once by topRouteObserver) subscribes LiveEvents. A `chat_message` event carries the
// message itself, so an open chat needs no fetch; `EventOrPoll` keeps a slow poll only for when the stream is down.
// Sending: a message gets a client id and shows at once; while offline it waits in the persisted outbox and goes out on
// reconnect. A resend with the same client id is one message on the server.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/utils/live_events.dart';

import 'chat_api.dart';
import 'chat_models.dart';

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
        ..local = const []
        ..createdAt = m.createdAt
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
  if (m.sendState == ChatSendState.failed) return ChatTick.failed;
  final id = m.id ?? 0;
  if (peerReadId != null && peerReadId >= id) return ChatTick.read;
  if (peerDeliveredId != null && peerDeliveredId >= id) return ChatTick.delivered;
  return ChatTick.sent;
}

enum ChatTick { sending, failed, sent, delivered, read }

class ChatHub extends ChangeNotifier {
  ChatHub._();
  static final ChatHub instance = ChatHub._();

  ChatApi api = ChatApi();
  SharedPreferences? _prefs;
  int? _myId;
  bool _started = false;
  StreamSubscription<LiveEvent>? _sub;

  final Map<int, ChatThreadController> _threads = {};
  final List<ChatConversation> conversations = [];
  bool loading = false, hasMore = false;
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

  int get myId => _myId ?? 0;

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
      _myId = id;
      drafts.clear();
      _loadDrafts();
      _loadOutbox();
    }
  }

  /// Once per app run (topRouteObserver).
  void start() {
    if (_started) return;
    _started = true;
    _sub = LiveEvents.instance.listen(
      {LiveEvents.chatMessage, LiveEvents.chatReceipt, LiveEvents.chatTyping, LiveEvents.chatPresence, LiveEvents.chatConversation, LiveEvents.connectivity},
      _onEvent,
    );
    ensureUser().then((_) => flushOutbox());
  }

  void stopForTest() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }

  void _onEvent(LiveEvent e) {
    switch (e.type) {
      case LiveEvents.chatMessage:
        _onMessage(e.data);
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
      t.catchUp();
    }
    if (conversations.isNotEmpty) load(silent: true);
  }

  void _onMessage(Map<String, dynamic> d) {
    final raw = d['message'];
    final conv = int.tryParse('${d['conversation_id'] ?? ''}');
    if (raw is! Map || conv == null) return;
    final msg = ChatMessage.fromJson(Map<String, dynamic>.from(raw));
    final isGroup = '${d['kind'] ?? ''}' == 'course_group';
    final mine = msg.senderId == myId;
    final open = _threads[conv];
    open?.onIncoming(msg);
    final row = conversations.where((c) => c.id == conv).firstOrNull;
    if (row == null) {
      if (filter == 'all' && search.isEmpty) load(silent: true);
    } else {
      row
        ..last = ChatLastMessage(id: msg.id ?? 0, kind: msg.kind, body: msg.body ?? '', senderId: msg.senderId, senderName: msg.senderName, createdAt: msg.createdAt)
        ..lastAt = msg.createdAt;
      if (!mine && !(open?.visible ?? false)) row.unread += 1;
      _sortRows();
      notifyListeners();
    }
    if (!mine) {
      if (open == null || !open.visible) {
        _queueDelivered(conv, msg.id);
      }
      if (isGroup && !(open?.visible ?? false)) {
        // a group sends no attention_changed (hundreds of re-reads per message): the badge is counted here
        if (!(row?.muted ?? false)) AttentionService.instance.bumpLocal(AttentionTabs.chat, 1);
      }
    }
  }

  final Map<int, int> _pendingDelivered = {};
  Timer? _deliveredTimer;

  void _queueDelivered(int conv, int? id) {
    if (id == null) return;
    _pendingDelivered[conv] = id;
    _deliveredTimer ??= Timer(const Duration(milliseconds: 600), () {
      _deliveredTimer = null;
      final items = [for (final e in _pendingDelivered.entries) {'conversation_id': e.key, 'message_id': e.value}];
      _pendingDelivered.clear();
      if (items.isNotEmpty) api.delivered(items).catchError((_) {});
    });
  }

  void _onReceipt(Map<String, dynamic> d) {
    final conv = int.tryParse('${d['conversation_id'] ?? ''}');
    if (conv == null) return;
    final read = int.tryParse('${d['read_id'] ?? ''}');
    final delivered = int.tryParse('${d['delivered_id'] ?? ''}');
    _threads[conv]?.onReceipt(read: read, delivered: delivered);
    final row = conversations.where((c) => c.id == conv).firstOrNull;
    if (row != null) {
      if (read != null) row.peerReadId = read;
      if (delivered != null) row.peerDeliveredId = delivered;
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
    _typingTimers[conv]?.cancel();
    if (on) {
      _typingTimers[conv] = Timer(const Duration(seconds: 6), () {
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
    } else if (action == 'read' && conv != null) {
      final row = conversations.where((c) => c.id == conv).firstOrNull;
      if (row != null) {
        row.unread = 0;
        notifyListeners();
      }
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
    if (!silent) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      final p = await api.conversations(filter: filter, courseId: courseId, role: role, q: search);
      conversations
        ..clear()
        ..addAll(p.items);
      hasMore = p.hasMore;
      filterCourses = p.courses;
      filterRoles = p.roles;
      error = null;
      // the list arrived: everything in it has reached this device
      final ack = [for (final c in p.items) if (c.unread > 0 && c.last != null) {'conversation_id': c.id, 'message_id': c.last!.id}];
      if (ack.isNotEmpty) api.delivered(ack.take(100).toList()).catchError((_) {});
    } catch (e) {
      error = ApiException.from(e).message;
    }
    loading = false;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (!hasMore || loading) return;
    final p = await api.conversations(filter: filter, courseId: courseId, role: role, q: search, offset: conversations.length);
    conversations.addAll(p.items);
    hasMore = p.hasMore;
    notifyListeners();
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

  /// True while this conversation is on screen (a push for it stays quiet).
  bool selectedOrOpen(int? conv) => conv != null && (_threads[conv]?.visible ?? false);

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
    final t = text.trim();
    if (t.isEmpty) {
      drafts.remove(conv);
    } else {
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

  void outboxAdd(ChatMessage m) {
    _outbox[m.clientId] = {
      'client_id': m.clientId,
      'conversation_id': m.conversationId,
      'body': m.body,
      'created_at': m.createdAt.toIso8601String(),
      'files': [for (final f in m.local) f.toJson()],
    };
    _saveOutbox();
  }

  void outboxRemove(String clientId) {
    if (_outbox.remove(clientId) != null) _saveOutbox();
  }

  List<ChatMessage> pendingFor(int conv) => [
        for (final m in _outbox.values)
          if ('${m['conversation_id']}' == '$conv')
            ChatMessage(
              clientId: '${m['client_id']}',
              conversationId: conv,
              body: m['body'] as String?,
              senderId: myId,
              createdAt: chatUtc(m['created_at']),
              local: [for (final f in (m['files'] as List? ?? const [])) if (f is Map) ChatLocalFile.fromJson(f)],
              sendState: ChatSendState.sending,
            ),
      ];

  /// Sends everything waiting, oldest first; stops on the first network failure.
  Future<void> flushOutbox() async {
    if (_flushing || _outbox.isEmpty) return;
    _flushing = true;
    try {
      final items = _outbox.values.toList()..sort((a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'));
      for (final m in items) {
        final conv = int.tryParse('${m['conversation_id']}') ?? 0;
        final thread = _threads[conv];
        if (thread != null) continue; // the open chat sends its own
        try {
          final files = [for (final f in (m['files'] as List? ?? const [])) if (f is Map) ChatLocalFile.fromJson(f)];
          final ids = <int>[];
          for (final f in files) {
            if (f.path == null) continue;
            ids.add((await api.upload(conv, f)).id);
          }
          await api.send(conv, clientId: '${m['client_id']}', body: m['body'] as String?, attachmentIds: ids);
          outboxRemove('${m['client_id']}');
        } catch (e) {
          if (_isNetwork(e)) break;
          outboxRemove('${m['client_id']}');
        }
      }
    } finally {
      _flushing = false;
    }
  }
}

bool _isNetwork(Object e) {
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
  EventOrPoll? _fallback;
  Timer? _typingStop;
  DateTime _lastTyping = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;

  ChatApi get _api => hub.api;

  Future<void> open() async {
    hub.registerThread(this);
    await hub.ensureUser();
    visible = true;
    await reloadHeader();
    try {
      final p = await _api.messages(conversationId);
      messages = chatMergeMessages([...hub.pendingFor(conversationId)], p.items);
      hasMore = p.hasMore;
      error = null;
    } catch (e) {
      error = ApiException.from(e).message;
    }
    loading = false;
    _notify();
    _markRead();
    _flushMine();
    _fallback ??= EventOrPoll(
      poll: () async => _syncNewest(),
      every: pollEvery,
      fallbackEvery: const Duration(minutes: 3),
      names: const {LiveEvents.chatMessage},
      match: (_) => false,        // every event already carries its message; only the timer runs this
    )..start();
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

  void onIncoming(ChatMessage m) {
    messages = chatMergeMessages(messages, [m]);
    if (m.senderId != hub.myId) _markRead();
    _notify();
  }

  void onReceipt({int? read, int? delivered}) {
    final c = conversation;
    if (c == null) return;
    if (read != null) c.peerReadId = read;
    if (delivered != null) c.peerDeliveredId = delivered;
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
    _flushMine();
  }

  Future<void> _syncNewest() async {
    final newest = messages.where((m) => m.id != null).firstOrNull?.id;
    if (newest == null) return;
    try {
      final p = await _api.messages(conversationId, after: newest, limit: 60);
      if (p.items.isEmpty) return;
      messages = chatMergeMessages(messages, p.items);
      _notify();
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
    if (!visible) return;
    final top = messages.where((m) => m.id != null && m.senderId != hub.myId).firstOrNull;
    if (top == null) return;
    final done = conversation?.lastReadId ?? 0;
    if (top.id! <= done) return;
    conversation?.lastReadId = top.id;
    hub.markLocallyRead(conversationId);
    _api.read(conversationId, top.id!).then((_) => AttentionService.instance.refresh(quiet: true), onError: (_) {});
  }

  void typingChanged(bool hasText) {
    if (!(conversation?.composer == ChatComposerState.open)) return;
    if (hasText && DateTime.now().difference(_lastTyping) > const Duration(seconds: 4)) {
      _lastTyping = DateTime.now();
      _api.typing(conversationId, true).catchError((_) {});
    }
    _typingStop?.cancel();
    _typingStop = Timer(const Duration(seconds: 5), () {
      _lastTyping = DateTime.fromMillisecondsSinceEpoch(0);
      _api.typing(conversationId, false).catchError((_) {});
    });
  }

  /// Show the message now, then send; offline it waits in the outbox.
  Future<void> send(String text, {List<ChatLocalFile> files = const []}) async {
    final t = text.trim();
    if (t.isEmpty && files.isEmpty) return;
    hub.setDraft(conversationId, '');
    final m = ChatMessage(
      clientId: chatNewClientId(),
      conversationId: conversationId,
      kind: files.isEmpty ? 'text' : 'file',
      body: t.isEmpty ? null : t,
      senderId: hub.myId,
      local: files,
      createdAt: DateTime.now().toUtc(),
      sendState: ChatSendState.sending,
    );
    messages = chatMergeMessages(messages, [m]);
    _notify();
    hub.outboxAdd(m);
    await _deliver(m);
  }

  Future<void> retry(ChatMessage m) async {
    m
      ..sendState = ChatSendState.sending
      ..error = null;
    _notify();
    hub.outboxAdd(m);
    await _deliver(m);
  }

  Future<void> _flushMine() async {
    for (final m in messages.where((m) => m.sendState == ChatSendState.sending).toList().reversed) {
      await _deliver(m);
    }
  }

  Future<void> _deliver(ChatMessage m) async {
    try {
      final ids = <int>[];
      for (final f in m.local) {
        ids.add((await _api.upload(conversationId, f)).id);
      }
      final sent = await _api.send(conversationId, clientId: m.clientId, body: m.body, attachmentIds: ids);
      hub.outboxRemove(m.clientId);
      messages = chatMergeMessages(messages, [sent]);
      _notify();
    } catch (e) {
      if (_isNetwork(e)) {
        // stays as "sending"; goes out on reconnect (flushOutbox / the next open)
        return;
      }
      m
        ..sendState = ChatSendState.failed
        ..error = ApiException.from(e).message;
      hub.outboxRemove(m.clientId);
      _notify();
      if (conversation != null && (ApiException.from(e).code ?? '').startsWith('chat_')) reloadHeader();
    }
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
