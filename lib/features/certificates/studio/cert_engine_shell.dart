// features/certificates/studio/cert_engine_shell.dart
//
// The workspace of the certificate studio (D-387): plain values and slots in, no provider read and no document owned.
//
//   wide (≥ 1180 px)    top bar · rail + open tool panel · canvas · inspector
//   medium (720-1180)   top bar · rail, the tool panel floats over the canvas · canvas · inspector
//   compact (< 720)     short top bar · canvas first · a non-modal sheet (a tool or the inspector) · bottom tool bar
//
// The top bar holds what the person watches while working: the name, one save status understood at a glance, undo /
// redo, zoom, the Arabic / English switch, preview and ONE primary action (Save while there is something to save,
// then Issue). Nothing here redraws on a drag: the bar's zoom and undo follow the controller through small listeners.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'package:flutter_education_app/design/app_contrast.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/export_layout/layout_canvas.dart' show LayoutAddOption;
import 'package:flutter_education_app/design/export_layout/layout_model.dart';
import 'package:flutter_education_app/design/studio/studio.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/certificates/studio/cert_engine_api.dart' show CertServerTemplate;

/// What the save status says.
enum CertSaveState { saved, unsaved, saving, conflict }

/// The left rail's tools; [inspector] exists only as a sheet on a phone.
enum CertTool { templates, wordings, elements, fields, images, layers, inspector }

const double kCertWide = 1180, kCertCompact = 720;
const double kCertPanelWidth = 272, kCertInspectorWidth = 320, kCertRailWidth = 76;

/// The backdrop behind the page: one step away from the app's background, so the paper is the brightest thing there.
Color certBackdrop(BuildContext context) {
  final c = context.colors;
  return Color.alphaBlend(c.textDark.withValues(alpha: c.isDark ? .05 : .045), c.background);
}

/// The status pill: a check when saved, a dot when not, red when it was saved elsewhere meanwhile.
class CertStatusPill extends StatelessWidget {
  const CertStatusPill({super.key, required this.state, this.onConflict});
  final CertSaveState state;
  final VoidCallback? onConflict;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (Color tone, String label, IconData? icon) = switch (state) {
      CertSaveState.saved => (c.success, t('كل التعديلات محفوظة', 'All changes saved'), Icons.check_rounded),
      CertSaveState.unsaved => (c.warning, t('تعديلات غير محفوظة', 'Unsaved changes'), null),
      CertSaveState.saving => (c.primary, t('جارٍ الحفظ…', 'Saving…'), null),
      CertSaveState.conflict => (c.danger, t('حُفظ في مكان آخر: اضغط للحل', 'Saved elsewhere: tap to resolve'), Icons.error_outline_rounded),
    };
    final ink = ensureContrast(tone, [c.cardBg]);
    final body = Row(mainAxisSize: MainAxisSize.min, children: [
      if (state == CertSaveState.saving)
        SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.8, color: ink))
      else if (icon != null)
        Icon(icon, size: AppIconSize.xs, color: ink)
      else
        Container(width: 8, height: 8, decoration: BoxDecoration(color: ink, shape: BoxShape.circle)),
      const SizedBox(width: AppSpace.xxs + 2),
      Flexible(
        child: Text(label, key: const ValueKey('cert-save-state'), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, w: FontWeight.w500, c: state == CertSaveState.saved ? c.textMedium : ink)),
      ),
    ]);
    if (state != CertSaveState.conflict) return Semantics(liveRegion: true, child: body);
    return Semantics(
      button: true,
      liveRegion: true,
      child: InkWell(
        key: const ValueKey('cert-conflict-pill'),
        borderRadius: AppRadius.chipAll,
        onTap: onConflict,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: 2),
          decoration: BoxDecoration(color: tone.withValues(alpha: .12), borderRadius: AppRadius.chipAll),
          child: body,
        ),
      ),
    );
  }
}

/// The one primary action of the top bar.
class CertPrimaryAction extends StatelessWidget {
  const CertPrimaryAction({super.key, required this.state, required this.onSave, required this.onIssue, this.compact = false, this.iconOnly = false});
  final CertSaveState state;
  final VoidCallback onSave;
  final VoidCallback? onIssue;
  final bool compact;

  /// A narrow phone: the icon alone (the label is its tooltip), so the design's name and status keep their room.
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final saving = state == CertSaveState.saving;
    final needsSave = state == CertSaveState.unsaved || state == CertSaveState.conflict;
    final issue = !needsSave && !saving ? onIssue : null;
    final height = compact ? AppTouch.min - 8 : AppTouch.min - 4;
    final style = FilledButton.styleFrom(minimumSize: Size(compact ? AppTouch.min : 88, height), padding: EdgeInsets.symmetric(horizontal: compact ? AppSpace.sm : AppSpace.md), shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll));
    if (iconOnly) {
      final (IconData icon, String tip, VoidCallback? go, String key) = issue != null
          ? (Icons.workspace_premium_outlined, t('إصدار', 'Issue'), issue, 'cert-issue')
          : (needsSave ? Icons.save_outlined : Icons.check_rounded, t('حفظ', 'Save'), needsSave ? onSave : null, 'cert-save');
      return Tooltip(
        message: tip,
        child: FilledButton(
          key: ValueKey(key),
          onPressed: saving ? null : go,
          style: FilledButton.styleFrom(minimumSize: Size(AppTouch.min, height), padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll)),
          child: saving ? const SizedBox(width: AppIconSize.sm, height: AppIconSize.sm, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon, size: AppIconSize.md),
        ),
      );
    }
    if (issue != null) {
      return FilledButton.icon(key: const ValueKey('cert-issue'), onPressed: issue, style: style, icon: const Icon(Icons.workspace_premium_outlined, size: AppIconSize.md), label: Text(t('إصدار', 'Issue')));
    }
    return FilledButton.icon(
      key: const ValueKey('cert-save'),
      onPressed: needsSave ? onSave : null,
      style: style,
      icon: saving
          ? const SizedBox(width: AppIconSize.sm, height: AppIconSize.sm, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(needsSave ? Icons.save_outlined : Icons.check_rounded, size: AppIconSize.md),
      label: Text(saving ? t('جارٍ الحفظ', 'Saving') : (needsSave ? t('حفظ', 'Save') : t('محفوظ', 'Saved'))),
    );
  }
}

