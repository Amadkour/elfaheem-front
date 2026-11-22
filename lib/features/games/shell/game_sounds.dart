// lib/features/games/shell/game_sounds.dart — the games' sound and vibration (Games v3 §11, D-1741): ONE seam,
// `GameFeedback.instance.play(GameSound.x)`, so the engines never import the audio package. The sounds are our own,
// synthesized by tool/gen_game_sounds.py into assets/sounds/games/<name>.mp3 (MP3 plays on Android, iOS and the web).
//
// Rules:
//   - nothing loads at app start: the first shell that opens with sound on creates the players and preloads the 7
//     short sounds (on the web it waits for the first touch, the browser's autoplay rule); `champion` loads when it
//     is first played (the winner sheet). The players are released when the last shell closes;
//   - the mute toggle (`games.muted`, on the device) mutes sound AND vibration; muted = no player is ever created;
//   - the kill switch `games.sounds` off = vibration only;
//   - iOS: the `ambient` session (follows the silent switch, mixes with other audio); Android: usage `game` with no
//     audio-focus request (music keeps playing). Reduce motion does not mute;
//   - never: `wrong` in a quran / tajweed game (vibration + colour only), any sound in the editor's preview, any sound
//     while a live room is open (a video is a full page over the game, so no tap reaches a game under it);
//   - `tap` is dropped when the last one played under 60 ms ago; `combo` REPLACES `correct` on every third right
//     answer in a row, they never play together;
//   - every failure (no codec, no plugin, a lost file) is swallowed: a sound never fails a round.
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/live/live_room_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The set (PLAN §11).
enum GameSound { tap, correct, wrong, combo, snap, flip, finish, champion }

/// The sounds' kill switch (front only: off = vibration only).
const String kGamesSoundsFeatureKey = 'games.sounds';

bool gameSoundsOff() => AppConfig.disableList.contains(kGamesSoundsFeatureKey);

/// The asset of [s] (under the `assets/` prefix the audio package adds).
String gameSoundAsset(GameSound s) => 'sounds/games/${s.name}.mp3';

/// What plays the sounds (the real one is [AudioGameSoundPlayer]; tests pass a fake).
abstract class GameSoundPlayer {
  Future<void> preload(Iterable<GameSound> sounds);
  Future<void> play(GameSound sound);
  Future<void> dispose();
}

/// The low-latency players of the audio package: one per sound, its source set once, restarted on each play.
class AudioGameSoundPlayer implements GameSoundPlayer {
  final Map<GameSound, Future<AudioPlayer>> _players = {};
  bool _disposed = false;

  static AudioContext get _context => AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.game,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      );

  Future<AudioPlayer> _player(GameSound s) => _players[s] ??= () async {
        final p = AudioPlayer();
        if (!kIsWeb) {
          await p.setAudioContext(_context);
          await p.setPlayerMode(PlayerMode.lowLatency);
        }
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setSource(AssetSource(gameSoundAsset(s)));
        return p;
      }();

  @override
  Future<void> preload(Iterable<GameSound> sounds) async {
    for (final s in sounds) {
      if (_disposed) return;
      try {
        await _player(s);
      } catch (_) {
        _players.remove(s); // tried again on its first play
      }
    }
  }

  @override
  Future<void> play(GameSound sound) async {
    if (_disposed) return;
    final p = await _player(sound);
    if (_disposed) return;
    await p.stop();
    await p.resume();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final all = [..._players.values];
    _players.clear();
    for (final f in all) {
      try {
        await (await f).dispose();
      } catch (_) {}
    }
  }
}

/// The games' sound and vibration, and the per-device mute (SharedPreferences `games.muted`).
class GameFeedback {
  GameFeedback._();

  static final GameFeedback instance = GameFeedback._();

  static const String _key = 'games.muted';

  /// The short sounds preloaded when a shell opens (`champion` loads when first played).
  static const List<GameSound> preloaded = [
    GameSound.tap,
    GameSound.correct,
    GameSound.wrong,
    GameSound.combo,
    GameSound.snap,
    GameSound.flip,
    GameSound.finish,
  ];

  /// How close two `tap` sounds may be.
  static const Duration tapGap = Duration(milliseconds: 60);

  /// True = no sound and no vibration. Read from the device once, the first time a shell opens.
  final ValueNotifier<bool> muted = ValueNotifier<bool>(false);
  bool _loaded = false;

  /// Makes the player (null = no sound here). The default makes the real one in the app and none under a test
  /// binding (no audio plugin there).
  GameSoundPlayer? Function() playerFactory = _defaultPlayer;

