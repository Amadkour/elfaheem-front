// lib/features/live/room/annotation/annotation_controller.dart
//
// The annotation board of one live room (D-079): strokes, laser dots, who may draw, and the local tool. Pure
// logic, no LiveKit import: RoomPage injects [AnnotSend] (publishData on the packet's topic, reliable or lossy,
// optionally to a few identities) and feeds every packet of the annotation topics into [receive] with the REAL
// sender identity (DataReceivedEvent.participant?.identity). Nothing in a payload decides who sent it.
//
// Roles: hosts (the session's teacher / meeting hosts) and the presenter (whoever shares) always draw; students
// draw only when the host allows it (everyone, or named identities). A packet from a sender who may not draw is
// dropped. Undo is per author (your own last stroke); the eraser removes strokes it touches (any stroke for a
// host / the presenter, your own otherwise); clear all is for hosts.
//
// Late joiners: [requestSnapshot] on joining; the responder (the presenter, else the first host by identity)
// answers with the board in chunks, then the permission and mode. [onParticipantJoined] makes the responder
// send it unasked too. Snapshots are merged, never trusted over newer live packets (erased refs and a clear
// seen since the request win).
//
// Burned-in mode (Android whole-screen share with the native overlay, android_overlay.dart): the presenter's
// strokes are drawn into the shared video by the overlay, so local strokes here are never sent as vectors, and
// students cannot draw.
library;

import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:flutter_education_app/features/live/room/annotation/annotation_protocol.dart';
import 'package:flutter_education_app/features/live/room/annotation/live_presence.dart';

/// Publishes [bytes] on [topic]; [to] limits the receivers (null = everyone).
typedef AnnotSend = Future<void> Function(String topic, List<int> bytes, bool reliable, {List<String>? to});

/// What a pointer does on the board.
enum AnnotTool { pen, highlighter, eraser, laser }

/// A stroke on the board. [points] grows while [open].
class AnnotStroke {
  AnnotStroke({
    required this.author,
    required this.id,
    required this.ink,
    required this.color,
    required this.width,
    List<AnnotPoint>? points,
    this.open = true,
    this.pressured,
  }) : points = points ?? <AnnotPoint>[];

  final String author;
  final String id;
  final AnnotInk ink;
  final int color;
  final double width;
  List<AnnotPoint> points;
  bool open;

  /// A stylus stroke: the width follows the pressure (`pr` on the wire). Null: an older sender did not say.
  final bool? pressured;
  bool _guessedPressure = false;

  /// Whether the width follows the pressure. For an older sender (no `pr`) it is guessed from the samples
  /// (any pressure away from 0.5), and once guessed it stays (the look never flips back mid-stroke).
  bool get isPressured {
    final p = pressured;
    if (p != null) return p;
    if (_guessedPressure) return true;
    if (ink == AnnotInk.pen && points.any((q) => (q.p - 0.5).abs() > 0.02)) _guessedPressure = true;
    return _guessedPressure;
  }

  /// Bumped on every change (the painter's path cache keys on it).
  int version = 0;

  AnnotRef get ref => AnnotRef(author, id);

  AnnotStrokeData toData({List<AnnotPoint>? points}) => AnnotStrokeData(
      author: author,
      id: id,
      ink: ink,
      color: color,
      width: width,
      points: points ?? this.points,
      open: open,
      pressured: pressured);
}

class AnnotLaserDot {
  const AnnotLaserDot({required this.author, required this.x, required this.y, required this.at});

  final String author;
  final double x;
  final double y;
  final DateTime at;
}

/// The drawable state. Notifies only when something visible changed: the painter repaints on it alone.
class AnnotBoard extends ChangeNotifier {
  final Map<String, AnnotStroke> _strokes = {}; // insertion order = drawing order
  final Map<String, AnnotLaserDot> _lasers = {};
  int _revision = 0;

  Iterable<AnnotStroke> get strokes => _strokes.values;
  Iterable<AnnotLaserDot> get lasers => _lasers.values;
  int get strokeCount => _strokes.length;
  bool get isEmpty => _strokes.isEmpty;
  bool get hasLasers => _lasers.isNotEmpty;
  int get revision => _revision;