/// The Arabic / English switch: which design is on the canvas.
class CertLangSwitch extends StatelessWidget {
  const CertLangSwitch({super.key, required this.languages, required this.lang, required this.onLang});
  final List<String> languages;
  final String lang;
  final ValueChanged<String> onLang;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final l in languages)
          Semantics(
            button: true,
            selected: l == lang,
            child: InkWell(
              key: ValueKey('cert-tab-$l'),
              borderRadius: BorderRadius.circular(AppRadius.chip - 3),
              onTap: () => onLang(l),
              child: AnimatedContainer(
                duration: motion.fast,
                curve: AppMotion.curve,
                constraints: const BoxConstraints(minHeight: AppTouch.min - 14, minWidth: 56),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                decoration: BoxDecoration(color: l == lang ? c.cardBg : null, borderRadius: BorderRadius.circular(AppRadius.chip - 3), boxShadow: l == lang ? c.cardShadow : null),
                child: Text(l == 'ar' ? t('العربية', 'Arabic') : 'English', style: appText(13, w: l == lang ? FontWeight.w600 : FontWeight.w500, c: l == lang ? c.textDark : c.textMedium)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// The zoom cluster of the top bar: −, the percentage (a menu), +, fit.
class CertZoomCluster extends StatelessWidget {
  const CertZoomCluster({super.key, required this.ctl});
  final StudioController<Object?> ctl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, children: [
        StudioToolButton(icon: Icons.remove_rounded, label: translate('studio_zoom_out'), onPressed: ctl.zoom > StudioController.minZoom + 1e-3 ? ctl.zoomOut : null),
        PopupMenuButton<double>(
          key: const ValueKey('cert-zoom'),
          tooltip: translate('studio_zoom'),
          onSelected: (v) => v < 0 ? ctl.fitPage() : ctl.setZoom(v),
          itemBuilder: (_) => [
            PopupMenuItem<double>(value: -1, child: Text(translate('studio_fit'), style: appText(14, c: c.textDark))),
            const PopupMenuDivider(),
            for (final z in StudioController.zoomSteps.reversed) PopupMenuItem<double>(value: z, child: Text('${(z * 100).round()}%', style: appText(14, c: c.textDark))),
          ],
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 52, minHeight: AppTouch.min),
            child: Center(child: Text('${(ctl.zoom * 100).round()}%', style: appText(13, w: FontWeight.w600, c: c.textDark).copyWith(fontFeatures: const [FontFeature.tabularFigures()]))),
          ),
        ),
        StudioToolButton(icon: Icons.add_rounded, label: translate('studio_zoom_in'), onPressed: ctl.zoom < StudioController.maxZoom - 1e-3 ? ctl.zoomIn : null),
        StudioToolButton(icon: Icons.fit_screen_rounded, label: translate('studio_fit'), active: ctl.fitted, onPressed: ctl.fitPage),
      ]),
    );
  }
}

/// Undo and redo, following the controller's history.
class CertUndoRedo extends StatelessWidget {
  const CertUndoRedo({super.key, required this.ctl});
  final StudioController<Object?> ctl;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: ctl,
        builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, children: [
          StudioToolButton(key: const ValueKey('cert-undo'), icon: Icons.undo_rounded, label: translate('studio_undo'), onPressed: ctl.canUndo ? ctl.undo : null),
          StudioToolButton(key: const ValueKey('cert-redo'), icon: Icons.redo_rounded, label: translate('studio_redo'), onPressed: ctl.canRedo ? ctl.redo : null),
        ]),
      );
}

/// Snap, grid and rulers: off the canvas unless they help.
class CertViewMenu extends StatelessWidget {
  const CertViewMenu({super.key, required this.ctl});
  final StudioController<Object?> ctl;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        key: const ValueKey('cert-view'),
        tooltip: t('العرض', 'View'),
        onSelected: (v) {
          switch (v) {
            case 'snap':
              ctl.toggleSnap();
            case 'grid':
              ctl.showGrid = !ctl.showGrid;
            case 'rulers':
              ctl.showRulers = !ctl.showRulers;
          }
        },
        itemBuilder: (_) => [
          CheckedPopupMenuItem(value: 'snap', checked: ctl.snapEnabled, child: Text(t('المحاذاة التلقائية', 'Smart alignment'))),
          CheckedPopupMenuItem(value: 'grid', checked: ctl.showGrid, child: Text(t('الشبكة', 'Grid'))),
          CheckedPopupMenuItem(value: 'rulers', checked: ctl.showRulers, child: Text(t('المساطر', 'Rulers'))),
        ],
        child: StudioToolFace(icon: Icons.grid_4x4_rounded, label: t('العرض', 'View'), trailingIcon: Icons.expand_more_rounded),
      );
}

