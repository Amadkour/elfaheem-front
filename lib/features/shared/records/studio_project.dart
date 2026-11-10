// lib/features/shared/records/studio_project.dart — the Studio's edit list and its history (D-590 … D-593). Pure: no
// widgets, no API, so test/org/studio_project_test.dart checks every rule.
//
//   StudioClip        a kept piece of the SOURCE [start, end] played at [speed]; the clips in order ARE the output
//                     (a split cuts one clip in two, a remove deletes what lies between two splits, a trim moves an
//                     edge). The timeline shows OUTPUT time: removed parts close up like in every editor.
//   StudioOverlay     a text or a picture on the frame. Its times are SOURCE times (it sticks to what it was put on:
//                     removing a part before it moves it along, D-592); position / size are fractions of the frame,
//                     so the preview and the 1080p file agree. In / out animations: [StudioAnim].
//   StudioEdit        clips + overlays + the output quality: one value, immutable; every operation returns a new one.
//   StudioHistory     every step as a snapshot of the edit with what it was in plain words ([studioStepLabel]): undo
//                     and redo move the head; Restore jumps to any step. A new step after an undo drops the undone
//                     ones (the page asks first, D-593). Saved as the project doc (autosave) and with each render.
//   studioRenderParams   what POST …/render receives: the clips, the overlays in OUTPUT seconds, the quality.
//   studioOverlayLook    how an overlay looks at a moment (opacity, offset, scale, typewriter reveal): the preview
//                        draws it, and services/studio_render.py builds the very same curves into ffmpeg.
library;

import 'dart:math' as math;

import '../../admin/admin_common.dart' show t, asMap, asMapList, asInt;
import 'records_api.dart';

/// No clip shorter than this survives an edit (a split this close to an edge is ignored).
const studioMinClip = 0.2;

/// What a clip may play at (the server's studio_render.SPEEDS).
const studioClipSpeeds = <double>[0.5, 0.75, 1, 1.25, 1.5, 2];

/// Up to this many overlays (the server's MAX_OVERLAYS).
const studioMaxOverlays = 40;

/// The history keeps this many steps (the oldest after the original go first).
const studioMaxSteps = 120;

double _d(dynamic v, [double or = 0]) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? or;
}

double _r3(double v) => (v * 1000).roundToDouble() / 1000;

int _seq = 0;

/// A short id, unique in this run (clips, overlays, steps).
String studioId(String prefix) => '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_seq++).toRadixString(36)}';

// ─────────────────────────────────────────────────────────────────────────────
// Clips
// ─────────────────────────────────────────────────────────────────────────────

class StudioClip {
  const StudioClip({required this.id, required this.start, required this.end, this.speed = 1});

  final String id;
  final double start;
  final double end;
  final double speed;

  /// How long it plays in the output.
  double get length => math.max(0.0, end - start) / speed;
  double get sourceLength => math.max(0.0, end - start);

  StudioClip copyWith({String? id, double? start, double? end, double? speed}) =>
      StudioClip(id: id ?? this.id, start: start ?? this.start, end: end ?? this.end, speed: speed ?? this.speed);

  Map<String, dynamic> toJson() => {'id': id, 'start': _r3(start), 'end': _r3(end), 'speed': speed};

  static StudioClip? fromJson(Map<String, dynamic> j) {
    final a = _d(j['start']), b = _d(j['end'], -1);
    if (b <= a) return null;
    final s = _d(j['speed'], 1);
    return StudioClip(id: '${j['id'] ?? studioId('c')}', start: a, end: b, speed: studioClipSpeeds.contains(s) ? s : 1);
  }

  @override
  bool operator ==(Object other) => other is StudioClip && other.id == id && other.start == start && other.end == end && other.speed == speed;

  @override
  int get hashCode => Object.hash(id, start, end, speed);
}

// ─────────────────────────────────────────────────────────────────────────────
// Overlays
// ─────────────────────────────────────────────────────────────────────────────

enum StudioAnim {
  none('none'),
  fade('fade'),
  slideUp('slide_up'),
  slideDown('slide_down'),
  slideLeft('slide_left'),
  slideRight('slide_right'),
  pop('pop'),
  typewriter('typewriter');

  const StudioAnim(this.wire);
  final String wire;

