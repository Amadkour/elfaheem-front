// lib/features/notebook/notebook_models.dart
//
// The student's notebook, دفتر المادة (WP10, docs/redesign/api/notebook.md): one page = typed blocks and / or ink.
// Ink points travel as integers, the first pair absolute and the rest deltas from the previous point; on the
// device a stroke holds absolute points in the page's canvas space (`ink.w` × `ink.h`).
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

/// The kinds of a typed block, in the server's short names.
enum NoteBlockKind {
  heading('h'),
  paragraph('p'),
  bullet('li'),
  highlight('hl'),
  equation('eq'),
  sticky('sticky');

  const NoteBlockKind(this.wire);

  final String wire;

  static NoteBlockKind of(String? s) =>
      NoteBlockKind.values.firstWhere((k) => k.wire == s, orElse: () => NoteBlockKind.paragraph);
}

/// One typed block: a heading, a paragraph, a bullet, a highlighted line, an equation or the sticky note.
class NoteBlock {
  const NoteBlock(this.kind, this.text);

  final NoteBlockKind kind;
  final String text;

  factory NoteBlock.fromJson(Map<String, dynamic> j) => NoteBlock(NoteBlockKind.of(j['t'] as String?), '${j['x'] ?? ''}');

  Map<String, dynamic> toJson() => {'t': kind.wire, 'x': text};

  @override
  bool operator ==(Object other) => other is NoteBlock && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);
}

/// A pen or a highlighter (the eraser removes whole strokes on the device; only what is left is saved).
enum InkTool {
  pen('pen'),
  highlighter('hl');

  const InkTool(this.wire);

  final String wire;

  static InkTool of(String? s) => s == 'hl' ? InkTool.highlighter : InkTool.pen;
}

/// One stroke in canvas coordinates. [color] is `#RRGGBB` (picked from a theme role on the device).
class InkStroke {
  InkStroke({required this.tool, required this.color, required this.width, List<Offset>? points})
      : points = points ?? <Offset>[];

  final InkTool tool;
  final String color;
  final double width;
  final List<Offset> points;

  /// The server's `[tool, color, width, [x0, y0, dx1, dy1, …]]`: rounded to integers, deltas clamped to the int16
  /// range the server accepts (a longer jump is split into steps). A one-point stroke (a dot) is sent twice.
  List<Object> toWire() {
    final nums = <int>[];
    var px = 0, py = 0;
    final pts = points.length == 1 ? [points.first, points.first] : points;
    for (final (i, p) in pts.indexed) {
      final x = p.dx.round(), y = p.dy.round();
      if (i == 0) {
        nums
          ..add(x)
          ..add(y);
      } else {
        var dx = x - px, dy = y - py;
        // a jump wider than the int16 range becomes several steps (never in practice: the canvas is ≤ 4096)
        while (dx.abs() > _maxDelta || dy.abs() > _maxDelta) {
          final sx = dx.clamp(-_maxDelta, _maxDelta), sy = dy.clamp(-_maxDelta, _maxDelta);
          nums
            ..add(sx)
            ..add(sy);
          dx -= sx;
          dy -= sy;
        }
        nums
          ..add(dx)
          ..add(dy);
      }
      px = x;
      py = y;
    }
    return [tool.wire, color, width.round().clamp(1, 64), nums];
  }

  static const int _maxDelta = 32767;

  static InkStroke? fromWire(Object? raw) {
    if (raw is! List || raw.length < 4 || raw[3] is! List) return null;
    final nums = [for (final n in raw[3] as List) (n as num).toInt()];
    if (nums.length < 2 || nums.length.isOdd) return null;
    final pts = <Offset>[];
    var x = nums[0], y = nums[1];
    pts.add(Offset(x.toDouble(), y.toDouble()));
    for (var i = 2; i < nums.length; i += 2) {
      x += nums[i];
      y += nums[i + 1];
      pts.add(Offset(x.toDouble(), y.toDouble()));
    }
    return InkStroke(
      tool: InkTool.of(raw[0] as String?),
      color: '${raw[1]}',
      width: ((raw[2] as num?) ?? 3).toDouble(),
      points: pts,
    );
  }
}

/// The ink of a page: its canvas size and its strokes.
class NoteInk {
  NoteInk({required this.width, required this.height, List<InkStroke>? strokes}) : strokes = strokes ?? <InkStroke>[];

  final double width, height;
  final List<InkStroke> strokes;

  bool get isEmpty => strokes.isEmpty;

  Map<String, dynamic> toJson() => {
    'w': width.round().clamp(1, 4096),
    'h': height.round().clamp(1, 4096),
    's': [for (final s in strokes) s.toWire()],
  };

