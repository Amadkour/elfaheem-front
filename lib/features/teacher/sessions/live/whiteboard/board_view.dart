// lib/features/teacher/sessions/live/whiteboard/board_view.dart
//
// The whiteboard as the room's stage (D-087): WhiteboardRoomView = the bar over the page (WhiteboardTopBar), the
// page (WhiteboardStage) and, for whoever may draw, the tool dock (WhiteboardToolbar) — bound to a BoardController.
// In the live room the bar is off (`showTopBar: false`): the room's top row carries it on the recording's line
// (D-108). In full view (`fullView`) the page is alone and fills the room; whoever may draw keeps drawing on it, and
// the room slides the tool dock ([WhiteboardDock]) in with its own bars (D-108, round 7). Since D-306 full view gives
// the page every pixel — no side gutter, the room drops its rounded frame and, on a phone / tablet, the system bars
// (immersive) and the orientation lock, so the page turns with the device; a fixed page whose shape fights the
// screen's (a landscape page on an upright phone) shows "Turn your device for a bigger page" for a few seconds
// ([boardFullViewTurnHint], [BoardTurnHint]); a continuous page fills both ways already.
// RoomPage puts it where the shared screen would go while a board is presented, for the presenter and every viewer;
// the room's recorder captures the room UI, so the board is in the recording as everyone sees it.
//
// The presenter's "Board" sheet ([showWhiteboardOptionsSheet]): page format (D-093: a change remaps the board for
// everyone, after a word when it has content), background, save as PNG (board_export.dart; continuous: the part on
// screen or the whole board), clear / delete the page, (host) "Let students draw and write" — the room's annotation
// permission, shared with screen annotation — and "Show who drew what", and (this device) "Stylus only".
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

import '../annotation/draw_input_prefs.dart';
import '../widgets/live_palette.dart';
import 'board_controller.dart';
import 'board_export.dart';
import 'board_painter.dart';
import 'board_protocol.dart';
import 'board_stage.dart';
import 'board_toolbar.dart';

class WhiteboardRoomView extends StatefulWidget {
  const WhiteboardRoomView({
    super.key,
    required this.controller,
    this.presenterName = '',
    this.fallbackRtl = false,
    this.onStop,
    this.onOptions,
    this.pageKey,
    this.keyboard,
    this.showTopBar = true,
    this.fullView = false,
    this.railKey,
  });

  final BoardController controller;

  /// The bar over the page (WhiteboardTopBar). The live room passes false: its top row carries the title, the
  /// page and the presenter's controls on the same line as the recording (D-108).
  final bool showTopBar;

  /// Full view (D-108): the page alone, with no room kept for a bar or the dock. The dock is not drawn here (the
  /// room shows a [WhiteboardDock] with its own bars); the page still takes the pen of whoever may draw.
  final bool fullView;

  /// On the continuous page's vertical rail (the room keeps its floating cameras clear of it, D-109).
  final GlobalKey? railKey;

  /// The viewers' title ("`name`'s whiteboard").
  final String presenterName;
  final bool fallbackRtl;

  /// The presenter's Stop presenting.
  final VoidCallback? onStop;

  /// The presenter's Board options.
  final VoidCallback? onOptions;

  /// The page's RepaintBoundary (Save as PNG).
  final GlobalKey? pageKey;

  /// Board keys on a hardware keyboard (null: web / desktop only).
  final bool? keyboard;

  @override
  State<WhiteboardRoomView> createState() => _WhiteboardRoomViewState();
}

class _WhiteboardRoomViewState extends State<WhiteboardRoomView> {
  BoardBackground? _bg;
  bool _keys = false;

  /// D-306: the turn hint's few seconds (armed each time full view opens).
  bool _turnHint = false;
  Timer? _turnTimer;

  BoardController get _c => widget.controller;