  static StudioAnim fromWire(dynamic v) => values.firstWhere((a) => a.wire == '$v', orElse: () => StudioAnim.none);

  String get label => switch (this) {
        StudioAnim.none => t('بلا حركة', 'None'),
        StudioAnim.fade => t('تلاشٍ', 'Fade'),
        StudioAnim.slideUp => t('انزلاق لأعلى', 'Slide up'),
        StudioAnim.slideDown => t('انزلاق لأسفل', 'Slide down'),
        StudioAnim.slideLeft => t('انزلاق لليسار', 'Slide left'),
        StudioAnim.slideRight => t('انزلاق لليمين', 'Slide right'),
        StudioAnim.pop => t('ظهور بارز', 'Pop'),
        StudioAnim.typewriter => t('آلة كاتبة', 'Typewriter'),
      };

  /// Typewriter types a text; a picture has nothing to type.
  bool fits(StudioOverlayKind kind) => this != StudioAnim.typewriter || kind == StudioOverlayKind.text;
}

enum StudioOverlayKind { text, image }

/// Where an overlay stands on the frame when it is added (the preset buttons).
enum StudioPlace {
  top(0.5, 0.14),
  center(0.5, 0.5),
  lowerThird(0.5, 0.8),
  topStart(0.2, 0.12),
  bottomEnd(0.85, 0.88);

  const StudioPlace(this.x, this.y);
  final double x, y;
}

class StudioOverlay {
  const StudioOverlay({
    required this.id,
    required this.kind,
    required this.start,
    required this.end,
    this.x = 0.5,
    this.y = 0.8,
    this.w = 0.3,
    this.opacity = 1,
    this.inAnim = StudioAnim.fade,
    this.outAnim = StudioAnim.fade,
    this.inDur = 0.5,
    this.outDur = 0.5,
    this.text = '',
    this.fontId = 'plex_arabic',
    this.size = 0.065,
    this.color = 0xFFFFFFFF,
    this.background,
    this.bold = true,
    this.asset,
    this.aspect = 1,
  });

  final String id;
  final StudioOverlayKind kind;

  /// SOURCE seconds (D-592).
  final double start;
  final double end;

  /// The centre, as fractions of the frame.
  final double x;
  final double y;

  /// A picture's width as a fraction of the frame's width (a text's width follows its words and [size]).
  final double w;
  final double opacity;
  final StudioAnim inAnim;
  final StudioAnim outAnim;
  final double inDur;
  final double outDur;

  // text
  final String text;
  final String fontId;

  /// The letters' height as a fraction of the frame's height.
  final double size;
  final int color;

  /// The pill behind the words (null: none — a soft shadow keeps them readable).
  final int? background;
  final bool bold;

  // picture: the uploaded asset (POST /studio/assets) and its height / width
  final String? asset;
  final double aspect;

  bool get isText => kind == StudioOverlayKind.text;

  /// What the history and the lane call it.
  String get name {
    if (!isText) return t('صورة', 'Picture');
    final one = text.replaceAll('\n', ' ').trim();
    return one.length > 24 ? '${one.substring(0, 23)}…' : one;
  }

  /// Arabic letters in the text: it reads (and types) right to left.
  bool get rtl => RegExp(r'[֐-ࣿיִ-﷿ﹰ-﻿]').hasMatch(text);

  StudioOverlay copyWith({
    double? start,
    double? end,
    double? x,
    double? y,
    double? w,
    double? opacity,
    StudioAnim? inAnim,
    StudioAnim? outAnim,
    double? inDur,
    double? outDur,
    String? text,
    String? fontId,
    double? size,
    int? color,
    int? Function()? background,
    bool? bold,
    String? asset,
    double? aspect,
  }) =>
      StudioOverlay(
        id: id,
        kind: kind,
        start: start ?? this.start,
        end: end ?? this.end,
        x: x ?? this.x,
        y: y ?? this.y,
        w: w ?? this.w,
        opacity: opacity ?? this.opacity,
        inAnim: inAnim ?? this.inAnim,
        outAnim: outAnim ?? this.outAnim,
        inDur: inDur ?? this.inDur,
        outDur: outDur ?? this.outDur,
        text: text ?? this.text,
        fontId: fontId ?? this.fontId,
        size: size ?? this.size,
        color: color ?? this.color,
        background: background != null ? background() : this.background,
        bold: bold ?? this.bold,
        asset: asset ?? this.asset,
        aspect: aspect ?? this.aspect,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'start': _r3(start),
        'end': _r3(end),
        'x': _r3(x),
        'y': _r3(y),
        'w': _r3(w),
        'opacity': _r3(opacity),
        'in': {'type': inAnim.wire, 'd': _r3(inDur)},
        'out': {'type': outAnim.wire, 'd': _r3(outDur)},
        if (isText) ...{'text': text, 'font': fontId, 'size': _r3(size), 'color': color, 'bg': background, 'bold': bold},
        if (!isText) ...{'asset': asset, 'aspect': _r3(aspect)},
      };

