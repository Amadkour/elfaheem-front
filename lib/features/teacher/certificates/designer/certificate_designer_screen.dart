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
//   2. EDITOR  – every element is a field on the page: drag to move, drag the corner handle to
//                resize, tap to select, then change text / font / size / colour / alignment in the
//                panel; add, duplicate, delete, rearrange (Layers tab). Page tab: orientation,
//                template image, regenerate from theme, signature (ink colour + strength), logo.
//   3. SAVE    – stores the template, signature and every field position. When opened from a
//                course certificate (certificateId) the design is also attached to it, so every
//                certificate issued afterwards (manual, bulk, approve, auto) is drawn with it.
//
// "Preview" renders the page on the server with sample data — exactly what students receive.
// The on-screen canvas uses the app's fonts; add Cinzel / GreatVibes / CormorantGaramond / Amiri to
// pubspec.yaml for an identical on-screen look (the server preview is always exact).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import 'certificate_design_models.dart';
import 'certificate_designer_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

final RegExp _arabicChars = RegExp(r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]');

Future<Uint8List?> _pickImage() async {
  final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400);
  return f == null ? null : await f.readAsBytes();
}

void _toast(BuildContext context, String message, {bool error = false}) {
  final c = context.colors;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message, style: const TextStyle(fontFamily: 'bahji', color: Colors.white)),
    backgroundColor: error ? c.danger : c.success,
    behavior: SnackBarBehavior.floating,
  ));
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

  const CertificateDesignerScreen({super.key, this.designId, this.certificateId, this.orgId});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => CertificateDesignerProvider(),
        child: _DesignerView(designId: designId, certificateId: certificateId, orgId: orgId),
      );
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
      if (widget.designId != null) {
        await p.loadDesign(widget.designId!);
      } else if (widget.certificateId != null) {
        await p.loadForCertificate(widget.certificateId!); // null design → wizard
      }
      if (mounted) setState(() => _initializing = false);
    });
  }

  Future<void> _save() async {
    final p = context.read<CertificateDesignerProvider>();
    final ok = await p.save();
    if (!mounted) return;
    if (!ok) {
      _toast(context, 'certificate_action_failed'.tr, error: true);
      return;
    }
    if (widget.certificateId != null) {
      final used = await p.attachToCertificate(widget.certificateId!);
      if (!mounted) return;
      _toast(context, used ? 'cert_design_saved_and_used'.tr : 'cert_design_saved_not_attached'.tr, error: !used);
    } else {
      _toast(context, 'cert_design_saved'.tr);
    }
  }

  Future<void> _showPreview() async {
    final p = context.read<CertificateDesignerProvider>();
    p.previewBytes = null;
    showDialog(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(value: p, child: const _PreviewDialog()),
    );
    await p.preview(arabic: p.editArabic);
  }

  Future<bool> _confirmDiscard() async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('cert_discard_changes_title'.tr),
        content: Text('cert_discard_changes_body'.tr),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('cancel'.tr)),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text('cert_discard'.tr)),
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

    return PopScope(
      canPop: !p.dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmDiscard()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(hasDesign ? p.design!.name : 'cert_designer_title'.tr, style: c.h2.copyWith(fontSize: 16)),
          centerTitle: true,
          actions: [
            if (hasDesign) ...[
              IconButton(
                tooltip: 'cert_preview'.tr,
                onPressed: p.busy || p.saving ? null : _showPreview,
                icon: const Icon(Icons.visibility_outlined),
              ),
              IconButton(
                tooltip: 'save'.tr,
                onPressed: (p.design!.canEdit && !p.saving && !p.busy) ? _save : null,
                icon: Icon(Icons.check_rounded, color: p.dirty ? c.success : null),
              ),
            ],
          ],
        ),
        body: SafeArea(
          child: _initializing || p.isLoading && !hasDesign
              ? const Center(child: AppLoadingIndicator())
              : Stack(children: [
                  hasDesign
                      ? Column(children: [
                          // read-only (organization / someone else's design): offer an editable copy
                          if (!p.design!.canEdit) _CustomizeBanner(certificateId: widget.certificateId),
                          const Expanded(child: _Editor()),
                        ])
                      : _Wizard(orgId: widget.orgId),
                  if (p.busy || p.saving)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.25),
                        child: const Center(child: AppLoadingIndicator()),
                      ),
                    ),
                ]),
        ),
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

    Widget section(String title, Widget child) => Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(c.radiusMedium), boxShadow: c.cardShadow),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 10),
            child,
          ]),
        );

    Future<void> generate() async {
      final ok = await p.createDraft(themeColorHex: colorToHex(c.primary), dark: dark, orgId: orgId);
      if (!ok && context.mounted) _toast(context, 'certificate_action_failed'.tr, error: true);
    }

    Future<void> fromTemplate() async {
      final bytes = await _pickImage();
      if (bytes == null) return;
      final ok = await p.createFromTemplateImage(bytes, orgId: orgId);
      if (!ok && context.mounted) _toast(context, 'certificate_action_failed'.tr, error: true);
    }

    Future<void> blank() async {
      final ok = await p.createBlank(orgId: orgId);
      if (!ok && context.mounted) _toast(context, 'certificate_action_failed'.tr, error: true);
    }

    return Stack(children: [
      Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text('cert_wizard_intro'.tr, style: c.body),
            const SizedBox(height: 14),
            section(
              'cert_orientation'.tr,
              Wrap(spacing: 8, children: [
                for (final o in const ['landscape', 'portrait'])
                  ChoiceChip(
                    selected: p.wizardOrientation == o,
                    label: Text('cert_orientation_$o'.tr),
                    avatar: Icon(o == 'landscape' ? Icons.crop_landscape_rounded : Icons.crop_portrait_rounded, size: 16),
                    onSelected: (_) => p.setWizardOrientation(o),
                  ),
              ]),
            ),
            section(
              'cert_style'.tr,
              Wrap(spacing: 8, children: [
                for (final s in const ['classic', 'modern', 'dark'])
                  ChoiceChip(
                    selected: p.wizardStyle == s,
                    label: Text('cert_style_$s'.tr),
                    onSelected: (_) => p.setWizardStyle(s),
                  ),
              ]),
            ),
            section(
              'cert_logo'.tr,
              _ImageRow(
                url: p.pendingLogoUrl,
                uploadLabel: 'cert_upload_logo'.tr,
                onUpload: () async {
                  final b = await _pickImage();
                  if (b != null) await p.uploadLogo(b);
                },
                onRemove: p.removeLogoImage,
                hint: orgId != null ? 'cert_logo_org_hint'.tr : null,
              ),
            ),
            section('cert_signature'.tr, const _SignatureEditor()),
            const SizedBox(height: 4),
            ElevatedButton.icon(
              onPressed: p.busy ? null : generate,
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text('cert_generate_draft'.tr),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: p.busy ? null : fromTemplate,
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: Text('cert_use_my_template'.tr),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: p.busy ? null : blank, child: Text('cert_start_blank'.tr)),
          ]),
        ),
      ),
      if (p.busy)
        Positioned.fill(
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.25), child: const Center(child: AppLoadingIndicator())),
        ),
    ]);
  }
}

