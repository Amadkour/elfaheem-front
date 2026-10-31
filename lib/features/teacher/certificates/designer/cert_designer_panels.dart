// features/teacher/certificates/designer/cert_designer_panels.dart
//
// The certificate designer's presentational parts — plain values in, callbacks out, no provider — so the layout
// harness (test/ui/cert_designer_v2_layout_test.dart) can pump each one at 320 × 640 and 1400 × 900:
//
//   CertLangSwitcher     ع / EN: one tab per enabled language, and under EN the English settings that still follow
//                        the Arabic design ("Same as Arabic: Background · Logo")
//   CertLangsControl     Arabic only · English only · Both
//   CertAssetRow         a page image (background, default logo / signature) with its state: Arabic upload /
//                        remove; English "Same as Arabic" + Customize for English, or its own image + Reset to Arabic
//   CertFieldProps       the selected element's properties (text · logo · signature with captions · QR · line ·
//                        photo) on the studio's property primitives (studio_props.dart)
//   CertSignatureTuner   ink colour + background-removal strength of an uploaded signature
//   CertToolsPanel       "Add to the page": text, dynamic field, logo, signature, line, student photo, QR
//   CertLayersList       every element, top first: select, show / hide, reorder, delete
//   CertToolbarRow       the studio toolbar + duplicate and order (z) commands
//   showCertCustomFieldDialog   "Add a field…": a custom {key} (a–z, 0–9, _) and its preview sample
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_contrast.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/studio/studio.dart';

import 'certificate_design_models.dart';

/// One property change of the selected element: `edit((f) => f.copyWith(size: 30), label: 'size')`.
typedef CertFieldEdit = void Function(CertField Function(CertField f) change, {String label, bool coalesce});

String certLangName(String l) => l == 'ar' ? 'certd_lang_ar'.tr : 'certd_lang_en'.tr;

IconData certKindIcon(CertFieldKind k) => switch (k) {
      CertFieldKind.text => Icons.text_fields_rounded,
      CertFieldKind.signature => Icons.draw_rounded,
      CertFieldKind.logo => Icons.image_outlined,
      CertFieldKind.line => Icons.horizontal_rule_rounded,
      CertFieldKind.photo => Icons.account_circle_outlined,
      CertFieldKind.qr => Icons.qr_code_2_rounded,
    };

String certKindLabel(CertFieldKind k) => switch (k) {
      CertFieldKind.text => 'certd_add_text'.tr,
      CertFieldKind.signature => 'certd_add_signature'.tr,
      CertFieldKind.logo => 'certd_add_logo'.tr,
      CertFieldKind.line => 'certd_add_line'.tr,
      CertFieldKind.photo => 'certd_add_photo'.tr,
      CertFieldKind.qr => 'certd_add_qr'.tr,
    };

/// A layer's one-line name: the wording for text, the signer's name for a signature, else the kind.
String certFieldTitle(CertField f, {required bool arabic}) {
  switch (f.kind) {
    case CertFieldKind.text:
      final t = ((arabic && (f.textAr ?? '').isNotEmpty) ? f.textAr! : (f.text ?? '')).replaceAll('\n', ' ').trim();
      return t.isEmpty ? certKindLabel(f.kind) : t;
    case CertFieldKind.signature:
      final n = (f.sigName ?? '').trim();
      return n.isEmpty ? certKindLabel(f.kind) : '${certKindLabel(f.kind)} · $n';
    default:
      return certKindLabel(f.kind);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Languages
// ─────────────────────────────────────────────────────────────────────────────

class CertLangSwitcher extends StatelessWidget {
  const CertLangSwitcher({
    super.key,
    required this.langs,
    required this.active,
    required this.onChanged,
    this.inheritedEn = const [],
    this.onManage,
  });

  /// The enabled languages (only those get a tab).
  final List<String> langs;
  final String active;
  final ValueChanged<String> onChanged;

  /// Labels of the English settings that follow the Arabic design.
  final List<String> inheritedEn;

  /// Opens the Languages control.
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = ensureContrast(c.primary, [Color.alphaBlend(c.primaryTint, c.cardBg), c.cardBg]);
    Widget tab(String l) {
      final on = l == active;
      return Semantics(
        button: true,
        selected: on,
        label: certLangName(l),
        excludeSemantics: true,
        child: InkWell(
          onTap: () => onChanged(l),
          borderRadius: AppRadius.chipAll,
          child: AnimatedContainer(
            duration: AppMotion.of(context).fast,
            curve: AppMotion.curve,
            constraints: const BoxConstraints(minHeight: AppTouch.min - 6),
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xs, AppSpace.xxs, AppSpace.sm, AppSpace.xxs),
            decoration: BoxDecoration(
              color: on ? c.cardBg : null,
              borderRadius: BorderRadius.circular(AppRadius.chip - 3),
              boxShadow: on ? c.cardShadow : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? c.primaryTint : c.cardBg,
                  shape: BoxShape.circle,
                  border: on ? null : Border.all(color: c.divider),
                ),
                child: Text(l == 'ar' ? 'ع' : 'EN',
                    style: l == 'ar'
                        // the Arabic letter in the person's Arabic UI font, whatever the UI language
                        ? appText(13, w: FontWeight.w600, c: on ? accent : c.textMedium)
                            .copyWith(fontFamily: AppFonts.arabicChoice.family)
                        : appText(10.5, w: FontWeight.w600, c: on ? accent : c.textMedium)),
              ),
              const SizedBox(width: AppSpace.xs),
              Flexible(
                child: Text(certLangName(l),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appText(13, w: on ? FontWeight.w600 : FontWeight.w500, c: on ? c.textDark : c.textMedium)),
              ),
            ]),
          ),
        ),
      );
    }

    final tabs = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final l in CertDesign.allLangs)
          if (langs.contains(l)) Flexible(child: tab(l)),
      ]),
    );
    final only = langs.length == 1;
    return Wrap(
      spacing: AppSpace.xs,
      runSpacing: AppSpace.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        tabs,
        if (only)
          Text(langs.first == 'ar' ? 'certd_langs_ar_only'.tr : 'certd_langs_en_only'.tr,
              style: AppType.meta(context)),
        if (onManage != null)
          TextButton.icon(
            onPressed: onManage,
            style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
            icon: Icon(Icons.translate_rounded, size: 18, color: accent),
            label: Text('certd_langs'.tr, style: appText(13, w: FontWeight.w600, c: accent)),
          ),
        if (active == 'en' && inheritedEn.isNotEmpty)
          Container(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xs, AppSpace.xxs, AppSpace.sm, AppSpace.xxs),
            decoration: BoxDecoration(color: c.primaryTint, borderRadius: AppRadius.chipAll),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.link_rounded, size: 16, color: accent),
              const SizedBox(width: AppSpace.xxs),
              Flexible(
                child: Text(
                  '${'certd_same_as_ar'.tr}: ${inheritedEn.join(' · ')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: appText(12, w: FontWeight.w500, c: c.textDark),
                ),
              ),
            ]),
          ),
      ],
    );
  }
}