  static StudioOverlay? fromJson(Map<String, dynamic> j) {
    final kind = j['kind'] == 'image' ? StudioOverlayKind.image : StudioOverlayKind.text;
    final a = _d(j['start']), b = _d(j['end'], -1);
    if (b <= a) return null;
    if (kind == StudioOverlayKind.text && '${j['text'] ?? ''}'.trim().isEmpty) return null;
    if (kind == StudioOverlayKind.image && '${j['asset'] ?? ''}'.isEmpty) return null;
    final inA = asMap(j['in']), outA = asMap(j['out']);
    final bg = j['bg'];
    return StudioOverlay(
      id: '${j['id'] ?? studioId('o')}',
      kind: kind,
      start: a,
      end: b,
      x: _d(j['x'], 0.5),
      y: _d(j['y'], 0.8),
      w: _d(j['w'], 0.3),
      opacity: _d(j['opacity'], 1).clamp(0.0, 1.0),
      inAnim: StudioAnim.fromWire(inA['type']),
      outAnim: StudioAnim.fromWire(outA['type']),
      inDur: _d(inA['d'], 0.5),
      outDur: _d(outA['d'], 0.5),
      text: '${j['text'] ?? ''}',
      fontId: '${j['font'] ?? 'plex_arabic'}',
      size: _d(j['size'], 0.065),
      color: asInt(j['color'], 0xFFFFFFFF),
      background: bg == null ? null : asInt(bg),
      bold: j['bold'] != false,
      asset: j['asset'] == null ? null : '${j['asset']}',
      aspect: _d(j['aspect'], 1),
    );
  }

  @override
  bool operator ==(Object other) => other is StudioOverlay && _eq(toJson(), other.toJson());

  @override
  int get hashCode => Object.hash(id, start, end, x, y, text);
}

bool _eq(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a.length != b.length) return false;
  for (final k in a.keys) {
    final x = a[k], y = b[k];
    if (x is Map<String, dynamic> && y is Map<String, dynamic>) {
      if (!_eq(x, y)) return false;
    } else if (x != y) {
      return false;
    }
  }
  return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// The edit
// ─────────────────────────────────────────────────────────────────────────────

/// Where an output time falls: the clip and the source second.
typedef StudioHit = ({int clip, double source});

class StudioEdit {
  const StudioEdit({required this.clips, this.overlays = const [], this.height, this.level});

  /// The whole source as one clip (what the Studio opens with).
  factory StudioEdit.original(double duration) =>
      StudioEdit(clips: [if (duration > 0) StudioClip(id: 'c0', start: 0, end: duration)]);

  final List<StudioClip> clips;
  final List<StudioOverlay> overlays;

  /// The output's short side (null: as it is) and the quality level (null: the source's quality).
  final int? height;
  final StudioQualityLevel? level;

  double get duration => clips.fold(0.0, (s, c) => s + c.length);

  /// Where clip [i] starts in the output.
  double clipStart(int i) {
    var s = 0.0;
    for (var k = 0; k < i && k < clips.length; k++) {
      s += clips[k].length;
    }
    return s;
  }

  /// Output seconds → the clip under it and its source second. The very end belongs to the last clip.
  StudioHit? hit(double out) {
    if (clips.isEmpty) return null;
    var s = 0.0;
    for (var i = 0; i < clips.length; i++) {
      final c = clips[i];
      final e = s + c.length;
      if (out < e || i == clips.length - 1) {
        final into = (out - s).clamp(0.0, c.length);
        return (clip: i, source: c.start + into * c.speed);
      }
      s = e;
    }
    return null;
  }

