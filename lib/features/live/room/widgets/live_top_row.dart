// lib/features/live/room/widgets/live_top_row.dart
//
// The live room's top row (D-095, D-108): ONE line above the stage, never wrapping, never two bars. Plain values
// only (no Room, no recorder, no board controller), so test/ui/live_top_row_layout_test.dart pumps every state with
// the layout harness and test/visual/live_top_row_golden_test.dart renders it; room.dart's `_buildTopRow()` maps
// its state onto it.
//
//   start   ⓘ LIVE 12:34 — how long the room has been live (`live_started_at`); the chip is the room's info
//           button · the free-time countdown (+ Upgrade) · the weak-network pill · Room locked
//   center  (a whiteboard on the stage, [LiveTopRow.board]) what it is and whose · "You can draw" · the page:
//           ‹ 2 / 3 › + for the presenter, "2 / 3" for everyone else — the board no longer draws its own bar over
//           the page, so the page number and the recording never sit on two stacked lines (D-108)
//   end     the recording control · (board) Board options · Stop presenting · Full view · Minimize · ⋮
//
// The recording control replaces the bottom bar's Pause / Resume, its REC chip and the meeting creator's pinned
// Record / Stop: "⏸ Not recording · ● Record" while this device may start one (a meeting's creator, D-313: the paused
// state from the first second, one tap starts it), a red dot + the
// recording time while recording (amber + pause glyph while paused); a tap opens Pause / Resume / Stop recording —
// exactly the actions the device had on the bar (a course's teacher: Pause / Resume; a meeting's creator: also
// Stop). Everyone sees "● REC" while the server records (no controls: the device does not record, D-090).
// D-310: in a meeting everyone else sees the device's recording too (live_rec_signal.dart, topic `rec`): the same
// control — pulsing red dot + REC + the time while recording, the amber pause glyph + "Paused" while paused — with
// no menu. The dot follows the room's pulse, which Reduce motion parks fully lit.
//
// Fitting ONE line (D-108): below [kLiveTopRowCompactWidth] the labels are icons (the times stay). Whatever still
// does not fit folds by priority — a labelled chip first loses its label, then the least important pieces move
// into the ⋮ menu (board title, "You can draw", network, lock, board options, minimize, full view, the presenter's
// page arrows, Stop), and only the LIVE time, the recording control and the page number never leave the row. If
// even those do not fit (an absurd text scale on a 320 px phone), the line is drawn a little smaller — it never
// wraps, never scrolls and never overflows. Every tappable piece is a 48 px target; the visual chips are 40 px.
//
// Full view ([LiveTopRow.onFocus], shown while something fills the stage, D-108): room.dart draws only the shared
// content; a tap on it slides this row in over the top (with the bar at the bottom), where the full view button
// reads "Exit full view" ([LiveTopRow.focused]); see live_focus_chrome.dart.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/live/live_rec_signal.dart' show LiveRemoteRecState;
import 'package:flutter_education_app/features/live/live_time_limit.dart' show LiveLimitTone, LiveTimeLimit;

import 'package:flutter_education_app/features/live/room/widgets/live_palette.dart';
import 'package:flutter_education_app/features/live/room/widgets/record/recorder_types.dart';

/// Below this width the row draws icons where it has room for labels on a wide screen.
const double kLiveTopRowCompactWidth = 600;

/// Whether the device's recorder controls (Pause / Resume) are offered. A teacher's follow the course's record
/// switch exactly as before; anyone else's (a meeting creator) only while THIS device is the one recording
/// ([recordsHere], room.dart `_recordsHere`). Pure, so the layout test covers every state.
bool showsRecorderControls({required bool isTeacher, required bool recordingEnabled, required bool recordsHere}) =>
    isTeacher ? recordingEnabled : recordsHere;

/// What the recording control shows.
enum LiveRecPhase {
  /// Nothing (nobody records, or this person may not know / do anything about it).
  none,

  /// The server records (LiveKit egress): "● REC" for everyone, no controls.
  server,

  /// This device may start a recording (a meeting's creator): "⏸ Not recording · ● Record" (D-313).
  offer,
  starting,
  recording,
  paused,
  uploading,
  saved,
  error,
}

/// The phase of the control. [state] = this device's recorder (null when it does not record); [pending] = a
/// recording was asked for and the recorder is not running yet; [offer] = Record may be pressed; [server] = the
/// room's server recording is on; [remote] = someone else in the meeting records on their device (D-310, shown before
/// the Record offer: a second recording of the same meeting helps nobody). The device's own recorder wins (it is the
/// one with controls).
LiveRecPhase liveRecPhase(
    {RecState? state, bool pending = false, bool offer = false, bool server = false, LiveRemoteRecState? remote}) {
  switch (state) {
    case RecState.starting:
      return LiveRecPhase.starting;
    case RecState.recording:
      return LiveRecPhase.recording;
    case RecState.paused:
      return LiveRecPhase.paused;
    case RecState.uploading:
      return LiveRecPhase.uploading;
    case RecState.done:
      return LiveRecPhase.saved;
    case RecState.error:
      return LiveRecPhase.error;
    case RecState.idle:
    case null:
      break;
  }
  if (pending) return LiveRecPhase.starting;
  if (remote == LiveRemoteRecState.recording) return LiveRecPhase.recording;
  if (remote == LiveRemoteRecState.paused) return LiveRecPhase.paused;
  if (offer) return LiveRecPhase.offer;
  if (server) return LiveRecPhase.server;
  return LiveRecPhase.none;
}

/// The recording control's values. A null callback hides that menu entry.
class LiveTopRecording {
  const LiveTopRecording({
    this.phase = LiveRecPhase.none,
    this.elapsed = Duration.zero,
    this.detail,
    this.busy = false,
    this.onRecord,
    this.onPause,
    this.onResume,
    this.onStop,
  });

  final LiveRecPhase phase;

  /// The recording's own time (paused time not counted).
  final Duration elapsed;

  /// The upload progress line in the menu ("Part 3 · 12.4 MB").
  final String? detail;

  /// A start / pause / resume is in flight: a spinner, no taps.
  final bool busy;
  final VoidCallback? onRecord;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onStop;

  bool get hasMenu => onPause != null || onResume != null || onStop != null;

  /// The time is shown (recording / paused).
  bool get timed => phase == LiveRecPhase.recording || phase == LiveRecPhase.paused;
}

/// The free-time countdown (live_time_limit.dart's rules, computed by the room).
class LiveTopLimit {
  const LiveTopLimit({
    required this.remaining,
    this.tone = LiveLimitTone.calm,
    this.showUpgrade = false,
    this.busy = false,
    this.onUpgrade,
  });

  final Duration remaining;
  final LiveLimitTone tone;
  final bool showUpgrade;
  final bool busy;
  final VoidCallback? onUpgrade;
}

