// lib/design/studio/studio_shortcuts.dart
//
// Keyboard on the web and desktop for every studio built on this engine (the certificate studio and the export
// designers, D-385): undo / redo, save, copy / cut / paste / duplicate, delete, select all, arrows to nudge
// (Shift = a larger step), group, bring forward / send back, zoom, Esc, Tab through layers and a "?" shortcut sheet.
//
// How it fits AppKeyboardSupport (lib/design/app_keyboard.dart): the app-wide layer runs before the focus tree and
// gives `AppKeyboard.keyClaim` the first look at every key, only where AppKeyboardSupport.enabled (web and desktop,
// never phones). A mounted StudioCanvas registers a [StudioKeyHost] here and the first one installs the claim, so:
//   · the keys work wherever the focus is on the studio's page, not only after a click on the canvas;
//   · nothing fires while typing (a focused EditableText, the in-place text editor) or under a dialog / sheet;
//   · with several canvases mounted (one per language in an IndexedStack) only the one on screen reacts;
//   · a plain key (arrows, Delete, Tab, Esc, [ ], ?) leaves the focus alone when a control holds it, so a focused
//     slider keeps its arrows and Tab keeps walking the controls.
// Modifier: Ctrl on Windows, Linux and the web, ⌘ on macOS (a Mac browser included).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../app_keyboard.dart';
import '../app_kit.dart' show appText, AppSheetHeader, showAppSheet;
import '../app_tokens.dart';
import 'studio_controller.dart';
import 'studio_layers.dart' show studioTr;

enum StudioCommand {
  undo,
  redo,
  save,
  copy,
  cut,
  paste,
  duplicate,
  delete,
  selectAll,
  deselect,
  nudge,
  group,
  ungroup,
  bringForward,
  sendBackward,
  bringToFront,
  sendToBack,
  zoomIn,
  zoomOut,
  zoomFit,
  nextLayer,
  prevLayer,
  lock,
  help,
}

/// True where the shortcut modifier is ⌘ rather than Ctrl (macOS, a browser on a Mac).
bool get studioMacKeys => defaultTargetPlatform == TargetPlatform.macOS;

bool _letter(LogicalKeyboardKey key, PhysicalKeyboardKey phys, LogicalKeyboardKey l, PhysicalKeyboardKey p) =>
    key == l || phys == p;

/// The command a key press means, or null. [primary] is the platform's modifier (Ctrl, or ⌘ on macOS); the physical key
/// is checked too, so the letters work on an Arabic layout.
StudioCommand? studioCommandFor(LogicalKeyboardKey key, PhysicalKeyboardKey phys, String? character,
    {required bool primary, required bool shift, bool alt = false}) {
  if (alt) return null;
  if (primary) {
    bool isL(LogicalKeyboardKey l, PhysicalKeyboardKey p) => _letter(key, phys, l, p);
    if (isL(LogicalKeyboardKey.keyZ, PhysicalKeyboardKey.keyZ)) return shift ? StudioCommand.redo : StudioCommand.undo;
    if (isL(LogicalKeyboardKey.keyY, PhysicalKeyboardKey.keyY)) return StudioCommand.redo;
    if (isL(LogicalKeyboardKey.keyS, PhysicalKeyboardKey.keyS)) return StudioCommand.save;
    if (isL(LogicalKeyboardKey.keyC, PhysicalKeyboardKey.keyC)) return StudioCommand.copy;
    if (isL(LogicalKeyboardKey.keyX, PhysicalKeyboardKey.keyX)) return StudioCommand.cut;
    if (isL(LogicalKeyboardKey.keyV, PhysicalKeyboardKey.keyV)) return StudioCommand.paste;
    if (isL(LogicalKeyboardKey.keyD, PhysicalKeyboardKey.keyD)) return StudioCommand.duplicate;
    if (isL(LogicalKeyboardKey.keyA, PhysicalKeyboardKey.keyA)) return StudioCommand.selectAll;
    if (isL(LogicalKeyboardKey.keyG, PhysicalKeyboardKey.keyG)) return shift ? StudioCommand.ungroup : StudioCommand.group;
    if (isL(LogicalKeyboardKey.keyL, PhysicalKeyboardKey.keyL)) return StudioCommand.lock;
    if (isL(LogicalKeyboardKey.bracketRight, PhysicalKeyboardKey.bracketRight)) return StudioCommand.bringToFront;
    if (isL(LogicalKeyboardKey.bracketLeft, PhysicalKeyboardKey.bracketLeft)) return StudioCommand.sendToBack;
    if (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.add || key == LogicalKeyboardKey.numpadAdd ||
        phys == PhysicalKeyboardKey.equal) {
      return StudioCommand.zoomIn;
    }
    if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract || phys == PhysicalKeyboardKey.minus) {
      return StudioCommand.zoomOut;
    }
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0 || phys == PhysicalKeyboardKey.digit0) {
      return StudioCommand.zoomFit;
    }
    return null;
  }
  if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown) {
    return StudioCommand.nudge;
  }
  if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) return StudioCommand.delete;
  if (key == LogicalKeyboardKey.escape) return StudioCommand.deselect;
  if (key == LogicalKeyboardKey.tab) return shift ? StudioCommand.prevLayer : StudioCommand.nextLayer;
  if (!shift) {
    if (key == LogicalKeyboardKey.bracketRight || phys == PhysicalKeyboardKey.bracketRight) return StudioCommand.bringForward;
    if (key == LogicalKeyboardKey.bracketLeft || phys == PhysicalKeyboardKey.bracketLeft) return StudioCommand.sendBackward;
  }
  if (character == '?' || character == '؟' || key == LogicalKeyboardKey.question ||
      (shift && phys == PhysicalKeyboardKey.slash)) {
    return StudioCommand.help;
  }
  return null;
}