  bool get _keyboardOn =>
      widget.keyboard ??
      (kIsWeb ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  void initState() {
    super.initState();
    _c.addListener(_onBoard);
    if (_keyboardOn) {
      HardwareKeyboard.instance.addHandler(_onKey);
      _keys = true;
    }
    _bg = _c.background;
    _fitColor();
    if (widget.fullView) _armTurnHint(); // opened straight into full view
  }

  @override
  void didUpdateWidget(WhiteboardRoomView old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_onBoard);
      widget.controller.addListener(_onBoard);
    }
    if (widget.fullView != old.fullView) _armTurnHint();
  }

  void _armTurnHint() {
    _turnTimer?.cancel();
    _turnHint = widget.fullView;
    if (!_turnHint) return;
    _turnTimer = Timer(kBoardTurnHintFor, () {
      if (mounted) setState(() => _turnHint = false);
    });
  }

  @override
  void dispose() {
    _turnTimer?.cancel();
    _c.removeListener(_onBoard);
    if (_keys) HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent e) => mounted && boardHandleKey(e, _c);

  void _onBoard() {
    if (_c.background != _bg) {
      _bg = _c.background;
      _fitColor();
    }
  }

  /// A dark ink on the blackboard (or chalk on paper) becomes the new page's default ink.
  void _fitColor() {
    final colors = boardInkColors(_c.background);
    if (!colors.any((c) => c.toARGB32() == _c.colorArgb)) _c.setColor(colors.first.toARGB32());
  }

  @override
  Widget build(BuildContext context) {
    LivePalette.sync(context);
    return ListenableBuilder(
      listenable: Listenable.merge([_c, _c.scene]),
      builder: (context, _) {
        final presenting = _c.isLocalPresenting;
        final full = widget.fullView;
        final canDraw = _c.canDrawLocal && !full; // the dock under the page (full view: the room's, with its bars)
        final bar = widget.showTopBar && !full;
        return LayoutBuilder(builder: (context, box) {
          // The dock's own height (one row on wide screens, two otherwise); its shapes / style panel opens over the
          // page. The bar, the page and the dock stay together in the middle when the page is shorter than the room.
          final wideDock = box.maxWidth - 16 >= kBoardDockWideWidth;
          final dockH = canDraw ? (wideDock ? 70.0 : 121.0) : (full ? 0.0 : 10.0);
          final topH = bar ? 64.0 : (full ? 0.0 : 6.0);
          // A phone gives the page every pixel of its width; full view every pixel of the screen (D-306).
          final side = full ? 0.0 : (box.maxWidth < 600 ? 4.0 : 12.0);
          // A continuous page takes all the height there is (it scrolls); a fixed one what its shape needs.
          final idealStage = _c.isContinuous ? double.infinity : (box.maxWidth - side * 2) / _c.aspect + 4;
          final stageH = math.max(0.0, math.min(idealStage, box.maxHeight - topH - dockH));
          final free = math.max(0.0, box.maxHeight - topH - stageH - dockH);
          final column = Column(children: [
            SizedBox(height: free / 2),
            if (!bar)
              SizedBox(height: topH)
            else
            SizedBox(
              height: topH,
              child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 6),
              child: WhiteboardTopBar(
              key: const ValueKey('board.topbar'),
              presenting: presenting,
              pageIndex: _c.pageIndex,
              pageCount: _c.pageCount,
              presenterName: widget.presenterName,
              canDraw: canDraw,
              onPrevious: _c.previousPage,
              onNext: _c.nextPage,
              onAddPage: _c.addPage,
              onOptions: widget.onOptions,
              onStop: widget.onStop,
            ),
          ),
            ),
            SizedBox(
              height: stageH,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: side),
                child: WhiteboardStage(
                  controller: _c,
                  pageKey: widget.pageKey,
                  railKey: widget.railKey,
                  fallbackRtl: widget.fallbackRtl,
                  presenterName: widget.presenterName,
                ),
              ),
            ),
          ]);
          // D-306: a fixed page that fights the screen's shape in full view says how to make it bigger.
          final turn = _turnHint &&
              boardFullViewTurnHint(
                  fullView: full, continuous: _c.isContinuous, aspect: _c.aspect, box: box.biggest, mobile: boardTurnableDevice());
          final hint = turn
              ? Positioned(
                  left: 12,
                  right: 12,
                  bottom: 16,
                  child: Center(child: BoardTurnHint(portraitPage: _c.aspect < 1)),
                )
              : null;
          // Always a Stack: the page keeps its state (zoom, scroll) when the dock comes and goes (full view, D-108).
          if (!canDraw) return Stack(children: [Positioned.fill(child: column), ?hint]);
          return Stack(children: [
            Positioned.fill(child: column),
            ?hint,
            PositionedDirectional(
              start: 0,
              end: 0,
              bottom: free / 2,
              child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              child: WhiteboardDock(controller: _c),
            ),
            ),
          ]);
        });
      },
    );
  }
}

/// The board's tool dock, bound to [controller]: under the page in the room, and in full view inside the room's bars
/// (D-108), so the tools come back with the controls. The tool, colour and size live in the controller, so the pen
/// keeps what was chosen before wherever the dock is drawn.
class WhiteboardDock extends StatefulWidget {
  const WhiteboardDock({super.key, required this.controller, this.wide});

  final BoardController controller;

  /// Null: by the available width ([kBoardDockWideWidth]).
  final bool? wide;

  @override
  State<WhiteboardDock> createState() => _WhiteboardDockState();
}

class _WhiteboardDockState extends State<WhiteboardDock> {
  BoardPanel _panel = BoardPanel.none;
  late BoardTool _lastShape = widget.controller.tool.isShape ? widget.controller.tool : BoardTool.rect;

  BoardController get _c => widget.controller;