/// The whiteboard's header, carried by the top row while a board fills the stage (D-108): the board draws no bar
/// of its own, so the page and the recording share ONE line. A null callback hides that control.
class LiveTopBoard {
  const LiveTopBoard({
    required this.presenting,
    required this.pageIndex,
    required this.pageCount,
    this.presenterName = '',
    this.canDraw = false,
    this.onPrevious,
    this.onNext,
    this.onAddPage,
    this.onOptions,
    this.onStop,
  });

  /// This device presents the board (the page arrows, + Page, Board options, Stop).
  final bool presenting;
  final int pageIndex;
  final int pageCount;

  /// The viewers' title: "`name`'s whiteboard".
  final String presenterName;

  /// A viewer the host allowed to draw ("You can draw").
  final bool canDraw;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// Null at the page limit.
  final VoidCallback? onAddPage;
  final VoidCallback? onOptions;

  /// The presenter's Stop presenting, or a host stopping a participant's board.
  final VoidCallback? onStop;

  int get pages => pageCount < 1 ? 1 : pageCount;
  bool get hasPrevious => pageIndex > 0;
  bool get hasNext => pageIndex < pages - 1;
  String get pageText => '${pageIndex + 1} / $pages';
  String get pageWords => t('الصفحة ${pageIndex + 1} من $pages', 'Page ${pageIndex + 1} of $pages');

  String get title => presenting || presenterName.isEmpty
      ? t('السبورة البيضاء', 'Whiteboard')
      : t('سبورة $presenterName', "$presenterName's whiteboard");
}

/// `mm:ss`, or `h:mm:ss` from an hour.
String liveClock(Duration d) => LiveTimeLimit.format(d);

class LiveTopRow extends StatelessWidget {
  const LiveTopRow({
    super.key,
    this.onInfo,
    this.liveFor,
    this.limit,
    this.netLowered = false,
    this.netRecovering = false,
    this.locked = false,
    this.onLocked,
    this.recording = const LiveTopRecording(),
    this.board,
    this.onFocus,
    this.focused = false,
    this.onMinimize,
    this.pulse,
  });

  /// (i): the room's info sheet. Null hides it.
  final VoidCallback? onInfo;

  /// How long the room has been live; null hides the LIVE chip (not connected yet).
  final Duration? liveFor;

  /// The free-time countdown; null hides it.
  final LiveTopLimit? limit;

  /// D-090: the video was lowered for a weak connection ([netRecovering]: one step back up already).
  final bool netLowered;
  final bool netRecovering;

  /// The room is locked (hosts); [onLocked] opens the participants panel, where the switch is.
  final bool locked;
  final VoidCallback? onLocked;

  final LiveTopRecording recording;

  /// A whiteboard fills the stage: its title, page and controls join the row (D-108).
  final LiveTopBoard? board;

  /// Full view on / off; null hides the button (nothing fills the stage).
  final VoidCallback? onFocus;

  /// The room is in full view (this row slid in over the content): the button reads "Exit full view".
  final bool focused;

  /// Shrinks the room to the floating box; null hides it (the room was pushed as a plain route).
  final VoidCallback? onMinimize;

  /// The REC blink (0.25–1); null draws a steady dot.
  final Animation<double>? pulse;

