// lib/core/attention/attention_service.dart
//
// Badge counts for every tab, from ONE server call: GET /api/v1/me/attention
// (back: services/attention_service.py). The server computes every item from live state, so an
// item is gone as soon as its problem is fixed; this service only keeps the last answer.
//
//   AttentionService.instance.count(AttentionTabs.orgPeople, orgId: 12)   → badge number
//   AttentionService.instance.items(AttentionTabs.home)                    → items with deep links
//   AttentionService.instance.refresh()                                     → reload now
//
// Refreshes: on the live event `attention_changed` (the SSE stream / a silent push, LiveEventsClient) and the
// `*_updated` events, every 60 s as a fallback (5 min while the stream is connected — the stream carries the change;
// the slow poll only catches what it missed), never while the app is in the background (attentionPollEvery), on app resume, on
// route push/return (TopRouteObserver → onRouteChanged, throttled) and — at once — after this user's own
// approve / reject / decide call succeeded (decision_refresh.dart → onDecision; the server tells only the others).
// Listen with ListenableBuilder(listenable: AttentionService.instance, …) (or AttentionBadge); polling (and the
// live stream it binds) runs only while something listens.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../utils/live_events.dart';
import '../api_client.dart';
import '../live/live_events_client.dart';
import 'decision_refresh.dart';

/// When a live event that changes the badges should reload them: [Duration.zero] = now; otherwise after the delay
/// (a reload ran less than [gap] ago, or is running — its answer may predate the change). Dropping such an event
/// instead left the badge stale until the next poll, 5 min while the stream is connected.
Duration attentionEventDelay({DateTime? last, required DateTime now, required bool running, Duration gap = const Duration(seconds: 5)}) {
  final since = last == null ? null : now.difference(last);
  if (!running && (since == null || since >= gap)) return Duration.zero;
  if (since == null || since >= gap || since.isNegative) return gap;
  return gap - since;
}

/// How often the badges are polled: null = not at all (the app is in the background: the stream is closed there too,
/// and a 60 s poll behind the person's back only costs battery; resuming reloads at once); 5 min while the live stream
/// is connected (it brings every change, the poll is only the safety net); 60 s without it.
Duration? attentionPollEvery({required bool inFront, required bool streamConnected}) {
  if (!inFront) return null;
  return streamConnected ? AttentionService.pollEveryLive : AttentionService.pollEvery;
}

/// Stable tab keys (same list as the server's TABS). Add new ones on both sides.
class AttentionTabs {
  AttentionTabs._();

  /// Personal to-do list (inbox "To do": forms, availability, terms, platform requirements, exams, replies).
  static const home = 'home';
  /// Unread complaint replies (students, teachers, parents).
  static const profile = 'profile';
  static const parentLink = 'parent.link';
  static const parentAlerts = 'parent.alerts';
  static const adminSupport = 'admin.support';
  static const adminFinance = 'admin.finance';
  static const orgPeople = 'org.people';
  /// Department choices, registrar decisions and auto-create suggestions (drafts to approve).
  static const orgAcademics = 'org.academics';
  static const orgTimetable = 'org.timetable';
  static const orgServices = 'org.services';
  static const orgSettings = 'org.settings';
  /// Admissions & appointments: cases the viewer can act on (D-1200, server TABS key `org_onboarding`).
  static const orgOnboarding = 'org_onboarding';
  /// The high-priority items of the teacher's automatic to-do list (D-303, services/teacher_todo_service.py).
  static const teacherTodo = 'teacher.todo';

  /// Unread messages of Alfaheem Messages (D-330, services/chat).
  static const chat = 'chat';

  /// Org dashboard section key ('people', 'academics', …) → tab key.
  static const orgSection = <String, String>{
    'people': orgPeople,
    'academics': orgAcademics,
    'timetable': orgTimetable,
    'services': orgServices,
    'settings': orgSettings,
  };

  /// An ITEM key of the `home` tab (not a tab): my pending organization invitations (C7); the dialog in
  /// features/org/org_invitation_prompt.dart reads it. Same string as the server's attention key.
  static const orgInvitationsItem = 'org_invitations';

  /// New accounts waiting for a platform admin's approval (D-1121).
  static const adminUsers = 'admin.users';

  static const all = [home, profile, parentLink, parentAlerts, adminSupport, adminFinance, orgPeople, orgAcademics,
    orgTimetable, orgServices, orgSettings, orgOnboarding, teacherTodo, chat, adminUsers];
}

