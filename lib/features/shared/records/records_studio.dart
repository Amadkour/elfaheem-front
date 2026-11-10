// lib/features/shared/records/records_studio.dart — the Studio (D-312, premium D-590 … D-597): the editor of one of my
// records or of a course session's video. Plain-values widgets: records_studio_parts.dart (bay, transport, layout, job
// card), studio_timeline.dart (the timeline), studio_stage.dart (texts and pictures on the picture), studio_panels.dart
// (Edit · Text · Picture · History); the pure edit list and its history: studio_project.dart.
//
//   The source is pluggable (studio_source.dart, D-315): a drive recording of Records (default) or a course session's
//   video material (MaterialStudioSource: no Cover, the job makes a DRAFT, `jobActions` puts Publish on the card).
//
//   One project, many steps (D-590): splits, removes, trims, per-part speed, texts and pictures with animations and the
//   quality are steps of ONE edit list, rendered by ONE job (POST …/render). Every step is in the history with what it
//   did; undo / redo / restore any step (D-593); the project autosaves to the server (GET|PUT …/project) so closing the
//   Studio loses nothing, and every rendered draft keeps its history ("Continue editing").
//   The preview plays THROUGH the edit: removed parts are skipped, each part plays at its speed, and the texts and
//   pictures animate over it as the file will show them (the text is drawn by the app and sent as a PNG, D-591).
//   A saved job is followed inline with EventOrPoll: stages, %, time left, Stop (D-594); a finished one plays, downloads
//   (D-596), publishes (a material) or opens again.
//   Keys (web / desktop, never while typing): Space play / pause · J −5 s · K pause · L +5 s · ← / → a frame (Shift: a
//   second) · I / O mark in / out · S split · Delete remove the marked period / the selection · Ctrl+Z undo ·
//   Ctrl+Shift+Z / Ctrl+Y redo · Home / End · + / − zoom · Esc clear the selection.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../admin/admin_common.dart' show t;
import 'records_api.dart';
import 'records_share_api.dart';
import 'records_studio_parts.dart';
import 'studio_download_io.dart' if (dart.library.js_interop) 'studio_download_web.dart' as saver;
import 'studio_panels.dart';
import 'studio_project.dart';
import 'studio_source.dart';
import 'studio_stage.dart';
import 'studio_timeline.dart';

class RecordStudioPage extends StatefulWidget {
  const RecordStudioPage({
    super.key,
    required this.item,
    this.others = const [],
    this.api,
    this.shareApi,
    this.onPlay,
    this.source,
    this.jobActions,
    this.libraryLabel,
    this.popResult,
  });

  /// What the page pops with (null: every item it made / changed). The material Studio pops with "changed": the
  /// page keeps the ONE PopScope, so a Back never pops twice (and the route underneath with it).
  final Object? Function()? popResult;

  final RecordItem item;

  /// What is edited (null: the Records drive recording through [api] / [shareApi]).
  final StudioSource? source;

  /// A finished job item's own buttons on the inline job card (a material draft: Publish · Discard).
  final Widget? Function(BuildContext context, RecordItem r)? jobActions;

  /// The job card's back-to-the-list words (null: "To Records").
  final String? libraryLabel;

  /// The rest of the library (the Merge tool's candidates).
  final List<RecordItem> others;
  final RecordsApi? api;
  final RecordShareApi? shareApi;

  /// Plays a finished item (the library's player).
  final void Function(BuildContext context, RecordItem r)? onPlay;

  @override
  State<RecordStudioPage> createState() => _RecordStudioPageState();
}

class _RecordStudioPageState extends State<RecordStudioPage> with SingleTickerProviderStateMixin {
  late final StudioSource _src = widget.source ?? RecordStudioSource(api: widget.api, shareApi: widget.shareApi);
  late RecordItem _item = widget.item;
  final _made = <RecordItem>[];

  // ── player ──
  VideoPlayerController? _player;
  String? _playError;
  bool _ready = false;
  late double _srcDur = widget.item.durationSeconds;
  double _aspect = 16 / 9;
  Size _videoSize = const Size(1280, 720);
  double _previewSpeed = 1;

  /// The playhead, OUTPUT seconds.
  double _pos = 0;
  bool _playing = false;

  /// Where the player last said it was (source s) and when: the ticker runs the playhead smoothly in between.
  double _lastSrc = 0;
  Duration _lastAt = Duration.zero;
  int _playClip = 0;
  late final Ticker _ticker = createTicker(_onTick);
  Duration _elapsed = Duration.zero;

  // seeking: one at a time, the newest wins (a scrub sends many)
  bool _seeking = false;
  double? _seekNext;
  bool _scrubbing = false;
  bool _wasPlaying = false;

  // ── the project ──
  late StudioHistory _hist = StudioHistory.start(widget.item.durationSeconds);
  StudioEdit? _live; // a drag / slider in progress (not a step yet)
  double? _markIn, _markOut;
  int? _selClip;
  String? _selOverlay;
  double _zoom = 1;
  String? _stageNote;
  StudioOverlay? _scaleBase;
  bool _projectLoaded = false;

  StudioEdit get _edit => _live ?? _hist.current;

  // ── tools ──
  late StudioTool _tool = _tools.first;
  List<int> _mergeIds = const [];
  bool _replace = false;
  StudioCanvas _canvas = StudioCanvas.dark;

  // ── frames ──
  RecordFrames? _frames;
  ui.Image? _sprite;
  ImageStream? _spriteStream;
  ImageStreamListener? _spriteListener;

  // ── save / job ──
  bool _busy = false;
  List<RecordItem>? _job;
  EventOrPoll? _jobWatch;
  final _samples = <int, List<(DateTime, int)>>{};
  final _downloads = <int, double>{};
  double? _originalDownload;

  // ── autosave ──
  Timer? _saveTimer;
  StudioSaveState _saveState = StudioSaveState.idle;

  // ── overlay pictures ──
  final _images = <String, Uint8List>{};
  final _textAssets = <String, ({String id, double w})>{};

  bool _titleTouched = false;
  late final TextEditingController _title = TextEditingController(text: _defaultTitle());
  final _focus = FocusNode(debugLabel: 'records-studio');

  /// An audio file has no picture to change or put things on.
  List<StudioTool> get _tools => [
        for (final x in _src.tools)
          if (!_item.isAudio || (x != StudioTool.quality && x != StudioTool.text && x != StudioTool.image)) x,
      ];

  Object? _popValue() => widget.popResult != null ? widget.popResult!() : List<RecordItem>.of(_made);

  @override
  void initState() {
    super.initState();
    _open();
    _loadFrames();
  }

