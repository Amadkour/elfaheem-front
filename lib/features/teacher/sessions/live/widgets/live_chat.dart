// lib/features/teacher/sessions/live/widgets/live_chat.dart
//
// In-room text chat over LiveKit data messages (no server, so guests use it too).
//
// Wire format (LiveKit data packet, reliable, topic 'chat'):
//   {"type":"chat","id":"<uuid>","name":"Sara","identity":"42","text":"…","ts":1700000000000}
//
// RoomPage owns one [LiveChatController]: it gives it an [LiveChatController.onSend] that publishes the packet,
// feeds incoming packets into [LiveChatController.receive] and shows a [LiveChatPanel] as a right drawer (wide) or
// a bottom sheet (phones). The controller keeps at most [LiveChatController.maxMessages], sends at most one message
// per [LiveChatController.minInterval], de-duplicates by id and counts unread messages while the panel is closed.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:uuid/uuid.dart';

import 'live_palette.dart';
import 'participant_info.dart' show isGuestIdentity;

const kLiveChatTopic = 'chat';
const kLiveChatMaxChars = 500;

class LiveChatMessage {
  const LiveChatMessage({
    required this.id,
    required this.identity,
    required this.name,
    required this.text,
    required this.ts,
    this.mine = false,
  });
  final String id;
  final String identity;
  final String name;
  final String text;
  /// Milliseconds since epoch.
  final int ts;
  final bool mine;
  bool get isGuest => isGuestIdentity(identity);
}

class LiveChatController extends ChangeNotifier {
  LiveChatController({
    required this.localIdentity,
    this.onSend,
    this.maxMessages = 300,
    this.minInterval = const Duration(milliseconds: 500),
    String Function()? newId,
    DateTime Function()? now,
  })  : _newId = newId ?? (() => const Uuid().v4()),
        _now = now ?? DateTime.now;

  final String Function() localIdentity;
  /// Publishes the encoded packet (RoomPage: `localParticipant.publishData(..., reliable: true, topic: 'chat')`).
  Future<void> Function(List<int> bytes)? onSend;
  final int maxMessages;
  final Duration minInterval;
  final String Function() _newId;
  final DateTime Function() _now;

  final List<LiveChatMessage> _messages = [];
  final Set<String> _ids = {};
  int _unread = 0;
  bool _open = false;
  DateTime? _lastSent;
  bool _disposed = false;

  List<LiveChatMessage> get messages => List.unmodifiable(_messages);
  int get unread => _unread;
  bool get isOpen => _open;

  /// The panel tells the controller when it is visible: no unread count while open.
  void setOpen(bool open) {
    if (_open == open && (!open || _unread == 0)) return;
    _open = open;
    if (open) _unread = 0;
    _notify();
  }

  void markRead() {
    if (_unread == 0) return;
    _unread = 0;
    _notify();
  }

  static List<int> encode(LiveChatMessage m) => utf8.encode(jsonEncode({
        'type': 'chat',
        'id': m.id,
        'name': m.name,
        'identity': m.identity,
        'text': m.text,
        'ts': m.ts,
      }));

  /// Sends [text] as [name]; returns false when empty or rate-limited (one message per [minInterval]).
  bool send(String text, {required String name}) {
    var t = text.trim();
    if (t.isEmpty) return false;
    if (t.length > kLiveChatMaxChars) t = t.substring(0, kLiveChatMaxChars);
    final now = _now();
    if (_lastSent != null && now.difference(_lastSent!) < minInterval) return false;
    _lastSent = now;
    final m = LiveChatMessage(
      id: _newId(),
      identity: localIdentity(),
      name: name,
      text: t,
      ts: now.millisecondsSinceEpoch,
      mine: true,
    );
    add(m);
    final cb = onSend;
    if (cb != null) cb(encode(m)).catchError((_) {});
    return true;
  }