  AnnotStroke? stroke(AnnotRef r) => _strokes[r.key];

  void _changed() {
    _revision++;
    notifyListeners();
  }
}

class AnnotationController extends ChangeNotifier {
  AnnotationController({
    required this.localIdentity,
    this.send,
    DateTime Function()? now,
    this.batchInterval = kAnnotBatchInterval,
    this.laserTtl = kAnnotLaserTtl,
    this.autoFlush = true,
    this.maxStrokes = 4000,
    String Function(String identity)? nameOf,
    String? idPrefix,
    int? color,
  })  : now = now ?? DateTime.now,
        nameOf = nameOf ?? ((id) => id),
        _idPrefix = idPrefix ?? _randomPrefix(),
        _color = color ?? 0xFFE53935;

  final String localIdentity;
  AnnotSend? send;
  final DateTime Function() now;

  /// A participant's display name (the room: LiveKit's name; a guest's typed name), for the name tags (D-093).
  String Function(String identity) nameOf;

  /// Who else is drawing now: the name tags over the shared screen.
  late final LivePresence presence = LivePresence(now: now);

  /// [nameOf], cleaned (bidi controls out, 24 characters at most).
  String displayName(String identity) => presenceSafeName(nameOf(identity), fallback: identity.isEmpty ? '' : '…');

  /// Whether [identity]'s tag shows here: never your own; the presenter's only when others may draw too.
  bool presenceShownFor(String identity) =>
      identity != localIdentity && (_allowStudents || _allowed.isNotEmpty || identity != _presenter);
  final Duration batchInterval;
  final Duration laserTtl;

  /// Off in tests: points then go out only on [flush] (or when a stroke ends).
  final bool autoFlush;
  final int maxStrokes;

  final AnnotBoard board = AnnotBoard();
  final String _idPrefix;
  int _nextId = 0;
  bool _disposed = false;

  // ── Roles and permission ───────────────────────────────────────────────────
  Set<String> _hosts = {};
  String? _presenter;
  bool _allowStudents = false;
  Set<String> _allowed = {};
  bool _burnedIn = false;
  bool _showAuthors = false;

  Set<String> get hosts => Set.unmodifiable(_hosts);
  String? get presenter => _presenter;
  bool get allowStudents => _allowStudents;

  /// The host's "Show who drew what" (D-093): an item's author on hover / long press (here and on the whiteboard).
  bool get showAuthors => _showAuthors;
  Set<String> get allowedIdentities => Set.unmodifiable(_allowed);
  bool get burnedIn => _burnedIn;
  bool get isHost => _hosts.contains(localIdentity);
  bool get isPresenter => _presenter == localIdentity;

  /// Hosts and the presenter may draw, erase anyone's strokes and send the board.
  bool isLead(String identity) => _hosts.contains(identity) || (_presenter != null && _presenter == identity);

  bool canDraw(String identity) {
    if (identity.isEmpty) return false;
    if (isLead(identity)) return true;
    if (_burnedIn) return false;
    return _allowStudents || _allowed.contains(identity);
  }

  bool get canDrawLocal => canDraw(localIdentity);

  /// The one who answers snapshot requests: the presenter, else the first host by identity.
  bool get isSnapshotResponder {
    if (_presenter != null) return _presenter == localIdentity;
    if (_hosts.isEmpty) return false;
    final first = (_hosts.toList()..sort()).first;
    return first == localIdentity;
  }

  /// RoomPage keeps this in step with the room: host identities present, and who shares (null = nobody).
  void setRoles({required Iterable<String> hosts, String? presenter}) {
    final h = hosts.toSet();
    if (setEquals(h, _hosts) && presenter == _presenter) return;
    _hosts = h;
    _presenter = presenter;
    _afterPermissionChange();
    _notify();
  }

  /// Host: let every student draw (or stop it). Sent to everyone.
  void setAllowStudents(bool allow) {
    if (!isHost || allow == _allowStudents) return;
    _allowStudents = allow;
    _emit(_permission);
    _afterPermissionChange();
    _notify();
  }

