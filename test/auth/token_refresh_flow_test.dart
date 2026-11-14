// F2: the token refresh with rotation, end to end through ApiClient's real interceptors over a fake backend:
// - a 401 refreshes the tokens once and retries the call with the new access token (the rotated refresh token is
//   stored, the old one is never sent again);
// - two calls refused at the same time share ONE refresh;
// - a refresh the server rejects clears the session and opens /login;
// - a refresh that cannot reach the server keeps the session (no sign-out on a dead network).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

void main() {
  late List<String> opened;
  late int refreshes;
  late List<String> refreshBodies;
  late Object? Function(RequestOptions o) refreshAnswer;
  late FakeApi api;

  Future<void> pumpApp(WidgetTester tester) async {
    opened = [];
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      onGenerateRoute: (s) {
        opened.add(s.name ?? '');
        return MaterialPageRoute(settings: s, builder: (_) => const SizedBox());
      },
    ));
    opened.clear();
  }

  /// Runs [call] while the fake clock moves, so every fake answer (10 ms each) lands.
  Future<T> drive<T>(WidgetTester tester, Future<T> call) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    return call;
  }

  setUp(() async {
    mockRequestPlugins();
    SharedPreferences.setMockInitialValues({}); // signing out clears the onboarding token there
    refreshes = 0;
    refreshBodies = [];
    refreshAnswer = (_) => {'access_token': 'new-access', 'refresh_token': 'refresh-2'};
    api = FakeApi({
      'GET /api/v1/me/thing': (o) => o.headers['Authorization'] == 'Bearer new-access'
          ? {'ok': true}
          : const FakeResponse(401, {'detail': 'Token expired'}),
      'POST /api/v1/auth/refresh': (o) {
        refreshes++;
        refreshBodies.add('${(o.data as Map)['refresh_token']}');
        return refreshAnswer(o);
      },
    }, latency: const Duration(milliseconds: 10))
      ..install();
    await ApiClient.instance.saveTokens(access: 'old-access', refresh: 'refresh-1');
  });

  tearDown(() => api.uninstall());

  testWidgets('401 → refresh → the call is retried with the new token', (tester) async {
    await pumpApp(tester);
    final r = await drive(tester, ApiClient.instance.get('/api/v1/me/thing'));
    expect(r, {'ok': true});
    expect(refreshes, 1);
    expect(refreshBodies, ['refresh-1']);
    expect(await ApiClient.instance.accessToken, 'new-access');
    expect(await ApiClient.instance.refreshToken, 'refresh-2'); // rotation: the new refresh token is kept
    expect(api.calls.map((c) => c.key), ['GET /api/v1/me/thing', 'POST /api/v1/auth/refresh', 'GET /api/v1/me/thing']);
    expect(opened, isEmpty);
  });

  testWidgets('two parallel 401s share one refresh', (tester) async {
    await pumpApp(tester);
    final a = ApiClient.instance.get('/api/v1/me/thing');
    final b = ApiClient.instance.get('/api/v1/me/thing');
    final both = await drive(tester, Future.wait([a, b]));
    expect(both, [{'ok': true}, {'ok': true}]);
    expect(refreshes, 1);
    expect(refreshBodies, ['refresh-1']); // the rotated-out token is never sent a second time (that is refresh_reuse)
  });

  testWidgets('a rejected refresh clears the session and opens the sign-in', (tester) async {
    refreshAnswer = (_) => const FakeResponse(401, {'detail': 'refresh_reuse'});
    await pumpApp(tester);
    Object? error;
    await drive(tester, ApiClient.instance.get('/api/v1/me/thing').catchError((Object e) {
      error = e;
      return null;
    }));
    expect(error, isA<ApiException>().having((e) => e.statusCode, 'status', 401));
    expect(refreshes, 1);
    expect(await ApiClient.instance.accessToken, isNull);
    expect(await ApiClient.instance.refreshToken, isNull);
    expect(ApiClient.instance.hasSession, isFalse);
    expect(opened, ['/login']);
    await tester.pump(const Duration(seconds: 3)); // the redirect's 2 s de-duplication window
  });

  testWidgets('a refresh that cannot reach the server keeps the session', (tester) async {
    refreshAnswer = (_) => const FakeResponse(503, {'detail': 'down'});
    await pumpApp(tester);
    Object? error;
    await drive(tester, ApiClient.instance.get('/api/v1/me/thing').catchError((Object e) {
      error = e;
      return null;
    }));
    expect(error, isA<ApiException>());
    expect(await ApiClient.instance.refreshToken, 'refresh-1');
    expect(opened, isEmpty);
  });
}
