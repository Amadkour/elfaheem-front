// NextBrain Messages (D-375): the client's delivery logic against a fake server: sending order, the queue, retry, replayed
// events, one controller per chat, the read mark and the "new messages" count.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/features/messaging/chat/chat_api.dart';
import 'package:flutter_education_app/features/messaging/chat/chat_models.dart';
import 'package:flutter_education_app/features/messaging/chat/chat_page.dart';
import 'package:flutter_education_app/features/messaging/chat/chat_store.dart';
import 'package:flutter_education_app/features/messaging/chat/chat_widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/layout_harness.dart';

const me = 1, peer = 2, conv = 7;

class FakeServer extends ChatApi {
  final sends = <String>[];
  final bodies = <String>[];
  final reads = <int>[];
  final delivered_ = <Map<String, int>>[];
  final afters = <int?>[];
  int uploads = 0, nextId = 100, maxConcurrent = 0, _inFlight = 0;
  Object? failNext;
  Object? failUpload;
  void Function()? onUpload, onSend, onMessages;
  List<ChatMessage> Function(int? after)? pageAfter;

  @override
  Future<ChatMessage> send(int id, {required String clientId, String? body, List<int> attachmentIds = const [], int? replyToId}) async {
    onSend?.call();
    _inFlight++;
    if (_inFlight > maxConcurrent) maxConcurrent = _inFlight;
    await Future<void>.delayed(Duration.zero);
    _inFlight--;
    final fail = failNext;
    if (fail != null) {
      failNext = null;
      throw fail;
    }
    sends.add(clientId);
    bodies.add(body ?? '');
    return ChatMessage(id: nextId++, clientId: clientId, conversationId: id, body: body, senderId: me, createdAt: DateTime.now().toUtc());
  }

  @override
  Future<ChatAttachment> upload(int conversationId, ChatLocalFile f) async {
    final fail = failUpload;
    if (fail != null) {
      failUpload = null;
      throw fail;
    }
    uploads++;
    onUpload?.call();
    return ChatAttachment(id: 500 + uploads, name: f.name, mime: 'application/pdf', ext: 'pdf');
  }

  @override
  Future<void> read(int id, int messageId) async => reads.add(messageId);

  @override
  Future<void> delivered(List<Map<String, int>> items) async => delivered_.addAll(items);

  @override
  Future<void> typing(int id, bool typing) async {}

  @override
  Future<ChatConversation> thread(int id) async => ChatConversation(id: id, kind: 'direct', lastAt: DateTime.now().toUtc(), composer: ChatComposerState.open);

  @override
  Future<ChatMessagePage> messages(int id, {int? before, int? after, int limit = 30}) async {
    afters.add(after);
    onMessages?.call();
    return ChatMessagePage(pageAfter?.call(after) ?? const [], false);
  }
}

ChatMessage incoming(int id, {int sender = peer, String? client}) =>
    ChatMessage(id: id, clientId: client ?? 'p$id', conversationId: conv, body: 'hi $id', senderId: sender, createdAt: DateTime.utc(2026, 1, 1).add(Duration(seconds: id)));

Map<String, dynamic> eventOf(ChatMessage m, {String kind = 'direct'}) => {
      'conversation_id': conv,
      'kind': kind,
      'message': {'id': m.id, 'client_id': m.clientId, 'conversation_id': conv, 'kind': 'text', 'body': m.body, 'sender_id': m.senderId, 'created_at': m.createdAt.toIso8601String(), 'attachments': const []},
    };

ChatConversation row({int? lastId, int unread = 0, String kind = 'direct'}) => ChatConversation(
      id: conv,
      kind: kind,
      lastAt: DateTime.utc(2026, 1, 1),
      unread: unread,
      last: lastId == null ? null : ChatLastMessage(id: lastId, kind: 'text', createdAt: DateTime.utc(2026, 1, 1)),
    );

const offlineError = ApiException(statusCode: 0, type: ApiErrorType.network, message: 'no network');
const forbidden = ApiException(statusCode: 403, type: ApiErrorType.forbidden, message: 'you can not send here');