/// The key label parts of a command: a modifier token 'mod', 'shift', else the key as printed.
const Map<StudioCommand, List<List<String>>> _keys = {
  StudioCommand.undo: [['mod', 'Z']],
  StudioCommand.redo: [['mod', 'shift', 'Z'], ['mod', 'Y']],
  StudioCommand.save: [['mod', 'S']],
  StudioCommand.copy: [['mod', 'C']],
  StudioCommand.cut: [['mod', 'X']],
  StudioCommand.paste: [['mod', 'V']],
  StudioCommand.duplicate: [['mod', 'D']],
  StudioCommand.delete: [['Del'], ['Backspace']],
  StudioCommand.selectAll: [['mod', 'A']],
  StudioCommand.deselect: [['Esc']],
  StudioCommand.group: [['mod', 'G']],
  StudioCommand.ungroup: [['mod', 'shift', 'G']],
  StudioCommand.bringForward: [[']']],
  StudioCommand.sendBackward: [['[']],
  StudioCommand.bringToFront: [['mod', ']']],
  StudioCommand.sendToBack: [['mod', '[']],
  StudioCommand.zoomIn: [['mod', '+']],
  StudioCommand.zoomOut: [['mod', '−']],
  StudioCommand.zoomFit: [['mod', '0']],
  StudioCommand.nextLayer: [['Tab']],
  StudioCommand.prevLayer: [['shift', 'Tab']],
  StudioCommand.lock: [['mod', 'L']],
  StudioCommand.help: [['?']],
};

String _token(String t) => switch (t) {
      'mod' => studioMacKeys ? '⌘' : 'Ctrl',
      'shift' => studioMacKeys ? '⇧' : 'Shift',
      _ => t,
    };

/// "Ctrl+Z" / "⌘Z" for [c], or null where the keyboard layer is off (phones).
String? studioShortcutHint(StudioCommand c) {
  if (!AppKeyboardSupport.enabled) return null;
  final first = _keys[c]?.first;
  if (first == null) return null;
  return first.map(_token).join(studioMacKeys ? '' : '+');
}

/// Toolbar / menu tooltip text: the label with its shortcut when the keyboard layer is on.
String studioTip(String label, StudioCommand c) {
  final h = studioShortcutHint(c);
  return h == null ? label : '$label ($h)';
}

/// Around a studio screen: what Ctrl+S does (the save lives in the host, not in the engine). Without one Ctrl+S is
/// left to the browser.
class StudioKeyboardScope extends StatelessWidget {
  const StudioKeyboardScope({super.key, required this.onSave, required this.child});
  final VoidCallback? onSave;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// One mounted canvas, as the keyboard sees it.
class StudioKeyHost {
  StudioKeyHost({required this.controller, required this.contextOf, required this.focusOf, required this.isMounted});