/// The top bar on a computer or a tablet.
class CertTopBar extends StatelessWidget {
  const CertTopBar({
    super.key,
    required this.title,
    required this.onRename,
    required this.saveState,
    required this.onBack,
    required this.onConflict,
    required this.ctl,
    required this.languages,
    required this.lang,
    required this.onLang,
    required this.onManageLanguages,
    required this.onPreview,
    required this.onSave,
    required this.onIssue,
    required this.more,
    required this.compact,
    this.keyboardAction,
  });

  final String title;
  final VoidCallback onRename, onBack, onConflict, onPreview, onSave, onManageLanguages;
  final VoidCallback? onIssue;
  final ValueListenable<CertSaveState> saveState;
  final StudioController<Object?>? ctl;
  final List<String> languages;
  final String lang;
  final ValueChanged<String> onLang;
  final Widget more;
  final bool compact;

  /// The slot for the keyboard shortcuts button (a [StudioToolButton]).
  final Widget? keyboardAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ctl = this.ctl;
    final nameBlock = ValueListenableBuilder<CertSaveState>(
      valueListenable: saveState,
      builder: (context, s, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Semantics(
          button: true,
          label: t('إعادة تسمية التصميم', 'Rename the design'),
          child: InkWell(
            key: const ValueKey('cert-title'),
            borderRadius: AppRadius.chipAll,
            onTap: onRename,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(compact ? 14 : 15, w: FontWeight.w600, c: c.textDark))),
              if (!compact) ...[
                const SizedBox(width: AppSpace.xxs),
                Icon(Icons.edit_outlined, size: AppIconSize.xs, color: c.textLight),
              ],
            ]),
          ),
        ),
        Flexible(child: CertStatusPill(state: s, onConflict: onConflict)),
      ]),
    );

    Widget primary({bool iconOnly = false}) => ValueListenableBuilder<CertSaveState>(
          valueListenable: saveState,
          builder: (context, s, _) => CertPrimaryAction(state: s, onSave: onSave, onIssue: onIssue, compact: compact, iconOnly: iconOnly),
        );

    return Container(
      constraints: BoxConstraints(minHeight: compact ? 56 : 64),
      padding: EdgeInsetsDirectional.only(start: AppSpace.xxs, end: compact ? AppSpace.xs : AppSpace.md),
      decoration: BoxDecoration(color: c.cardBg, border: Border(bottom: BorderSide(color: c.divider))),
      child: compact
          ? LayoutBuilder(
              builder: (context, box) => Row(children: [
                AppBackButton(onPressed: onBack),
                Expanded(child: nameBlock),
                StudioToolButton(key: const ValueKey('cert-preview'), icon: Icons.visibility_outlined, label: t('معاينة', 'Preview'), onPressed: onPreview),
                more,
                const SizedBox(width: AppSpace.xxs),
                primary(iconOnly: box.maxWidth < 360),
              ]),
            )
          : LayoutBuilder(builder: (context, box) {
              final roomy = box.maxWidth >= 1040;
              final hasZoom = roomy && ctl != null;
              return Row(children: [
                AppBackButton(onPressed: onBack),
                const SizedBox(width: AppSpace.xxs),
                Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: nameBlock)),
                if (ctl != null) ...[
                  const SizedBox(width: AppSpace.sm),
                  CertUndoRedo(ctl: ctl),
                  if (hasZoom) ...[
                    _divider(context),
                    CertZoomCluster(ctl: ctl),
                  ],
                  _divider(context),
                  CertViewMenu(ctl: ctl),
                ],
                ?keyboardAction,
                if (languages.length > 1) ...[
                  const SizedBox(width: AppSpace.xs),
                  CertLangSwitch(languages: languages, lang: lang, onLang: onLang),
                ] else ...[
                  const SizedBox(width: AppSpace.xs),
                  _AddLanguage(lang: languages.first, onTap: onManageLanguages),
                ],
                const SizedBox(width: AppSpace.sm),
                more,
                const SizedBox(width: AppSpace.xs),
                OutlinedButton.icon(
                  key: const ValueKey('cert-preview'),
                  onPressed: onPreview,
                  icon: const Icon(Icons.visibility_outlined, size: AppIconSize.md),
                  label: Text(t('معاينة', 'Preview')),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(88, AppTouch.min - 4), padding: const EdgeInsets.symmetric(horizontal: AppSpace.md), shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll)),
                ),
                const SizedBox(width: AppSpace.xs),
                primary(),
              ]);
            }),
    );
  }

  Widget _divider(BuildContext context) => Container(width: 1, height: AppSpace.lg, margin: const EdgeInsets.symmetric(horizontal: AppSpace.xs), color: context.colors.divider);
}

