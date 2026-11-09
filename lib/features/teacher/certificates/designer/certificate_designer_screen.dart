// features/teacher/certificates/designer/certificate_designer_screen.dart
//
// Certificate designer (teachers, teacher assistants, admins, admin assistants, universities).
//
//   1. WIZARD  – pick portrait / landscape + a style, optionally upload a logo and a signature
//                photo (its background is removed on the server), then
//                  • "Generate draft"  → a complete certificate built from the app's CURRENT
//                                        THEME colour + logo + signature, or
//                  • "Use my template" → your own certificate image becomes the background, or
//                  • "Blank page".
//   2. EDITOR  – the studio engine (lib/design/studio/): drag to move, handles to resize, smart guides, align,
//                nudge with the arrows, duplicate, delete, order, undo / redo, zoom. Two INDEPENDENT designs:
//                the ع / EN switcher edits the Arabic or the English one — each has its own layout, orientation,
//                background, theme and default logo / signature (English may follow the Arabic settings until
//                "Customize for English"); "Languages" picks which ones certificates are issued in. Any number of
//                logos and signatures (each with its own image; signatures with the signer's name and title),
//                a verification QR, the student photo, dynamic values and custom {fields}.
//                Desktop (≥ 1100): tools + layers on the start side, the page in the middle, properties on the end.
//                Tablet (≥ 600): the page and the properties docked on the end side; tools and layers in sheets.
//                Phone: the page above a NON-modal properties panel docked at the bottom (collapsible); selecting
//                an element opens it and pans the page so the element stays in view above it.
//                Every edit is autosaved as a local draft (device storage); opening the design again offers it back.
//   3. SAVE    – stores both languages. When opened from a course certificate (certificateId) the design is also
//                attached to it, so every certificate issued afterwards (manual, bulk, approve, auto) uses it.
//
// "Preview" renders the page on the server with sample data — exactly what students receive. The canvas draws
// with the bundled cert fonts (kCertFonts, the server's own files), so it matches the preview.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_contrast.dart';
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/studio/studio.dart';

import 'package:dio/dio.dart';

import 'cert_canvas_item.dart';
import 'cert_designer_panels.dart';
import 'cert_studio_adapter.dart';
import 'certificate_design_models.dart';
import 'certificate_designer_provider.dart';

/// Logo, signature, background and image fields: pick → app cropper (zoom, circle, size — or "use original").
Future<Uint8List?> _pickImage(BuildContext context, {bool allowBackground = true}) async {
  final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400);
  if (f == null) return null;
  final bytes = await f.readAsBytes();
  if (!context.mounted) return null;
  return showAppImageCropper(context, bytes, allowBackground: allowBackground);
}

void _failed(CertificateDesignerProvider p, [String key = 'certd_upload_failed']) =>
    showAppNotice(p.errorMessage ?? key.tr, error: true);

/// The bytes of an image already on the page (to crop it). Null when it cannot be read (offline, CORS on the web).
Future<Uint8List?> _imageBytes(String url) async {
  try {
    final r = await Dio().get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
    final data = r.data;
    return data == null ? null : Uint8List.fromList(data);
  } catch (_) {
    return null;
  }
}

/// Crop element [id]'s image: the current image in the app cropper (or a new one when it cannot be read).
Future<void> _cropFieldImage(BuildContext context, String id, String? url) async {
  final p = context.read<CertificateDesignerProvider>();
  final current = (url ?? '').isEmpty ? null : await _imageBytes(url!);
  if (!context.mounted) return;
  final bytes = current == null ? await _pickImage(context) : await showAppImageCropper(context, current, allowOriginal: false);
  if (bytes == null || !context.mounted) return;
  if (!await p.cropFieldImage(id, bytes) && context.mounted) _failed(p);
}

/// Open the designer.
///  • [designId]      edit this design
///  • [certificateId] the course certificate the design is for (its current design is loaded, and
///                    saving attaches the design to it)
///  • [orgId]         create new designs inside this organization (university / faculty …)
Future<void> openCertificateDesigner(
  BuildContext context, {
  int? designId,
  int? certificateId,
  int? orgId,
}) =>
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CertificateDesignerScreen(designId: designId, certificateId: certificateId, orgId: orgId),
    ));

class CertificateDesignerScreen extends StatelessWidget {
  final int? designId;
  final int? certificateId;
  final int? orgId;

  const CertificateDesignerScreen({super.key, this.designId, this.certificateId, this.orgId, this.provider});

  /// A provider that already holds a design (tests and renders); nothing is loaded then.
  @visibleForTesting
  final CertificateDesignerProvider? provider;

  @override
  Widget build(BuildContext context) {
    final view = _DesignerView(designId: designId, certificateId: certificateId, orgId: orgId);
    final given = provider;
    if (given != null) return ChangeNotifierProvider.value(value: given, child: view);
    return ChangeNotifierProvider(
      create: (_) => CertificateDesignerProvider(initialLang: AppConfig.lang),
      child: view,
    );
  }
}

class _DesignerView extends StatefulWidget {
  final int? designId;
  final int? certificateId;
  final int? orgId;

  const _DesignerView({this.designId, this.certificateId, this.orgId});

  @override
  State<_DesignerView> createState() => _DesignerViewState();
}