/// Which languages certificates are issued in.
class CertLangsControl extends StatelessWidget {
  const CertLangsControl({super.key, required this.langs, required this.onChanged, this.enabled = true});

  final List<String> langs;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final value = langs.length == 2 ? 'both' : langs.first;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StudioSegmented<String>(
        segments: [
          StudioSegment(value: 'ar', label: 'certd_langs_ar_only'.tr),
          StudioSegment(value: 'en', label: 'certd_langs_en_only'.tr),
          StudioSegment(value: 'both', label: 'certd_langs_both'.tr),
        ],
        value: value,
        onChanged: enabled ? (v) => onChanged(v == 'both' ? const ['ar', 'en'] : [v]) : null,
      ),
      const SizedBox(height: AppSpace.xs),
      Text('certd_langs_hint'.tr, style: AppType.meta(context)),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page images
// ─────────────────────────────────────────────────────────────────────────────

/// A page image row. Arabic: [state] own (an image) or none. English: same (follows Arabic), own or none.
class CertAssetRow extends StatelessWidget {
  const CertAssetRow({
    super.key,
    required this.title,
    required this.url,
    this.state = CertInherit.own,
    this.english = false,
    this.enabled = true,
    this.onUpload,
    this.onRemove,
    this.onCustomize,
    this.onReset,
    this.hint,
    this.more = const [],
  });

  final String title;

  /// The image in effect (the Arabic one while English follows it).
  final String? url;
  final CertInherit state;
  final bool english;
  final bool enabled;
  final VoidCallback? onUpload, onRemove, onCustomize, onReset;
  final String? hint;

  /// Extra actions after the row's own (e.g. "Generate from theme").
  final List<Widget> more;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final has = (url ?? '').isNotEmpty;
    final same = english && state == CertInherit.same;
    final accent = ensureContrast(c.primary, [c.cardBg]);
    final status = same
        ? 'certd_same_as_ar'.tr
        : (!has ? (english ? 'certd_none_in_en'.tr : 'certd_no_image'.tr) : (english ? 'certd_own_en'.tr : ''));

    Widget action(IconData icon, String label, VoidCallback? onTap, {bool danger = false}) => TextButton.icon(
          onPressed: enabled ? onTap : null,
          style: TextButton.styleFrom(
            minimumSize: const Size(AppTouch.min, AppTouch.min),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
            foregroundColor: danger ? ensureContrast(c.danger, [c.cardBg]) : accent,
          ),
          icon: Icon(icon, size: 18),
          label: Text(label, style: appText(13, w: FontWeight.w600)),
        );

    final actions = <Widget>[
      if (same) action(Icons.tune_rounded, 'certd_customize_en'.tr, onCustomize),
      if (!same) action(Icons.upload_rounded, has ? 'certd_replace_image'.tr : 'certd_upload_image'.tr, onUpload),
      if (!same && has && onRemove != null) action(Icons.delete_outline_rounded, 'remove'.tr, onRemove, danger: true),
      if (english && !same) action(Icons.undo_rounded, 'certd_reset_to_ar'.tr, onReset),
      ...more,
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: c.inputBg,
            borderRadius: AppRadius.chipAll,
            border: Border.all(color: c.divider),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(fit: StackFit.expand, children: [
            if (has)
              Opacity(
                opacity: same ? 0.55 : 1,
                child: Image.network(url!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: c.textLight)),
              )
            else
              Icon(Icons.image_outlined, color: c.textLight),
            if (same)
              PositionedDirectional(
                end: 2,
                bottom: 2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(color: c.cardBg, shape: BoxShape.circle),
                  child: Icon(Icons.link_rounded, size: 14, color: accent),
                ),
              ),
          ]),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title.isNotEmpty) Text(title, style: appText(14, w: FontWeight.w600, c: c.textDark)),
            if (status.isNotEmpty) ...[
              if (title.isNotEmpty) const SizedBox(height: 2),
              Row(children: [
                if (same) ...[Icon(Icons.link_rounded, size: 14, color: accent), const SizedBox(width: 4)],
                Flexible(
                  child: Text(status,
                      style: appText(12, w: FontWeight.w500, c: same ? accent : c.textMedium)),
                ),
              ]),
            ],
            if (hint != null) ...[
              const SizedBox(height: 2),
              Text(hint!, style: AppType.meta(context)),
            ],
          ]),
        ),
      ]),
      if (actions.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xxs),
        Wrap(spacing: AppSpace.xxs, runSpacing: 0, children: actions),
      ],
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Signature tuner
// ─────────────────────────────────────────────────────────────────────────────

