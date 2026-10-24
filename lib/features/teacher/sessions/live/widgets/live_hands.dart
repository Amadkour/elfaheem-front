// lib/features/teacher/sessions/live/widgets/live_hands.dart
//
// Hand-raise queue for the LiveKit room. Students and guests toggle "Raise hand" in the control bar; the teacher
// sees an ordered queue (first raised first) and can lower a hand or, for a guest, allow them to speak.
//
// Wire format (LiveKit data packet, reliable, topic 'hand'):
//   {"type":"hand","up":true,"name":"Sara","identity":"42","ts":1700000000000}   raise
//   {"type":"hand","up":false,"identity":"42"}                                     lower (own, or by the teacher)
//
// RoomPage owns one [LiveHandsController]: it gives it an [LiveHandsController.onSend] that publishes the packet,
// feeds incoming packets into [LiveHandsController.receive], drops a participant on disconnect and stacks a
// [LiveHandsPanel] (teacher) or shows the raiser's [LiveHandBadge] on tiles. Pure logic (ordering, dedupe, drop,
// own-state reset) is in the controller so it can be unit-tested without a Room.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show trp;

import 'live_palette.dart';
import 'participant_info.dart' show isGuestIdentity;

const kLiveHandTopic = 'hand';

class LiveHand {
  const LiveHand({required this.identity, required this.name, required this.ts});
  final String identity;
  final String name;
  /// Milliseconds since epoch (sender's clock) — the queue order.
  final int ts;
  bool get isGuest => isGuestIdentity(identity);
}

class LiveHandsController extends ChangeNotifier {
  LiveHandsController({required this.localIdentity, this.onSend});

  /// The local participant's LiveKit identity (RoomPage: `room.localParticipant?.identity`).
  final String Function() localIdentity;

  /// Publishes the encoded packet (RoomPage: `localParticipant.publishData(..., reliable: true, topic: 'hand')`).
  Future<void> Function(List<int> bytes)? onSend;

  final List<LiveHand> _hands = [];
  bool _disposed = false;

  /// Raised hands, oldest first.
  List<LiveHand> get hands => List.unmodifiable(_hands);
  int get count => _hands.length;
  bool get localUp => isUp(localIdentity());
  bool isUp(String identity) => _hands.any((h) => h.identity == identity);

  static List<int> encode({required bool up, required String identity, String? name, int? ts}) =>
      utf8.encode(jsonEncode({
        'type': 'hand',
        'up': up,
        'identity': identity,
        if (up) 'name': name ?? '',
        if (up) 'ts': ts ?? DateTime.now().millisecondsSinceEpoch,
      }));

  /// Adds (or ignores a duplicate of) a raised hand and keeps the queue ordered by [LiveHand.ts].
  /// Returns true when the queue changed.
  bool add(LiveHand hand) {
    if (hand.identity.isEmpty || isUp(hand.identity)) return false;
    _hands.add(hand);
    _hands.sort((a, b) => a.ts.compareTo(b.ts));
    _notify();
    return true;
  }

  /// Removes [identity] from the queue (no packet). Returns true when it was there.
  bool remove(String identity) {
    final before = _hands.length;
    _hands.removeWhere((h) => h.identity == identity);
    if (_hands.length == before) return false;
    _notify();
    return true;
  }

  /// Raise / lower the local participant's hand and tell the room.
  void setLocal(bool up, {required String name}) {
    final id = localIdentity();
    if (id.isEmpty) return;
    if (up) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      if (!add(LiveHand(identity: id, name: name, ts: ts))) return;
      _send(encode(up: true, identity: id, name: name, ts: ts));
    } else {
      if (!remove(id)) return;
      _send(encode(up: false, identity: id));
    }
  }

  void toggleLocal({required String name}) => setLocal(!localUp, name: name);

  /// Re-announces the local hand (for someone who joined after it was raised).
  void reannounceLocal() {
    final id = localIdentity();
    final mine = _hands.where((h) => h.identity == id).toList();
    if (mine.isEmpty) return;
    _send(encode(up: true, identity: id, name: mine.first.name, ts: mine.first.ts));
  }

  /// Teacher: lowers someone's hand locally and tells everyone (the raiser's toggle resets on receipt).
  void lower(String identity) {
    if (!remove(identity)) return;
    _send(encode(up: false, identity: identity));
  }

  /// A participant left: their hand goes with them.
  void drop(String identity) => remove(identity);

  /// Parses an incoming packet; returns true when it was a hand packet. [senderIdentity] / [fallbackName] come
  /// from the LiveKit participant and are used when the payload is incomplete.
  bool receive(List<int> data, {String? senderIdentity, String? fallbackName}) {
    try {
      final m = jsonDecode(utf8.decode(data));
      if (m is! Map || m['type'] != 'hand') return false;
      final identity = '${m['identity'] ?? senderIdentity ?? ''}';
      if (identity.isEmpty) return true;
      if (m['up'] == true) {
        final raw = '${m['name'] ?? ''}'.trim();
        final ts = m['ts'] is num ? (m['ts'] as num).toInt() : DateTime.now().millisecondsSinceEpoch;
        add(LiveHand(identity: identity, name: raw.isNotEmpty ? raw : (fallbackName ?? identity), ts: ts));
      } else {
        // A lower for the local identity (sent by the teacher) resets the local toggle too, since the local
        // hand is simply "my identity is in the queue".
        remove(identity);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  void clear() {
    if (_hands.isEmpty) return;
    _hands.clear();
    _notify();
  }

  void _send(List<int> bytes) {
    final cb = onSend;
    if (cb != null) cb(bytes).catchError((_) {});
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

/// Small ✋ chip for a tile (and the raiser's own PiP).
class LiveHandBadge extends StatelessWidget {
  const LiveHandBadge({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = LivePalette.warning;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 8, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(c.withValues(alpha: 0.25), Colors.black.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.7)),
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.3), blurRadius: 10)],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('✋', style: TextStyle(fontSize: compact ? 11 : 14, height: 1.1)),
        if (!compact) ...[
          const SizedBox(width: 4),
          Text('lr_hand_raised'.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'tajawal', fontSize: 10, fontWeight: FontWeight.w800, color: c)),
        ],
      ]),
    );
  }
}