/// Thumbnail + upload / remove buttons for a logo.
class _ImageRow extends StatelessWidget {
  final String? url;
  final String uploadLabel;
  final VoidCallback onUpload;
  final VoidCallback onRemove;
  final String? hint;

  const _ImageRow({required this.url, required this.uploadLabel, required this.onUpload, required this.onRemove, this.hint});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: url == null
            ? Icon(Icons.image_outlined, color: c.textLight)
            : Image.network(url!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: onUpload, icon: const Icon(Icons.upload_rounded, size: 16), label: Text(uploadLabel)),
            if (url != null) IconButton(onPressed: onRemove, icon: Icon(Icons.delete_outline_rounded, color: c.danger)),
          ]),
          if (hint != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(hint!, style: c.caption)),
        ]),
      ),
    ]);
  }
}

/// Signature upload with automatic background removal + ink colour + sensitivity.
class _SignatureEditor extends StatefulWidget {
  const _SignatureEditor();

  @override
  State<_SignatureEditor> createState() => _SignatureEditorState();
}

class _SignatureEditorState extends State<_SignatureEditor> {
  double? _strength;

  static const _inks = <String?, Color>{
    null: Color(0xFF9CA3AF), // keep the original colour
    '#000000': Colors.black,
    '#1E3A8A': Color(0xFF1E3A8A),
    '#1D4ED8': Color(0xFF1D4ED8),
  };

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignerProvider>();
    final c = context.colors;
    final url = p.design?.signatureUrl ?? p.pendingSignatureUrl;
    _strength ??= p.signatureStrength;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _ImageRow(
        url: url,
        uploadLabel: 'cert_upload_signature'.tr,
        onUpload: () async {
          final b = await _pickImage();
          if (b == null) return;
          final ok = await p.uploadSignature(b);
          if (!ok && context.mounted) _toast(context, 'cert_signature_failed'.tr, error: true);
        },
        onRemove: p.removeSignatureImage,
        hint: 'cert_signature_hint'.tr,
      ),
      if (url != null && p.canReprocessSignature) ...[
        const SizedBox(height: 10),
        Text('cert_signature_ink'.tr, style: c.caption),
        const SizedBox(height: 6),
        Row(children: [
          for (final e in _inks.entries)
            GestureDetector(
              onTap: p.busy ? null : () => p.reprocessSignature(inkColor: e.key),
              child: Container(
                width: 30,
                height: 30,
                margin: const EdgeInsetsDirectional.only(end: 8),
                decoration: BoxDecoration(
                  color: e.value,
                  shape: BoxShape.circle,
                  border: Border.all(color: p.signatureInk == e.key ? c.primary : c.divider, width: p.signatureInk == e.key ? 3 : 1),
                ),
                child: e.key == null ? const Icon(Icons.palette_outlined, size: 16, color: Colors.white) : null,
              ),
            ),
        ]),
        const SizedBox(height: 6),
        Text('cert_signature_strength'.tr, style: c.caption),
        Slider(
          value: _strength!,
          onChanged: (v) => setState(() => _strength = v),
          onChangeEnd: (v) => p.reprocessSignature(keepInk: true, strength: v),
        ),
      ],
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Editor
// ─────────────────────────────────────────────────────────────────────────────

class _Editor extends StatelessWidget {
  const _Editor();

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width > 900;
    final canvasArea = Column(children: const [
      _Toolbar(),
      Expanded(child: _CanvasArea()),
    ]);
    if (wide) {
      return Row(children: [
        Expanded(child: canvasArea),
        const VerticalDivider(width: 1),
        const SizedBox(width: 360, child: _SidePanel()),
      ]);
    }
    return Column(children: [
      Expanded(flex: 5, child: canvasArea),
      const Divider(height: 1),
      const Expanded(flex: 4, child: _SidePanel()),
    ]);
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignerProvider>();
    final c = context.colors;
    final d = p.design!;