  static const double height = 48;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth.isFinite ? box.maxWidth : MediaQuery.sizeOf(context).width;
      final compact = w < kLiveTopRowCompactWidth;
      // A phone with a status pill beside the clock: the LIVE chip drops its (i) glyph (it stays the info button).
      final crowded = compact && (limit != null || netLowered || locked || board != null);
      final b = board;
      final items = <_Item>[
        // ── start ──
        if (liveFor != null)
          _Item(
            'live',
            _LiveChip(liveFor: liveFor!, onInfo: onInfo, compact: compact, glyph: !crowded),
            fallback: _LiveChip(liveFor: liveFor!, onInfo: onInfo, compact: true, glyph: false, tight: true),
            foldAt: 95,
            pinned: true,
          )
        else if (onInfo != null)
          _Item('info', _InfoButton(onTap: onInfo!), pinned: true),
        if (limit != null)
          _Item(
            'limit',
            _LimitChip(limit: limit!, compact: compact),
            fallback: compact ? null : _LimitChip(limit: limit!, compact: true),
            foldAt: 29,
            hideAt: 85,
            menu: [
              _MenuEntry(
                'live_room.top_more.limit',
                Icons.hourglass_bottom_rounded,
                limit!.tone == LiveLimitTone.over
                    ? t('انتهى الوقت المجاني', 'Free time is over')
                    : t('الوقت المجاني المتبقي ${liveClock(limit!.remaining)}', 'Free time left ${liveClock(limit!.remaining)}'),
              ),
              if (limit!.showUpgrade)
                _MenuEntry('live_room.top_more.upgrade', Icons.bolt_rounded, t('ترقية', 'Upgrade'),
                    onTap: limit!.busy ? null : limit!.onUpgrade, color: LivePalette.warning),
            ],
          ),
        if (netLowered)
          _Item(
            'net',
            _NetChip(recovering: netRecovering, compact: compact),
            fallback: compact ? null : _NetChip(recovering: netRecovering, compact: true),
            foldAt: 22,
            hideAt: 30,
            menu: [
              _MenuEntry('live_room.top_more.net', netRecovering ? Icons.network_check_rounded : Icons.speed_rounded,
                  _NetChip.tip(netRecovering), color: LivePalette.warning),
            ],
          ),
        if (locked)
          _Item(
            'locked',
            _LockedChip(onTap: onLocked, compact: compact),
            fallback: compact ? null : _LockedChip(onTap: onLocked, compact: true),
            foldAt: 24,
            hideAt: 35,
            menu: [
              _MenuEntry('live_room.top_more.locked', Icons.lock_rounded, t('الغرفة مقفلة', 'Room locked'),
                  onTap: onLocked, color: LivePalette.warning),
            ],
          ),
        // ── center: the whiteboard ──
        if (b != null) ...[
          _Item('board_title', _BoardTitleChip(title: b.title), group: _Group.center, hideAt: 10),
          if (b.canDraw && !b.presenting)
            _Item(
              'board_can_draw',
              _CanDrawChip(compact: compact),
              fallback: compact ? null : const _CanDrawChip(compact: true),
              group: _Group.center,
              foldAt: 15,
              hideAt: 20,
              menu: [_MenuEntry('live_room.top_more.can_draw', Icons.edit_rounded, t('يمكنك الرسم', 'You can draw'), color: LivePalette.success)],
            ),
          if (b.presenting)
            _Item(
              'board_pager',
              _BoardPager(board: b, compact: compact),
              fallback: _BoardPageChip(board: b, compact: true),
              group: _Group.center,
              foldAt: 60,
              pinned: true,
              menuWhenFolded: true,
              menu: [
                _MenuEntry('live_room.top_more.page_prev', Icons.chevron_left_rounded, t('الصفحة السابقة', 'Previous page'),
                    onTap: b.hasPrevious ? b.onPrevious : null),
                _MenuEntry('live_room.top_more.page_next', Icons.chevron_right_rounded, t('الصفحة التالية', 'Next page'),
                    onTap: b.hasNext ? b.onNext : null),
                if (b.onAddPage != null)
                  _MenuEntry('live_room.top_more.page_add', Icons.add_rounded, t('صفحة جديدة', 'New page'), onTap: b.onAddPage),
              ],
            )
          else
            _Item('board_page', _BoardPageChip(board: b, compact: compact), group: _Group.center, pinned: true),
        ],
        // ── end ──
        if (recording.phase != LiveRecPhase.none)
          _Item(
            'rec',
            _RecordControl(rec: recording, compact: compact, pulse: pulse),
            fallback: compact ? null : _RecordControl(rec: recording, compact: true, pulse: pulse),
            group: _Group.end,
            foldAt: 90,
            pinned: true,
          ),
        if (b != null && b.onOptions != null)
          _Item(
            'board_options',
            _TopChip(
              key: const ValueKey('board.options'),
              icon: Icons.tune_rounded,
              tooltip: t('إعدادات السبورة', 'Board options'),
              onTap: b.onOptions,
            ),
            group: _Group.end,
            hideAt: 40,
            menu: [_MenuEntry('live_room.top_more.board_options', Icons.tune_rounded, t('إعدادات السبورة', 'Board options'), onTap: b.onOptions)],
          ),
        if (b != null && b.onStop != null)
          _Item(
            'board_stop',
            _BoardStopChip(onTap: b.onStop!, compact: compact),
            fallback: compact ? null : _BoardStopChip(onTap: b.onStop!, compact: true),
            group: _Group.end,
            foldAt: 28,
            hideAt: 70,
            menu: [
              _MenuEntry('live_room.top_more.board_stop', Icons.stop_circle_rounded, t('إيقاف العرض', 'Stop presenting'),
                  onTap: b.onStop, color: LivePalette.danger),
            ],
          ),
        if (onFocus != null)
          _Item(
            'focus',
            _FocusChip(onTap: onFocus!, focused: focused, compact: compact),
            fallback: compact ? null : _FocusChip(onTap: onFocus!, focused: focused, compact: true),
            group: _Group.end,
            foldAt: 27,
            hideAt: 55,
            pinned: focused, // in full view it is the way out: never in ⋮
            menu: [
              _MenuEntry(
                'live_room.top_more.focus',
                focused ? Icons.fullscreen_exit_rounded : Icons.fit_screen_rounded,
                focused ? t('الخروج من العرض الكامل', 'Exit full view') : t('عرض كامل', 'Full view'),
                onTap: onFocus,
              ),
            ],
          ),
        if (onMinimize != null)
          _Item(
            'minimize',
            _MinimizeChip(onTap: onMinimize!, compact: compact),
            fallback: compact ? null : _MinimizeChip(onTap: onMinimize!, compact: true),
            group: _Group.end,
            foldAt: 26,
            hideAt: 50,
            menu: [
              _MenuEntry('live_room.top_more.minimize', Icons.close_fullscreen_rounded, t('تصغير', 'Minimize'), onTap: onMinimize),
            ],
          ),
      ];
      final fold = _Fold(items);
      final children = <Widget>[
        for (final i in items) ...[i.child, ?i.fallback],
        _MoreButton(fold: fold),
      ];
      return SizedBox(
        key: const ValueKey('live_room.top_row'),
        height: height,
        child: _FoldRow(
          fold: fold,
          height: height,
          gap: compact ? 4 : 6,
          groupGap: compact ? 8 : 12,
          textDirection: Directionality.of(context),
          children: children,
        ),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The one-line fitting (D-108)
// ─────────────────────────────────────────────────────────────────────────────

enum _Group { start, center, end }

/// A line of the ⋮ menu. A null [onTap] is an information line (drawn, not tappable).
class _MenuEntry {
  const _MenuEntry(this.key, this.icon, this.label, {this.onTap, this.color});
  final String key;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
}

/// One piece of the row. It folds in two steps, each when its priority comes (the lowest first): at [foldAt] it
/// is drawn as [fallback] (a label dropped, a pager shrunk to the page number), at [hideAt] it leaves the row for
/// the ⋮ menu ([menu]). A [pinned] piece never leaves the row.
class _Item {
  const _Item(
    this.id,
    this.child, {
    this.fallback,
    this.group = _Group.start,
    this.foldAt = 0,
    this.hideAt = 0,
    this.pinned = false,
    this.menuWhenFolded = false,
    this.menu = const [],
  });

  final String id;
  final Widget child;
  final Widget? fallback;
  final _Group group;
  final int foldAt;
  final int hideAt;
  final bool pinned;

  /// The fallback drops actions (the pager's arrows): its [menu] is offered while folded too.
  final bool menuWhenFolded;
  final List<_MenuEntry> menu;
}

/// What the layout decided (0 = shown, 1 = folded, 2 = in the menu), per item; written by [_RenderFoldRow] during
/// layout and read by the ⋮ button when it is tapped.
class _Fold {
  _Fold(this.items) : stage = List<int>.filled(items.length, 0);
  final List<_Item> items;
  final List<int> stage;

  List<_MenuEntry> get menu => [
        for (var i = 0; i < items.length; i++)
          if (stage[i] == 2 || (stage[i] == 1 && items[i].menuWhenFolded)) ...items[i].menu,
      ];

  /// The ⋮ button is drawn.
  bool get anyInMenu => menu.isNotEmpty;
}

class _FoldRow extends MultiChildRenderObjectWidget {
  const _FoldRow({
    required this.fold,
    required this.height,
    required this.gap,
    required this.groupGap,
    required this.textDirection,
    required super.children,
  });

  final _Fold fold;
  final double height;
  final double gap;
  final double groupGap;
  final TextDirection textDirection;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFoldRow(fold: fold, height: height, gap: gap, groupGap: groupGap, textDirection: textDirection);

  @override
  void updateRenderObject(BuildContext context, _RenderFoldRow renderObject) {
    renderObject
      ..fold = fold
      ..rowHeight = height
      ..gap = gap
      ..groupGap = groupGap
      ..textDirection = textDirection;
  }
}

class _FoldParentData extends ContainerBoxParentData<RenderBox> {
  bool shown = false;
}

class _RenderFoldRow extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _FoldParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _FoldParentData> {
  _RenderFoldRow({
    required _Fold fold,
    required double height,
    required double gap,
    required double groupGap,
    required TextDirection textDirection,
  })  : _fold = fold,
        _height = height,
        _gap = gap,
        _groupGap = groupGap,
        _dir = textDirection;

  _Fold _fold;
  set fold(_Fold v) {
    if (identical(v, _fold)) return;
    _fold = v;
    markNeedsLayout();
  }

  double _height;
  set rowHeight(double v) {
    if (v == _height) return;
    _height = v;
    markNeedsLayout();
  }

  double _gap;
  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  double _groupGap;
  set groupGap(double v) {
    if (v == _groupGap) return;
    _groupGap = v;
    markNeedsLayout();
  }

  TextDirection _dir;
  set textDirection(TextDirection v) {
    if (v == _dir) return;
    _dir = v;
    markNeedsLayout();
  }

  /// The last-resort shrink (null: drawn at full size).
  Matrix4? _matrix;
  final LayerHandle<TransformLayer> _layer = LayerHandle<TransformLayer>();

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FoldParentData) child.parentData = _FoldParentData();
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) {
    // The full pieces only (not the fallbacks, not ⋮).
    var sum = 0.0;
    var c = firstChild;
    for (final it in _fold.items) {
      if (c == null) break;
      sum += c.getMaxIntrinsicWidth(_height);
      c = childAfter(c);
      if (it.fallback != null && c != null) c = childAfter(c);
    }
    return sum + _groupGap * 2 + _gap * math.max(0, _fold.items.length - 1);
  }