  void _tool(BoardTool tl) {
    if (tl.isShape) _lastShape = tl;
    _c.setTool(tl);
    _c.setDrawMode(true);
    setState(() => _panel = tl.isShape ? BoardPanel.none : (_panel == BoardPanel.shapes ? BoardPanel.none : _panel));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([_c, _c.scene]),
        builder: (context, _) {
          final colors = boardInkColors(_c.background);
          return WhiteboardToolbar(
            key: const ValueKey('board.toolbar'),
            tool: _c.tool,
            color: Color(_c.colorArgb),
            colors: colors,
            colorLabels: boardColorLabels(_c.background),
            thickness: _c.thickness,
            fontStep: _c.fontStep,
            textStyle: _c.tool == BoardTool.text || _c.selectedItem is BoardText,
            canUndo: _c.canUndo,
            canRedo: _c.canRedo,
            wide: widget.wide,
            panel: _panel,
            lastShape: _lastShape,
            onTool: _tool,
            onColor: (col) => _c.setColor(col.toARGB32()),
            onThickness: _c.setThickness,
            onFontStep: _c.setFontStep,
            onUndo: _c.undo,
            onRedo: _c.redo,
            onPanel: (p) => setState(() => _panel = p),
          );
        },
      );
}

/// The presenter's Board sheet. [allowStudents] / [onAllowStudents]: the room's annotation permission (host only);
/// [showAuthors] / [onShowAuthors]: the host's "Show who drew what" (D-093); [listenable] rebuilds the sheet when they
/// change elsewhere.
Future<void> showWhiteboardOptionsSheet(
  BuildContext context, {
  required BoardController controller,
  required GlobalKey pageKey,
  bool isHost = false,
  bool Function()? allowStudents,
  ValueChanged<bool>? onAllowStudents,
  bool Function()? showAuthors,
  ValueChanged<bool>? onShowAuthors,
  Listenable? listenable,
  String fileStem = 'whiteboard',
}) =>
    showAppSheet<void>(
      context,
      (ctx) => ListenableBuilder(
        listenable: Listenable.merge([controller, controller.scene, DrawInputPrefs.stylusOnly, ?listenable]),
        builder: (ctx, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSheetHeader(t('السبورة', 'Board')),
          Flexible(
            child: SingleChildScrollView(
              child: WhiteboardOptionsLayout(
                background: controller.background,
                format: controller.format,
                pageIndex: controller.pageIndex,
                pageCount: controller.pageCount,
                pageEmpty: controller.scene.pageEmpty,
                isHost: isHost,
                allowStudents: allowStudents?.call() ?? false,
                showAuthors: showAuthors?.call() ?? false,
                stylusOnly: DrawInputPrefs.stylusOnly.value,
                onBackground: controller.setBackground,
                onFormat: (f) => unawaited(_changeFormat(ctx, controller, f)),
                onAllowStudents: onAllowStudents,
                onShowAuthors: onShowAuthors,
                onStylusOnly: (v) => unawaited(DrawInputPrefs.setStylusOnly(v)),
                onExport: () async {
                  Navigator.pop(ctx);
                  await saveBoardImage(controller,
                      region: controller.isContinuous ? BoardExportRegion.visible : BoardExportRegion.page, fileStem: fileStem);
                },
                onExportWhole: () async {
                  Navigator.pop(ctx);
                  await saveBoardImage(controller, region: BoardExportRegion.whole, fileStem: fileStem);
                },
                onClearPage: () async {
                  final ok = await appConfirm(
                    ctx,
                    message: t('مسح كل ما على هذه الصفحة لدى الجميع؟', 'Clear everything on this page for everyone?'),
                    danger: true,
                    confirmLabel: t('مسح الصفحة', 'Clear page'),
                  );
                  if (ok) controller.clearPage();
                },
                onDeletePage: () async {
                  final ok = await appConfirm(
                    ctx,
                    message: t('حذف هذه الصفحة وما عليها لدى الجميع؟', 'Delete this page and everything on it for everyone?'),
                    danger: true,
                    confirmLabel: t('حذف الصفحة', 'Delete page'),
                  );
                  if (ok) controller.deletePage();
                },
              ),
            ),
          ),
        ]),
      ),
    );

/// The presenter picks a format: on a board with content, a word first (it is resized to fit, for everyone).
Future<void> _changeFormat(BuildContext context, BoardController c, BoardFormat f) async {
  if (f == c.format) return;
  final empty = !c.scene.items.any((_) => true);
  if (!empty) {
    final ok = await appConfirm(
      context,
      message: t('تغيير شكل الصفحة إلى «${boardFormatLabel(f)}»؟ يبقى كل ما على السبورة ويُصغَّر عند الحاجة ليتّسع، لدى الجميع.',
          'Change the page to ${boardFormatLabel(f)}? Everything on the board stays, made smaller where it has to fit, for everyone.'),
      confirmLabel: t('تغيير', 'Change'),
    );
    if (!ok) return;
  }
  c.setFormat(f);
}