  /// Source seconds → output seconds (null: that moment was removed).
  double? outputOf(double source) {
    var s = 0.0;
    for (final c in clips) {
      if (source >= c.start - 1e-6 && source <= c.end + 1e-6) return s + (source.clamp(c.start, c.end) - c.start) / c.speed;
      s += c.length;
    }
    return null;
  }

  /// The output seconds an overlay is on screen (null: everything it covered was removed).
  (double, double)? overlayOut(StudioOverlay o) {
    double? a, b;
    var s = 0.0;
    for (final c in clips) {
      final lo = math.max(o.start, c.start), hi = math.min(o.end, c.end);
      if (hi - lo > 1e-6) {
        final oa = s + (lo - c.start) / c.speed, ob = s + (hi - c.start) / c.speed;
        a = a == null ? oa : math.min(a, oa);
        b = b == null ? ob : math.max(b, ob);
      }
      s += c.length;
    }
    if (a == null || b == null || b - a < 0.05) return null;
    return (a, b);
  }

  /// Output seconds → the source second an overlay edge anchors to (the end of a clip for [end]).
  double anchor(double out, {bool end = false}) {
    if (clips.isEmpty) return 0;
    var s = 0.0;
    for (var i = 0; i < clips.length; i++) {
      final c = clips[i];
      final e = s + c.length;
      final inside = end ? out <= e + 1e-6 : out < e - 1e-6;
      if (inside || i == clips.length - 1) return c.start + (out - s).clamp(0.0, c.length) * c.speed;
      s = e;
    }
    return clips.last.end;
  }

  /// The output times where clips meet (the snapping points of the timeline).
  List<double> get cuts => [for (var i = 1; i < clips.length; i++) clipStart(i)];

  StudioEdit copyWith({List<StudioClip>? clips, List<StudioOverlay>? overlays, int? Function()? height, StudioQualityLevel? Function()? level}) =>
      StudioEdit(
        clips: clips ?? this.clips,
        overlays: overlays ?? this.overlays,
        height: height != null ? height() : this.height,
        level: level != null ? level() : this.level,
      );

  // ── operations (each returns a new edit, or this one when nothing changes) ──

  /// Cuts the clip under [out] in two. Too close to an edge (or to another cut): nothing.
  StudioEdit split(double out) {
    final h = hit(out);
    if (h == null) return this;
    final c = clips[h.clip];
    if (h.source - c.start < studioMinClip || c.end - h.source < studioMinClip) return this;
    final next = [...clips];
    next.replaceRange(h.clip, h.clip + 1, [
      c.copyWith(end: h.source),
      StudioClip(id: studioId('c'), start: h.source, end: c.end, speed: c.speed),
    ]);
    return copyWith(clips: next);
  }

  /// Removes the output range [a, b] (the parts on both sides close up). Never removes everything.
  StudioEdit remove(double a, double b) {
    final lo = math.min(a, b).clamp(0.0, duration), hi = math.max(a, b).clamp(0.0, duration);
    if (hi - lo < 0.05) return this;
    final e = split(lo).split(hi);
    final keep = <StudioClip>[];
    var s = 0.0;
    for (final c in e.clips) {
      final mid = s + c.length / 2;
      if (mid < lo || mid > hi) keep.add(c);
      s += c.length;
    }
    if (keep.isEmpty || keep.fold(0.0, (v, c) => v + c.length) < 0.5) return this;
    return copyWith(clips: keep);
  }

  /// Keeps only the output range [a, b].
  StudioEdit keepOnly(double a, double b) {
    final lo = math.min(a, b).clamp(0.0, duration), hi = math.max(a, b).clamp(0.0, duration);
    if (hi - lo < 0.5) return this;
    final e = split(lo).split(hi);
    final keep = <StudioClip>[];
    var s = 0.0;
    for (final c in e.clips) {
      final mid = s + c.length / 2;
      if (mid > lo && mid < hi) keep.add(c);
      s += c.length;
    }
    if (keep.isEmpty) return this;
    return copyWith(clips: keep);
  }

  /// Deletes clip [i] (the last clip stays).
  StudioEdit deleteClip(int i) {
    if (clips.length <= 1 || i < 0 || i >= clips.length) return this;
    return copyWith(clips: [...clips]..removeAt(i));
  }