  @override
  double computeMinIntrinsicHeight(double width) => _height;

  @override
  double computeMaxIntrinsicHeight(double width) => _height;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.constrain(Size(constraints.maxWidth.isFinite ? constraints.maxWidth : getMaxIntrinsicWidth(_height), _height));

  @override
  void performLayout() {
    final items = _fold.items;
    final stage = _fold.stage;
    final h = constraints.constrainHeight(_height);
    final full = <RenderBox>[];
    final fallback = <RenderBox?>[];
    var c = firstChild;
    for (final it in items) {
      full.add(c!);
      c = childAfter(c);
      if (it.fallback != null) {
        fallback.add(c);
        c = childAfter(c!);
      } else {
        fallback.add(null);
      }
    }
    final more = c!;
    final loose = BoxConstraints(maxHeight: h);
    var k = firstChild;
    while (k != null) {
      k.layout(loose, parentUsesSize: true);
      (k.parentData! as _FoldParentData).shown = false;
      k = childAfter(k);
    }
    for (var i = 0; i < stage.length; i++) {
      stage[i] = 0;
    }

    double widthOf(int i) => switch (stage[i]) {
          0 => full[i].size.width,
          1 => fallback[i]!.size.width,
          _ => 0,
        };
    bool menu() => _fold.anyInMenu;
    double total() {
      var sum = 0.0;
      var n = 0;
      final groups = <_Group>{};
      for (var i = 0; i < items.length; i++) {
        if (stage[i] == 2) continue;
        sum += widthOf(i);
        n++;
        groups.add(items[i].group);
      }
      if (menu()) {
        sum += more.size.width;
        n++;
        groups.add(_Group.end);
      }
      return sum + _gap * math.max(0, n - 1) + (_groupGap - _gap) * math.max(0, groups.length - 1);
    }

    final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : total();
    // Fold the lowest priority step first until the line fits.
    while (total() > maxW + 0.5) {
      int? pick;
      var pickAt = 0;
      for (var i = 0; i < items.length; i++) {
        final it = items[i];
        int? at;
        if (stage[i] == 0 && it.fallback != null) {
          at = it.foldAt;
        } else if (stage[i] < 2 && !it.pinned) {
          at = it.hideAt;
        }
        if (at == null) continue;
        if (pick == null || at < pickAt || (at == pickAt && i > pick)) {
          pick = i;
          pickAt = at;
        }
      }
      if (pick == null) break;
      stage[pick] = stage[pick] == 0 && items[pick].fallback != null ? 1 : 2;
    }

    final need = total();
    final vw = math.max(maxW, need);
    final scale = need > maxW + 0.5 && need > 0 ? maxW / need : 1.0;
    _matrix = scale < 1 ? (Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(0, h * (1 - scale) / 2, 0)) : null;

    // The pieces drawn, per group, in order.
    final groups = {for (final g in _Group.values) g: <RenderBox>[]};
    for (var i = 0; i < items.length; i++) {
      final box = switch (stage[i]) {
        0 => full[i],
        1 => fallback[i],
        _ => null,
      };
      if (box != null) groups[items[i].group]!.add(box);
    }
    if (menu()) groups[_Group.end]!.add(more);

    double span(List<RenderBox> l) =>
        l.isEmpty ? 0 : l.fold<double>(0, (s, b) => s + b.size.width) + _gap * (l.length - 1);

    void place(List<RenderBox> l, double from) {
      var x = from;
      for (final b in l) {
        final pd = b.parentData! as _FoldParentData;
        final left = _dir == TextDirection.rtl ? vw - x - b.size.width : x;
        pd.offset = Offset(left, (h - b.size.height) / 2);
        pd.shown = true;
        x += b.size.width + _gap;
      }
    }

    final start = groups[_Group.start]!;
    final center = groups[_Group.center]!;
    final end = groups[_Group.end]!;
    final startW = span(start);
    final centerW = span(center);
    final endW = span(end);
    place(start, 0);
    final endFrom = vw - endW;
    place(end, endFrom);
    if (center.isNotEmpty) {
      final lo = start.isEmpty ? 0.0 : startW + _groupGap;
      final hi = end.isEmpty ? vw - centerW : endFrom - _groupGap - centerW;
      final ideal = (vw - centerW) / 2;
      place(center, hi < lo ? lo : ideal.clamp(lo, hi));
    }
    size = constraints.constrain(Size(maxW, h));
  }

  bool _shown(RenderBox child) => (child.parentData! as _FoldParentData).shown;

  @override
  bool paintsChild(RenderBox child) => _shown(child);

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (_matrix != null) transform.multiply(_matrix!);
    final o = (child.parentData! as _FoldParentData).offset;
    transform.translateByDouble(o.dx, o.dy, 0, 1);
  }

  void _paintKids(PaintingContext context, Offset offset) {
    var c = firstChild;
    while (c != null) {
      final pd = c.parentData! as _FoldParentData;
      if (pd.shown) context.paintChild(c, offset + pd.offset);
      c = pd.nextSibling;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final m = _matrix;
    if (m == null) {
      _layer.layer = null;
      _paintKids(context, offset);
      return;
    }
    _layer.layer = context.pushTransform(needsCompositing, offset, m, _paintKids, oldLayer: _layer.layer);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintTransform(
        transform: _matrix,
        position: position,
        hitTest: (r, p) {
          var c = lastChild;
          while (c != null) {
            final child = c;
            final pd = child.parentData! as _FoldParentData;
            if (pd.shown && r.addWithPaintOffset(offset: pd.offset, position: p, hitTest: (r2, q) => child.hitTest(r2, position: q))) {
              return true;
            }
            c = pd.previousSibling;
          }
          return false;
        },
      );

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    var c = firstChild;
    while (c != null) {
      if (_shown(c)) visitor(c);
      c = childAfter(c);
    }
  }

  @override
  void dispose() {
    _layer.layer = null;
    super.dispose();
  }
}