/// Ink colours a signature can be recoloured to (null = keep the original ink).
const certSignatureInks = <String?>[null, '#000000', '#1E3A8A', '#1D4ED8'];

class CertSignatureTuner extends StatefulWidget {
  const CertSignatureTuner({
    super.key,
    required this.ink,
    required this.strength,
    required this.onInk,
    required this.onStrength,
    this.enabled = true,
  });

  final String? ink;
  final double strength;
  final ValueChanged<String?> onInk;

  /// Called when the slider is released (each change re-runs the background removal on the server).
  final ValueChanged<double> onStrength;
  final bool enabled;

  @override
  State<CertSignatureTuner> createState() => _CertSignatureTunerState();
}

class _CertSignatureTunerState extends State<CertSignatureTuner> {
  late double _strength = widget.strength;

  @override
  void didUpdateWidget(covariant CertSignatureTuner old) {
    super.didUpdateWidget(old);
    if (old.strength != widget.strength) _strength = widget.strength;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ring = ensureContrast(c.primary, [c.cardBg]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StudioPropField(
        label: 'cert_signature_ink'.tr,
        child: Wrap(children: [
          for (final ink in certSignatureInks)
            Semantics(
              button: true,
              selected: widget.ink == ink,
              label: ink ?? 'certd_ink_original'.tr,
              excludeSemantics: true,
              child: InkResponse(
                onTap: widget.enabled ? () => widget.onInk(ink) : null,
                radius: AppTouch.min / 2,
                child: SizedBox(
                  width: AppTouch.min,
                  height: AppTouch.min,
                  child: Center(
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: ink == null ? c.inputBg : hexToColor(ink),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: widget.ink == ink ? ring : c.divider, width: widget.ink == ink ? 3 : 1),
                      ),
                      child: ink == null ? Icon(Icons.palette_outlined, size: 16, color: c.textMedium) : null,
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: AppSpace.xs),
      StudioPropField(
        label: 'cert_signature_strength'.tr,
        value: '${(_strength * 100).round()}%',
        child: Slider(
          value: _strength.clamp(0.0, 1.0),
          onChanged: widget.enabled ? (v) => setState(() => _strength = v) : null,
          onChangeEnd: widget.enabled ? widget.onStrength : null,
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Element properties
// ─────────────────────────────────────────────────────────────────────────────

class CertFieldProps extends StatefulWidget {
  const CertFieldProps({
    super.key,
    required this.field,
    required this.arabic,
    required this.onEdit,
    required this.onText,
    this.enabled = true,
    this.defaultImageUrl,
    this.themeHex,
    this.customKeys = const [],
    this.onAskCustomField,
    this.onReplaceImage,
    this.onUseDefaultImage,
    this.signatureTuner,
    this.onDuplicate,
    this.onDelete,
    this.onForward,
    this.onBackward,
  });

  final CertField field;

  /// The language being edited (the text box edits that language's wording).
  final bool arabic;
  final CertFieldEdit onEdit;

  /// The wording of a text element (the host applies the language rule).
  final ValueChanged<String> onText;
  final bool enabled;

  /// The language's default logo / signature (what a box without its own image shows).
  final String? defaultImageUrl;

  /// The design's theme colour, offered first among the swatches.
  final String? themeHex;

  /// Custom placeholders already used in this layout.
  final List<String> customKeys;

  /// "Add a field…": asks for a custom key and returns it (null = cancelled).
  final Future<String?> Function()? onAskCustomField;
  final VoidCallback? onReplaceImage, onUseDefaultImage;
  final Widget? signatureTuner;
  final VoidCallback? onDuplicate, onDelete, onForward, onBackward;

  @override
  State<CertFieldProps> createState() => _CertFieldPropsState();
}

class _CertFieldPropsState extends State<CertFieldProps> {
  late final _text = TextEditingController(text: _wording(widget.field));
  late final _name = TextEditingController(text: widget.field.sigName ?? '');
  late final _title = TextEditingController(text: widget.field.sigTitle ?? '');
  late final _qr = TextEditingController(text: widget.field.text ?? '');
  final _textFocus = FocusNode();
  final _nameFocus = FocusNode();
  final _titleFocus = FocusNode();
  final _qrFocus = FocusNode();

  String _wording(CertField f) => widget.arabic
      ? ((f.textAr ?? '').isNotEmpty ? f.textAr! : (f.text ?? ''))
      : (f.text ?? '');

  @override
  void didUpdateWidget(covariant CertFieldProps old) {
    super.didUpdateWidget(old);
    final f = widget.field;
    void sync(TextEditingController c, FocusNode n, String v) {
      if ((!n.hasFocus || old.field.id != f.id) && c.text != v) c.text = v;
    }

    sync(_text, _textFocus, _wording(f));
    sync(_name, _nameFocus, f.sigName ?? '');
    sync(_title, _titleFocus, f.sigTitle ?? '');
    sync(_qr, _qrFocus, f.text ?? '');
  }

  @override
  void dispose() {
    for (final c in [_text, _name, _title, _qr]) {
      c.dispose();
    }
    for (final n in [_textFocus, _nameFocus, _titleFocus, _qrFocus]) {
      n.dispose();
    }
    super.dispose();
  }

  void _insert(String token) {
    final t = _text.text;
    final s = _text.selection;
    final start = s.isValid ? s.start : t.length;
    final end = s.isValid ? s.end : t.length;
    final next = t.replaceRange(start, end, token);
    _text.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: start + token.length));
    widget.onText(next);
  }

  void _edit(CertField Function(CertField f) change, {String label = 'edit', bool coalesce = true}) =>
      widget.onEdit(change, label: label, coalesce: coalesce);

  List<Color> get _swatches {
    final theme = widget.themeHex == null ? null : hexToColor(widget.themeHex!);
    return [?theme, ...kStudioSwatches.where((s) => theme == null || s != theme)];
  }

  Widget _color(String label, CertField f) => StudioColorField(
        label: label,
        value: hexToColor(f.color),
        swatches: _swatches,
        onChanged: (col) {
          if (col != null) _edit((x) => x.copyWith(color: colorToHex(col)), label: 'color');
        },
      );

  Widget _opacity(CertField f) => StudioOpacitySlider(
        value: f.opacity,
        onChanged: (v) => _edit((x) => x.copyWith(opacity: (v * 100).roundToDouble() / 100), label: 'opacity'),
      );

  Widget _font(CertField f) => StudioFontPicker(
        options: [for (final ft in kCertFonts) StudioFontOption(id: ft.key, label: ft.labelKey.tr, family: ft.family)],
        value: f.font,
        onChanged: (v) => _edit((x) => x.copyWith(font: v), label: 'font', coalesce: false),
      );

  Widget _pair(Widget a, Widget b) => LayoutBuilder(
        builder: (context, box) => box.maxWidth < 300
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: AppSpace.sm), b])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: a),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: b),
              ]),
      );