  /// How far clip [i]'s start may go (source seconds): not over the previous clip, not past its own end.
  (double, double) startBounds(int i) {
    final c = clips[i];
    final lo = i > 0 ? clips[i - 1].end : 0.0;
    return (math.min(lo, c.start), math.max(c.start, c.end - studioMinClip));
  }

  /// How far clip [i]'s end may go: not into the next clip, not past the source's [sourceDuration].
  (double, double) endBounds(int i, double sourceDuration) {
    final c = clips[i];
    final hi = i < clips.length - 1 ? clips[i + 1].start : sourceDuration;
    return (math.min(c.end, c.start + studioMinClip), math.max(hi, c.end));
  }

  /// Moves clip [i]'s start to the source second [to] (inside [startBounds]).
  StudioEdit trimStart(int i, double to) {
    if (i < 0 || i >= clips.length) return this;
    final (lo, hi) = startBounds(i);
    final v = to.clamp(lo, hi);
    if ((v - clips[i].start).abs() < 1e-4) return this;
    return copyWith(clips: [...clips]..[i] = clips[i].copyWith(start: v));
  }

  StudioEdit trimEnd(int i, double to, double sourceDuration) {
    if (i < 0 || i >= clips.length) return this;
    final (lo, hi) = endBounds(i, sourceDuration);
    final v = to.clamp(lo, hi);
    if ((v - clips[i].end).abs() < 1e-4) return this;
    return copyWith(clips: [...clips]..[i] = clips[i].copyWith(end: v));
  }

  /// [speed] on the output range [a, b] (split at both ends first) — or on clip [clip] alone.
  StudioEdit speedOn(double speed, {double? a, double? b, int? clip}) {
    if (!studioClipSpeeds.contains(speed)) return this;
    if (clip != null) {
      if (clip < 0 || clip >= clips.length || clips[clip].speed == speed) return this;
      return copyWith(clips: [...clips]..[clip] = clips[clip].copyWith(speed: speed));
    }
    final lo = math.min(a ?? 0, b ?? duration), hi = math.max(a ?? 0, b ?? duration);
    final e = split(lo).split(hi);
    var s = 0.0;
    final next = <StudioClip>[];
    for (final c in e.clips) {
      final mid = s + c.length / 2;
      next.add(mid > lo && mid < hi ? c.copyWith(speed: speed) : c);
      s += c.length;
    }
    return copyWith(clips: next);
  }

  StudioEdit putOverlay(StudioOverlay o) {
    final i = overlays.indexWhere((x) => x.id == o.id);
    if (i < 0) {
      if (overlays.length >= studioMaxOverlays) return this;
      return copyWith(overlays: [...overlays, o]);
    }
    return copyWith(overlays: [...overlays]..[i] = o);
  }

  StudioEdit removeOverlay(String id) => copyWith(overlays: [for (final o in overlays) if (o.id != id) o]);

  /// Nothing changed from the original source of [duration] seconds.
  bool isOriginal(double sourceDuration) =>
      overlays.isEmpty &&
      height == null &&
      level == null &&
      clips.length == 1 &&
      clips.first.speed == 1 &&
      clips.first.start < 0.01 &&
      (clips.first.end - sourceDuration).abs() < 0.05;

  Map<String, dynamic> toJson() => {
        'clips': [for (final c in clips) c.toJson()],
        'overlays': [for (final o in overlays) o.toJson()],
        if (height != null) 'height': height,
        if (level != null) 'level': level!.wire,
      };

