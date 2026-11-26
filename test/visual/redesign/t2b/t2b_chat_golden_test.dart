// VISUAL review renders of the teacher's messages (redesign T2b, Tea2Chat chat / newmsg): 390x844 and 1360x900,
// Arabic and English, light, CAST demo data. Compared by eye with D:/platform/redesign-ref/ref/teacher/103_* … 105_*.
// Not a CI suite.
//
//   flutter test test/visual/redesign/t2b/t2b_chat_golden_test.dart --update-goldens
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/messaging/chat/chat_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/redesign/t2b_fakes.dart';
import '../kit_golden_harness.dart';

void main() {
  late StorageService storage;
  setUpAll(() async => storage = await kitGoldenSetUp());

  testWidgets('chat', (tester) async {
    await t2bSetUp();
    final auth = MyAuthProvider(storage: storage)..loadCachedUser();
    await kitRender(
      tester,
      't2b_chat',
      () => ChangeNotifierProvider<MyAuthProvider>.value(value: auth, child: const ChatHomePage()),
      storage: storage,
      modes: const [false],
      scaffold: false,
      grow: false,
    );
    // the presence poll and the typing timers end with the page
    await tester.pump(const Duration(minutes: 2));
  });
}
