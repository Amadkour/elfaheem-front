// Notices raised inside the full-screen live room (LiveRoomLayer, D-059) are drawn ABOVE the room's own sheets
// and dialogs: the room has its own Navigator above the app's, so the root overlay would sit behind it.
// Minimized, the notice goes back to the app's root overlay.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/features/shared/live/live_room_host.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_test/flutter_test.dart';

Widget _app() => ThemeConfigScope(
      provider: ThemeConfigProvider(api: ApiClient()),
      child: MaterialApp(
        navigatorKey: navigatorKey,
        builder: (_, child) => LiveRoomLayer(child: child!),
        home: const Scaffold(body: Center(child: Text('home page'))),
      ),
    );

class _Room extends StatelessWidget {
  const _Room();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => SizedBox(
                  height: 300,
                  child: Center(
                    child: TextButton(onPressed: () => showAppNotice('from the sheet'), child: const Text('notify')),
                  ),
                ),
              ),
              child: const Text('open sheet'),
            ),
            TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  content: TextButton(
                      onPressed: () => showAppNotice('from the dialog', error: true), child: const Text('notify')),
                ),
              ),
              child: const Text('open dialog'),
            ),
            TextButton(onPressed: LiveRoomScope.maybeOf(context)!.minimize, child: const Text('minimize')),
          ]),
        ),
      );
}

/// The notice slides in from above the screen: one frame to mount it, then let the animation run.
Future<void> _settleNotice(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(_app());
  LiveRoomHost.open(LiveRoomSession(page: const _Room(), mini: (_) => const Text('box')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(LiveRoomHost.reset);

  testWidgets('a notice from an open sheet in the full-screen room is drawn above the sheet', (tester) async {
    await _open(tester);
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('notify'));
    await _settleNotice(tester);
    // hit-testable = on top: under the sheet's barrier (or under the room page) the hit would land elsewhere
    expect(find.text('from the sheet').hitTestable(), findsOneWidget);
    expect(LiveRoomHost.noticeOverlay(), isNotNull);
    expect(appNoticeTopOverlay?.call(), same(LiveRoomHost.noticeOverlay()));
    hideAppNotice();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // the exit (180 ms) plays before the entry leaves
    expect(find.text('from the sheet'), findsNothing);
  });

  testWidgets('a notice from a dialog in the room is drawn above the dialog and times out', (tester) async {
    await _open(tester);
    await tester.tap(find.text('open dialog'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('notify'));
    await _settleNotice(tester);
    expect(find.text('from the dialog').hitTestable(), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 300)); // the exit (180 ms) plays before the entry leaves
    expect(find.text('from the dialog'), findsNothing);
  });

  testWidgets('minimized: the notice goes to the app root overlay and is visible over the app', (tester) async {
    await _open(tester);
    await tester.tap(find.text('minimize'));
    await tester.pumpAndSettle();
    expect(LiveRoomHost.noticeOverlay(), isNull);
    showAppNotice('over the app');
    await _settleNotice(tester);
    expect(find.text('over the app').hitTestable(), findsOneWidget);
    expect(find.text('home page'), findsOneWidget);
    hideAppNotice(); // its dismiss timer must not outlive the test
  });

  testWidgets('hideAppNotice(message:) leaves a newer notice alone', (tester) async {
    await _open(tester);
    showAppNotice('first');
    showAppNotice('second');
    await _settleNotice(tester);
    hideAppNotice(message: 'first');
    await tester.pump();
    expect(find.text('second'), findsOneWidget);
    hideAppNotice(message: 'second');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // the exit (180 ms) plays before the entry leaves
    expect(find.text('second'), findsNothing);
  });
}
