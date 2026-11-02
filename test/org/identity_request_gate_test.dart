// The student's identifier dialog over the fake backend (D-150): a pending request opens the dialog, a value the
// field's rules refuse never leaves the phone, a value another student already holds gets the server's 409 sentence,
// a valid one (Arabic-Indic digits) closes it. "Later" hides it; a failed check never blocks the app; the kill switch
// `exam.identifiers` hides everything. Replies are the recorded ones (test/org/fixtures/omr_setup_payloads.json).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/identity/identity_request_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

Map<String, dynamic> _p(String name) =>
    ((jsonDecode(File('test/org/fixtures/omr_setup_payloads.json').readAsStringSync()) as Map)['payloads'] as Map)[name] as Map<String, dynamic>;

Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  Widget host() => layoutHost(IdentityRequestGate(enabled: (_) => true, child: const Center(child: Text('home'))), scale: 1);

  testWidgets('pending → a duplicate → the 409 sentence → a valid value → closed', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    var pending = true;
    final sent = <String>[];
    final fake = FakeApi({
      'GET /api/v1/me/identity-requests': (_) => pending ? _p('me_requests_nid') : const {'items': []},
      'POST /api/v1/me/identity-requests/1': (o) {
        final v = '${(o.data as Map)['value']}';
        sent.add(v);
        if (v == '29901010000005') return FakeResponse(409, _p('err_taken'));
        pending = false;
        return _p('submit');
      },
    })
      ..install();
    addTearDown(fake.uninstall);

    await tester.pumpWidget(host());
    await _frames(tester);
    expect(find.text('Your teacher needs your National ID for the upcoming exam. Please enter it before exam day.'), findsOneWidget);
    expect(find.text('14 digits'), findsOneWidget, reason: 'the field\'s rule is shown before typing');

    // 13 digits: refused here, nothing sent
    await tester.enterText(find.byKey(const ValueKey('identity.value')), '2990101000000');
    await tester.tap(find.text('Save'));
    await _frames(tester, 3);
    expect(find.text('This must be exactly 14 digits.'), findsOneWidget);
    expect(sent, isEmpty);

    // another student's number: the server's sentence
    await tester.enterText(find.byKey(const ValueKey('identity.value')), '29901010000005');
    await tester.tap(find.text('Save'));
    await _frames(tester);
    expect(sent, ['29901010000005']);
    expect(find.text('This number is already used by another student. Please check it.'), findsOneWidget);

    // a valid one, typed with Arabic-Indic digits and a dash
    await tester.enterText(find.byKey(const ValueKey('identity.value')), '٢٩٩٠١٠١-٠٠٠٠٠٩٠');
    await _frames(tester, 4); // the field's error fades out
    expect(find.text('This number is already used by another student. Please check it.'), findsNothing, reason: 'typing clears the error');
    await tester.tap(find.text('Save'));
    await _frames(tester);
    expect(sent.last, '٢٩٩٠١٠١-٠٠٠٠٠٩٠', reason: 'sent as typed: the server normalises');
    expect(find.byType(IdentityRequestCard), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _done(tester);
  });

  testWidgets('Later hides it until the next check; a wake (push tap) shows it again', (tester) async {
    final fake = FakeApi({'GET /api/v1/me/identity-requests': (_) => _p('me_requests_custom')})..install();
    addTearDown(fake.uninstall);
    await tester.pumpWidget(host());
    await _frames(tester);
    expect(find.byType(IdentityRequestCard), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('identity.later')));
    await _frames(tester, 2);
    expect(find.byType(IdentityRequestCard), findsNothing);
    IdentityRequestGate.wake();
    await _frames(tester);
    expect(find.byType(IdentityRequestCard), findsOneWidget);
    await _done(tester);
  });

  testWidgets('a failed check never blocks the app; the kill switch hides it all', (tester) async {
    final fake = FakeApi({'GET /api/v1/me/identity-requests': (_) => const FakeResponse(500, {'detail': 'boom'})})..install();
    addTearDown(fake.uninstall);
    await tester.pumpWidget(host());
    await _frames(tester);
    expect(find.byType(IdentityRequestCard), findsNothing);
    expect(find.text('home'), findsOneWidget);
    await _done(tester);

    fake.uninstall();
    final ok = FakeApi({'GET /api/v1/me/identity-requests': (_) => _p('me_requests_nid')})..install();
    addTearDown(ok.uninstall);
    AppConfig.disableList = ['exam.identifiers'];
    await tester.pumpWidget(host());
    await _frames(tester);
    expect(find.byType(IdentityRequestCard), findsNothing);
    expect(ok.calls, isEmpty, reason: 'switched off: not even asked');
    await _done(tester);
  });
}