  final StudioController<Object?> controller;
  final BuildContext Function() contextOf;
  final FocusNode Function() focusOf;
  final bool Function() isMounted;

  bool get _onTop {
    if (!isMounted()) return false;
    final route = ModalRoute.of(contextOf());
    return route == null || route.isCurrent;
  }

  /// Drawn right now: reached by a hit test at its centre (an IndexedStack paints and hits only the current child).
  bool get _onScreen {
    final ro = contextOf().findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize || ro.size.isEmpty) return false;
    RenderObject? top = ro;
    while (top != null && top is! RenderView) {
      top = top.parent;
    }
    if (top is! RenderView) return false;
    final centre = ro.localToGlobal(ro.size.center(Offset.zero));
    final result = BoxHitTestResult();
    top.hitTest(result, position: centre);
    return result.path.any((e) => identical(e.target, ro));
  }
}

/// The dispatch; a canvas calls [attach] / [detach] and [touch] on a pointer down.
abstract final class StudioKeyboard {
  static final List<StudioKeyHost> _hosts = [];
  static bool Function(KeyDownEvent e)? _prev;
  static bool _installed = false;

  static void _install() {
    if (_installed) return;
    _prev = AppKeyboard.keyClaim;
    AppKeyboard.keyClaim = _claim;
    _installed = true;
  }

  static void attach(StudioKeyHost host) {
    _hosts.add(host);
    _install();
  }

  static void detach(StudioKeyHost host) {
    _hosts.remove(host);
    if (_hosts.isEmpty) {
      if (AppKeyboard.keyClaim == _claim) AppKeyboard.keyClaim = _prev;
      _prev = null;
      _installed = false;
    }
  }

  /// The canvas the person last used comes first; re-installs the claim if another owner dropped it.
  static void touch(StudioKeyHost host) {
    if (_hosts.remove(host)) _hosts.add(host);
    if (_installed && AppKeyboard.keyClaim == null) AppKeyboard.keyClaim = _claim;
  }

  static KeyDownEvent? _last;

  /// [_claim] acted on this key press: the focus tree (which also receives it) must not act twice.
  static bool handled(KeyEvent e) => e is KeyDownEvent && _last != null && _last!.timeStamp == e.timeStamp && _last!.logicalKey == e.logicalKey;

  static StudioKeyHost? _active() {
    for (final h in _hosts.reversed) {
      if (h._onTop && h._onScreen) return h;
    }
    return null;
  }

  static bool _typing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// Nothing else needs the plain keys: the focus is on a canvas, or on no control at all.
  static bool _neutralFocus() {
    final f = FocusManager.instance.primaryFocus;
    if (f == null || f is FocusScopeNode) return true;
    return _hosts.any((h) => identical(h.focusOf(), f));
  }

  static const Set<StudioCommand> _plain = {
    StudioCommand.nudge,
    StudioCommand.delete,
    StudioCommand.deselect,
    StudioCommand.nextLayer,
    StudioCommand.prevLayer,
    StudioCommand.bringForward,
    StudioCommand.sendBackward,
  };

  static bool _claim(KeyDownEvent e) {
    bool next() => _prev?.call(e) ?? false;
    if (!AppKeyboardSupport.enabled) return next();
    final host = _active();
    if (host == null || _typing() || host.controller.editingId != null || host.controller.dragging) return next();
    final kb = HardwareKeyboard.instance;
    final primary = studioMacKeys ? kb.isMetaPressed : kb.isControlPressed;
    final cmd = studioCommandFor(e.logicalKey, e.physicalKey, e.character,
        primary: primary, shift: kb.isShiftPressed, alt: kb.isAltPressed);
    if (cmd == null) return next();
    if (_plain.contains(cmd) && !_neutralFocus()) return next();
    if (!_run(host, cmd, e, big: kb.isShiftPressed)) return next();
    _last = e;
    if (_plain.contains(cmd) && !host.focusOf().hasFocus) host.focusOf().requestFocus();
    return true;
  }

