// lib/features/games/core/game_audio.dart — the games' music and the Quran recitation (Games v4 T24, CONTRACT §8, §9).
//
// The short SFX stay in shell/game_sounds.dart (`GameFeedback`, the one seam); this file wraps it and adds the two
// long sounds on the same `audioplayers` package:
//   - MUSIC: two looping tracks (`music_kids`, `music_calm`). audioplayers' own loop mode is not gapless: an MP3
//     carries encoder padding and every platform re-opens the file at the loop point (a gap of tens of ms on
//     Android's MediaPlayer, more on the web's <audio loop>). So the loop is done by hand with TWO voices: [fade]
//     before the end of the track the other voice starts from 0 and the two cross-fade, then the roles swap. The
//     track's own length comes from the player (`durationMs`); until it is known the track just plays on.
//   - RECITATION: a playlist of `{url, start_ms, end_ms}` (one entry per ayah; a `surah_files` reciter gives
//     one big file and the ayah's window in it). Each entry seeks to `start_ms` and stops at `end_ms` (a one-shot
//     timer fires the last 300 ms so the 200 ms position tick never overshoots into the next ayah).
//
// Rules:
//   - while a recitation plays the music is paused (it comes back when the recitation ends) and EVERY SFX is silent
//     (`GameFeedback.mediaBusy` is wrapped by [GameAudio.attach]); haptics still work;
//   - kill switch `games.sounds` = haptics only: no SFX and no music. The recitation is the lesson itself, so it is
//     not an effect: it plays when the learner asks for it (the device mute toggle does not stop it either);
//   - a recitation file is cached per reciter (`recitation_cache.dart`): an ayah file is fetched in the background
//     while it streams; a 32 MB surah file is never fetched on its own (only [GameAudio.prefetch]) and, on the web or
//     before it is cached, it STREAMS and seeks, which the browser / ExoPlayer do with HTTP range requests, so a
//     segment starts without the whole file;
//   - `switchReciter(key)` re-resolves the playlist through `GET /games/quran/audio`, saves the choice
//     (`PUT /me/games/profile {reciter_key}`) and replays the current ayah. The score and the trace never change;
//   - every failure is swallowed: sound never fails a round.
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/games/core/recitation_cache.dart';
import 'package:flutter_education_app/features/games/shell/game_sounds.dart';

/// The two music tracks.
enum GameMusic { kids, calm }

String gameMusicAsset(GameMusic m) => 'sounds/games/music_${m.name}.mp3';

/// One entry of a recitation playlist (CONTRACT §4 `media.audio`).
class RecitationSegment {
  const RecitationSegment({required this.url, this.startMs = 0, this.endMs, this.reciter, this.ref});

  final String url;
  final int startMs;

  /// Null = to the end of the file.
  final int? endMs;

  /// Who the server used for this entry (differs from the asked one on a fallback).
  final String? reciter;

  /// `"112:1"`: what `switchReciter` re-resolves.
  final String? ref;

  /// A whole small file (an `ayah_files` entry); anything else is a window of a big surah file.
  bool get wholeFile => startMs == 0 && endMs == null;

  factory RecitationSegment.fromJson(Map<String, dynamic> j, {String? ref}) => RecitationSegment(
        url: '${j['url']}',
        startMs: (j['start_ms'] as num?)?.toInt() ?? 0,
        endMs: (j['end_ms'] as num?)?.toInt(),
        reciter: j['reciter'] as String?,
        ref: ref,
      );

  RecitationSegment withRef(String? r) =>
      RecitationSegment(url: url, startMs: startMs, endMs: endMs, reciter: reciter, ref: r);
}

/// A reciter of `GET /games/reciters` (§9).
class GameReciter {
  const GameReciter({required this.key, required this.nameAr, required this.nameEn, this.sample});

  final String key;
  final String nameAr;
  final String nameEn;
  final RecitationSegment? sample;

  factory GameReciter.fromJson(Map<String, dynamic> j) => GameReciter(
        key: '${j['key']}',
        nameAr: '${j['name_ar'] ?? ''}',
        nameEn: '${j['name_en'] ?? ''}',
        sample: j['sample'] is Map ? RecitationSegment.fromJson(Map<String, dynamic>.from(j['sample'] as Map)) : null,
      );
}