  Widget _position(CertField f) {
    final square = f.isSquare;
    return StudioPropSection(title: 'certd_position'.tr, children: [
      _pair(
        StudioStepper(
          label: 'X',
          value: f.x,
          min: -300,
          max: 1500,
          onChanged: (v) => _edit((x) => x.copyWith(x: v), label: 'move'),
        ),
        StudioStepper(
          label: 'Y',
          value: f.y,
          min: -300,
          max: 1500,
          onChanged: (v) => _edit((x) => x.copyWith(y: v), label: 'move'),
        ),
      ),
      if (f.isImage)
        _pair(
          StudioStepper(
            label: 'certd_w'.tr,
            value: f.w,
            min: 16,
            max: 1000,
            onChanged: (v) => _edit((x) => x.copyWith(w: v), label: 'resize'),
          ),
          StudioStepper(
            label: 'certd_h'.tr,
            value: f.h <= 0 ? (f.w * 0.5).roundToDouble() : f.h,
            min: 10,
            max: 1000,
            onChanged: (v) => _edit((x) => x.copyWith(h: v), label: 'resize'),
          ),
        )
      else
        StudioStepper(
          label: square ? 'certd_size'.tr : 'certd_w'.tr,
          value: f.w,
          min: square ? 40 : 20,
          max: 1000,
          onChanged: (v) => _edit((x) => x.copyWith(w: v, h: f.kind == CertFieldKind.photo ? v : null), label: 'resize'),
        ),
    ]);
  }