  static bool _run(StudioKeyHost host, StudioCommand cmd, KeyDownEvent e, {required bool big}) {
    final ctl = host.controller;
    final hasSel = ctl.selection.isNotEmpty;
    switch (cmd) {
      case StudioCommand.undo:
        ctl.undo();
      case StudioCommand.redo:
        ctl.redo();
      case StudioCommand.save:
        final onSave = host.contextOf().findAncestorWidgetOfExactType<StudioKeyboardScope>()?.onSave;
        if (onSave == null) return false;
        onSave();
      case StudioCommand.copy:
        if (!hasSel) return false;
        ctl.copy();
      case StudioCommand.cut:
        if (!hasSel) return false;
        ctl.cut();
      case StudioCommand.paste:
        if (!ctl.canPaste) return false;
        ctl.paste();
      case StudioCommand.duplicate:
        if (!hasSel) return false;
        ctl.duplicate();
      case StudioCommand.delete:
        if (!hasSel) return false;
        ctl.deleteSelection();
      case StudioCommand.selectAll:
        ctl.selectAll();
      case StudioCommand.deselect:
        if (!hasSel) return false;
        ctl.clearSelection();
      case StudioCommand.nudge:
        if (!hasSel) return false;
        final (dx, dy) = switch (e.logicalKey) {
          LogicalKeyboardKey.arrowLeft => (-1, 0),
          LogicalKeyboardKey.arrowRight => (1, 0),
          LogicalKeyboardKey.arrowUp => (0, -1),
          _ => (0, 1),
        };
        ctl.nudge(dx, dy, big: big);
      case StudioCommand.group:
        if (!ctl.canGroup) return false;
        ctl.group();
      case StudioCommand.ungroup:
        if (!ctl.canUngroup) return false;
        ctl.ungroup();
      case StudioCommand.bringForward:
        if (!hasSel) return false;
        ctl.bringForward();
      case StudioCommand.sendBackward:
        if (!hasSel) return false;
        ctl.sendBackward();
      case StudioCommand.bringToFront:
        if (!hasSel) return false;
        ctl.bringToFront();
      case StudioCommand.sendToBack:
        if (!hasSel) return false;
        ctl.sendToBack();
      case StudioCommand.zoomIn:
        ctl.zoomIn();
      case StudioCommand.zoomOut:
        ctl.zoomOut();
      case StudioCommand.zoomFit:
        ctl.fitPage();
      case StudioCommand.nextLayer:
        return _stepLayer(ctl, 1);
      case StudioCommand.prevLayer:
        return _stepLayer(ctl, -1);
      case StudioCommand.lock:
        if (!ctl.canLock) return false;
        ctl.toggleLock();
      case StudioCommand.help:
        showStudioShortcuts(host.contextOf());
    }
    return true;
  }

  /// Tab through the visible layers, top first (the order of the layers panel), wrapping; each one comes into view.
  static bool _stepLayer(StudioController<Object?> ctl, int dir) {
    final order = [for (final i in ctl.items.reversed) if (i.visible) i.id];
    if (order.isEmpty) return false;
    final sel = ctl.selection;
    final current = sel.length == 1 ? order.indexOf(sel.first) : -1;
    final next = current < 0 ? (dir > 0 ? 0 : order.length - 1) : (current + dir) % order.length;
    final id = order[next];
    ctl.selectIds([id]);
    ctl.reveal(id);
    return true;
  }
}

// ── the "?" sheet ──────────────────────────────────────────────────────────────────────────────────────────────

class StudioShortcutRow {
  const StudioShortcutRow(this.label, this.keys);
  final String label;

  /// Each alternative: the key parts as printed ("Ctrl", "Z").
  final List<List<String>> keys;
}

class StudioShortcutGroup {
  const StudioShortcutGroup(this.title, this.rows);
  final String title;
  final List<StudioShortcutRow> rows;
}

List<List<String>> _printed(StudioCommand c) => [
      for (final alt in (_keys[c] ?? const <List<String>>[])) [for (final t in alt) _token(t)],
    ];

