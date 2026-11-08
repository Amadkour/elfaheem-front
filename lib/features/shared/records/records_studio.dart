// lib/features/shared/records/records_studio.dart — the Studio (D-312): the editor of one of my records. Plain-values
// widgets: records_studio_parts.dart; pure parts: records_api.dart, records_share_api.dart (the filmstrip).
//
//   RecordStudioPage(item:, others:)   the player (a signed, Range-proxied stream) on a large stage with its own
//                                      transport, the filmstrip timeline (POST …/frames: a sprite made once by the
//                                      server; `pending` waits on job_updated{kind: record_frames} with JobWatch), the
//                                      tools Trim · Cut a part · Split · Speed · Cover · Merge, the live summary, Undo
//                                      of the pending selection, one primary "Save as new" (or "Save and replace").
//                                      The saved job is followed inline with EventOrPoll (job_updated{kind:
//                                      recording}); the page pops with every item it made / changed.
//   Keys (web / desktop, never while typing in the name): Space play / pause · J −5 s · K pause · L +5 s ·
//   ← / → ±1 s · I start · O end · S split here · Ctrl+Z undo.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../admin/admin_common.dart' show t;
import 'records_api.dart';
import 'records_share_api.dart';
import 'records_studio_parts.dart';

/// One pending selection (what Undo brings back).
typedef _Sel = ({double start, double end, double at, double speed, List<int> merge});

class RecordStudioPage extends StatefulWidget {
  const RecordStudioPage({super.key, required this.item, this.others = const [], this.api, this.shareApi, this.onPlay});

  final RecordItem item;

  /// The rest of the library (the Merge tool's candidates).
  final List<RecordItem> others;
  final RecordsApi? api;
  final RecordShareApi? shareApi;

  /// Plays a finished item (the library's player).
  final void Function(BuildContext context, RecordItem r)? onPlay;

  @override
  State<RecordStudioPage> createState() => _RecordStudioPageState();
}

class _RecordStudioPageState extends State<RecordStudioPage> {
  late final RecordsApi _api = widget.api ?? RemoteRecordsApi();
  late final RecordShareApi _shareApi = widget.shareApi ?? RemoteRecordShareApi();
  late RecordItem _item = widget.item;
  final _made = <RecordItem>[];

  VideoPlayerController? _player;
  String? _playError;
  bool _ready = false;
  bool _wasPlaying = false;
  double _pos = 0;
  late double _dur = widget.item.durationSeconds;
  double _previewSpeed = 1;

