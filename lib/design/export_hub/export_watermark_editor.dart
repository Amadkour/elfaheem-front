// lib/design/export_hub/export_watermark_editor.dart
//
// The watermark controls (6.4), one widget for the export designer (PDF / Word / Excel of a design) and the Excel
// studio: text or image, the text / the uploaded image, position, size, rotation, opacity, colour. Built on the
// studio's property primitives (studio_props.dart). The caller applies each change ([onEdit]: undo history,
// setState) and uploads the image ([onUpload] returns its URL, or null).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../app_kit.dart';
import '../app_tokens.dart';
import '../export/export_watermark.dart';
import '../export/table_export_model.dart' show tx;
import '../studio/studio_props.dart';

Map<String, String> exportWatermarkPositionLabels() => {
      'center': tx('exs_wm_center', 'Centre', 'في المنتصف'),
      'top': tx('exs_wm_top', 'Top', 'أعلى'),
      'bottom': tx('exs_wm_bottom', 'Bottom', 'أسفل'),
      'top_start': tx('exs_wm_top_start', 'Top, start', 'أعلى البداية'),
      'top_end': tx('exs_wm_top_end', 'Top, end', 'أعلى النهاية'),
      'bottom_start': tx('exs_wm_bottom_start', 'Bottom, start', 'أسفل البداية'),
      'bottom_end': tx('exs_wm_bottom_end', 'Bottom, end', 'أسفل النهاية'),
    };

class ExportWatermarkEditor extends StatefulWidget {
  const ExportWatermarkEditor({super.key, required this.mark, required this.onEdit, this.onUpload, this.note});
  final ExportWatermark mark;

  /// Applies [change] to [mark] (the caller records undo / rebuilds).
  final void Function(VoidCallback change) onEdit;

  /// Picks and uploads an image; its URL, or null. Null = only a pasted link.
  final Future<String?> Function()? onUpload;

  /// A line under the controls (Excel: "printed as a header picture").
  final String? note;

  @override
  State<ExportWatermarkEditor> createState() => _ExportWatermarkEditorState();
}

class _ExportWatermarkEditorState extends State<ExportWatermarkEditor> {
  late final _text = TextEditingController(text: widget.mark.text);
  late final _url = TextEditingController(text: widget.mark.imageUrl);

  @override
  void didUpdateWidget(covariant ExportWatermarkEditor old) {
    super.didUpdateWidget(old);
    if (_text.text != widget.mark.text) _text.text = widget.mark.text;
    if (_url.text != widget.mark.imageUrl) _url.text = widget.mark.imageUrl;
  }

  @override
  void dispose() {
    _text.dispose();
    _url.dispose();
    super.dispose();
  }

  Color _color(String hex) => Color(0xFF000000 | (int.tryParse(hex, radix: 16) ?? 0x94A3B8));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wm = widget.mark;
    final edit = widget.onEdit;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      StudioSegmented<String>(
        segments: [
          StudioSegment(value: 'text', label: tx('exs_wm_text', 'Text', 'نص'), icon: Icons.text_fields_rounded),
          StudioSegment(value: 'image', label: tx('exs_wm_image', 'Image', 'صورة'), icon: Icons.image_outlined),
        ],
        value: wm.kind,
        onChanged: (v) => edit(() => wm.kind = v),
      ),
      const SizedBox(height: AppSpace.xs),
      if (!wm.isImage)
        StudioPropField(
          label: tx('exs_wm_text_label', 'Watermark text', 'نص العلامة المائية'),
          child: TextField(
            controller: _text,
            maxLength: 60,
            decoration: InputDecoration(isDense: true, counterText: '', hintText: tx('exs_wm_hint', 'Confidential', 'سري')),
            onChanged: (v) => edit(() => wm.text = v),
          ),
        )
      else ...[
        StudioPropField(
          label: tx('exs_wm_image_link', 'Image link', 'رابط الصورة'),
          child: TextField(
            controller: _url,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(isDense: true, hintText: 'https://…'),
            onChanged: (v) => edit(() => wm.imageUrl = v.trim()),
          ),
        ),
        if (widget.onUpload != null) ...[
          const SizedBox(height: AppSpace.xxs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppPill(
              icon: Icons.upload_rounded,
              label: tx('exs_wm_upload', 'Upload an image', 'رفع صورة'),
              onTap: () async {
                final url = await widget.onUpload!();
                if (url != null && url.isNotEmpty) edit(() => wm.imageUrl = _url.text = url);
              },
            ),
          ),
        ],
      ],
      if (wm.visible) ...[
        const SizedBox(height: AppSpace.xs),
        StudioPropField(
          label: tx('exs_wm_position', 'Position', 'الموضع'),
          child: AppDropdown<String>(
            value: wm.position,
            decoration: const InputDecoration(isDense: true),
            items: [for (final e in exportWatermarkPositionLabels().entries) DropdownMenuItem(value: e.key, child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => edit(() => wm.position = v ?? 'center'),
          ),
        ),
        if (wm.isImage)
          StudioStepper(
            label: tx('exs_wm_width', 'Width', 'العرض'),
            value: (wm.imageWidth * 100).roundToDouble(),
            min: 5,
            max: 100,
            step: 5,
            suffix: '%',
            onChanged: (v) => edit(() => wm.imageWidth = (v / 100).clamp(.05, 1).toDouble()),
          )
        else
          StudioStepper(label: tx('exs_wm_size', 'Size', 'الحجم'), value: wm.size, min: 12, max: 160, step: 4, suffix: 'pt', onChanged: (v) => edit(() => wm.size = v)),
        StudioStepper(label: tx('exs_wm_angle', 'Rotation', 'الدوران'), value: wm.angle, min: -90, max: 90, step: 5, suffix: '°', onChanged: (v) => edit(() => wm.angle = v)),
        StudioOpacitySlider(value: wm.opacity, onChanged: (v) => edit(() => wm.opacity = v)),
        if (!wm.isImage)
          StudioColorField(
            label: tx('exs_wm_colour', 'Colour', 'اللون'),
            value: _color(wm.color),
            onChanged: (col) => edit(() => wm.color = col == null ? '94A3B8' : studioHex(col)),
          ),
      ],
      if (widget.note != null) ...[
        const SizedBox(height: AppSpace.xxs),
        Text(widget.note!, style: appText(12, c: c.textMedium)),
      ],
    ]);
  }
}
