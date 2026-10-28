// lib/design/app_keyboard.dart
//
// Keyboard support for the web (and desktop) build — one layer for EVERY text field of every screen, mounted once
// in MaterialApp.builder (`AppKeyboardSupport`). It listens to HardwareKeyboard, so no screen has to wire anything:
//
//   Enter in a single-line field
//     · the field's own onSubmitted / onEditingComplete when it has one — unchanged, the engine fires it;
//     · a search / filter box: nothing (it filters as you type);
//     · another field after it in the same form → the focus moves there (Enter walks the form like Tab);
//     · the last field → the form's primary button is pressed (see [_pickButton]: PrimaryButton / AppPrimaryButton /
//       FilledButton / ElevatedButton, the one closest to the field in the tree; in a dialog with text buttons only,
//       the last text button, i.e. "OK");
//     · a field whose textInputAction is done / go / send submits right away.
//   Enter in a multi-line field inserts a newline, as before; Ctrl+Enter / ⌘+Enter submits it the same way.
//   Esc in a field on a page takes the focus out of it; in a dialog or sheet Flutter's DismissIntent closes it.
//   Ctrl+K / ⌘+K, or "/" while not typing, focuses the first search box of the screen and selects its text.
//
// A screen decides for itself with `EnterSubmits(onSubmit: …, child: …)` around its fields (`EnterSubmits.none`
// makes Enter do nothing there, e.g. inside an exam). Pure parts are unit-tested in test/ui/app_keyboard_test.dart.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../utils/top_route_observer.dart' show topRouteObserver;
import '../utils/widget/primary_button.dart';

/// What Enter does for the text fields below this widget that have no handler of their own.
/// `onSubmit == null` (or [EnterSubmits.none]) means "nothing": the field keeps the platform's default.
class EnterSubmits extends InheritedWidget {
  const EnterSubmits({super.key, required this.onSubmit, required super.child});
  const EnterSubmits.none({super.key, required super.child}) : onSubmit = null;

  final VoidCallback? onSubmit;

  @override
  bool updateShouldNotify(EnterSubmits oldWidget) => false;
}

/// Mount once around the app (MaterialApp.builder). See the file header.
class AppKeyboardSupport extends StatefulWidget {
  const AppKeyboardSupport({super.key, required this.child});

  final Widget child;

  /// Tests force it on; otherwise only where hardware keyboards are the norm.
  static bool? enabledOverride;

