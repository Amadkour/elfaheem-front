// Games v4 T24: GameAudio against a fake voice (CONTRACT §8, §9): SFX silent during a recitation, stop at end_ms,
// the reciter switch replays, music pauses and returns, the music loop crosses over before the track ends.
import 'dart:async';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/games/core/game_audio.dart';
import 'package:flutter_education_app/features/games/core/recitation_cache.dart';
import 'package:flutter_education_app/features/games/shell/game_sounds.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeVoice implements AudioVoice {
  final plays = <({AudioRef ref, int startMs, double volume})>[];
  final volumes = <double>[];
  int stops = 0;
  bool disposed = false;
  final pos = StreamController<int>.broadcast();
  final dur = StreamController<int>.broadcast();
  final done = StreamController<void>.broadcast();

  @override
  Future<void> play(AudioRef ref, {int startMs = 0, double volume = 1}) async =>
      plays.add((ref: ref, startMs: startMs, volume: volume));
  @override
  Future<void> setVolume(double v) async => volumes.add(v);
  @override
  Future<void> stop() async => stops++;
  @override
  Stream<int> get positionMs => pos.stream;
  @override
  Stream<int> get durationMs => dur.stream;
  @override
  Stream<void> get completed => done.stream;
  @override
  Future<void> dispose() async => disposed = true;
}

class FakeSfx implements GameSoundPlayer {
  final played = <GameSound>[];
  @override
  Future<void> preload(Iterable<GameSound> sounds) async {}
  @override
  Future<void> play(GameSound sound) async => played.add(sound);
  @override
  Future<void> dispose() async {}
}