class _AddLanguage extends StatelessWidget {
  const _AddLanguage({required this.lang, required this.onTap});
  final String lang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final other = lang == 'ar' ? 'English' : t('العربية', 'Arabic');
    return Tooltip(
      message: t('أضف تصميمًا بلغة أخرى', 'Add a design in another language'),
      child: InkWell(
        key: const ValueKey('cert-add-language'),
        borderRadius: AppRadius.chipAll,
        onTap: onTap,
        child: Container(
          height: AppTouch.min - 12,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
          decoration: BoxDecoration(borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_rounded, size: AppIconSize.sm, color: c.textMedium),
            const SizedBox(width: AppSpace.xxs),
            Text(other, style: appText(13, w: FontWeight.w500, c: c.textMedium)),
          ]),
        ),
      ),
    );
  }
}

/// One tool of the rail.
class _RailItem {
  const _RailItem(this.tool, this.icon, this.label);
  final CertTool tool;
  final IconData icon;
  final String label;
}

List<_RailItem> _railItems() => [
      _RailItem(CertTool.templates, Icons.dashboard_customize_outlined, t('القوالب', 'Templates')),
      _RailItem(CertTool.wordings, Icons.format_quote_rounded, t('الصيغ', 'Wordings')),
      _RailItem(CertTool.elements, Icons.category_outlined, t('العناصر', 'Elements')),
      _RailItem(CertTool.fields, Icons.data_object_rounded, t('الحقول', 'Fields')),
      _RailItem(CertTool.images, Icons.image_outlined, t('الصور', 'Images')),
      _RailItem(CertTool.layers, Icons.layers_outlined, t('الطبقات', 'Layers')),
    ];

String certToolTitle(CertTool tool) => switch (tool) {
      CertTool.templates => t('القوالب', 'Templates'),
      CertTool.wordings => t('صيغ جاهزة', 'Ready wordings'),
      CertTool.elements => t('العناصر', 'Elements'),
      CertTool.fields => t('الحقول', 'Fields'),
      CertTool.images => t('الصور', 'Images'),
      CertTool.layers => t('الطبقات', 'Layers'),
      CertTool.inspector => t('الخصائص', 'Properties'),
    };

class _RailButton extends StatelessWidget {
  const _RailButton({required this.item, required this.selected, required this.onTap, this.width = kCertRailWidth - AppSpace.sm});
  final _RailItem item;
  final bool selected;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = ensureContrast(c.primary, [c.cardBg]);
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('cert-rail-${item.tool.name}'),
        borderRadius: AppRadius.chipAll,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.of(context).fast,
          curve: AppMotion.curve,
          width: width,
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          decoration: BoxDecoration(color: selected ? c.primaryTint : null, borderRadius: AppRadius.chipAll),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(item.icon, size: AppIconSize.md, color: selected ? accent : c.textMedium),
            const SizedBox(height: AppSpace.xxs),
            Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11, w: selected ? FontWeight.w600 : FontWeight.w500, c: selected ? accent : c.textMedium)),
          ]),
        ),
      ),
    );
  }
}

/// The tool bar on a phone: the canvas stays first, tools come up as a sheet over it.
class CertBottomTools extends StatelessWidget {
  const CertBottomTools({super.key, required this.tool, required this.onTool, required this.inspectIcon, required this.inspectLabel});
  final CertTool? tool;
  final ValueChanged<CertTool> onTool;
  final IconData inspectIcon;
  final String inspectLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = [..._railItems(), _RailItem(CertTool.inspector, inspectIcon, inspectLabel)];
    return Container(
      decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider))),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs, vertical: AppSpace.xxs),
      child: Row(children: [
        for (final it in items)
          Expanded(
            child: _RailButton(item: it, selected: tool == it.tool, width: double.infinity, onTap: () => onTool(it.tool)),
          ),
      ]),
    );
  }
}

/// A panel's frame on a computer: the title, close, and the tool under it.
class CertToolPanel extends StatelessWidget {
  const CertToolPanel({super.key, required this.tool, required this.child, required this.onClose, this.floating = false});
  final CertTool tool;
  final Widget child;
  final VoidCallback onClose;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: kCertPanelWidth,
      decoration: BoxDecoration(
        color: c.cardBg,
        border: BorderDirectional(end: BorderSide(color: c.divider)),
        boxShadow: floating ? AppElevation.of(context, 3) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xs, AppSpace.xxs, AppSpace.xs),
          child: Row(children: [
            Expanded(child: Text(certToolTitle(tool), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(15, w: FontWeight.w600, c: c.textDark))),
            IconButton(key: const ValueKey('cert-panel-close'), tooltip: t('إغلاق', 'Close'), onPressed: onClose, icon: Icon(Icons.close_rounded, size: AppIconSize.md, color: c.textMedium)),
          ]),
        ),
        Expanded(child: child),
      ]),
    );
  }
}

/// Ready elements as a grid of tiles: icon over label, one tap adds it to the page.
class CertAddGrid extends StatelessWidget {
  const CertAddGrid({super.key, required this.options, required this.onAdd, this.hint, this.footer});
  final List<LayoutAddOption> options;
  final ValueChanged<LayoutAddOption> onAdd;
  final String? hint;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
      children: [
        if (hint != null) ...[
          Text(hint!, style: appText(12.5, c: c.textMedium, h: 1.45)),
          const SizedBox(height: AppSpace.sm),
        ],
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: AppSpace.xs,
          mainAxisSpacing: AppSpace.xs,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.25,
          children: [for (final o in options) _AddTile(option: o, onTap: () => onAdd(o))],
        ),
        if (footer != null) ...[const SizedBox(height: AppSpace.sm), footer!],
      ],
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.option, required this.onTap});
  final LayoutAddOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.inputBg,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll, side: BorderSide(color: c.divider)),
      child: InkWell(
        key: ValueKey('cert-add-${option.label}'),
        borderRadius: AppRadius.chipAll,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xs),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(option.icon, size: AppIconSize.lg, color: c.textMedium),
            const SizedBox(height: AppSpace.xxs + 2),
            Text(option.label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, w: FontWeight.w500, c: c.textDark, h: 1.2)),
          ]),
        ),
      ),
    );
  }
}

