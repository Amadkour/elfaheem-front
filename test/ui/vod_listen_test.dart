// Course video player: the quality switch (it used to close the player) and listen-only (D-104).
//
//   pure        vodSwitchDecision · VodCarry.seekIn · vodListenVariant · vodFraction / vodFinished · MediaFocus
//   regression  inside a role shell (D-081) the picker sheet sits on the ROOT navigator and the player on the tab's:
//               closing the sheet with the player's context closed the player — showVodPicker closes it with its own
//   session     VodListenSession over a fake controller: play / pause / ±10 s / scrub, the audio track swap and the
//               way back, resume position, 75 % mark, one sound at a time (a new player or a live room stops it)
//   layer       the bar at the top of the app, the app below it without the status-bar inset twice, Expand back to
//               the player with the SAME controller, Listen only from the player, close
//   layout      the bar in every state and the player's button at 320×640 / 1400×900, ar / en, text × 1.3
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/media_focus.dart';
import 'package:flutter_education_app/design/app_shell.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/shared/session/material/session_material_model.dart';
import 'package:flutter_education_app/features/shared/session/video/video_player_screen.dart';
import 'package:flutter_education_app/features/shared/session/video/vod_listen.dart';
import 'package:flutter_education_app/features/shared/session/video/vod_listen_bar.dart';
import 'package:flutter_education_app/features/shared/session/video/vod_listen_layer.dart';
import 'package:flutter_education_app/features/shared/session/video/vod_player_parts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'layout_harness.dart';

/// A controller that never touches a platform player.
class FakeVc extends VideoPlayerController {
  FakeVc({Duration duration = const Duration(minutes: 40), Duration at = Duration.zero, bool playing = false, this.tag = 'v'})
      : super.networkUrl(Uri.parse('https://media.test/$tag.mp4')) {
    value = VideoPlayerValue(
        duration: duration, position: at, isInitialized: true, isPlaying: playing, size: const Size(1280, 720));
  }

  final String tag;
  bool disposed = false;
  int plays = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> play() async {
    plays++;
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async => value = value.copyWith(isPlaying: false);

  @override
  Future<void> seekTo(Duration position) async => value = value.copyWith(position: position);

  @override
  Future<void> setPlaybackSpeed(double speed) async => value = value.copyWith(playbackSpeed: speed);

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setClosedCaptionFile(Future<ClosedCaptionFile>? closedCaptionFile) async {}

  @override
  Future<Duration?> get position async => value.position;

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }
}

SessionMaterialModel _lecture({bool audio = true, bool tiers = true}) => SessionMaterialModel(
      id: 11,
      sessionId: 4,
      name: 'المحاضرة الثالثة — التكامل بالتجزئة وتطبيقاته في الفيزياء',
      type: SessionMaterialType.video,
      order: 0,
      createdAt: DateTime(2026),
      completed: false,
      urlHigh: tiers ? 'https://media.test/high.mp4' : 'https://media.test/only.mp4',
      urlMedium: tiers ? 'https://media.test/medium.mp4' : 'https://media.test/only.mp4',
      urlLow: tiers ? 'https://media.test/low.mp4' : 'https://media.test/only.mp4',
      rawUrlHigh: tiers ? 'https://media.test/high.mp4' : null,
      rawUrlMedium: tiers ? 'https://media.test/medium.mp4' : null,
      rawUrlLow: tiers ? 'https://media.test/low.mp4' : null,
      audioUrl: audio ? 'https://media.test/audio_high.ogg' : null,
      audioMediumUrl: audio ? 'https://media.test/audio_medium.ogg' : null,
    );

MaterialVariant _v(String url, {QualityTier tier = QualityTier.medium, bool audio = false}) =>
    MaterialVariant(url: url, tier: tier, isAudio: audio);