  static NoteInk? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final strokes = <InkStroke>[];
    for (final s in (raw['s'] as List?) ?? const []) {
      final st = InkStroke.fromWire(s);
      if (st != null) strokes.add(st);
    }
    return NoteInk(
      width: math.max(1, ((raw['w'] as num?) ?? 1).toDouble()),
      height: math.max(1, ((raw['h'] as num?) ?? 1).toDouble()),
      strokes: strokes,
    );
  }
}

/// `typed` · `ink` · `mixed`, from what the page holds.
String noteKindOf(List<NoteBlock> blocks, NoteInk? ink) {
  final hasText = blocks.any((b) => b.text.trim().isNotEmpty);
  final hasInk = ink != null && !ink.isEmpty;
  if (hasText && hasInk) return 'mixed';
  return hasInk ? 'ink' : 'typed';
}

/// One notebook page.
class NotePage {
  const NotePage({
    required this.id,
    required this.clientId,
    this.subjectId,
    this.courseId,
    this.lessonId,
    this.title = '',
    this.kind = 'typed',
    this.blocks = const [],
    this.ink,
    this.shared = false,
    this.version = 0,
    this.createdAt,
    this.updatedAt,
    this.deleted = false,
    this.preview,
    this.strokeCount,
  });

  /// 0 = not saved yet.
  final int id;
  final String clientId;
  final int? subjectId, courseId, lessonId;
  final String title;
  final String kind;
  final List<NoteBlock> blocks;
  final NoteInk? ink;
  final bool shared;
  final int version;
  final DateTime? createdAt, updatedAt;
  final bool deleted;

  /// A list answer without `full=true`: the first typed characters and the stroke count instead of the content.
  final String? preview;
  final int? strokeCount;

  bool get isEmpty => blocks.every((b) => b.text.trim().isEmpty) && (ink == null || ink!.isEmpty);

  factory NotePage.fromJson(Map<String, dynamic> j) => NotePage(
    id: (j['id'] as num?)?.toInt() ?? 0,
    clientId: '${j['client_id'] ?? ''}',
    subjectId: (j['subject_id'] as num?)?.toInt(),
    courseId: (j['course_id'] as num?)?.toInt(),
    lessonId: (j['lesson_id'] as num?)?.toInt(),
    title: '${j['title'] ?? ''}',
    kind: '${j['kind'] ?? 'typed'}',
    blocks: [
      for (final b in (j['blocks'] as List?) ?? const [])
        if (b is Map) NoteBlock.fromJson(Map<String, dynamic>.from(b)),
    ],
    ink: NoteInk.fromJson(j['ink']),
    shared: j['shared'] == true,
    version: (j['version'] as num?)?.toInt() ?? 0,
    createdAt: notebookParseUtc(j['created_at']),
    updatedAt: notebookParseUtc(j['updated_at']),
    deleted: j['deleted'] == true,
    preview: j['preview'] as String?,
    strokeCount: (j['strokes'] as num?)?.toInt(),
  );

  /// The body of a create (`POST /pages`).
  Map<String, dynamic> toCreateJson() => {
    'client_id': clientId,
    'subject_id': ?subjectId,
    'course_id': ?courseId,
    'lesson_id': ?lessonId,
    'title': title,
    'kind': noteKindOf(blocks, ink),
    'blocks': [for (final b in blocks) b.toJson()],
    if (ink != null && !ink!.isEmpty) 'ink': ink!.toJson(),
  };

  /// The body of an update (`PUT /pages/{id}`) on top of [baseVersion].
  Map<String, dynamic> toUpdateJson(int baseVersion) => {
    'base_version': baseVersion,
    'title': title,
    'kind': noteKindOf(blocks, ink),
    'blocks': [for (final b in blocks) b.toJson()],
    'ink': ink != null && !ink!.isEmpty ? ink!.toJson() : null,
  };

  NotePage copyWith({
    int? id,
    String? title,
    List<NoteBlock>? blocks,
    NoteInk? ink,
    bool clearInk = false,
    int? version,
    bool? shared,
  }) => NotePage(
    id: id ?? this.id,
    clientId: clientId,
    subjectId: subjectId,
    courseId: courseId,
    lessonId: lessonId,
    title: title ?? this.title,
    kind: noteKindOf(blocks ?? this.blocks, clearInk ? null : (ink ?? this.ink)),
    blocks: blocks ?? this.blocks,
    ink: clearInk ? null : (ink ?? this.ink),
    shared: shared ?? this.shared,
    version: version ?? this.version,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deleted: deleted,
  );
}

/// The server stores naive UTC: a time without a zone is read as UTC.
DateTime? notebookParseUtc(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  final hasZone = raw.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(raw);
  return DateTime.tryParse(hasZone ? raw : '${raw}Z')?.toUtc();
}

/// A new client id (8..64 of `[A-Za-z0-9_-]`): time + randomness, unique per device.
String newNoteClientId([math.Random? random]) {
  final r = random ?? math.Random.secure();
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final tail = List.generate(12, (_) => chars[r.nextInt(chars.length)]).join();
  return 'nb_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_$tail';
}
