// Live rooms — the host layer (lib/features/shared/live/live_room_host.dart): the room lives above the Navigator,
// shrinks to a box and comes back; the back button closes the room's own dialog, then minimizes, and is left to
// the app while minimized; closing unmounts the page and completes the handle. Plus the pure geometry of the box
// and the pure choice of what the box shows (live_mini_box.dart). No LiveKit: the page and the box are plain widgets.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/live/live_mini_box.dart';
import 'package:flutter_education_app/features/shared/live/live_room_host.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app() => MaterialApp(
      builder: (_, child) => LiveRoomLayer(child: child!),
      home: const Scaffold(body: Text('home page')),
    );

class _Page extends StatefulWidget {
  const _Page();

  static int disposed = 0;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  void dispose() {
    _Page.disposed++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = LiveRoomScope.maybeOf(context)!;
    return Scaffold(
      body: Column(children: [
        const Text('room page'),
        TextButton(onPressed: scope.minimize, child: const Text('minimize')),
        TextButton(
          onPressed: () => showDialog<void>(context: context, builder: (_) => const AlertDialog(title: Text('room dialog'))),
          child: const Text('dialog'),
        ),
        TextButton(onPressed: scope.close, child: const Text('close')),
      ]),
    );
  }
}

LiveRoomSession _session() => LiveRoomSession(
      page: const _Page(),
      mini: (context) => TextButton(onPressed: LiveRoomScope.maybeOf(context)!.expand, child: const Text('box')),
    );