class _DesignerViewState extends State<_DesignerView> {
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final p = context.read<CertificateDesignerProvider>();
      if (p.design != null) {
        // already loaded (an injected provider)
      } else if (widget.designId != null) {
        await p.loadDesign(widget.designId!);
      } else if (widget.certificateId != null) {
        await p.loadForCertificate(widget.certificateId!); // null design → wizard
      }
      if (p.design != null && await p.restoreDraftIfAny()) {
        showAppNotice('certd_draft_restored'.tr,
            icon: Icons.restore_rounded, actionLabel: 'certd_draft_discard'.tr, onAction: p.discardDraft);
      }
      if (mounted) setState(() => _initializing = false);
    });
  }

  Future<void> _save() async {
    final p = context.read<CertificateDesignerProvider>();
    final ok = await p.save();
    if (!mounted) return;
    if (!ok) {
      showAppNotice(p.errorMessage ?? 'certificate_action_failed'.tr, error: true);
      return;
    }
    if (widget.certificateId != null) {
      final used = await p.attachToCertificate(widget.certificateId!);
      if (!mounted) return;
      showAppNotice(used ? 'cert_design_saved_and_used'.tr : 'cert_design_saved_not_attached'.tr, error: !used);
    } else {
      showAppNotice('cert_design_saved'.tr);
    }
  }

  Future<void> _showPreview() async {
    final p = context.read<CertificateDesignerProvider>();
    p.previewBytes = null;
    final lang = p.lang;
    showDialog(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(value: p, child: CertPreviewDialog(initialLang: lang)),
    );
    await p.preview(lang);
  }

  Future<bool> _confirmDiscard() async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('cert_discard_changes_title'.tr),
        content: Text('cert_discard_changes_body'.tr),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('cancel'.tr)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('cert_discard'.tr)),
        ],
      ),
    );
    return r == true;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignerProvider>();
    final c = context.colors;
    final hasDesign = p.design != null;
    final working = p.busy || p.saving;

    return PopScope(
      canPop: !p.dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final p = context.read<CertificateDesignerProvider>();
        if (await _confirmDiscard()) {
          await p.discardDraft(); // "Discard" also drops the autosaved draft
          nav.pop();
        }
      },
      child: Scaffold(
        backgroundColor: c.background,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(AppHeader.openHeightWithSubtitle * 1.6 + 2),
          // the design's name in either script whatever the UI language (an Arabic name in the English UI drew only
          // its punctuation: the Latin UI font has no Arabic glyphs); no name → the page's title
          child: DefaultTextStyle.merge(
            style: TextStyle(fontFamilyFallback: AppFonts.fallback),
            child: AppHeader(
              compact: true,
              title: hasDesign && p.design!.name.trim().isNotEmpty ? p.design!.name : 'cert_designer_title'.tr,
              actions: [
                if (hasDesign) ...[
                  _AppBarAction(
                    icon: Icons.visibility_outlined,
                    label: 'certd_preview'.tr,
                    onPressed: working ? null : _showPreview,
                  ),
                  const SizedBox(width: AppSpace.xxs),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: AppSpace.xxs),
                    child: _SaveButton(
                      dirty: p.dirty,
                      saving: p.saving,
                      onPressed: (p.design!.canEdit && !working) ? _save : null,
                    ),
                  ),
                ],
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: SizedBox(height: 2, child: working ? const LinearProgressIndicator(minHeight: 2) : null),
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: _initializing || (p.isLoading && !hasDesign && !p.busy)
              ? const _DesignerSkeleton()
              : AbsorbPointer(
                  absorbing: working,
                  child: hasDesign
                      ? Column(children: [
                          // read-only (organization / someone else's design): offer an editable copy
                          if (!p.design!.canEdit) _CustomizeBanner(certificateId: widget.certificateId),
                          const Expanded(child: _Editor()),
                        ])
                      : _Wizard(orgId: widget.orgId),
                ),
        ),
      ),
    );
  }
}

class _AppBarAction extends StatelessWidget {
  const _AppBarAction({required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wide = MediaQuery.sizeOf(context).width >= 600;
    if (!wide) return IconButton(tooltip: label, onPressed: onPressed, icon: Icon(icon));
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(AppTouch.min, AppTouch.min),
        foregroundColor: ensureContrast(c.primary, [c.cardBg, c.background]),
      ),
      icon: Icon(icon, size: 20),
      label: Text(label, style: appText(14, w: FontWeight.w600)),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.dirty, required this.saving, required this.onPressed});
  final bool dirty, saving;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final label = Text(dirty ? 'certd_save'.tr : 'certd_saved'.tr, style: appText(14, w: FontWeight.w600, c: c.onHero));
    final icon = Icon(dirty ? Icons.save_outlined : Icons.check_rounded, size: 20, color: c.onHero);
    if (!wide) {
      return IconButton.filled(
        tooltip: 'certd_save'.tr,
        onPressed: onPressed,
        style: IconButton.styleFrom(backgroundColor: c.primary),
        icon: icon,
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(AppTouch.min, AppTouch.min - 4),
        backgroundColor: c.primary,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll),
      ),
      icon: icon,
      label: label,
    );
  }
}

