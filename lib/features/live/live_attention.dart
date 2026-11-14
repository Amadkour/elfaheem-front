// lib/features/live/live_attention.dart
//
// What in the live room waits for the person's eyes (item 4 of the owner's device test 2026-10-29): unread chat,
// hands raised since the host last looked at the queue, lobby requests not seen yet, screen-share requests. The
// room feeds it the live facts; the bar's "More" button (phones), the chat button and the minimized box draw the
// counts. Looking at a thing ([markSeen]) clears its count; a hand that goes down and up again counts again.
// Pure (ChangeNotifier only), unit-tested in test/org/live_attention_test.dart.
library;

import 'package:flutter/foundation.dart' show ChangeNotifier;

enum LiveAttentionKind { chat, hands, lobby, share }

class LiveAttention extends ChangeNotifier {
  int _chat = 0;
  int _share = 0;
  Set<String> _hands = const {};
  final Set<String> _handsSeen = {};
  Set<String> _lobby = const {};
  final Set<String> _lobbySeen = {};
  final Set<LiveAttentionKind> _watching = {};
  bool _disposed = false;

  /// Unread chat messages (the chat controller already counts them while the chat is closed).
  void setChatUnread(int n) => _set(() => _chat = n < 0 ? 0 : n);

  /// Who has a hand up now.
  void setHands(Iterable<String> identities) => _set(() {
        _hands = identities.toSet();
        _handsSeen.retainAll(_hands); // lowered: a new raise counts again
        if (_watching.contains(LiveAttentionKind.hands)) _handsSeen.addAll(_hands);
      });

  /// The lobby's waiting request ids.
  void setLobby(Iterable<String> requestIds) => _set(() {
        _lobby = requestIds.toSet();
        _lobbySeen.retainAll(_lobby);
        if (_watching.contains(LiveAttentionKind.lobby)) _lobbySeen.addAll(_lobby);
      });

  /// Share requests waiting for an answer (they count until answered or expired).
  void setShareRequests(int n) => _set(() => _share = n < 0 ? 0 : n);

  /// The person looked at [kind]: its count is cleared (chat clears itself through the chat controller).
  void markSeen(LiveAttentionKind kind) => _set(() {
        switch (kind) {
          case LiveAttentionKind.hands:
            _handsSeen.addAll(_hands);
          case LiveAttentionKind.lobby:
            _lobbySeen.addAll(_lobby);
          case LiveAttentionKind.chat:
            _chat = 0;
          case LiveAttentionKind.share:
            break; // a request is answered, never just "seen"
        }
      });

  /// [kind] is on screen now (its panel / sheet is open): everything that arrives meanwhile is seen at once.
  void setWatching(LiveAttentionKind kind, bool on) => _set(() {
        on ? _watching.add(kind) : _watching.remove(kind);
        if (on) {
          if (kind == LiveAttentionKind.hands) _handsSeen.addAll(_hands);
          if (kind == LiveAttentionKind.lobby) _lobbySeen.addAll(_lobby);
        }
      });

  int count(LiveAttentionKind kind) => switch (kind) {
        LiveAttentionKind.chat => _chat,
        LiveAttentionKind.hands => _hands.difference(_handsSeen).length,
        LiveAttentionKind.lobby => _lobby.difference(_lobbySeen).length,
        LiveAttentionKind.share => _share,
      };

  int get total => LiveAttentionKind.values.fold(0, (s, k) => s + count(k));

  String _lastKey = '';

  void _set(void Function() change) {
    change();
    final key = '${count(LiveAttentionKind.chat)}/${count(LiveAttentionKind.hands)}/'
        '${count(LiveAttentionKind.lobby)}/${count(LiveAttentionKind.share)}';
    if (key == _lastKey) return;
    _lastKey = key;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