  /// Host: let these students draw while [allowStudents] is off.
  void setAllowedIdentities(Set<String> ids) {
    if (!isHost || setEquals(ids, _allowed)) return;
    _allowed = Set.of(ids);
    _emit(_permission);
    _afterPermissionChange();
    _notify();
  }

  /// Host: show (or stop showing) who drew what on hover / long press. Off by default. Sent to everyone.
  void setShowAuthors(bool on) {
    if (!isHost || on == _showAuthors) return;
    _showAuthors = on;
    _emit(_permission);
    _notify();
  }

  AnnotPermission get _permission =>
      AnnotPermission(allowStudents: _allowStudents, allowed: _allowed, showAuthors: _showAuthors);

  /// The presenter (or a host) switches burned-in mode for the Android whole-screen share.
  void setBurnedIn(bool on) {
    if (on == _burnedIn) return;
    if (!isLead(localIdentity)) return;
    _burnedIn = on;
    _emit(AnnotMode(burnedIn: on));
    _afterPermissionChange();
    _notify();
  }

  void _afterPermissionChange() {
    if (!canDrawLocal) {
      if (_current != null) endStroke();
      _drawMode = false;
    }
  }

  // ── Local tool ─────────────────────────────────────────────────────────────
  AnnotTool _tool = AnnotTool.pen;
  /// ARGB; RoomPage passes the first colour of `annotPresetColors` (the theme's danger red).
  int _color;
  int _thickness = 1;
  bool _drawMode = false;

  AnnotTool get tool => _tool;
  int get colorArgb => _color;

  /// 0, 1, 2: thin, medium, thick.
  int get thickness => _thickness;

  /// The layer takes the pointer (otherwise the video below gets it).
  bool get drawMode => _drawMode && canDrawLocal;

  void setTool(AnnotTool t) {
    if (t == _tool) return;
    if (_current != null) endStroke();
    _tool = t;
    _notify();
  }

  void setColor(int argb) {
    if (argb == _color) return;
    _color = argb;
    _notify();
  }

  void setThickness(int step) {
    final s = step.clamp(0, kAnnotPenWidths.length - 1);
    if (s == _thickness) return;
    _thickness = s;
    _notify();
  }

  void setDrawMode(bool on) {
    final next = on && canDrawLocal;
    if (next == _drawMode) return;
    if (!next && _current != null) endStroke();
    _drawMode = next;
    _notify();
  }

  // ── Local drawing ──────────────────────────────────────────────────────────
  AnnotStroke? _current;
  AnnotTool? _gestureTool;
  final AnnotPointBatcher _batch = AnnotPointBatcher();
  final List<AnnotRef> _pendingErase = [];
  final List<String> _undoStack = [];
  Timer? _flushTimer;
  DateTime? _lastLaserSent;

  bool get isDrawing => _gestureTool != null;
  bool get canUndo => _undoStack.any((id) => board.stroke(AnnotRef(localIdentity, id)) != null);

  /// A pointer went down at ([x], [y]) (normalised) with pressure [p]. [toolOverride]: the stylus's eraser end.
  /// [stylus]: the pen's width follows the pressure (the stroke says so on the wire, `pr`). The layer feeds
  /// FILTERED points (annotation_ink.dart). Returns false when the local person may not draw.
  bool begin(double x, double y, {double p = 0.5, AnnotTool? toolOverride, bool stylus = false}) {
    if (!canDrawLocal) return false;
    if (_gestureTool != null) end();
    final tool = toolOverride ?? _tool;
    _gestureTool = tool;
    switch (tool) {
      case AnnotTool.pen:
      case AnnotTool.highlighter:
        _startStroke(tool == AnnotTool.pen ? AnnotInk.pen : AnnotInk.highlighter, AnnotPoint.wire(x, y, stylus ? p : 0.5),
            pressured: stylus && tool == AnnotTool.pen);
      case AnnotTool.eraser:
        eraseAt(x, y);
      case AnnotTool.laser:
        pointLaser(x, y);
    }
    return true;
  }

