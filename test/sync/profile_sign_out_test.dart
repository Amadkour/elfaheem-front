// The main sign-out button (ProfileProvider.logout) runs the one sign-out flow (MyAuthProvider.logout): the offline
// outbox and the read cache (/me/home, courses, library, progress) are wiped, so nothing stays on the device for the
// next person; Cancel on the unsent-work question keeps the person signed in with everything in place. A forced
// sign-out (ApiClient.onSessionLost: the session expired or the refresh was refused) wipes without asking.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/core/offline/sync/local_db.dart';
import 'package:flutter_education_app/core/offline/sync/outbox.dart';
import 'package:flutter_education_app/core/offline/sync/read_cache.dart';
import 'package:flutter_education_app/core/offline/sync/sync_status.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/payments/enrollment_request/teacher_transfers_provider.dart';
import 'package:flutter_education_app/features/profile/profile_provider.dart';
import 'package:flutter_education_app/features/profile/teacher/switch_device_requests/teacher_device_requests_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

void main() {
  late MemoryLocalDb db;
  late MyAuthProvider auth;
  late ProfileProvider profile;
  late FakeApi api;
  final asked = <int>[];
  var answer = true;

  setUp(() async {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    api = FakeApi({}, latency: Duration.zero, fallback: (_) => const <String, dynamic>{})..install();
    final storage = await StorageService.getInstance();
    await storage.saveUser({'id': 7, 'name': 'Test', 'gmail': 'u@example.com', 'role': 'student'});
    await ApiClient.instance.saveTokens(access: 'a', refresh: 'r');
    db = MemoryLocalDb();
    Outbox.instance = Outbox(open: () async => db, userId: () async => 7, available: () => true, viewingAs: () => false, status: SyncStatus());
    ReadCache.instance = ReadCache();
    await Outbox.instance.enqueue(id: 'op-left-0001', kind: SyncKinds.gamePlay, payload: {'game_id': 1});
    await ReadCache.instance.put('me.home', {'courses': [1, 2]});
    AppConnectivity.instance.online.value = false; // the queued op cannot be sent first: the question decides
    asked.clear();
    answer = true;
    MyAuthProvider.confirmUnsentLoss = (n) async {
      asked.add(n);
      return answer;
    };
    auth = MyAuthProvider(storage: storage);
    profile = ProfileProvider(storage: storage);
  });

  tearDown(() {
    MyAuthProvider.confirmUnsentLoss = null;
    AppConnectivity.instance.online.value = true;
    api.uninstall();
  });

  Future<BuildContext> pump(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<MyAuthProvider>.value(value: auth),
        ChangeNotifierProvider<ProfileProvider>.value(value: profile),
        ChangeNotifierProvider(create: (_) => TeacherTransfersProvider()),
        ChangeNotifierProvider(create: (_) => TeacherDeviceRequestsProvider()),
      ],
      child: MaterialApp(home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })),
    ));
    return ctx;
  }

  testWidgets('the profile sign-out wipes the outbox and the read cache', (tester) async {
    final ctx = await pump(tester);
    await tester.runAsync(() async {
      await profile.logout(ctx);
      expect(asked, [1]);
      expect(await db.outboxRows(), isEmpty);
      expect(await ReadCache.instance.get('me.home'), isNull);
      expect(auth.isAuthenticated, isFalse);
      expect(await ApiClient.instance.accessToken, isNull);
    });
  });

  testWidgets('Cancel on the unsent-work question keeps the session, the outbox and the cache', (tester) async {
    answer = false;
    final ctx = await pump(tester);
    await tester.runAsync(() async {
      await profile.logout(ctx);
      expect(asked, [1]);
      expect(await db.outboxRows(), hasLength(1));
      expect(await ReadCache.instance.get('me.home'), isNotNull);
      expect(auth.isAuthenticated, isTrue);
      expect(await ApiClient.instance.accessToken, 'a');
    });
  });

  testWidgets('a forced sign-out (the session is gone) wipes without asking', (tester) async {
    await pump(tester);
    await tester.runAsync(() async {
      await ApiClient.onSessionLost!();
      expect(asked, isEmpty);
      expect(await db.outboxRows(), isEmpty);
      expect(await ReadCache.instance.get('me.home'), isNull);
      expect(auth.isAuthenticated, isFalse);
    });
  });
}