    Widget tool(IconData icon, String label, VoidCallback? onTap) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 6),
          child: OutlinedButton.icon(
            onPressed: d.canEdit ? onTap : null,
            icon: Icon(icon, size: 16),
            label: Text(label, style: const TextStyle(fontFamily: 'tajawal', fontSize: 12)),
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        );

    return Container(
      color: c.cardBg,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          tool(Icons.text_fields_rounded, 'cert_add_text'.tr, p.addText),
          PopupMenuButton<String>(
            enabled: d.canEdit,
            tooltip: 'cert_add_dynamic'.tr,
            onSelected: p.addPlaceholder,
            itemBuilder: (_) => [
              for (final ph in kCertPlaceholders) PopupMenuItem(value: ph.key, child: Text(ph.labelKey.tr)),
            ],
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: IgnorePointer(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.data_object_rounded, size: 16),
                  label: Text('cert_add_dynamic'.tr, style: const TextStyle(fontFamily: 'tajawal', fontSize: 12)),
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ),
            ),
          ),
          tool(Icons.draw_rounded, 'cert_add_signature'.tr, () {
            if (d.signatureUrl == null) {
              _toast(context, 'cert_upload_signature_first'.tr, error: true);
            } else {
              p.addSignature();
            }
          }),
          tool(Icons.image_outlined, 'cert_add_logo'.tr, () {
            if (d.logoUrl == null) {
              _toast(context, 'cert_upload_logo_first'.tr, error: true);
            } else {
              p.addLogo();
            }
          }),
          tool(Icons.horizontal_rule_rounded, 'cert_add_line'.tr, p.addLine),
          const SizedBox(width: 8),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: false, label: Text('EN')),
              ButtonSegment(value: true, label: Text('ع')),
            ],
            selected: {p.editArabic},
            onSelectionChanged: (s) => p.setEditArabic(s.first),
          ),
        ]),
      ),
    );
  }
}

class _CanvasArea extends StatelessWidget {
  const _CanvasArea();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignerProvider>();
    final d = p.design!;
    final c = context.colors;
    final dark = d.theme['dark'] == true;