/// ⋮ — what the line had no room for (drawn only while something is in it).
class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.fold});
  final _Fold fold;

  Future<void> _open(BuildContext anchor) async {
    final entries = fold.menu;
    if (entries.isEmpty) return;
    final picked = await _showTopMenu<int>(anchor, [
      for (var i = 0; i < entries.length; i++)
        PopupMenuItem<int>(
          key: ValueKey(entries[i].key),
          value: i,
          enabled: entries[i].onTap != null,
          height: 48,
          child: Row(children: [
            Icon(entries[i].icon, size: 20, color: entries[i].color ?? LivePalette.textHigh),
            const SizedBox(width: 12),
            Flexible(
              child: Text(entries[i].label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _label(entries[i].onTap == null ? LivePalette.textMid : LivePalette.textHigh, size: 14, w: FontWeight.w700)),
            ),
          ]),
        ),
    ]);
    if (picked != null) entries[picked].onTap?.call();
  }

  @override
  Widget build(BuildContext context) => _TopChip(
        key: const ValueKey('live_room.top_more'),
        icon: Icons.more_vert_rounded,
        tooltip: t('المزيد', 'More'),
        onTapAnchor: _open,
      );
}

/// A menu under [anchor], aligned with its end edge (the row's menus).
Future<T?> _showTopMenu<T>(BuildContext anchor, List<PopupMenuEntry<T>> items) {
  final box = anchor.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return Future.value();
  final rtl = Directionality.of(anchor) == TextDirection.rtl;
  final rect = MatrixUtils.transformRect(box.getTransformTo(overlay), Offset.zero & box.size);
  final position = RelativeRect.fromLTRB(
    rtl ? rect.left : rect.right - 1,
    rect.bottom,
    rtl ? overlay.size.width - rect.left - 1 : overlay.size.width - rect.right,
    0,
  );
  return showMenu<T>(
    context: anchor,
    color: LivePalette.surfaceHi,
    elevation: 20,
    constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: LivePalette.glassBorder)),
    position: position,
    items: items,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// The end pieces and the board's pieces
// ─────────────────────────────────────────────────────────────────────────────

class _FocusChip extends StatelessWidget {
  const _FocusChip({required this.onTap, required this.focused, required this.compact});
  final VoidCallback onTap;
  final bool focused;
  final bool compact;

  @override
  Widget build(BuildContext context) => focused
      ? _TopChip(
          key: const ValueKey('live_room.focus_exit'),
          icon: Icons.fullscreen_exit_rounded,
          label: compact ? null : t('خروج', 'Exit'),
          dense: compact,
          tooltip: t('الخروج من العرض الكامل (Esc)', 'Exit full view (Esc)'),
          onTap: onTap,
        )
      : _TopChip(
          key: const ValueKey('live_room.focus'),
          icon: Icons.fit_screen_rounded,
          label: compact ? null : t('عرض كامل', 'Full view'),
          dense: compact,
          tooltip: t('عرض المحتوى على الشاشة كلها (F)', 'Show the content on the whole screen (F)'),
          onTap: onTap,
        );
}

class _MinimizeChip extends StatelessWidget {
  const _MinimizeChip({required this.onTap, required this.compact});
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => _TopChip(
        key: const ValueKey('live_room.minimize'),
        icon: Icons.close_fullscreen_rounded,
        label: compact ? null : t('تصغير', 'Minimize'),
        dense: compact,
        tooltip: t('تصغير الغرفة ومتابعة استخدام التطبيق', 'Minimize the room and keep using the app'),
        onTap: onTap,
      );
}

/// ✎ Whiteboard / "Sara's whiteboard" (a label, not a button).
class _BoardTitleChip extends StatelessWidget {
  const _BoardTitleChip({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => _TopChip(
        key: const ValueKey('board.title'),
        tooltip: title,
        fill: Colors.transparent,
        border: Colors.transparent,
        flat: true,
        lead: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [LivePalette.accent, LivePalette.accent2]),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.draw_rounded, size: 15, color: LivePalette.textHigh),
        ),
        parts: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: _label(LivePalette.textHigh, w: FontWeight.w700)),
          ),
        ],
      );
}

class _CanDrawChip extends StatelessWidget {
  const _CanDrawChip({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = LivePalette.success;
    return _TopChip(
      key: const ValueKey('board.can_draw'),
      icon: Icons.edit_rounded,
      label: compact ? null : t('يمكنك الرسم', 'You can draw'),
      dense: compact,
      ink: c,
      border: c.withValues(alpha: 0.55),
      tooltip: t('يمكنك الرسم والكتابة على السبورة', 'You can draw and write on the whiteboard'),
    );
  }
}

/// "2 / 3" — the page everyone is on (a viewer's, or the presenter's when the arrows went into ⋮).
class _BoardPageChip extends StatelessWidget {
  const _BoardPageChip({required this.board, required this.compact});
  final LiveTopBoard board;
  final bool compact;

  @override
  Widget build(BuildContext context) => _TopChip(
        key: const ValueKey('board.page_label'),
        icon: compact ? null : Icons.description_outlined,
        dense: true,
        tooltip: board.pageWords,
        parts: [Text(board.pageText, maxLines: 1, textDirection: TextDirection.ltr, style: _label(LivePalette.textHigh, w: FontWeight.w700))],
      );
}

/// The presenter's ‹ 2 / 3 › | + Page — one 40 px pill whose buttons are 48 px targets.
class _BoardPager extends StatelessWidget {
  const _BoardPager({required this.board, required this.compact});
  final LiveTopBoard board;
  final bool compact;

  Widget _button(String key, String label, VoidCallback? onTap, Widget child, {double width = 44}) => Semantics(
        button: true,
        enabled: onTap != null,
        label: label,
        excludeSemantics: true,
        child: Tooltip(
          message: label,
          waitDuration: const Duration(milliseconds: 400),
          child: InkResponse(
            key: ValueKey(key),
            onTap: onTap,
            radius: 22,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: width, minHeight: 48),
              child: Center(widthFactor: 1, child: child),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final b = board;
    final canAdd = b.onAddPage != null;
    return SizedBox(
      height: 48,
      child: Stack(children: [
        Positioned.fill(
          top: 4,
          bottom: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _chipFill,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: LivePalette.glassBorder),
              boxShadow: [BoxShadow(color: LivePalette.shade(0.28), blurRadius: 12, offset: const Offset(0, 3))],
            ),
          ),
        ),
        Material(
          type: MaterialType.transparency,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _button('board.page_prev', t('الصفحة السابقة', 'Previous page'), b.hasPrevious ? b.onPrevious : null,
                Icon(Icons.chevron_left_rounded, size: 24, color: b.hasPrevious ? LivePalette.textHigh : LivePalette.textLow)),
            Semantics(
              label: b.pageWords,
              excludeSemantics: true,
              child: Text(b.pageText, key: const ValueKey('board.page_label'), maxLines: 1, textDirection: TextDirection.ltr, style: _label(LivePalette.textHigh, w: FontWeight.w700)),
            ),
            _button('board.page_next', t('الصفحة التالية', 'Next page'), b.hasNext ? b.onNext : null,
                Icon(Icons.chevron_right_rounded, size: 24, color: b.hasNext ? LivePalette.textHigh : LivePalette.textLow)),
            Container(width: 1, height: 22, color: LivePalette.ink(0.16)),
            _button(
              'board.page_add',
              t('صفحة جديدة', 'New page'),
              b.onAddPage,
              Padding(
                padding: EdgeInsetsDirectional.only(start: compact ? 0 : 8, end: compact ? 0 : 12),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_rounded, size: 20, color: canAdd ? LivePalette.textHigh : LivePalette.textLow),
                  if (!compact) ...[
                    const SizedBox(width: 4),
                    Text(t('صفحة', 'Page'), maxLines: 1, style: _label(canAdd ? LivePalette.textHigh : LivePalette.textLow, w: FontWeight.w700)),
                  ],
                ]),
              ),
              width: 48,
            ),
          ]),
        ),
      ]),
    );
  }
}

