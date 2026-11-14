// lib/features/records/records_studio.dart — the Studio (D-312, premium D-590 … D-597, redesigned D-820 … D-829):
// the editor of one of my records or of a course session's video. Plain-values widgets: records_studio_parts.dart (bay,
// top bar, transport, action bars, layout, job card), studio_timeline.dart (the multi-track timeline), studio_stage.dart
// (texts and pictures on the picture), studio_panels.dart (Edit · Text · Picture · History), studio_export.dart (the
// Export panel); the pure edit list and its history: studio_project.dart; where the work is kept: studio_autosave.dart.
//
//   The source is pluggable (studio_source.dart, D-315): a drive recording of Records (default) or a course session's
//   video material (MaterialStudioSource: no Cover, the job makes a DRAFT, `jobActions` puts Publish on the card).
//
//   One project, many steps (D-590): splits, removes, trims, moves, per-part speed, texts and pictures with animations
//   are steps of ONE edit list, rendered by ONE job (POST …/render) from the Export panel, which also holds the quality
//   and "two files" (D-827). Undo / Redo sit in the top bar; the project autosaves (D-826: the device first, then the
//   server with a revision; a newer copy elsewhere is never overwritten in silence). Editing never waits for an export
//   (D-828): the render runs on the server while the person keeps working.
//   The preview plays THROUGH the edit: removed parts are skipped, each part plays at its speed, and the texts and
//   pictures animate over it as the file will show them (the text is drawn by the app and sent as a PNG, D-591).
//   Keys (web / desktop, never while typing): Space play / pause · J −5 s · K pause · L +5 s · ← / → a frame (Shift: a
//   second) · I / O mark in / out · S split · Delete remove the marked period / the selection · Alt+← / → move the
//   selected part · Ctrl+Z undo · Ctrl+Shift+Z / Ctrl+Y redo · Ctrl+S save now · Ctrl+E export · Home / End · + / −
//   zoom · Esc close the panel / clear the selection.
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
import 'package:flutter_education_app/core/api_client.dart' show ApiException;
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/records/records_api.dart';
import 'package:flutter_education_app/features/records/records_share.dart' show showRecordShareSheet;
import 'package:flutter_education_app/features/records/records_share_api.dart';
import 'package:flutter_education_app/features/records/records_studio_parts.dart';
import 'package:flutter_education_app/features/records/studio_autosave.dart';
import 'package:flutter_education_app/features/records/studio_download_io.dart' if (dart.library.js_interop) 'package:flutter_education_app/features/records/studio_download_web.dart' as saver;
import 'package:flutter_education_app/features/records/studio_export.dart';
import 'package:flutter_education_app/features/records/studio_panels.dart';
import 'package:flutter_education_app/features/records/studio_project.dart';
import 'package:flutter_education_app/features/records/studio_source.dart';
import 'package:flutter_education_app/features/records/studio_stage.dart';
import 'package:flutter_education_app/features/records/studio_timeline.dart';

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

  /// The saved work has been looked for (editing waits for it: an edit made before would overwrite it, D-826).
  bool _projectReady = false;

  /// The server's revision of the project this history was made from.
  int _rev = 0;

  /// Phones: the open tool's panel is shown in place of the timeline (D-820).
  bool _panelOpen = false;

  StudioEdit get _edit => _live ?? _hist.current;

  // ── tools ──
  late StudioTool _tool = _tools.first;
  List<int> _mergeIds = const [];
  bool _replace = false;

  // ── export settings (D-827: choices of the export, not steps of the edit) ──
  int? _exHeight;
  StudioQualityLevel _exLevel = StudioQualityLevel.balanced;
  bool _twoFiles = false;

  /// The export panel follows the job: it rebuilds on this.
  final _sheet = _Tick();
  bool _sheetOpen = false;

  /// The last export finished and has not been looked at.
  bool _exportUnseen = false;
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
  late final TextEditingController _mergeTitle = TextEditingController(text: defaultEditTitle(widget.item.title, RecordOp.merge));
  final _focus = FocusNode(debugLabel: 'records-studio');

  /// An audio file has no picture to change or put things on; Quality and Two files live in the Export panel.
  List<StudioTool> get _tools => [
        for (final x in _src.tools)
          if (x.inRail && (!_item.isAudio || (x != StudioTool.text && x != StudioTool.image))) x,
      ];

  bool get _offersQuality => !_item.isAudio && _src.tools.contains(StudioTool.quality);
  bool get _offersTwoFiles => _src.tools.contains(StudioTool.split);
  String get _storeKind => _src.jobEventKind;

  Object? _popValue() => widget.popResult != null ? widget.popResult!() : List<RecordItem>.of(_made);

  @override
  void initState() {
    super.initState();
    _open();
    _loadProject();
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
    _mergeTitle.dispose();
    _sheet.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Player: plays THROUGH the edit
  // ─────────────────────────────────────────────────────────────────────────

  /// The preview failed (a link that expired, a dropped connection, a file the browser can't play): try again in place.
  Future<void> _reopen() async {
    final old = _player;
    setState(() {
      _playError = null;
      _ready = false;
      _player = null;
    });
    old?.removeListener(_onPlayer);
    await old?.dispose();
    _open();
  }

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
      _loadProject(); // a record whose length was unknown until now
    } catch (e) {
      if (mounted) setState(() => _playError = recordsErrorText(e));
      _loadProject();
    }
  }

  /// The person's saved work on this source, if it fits the source: the server's copy, or the device's when it holds
  /// work the server never got (D-826). Editing waits for this (an edit made first would be saved over it).
  Future<void> _loadProject() async {
    if (_projectLoaded) return;
    if (_srcDur <= 0) {
      // the length comes with the player; without a player there is nothing to edit
      if (_playError != null && mounted) setState(() => _projectReady = true);
      return;
    }
    _projectLoaded = true;
    Map<String, dynamic>? server;
    var failed = false;
    try {
      server = await _src.loadProject(_item.id);
    } catch (_) {
      failed = true; // offline, or an older server: the device copy may still have it
    }
    final local = await StudioLocalStore.read(_storeKind, _item.id);
    if (!mounted) return;
    // unsent work here that another device has saved past: the person chooses below (D-831); mine shows meanwhile
    final conflict = studioProjectConflict(server: server, local: local, serverFailed: failed);
    final (doc, fromDevice) = conflict ? (local!.doc, true) : studioPickProject(server: server, local: local, serverFailed: failed);
    // offline, the server's revision is unknown: the device copy's base is the last one seen (D-832)
    _rev = failed || conflict ? (local?.base ?? 0) : studioDocRev(server);
    final h = doc == null ? null : StudioHistory.fromJson(doc, duration: _srcDur);
    setState(() {
      _projectReady = true;
      if (h != null && h.steps.length >= 2) {
        _hist = h;
        _readExport(doc!);
        _fixSelection();
        _saveState = fromDevice ? StudioSaveState.local : StudioSaveState.saved;
      }
    });
    _resumeJobs(doc);
    if (conflict) {
      if (h != null && h.steps.length >= 2) _fetchImages();
      await _resolve(server, studioDocRev(server));
      return;
    }
    if (h == null || h.steps.length < 2) return;
    _fetchImages();
    if (fromDevice && !failed) _scheduleSave(); // send what the server never got
    showAppNotice(t('أكملنا من حيث توقفت — ${h.steps.length - 1} خطوة محفوظة', 'Picked up where you left off — ${h.steps.length - 1} steps kept'));
  }

  /// The export choices kept with the project (and an older project's Quality step, D-827).
  void _readExport(Map<String, dynamic> doc) {
    final x = doc['export'];
    if (x is Map) {
      final hh = x['height'];
      _exHeight = hh is num ? hh.toInt() : null;
      _exLevel = StudioQualityLevel.values.where((l) => l.wire == '${x['level'] ?? ''}').firstOrNull ?? StudioQualityLevel.balanced;
      _twoFiles = x['two'] == true;
    } else {
      _exHeight = _hist.current.height;
      _exLevel = _hist.current.level ?? StudioQualityLevel.balanced;
    }
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

  /// [next] as a new step. Undone steps go (D-825: no question in the middle of a drag; a notice says how many, and the
  /// History panel's restore still reaches every step before them).
  Future<void> _commit(StudioStepKind kind, StudioEdit next, {Map<String, dynamic> info = const {}}) async {
    if (identical(next, _hist.current)) {
      if (_live != null) setState(() => _live = null);
      return;
    }
    final dropped = _hist.undone;
    final before = _hist;
    setState(() {
      _hist = _hist.commit(kind, next, info: info);
      _live = null;
      _fixSelection();
    });
    if (dropped >= 2 && !identical(before, _hist)) {
      showAppNotice(t('حُذفت $dropped خطوات كنت تراجعت عنها', 'The $dropped steps you had undone were dropped'));
    }
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
    if (mounted && _saveState != StudioSaveState.saving) setState(() => _saveState = StudioSaveState.saving);
    _saveTimer = Timer(const Duration(milliseconds: 1200), _saveNow);
  }

  /// Saves at once (Ctrl+S, leaving, before an export).
  Future<void> _flushSave() async {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      await _saveNow();
    } else if (_saving != null) {
      await _saving;
    }
  }

  Future<void>? _saving;

  Map<String, dynamic>? _doc(int rev) => _hist.steps.length <= 1
      ? null
      : {
          ..._hist.toJson(_srcDur),
          'rev': rev,
          'export': {'height': _exHeight, 'level': _exLevel.wire, 'two': _twoFiles, 'jobs': _jobIds},
        };

  List<int> get _jobIds => [for (final r in _job ?? const <RecordItem>[]) r.id];

  /// Remembers the running export on the device and with the project, so a reload follows it again (D-905).
  void _rememberJobs() {
    StudioLocalStore.writeJobs(_storeKind, _item.id, _jobIds);
    if (_hist.steps.length > 1) _scheduleSave();
  }

  /// After a reload: the exports this source had going (device or project), followed again — running ones show their
  /// percent on Export, finished ones say Ready until they are seen.
  Future<void> _resumeJobs(Map<String, dynamic>? doc) async {
    final ids = {...studioDocJobs(doc), ...await StudioLocalStore.readJobs(_storeKind, _item.id)}.toList();
    if (ids.isEmpty || _job != null) return;
    final found = <RecordItem>[];
    for (final id in ids) {
      try {
        final r = await _src.get(id);
        if (r != null) found.add(r);
      } catch (_) {/* gone: nothing to follow */}
    }
    if (!mounted || _job != null) return;
    if (found.isEmpty) {
      StudioLocalStore.writeJobs(_storeKind, _item.id, const []);
      return;
    }
    final running = found.any((r) => r.inProgress);
    _update(() {
      _job = found;
      _exportUnseen = true;
    });
    _keep(found);
    _watchJob();
    showAppNotice(running ? t('التصدير ما زال يجري — نتابعه هنا', 'Your export is still running — following it here') : t('آخر تصدير جاهز', 'Your last export is ready'));
  }

  Future<void> _saveNow() {
    final run = _saveOnce();
    _saving = run;
    return run.whenComplete(() {
      if (identical(_saving, run)) _saving = null;
    });
  }

  /// The next save overwrites without a base: only after the person said so, when the other copy's revision is unknown.
  bool _overwrite = false;

  Future<void> _saveOnce() async {
    final base = _rev;
    final doc = _doc(base + 1);
    // the device first: a lost connection or a closed tab keeps the work (D-826)
    await StudioLocalStore.write(_storeKind, _item.id, doc, dirty: true, base: base);
    if (mounted) setState(() => _saveState = StudioSaveState.saving);
    try {
      await _src.saveProject(_item.id, doc, base: _overwrite ? null : base);
      _overwrite = false;
      _rev = doc == null ? 0 : base + 1;
      await StudioLocalStore.write(_storeKind, _item.id, null, dirty: false, base: 0);
      if (mounted) setState(() => _saveState = doc == null ? StudioSaveState.idle : StudioSaveState.saved);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409 && e.code == 'project_conflict') {
        await _conflict(e);
        return;
      }
      final offline = e.statusCode == 0 || e.statusCode >= 500;
      setState(() => _saveState = offline ? StudioSaveState.local : StudioSaveState.failed);
      _saveTimer = Timer(const Duration(seconds: 12), _saveNow);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saveState = StudioSaveState.local);
      _saveTimer = Timer(const Duration(seconds: 12), _saveNow);
    }
  }

  /// The server holds a newer copy (another tab or device): keep mine or take theirs, never overwrite in silence.
  Future<void> _conflict(ApiException e) async {
    final c = studioConflictOf(e.body); // a Map or a JSON string (D-832)
    await _resolve(c.doc, c.rev);
  }

  /// Keep mine or open theirs ([theirs] at revision [theirRev]; null rev: the other copy could not be read). Nothing is
  /// overwritten without a yes, and an unreadable answer never sets the revision (that looped a 409 on every save).
  Future<void> _resolve(Map<String, dynamic>? theirs, int? theirRev) async {
    _saveTimer?.cancel();
    final h = theirs == null ? null : StudioHistory.fromJson(theirs, duration: _srcDur);
    if (h == null) {
      final overwrite = await appConfirm(context,
          message: t('عُدّل هذا المشروع في نافذة أو جهاز آخر ولا يمكن فتح تلك النسخة هنا. أتستبدلها بنسختك؟',
              'This project was changed in another window or device, and that version cannot be opened here. Replace it with yours?'),
          danger: true,
          confirmLabel: t('استبدلها بنسختي', 'Replace with mine'));
      if (!mounted) return;
      if (!overwrite) {
        setState(() => _saveState = StudioSaveState.failed); // mine stays on this device, unsent, until the next change
        return;
      }
      if (theirRev != null) {
        _rev = theirRev;
      } else {
        _overwrite = true;
      }
      _scheduleSave();
      return;
    }
    final keepMine = await appConfirm(context,
        message: t('عُدّل هذا المشروع في نافذة أو جهاز آخر (${h.steps.length - 1} خطوة). احتفظ بنسختك هنا، أو افتح النسخة الأخرى؟',
            'This project was changed in another window or device (${h.steps.length - 1} steps). Keep your version here, or open the other one?'),
        confirmLabel: t('احتفظ بنسختي', 'Keep mine'));
    if (!mounted) return;
    _rev = theirRev ?? studioDocRev(theirs);
    if (keepMine) {
      _scheduleSave(); // over theirs, now knowingly
      return;
    }
    setState(() {
      _hist = h;
      _live = null;
      _readExport(theirs!);
      _fixSelection();
      _saveState = StudioSaveState.saved;
    });
    await StudioLocalStore.write(_storeKind, _item.id, null, dirty: false, base: 0);
    _fetchImages();
    _seek(_pos);
  }

  /// Back: the last change is saved first (a moment at most); what the server could not take stays on the device.
  Future<void> _leave() async {
    if ((_saveTimer?.isActive ?? false) || _saving != null) {
      await _flushSave().timeout(const Duration(seconds: 4), onTimeout: () {});
    }
    if (!mounted) return;
    if (_saveState == StudioSaveState.local || _saveState == StudioSaveState.failed) {
      showAppNotice(t('حُفظ عملك على هذا الجهاز، ويُرسل عند فتح الاستوديو مرة أخرى', 'Your work is kept on this device and sent the next time you open the Studio'));
    }
    Navigator.of(context).pop(_popValue());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Edit operations
  // ─────────────────────────────────────────────────────────────────────────

  void _split() {
    final e = _edit;
    final n = e.split(_pos);
    if (identical(n, e)) {
      showAppNotice(t('المؤشر على حافة جزء — حرّكه قليلاً ثم قسّم', 'The playhead is on a part’s edge — move it a little, then split'), error: true);
      return;
    }
    _commit(StudioStepKind.split, n, info: {'at': _pos});
    setState(() => _selClip = n.hit(_pos)?.clip);
  }

  /// Trim start / Trim end (Q / W, D-904): the part under the playhead loses everything before / after it — the
  /// quickest way to trim a start or an end without dragging a handle.
  void _trimToPlayhead(bool start) {
    final e = _edit;
    final r = studioTrimAt(e, _pos, start: start, selected: _selClip, sourceDuration: _srcDur);
    if (r == null) {
      showAppNotice(t('لا شيء يُقص هنا — حرّك المؤشر داخل الجزء', 'Nothing to trim here — move the playhead inside the part'), error: true);
      return;
    }
    final (n, i, src) = r;
    _commit(start ? StudioStepKind.trimStart : StudioStepKind.trimEnd, n, info: {'to': src});
    setState(() => _selClip = i);
    _seek(start ? n.clipStart(i) : math.max(0, n.clipStart(i) + n.clips[i].length - 0.04));
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

  /// Plays the part [from] at place [to] (drag on the timeline, the Move buttons, Alt+← / →; D-823).
  void _moveClip(int from, int to) {
    final n = _edit.moveClip(from, to);
    if (identical(n, _edit)) return;
    final at = _pos;
    _commit(StudioStepKind.moveClip, n, info: {'to': to + 1});
    setState(() => _selClip = to.clamp(0, n.clips.length - 1));
    _seek(math.min(at, n.duration));
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
    if (!mounted) return;
    setState(() => _selOverlay = o.id);
    _seek(e.outputOf(o.start) == null ? _pos : a + math.min(1.0, o.inDur + 0.1)); // past its entrance: it shows at once
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

  /// The export's quality: a choice of the export, kept with the project, not a step of the edit (D-827).
  void _setExportQuality(int? height, StudioQualityLevel level) {
    _update(() {
      _exHeight = height;
      _exLevel = level;
    });
    _scheduleSave();
  }

  /// setState that also rebuilds the open Export panel.
  void _update(VoidCallback fn) {
    setState(fn);
    _sheet.ping();
  }

  void _toggleMerge(RecordItem r) => setState(() {
        _mergeIds = _mergeIds.contains(r.id) ? [for (final i in _mergeIds) if (i != r.id) i] : [..._mergeIds, r.id];
      });

  void _setTool(StudioTool x, {bool open = true}) {
    setState(() {
      _tool = x;
      if (open && !studioIsWide(MediaQuery.sizeOf(context))) _panelOpen = true;
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
        _markIn = _markOut = null;
      }
    });
  }

  String _defaultTitle() => '${_item.title} · ${RecordOp.project.madeBy}'; // Merge names its result in its own panel

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

  /// The edit as the export renders it: the edit list with the export's quality.
  StudioEdit get _exportEdit => _edit.copyWith(height: () => _offersQuality ? _exHeight : null, level: () => _offersQuality ? _exLevel : null);

  (double, double)? get _halves {
    final h = studioHalves(_exportEdit, _pos);
    return h == null ? null : (h.$1.duration, h.$2.duration);
  }

  /// Why the export cannot be made (null: it can).
  String? get _exportProblem {
    final e = _edit;
    if (!_ready) return t('ينتظر تحميل الفيديو', 'Waiting for the video');
    if (e.duration < 1) return t('الفيديو الناتج قصير جداً', 'The result is too short');
    if (_twoFiles && _halves == null) return t('ضع المؤشر داخل الفيديو ليُقسم عنده', 'Put the playhead inside the video to split there');
    final sameQuality = !_offersQuality || (_exHeight == null && _exLevel == StudioQualityLevel.balanced);
    if (!_twoFiles && e.isOriginal(_srcDur) && sameQuality) return t('لم تغيّر شيئاً بعد', 'Nothing has changed yet');
    return null;
  }

  List<double> get _exportResult {
    if (_twoFiles) {
      final h = _halves;
      return h == null ? const [] : [h.$1, h.$2];
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

  /// Renders the project (once, or as two files) with the export's choices. Editing goes on meanwhile (D-828).
  Future<void> _export() async {
    if (_exportProblem != null || _busy) return;
    if (_replace &&
        !_src.drafts &&
        !_twoFiles &&
        !await appConfirm(context,
            message: t('سيُحذف الأصل من القائمة ومن السحابة بعد نجاح التصدير. متابعة؟',
                'The original will be deleted from the list and the drive once the export is done. Continue?'),
            danger: true,
            confirmLabel: t('متابعة', 'Continue'))) {
      return;
    }
    if (!mounted) return;
    // a change still in the making (a text being typed, a slider held) becomes a step first: the file, the history and
    // the draft's saved project always agree
    if (_live != null) {
      await _commit(StudioStepKind.overlayStyle, _live!, info: {'name': _overlay(_selOverlay)?.name ?? ''});
      if (!mounted) return;
    }
    _flushSave();
    _update(() => _busy = true);
    _player?.pause();
    try {
      final e = _exportEdit;
      final (assets, widths) = await _prepareAssets(e);
      final doc = _hist.toJson(_srcDur);
      final List<RecordItem> made = [];
      if (_twoFiles) {
        final halves = studioHalves(e, _pos)!;
        final base = _title.text.trim();
        for (final (i, h) in [halves.$1, halves.$2].indexed) {
          final p = studioRenderParams(h, assets: assets, textWidths: widths, history: doc, title: base.isEmpty ? null : '$base · ${i + 1}');
          made.addAll(await _src.render(_item.id, p));
        }
      } else {
        final p = studioRenderParams(e, assets: assets, textWidths: widths, history: doc, title: _title.text);
        if (_replace && !_src.drafts) p['delete_source'] = true;
        made.addAll(await _src.render(_item.id, p));
      }
      if (!mounted) return;
      _started(made);
    } catch (e) {
      if (!mounted) return;
      _update(() => _busy = false);
      showAppNotice(recordsErrorText(e), error: true);
    }
  }

  /// Merge (Records' originals, not the project): its own button in the Merge panel; the job shows in the Export panel.
  Future<void> _merge() async {
    if (_mergeIds.isEmpty || _busy) return;
    if (_replace &&
        !_src.drafts &&
        !await appConfirm(context,
            message: t('ستُحذف الأصول من القائمة ومن السحابة بعد نجاح الدمج. متابعة؟', 'The originals will be deleted from the list and the drive once merged. Continue?'),
            danger: true,
            confirmLabel: t('متابعة', 'Continue'))) {
      return;
    }
    if (!mounted) return;
    _update(() => _busy = true);
    _player?.pause();
    try {
      final made = await _src.merge([_item.id, ..._mergeIds], title: _mergeTitle.text, deleteSources: _replace && !_src.drafts);
      if (!mounted) return;
      _started(made);
      if (!_sheetOpen) _openExport();
    } catch (e) {
      if (!mounted) return;
      _update(() => _busy = false);
      showAppNotice(recordsErrorText(e), error: true);
    }
  }

  void _started(List<RecordItem> made) {
    _update(() {
      _busy = false;
      _job = made;
      _exportUnseen = !_sheetOpen;
    });
    _keep(made);
    _rememberJobs();
    _watchJob();
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
      final wasRunning = job.any((r) => r.inProgress);
      _update(() {
        _job = fresh;
        if (wasRunning && !fresh.any((r) => r.inProgress) && !_sheetOpen) _exportUnseen = true;
      });
      _keep(fresh);
      if (wasRunning && !fresh.any((r) => r.inProgress) && !_sheetOpen) {
        showAppNotice(fresh.every((r) => r.isDone) ? t('التصدير جاهز', 'The export is ready') : t('تعذّر إكمال التصدير', 'The export could not finish'),
            error: !fresh.every((r) => r.isDone));
      }
    } catch (_) {/* the next event / poll tries again */}
    _watchJob();
  }

  Future<void> _retryJob(RecordItem r) async {
    try {
      final n = await _src.retry(r.id);
      if (n == null || !mounted) return;
      _samples.remove(r.id);
      _update(() => _job = [for (final x in _job ?? const <RecordItem>[]) x.id == n.id ? n : x]);
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
      _update(() => _job = [for (final x in _job ?? const <RecordItem>[]) x.id == n.id ? n : x]);
      _watchJob();
    } catch (e) {
      if (mounted) showAppNotice(recordsErrorText(e), error: true);
    }
  }

  /// Opens what a finished export was made from as a NEW step (D-825: the work since then stays in the history).
  Future<void> _continueJob(RecordItem r) async {
    try {
      final p = await _src.jobProject(r.id);
      final doc = p == null ? null : p['history'];
      final h = doc is Map ? StudioHistory.fromJson(Map<String, dynamic>.from(doc), duration: _srcDur) : null;
      if (h == null) {
        showAppNotice(t('لا يوجد سجل محفوظ لهذا التعديل', 'This edit has no saved history'), error: true);
        return;
      }
      if (!mounted) return;
      if (_sheetOpen) Navigator.of(context).maybePop();
      await _commit(StudioStepKind.restore, h.current, info: {'name': r.title});
      if (!mounted) return;
      setState(() => _tool = StudioTool.edit);
      _fetchImages();
      _seek(0);
    } catch (e) {
      if (mounted) showAppNotice(recordsErrorText(e), error: true);
    }
  }

  Future<void> _download({RecordItem? job}) async {
    if (job == null ? _originalDownload != null : _downloads.containsKey(job.id)) return;
    void progress(double v) {
      if (!mounted) return;
      _update(() {
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
        _update(() {
          if (job == null) {
            _originalDownload = null;
          } else {
            _downloads.remove(job.id);
          }
        });
      }
    }
  }

  /// A new export (the last one's result stays in Records / the drafts).
  void _again() {
    _jobWatch?.stop();
    _update(() {
      _job = null;
      _replace = false;
      _titleTouched = false;
      _syncTitle();
    });
    _rememberJobs(); // nothing to follow after a reload any more
  }

  /// Every key of the Studio in one sheet (? or ⋯ › Keyboard shortcuts, D-910).
  void _showKeys() {
    showAppSheet<void>(
      context,
      (ctx) => AppSheetContent(title: t('اختصارات لوحة المفاتيح', 'Keyboard shortcuts'), icon: Icons.keyboard_alt_outlined, children: const [StudioKeysHint(sheet: true)]),
    );
  }

  /// The Export panel: the settings, or the job it follows.
  Future<void> _openExport() async {
    if (_sheetOpen) return;
    final job = _job;
    if (job != null && !job.any((r) => r.inProgress) && !_exportUnseen) _again(); // the last one was seen: a new export
    setState(() {
      _sheetOpen = true;
      _exportUnseen = false;
      _panelOpen = false;
    });
    _player?.pause();
    await showAppSheet<void>(
      context,
      (ctx) => ListenableBuilder(listenable: _sheet, builder: (ctx, _) => _exportPanel(ctx)),
    );
    if (mounted) setState(() => _sheetOpen = false);
  }

  Widget _exportPanel(BuildContext ctx) {
    final job = _job;
    final running = job != null && job.any((r) => r.inProgress);
    final done = job != null && job.isNotEmpty && job.every((r) => r.isDone);
    final title = job == null
        ? t('تصدير', 'Export')
        : running
            ? t('يجري التصدير', 'Exporting')
            : done
                ? t('جاهز', 'Ready')
                : t('التصدير', 'The export');
    return AppSheetContent(
      title: title,
      icon: Icons.ios_share_rounded,
      subtitle: job == null ? _item.title : null,
      children: [
        if (job == null)
          StudioExportSettings(
            item: _item,
            duration: _exportEdit.duration,
            form: StudioSaveArea(
              title: TextField(
                key: const ValueKey('studio.title'),
                controller: _title,
                maxLength: 120,
                onChanged: (_) => _titleTouched = true,
                decoration: InputDecoration(
                  labelText: _twoFiles
                      ? t('اسم الملفين (يُضاف 1 و2)', 'Name of the two (1 and 2 are added)')
                      : _src.drafts
                          ? t('اسم الفيديو الجديد', 'Name of the new video')
                          : t('اسم التسجيل الجديد', 'Name of the new recording'),
                ),
              ),
              draft: _src.drafts,
              replace: _replace && !_twoFiles,
              busy: _busy,
              onReplace: _twoFiles ? null : (v) => _update(() => _replace = v),
            ).form,
            height: _exHeight,
            level: _exLevel,
            onQuality: _offersQuality ? _setExportQuality : null,
            twoFiles: _twoFiles,
            halves: _halves,
            onTwoFiles: _offersTwoFiles
                ? (v) {
                    _update(() => _twoFiles = v);
                    _scheduleSave();
                  }
                : null,
            result: _exportResult,
            problem: _exportProblem,
            busy: _busy,
            draft: _src.drafts,
            replace: _replace && !_twoFiles,
            onExport: _export,
          )
        else
          StudioExportJob(
            running: running,
            card: StudioJobCard(
              items: job,
              eta: {for (final r in job) r.id: _eta(r)},
              downloading: _downloads,
              onRetry: _retryJob,
              onCancel: _cancelJob,
              onDownload: (r) => _download(job: r),
              onContinue: _continueJob,
              onShare: widget.source == null ? (r) => showRecordShareSheet(ctx, r, api: widget.shareApi) : null,
              onPlay: widget.onPlay == null ? null : (r) => widget.onPlay!(ctx, r),
              onLibrary: () {
                Navigator.of(ctx).pop();
                _leave();
              },
              actionsFor: widget.jobActions == null ? null : (r) => widget.jobActions!(ctx, r),
              drafts: _src.drafts,
              libraryLabel: widget.libraryLabel,
            ),
            onKeepEditing: () => Navigator.of(ctx).pop(),
            onExportAgain: _again,
          ),
      ],
    );
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
    if (typing || _sheetOpen) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final kb = HardwareKeyboard.instance;
    final ctrl = kb.isControlPressed || kb.isMetaPressed;
    final edit = _projectReady && !_busy;
    if (ctrl && k == LogicalKeyboardKey.keyZ) {
      if (edit) kb.isShiftPressed ? _redo() : _undo();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyY) {
      if (edit) _redo();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyS) {
      _flushSave();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyE) {
      _openExport();
      return KeyEventResult.handled;
    }
    if (ctrl) return KeyEventResult.ignored;
    if (e.character == '?' || (k == LogicalKeyboardKey.slash && kb.isShiftPressed)) {
      _showKeys();
      return KeyEventResult.handled;
    }
    final step = kb.isShiftPressed ? 1.0 : StudioTransport.frame;
    if (kb.isAltPressed && (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight)) {
      final i = _selClip;
      if (edit && i != null) _moveClip(i, i + (k == LogicalKeyboardKey.arrowLeft ? -1 : 1));
      return KeyEventResult.handled;
    }
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
    } else if (k == LogicalKeyboardKey.keyI && edit) {
      _setMark(true);
    } else if (k == LogicalKeyboardKey.keyO && edit) {
      _setMark(false);
    } else if (k == LogicalKeyboardKey.keyS && edit) {
      _split();
    } else if (k == LogicalKeyboardKey.keyQ && edit) {
      _trimToPlayhead(true);
    } else if (k == LogicalKeyboardKey.keyW && edit) {
      _trimToPlayhead(false);
    } else if ((k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) && edit) {
      if (_markIn != null && _markOut != null) {
        _removeMarked();
      } else if (_selOverlay != null) {
        _deleteOverlay(_selOverlay!);
      } else if (_selClip != null) {
        _deleteClip();
      }
    } else if (k == LogicalKeyboardKey.escape) {
      setState(() {
        if (_panelOpen) {
          _panelOpen = false;
        } else {
          _selClip = null;
          _selOverlay = null;
          _markIn = _markOut = null;
        }
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
  // What can be done now (D-824): one list, a phone's bottom bar or the strip over the timeline
  // ─────────────────────────────────────────────────────────────────────────

  void _openTool(StudioTool x) => _setTool(x);

  Future<void> _quickText() async {
    await _addOverlay(StudioOverlayKind.text, StudioPlace.lowerThird);
    if (mounted) _setTool(StudioTool.text);
  }

  Future<void> _quickPicture() async {
    await _addOverlay(StudioOverlayKind.image, StudioPlace.bottomEnd);
    if (mounted && _selOverlay != null) _setTool(StudioTool.image);
  }

  (List<StudioAction>, StudioActionContext?) _actions({required bool wide}) {
    final e = _edit;
    final split = StudioAction(id: 'split', icon: Icons.content_cut_rounded, label: t('تقسيم', 'Split'), tip: t('تقسيم عند المؤشر (S)', 'Split at the playhead (S)'), onTap: _split);
    final speed = StudioAction(id: 'speed', icon: Icons.speed_rounded, label: t('السرعة', 'Speed'), onTap: () => _openTool(StudioTool.edit));
    final trimIn = StudioAction(
        id: 'trim_start', icon: Icons.start_rounded, timeIcon: true, label: t('قص البداية', 'Trim start'), tip: t('حذف ما قبل المؤشر في هذا الجزء (Q)', 'Remove what is before the playhead in this part (Q)'), onTap: () => _trimToPlayhead(true));
    final trimOut = StudioAction(
        id: 'trim_end', icon: Icons.keyboard_tab_rounded, timeIcon: true, label: t('قص النهاية', 'Trim end'), tip: t('حذف ما بعد المؤشر في هذا الجزء (W)', 'Remove what is after the playhead in this part (W)'), onTap: () => _trimToPlayhead(false));
    void clear() => setState(() {
          _selClip = null;
          _selOverlay = null;
          _markIn = _markOut = null;
        });
    // a marked period
    if (_markIn != null && _markOut != null && _markOut! > _markIn!) {
      final a = _markIn!, b = _markOut!;
      return (
        [
          StudioAction(id: 'remove_marked', icon: Icons.delete_sweep_outlined, label: t('حذف الفترة', 'Remove it'), danger: true, tip: t('حذف الفترة المحددة (Delete)', 'Remove the marked period (Delete)'), onTap: _removeMarked),
          StudioAction(id: 'keep_marked', icon: Icons.crop_rounded, label: t('الإبقاء عليها', 'Keep only it'), onTap: _keepMarked),
          speed,
          StudioAction(id: 'mark_in', icon: Icons.first_page_rounded, timeIcon: true, label: t('البداية هنا', 'In here'), tip: t('بداية الفترة عند المؤشر (I)', 'Mark in at the playhead (I)'), onTap: () => _setMark(true)),
          StudioAction(id: 'mark_out', icon: Icons.last_page_rounded, timeIcon: true, label: t('النهاية هنا', 'Out here'), tip: t('نهاية الفترة عند المؤشر (O)', 'Mark out at the playhead (O)'), onTap: () => _setMark(false)),
        ],
        StudioActionContext(label: t('الفترة ${studioTimecodeShort(a)} – ${studioTimecodeShort(b)}', 'Marked ${studioTimecodeShort(a)} – ${studioTimecodeShort(b)}'), onClear: clear),
      );
    }
    // a text or a picture
    final o = _overlay(_selOverlay);
    if (o != null) {
      return (
        [
          StudioAction(id: 'overlay_edit', icon: o.isText ? Icons.edit_rounded : Icons.tune_rounded, label: o.isText ? t('تعديل النص', 'Edit text') : t('الإعدادات', 'Settings'), onTap: () => _openTool(o.isText ? StudioTool.text : StudioTool.image)),
          StudioAction(id: 'overlay_duplicate', icon: Icons.copy_rounded, label: t('نسخة', 'Duplicate'), onTap: () => _duplicateOverlay(o.id)),
          split,
          StudioAction(id: 'overlay_delete', icon: Icons.delete_outline_rounded, label: t('حذف', 'Delete'), danger: true, tip: t('حذف (Delete)', 'Delete (Delete)'), onTap: () => _deleteOverlay(o.id)),
        ],
        StudioActionContext(label: o.isText ? t('نص «${o.name}»', 'Text “${o.name}”') : t('صورة', 'Picture'), onClear: clear),
      );
    }
    // a part
    final i = _selClip;
    if (i != null && i < e.clips.length) {
      final c = e.clips[i];
      return (
        [
          split,
          trimIn,
          trimOut,
          speed,
          if (wide) ...[
            StudioAction(id: 'move_back', icon: Icons.keyboard_double_arrow_left_rounded, timeIcon: true, label: t('للخلف', 'Earlier'), tip: t('تشغيله قبل الجزء السابق (Alt+←)', 'Play it before the part before (Alt+←)'), onTap: i > 0 ? () => _moveClip(i, i - 1) : null),
            StudioAction(id: 'move_fwd', icon: Icons.keyboard_double_arrow_right_rounded, timeIcon: true, label: t('للأمام', 'Later'), tip: t('تشغيله بعد الجزء التالي (Alt+→)', 'Play it after the next part (Alt+→)'), onTap: i < e.clips.length - 1 ? () => _moveClip(i, i + 1) : null),
          ] else if (e.clips.length > 1)
            // phones: one Move (the bar keeps six whole words, D-902); dragging the part works too
            StudioAction(id: 'move', icon: Icons.swap_horiz_rounded, label: t('نقل', 'Move'), onTap: () => _moveSheet(i)),
          StudioAction(id: 'delete_clip', icon: Icons.delete_outline_rounded, label: t('حذف', 'Delete'), danger: true, tip: t('حذف الجزء (Delete)', 'Delete the part (Delete)'), onTap: e.clips.length > 1 ? _deleteClip : null),
        ],
        StudioActionContext(
          label: t('الجزء ${i + 1} من ${e.clips.length} · ${studioTimecodeShort(c.length)}', 'Part ${i + 1} of ${e.clips.length} · ${studioTimecodeShort(c.length)}'),
          onClear: clear,
        ),
      );
    }
    // nothing selected: the tools (a wide window has them on the rail, so its strip keeps to the timeline's own)
    final markIn = StudioAction(id: 'mark_in', icon: Icons.first_page_rounded, timeIcon: true, label: t('بداية', 'Mark in'), tip: t('بداية الفترة عند المؤشر (I)', 'Mark in at the playhead (I)'), onTap: () => _setMark(true));
    final markOut = StudioAction(id: 'mark_out', icon: Icons.last_page_rounded, timeIcon: true, label: t('نهاية', 'Mark out'), tip: t('نهاية الفترة عند المؤشر (O)', 'Mark out at the playhead (O)'), onTap: () => _setMark(false));
    final marking = _markIn != null || _markOut != null ? StudioActionContext(label: t('حدّد النهاية', 'Now mark the end'), onClear: clear) : null;
    if (wide) return ([split, trimIn, trimOut, markIn, markOut], marking);
    // phones: the six that fit a 390 px bar with their words whole; the rest under More (D-902)
    return (
      [
        split,
        trimIn,
        trimOut,
        if (!_item.isAudio && _tools.contains(StudioTool.text)) StudioAction(id: 'text', icon: Icons.title_rounded, label: t('نص', 'Text'), onTap: _quickText),
        if (!_item.isAudio && _tools.contains(StudioTool.image)) StudioAction(id: 'image', icon: Icons.add_photo_alternate_outlined, label: t('صورة', 'Picture'), onTap: _quickPicture),
        if (_markIn != null) markOut,
        StudioAction(id: 'more', icon: Icons.more_horiz_rounded, label: t('المزيد', 'More'), onTap: _moreSheet),
      ],
      marking,
    );
  }

  /// Phones: move the selected part one place earlier or later (or drag it on the timeline).
  void _moveSheet(int i) {
    final n = _edit.clips.length;
    showAppSheet<void>(context, (ctx) {
      Widget row(String key, IconData icon, String label, VoidCallback? onTap) => ListTile(
            key: ValueKey('studio.move.$key'),
            enabled: onTap != null,
            leading: Directionality(textDirection: TextDirection.ltr, child: Icon(icon)),
            title: Text(label),
            onTap: onTap == null
                ? null
                : () {
                    Navigator.of(ctx).pop();
                    onTap();
                  },
          );
      return AppSheetContent(
        title: t('نقل الجزء ${i + 1}', 'Move part ${i + 1}'),
        icon: Icons.swap_horiz_rounded,
        subtitle: t('أو اسحبه على الخط الزمني', 'Or drag it on the timeline'),
        children: [
          row('first', Icons.first_page_rounded, t('إلى البداية', 'To the start'), i > 0 ? () => _moveClip(i, 0) : null),
          row('back', Icons.keyboard_double_arrow_left_rounded, t('مكاناً واحداً للخلف', 'One place earlier'), i > 0 ? () => _moveClip(i, i - 1) : null),
          row('fwd', Icons.keyboard_double_arrow_right_rounded, t('مكاناً واحداً للأمام', 'One place later'), i < n - 1 ? () => _moveClip(i, i + 1) : null),
          row('last', Icons.last_page_rounded, t('إلى النهاية', 'To the end'), i < n - 1 ? () => _moveClip(i, n - 1) : null),
        ],
      );
    });
  }

  /// Phones: what does not fit the bar (Speed, History, Merge, Cover).
  void _moreSheet() {
    showAppSheet<void>(context, (ctx) {
      Widget row(String key, IconData icon, String label, String sub, VoidCallback onTap) => ListTile(
            key: ValueKey('studio.more.$key'),
            leading: Icon(icon),
            title: Text(label),
            subtitle: Text(sub),
            onTap: () {
              Navigator.of(ctx).pop();
              onTap();
            },
          );
      return AppSheetContent(title: t('المزيد', 'More'), icon: Icons.more_horiz_rounded, children: [
        row('mark_in', Icons.first_page_rounded, t('بداية فترة هنا', 'Mark in here'), t('ثم «نهاية» لتحديد فترة تحذفها أو تبقيها', 'Then Mark out, to remove or keep that period'), () => _setMark(true)),
        row('speed', Icons.speed_rounded, t('السرعة', 'Speed'), t('للجزء المحدد أو للفيديو كله', 'For the selected part or the whole video'), () => _openTool(StudioTool.edit)),
        row('history', Icons.history_rounded, t('السجل', 'History'), t('كل خطوة، والعودة إلى أي منها', 'Every step; go back to any of them'), () => _openTool(StudioTool.history)),
        if (_tools.contains(StudioTool.merge))
          row('merge', Icons.merge_rounded, StudioTool.merge.label, t('ضم تسجيلات أخرى بعد هذا', 'Add other recordings after this one'), () => _openTool(StudioTool.merge)),
        if (_tools.contains(StudioTool.cover))
          row('cover', Icons.image_outlined, StudioTool.cover.label, t('الصورة في المكتبة وعند المشاركة', 'The picture in the library and when shared'), () => _openTool(StudioTool.cover)),
      ]);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  Widget _preview(BuildContext context) {
    final c = context.colors;
    final p = _player;
    if (_playError != null) return StudioPreviewProblem(detail: _playError!, onRetry: _reopen);
    if (!_ready || p == null) return const StudioPreviewLoading();
    if (_item.isAudio) {
      return GestureDetector(
        onTap: _playPause,
        child: Stack(fit: StackFit.expand, children: [
          Center(child: Icon(Icons.graphic_eq_rounded, color: c.onHeroFaint, size: 88)),
          StudioPlayMark(playing: _playing),
        ]),
      );
    }
    final editing = !_busy && _projectReady;
    return Stack(fit: StackFit.expand, children: [
      VideoPlayer(p),
      StudioOverlayLayer(
        edit: _edit,
        now: _pos,
        selected: _selOverlay,
        images: _images,
        editing: editing,
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
      case StudioTool.merge:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          StudioToolPanel(
            tool: StudioTool.merge,
            item: _item,
            duration: e.duration,
            merge: studioMergePicks(_item, widget.others, _mergeIds),
            enabled: !_busy,
            onToggleMerge: _toggleMerge,
          ),
          const SizedBox(height: AppSpace.md),
          if (_mergeIds.isNotEmpty) ...[
            StudioSummary(original: _srcDur, result: [mergedDuration(_mergeParts)]),
            const SizedBox(height: AppSpace.md),
          ],
          StudioSaveArea(
            title: TextField(
              key: const ValueKey('studio.merge.title'),
              controller: _mergeTitle,
              maxLength: 120,
              decoration: InputDecoration(labelText: t('اسم التسجيل المدموج', 'Name of the merged recording')),
            ),
            merge: true,
            draft: _src.drafts,
            replace: _replace,
            canSave: _mergeIds.isNotEmpty && _job?.any((r) => r.inProgress) != true,
            busy: _busy,
            showHistory: false,
            saveIcon: Icons.merge_rounded,
            saveLabel: t('دمج', 'Merge'),
            onReplace: (v) => setState(() => _replace = v),
            onSave: _merge,
          ),
        ]);
      case StudioTool.quality:
      case StudioTool.split:
      case StudioTool.cover:
        return StudioToolPanel(
          tool: StudioTool.cover,
          item: _item,
          duration: e.duration,
          enabled: !_busy,
          onPickCover: _pickCover,
          onRemoveCover: () => _coverCall(() => _src.clearCover(_item.id), t('أُزيل الغلاف', 'Cover removed')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _frames;
    final editing = !_busy && _projectReady;
    final e = _edit;
    final size = MediaQuery.sizeOf(context);
    final wide = studioIsWide(size);
    final maxZoom = StudioTimelineView.maxZoom(math.max(320, size.width - (wide ? 600 : 60)), e.duration);
    if (_zoom > maxZoom) _zoom = maxZoom;
    final (actions, actionContext) = _actions(wide: wide);
    final job = _job;
    final running = job != null && job.any((r) => r.inProgress);
    int? exporting;
    if (running) {
      final ps = [for (final r in job) if (r.inProgress) r.progress ?? -1];
      exporting = ps.isEmpty ? -1 : ps.reduce(math.min);
    }
    final layout = RecordStudioLayout(
      busy: !editing,
      tools: _tools,
      tool: _tool,
      onTool: _setTool,
      canvas: _canvas,
      aspect: _item.isAudio ? 16 / 9 : _aspect,
      actions: actions,
      actionContext: actionContext,
      panelOpen: _panelOpen,
      onClosePanel: () => setState(() => _panelOpen = false),
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
        overlays: !_item.isAudio,
        onZoom: (z) => setState(() => _zoom = z),
        onScrubStart: _scrubStart,
        onScrub: _scrub,
        onScrubEnd: _scrubEnd,
        onSelectClip: (i) => setState(() {
          _selClip = i;
          _selOverlay = null;
          if (i != null) {
            _markIn = _markOut = null;
            if (_tool != StudioTool.edit && wide) _tool = StudioTool.edit;
          }
        }),
        onSelectOverlay: _selectOverlay,
        onTrim: _onTrim,
        onTrimEnd: _onTrimEnd,
        onOverlaySpan: _overlaySpan,
        onOverlaySpanEnd: _overlaySpanEnd,
        onMoveClip: _moveClip,
        onMarks: (a, b) => setState(() {
          _markIn = a;
          _markOut = b;
          final at = a != _markIn ? a : b;
          if (at != null) _seek(at);
        }),
      ),
      panel: _panel(context, editing),
      footer: wide ? const StudioKeysHint() : null, // keys: a desktop's, not a phone browser's
      stageNote: _stageNote ?? (_projectReady ? null : t('يجهّز عملك المحفوظ…', 'Getting your saved work…')),
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_panelOpen) {
          setState(() => _panelOpen = false);
          return;
        }
        _leave();
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
          onShortcuts: wide ? _showKeys : null,
          downloading: _originalDownload,
          canUndo: editing && _hist.canUndo,
          canRedo: editing && _hist.canRedo,
          onUndo: _undo,
          onRedo: _redo,
          onExport: _ready && _projectReady ? _openExport : null,
          exporting: exporting,
          exportDone: _exportUnseen && !running && job != null && job.every((r) => r.isDone),
        ),
        child: Focus(focusNode: _focus, autofocus: true, onKeyEvent: _key, child: layout),
      ),
    );
  }
}

/// Rebuilds the open Export panel.
class _Tick extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// Is the app in Arabic (a new text starts in the Arabic font choice).
abstract final class AppConfigLang {
  static bool get isArabic => t('ar', 'en') == 'ar';
}