    return ColoredBox(
      color: Colors.grey.shade300,
      child: LayoutBuilder(builder: (context, box) {
        const pad = 14.0;
        final scale = ((box.maxWidth - pad * 2) / d.logicalW).clamp(0.05, 10.0).toDouble();
        final fit = ((box.maxHeight - pad * 2) / d.logicalH).clamp(0.05, 10.0).toDouble();
        final s = scale < fit ? scale : fit;
        final pageW = d.logicalW * s, pageH = d.logicalH * s;
        final selected = p.selected;
        final centered = selected != null && ((selected.x + selected.w / 2) - d.logicalW / 2).abs() < 0.5;

        return Center(
          child: GestureDetector(
            onTap: () => p.select(null),
            child: Container(
              width: pageW,
              height: pageH,
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF101014) : Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 14)],
              ),
              child: Stack(clipBehavior: Clip.none, children: [
                if (d.backgroundUrl != null)
                  Positioned.fill(
                    child: Image.network(d.backgroundUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                  ),
                if (centered)
                  Positioned(left: pageW / 2, top: 0, bottom: 0, width: 1, child: ColoredBox(color: c.primary.withValues(alpha: 0.5))),
                for (final f in d.fields)
                  _CanvasField(key: ValueKey(f.id), field: f, scale: s, selected: f.id == p.selectedId),
              ]),
            ),
          ),
        );
      }),
    );
  }
}

class _CanvasField extends StatelessWidget {
  final CertField field;
  final double scale;
  final bool selected;

  const _CanvasField({super.key, required this.field, required this.scale, required this.selected});

  @override
  Widget build(BuildContext context) {
    final p = context.read<CertificateDesignerProvider>();
    final d = p.design!;
    final c = context.colors;
    final f = field;
    final editable = d.canEdit;

    Widget content;
    switch (f.kind) {
      case CertFieldKind.text:
        content = _textContent(p);
        break;
      case CertFieldKind.signature:
      case CertFieldKind.logo:
        final url = f.kind == CertFieldKind.signature ? d.signatureUrl : d.logoUrl;
        content = SizedBox(
          height: (f.h <= 0 ? f.w * 0.35 : f.h) * scale,
          child: Opacity(
            opacity: f.opacity,
            child: url == null
                ? Container(color: Colors.black12, child: const Icon(Icons.image_not_supported_outlined, size: 18))
                : Image.network(url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
          ),
        );
        break;
      case CertFieldKind.line:
        content = Container(height: (f.h < 1 ? 1 : f.h) * scale, color: hexToColor(f.color).withValues(alpha: f.opacity));
        break;
    }

    return Positioned(
      left: f.x * scale,
      top: f.y * scale,
      width: f.w * scale,
      child: Opacity(
        opacity: f.visible ? 1 : 0.25,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => p.select(f.id),
          onPanStart: (_) => p.select(f.id),
          onPanUpdate: editable ? (u) => p.moveField(f.id, u.delta.dx / scale, u.delta.dy / scale) : null,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              decoration: selected
                  ? BoxDecoration(border: Border.all(color: c.primary, width: 1.4))
                  : BoxDecoration(border: Border.all(color: Colors.transparent, width: 1.4)),
              child: content,
            ),
            if (selected && editable)
              PositionedDirectional(
                end: -9,
                bottom: -9,
                child: GestureDetector(
                  onPanUpdate: (u) => p.resizeField(f.id, u.delta.dx / scale, u.delta.dy / scale),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: c.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _textContent(CertificateDesignerProvider p) {
    final f = field;
    final ar = p.editArabic;
    final raw = (ar && (f.textAr ?? '').isNotEmpty) ? f.textAr! : (f.text ?? '');
    final resolved = resolveSample(raw, arabic: ar);
    final cf = certFont(f.font);
    final style = TextStyle(
      fontFamily: cf.family,
      fontWeight: cf.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: cf.italic ? FontStyle.italic : FontStyle.normal,
      fontSize: f.size * scale,
      color: hexToColor(f.color).withValues(alpha: f.opacity),
      letterSpacing: f.letterSpacing * scale,
      height: 1.15,
    );
    final align = f.align == 'left' ? TextAlign.left : (f.align == 'right' ? TextAlign.right : TextAlign.center);
    final alignment = f.align == 'left' ? Alignment.centerLeft : (f.align == 'right' ? Alignment.centerRight : Alignment.center);
    final dir = _arabicChars.hasMatch(resolved) ? TextDirection.rtl : TextDirection.ltr;
    final text = resolved.isEmpty ? ' ' : resolved;

    if (f.maxLines == 1) {
      return SizedBox(
        width: f.w * scale,
        child: FittedBox(
          fit: f.shrink ? BoxFit.scaleDown : BoxFit.none,
          alignment: alignment,
          child: Text(text, style: style, textDirection: dir, softWrap: false),
        ),
      );
    }
    return SizedBox(
      width: f.w * scale,
      child: Text(text, style: style, textAlign: align, textDirection: dir, maxLines: f.maxLines, overflow: TextOverflow.fade),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Side panel: Field · Layers · Page
// ─────────────────────────────────────────────────────────────────────────────

class _SidePanel extends StatefulWidget {
  const _SidePanel();

  @override
  State<_SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<_SidePanel> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  String? _lastSelected;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignerProvider>();
    final c = context.colors;
    // picking something on the canvas jumps to the Field tab
    if (p.selectedId != null && p.selectedId != _lastSelected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tabs.index != 0) _tabs.animateTo(0);
      });
    }
    _lastSelected = p.selectedId;
    final sel = p.selected;

    return Container(
      color: c.cardBg,
      child: Column(children: [
        TabBar(
          controller: _tabs,
          labelStyle: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, fontSize: 13),
          tabs: [
            Tab(text: 'cert_tab_field'.tr),
            Tab(text: 'cert_tab_layers'.tr),
            Tab(text: 'cert_tab_page'.tr),
          ],
        ),
        Expanded(
          child: TabBarView(controller: _tabs, children: [
            sel == null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('cert_select_field_hint'.tr, style: c.body, textAlign: TextAlign.center)))
                : _FieldPanel(key: ValueKey(sel.id), field: sel),
            const _LayersPanel(),
            const _PagePanel(),
          ]),
        ),
      ]),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int decimals;

  const _LabeledSlider({required this.label, required this.value, required this.min, required this.max, required this.onChanged, this.decimals = 0});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      SizedBox(width: 92, child: Text(label, style: c.caption)),
      Expanded(child: Slider(value: value.clamp(min, max).toDouble(), min: min, max: max, onChanged: onChanged)),
      SizedBox(width: 38, child: Text(value.toStringAsFixed(decimals), style: c.caption, textAlign: TextAlign.end)),
    ]);
  }
}

