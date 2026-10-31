// lib/core/inbox_badge.dart
//
// The inbox's To do count, app-wide, for the bell: the bell and the home's inbox entry count only what is
// ACTIONABLE — the to-dos plus the unread notifications (announcements and offers never inflate them). The unread
// count is NotificationsProvider's; this keeps the other half, fed by the answers the app already gets (no request
// of its own): GET /me/home's `inbox_counts.todo` (MeHomeService) and the whole inbox page's GET /me/inbox
// (InboxController, never an organization's slice). A role that loads neither (the admins) keeps 0.
library;

import 'package:flutter/foundation.dart';

/// To-dos plus unread notifications: the one count the bell, the inbox entry and the inbox page carry.
int inboxActionableCount({required int todo, required int unread}) => (todo < 0 ? 0 : todo) + (unread < 0 ? 0 : unread);

class InboxBadge extends ChangeNotifier {
  InboxBadge._();

  static final InboxBadge instance = InboxBadge._();

  int _todo = 0;

  /// The latest known count of the inbox's To do tab (the whole inbox, every organization).
  int get todo => _todo;

  void setTodo(int n) {
    final v = n < 0 ? 0 : n;
    if (v == _todo) return;
    _todo = v;
    notifyListeners();
  }

  /// Logout.
  void clear() => setTodo(0);
}