class GameReciterList {
  const GameReciterList({required this.items, this.defaultKey, this.kidsKey, this.mine, this.effective});

  final List<GameReciter> items;
  final String? defaultKey;
  final String? kidsKey;
  final String? mine;
  final String? effective;
}

/// What a voice plays: an asset, a URL or a file.
class AudioRef {
  const AudioRef.asset(this.path) : kind = 'asset';
  const AudioRef.url(this.path) : kind = 'url';
  const AudioRef.file(this.path) : kind = 'file';

  final String kind;
  final String path;
}

/// ONE player (the real one is [AudioplayersVoice]; tests pass a fake).
abstract class AudioVoice {
  /// Opens [ref], seeks to [startMs] and plays at [volume].
  Future<void> play(AudioRef ref, {int startMs = 0, double volume = 1});
  Future<void> setVolume(double volume);
  Future<void> stop();
  Stream<int> get positionMs;
  Stream<int> get durationMs;
  Stream<void> get completed;
  Future<void> dispose();
}

class AudioplayersVoice implements AudioVoice {
  AudioplayersVoice() : _p = AudioPlayer() {
    unawaited(_init());
  }

  final AudioPlayer _p;

  Future<void> _init() async {
    try {
      await _p.setReleaseMode(ReleaseMode.stop);
      if (!kIsWeb) {
        await _p.setAudioContext(AudioContext(
          android: const AudioContextAndroid(
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.game,
            audioFocus: AndroidAudioFocus.none,
          ),
          iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
        ));
      }
    } catch (_) {}
  }

  @override
  Future<void> play(AudioRef ref, {int startMs = 0, double volume = 1}) async {
    await _p.setVolume(volume);
    final Source src = switch (ref.kind) {
      'asset' => AssetSource(ref.path),
      'file' => DeviceFileSource(ref.path),
      _ => UrlSource(ref.path),
    };
    await _p.setSource(src);
    if (startMs > 0) await _p.seek(Duration(milliseconds: startMs));
    await _p.resume();
  }

  @override
  Future<void> setVolume(double volume) => _p.setVolume(volume.clamp(0.0, 1.0));
  @override
  Future<void> stop() => _p.stop();
  @override
  Stream<int> get positionMs => _p.onPositionChanged.map((d) => d.inMilliseconds);
  @override
  Stream<int> get durationMs => _p.onDurationChanged.map((d) => d.inMilliseconds);
  @override
  Stream<void> get completed => _p.onPlayerComplete;
  @override
  Future<void> dispose() => _p.dispose();
}

/// A seamless loop of one track on two voices (see the library comment).
class CrossfadeLoop {
  CrossfadeLoop({required this.voices, required this.ref, this.volume = 0.35, this.fade = const Duration(milliseconds: 1500)})
      : assert(voices.length == 2);

  final List<AudioVoice> voices;
  final AudioRef ref;
  final double volume;
  final Duration fade;

  static const Duration _tick = Duration(milliseconds: 50);

  int _active = 0;
  int _durationMs = 0;
  bool _fading = false;
  bool _running = false;
  Timer? _ramp;
  final List<StreamSubscription<dynamic>> _subs = [];

  bool get running => _running;