class _FieldPanel extends StatefulWidget {
  final CertField field;

  const _FieldPanel({super.key, required this.field});

  @override
  State<_FieldPanel> createState() => _FieldPanelState();
}

class _FieldPanelState extends State<_FieldPanel> {
  late final TextEditingController _en = TextEditingController(text: widget.field.text ?? '');
  late final TextEditingController _ar = TextEditingController(text: widget.field.textAr ?? '');

  @override
  void dispose() {
    _en.dispose();
    _ar.dispose();
    super.dispose();
  }

  void _insert(CertificateDesignerProvider p, String token) {
    final ctl = p.editArabic ? _ar : _en;
    final t = ctl.text;
    final s = ctl.selection;
    final start = s.isValid ? s.start : t.length;
    final end = s.isValid ? s.end : t.length;
    final next = t.replaceRange(start, end, token);
    ctl.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: start + token.length));
    _push(p);
  }

  void _push(CertificateDesignerProvider p) {
    final ar = _ar.text.trim();
    p.updateField(widget.field.id, (f) => f.copyWith(text: _en.text, textAr: ar.isEmpty ? null : _ar.text, clearTextAr: ar.isEmpty));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignerProvider>();
    final c = context.colors;
    final f = p.selected ?? widget.field;
    final enabled = p.design!.canEdit;
    void edit(CertField Function(CertField) fn) => p.updateField(f.id, fn);

    final themeHex = p.design!.theme['color'] as String?;

    return AbsorbPointer(
      absorbing: !enabled,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        if (f.isText) ...[
          TextField(
            controller: _en,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(labelText: 'cert_field_text'.tr, border: const OutlineInputBorder(), isDense: true),
            onChanged: (_) => _push(p),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ar,
            minLines: 1,
            maxLines: 4,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              labelText: 'cert_field_text_ar'.tr,
              helperText: 'cert_field_text_ar_hint'.tr,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _push(p),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 0, children: [
            for (final ph in kCertPlaceholders)
              ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text(ph.labelKey.tr, style: const TextStyle(fontFamily: 'tajawal', fontSize: 11)),
                onPressed: () => _insert(p, '{${ph.key}}'),
              ),
          ]),
          const SizedBox(height: 10),
          AppDropdown<String>(
            value: f.font,
            isExpanded: true,
            decoration: InputDecoration(labelText: 'cert_font'.tr, border: const OutlineInputBorder(), isDense: true),
            items: [
              for (final ft in kCertFonts)
                DropdownMenuItem(value: ft.key, child: Text(ft.labelKey.tr, style: TextStyle(fontFamily: ft.family))),
            ],
            onChanged: (v) {
              if (v != null) edit((x) => x.copyWith(font: v));
            },
          ),
          _LabeledSlider(label: 'cert_size'.tr, value: f.size, min: 6, max: 150, onChanged: (v) => edit((x) => x.copyWith(size: v))),
        ],
        if (f.kind == CertFieldKind.line)
          _LabeledSlider(label: 'cert_thickness'.tr, value: f.h < 1 ? 1 : f.h, min: 1, max: 12, onChanged: (v) => edit((x) => x.copyWith(h: v))),
        if (f.isImage)
          _LabeledSlider(label: 'cert_height'.tr, value: f.h <= 0 ? 60 : f.h, min: 10, max: 400, onChanged: (v) => edit((x) => x.copyWith(h: v))),
        _LabeledSlider(label: 'cert_width'.tr, value: f.w, min: 20, max: 1000, onChanged: (v) => edit((x) => x.copyWith(w: v))),
        if (f.kind != CertFieldKind.signature && f.kind != CertFieldKind.logo) ...[
          const SizedBox(height: 4),
          Text('cert_color'.tr, style: c.caption),
          const SizedBox(height: 6),
          _ColorPicker(value: f.color, themeHex: themeHex, onChanged: (hex) => edit((x) => x.copyWith(color: hex))),
        ],
        if (f.isText) ...[
          const SizedBox(height: 6),
          Row(children: [
            Text('cert_align'.tr, style: c.caption),
            const SizedBox(width: 10),
            for (final a in const [('left', Icons.format_align_left_rounded), ('center', Icons.format_align_center_rounded), ('right', Icons.format_align_right_rounded)])
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => edit((x) => x.copyWith(align: a.$1)),
                icon: Icon(a.$2, color: f.align == a.$1 ? c.primary : c.textLight),
              ),
          ]),
          _LabeledSlider(label: 'cert_letter_spacing'.tr, value: f.letterSpacing, min: 0, max: 20, decimals: 1, onChanged: (v) => edit((x) => x.copyWith(letterSpacing: v))),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('cert_auto_fit'.tr, style: const TextStyle(fontFamily: 'tajawal', fontSize: 13)),
            value: f.shrink,
            onChanged: (v) => edit((x) => x.copyWith(shrink: v)),
          ),
          Row(children: [
            Text('cert_max_lines'.tr, style: c.caption),
            const Spacer(),
            IconButton(visualDensity: VisualDensity.compact, onPressed: f.maxLines > 1 ? () => edit((x) => x.copyWith(maxLines: x.maxLines - 1)) : null, icon: const Icon(Icons.remove_circle_outline)),
            Text('${f.maxLines}', style: c.body),
            IconButton(visualDensity: VisualDensity.compact, onPressed: f.maxLines < 6 ? () => edit((x) => x.copyWith(maxLines: x.maxLines + 1)) : null, icon: const Icon(Icons.add_circle_outline)),
          ]),
        ],
        _LabeledSlider(label: 'cert_opacity'.tr, value: f.opacity, min: 0.1, max: 1, decimals: 2, onChanged: (v) => edit((x) => x.copyWith(opacity: v))),
        const Divider(),
        Wrap(spacing: 6, runSpacing: 6, children: [
          OutlinedButton.icon(onPressed: () => p.centerHorizontally(f.id), icon: const Icon(Icons.align_horizontal_center_rounded, size: 16), label: Text('cert_center'.tr)),
          OutlinedButton.icon(onPressed: () => p.duplicateField(f.id), icon: const Icon(Icons.copy_rounded, size: 16), label: Text('cert_duplicate'.tr)),
          OutlinedButton.icon(onPressed: () => p.bringForward(f.id), icon: const Icon(Icons.flip_to_front_rounded, size: 16), label: Text('cert_bring_forward'.tr)),
          OutlinedButton.icon(onPressed: () => p.sendBackward(f.id), icon: const Icon(Icons.flip_to_back_rounded, size: 16), label: Text('cert_send_backward'.tr)),
          OutlinedButton.icon(
            onPressed: () => p.removeField(f.id),
            icon: Icon(Icons.delete_outline_rounded, size: 16, color: c.danger),
            label: Text('delete'.tr, style: TextStyle(color: c.danger)),
          ),
        ]),
      ]),
    );
  }
}

