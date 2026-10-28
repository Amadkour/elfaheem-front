// lib/features/teacher/sessions/live/widgets/live_reactions.dart
//
// Live emoji reactions for the LiveKit room: every participant (teacher and students) can send one; everyone sees it
// rise and fade on the trailing edge of the video stage.
//
// Wire format (LiveKit data packet, lossy, topic 'reaction'):
//   {"type":"reaction","emoji":"👍","name":"Sara"}
//
// RoomPage owns one [LiveReactionsController]; it gives it a [LiveReactionsController.onSend] that publishes the
// packet, feeds incoming packets into [LiveReactionsController.receive], and stacks a [LiveReactionsOverlay] on the
// video area. The controls bar's reaction button calls [LiveReactionsController.togglePicker].
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';

import 'live_palette.dart';

const kLiveReactionTopic = 'reaction';
const kLiveReactionEmojis = <String>['👍', '❤️', '😂', '👏', '🎉', '😮'];

class LiveReaction {
  LiveReaction({required this.id, required this.emoji, required this.name, required this.seed});
  final int id;
  final String emoji;
  final String name;
  /// 0..1, picks the lane / wobble so simultaneous bubbles don't stack exactly.
  final double seed;
}

class LiveReactionsController extends ChangeNotifier {
  LiveReactionsController({this.onSend, this.maxBubbles = 30, this.minInterval = const Duration(milliseconds: 400)});

  /// Publishes the encoded packet (RoomPage: `localParticipant.publishData(..., reliable: false, topic: 'reaction')`).
  Future<void> Function(List<int> bytes)? onSend;
  final int maxBubbles;
  final Duration minInterval;

  final _rand = math.Random();
  final List<LiveReaction> _bubbles = [];
  int _nextId = 0;
  DateTime? _lastSent;
  bool _pickerOpen = false;
  bool _disposed = false;

  List<LiveReaction> get bubbles => List.unmodifiable(_bubbles);
  bool get pickerOpen => _pickerOpen;

  void togglePicker() {
    _pickerOpen = !_pickerOpen;
    _notify();
  }

  void closePicker() {
    if (!_pickerOpen) return;
    _pickerOpen = false;
    _notify();
  }

  static List<int> encode(String emoji, String name) =>
      utf8.encode(jsonEncode({'type': 'reaction', 'emoji': emoji, 'name': name}));

  /// Sends [emoji] as [name] and shows it locally. Returns false when rate-limited (max one per [minInterval]).
  bool send(String emoji, String name) {
    final now = DateTime.now();
    if (_lastSent != null && now.difference(_lastSent!) < minInterval) return false;
    _lastSent = now;
    add(emoji, name);
    final cb = onSend;
    if (cb != null) {
      cb(encode(emoji, name)).catchError((_) {}); // lossy by design: a dropped reaction is fine
    }
    return true;
  }

  /// Parses an incoming packet; returns true when it was a reaction (and shows it). [fallbackName] is the
  /// sender's LiveKit name, used when the payload has none.
  bool receive(List<int> data, {String? fallbackName}) {
    try {
      final m = jsonDecode(utf8.decode(data));
      if (m is! Map || m['type'] != 'reaction') return false;
      final emoji = '${m['emoji'] ?? ''}';
      // Only the known set: never render arbitrary text pushed by a peer.
      if (!kLiveReactionEmojis.contains(emoji)) return true;
      final raw = '${m['name'] ?? ''}'.trim();
      add(emoji, raw.isNotEmpty ? raw : (fallbackName ?? ''));
      return true;
    } catch (_) {
      return false;
    }
  }

  void add(String emoji, String name) {
    final n = name.length > 24 ? '${name.substring(0, 23)}…' : name;
    _bubbles.add(LiveReaction(id: _nextId++, emoji: emoji, name: n, seed: _rand.nextDouble()));
    while (_bubbles.length > maxBubbles) {
      _bubbles.removeAt(0);
    }
    _notify();
  }

  void remove(int id) {
    final before = _bubbles.length;
    _bubbles.removeWhere((b) => b.id == id);
    if (_bubbles.length != before) _notify();
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

/// Fills its parent (put it in the video-area Stack). Bubbles are pointer-transparent; the picker (when open) sits
/// at the bottom-centre and is tappable.
class LiveReactionsOverlay extends StatelessWidget {
  const LiveReactionsOverlay({super.key, required this.controller, required this.senderName});
  final LiveReactionsController controller;
  /// The local participant's display name, sent with every reaction.
  final String senderName;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, c) {
            final h = c.maxHeight.isFinite ? c.maxHeight : 400.0;
            final w = c.maxWidth.isFinite ? c.maxWidth : 320.0;
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                IgnorePointer(
                  child: Stack(
                    children: [
                      for (final b in controller.bubbles)
                        _Bubble(
                          key: ValueKey('live_reaction.${b.id}'),
                          reaction: b,
                          travel: math.max(80.0, h * 0.6),
                          laneWidth: math.min(90.0, w * 0.25),
                          onDone: () => controller.remove(b.id),
                        ),
                    ],
                  ),
                ),
                if (controller.pickerOpen)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 12,
                    child: Center(
                      child: LiveReactionPicker(
                        onPick: (e) => controller.send(e, senderName),
                        onClose: controller.closePicker,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({super.key, required this.reaction, required this.travel, required this.laneWidth, required this.onDone});
  final LiveReaction reaction;
  final double travel;
  final double laneWidth;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final seed = reaction.seed;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 2400 + (seed * 900).round()),
      curve: Curves.easeOut,
      onEnd: onDone,
      builder: (context, t, child) {
        final opacity = t < 0.12 ? t / 0.12 : (t > 0.7 ? (1 - t) / 0.3 : 1.0);
        final wobble = math.sin((t * 3 + seed) * math.pi * 2) * 8;
        final scale = 0.6 + 0.4 * Curves.elasticOut.transform((t * 4).clamp(0.0, 1.0));
        return PositionedDirectional(
          end: 12 + seed * laneWidth + wobble,
          bottom: 56 + t * travel,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(reaction.emoji, style: const TextStyle(fontSize: 30, height: 1.1)),
            if (reaction.name.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: LivePalette.shade(0.45),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  reaction.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9, color: LivePalette.textHigh, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A compact pill of emoji buttons. Scrolls horizontally if it can't fit (very narrow / large text).
class LiveReactionPicker extends StatelessWidget {
  const LiveReactionPicker({super.key, required this.onPick, this.onClose, this.emojis = kLiveReactionEmojis});
  final ValueChanged<String> onPick;
  final VoidCallback? onClose;
  final List<String> emojis;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'lr_reactions'.tr,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: LivePalette.surfaceHi.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: LivePalette.glassBorder),
            boxShadow: [BoxShadow(color: LivePalette.shade(0.4), blurRadius: 18)],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in emojis)
                  InkResponse(
                    key: ValueKey('live_reaction.pick.$e'),
                    radius: 24,
                    onTap: () => onPick(e),
                    child: Semantics(
                      button: true,
                      label: e,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Text(e, style: const TextStyle(fontSize: 26, height: 1.2)),
                      ),
                    ),
                  ),
                if (onClose != null)
                  IconButton(
                    key: const ValueKey('live_reaction.close'),
                    tooltip: 'lr_close'.tr,
                    icon: const Icon(Icons.close_rounded, color: LivePalette.textMid, size: 20),
                    onPressed: onClose,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