void main() {
  // package:floating (Android PiP) has no test side: the player's dispose call would fail after the test.
  setUpAll(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('floating'), (_) async => null));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MediaFocus.reset();
    VodListenSession.instance.debugReset();
  });

  group('pure', () {
    test('a switch to the stream playing does nothing, one without a link is refused', () {
      final a = _v('https://media.test/low.mp4');
      expect(vodSwitchDecision(a, _v('https://media.test/low.mp4')), VodSwitch.same);
      expect(vodSwitchDecision(a, _v('https://media.test/high.mp4')), VodSwitch.go);
      expect(vodSwitchDecision(a, const MaterialVariant(url: null, tier: QualityTier.low, isAudio: false)),
          VodSwitch.unavailable);
      expect(vodSwitchDecision(a, _v('')), VodSwitch.unavailable);
    });

    test('the place carries over, kept inside a shorter stream', () {
      const c = VodCarry(position: Duration(minutes: 12, seconds: 3), playing: true, speed: 1.5, captionsOn: true);
      expect(c.seekIn(const Duration(minutes: 40)), const Duration(minutes: 12, seconds: 3));
      expect(c.seekIn(Duration.zero), const Duration(minutes: 12, seconds: 3), reason: 'unknown length');
      expect(c.seekIn(const Duration(minutes: 12)), const Duration(minutes: 11, seconds: 59, milliseconds: 500));
      expect(const VodCarry(position: Duration.zero, playing: false).seekIn(const Duration(minutes: 3)), Duration.zero);
      expect(const VodCarry(position: Duration(seconds: 2), playing: false).seekIn(const Duration(milliseconds: 300)),
          Duration.zero);
    });

    test('listen-only plays the audio track paired with the quality, else the lightest video', () {
      final m = _lecture();
      final high = m.videoVariants.last;
      final low = m.videoVariants.first;
      expect(high.tier, QualityTier.high);
      expect(vodListenVariant(m, high).url, 'https://media.test/audio_high.ogg');
      expect(vodListenVariant(m, low).url, 'https://media.test/audio_medium.ogg');
      final noAudio = _lecture(audio: false);
      expect(vodListenVariant(noAudio, noAudio.videoVariants.last).url, 'https://media.test/low.mp4');
      expect(vodListenVariant(noAudio, noAudio.videoVariants.first).url, 'https://media.test/low.mp4');
      final local = _v('http://127.0.0.1:5555/v');
      expect(vodListenVariant(m, local, offline: true), same(local), reason: 'an offline copy is the only stream');
      final audio = m.audioVariants.first;
      expect(vodListenVariant(m, audio), same(audio));
    });

    test('progress fraction and the end', () {
      expect(vodFraction(const Duration(minutes: 10), const Duration(minutes: 40)), 0.25);
      expect(vodFraction(const Duration(minutes: 10), Duration.zero), 0);
      expect(vodFraction(Duration.zero, const Duration(minutes: 40), dragging: 1.4), 1);
      expect(vodFinished(const Duration(minutes: 40), const Duration(minutes: 40), playing: false), isTrue);
      expect(vodFinished(const Duration(minutes: 40), const Duration(minutes: 40), playing: true), isFalse);
      expect(vodFinished(const Duration(minutes: 3), const Duration(minutes: 40), playing: false), isFalse);
    });

    test('one sound at a time: a claim stops the holder that asked to be told', () {
      var stopped = 0;
      final bar = Object(), player = Object(), room = Object();
      MediaFocus.claim(bar, onLost: () => stopped++);
      MediaFocus.claim(bar, onLost: () => stopped++);
      expect(stopped, 0, reason: 'claiming again is not a loss');
      MediaFocus.claim(player);
      expect(stopped, 1);
      expect(MediaFocus.holds(bar), isFalse);
      MediaFocus.claim(room);
      expect(MediaFocus.holds(player), isFalse);
      expect(stopped, 1, reason: 'the player only claimed');
    });
  });

  group('regression: the picker closed the player', () {
    late StorageService storage;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = await StorageService.getInstance();
      AppConfig.lang = 'en';
    });

    Future<void> pumpShell(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider(create: (_) => MyAuthProvider(storage: storage))],
        child: ThemeConfigScope(
          provider: ThemeConfigProvider(api: ApiClient()),
          child: MaterialApp(
            home: LayoutBuilder(
              builder: (context, box) => AppShell(
                width: box.maxWidth,
                currentIndex: 0,
                onTap: (_) {},
                items: [
                  DashboardItem(Icons.home_outlined, Icons.home, 'Home', null, const _CourseTab()),
                  DashboardItem(Icons.person_outline, Icons.person, 'Profile', null, const Text('profile')),
                ],
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open lecture'));
      await tester.pumpAndSettle();
      expect(find.text('player page'), findsOneWidget);
    }

    testWidgets('closing the sheet with the player context pops the PLAYER (the old code)', (tester) async {
      await pumpShell(tester);
      await tester.tap(find.text('old picker'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('720p'));
      await tester.pumpAndSettle();
      expect(find.text('player page'), findsNothing, reason: 'the root cause: the tab navigator popped the player');
      expect(find.text('720p'), findsOneWidget, reason: '… and the sheet on the root navigator stayed open');
    });

    testWidgets('showVodPicker closes only the sheet and hands back the choice', (tester) async {
      await pumpShell(tester);
      await tester.tap(find.text('new picker'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('720p'));
      await tester.pumpAndSettle();
      expect(find.text('player page'), findsOneWidget);
      expect(find.text('picked 720p'), findsOneWidget);
      expect(find.text('1080p'), findsNothing, reason: 'the sheet is closed');
    });
  });

  group('session', () {
    final m = _lecture();
    VodListenHandoff handoff(FakeVc vc, {MaterialVariant? variant}) => VodListenHandoff(
          controller: vc,
          material: m,
          current: m,
          variant: variant ?? m.videoVariants.last,
          speed: 1.25,
        );

    testWidgets('takes over, swaps to the audio track at the same place, and gives the way back', (tester) async {
      final opened = <String>[];
      final audio = FakeVc(tag: 'audio', at: Duration.zero);
      VodListenSession.opener = (v, {at = Duration.zero, speed = 1.0}) async {
        opened.add(v.url!);
        await audio.seekTo(at);
        await audio.setPlaybackSpeed(speed);
        return audio;
      };
      addTearDown(() => VodListenSession.opener =
          (v, {at = Duration.zero, speed = 1.0}) => openVodController(v, at: at, speed: speed));
      final vc = FakeVc(at: const Duration(minutes: 12), playing: true);
      final s = VodListenSession.instance;
      s.start(handoff(vc), play: true);
      await tester.pump();
      expect(s.active, isTrue);
      expect(opened, ['https://media.test/audio_high.ogg'], reason: '1080p on screen → the 192 kbps track');
      final h = s.handoff!;
      expect(h.controller, same(audio));
      expect(h.variant.isAudio, isTrue);
      expect(h.returnTo?.url, 'https://media.test/high.mp4');
      expect(audio.value.position, const Duration(minutes: 12));
      expect(audio.value.playbackSpeed, 1.25);
      expect(audio.value.isPlaying, isTrue);
      expect(vc.disposed, isTrue, reason: 'the picture stream is let go');
      expect(vc.value.isPlaying, isFalse, reason: 'never two sounds');

      s.seekBy(10);
      expect(audio.value.position, const Duration(minutes: 12, seconds: 10));
      s.seekBy(-3600);
      expect(audio.value.position, Duration.zero);
      s.seekToFraction(0.5);
      expect(audio.value.position, const Duration(minutes: 20));
      s.togglePlay();
      expect(audio.value.isPlaying, isFalse);
      s.togglePlay();
      expect(audio.value.isPlaying, isTrue);

      final back = s.takeBack();
      expect(back, same(h));
      expect(s.active, isFalse);
      expect(audio.disposed, isFalse, reason: 'Expand keeps the controller');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('vod_pos_4_11'), const Duration(minutes: 20).inMilliseconds, reason: 'resume position saved');
    });

    testWidgets('a failed swap keeps the stream on screen playing', (tester) async {
      VodListenSession.opener = (v, {at = Duration.zero, speed = 1.0}) async => throw StateError('404');
      addTearDown(() => VodListenSession.opener =
          (v, {at = Duration.zero, speed = 1.0}) => openVodController(v, at: at, speed: speed));
      final vc = FakeVc(at: const Duration(minutes: 3), playing: true);
      VodListenSession.instance.start(handoff(vc), play: true);
      await tester.pump();
      final h = VodListenSession.instance.handoff!;
      expect(h.controller, same(vc));
      expect(h.returnTo, isNull);
      expect(vc.value.isPlaying, isTrue);
      expect(VodListenSession.instance.switching, isFalse);
      await VodListenSession.instance.stop();
      await tester.pump();
      expect(vc.disposed, isTrue);
    });

    testWidgets('another player or a live room stops the bar; 75 % marks the lecture watched once', (tester) async {
      final vc = FakeVc(at: const Duration(minutes: 1), playing: true);
      // already the audio track: no swap
      VodListenSession.instance.start(handoff(vc, variant: m.audioVariants.first), play: true);
      await tester.pump();
      expect(VodListenSession.instance.handoff!.controller, same(vc));
      await vc.seekTo(const Duration(minutes: 31));
      expect(VodListenSession.instance.handoff!.completionSent, isTrue);
      MediaFocus.claim(Object()); // RoomPage.initState / a new VideoPlayerScreen
      await tester.pump();
      expect(VodListenSession.instance.active, isFalse);
      expect(vc.disposed, isTrue);
    });
  });

  group('layer', () {
    setUp(() {
      VodListenLayer.debugSignedIn = (_) => true;
      AppConfig.lang = 'en';
    });
    tearDown(() => VodListenLayer.debugSignedIn = null);

    Widget app(GlobalKey<NavigatorState> key) => ThemeConfigScope(
          provider: ThemeConfigProvider(api: ApiClient()),
          child: MaterialApp(
            navigatorKey: key,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(padding: const EdgeInsets.only(top: 24)),
              child: VodListenLayer(navigatorKey: key, child: child!),
            ),
            home: Scaffold(
              appBar: AppBar(title: const Text('Courses home')),
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => VideoPlayerScreen(material: _lecture(audio: false), resume: _fresh()))),
                    child: const Text('open lecture'),
                  ),
                ),
              ),
            ),
          ),
        );

    testWidgets('Listen only → the bar on top, the app below it; Expand → the same controller; Close', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS; // no Android PiP timer in tests
      try {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey<NavigatorState>();
        await tester.pumpWidget(app(key));
        await tester.tap(find.text('open lecture'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.byType(VideoPlayerScreen), findsOneWidget);
        final vc = _lastFresh!;

        await tester.tap(find.byType(VodListenButton));
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.byType(VideoPlayerScreen), findsNothing, reason: 'the player page closed');
        expect(find.byType(VodListenBar), findsOneWidget);
        expect(find.text('Courses home'), findsOneWidget, reason: 'the person is back in the app');
        expect(VodListenSession.instance.handoff!.controller, same(vc), reason: 'no audio track here, the lowest tier already plays');
        expect(vc.value.isPlaying, isTrue);
        expect(vc.disposed, isFalse);
        // the bar takes the status bar: the page below it gets no top inset a second time
        final barBottom = tester.getBottomLeft(find.byType(VodListenBar)).dy;
        expect(barBottom, 24 + VodListenBar.height);
        expect(tester.getTopLeft(find.byType(AppBar)).dy, barBottom);
        expect(MediaQuery.paddingOf(tester.element(find.text('open lecture'))).top, 0);

        final sem = tester.ensureSemantics();
        await tester.pump();
        expect(find.semantics.byLabel('vod_expand'), findsOneWidget, reason: 'the bar is in the semantics tree');
        sem.dispose();
        await tester.tap(find.byIcon(Icons.open_in_full_rounded));
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.byType(VodListenBar), findsNothing);
        expect(find.byType(VideoPlayerScreen), findsOneWidget);
        expect(VodListenSession.instance.active, isFalse);
        expect(vc.disposed, isFalse, reason: 'the same controller plays on in the player');

        await tester.tap(find.byType(VodListenButton));
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.tap(find.byIcon(Icons.close_rounded));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.byType(VodListenBar), findsNothing);
        expect(vc.disposed, isTrue);
        expect(tester.getTopLeft(find.byType(AppBar)).dy, 0);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('layout', () {
    Widget bars() => ListView(children: [
          for (final s in _barStates)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: VodListenBar(
                title: s.$1,
                position: s.$2,
                duration: const Duration(hours: 1, minutes: 12, seconds: 9),
                buffered: 0.6,
                playing: s.$3,
                busy: s.$4,
                speed: s.$5,
                onPlayPause: () {},
                onSeekBy: (_) {},
                onSeekTo: (_) {},
                onExpand: () {},
                onClose: () {},
              ),
            ),
          VodListenBar(
            title: 'x',
            position: Duration.zero,
            duration: Duration.zero,
            onPlayPause: () {},
            onSeekBy: (_) {},
            onSeekTo: (_) {},
            onExpand: () {},
            onClose: () {},
          ),
        ]);

    testWidgets('the bar never overflows', (tester) async {
      await expectNoLayoutErrors(tester, bars);
    });

    testWidgets('the bar scrubs', (tester) async {
      double? to;
      await tester.pumpWidget(layoutHost(VodListenBar(
        title: 'Lecture',
        position: const Duration(minutes: 10),
        duration: const Duration(minutes: 40),
        playing: true,
        onPlayPause: () {},
        onSeekBy: (_) {},
        onSeekTo: (f) => to = f,
        onExpand: () {},
        onClose: () {},
      )));
      final bar = tester.getRect(find.byType(VodListenBar));
      await tester.dragFrom(Offset(bar.left + 20, bar.bottom - 4), Offset(bar.width / 2, 0));
      await tester.pump();
      expect(to, isNotNull);
      expect(to!, greaterThan(0.45));
    });

    testWidgets('every bar button can be activated through semantics (screen readers, the web)', (tester) async {
      final handle = tester.ensureSemantics();
      final taps = <String>[];
      await tester.pumpWidget(layoutHost(VodListenBar(
        title: 'Lecture',
        position: const Duration(minutes: 10),
        duration: const Duration(minutes: 40),
        playing: true,
        onPlayPause: () => taps.add('play'),
        onSeekBy: (s) => taps.add('seek$s'),
        onSeekTo: (_) {},
        onExpand: () => taps.add('expand'),
        onClose: () => taps.add('close'),
      )));
      for (final l in ['vod_pause', 'vod_back10', 'vod_fwd10', 'vod_expand', 'vod_close_listen']) {
        tester.semantics.tap(find.semantics.byLabel(l));
      }
      expect(taps, ['play', 'seek-10', 'seek10', 'expand', 'close']);
      handle.dispose();
    });

    testWidgets('the player button never overflows', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => ColoredBox(
          color: VodInk.letterbox,
          child: Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              VodListenButton(onTap: () {}, tooltip: 'vod_listen_only_hint', label: 'vod_listen_short'),
              VodListenButton(onTap: () {}, tooltip: 'vod_listen_only_hint'),
            ]),
          ),
        ),
      );
    });
  });
}