/// The sheet's content, in the reader's language and for this platform's modifier.
List<StudioShortcutGroup> studioShortcutGroups() {
  StudioShortcutRow r(StudioCommand c, String ar, String en) => StudioShortcutRow(studioTr(ar, en), _printed(c));
  final arrows = [
    ['←', '→', '↑', '↓'],
  ];
  return [
    StudioShortcutGroup(studioTr('التعديل', 'Editing'), [
      r(StudioCommand.undo, 'تراجع', 'Undo'),
      r(StudioCommand.redo, 'إعادة', 'Redo'),
      r(StudioCommand.save, 'حفظ', 'Save'),
      r(StudioCommand.duplicate, 'تكرار', 'Duplicate'),
      r(StudioCommand.delete, 'حذف', 'Delete'),
      r(StudioCommand.lock, 'قفل / فتح', 'Lock / unlock'),
    ]),
    StudioShortcutGroup(studioTr('النسخ', 'Clipboard'), [
      r(StudioCommand.cut, 'قص', 'Cut'),
      r(StudioCommand.copy, 'نسخ', 'Copy'),
      r(StudioCommand.paste, 'لصق', 'Paste'),
    ]),
    StudioShortcutGroup(studioTr('التحديد', 'Selection'), [
      r(StudioCommand.selectAll, 'تحديد الكل', 'Select all'),
      r(StudioCommand.deselect, 'إلغاء التحديد', 'Deselect'),
      r(StudioCommand.nextLayer, 'الطبقة التالية', 'Next layer'),
      r(StudioCommand.prevLayer, 'الطبقة السابقة', 'Previous layer'),
      r(StudioCommand.group, 'تجميع', 'Group'),
      r(StudioCommand.ungroup, 'فك التجميع', 'Ungroup'),
    ]),
    StudioShortcutGroup(studioTr('التحريك', 'Moving'), [
      StudioShortcutRow(studioTr('تحريك', 'Nudge'), arrows),
      StudioShortcutRow(studioTr('تحريك بخطوة أكبر', 'Nudge further'), [
        [_token('shift'), '←', '→', '↑', '↓'],
      ]),
    ]),
    StudioShortcutGroup(studioTr('الترتيب', 'Arrange'), [
      r(StudioCommand.bringForward, 'للأمام خطوة', 'Bring forward'),
      r(StudioCommand.sendBackward, 'للخلف خطوة', 'Send backward'),
      r(StudioCommand.bringToFront, 'إلى المقدمة', 'Bring to front'),
      r(StudioCommand.sendToBack, 'إلى الخلف', 'Send to back'),
    ]),
    StudioShortcutGroup(studioTr('العرض', 'View'), [
      r(StudioCommand.zoomIn, 'تكبير', 'Zoom in'),
      r(StudioCommand.zoomOut, 'تصغير', 'Zoom out'),
      r(StudioCommand.zoomFit, 'ملاءمة الصفحة', 'Fit page'),
      r(StudioCommand.help, 'هذه القائمة', 'This list'),
    ]),
  ];
}

Future<void> showStudioShortcuts(BuildContext context) =>
    showAppSheet<void>(context, (ctx) => const StudioShortcutsPanel());

/// The shortcut list (plain values: the layout test pumps it).
class StudioShortcutsPanel extends StatelessWidget {
  const StudioShortcutsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final groups = studioShortcutGroups();
    return LayoutBuilder(builder: (context, box) {
      final two = box.maxWidth >= 560;
      final w = two ? (box.maxWidth - AppSpace.lg * 3) / 2 : box.maxWidth - AppSpace.md * 2;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          AppSheetHeader(studioTr('اختصارات لوحة المفاتيح', 'Keyboard shortcuts')),
          Wrap(spacing: AppSpace.lg, runSpacing: AppSpace.md, children: [
            for (final g in groups) SizedBox(width: w, child: _GroupCard(g)),
          ]),
        ]),
      );
    });
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard(this.group);
  final StudioShortcutGroup group;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(group.title, style: appText(13, w: FontWeight.w700, c: c.textMedium)),
      const SizedBox(height: AppSpace.xxs),
      for (final r in group.rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(r.label, style: appText(14, c: c.textDark))),
            const SizedBox(width: AppSpace.sm),
            Flexible(
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Wrap(alignment: WrapAlignment.end, spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
                  for (var i = 0; i < r.keys.length; i++) ...[
                    if (i > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text('/', style: appText(12, c: c.textLight))),
                    for (final k in r.keys[i]) _Cap(k),
                  ],
                ]),
              ),
            ),
          ]),
        ),
    ]);
  }
}

class _Cap extends StatelessWidget {
  const _Cap(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: 2),
      decoration: BoxDecoration(color: c.background, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
      child: Text(label, style: appText(12, w: FontWeight.w600, c: c.textDark)),
    );
  }
}