void main() {
  setUp(() {
    LiveRoomHost.reset();
    _Page.disposed = 0;
  });

  group('LiveRoomLayer', () {
    testWidgets('open shows the page full-screen; minimize shows the box and keeps the page mounted', (tester) async {
      await tester.pumpWidget(_app());
      expect(LiveRoomHost.isInstalled, isTrue);
      final handle = LiveRoomHost.open(_session());
      await tester.pump();
      expect(find.text('room page'), findsOneWidget);
      expect(LiveRoomHost.isOpen, isTrue);

      await tester.tap(find.text('minimize'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(handle.minimized.value, isTrue);
      expect(find.text('box'), findsOneWidget);
      // the page is offstage, not gone: nothing was disposed and the home page is reachable again
      expect(_Page.disposed, 0);
      expect(find.text('room page', skipOffstage: false), findsOneWidget);
      expect(find.text('room page'), findsNothing);
      expect(find.text('home page'), findsOneWidget);

      await tester.tap(find.text('box'));
      await tester.pump();
      expect(handle.minimized.value, isFalse);
      expect(find.text('room page'), findsOneWidget);
      expect(find.text('box'), findsNothing);
    });

    testWidgets('close unmounts the page and completes the handle', (tester) async {
      await tester.pumpWidget(_app());
      final handle = LiveRoomHost.open(_session());
      await tester.pump();
      var closed = false;
      handle.closed.then((_) => closed = true);
      await tester.tap(find.text('close'));
      await tester.pump();
      expect(closed, isTrue);
      expect(_Page.disposed, 1);
      expect(find.text('room page', skipOffstage: false), findsNothing);
      expect(LiveRoomHost.isOpen, isFalse);
    });

    testWidgets('the room\'s dialog opens above the room, in the layer\'s own navigator', (tester) async {
      await tester.pumpWidget(_app());
      LiveRoomHost.open(_session());
      await tester.pump();
      await tester.tap(find.text('dialog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('room dialog'), findsOneWidget);
      // back: the dialog first, then minimize, then nothing (the app's turn)
      expect(await LiveRoomHost.handleBack(), isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('room dialog'), findsNothing);
      expect(LiveRoomHost.isMinimized, isFalse);
      expect(await LiveRoomHost.handleBack(), isTrue);
      await tester.pump();
      expect(LiveRoomHost.isMinimized, isTrue);
      expect(await LiveRoomHost.handleBack(), isFalse);
    });

    testWidgets('minimizing closes the room\'s open sheet first; a second room replaces the first', (tester) async {
      await tester.pumpWidget(_app());
      final first = LiveRoomHost.open(_session());
      await tester.pump();
      await tester.tap(find.text('dialog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      LiveRoomHost.minimize();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('room dialog', skipOffstage: false), findsNothing);

      var firstClosed = false;
      first.closed.then((_) => firstClosed = true);
      final second = LiveRoomHost.open(_session());
      await tester.pump();
      expect(firstClosed, isTrue);
      expect(second.minimized.value, isFalse);
      expect(find.text('room page'), findsOneWidget);
      expect(_Page.disposed, 1);
    });

    testWidgets('the box can be dragged and snaps to a side', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app());
      LiveRoomHost.open(_session());
      await tester.pump();
      LiveRoomHost.minimize();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final box = find.byKey(const ValueKey('live_room.mini_box'));
      final before = tester.getTopLeft(box);
      expect(before.dx, greaterThan(200)); // LTR: starts at the end side
      await tester.drag(box, const Offset(-300, -100));
      await tester.pump();
      final after = tester.getTopLeft(box);
      expect(after.dx, liveMiniEdge); // snapped to the left edge
      expect(after.dy, closeTo(before.dy - 100, 20)); // minus the touch slop
    });

    testWidgets('without a layer nothing is installed and handleBack is false', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('plain'))));
      expect(LiveRoomHost.isInstalled, isFalse);
      expect(await LiveRoomHost.handleBack(), isFalse);
    });
  });

  group('box geometry', () {
    test('liveMiniSize: two fifths of a phone, capped on a wide window', () {
      expect(liveMiniSize(const Size(320, 640)), const Size(150, 94));
      expect(liveMiniSize(const Size(400, 800)), const Size(168, 105));
      expect(liveMiniSize(const Size(1400, 900)), const Size(240, 150));
    });

    test('liveMiniSnap: nearer side, inside the safe area, never off-screen', () {
      const screen = Size(400, 800);
      const pad = EdgeInsets.fromLTRB(0, 40, 0, 20);
      const box = Size(168, 105);
      expect(liveMiniSnap(const Offset(10, 300), screen, pad, box), const Offset(12, 300));
      expect(liveMiniSnap(const Offset(300, 300), screen, pad, box), const Offset(400 - 168 - 12, 300));
      expect(liveMiniSnap(const Offset(300, -50), screen, pad, box).dy, 52);
      expect(liveMiniSnap(const Offset(300, 900), screen, pad, box).dy, 800 - 20 - 105 - 12);
      // a screen too small for the box: pinned to the top, x never negative
      expect(liveMiniSnap(const Offset(0, 0), const Size(100, 100), EdgeInsets.zero, box), const Offset(0, 12));
    });

    test('liveMiniDefault: the end side, above a bottom bar', () {
      const screen = Size(400, 800);
      const box = Size(168, 105);
      expect(liveMiniDefault(screen, EdgeInsets.zero, box, rtl: false).dx, 400 - 168 - 12);
      expect(liveMiniDefault(screen, EdgeInsets.zero, box, rtl: true).dx, 12);
      expect(liveMiniDefault(screen, EdgeInsets.zero, box, rtl: false).dy, 800 - 105 - 96);
    });
  });

  group('liveMiniPick', () {
    const me = LiveMiniCandidate(name: 'me', isLocal: true, hasVideo: true, speaking: true);
    const quiet = LiveMiniCandidate(name: 'quiet', lastSpokeMs: 10);
    const talker = LiveMiniCandidate(name: 'talker', speaking: true, lastSpokeMs: 30);
    const camera = LiveMiniCandidate(name: 'camera', hasVideo: true, lastSpokeMs: 5);
    const screen = LiveMiniCandidate(name: 'screen', screenShare: true, hasVideo: true);

    test('empty → null', () => expect(liveMiniPick(const []), isNull));

    test('a screen share beats everything', () {
      expect(liveMiniPick(const [me, talker, camera, screen]), 3);
    });

    test('a remote camera beats the local one, which beats a speaker without video', () {
      expect(liveMiniPick(const [me, talker, camera]), 2);
      expect(liveMiniPick(const [me, talker]), 0);
    });

    test('nobody on camera: the speaker, else the latest speaker, remote before local', () {
      expect(liveMiniPick(const [quiet, talker]), 1);
      const later = LiveMiniCandidate(name: 'later', lastSpokeMs: 20);
      expect(liveMiniPick(const [quiet, later]), 1);
      const localQuiet = LiveMiniCandidate(name: 'local', isLocal: true);
      expect(liveMiniPick(const [localQuiet, quiet]), 1);
      expect(liveMiniPick(const [localQuiet]), 0);
    });
  });
}