  static bool get enabled {
    if (enabledOverride != null) return enabledOverride!;
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  @override
  State<AppKeyboardSupport> createState() => _AppKeyboardSupportState();
}

class _AppKeyboardSupportState extends State<AppKeyboardSupport> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handle);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handle);
    super.dispose();
  }

  bool _handle(KeyEvent e) {
    if (!AppKeyboardSupport.enabled || e is! KeyDownEvent) return false;
    try {
      return AppKeyboard.handleKeyDown(e);
    } catch (err, st) {
      // Never let a lookup failure break typing.
      assert(() {
        debugPrint('AppKeyboard: $err\n$st');
        return true;
      }());
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The decisions, kept static so a test can drive them with `tester.sendKeyEvent`.
abstract final class AppKeyboard {
  /// A widget that owns some keys for a moment — an open @mention list (`Mentions` in app_mentions.dart, D-075):
  /// every key goes to it first, and what it handles (Enter picks, Esc closes) never reaches the rules below.
  static bool Function(KeyDownEvent e)? keyClaim;

  static bool handleKeyDown(KeyDownEvent e) {
    final claim = keyClaim;
    if (claim != null && claim(e)) return true;
    final kb = HardwareKeyboard.instance;
    if (kb.isAltPressed) return false;
    final ctrl = kb.isControlPressed || kb.isMetaPressed;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) return _onEnter(ctrl);
    if (key == LogicalKeyboardKey.escape) return _onEscape();
    if (ctrl && key == LogicalKeyboardKey.keyK) return focusSearch();
    if (!ctrl && (key == LogicalKeyboardKey.slash || e.character == '/') && _FocusedField.current() == null) {
      return focusSearch();
    }
    return false;
  }

  static bool _onEnter(bool ctrl) {
    final f = _FocusedField.current();
    if (f == null || f.editable.readOnly || f.composing) return false;
    final explicit = f.editableEl.findAncestorWidgetOfExactType<EnterSubmits>();

    if (f.multiline) {
      if (!ctrl) return false; // a newline
      if (f.editable.onSubmitted != null) {
        f.editable.onSubmitted!(f.editable.controller.text);
        return true;
      }
      if (explicit != null) return _run(explicit.onSubmit);
      return _pressPrimary(f);
    }

    // single line: the field's own handler stays in charge (the engine fires it on Enter)
    if (f.editable.onSubmitted != null || f.editable.onEditingComplete != null) return false;
    if (explicit != null) return _run(explicit.onSubmit);
    if (f.isSearch) return false;
    switch (f.editable.textInputAction) {
      case TextInputAction.done:
      case TextInputAction.go:
      case TextInputAction.send:
        return _pressPrimary(f);
      case TextInputAction.search:
      case TextInputAction.none:
      case TextInputAction.newline:
      case TextInputAction.unspecified:
      case TextInputAction.previous:
      case TextInputAction.continueAction:
      case TextInputAction.join:
      case TextInputAction.route:
      case TextInputAction.emergencyCall:
        return false;
      case TextInputAction.next:
        // the web engine moves the focus by traversal order (a button may be in between); desktop embedders too,
        // but asynchronously — there we leave it to them so the focus is not moved twice
        if (!kIsWeb) return false;
        return _nextOrSubmit(f);
      case null:
        return _nextOrSubmit(f);
    }
  }

  /// Enter walks the form: the next field after this one, or the primary button when this is the last.
  static bool _nextOrSubmit(_FocusedField f) {
    final scan = _Scan.of(f);
    final next = scan.fieldAfterFocused;
    if (next != null) {
      // after this handler the web engine performs the field's action (unfocus / nextFocus) synchronously, which
      // would overwrite a focus request made now — ours is applied in a microtask, after it
      scheduleMicrotask(() {
        if (next.focusNode.canRequestFocus) next.focusNode.requestFocus();
      });
      return true;
    }
    return _press(scan.pickButton());
  }

  static bool _pressPrimary(_FocusedField f) => _press(_Scan.of(f).pickButton());

  static bool _press(_Candidate? b) {
    if (b == null) return false;
    b.press();
    return true;
  }

  static bool _run(VoidCallback? fn) {
    if (fn == null) return false;
    fn();
    return true;
  }

  static bool _onEscape() {
    final f = _FocusedField.current();
    if (f == null) return false;
    final route = ModalRoute.of(f.editableEl);
    if (route is PopupRoute) return false; // DismissIntent closes the dialog / sheet
    f.editable.focusNode.unfocus();
    return true;
  }

  /// Ctrl+K / "/": focus the first search box of the screen (its text selected, ready to be replaced).
  static bool focusSearch() {
    final root = _routeRoot();
    if (root == null) return false;
    final scan = _Scan(root, focused: null);
    for (final field in scan.fields) {
      if (!field.isSearch || !field.editable.focusNode.canRequestFocus || !_visible(field.element)) continue;
      final ed = field.editable;
      ed.focusNode.requestFocus();
      ed.controller.selection = TextSelection(baseOffset: 0, extentOffset: ed.controller.text.length);
      return true;
    }
    return false;
  }

  /// The element under which the current route's content lives.
  static Element? _routeRoot() {
    final node = FocusManager.instance.primaryFocus;
    final scope = node == null ? null : (node is FocusScopeNode ? node : node.nearestScope);
    final ctx = scope?.context;
    if (ctx is Element && scope != FocusManager.instance.rootScope) return ctx;
    final route = topRouteObserver.topRoute.value;
    final sub = route is ModalRoute ? route.subtreeContext : null;
    return sub is Element ? sub : null;
  }
}

// ── the focused field ───────────────────────────────────────────────────────

class _FocusedField {
  _FocusedField(this.editable, this.editableEl, this.textField);

  final EditableText editable;
  final Element editableEl;
  final TextField? textField;

  bool get multiline => editable.maxLines != 1;
  bool get composing => editable.controller.value.composing.isValid;
  bool get isSearch => looksLikeSearch(textField, editable, editableEl);

  /// The field that has the keyboard focus, or null when the focus is elsewhere (a button, nothing).
  static _FocusedField? current() {
    final node = FocusManager.instance.primaryFocus;
    if (node == null || node is FocusScopeNode) return null;
    final ctx = node.context;
    if (ctx is! Element) return null;
    EditableText? editable;
    Element? editableEl;
    TextField? field;
    ctx.visitAncestorElements((a) {
      final w = a.widget;
      if (editable == null) {
        if (w is EditableText) {
          editable = w;
          editableEl = a;
        }
        return true;
      }
      if (w is TextField) {
        field = w;
        return false;
      }
      return true;
    });
    if (editable == null) return null;
    // the node must be the field's own (not a button inside its decoration)
    if (!identical(editable!.focusNode, node)) return null;
    return _FocusedField(editable!, editableEl!, field);
  }

  static final _searchIcons = <IconData>{
    Icons.search, Icons.search_rounded, Icons.search_outlined, Icons.search_sharp,
    Icons.manage_search, Icons.manage_search_rounded, Icons.manage_search_outlined,
    Icons.filter_alt, Icons.filter_alt_rounded, Icons.filter_alt_outlined,
    Icons.filter_list, Icons.filter_list_rounded, Icons.filter_list_outlined,
  };

  static bool looksLikeSearch(TextField? tf, EditableText ed, Element el) {
    if (ed.textInputAction == TextInputAction.search) return true;
    final d = tf?.decoration;
    if (d != null) {
      if (_searchIcon(d.prefixIcon) || _searchIcon(d.icon) || _searchIcon(d.suffixIcon)) return true;
      if (_searchText(d.hintText) || _searchText(d.labelText) || _searchText(_textOf(d.hint)) || _searchText(_textOf(d.label))) {
        return true;
      }
    }
    return el.findAncestorWidgetOfExactType<SearchBar>() != null;
  }

  static String? _textOf(Widget? w) => w is Text ? w.data : null;

  static bool _searchText(String? s) {
    if (s == null) return false;
    final l = s.toLowerCase();
    return l.contains('search') || l.contains('filter') || l.contains('بحث') || l.contains('ابحث') || l.contains('تصفية') || l.contains('فلتر');
  }

  static bool _searchIcon(Widget? w) {
    for (var i = 0; i < 4 && w != null; i++) {
      if (w is Icon) return _searchIcons.contains(w.icon);
      if (w is IconButton) {
        w = w.icon;
      } else if (w is SingleChildRenderObjectWidget) {
        w = w.child; // Padding, SizedBox, Align, Opacity, …
      } else {
        return false;
      }
    }
    return false;
  }
}

// ── one pass over the form / route ──────────────────────────────────────────

class _Field {
  _Field(this.element, this.editable, this.textField, this.order);
  final Element element;
  final EditableText editable;
  final TextField? textField;
  final int order;
  bool get isSearch => _FocusedField.looksLikeSearch(textField, editable, element);
  bool get focusable => !editable.readOnly && editable.focusNode.canRequestFocus;
}

class _Candidate {
  _Candidate(this.element, this.press, this.path, this.order, {this.secondary = false});
  final Element element;
  final VoidCallback press;
  final List<Element> path;
  final int order;
  final bool secondary; // a TextButton: only counts in a dialog with no filled button
}

class _Scan {
  _Scan(this.root, {required this.focused}) {
    _walk(root);
  }

  /// The form the focused field is in: its `Form` when it has one with a button, else the route.
  factory _Scan.of(_FocusedField f) {
    Element? form;
    final root = AppKeyboard._routeRoot();
    f.editableEl.visitAncestorElements((a) {
      if (identical(a, root)) return false;
      if (a.widget is Form) {
        form = a;
        return false;
      }
      return true;
    });
    if (form != null) {
      final inForm = _Scan(form!, focused: f.editableEl);
      if (inForm.pickButton() != null) return inForm;
    }
    return _Scan(root ?? form ?? f.editableEl, focused: f.editableEl);
  }

  final Element root;
  final Element? focused;
  final fields = <_Field>[];
  final candidates = <_Candidate>[];
  final _stack = <Element>[];
  int _order = 0;
  List<Element>? _focusedPath;
  int _focusedOrder = -1;

  void _walk(Element e) {
    _stack.add(e);
    final w = e.widget;
    if ((w is Offstage && w.offstage) || (w is Visibility && !w.visible)) {
      _stack.removeLast();
      return;
    }
    final order = _order++;
    if (w is EditableText) {
      TextField? tf;
      for (var i = _stack.length - 2; i >= 0 && i >= _stack.length - 30; i--) {
        final a = _stack[i].widget;
        if (a is TextField) {
          tf = a;
          break;
        }
      }
      fields.add(_Field(e, w, tf, order));
      if (identical(e, focused)) {
        _focusedPath = List<Element>.of(_stack);
        _focusedOrder = order;
      }
    } else if (w is PrimaryButton) {
      if (w.enable && !w.isLoading && w.onPressed != null) candidates.add(_Candidate(e, w.onPressed!, List.of(_stack), order));
    } else if (w is FilledButton || w is ElevatedButton) {
      final b = w as ButtonStyleButton;
      if (b.onPressed != null) candidates.add(_Candidate(e, b.onPressed!, List.of(_stack), order));
    } else if (w is TextButton) {
      if (w.onPressed != null) candidates.add(_Candidate(e, w.onPressed!, List.of(_stack), order, secondary: true));
    } else {
      e.visitChildElements(_walk);
    }
    _stack.removeLast();
  }

  /// The next focusable field after the focused one (document order).
  EditableText? get fieldAfterFocused {
    for (final f in fields) {
      if (f.order > _focusedOrder && f.focusable && _visible(f.element)) return f.editable;
    }
    return null;
  }

  /// The button Enter presses: the enabled, visible primary button that shares the deepest ancestor with the field,
  /// preferring the first one after the field (a form ends with its submit button). A dialog whose only buttons are
  /// text buttons uses the last of them ("OK" comes last).
  _Candidate? pickButton() {
    final primary = candidates.where((c) => !c.secondary && _visible(c.element)).toList();
    if (primary.isNotEmpty) return _closest(primary);
    final focusedRoute = focused == null ? null : ModalRoute.of(focused!);
    if (focusedRoute is! PopupRoute) return null;
    final text = candidates.where((c) => c.secondary && _visible(c.element)).toList();
    if (text.isEmpty) return null;
    final after = text.where((c) => c.order > _focusedOrder).toList();
    return (after.isEmpty ? text : after).last;
  }

  _Candidate _closest(List<_Candidate> list) {
    final fp = _focusedPath ?? const <Element>[];
    _Candidate? best;
    var bestLca = -1;
    var bestAfter = false;
    for (final c in list) {
      var lca = 0;
      while (lca < fp.length && lca < c.path.length && identical(fp[lca], c.path[lca])) {
        lca++;
      }
      final after = c.order > _focusedOrder;
      final better = best == null ||
          lca > bestLca ||
          (lca == bestLca && after && !bestAfter) ||
          (lca == bestLca && after == bestAfter && (after ? c.order < best.order : c.order > best.order));
      if (better) {
        best = c;
        bestLca = lca;
        bestAfter = after;
      }
    }
    return best!;
  }
}

/// On screen: attached, laid out, and — when its centre is inside the window — reached by a hit test there (a tab
/// that is not shown, an Offstage, something under another widget). A button below the fold is taken as visible.
bool _visible(Element e) {
  final ro = e.renderObject;
  if (ro is! RenderBox || !ro.attached || !ro.hasSize) return false;
  RenderObject? top = ro;
  while (top != null && top is! RenderView) {
    top = top.parent;
  }
  if (top is! RenderView) return false;
  final center = ro.localToGlobal(ro.size.center(Offset.zero));
  if (!(Offset.zero & top.size).contains(center)) return true;
  final result = BoxHitTestResult();
  top.hitTest(result, position: center);
  for (final entry in result.path) {
    if (identical(entry.target, ro)) return true;
  }
  return false;
}