const _barStates = <(String, Duration, bool, bool, double)>[
  ('المحاضرة الثالثة — التكامل بالتجزئة وتطبيقاته في الفيزياء والهندسة', Duration(minutes: 12, seconds: 3), true, false, 1.0),
  ('Lecture 3 — Integration by parts and its uses in physics and engineering', Duration(minutes: 40), false, false, 1.5),
  ('مقدمة', Duration(seconds: 4), true, true, 2.0),
  ('Ende', Duration(hours: 1, minutes: 12, seconds: 9), false, false, 0.75),
];

FakeVc? _lastFresh;

/// A handoff as if the bar had just given the player back (the player then plays on without POST …/play).
VodListenHandoff _fresh() {
  final m = _lecture(audio: false);
  final vc = FakeVc(at: const Duration(minutes: 5), playing: true, tag: 'low');
  _lastFresh = vc;
  return VodListenHandoff(controller: vc, material: m, current: m, variant: m.videoVariants.first);
}

class _CourseTab extends StatelessWidget {
  const _CourseTab();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _PlayerStandIn())),
            child: const Text('open lecture'),
          ),
        ),
      );
}

/// Stands in for VideoPlayerScreen: a page of the tab's navigator that opens a quality sheet.
class _PlayerStandIn extends StatefulWidget {
  const _PlayerStandIn();

  @override
  State<_PlayerStandIn> createState() => _PlayerStandInState();
}

class _PlayerStandInState extends State<_PlayerStandIn> {
  String? _picked;

  Widget _options(void Function(String) onSelect) => Material(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final q in const ['360p', '720p', '1080p'])
            ListTile(title: Text(q), onTap: () => onSelect(q)),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('player page'),
            if (_picked != null) Text('picked $_picked'),
            // what _openStreamPicker did before
            TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => _options((q) {
                  Navigator.pop(context);
                  setState(() => _picked = q);
                }),
              ),
              child: const Text('old picker'),
            ),
            TextButton(
              onPressed: () async {
                final q = await showVodPicker<String>(context, (_, pick) => _options(pick));
                if (mounted && q != null) setState(() => _picked = q);
              },
              child: const Text('new picker'),
            ),
          ]),
        ),
      );
}