class AttentionItem {
  AttentionItem(Map<String, dynamic> m)
      : raw = m,
        key = '${m['key'] ?? ''}',
        kind = '${m['kind'] ?? ''}',
        tab = '${m['tab'] ?? ''}',
        orgId = m['org_id'] == null ? null : int.tryParse('${m['org_id']}'),
        count = int.tryParse('${m['count'] ?? 1}') ?? 1,
        titleAr = '${m['title'] ?? ''}',
        titleEn = '${m['title_en'] ?? m['title'] ?? ''}',
        subtitle = m['subtitle']?.toString(),
        severity = '${m['severity'] ?? 'info'}',
        route = '${m['route'] ?? ''}',
        entityId = m['entity_id'] == null ? null : int.tryParse('${m['entity_id']}'),
        action = m['action'] is Map ? Map<String, dynamic>.from(m['action'] as Map) : const {};

  final Map<String, dynamic> raw;
  final String key, kind, tab, titleAr, titleEn, severity, route;
  final String? subtitle;
  final int? orgId, entityId;
  final int count;
  final Map<String, dynamic> action;

  String get actionType => '${action['type'] ?? ''}';
  bool get isSuggestion => kind == 'suggestion';
}

/// Where the org dashboard should go next (set by a deep link, consumed by the dashboard).
class OrgTabRequest {
  const OrgTabRequest(this.orgId, this.section, this.sub);
  final int orgId;
  final String section;
  final String? sub;
}

class AttentionService extends ChangeNotifier with WidgetsBindingObserver {
  AttentionService._();