class _BoardStopChip extends StatelessWidget {
  const _BoardStopChip({required this.onTap, required this.compact});
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => _TopChip(
        key: const ValueKey('board.stop'),
        icon: Icons.stop_rounded,
        label: compact ? null : t('إيقاف العرض', 'Stop presenting'),
        dense: compact,
        tooltip: t('إيقاف عرض السبورة', 'Stop presenting the whiteboard'),
        fill: LivePalette.danger,
        border: LivePalette.danger,
        glow: LivePalette.danger.withValues(alpha: 0.3),
        onTap: onTap,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Pieces
// ─────────────────────────────────────────────────────────────────────────────

TextStyle _label(Color c, {double size = 13, FontWeight w = FontWeight.w800, double spacing = 0.1}) => TextStyle(
      fontFamily: AppFonts.family,
      fontSize: size,
      height: 1.15,
      fontWeight: w,
      color: c,
      letterSpacing: spacing,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

Color get _chipFill => LivePalette.surfaceHi.withValues(alpha: 0.88);

/// One chip of the row: a 40 px pill (a 40 px circle with an icon alone) inside a 48 px target, hover and press
/// washes, a tooltip, one semantics node.
class _TopChip extends StatefulWidget {
  const _TopChip({
    super.key,
    this.icon,
    this.lead,
    this.label,
    this.parts,
    this.trail,
    this.tooltip,
    this.onTap,
    this.onTapAnchor,
    this.fill,
    this.border,
    this.ink,
    this.glow,
    this.dense = false,
    this.flat = false,
  });

  /// No shadow (a label on the row, not a control).
  final bool flat;

  final IconData? icon;

  /// Drawn before [icon] / [label] (a dot, a spinner, a tag).
  final Widget? lead;
  final String? label;

  /// Replaces [label] (several texts).
  final List<Widget>? parts;
  final Widget? trail;
  final String? tooltip;
  final VoidCallback? onTap;

  /// A tap that needs the chip's own context (a menu anchored under it).
  final void Function(BuildContext anchor)? onTapAnchor;
  final Color? fill;
  final Color? border;
  final Color? ink;
  final Color? glow;

  /// Phones: tighter padding.
  final bool dense;

  @override
  State<_TopChip> createState() => _TopChipState();
}

class _TopChipState extends State<_TopChip> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final ink = w.ink ?? LivePalette.textHigh;
    final tappable = w.onTap != null || w.onTapAnchor != null;
    final iconOnly = w.label == null && w.parts == null && w.lead == null && w.trail == null;
    final base = w.fill ?? _chipFill;
    final fill = !tappable
        ? base
        : _down
            ? Color.alphaBlend(LivePalette.ink(0.14), base)
            : _hover
                ? Color.alphaBlend(LivePalette.ink(0.08), base)
                : base;
    final inner = w.dense ? 6.0 : 7.0;
    final content = <Widget>[
      if (w.lead != null) w.lead!,
      if (w.lead != null && (w.icon != null || w.label != null || w.parts != null)) SizedBox(width: inner),
      if (w.icon != null) Icon(w.icon, size: 18, color: ink),
      if (w.icon != null && (w.label != null || w.parts != null)) SizedBox(width: inner),
      if (w.parts != null) ...w.parts!,
      // No Flexible: the row lays every chip out at its natural width and folds what does not fit (D-108).
      if (w.label != null) Text(w.label!, maxLines: 1, style: _label(ink)),
      if (w.trail != null) ...[const SizedBox(width: 4), w.trail!],
    ];
    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      height: 40,
      width: iconOnly ? 40 : null,
      padding: iconOnly ? null : EdgeInsets.symmetric(horizontal: w.dense ? 10 : 13),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: w.border ?? LivePalette.glassBorder),
        boxShadow: [
          if (!w.flat) BoxShadow(color: LivePalette.shade(0.28), blurRadius: 12, offset: const Offset(0, 3)),
          if (w.glow != null) BoxShadow(color: w.glow!, blurRadius: 14),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: content),
    );
    Widget target = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      child: Center(widthFactor: 1, child: chip),
    );
    if (tappable) {
      target = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: w.onTapAnchor != null ? () => w.onTapAnchor!(context) : w.onTap,
          child: target,
        ),
      );
    }
    final label = w.tooltip ?? w.label ?? '';
    target = Semantics(button: tappable, label: label, excludeSemantics: true, child: target);
    if (w.tooltip == null) return target;
    return Tooltip(message: w.tooltip!, waitDuration: const Duration(milliseconds: 400), child: target);
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.size = 10, this.opacity = 1});
  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.35 + 0.65 * opacity),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.55 * opacity), blurRadius: 8)],
        ),
      );
}

/// A dot that follows [pulse] (steady without one).
class _PulseDot extends StatelessWidget {
  const _PulseDot({required this.color, this.pulse});
  final Color color;
  final Animation<double>? pulse;

  @override
  Widget build(BuildContext context) {
    final p = pulse;
    if (p == null) return _Dot(color: color);
    return AnimatedBuilder(animation: p, builder: (_, _) => _Dot(color: color, opacity: p.value));
  }
}

Widget _spinner(Color c) => SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: c));

class _InfoButton extends StatelessWidget {
  const _InfoButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _TopChip(
        key: const ValueKey('live_room.info'),
        icon: Icons.info_outline_rounded,
        tooltip: t('عن الغرفة', 'About this room'),
        onTap: onTap,
      );
}

/// ⓘ LIVE 12:34 — how long the room has been live; with [onInfo], the chip is the room's info button too.
class _LiveChip extends StatelessWidget {
  const _LiveChip({required this.liveFor, required this.compact, this.onInfo, this.glyph = true, this.tight = false});
  final Duration liveFor;
  final bool compact;
  final VoidCallback? onInfo;

  /// The (i) glyph of the info button (dropped on a crowded phone row; the chip still opens the info sheet).
  final bool glyph;