class _ColorPicker extends StatefulWidget {
  final String value;
  final String? themeHex;
  final ValueChanged<String> onChanged;

  const _ColorPicker({required this.value, required this.onChanged, this.themeHex});

  @override
  State<_ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<_ColorPicker> {
  late final TextEditingController _hex = TextEditingController(text: widget.value);

  static const _base = ['#000000', '#1C1C24', '#FFFFFF', '#F5F1E6', '#C49A47', '#1F3A8A', '#1E6FD9', '#0E9F6E', '#D64545', '#7C3AED', '#6B7280'];

  @override
  void didUpdateWidget(covariant _ColorPicker old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _hex.text.toUpperCase() != widget.value.toUpperCase()) _hex.text = widget.value;
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final swatches = [if (widget.themeHex != null) widget.themeHex!, ..._base];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in swatches)
          GestureDetector(
            onTap: () => widget.onChanged(s.toUpperCase()),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: hexToColor(s),
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.value.toUpperCase() == s.toUpperCase() ? c.primary : Colors.black26,
                  width: widget.value.toUpperCase() == s.toUpperCase() ? 3 : 1,
                ),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        width: 150,
        child: TextField(
          controller: _hex,
          maxLength: 7,
          decoration: InputDecoration(counterText: '', isDense: true, border: const OutlineInputBorder(), labelText: 'HEX', prefixIcon: Padding(
            padding: const EdgeInsets.all(8),
            child: CircleAvatar(radius: 8, backgroundColor: hexToColor(_hex.text, fallback: Colors.transparent)),
          )),
          onChanged: (v) {
            final t = v.startsWith('#') ? v : '#$v';
            if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(t)) widget.onChanged(t.toUpperCase());
          },
        ),
      ),
    ]);
  }
}