/// Saves [region] of the board as a PNG drawn from its items (board_export.dart; downloads on the web, the share /
/// save sheet on phones).
Future<void> saveBoardImage(BoardController c, {BoardExportRegion region = BoardExportRegion.page, String fileStem = 'whiteboard'}) =>
    boardOnce(() async {
      try {
        final bytes = await boardRenderPng(c, region: region, view: c.localViewport);
        if (bytes == null) {
          showAppNotice(t('افتح السبورة أولاً لحفظها', 'Open the board first to save it'), error: true);
          return;
        }
        final now = DateTime.now();
        String two(int v) => v.toString().padLeft(2, '0');
        final suffix = region == BoardExportRegion.whole ? 'all' : 'p${c.pageIndex + 1}';
        final name = '$fileStem-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}-$suffix'
            .replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
        await FileSaver.instance.saveFile(name: name, bytes: bytes, fileExtension: 'png', mimeType: MimeType.png);
        showAppNotice(
            region == BoardExportRegion.whole
                ? t('حُفظت السبورة كاملة كصورة', 'The whole board was saved as an image')
                : t('حُفظت الصفحة كصورة', 'The page was saved as an image'),
            icon: Icons.image_outlined);
      } catch (e) {
        showAppNotice(t('تعذّر حفظ الصورة', "Couldn't save the image"), error: true);
      }
    });

/// Saves the page on screen as a 1920 px PNG (the stage's RepaintBoundary; [saveBoardImage] draws it from the items
/// instead and is what the Board sheet uses).
Future<void> saveWhiteboardPng(GlobalKey pageKey, {int pageNumber = 1, String fileStem = 'whiteboard'}) => boardOnce(() async {
      try {
        final bytes = await boardPagePng(pageKey);
        if (bytes == null) {
          showAppNotice(t('افتح السبورة أولاً لحفظها', 'Open the board first to save it'), error: true);
          return;
        }
        final now = DateTime.now();
        String two(int v) => v.toString().padLeft(2, '0');
        final name = '$fileStem-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}-p$pageNumber'
            .replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
        await FileSaver.instance.saveFile(name: name, bytes: bytes, fileExtension: 'png', mimeType: MimeType.png);
        showAppNotice(t('حُفظت الصفحة كصورة', 'The page was saved as an image'), icon: Icons.image_outlined);
      } catch (e) {
        showAppNotice(t('تعذّر حفظ الصورة', "Couldn't save the image"), error: true);
      }
    });

// ── D-306: full view's turn hint ──────────────────────────────────────────────────────────────────────────────

/// How long the turn hint stays once full view opens.
const Duration kBoardTurnHintFor = Duration(seconds: 5);

/// A phone or a tablet (the device turns; a desktop window does not).
bool boardTurnableDevice() =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// Full view of a fixed page ([aspect] = width / height) in [box] wastes so much of the screen that turning the
/// device is worth saying: the page and the screen are of opposite shapes and the fitted page covers less than 55 %
/// of it. Never for a continuous page (it fills the width and scrolls) or off a phone / tablet.
bool boardFullViewTurnHint({
  required bool fullView,
  required bool continuous,
  required double aspect,
  required Size box,
  required bool mobile,
}) {
  if (!fullView || continuous || !mobile || aspect <= 0 || box.isEmpty || !box.isFinite) return false;
  final screen = box.width / box.height;
  if ((aspect >= 1) == (screen >= 1)) return false;
  final pageArea = math.min(box.width, box.height * aspect) * math.min(box.height, box.width / aspect);
  return pageArea / (box.width * box.height) < 0.55;
}

/// "Turn your device for a bigger page" — a glass pill over the page (plain values,
/// test/ui/whiteboard_full_view_layout_test.dart).
class BoardTurnHint extends StatelessWidget {
  const BoardTurnHint({super.key, this.portraitPage = false});

  /// The page is upright (turn back to portrait); else it is wide (turn sideways).
  final bool portraitPage;

  @override
  Widget build(BuildContext context) {
    final text = portraitPage
        ? t('أدِر جهازك رأسيًا لصفحة أكبر', 'Turn your device upright for a bigger page')
        : t('أدِر جهازك أفقيًا لصفحة أكبر', 'Turn your device sideways for a bigger page');
    return Semantics(
      liveRegion: true,
      label: text,
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey('board.turn_hint'),
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 18, 10),
          decoration: BoxDecoration(
            color: LivePalette.shade(0.72),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0x33FFFFFF)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.screen_rotation_rounded, size: 20, color: LivePalette.accent),
            const SizedBox(width: AppSpace.sm),
            Flexible(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: appText(13.5, w: FontWeight.w600, c: const Color(0xFFF8FAFC), h: 1.3),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
