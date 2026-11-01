// lib/design/studio/studio_dock.dart
//
// The phone's properties panel, docked UNDER the page (never over it, never modal): a header that folds /
// unfolds it and the host's properties under it. Selecting an element opens it and asks the canvas to keep that
// element in view above it, so a single tap on the page shows its properties at once. Both studios use it below
// their side-panel width (the certificate designer's CertDockPanel, the Export Hub designer).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../app_contrast.dart';
import '../app_tokens.dart';
import 'studio_controller.dart';

class StudioDockPanel extends StatefulWidget {
  const StudioDockPanel({
    super.key,
    required this.controller,
    required this.open,
    required this.maxHeight,
    required this.title,
    required this.body,
    this.icon = Icons.tune_rounded,
    this.semanticLabel,
    this.footer,
    this.openFraction = .45,
  });

  final StudioController<Object?> controller;

  /// Open (properties shown) or folded to its header; the host may open it too (a double tap, a button).
  final ValueNotifier<bool> open;

  /// The editor's height: the open panel takes [openFraction] of it (220 – 460 px).
  final double maxHeight;
  final double openFraction;

  /// The header: what is selected ("Text", "Page", "3 selected").
  final String title;
  final IconData icon;

  /// Read by screen readers before the title ("Properties").
  final String? semanticLabel;

  /// The properties: scrolls on its own (give it a scroll view).
  final Widget body;

  /// Always visible under the panel, open or folded (a Save row).
  final Widget? footer;

  static const double headerHeight = 52;

  @override
  State<StudioDockPanel> createState() => _StudioDockPanelState();
}

class _StudioDockPanelState extends State<StudioDockPanel> {
  String? _last;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onStudio);
    widget.open.addListener(_onOpen);
  }

  @override
  void didUpdateWidget(covariant StudioDockPanel old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onStudio);
      widget.controller.addListener(_onStudio);
    }
    if (old.open != widget.open) {
      old.open.removeListener(_onOpen);
      widget.open.addListener(_onOpen);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStudio);
    widget.open.removeListener(_onOpen);
    super.dispose();
  }

  void _onStudio() {
    final id = widget.controller.single?.id;
    if (id != null && id != _last) {
      _last = id;
      if (!widget.open.value) {
        widget.open.value = true;
      } else {
        _reveal();
      }
    } else if (id == null) {
      _last = null;
    }
    if (mounted) setState(() {});
  }

  void _onOpen() {
    if (mounted) setState(() {});
    if (widget.open.value) _reveal();
  }

  /// After the panel's animation the canvas is shorter: keep the selected element in view.
  void _reveal() {
    final id = widget.controller.single?.id;
    if (id == null) return;
    Future.delayed(AppMotion.of(context).base + const Duration(milliseconds: 40), () {
      if (mounted) widget.controller.reveal(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final open = widget.open.value;
    final accent = ensureContrast(c.primary, [c.cardBg]);
    final height = open
        ? (widget.maxHeight * widget.openFraction).clamp(220.0, 460.0).toDouble()
        : StudioDockPanel.headerHeight + 1; // + the top border
    final panel = AnimatedContainer(
      duration: AppMotion.of(context).base,
      curve: AppMotion.curve,
      height: height,
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border(top: BorderSide(color: c.divider)),
        boxShadow: AppShadow.card(context),
      ),
      child: Column(children: [
        Semantics(
          button: true,
          expanded: open,
          label: widget.semanticLabel == null ? widget.title : '${widget.semanticLabel} · ${widget.title}',
          excludeSemantics: true,
          child: InkWell(
            onTap: () => widget.open.value = !open,
            child: SizedBox(
              height: StudioDockPanel.headerHeight,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, 0, AppSpace.xs, 0),
                child: Row(children: [
                  Icon(widget.icon, size: 20, color: accent),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                  ),
                  SizedBox(
                    width: AppTouch.min,
                    height: AppTouch.min,
                    child: Icon(open ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded, color: c.textMedium),
                  ),
                ]),
              ),
            ),
          ),
        ),
        // the body only where the (animating) height leaves room for it
        Expanded(
          child: open
              ? LayoutBuilder(
                  builder: (context, box) => box.maxHeight < 24
                      ? const SizedBox.shrink()
                      : Column(children: [
                          Divider(height: 1, color: c.divider),
                          Expanded(child: widget.body),
                        ]),
                )
              : const SizedBox.shrink(),
        ),
      ]),
    );
    final footer = widget.footer;
    if (footer == null) return panel;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      panel,
      Container(color: c.cardBg, child: footer),
    ]);
  }
}