/// The Fields tab: the values that change per recipient, then the certificate's own variables.
class CertFieldsPanel extends StatelessWidget {
  const CertFieldsPanel({super.key, required this.options, required this.custom, required this.onAdd, required this.onNewVariable});
  final List<LayoutAddOption> options;
  final List<LayoutAddOption> custom;
  final ValueChanged<LayoutAddOption> onAdd;
  final VoidCallback onNewVariable;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget row(LayoutAddOption o) => InkWell(
          key: ValueKey('cert-add-${o.label}'),
          borderRadius: AppRadius.chipAll,
          onTap: () => onAdd(o),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            child: Row(children: [
              Icon(o.icon, size: AppIconSize.md, color: c.textMedium),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: Text(o.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w500, c: c.textDark))),
              Icon(Icons.add_rounded, size: AppIconSize.md, color: c.textLight),
            ]),
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
      children: [
        Text(t('يُملأ كل حقل تلقائيًا لكل مستلم عند الإصدار.', 'Each field is filled in for every recipient when you issue.'), style: appText(12.5, c: c.textMedium, h: 1.45)),
        const SizedBox(height: AppSpace.xs),
        for (final o in options) row(o),
        if (custom.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Text(t('متغيراتك', 'Your variables'), style: appText(12, w: FontWeight.w600, c: c.textMedium)),
          for (final o in custom) row(o),
        ],
        const SizedBox(height: AppSpace.sm),
        OutlinedButton.icon(
          key: const ValueKey('cert-new-variable'),
          onPressed: onNewVariable,
          icon: const Icon(Icons.add_rounded, size: AppIconSize.md),
          label: Text(t('متغيّر جديد', 'New variable')),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
        ),
      ],
    );
  }
}

/// The Templates tab. ONE slot: the studio's ready-made designs as thumbnails, a tap replaces this language's design;
/// the full gallery (colours, starters) opens from the button.
class CertTemplatesSlot extends StatefulWidget {
  const CertTemplatesSlot({super.key, required this.lang, required this.load, required this.onPick, required this.onBrowse, this.previewOf});
  final String lang;
  final Future<List<CertServerTemplate>> Function() load;

  /// The real render of a template (the list carries names only); null while there is none to show.
  final Future<Uint8List?> Function(String key, String lang)? previewOf;
  final ValueChanged<CertServerTemplate> onPick;
  final VoidCallback onBrowse;

  @override
  State<CertTemplatesSlot> createState() => _CertTemplatesSlotState();
}

class _CertTemplatesSlotState extends State<CertTemplatesSlot> {
  late final Future<List<CertServerTemplate>> _items = widget.load();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
      children: [
        OutlinedButton.icon(
          key: const ValueKey('cert-browse-templates'),
          onPressed: widget.onBrowse,
          icon: const Icon(Icons.collections_bookmark_outlined, size: AppIconSize.md),
          label: Text(t('كل التصاميم والألوان', 'All designs and colours')),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
        ),
        const SizedBox(height: AppSpace.sm),
        FutureBuilder<List<CertServerTemplate>>(
          future: _items,
          builder: (context, snap) {
            if (!snap.hasData) {
              return AppShimmer(
                child: Column(children: [for (var i = 0; i < 3; i++) const Padding(padding: EdgeInsets.only(bottom: AppSpace.xs), child: AppSkeletonBox(height: 120, radius: AppRadius.chip))]),
              );
            }
            final items = snap.data!;
            if (items.isEmpty) {
              return Text(t('افتح المعرض لاختيار تصميم جاهز.', 'Open the gallery to pick a ready design.'), style: appText(12.5, c: c.textMedium));
            }
            return Column(children: [
              for (final tp in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: _TemplateTile(template: tp, lang: widget.lang, previewOf: widget.previewOf, onTap: () => widget.onPick(tp)),
                ),
            ]);
          },
        ),
      ],
    );
  }
}

class _TemplateTile extends StatefulWidget {
  const _TemplateTile({required this.template, required this.lang, required this.onTap, this.previewOf});
  final CertServerTemplate template;
  final String lang;
  final VoidCallback onTap;
  final Future<Uint8List?> Function(String key, String lang)? previewOf;

  @override
  State<_TemplateTile> createState() => _TemplateTileState();
}

class _TemplateTileState extends State<_TemplateTile> {
  late Future<Uint8List?> _loaded = _load();

  Future<Uint8List?> _load() async {
    final own = widget.template.preview(widget.lang);
    if (own != null) return own;
    final of = widget.previewOf;
    return of == null ? null : of(widget.template.key, widget.lang);
  }