  /// The narrowest form (a crowded 320 px line, D-108): a red dot instead of the LIVE tag.
  final bool tight;

  @override
  Widget build(BuildContext context) {
    final clock = liveClock(liveFor);
    final live = t('مباشر منذ $clock', 'Live for $clock');
    return _TopChip(
      key: ValueKey(onInfo != null ? 'live_room.info' : 'live_room.live_chip'),
      tooltip: onInfo != null ? '$live · ${t('عن الغرفة', 'About this room')}' : live,
      dense: compact,
      lead: onInfo != null && glyph ? Icon(Icons.info_outline_rounded, size: 17, color: LivePalette.ink(0.78)) : null,
      parts: [
        if (tight)
          _Dot(color: LivePalette.danger, size: 8)
        else
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(color: LivePalette.danger, borderRadius: BorderRadius.circular(6)),
          child: Text(t('مباشر', 'LIVE'), style: _label(LivePalette.textHigh, size: 10.5, w: FontWeight.w900, spacing: 0.8)),
        ),
        SizedBox(width: compact ? 6 : 8),
        Text(clock, key: const ValueKey('live_room.live_time'), maxLines: 1, style: _label(LivePalette.textHigh)),
      ],
      onTap: onInfo,
    );
  }
}

class _LimitChip extends StatelessWidget {
  const _LimitChip({required this.limit, required this.compact});
  final LiveTopLimit limit;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = limit;
    final color = switch (l.tone) {
      LiveLimitTone.calm => LivePalette.textHigh,
      LiveLimitTone.warn => LivePalette.warning,
      LiveLimitTone.over => LivePalette.danger,
    };
    final over = l.tone == LiveLimitTone.over;
    final clock = liveClock(l.remaining);
    final text = over
        ? (compact ? '00:00' : t('انتهى الوقت المجاني', 'Free time is over'))
        : (compact ? clock : '${t('الوقت المجاني', 'Free time')} $clock');
    final upgradeInk = LivePalette.shade(0.85);
    final upgrade = l.showUpgrade && compact
        ? Container(
            key: const ValueKey('live_room.time_limit.upgrade'),
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: LivePalette.warning, shape: BoxShape.circle),
            child: Center(
              child: l.busy
                  ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: upgradeInk))
                  : Icon(Icons.bolt_rounded, size: 17, color: upgradeInk),
            ),
          )
        : l.showUpgrade
        ? Container(
            key: const ValueKey('live_room.time_limit.upgrade'),
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: LivePalette.warning, borderRadius: BorderRadius.circular(14)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (l.busy)
                SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: LivePalette.shade(0.85)))
              else
                Icon(Icons.bolt_rounded, size: 15, color: LivePalette.shade(0.85)),
              const SizedBox(width: 4),
              Text(t('ترقية', 'Upgrade'), style: _label(LivePalette.shade(0.85), size: 12, w: FontWeight.w900)),
            ]),
          )
        : null;
    return _TopChip(
      key: const ValueKey('live_room.time_limit'),
      icon: compact && l.showUpgrade ? null : Icons.hourglass_bottom_rounded,
      dense: compact,
      ink: color,
      border: l.tone == LiveLimitTone.calm ? null : color.withValues(alpha: 0.6),
      tooltip: [
        over ? t('انتهى الوقت المجاني', 'Free time is over') : t('الوقت المجاني المتبقي $clock', 'Free time left $clock'),
        if (l.showUpgrade) t('ترقية', 'Upgrade'),
      ].join(' · '),
      parts: [Text(text, maxLines: 1, style: _label(color))],
      trail: upgrade == null ? null : Padding(padding: const EdgeInsetsDirectional.only(start: 4), child: upgrade),
      onTap: l.showUpgrade && !l.busy ? l.onUpgrade : null,
    );
  }
}

class _NetChip extends StatelessWidget {
  const _NetChip({required this.recovering, required this.compact});
  final bool recovering;
  final bool compact;

  static String tip(bool recovering) => recovering
      ? t('الاتصال يتحسّن — تعود الجودة تدريجيًا', 'Connection improving — quality coming back')
      : t('الاتصال ضعيف — خُفِّضت جودة الفيديو', 'Poor connection — video quality lowered');

  @override
  Widget build(BuildContext context) {
    final color = LivePalette.warning;
    return Semantics(
      liveRegion: true,
      child: _TopChip(
        key: const ValueKey('live_room.net_pill'),
        icon: recovering ? Icons.network_check_rounded : Icons.speed_rounded,
        label: compact ? null : (recovering ? t('يتحسّن', 'Improving') : t('اتصال ضعيف', 'Weak connection')),
        dense: compact,
        ink: color,
        border: color.withValues(alpha: 0.55),
        tooltip: tip(recovering),
      ),
    );
  }
}

class _LockedChip extends StatelessWidget {
  const _LockedChip({required this.onTap, required this.compact});
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = LivePalette.warning;
    return _TopChip(
      key: const ValueKey('live_room.locked'),
      icon: Icons.lock_rounded,
      label: compact ? null : t('مقفلة', 'Locked'),
      dense: compact,
      ink: color,
      border: color.withValues(alpha: 0.55),
      tooltip: t('الغرفة مقفلة', 'Room locked'),
      onTap: onTap,
    );
  }
}

enum _RecAction { pause, resume, stop }

/// The recording control (see the header).
class _RecordControl extends StatelessWidget {
  const _RecordControl({required this.rec, required this.compact, this.pulse});
  final LiveTopRecording rec;
  final bool compact;
  final Animation<double>? pulse;

  String get _stateText => switch (rec.phase) {
        LiveRecPhase.recording => t('يُسجَّل', 'Recording'),
        LiveRecPhase.paused => t('التسجيل متوقف مؤقتًا', 'Recording paused'),
        LiveRecPhase.starting => t('جارٍ بدء التسجيل…', 'Starting the recording…'),
        LiveRecPhase.uploading => t('جارٍ رفع التسجيل…', 'Uploading the recording…'),
        LiveRecPhase.saved => t('حُفظ التسجيل', 'Recording saved'),
        LiveRecPhase.error => t('تعذّر التسجيل', 'Recording failed'),
        LiveRecPhase.server => t('هذه الجلسة تُسجَّل', 'This session is being recorded'),
        LiveRecPhase.offer => t('لا يُسجَّل بعد · اضغط لبدء التسجيل', 'Not recording yet · tap to start recording'),
        LiveRecPhase.none => '',
      };