class _LayersPanel extends StatelessWidget {
  const _LayersPanel();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignerProvider>();
    final c = context.colors;
    final d = p.design!;
    if (d.fields.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('cert_no_fields'.tr, style: c.body, textAlign: TextAlign.center)));
    }

    String label(CertField f) {
      switch (f.kind) {
        case CertFieldKind.signature:
          return 'cert_add_signature'.tr;
        case CertFieldKind.logo:
          return 'cert_add_logo'.tr;
        case CertFieldKind.line:
          return 'cert_add_line'.tr;
        case CertFieldKind.text:
          final t = (f.text ?? '').replaceAll('\n', ' ');
          return t.isEmpty ? 'cert_add_text'.tr : t;
      }
    }

    IconData icon(CertField f) => switch (f.kind) {
          CertFieldKind.signature => Icons.draw_rounded,
          CertFieldKind.logo => Icons.image_outlined,
          CertFieldKind.line => Icons.horizontal_rule_rounded,
          CertFieldKind.text => Icons.text_fields_rounded,
        };

    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 0), child: Text('cert_layers_hint'.tr, style: c.caption)),
      Expanded(
        child: ReorderableListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: d.fields.length,
          onReorder: d.canEdit ? p.reorder : (_, __) {},
          itemBuilder: (_, i) {
            final f = d.fields[i];
            return ListTile(
              key: ValueKey(f.id),
              dense: true,
              selected: f.id == p.selectedId,
              selectedTileColor: c.primary.withValues(alpha: 0.08),
              leading: Icon(icon(f), size: 18),
              title: Text(label(f), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'tajawal', fontSize: 13)),
              onTap: () => p.select(f.id),
              trailing: d.canEdit
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => p.updateField(f.id, (x) => x.copyWith(visible: !x.visible)),
                        icon: Icon(f.visible ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => p.removeField(f.id),
                        icon: Icon(Icons.delete_outline_rounded, size: 18, color: c.danger),
                      ),
                      const SizedBox(width: 22), // room for the drag handle
                    ])
                  : null,
            );
          },
        ),
      ),
    ]);
  }
}

class _PagePanel extends StatefulWidget {
  const _PagePanel();

  @override
  State<_PagePanel> createState() => _PagePanelState();
}

class _PagePanelState extends State<_PagePanel> {
  String _style = 'classic';
  bool _resetFields = false;
  late final TextEditingController _name = TextEditingController(text: context.read<CertificateDesignerProvider>().design!.name);