/// The page's shape while the design loads (no spinner).
class _DesignerSkeleton extends StatelessWidget {
  const _DesignerSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppShimmer(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(children: [
          const Row(children: [
            Flexible(child: AppSkeletonBox(width: 180, height: 40, radius: 12)),
            Spacer(),
            Flexible(child: AppSkeletonBox(width: 120, height: 40, radius: 12)),
          ]),
          const SizedBox(height: AppSpace.sm),
          const AppSkeletonBox(width: double.infinity, height: 48, radius: 12),
          const SizedBox(height: AppSpace.md),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: kLogicalLong / kLogicalShort,
                child: Container(
                  decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider)),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wizard (no design yet)
// ─────────────────────────────────────────────────────────────────────────────

class _Wizard extends StatelessWidget {
  final int? orgId;

  const _Wizard({this.orgId});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignerProvider>();
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;

    Widget section(String title, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title, style: AppType.section(context)),
              const SizedBox(height: AppSpace.sm),
              child,
            ]),
          ),
        );

    Future<void> generate() async {
      final ok = await p.createDraft(themeColorHex: colorToHex(c.primary), dark: dark, orgId: orgId);
      if (!ok && context.mounted) _failed(p, 'certificate_action_failed');
    }

    Future<void> fromTemplate() async {
      final bytes = await _pickImage(context, allowBackground: false); // a whole certificate page
      if (bytes == null) return;
      final ok = await p.createFromTemplateImage(bytes, orgId: orgId);
      if (!ok && context.mounted) _failed(p, 'certificate_action_failed');
    }

    Future<void> blank() async {
      final ok = await p.createBlank(orgId: orgId);
      if (!ok && context.mounted) _failed(p, 'certificate_action_failed');
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
          Text('cert_wizard_intro'.tr, style: AppType.row(context).copyWith(height: 1.5)),
          const SizedBox(height: AppSpace.md),
          section('certd_templates'.tr, _TemplateStrip(orgId: orgId)),
          section(
            'cert_orientation'.tr,
            StudioSegmented<String>(
              segments: [
                StudioSegment(value: 'landscape', label: 'cert_orientation_landscape'.tr),
                StudioSegment(value: 'portrait', label: 'cert_orientation_portrait'.tr),
              ],
              value: p.wizardOrientation,
              onChanged: p.setWizardOrientation,
            ),
          ),
          section(
            'cert_style'.tr,
            StudioSegmented<String>(
              segments: [for (final s in const ['classic', 'modern', 'dark']) StudioSegment(value: s, label: 'cert_style_$s'.tr)],
              value: p.wizardStyle,
              onChanged: p.setWizardStyle,
            ),
          ),
          section(
            'cert_logo'.tr,
            CertAssetRow(
              title: 'certd_default_logo'.tr,
              url: p.pendingLogoUrl,
              state: p.pendingLogoUrl == null ? CertInherit.none : CertInherit.own,
              hint: orgId != null ? 'cert_logo_org_hint'.tr : null,
              onUpload: () async {
                final b = await _pickImage(context);
                if (b != null && !await p.uploadLogo(b) && context.mounted) _failed(p);
              },
              onRemove: p.removePendingLogo,
            ),
          ),
          section(
            'cert_signature'.tr,
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              CertAssetRow(
                title: 'certd_default_signature'.tr,
                url: p.pendingSignatureUrl,
                state: p.pendingSignatureUrl == null ? CertInherit.none : CertInherit.own,
                hint: 'cert_signature_hint'.tr,
                onUpload: () async {
                  final b = await _pickImage(context);
                  if (b != null && !await p.uploadSignature(b) && context.mounted) _failed(p, 'cert_signature_failed');
                },
                onRemove: p.removePendingSignature,
              ),
              if (p.pendingSignatureUrl != null && p.canReprocess('pending'))
                CertSignatureTuner(
                  ink: p.sigInk('pending'),
                  strength: p.sigStrength('pending'),
                  enabled: !p.busy,
                  onInk: (ink) => p.reprocessSignature('pending', inkColor: ink),
                  onStrength: (v) => p.reprocessSignature('pending', keepInk: true, strength: v),
                ),
            ]),
          ),
          const SizedBox(height: AppSpace.xxs),
          AppPrimaryButton(
            label: 'cert_generate_draft'.tr,
            icon: Icons.auto_awesome_rounded,
            busy: p.busy,
            onPressed: generate,
          ),
          const SizedBox(height: AppSpace.xs),
          SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              onPressed: p.busy ? null : fromTemplate,
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: Text('cert_use_my_template'.tr, style: appText(14, w: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          TextButton(
            onPressed: p.busy ? null : blank,
            style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
            child: Text('cert_start_blank'.tr, style: appText(14, w: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Editor
// ─────────────────────────────────────────────────────────────────────────────

/// Adds an element from the tools (uploads first for a logo / signature).
Future<void> _addTool(BuildContext context, CertTool t) async {
  final p = context.read<CertificateDesignerProvider>();
  if (!p.canAddField) {
    showAppNotice('certd_max_fields'.tr, error: true);
    return;
  }
  switch (t) {
    case CertTool.text:
      p.addText();
    case CertTool.field:
      final key = await _pickPlaceholder(context);
      if (key != null) p.addPlaceholder(key);
    case CertTool.logo:
      final b = await _pickImage(context);
      if (b == null) return;
      if (await p.addLogoImage(b) == null && context.mounted) _failed(p);
    case CertTool.signature:
      final b = await _pickImage(context);
      if (b == null) return;
      if (await p.addSignatureImage(b) == null && context.mounted) _failed(p, 'cert_signature_failed');
    case CertTool.line:
      p.addLine();
    case CertTool.photo:
      p.addPhoto();
    case CertTool.qr:
      p.addQr();
  }
}

/// "Add a field…" dialog; stores the sample. Returns the key.
Future<String?> _askCustomField(BuildContext context) async {
  final p = context.read<CertificateDesignerProvider>();
  final r = await showCertCustomFieldDialog(context);
  if (r == null) return null;
  p.setCustomSample(r.$1, r.$2);
  return r.$1;
}

/// Dynamic value picker for a new text element: the built-in values, the custom ones in use and "Add a field…".
Future<String?> _pickPlaceholder(BuildContext context) async {
  final p = context.read<CertificateDesignerProvider>();
  final custom = customPlaceholdersOf(p.fieldsOf(p.lang));
  final picked = await showAppSheet<String>(context, (ctx) {
    final c = ctx.colors;
    Widget row(String label, String value, IconData icon) => ListTile(
          minTileHeight: AppTouch.min,
          leading: Icon(icon, color: ensureContrast(c.primary, [c.cardBg])),
          title: Text(label, style: AppType.row(ctx)),
          subtitle: Text('{$value}', textDirection: TextDirection.ltr, style: AppType.meta(ctx)),
          onTap: () => Navigator.pop(ctx, value),
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AppSheetHeader('certd_add_field'.tr),
      Flexible(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: AppSpace.md), children: [
          for (final ph in kCertPlaceholders) row(ph.labelKey.tr, ph.key, Icons.data_object_rounded),
          for (final k in custom) row(k, k, Icons.label_outline_rounded),
          ListTile(
            minTileHeight: AppTouch.min,
            leading: Icon(Icons.add_circle_outline_rounded, color: ensureContrast(c.primary, [c.cardBg])),
            title: Text('certd_custom_field'.tr, style: AppType.row(ctx)),
            subtitle: Text('certd_custom_field_hint'.tr, style: AppType.meta(ctx)),
            onTap: () => Navigator.pop(ctx, '\u0000custom'),
          ),
        ]),
      ),
    ]);
  });
  if (picked == '\u0000custom') {
    if (!context.mounted) return null;
    return _askCustomField(context);
  }
  return picked;
}

class _Editor extends StatefulWidget {
  const _Editor();

  static const double wideMin = 1100, tabletMin = 600;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  /// The phone's docked panel: open (properties shown) or folded to its header.
  final _dockOpen = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _dockOpen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignerProvider>();
    final c = context.colors;
    final studio = p.studio;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= _Editor.wideMin;
      final tablet = !wide && box.maxWidth >= _Editor.tabletMin;
      final phone = !wide && !tablet;
      final canvas = Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, AppSpace.sm, 0),
          child: const _LangBar(),
        ),
        Padding(
          padding: EdgeInsets.all(phone ? AppSpace.xs : AppSpace.sm),
          child: CertToolbarRow(
            controller: studio,
            enabled: p.canEdit,
            leading: wide
                ? const []
                : [
                    StudioToolButton(
                      icon: Icons.add_box_outlined,
                      label: 'certd_tools'.tr,
                      showLabel: true,
                      onPressed: p.canEdit ? () => _openToolsSheet(context) : null,
                    ),
                    StudioToolButton(
                      icon: Icons.layers_outlined,
                      label: 'certd_layers'.tr,
                      showLabel: !phone,
                      onPressed: () => _openLayersSheet(context),
                    ),
                  ],
          ),
        ),
        Expanded(
          child: ClipRect(
            child: _Canvas(onDoubleTap: phone ? () => _dockOpen.value = true : null),
          ),
        ),
      ]);
      final side = BoxDecoration(color: c.cardBg, border: Border.symmetric(vertical: BorderSide(color: c.divider)));
      if (wide) {
        return Row(children: [
          Container(width: 224, decoration: side, child: const _ToolsColumn()),
          Expanded(child: canvas),
          Container(width: 336, decoration: side, child: const _PropsHost(scroll: true)),
        ]);
      }
      if (tablet) {
        // the properties stay docked on the end side: the page is never covered
        return Row(children: [
          Expanded(child: canvas),
          Container(width: box.maxWidth >= 900 ? 336 : 300, decoration: side, child: const _PropsHost(scroll: true)),
        ]);
      }
      return Column(children: [
        Expanded(child: canvas),
        CertDockPanel(controller: studio, open: _dockOpen, maxHeight: box.maxHeight),
      ]);
    });
  }
}