  /// Parses an incoming packet; returns true when it was a chat message. Unknown / malformed → false.
  bool receive(List<int> data, {String? senderIdentity, String? fallbackName}) {
    try {
      final m = jsonDecode(utf8.decode(data));
      if (m is! Map || m['type'] != 'chat') return false;
      var text = '${m['text'] ?? ''}'.trim();
      if (text.isEmpty) return true;
      if (text.length > kLiveChatMaxChars) text = text.substring(0, kLiveChatMaxChars);
      final identity = '${m['identity'] ?? senderIdentity ?? ''}';
      final rawName = '${m['name'] ?? ''}'.trim();
      add(LiveChatMessage(
        id: '${m['id'] ?? ''}'.isNotEmpty ? '${m['id']}' : _newId(),
        identity: identity,
        name: rawName.isNotEmpty ? rawName : (fallbackName ?? identity),
        text: text,
        ts: m['ts'] is num ? (m['ts'] as num).toInt() : _now().millisecondsSinceEpoch,
        mine: identity.isNotEmpty && identity == localIdentity(),
      ));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Appends a message (ignored when its id was already seen), trims to [maxMessages], counts it as unread when
  /// it is not mine and the panel is closed. Returns true when it was added.
  bool add(LiveChatMessage m) {
    if (!_ids.add(m.id)) return false;
    _messages.add(m);
    while (_messages.length > maxMessages) {
      _ids.remove(_messages.removeAt(0).id);
    }
    if (!m.mine && !_open) _unread++;
    _notify();
    return true;
  }

  /// Local only (the teacher's "Clear chat"); other participants keep their copy.
  void clear() {
    if (_messages.isEmpty && _unread == 0) return;
    _messages.clear();
    _ids.clear();
    _unread = 0;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// "8:30 AM" in the platform / organization zone and 12h/24h choice.
String liveChatTime(int ts) => AppTime.time(DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true));

/// Messages + input row. Dark, like the participant panel; fills whatever its parent gives it (a right drawer or
/// a bottom sheet). Own messages sit on the trailing side. The input never triggers the room's keyboard shortcuts:
/// the room's Focus handler ignores events while a text field has focus.
class LiveChatPanel extends StatefulWidget {
  const LiveChatPanel({
    super.key,
    required this.controller,
    required this.senderName,
    this.onClose,
    this.canClear = false,
    this.inputController,
  });

  final LiveChatController controller;
  final String senderName;
  final VoidCallback? onClose;
  /// Teacher: shows "Clear chat" (local).
  final bool canClear;
  final TextEditingController? inputController;

  @override
  State<LiveChatPanel> createState() => _LiveChatPanelState();
}

class _LiveChatPanelState extends State<LiveChatPanel> {
  static const _textHigh = LivePalette.textHigh;
  static const _textMid = LivePalette.textMid;
  static const _textLow = LivePalette.textLow;
  static const _glassBdr = LivePalette.glassBorder;
  static const _glass10 = LivePalette.glass;

  late final TextEditingController _input = widget.inputController ?? TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'live_chat_input');
  int _seen = 0;
  bool _limitHit = false;

  @override
  void initState() {
    super.initState();
    widget.controller.setOpen(true);
    widget.controller.addListener(_onChanged);
    _seen = widget.controller.messages.length;
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    widget.controller.setOpen(false);
    if (widget.inputController == null) _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    final n = widget.controller.messages.length;
    if (n != _seen) {
      _seen = n;
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
    }
    setState(() {});
  }

  void _jumpToEnd() {
    if (!mounted || !_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  void _send() {
    final ok = widget.controller.send(_input.text, name: widget.senderName);
    if (ok) {
      _input.clear();
      _limitHit = false;
    } else if (_input.text.trim().isNotEmpty) {
      _limitHit = true; // rate-limited: keep the text, show the hint
    }
    setState(() {});
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final msgs = widget.controller.messages;
    return Material(
      color: LivePalette.surfaceHi,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Header
        Container(
          key: const ValueKey('live_chat.header'),
          padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 8, 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _glassBdr))),
          child: Row(children: [
            Icon(Icons.chat_bubble_outline_rounded, color: LivePalette.accent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('lr_chat'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontFamily: 'tajawal', color: _textHigh, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            if (widget.canClear && msgs.isNotEmpty)
              IconButton(
                key: const ValueKey('live_chat.clear'),
                tooltip: 'lr_clear_chat'.tr,
                onPressed: widget.controller.clear,
                icon: const Icon(Icons.delete_sweep_outlined, size: 20, color: _textMid),
              ),
            if (widget.onClose != null)
              IconButton(
                key: const ValueKey('live_chat.close'),
                tooltip: 'lr_close'.tr,
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded, size: 18, color: _textMid),
              ),
          ]),
        ),

        // Messages
        Expanded(
          child: msgs.isEmpty
              ? Center(
                  key: const ValueKey('live_chat.empty'),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.forum_outlined, color: _textLow, size: 32),
                      const SizedBox(height: 10),
                      Text('lr_chat_empty'.tr,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontFamily: 'tajawal', color: _textLow, fontSize: 13)),
                    ]),
                  ),
                )
              : ListView.builder(
                  key: const ValueKey('live_chat.list'),
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final m = msgs[i];
                    final prev = i > 0 ? msgs[i - 1] : null;
                    final grouped = prev != null && prev.identity == m.identity && (m.ts - prev.ts) < 120000;
                    return _Bubble(message: m, showName: !grouped);
                  },
                ),
        ),

        // Input row
        Container(
          key: const ValueKey('live_chat.input_row'),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: _glassBdr))),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_limitHit)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('lr_chat_slow_down'.tr,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'tajawal', fontSize: 11, color: LivePalette.warning)),
              ),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('live_chat.input'),
                  controller: _input,
                  focusNode: _focus,
                  maxLength: kLiveChatMaxChars,
                  maxLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  style: const TextStyle(fontFamily: 'tajawal', color: _textHigh, fontSize: 14),
                  cursorColor: LivePalette.accent,
                  decoration: InputDecoration(
                    counterText: '',
                    isDense: true,
                    hintText: 'lr_chat_hint'.tr,
                    hintStyle: const TextStyle(fontFamily: 'tajawal', color: _textLow, fontSize: 13),
                    filled: true,
                    fillColor: _glass10,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _glassBdr)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _glassBdr)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: LivePalette.accent.withValues(alpha: 0.8))),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                height: 44,
                child: Material(
                  color: LivePalette.accent,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    key: const ValueKey('live_chat.send'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: _send,
                    child: Semantics(
                      button: true,
                      label: 'lr_send'.tr,
                      child: const Icon(Icons.send_rounded, color: LivePalette.textHigh, size: 20),
                    ),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.showName});
  final LiveChatMessage message;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final mine = m.mine;
    final accent = LivePalette.accent;
    final fill = mine ? accent.withValues(alpha: 0.26) : LivePalette.glass;
    final border = mine ? accent.withValues(alpha: 0.5) : LivePalette.glassBorder;
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
            margin: EdgeInsets.only(top: showName ? 8 : 2),
            padding: const EdgeInsets.fromLTRB(11, 7, 11, 7),
            decoration: BoxDecoration(
              color: fill,
              border: Border.all(color: border),
              borderRadius: BorderRadiusDirectional.only(
                topStart: const Radius.circular(14),
                topEnd: const Radius.circular(14),
                bottomStart: Radius.circular(mine ? 14 : 4),
                bottomEnd: Radius.circular(mine ? 4 : 14),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showName && !mine)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                        child: Text(
                          m.name.isNotEmpty ? m.name : m.identity,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: 'tajawal', fontSize: 11, fontWeight: FontWeight.w800, color: accent),
                        ),
                      ),
                      if (m.isGuest) ...[
                        const SizedBox(width: 5),
                        Text('lr_guest'.tr,
                            style: TextStyle(
                                fontFamily: 'tajawal',
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: LivePalette.warning)),
                      ],
                    ]),
                  ),
                Text(m.text,
                    style: const TextStyle(fontFamily: 'tajawal', fontSize: 13.5, height: 1.35, color: LivePalette.textHigh)),
                const SizedBox(height: 2),
                Text(liveChatTime(m.ts),
                    style: const TextStyle(fontFamily: 'tajawal', fontSize: 9.5, color: LivePalette.textSoft)),
              ],
            ),
        ),
      ),
    );
  }
}