  @override
  void didUpdateWidget(_TemplateTile old) {
    super.didUpdateWidget(old);
    if (old.template.key != widget.template.key || old.lang != widget.lang) _loaded = _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final template = widget.template, lang = widget.lang, onTap = widget.onTap;
    final blank = Icon(template.orientation == 'portrait' ? Icons.crop_portrait_rounded : Icons.crop_landscape_rounded, color: c.textLight);
    return Semantics(
      button: true,
      label: template.name(lang),
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('cert-slot-template-${template.key}'),
        borderRadius: AppRadius.chipAll,
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: 128,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
            child: FutureBuilder<Uint8List?>(
              future: _loaded,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const AppShimmer(child: AppSkeletonBox(height: 128, radius: AppRadius.chip));
                final preview = snap.data;
                if (preview == null) return blank;
                return Image.memory(preview, fit: BoxFit.cover, gaplessPlayback: true, excludeFromSemantics: true, errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: c.textLight));
              },
            ),
          ),
          const SizedBox(height: AppSpace.xxs),
          Text(template.name(lang), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, w: FontWeight.w500, c: c.textDark)),
        ]),
      ),
    );
  }
}

/// What an empty page says: a ready design, or the first element.
class CertEmptyPage extends StatelessWidget {
  const CertEmptyPage({super.key, required this.onTemplates, required this.onAddText});
  final VoidCallback onTemplates, onAddText;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider), boxShadow: AppElevation.of(context, 2)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.workspace_premium_outlined, size: AppIconSize.hero, color: ensureContrast(c.primary, [c.cardBg])),
          const SizedBox(height: AppSpace.sm),
          Text(t('شهادتك تبدأ من هنا', 'Your certificate starts here'), textAlign: TextAlign.center, style: AppType.section(context)),
          const SizedBox(height: AppSpace.xxs),
          Text(t('ابدأ بقالب جاهز أو أضف أول عنصر إلى الصفحة.', 'Start from a ready design, or add the first element to the page.'), textAlign: TextAlign.center, style: AppType.body(context)),
          const SizedBox(height: AppSpace.md),
          FilledButton.icon(
            key: const ValueKey('cert-empty-templates'),
            onPressed: onTemplates,
            icon: const Icon(Icons.dashboard_customize_outlined, size: AppIconSize.md),
            label: Text(t('تصفّح القوالب', 'Browse the templates')),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
          ),
          const SizedBox(height: AppSpace.xs),
          TextButton(
            key: const ValueKey('cert-empty-text'),
            onPressed: onAddText,
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
            child: Text(t('أضف عنوانًا', 'Add a title')),
          ),
        ]),
      ),
    );
  }
}

/// Loading: the shape of the workspace, not a spinner.
class CertStudioSkeleton extends StatelessWidget {
  const CertStudioSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: certBackdrop(context),
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= kCertCompact;
        final paper = AspectRatio(
          aspectRatio: 1.414,
          child: Container(
            decoration: BoxDecoration(color: c.cardBg, boxShadow: AppElevation.of(context, 2)),
            padding: const EdgeInsets.all(AppSpace.md),
            child: AppShimmer(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(mainAxisSize: MainAxisSize.min, children: const [
                  AppSkeletonBox(width: 220, height: 20),
                  SizedBox(height: AppSpace.md),
                  AppSkeletonBox(width: 140, height: 12),
                  SizedBox(height: AppSpace.lg),
                  AppSkeletonBox(width: 260, height: 26),
                  SizedBox(height: AppSpace.md),
                  AppSkeletonBox(width: 300, height: 12),
                ]),
              ),
            ),
          ),
        );
        final topBar = Container(
          height: wide ? 64 : 56,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          decoration: BoxDecoration(color: c.cardBg, border: Border(bottom: BorderSide(color: c.divider))),
          child: AppShimmer(
            child: Row(children: [
              const AppSkeletonBox(width: 24, height: 24),
              const SizedBox(width: AppSpace.md),
              const AppSkeletonBox(width: 160, height: 14),
              const Spacer(),
              if (wide) const AppSkeletonBox(width: 88, height: 36, radius: AppRadius.chip),
              if (wide) const SizedBox(width: AppSpace.xs),
              const AppSkeletonBox(width: 80, height: 36, radius: AppRadius.chip),
            ]),
          ),
        );
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          topBar,
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (wide) Container(width: kCertRailWidth, color: c.cardBg),
              Expanded(
                child: Center(
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: Padding(padding: const EdgeInsets.all(AppSpace.lg), child: paper)),
                ),
              ),
              if (wide) Container(width: 300, color: c.cardBg, padding: const EdgeInsets.all(AppSpace.md), child: const AppShimmer(child: Column(children: [AppSkeletonBox(height: 40), SizedBox(height: AppSpace.md), AppSkeletonBox(height: 48), SizedBox(height: AppSpace.xs), AppSkeletonBox(height: 48), SizedBox(height: AppSpace.md), AppSkeletonBox(height: 120)]))),
            ]),
          ),
          if (!wide) Container(height: 64, color: c.cardBg),
        ]);
      }),
    );
  }
}

