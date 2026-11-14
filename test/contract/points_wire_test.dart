// The points wallet, the live plan, card top-ups and the live time (docs/backend/live-rooms-spec.md Part 3 §13 – §16)
// against REAL server responses: every test/fixtures/points/*.json was captured by the backend from its own e2e
// run (the backend agent writes them; regenerate after a payload change). Each capture is parsed with the app's own
// models — points_api.dart (PointsWallet, LivePlan, PointsTopup, PointsCheckout, PointsSettings, MeetingTimeLimit),
// JoinOutcome.parse / LiveResponseModel, GuestJoin, the coded errors through ApiException.fromResponse — and the
// fields the screens rely on must come out equal to the JSON.
//
// A capture is told apart by its route (`_source.route` "METHOD /path", or `_source.method` + `_source.path`, or
// `method` / `path` at the top), falling back to its file name. The REQUIRED captures below must all be there: a
// missing one fails the test by name, so a capture the backend stopped writing is noticed.
//
// Envelope: `{"_source": {route, status?, uid?}, "payload": <body>}` (as test/fixtures/payloads/), or
// `{status, body | json | payload}`; a bare JSON body is taken as a 200.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/shared/guest/guest_live_api.dart' show GuestJoin;
import 'package:flutter_education_app/features/live/live_room.dart' show JoinOutcome;
import 'package:flutter_education_app/features/live/live_time_limit.dart' show parseNaiveUtc;
import 'package:flutter_education_app/features/shared/points/points_api.dart';
import 'package:flutter_education_app/features/teacher/sessions/model/live_response_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _dir = 'test/fixtures/points';

/// One recorded response.
class Capture {
  Capture(this.file, this.method, this.path, this.status, this.payload);

  final String file;
  final String method;
  final String path;
  final int status;
  final dynamic payload;

  Map<String, dynamic> get map => Map<String, dynamic>.from(payload as Map);

  @override
  String toString() => '$file ($method $path → $status)';
}

Capture _load(File f) {
  final name = f.uri.pathSegments.last;
  final raw = jsonDecode(f.readAsStringSync());
  var method = '';
  var path = '';
  int? status;
  dynamic payload = raw;
  if (raw is Map) {
    final src = raw['_source'] is Map ? raw['_source'] as Map : raw;
    final route = '${src['route'] ?? ''}'.trim();
    if (route.contains(' ')) {
      method = route.split(' ').first.toUpperCase();
      path = route.substring(route.indexOf(' ') + 1).trim();
    } else {
      method = '${src['method'] ?? ''}'.toUpperCase();
      path = '${src['path'] ?? route}';
    }
    status = int.tryParse('${src['status'] ?? src['status_code'] ?? raw['status'] ?? raw['status_code'] ?? ''}');
    for (final k in ['payload', 'body', 'json', 'response']) {
      if (raw.containsKey(k)) {
        payload = raw[k];
        break;
      }
    }
  }
  path = path.split('?').first;
  final isError = payload is Map && payload['detail'] != null;
  return Capture(name, method, path, status ?? (isError ? 400 : 200), payload);
}

/// What each capture is: a route pattern (method + path) or, without a route, file-name keywords.
class Kind {
  const Kind(this.id, this.method, this.path, this.names, {this.required = true, this.error = false});

  final String id;
  final String method;
  final RegExp path;
  final List<String> names;
  final bool required;

  /// An error capture (status ≥ 400) of that route.
  final bool error;

  bool matches(Capture c) {
    if (error != (c.status >= 400)) return false;
    if (c.path.isNotEmpty) return (method.isEmpty || c.method.isEmpty || c.method == method) && path.hasMatch(c.path);
    final n = c.file.toLowerCase();
    return names.any(n.contains);
  }
}