class NoCache extends RecitationCache {
  NoCache() : super(root: () async => Directory.systemTemp, fetch: (u, f) async {});
  @override
  Future<File?> cached(String reciter, String url) async => null;
  @override
  Future<File?> ensure(String reciter, String url) async => null;
}

Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<FakeVoice> voices;
  late FakeSfx sfx;
  final audio = GameAudio.instance;

  setUp(() async {
    await audio.reset();
    GameFeedback.instance.reset();
    GameFeedback.instance.haptic = (_) {};
    sfx = FakeSfx();
    GameFeedback.instance.playerFactory = () => sfx;
    GameFeedback.instance.mediaBusy = () => false;
    AppConfig.disableList = [];
    voices = [];
    audio.voiceFactory = () {
      final v = FakeVoice();
      voices.add(v);
      return v;
    };
    audio.cache = NoCache();
    audio.saveReciter = (_) async {};
  });

  tearDown(() async {
    await audio.reset();
    GameFeedback.instance.reset();
  });

  test('every SFX is silent while a recitation plays, and back after', () async {
    GameFeedback.instance.play(GameSound.correct);
    expect(sfx.played, [GameSound.correct]);
    await audio.playRecitation([const RecitationSegment(url: 'https://x/a.mp3', ref: '1:1')]);
    await pump();
    expect(audio.recitationActive.value, isTrue);
    GameFeedback.instance.play(GameSound.correct);
    GameFeedback.instance.play(GameSound.finish);
    expect(sfx.played, [GameSound.correct], reason: 'silent during recitation');
    await audio.stopRecitation();
    GameFeedback.instance.play(GameSound.finish);
    expect(sfx.played, [GameSound.correct, GameSound.finish]);
  });

  test('a segment seeks to start_ms and stops at end_ms, then the next one plays', () async {
    await audio.playRecitation([
      const RecitationSegment(url: 'https://x/112.mp3', startMs: 1000, endMs: 2000, ref: '112:1'),
      const RecitationSegment(url: 'https://x/112.mp3', startMs: 2000, endMs: 3000, ref: '112:2'),
    ]);
    await pump();
    final v = voices.first;
    expect(v.plays.single.startMs, 1000);
    v.pos.add(1500);
    await pump();
    expect(v.stops, 0);
    v.pos.add(2000); // end_ms reached
    await pump();
    expect(v.stops, greaterThan(0));
    expect(v.plays.length, 2);
    expect(v.plays[1].startMs, 2000);
    expect(audio.currentIndex, 1);
    v.pos.add(3100);
    await pump();
    expect(audio.recitationActive.value, isFalse);
  });

  test('the last 300 ms are cut by a timer, not the next position tick', () async {
    await audio.playRecitation([const RecitationSegment(url: 'https://x/s.mp3', startMs: 0, endMs: 1000, ref: '1:1')]);
    await pump();
    voices.first.pos.add(800);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(audio.recitationActive.value, isFalse);
  });

  test('switchReciter re-resolves, saves the choice and replays the current ayah', () async {
    String? saved;
    List<String>? asked;
    audio.saveReciter = (k) async => saved = k;
    audio.fetchAudio = (refs, key) async {
      asked = refs;
      return {
        for (final r in refs) r: RecitationSegment(url: 'https://x/$key/$r.mp3', reciter: key, ref: r),
      };
    };
    await audio.playRecitation([
      const RecitationSegment(url: 'https://x/alafasy/112_1.mp3', ref: '112:1', reciter: 'alafasy'),
      const RecitationSegment(url: 'https://x/alafasy/112_2.mp3', ref: '112:2', reciter: 'alafasy'),
    ], reciter: 'alafasy');
    await pump();
    voices.first.done.add(null); // ayah 1 ends -> ayah 2 plays
    await pump();
    expect(audio.currentIndex, 1);
    expect(await audio.switchReciter('husary'), isTrue);
    await pump();
    expect(asked, ['112:1', '112:2']);
    expect(saved, 'husary');
    expect(audio.reciterKey, 'husary');
    expect(audio.currentIndex, 1, reason: 'the current ayah is replayed');
    final played = voices.expand((v) => v.plays).map((p) => p.ref.path).toList();
    expect(played.last, 'https://x/husary/112:2.mp3');
  });

  test('a failed switch keeps the old voice', () async {
    audio.fetchAudio = (r, k) async => throw StateError('x');
    await audio.playRecitation([const RecitationSegment(url: 'https://x/a.mp3', ref: '1:1')]);
    await pump();
    expect(await audio.switchReciter('husary'), isFalse);
    expect(audio.recitationActive.value, isTrue);
  });

  test('music pauses for a recitation and comes back; games.sounds off = no music', () async {
    await audio.playMusic(GameMusic.calm);
    await pump();
    expect(voices.length, 2);
    expect(voices[0].plays.single.ref.path, 'sounds/games/music_calm.mp3');
    await audio.playRecitation([const RecitationSegment(url: 'https://x/a.mp3', ref: '1:1')]);
    await pump();
    expect(voices[0].disposed, isTrue, reason: 'music stopped');
    await audio.stopRecitation();
    await pump();
    expect(voices.where((v) => v.plays.any((p) => p.ref.kind == 'asset')).length, 2, reason: 'one new music voice');
    await audio.stopMusic();

    AppConfig.disableList = [kGamesSoundsFeatureKey];
    voices.clear();
    await audio.playMusic(GameMusic.kids);
    expect(voices, isEmpty);
  });

  test('the music loop crosses over before the end of the track', () async {
    final a = FakeVoice(), b = FakeVoice();
    final loop = CrossfadeLoop(
        voices: [a, b], ref: const AudioRef.asset('m.mp3'), volume: 0.5, fade: const Duration(milliseconds: 100));
    await loop.start();
    a.dur.add(10000);
    a.pos.add(5000);
    await pump();
    expect(b.plays, isEmpty);
    a.pos.add(9950); // inside the last [fade]
    await pump();
    expect(b.plays.single.startMs, 0);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(loop.activeIndex, 1);
    expect(a.stops, greaterThan(0));
    expect(b.volumes.last, closeTo(0.5, 0.001));
    await loop.dispose();
  });

  test('RecitationCache names one file per url and keeps no half file', () async {
    final dir = await Directory.systemTemp.createTemp('rc');
    final c = RecitationCache(root: () async => dir, fetch: (u, f) async => f.writeAsString('x'));
    expect(RecitationCache.fileName('https://e/data/Alafasy_64kbps/001002.mp3'), '001002.mp3');
    expect(await c.cached('alafasy', 'https://e/001002.mp3'), isNull);
    final f = await c.ensure('alafasy', 'https://e/001002.mp3');
    expect(f!.path.replaceAll('\\', '/').endsWith('alafasy/001002.mp3'), isTrue);
    expect(await File('${f.path}.part').exists(), isFalse);
    expect(await c.cached('alafasy', 'https://e/001002.mp3'), isNotNull);
    await dir.delete(recursive: true);
  });
}