/// The phone's properties panel, docked under the page (never over it): the engine's [StudioDockPanel] with the
/// selected element's properties (or the page's). Selecting an element opens it and keeps that element in view.
class CertDockPanel extends StatelessWidget {
  const CertDockPanel({super.key, required this.controller, required this.open, required this.maxHeight});

  final StudioController<CertField> controller;
  final ValueNotifier<bool> open;

  /// The editor's height: the open panel takes about 45 % of it.
  final double maxHeight;

  static const double headerHeight = StudioDockPanel.headerHeight;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final sel = controller.single;
          final multi = controller.selection.length > 1;
          final title = sel != null
              ? certKindLabel(sel.payload.kind)
              : (multi ? 'certd_multi_selected'.tr.replaceAll('{n}', '${controller.selection.length}') : 'certd_page'.tr);
          return StudioDockPanel(
            controller: controller,
            open: open,
            maxHeight: maxHeight,
            title: title,
            icon: sel != null ? certKindIcon(sel.payload.kind) : Icons.description_outlined,
            semanticLabel: 'certd_properties'.tr,
            body: const _PropsHost(scroll: true),
          );
        },
      );
}

void _openToolsSheet(BuildContext context) {
  final p = context.read<CertificateDesignerProvider>();
  showAppSheet<void>(context, (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        AppSheetHeader('certd_tools'.tr),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
            child: CertToolsPanel(
              grid: true,
              enabled: p.canEdit,
              onAdd: (t) {
                Navigator.pop(ctx);
                _addTool(context, t);
              },
            ),
          ),
        ),
      ]));
}

void _openLayersSheet(BuildContext context) {
  final p = context.read<CertificateDesignerProvider>();
  showAppSheet<void>(context, (ctx) => ChangeNotifierProvider.value(
        value: p,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppSheetHeader('certd_layers'.tr),
          const Flexible(child: _LayersHost(shrinkWrap: true)),
        ]),
      ));
}

/// Desktop start column: "Add to the page" + the layers of the language being edited.
class _ToolsColumn extends StatelessWidget {
  const _ToolsColumn();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignerProvider>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xs),
        child: Text('certd_tools'.tr, style: AppType.section(context)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
        child: CertToolsPanel(enabled: p.canEdit, onAdd: (t) => _addTool(context, t)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xxs),
        child: Text('certd_layers'.tr, style: AppType.section(context)),
      ),
      const Expanded(child: _LayersHost()),
    ]);
  }
}