/// The whole workspace. The canvas and the bodies come from the studio; this widget owns only which tool is open.
class CertStudioShell extends StatefulWidget {
  const CertStudioShell({
    super.key,
    required this.ctl,
    required this.title,
    required this.onRename,
    required this.saveState,
    required this.onSave,
    required this.onIssue,
    required this.onConflict,
    required this.onPreview,
    required this.onBack,
    required this.languages,
    required this.lang,
    required this.onLang,
    required this.onManageLanguages,
    required this.more,
    required this.canvas,
    required this.inspector,
    required this.toolBody,
    required this.emptyPage,
    required this.pageCaption,
    required this.onPageTap,
    this.banner,
    this.keyboardAction,
  });

  /// Null until the first frame of the canvas (the controller lives inside it).
  final StudioController<LayoutElement>? ctl;
  final String title, pageCaption;
  final VoidCallback onRename, onSave, onConflict, onPreview, onBack, onManageLanguages, onPageTap;
  final VoidCallback? onIssue;
  final ValueListenable<CertSaveState> saveState;
  final List<String> languages;
  final String lang;
  final ValueChanged<String> onLang;
  final Widget more, canvas, inspector;
  final Widget Function(BuildContext context, CertTool tool) toolBody;
  final Widget Function(BuildContext context) emptyPage;
  final Widget? banner;

  /// The slot for the keyboard-shortcuts button of the top bar.
  final Widget? keyboardAction;

  @override
  State<CertStudioShell> createState() => CertStudioShellState();
}

class CertStudioShellState extends State<CertStudioShell> {
  CertTool? _tool;
  bool _toolDefaulted = false;
  String? _lastSelected;
  bool _compact = false, _medium = false;
  StudioController<LayoutElement>? _listening;

  @override
  void initState() {
    super.initState();
    _watch(widget.ctl);
  }

  @override
  void didUpdateWidget(covariant CertStudioShell old) {
    super.didUpdateWidget(old);
    if (old.ctl != widget.ctl) _watch(widget.ctl);
  }

  @override
  void dispose() {
    _listening?.removeListener(_onCtl);
    super.dispose();
  }

  void _watch(StudioController<LayoutElement>? ctl) {
    _listening?.removeListener(_onCtl);
    _listening = ctl?..addListener(_onCtl);
    _lastSelected = ctl?.single?.id;
  }

  void _onCtl() {
    final id = _listening?.single?.id;
    if (id == _lastSelected) return;
    _lastSelected = id;
    if (_compact) {
      if (id != null && (_tool == null || _tool == CertTool.inspector || _tool == CertTool.elements || _tool == CertTool.images || _tool == CertTool.fields || _tool == CertTool.templates)) {
        setState(() => _tool = CertTool.inspector);
        _revealAfterMotion(id);
      } else if (id == null && _tool == CertTool.inspector) {
        setState(() => _tool = null);
      }
    } else if (_medium && id != null && _tool != null && _tool != CertTool.layers) {
      setState(() => _tool = null);
    }
  }

  /// The sheet slides up: keep the selected element in view above it.
  void _revealAfterMotion(String id) {
    final d = AppMotion.of(context).base + const Duration(milliseconds: 40);
    unawaited(Future<void>.delayed(d, () {
      if (mounted) _listening?.reveal(id);
    }));
  }

  /// The studio asks for the properties (a double click, "Page and background").
  void showInspector() {
    if (_compact) {
      setState(() => _tool = CertTool.inspector);
      final id = _listening?.single?.id;
      if (id != null) _revealAfterMotion(id);
    }
  }

  /// The studio opens the templates tab from an empty page.
  void showTool(CertTool tool) => setState(() => _tool = tool);

  void _toggle(CertTool tool) => setState(() => _tool = _tool == tool ? null : tool);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.cardBg,
      child: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final width = box.maxWidth;
          _compact = width < kCertCompact;
          _medium = !_compact && width < kCertWide;
          final wide = !_compact && !_medium;
          if (!_toolDefaulted) {
            _toolDefaulted = true;
            _tool = wide ? CertTool.elements : null;
          }
          final tool = _tool;
          final ctl = widget.ctl;
          final topBar = CertTopBar(
            title: widget.title,
            onRename: widget.onRename,
            saveState: widget.saveState,
            onBack: widget.onBack,
            onConflict: widget.onConflict,
            ctl: ctl,
            languages: widget.languages,
            lang: widget.lang,
            onLang: widget.onLang,
            onManageLanguages: widget.onManageLanguages,
            onPreview: widget.onPreview,
            onSave: widget.onSave,
            onIssue: widget.onIssue,
            more: widget.more,
            compact: _compact,
            keyboardAction: widget.keyboardAction,
          );
          final panel = tool != null && tool != CertTool.inspector ? CertToolPanel(tool: tool, onClose: () => setState(() => _tool = null), floating: _medium, child: widget.toolBody(context, tool)) : null;

