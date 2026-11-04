// lib/design/export_layout/layout_canvas.dart
//
// A v3 element list (the row card, or one band) on the shared studio engine (lib/design/studio/, used as it is):
//
//   LayoutElementsAdapter   StudioAdapter over a List<LayoutElement> — rects in mm from the top-left (physical),
//                           snapshot = the elements' JSON, restore refills the SAME list (the design keeps it)
//   LayoutCanvasEditor      toolbar (add element · the engine's commands) + StudioCanvas + the properties of the
//                           selection: docked at the side on wide screens, a non-blocking panel under the canvas on
//                           narrower ones (the engine's StudioDockPanel). Double click / long-press on a static text
//                           edits it in place on the canvas (the engine's inline editor, one undo step); on a bound
//                           field it focuses the field picker inside the docked panel (no sheet over the canvas).
//                           Right click: the engine's context menu (lock included).
//
//   The side panel / dock has two tabs: Properties and Layers (the engine's StudioLayersPanel: select, reorder,
//   lock, hide — an editor-only view setting here —, rename). The rotate knob, resize of a turned element, match
//   size and the keyboard ([ ] z order, Ctrl+L lock) come from the engine. `pageBackground` (v4 page background
//   image) is drawn under everything; `pageMargins` (mm) turns the canvas into the content box of a whole page
//   (mode "page": the paper is the page, the card is its content box — the caller passes the content width and
//   height, the row height is not involved).
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../../features/admin/admin_common.dart' show t;
import '../app_kit.dart';
import '../app_tokens.dart';
import '../studio/studio.dart';
import 'layout_element_view.dart';
import 'layout_model.dart';
import 'layout_props.dart';

/// The width of the docked properties panel beside the canvas.
const double kLayoutDockWidth = 340;

class LayoutElementsAdapter implements StudioAdapter<LayoutElement>, StudioLockAdapter, StudioLayersAdapter, StudioRotateAdapter {
  LayoutElementsAdapter(this.elements, {required this.newId});

  /// The design's own list (mutated in place).
  final List<LayoutElement> elements;
  final String Function() newId;

  /// The ids hidden in the editor (the element model has no visibility flag: this is a view setting, it is not
  /// saved, not in the history, and the element is still in the file).
  final Set<String> hidden = {};

  static StudioResize _resize(LayoutElement e) => switch (e.kind) {
        'line' => StudioResize.horizontal,
        _ => StudioResize.free,
      };

  @override
  List<StudioItem<LayoutElement>> readItems() => [
        for (final e in elements)
          StudioItem(
            id: e.id,
            rect: Rect.fromLTWH(e.x, e.y, e.w, e.h),
            payload: e,
            locked: e.locked,
            visible: !hidden.contains(e.id),
            rotation: e.rotation,
            resize: _resize(e),
            minSize: Size(2, e.kind == 'line' ? .5 : 2),
          ),
      ];

  @override
  void writeRects(Map<String, Rect> rects) {
    for (final e in elements) {
      final r = rects[e.id];
      if (r == null) continue;
      e
        ..x = mm(r.left)
        ..y = mm(r.top)
        ..w = mm(r.width)
        ..h = mm(r.height);
    }
  }

  @override
  void addItems(List<StudioItem<LayoutElement>> items) {
    for (final i in items) {
      elements.add(i.payload
        ..id = i.id
        ..x = mm(i.rect.left)
        ..y = mm(i.rect.top)
        ..w = mm(i.rect.width)
        ..h = mm(i.rect.height));
    }
  }

  @override
  void removeItems(Set<String> ids) {
    elements.removeWhere((e) => ids.contains(e.id));
    hidden.removeAll(ids);
  }

  @override
  bool get canHide => true;

  @override
  bool get hideIsUndoable => false;

  @override
  void setVisible(Set<String> ids, bool visible) => visible ? hidden.removeAll(ids) : hidden.addAll(ids);

  @override
  bool get canRename => true;

  @override
  void rename(String id, String name) {
    for (final e in elements) {
      if (e.id == id) e.name = name.isEmpty ? null : name;
    }
  }