  Widget _imageSection(CertField f, String defaultLabel) {
    final c = context.colors;
    final own = (f.src ?? '').isNotEmpty;
    final url = own ? f.src : widget.defaultImageUrl;
    final accent = ensureContrast(c.primary, [c.cardBg]);
    return StudioPropSection(title: 'certd_image'.tr, first: true, children: [
      Row(children: [
        Container(
          width: 72,
          height: 56,
          decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
          clipBehavior: Clip.antiAlias,
          child: (url ?? '').isEmpty
              ? Icon(certKindIcon(f.kind), color: c.textLight)
              : Image.network(url!,
                  fit: BoxFit.contain, errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: c.textLight)),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text(
            own ? 'certd_own_image'.tr : ((url ?? '').isEmpty ? 'certd_no_image'.tr : 'certd_uses_default'.tr),
            style: appText(12.5, w: FontWeight.w500, c: c.textMedium),
          ),
        ),
      ]),
      Wrap(spacing: AppSpace.xxs, children: [
        TextButton.icon(
          onPressed: widget.enabled ? widget.onReplaceImage : null,
          style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min), foregroundColor: accent),
          icon: const Icon(Icons.upload_rounded, size: 18),
          label: Text(own || (url ?? '').isNotEmpty ? 'certd_replace_image'.tr : 'certd_upload_image'.tr,
              style: appText(13, w: FontWeight.w600)),
        ),
        if (own && (widget.defaultImageUrl ?? '').isNotEmpty)
          TextButton.icon(
            onPressed: widget.enabled ? widget.onUseDefaultImage : null,
            style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min), foregroundColor: accent),
            icon: const Icon(Icons.undo_rounded, size: 18),
            label: Text(defaultLabel, style: appText(13, w: FontWeight.w600)),
          ),
      ]),
    ]);
  }

  /// The length counter only shows near the server's limit (calm until it matters).
  static Widget? _counter(BuildContext context,
      {required int currentLength, required bool isFocused, required int? maxLength}) {
    if (maxLength == null || currentLength < maxLength * 0.8) return null;
    return Text('$currentLength / $maxLength', style: AppType.meta(context));
  }

  Widget _captionField(TextEditingController ctl, FocusNode focus, String label, ValueChanged<String> onChanged) =>
      StudioPropField(
        label: label,
        child: TextField(
          controller: ctl,
          focusNode: focus,
          maxLength: kCertCaptionMax,
          buildCounter: _counter,
          maxLines: 1,
          textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
          style: appText(14, w: FontWeight.w500, c: context.colors.textDark),
          decoration: const InputDecoration(isDense: true),
          onChanged: onChanged,
        ),
      );

  List<Widget> _textBody(CertField f) {
    final c = context.colors;
    final accent = ensureContrast(c.primary, [c.cardBg]);
    Widget chip(String label, String token, {bool custom = false}) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xxs),
          child: ActionChip(
            visualDensity: VisualDensity.compact,
            avatar: Icon(custom ? Icons.data_object_rounded : Icons.add_rounded, size: 16, color: accent),
            label: Text(label, style: appText(12, w: FontWeight.w500, c: c.textDark)),
            onPressed: widget.enabled ? () => _insert(token) : null,
          ),
        );
    return [
      StudioPropSection(title: 'certd_text'.tr, first: true, children: [
        StudioPropField(
          label: widget.arabic ? 'certd_text_ar'.tr : 'certd_text_en'.tr,
          child: TextField(
            controller: _text,
            focusNode: _textFocus,
            minLines: 2,
            maxLines: 5,
            maxLength: kCertTextMax,
            buildCounter: _counter,
            textDirection: widget.arabic ? TextDirection.rtl : TextDirection.ltr,
            style: appText(14, w: FontWeight.w500, c: c.textDark),
            decoration: const InputDecoration(isDense: true),
            onChanged: widget.onText,
          ),
        ),
        StudioPropField(
          label: 'certd_insert_value'.tr,
          child: Wrap(spacing: AppSpace.xxs, children: [
            for (final ph in kCertPlaceholders) chip(ph.labelKey.tr, '{${ph.key}}'),
            for (final k in widget.customKeys) chip('{$k}', '{$k}', custom: true),
            if (widget.onAskCustomField != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xxs),
                child: ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.add_circle_outline_rounded, size: 16, color: accent),
                  label: Text('certd_custom_field'.tr, style: appText(12, w: FontWeight.w600, c: accent)),
                  onPressed: widget.enabled
                      ? () async {
                          final k = await widget.onAskCustomField!();
                          if (k != null && mounted) _insert('{$k}');
                        }
                      : null,
                ),
              ),
          ]),
        ),
      ]),
      StudioPropSection(title: 'certd_typography'.tr, children: [
        _font(f),
        StudioStepper(
          label: 'certd_font_size'.tr,
          value: f.size,
          min: 6,
          max: 150,
          onChanged: (v) => _edit((x) => x.copyWith(size: v), label: 'size'),
        ),
        StudioTextAlignPicker(
          value: f.align == 'left' ? TextAlign.left : (f.align == 'right' ? TextAlign.right : TextAlign.center),
          onChanged: (a) => _edit(
              (x) => x.copyWith(align: a == TextAlign.left ? 'left' : (a == TextAlign.right ? 'right' : 'center')),
              label: 'align',
              coalesce: false),
        ),
        _color('studio_color'.tr, f),
        StudioStepper(
          label: 'cert_letter_spacing'.tr,
          value: f.letterSpacing,
          min: 0,
          max: 20,
          step: .5,
          decimals: 1,
          onChanged: (v) => _edit((x) => x.copyWith(letterSpacing: v), label: 'spacing'),
        ),
        StudioStepper(
          label: 'cert_max_lines'.tr,
          value: f.maxLines.toDouble(),
          min: 1,
          max: 10,
          onChanged: (v) => _edit((x) => x.copyWith(maxLines: v.round()), label: 'lines'),
        ),
        AppSwitchTile(
          dense: true,
          title: 'cert_auto_fit'.tr,
          value: f.shrink,
          onChanged: widget.enabled ? (v) => _edit((x) => x.copyWith(shrink: v), label: 'fit', coalesce: false) : null,
        ),
        _opacity(f),
      ]),
    ];
  }

  List<Widget> _body(CertField f) {
    final c = context.colors;
    switch (f.kind) {
      case CertFieldKind.text:
        return _textBody(f);
      case CertFieldKind.logo:
        return [
          _imageSection(f, 'certd_use_default_logo'.tr),
          StudioPropSection(title: 'certd_appearance'.tr, children: [_opacity(f)]),
        ];
      case CertFieldKind.signature:
        return [
          _imageSection(f, 'certd_use_default_sig'.tr),
          ?widget.signatureTuner,
          StudioPropSection(title: 'certd_captions'.tr, children: [
            _captionField(_name, _nameFocus, 'certd_sig_name'.tr,
                (v) => _edit((x) => x.copyWith(sigName: v), label: 'caption')),
            _captionField(_title, _titleFocus, 'certd_sig_title'.tr,
                (v) => _edit((x) => x.copyWith(sigTitle: v), label: 'caption')),
            _font(f),
            StudioStepper(
              label: 'certd_caption_size'.tr,
              value: f.size,
              min: 8,
              max: 80,
              onChanged: (v) => _edit((x) => x.copyWith(size: v), label: 'size'),
            ),
            _color('studio_color'.tr, f),
            _opacity(f),
          ]),
        ];
      case CertFieldKind.qr:
        final custom = (f.text ?? '').isNotEmpty && f.text != kCertQrDefaultText;
        return [
          StudioPropSection(title: 'certd_qr_content'.tr, first: true, children: [
            StudioSegmented<bool>(
              segments: [
                StudioSegment(value: false, label: 'certd_qr_verify'.tr),
                StudioSegment(value: true, label: 'certd_qr_custom'.tr),
              ],
              value: custom,
              onChanged: widget.enabled
                  ? (v) {
                      if (!v) {
                        _qr.text = '';
                        _edit((x) => x.copyWith(clearText: true), label: 'qr', coalesce: false);
                      } else if (!custom) {
                        _qr.text = '{serial}';
                        _edit((x) => x.copyWith(text: '{serial}'), label: 'qr', coalesce: false);
                      }
                    }
                  : null,
            ),
            if (custom)
              StudioPropField(
                label: 'certd_qr_text'.tr,
                child: TextField(
                  controller: _qr,
                  focusNode: _qrFocus,
                  maxLength: kCertTextMax,
                  buildCounter: _counter,
                  style: appText(14, w: FontWeight.w500, c: c.textDark),
                  decoration: const InputDecoration(isDense: true),
                  onChanged: (v) => _edit((x) => v.trim().isEmpty ? x.copyWith(clearText: true) : x.copyWith(text: v),
                      label: 'qr'),
                ),
              ),
            Text('certd_qr_hint'.tr, style: AppType.meta(context)),
          ]),
          StudioPropSection(title: 'certd_appearance'.tr, children: [_color('certd_qr_ink'.tr, f), _opacity(f)]),
        ];
      case CertFieldKind.line:
        return [
          StudioPropSection(title: 'certd_appearance'.tr, first: true, children: [
            StudioStepper(
              label: 'cert_thickness'.tr,
              value: f.h < 1 ? 1 : f.h,
              min: 1,
              max: 12,
              step: .5,
              decimals: 1,
              onChanged: (v) => _edit((x) => x.copyWith(h: v), label: 'thickness'),
            ),
            _color('studio_color'.tr, f),
            _opacity(f),
          ]),
        ];
      case CertFieldKind.photo:
        return [
          StudioPropSection(title: 'certd_appearance'.tr, first: true, children: [
            StudioPropField(
              label: 'certd_shape'.tr,
              child: StudioSegmented<String>(
                segments: [
                  StudioSegment(value: 'circle', label: 'certd_shape_circle'.tr),
                  StudioSegment(value: 'rounded', label: 'certd_shape_rounded'.tr),
                ],
                value: f.shape == 'rounded' ? 'rounded' : 'circle',
                onChanged: widget.enabled
                    ? (v) => _edit((x) => x.copyWith(shape: v), label: 'shape', coalesce: false)
                    : null,
              ),
            ),
            Text('certd_photo_hint'.tr, style: AppType.meta(context)),
            _opacity(f),
          ]),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = widget.field;
    final accent = ensureContrast(c.primary, [c.cardBg]);
    Widget cmd(IconData icon, String label, VoidCallback? onTap, {bool danger = false}) => TextButton.icon(
          onPressed: widget.enabled ? onTap : null,
          style: TextButton.styleFrom(
            minimumSize: const Size(AppTouch.min, AppTouch.min),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
            foregroundColor: danger ? ensureContrast(c.danger, [c.cardBg]) : accent,
          ),
          icon: Icon(icon, size: 18),
          label: Text(label, style: appText(13, w: FontWeight.w600)),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: c.primaryTint, borderRadius: AppRadius.chipAll),
          child: Icon(certKindIcon(f.kind), size: 20, color: accent),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(certKindLabel(f.kind),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
            Text('${'certd_editing'.tr} · ${certLangName(widget.arabic ? 'ar' : 'en')}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ]),
        ),
      ]),
      const SizedBox(height: AppSpace.xs),
      AbsorbPointer(
        absorbing: !widget.enabled,
        child: Opacity(
          opacity: widget.enabled ? 1 : 0.6,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ..._body(f),
            _position(f),
          ]),
        ),
      ),
      if (widget.enabled) ...[
        Divider(height: AppSpace.md, color: c.divider),
        Wrap(spacing: AppSpace.xxs, children: [
          if (widget.onDuplicate != null) cmd(Icons.copy_rounded, 'certd_duplicate'.tr, widget.onDuplicate),
          if (widget.onForward != null) cmd(Icons.flip_to_front_rounded, 'certd_forward'.tr, widget.onForward),
          if (widget.onBackward != null) cmd(Icons.flip_to_back_rounded, 'certd_backward'.tr, widget.onBackward),
          if (widget.onDelete != null) cmd(Icons.delete_outline_rounded, 'certd_delete'.tr, widget.onDelete, danger: true),
        ]),
      ],
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tools, layers, toolbar
// ─────────────────────────────────────────────────────────────────────────────