  /// The voice that carries the track now (tests).
  @visibleForTesting
  int get activeIndex => _active;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _active = 0;
    _fading = false;
    _listen(0);
    await voices[0].play(ref, volume: volume);
  }

  void _listen(int i) {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _subs.add(voices[i].durationMs.listen((d) {
      if (d > 0) _durationMs = d;
    }));
    _subs.add(voices[i].positionMs.listen((p) => _onPosition(i, p)));
    // A track whose length never arrived: the player's own end restarts it (a small gap beats silence).
    _subs.add(voices[i].completed.listen((_) {
      if (_running && !_fading && i == _active) _swap(i, instant: true);
    }));
  }

  void _onPosition(int i, int p) {
    if (!_running || _fading || i != _active || _durationMs <= 0) return;
    if (p >= _durationMs - fade.inMilliseconds) _swap(i);
  }

  void _swap(int from, {bool instant = false}) {
    if (_fading) return;
    _fading = true;
    final to = 1 - from;
    final steps = instant ? 1 : (fade.inMilliseconds / _tick.inMilliseconds).ceil().clamp(1, 1000);
    unawaited(voices[to].play(ref, volume: instant ? volume : 0).catchError((Object _) {}));
    var n = 0;
    _ramp?.cancel();
    _ramp = Timer.periodic(_tick, (t) {
      n++;
      final f = (n / steps).clamp(0.0, 1.0);
      voices[from].setVolume(volume * (1 - f)).catchError((Object _) {});
      voices[to].setVolume(volume * f).catchError((Object _) {});
      if (f >= 1) {
        t.cancel();
        voices[from].stop().catchError((Object _) {});
        _active = to;
        _fading = false;
        _listen(to);
      }
    });
  }

  Future<void> stop() async {
    _running = false;
    _fading = false;
    _ramp?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    for (final v in voices) {
      try {
        await v.stop();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await stop();
    for (final v in voices) {
      try {
        await v.dispose();
      } catch (_) {}
    }
  }
}

/// Resolves refs through `GET /games/quran/audio` (tests replace it).
typedef QuranAudioFetch = Future<Map<String, RecitationSegment>> Function(List<String> refs, String reciter);

/// Saves the learner's reciter (tests replace it).
typedef ReciterSave = Future<void> Function(String key);

class GameAudio {
  GameAudio._();

  static final GameAudio instance = GameAudio._();

  /// The cross-fade length of the music loop.
  static const Duration loopFade = Duration(milliseconds: 1500);

  /// Music volume under the SFX.
  static const double musicVolume = 0.35;

  /// Makes a voice (null = no sound here). The default makes real ones in the app and none under a test binding.
  AudioVoice? Function() voiceFactory = _defaultVoice;

  static AudioVoice? _defaultVoice() => WidgetsBinding.instance is WidgetsFlutterBinding ? AudioplayersVoice() : null;

  RecitationCache cache = RecitationCache.instance;
  QuranAudioFetch fetchAudio = _apiFetch;
  ReciterSave saveReciter = _apiSave;

  /// True while a recitation plays (a screen can dim its controls).
  final ValueNotifier<bool> recitationActive = ValueNotifier<bool>(false);

  /// The reciter of the current playlist (null until a recitation was asked with one).
  String? reciterKey;

  bool _attached = false;
  bool Function()? _outerBusy;
  GameMusic? _wanted;
  CrossfadeLoop? _loop;
  AudioVoice? _voice;
  StreamSubscription<int>? _posSub;
  StreamSubscription<void>? _doneSub;
  Timer? _endTimer;
  Completer<void>? _curDone;
  List<RecitationSegment> _playlist = const [];
  int _index = 0;
  int _gen = 0;
  bool _resumeMusic = false;

  /// Tests: back to a fresh state.
  @visibleForTesting
  Future<void> reset() async {
    await stopRecitation();
    await stopMusic();
    if (_attached) {
      GameFeedback.instance.muted.removeListener(_onMuted);
      GameFeedback.instance.mediaBusy = _outerBusy ?? (() => false);
    }
    _attached = false;
    _outerBusy = null;
    voiceFactory = _defaultVoice;
    cache = RecitationCache.instance;
    fetchAudio = _apiFetch;
    saveReciter = _apiSave;
    reciterKey = null;
    _playlist = const [];
    _index = 0;
  }

  /// Wraps the SFX seam: every SFX is silent while a recitation plays. Safe to call again.
  void attach() {
    if (_attached) return;
    _attached = true;
    final fb = GameFeedback.instance;
    final outer = fb.mediaBusy;
    _outerBusy = outer;
    fb.mediaBusy = () => recitationActive.value || outer();
    fb.muted.addListener(_onMuted);
  }

  void _onMuted() {
    if (GameFeedback.instance.muted.value) {
      unawaited(_stopLoop());
    } else if (_wanted != null) {
      unawaited(playMusic(_wanted!));
    }
  }

  bool get _musicAllowed {
    if (gameSoundsOff() || GameFeedback.instance.muted.value || recitationActive.value) return false;
    try {
      return !(_outerBusy ?? () => false)();
    } catch (_) {
      return true;
    }
  }

  // ---- music ----

  /// Starts [track] (the calm one for a sacred game). Nothing when muted, `games.sounds` is off, a recitation plays
  /// or a live room is open; the choice is remembered and the music comes back when that ends.
  Future<void> playMusic(GameMusic track) async {
    attach();
    _wanted = track;
    if (!_musicAllowed) return;
    try {
      final cur = _loop;
      if (cur != null && cur.running && cur.ref.path == gameMusicAsset(track)) return;
      await _stopLoop();
      final a = voiceFactory();
      final b = a == null ? null : voiceFactory();
      if (a == null || b == null) return;
      final loop = CrossfadeLoop(
          voices: [a, b], ref: AudioRef.asset(gameMusicAsset(track)), volume: musicVolume, fade: loopFade);
      _loop = loop;
      await loop.start();
    } catch (_) {}
  }

  /// Stops the music for good (a game closed).
  Future<void> stopMusic() async {
    _wanted = null;
    await _stopLoop();
  }

  Future<void> _stopLoop() async {
    final l = _loop;
    _loop = null;
    if (l != null) {
      try {
        await l.dispose();
      } catch (_) {}
    }
  }

  // ---- recitation ----

  int get currentIndex => _index;
  List<RecitationSegment> get playlist => List.unmodifiable(_playlist);

  /// Starts [segments] in order from [from] (returns when the first is set up, not when the list ends). [reciter]
  /// names the voice asked (kept for `switchReciter`).
  Future<void> playRecitation(List<RecitationSegment> segments, {int from = 0, String? reciter}) async {
    attach();
    _gen++;
    await _haltVoice();
    if (segments.isEmpty) return;
    _playlist = List.of(segments);
    _index = from.clamp(0, segments.length - 1);
    if (reciter != null) reciterKey = reciter;
    final gen = _gen;
    if (!recitationActive.value) {
      _resumeMusic = _loop?.running ?? false;
      if (_resumeMusic) await _stopLoop();
    }
    recitationActive.value = true;
    unawaited(_playFrom(gen));
  }

  Future<void> _playFrom(int gen) async {
    while (gen == _gen && _index < _playlist.length) {
      final done = Completer<void>();
      _curDone = done;
      try {
        await _playSegment(_playlist[_index], gen, done);
        await done.future;
      } catch (_) {
        // a lost file: the next ayah, never a stuck round
      }
      if (gen != _gen) return;
      _index++;
    }
    if (gen == _gen) {
      _index = _playlist.isEmpty ? 0 : _playlist.length - 1;
      await _finish();
    }
  }

  Future<void> _playSegment(RecitationSegment s, int gen, Completer<void> done) async {
    final voice = _voice ??= voiceFactory();
    if (voice == null) {
      done.complete();
      return;
    }
    final ref = await _refFor(s);
    if (gen != _gen) {
      if (!done.isCompleted) done.complete();
      return;
    }
    void end() {
      _endTimer?.cancel();
      _posSub?.cancel();
      _doneSub?.cancel();
      if (!done.isCompleted) done.complete();
    }

    await _posSub?.cancel();
    await _doneSub?.cancel();
    _endTimer?.cancel();
    final endMs = s.endMs;
    _doneSub = voice.completed.listen((_) => end());
    if (endMs != null) {
      _posSub = voice.positionMs.listen((p) {
        if (gen != _gen) return;
        final left = endMs - p;
        if (left <= 0) {
          voice.stop().catchError((Object _) {});
          end();
        } else if (left < 300) {
          _endTimer?.cancel();
          _endTimer = Timer(Duration(milliseconds: left), () {
            voice.stop().catchError((Object _) {});
            end();
          });
        }
      });
    }
    try {
      await voice.play(ref, startMs: s.startMs);
    } catch (_) {
      end();
    }
  }

  Future<AudioRef> _refFor(RecitationSegment s) async {
    final who = s.reciter ?? reciterKey ?? 'default';
    final f = await cache.cached(who, s.url);
    if (f != null) return AudioRef.file(f.path);
    // A small ayah file is fetched while it streams; a big surah file only through [prefetch].
    if (s.wholeFile) unawaited(cache.ensure(who, s.url));
    return AudioRef.url(s.url);
  }

  /// Downloads the files of [segments] (on Wi-Fi: the offline cache and a "download this surah" button).
  Future<void> prefetch(List<RecitationSegment> segments, {String? reciter}) async {
    final seen = <String>{};
    for (final s in segments) {
      if (!seen.add(s.url)) continue;
      await cache.ensure(s.reciter ?? reciter ?? reciterKey ?? 'default', s.url);
    }
  }

  /// Stops the recitation (the music comes back if it was playing).
  Future<void> stopRecitation() async {
    _gen++;
    await _haltVoice();
    await _finish();
  }

  Future<void> _haltVoice() async {
    _endTimer?.cancel();
    final d = _curDone;
    if (d != null && !d.isCompleted) d.complete();
    await _posSub?.cancel();
    await _doneSub?.cancel();
    _posSub = null;
    _doneSub = null;
    final v = _voice;
    if (v != null) {
      try {
        await v.stop();
      } catch (_) {}
    }
  }

  Future<void> _finish() async {
    final was = recitationActive.value;
    recitationActive.value = false;
    final v = _voice;
    _voice = null;
    if (v != null) {
      try {
        await v.dispose();
      } catch (_) {}
    }
    final resume = _resumeMusic;
    _resumeMusic = false;
    if (was && resume && _wanted != null) await playMusic(_wanted!);
  }

  /// The quick switch: re-resolves the playlist with [key], saves the choice and replays the current ayah.
  /// False when the server could not resolve (the old voice keeps playing).
  Future<bool> switchReciter(String key) async {
    if (_playlist.isEmpty) {
      reciterKey = key;
      unawaited(_save(key));
      return true;
    }
    final refs = <String>{for (final s in _playlist) if (s.ref != null) s.ref!}.take(60).toList();
    if (refs.isEmpty) return false;
    Map<String, RecitationSegment> got;
    try {
      got = await fetchAudio(refs, key);
    } catch (_) {
      return false;
    }
    if (got.isEmpty) return false;
    final list = [
      for (final s in _playlist) (s.ref != null && got[s.ref] != null) ? got[s.ref!]!.withRef(s.ref) : s,
    ];
    unawaited(_save(key));
    final from = _index.clamp(0, list.length - 1);
    await playRecitation(list, from: from, reciter: key);
    return true;
  }

  Future<void> _save(String key) async {
    try {
      await saveReciter(key);
    } catch (_) {}
  }

  // ---- reciters list and the 3-second sample ----

  Future<GameReciterList> loadReciters() async {
    final j = await ApiClient().get('/games/reciters');
    final m = Map<String, dynamic>.from(j as Map);
    return GameReciterList(
      items: [
        for (final r in (m['items'] as List? ?? const [])) GameReciter.fromJson(Map<String, dynamic>.from(r as Map)),
      ],
      defaultKey: m['default_key'] as String?,
      kidsKey: m['kids_key'] as String?,
      mine: m['mine'] as String?,
      effective: m['effective'] as String?,
    );
  }

  /// Plays 3 seconds of a reciter's sample (the picker).
  Future<void> playSample(GameReciter r) async {
    final s = r.sample;
    if (s == null) return;
    await playRecitation([RecitationSegment(url: s.url, startMs: s.startMs, endMs: s.startMs + 3000, reciter: r.key)]);
  }

  static Future<Map<String, RecitationSegment>> _apiFetch(List<String> refs, String reciter) async {
    final j = await ApiClient().get('/games/quran/audio', queryParams: {'refs': refs.join(','), 'reciter': reciter});
    final items = Map<String, dynamic>.from((j as Map)['items'] as Map? ?? const {});
    return {
      for (final e in items.entries)
        if (e.value is Map) e.key: RecitationSegment.fromJson(Map<String, dynamic>.from(e.value as Map), ref: e.key),
    };
  }

  static Future<void> _apiSave(String key) async {
    await ApiClient().put('/me/games/profile', body: {'reciter_key': key});
  }
}