/// The teacher's queue (also fine read-only for anyone). Dark, matching the participant panel; sizes itself to
/// its parent (a 320 px drawer or a bottom sheet) and never overflows: the name column is the only flexible one.
class LiveHandsPanel extends StatelessWidget {
  const LiveHandsPanel({
    super.key,
    required this.controller,
    required this.isTeacher,
    this.onLower,
    this.onAllowSpeak,
    this.onClose,
    this.busyIdentity,
  });

  final LiveHandsController controller;
  final bool isTeacher;
  /// Teacher: lower this participant's hand (RoomPage calls `controller.lower`).
  final ValueChanged<String>? onLower;
  /// Teacher, guests only: `POST …/guests/{identity}/allow-speak`.
  final ValueChanged<String>? onAllowSpeak;
  final VoidCallback? onClose;
  /// Identity whose allow-speak call is in flight (shows a spinner on that row).
  final String? busyIdentity;

  static const _textHigh = Color(0xFFFFFFFF);
  static const _textMid = Color(0xB3FFFFFF);
  static const _textLow = Color(0x66FFFFFF);
  static const _glassBdr = Color(0x30FFFFFF);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LivePalette.surfaceHi,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final hands = controller.hands;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              key: const ValueKey('live_hands.header'),
              padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 8, 12),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _glassBdr))),
              child: Row(children: [
                const Text('✋', style: TextStyle(fontSize: 18, height: 1.1)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    trp('lr_raised_hands_n', {'n': '${hands.length}'}),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'tajawal', color: _textHigh, fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    key: const ValueKey('live_hands.close'),
                    tooltip: 'lr_close'.tr,
                    visualDensity: VisualDensity.compact,
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, size: 18, color: _textMid),
                  ),
              ]),
            ),
            Flexible(
              child: hands.isEmpty
                  ? Padding(
                      key: const ValueKey('live_hands.empty'),
                      padding: const EdgeInsets.fromLTRB(24, 36, 24, 36),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.back_hand_outlined, color: _textLow, size: 32),
                        const SizedBox(height: 10),
                        Text('lr_no_hands'.tr,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontFamily: 'tajawal', color: _textLow, fontSize: 13)),
                      ]),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: hands.length,
                      itemBuilder: (_, i) => _HandRow(
                        index: i + 1,
                        hand: hands[i],
                        isTeacher: isTeacher,
                        busy: busyIdentity == hands[i].identity,
                        onLower: onLower,
                        onAllowSpeak: onAllowSpeak,
                      ),
                    ),
            ),
          ]);
        },
      ),
    );
  }
}

class _HandRow extends StatelessWidget {
  const _HandRow({
    required this.index,
    required this.hand,
    required this.isTeacher,
    required this.busy,
    this.onLower,
    this.onAllowSpeak,
  });

  final int index;
  final LiveHand hand;
  final bool isTeacher;
  final bool busy;
  final ValueChanged<String>? onLower;
  final ValueChanged<String>? onAllowSpeak;

  String _since() {
    final secs = ((DateTime.now().millisecondsSinceEpoch - hand.ts) / 1000).round();
    if (secs < 60) return 'lr_just_now'.tr;
    return trp('lr_duration_m', {'m': '${secs ~/ 60}'});
  }

  @override
  Widget build(BuildContext context) {
    final warn = LivePalette.warning;
    final name = hand.name.isNotEmpty ? hand.name : hand.identity;
    return Container(
      key: ValueKey('live_hands.row.${hand.identity}'),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 6, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Row(children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: warn.withValues(alpha: index == 1 ? 0.28 : 0.12),
            border: Border.all(color: warn.withValues(alpha: index == 1 ? 0.7 : 0.3)),
          ),
          child: Text('$index',
              style: TextStyle(fontFamily: 'tajawal', fontSize: 11, fontWeight: FontWeight.w800, color: warn)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: LiveHandsPanel._textHigh, fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 2),
            Row(children: [
              if (hand.isGuest) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: warn.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: warn.withValues(alpha: 0.3)),
                  ),
                  child: Text('lr_guest'.tr,
                      style: TextStyle(fontFamily: 'tajawal', color: warn, fontSize: 9, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(_since(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'tajawal', color: LiveHandsPanel._textLow, fontSize: 10)),
              ),
            ]),
          ]),
        ),
        if (isTeacher) ...[
          if (hand.isGuest && onAllowSpeak != null)
            busy
                ? const SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(
                        child: SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))))
                : IconButton(
                    key: ValueKey('live_hands.allow.${hand.identity}'),
                    tooltip: 'lr_allow_speak'.tr,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    padding: EdgeInsets.zero,
                    onPressed: () => onAllowSpeak!(hand.identity),
                    icon: Icon(Icons.mic_rounded, size: 18, color: LivePalette.success),
                  ),
          if (onLower != null)
            IconButton(
              key: ValueKey('live_hands.lower.${hand.identity}'),
              tooltip: 'lr_lower_hand'.tr,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
              onPressed: () => onLower!(hand.identity),
              icon: const Icon(Icons.do_not_touch_outlined, size: 18, color: LiveHandsPanel._textMid),
            ),
        ],
      ]),
    );
  }
}
