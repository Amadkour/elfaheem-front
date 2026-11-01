// lib/design/studio/studio_toolbar.dart
//
// The studio's command bar: undo · redo | zoom out · zoom % (menu) · zoom in · fit | snap | align & distribute
// (menu) | delete, plus the host's own [leading] / [trailing] actions (add text, preview, save, …). From
// [wideBreakpoint] the main commands carry their label next to the icon; below it they are icons with tooltips
// and the bar scrolls sideways instead of overflowing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../app_contrast.dart';
import '../app_kit.dart' show appText;
import '../app_tokens.dart';
import '../export/export_fonts.dart' show ExportFonts;
import 'studio_controller.dart';
import 'studio_model.dart';

class StudioToolbar extends StatelessWidget {
  const StudioToolbar({
    super.key,
    required this.controller,
    this.leading = const [],
    this.trailing = const [],
    this.wideBreakpoint = 720,
  });

  final StudioController<Object?> controller;

  /// Host actions before / after the engine's commands; [StudioToolButton] gives them the same look.
  final List<Widget> leading, trailing;
  final double wideBreakpoint;

  @override
  Widget build(BuildContext context) {
    // the certificate fonts are plain assets (not pubspec fonts): registered the first time a studio shows (7.1;
    // both designers show this toolbar). Idempotent: the registration runs once per app run.
    ExportFonts.ensureCertFamilies();
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= wideBreakpoint;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: c.divider),
        ),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final ctl = controller;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs, vertical: AppSpace.xxs),
              child: Row(children: [
                ...leading,
                if (leading.isNotEmpty) const _Sep(),
                StudioToolButton(
                  icon: Icons.undo_rounded,
                  label: translate('studio_undo'),
                  showLabel: wide,
                  onPressed: ctl.canUndo ? ctl.undo : null,
                ),
                StudioToolButton(
                  icon: Icons.redo_rounded,
                  label: translate('studio_redo'),
                  showLabel: wide,
                  onPressed: ctl.canRedo ? ctl.redo : null,
                ),
                const _Sep(),
                StudioToolButton(
                  icon: Icons.remove_rounded,
                  label: translate('studio_zoom_out'),
                  onPressed: ctl.zoom > StudioController.minZoom + 1e-3 ? ctl.zoomOut : null,
                ),
                _ZoomMenu(controller: ctl),
                StudioToolButton(
                  icon: Icons.add_rounded,
                  label: translate('studio_zoom_in'),
                  onPressed: ctl.zoom < StudioController.maxZoom - 1e-3 ? ctl.zoomIn : null,
                ),
                StudioToolButton(
                  icon: Icons.fit_screen_rounded,
                  label: translate('studio_fit'),
                  showLabel: wide,
                  active: ctl.fitted,
                  onPressed: ctl.fitPage,
                ),
                const _Sep(),
                StudioToolButton(
                  icon: Icons.grid_4x4_rounded,
                  label: translate('studio_snap'),
                  showLabel: wide,
                  active: ctl.snapEnabled,
                  onPressed: ctl.toggleSnap,
                ),
                _AlignMenu(controller: ctl, showLabel: wide),
                const _Sep(),
                StudioToolButton(
                  icon: Icons.delete_outline_rounded,
                  label: translate('studio_delete'),
                  showLabel: wide,
                  danger: true,
                  onPressed: ctl.selection.any((id) => !(ctl.itemById(id)?.locked ?? true)) ? ctl.deleteSelection : null,
                ),
                if (trailing.isNotEmpty) const _Sep(),
                ...trailing,
              ]),
            );
          },
        ),
      );
    });
  }
}

/// One toolbar command: icon, and its label beside it when [showLabel] (else the label is the tooltip).
/// A 48 px target either way.
class StudioToolButton extends StatelessWidget {
  const StudioToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.showLabel = false,
    this.active = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool showLabel, active, danger;

  @override
  Widget build(BuildContext context) {
    final face = StudioToolFace(
      icon: icon,
      label: label,
      showLabel: showLabel,
      active: active,
      danger: danger,
      enabled: onPressed != null,
    );
    final button = Semantics(
      button: true,
      enabled: onPressed != null,
      toggled: active ? true : null,
      label: showLabel ? null : label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppRadius.chipAll,
        child: face,
      ),
    );
    return showLabel ? button : Tooltip(message: label, child: button);
  }
}

/// The look of a toolbar command without its tap (menus wrap it).
class StudioToolFace extends StatelessWidget {
  const StudioToolFace({
    super.key,
    required this.icon,
    required this.label,
    this.showLabel = false,
    this.active = false,
    this.danger = false,
    this.enabled = true,
    this.trailingIcon,
  });

