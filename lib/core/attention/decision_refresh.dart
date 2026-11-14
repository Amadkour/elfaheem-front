// lib/core/attention/decision_refresh.dart
//
// After YOU approve / reject / decide something, every badge that counted it drops at once.
//
// The badge counts (GET /api/v1/me/attention, AttentionService) are computed from live state on the server, so the
// number is right the moment a request is decided — but the app only re-read it on a live event, a route push / pop
// (throttled to one per 15 s, so "open the list, approve, go back" inside 15 s never re-read it) or the slow poll.
// The server sends `attention_changed` to the OTHER reviewers (services/attention_fanout.py and the per-feature
// emits), never to the person who acted. So the app tells itself: ApiClient calls [DecisionRefresh.onSuccess] after
// every successful request, and a write to a decision route ([isDecisionRequest]) puts ONE local
// `attention_changed {tab: null, local: decision}` on the LiveEvents bus (coalesced: a bulk run is one event).
// Everything that holds such a count already listens to that event — AttentionService (the shell / home badges,
// reloaded at once, or right after a reload that was already running), the role homes (MeHome), the admin
// overview, the organization dashboard's store.
//
// Reads never trigger it, and neither does any write that is not a decision (autosaves, chat, check-ins), so the
// request budgets of opening / refreshing a home (test/perf/) are unchanged.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../utils/live_events.dart';

/// The last path segment(s) of a request that decides a waiting item. Same list as the server's
/// services/attention_fanout.py (which tells the other reviewers).
final RegExp _decisionVerb = RegExp(
    r'/(approve|reject|accept|decline|decide|resolve|deny|dismiss|edit|answer|respond|vote|bulk|bulk-approve|'
    r'accept-all|accept-proposal|admit|admit-all|resubmit|cancel|close|reopen|status|withdraw|recall|mark-paid|'
    r'suspend|reactivate|revoke)$');

/// Decisions sent as a plain write on the item: an org form response / complaint status (PUT), the platform
/// complaint status and a reply to it, the org dashboard's one-tap tasks, registrar verdicts, graduation sign-off.
final RegExp _decisionItem = RegExp(
    r'/(form-responses/\d+|complaints/\d+|complaints/\d+/replies|tasks/[^/]+/[^/]+|decisions/\d+/[a-z_-]+|'
    r'graduation/\d+)$');

/// True when a successful [method] on [path] decided (or changed the state of) something a badge counts.
bool isDecisionRequest(String method, String path) {
  final m = method.toUpperCase();
  if (m != 'POST' && m != 'PUT' && m != 'PATCH' && m != 'DELETE') return false;
  var p = path;
  final q = p.indexOf('?');
  if (q >= 0) p = p.substring(0, q);
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  if (!p.contains('/api/')) return false; // only the app's own API (never a presigned upload URL)
  return _decisionVerb.hasMatch(p) || _decisionItem.hasMatch(p);
}

class DecisionRefresh {
  DecisionRefresh._();

  /// Decisions closer together than this are one event (a bulk approve loop, approve + its follow-up write).
  static const coalesce = Duration(milliseconds: 250);

  /// The `local` value of the event's data (AttentionService reloads at once for it).
  static const marker = 'decision';

  static Timer? _pending;

  /// Off in tests that count requests and do not want the follow-up reloads.
  @visibleForTesting
  static bool enabled = true;

  /// Called by ApiClient for every successful response.
  static void onSuccess(String method, String path) {
    if (!enabled || !isDecisionRequest(method, path)) return;
    _pending?.cancel();
    _pending = Timer(coalesce, () {
      _pending = null;
      LiveEvents.instance.emit(LiveEvents.attentionChanged, {'tab': null, 'local': marker});
    });
  }

  /// True for the event [onSuccess] puts on the bus.
  static bool isLocal(LiveEvent e) => e.type == LiveEvents.attentionChanged && e.data['local'] == marker;
}