  void move(double x, double y, {double p = 0.5, double aspect = 16 / 9}) {
    switch (_gestureTool) {
      case AnnotTool.pen:
      case AnnotTool.highlighter:
        _addPoint(AnnotPoint.wire(x, y, _current?.pressured == true ? p : 0.5));
      case AnnotTool.eraser:
        eraseAt(x, y, aspect: aspect);
      case AnnotTool.laser:
        pointLaser(x, y);
      case null:
        break;
    }
  }

  void end() {
    final t = _gestureTool;
    _gestureTool = null;
    if (t == AnnotTool.pen || t == AnnotTool.highlighter) endStroke();
    if (_pendingErase.isNotEmpty) flush();
  }

  /// Palm rejection: the touch that started a stroke turned out to be a palm (a stylus came down). The stroke
  /// is removed everywhere.
  void cancel() {
    final s = _current;
    _gestureTool = null;
    _current = null;
    _batch.clear();
    if (s == null) return;
    board._strokes.remove(s.ref.key);
    board._changed();
    _emit(AnnotErase([s.ref]));
    _notify();
  }

  void _startStroke(AnnotInk ink, AnnotPoint first, {bool pressured = false}) {
    if (board.strokeCount >= maxStrokes) return;
    final id = '$_idPrefix${(_nextId++).toRadixString(36)}';
    final widths = ink == AnnotInk.pen ? kAnnotPenWidths : kAnnotHighlighterWidths;
    final s = AnnotStroke(
      author: localIdentity,
      id: id,
      ink: ink,
      color: _color,
      width: annotRound(widths[_thickness]).toDouble(),
      points: [first],
      pressured: pressured,
    );
    _current = s;
    board._strokes[s.ref.key] = s;
    board._changed();
    _emit(AnnotStart(id: id, author: localIdentity, ink: ink, color: s.color, width: s.width, pressured: pressured));
    _batch.add(first, now());
    _scheduleFlush();
  }

  void _addPoint(AnnotPoint p) {
    final s = _current;
    if (s == null || s.points.length >= kAnnotMaxPointsPerStroke) return;
    final last = s.points.last;
    if (last.x == p.x && last.y == p.y && last.p == p.p) return;
    s.points.add(p);
    s.version++;
    board._changed();
    _batch.add(p, now());
    if (_batch.due(now())) {
      flush();
    } else {
      _scheduleFlush();
    }
  }

  /// Finishes the stroke in progress: the last points go out, then the end. The points are kept as drawn (an
  /// end-of-stroke simplification used to move the finished curve under the pen, D-083).
  void endStroke() {
    final s = _current;
    if (s == null) return;
    flush(); // while _current is still this stroke: the pending points carry its id
    _current = null;
    if (_gestureTool == AnnotTool.pen || _gestureTool == AnnotTool.highlighter) _gestureTool = null;
    _emit(AnnotEnd(s.id));
    _finish(s);
    _undoStack.add(s.id);
    if (_undoStack.length > 200) _undoStack.removeAt(0);
    _notify();
  }

  void _finish(AnnotStroke s) {
    s.open = false;
    s.version++;
    board._changed();
  }

