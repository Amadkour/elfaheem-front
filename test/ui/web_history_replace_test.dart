// A page replaced by another on the web (the player's Open in Studio): the sync steps the browser back over the old
// page and pushes the new one. The popstate of that step reached the app only after the push, looked like the person
// pressing Back, and closed the new page.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/core/routing/web_history.dart';
import 'package:flutter_test/flutter_test.dart';

class _Browser {
  final entries = <Map>[];
  var at = -1;

  Future<Object?> onMessage(MethodCall call) async {
    if (call.method != 'routeInformationUpdated') return null;
    final a = call.arguments as Map;
    final entry = {'uri': a['uri'] ?? a['location'], 'state': a['state']};
    if (a['replace'] == true && at >= 0) {
      entries[at] = entry;
    } else {
      entries.removeRange(at + 1, entries.length);
      entries.add(entry);
      at++;
    }
    return null;
  }

  Future<bool> go(int delta) async {
    at += delta;
    final e = entries[at];
    // as in the engine: the popstate is delivered around the time go() completes
    Future<void>.microtask(() => WebHistory.instance.browserMoved(
        RouteInformation(uri: Uri.parse('${e['uri']}'), state: e['state'])));
    return true;
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
}

void main() {
  testWidgets('a replaced page stays open: the sync\'s own step back is not the person pressing Back', (tester) async {
    final browser = _Browser();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.navigation, browser.onMessage);
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.navigation, null);
      WebHistory.instance.reset();
    });
    final key = GlobalKey<NavigatorState>();
    WebHistory.instance
      ..reset()
      ..go = browser.go
      ..onBack = (() => key.currentState!.maybePop())
      ..enable();

    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      navigatorObservers: [WebHistory.instance],
      home: const Text('course'),
    ));
    await _settle(tester);
    key.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Text('player')));
    await _settle(tester);
    expect(find.text('player'), findsOneWidget);

    key.currentState!.pushReplacement(MaterialPageRoute<void>(builder: (_) => const Text('studio')));
    await _settle(tester);

    expect(find.text('studio'), findsOneWidget);
    expect(find.text('course'), findsNothing);
    expect(browser.at, 2, reason: 'guard · course · studio');

    // A real Back afterwards still closes it.
    await browser.go(-1);
    await _settle(tester);
    expect(find.text('course'), findsOneWidget);
  });
}