  @override
  void dispose() {
    _flushSave();
    _ticker.dispose();
    _jobWatch?.dispose();
    _player?.removeListener(_onPlayer);
    _player?.dispose();
    if (_spriteListener != null) _spriteStream?.removeListener(_spriteListener!);
    _sprite?.dispose();
    _title.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Player: plays THROUGH the edit
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _open() async {
    try {
      final play = await _src.play(_item.id);
      if (!mounted) return;
      final p = VideoPlayerController.networkUrl(Uri.parse(play.url));
      _player = p;
      await p.initialize();
      if (!mounted) return;
      p.addListener(_onPlayer);
      final d = p.value.duration.inMilliseconds / 1000;
      setState(() {
        _ready = true;
        if (p.value.size.width > 0 && p.value.size.height > 0) {
          _videoSize = p.value.size;
          _aspect = (p.value.size.width / p.value.size.height).clamp(0.5, 2.6);
        }
        if (d > 0 && (_srcDur <= 0 || (d - _srcDur).abs() > 1)) {
          _srcDur = d;
          if (_hist.steps.length == 1) _hist = StudioHistory.start(d);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _playError = recordsErrorText(e));
    }
    _loadProject();
  }

  /// The person's saved work on this source (autosave), if it fits the source.
  Future<void> _loadProject() async {
    if (_projectLoaded || _srcDur <= 0) return;
    _projectLoaded = true;
    try {
      final doc = await _src.loadProject(_item.id);
      if (!mounted || doc == null) return;
      final h = StudioHistory.fromJson(doc, duration: _srcDur);
      if (h == null || h.steps.length < 2 || _hist.steps.length > 1) return;
      setState(() {
        _hist = h;
        _saveState = StudioSaveState.saved;
      });
      _fetchImages();
      showAppNotice(t('أكملنا من حيث توقفت — ${h.steps.length - 1} خطوة محفوظة', 'Picked up where you left off — ${h.steps.length - 1} steps kept'));
    } catch (_) {/* an older server, or nothing saved: start fresh */}
  }

  /// The pictures of the project's image overlays (after a load, an undo across a session).
  Future<void> _fetchImages() async {
    final ids = {
      for (final s in _hist.steps)
        for (final o in s.edit.overlays)
          if (!o.isText && o.asset != null && !_images.containsKey(o.asset)) o.asset!,
    }.toList();
    if (ids.isEmpty) return;
    try {
      final links = await _src.assetLinks(ids);
      for (final e in links.entries) {
        final r = await Dio().get<List<int>>(e.value, options: Options(responseType: ResponseType.bytes));
        if (r.data != null) _images[e.key] = Uint8List.fromList(r.data!);
      }
      if (mounted) setState(() {});
    } catch (_) {/* the frame shows an empty box; the render still has the asset */}
  }

  void _onPlayer() {
    final p = _player;
    if (p == null || !mounted) return;
    final v = p.value;
    if (_seeking || _scrubbing) return;
    _lastSrc = v.position.inMilliseconds / 1000;
    _lastAt = _elapsed;
    if (v.isPlaying != _playing) {
      setState(() => _playing = v.isPlaying);
      if (v.isPlaying) {
        if (!_ticker.isActive) _ticker.start();
      } else {
        _ticker.stop();
        _syncPos(_lastSrc);
      }
    }
    if (!v.isPlaying && !_ticker.isActive) _syncPos(_lastSrc);
  }

  /// The source second [src] as the playhead (in the clip we play, or wherever it lands).
  void _syncPos(double src) {
    final e = _edit;
    final c = _playClip < e.clips.length ? e.clips[_playClip] : null;
    double? out;
    if (c != null && src >= c.start - 0.05 && src <= c.end + 0.05) {
      out = e.clipStart(_playClip) + (src.clamp(c.start, c.end) - c.start) / c.speed;
    } else {
      out = e.outputOf(src);
    }
    if (out != null && (out - _pos).abs() > 0.01) setState(() => _pos = out!.clamp(0.0, e.duration));
  }

  void _onTick(Duration elapsed) {
    _elapsed = elapsed;
    final p = _player;
    if (p == null || !_playing || _seeking || _scrubbing) return;
    final e = _edit;
    if (e.clips.isEmpty) return;
    if (_playClip >= e.clips.length) _playClip = e.clips.length - 1;
    final c = e.clips[_playClip];
    final est = _lastSrc + (elapsed - _lastAt).inMicroseconds / 1e6 * c.speed * _previewSpeed;
    if (est >= c.end - 0.02) {
      // the end of this part: on to the next one (a removed part is never shown)
      if (_playClip + 1 < e.clips.length) {
        _playClip++;
        final n = e.clips[_playClip];
        _seekSource(n.start, then: () => _applySpeed());
      } else {
        p.pause();
        setState(() => _pos = e.duration);
      }
      return;
    }
    if (est < c.start - 0.25) {
      // the player is somewhere this part does not cover (a fresh seek): find where it is
      final o = e.outputOf(est);
      if (o != null) _playClip = e.hit(o)?.clip ?? _playClip;
    }
    final out = e.clipStart(_playClip) + (est.clamp(c.start, c.end) - c.start) / c.speed;
    if ((out - _pos).abs() > 1 / 120) setState(() => _pos = out.clamp(0.0, e.duration));
  }

  void _applySpeed() {
    final e = _edit;
    final c = _playClip < e.clips.length ? e.clips[_playClip] : null;
    _player?.setPlaybackSpeed((c?.speed ?? 1) * _previewSpeed);
  }

  /// Seeks the player to the source second [src]; a seek already running takes the newest target when it lands.
  void _seekSource(double src, {VoidCallback? then}) {
    final p = _player;
    if (p == null || !_ready) return;
    if (_seeking) {
      _seekNext = src;
      return;
    }
    _seeking = true;
    p.seekTo(Duration(milliseconds: (src * 1000).round())).whenComplete(() {
      _lastSrc = src;
      _lastAt = _elapsed;
      _seeking = false;
      final next = _seekNext;
      _seekNext = null;
      if (next != null && mounted) {
        _seekSource(next, then: then);
      } else {
        then?.call();
      }
    });
  }

  /// The playhead to OUTPUT second [out] (and the player to that frame).
  void _seek(double out) {
    final e = _edit;
    final to = out.clamp(0.0, math.max(0.0, e.duration)).toDouble();
    final h = e.hit(to);
    setState(() {
      _pos = to;
      _stageNote = null;
    });
    if (h == null) return;
    _playClip = h.clip;
    _seekSource(h.source, then: _applySpeed);
  }

  void _playPause() {
    final p = _player;
    if (p == null || !_ready) return;
    if (p.value.isPlaying) {
      p.pause();
      return;
    }
    final e = _edit;
    if (_pos >= e.duration - 0.05) _seek(0); // at the end: from the start
    final h = e.hit(_pos);
    if (h != null) _playClip = h.clip;
    _applySpeed();
    p.play();
  }

  void _nextPreviewSpeed() {
    final i = studioPreviewSpeeds.indexOf(_previewSpeed);
    setState(() => _previewSpeed = studioPreviewSpeeds[(i + 1) % studioPreviewSpeeds.length]);
    _applySpeed();
  }

  // scrubbing: pause, show every frame the finger passes, stay paused
  void _scrubStart() {
    _wasPlaying = _player?.value.isPlaying ?? false;
    _player?.pause();
    _scrubbing = true;
  }

  void _scrub(double out) {
    final e = _edit;
    final to = out.clamp(0.0, e.duration);
    setState(() => _pos = to);
    final h = e.hit(to);
    if (h == null) return;
    _playClip = h.clip;
    _seekSource(h.source); // the player's own updates are ignored while scrubbing: the playhead never jumps back
  }

  void _scrubEnd() {
    _scrubbing = false;
    if (_wasPlaying) _playPause();
    _wasPlaying = false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Filmstrip
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadFrames() async {
    if (_item.isAudio) return;
    JobWatch? watch;
    try {
      for (var i = 0; i < 10 && mounted; i++) {
        final f = await _src.frames(_item.id);
        if (!mounted) return;
        setState(() => _frames = f);
        if (f.ready) {
          _resolveSprite(f.url!);
          return;
        }
        if (!f.pending) return;
        watch ??= JobWatch(kind: _src.framesEventKind, id: '${_item.id}');
        await watch.next(const Duration(seconds: 5), fallbackEvery: const Duration(seconds: 20));
      }
    } catch (_) {
      if (mounted) setState(() => _frames = const RecordFrames(status: 'unavailable')); // the plain track
    } finally {
      watch?.dispose();
    }
  }

  void _resolveSprite(String url) {
    final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
    _spriteStream = stream;
    _spriteListener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() {
        _sprite?.dispose();
        _sprite = info.image.clone();
      });
    }, onError: (_, _) {});
    stream.addListener(_spriteListener!);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Steps, undo, autosave
  // ─────────────────────────────────────────────────────────────────────────

  /// [next] as a new step. Two or more undone steps are dropped only after a yes.
  Future<void> _commit(StudioStepKind kind, StudioEdit next, {Map<String, dynamic> info = const {}}) async {
    if (identical(next, _hist.current)) {
      if (_live != null) setState(() => _live = null);
      return;
    }
    if (_hist.undone >= 2) {
      final ok = await appConfirm(context,
          message: t('تراجعت عن ${_hist.undone} خطوات. تعديل جديد يحذفها من السجل. متابعة؟',
              'You undid ${_hist.undone} steps. A new change drops them from the history. Continue?'),
          confirmLabel: t('متابعة', 'Continue'));
      if (!ok || !mounted) {
        setState(() => _live = null);
        return;
      }
    }
    setState(() {
      _hist = _hist.commit(kind, next, info: info);
      _live = null;
      _fixSelection();
    });
    _scheduleSave();
  }

  void _fixSelection() {
    final e = _edit;
    if (_selClip != null && _selClip! >= e.clips.length) _selClip = null;
    if (_selOverlay != null && !e.overlays.any((o) => o.id == _selOverlay)) _selOverlay = null;
    if (_pos > e.duration) _pos = e.duration;
    if (_markIn != null && _markIn! > e.duration) _markIn = null;
    if (_markOut != null && _markOut! > e.duration) _markOut = e.duration;
  }

  void _moveHead(StudioHistory h) {
    setState(() {
      _hist = h;
      _live = null;
      _fixSelection();
    });
    _seek(_pos);
    _scheduleSave();
  }

  void _undo() {
    if (_hist.canUndo) _moveHead(_hist.undo());
  }

  void _redo() {
    if (_hist.canRedo) _moveHead(_hist.redo());
  }

  void _reset() => _commit(StudioStepKind.reset, StudioEdit.original(_srcDur));

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1500), _saveNow);
  }

  void _flushSave() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _saveNow();
    }
  }

  Future<void> _saveNow() async {
    final doc = _hist.steps.length <= 1 ? null : _hist.toJson(_srcDur);
    if (mounted) setState(() => _saveState = StudioSaveState.saving);
    try {
      await _src.saveProject(_item.id, doc);
      if (mounted) setState(() => _saveState = doc == null ? StudioSaveState.idle : StudioSaveState.saved);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saveState = StudioSaveState.failed);
      _saveTimer = Timer(const Duration(seconds: 12), _saveNow);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Edit operations
  // ─────────────────────────────────────────────────────────────────────────

  void _split() {
    final e = _edit;
    final n = e.split(_pos);
    if (identical(n, e)) {
      showAppNotice(t('المؤشر على حافة جزء — حرّكه قليلاً', 'The playhead is on a part’s edge — move it a little'));
      return;
    }
    _commit(StudioStepKind.split, n, info: {'at': _pos});
    setState(() => _selClip = n.hit(_pos)?.clip);
  }

  void _setMark(bool isIn) {
    setState(() {
      if (isIn) {
        _markIn = _pos;
        if (_markOut != null && _markOut! <= _pos) _markOut = null;
      } else {
        _markOut = _pos;
        if (_markIn != null && _markIn! >= _pos) _markIn = null;
        _markIn ??= 0;
      }
    });
  }

  void _removeMarked() {
    final a = _markIn, b = _markOut;
    if (a == null || b == null) return;
    final n = _edit.remove(a, b);
    if (identical(n, _edit)) {
      showAppNotice(t('لا يمكن حذف الفيديو كله', 'You can’t remove the whole video'), error: true);
      return;
    }
    _commit(StudioStepKind.remove, n, info: {'a': a, 'b': b});
    setState(() {
      _markIn = _markOut = null;
      _selClip = null;
    });
    _seek(a);
  }

  void _keepMarked() {
    final a = _markIn, b = _markOut;
    if (a == null || b == null) return;
    final n = _edit.keepOnly(a, b);
    if (identical(n, _edit)) return;
    _commit(StudioStepKind.keep, n, info: {'a': a, 'b': b});
    setState(() {
      _markIn = _markOut = null;
      _selClip = null;
    });
    _seek(0);
  }

  void _deleteClip() {
    final i = _selClip;
    if (i == null) return;
    final len = _edit.clips[i].length;
    final at = _edit.clipStart(i);
    final n = _edit.deleteClip(i);
    if (identical(n, _edit)) return;
    _commit(StudioStepKind.deleteClip, n, info: {'len': len});
    setState(() => _selClip = null);
    _seek(at);
  }

  void _speed(double s) {
    final e = _edit;
    final StudioEdit n;
    final Map<String, dynamic> info;
    if (_markIn != null && _markOut != null && _markOut! > _markIn!) {
      n = e.speedOn(s, a: _markIn, b: _markOut);
      info = {'speed': s, 'a': _markIn, 'b': _markOut};
    } else if (_selClip != null) {
      n = e.speedOn(s, clip: _selClip);
      info = {'speed': s, 'a': e.clipStart(_selClip!), 'b': e.clipStart(_selClip!) + e.clips[_selClip!].length};
    } else {
      n = e.speedOn(s, a: 0, b: e.duration);
      info = {'speed': s, 'a': 0.0, 'b': e.duration};
    }
    _commit(StudioStepKind.speed, n, info: info);
    _applySpeed();
  }

  void _nudgeClip(bool start, double by) {
    final i = _selClip;
    if (i == null) return;
    final c = _edit.clips[i];
    final n = start ? _edit.trimStart(i, c.start + by) : _edit.trimEnd(i, c.end + by, _srcDur);
    _commit(start ? StudioStepKind.trimStart : StudioStepKind.trimEnd, n, info: {'to': start ? c.start + by : c.end + by});
    _seekSource(start ? n.clips[i].start : n.clips[i].end);
  }

  void _onTrim(int i, bool start, double source) {
    final e = _hist.current;
    setState(() {
      _live = start ? e.trimStart(i, source) : e.trimEnd(i, source, _srcDur);
      _selClip = i;
      _stageNote = '${start ? t('البداية', 'Start') : t('النهاية', 'End')} · ${studioTimecode(source)}';
    });
    _player?.pause();
    _seekSource(source);
  }

  void _onTrimEnd(int i, bool start, double? source) {
    final e = _hist.current;
    setState(() => _stageNote = null);
    if (source == null) {
      setState(() => _live = null);
      return;
    }
    final n = start ? e.trimStart(i, source) : e.trimEnd(i, source, _srcDur);
    _commit(start ? StudioStepKind.trimStart : StudioStepKind.trimEnd, n, info: {'to': source});
    final edge = start ? n.clipStart(i) : n.clipStart(i) + n.clips[i].length;
    _seek(start ? edge : math.max(0, edge - 0.04));
  }

  // ── overlays ──

  StudioOverlay? _overlay(String? id) => id == null ? null : _edit.overlays.where((o) => o.id == id).firstOrNull;

  Future<void> _addOverlay(StudioOverlayKind kind, StudioPlace place, {String? text, int? background, double? size}) async {
    final e = _edit;
    if (e.overlays.length >= studioMaxOverlays) {
      showAppNotice(t('حتى $studioMaxOverlays نصاً وصورة', 'Up to $studioMaxOverlays texts and pictures'), error: true);
      return;
    }
    final a = _pos.clamp(0.0, math.max(0.0, e.duration - 0.5)).toDouble();
    final b = math.min(e.duration, a + 5);
    StudioOverlay o;
    if (kind == StudioOverlayKind.text) {
      final arabic = AppConfigLang.isArabic;
      o = StudioOverlay(
        id: studioId('o'),
        kind: kind,
        start: e.anchor(a),
        end: e.anchor(b, end: true),
        x: place.x,
        y: place.y,
        text: text ?? t('اكتب هنا', 'Type here'),
        fontId: arabic ? AppFonts.arabicChoice.id : AppFonts.latinChoice.id,
        size: size ?? 0.065,
        background: background,
        inAnim: StudioAnim.fade,
        outAnim: StudioAnim.fade,
      );
      await AppFonts.ensureLoaded(AppFonts.byIdOrDefault(o.fontId));
    } else {
      final picked = await _pickPicture();
      if (picked == null || !mounted) return;
      o = StudioOverlay(
        id: studioId('o'),
        kind: kind,
        start: e.anchor(a),
        end: e.anchor(b, end: true),
        x: place.x,
        y: place.y,
        w: 0.22,
        asset: picked.id,
        aspect: picked.height > 0 && picked.width > 0 ? picked.height / picked.width : 1,
        inAnim: StudioAnim.pop,
        outAnim: StudioAnim.fade,
      );
    }
    await _commit(kind == StudioOverlayKind.text ? StudioStepKind.textAdd : StudioStepKind.imageAdd, e.putOverlay(o), info: {'name': o.name});
    if (mounted) setState(() => _selOverlay = o.id);
  }

  /// A picture from the device → uploaded as an overlay asset.
  Future<StudioAsset?> _pickPicture() async {
    final XFile? f;
    try {
      f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400);
    } catch (_) {
      if (mounted) showAppNotice(t('تعذّر فتح الصور', "Couldn't open your pictures"), error: true);
      return null;
    }
    if (f == null) return null;
    final raw = await f.readAsBytes();
    if (!mounted) return null;
    setState(() => _busy = true);
    try {
      final a = await _src.uploadAsset(raw, fileName: f.name.isEmpty ? 'picture.png' : f.name);
      _images[a.id] = raw;
      return a;
    } catch (e) {
      showAppNotice(recordsErrorText(e), error: true);
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _overlayChange(StudioOverlay o, {required bool commit, required StudioStepKind kind}) {
    final before = _overlay(o.id);
    if (o.fontId != before?.fontId) {
      AppFonts.ensureLoaded(AppFonts.byIdOrDefault(o.fontId)).then((_) {
        if (mounted) setState(() {});
      });
    }
    final n = _hist.current.putOverlay(o);
    if (commit) {
      _commit(kind, n, info: {'name': o.name});
    } else {
      setState(() => _live = n);
    }
  }

  void _overlaySpan(String id, double a, double b) {
    final o = _hist.current.overlays.where((x) => x.id == id).firstOrNull;
    if (o == null) return;
    final e = _hist.current;
    setState(() => _live = e.putOverlay(o.copyWith(start: e.anchor(a), end: e.anchor(b, end: true))));
  }

  void _overlaySpanEnd(String id, double? a, double? b) {
    final o = _hist.current.overlays.where((x) => x.id == id).firstOrNull;
    if (o == null || a == null || b == null) {
      setState(() => _live = null);
      return;
    }
    final e = _hist.current;
    _commit(StudioStepKind.overlayTime, e.putOverlay(o.copyWith(start: e.anchor(a), end: e.anchor(b, end: true))),
        info: {'name': o.name, 'a': a, 'b': b});
  }

  void _overlayMove(String id, double x, double y) {
    final o = _hist.current.overlays.where((v) => v.id == id).firstOrNull;
    if (o == null) return;
    setState(() => _live = _hist.current.putOverlay(o.copyWith(x: x, y: y)));
  }

  void _overlayMoveEnd(String id) {
    final o = _overlay(id);
    if (o == null || _live == null) return;
    _commit(StudioStepKind.overlayMove, _live!, info: {'name': o.name});
  }

  void _overlayScale(String id, double f) {
    final base = _scaleBase?.id == id ? _scaleBase! : (_scaleBase = _hist.current.overlays.where((v) => v.id == id).firstOrNull);
    if (base == null) return;
    final n = base.isText ? base.copyWith(size: (base.size * f).clamp(0.02, 0.25)) : base.copyWith(w: (base.w * f).clamp(0.04, 1.2));
    setState(() => _live = _hist.current.putOverlay(n));
  }

  void _overlayScaleEnd(String id) {
    final o = _overlay(id);
    _scaleBase = null;
    if (o == null || _live == null) return;
    _commit(StudioStepKind.overlayStyle, _live!, info: {'name': o.name});
  }

  void _deleteOverlay(String id) {
    final o = _overlay(id);
    if (o == null) return;
    _commit(StudioStepKind.overlayRemove, _hist.current.removeOverlay(id), info: {'name': o.name});
    setState(() => _selOverlay = null);
  }

  void _duplicateOverlay(String id) {
    final o = _overlay(id);
    if (o == null) return;
    final copy = StudioOverlay.fromJson({...o.toJson(), 'id': studioId('o'), 'y': (o.y + 0.08).clamp(0.05, 0.95)});
    if (copy == null) return;
    _commit(o.isText ? StudioStepKind.textAdd : StudioStepKind.imageAdd, _hist.current.putOverlay(copy), info: {'name': copy.name});
    setState(() => _selOverlay = copy.id);
  }

  void _setQuality(int? height, StudioQualityLevel level) {
    final n = _hist.current.copyWith(height: () => height, level: () => height == null && level == StudioQualityLevel.balanced ? null : level);
    _commit(StudioStepKind.quality, n, info: {'label': [if (height != null) '${height}p' else t('الدقة الأصلية', 'original size'), level.label].join(' · ')});
  }

  void _toggleMerge(RecordItem r) => setState(() {
        _mergeIds = _mergeIds.contains(r.id) ? [for (final i in _mergeIds) if (i != r.id) i] : [..._mergeIds, r.id];
      });

  void _setTool(StudioTool x) {
    setState(() {
      _tool = x;
      if (x != StudioTool.text && x != StudioTool.image) _selOverlay = null;
      if (x == StudioTool.text || x == StudioTool.image) {
        final o = _overlay(_selOverlay);
        if (o != null && o.kind != (x == StudioTool.text ? StudioOverlayKind.text : StudioOverlayKind.image)) _selOverlay = null;
      }
      _syncTitle();
    });
  }

  void _selectOverlay(String? id) {
    final o = _overlay(id);
    setState(() {
      _selOverlay = id;
      if (o != null) {
        _tool = o.isText ? StudioTool.text : StudioTool.image;
        _selClip = null;
      }
    });
  }

  String _defaultTitle() => _tool == StudioTool.merge ? defaultEditTitle(_item.title, RecordOp.merge) : '${_item.title} · ${RecordOp.project.madeBy}';

  void _syncTitle() {
    if (!_titleTouched) _title.text = _defaultTitle();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // What comes out
  // ─────────────────────────────────────────────────────────────────────────

  List<RecordItem> get _mergeParts => [
        _item,
        for (final id in _mergeIds) ?widget.others.where((r) => r.id == id).firstOrNull,
      ];

  String? get _problem {
    if (_tool == StudioTool.merge) {
      return _mergeIds.isEmpty ? t('اختر تسجيلاً واحداً على الأقل لإضافته', 'Pick at least one recording to add') : null;
    }
    final e = _edit;
    if (_tool == StudioTool.split) {
      return studioHalves(e, _pos) == null ? t('ضع المؤشر داخل الفيديو ليُقسم عنده', 'Put the playhead inside the video to split there') : null;
    }
    if (e.duration < 1) return t('الفيديو الناتج قصير جداً', 'The result is too short');
    if (e.isOriginal(_srcDur)) return t('لم تغيّر شيئاً بعد', 'Nothing has changed yet');
    return null;
  }

  List<double> get _result {
    if (_tool == StudioTool.cover) return const [];
    if (_tool == StudioTool.merge) return _mergeIds.isEmpty ? const [] : [mergedDuration(_mergeParts)];
    if (_tool == StudioTool.split) {
      final h = studioHalves(_edit, _pos);
      return h == null ? const [] : [h.$1.duration, h.$2.duration];
    }
    return [_edit.duration];
  }

  /// The texts drawn as PNGs at the video's size and uploaded once each; the pictures are uploaded already.
  Future<(Map<String, String>, Map<String, double>)> _prepareAssets(StudioEdit e) async {
    final assets = <String, String>{}, widths = <String, double>{};
    final fw = _videoSize.width > 0 ? _videoSize.width : 1280.0, fh = _videoSize.height > 0 ? _videoSize.height : 720.0;
    for (final o in e.overlays) {
      if (e.overlayOut(o) == null) continue;
      if (!o.isText) {
        if (o.asset != null) assets[o.id] = o.asset!;
        continue;
      }
      final key = '${o.text}|${o.fontId}|${o.size}|${o.color}|${o.background}|${o.bold}|$fw|$fh';
      var a = _textAssets[key];
      if (a == null) {
        await AppFonts.ensureLoaded(AppFonts.byIdOrDefault(o.fontId));
        final r = await studioRasterText(o, frameW: fw, frameH: fh);
        final up = await _src.uploadAsset(r.png, fileName: 'text.png');
        a = (id: up.id, w: r.w);
        _textAssets[key] = a;
      }
      assets[o.id] = a.id;
      widths[o.id] = a.w;
    }
    return (assets, widths);
  }

  Future<void> _save() async {
    if (_problem != null || _busy) return;
    if (_replace &&
        !_src.drafts &&
        !await appConfirm(context,
            message: _tool == StudioTool.merge
                ? t('ستُحذف الأصول من القائمة ومن السحابة بعد نجاح الدمج. متابعة؟',
                    'The originals will be deleted from the list and the drive once merged. Continue?')
                : t('سيُحذف الأصل من القائمة ومن السحابة بعد نجاح التعديل. متابعة؟',
                    'The original will be deleted from the list and the drive once the edit is done. Continue?'),
            danger: true,
            confirmLabel: t('متابعة', 'Continue'))) {
      return;
    }
    if (!mounted) return;
    _flushSave();
    setState(() => _busy = true);
    _player?.pause();
    try {
      final List<RecordItem> made;
      if (_tool == StudioTool.merge) {
        made = await _src.merge([_item.id, ..._mergeIds], title: _title.text, deleteSources: _replace && !_src.drafts);
      } else if (_tool == StudioTool.split) {
        final halves = studioHalves(_edit, _pos)!;
        final (assets, widths) = await _prepareAssets(_edit);
        final base = _title.text.trim();
        made = [];
        for (final (i, h) in [halves.$1, halves.$2].indexed) {
          final p = studioRenderParams(h, assets: assets, textWidths: widths, title: base.isEmpty ? null : '$base · ${i + 1}');
          made.addAll(await _src.render(_item.id, p));
        }
      } else {
        final e = _edit;
        final (assets, widths) = await _prepareAssets(e);
        final doc = _hist.toJson(_srcDur);
        final p = studioRenderParams(e, assets: assets, textWidths: widths, history: doc, title: _title.text);
        if (_replace && !_src.drafts) p['delete_source'] = true;
        made = await _src.render(_item.id, p);
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _job = made;
      });
      _keep(made);
      _watchJob();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppNotice(recordsErrorText(e), error: true);
    }
  }

  void _keep(List<RecordItem> fresh) {
    final ids = {for (final f in fresh) f.id};
    _made
      ..removeWhere((r) => ids.contains(r.id))
      ..addAll(fresh);
    final now = DateTime.now();
    for (final r in fresh) {
      if (r.inProgress && r.progress != null) (_samples[r.id] ??= []).add((now, r.progress!));
    }
  }

  /// Time left at the pace of the last minute (null until it is worth saying).
  Duration? _eta(RecordItem r) {
    final s = _samples[r.id];
    if (s == null || s.length < 2 || !r.inProgress) return null;
    final now = s.last;
    final from = s.firstWhere((x) => now.$1.difference(x.$1).inSeconds <= 90, orElse: () => s.first);
    final dp = now.$2 - from.$2;
    final dt = now.$1.difference(from.$1).inMilliseconds / 1000;
    if (dp < 2 || dt < 4) return null;
    return Duration(seconds: ((100 - now.$2) / (dp / dt)).round());
  }

  void _watchJob() {
    final running = (_job ?? const []).any((r) => r.inProgress);
    if (!running) {
      _jobWatch?.stop();
      return;
    }
    _jobWatch ??= EventOrPoll(
      kind: _src.jobEventKind,
      every: const Duration(seconds: 4),
      fallbackEvery: const Duration(seconds: 15),
      poll: _refreshJob,
    );
    if (!_jobWatch!.running) _jobWatch!.start();
  }

  Future<void> _refreshJob() async {
    final job = _job;
    if (job == null) return;
    try {
      final fresh = [for (final r in job) (await _src.get(r.id)) ?? r];
      if (!mounted) return;
      setState(() => _job = fresh);
      _keep(fresh);
    } catch (_) {/* the next event / poll tries again */}
    _watchJob();
  }

  Future<void> _retryJob(RecordItem r) async {
    try {
      final n = await _src.retry(r.id);
      if (n == null || !mounted) return;
      _samples.remove(r.id);
      setState(() => _job = [for (final x in _job ?? const <RecordItem>[]) x.id == n.id ? n : x]);
      _keep([n]);
      _watchJob();
    } catch (e) {
      if (mounted) showAppNotice(recordsErrorText(e), error: true);
    }
  }

  Future<void> _cancelJob(RecordItem r) async {
    if (!await appConfirm(context,
        message: t('إيقاف حفظ «${r.title}»؟ يمكنك تشغيله من جديد لاحقاً.', 'Stop saving “${r.title}”? You can run it again later.'),
        danger: true,
        confirmLabel: t('إيقاف', 'Stop'))) {
      return;
    }
    try {
      final n = await _src.cancel(r.id);
      if (n == null || !mounted) return;
      setState(() => _job = [for (final x in _job ?? const <RecordItem>[]) x.id == n.id ? n : x]);
      _watchJob();
    } catch (e) {
      if (mounted) showAppNotice(recordsErrorText(e), error: true);
    }
  }

  Future<void> _continueJob(RecordItem r) async {
    try {
      final p = await _src.jobProject(r.id);
      final doc = p == null ? null : p['history'];
      final h = doc is Map ? StudioHistory.fromJson(Map<String, dynamic>.from(doc), duration: _srcDur) : null;
      if (h == null) {
        showAppNotice(t('لا يوجد سجل محفوظ لهذا التعديل', 'This edit has no saved history'), error: true);
        return;
      }
      _jobWatch?.stop();
      setState(() {
        _job = null;
        _hist = h;
        _live = null;
        _tool = StudioTool.edit;
        _fixSelection();
      });
      _fetchImages();
      _scheduleSave();
    } catch (e) {
      if (mounted) showAppNotice(recordsErrorText(e), error: true);
    }
  }

  Future<void> _download({RecordItem? job}) async {
    if (job == null ? _originalDownload != null : _downloads.containsKey(job.id)) return;
    void progress(double v) {
      if (!mounted) return;
      setState(() {
        if (job == null) {
          _originalDownload = v;
        } else {
          _downloads[job.id] = v;
        }
      });
    }

    progress(0);
    try {
      final d = job == null ? await _src.download(_item.id) : await _src.downloadJob(job.id);
      final where = await saver.studioSaveUrl(d.url, d.fileName, onProgress: progress);
      if (mounted && where != null) {
        showAppNotice(kIsWeb ? t('بدأ تنزيل «${d.fileName}»', 'Downloading “${d.fileName}”') : t('حُفظ «${d.fileName}»', 'Saved “${d.fileName}”'));
      }
    } catch (e) {
      if (mounted) showAppNotice(recordsErrorText(e), error: true);
    } finally {
      if (mounted) {
        setState(() {
          if (job == null) {
            _originalDownload = null;
          } else {
            _downloads.remove(job.id);
          }
        });
      }
    }
  }

  void _again() {
    _jobWatch?.stop();
    setState(() {
      _job = null;
      _replace = false;
      _titleTouched = false;
      _syncTitle();
    });
  }

  // ── cover (saved at once) ──

  Future<void> _pickCover() async {
    final XFile? f;
    try {
      f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400);
    } catch (_) {
      if (mounted) showAppNotice(t('تعذّر فتح الصور', "Couldn't open your pictures"), error: true);
      return;
    }
    if (f == null || !mounted) return;
    final raw = await f.readAsBytes();
    if (!mounted) return;
    final cropped = await showAppImageCropper(context, raw, shape: CropShape.wide, allowShapeChange: false);
    if (cropped == null || !mounted) return;
    await _coverCall(() => _src.setCover(_item.id, cropped, fileName: 'cover.png'), t('تم حفظ الغلاف', 'Cover saved'));
  }

  Future<void> _coverCall(Future<RecordItem?> Function() call, String done) async {
    setState(() => _busy = true);
    try {
      final n = await call();
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (n != null) _item = n;
      });
      if (n != null) _keep([n]);
      showAppNotice(done);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppNotice(recordsErrorText(e), error: true);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Keyboard
  // ─────────────────────────────────────────────────────────────────────────

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final typing = FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (typing || _busy || _job != null) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final kb = HardwareKeyboard.instance;
    final ctrl = kb.isControlPressed || kb.isMetaPressed;
    if (ctrl && k == LogicalKeyboardKey.keyZ) {
      kb.isShiftPressed ? _redo() : _undo();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyY) {
      _redo();
      return KeyEventResult.handled;
    }
    if (ctrl) return KeyEventResult.ignored;
    final step = kb.isShiftPressed ? 1.0 : StudioTransport.frame;
    if (k == LogicalKeyboardKey.space) {
      _playPause();
    } else if (k == LogicalKeyboardKey.keyK) {
      _player?.pause();
    } else if (k == LogicalKeyboardKey.keyJ) {
      _seek(_pos - 5);
    } else if (k == LogicalKeyboardKey.keyL) {
      _seek(_pos + 5);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _player?.pause();
      _seek(_pos - step);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _player?.pause();
      _seek(_pos + step);
    } else if (k == LogicalKeyboardKey.home) {
      _seek(0);
    } else if (k == LogicalKeyboardKey.end) {
      _seek(_edit.duration);
    } else if (k == LogicalKeyboardKey.keyI && _tool.isEditing) {
      _setMark(true);
    } else if (k == LogicalKeyboardKey.keyO && _tool.isEditing) {
      _setMark(false);
    } else if (k == LogicalKeyboardKey.keyS && _tool.isEditing) {
      _split();
    } else if ((k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) && _tool.isEditing) {
      if (_markIn != null && _markOut != null) {
        _removeMarked();
      } else if (_selOverlay != null) {
        _deleteOverlay(_selOverlay!);
      } else if (_selClip != null) {
        _deleteClip();
      }
    } else if (k == LogicalKeyboardKey.escape) {
      setState(() {
        _selClip = null;
        _selOverlay = null;
        _markIn = _markOut = null;
      });
    } else if (k == LogicalKeyboardKey.equal || k == LogicalKeyboardKey.numpadAdd) {
      setState(() => _zoom = math.min(_zoom * 2, 4096));
    } else if (k == LogicalKeyboardKey.minus || k == LogicalKeyboardKey.numpadSubtract) {
      setState(() => _zoom = math.max(1, _zoom / 2));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  Widget _preview(BuildContext context) {
    final c = context.colors;
    final p = _player;
    if (_playError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Text(_playError!, textAlign: TextAlign.center, style: appText(13, c: c.onHeroMuted, h: 1.4)),
        ),
      );
    }
    if (!_ready || p == null) return AppShimmer(child: ColoredBox(color: c.heroShade, child: const SizedBox.expand()));
    if (_item.isAudio) {
      return GestureDetector(
        onTap: _playPause,
        child: Stack(fit: StackFit.expand, children: [
          Center(child: Icon(Icons.graphic_eq_rounded, color: c.onHeroFaint, size: 88)),
          StudioPlayMark(playing: _playing),
        ]),
      );
    }
    final editing = !_busy && _job == null;
    return Stack(fit: StackFit.expand, children: [
      VideoPlayer(p),
      StudioOverlayLayer(
        edit: _edit,
        now: _pos,
        selected: _selOverlay,
        images: _images,
        editing: editing && (_tool == StudioTool.text || _tool == StudioTool.image || _tool == StudioTool.edit),
        onSelect: _selectOverlay,
        onMove: _overlayMove,
        onMoveEnd: _overlayMoveEnd,
        onScale: _overlayScale,
        onScaleEnd: _overlayScaleEnd,
        onTapEmpty: () {
          if (_selOverlay != null) {
            setState(() => _selOverlay = null);
          } else {
            _playPause();
          }
        },
      ),
      StudioPlayMark(playing: _playing || _selOverlay != null),
    ]);
  }

  Widget _panel(BuildContext context, bool editing) {
    final e = _edit;
    switch (_tool) {
      case StudioTool.edit:
        return StudioEditPanel(
          edit: e,
          position: _pos,
          markIn: _markIn,
          markOut: _markOut,
          selectedClip: _selClip,
          enabled: editing,
          onSplit: _split,
          onMarkIn: () => _setMark(true),
          onMarkOut: () => _setMark(false),
          onNudgeMark: (isIn, by) => setState(() {
            if (isIn && _markIn != null) _markIn = (_markIn! + by).clamp(0.0, (_markOut ?? e.duration) - 0.05);
            if (!isIn && _markOut != null) _markOut = (_markOut! + by).clamp((_markIn ?? 0) + 0.05, e.duration);
            _seek(isIn ? _markIn! : _markOut!);
          }),
          onClearMarks: () => setState(() => _markIn = _markOut = null),
          onRemoveMarked: _removeMarked,
          onKeepMarked: _keepMarked,
          onDeleteClip: _deleteClip,
          onNudgeClip: _nudgeClip,
          onSpeed: _speed,
        );
      case StudioTool.text:
      case StudioTool.image:
        final kind = _tool == StudioTool.text ? StudioOverlayKind.text : StudioOverlayKind.image;
        final sel = _overlay(_selOverlay);
        return StudioOverlayPanel(
          kind: kind,
          edit: e,
          position: _pos,
          selected: sel != null && sel.kind == kind ? sel : null,
          images: _images,
          enabled: editing,
          canAdd: !_item.isAudio,
          onAdd: (place, {text, background, size}) => _addOverlay(kind, place, text: text, background: background, size: size),
          onSelect: _selectOverlay,
          onChange: _overlayChange,
          onDelete: _deleteOverlay,
          onDuplicate: _duplicateOverlay,
        );
      case StudioTool.history:
        return StudioHistoryPanel(
          history: _hist,
          enabled: editing,
          onRestore: (i) => _moveHead(_hist.restore(i)),
          onReset: _reset,
          clock: (at) => AppTime.time(at.toUtc()),
        );
      case StudioTool.split:
        final h = studioHalves(e, _pos);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(children: [
              Expanded(child: StudioTimeField(label: t('الملف الأول', 'File 1'), value: h?.$1.duration ?? 0, idKey: 'part1')),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: StudioTimeField(label: t('الملف الثاني', 'File 2'), value: h?.$2.duration ?? 0, idKey: 'part2')),
            ]),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(t('حرّك المؤشر إلى حيث تريد القسمة. تشمل الملفّان كل تعديلاتك ونصوصك وصورك.', 'Move the playhead to where it should split. Both files carry all your edits, texts and pictures.'),
              style: appText(12, c: context.colors.textMedium, h: 1.45)),
        ]);
      case StudioTool.quality:
      case StudioTool.cover:
      case StudioTool.merge:
        return StudioToolPanel(
          tool: _tool,
          item: _item,
          duration: e.duration,
          height: e.height,
          level: e.level ?? StudioQualityLevel.balanced,
          merge: studioMergePicks(_item, widget.others, _mergeIds),
          enabled: editing,
          onQuality: _setQuality,
          onPickCover: _pickCover,
          onRemoveCover: () => _coverCall(() => _src.clearCover(_item.id), t('أُزيل الغلاف', 'Cover removed')),
          onToggleMerge: _toggleMerge,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _frames;
    final editing = !_busy && _job == null;
    final e = _edit;
    final wide = MediaQuery.sizeOf(context).width;
    final maxZoom = StudioTimelineView.maxZoom(math.max(320, wide - 520), e.duration);
    if (_zoom > maxZoom) _zoom = maxZoom;
    final layout = RecordStudioLayout(
      busy: !editing,
      tools: _tools,
      tool: _tool,
      onTool: _setTool,
      canvas: _canvas,
      aspect: _item.isAudio ? 16 / 9 : _aspect,
      preview: _preview(context),
      transport: StudioTransport(
        position: _pos,
        duration: e.duration,
        playing: _playing,
        previewSpeed: _previewSpeed,
        enabled: _ready,
        zoom: _zoom,
        maxZoom: maxZoom,
        onPlayPause: _playPause,
        onSkip: (by) {
          if (by.abs() < 1) _player?.pause();
          _seek(_pos + by);
        },
        onPreviewSpeed: _nextPreviewSpeed,
        onZoom: (z) => setState(() => _zoom = z),
      ),
      timeline: StudioTimelineView(
        edit: e,
        position: _pos,
        sourceDuration: _srcDur,
        zoom: _zoom,
        markIn: _markIn,
        markOut: _markOut,
        selectedClip: _selClip,
        selectedOverlay: _selOverlay,
        sprite: _sprite,
        spriteCount: f?.count ?? 0,
        waveform: f?.waveform,
        framesPending: f == null ? !_item.isAudio : f.pending,
        playing: _playing,
        enabled: editing && _ready,
        onZoom: (z) => setState(() => _zoom = z),
        onScrubStart: _scrubStart,
        onScrub: _scrub,
        onScrubEnd: _scrubEnd,
        onSelectClip: (i) => setState(() {
          _selClip = i;
          _selOverlay = null;
          if (i != null && !_tool.isEditing) _tool = StudioTool.edit;
          if (i != null && (_tool == StudioTool.text || _tool == StudioTool.image)) _tool = StudioTool.edit;
        }),
        onSelectOverlay: _selectOverlay,
        onTrim: _onTrim,
        onTrimEnd: _onTrimEnd,
        onOverlaySpan: _overlaySpan,
        onOverlaySpanEnd: _overlaySpanEnd,
        onMarks: (a, b) => setState(() {
          _markIn = a;
          _markOut = b;
          final at = a != _markIn ? a : b;
          if (at != null) _seek(at);
        }),
      ),
      panel: _panel(context, editing),
      summary: StudioSummary(original: _srcDur, result: _result, problem: _tool == StudioTool.cover || _tool == StudioTool.history ? null : _problem),
      save: _tool == StudioTool.cover
          ? null
          : StudioSaveArea(
              merge: _tool == StudioTool.merge,
              draft: _src.drafts,
              replace: _replace,
              canSave: _problem == null && _ready,
              canUndo: _hist.canUndo,
              canRedo: _hist.canRedo,
              busy: _busy,
              saveLabel: _tool == StudioTool.split ? (_src.drafts ? t('حفظ مسودتين', 'Save two drafts') : t('حفظ ملفين', 'Save two files')) : null,
              onReplace: (v) => setState(() => _replace = v),
              onUndo: _undo,
              onRedo: _redo,
              onReset: _hist.current.isOriginal(_srcDur) ? null : _reset,
              onSave: _save,
              title: TextField(
                key: const ValueKey('studio.title'),
                controller: _title,
                maxLength: 120,
                onChanged: (_) => _titleTouched = true,
                decoration: InputDecoration(
                  labelText: _tool == StudioTool.split
                      ? t('اسم الملفين (يُضاف 1 و2)', 'Name of the two (1 and 2 are added)')
                      : _src.drafts
                          ? t('اسم الفيديو الجديد', 'Name of the new video')
                          : t('اسم التسجيل الجديد', 'Name of the new recording'),
                ),
              ),
            ),
      job: _job == null
          ? null
          : StudioJobCard(
              items: _job!,
              eta: {for (final r in _job!) r.id: _eta(r)},
              downloading: _downloads,
              onRetry: _retryJob,
              onCancel: _cancelJob,
              onDownload: (r) => _download(job: r),
              onContinue: _continueJob,
              onPlay: widget.onPlay == null ? null : (r) => widget.onPlay!(context, r),
              onAgain: _again,
              onLibrary: () => Navigator.of(context).pop(_popValue()),
              actionsFor: widget.jobActions == null ? null : (r) => widget.jobActions!(context, r),
              drafts: _src.drafts,
              libraryLabel: widget.libraryLabel,
            ),
      footer: kIsWeb || studioIsWide(MediaQuery.sizeOf(context)) ? const StudioKeysHint() : null,
      stageNote: _stageNote,
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_popValue());
      },
      child: BasePage(
        key: const ValueKey('records.studio'),
        background: StudioBay.of(context).deck,
        appBar: StudioTopBar(
          title: _item.title,
          facts: _item.facts(),
          saveState: _saveState,
          canvas: _canvas,
          onCanvas: () => setState(() => _canvas = StudioCanvas.values[(_canvas.index + 1) % StudioCanvas.values.length]),
          onDownload: () => _download(),
          downloading: _originalDownload,
        ),
        child: Focus(focusNode: _focus, autofocus: true, onKeyEvent: _key, child: layout),
      ),
    );
  }
}

/// Is the app in Arabic (a new text starts in the Arabic font choice).
abstract final class AppConfigLang {
  static bool get isArabic => t('ar', 'en') == 'ar';
}