  /// Polling runs only while something listens (a badge on screen), so tests and logged-out screens stay idle.
  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_active) return;
    _active = true;
    WidgetsBinding.instance.addObserver(this);
    _live = LiveEvents.instance.listen({...LiveEvents.silentTypes, LiveEvents.attentionChanged},
        (e) => DecisionRefresh.isLocal(e) ? onDecision() : _onLiveEvent());
    final stream = LiveEventsClient.instance;
    stream.connected.addListener(_onStreamChanged);
    stream.bind();
    _startTimer();
    refresh(quiet: true);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) _stop();
  }

  /// A live event: reload now, or once right after the reload that is running / just ran (never dropped).
  void _onLiveEvent() {
    if (_trailing != null) return;
    final d = attentionEventDelay(last: _last, now: DateTime.now(), running: _running != null);
    if (d == Duration.zero) {
      refresh(quiet: true);
      return;
    }
    _trailing = Timer(d, () {
      _trailing = null;
      if (!_active) return; // stopped meanwhile
      _onLiveEvent();
    });
  }

  /// THIS user just decided something (decision_refresh.dart): reload now — never throttled, since the badge must
  /// drop while the person is still looking at it. A reload that is already running may have read the count
  /// before the decision, so one more runs right after it.
  @visibleForTesting
  void onDecision() {
    if (!_active) return; // nothing on screen counts
    final running = _running;
    if (running == null) {
      refresh();
      return;
    }
    if (_afterRunning) return;
    _afterRunning = true;
    running.whenComplete(() {
      _afterRunning = false;
      if (_active) refresh();
    });
  }

  void _stop() {
    _active = false;
    _timer?.cancel();
    _timer = null;
    _trailing?.cancel();
    _trailing = null;
    _live?.cancel();
    _live = null;
    final stream = LiveEventsClient.instance;
    stream.connected.removeListener(_onStreamChanged);
    stream.release();
    WidgetsBinding.instance.removeObserver(this);
  }

  /// The poll is the fallback (attentionPollEvery): slow while the live stream is connected, 60 s when it is not,
  /// none in the background.
  void _startTimer() {
    _timer?.cancel();
    _timer = null;
    final every = attentionPollEvery(inFront: _inFront, streamConnected: LiveEventsClient.instance.connected.value);
    if (every != null) _timer = Timer.periodic(every, (_) => refresh(quiet: true));
  }

  void _onStreamChanged() {
    if (!_active) return;
    _startTimer();
    // a reconnect may have missed events (beyond the replay window): catch up once
    if (_inFront && LiveEventsClient.instance.connected.value) refresh(quiet: true);
  }

  /// The poll that runs now (null = none: nothing listens, or the app is in the background).
  @visibleForTesting
  Duration? get pollingEvery => _timer == null ? null : attentionPollEvery(inFront: _inFront, streamConnected: LiveEventsClient.instance.connected.value);

  static final AttentionService instance = AttentionService._();
  static const pollEvery = Duration(seconds: 60);
  static const pollEveryLive = Duration(minutes: 5);
  static const _minGap = Duration(seconds: 15);

  Timer? _timer;
  /// Something listens (a badge on screen): the live events are bound; the poll runs while [_inFront] too.
  bool _active = false;
  bool _inFront = true;
  Timer? _trailing;
  bool _afterRunning = false;
  StreamSubscription<LiveEvent>? _live;
  List<AttentionItem> _items = const [];
  List<AttentionItem> _focusItems = const [];
  int? _focusOrg;
  bool _focusFetch = false;
  DateTime? _last;
  Future<void>? _running;

  /// Deep link into the org dashboard: it listens and jumps to the section.
  final ValueNotifier<OrgTabRequest?> orgTabRequest = ValueNotifier(null);

  /// Org dashboards call this with the open organization (null when leaving) so `count(…, orgId:)` is exact.
  /// [perOrg]: the person gets this organization's items only per org (a platform admin, who manages every org).
  /// Only then is anything fetched, and only the org's own list: a member's general answer already holds their
  /// organizations' items, so focusing costs no request (home request budgets).
  void focusOrg(int? orgId, {bool perOrg = false}) {
    final wanted = orgId != null && perOrg;
    if (orgId == _focusOrg && wanted == _focusFetch) return;
    _focusOrg = orgId;
    _focusFetch = wanted;
    _focusItems = const [];
    if (wanted) unawaited(_loadFocus(orgId));
  }

  Future<void> _loadFocus(int orgId) async {
    try {
      final res = await ApiClient().get('/api/v1/me/attention', queryParams: {'org_id': orgId});
      if (orgId != _focusOrg || !_focusFetch) return;
      _focusItems = _parse(res);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('[attention] org $orgId: $e');
    }
  }

  List<AttentionItem> _pool(int? orgId) {
    if (orgId != null && orgId == _focusOrg && _focusItems.isNotEmpty) return _focusItems;
    return _items;
  }

  /// Badge number of a tab. With [orgId]: only that organization's items.
  int count(String tabKey, {int? orgId}) {
    var n = 0;
    for (final x in _pool(orgId)) {
      if (x.tab == tabKey && (orgId == null || x.orgId == orgId)) n += x.count;
    }
    if (orgId == null) n += _localBump[tabKey] ?? 0;
    return n;
  }

  /// Count [delta] onto a tab until the next answer from the server replaces it: what the app knows before asking,
  /// so a message in a busy group does not make every member re-read their badges (D-330).
  void bumpLocal(String tabKey, int delta) {
    _localBump[tabKey] = (_localBump[tabKey] ?? 0) + delta;
    notifyListeners();
  }

  final Map<String, int> _localBump = {};

  /// Items of a tab, most urgent first (server order).
  List<AttentionItem> items(String tabKey, {int? orgId}) =>
      [for (final x in _pool(orgId)) if (x.tab == tabKey && (orgId == null || x.orgId == orgId)) x];

  int get total => _items.fold(0, (s, x) => s + x.count);

  Future<void> refresh({bool quiet = false}) {
    if (quiet && _last != null && DateTime.now().difference(_last!) < const Duration(seconds: 5)) {
      return Future.value();
    }
    return _running ??= _load().whenComplete(() => _running = null);
  }

  Future<void> _load() async {
    _last = DateTime.now();
    final api = ApiClient();
    String? token;
    try {
      token = await api.accessToken;
    } catch (_) {}
    if (token == null || token.isEmpty) {
      if (_items.isNotEmpty || _focusItems.isNotEmpty) {
        _items = const [];
        _focusItems = const [];
        notifyListeners();
      }
      return;
    }
    // a token is here (just logged in, or the stream halted on an old one): let the stream reopen
    LiveEventsClient.instance.poke();
    final focus = _focusFetch ? _focusOrg : null;
    try {
      final res = await Future.wait([
        api.get('/api/v1/me/attention'),
        if (focus != null) api.get('/api/v1/me/attention', queryParams: {'org_id': focus}),
      ]);
      _items = _parse(res[0]);
      _localBump.clear();
      if (focus != null && focus == _focusOrg) _focusItems = _parse(res[1]);
      notifyListeners();
    } catch (e) {
      // keep the last answer: a failed poll never blanks the badges
      if (kDebugMode) debugPrint('[attention] $e');
    }
  }

  static List<AttentionItem> _parse(dynamic r) {
    final list = r is Map ? r['items'] : null;
    if (list is! List) return const [];
    return [for (final m in list) if (m is Map) AttentionItem(Map<String, dynamic>.from(m))];
  }

  /// TopRouteObserver calls this on push/pop: coming back from a screen usually means something was handled.
  void onRouteChanged() {
    if (!hasListeners) return;
    if (_last == null || DateTime.now().difference(_last!) >= _minGap) refresh(quiet: true);
  }

  /// Forget everything (logout).
  void clear() {
    _items = const [];
    _focusItems = const [];
    _focusOrg = null;
    _focusFetch = false;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        final was = _inFront;
        _inFront = true;
        if (_active && !was) _startTimer();
        refresh(quiet: true);
      case AppLifecycleState.paused || AppLifecycleState.hidden || AppLifecycleState.detached:
        // `inactive` (a system sheet, the app switcher) keeps polling: the app is still on screen
        _inFront = false;
        _timer?.cancel();
        _timer = null;
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}
