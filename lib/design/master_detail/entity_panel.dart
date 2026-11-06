// lib/design/master_detail/entity_panel.dart — the chrome of the detail panel (D-290).
//
//   ┌ back · forward ·········· previous · next · open full page · close ┐   (the sheet adds a drag handle above)
//   │ Students › Sara Ali › Python Basics                                │   breadcrumbs, once the trail has 2 entries
//   ├────────────────────────────────────────────────────────────────────┤
//   │ EntityDetailView (header · badges · stats · sections)              │
//   └────────────────────────────────────────────────────────────────────┘
//
// The same panel is the inline side panel, the overlay, the phone's bottom sheet and the full page ([EntityPanelMode]).
// It is a labelled region for screen readers; links inside it drill in (MasterDetailScope.inPanel).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';

import '../app_kit.dart';
import 'entity_chip.dart';
import 'entity_detail_view.dart';
import 'entity_navigator.dart';
import 'entity_panel_controller.dart';

enum EntityPanelMode { inline, overlay, sheet, page }

class EntityPanel extends StatelessWidget {
  const EntityPanel({
    super.key,
    required this.controller,
    this.mode = EntityPanelMode.inline,
    this.actions,
    this.rootLabel,
    this.scrollController,
    this.onHandleDrag,
    this.onHandleTap,
    this.onPageBack,
  });

  final EntityPanelController controller;
  final EntityPanelMode mode;
  final EntityActionsBuilder? actions;

  /// The list's name, the first breadcrumb ("Students"): a tap closes the panel.
  final String? rootLabel;

  /// The sheet's scroll controller (DraggableScrollableSheet).
  final ScrollController? scrollController;

  /// The sheet's handle: dragged (the delta in pixels) / tapped.
  final ValueChanged<double>? onHandleDrag;
  final VoidCallback? onHandleTap;

  /// The full page's Back (null: Navigator.maybePop).
  final VoidCallback? onPageBack;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final current = controller.current;
        if (current == null) return const SizedBox.shrink();
        final c = context.colors;
        final trail = controller.trail;
        final name = current.name;
        return MasterDetailScope(
          controller: controller,
          inPanel: true,
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            label: name.isEmpty ? 'md_panel_label'.tr : '${'md_panel_label'.tr}: $name',
            child: Material(
              color: c.cardBg,
              surfaceTintColor: Colors.transparent,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (mode == EntityPanelMode.sheet) _SheetHandle(onDrag: onHandleDrag, onTap: onHandleTap),
                _ChromeBar(controller: controller, mode: mode, onPageBack: onPageBack),
                if (trail.length > 1 || (rootLabel != null && mode != EntityPanelMode.page))
                  _Breadcrumbs(controller: controller, trail: trail, rootLabel: mode == EntityPanelMode.page ? null : rootLabel),
                Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
                Expanded(
                  child: EntityDetailView(
                    key: ValueKey('md.detail.${current.toToken()}'),
                    entity: _withSiblingLabel(current),
                    controller: controller,
                    actions: actions,
                    scrollController: scrollController,
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  /// The row's own name / picture when the ref came without one (a keyboard step, a deep link).
  EntityRef _withSiblingLabel(EntityRef r) {
    if (r.label != null) return r;
    for (final s in controller.siblings) {
      if (s == r) return r.withLabel(label: s.label, labelEn: s.labelEn, imageUrl: s.imageUrl);
    }
    return r;
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle({this.onDrag, this.onTap});

  final ValueChanged<double>? onDrag;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'md_sheet_handle'.tr,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onVerticalDragUpdate: onDrag == null ? null : (d) => onDrag!(d.delta.dy),
        child: SizedBox(
          height: AppSpace.lg,
          child: Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: c.textLight.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChromeBar extends StatelessWidget {
  const _ChromeBar({required this.controller, required this.mode, this.onPageBack});

  final EntityPanelController controller;
  final EntityPanelMode mode;
  final VoidCallback? onPageBack;

  @override
  Widget build(BuildContext context) {
    final page = mode == EntityPanelMode.page;
    final current = controller.current!;
    final inList = !page && controller.siblingIndex >= 0;
    final total = controller.siblings.length;
    final pos = controller.siblingIndex + 1;
    return LayoutBuilder(builder: (context, box) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs, vertical: AppSpace.xxs),
      child: Row(children: [
        if (page)
          AppIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'md_back_page'.tr,
            onPressed: onPageBack ?? () => Navigator.of(context).maybePop(),
          ),
        if (controller.trail.length > 1 || controller.canForward) ...[
          AppIconButton(
            key: const ValueKey('md.back'),
            icon: Icons.arrow_back_rounded,
            tooltip: 'md_back'.tr,
            onPressed: controller.canBack ? controller.back : null,
          ),
          AppIconButton(
            key: const ValueKey('md.forward'),
            icon: Icons.arrow_forward_rounded,
            tooltip: 'md_forward'.tr,
            onPressed: controller.canForward ? controller.forward : null,
          ),
        ],
        const Spacer(),
        if (inList && total > 1) ...[
          if (box.maxWidth >= 400)
            ExcludeSemantics(
            child: Text('$pos / $total',
                style: AppType.meta(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          AppIconButton(
            key: const ValueKey('md.previous'),
            icon: Icons.keyboard_arrow_up_rounded,
            tooltip: 'md_previous'.tr,
            onPressed: controller.hasPrevious ? controller.previous : null,
          ),
          AppIconButton(
            key: const ValueKey('md.next'),
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: 'md_next'.tr,
            onPressed: controller.hasNext ? controller.next : null,
          ),
        ],
        if (!page)
          AppIconButton(
            key: const ValueKey('md.full_page'),
            icon: Icons.open_in_full_rounded,
            tooltip: 'md_open_full'.tr,
            onPressed: () => EntityNavigator.openFullPage(context, current, from: controller.contextRef),
          ),
        if (!page)
          AppIconButton(
            key: const ValueKey('md.close'),
            icon: Icons.close_rounded,
            tooltip: 'md_close'.tr,
            onPressed: controller.close,
          ),
      ]),
    ));
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.controller, required this.trail, this.rootLabel});

  final EntityPanelController controller;
  final List<EntityRef> trail;
  final String? rootLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = <Widget>[];
    void sep() => items.add(ExcludeSemantics(
          child: Icon(Icons.chevron_right_rounded, size: AppIconSize.sm, color: c.textLight),
        ));
    if (rootLabel != null) {
      items.add(_Crumb(label: rootLabel!, onTap: controller.close));
    }
    for (var i = 0; i < trail.length; i++) {
      if (items.isNotEmpty) sep();
      final r = trail[i];
      final label = r.name.isEmpty ? '${entityKindLabel(r.kind)} #${r.id}' : r.name;
      items.add(_Crumb(label: label, onTap: i == trail.length - 1 ? null : () => controller.jumpTo(i)));
    }
    return Semantics(
      label: 'md_breadcrumbs'.tr,
      container: true,
      explicitChildNodes: true,
      child: SizedBox(
        height: AppTouch.min,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
          child: Row(children: items),
        ),
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final current = onTap == null;
    final text = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: current
              ? AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)
              : AppType.label(context).copyWith(
                  color: c.textDark, decoration: TextDecoration.underline, decorationColor: c.textMedium)),
    );
    if (current) {
      return Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs), child: text);
    }
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.chipAll,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min, minWidth: AppTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
            child: Center(widthFactor: 1, child: text),
          ),
        ),
      ),
    );
  }
}