  final IconData icon;
  final String label;
  final bool showLabel, active, danger, enabled;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Readable on the bar in both themes (the raw indigo is ~2:1 on the dark surfaces).
    final tint = Color.alphaBlend(c.primaryTint, c.cardBg);
    final fg = !enabled
        ? c.textLight
        : (danger ? ensureContrast(c.danger, [c.cardBg]) : (active ? ensureContrast(c.primary, [tint, c.cardBg]) : c.textDark));
    return AnimatedContainer(
      duration: AppMotion.of(context).fast,
      curve: AppMotion.curve,
      constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
      padding: EdgeInsets.symmetric(horizontal: showLabel ? AppSpace.sm : AppSpace.xs),
      decoration: BoxDecoration(
        color: active ? c.primaryTint : null,
        borderRadius: AppRadius.chipAll,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 20, color: fg),
        if (showLabel) ...[
          const SizedBox(width: AppSpace.xs - 2),
          Text(label, maxLines: 1, style: appText(13, w: FontWeight.w600, c: fg)),
        ],
        if (trailingIcon != null) Icon(trailingIcon, size: 16, color: fg),
      ]),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: AppSpace.lg,
        margin: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
        color: context.colors.divider,
      );
}

class _ZoomMenu extends StatelessWidget {
  const _ZoomMenu({required this.controller});
  final StudioController<Object?> controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pct = '${(controller.zoom * 100).round()}%';
    return PopupMenuButton<double>(
      tooltip: translate('studio_zoom'),
      onSelected: (v) => v < 0 ? controller.fitPage() : controller.setZoom(v),
      itemBuilder: (context) => [
        PopupMenuItem<double>(value: -1, child: Text(translate('studio_fit'), style: appText(14, c: c.textDark))),
        const PopupMenuDivider(),
        for (final z in StudioController.zoomSteps.reversed)
          PopupMenuItem<double>(
            value: z,
            child: Text('${(z * 100).round()}%', style: appText(14, c: c.textDark)),
          ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 60, minHeight: AppTouch.min),
        child: Center(
          child: Text(
            pct,
            style: appText(13, w: FontWeight.w600, c: c.textDark)
                .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
      ),
    );
  }
}

class _AlignMenu extends StatelessWidget {
  const _AlignMenu({required this.controller, required this.showLabel});
  final StudioController<Object?> controller;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = controller.hasEditableSelection;
    PopupMenuItem<String> row(String value, IconData icon, String key, {bool on = true}) => PopupMenuItem<String>(
          value: value,
          enabled: on,
          child: Row(children: [
            Icon(icon, size: 20, color: on ? c.textMedium : c.textLight),
            const SizedBox(width: AppSpace.sm),
            Flexible(child: Text(translate(key), style: appText(14, c: on ? c.textDark : c.textLight))),
          ]),
        );
    return PopupMenuButton<String>(
      enabled: enabled,
      tooltip: translate('studio_align'),
      onSelected: (v) {
        switch (v) {
          case 'dh':
            controller.distribute(StudioAxis.horizontal);
          case 'dv':
            controller.distribute(StudioAxis.vertical);
          case 'page':
            controller.alignToPage = !controller.alignToPage;
          default:
            controller.align(StudioAlign.values.byName(v));
        }
      },
      itemBuilder: (context) => [
        row('left', Icons.align_horizontal_left_rounded, 'studio_align_left'),
        row('centerH', Icons.align_horizontal_center_rounded, 'studio_align_center_h'),
        row('right', Icons.align_horizontal_right_rounded, 'studio_align_right'),
        const PopupMenuDivider(),
        row('top', Icons.align_vertical_top_rounded, 'studio_align_top'),
        row('middle', Icons.align_vertical_center_rounded, 'studio_align_middle'),
        row('bottom', Icons.align_vertical_bottom_rounded, 'studio_align_bottom'),
        const PopupMenuDivider(),
        row('dh', Icons.horizontal_distribute_rounded, 'studio_distribute_h', on: controller.canDistribute),
        row('dv', Icons.vertical_distribute_rounded, 'studio_distribute_v', on: controller.canDistribute),
        const PopupMenuDivider(),
        CheckedPopupMenuItem<String>(
          value: 'page',
          checked: controller.alignToPage,
          child: Text(translate('studio_align_to_page'), style: appText(14, c: c.textDark)),
        ),
      ],
      child: StudioToolFace(
        icon: Icons.align_horizontal_center_rounded,
        label: translate('studio_align'),
        showLabel: showLabel,
        enabled: enabled,
        trailingIcon: Icons.expand_more_rounded,
      ),
    );
  }
}