final _kinds = <Kind>[
  Kind('wallet', 'GET', RegExp(r'^/api/v1/me/points$'), ['wallet', 'me_points.']),
  Kind('checkout', 'POST', RegExp(r'^/api/v1/me/points/checkout$'), ['checkout']),
  Kind('topup', 'GET', RegExp(r'^/api/v1/me/points/topups/\d+$'), ['topup_poll', 'my_topup', 'points_topup']),
  Kind('plan', 'GET', RegExp(r'^/api/v1/me/live-plan$'), ['live_plan_get', 'live_plan.', 'plan_status']),
  Kind('plan_auto_renew', 'PUT', RegExp(r'^/api/v1/me/live-plan$'), ['auto_renew', 'live_plan_put']),
  Kind('meeting_join', 'POST', RegExp(r'^/api/v1/me/calendar/meetings/\d+/join$'), ['meeting_join']),
  Kind('meeting_detail', 'GET', RegExp(r'^/api/v1/me/calendar/meetings/\d+$'), ['meeting_detail']),
  Kind('daily_limit_402', 'POST', RegExp(r'/join$'), ['daily_limit', 'live_plan_required'], error: true),
  // optional: checked when the backend captured them
  Kind('session_join', 'GET', RegExp(r'^/api/v1/live-sessions/\d+/join$'), ['session_join'], required: false),
  Kind('session_start', 'POST', RegExp(r'^/api/v1/live-sessions/start$'), ['session_start'], required: false),
  Kind('guest_join', 'POST', RegExp(r'^/api/v1/public/live/[^/]+/join$'), ['guest_join'], required: false),
  Kind('link_join', 'POST', RegExp(r'^/api/v1/live/links/[^/]+/join$'), ['link_join'], required: false),
  Kind('member_poll', 'GET', RegExp(r'^/api/v1/(public/)?live/requests/[^/]+$'), ['request_poll', 'admitted'], required: false),
  Kind('admin_topups', 'GET', RegExp(r'^/api/v1/admin/points/topups$'), ['admin_topups'], required: false),
  Kind('admin_settings', '', RegExp(r'^/api/v1/admin/points/settings$'), ['admin_settings', 'points_settings'], required: false),
  Kind('topup_by_card_409', 'POST', RegExp(r'^/api/v1/admin/points/topups/\d+/approve$'), ['topup_by_card'],
      required: false, error: true),
];

Map<String, dynamic> m(dynamic v) => Map<String, dynamic>.from(v as Map);

/// The parser reads these keys: the real payload must carry every one of them.
void hasKeys(Map<String, dynamic> j, Iterable<String> keys, Object where) {
  for (final k in keys) {
    expect(j.containsKey(k), isTrue, reason: '$where: the server sends no "$k" (renamed or dropped?) — keys: ${j.keys}');
  }
}

/// The server's naive-UTC (or zoned) ISO time as the UTC instant it means.
DateTime? utc(dynamic v) {
  if (v == null) return null;
  final s = '$v';
  final zoned = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  return DateTime.parse(zoned ? s : '${s}Z').toUtc();
}

/// The error exactly as ApiClient would throw it for this response.
ApiException apiError(Capture c) => ApiException.fromResponse(
    Response(requestOptions: RequestOptions(path: c.path), statusCode: c.status, data: c.payload));

