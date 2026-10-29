// lib/features/teacher/sessions/live/whiteboard/board_view.dart
//
// The whiteboard as the room's stage (D-087): WhiteboardRoomView = the bar over the page (WhiteboardTopBar), the
// page (WhiteboardStage) and, for whoever may draw, the tool dock (WhiteboardToolbar) — bound to a BoardController.
// RoomPage puts it where the shared screen would go while a board is presented, for the presenter and every viewer;
// the room's recorder captures the room UI, so the board is in the recording as everyone sees it.
//
// The presenter's "Board" sheet ([showWhiteboardOptionsSheet]): background, save the page as PNG, clear / delete the
// page, and (host) "Let students draw and write" — the room's annotation permission, shared with screen annotation.
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

import '../widgets/live_palette.dart';
import 'board_controller.dart';
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
  });

  final BoardController controller;

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
  BoardPanel _panel = BoardPanel.none;
  BoardTool _lastShape = BoardTool.rect;
  BoardBackground? _bg;
  bool _keys = false;

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
  }

  @override
  void didUpdateWidget(WhiteboardRoomView old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_onBoard);
      widget.controller.addListener(_onBoard);
    }
  }

  @override
  void dispose() {
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

  void _tool(BoardTool tl) {
    if (tl.isShape) _lastShape = tl;
    _c.setTool(tl);
    _c.setDrawMode(true);
    setState(() => _panel = tl.isShape ? BoardPanel.none : (_panel == BoardPanel.shapes ? BoardPanel.none : _panel));
  }

  @override
  Widget build(BuildContext context) {
    LivePalette.sync(context);
    return ListenableBuilder(
      listenable: Listenable.merge([_c, _c.scene]),
      builder: (context, _) {
        final presenting = _c.isLocalPresenting;
        final canDraw = _c.canDrawLocal;
        final colors = boardInkColors(_c.background);
        final textStyle = _c.tool == BoardTool.text || _c.selectedItem is BoardText;
        return LayoutBuilder(builder: (context, box) {
          // The dock's own height (one row on wide screens, two otherwise); its shapes / style panel opens over the
          // page. The bar, the page and the dock stay together in the middle when the page is shorter than the room.
          final wideDock = box.maxWidth - 16 >= kBoardDockWideWidth;
          final dockH = canDraw ? (wideDock ? 70.0 : 121.0) : 10.0;
          const topH = 64.0;
          final side = box.maxWidth < 600 ? 4.0 : 12.0; // a phone gives the page every pixel of its width
          final idealStage = (box.maxWidth - side * 2) / kBoardAspect + 4;
          final stageH = math.max(0.0, math.min(idealStage, box.maxHeight - topH - dockH));
          final free = math.max(0.0, box.maxHeight - topH - stageH - dockH);
          final column = Column(children: [
            SizedBox(height: free / 2),
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
                child: WhiteboardStage(controller: _c, pageKey: widget.pageKey, fallbackRtl: widget.fallbackRtl),
              ),
            ),
          ]);
          if (!canDraw) return column;
          return Stack(children: [
            Positioned.fill(child: column),
            PositionedDirectional(
              start: 0,
              end: 0,
              bottom: free / 2,
              child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              child: WhiteboardToolbar(
                key: const ValueKey('board.toolbar'),
                tool: _c.tool,
                color: Color(_c.colorArgb),
                colors: colors,
                colorLabels: boardColorLabels(_c.background),
                thickness: _c.thickness,
                fontStep: _c.fontStep,
                textStyle: textStyle,
                canUndo: _c.canUndo,
                canRedo: _c.canRedo,
                panel: _panel,
                lastShape: _lastShape,
                onTool: _tool,
                onColor: (col) => _c.setColor(col.toARGB32()),
                onThickness: _c.setThickness,
                onFontStep: _c.setFontStep,
                onUndo: _c.undo,
                onRedo: _c.redo,
                onPanel: (p) => setState(() => _panel = p),
              ),
            ),
            ),
          ]);
        });
      },
    );
  }
}

/// The presenter's Board sheet. [allowStudents] / [onAllowStudents]: the room's annotation permission (host only);
/// [listenable] rebuilds the sheet when it changes elsewhere.
Future<void> showWhiteboardOptionsSheet(
  BuildContext context, {
  required BoardController controller,
  required GlobalKey pageKey,
  bool isHost = false,
  bool Function()? allowStudents,
  ValueChanged<bool>? onAllowStudents,
  Listenable? listenable,
  String fileStem = 'whiteboard',
}) =>
    showAppSheet<void>(
      context,
      (ctx) => ListenableBuilder(
        listenable: Listenable.merge([controller, controller.scene, ?listenable]),
        builder: (ctx, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSheetHeader(t('السبورة', 'Board')),
          Flexible(
            child: SingleChildScrollView(
              child: WhiteboardOptionsLayout(
                background: controller.background,
                pageIndex: controller.pageIndex,
                pageCount: controller.pageCount,
                pageEmpty: controller.scene.pageEmpty,
                isHost: isHost,
                allowStudents: allowStudents?.call() ?? false,
                onBackground: controller.setBackground,
                onAllowStudents: onAllowStudents,
                onExport: () async {
                  Navigator.pop(ctx);
                  await Future<void>.delayed(const Duration(milliseconds: 250)); // the sheet leaves the page first
                  await saveWhiteboardPng(pageKey, pageNumber: controller.pageIndex + 1, fileStem: fileStem);
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

/// Saves the page on screen as a 1920 px PNG (downloads on the web, the share / save sheet on phones).
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