  /// Sends the pending points and erases now.
  void flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    final s = _current;
    while (_batch.hasPending) {
      final pts = _batch.take();
      if (s != null) _emit(AnnotPoints(id: s.id, points: pts));
    }
    if (_pendingErase.isNotEmpty) {
      final refs = List.of(_pendingErase);
      _pendingErase.clear();
      _emit(AnnotErase(refs));
    }
  }

  void _scheduleFlush() {
    if (!autoFlush || _flushTimer != null) return;
    _flushTimer = Timer(batchInterval, flush);
  }

  /// Your own last stroke still on the board is removed everywhere.
  void undo() {
    while (_undoStack.isNotEmpty) {
      final id = _undoStack.removeLast();
      final ref = AnnotRef(localIdentity, id);
      if (board.stroke(ref) == null) continue;
      board._strokes.remove(ref.key);
      board._changed();
      _emit(AnnotUndo(author: localIdentity, id: id));
      _notify();
      return;
    }
  }

  /// Removes the strokes under ([x], [y]). [aspect] is the content's width / height (distances are measured in
  /// frame widths on both axes); [tolerance] is added to each stroke's half width.
  List<AnnotRef> eraseAt(double x, double y, {double aspect = 16 / 9, double tolerance = 0.012}) {
    if (!canDrawLocal) return const [];
    final anyone = isLead(localIdentity);
    final hits = hitTest(x, y, aspect: aspect, tolerance: tolerance)
        .where((s) => anyone || s.author == localIdentity)
        .toList();
    if (hits.isEmpty) return const [];
    for (final s in hits) {
      board._strokes.remove(s.ref.key);
      _pendingErase.add(s.ref);
    }
    board._changed();
    if (autoFlush) {
      _scheduleFlush();
    }
    _notify();
    return [for (final s in hits) s.ref];
  }

  /// Strokes whose path passes within [tolerance] + half its width of ([x], [y]), topmost first.
  List<AnnotStroke> hitTest(double x, double y, {double aspect = 16 / 9, double tolerance = 0.012}) {
    final a = aspect <= 0 || !aspect.isFinite ? 1.0 : aspect;
    final py = y / a;
    final out = <AnnotStroke>[];
    for (final s in board.strokes.toList().reversed) {
      if (identical(s, _current)) continue;
      final r = tolerance + s.width / 2;
      final pts = s.points;
      var hit = false;
      if (pts.length == 1) {
        hit = _dist(x, py, pts[0].x, pts[0].y / a) <= r;
      } else {
        for (var i = 1; i < pts.length && !hit; i++) {
          hit = _segDist(x, py, pts[i - 1].x, pts[i - 1].y / a, pts[i].x, pts[i].y / a) <= r;
        }
      }
      if (hit) out.add(s);
    }
    return out;
  }

  /// Host: removes every stroke for everyone.
  void clearAll() {
    if (!isHost) return;
    if (_current != null) cancel();
    _clearBoard();
    _emit(const AnnotClear());
    _notify();
  }

  void _clearBoard() {
    _current = null;
    _batch.clear();
    _undoStack.clear();
    if (board._strokes.isEmpty) return;
    board._strokes.clear();
    board._changed();
  }

  /// Moves the local laser dot (sent lossy, at most every [batchInterval]).
  void pointLaser(double x, double y) {
    if (!canDrawLocal) return;
    final t = now();
    final dot = AnnotLaserDot(author: localIdentity, x: _c(x), y: _c(y), at: t);
    board._lasers[localIdentity] = dot;
    board._changed();
    if (_lastLaserSent != null && t.difference(_lastLaserSent!) < batchInterval) return;
    _lastLaserSent = t;
    _emit(AnnotLaser(x: dot.x, y: dot.y, author: localIdentity));
  }

  /// Drops laser dots older than [laserTtl]. Returns whether any are left (the layer's ticker keeps going).
  bool pruneLasers() {
    final t = now();
    final before = board._lasers.length;
    board._lasers.removeWhere((_, d) => t.difference(d.at) >= laserTtl);
    if (board._lasers.length != before) board._changed();
    return board._lasers.isNotEmpty;
  }

  /// 1 → 0 over the last 40 % of the laser's life.
  double laserOpacity(AnnotLaserDot d) {
    final age = now().difference(d.at).inMicroseconds / laserTtl.inMicroseconds;
    if (age <= 0.6) return 1;
    return (1 - (age - 0.6) / 0.4).clamp(0.0, 1.0).toDouble();
  }

  // ── Late joiners ───────────────────────────────────────────────────────────
  final AnnotSnapshotAssembler _assembler = AnnotSnapshotAssembler();
  final Set<String> _tombstones = {};
  bool _awaitingSnapshot = false;

  /// On joining (and on reconnect): asks the room for the board.
  void requestSnapshot() {
    _awaitingSnapshot = true;
    _tombstones.clear();
    _emit(const AnnotSnapshotRequest());
  }

  /// RoomPage: a participant connected. The responder sends them the board.
  void onParticipantJoined(String identity) {
    if (identity == localIdentity || !isSnapshotResponder) return;
    sendSnapshot(to: [identity]);
  }

  /// Sends the whole board (chunked), then the permission and the mode, to [to] (null = everyone).
  void sendSnapshot({List<String>? to}) {
    final cb = send;
    if (cb == null) return;
    final sid = '${_idPrefix}s${(_nextId++).toRadixString(36)}';
    // Every point as drawn: a late joiner draws exactly what the others see (D-083).
    final chunks = AnnotCodec.snapshotChunks([for (final s in board.strokes) s.toData()], sid: sid);
    for (final c in chunks) {
      _sendRaw(kAnnotTopic, c, true, to: to);
    }
    if (isHost) _emit(_permission, to: to, force: true);
    if (_burnedIn) _emit(const AnnotMode(burnedIn: true), to: to, force: true);
  }

  void _applySnapshot(List<AnnotStrokeData> strokes) {
    _awaitingSnapshot = false;
    var changed = false;
    for (final d in strokes) {
      final key = d.ref.key;
      if (_tombstones.contains(key)) continue;
      final have = board._strokes[key];
      if (have != null && have.points.length >= d.points.length) continue;
      if (have == null && board.strokeCount >= maxStrokes) continue;
      final s = have ??
          AnnotStroke(
              author: d.author, id: d.id, ink: d.ink, color: d.color, width: d.width, open: d.open, pressured: d.pressured);
      s.points = List.of(d.points);
      s.open = d.open;
      s.version++;
      board._strokes[key] = s;
      changed = true;
    }
    _tombstones.clear();
    if (changed) board._changed();
  }

  // ── Receiving ──────────────────────────────────────────────────────────────

  /// A packet on [kAnnotTopic] / [kAnnotLaserTopic] from [sender] (LiveKit's participant identity; null = the
  /// server, which never sends annotation, so it is ignored). Returns whether it was applied.
  bool receive(String topic, List<int> data, {required String? sender}) {
    if (sender == null || sender.isEmpty || sender == localIdentity) return false;
    final m = AnnotCodec.decode(data, topic: topic);
    if (m == null) return false;
    final ok = _apply(m, sender);
    if (!ok && kDebugMode) log('annotation: dropped ${m.runtimeType} from $sender');
    return ok;
  }

  bool _apply(AnnotMsg m, String sender) {
    switch (m) {
      case AnnotStart():
        if (!canDraw(sender)) return false;
        final ref = AnnotRef(sender, m.id);
        if (board.stroke(ref) != null || board.strokeCount >= maxStrokes) return false;
        if (board.strokes.where((s) => s.open && s.author == sender).length >= 4) return false;
        board._strokes[ref.key] =
            AnnotStroke(author: sender, id: m.id, ink: m.ink, color: m.color, width: m.width, pressured: m.pressured);
        board._changed();
        return true;
      case AnnotPoints():
        if (!canDraw(sender)) return false;
        final s = board.stroke(AnnotRef(sender, m.id));
        if (s == null || !s.open) return false;
        final room = kAnnotMaxPointsPerStroke - s.points.length;
        if (room <= 0) return false;
        s.points.addAll(m.points.take(room));
        s.version++;
        board._changed();
        final tip = s.points.last;
        presence.mark(sender, name: displayName(sender), x: tip.x, y: tip.y, color: s.color, active: true);
        return true;
      case AnnotEnd():
        final s = board.stroke(AnnotRef(sender, m.id));
        if (s == null || !s.open) return false;
        _finish(s);
        presence.end(sender);
        return true;
      case AnnotUndo():
        if (m.author.isNotEmpty && m.author != sender) return false;
        return _remove([AnnotRef(sender, m.id)]);
      case AnnotErase():
        final anyone = isLead(sender);
        final refs = m.refs.where((r) => anyone || r.author == sender).toList();
        if (refs.isEmpty) return false;
        _remove(refs);
        return true;
      case AnnotClear():
        if (!_hosts.contains(sender)) return false;
        _clearBoard();
        if (_awaitingSnapshot) _tombstones.add('\u0001clear');
        _notify();
        return true;
      case AnnotSnapshotRequest():
        if (!isSnapshotResponder) return false;
        sendSnapshot(to: [sender]);
        return true;
      case AnnotSnapshotChunk():
        if (!isLead(sender)) return false;
        final strokes = _assembler.add(sender, m);
        if (strokes != null) {
          if (_tombstones.contains('\u0001clear')) {
            _awaitingSnapshot = false;
            _tombstones.clear();
          } else {
            _applySnapshot(strokes);
          }
          _notify();
        }
        return true;
      case AnnotPermission():
        if (!_hosts.contains(sender)) return false;
        _allowStudents = m.allowStudents;
        _allowed = Set.of(m.allowed);
        _showAuthors = m.showAuthors;
        _afterPermissionChange();
        _notify();
        return true;
      case AnnotMode():
        if (!isLead(sender)) return false;
        if (_burnedIn != m.burnedIn) {
          _burnedIn = m.burnedIn;
          _afterPermissionChange();
          _notify();
        }
        return true;
      case AnnotLaser():
        if (!canDraw(sender)) return false;
        board._lasers[sender] = AnnotLaserDot(author: sender, x: m.x, y: m.y, at: now());
        board._changed();
        presence.mark(sender, name: displayName(sender), x: m.x, y: m.y, active: false);
        return true;
    }
  }

  /// The topmost stroke under ([x], [y]) (for "Drawn by …"). [aspect]: the content's width / height.
  AnnotStroke? strokeAt(double x, double y, {double aspect = 16 / 9}) {
    final hits = hitTest(x, y, aspect: aspect, tolerance: 0.01);
    return hits.isEmpty ? null : hits.first;
  }

  /// RoomPage: someone left (their tag goes).
  void participantLeft(String identity) => presence.remove(identity);

  bool _remove(List<AnnotRef> refs) {
    var any = false;
    for (final r in refs) {
      if (_awaitingSnapshot && _tombstones.length < 10000) _tombstones.add(r.key);
      if (board._strokes.remove(r.key) != null) any = true;
    }
    if (any) {
      board._changed();
      _notify();
    }
    return any;
  }

  // ── Sending ────────────────────────────────────────────────────────────────

  /// Encodes and publishes [m]. In burned-in mode the presenter's strokes are in the video already, so stroke
  /// packets stay local ([force] is for the snapshot's own permission / mode packets).
  void _emit(AnnotMsg m, {List<String>? to, bool force = false}) {
    if (_burnedIn && !force && _isStrokeTraffic(m)) return;
    _sendRaw(m.topic, AnnotCodec.encode(m), m.reliable, to: to);
  }

  static bool _isStrokeTraffic(AnnotMsg m) =>
      m is AnnotStart || m is AnnotPoints || m is AnnotEnd || m is AnnotUndo || m is AnnotErase || m is AnnotLaser;

  void _sendRaw(String topic, List<int> bytes, bool reliable, {List<String>? to}) {
    final cb = send;
    if (cb == null) return;
    try {
      cb(topic, bytes, reliable, to: to).catchError((Object e) {
        if (kDebugMode) log('annotation: send failed: $e');
      });
    } catch (e) {
      if (kDebugMode) log('annotation: send failed: $e');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    board.dispose();
    presence.dispose();
    super.dispose();
  }
}

double _c(double v) => v.isNaN ? 0 : v.clamp(0.0, 1.0).toDouble();

double _dist(double ax, double ay, double bx, double by) {
  final dx = ax - bx, dy = ay - by;
  return math.sqrt(dx * dx + dy * dy);
}

double _segDist(double px, double py, double ax, double ay, double bx, double by) {
  final dx = bx - ax, dy = by - ay;
  final l2 = dx * dx + dy * dy;
  if (l2 == 0) return _dist(px, py, ax, ay);
  final t = (((px - ax) * dx + (py - ay) * dy) / l2).clamp(0.0, 1.0);
  return _dist(px, py, ax + dx * t, ay + dy * t);
}

String _randomPrefix() {
  final r = math.Random();
  const abc = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return String.fromCharCodes([for (var i = 0; i < 4; i++) abc.codeUnitAt(r.nextInt(abc.length))]);
}