          final canvasStack = Stack(children: [
            Positioned.fill(child: widget.canvas),
            if (ctl != null)
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: ctl,
                  builder: (context, _) => ctl.items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpace.md),
                            child: SingleChildScrollView(child: widget.emptyPage(context)),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            if (!_compact)
              PositionedDirectional(
                bottom: AppSpace.sm,
                start: AppSpace.sm,
                child: _PageCaption(text: widget.pageCaption, onTap: widget.onPageTap),
              ),
            if (_compact && ctl != null) ...[
              PositionedDirectional(start: AppSpace.xs, top: AppSpace.xs, child: _FloatingUndo(ctl: ctl)),
              if (widget.languages.length > 1) PositionedDirectional(end: AppSpace.xs, top: AppSpace.xs, child: CertLangSwitch(languages: widget.languages, lang: widget.lang, onLang: widget.onLang)),
            ],
            if (_medium && panel != null) PositionedDirectional(start: 0, top: 0, bottom: 0, child: panel),
          ]);

          final body = _compact
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: canvasStack),
                  _CompactSheet(
                    tool: tool,
                    height: (box.maxHeight * .45).clamp(220.0, 460.0).toDouble(),
                    title: tool == CertTool.inspector ? _inspectTitle(ctl) : (tool == null ? '' : certToolTitle(tool)),
                    onClose: () => setState(() => _tool = null),
                    child: tool == null ? const SizedBox.shrink() : (tool == CertTool.inspector ? widget.inspector : widget.toolBody(context, tool)),
                  ),
                  ListenableBuilder(
                    listenable: ctl ?? _nothing,
                    builder: (context, _) {
                      final selected = ctl != null && ctl.selection.isNotEmpty;
                      return CertBottomTools(
                        tool: tool,
                        onTool: _toggle,
                        inspectIcon: selected ? Icons.tune_rounded : Icons.crop_landscape_rounded,
                        inspectLabel: selected ? t('تعديل', 'Edit') : t('الصفحة', 'Page'),
                      );
                    },
                  ),
                ])
              : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Listener(onPointerDown: _giveKeysToCanvas, child: _Rail(tool: tool, onTool: _toggle, width: _medium ? kCertRailWidth - 8 : kCertRailWidth)),
                  if (wide && panel != null) panel,
                  Expanded(child: canvasStack),
                  Container(
                    width: _medium ? kCertInspectorWidth - 20 : kCertInspectorWidth,
                    decoration: BoxDecoration(color: c.cardBg, border: BorderDirectional(start: BorderSide(color: c.divider))),
                    child: widget.inspector,
                  ),
                ]);

          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Listener(onPointerDown: _giveKeysToCanvas, child: topBar),
            ?widget.banner,
            Expanded(child: body),
          ]);
        }),
      ),
    );
  }

  static final _nothing = ChangeNotifier();

  /// A click on the top bar or the rail leaves the shortcuts on the canvas.
  void _giveKeysToCanvas(PointerDownEvent _) => StudioKeyboard.focusCanvas();

  String _inspectTitle(StudioController<LayoutElement>? ctl) {
    final sel = ctl?.single?.payload;
    if (sel != null) return sel.name ?? t('العنصر المحدد', 'Selected element');
    if ((ctl?.selection.length ?? 0) > 1) return t('عدة عناصر', 'Several elements');
    return t('الصفحة', 'Page');
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.tool, required this.onTool, required this.width});
  final CertTool? tool;
  final ValueChanged<CertTool> onTool;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs, horizontal: AppSpace.xxs),
      decoration: BoxDecoration(color: c.cardBg, border: BorderDirectional(end: BorderSide(color: c.divider))),
      child: SingleChildScrollView(
        child: Column(children: [
          for (final it in _railItems())
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xxs),
              child: _RailButton(item: it, selected: tool == it.tool, width: width - AppSpace.xs, onTap: () => onTool(it.tool)),
            ),
        ]),
      ),
    );
  }
}

class _PageCaption extends StatelessWidget {
  const _PageCaption({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      child: Material(
        color: c.cardBg.withValues(alpha: .9),
        borderRadius: AppRadius.chipAll,
        child: InkWell(
          key: const ValueKey('cert-page-caption'),
          borderRadius: AppRadius.chipAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs + 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.crop_landscape_rounded, size: AppIconSize.xs, color: c.textMedium),
              const SizedBox(width: AppSpace.xxs + 2),
              Text(text, style: appText(11.5, w: FontWeight.w500, c: c.textMedium)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Undo / redo over the canvas on a phone (the top bar has no room for them).
class _FloatingUndo extends StatelessWidget {
  const _FloatingUndo({required this.ctl});
  final StudioController<Object?> ctl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.chipAll, boxShadow: AppElevation.of(context, 2), border: AppElevation.border(context, 2)),
      child: CertUndoRedo(ctl: ctl),
    );
  }
}

/// The phone's non-modal sheet: the canvas above stays live, so a tool or a property change shows at once.
class _CompactSheet extends StatelessWidget {
  const _CompactSheet({required this.tool, required this.height, required this.title, required this.onClose, required this.child});
  final CertTool? tool;
  final double height;
  final String title;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final open = tool != null;
    return AnimatedContainer(
      key: const ValueKey('cert-sheet'),
      duration: AppMotion.of(context).base,
      curve: AppMotion.curve,
      height: open ? height : 0,
      decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider)), boxShadow: open ? AppElevation.of(context, 2) : null),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(builder: (context, box) {
        if (box.maxHeight < 72) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xxs, AppSpace.xxs, 0),
            child: Row(children: [
              // the inspector carries its own heading: a second title here would repeat it
              Expanded(child: tool == CertTool.inspector ? const SizedBox.shrink() : Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w600, c: c.textDark))),
              IconButton(key: const ValueKey('cert-sheet-close'), tooltip: t('إغلاق', 'Close'), onPressed: onClose, icon: Icon(Icons.keyboard_arrow_down_rounded, color: c.textMedium)),
            ]),
          ),
          Expanded(child: child),
        ]);
      }),
    );
  }
}