  StudioTool _tool = StudioTool.trim;
  late double _start = 0;
  late double _end = _dur;
  late double _at = _dur / 2;
  double _speed = 1.5;
  List<int> _mergeIds = const [];
  double _zoom = 1;
  bool _replace = false;
  final _history = <_Sel>[];
  DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);

  RecordFrames? _frames;
  bool _busy = false;
  List<RecordItem>? _job;
  EventOrPoll? _jobWatch;

  bool _titleTouched = false;
  late final TextEditingController _title = TextEditingController(text: _defaultTitle());
  final _focus = FocusNode(debugLabel: 'records-studio');

  @override
  void initState() {
    super.initState();
    _open();
    _loadFrames();
  }

  @override
  void dispose() {
    _jobWatch?.dispose();
    _player?.removeListener(_tick);
    _player?.dispose();
    _title.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ── player ──

  Future<void> _open() async {
    try {
      final play = await _api.play(_item.id);
      if (!mounted) return;
      final p = VideoPlayerController.networkUrl(Uri.parse(play.url));
      _player = p;
      await p.initialize();
      if (!mounted) return;
      p.addListener(_tick);
      final d = p.value.duration.inMilliseconds / 1000;
      setState(() {
        _ready = true;
        if (d > 0 && (_dur <= 0 || (d - _dur).abs() > 1)) {
          _dur = d;
          _end = d;
          _at = d / 2;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _playError = recordsErrorText(e));
    }
  }

  void _tick() {
    final p = _player;
    if (p == null || !mounted) return;
    final s = p.value.position.inMilliseconds / 1000;
    if ((s - _pos).abs() >= 0.1 || p.value.isPlaying != _wasPlaying) {
      _wasPlaying = p.value.isPlaying;
      setState(() => _pos = s.clamp(0, _dur > 0 ? _dur : s).toDouble());
    }
  }

  void _seek(double s) {
    final to = s.clamp(0, _dur > 0 ? _dur : s).toDouble();
    setState(() => _pos = to);
    _player?.seekTo(Duration(milliseconds: (to * 1000).round()));
  }

  void _playPause() {
    final p = _player;
    if (p == null || !_ready) return;
    p.value.isPlaying ? p.pause() : p.play();
  }

  void _applySpeed() => _player?.setPlaybackSpeed(_tool == StudioTool.speed ? _speed : _previewSpeed);

  void _nextPreviewSpeed() {
    final i = studioPreviewSpeeds.indexOf(_previewSpeed);
    setState(() => _previewSpeed = studioPreviewSpeeds[(i + 1) % studioPreviewSpeeds.length]);
    _applySpeed();
  }

  // ── filmstrip ──

  Future<void> _loadFrames() async {
    if (_item.isAudio) return;
    JobWatch? watch;
    try {
      for (var i = 0; i < 8 && mounted; i++) {
        final f = await _shareApi.frames(_item.id);
        if (!mounted) return;
        setState(() => _frames = f);
        if (!f.pending) return;
        watch ??= JobWatch(kind: 'record_frames', id: '${_item.id}');
        await watch.next(const Duration(seconds: 5), fallbackEvery: const Duration(seconds: 20));
      }
    } catch (_) {
      if (mounted) setState(() => _frames = const RecordFrames(status: 'unavailable')); // the tinted track
    } finally {
      watch?.dispose();
    }
  }

  // ── selection + undo ──

  _Sel get _sel => (start: _start, end: _end, at: _at, speed: _speed, merge: _mergeIds);

  /// Remembers the selection before a change (a drag counts once: pushes are 700 ms apart at least).
  void _remember() {
    final now = DateTime.now();
    if (now.difference(_lastPush) < const Duration(milliseconds: 700) && _history.isNotEmpty) return;
    _lastPush = now;
    final s = _sel;
    if (_history.isEmpty || _history.last != s) _history.add(s);
    if (_history.length > 50) _history.removeAt(0);
  }

  void _restore(_Sel s) => setState(() {
        _start = s.start;
        _end = s.end;
        _at = s.at;
        _speed = s.speed;
        _mergeIds = s.merge;
        _syncTitle();
      });

  void _undo() {
    if (_history.isEmpty) return;
    _restore(_history.removeLast());
    _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
    _applySpeed();
  }

  void _reset() {
    _remember();
    _restore((start: 0, end: _dur, at: _dur / 2, speed: 1.5, merge: const []));
    _applySpeed();
  }

  bool get _changed {
    if (_history.isNotEmpty) return true;
    return _start != 0 || (_end - _dur).abs() > 0.01 || _mergeIds.isNotEmpty;
  }

  void _setRange(double a, double b) {
    _remember();
    setState(() {
      _start = a;
      _end = b;
    });
  }

  void _setAt(double s) {
    _remember();
    setState(() => _at = s.clamp(recordMinPart, _dur - recordMinPart > recordMinPart ? _dur - recordMinPart : recordMinPart).toDouble());
  }

  void _setSpeed(double s) {
    _remember();
    setState(() {
      _speed = s;
      _syncTitle();
    });
    _applySpeed();
  }

  void _toggleMerge(RecordItem r) {
    _remember();
    setState(() {
      _mergeIds = _mergeIds.contains(r.id) ? [for (final i in _mergeIds) if (i != r.id) i] : [..._mergeIds, r.id];
    });
  }

  void _setTool(StudioTool x) {
    setState(() {
      _tool = x;
      _syncTitle();
    });
    _applySpeed();
  }

  String _defaultTitle() => defaultEditTitle(_item.title, _tool.op ?? RecordOp.trim, speed: _speed);

  void _syncTitle() {
    if (!_titleTouched) _title.text = _defaultTitle();
  }

  // ── what comes out ──

  RecordEdit? get _edit => studioEdit(_tool, start: _start, end: _end, at: _at, speed: _speed);

  List<RecordItem> get _mergeParts => [
        _item,
        for (final id in _mergeIds) ?widget.others.where((r) => r.id == id).firstOrNull,
      ];

  String? get _problem {
    if (_tool == StudioTool.merge) {
      return _mergeIds.isEmpty ? t('اختر تسجيلاً واحداً على الأقل لإضافته', 'Pick at least one recording to add') : null;
    }
    final e = _edit;
    return e == null ? null : editProblem(e, _dur);
  }

  List<double> get _result {
    if (_tool == StudioTool.cover) return const [];
    if (_tool == StudioTool.merge) return _mergeIds.isEmpty ? const [] : [mergedDuration(_mergeParts)];
    final e = _edit;
    return e == null ? const [] : editResultDurations(e, _dur);
  }

  // ── save ──

  Future<void> _save() async {
    if (_problem != null || _busy) return;
    if (_replace &&
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
    setState(() => _busy = true);
    _player?.pause();
    try {
      final List<RecordItem> made;
      if (_tool == StudioTool.merge) {
        made = await _api.merge([_item.id, ..._mergeIds], title: _title.text, deleteSources: _replace);
      } else {
        final e = _edit!;
        made = await _api.edit(_item.id,
            RecordEdit(op: e.op, start: e.start, end: e.end, at: e.at, speed: e.speed, title: _title.text, deleteSource: _replace));
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
  }

  void _watchJob() {
    final running = (_job ?? const []).any((r) => r.inProgress);
    if (!running) {
      _jobWatch?.stop();
      return;
    }
    _jobWatch ??= EventOrPoll(
      kind: 'recording',
      every: const Duration(seconds: 6),
      fallbackEvery: const Duration(seconds: 30),
      poll: _refreshJob,
    );
    if (!_jobWatch!.running) _jobWatch!.start();
  }

  Future<void> _refreshJob() async {
    final job = _job;
    if (job == null) return;
    try {
      final fresh = [for (final r in job) (await _api.get(r.id)) ?? r];
      if (!mounted) return;
      setState(() => _job = fresh);
      _keep(fresh);
    } catch (_) {/* the next event / poll tries again */}
    _watchJob();
  }

  Future<void> _retryJob(RecordItem r) async {
    try {
      final n = await _api.retry(r.id);
      if (n == null || !mounted) return;
      setState(() => _job = [for (final x in _job ?? const <RecordItem>[]) x.id == n.id ? n : x]);
      _keep([n]);
      _watchJob();
    } catch (e) {
      if (mounted) showAppNotice(recordsErrorText(e), error: true);
    }
  }

  void _again() {
    _jobWatch?.stop();
    setState(() {
      _job = null;
      _history.clear();
      _replace = false;
      _titleTouched = false;
    });
    _reset();
    _history.clear();
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
    await _coverCall(() => _api.setCover(_item.id, cropped, fileName: 'cover.png'), t('تم حفظ الغلاف', 'Cover saved'));
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

  // ── keyboard ──

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final typing = FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (typing || _busy || _job != null) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    if (ctrl && k == LogicalKeyboardKey.keyZ) {
      _undo();
      return KeyEventResult.handled;
    }
    if (ctrl) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.space) {
      _playPause();
    } else if (k == LogicalKeyboardKey.keyK) {
      _player?.pause();
    } else if (k == LogicalKeyboardKey.keyJ) {
      _seek(_pos - 5);
    } else if (k == LogicalKeyboardKey.keyL) {
      _seek(_pos + 5);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _seek(_pos - 1);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _seek(_pos + 1);
    } else if (k == LogicalKeyboardKey.keyI && _tool.ranged) {
      _setRange(_pos.clamp(0, (_end - recordMinPart).clamp(0, _dur)).toDouble(), _end);
    } else if (k == LogicalKeyboardKey.keyO && _tool.ranged) {
      _setRange(_start, _pos.clamp((_start + recordMinPart).clamp(0, _dur), _dur).toDouble());
    } else if (k == LogicalKeyboardKey.keyS && _tool == StudioTool.split) {
      _setAt(_pos);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ── build ──

  Widget _preview(ThemeConfigProvider c) {
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
    if (_item.isAudio) return Center(child: Icon(Icons.graphic_eq_rounded, color: c.onHeroMuted, size: 72));
    return GestureDetector(
      onTap: _playPause,
      child: Center(child: AspectRatio(aspectRatio: p.value.aspectRatio, child: VideoPlayer(p))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = _frames;
    final editing = !_busy && _job == null;
    final picks = studioMergePicks(_item, widget.others, _mergeIds);
    final layout = RecordStudioLayout(
      busy: !editing,
      tool: _tool,
      onTool: _setTool,
      preview: _preview(c),
      transport: StudioTransport(
        position: _pos,
        duration: _dur,
        playing: _player?.value.isPlaying ?? false,
        previewSpeed: _tool == StudioTool.speed ? _speed : _previewSpeed,
        enabled: _ready,
        onPlayPause: _playPause,
        onSkip: (by) => _seek(_pos + by),
        onPreviewSpeed: _tool == StudioTool.speed ? null : _nextPreviewSpeed,
      ),
      timeline: StudioTimeline(
        duration: _dur,
        position: _pos,
        tool: _tool,
        start: _start,
        end: _end,
        at: _at,
        zoom: _zoom,
        frames: f != null && f.ready ? NetworkImage(f.url!) : null,
        framesPending: f == null ? !_item.isAudio : f.pending,
        enabled: editing,
        onSeek: _seek,
        onRange: _setRange,
        onAt: _setAt,
        onZoom: (z) => setState(() => _zoom = z),
      ),
      panel: StudioToolPanel(
        tool: _tool,
        item: _item,
        duration: _dur,
        position: _pos,
        start: _start,
        end: _end,
        at: _at,
        speed: _speed,
        merge: picks,
        enabled: editing,
        showDescription: MediaQuery.sizeOf(context).width < studioWideMin,
        onRange: _setRange,
        onAt: _setAt,
        onSpeed: _setSpeed,
        onPickCover: _pickCover,
        onRemoveCover: () => _coverCall(() => _api.clearCover(_item.id), t('أُزيل الغلاف', 'Cover removed')),
        onToggleMerge: _toggleMerge,
      ),
      summary: StudioSummary(original: _dur, result: _result, problem: _tool == StudioTool.cover ? null : _problem),
      save: _tool == StudioTool.cover
          ? null
          : StudioSaveArea(
              merge: _tool == StudioTool.merge,
              replace: _replace,
              canSave: _problem == null && _ready,
              canUndo: _changed,
              busy: _busy,
              onReplace: (v) => setState(() => _replace = v),
              onUndo: _undo,
              onReset: _reset,
              onSave: _save,
              title: TextField(
                key: const ValueKey('studio.title'),
                controller: _title,
                maxLength: 120,
                onChanged: (_) => _titleTouched = true,
                decoration: InputDecoration(
                  labelText: _tool == StudioTool.split
                      ? t('اسم التسجيلين (يُضاف 1 و2)', 'Name of the two (1 and 2 are added)')
                      : t('اسم التسجيل الجديد', 'Name of the new recording'),
                ),
              ),
            ),
      job: _job == null
          ? null
          : StudioJobCard(
              items: _job!,
              onRetry: _retryJob,
              onPlay: widget.onPlay == null ? null : (r) => widget.onPlay!(context, r),
              onAgain: _again,
              onLibrary: () => Navigator.of(context).pop(List<RecordItem>.of(_made)),
            ),
      footer: kIsWeb || MediaQuery.sizeOf(context).width >= studioWideMin ? const StudioKeysHint() : null,
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(List<RecordItem>.of(_made));
      },
      child: BasePage(
        key: const ValueKey('records.studio'),
        appBar: ScreenAppBar(title: t('الاستوديو · ${_item.title}', 'Studio · ${_item.title}')),
        child: Focus(focusNode: _focus, autofocus: true, onKeyEvent: _key, child: layout),
      ),
    );
  }
}