class _LayersHost extends StatelessWidget {
  const _LayersHost({this.shrinkWrap = false});
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignerProvider>();
    final st = p.studio;
    return ListenableBuilder(
      listenable: st,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
        child: CertLayersList(
          shrinkWrap: shrinkWrap,
          fields: p.fieldsOf(p.lang),
          arabic: p.editArabic,
          selectedId: st.single?.id,
          enabled: p.canEdit,
          onSelect: (id) => st.select(id),
          onToggleVisible: (id) =>
              p.updateField(id, (f) => f.copyWith(visible: !f.visible), label: 'visibility', coalesce: false),
          onToggleLock: (id) => p.updateField(id, (f) => f.copyWith(locked: !f.locked), label: 'lock', coalesce: false),
          onReorder: p.reorderLayer,
          onDelete: p.removeField,
        ),
      ),
    );
  }
}

/// ع / EN + Languages.
class _LangBar extends StatelessWidget {
  const _LangBar();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignerProvider>();
    final d = p.design!;
    final inherited = <String>[
      if (certImageInherit(d.backgroundUrlEn, d.backgroundUrl) == CertInherit.same) 'cert_background'.tr,
      if (p.themeInheritEn == CertInherit.same) 'certd_theme'.tr,
      if (certImageInherit(d.logoUrlEn, d.logoUrl) == CertInherit.same) 'certd_default_logo'.tr,
      if (certImageInherit(d.signatureUrlEn, d.signatureUrl) == CertInherit.same) 'certd_default_signature'.tr,
    ];
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: CertLangSwitcher(
        langs: d.langs,
        active: p.lang,
        inheritedEn: inherited,
        onChanged: p.setLang,
        onManage: p.canEdit ? () => _openLangsSheet(context) : null,
      ),
    );
  }
}

Future<void> _setLangs(BuildContext context, List<String> next) async {
  final p = context.read<CertificateDesignerProvider>();
  final off = p.design!.langs.where((l) => !next.contains(l)).toList();
  for (final l in off) {
    if (p.langHasContent(l)) {
      final ok = await appConfirm(
        context,
        message: 'certd_disable_lang_confirm'.tr.replaceAll('{lang}', certLangName(l)),
        confirmLabel: 'certd_turn_off'.tr,
      );
      if (!ok) return;
    }
  }
  p.setLangs(next);
}

void _openLangsSheet(BuildContext context) {
  final p = context.read<CertificateDesignerProvider>();
  showAppSheet<void>(context, (ctx) => ChangeNotifierProvider.value(
        value: p,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppSheetHeader('certd_langs'.tr),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.lg),
              child: Builder(
                builder: (ctx) => CertLangsControl(
                  langs: ctx.watch<CertificateDesignerProvider>().design!.langs,
                  onChanged: (l) => _setLangs(context, l),
                ),
              ),
            ),
          ),
        ]),
      ));
}

class _Canvas extends StatelessWidget {
  const _Canvas({this.onDoubleTap});
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignerProvider>();
    final v = p.view;
    final bg = v.backgroundUrl;
    final arabic = p.editArabic;
    final samples = Map<String, String>.of(p.customSamples);
    return StudioCanvas<CertField>(
      key: ValueKey('canvas-${p.lang}'),
      controller: p.studio,
      pageColor: v.dark ? const Color(0xFF101014) : kStudioPaper,
      pageBackground: (bg ?? '').isEmpty
          ? null
          : Image.network(bg!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
      overlayBuilder: CertWatermark.of(v.theme)?.visible == true
          ? (context, scale) =>
              CertWatermarkView(watermark: CertWatermark.of(v.theme)!, scale: scale, samples: samples, arabic: arabic)
          : null,
      onItemDoubleTap: onDoubleTap == null ? null : (_) => onDoubleTap!(),
      // double click (long-press on touch) on a text edits it on the page; right click = the context menu
      contextMenu: p.canEdit,
      inlineText: p.canEdit ? (item) => item.payload.isText ? certFieldRawText(item.payload, arabic: arabic) : null : null,
      inlineStyle: (context, item, scale) => certInlineStyle(item.payload, arabic: arabic, scale: scale, samples: samples),
      onInlineCommit: (item, text) => p.setText(item.id, text),
      itemBuilder: (context, item, selected) {
        final f = item.payload;
        final url = f.isImage
            ? ((f.src ?? '').isNotEmpty ? f.src : (f.kind == CertFieldKind.logo ? v.logoUrl : v.signatureUrl))
            : null;
        return CertFieldView(
          field: f,
          size: item.rect.size,
          scale: StudioCanvas.scaleOf(context),
          arabic: arabic,
          imageUrl: url,
          samples: samples,
        );
      },
    );
  }
}

/// The end column (or the properties sheet): the selected element, else the page settings of the language.
class _PropsHost extends StatelessWidget {
  const _PropsHost({this.scroll = false});
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignerProvider>();
    final st = p.studio;
    return ListenableBuilder(
      listenable: st,
      builder: (context, _) {
        final f = p.selected;
        final multi = st.selection.length > 1;
        final Widget body;
        if (f != null) {
          body = _FieldPropsHost(key: ValueKey('${p.lang}:${f.id}'), field: f);
        } else if (multi) {
          body = _MultiSelection(count: st.selection.length);
        } else {
          body = _PagePanel(key: ValueKey('page-${p.lang}'));
        }
        if (!scroll) return body;
        return SingleChildScrollView(padding: const EdgeInsets.all(AppSpace.md), child: body);
      },
    );
  }
}