  @override
  void writeRotations(Map<String, double> rotations) {
    for (final e in elements) {
      final r = rotations[e.id];
      if (r != null) e.rotation = double.parse(r.toStringAsFixed(1));
    }
  }

  @override
  void reorder(List<String> ids) {
    final byId = {for (final e in elements) e.id: e};
    final next = [for (final id in ids) ?byId[id], ...elements.where((e) => !ids.contains(e.id))];
    elements
      ..clear()
      ..addAll(next);
  }

  @override
  StudioItem<LayoutElement> cloneItem(StudioItem<LayoutElement> item) {
    final id = newId();
    return item.copyWith(id: id, payload: item.payload.copy(id: id), visible: true);
  }

  @override
  bool get canLock => true;

  @override
  void setLocked(Set<String> ids, bool locked) {
    for (final e in elements) {
      if (ids.contains(e.id)) e.locked = locked;
    }
  }

  @override
  Object snapshot() => [for (final e in elements) e.toJson()];

  @override
  void restore(Object snapshot) {
    elements
      ..clear()
      ..addAll([for (final j in snapshot as List) LayoutElement.fromJson((j as Map).cast<String, dynamic>())]);
  }
}

/// The "Ellipse" entry of an add menu (layout_steps.dart adds it next to Box).
LayoutAddOption layoutEllipseAddOption() => LayoutAddOption(
      t('شكل بيضاوي', 'Ellipse'),
      Icons.circle_outlined,
      (id) => LayoutElement(id: id, kind: 'ellipse', y: 1, w: 16, h: 16, style: LayoutStyle(bg: '#F2F4F7', padding: 0)),
    );

/// One "add" entry of the editor's menu: a ready element (placed by the editor).
class LayoutAddOption {
  const LayoutAddOption(this.label, this.icon, this.build, {this.centered = false, this.toBack = false});
  final String label;
  final IconData icon;
  final LayoutElement Function(String id) build;

  /// Placed in the middle of the page instead of at the start side.
  final bool centered;

  /// Inserted as the first element (drawn behind the others).
  final bool toBack;
}

class LayoutCanvasEditor extends StatefulWidget {
  const LayoutCanvasEditor({
    super.key,
    required this.elements,
    required this.width,
    required this.height,
    required this.rtl,
    required this.pageFont,
    this.pageFontSize = 10,
    required this.lang,
    required this.fields,
    required this.addOptions,
    required this.newId,
    required this.onChanged,
    required this.upload,
    this.uploadFor,
    this.extraFor,
    this.vars = const {},
    this.fieldOf,
    this.background,
    this.border,
    this.radius = 0,
    this.wide = true,
    this.backgroundImage,
    this.backgroundFit = 'cover',
    this.pageMargins,
  });

  final List<LayoutElement> elements;

  /// The canvas in mm (the card, or the band's width × height).
  final double width, height;
  final bool rtl;
  final String pageFont, lang;

  /// The page's text size (pt): elements without their own size.
  final double pageFontSize;
  final List<LayoutFieldOption> fields;
  final List<LayoutAddOption> addOptions;
  final String Function() newId;
  final VoidCallback onChanged;
  final LayoutAssetUploader upload;

  /// Optional, wins over [upload] (told the element).
  final LayoutElementUploader? uploadFor;
  final Widget? Function(BuildContext context, LayoutElement element, StudioController<LayoutElement> ctl)? extraFor;
  final Map<String, String> vars;
  final LayoutField? Function(String key)? fieldOf;
  final String? background;
  final LayoutBorder? border;
  final double radius;

  /// The properties dock at the side (else under the canvas).
  final bool wide;

  /// v4: the page background image (an asset id or an https URL) and how it fills (cover | contain | fill).
  final String? backgroundImage;
  final String backgroundFit;

  /// Mode "page": the margins (mm) of the whole page around this canvas, which is then its content box. The paper
  /// (margins included) is drawn and fitted as one and the background image fills it. Null = the canvas is the card.
  final EdgeInsets? pageMargins;

  @override
  State<LayoutCanvasEditor> createState() => _LayoutCanvasEditorState();
}