enum CertTool { text, field, logo, signature, line, photo, qr }

IconData certToolIcon(CertTool t) => switch (t) {
      CertTool.text => Icons.text_fields_rounded,
      CertTool.field => Icons.data_object_rounded,
      CertTool.logo => Icons.image_outlined,
      CertTool.signature => Icons.draw_rounded,
      CertTool.line => Icons.horizontal_rule_rounded,
      CertTool.photo => Icons.account_circle_outlined,
      CertTool.qr => Icons.qr_code_2_rounded,
    };

String certToolLabel(CertTool t) => switch (t) {
      CertTool.text => 'certd_add_text'.tr,
      CertTool.field => 'certd_add_field'.tr,
      CertTool.logo => 'certd_add_logo'.tr,
      CertTool.signature => 'certd_add_signature'.tr,
      CertTool.line => 'certd_add_line'.tr,
      CertTool.photo => 'certd_add_photo'.tr,
      CertTool.qr => 'certd_add_qr'.tr,
    };

/// "Add to the page": every element kind as an icon + label row ([grid] lays them out as tiles, for a sheet).
class CertToolsPanel extends StatelessWidget {
  const CertToolsPanel({super.key, required this.onAdd, this.enabled = true, this.grid = false});

  final ValueChanged<CertTool> onAdd;
  final bool enabled;
  final bool grid;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = ensureContrast(c.primary, [c.cardBg]);
    Widget tile(CertTool t) => Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: enabled ? () => onAdd(t) : null,
            borderRadius: AppRadius.chipAll,
            child: Container(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
              decoration: grid
                  ? BoxDecoration(borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider))
                  : null,
              child: Row(mainAxisSize: grid ? MainAxisSize.min : MainAxisSize.max, children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(AppRadius.chip - 2)),
                  child: Icon(certToolIcon(t), size: 18, color: enabled ? accent : c.textLight),
                ),
                const SizedBox(width: AppSpace.sm),
                Flexible(
                  child: Text(certToolLabel(t),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: appText(13.5, w: FontWeight.w500, c: enabled ? c.textDark : c.textLight)),
                ),
              ]),
            ),
          ),
        );
    if (grid) {
      return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [for (final t in CertTool.values) tile(t)]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final t in CertTool.values) tile(t)]);
  }
}