class _MultiSelection extends StatelessWidget {
  const _MultiSelection({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('certd_multi_selected'.tr.replaceAll('{n}', '$count'), style: AppType.section(context)),
        const SizedBox(height: AppSpace.xs),
        Text('certd_multi_hint'.tr, style: AppType.meta(context)),
      ]);
}

class _FieldPropsHost extends StatelessWidget {
  const _FieldPropsHost({super.key, required this.field});
  final CertField field;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignerProvider>();
    final st = p.studio;
    final f = field;
    final v = p.view;
    final target = CertificateDesignerProvider.fieldTarget(p.lang, f.id);
    final ownSig = f.kind == CertFieldKind.signature && (f.src ?? '').isNotEmpty;
    return CertFieldProps(
      field: f,
      arabic: p.editArabic,
      enabled: p.canEdit,
      themeHex: v.theme['color'] as String?,
      defaultImageUrl: f.kind == CertFieldKind.logo ? v.logoUrl : (f.kind == CertFieldKind.signature ? v.signatureUrl : null),
      customKeys: customPlaceholdersOf(p.fieldsOf(p.lang)),
      onAskCustomField: () => _askCustomField(context),
      onEdit: (change, {label = 'edit', coalesce = true}) => p.updateField(f.id, change, label: label, coalesce: coalesce),
      onText: (t) => p.setText(f.id, t),
      onReplaceImage: () async {
        final b = await _pickImage(context);
        if (b != null && !await p.replaceFieldImage(f.id, b) && context.mounted) _failed(p);
      },
      onUseDefaultImage: () => p.useDefaultImage(f.id),
      onCropImage: f.isImage
          ? () => _cropFieldImage(
              context,
              f.id,
              (f.src ?? '').isNotEmpty
                  ? f.src
                  : (f.kind == CertFieldKind.logo ? v.logoUrl : v.signatureUrl))
          : null,
      autoLineHeight: f.isText
          ? certFieldLayout(f.copyWith(lineHeight: null), arabic: p.editArabic, samples: p.customSamples)?.heightFactor
          : null,
      signatureTuner: ownSig && p.canReprocess(target)
          ? CertSignatureTuner(
              ink: p.sigInk(target),
              strength: p.sigStrength(target),
              enabled: !p.busy,
              onInk: (ink) => p.reprocessSignature(target, inkColor: ink),
              onStrength: (s) => p.reprocessSignature(target, keepInk: true, strength: s),
            )
          : null,
      onDuplicate: st.duplicate,
      onForward: st.bringForward,
      onBackward: st.sendBackward,
      onDelete: st.deleteSelection,
    );
  }
}

/// Page settings of the language being edited.
class _PagePanel extends StatefulWidget {
  const _PagePanel({super.key});

  @override
  State<_PagePanel> createState() => _PagePanelState();
}