  static StudioEdit? fromJson(Map<String, dynamic> j) {
    final clips = [for (final c in asMapList(j['clips'])) ?StudioClip.fromJson(c)];
    if (clips.isEmpty) return null;
    final lv = '${j['level'] ?? ''}';
    return StudioEdit(
      clips: clips,
      overlays: [for (final o in asMapList(j['overlays'])) ?StudioOverlay.fromJson(o)],
      height: j['height'] == null ? null : asInt(j['height']),
      level: StudioQualityLevel.values.where((l) => l.wire == lv).firstOrNull,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// History
// ─────────────────────────────────────────────────────────────────────────────

/// What a step did (the history's words come from it and its [StudioStep.info]).
enum StudioStepKind {
  open,
  split,
  remove,
  keep,
  deleteClip,
  trimStart,
  trimEnd,
  speed,
  textAdd,
  imageAdd,
  overlayMove,
  overlayTime,
  overlayStyle,
  overlayAnim,
  overlayRemove,
  quality,
  reset;

  static StudioStepKind fromWire(dynamic v) => values.firstWhere((k) => k.name == '$v', orElse: () => StudioStepKind.open);

  /// The history row's icon name (the panel maps it to an IconData).
  bool get isOverlay => index >= StudioStepKind.textAdd.index && index <= StudioStepKind.overlayRemove.index;
}

class StudioStep {
  const StudioStep({required this.id, required this.kind, required this.edit, required this.at, this.info = const {}});

  final String id;
  final StudioStepKind kind;
  final StudioEdit edit;
  final DateTime at;

  /// The numbers and names the words need (output seconds at the time of the step, a speed, a text).
  final Map<String, dynamic> info;

  Map<String, dynamic> toJson() => {'id': id, 'kind': kind.name, 'at': at.toUtc().toIso8601String(), 'info': info, 'edit': edit.toJson()};

  static StudioStep? fromJson(Map<String, dynamic> j) {
    final e = StudioEdit.fromJson(asMap(j['edit']));
    if (e == null) return null;
    return StudioStep(
      id: '${j['id'] ?? studioId('s')}',
      kind: StudioStepKind.fromWire(j['kind']),
      edit: e,
      at: DateTime.tryParse('${j['at'] ?? ''}')?.toLocal() ?? DateTime.now(),
      info: asMap(j['info']),
    );
  }
}

/// The steps (the first is the original) and the one the Studio shows.
class StudioHistory {
  const StudioHistory({required this.steps, required this.head});

  factory StudioHistory.start(double duration, {DateTime? now}) => StudioHistory(
        steps: [StudioStep(id: 's0', kind: StudioStepKind.open, edit: StudioEdit.original(duration), at: now ?? DateTime.now())],
        head: 0,
      );

  final List<StudioStep> steps;
  final int head;

  StudioEdit get current => steps[head].edit;
  bool get canUndo => head > 0;
  bool get canRedo => head < steps.length - 1;

  /// How many undone steps a new step would drop.
  int get undone => steps.length - 1 - head;

  StudioHistory undo() => canUndo ? StudioHistory(steps: steps, head: head - 1) : this;
  StudioHistory redo() => canRedo ? StudioHistory(steps: steps, head: head + 1) : this;
  StudioHistory restore(int i) => i < 0 || i >= steps.length || i == head ? this : StudioHistory(steps: steps, head: i);

  /// [edit] as a new step after the head (the undone steps go). Nothing changed: this history.
  StudioHistory commit(StudioStepKind kind, StudioEdit edit, {Map<String, dynamic> info = const {}, DateTime? now}) {
    if (identical(edit, current) || _same(edit, current)) return this;
    final kept = [...steps.take(head + 1), StudioStep(id: studioId('s'), kind: kind, edit: edit, at: now ?? DateTime.now(), info: info)];
    while (kept.length > studioMaxSteps) {
      kept.removeAt(1); // the original stays first
    }
    return StudioHistory(steps: kept, head: kept.length - 1);
  }

  static bool _same(StudioEdit a, StudioEdit b) => _eq(a.toJson(), b.toJson());

  Map<String, dynamic> toJson(double duration) => {
        'v': 1,
        'duration': _r3(duration),
        'head': head,
        'steps': [for (final s in steps) s.toJson()],
      };

  /// A saved doc (null: none, broken, or made for a source of another length).
  static StudioHistory? fromJson(Map<String, dynamic> j, {required double duration}) {
    if (asInt(j['v']) != 1) return null;
    final d = _d(j['duration']);
    if (duration > 0 && d > 0 && (d - duration).abs() > 1.0) return null;
    final steps = [for (final s in asMapList(j['steps'])) ?StudioStep.fromJson(s)];
    if (steps.isEmpty) return null;
    return StudioHistory(steps: steps, head: asInt(j['head']).clamp(0, steps.length - 1));
  }
}

/// The history row's words: what the step did, with its times.
String studioStepLabel(StudioStep s) {
  final i = s.info;
  String tm(String k) => mmss(_d(i[k]));
  final name = '${i['name'] ?? ''}';
  return switch (s.kind) {
    StudioStepKind.open => t('الأصل كما هو', 'The original'),
    StudioStepKind.split => t('تقسيم عند ${tm('at')}', 'Split at ${tm('at')}'),
    StudioStepKind.remove => t('حذف ${tm('a')} – ${tm('b')}', 'Removed ${tm('a')} – ${tm('b')}'),
    StudioStepKind.keep => t('الإبقاء على ${tm('a')} – ${tm('b')} فقط', 'Kept only ${tm('a')} – ${tm('b')}'),
    StudioStepKind.deleteClip => t('حذف جزء (${tm('len')})', 'Deleted a part (${tm('len')})'),
    StudioStepKind.trimStart => t('تعديل بداية جزء إلى ${tm('to')}', "Moved a part's start to ${tm('to')}"),
    StudioStepKind.trimEnd => t('تعديل نهاية جزء إلى ${tm('to')}', "Moved a part's end to ${tm('to')}"),
    StudioStepKind.speed => t('السرعة ${speedLabel(_d(i['speed'], 1))} على ${tm('a')} – ${tm('b')}', 'Speed ${speedLabel(_d(i['speed'], 1))} on ${tm('a')} – ${tm('b')}'),
    StudioStepKind.textAdd => t('إضافة نص «$name»', 'Added the text “$name”'),
    StudioStepKind.imageAdd => t('إضافة صورة', 'Added a picture'),
    StudioStepKind.overlayMove => t('تحريك «$name»', 'Moved “$name”'),
    StudioStepKind.overlayTime => t('وقت «$name»: ${tm('a')} – ${tm('b')}', 'When “$name” shows: ${tm('a')} – ${tm('b')}'),
    StudioStepKind.overlayStyle => t('تنسيق «$name»', 'Styled “$name”'),
    StudioStepKind.overlayAnim => t('حركة «$name»', 'Animation of “$name”'),
    StudioStepKind.overlayRemove => t('حذف «$name»', 'Removed “$name”'),
    StudioStepKind.quality => t('الجودة: ${i['label'] ?? ''}', 'Quality: ${i['label'] ?? ''}'),
    StudioStepKind.reset => t('العودة إلى الأصل', 'Back to the original'),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Render
// ─────────────────────────────────────────────────────────────────────────────

/// What POST …/render receives. [assets] maps each overlay id to the PNG uploaded for it (a text: drawn by the app,
/// [textWidths] its width as a fraction of the frame); an overlay without one is left out.
Map<String, dynamic> studioRenderParams(StudioEdit e,
    {required Map<String, String> assets, Map<String, double> textWidths = const {}, Map<String, dynamic>? history, String? title}) {
  final overlays = <Map<String, dynamic>>[];
  for (final o in e.overlays) {
    final span = e.overlayOut(o);
    final asset = assets[o.id];
    if (span == null || asset == null) continue;
    overlays.add({
      'id': o.id,
      'kind': o.kind.name,
      'asset': asset,
      'start': _r3(span.$1),
      'end': _r3(span.$2),
      'x': _r3(o.x),
      'y': _r3(o.y),
      'w': _r3(o.isText ? (textWidths[o.id] ?? 0.3) : o.w),
      'opacity': _r3(o.opacity),
      'in': {'type': o.inAnim.wire, 'd': _r3(o.inDur)},
      'out': {'type': o.outAnim.wire, 'd': _r3(o.outDur)},
      'rtl': o.isText && o.rtl,
      'chars': o.isText ? math.max(1, o.text.replaceAll(RegExp(r'\s'), '').runes.length) : 1,
    });
  }
  return {
    'clips': [
      for (final c in e.clips) {'start': _r3(c.start), 'end': _r3(c.end), 'speed': c.speed}
    ],
    'overlays': overlays,
    if (e.height != null) 'height': e.height,
    if (e.level != null) 'level': e.level!.wire,
    'history': ?history,
    if ((title ?? '').trim().isNotEmpty) 'title': title!.trim(),
  };
}

/// The two halves of [e] at output second [at]: "Split into two files" renders each as its own project.
(StudioEdit, StudioEdit)? studioHalves(StudioEdit e, double at) {
  final s = e.split(at);
  var t0 = 0.0;
  final a = <StudioClip>[], b = <StudioClip>[];
  for (final c in s.clips) {
    (t0 + c.length / 2 < at ? a : b).add(c);
    t0 += c.length;
  }
  if (a.isEmpty || b.isEmpty) return null;
  final ea = StudioEdit(clips: a, overlays: e.overlays, height: e.height, level: e.level);
  final eb = StudioEdit(clips: b, overlays: e.overlays, height: e.height, level: e.level);
  if (ea.duration < 1 || eb.duration < 1) return null;
  return (ea, eb);
}

// ─────────────────────────────────────────────────────────────────────────────
// How an overlay looks at a moment (the preview; studio_render.py draws the same curves)
// ─────────────────────────────────────────────────────────────────────────────

class StudioLook {
  const StudioLook({this.opacity = 1, this.dx = 0, this.dy = 0, this.scale = 1, this.reveal = 1});

  /// 0–1, times the overlay's own opacity.
  final double opacity;

  /// Offset as fractions of the frame's width / height.
  final double dx;
  final double dy;
  final double scale;

  /// Typewriter: the share of the width shown (from the reading start).
  final double reveal;
}

double _clip01(double v) => v.isNaN ? 0 : v.clamp(0.0, 1.0);
double _easeOutCubic(double p) => 1 - math.pow(1 - p, 3).toDouble();
double _easeOutBack(double p) => 1 + 2.70158 * math.pow(p - 1, 3) + 1.70158 * math.pow(p - 1, 2);

/// [o] at output second [now], shown over [a, b] (output). Null: not on screen.
StudioLook? studioOverlayLook(StudioOverlay o, double a, double b, double now) {
  if (now < a || now > b) return null;
  final len = b - a;
  final u = now - a;
  final di = o.inAnim == StudioAnim.none ? 0.0 : math.min(o.inDur, len / 2);
  final dOut = o.outAnim == StudioAnim.none ? 0.0 : math.min(o.outDur, len / 2);
  final pin = di > 0 ? _clip01(u / di) : 1.0;
  final pout = dOut > 0 ? _clip01((len - u) / dOut) : 1.0;
  var opacity = 1.0, dx = 0.0, dy = 0.0, scale = 1.0, reveal = 1.0;
  const fades = {StudioAnim.fade, StudioAnim.slideUp, StudioAnim.slideDown, StudioAnim.slideLeft, StudioAnim.slideRight, StudioAnim.pop};
  if (fades.contains(o.inAnim) && di > 0) opacity *= pin;
  if (fades.contains(o.outAnim) && dOut > 0) opacity *= pout;
  if (o.inAnim == StudioAnim.pop && di > 0) scale *= 0.6 + 0.4 * _easeOutBack(pin);
  if (o.outAnim == StudioAnim.pop && dOut > 0) scale *= 0.6 + 0.4 * _easeOutCubic(pout);
  void slide(StudioAnim k, double e, bool entering) {
    final m = 0.06 * (1 - e);
    switch (k) {
      case StudioAnim.slideUp:
        dy += entering ? m : -m;
      case StudioAnim.slideDown:
        dy += entering ? -m : m;
      case StudioAnim.slideLeft:
        dx += entering ? m : -m;
      case StudioAnim.slideRight:
        dx += entering ? -m : m;
      default:
        break;
    }
  }

  if (di > 0) slide(o.inAnim, _easeOutCubic(pin), true);
  if (dOut > 0) slide(o.outAnim, _easeOutCubic(pout), false);
  if (o.isText && (o.inAnim == StudioAnim.typewriter || o.outAnim == StudioAnim.typewriter)) {
    final n = math.max(1, o.text.replaceAll(RegExp(r'\s'), '').runes.length);
    final rin = o.inAnim == StudioAnim.typewriter && di > 0 ? (pin * n).floor() / n : 1.0;
    final rout = o.outAnim == StudioAnim.typewriter && dOut > 0 ? (pout * n).floor() / n : 1.0;
    reveal = rin * rout;
  }
  return StudioLook(opacity: opacity * o.opacity, dx: dx, dy: dy, scale: scale, reveal: reveal);
}

/// The ruler / readout time with hundredths: "01:23.45".
String studioTimecode(double seconds) {
  final s = seconds.isFinite && seconds > 0 ? seconds : 0.0;
  final cs = ((s - s.floor()) * 100).floor().clamp(0, 99);
  return '${mmss(s)}.${cs.toString().padLeft(2, '0')}';
}