  @override
  void initState() {
    super.initState();
    _style = (context.read<CertificateDesignerProvider>().design!.theme['style'] as String?) ?? 'classic';
  }

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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final themeHex = colorToHex(c.primary);

    Widget section(String title, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 8),
            child,
          ]),
        );

    return AbsorbPointer(
      absorbing: !d.canEdit,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        section(
          'cert_design_name'.tr,
          TextField(
            controller: _name,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            onChanged: p.rename,
          ),
        ),
        section(
          'cert_orientation'.tr,
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'landscape', icon: const Icon(Icons.crop_landscape_rounded, size: 16), label: Text('cert_orientation_landscape'.tr)),
              ButtonSegment(value: 'portrait', icon: const Icon(Icons.crop_portrait_rounded, size: 16), label: Text('cert_orientation_portrait'.tr)),
            ],
            selected: {d.orientation},
            onSelectionChanged: (s) => p.setOrientation(s.first, themeColorHex: themeHex, dark: dark),
          ),
        ),
        section(
          'cert_background'.tr,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in const ['classic', 'modern', 'dark'])
                ChoiceChip(label: Text('cert_style_$s'.tr), selected: _style == s, onSelected: (_) => setState(() => _style = s)),
            ]),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('cert_reset_layout'.tr, style: const TextStyle(fontFamily: 'tajawal', fontSize: 13)),
              value: _resetFields,
              onChanged: (v) => setState(() => _resetFields = v),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ElevatedButton.icon(
                onPressed: () async {
                  final ok = await p.regenerateBackground(themeColorHex: themeHex, dark: dark, style: _style, resetFields: _resetFields);
                  if (!ok && context.mounted) _toast(context, 'certificate_action_failed'.tr, error: true);
                },
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: Text('cert_regenerate_from_theme'.tr),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final b = await _pickImage();
                  if (b != null) await p.uploadBackground(b);
                },
                icon: const Icon(Icons.upload_file_rounded, size: 16),
                label: Text('cert_upload_template'.tr),
              ),
              if (d.backgroundUrl != null)
                TextButton.icon(onPressed: p.removeBackground, icon: Icon(Icons.layers_clear_outlined, size: 16, color: c.danger), label: Text('cert_remove_background'.tr, style: TextStyle(color: c.danger))),
            ]),
          ]),
        ),
        section('cert_signature'.tr, const _SignatureEditor()),
        section(
          'cert_logo'.tr,
          _ImageRow(
            url: d.logoUrl,
            uploadLabel: 'cert_upload_logo'.tr,
            onUpload: () async {
              final b = await _pickImage();
              if (b != null) await p.uploadLogo(b);
            },
            onRemove: p.removeLogoImage,
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Preview (exact server render with sample data)
// ─────────────────────────────────────────────────────────────────────────────

class _PreviewDialog extends StatelessWidget {
  const _PreviewDialog();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignerProvider>();
    final c = context.colors;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(children: [
              Expanded(child: Text('cert_preview'.tr, style: c.h2.copyWith(fontSize: 15))),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [ButtonSegment(value: false, label: Text('EN')), ButtonSegment(value: true, label: Text('ع'))],
                selected: {p.editArabic},
                onSelectionChanged: (s) {
                  p.setEditArabic(s.first);
                  p.preview(arabic: s.first);
                },
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: p.previewing || p.previewBytes == null
                  ? SizedBox(height: 240, child: Center(child: p.failed && !p.previewing ? Text('certificate_action_failed'.tr, style: c.body) : const AppLoadingIndicator()))
                  : InteractiveViewer(maxScale: 5, child: Image.memory(p.previewBytes!, fit: BoxFit.contain)),
            ),
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
    final c = context.colors;
    final p = context.watch<CertificateDesignerProvider>();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: c.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.warning.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(Icons.lock_outline_rounded, color: c.warning, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text('cert_readonly_design'.tr,
              style: TextStyle(fontFamily: 'tajawal', fontSize: 12.5, fontWeight: FontWeight.w600, color: c.textDark, height: 1.4)),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: p.busy || p.saving
              ? null
              : () async {
                  final ok = await context.read<CertificateDesignerProvider>().customizeCopy(certificateId: certificateId);
                  if (ok && context.mounted) {
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('cert_copy_ready'.tr)));
                  }
                },
          icon: const Icon(Icons.edit_rounded, size: 18),
          label: Text('cert_customize_copy'.tr),
        ),
      ]),
    );
  }
}
