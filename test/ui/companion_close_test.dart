// D-810: the companion phone's page closes itself when the room ends (companion_screen.dart `_finish`).
//
// The page refuses a back gesture (`PopScope(canPop: false)`: back means "Leave", which tells the person's other
// device first). It used to close itself with `Navigator.maybePop`, which asks that PopScope: the PopScope said no and
// re-ran Leave, which found the page already closing and did nothing — the page stayed on screen with dead buttons and a
// dead back button, and the phone looked frozen. `closeCompanionRoute` pops past it.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/live/companion/companion_parts.dart';
import 'package:flutter_test/flutter_test.dart';

/// The phone page's shape: a PopScope that refuses and runs "leave" instead, and a way to close itself.
class _GuardedPage extends StatefulWidget {
  const _GuardedPage({required this.close});
  final void Function(BuildContext context) close;

  @override
  State<_GuardedPage> createState() => _GuardedPageState();
}

class _GuardedPageState extends State<_GuardedPage> {
  int leaveRuns = 0;
  bool closed = false;

  void finish() {
    if (closed) return; // the page's own "once" guard
    closed = true;
    widget.close(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          leaveRuns++;
          finish(); // Leave → finish, already closed → nothing
        },
        child: const Scaffold(body: Text('phone page')),
      );
}

Future<GlobalKey<NavigatorState>> _open(WidgetTester tester, void Function(BuildContext) close,
    {bool dialogAbove = false}) async {
  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(MaterialApp(navigatorKey: nav, home: const Scaffold(body: Text('home'))));
  nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => _GuardedPage(close: close)));
  await tester.pumpAndSettle();
  if (dialogAbove) {
    showDialog<void>(context: nav.currentContext!, builder: (_) => const AlertDialog(content: Text('dialog')));
    await tester.pumpAndSettle();
  }
  return nav;
}

void main() {
  testWidgets('the old maybePop leaves the page on screen (the frozen phone)', (tester) async {
    await _open(tester, (ctx) => Navigator.of(ctx).maybePop());
    tester.state<_GuardedPageState>(find.byType(_GuardedPage)).finish(); // the room ended
    await tester.pumpAndSettle();
    expect(find.text('phone page'), findsOneWidget);
    expect(tester.state<_GuardedPageState>(find.byType(_GuardedPage)).leaveRuns, 1);
  });

  testWidgets('closeCompanionRoute closes the page when the room ends', (tester) async {
    await _open(tester, closeCompanionRoute);
    tester.state<_GuardedPageState>(find.byType(_GuardedPage)).finish();
    await tester.pumpAndSettle();
    expect(find.text('phone page'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('it closes the page under a dialog too, and a second call is harmless', (tester) async {
    await _open(tester, closeCompanionRoute, dialogAbove: true);
    final page = tester.state<_GuardedPageState>(find.byType(_GuardedPage, skipOffstage: false));
    final ctx = page.context;
    page.finish();
    closeCompanionRoute(ctx);
    await tester.pumpAndSettle();
    expect(find.text('phone page', skipOffstage: false), findsNothing);
    expect(find.text('dialog'), findsOneWidget, reason: 'only the page goes');
  });
}