class _PagePanelState extends State<_PagePanel> {
  bool _resetFields = false;
  late final TextEditingController _name =
      TextEditingController(text: context.read<CertificateDesignerProvider>().design!.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignerProvider>();
    final c = context.colors;
    final d = p.design!;
    final l = p.lang;
    final en = l == 'en';
    final v = p.view;
    final edit = p.canEdit;
    final accent = ensureContrast(c.primary, [c.cardBg]);

    Future<void> upload(Future<bool> Function(Uint8List b) send, [String failKey = 'certd_upload_failed', bool allowBackground = true]) async {
      final b = await _pickImage(context, allowBackground: allowBackground);
      if (b == null) return;
      if (!await send(b) && context.mounted) _failed(p, failKey);
    }

    final themeState = en ? p.themeInheritEn : CertInherit.own;
    final theme = v.theme;
    final themeColor = (theme['color'] as String?) ?? colorToHex(c.primary);
    final style = (theme['style'] as String?) ?? 'classic';
    void setTheme(Map<String, dynamic> next, {bool coalesce = false}) =>
        p.setTheme(l, {...theme, ...next}, coalesce: coalesce);

    final bgState = en ? certImageInherit(d.backgroundUrlEn, d.backgroundUrl) : CertInherit.own;
    final logoState = en ? certImageInherit(d.logoUrlEn, d.logoUrl) : CertInherit.own;
    final sigState = en ? certImageInherit(d.signatureUrlEn, d.signatureUrl) : CertInherit.own;
    final sigTarget = CertificateDesignerProvider.defaultTarget(l);

    return AbsorbPointer(
      absorbing: !edit,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${'certd_page'.tr} · ${certLangName(l)}', style: AppType.section(context)),
        const SizedBox(height: AppSpace.xxs),
        Text('certd_select_hint'.tr, style: AppType.meta(context)),
        StudioPropSection(title: 'cert_design_name'.tr, children: [
          TextField(
            controller: _name,
            maxLength: 255,
            style: appText(14, w: FontWeight.w500, c: c.textDark),
            decoration: const InputDecoration(isDense: true, counterText: ''),
            onChanged: p.rename,
          ),
        ]),
        StudioPropSection(title: 'certd_langs'.tr, children: [
          CertLangsControl(langs: d.langs, enabled: edit, onChanged: (next) => _setLangs(context, next)),
        ]),
        StudioPropSection(title: 'cert_orientation'.tr, children: [
          StudioSegmented<String>(
            segments: [
              StudioSegment(value: 'landscape', label: 'cert_orientation_landscape'.tr),
              StudioSegment(value: 'portrait', label: 'cert_orientation_portrait'.tr),
            ],
            value: v.orientation,
            onChanged: edit ? (o) => p.setOrientation(l, o) : null,
          ),
          if (en) Text('certd_orientation_own'.tr, style: AppType.meta(context)),
        ]),
        StudioPropSection(title: 'certd_paper'.tr, children: [
          CertPaperControl(
            page: CertPage.of(v.theme),
            enabled: edit,
            onChanged: (pg) => p.setPage(l, pg),
          ),
          if (en && themeState == CertInherit.same) Text('certd_paper_follows_ar'.tr, style: AppType.meta(context)),
        ]),
        StudioPropSection(title: 'certd_watermark'.tr, children: [
          CertWatermarkControl(
            watermark: CertWatermark.of(v.theme),
            enabled: edit,
            onChanged: (wm, {coalesce = false}) => p.setWatermark(l, wm, coalesce: coalesce),
            onUploadImage: () => upload((b) => p.uploadWatermarkImage(l, b)),
          ),
        ]),
        StudioPropSection(title: 'cert_background'.tr, children: [
          CertAssetRow(
            title: '',
            url: v.backgroundUrl,
            english: en,
            state: en ? bgState : ((v.backgroundUrl ?? '').isEmpty ? CertInherit.none : CertInherit.own),
            enabled: edit,
            onUpload: () => upload((b) => p.uploadBackground(l, b), 'certd_upload_failed', false),
            onCustomize: () => upload((b) => p.uploadBackground(l, b), 'certd_upload_failed', false),
            onRemove: () => p.setBackground(l, null),
            onReset: () => p.setBackground(l, null, inherit: true),
            more: [
              if (en && bgState == CertInherit.same)
                TextButton.icon(
                  onPressed: edit ? () => p.setBackground(l, null) : null,
                  style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min), foregroundColor: accent),
                  icon: const Icon(Icons.layers_clear_outlined, size: 18),
                  label: Text('certd_bg_none_en'.tr, style: appText(13, w: FontWeight.w600)),
                ),
            ],
          ),
        ]),
        StudioPropSection(
          title: 'certd_theme'.tr,
          trailing: en && themeState == CertInherit.own
              ? TextButton(
                  onPressed: () => p.setTheme(l, null),
                  style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
                  child: Text('certd_reset_to_ar'.tr, style: appText(13, w: FontWeight.w600, c: accent)),
                )
              : null,
          children: [
            if (en && themeState == CertInherit.same) ...[
              Row(children: [
                Icon(Icons.link_rounded, size: 16, color: accent),
                const SizedBox(width: AppSpace.xxs),
                Expanded(child: Text('certd_same_as_ar'.tr, style: appText(12.5, w: FontWeight.w500, c: accent))),
              ]),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: () => p.setTheme(l, Map<String, dynamic>.of(d.theme)),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text('certd_customize_en'.tr, style: appText(13, w: FontWeight.w600)),
                ),
              ),
            ] else ...[
              StudioColorField(
                label: 'certd_theme_accent'.tr,
                value: hexToColor(themeColor),
                onChanged: (col) {
                  if (col != null) setTheme({'color': colorToHex(col)}, coalesce: true);
                },
              ),
              AppSwitchTile(
                dense: true,
                title: 'certd_dark_page'.tr,
                subtitle: 'certd_dark_page_hint'.tr,
                value: theme['dark'] == true,
                onChanged: (on) => setTheme({'dark': on}),
              ),
              StudioPropField(
                label: 'cert_style'.tr,
                child: StudioSegmented<String>(
                  segments: [for (final s in const ['classic', 'modern', 'dark']) StudioSegment(value: s, label: 'cert_style_$s'.tr)],
                  value: style,
                  onChanged: (s) => setTheme({'style': s}),
                ),
              ),
              ...[
                AppSwitchTile(
                  dense: true,
                  title: 'cert_reset_layout'.tr,
                  value: _resetFields,
                  onChanged: (on) => setState(() => _resetFields = on),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.tonalIcon(
                    onPressed: () async {
                      final ok = await p.regenerateBackground(
                        lang: l,
                        themeColorHex: themeColor,
                        dark: theme['dark'] == true,
                        style: style,
                        resetFields: _resetFields,
                      );
                      if (!ok && context.mounted) _failed(p, 'certificate_action_failed');
                    },
                    style: FilledButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: Text('cert_regenerate_from_theme'.tr, style: appText(13, w: FontWeight.w600)),
                  ),
                ),
              ],
            ],
          ],
        ),
        StudioPropSection(title: 'certd_defaults'.tr, children: [
          Text('certd_default_hint'.tr, style: AppType.meta(context)),
          CertAssetRow(
            title: 'certd_default_logo'.tr,
            url: v.logoUrl,
            english: en,
            state: en ? logoState : ((v.logoUrl ?? '').isEmpty ? CertInherit.none : CertInherit.own),
            enabled: edit,
            onUpload: () => upload((b) => p.uploadDefaultLogo(l, b)),
            onCustomize: () => upload((b) => p.uploadDefaultLogo(l, b)),
            onRemove: () => p.setDefaultLogo(l, null),
            onReset: () => p.setDefaultLogo(l, null, inherit: true),
          ),
          CertAssetRow(
            title: 'certd_default_signature'.tr,
            url: v.signatureUrl,
            english: en,
            state: en ? sigState : ((v.signatureUrl ?? '').isEmpty ? CertInherit.none : CertInherit.own),
            enabled: edit,
            hint: 'cert_signature_hint'.tr,
            onUpload: () => upload((b) => p.uploadDefaultSignature(l, b), 'cert_signature_failed'),
            onCustomize: () => upload((b) => p.uploadDefaultSignature(l, b), 'cert_signature_failed'),
            onRemove: () => p.setDefaultSignature(l, null),
            onReset: () => p.setDefaultSignature(l, null, inherit: true),
          ),
          if ((v.signatureUrl ?? '').isNotEmpty && p.canReprocess(sigTarget) && (!en || sigState != CertInherit.same))
            CertSignatureTuner(
              ink: p.sigInk(sigTarget),
              strength: p.sigStrength(sigTarget),
              enabled: !p.busy,
              onInk: (ink) => p.reprocessSignature(sigTarget, inkColor: ink),
              onStrength: (s) => p.reprocessSignature(sigTarget, keepInk: true, strength: s),
            ),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Preview (exact server render with sample data)
// ─────────────────────────────────────────────────────────────────────────────

/// The server's exact render with sample data — and "Sample data": the person types a real student's values
/// (name, course, teacher, date, …) per language to see the certificate as it will be issued.
class CertPreviewDialog extends StatefulWidget {
  const CertPreviewDialog({super.key, required this.initialLang});
  final String initialLang;

  @override
  State<CertPreviewDialog> createState() => _CertPreviewDialogState();
}

class _CertPreviewDialogState extends State<CertPreviewDialog> {
  late String _lang = widget.initialLang;
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignerProvider>();
    final c = context.colors;
    final langs = p.design?.langs ?? const ['ar', 'en'];
    final lv = p.design?.view(_lang);
    final ratio = lv == null ? kLogicalLong / kLogicalShort : lv.logicalW / lv.logicalH;
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpace.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 780),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.xs),
            child: Row(children: [
              Expanded(child: Text('certd_preview'.tr, style: AppType.section(context))),
              if (langs.length > 1)
                SizedBox(
                  width: 200,
                  child: StudioSegmented<String>(
                    segments: [for (final l in langs) StudioSegment(value: l, label: certLangName(l))],
                    value: _lang,
                    onChanged: (l) {
                      setState(() => _lang = l);
                      p.preview(l);
                    },
                  ),
                ),
              IconButton(
                tooltip: 'certd_sample_data'.tr,
                isSelected: _editing,
                onPressed: () => setState(() => _editing = !_editing),
                icon: const Icon(Icons.edit_note_rounded),
              ),
              IconButton(
                tooltip: 'close'.tr,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
          ),
          if (_editing)
            Flexible(
              child: CertSampleDataForm(
                key: ValueKey('samples-$_lang'),
                lang: _lang,
                values: p.previewSamples[_lang] ?? const {},
                onApply: (vals) {
                  p.setPreviewSamples(_lang, vals);
                  setState(() => _editing = false);
                  p.preview(_lang);
                },
              ),
            ),
          if (!_editing)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
              child: p.previewing || p.previewBytes == null
                  ? (p.failed && !p.previewing
                      ? SizedBox(
                          height: 200,
                          child: Center(child: Text(p.errorMessage ?? 'certificate_action_failed'.tr, style: AppType.row(context))),
                        )
                      : AspectRatio(
                          aspectRatio: ratio,
                          child: AppShimmer(
                            child: Container(
                              decoration: BoxDecoration(color: c.divider, borderRadius: AppRadius.chipAll),
                            ),
                          ),
                        ))
                  : InteractiveViewer(maxScale: 5, child: Image.memory(p.previewBytes!, fit: BoxFit.contain)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.sm),
            child: Text('certd_preview_hint'.tr, style: AppType.meta(context)),
          ),
        ]),
      ),
    );
  }
}

