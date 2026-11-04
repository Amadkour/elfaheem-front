// lib/design/studio/studio_layers.dart
//
// The layers panel of the studio engine, for every host: the items top-most first with a kind icon and a name.
//
//   tap          select (shift: the range from the last selected layer · ctrl / ⌘: add or remove)
//   drag handle  reorder (the z order; ONE undo step per drop)
//   eye          show / hide the layer (only when the adapter is a StudioLayersAdapter with canHide)
//   lock         lock / unlock the layer (only when the adapter is a StudioLockAdapter)
//   double tap   rename in place (only when the adapter is a StudioLayersAdapter with canRename)
//
// The panel reads and writes through the StudioController, so it works for any adapter: a host that offers none of
// the optional hooks still gets select + reorder.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../app_kit.dart' show appText;
import '../app_tokens.dart';
import 'studio_controller.dart';
import 'studio_model.dart';

/// Arabic or English text for the studio's own labels (the engine ships no translation keys of its own for these).
String studioTr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

class StudioLayersPanel<P> extends StatefulWidget {
  const StudioLayersPanel({
    super.key,
    required this.controller,
    required this.nameOf,
    required this.iconOf,
    this.rowHeight = AppTouch.min,
  });

  final StudioController<P> controller;

  /// The layer's name (a custom name, else the kind's).
  final String Function(StudioItem<P> item) nameOf;
  final IconData Function(StudioItem<P> item) iconOf;
  final double rowHeight;

  @override
  State<StudioLayersPanel<P>> createState() => _StudioLayersPanelState<P>();
}

class _StudioLayersPanelState<P> extends State<StudioLayersPanel<P>> {
  String? _renaming;
  String? _anchor;
  final _text = TextEditingController();
  final _focus = FocusNode(debugLabel: 'studio-layer-rename');

  StudioController<P> get _ctl => widget.controller;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _tap(StudioItem<P> it) {
    final k = HardwareKeyboard.instance;
    if (k.isShiftPressed && _anchor != null && _ctl.itemById(_anchor!) != null) {
      _ctl.selectRange(_anchor!, it.id, additive: k.isControlPressed || k.isMetaPressed);
      return;
    }
    _ctl.select(it.id, additive: k.isControlPressed || k.isMetaPressed);
    _anchor = it.id;
  }

  void _startRename(StudioItem<P> it) {
    if (!_ctl.layersCanRename) return;
    _text.text = widget.nameOf(it);
    _text.selection = TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    setState(() => _renaming = it.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _commitRename() {
    final id = _renaming;
    if (id == null) return;
    setState(() => _renaming = null);
    final it = _ctl.itemById(id);
    if (it != null && _text.text.trim() != widget.nameOf(it)) _ctl.renameLayer(id, _text.text);
  }

  void _cancelRename() {
    if (_renaming != null) setState(() => _renaming = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: _ctl,
      builder: (context, _) {
        final rev = _ctl.items.reversed.toList();
        if (rev.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Text(
                studioTr('لا توجد طبقات بعد', 'No layers yet'),
                textAlign: TextAlign.center,
                style: appText(13, c: c.textMedium),
              ),
            ),
          );
        }
        final canHide = _ctl.layersCanHide, canLock = _ctl.layersCanLock;
        return Semantics(
          container: true,
          label: studioTr('الطبقات', 'Layers'),
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemExtent: widget.rowHeight,
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            itemCount: rev.length,
            onReorderItem: (from, to) {
              // display index 0 is the top-most layer = the highest z
              _ctl.moveLayer(rev[from].id, rev.length - 1 - to);
            },
            proxyDecorator: (child, index, animation) => Material(
              elevation: 4,
              color: c.cardBg,
              borderRadius: AppRadius.chipAll,
              child: child,
            ),
            itemBuilder: (context, i) {
              final it = rev[i];
              final selected = _ctl.isSelected(it.id);
              final renaming = _renaming == it.id;
              final name = widget.nameOf(it);
              return Material(
                key: ValueKey('layer-${it.id}'),
                color: selected ? c.primaryTint : Colors.transparent,
                child: Semantics(
                  selected: selected,
                  label: name,
                  child: InkWell(
                    onTap: () => _tap(it),
                    onDoubleTap: _ctl.layersCanRename ? () => _startRename(it) : null,
                    child: Row(children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: Tooltip(
                          message: studioTr('اسحب لإعادة الترتيب', 'Drag to reorder'),
                          child: SizedBox(
                            width: AppTouch.min * .75,
                            height: widget.rowHeight,
                            child: Icon(Icons.drag_indicator_rounded, size: 20, color: c.textLight),
                          ),
                        ),
                      ),
                      Icon(widget.iconOf(it), size: 18, color: it.visible ? c.textMedium : c.textLight),
                      const SizedBox(width: AppSpace.xs),
                      Expanded(
                        child: renaming
                            ? Focus(
                                onKeyEvent: (node, e) {
                                  if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
                                    _cancelRename();
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                },
                                child: TextField(
                                  key: const ValueKey('layer-rename'),
                                  controller: _text,
                                  focusNode: _focus,
                                  maxLength: 60,
                                  style: appText(13, w: FontWeight.w600, c: c.textDark),
                                  decoration: const InputDecoration(isDense: true, counterText: '', border: InputBorder.none),
                                  onSubmitted: (_) => _commitRename(),
                                  onTapOutside: (_) => _commitRename(),
                                ),
                              )
                            : Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: appText(13, w: selected ? FontWeight.w700 : FontWeight.w500, c: it.visible ? c.textDark : c.textLight),
                              ),
                      ),
                      if (canHide)
                        _RowButton(
                          icon: it.visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          tooltip: it.visible ? studioTr('إخفاء', 'Hide') : studioTr('إظهار', 'Show'),
                          active: !it.visible,
                          onPressed: () => _ctl.setVisibleIds({it.id}, !it.visible),
                        ),
                      if (canLock)
                        _RowButton(
                          icon: it.locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                          tooltip: it.locked ? studioTr('إلغاء القفل', 'Unlock') : studioTr('قفل', 'Lock'),
                          active: it.locked,
                          onPressed: () => _ctl.setLockedIds({it.id}, !it.locked),
                        ),
                    ]),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _RowButton extends StatelessWidget {
  const _RowButton({required this.icon, required this.tooltip, required this.onPressed, this.active = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
      icon: Icon(icon, size: 20, color: active ? c.primary : c.textMedium),
    );
  }
}
