// lib/core/guest_link_visit.dart — "a guest link's page is on screen" (D-840).
//
// The guest pages (a live room's guest link `/live/<token>`, a shared recording `/s/record/g_…`, a course video's
// guest link `/s/video/v_…`) call only public routes with `auth: false`. Something else in the app may still fire an
// authenticated call while they are open — a stale session left in this browser, a global service — and its 401 used
// to end in ApiClient's redirect to the login page, which threw the guest out of the video or the meeting. While at
// least one guest page holds a visit, ApiClient keeps the redirect to itself (the call still fails, quietly).
//
//   GuestLinkVisit.enter(this) in initState, GuestLinkVisit.leave(this) in dispose (idempotent per owner).
library;

import 'package:flutter/foundation.dart' show visibleForTesting;

class GuestLinkVisit {
  GuestLinkVisit._();

  static final Set<Object> _owners = <Object>{};

  /// A guest link's page is open: no redirect to the login page.
  static bool get active => _owners.isNotEmpty;

  static void enter(Object owner) => _owners.add(owner);

  static void leave(Object owner) => _owners.remove(owner);

  @visibleForTesting
  static void reset() => _owners.clear();
}