/// Shown above a design the teacher may use but not edit. One tap → their own copy, attached to the course
/// certificate, fully editable (positions, alignment, fonts, sizes, colours …). The shared original is untouched.
class _CustomizeBanner extends StatelessWidget {
  const _CustomizeBanner({required this.certificateId});
  final int? certificateId;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignerProvider>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, AppSpace.sm, 0),
      child: AppBanner(
        icon: Icons.lock_outline_rounded,
        color: context.colors.warning,
        text: 'cert_readonly_design'.tr,
        action: FilledButton.icon(
          onPressed: p.busy || p.saving
              ? null
              : () async {
                  final ok = await context.read<CertificateDesignerProvider>().customizeCopy(certificateId: certificateId);
                  if (ok && context.mounted) showAppNotice('cert_copy_ready'.tr);
                },
          icon: const Icon(Icons.edit_rounded, size: 18),
          label: Text('cert_customize_copy'.tr),
        ),
      ),
    );
  }
}

/// The template gallery in the wizard: ready-made designs (each with its own Arabic and English layout); a tap makes
/// the person's own copy and opens it in the editor.
class _TemplateStrip extends StatefulWidget {
  const _TemplateStrip({this.orgId});
  final int? orgId;

  @override
  State<_TemplateStrip> createState() => _TemplateStripState();
}

class _TemplateStripState extends State<_TemplateStrip> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CertificateDesignerProvider>().loadTemplates();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignerProvider>();
    final list = p.templates;
    final lang = AppConfig.lang == 'ar' ? 'ar' : 'en';
    if (list == null) {
      return SizedBox(
        height: 170,
        child: AppShimmer(
          child: Row(children: [
            for (var i = 0; i < 2; i++) ...[
              const AppSkeletonBox(width: 200, height: 160, radius: 12),
              const SizedBox(width: AppSpace.sm),
            ],
          ]),
        ),
      );
    }
    if (list.isEmpty) return Text('certd_templates_none'.tr, style: AppType.meta(context));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('certd_templates_hint'.tr, style: AppType.meta(context)),
      const SizedBox(height: AppSpace.sm),
      SizedBox(
        height: 172,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm),
          itemBuilder: (context, i) {
            final t = list[i];
            final img = t.preview(lang);
            return CertTemplateCard(
              name: t.name(lang),
              preview: img == null ? null : MemoryImage(img),
              portrait: t.orientation == 'portrait',
              onTap: p.busy
                  ? null
                  : () async {
                      final ok = await p.createFromTemplate(t.key, orgId: widget.orgId);
                      if (!ok && context.mounted) _failed(p, 'certificate_action_failed');
                    },
            );
          },
        ),
      ),
    ]);
  }
}