void main() {
  late ChatHub hub;
  late FakeServer api;

  ChatThreadController opened() {
    final t = ChatThreadController(conv, hub: hub)
      ..loaded = true
      ..visible = true;
    hub.registerThread(t);
    return t;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({'current_user': jsonEncode({'id': me})});
    AppConfig.lang = 'en';
    AppConnectivity.instance.online.value = true;
    api = FakeServer();
    hub = ChatHub.forTest()
      ..api = api
      ..debugSetMyId(me);
  });

  group('sending', () {
    test('two messages typed quickly: one in flight at a time, oldest first', () async {
      final t = opened();
      final a = t.send('first');
      final b = t.send('second');
      await Future.wait([a, b]);
      await Future<void>.delayed(Duration.zero);
      expect(api.bodies, ['first', 'second']);
      expect(api.maxConcurrent, 1);
      expect(t.messages.every((m) => m.sendState == ChatSendState.sent), isTrue);
      expect(hub.debugOutbox, isEmpty);
    });

    test('offline: stays on screen as queued, in the outbox; reconnect sends it', () async {
      AppConnectivity.instance.online.value = false;
      api.failNext = offlineError;
      final t = opened();
      await t.send('while offline');
      expect(t.messages.single.sendState, ChatSendState.queued);
      expect(hub.debugOutbox.length, 1);
      expect(chatTickFor(t.messages.single), ChatTick.queued);
      api.failNext = null;
      AppConnectivity.instance.online.value = true;
      await t.resumeQueued();
      await Future<void>.delayed(Duration.zero);
      expect(api.bodies, ['while offline']);
      expect(t.messages.single.sendState, ChatSendState.sent);
      expect(hub.debugOutbox, isEmpty);
    });

    test('online but the server did not answer: failed, tap to retry, and a reconnect retries by itself', () async {
      api.failNext = offlineError;
      final t = opened();
      await t.send('hello');
      final m = t.messages.single;
      expect(m.sendState, ChatSendState.failed);
      expect(m.autoRetry, isTrue);
      await t.resumeQueued();
      await Future<void>.delayed(Duration.zero);
      expect(api.bodies, ['hello']);
      expect(m.sendState, ChatSendState.sent);
    });

    test('the server says no: the text is kept as failed, across a restart; retry and delete both work', () async {
      api.failNext = forbidden;
      final t = opened();
      await t.send('kept');
      final m = t.messages.single;
      expect(m.sendState, ChatSendState.failed);
      expect(m.error, 'you can not send here');
      // a new screen after the app restarted still has it, as failed
      final pending = hub.pendingFor(conv);
      expect(pending.single.body, 'kept');
      expect(pending.single.sendState, ChatSendState.failed);
      await t.retry(m);
      expect(m.sendState, ChatSendState.sent);
      expect(hub.debugOutbox, isEmpty);

      api.failNext = forbidden;
      await t.send('give up');
      final gone = t.messages.firstWhere((x) => x.body == 'give up');
      t.discard(gone);
      expect(t.messages.where((x) => x.body == 'give up'), isEmpty);
      expect(hub.debugOutbox, isEmpty);
    });

    test('a retry never uploads a file twice', () async {
      final t = opened();
      final file = ChatLocalFile(name: 'a.pdf', bytes: Uint8List(4), size: 4);
      api.failNext = forbidden;
      await t.send('with file', files: [file]);
      expect(api.uploads, 1);
      await t.retry(t.messages.single);
      expect(api.uploads, 1);
      expect(t.messages.single.sendState, ChatSendState.sent);
    });

    test('a resend with a file whose bytes are gone shows failed, and never sends without the file', () async {
      hub.outboxAdd(ChatMessage(clientId: 'x', conversationId: conv, body: 'b', senderId: me, local: [ChatLocalFile(name: 'a.png')], createdAt: DateTime.utc(2026, 1, 1), sendState: ChatSendState.queued));
      final pending = hub.pendingFor(conv).single;
      expect(pending.sendState, ChatSendState.failed);
      expect(pending.error, ChatMessage.lostFileError);
      final t = opened()..messages = [pending];
      await t.resumeQueued();
      expect(api.sends, isEmpty);
    });

    test('another account on this device never sends the last one\'s outbox', () async {
      SharedPreferences.setMockInitialValues({'current_user': jsonEncode({'id': 9})});
      hub.outboxAdd(ChatMessage(clientId: 'y', conversationId: conv, body: 'mine', senderId: me, createdAt: DateTime.utc(2026, 1, 1)));
      await hub.ensureUser();
      expect(hub.myId, 9);
      expect(hub.debugOutbox, isEmpty);
    });

    test('a client id is unique across a burst', () {
      expect({for (var i = 0; i < 2000; i++) chatNewClientId()}.length, 2000);
    });
  });

  group('accounts', () {
    test('signing out wipes the outbox and drafts on the device, and the hub', () async {
      await hub.ensureUser();
      hub.setDraft(conv, 'a private draft');
      await hub.outboxAddAndSettle(ChatMessage(clientId: 'z', conversationId: conv, body: 'unsent', senderId: me, createdAt: DateTime.utc(2026, 1, 1)));
      hub.conversations.add(row(lastId: 1));
      final t = hub.acquire(conv)..loaded = true;
      final p = await SharedPreferences.getInstance();
      expect(p.getKeys().where((k) => k.startsWith('chat_')), isNotEmpty);
      await hub.signedOut();
      expect(p.getKeys().where((k) => k.startsWith('chat_outbox_') || k.startsWith('chat_drafts_')), isEmpty);
      expect(hub.conversations, isEmpty);
      expect(hub.debugOutbox, isEmpty);
      expect(hub.drafts, isEmpty);
      expect(hub.myId, 0);
      hub.setDraft(conv, 'closing screen writes this');
      expect(p.getKeys().where((k) => k.startsWith('chat_drafts_')), isEmpty);
      expect(identical(hub.acquire(conv), t), isFalse);
    });

    test('the outbox refuses a message of an account that is gone', () {
      hub.debugSetMyId(9);
      hub.outboxAdd(ChatMessage(clientId: 'old', conversationId: conv, body: 'x', senderId: me, createdAt: DateTime.utc(2026, 1, 1)));
      expect(hub.debugOutbox, isEmpty);
    });

    test('the account changing during an upload stops the send', () async {
      final t = opened();
      api.onUpload = () => hub.debugSetMyId(9);
      await t.send('secret', files: [ChatLocalFile(name: 'a.pdf', bytes: Uint8List(1), size: 1)]);
      expect(api.sends, isEmpty);
    });

    test('the account changing during a flush stops it, the new one sends nothing of the old', () async {
      for (final id in const ['a', 'b']) {
        hub.outboxAdd(ChatMessage(clientId: id, conversationId: conv + 1, body: id, senderId: me, createdAt: DateTime.utc(2026, 1, 1)));
      }
      api.onSend = () => hub.debugSetMyId(9);
      await hub.flushOutbox();
      expect(api.sends.length, lessThanOrEqualTo(1));
    });

    test('a disposed controller sends no more', () async {
      final t = opened();
      api.onUpload = t.dispose;
      await t.send('x', files: [ChatLocalFile(name: 'a.pdf', bytes: Uint8List(1), size: 1)]);
      expect(api.sends, isEmpty);
    });

    test('closing the screen during the first load starts no poller', () async {
      final t = hub.acquire(conv);
      api.onMessages = () => hub.release(t);
      await t.open();
      expect(t.debugPolling, isFalse);
      expect(t.visible, isFalse);
    });
  });

  group('events', () {
    test('a replayed message does not count twice, on a row loaded before or after it', () {
      hub.conversations.add(row(lastId: 10));
      final fresh = incoming(11);
      hub.onMessageEvent(eventOf(fresh));
      expect(hub.conversations.single.unread, 1);
      hub.onMessageEvent(eventOf(fresh)); // the stream replayed it
      expect(hub.conversations.single.unread, 1);
      // the list was loaded after this message arrived, then the stream replayed it
      hub.conversations
        ..clear()
        ..add(row(lastId: 11, unread: 1));
      hub.onMessageEvent(eventOf(fresh));
      expect(hub.conversations.single.unread, 1);
      expect(hub.conversations.single.last!.id, 11);
    });

    test('a replay does not rewind the preview', () {
      hub.conversations.add(row(lastId: 20));
      hub.onMessageEvent(eventOf(incoming(5)));
      expect(hub.conversations.single.last!.id, 20);
    });

    test('two out of order count both, and the preview ends on the newest', () {
      hub.conversations.add(row(lastId: 10));
      hub.onMessageEvent(eventOf(incoming(12)));
      hub.onMessageEvent(eventOf(incoming(11)));
      expect(hub.conversations.single.unread, 2);
      expect(hub.conversations.single.last!.id, 12);
    });

    test('a receipt never moves a tick back', () {
      final r = row(lastId: 1)..peerReadId = 9;
      hub.conversations.add(r);
      final t = opened()..conversation = (row()..peerReadId = 9);
      t.onReceipt(read: 3);
      expect(t.conversation!.peerReadId, 9);
    });

    test('my own message from another device is not unread', () {
      hub.conversations.add(row(lastId: 1));
      hub.onMessageEvent(eventOf(incoming(2, sender: me)));
      expect(hub.conversations.single.unread, 0);
    });

    test('a message clears the typing dots', () async {
      final t = opened();
      t.onTyping('Sara');
      hub.typing[conv] = 'Sara';
      hub.onMessageEvent(eventOf(incoming(3)));
      expect(t.typingName, isNull);
      expect(hub.typing.containsKey(conv), isFalse);
    });
  });

  group('one thread, one controller', () {
    test('acquire twice is one controller; closing one screen leaves the other live', () {
      final a = hub.acquire(conv);
      final b = hub.acquire(conv);
      expect(identical(a, b), isTrue);
      a.visible = true;
      hub.release(b);
      expect(a.visible, isTrue, reason: 'one screen still shows it');
      hub.release(a);
      expect(a.visible, isFalse);
      expect(identical(hub.acquire(conv), a), isTrue, reason: 'reopening keeps what was loaded');
    });

    test('a thread that is closed still takes in what arrives', () {
      final t = hub.acquire(conv)..loaded = true;
      t.visible = false;
      hub.onMessageEvent(eventOf(incoming(4)));
      expect(t.messages.single.id, 4);
    });

    test('a controller busy sending is not dropped from the LRU', () async {
      final t = hub.acquire(conv)..loaded = true;
      unawaited(t.send('slow'));
      hub.release(t);
      for (var i = 100; i < 120; i++) {
        hub.release(hub.acquire(i));
      }
      await Future<void>.delayed(Duration.zero);
      expect(api.bodies, ['slow']);
    });
  });

  group('reading', () {
    test('scrolled up: nothing is marked read and new messages are counted', () {
      final t = opened();
      t.setAtLatest(false);
      t.onIncoming(incoming(30));
      t.onIncoming(incoming(31));
      expect(api.reads, isEmpty);
      expect(t.newBelow, 2);
      t.setAtLatest(true);
      expect(t.newBelow, 0);
      expect(api.reads, [31]);
    });

    test('at the newest message: read at once', () {
      final t = opened();
      t.onIncoming(incoming(40));
      expect(api.reads, [40]);
      expect(t.newBelow, 0);
    });

    test('catching up asks from the last fetch, so a gap behind a live event is filled', () async {
      final t = opened()..messages = [incoming(10)];
      t.debugSynced(10);
      t.onIncoming(incoming(50)); // arrived live, messages 11..49 missed
      api.pageAfter = (after) => after == 10 ? [incoming(50), incoming(11)] : const [];
      t.catchUp();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(api.afters.first, 10);
      expect(t.messages.map((m) => m.id), [50, 11, 10]);
    });
  });

  group('keys', () {
    test('Enter sends on the web and desktop, not on a phone', () {
      expect(chatEnterSendsOn(TargetPlatform.windows), isTrue);
      expect(chatEnterSendsOn(TargetPlatform.macOS), isTrue);
      expect(chatEnterSendsOn(TargetPlatform.android), isFalse);
      expect(chatEnterSendsOn(TargetPlatform.iOS), isFalse);
    });

    testWidgets('Enter sends; Shift+Enter is a new line and sends nothing', (t) async {
      final text = TextEditingController(text: 'hello');
      final focus = FocusNode();
      var sent = 0;
      await t.pumpWidget(layoutHost(StatefulBuilder(builder: (_, _) => ChatComposerBar(controller: text, focusNode: focus, onChanged: (_) {}, onSend: () => sent++, enterSends: true)), scale: 1));
      focus.requestFocus();
      await t.pump();
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(sent, 0);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sent, 1);
      expect(focus.hasFocus, isTrue);
    });
  });

  group('screen', () {
    testWidgets('scrolled up, a new message leaves what is on screen alone and shows the count', (t) async {
      final thread = ChatThreadController(conv, hub: hub)
        ..loaded = true
        ..loading = false
        ..conversation = ChatConversation(id: conv, kind: 'direct', lastAt: DateTime.utc(2026, 1, 1), composer: ChatComposerState.open)
        ..messages = [for (var i = 60; i > 0; i--) incoming(i)];
      hub.registerThread(thread);
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(390, 700);
      addTearDown(() {
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      await t.pumpWidget(layoutHost(ChatThreadView(conversationId: conv, controller: thread), scale: 1));
      await t.pump();
      await t.drag(find.byType(CustomScrollView), const Offset(0, 500));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      final anchor = find.textContaining('hi 45', findRichText: true);
      expect(anchor, findsOneWidget);
      final before = t.getTopLeft(anchor).dy;
      thread.visible = true;
      thread.onIncoming(incoming(61));
      await t.pump();
      expect(t.getTopLeft(find.textContaining('hi 45', findRichText: true)).dy, before, reason: 'the list did not move');
      expect(find.byType(ChatJumpToLatest), findsOneWidget);
      expect(find.text('1'), findsWidgets);
      await t.tap(find.byType(ChatJumpToLatest));
      await t.pump(const Duration(milliseconds: 500));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('hi 61', findRichText: true), findsOneWidget);
      expect(find.byType(ChatJumpToLatest), findsNothing);
    });
  });
}

void unawaited(Future<void> f) {}
