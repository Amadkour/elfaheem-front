// The live room's attention counts (lib/features/shared/live/live_attention.dart) and the phone pill's "More"
// badge (live_control_bar.dart liveMoreBadge).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/live/live_attention.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_control_bar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat, hands, lobby and share requests add up; looking clears them', () {
    final a = LiveAttention();
    var notified = 0;
    a.addListener(() => notified++);
    a.setChatUnread(3);
    a.setHands(['s1', 's2']);
    a.setLobby(['r1']);
    a.setShareRequests(1);
    expect(a.total, 7);
    expect(a.count(LiveAttentionKind.hands), 2);

    a.markSeen(LiveAttentionKind.hands);
    expect(a.count(LiveAttentionKind.hands), 0);
    a.setHands(['s1', 's2', 's3']);
    expect(a.count(LiveAttentionKind.hands), 1, reason: 'only the new hand');
    a.setHands(['s2', 's3']); // s1 lowered
    a.setHands(['s1', 's2', 's3']); // … and raised again
    expect(a.count(LiveAttentionKind.hands), 2, reason: 'a hand raised again counts again');

    a.markSeen(LiveAttentionKind.lobby);
    expect(a.count(LiveAttentionKind.lobby), 0);
    a.markSeen(LiveAttentionKind.share);
    expect(a.count(LiveAttentionKind.share), 1, reason: 'a request is answered, not seen');
    a.setChatUnread(0);
    expect(a.total, 3);

    final before = notified;
    a.setChatUnread(0);
    a.setLobby(['r1']);
    expect(notified, before, reason: 'no change, no notification');
    a.dispose();
  });

  test('while a panel is open, what arrives is seen at once', () {
    final a = LiveAttention();
    a.setWatching(LiveAttentionKind.lobby, true);
    a.setLobby(['r1', 'r2']);
    expect(a.count(LiveAttentionKind.lobby), 0);
    a.setWatching(LiveAttentionKind.lobby, false);
    a.setLobby(['r1', 'r2', 'r3']);
    expect(a.count(LiveAttentionKind.lobby), 1);
    a.setWatching(LiveAttentionKind.hands, true);
    a.setHands(['s1']);
    expect(a.count(LiveAttentionKind.hands), 0);
    a.dispose();
  });

  test('the "More" badge sums what waits inside the sheet', () {
    const chat = LiveControlAction(icon: Icons.chat_bubble_rounded, label: 'Chat', badge: 2);
    const hands = LiveControlAction(icon: Icons.back_hand_rounded, label: 'Hands', badge: 5, attention: 1);
    const speaker = LiveControlAction(icon: Icons.speaker_phone_rounded, label: 'Speaker');
    expect(liveMoreBadge(const [chat, hands, speaker]), 3, reason: 'hands up: only the new one counts');
    expect(liveMoreBadge(const [speaker]), 0);
  });
}