  Future<void> _openMenu(BuildContext anchor) async {
    final box = anchor.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final rtl = Directionality.of(anchor) == TextDirection.rtl;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottom = topLeft.dy + box.size.height;
    final position = RelativeRect.fromLTRB(
      rtl ? topLeft.dx : topLeft.dx + box.size.width - 1,
      bottom,
      rtl ? overlay.size.width - topLeft.dx - 1 : overlay.size.width - topLeft.dx - box.size.width,
      0,
    );
    final paused = rec.phase == LiveRecPhase.paused;
    final ink = paused ? LivePalette.warning : LivePalette.danger;
    PopupMenuItem<_RecAction> item(_RecAction a, String key, IconData icon, String label, VoidCallback? cb, Color c) =>
        PopupMenuItem<_RecAction>(
          key: ValueKey(key),
          value: a,
          enabled: cb != null,
          height: 48,
          child: Row(children: [
            Icon(icon, size: 20, color: cb == null ? LivePalette.textLow : c),
            const SizedBox(width: 12),
            Flexible(child: Text(label, style: _label(cb == null ? LivePalette.textLow : LivePalette.textHigh, size: 14, w: FontWeight.w700))),
          ]),
        );
    final picked = await showMenu<_RecAction>(
      context: anchor,
      color: LivePalette.surfaceHi,
      elevation: 20,
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: LivePalette.glassBorder)),
      position: position,
      items: [
        PopupMenuItem<_RecAction>(
          enabled: false,
          height: 52,
          child: Row(children: [
            paused ? Icon(Icons.pause_rounded, size: 18, color: ink) : _Dot(color: ink, size: 10),
            const SizedBox(width: 10),
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$_stateText${rec.timed ? ' · ${liveClock(rec.elapsed)}' : ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: _label(LivePalette.textHigh, size: 13)),
                if (rec.detail != null)
                  Text(rec.detail!, maxLines: 1, overflow: TextOverflow.ellipsis, style: _label(LivePalette.textSoft, size: 11.5, w: FontWeight.w600)),
              ]),
            ),
          ]),
        ),
        const PopupMenuDivider(height: 1),
        if (rec.phase == LiveRecPhase.recording)
          item(_RecAction.pause, 'live_room.rec_menu.pause', Icons.pause_circle_outline_rounded, t('إيقاف مؤقت للتسجيل', 'Pause recording'),
              rec.onPause, LivePalette.warning),
        if (rec.phase == LiveRecPhase.paused)
          item(_RecAction.resume, 'live_room.rec_menu.resume', Icons.play_circle_outline_rounded, t('استئناف التسجيل', 'Resume recording'),
              rec.onResume, LivePalette.success),
        if (rec.onStop != null)
          item(_RecAction.stop, 'live_room.rec_menu.stop', Icons.stop_circle_rounded, t('إيقاف التسجيل', 'Stop recording'), rec.onStop,
              LivePalette.danger),
      ],
    );
    switch (picked) {
      case _RecAction.pause:
        rec.onPause?.call();
      case _RecAction.resume:
        rec.onResume?.call();
      case _RecAction.stop:
        rec.onStop?.call();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = rec;
    final danger = LivePalette.danger;
    final amber = LivePalette.warning;
    final chevron = Icon(Icons.expand_more_rounded, size: 18, color: LivePalette.ink(0.8));
    final clock = Text(liveClock(r.elapsed), maxLines: 1, style: _label(LivePalette.textHigh));
    switch (r.phase) {
      case LiveRecPhase.none:
        return const SizedBox.shrink();
      case LiveRecPhase.offer:
        // D-313: from the first second the recording shows its state — paused / not recording yet (the amber pause
        // glyph) — with the one tap that starts it (● Record). Nothing records before that tap.
        return _TopChip(
          key: const ValueKey('live_room.record'),
          lead: r.busy ? _spinner(amber) : Icon(Icons.pause_rounded, size: 18, color: amber),
          parts: [
            if (!compact) ...[
              Text(t('لا يُسجَّل', 'Not recording'), maxLines: 1, style: _label(amber, spacing: 0.2)),
              const SizedBox(width: 8),
            ],
            _Dot(color: danger, size: 9),
            const SizedBox(width: 6),
            Text(t('تسجيل', 'Record'), maxLines: 1, style: _label(LivePalette.textHigh)),
          ],
          dense: compact,
          tooltip: _stateText,
          fill: Color.alphaBlend(amber.withValues(alpha: 0.14), _chipFill),
          border: amber.withValues(alpha: 0.55),
          onTap: r.busy ? null : r.onRecord,
        );
      case LiveRecPhase.server:
        return _TopChip(
          key: const ValueKey('live_room.rec_server'),
          lead: _PulseDot(color: danger, pulse: pulse),
          label: t('يُسجَّل', 'REC'),
          dense: compact,
          tooltip: _stateText,
          ink: danger,
          fill: Color.alphaBlend(danger.withValues(alpha: 0.16), _chipFill),
          border: danger.withValues(alpha: 0.5),
        );
      case LiveRecPhase.recording:
      case LiveRecPhase.paused:
        final paused = r.phase == LiveRecPhase.paused;
        final c = paused ? amber : danger;
        return _TopChip(
          key: const ValueKey('live_room.rec_control'),
          lead: r.busy ? _spinner(c) : (paused ? Icon(Icons.pause_rounded, size: 18, color: c) : _PulseDot(color: c, pulse: pulse)),
          parts: [
            if (!compact) ...[
              Text(paused ? t('متوقف مؤقتًا', 'Paused') : t('يُسجَّل', 'REC'), maxLines: 1, style: _label(c, spacing: paused ? 0.2 : 0.8)),
              const SizedBox(width: 8),
            ],
            clock,
          ],
          // Phones: no chevron (every pixel counts; the tap still opens the menu).
          trail: r.hasMenu && !compact ? chevron : null,
          dense: compact,
          tooltip: '$_stateText · ${liveClock(r.elapsed)}',
          fill: Color.alphaBlend(c.withValues(alpha: 0.20), _chipFill),
          border: c.withValues(alpha: 0.65),
          glow: paused ? null : danger.withValues(alpha: 0.22),
          onTapAnchor: r.hasMenu && !r.busy ? _openMenu : null,
        );
      case LiveRecPhase.starting:
      case LiveRecPhase.uploading:
        final c = r.phase == LiveRecPhase.starting ? LivePalette.textHigh : amber;
        return _TopChip(
          key: const ValueKey('live_room.rec_control'),
          lead: _spinner(c),
          label: compact ? null : (r.phase == LiveRecPhase.starting ? t('جارٍ البدء…', 'Starting…') : t('جارٍ الرفع…', 'Uploading…')),
          tooltip: _stateText,
          ink: c,
          trail: r.hasMenu ? chevron : null,
          onTapAnchor: r.hasMenu ? _openMenu : null,
        );
      case LiveRecPhase.saved:
      case LiveRecPhase.error:
        final ok = r.phase == LiveRecPhase.saved;
        final c = ok ? LivePalette.success : danger;
        return _TopChip(
          key: const ValueKey('live_room.rec_control'),
          icon: ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          label: compact ? null : (ok ? t('حُفظ', 'Saved') : t('خطأ في التسجيل', 'Recording error')),
          tooltip: _stateText,
          ink: c,
          border: c.withValues(alpha: 0.55),
        );
    }
  }
}
