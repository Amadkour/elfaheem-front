// The course video player screen itself (VideoPlayerScreen), over FakeApi and a controller that never touches a
// platform player (VideoPlayerScreen.debugController):
//   • playlist  picking another lecture switches IN PLACE: the same page and State, no second route, the next
//               lecture's own POST …/play, the screen protection never flips off between the two
//   • stale     a slow …/play answer for the lecture left behind never plays under the new lecture's title, and
//               its error never closes the player on the new lecture
//   • refusals  VIEW_LIMIT_REACHED → the "No views left" dialog, then the player closes; DEVICE_MISMATCH → the
//               device check + the blocked-device dialog, then the player closes
//   • security  ScreenSecurity is taken once when the page opens and given back once when it closes — after a
//               normal back, after a refusal, after a failed play (D-083)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/media_focus.dart';
import 'package:flutter_education_app/core/screen_security.dart';
import 'package:flutter_education_app/features/sessions/material/session_material_model.dart';
import 'package:flutter_education_app/features/sessions/video/video_player_screen.dart';
import 'package:flutter_education_app/features/sessions/video/vod_listen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../support/fake_api.dart';

/// A controller that never touches a platform player; remembers the URL it was made for.
class _FakeVc extends VideoPlayerController {
  _FakeVc(super.url) : super.networkUrl() {
    value = VideoPlayerValue(duration: const Duration(minutes: 40), isInitialized: true, size: const Size(1280, 720));
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> play() async => value = value.copyWith(isPlaying: true);

  @override
  Future<void> pause() async => value = value.copyWith(isPlaying: false);

  @override
  Future<void> seekTo(Duration position) async => value = value.copyWith(position: position);

  @override
  Future<void> setPlaybackSpeed(double speed) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setClosedCaptionFile(Future<ClosedCaptionFile>? closedCaptionFile) async {}

  @override
  Future<Duration?> get position async => value.position;
}

SessionMaterialModel _lecture(int id, String name) => SessionMaterialModel(
      id: id,
      sessionId: 4,
      name: name,
      type: SessionMaterialType.video,
      order: id,
      createdAt: DateTime(2026),
      completed: false,
      requiresPlay: true, // the list hid the URLs: POST …/play gives them (and counts the view)
    );

final _one = _lecture(11, 'Lecture one');
final _two = _lecture(12, 'Lecture two');
final _limit = _lecture(13, 'Lecture three');
final _device = _lecture(14, 'Lecture four');
final _five = _lecture(15, 'Lecture five');

Map<String, Object?> _play(int id) => {'url': 'https://media.test/$id.mp4', 'views_left': 2};

FakeResponse _refused(String code) => FakeResponse(403, {
      'detail': {'code': code, 'message': 'refused: $code'},
    });

/// iOS: no Android PiP timer in tests, and the phone branches (brightness / volume) run.
final _ios = TargetPlatformVariant.only(TargetPlatform.iOS);

void main() {
  late FakeApi api;
  late List<String> security;
  final made = <String>[];

  setUpAll(() {
    // package:floating (Android PiP) has no test side
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('floating'), (_) async => null);
  });

  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    MediaFocus.reset();
    VodListenSession.instance.debugReset();
    made.clear();
    VideoPlayerScreen.debugLocalCopy = (_, _) async => null; // no downloaded copy
    VideoPlayerScreen.debugController = (url) {
      made.add(url.toString());
      return _FakeVc(url);
    };
    security = [];
    ScreenSecurity.instance.debugReset();
    ScreenSecurity.instance.debugPlatform = (call, _) async => security.add(call);
    api = FakeApi({
      'POST /api/v1/sessions/4/materials/11/play': (_) => _play(11),
      'POST /api/v1/sessions/4/materials/12/play': (_) => _play(12),
      'POST /api/v1/sessions/4/materials/13/play': (_) => _refused('VIEW_LIMIT_REACHED'),
      'POST /api/v1/sessions/4/materials/14/play': (_) => _refused('DEVICE_MISMATCH'),
      'POST /api/v1/sessions/4/materials/15/play': (_) => _play(15),
      'GET /api/v1/devices/status': (_) => {'allowed': false, 'can_request': false},
    }, latency: const Duration(milliseconds: 100))
      ..install();
  });

  tearDown(() {
    api.uninstall();
    VideoPlayerScreen.debugController = null;
    VideoPlayerScreen.debugLocalCopy = null;
    ScreenSecurity.instance.debugReset();
  });

  final pages = <Route<dynamic>>[];
  Widget app(Widget player) => ThemeConfigScope(
        provider: ThemeConfigProvider(api: ApiClient()),
        child: MaterialApp(
          navigatorObservers: [_Pushes(pages)],
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => player)),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> frames(WidgetTester tester, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> open(WidgetTester tester, Widget player) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    pages.clear();
    await tester.pumpWidget(app(player));
    await tester.tap(find.text('open'));
    await frames(tester);
  }

  /// Closes the player with the system back and lets its dispose run.
  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await frames(tester, 20);
  }

  int plays(int id) => api.calls.where((c) => c.key == 'POST /api/v1/sessions/4/materials/$id/play').length;


  testWidgets('another lecture from the list plays IN PLACE: same page, same State, its own …/play', (tester) async {
    await open(tester, VideoPlayerScreen(material: _one, playlist: [_one, _two]));
    expect(made, ['https://media.test/11.mp4']);
    final state = tester.state(find.byType(VideoPlayerScreen));
    final routes = pages.length;

    await tester.tap(find.text('Lectures'));
    await frames(tester);
    await tester.tap(find.text('Lecture two').last);
    await frames(tester, 20);

    expect(plays(12), 1);
    expect(made.last, 'https://media.test/12.mp4', reason: 'the new lecture plays its own stream');
    expect(find.byType(VideoPlayerScreen), findsOneWidget);
    expect(tester.state(find.byType(VideoPlayerScreen)), same(state), reason: 'switched in place');
    expect(pages.length, routes, reason: 'no second player page was pushed (the lecture sheet came and went)');
    expect(security, ['protect'], reason: 'the protection never flipped off between the two lectures');

    await back(tester);
    expect(find.byType(VideoPlayerScreen), findsNothing);
    expect(security, ['protect', 'unprotect']);
    expect(ScreenSecurity.instance.isProtected, isFalse);
    expect(api.unmatched, isEmpty);
  }, variant: _ios);

  Future<void> pick(WidgetTester tester, String lecture) async {
    await tester.tap(find.text('Lectures'));
    await frames(tester, 6);
    await tester.tap(find.text(lecture).last);
    await frames(tester, 8); // the sheet closes
  }

  /// Lecture one plays; then on a slow server the student picks lecture two and, while its …/play is still out,
  /// lecture five (the previous picture stays on screen with its controls while the next lecture loads).
  Future<void> moveOnWhileLoading(WidgetTester tester) async {
    await open(tester, VideoPlayerScreen(material: _one, playlist: [_one, _two, _five]));
    expect(made, ['https://media.test/11.mp4']);
    api.uninstall();
    api = FakeApi(api.routes, latency: const Duration(milliseconds: 1500))..install();
    await pick(tester, 'Lecture two');
    expect(api.calls.map((c) => c.key), ['POST /api/v1/sessions/4/materials/12/play']);
    await pick(tester, 'Lecture five');
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50)); // both answers arrive, lecture two's first
    }
    expect(plays(15), 1);
  }

  testWidgets("a slow answer for the lecture left behind never plays under the new lecture's title", (tester) async {
    await moveOnWhileLoading(tester);
    expect(made, ['https://media.test/11.mp4', 'https://media.test/15.mp4'],
        reason: "lecture two's stream was never opened under lecture five");
    expect(find.byType(VideoPlayerScreen), findsOneWidget);
    await back(tester);
    expect(security, ['protect', 'unprotect']);
  }, variant: _ios);

  testWidgets("a refusal for the lecture left behind never closes the player on the new one", (tester) async {
    api.routes['POST /api/v1/sessions/4/materials/12/play'] = (_) => _refused('VIEW_LIMIT_REACHED');
    await moveOnWhileLoading(tester);
    expect(find.text('No views left'), findsNothing);
    expect(find.byType(VideoPlayerScreen), findsOneWidget, reason: 'lecture five plays on');
    expect(made, ['https://media.test/11.mp4', 'https://media.test/15.mp4']);
    await back(tester);
    expect(security, ['protect', 'unprotect']);
  }, variant: _ios);

  testWidgets('VIEW_LIMIT_REACHED: the "No views left" dialog, then the player closes and gives the protection back',
      (tester) async {
    await open(tester, VideoPlayerScreen(material: _limit));
    expect(find.text('No views left'), findsOneWidget);
    expect(find.text('refused: VIEW_LIMIT_REACHED'), findsOneWidget, reason: "the server's own words");
    expect(made, isEmpty, reason: 'nothing plays');
    expect(ScreenSecurity.instance.isProtected, isTrue, reason: 'still on screen behind the dialog');

    await tester.tap(find.text('OK'));
    await frames(tester, 20);
    expect(find.byType(VideoPlayerScreen), findsNothing, reason: 'the player closed');
    expect(security, ['protect', 'unprotect']);
  }, variant: _ios);

  testWidgets('DEVICE_MISMATCH: the device check, the blocked-device dialog, then the player closes', (tester) async {
    await open(tester, VideoPlayerScreen(material: _device));
    await frames(tester);
    expect(api.calls.map((c) => c.key), contains('GET /api/v1/devices/status'));
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(find.byIcon(Icons.phonelink_lock_rounded), findsOneWidget);
    expect(made, isEmpty);

    await tester.tap(find.descendant(of: dialog, matching: find.byType(TextButton)).first); // Close
    await frames(tester, 20);
    expect(find.byType(VideoPlayerScreen), findsNothing);
    expect(security, ['protect', 'unprotect']);
  }, variant: _ios);

  testWidgets('a refused play (server error) closes the player and gives the protection back', (tester) async {
    api.routes['POST /api/v1/sessions/4/materials/11/play'] = (_) => const FakeResponse(500, {'detail': 'boom'});
    await open(tester, VideoPlayerScreen(material: _one));
    await frames(tester, 20);
    expect(find.byType(VideoPlayerScreen), findsNothing);
    expect(made, isEmpty);
    expect(security, ['protect', 'unprotect']);
  }, variant: _ios);

  testWidgets('a broken play answer keeps the page with its error; back still gives the protection back',
      (tester) async {
    api.routes['POST /api/v1/sessions/4/materials/11/play'] = (_) => const ['not', 'a', 'map'];
    await open(tester, VideoPlayerScreen(material: _one));
    expect(find.byType(VideoPlayerScreen), findsOneWidget);
    expect(made, isEmpty);
    expect(security, ['protect']);
    await back(tester);
    expect(security, ['protect', 'unprotect']);
    expect(ScreenSecurity.instance.isProtected, isFalse);
  }, variant: _ios);

  testWidgets('another protected screen closing never switches the player\'s protection off', (tester) async {
    final exam = Object();
    await ScreenSecurity.instance.protect(exam);
    await open(tester, VideoPlayerScreen(material: _one));
    await ScreenSecurity.instance.release(exam);
    expect(ScreenSecurity.instance.isProtected, isTrue, reason: 'the player still owns it');
    await back(tester);
    expect(ScreenSecurity.instance.isProtected, isFalse);
    expect(security, ['protect', 'unprotect']);
  }, variant: _ios);
}

/// Counts the pages pushed on the app's navigator (sheets and dialogs are popup routes, not pages).
class _Pushes extends NavigatorObserver {
  _Pushes(this.pages);
  final List<Route<dynamic>> pages;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) pages.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) pages.remove(route);
  }
}