  static GameSoundPlayer? _defaultPlayer() => WidgetsBinding.instance is WidgetsFlutterBinding ? AudioGameSoundPlayer() : null;

  /// True while something else owns the sound (a live room).
  bool Function() mediaBusy = () => LiveRoomHost.isOpen;

  /// The vibration (tests replace it).
  void Function(GameSound sound) haptic = _haptic;

  /// The clock of the tap rate limit (tests replace it).
  DateTime Function() now = DateTime.now;

  GameSoundPlayer? _player;
  bool _preloaded = false;
  int _shells = 0;
  DateTime? _lastTap;

  /// Tests: back to a fresh state.
  @visibleForTesting
  void reset() {
    unawaited(_release());
    _shells = 0;
    _lastTap = null;
    _loaded = false;
    muted.value = false;
    playerFactory = _defaultPlayer;
    mediaBusy = () => LiveRoomHost.isOpen;
    haptic = _haptic;
    now = DateTime.now;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      muted.value = p.getBool(_key) ?? false;
    } catch (_) {}
  }

  Future<void> setMuted(bool v) async {
    muted.value = v;
    if (v) unawaited(_release());
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, v);
    } catch (_) {}
  }

  bool get _soundAllowed => !muted.value && !gameSoundsOff();

  /// A shell opened: on a phone the players are made and the short sounds preloaded now (after the mute is read).
  void attach() {
    _shells++;
    if (!kIsWeb) unawaited(load().then((_) => _warm()));
  }

  /// A shell closed: the last one releases the players.
  void detach() {
    _shells = _shells > 0 ? _shells - 1 : 0;
    if (_shells == 0) unawaited(_release());
  }

  /// A touch inside a shell: on the web the preload waits for this (the browser's autoplay rule).
  void userGesture() {
    if (kIsWeb) _warm();
  }

  void _warm() {
    if (_preloaded || _shells == 0 || !_soundAllowed) return;
    final p = _ensurePlayer();
    if (p == null) return;
    _preloaded = true;
    _swallow(() => p.preload(preloaded));
  }

  GameSoundPlayer? _ensurePlayer() {
    if (_player != null) return _player;
    try {
      return _player = playerFactory();
    } catch (_) {
      return null;
    }
  }

  Future<void> _release() async {
    final p = _player;
    _player = null;
    _preloaded = false;
    if (p != null) await _swallowAsync(p.dispose);
  }

  /// Plays [sound] with its vibration. [sacred] (a quran / tajweed game): never the `wrong` sound. [silent] (the
  /// editor's preview): vibration only.
  void play(GameSound sound, {bool sacred = false, bool silent = false}) {
    if (muted.value) return;
    try {
      haptic(sound);
    } catch (_) {}
    if (silent || gameSoundsOff() || (sacred && sound == GameSound.wrong)) return;
    try {
      if (mediaBusy()) return;
    } catch (_) {}
    if (sound == GameSound.tap) {
      final at = now();
      final last = _lastTap;
      if (last != null && at.difference(last) < tapGap) return;
      _lastTap = at;
    }
    final p = _ensurePlayer();
    if (p == null) return;
    _swallow(() => p.play(sound));
  }

  /// The super admin's Sound check: [sound] alone, whatever the mute or a live room (the kill switch still wins).
  void audition(GameSound sound) {
    if (gameSoundsOff()) return;
    final p = _ensurePlayer();
    if (p == null) return;
    _swallow(() => p.play(sound));
  }

  /// One answer: `correct`, `wrong`, or `combo` instead of `correct` on every [kComboEvery]-th right answer in a row
  /// ([streak] counts this one).
  void answer(bool correct, {int streak = 0, bool sacred = false, bool silent = false}) =>
      play(answerSound(correct, streak), sacred: sacred, silent: silent);

  static const int kComboEvery = 3;

  /// The sound of one answer (pure).
  static GameSound answerSound(bool correct, int streak) {
    if (!correct) return GameSound.wrong;
    return streak >= kComboEvery && streak % kComboEvery == 0 ? GameSound.combo : GameSound.correct;
  }

  /// The old cue (one answer, no streak).
  void cue(bool correct) => answer(correct);

  static void _haptic(GameSound s) {
    switch (s) {
      case GameSound.correct:
      case GameSound.combo:
        HapticFeedback.selectionClick();
      case GameSound.wrong:
        HapticFeedback.lightImpact();
      default:
        break;
    }
  }

  static void _swallow(Future<void> Function() f) {
    try {
      f().catchError((Object _) {});
    } catch (_) {}
  }

  static Future<void> _swallowAsync(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }
}