void checkTimeLimit(dynamic raw, Object where) {
  if (raw == null) return; // unlimited (staff / a plan)
  final j = m(raw);
  hasKeys(j, ['ends_at', 'free_minutes', 'daily_minutes', 'daily_left'], '$where time_limit');
  final l = MeetingTimeLimit.parse(j)!;
  expect(l.endsAt, utc(j['ends_at']), reason: '$where time_limit.ends_at');
  expect(l.freeMinutes, j['free_minutes'], reason: '$where time_limit.free_minutes');
  expect(l.dailyMinutes, j['daily_minutes'], reason: '$where time_limit.daily_minutes');
  expect(l.dailyLeft, j['daily_left'], reason: '$where time_limit.daily_left');
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  final dir = Directory(_dir);
  final captures = dir.existsSync()
      ? (dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
            ..sort((a, b) => a.path.compareTo(b.path)))
          .map(_load)
          .toList()
      : <Capture>[];

  List<Capture> of(String id) {
    final k = _kinds.firstWhere((k) => k.id == id);
    return [for (final c in captures) if (k.matches(c)) c];
  }

  test('the backend captured every required response', () {
    expect(dir.existsSync(), isTrue,
        reason: '$_dir is missing: the backend writes the real-server captures there (Part 3 wire fixtures)');
    expect(captures, isNotEmpty, reason: '$_dir has no *.json capture');
    final missing = [for (final k in _kinds) if (k.required && of(k.id).isEmpty) k.id];
    expect(missing, isEmpty,
        reason: 'no capture for: ${missing.join(', ')} — captures present: ${captures.join('; ')}');
  });

  test('wallet: balance, price, methods (card), top-ups and history', () {
    for (final c in of('wallet')) {
      final j = c.map;
      hasKeys(j, ['balance', 'price_per_point', 'currency', 'topup_min', 'methods', 'history', 'topups'], c);
      final w = PointsWallet.fromJson(j);
      expect(w.balance, j['balance'], reason: '$c balance');
      expect(w.pricePerPoint, (j['price_per_point'] as num).toDouble(), reason: '$c price_per_point');
      expect(w.currency, j['currency'], reason: '$c currency');
      expect(w.topupMin, j['topup_min'], reason: '$c topup_min');
      final methods = [for (final x in j['methods'] as List) x is Map ? '${x['id'] ?? x['key'] ?? x['method']}' : '$x'];
      expect(w.methods, methods, reason: '$c methods');
      expect(w.hasCard, methods.contains('card'), reason: '$c card offered');
      expect(w.history.length, (j['history'] as List).length, reason: '$c history');
      expect(w.topups.length, (j['topups'] as List).length, reason: '$c topups');
      for (var i = 0; i < w.topups.length; i++) {
        final t = m((j['topups'] as List)[i]);
        expect(w.topups[i].id, t['id'], reason: '$c topups[$i].id');
        expect(w.topups[i].status, topupStatusFrom(t['status']), reason: '$c topups[$i].status');
        expect(w.topups[i].method, t['method'], reason: '$c topups[$i].method');
        expect(w.topups[i].isCard, t['method'] == 'card', reason: '$c topups[$i] card');
      }
    }
  });

  test('checkout: what opens the provider page', () {
    for (final c in of('checkout')) {
      final j = c.map;
      hasKeys(j, ['topup_id', 'provider', 'amount', 'currency', 'checkout_url'], c);
      final x = PointsCheckout.fromJson(j);
      expect(x.topupId, j['topup_id'], reason: '$c topup_id');
      expect(x.topupId, greaterThan(0), reason: '$c topup_id');
      expect(x.checkoutUrl, j['checkout_url'], reason: '$c checkout_url');
      expect(x.canOpen, isTrue, reason: '$c checkout_url must be an http(s) URL: ${j['checkout_url']}');
      expect(x.provider, j['provider'], reason: '$c provider');
      expect(x.amount, (j['amount'] as num).toDouble(), reason: '$c amount');
      expect(x.currency, j['currency'], reason: '$c currency');
      expect(x.alreadyPaid, j['already_paid'] == true, reason: '$c already_paid');
    }
  });

  test('my top-up (the poll): status, method card, provider, payment id', () {
    for (final c in of('topup')) {
      final j = c.map;
      hasKeys(j, ['id', 'points', 'amount', 'currency', 'method', 'status', 'provider', 'payment_id'], c);
      final x = PointsTopup.fromJson(j);
      expect(x.id, j['id'], reason: '$c id');
      expect(x.status, topupStatusFrom(j['status']), reason: '$c status');
      expect(x.status, isNot(TopupStatus.unknown), reason: '$c status "${j['status']}" is not one the app knows');
      expect(x.method, j['method'], reason: '$c method');
      expect(x.isCard, j['method'] == 'card', reason: '$c card');
      expect(x.provider, j['provider'], reason: '$c provider');
      expect(x.paymentId, j['payment_id'] == null ? null : '${j['payment_id']}', reason: '$c payment_id');
      if (j.containsKey('has_receipt')) expect(x.hasReceipt, j['has_receipt'], reason: '$c has_receipt');
      if (x.isCard) expect(x.hasReceipt, isFalse, reason: '$c a card top-up has no receipt');
    }
  });

  test('live plan: active, ends_at, auto_renew, days_left, daily free minutes', () {
    for (final c in [...of('plan'), ...of('plan_auto_renew')]) {
      final j = c.map;
      hasKeys(j, ['active', 'ends_at', 'price_points', 'days', 'free_minutes', 'balance', 'needed'], c);
      hasKeys(j, ['daily_free_minutes', 'daily_free_left', 'auto_renew', 'days_left'], c);
      final p = LivePlan.fromJson(j);
      expect(p.active, j['active'], reason: '$c active');
      expect(p.endsAt, utc(j['ends_at']), reason: '$c ends_at');
      expect(p.balance, j['balance'], reason: '$c balance');
      expect(p.needed, j['needed'], reason: '$c needed');
      expect(p.autoRenew, j['auto_renew'], reason: '$c auto_renew');
      expect(p.serverDaysLeft, j['days_left'], reason: '$c days_left');
      expect(p.dailyFreeMinutes, j['daily_free_minutes'], reason: '$c daily_free_minutes');
      expect(p.dailyFreeLeft, j['daily_free_left'], reason: '$c daily_free_left');
      if (p.active && p.endsAt != null && j['days_left'] is int) {
        expect(p.daysLeft(DateTime.now().toUtc()), j['days_left'], reason: '$c days left shown');
      }
    }
  });

  test('meeting join (200): live_started_at and time_limit reach the room', () {
    for (final c in [...of('meeting_join'), ...of('link_join'), ...of('member_poll')]) {
      final j = c.map;
      final o = JoinOutcome.parse(j);
      if (!o.isAdmitted) continue; // a 202 waiting capture
      hasKeys(j, ['token', 'live_started_at', 'time_limit'], c);
      expect(o.token, j['token'], reason: '$c token');
      expect(o.url, isNotEmpty, reason: '$c url / ws_url');
      expect(o.liveStartedAt, utc(j['live_started_at']), reason: '$c live_started_at');
      expect(o.liveStartedAt, isNotNull, reason: '$c a successful join stamps the room start');
      expect(o.freeEndsAt, utc((j['time_limit'] as Map?)?['ends_at']), reason: '$c time_limit.ends_at');
      checkTimeLimit(j['time_limit'], c);
      final live = o.live(sessionId: -1);
      expect(live.liveStartedAt, o.liveStartedAt, reason: '$c → LiveResponseModel.liveStartedAt');
      expect(live.freeEndsAt, o.freeEndsAt, reason: '$c → LiveResponseModel.freeEndsAt');
    }
  });

  test('meeting detail: live_started_at, time_limit with the daily fields, owner_plan_active', () {
    for (final c in of('meeting_detail')) {
      final j = c.map;
      hasKeys(j, ['live_started_at', 'time_limit', 'owner_plan_active'], c);
      expect(parseNaiveUtc(j['live_started_at']), utc(j['live_started_at']), reason: '$c live_started_at');
      expect(j['owner_plan_active'], isA<bool>(), reason: '$c owner_plan_active');
      checkTimeLimit(j['time_limit'], c);
      final l = MeetingTimeLimit.parse(j['time_limit']);
      if (l != null) {
        // the detail's free-time note is built from it without throwing, for the owner and the others
        expect(meetingFreeNote(l, DateTime.now().toUtc(), owner: true), isNotEmpty);
        expect(meetingFreeNote(l, DateTime.now().toUtc()), isNotEmpty);
      }
    }
  });

  test('402 live_plan_required with reason daily_limit', () {
    for (final c in of('daily_limit_402')) {
      final e = apiError(c);
      final code = pointsErrorCode(e);
      if (code != 'live_plan_required') continue; // another refused join (meeting_time_limit)
      expect(c.status, 402, reason: '$c status');
      final d = pointsErrorDetail(e);
      hasKeys(d, ['code', 'reason'], '$c detail');
      expect(d['reason'], kDailyLimitReason, reason: '$c reason');
      expect(livePlanReasonText('${d['reason']}'), "Today's free time is used up", reason: '$c header');
      expect(pointsErrorText(e), isNotEmpty);
    }
    expect([for (final c in of('daily_limit_402')) if (pointsErrorCode(apiError(c)) == 'live_plan_required') c], isNotEmpty,
        reason: 'no 402 live_plan_required capture among: ${of('daily_limit_402')}');
  });

  test('course session start / join and the guest join carry live_started_at (when captured)', () {
    for (final c in [...of('session_join'), ...of('session_start')]) {
      final j = c.map;
      final o = JoinOutcome.parse(j);
      if (!o.isAdmitted) continue;
      hasKeys(j, ['token', 'live_started_at'], c);
      // the same reads sessions_provider.dart does
      final live = LiveResponseModel(
          sessionId: 1,
          url: '${j['ws_url'] ?? ''}',
          token: '${j['token']}',
          liveStartedAt: parseNaiveUtc(j['live_started_at']));
      expect(live.liveStartedAt, utc(j['live_started_at']), reason: '$c live_started_at');
      expect(o.liveStartedAt, utc(j['live_started_at']), reason: '$c JoinOutcome.liveStartedAt');
    }
    for (final c in of('guest_join')) {
      final j = c.map;
      final o = JoinOutcome.parse(j);
      if (!o.isAdmitted) continue;
      hasKeys(j, ['token', 'live_started_at'], c);
      final g = GuestJoin.fromJson(j);
      expect(g.liveStartedAt, utc(j['live_started_at']), reason: '$c guest live_started_at');
      expect(g.freeEndsAt, utc((j['time_limit'] as Map?)?['ends_at']), reason: '$c guest time_limit');
    }
  });

  test('admin: top-ups with card rows, settings with the Part 3 keys (when captured)', () {
    for (final c in of('admin_topups')) {
      final items = PointsTopup.listFrom(c.payload);
      final raw = [for (final x in (c.payload is Map ? c.map['items'] : c.payload) as List) m(x)];
      expect(items.length, raw.length, reason: '$c items');
      for (var i = 0; i < items.length; i++) {
        expect(items[i].method, raw[i]['method'], reason: '$c [$i].method');
        expect(items[i].provider, raw[i]['provider'], reason: '$c [$i].provider');
        expect(items[i].status, topupStatusFrom(raw[i]['status']), reason: '$c [$i].status');
        if (raw[i]['user'] != null) expect(items[i].user?.id, m(raw[i]['user'])['id'], reason: '$c [$i].user');
      }
    }
    for (final c in of('admin_settings')) {
      final j = c.map;
      final s0 = j['settings'] is Map ? m(j['settings']) : j;
      hasKeys(s0, ['live_meeting_free_minutes_daily', 'points_card_enabled'], c);
      final s = PointsSettings.fromJson(j);
      expect(s.freeMinutesDaily, s0['live_meeting_free_minutes_daily'], reason: '$c daily minutes');
      expect(s.cardEnabled, s0['points_card_enabled'], reason: '$c card enabled');
      expect(s.toJson().keys, containsAll(['live_meeting_free_minutes_daily', 'points_card_enabled']));
    }
    for (final c in of('topup_by_card_409')) {
      final e = apiError(c);
      expect(pointsErrorCode(e), 'topup_by_card', reason: '$c code');
      expect(pointsCodeText('topup_by_card'), isNotNull);
    }
  });
}