/// Every element of the layout, the TOP one first (like a layers panel): tap to select, eye to show / hide, drag
/// to reorder, bin to delete.
class CertLayersList extends StatelessWidget {
  const CertLayersList({
    super.key,
    required this.fields,
    required this.arabic,
    required this.onSelect,
    this.selectedId,
    this.enabled = true,
    this.onToggleVisible,
    this.onReorder,
    this.onDelete,
    this.shrinkWrap = false,
  });

  /// Bottom first (the layout's order).
  final List<CertField> fields;
  final bool arabic;
  final String? selectedId;
  final bool enabled;
  final ValueChanged<String> onSelect;
  final ValueChanged<String>? onToggleVisible;

  /// Layout (bottom-first) indices: the element at [from] ends at [to].
  final void Function(int from, int to)? onReorder;
  final ValueChanged<String>? onDelete;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (fields.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Text('cert_no_fields'.tr, textAlign: TextAlign.center, style: AppType.meta(context)),
      );
    }
    final top = fields.reversed.toList();
    final n = fields.length;
    return ReorderableListView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
      itemCount: top.length,
      onReorderItem: (a, b) {
        if (!enabled || onReorder == null) return;
        // top-first list → layout indices (bottom first); b is already the final position
        onReorder!(n - 1 - a, n - 1 - b);
      },
      itemBuilder: (context, i) {
        final f = top[i];
        final sel = f.id == selectedId;
        return Material(
          key: ValueKey(f.id),
          color: sel ? c.primaryTint : Colors.transparent,
          borderRadius: AppRadius.chipAll,
          child: InkWell(
            borderRadius: AppRadius.chipAll,
            onTap: () => onSelect(f.id),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Row(children: [
                if (enabled && onReorder != null)
                  ReorderableDragStartListener(
                    index: i,
                    child: Tooltip(
                      message: 'certd_drag_reorder'.tr,
                      child: SizedBox(
                        width: 36,
                        height: AppTouch.min,
                        child: Icon(Icons.drag_indicator_rounded, size: 18, color: c.textLight),
                      ),
                    ),
                  )
                else
                  const SizedBox(width: AppSpace.sm),
                Icon(certKindIcon(f.kind), size: 18, color: f.visible ? c.textMedium : c.textLight),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Builder(builder: (context) {
                    final title = certFieldTitle(f, arabic: arabic);
                    final rtl = Directionality.of(context) == TextDirection.rtl;
                    // the direction of the first strong letter: "{student_name}" stays readable in an Arabic list,
                    // Arabic wording in an English one
                    final strong = RegExp(r'[A-Za-z\u0600-\u06FF]').firstMatch(title)?.group(0) ?? '';
                    final ar = RegExp(r'[\u0600-\u06FF]').hasMatch(strong);
                    return Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: strong.isEmpty ? null : (ar ? TextDirection.rtl : TextDirection.ltr),
                      textAlign: rtl ? TextAlign.right : TextAlign.left,
                      style: appText(13,
                          w: sel ? FontWeight.w600 : FontWeight.w500, c: f.visible ? c.textDark : c.textLight),
                    );
                  }),
                ),
                if (enabled && onToggleVisible != null)
                  IconButton(
                    tooltip: (f.visible ? 'pl_hide' : 'pl_show').tr,
                    onPressed: () => onToggleVisible!(f.id),
                    icon: Icon(f.visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        size: 18, color: f.visible ? c.textLight : c.textMedium),
                  ),
                if (enabled && onDelete != null && sel)
                  IconButton(
                    tooltip: 'certd_delete'.tr,
                    onPressed: () => onDelete!(f.id),
                    icon: Icon(Icons.delete_outline_rounded, size: 18, color: ensureContrast(c.danger, [c.cardBg])),
                  ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// The studio toolbar with the designer's own trailing commands: duplicate and the order (z) menu.
class CertToolbarRow extends StatelessWidget {
  const CertToolbarRow({super.key, required this.controller, this.leading = const [], this.enabled = true});

  final StudioController<Object?> controller;
  final List<Widget> leading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => LayoutBuilder(builder: (context, box) {
        // the designer's own commands keep their label only where the whole bar fits (they also sit, labelled, in
        // the properties panel)
        final wide = box.maxWidth >= 1000;
        final has = enabled && controller.selection.isNotEmpty;
        PopupMenuItem<String> row(String v, IconData icon, String key) => PopupMenuItem<String>(
              value: v,
              child: Row(children: [
                Icon(icon, size: 20, color: c.textMedium),
                const SizedBox(width: AppSpace.sm),
                Flexible(child: Text(key.tr, style: appText(14, c: c.textDark))),
              ]),
            );
        return StudioToolbar(
          controller: controller,
          leading: leading,
          trailing: [
            StudioToolButton(
              icon: Icons.copy_rounded,
              label: 'certd_duplicate'.tr,
              showLabel: wide,
              onPressed: has ? controller.duplicate : null,
            ),
            PopupMenuButton<String>(
              enabled: has,
              tooltip: 'certd_order'.tr,
              onSelected: (v) => switch (v) {
                'front' => controller.bringToFront(),
                'forward' => controller.bringForward(),
                'backward' => controller.sendBackward(),
                _ => controller.sendToBack(),
              },
              itemBuilder: (_) => [
                row('front', Icons.vertical_align_top_rounded, 'certd_to_front'),
                row('forward', Icons.flip_to_front_rounded, 'certd_forward'),
                row('backward', Icons.flip_to_back_rounded, 'certd_backward'),
                row('back', Icons.vertical_align_bottom_rounded, 'certd_to_back'),
              ],
              child: StudioToolFace(
                icon: Icons.layers_outlined,
                label: 'certd_order'.tr,
                showLabel: wide,
                enabled: has,
                trailingIcon: Icons.expand_more_rounded,
              ),
            ),
          ],
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom placeholder
// ─────────────────────────────────────────────────────────────────────────────

/// "Add a field…": a custom {key} and an optional sample for the preview. Returns (key, sample) or null.
Future<(String, String)?> showCertCustomFieldDialog(BuildContext context, {String initialKey = ''}) =>
    showDialog<(String, String)>(context: context, builder: (_) => _CustomFieldDialog(initialKey: initialKey));

class _CustomFieldDialog extends StatefulWidget {
  const _CustomFieldDialog({required this.initialKey});
  final String initialKey;

  @override
  State<_CustomFieldDialog> createState() => _CustomFieldDialogState();
}

class _CustomFieldDialogState extends State<_CustomFieldDialog> {
  late final _key = TextEditingController(text: widget.initialKey);
  final _sample = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    _sample.dispose();
    super.dispose();
  }

  void _submit() {
    final err = certPlaceholderKeyError(_key.text);
    if (err != null) {
      setState(() => _error = err == 'empty' ? 'certd_key_empty'.tr : 'certd_key_invalid'.tr);
      return;
    }
    Navigator.pop(context, (normalizePlaceholderKey(_key.text), _sample.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      title: Text('certd_custom_field_title'.tr, style: AppType.section(context)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('certd_custom_field_body'.tr, style: AppType.meta(context)),
          const SizedBox(height: AppSpace.sm),
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _key,
              autofocus: true,
              maxLength: 40,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_{}]'))],
              style: appText(14, w: FontWeight.w600, c: c.textDark),
              decoration: InputDecoration(
                labelText: 'certd_custom_field_key'.tr,
                hintText: 'grade',
                prefixText: '{',
                suffixText: '}',
                errorText: _error,
                helperText: 'certd_custom_field_hint'.tr,
                helperMaxLines: 2,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          TextField(
            controller: _sample,
            maxLength: 300,
            style: appText(14, w: FontWeight.w500, c: c.textDark),
            decoration: InputDecoration(labelText: 'certd_custom_field_sample'.tr),
            onSubmitted: (_) => _submit(),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('cancel'.tr)),
        FilledButton(onPressed: _submit, child: Text('certd_insert'.tr)),
      ],
    );
  }
}