class _LayoutCanvasEditorState extends State<LayoutCanvasEditor> {
  late StudioController<LayoutElement> _ctl;
  String _sig = '';
  final _dockOpen = ValueNotifier<bool>(false);
  final _fieldFocus = FocusNode(debugLabel: 'layout-field-picker');

  /// 0 = properties, 1 = layers.
  final _tab = ValueNotifier<int>(0);
  Widget? _bg;
  String? _bgKey;

  StudioPage get _page => StudioPage(widget.width, widget.height, unitPx: kMmPx);

  @override
  void initState() {
    super.initState();
    _make();
  }

  void _make() {
    _ctl = StudioController<LayoutElement>(
      adapter: LayoutElementsAdapter(widget.elements, newId: widget.newId),
      page: _page,
      grid: const Size(1, 1),
      minSize: const Size(2, 1),
      nudgeStep: .5,
      nudgeBigStep: 5,
    )..addListener(_onCtl);
    _sig = _signature();
  }

  String _signature() => jsonEncode([for (final e in widget.elements) e.toJson()]);

  void _onCtl() {
    final s = _signature();
    if (s == _sig) {
      if (mounted) setState(() {});
      return;
    }
    _sig = s;
    widget.onChanged();
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant LayoutCanvasEditor old) {
    super.didUpdateWidget(old);
    if (!identical(old.elements, widget.elements)) {
      _ctl
        ..removeListener(_onCtl)
        ..dispose();
      _make();
    } else {
      // the controller notifies its listeners: never during this build
      final page = _page;
      final s = _signature();
      if (page != _ctl.page || s != _sig) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _ctl.page = page;
          if (_signature() != _sig) {
            // changed from outside (a template, the other tab, the row options): re-read
            _sig = _signature();
            _ctl.refresh();
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _ctl
      ..removeListener(_onCtl)
      ..dispose();
    _dockOpen.dispose();
    _tab.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  void _add(LayoutAddOption o) {
    final e = o.build(widget.newId());
    e.w = e.w.clamp(2, widget.width).toDouble();
    e.h = e.h.clamp(.5, widget.height).toDouble();
    // the start side of the design: the right of an Arabic card
    e.x = widget.rtl ? widget.width - e.w - 2 : 2;
    e.x = e.x.clamp(0, widget.width - e.w).toDouble();
    if (o.centered) {
      e.x = (widget.width - e.w) / 2;
      e.y = (widget.height - e.h) / 2;
    }
    e.y = e.y.clamp(0, widget.height - e.h).toDouble();
    _ctl.record('add', () => o.toBack ? widget.elements.insert(0, e) : widget.elements.add(e));
    _ctl.select(e.id);
  }

  /// The text an element edits in place: static text, a page number, a QR code's text (a bound field or a computed
  /// value has none: it picks a field instead).
  static String? _inlineText(StudioItem<LayoutElement> item) {
    final e = item.payload;
    if (e.locked || e.bind != null || e.computed != null) return null;
    if (e.kind == 'text' || e.kind == 'badge' || e.kind == 'page_number' || e.kind == 'qr') return e.value ?? '';
    return null;
  }

  StudioInlineStyle _inlineStyle(BuildContext context, StudioItem<LayoutElement> item, double scale) {
    final e = item.payload;
    final s = e.style;
    return StudioInlineStyle(
      style: layoutTextStyle(e, widget.pageFont, scale, layoutColor(s.color, const Color(0xFF1A1A1A))!, pageFontSize: widget.pageFontSize),
      textAlign: switch (s.align) {
        'center' => TextAlign.center,
        'end' => TextAlign.end,
        _ => TextAlign.start,
      },
      textDirection: widget.rtl ? TextDirection.rtl : TextDirection.ltr,
      multiline: s.maxLines != 1,
      padding: EdgeInsets.all((s.padding * scale).clamp(0.0, 40.0)),
      background: layoutColor(s.bg),
    );
  }

  /// Double click on an element without in-place text: its properties (the docked panel opens on a phone-width
  /// editor); on a bound field the inline field picker in that panel takes the focus — no sheet over the canvas.
  void _doubleTap(String id) {
    final e = _ctl.itemById(id)?.payload;
    if (e == null || e.locked) return;
    if (_ctl.single?.id != id) _ctl.select(id);
    if (!widget.wide) _dockOpen.value = true;
    if (e.bind == null || e.computed != null) return;
    // the panel is (re)built for this element on the next frame: focus its picker then
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fieldFocus.requestFocus();
      final at = _fieldFocus.context;
      if (at != null && at.mounted) unawaited(Scrollable.ensureVisible(at, alignment: .2, duration: AppMotion.of(context).base));
    });
  }

  Widget _addMenu(BuildContext context) => PopupMenuButton<LayoutAddOption>(
        tooltip: t('إضافة عنصر', 'Add an element'),
        onSelected: _add,
        itemBuilder: (_) => [
          for (final o in widget.addOptions)
            PopupMenuItem(
              value: o,
              height: AppTouch.min,
              child: Row(children: [Icon(o.icon, size: 20), const SizedBox(width: AppSpace.sm), Flexible(child: Text(o.label))]),
            ),
        ],
        child: StudioToolFace(icon: Icons.add_box_outlined, label: t('إضافة', 'Add'), showLabel: true),
      );

  /// A stable method (not a closure): the canvas keeps the item widgets of the elements that did not change.
  Widget _buildItem(BuildContext context, StudioItem<LayoutElement> item, bool selected) => LayoutElementView(
        element: item.payload,
        scale: StudioCanvas.scaleOf(context),
        rtl: widget.rtl,
        pageFont: widget.pageFont,
        pageFontSize: widget.pageFontSize,
        lang: widget.lang,
        vars: widget.vars,
        fieldOf: widget.fieldOf,
        ghostHidden: true,
      );

  Widget _borderOverlay(BuildContext context, double scale) {
    final b = widget.border;
    if (b == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius * scale),
          border: Border.all(color: layoutColor(b.color, const Color(0xFFD0D5DD))!, width: (b.width * scale).clamp(.5, 6.0)),
        ),
      ),
    );
  }

  /// The whole paper of mode "page": its colour, the background image, and the content box drawn dashed.
  Widget _paper(BuildContext context, double scale) {
    final m = widget.pageMargins ?? EdgeInsets.zero;
    final c = context.colors;
    return Stack(children: [
      Positioned.fill(child: _backgroundWidget()),
      Positioned(
        left: m.left * scale,
        top: m.top * scale,
        right: m.right * scale,
        bottom: m.bottom * scale,
        child: IgnorePointer(
          child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: c.divider))),
        ),
      ),
    ]);
  }

  Widget _backgroundWidget() {
    final key = '${widget.backgroundImage}|${widget.backgroundFit}';
    if (_bg == null || _bgKey != key) {
      _bgKey = key;
      _bg = LayoutPageBackground(image: widget.backgroundImage, fit: widget.backgroundFit, cacheWidth: 1600);
    }
    return _bg!;
  }

  /// Changes whenever the same elements would be drawn differently by [_buildItem].
  Object get _buildKey => Object.hash(
        widget.rtl,
        widget.pageFont,
        widget.pageFontSize,
        widget.lang,
        widget.fields.length,
        Object.hashAllUnordered(widget.vars.entries.map((e) => Object.hash(e.key, e.value))),
      );

  String _layerName(StudioItem<LayoutElement> i) => i.payload.name ?? layoutKindLabel(i.payload.kind);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sel = _ctl.single?.payload;
    final canvas = DecoratedBox(
      decoration: BoxDecoration(color: c.background, border: Border.all(color: c.divider), borderRadius: AppRadius.cardAll),
      child: ClipRRect(
        borderRadius: AppRadius.cardAll,
        child: StudioCanvas<LayoutElement>(
          key: ObjectKey(_ctl),
          controller: _ctl,
          pageColor: layoutColor(widget.background, kStudioPaper)!,
          pageBackground: widget.pageMargins == null && widget.backgroundImage != null ? _backgroundWidget() : null,
          paperInsets: widget.pageMargins ?? EdgeInsets.zero,
          paperBuilder: widget.pageMargins == null ? null : _paper,
          buildKey: Object.hash(_buildKey, widget.border?.color, widget.border?.width, widget.radius),
          padding: AppSpace.md,
          onItemDoubleTap: _doubleTap,
          inlineText: _inlineText,
          inlineStyle: _inlineStyle,
          onInlineCommit: (item, text) => item.payload.value = text,
          overlayBuilder: widget.border == null ? null : _borderOverlay,
          itemBuilder: _buildItem,
        ),
      ),
    );
    final props = sel == null
        ? _EmptyProps(wide: widget.wide)
        : LayoutElementProps(
            key: ValueKey('props-${sel.id}'),
            ctl: _ctl,
            element: sel,
            fields: widget.fields,
            upload: widget.upload,
            uploadFor: widget.uploadFor,
            extraFor: widget.extraFor,
            pageFontSize: widget.pageFontSize,
            fieldFocus: _fieldFocus,
            onClose: () => _ctl.clearSelection(),
          );
    final toolbar = StudioToolbar(controller: _ctl, leading: [_addMenu(context)]);
    final tabbed = ValueListenableBuilder<int>(
      valueListenable: _tab,
      builder: (context, tab, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xs, AppSpace.sm, AppSpace.xxs),
          child: StudioSegmented<int>(
            segments: [
              StudioSegment(value: 0, label: t('الخصائص', 'Properties'), icon: Icons.tune_rounded),
              StudioSegment(value: 1, label: t('الطبقات', 'Layers'), icon: Icons.layers_outlined),
            ],
            value: tab,
            onChanged: (v) => _tab.value = v,
          ),
        ),
        Expanded(
          child: tab == 0
              ? props
              : StudioLayersPanel<LayoutElement>(
                  key: const ValueKey('layout-layers'),
                  controller: _ctl,
                  nameOf: _layerName,
                  iconOf: (i) => layoutKindIcon(i.payload.kind),
                ),
        ),
      ]),
    );
    final panel = DecoratedBox(
      decoration: BoxDecoration(color: c.cardBg, border: Border.all(color: c.divider), borderRadius: AppRadius.cardAll),
      child: ClipRRect(borderRadius: AppRadius.cardAll, child: tabbed),
    );
    if (widget.wide) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        toolbar,
        const SizedBox(height: AppSpace.xs),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: canvas),
            const SizedBox(width: AppSpace.sm),
            SizedBox(width: kLayoutDockWidth, child: panel),
          ]),
        ),
      ]);
    }
    return LayoutBuilder(
      builder: (context, box) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        toolbar,
        const SizedBox(height: AppSpace.xs),
        Expanded(child: canvas),
        StudioDockPanel(
          controller: _ctl,
          open: _dockOpen,
          maxHeight: box.maxHeight,
          semanticLabel: t('خصائص العنصر', 'Element properties'),
          title: sel == null
              ? (_ctl.selection.length > 1 ? '${_ctl.selection.length} ${t('عناصر محددة', 'selected')}' : t('لا عنصر محدد', 'Nothing selected'))
              : (sel.name ?? layoutKindLabel(sel.kind)),
          icon: sel == null ? Icons.ads_click_rounded : Icons.tune_rounded,
          body: tabbed,
        ),
      ]),
    );
  }
}

class _EmptyProps extends StatelessWidget {
  const _EmptyProps({required this.wide});
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(children: [
        Icon(Icons.ads_click_rounded, size: 36, color: c.textLight),
        const SizedBox(height: AppSpace.sm),
        Text(t('اختر عنصرًا لتعديله', 'Select an element to edit it'), textAlign: TextAlign.center, style: appText(14, w: FontWeight.w600, c: c.textDark)),
        const SizedBox(height: AppSpace.xxs),
        Text(
          t('انقر مرتين على نص لتعديله مباشرة، واسحب لتحريك العناصر، واستخدم «إضافة» لعناصر جديدة.',
              'Double click a text to edit it in place, drag to move things, and use "Add" for new elements.'),
          textAlign: TextAlign.center,
          style: appText(12.5, c: c.textMedium),
        ),
      ]),
    );
  }
}
