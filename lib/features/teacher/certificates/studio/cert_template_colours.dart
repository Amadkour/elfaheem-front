// features/teacher/certificates/studio/cert_template_colours.dart
//
// Background colours of a certificate template (D-401): the curated palettes of a template plus a custom colour, in the
// gallery's large preview and in the studio's page inspector. The server paints the chosen colours into the page and
// fits the text inks to it; this file only picks colours. Plain values in, plain values out.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../../../../design/app_kit.dart';
import '../../../../design/export_layout/layout_element_view.dart' show layoutColor, layoutHex;
import '../../../../design/studio/studio.dart';
import '../../../admin/admin_common.dart' show t;
import 'cert_engine_api.dart';

/// What the person chose: all null = the template's own colours.
class CertTemplateColors {
  const CertTemplateColors({this.bg, this.bg2, this.accent});
  final String? bg, bg2, accent;

  bool get isOriginal => bg == null && bg2 == null && accent == null;
}

/// The colours a [p] sends: the template's own palette sends nothing, so it stays exactly as drawn.
CertTemplateColors certPaletteColors(CertPalette p) => p.isOriginal ? const CertTemplateColors() : CertTemplateColors(bg: p.bg, bg2: p.bg2, accent: p.accent);

/// The curated swatches and a custom background colour.
class CertPalettePicker extends StatelessWidget {
  const CertPalettePicker({super.key, required this.palettes, required this.selectedId, required this.customBg, required this.lang, required this.onPalette, required this.onCustomBg});
  final List<CertPalette> palettes;
  final String? selectedId;

  /// "#RRGGBB" of a custom background (null = a palette is in use).
  final String? customBg;
  final String lang;
  final ValueChanged<CertPalette> onPalette;
  final ValueChanged<String> onCustomBg;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
        for (final p in palettes) _Swatch(palette: p, label: p.name(lang), selected: customBg == null && selectedId == p.id, onTap: () => onPalette(p)),
      ]),
      const SizedBox(height: AppSpace.xs),
      StudioColorField(
        key: const ValueKey('cert-custom-bg'),
        label: t('لون خلفية مخصص', 'Custom background colour'),
        value: layoutColor(customBg),
        swatches: const [],
        onChanged: (col) {
          if (col != null) onCustomBg(layoutHex(col));
        },
      ),
      const SizedBox(height: AppSpace.xxs),
      Text(t('لون الكتابة يتكيّف تلقائيًا ليبقى مقروءًا على أي لون.', 'The text colour adapts automatically to stay readable on any colour.'), style: appText(12, c: c.textMedium)),
    ]);
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.palette, required this.label, required this.selected, required this.onTap});
  final CertPalette palette;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = layoutColor(palette.bg, c.cardBg)!;
    final second = layoutColor(palette.bg2) ?? layoutColor(palette.accent) ?? bg;
    final ring = selected ? c.primary : c.divider;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          key: ValueKey('cert-palette-${palette.id}'),
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: AppTouch.min,
            height: AppTouch.min,
            child: Center(
              child: AnimatedContainer(
                duration: AppMotion.of(context).fast,
                width: 34,
                height: 34,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: selected ? AppBorder.strong : AppBorder.hairline)),
                child: ClipOval(
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [bg, bg, second, second], stops: const [0, .5, .5, 1])),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The studio's "Template colours": what the page was made from, applied on the real page by the server. [apply] asks
/// the server for the page in the new colours.
class CertTemplateColoursPanel extends StatefulWidget {
  const CertTemplateColoursPanel({super.key, required this.templateKey, required this.load, required this.lang, required this.currentBg, required this.currentBg2, required this.currentAccent, required this.apply});
  final String templateKey, lang;
  final String? currentBg, currentBg2, currentAccent;
  final Future<List<CertServerTemplate>> Function() load;
  final Future<void> Function(CertTemplateColors colors) apply;

  @override
  State<CertTemplateColoursPanel> createState() => _CertTemplateColoursPanelState();
}

class _CertTemplateColoursPanelState extends State<CertTemplateColoursPanel> {
  late final Future<List<CertServerTemplate>> _templates = widget.load();
  Timer? _debounce;
  bool _busy = false;

  /// A custom colour picked here, not yet back from the server.
  String? _pending;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  String? _selected(List<CertPalette> palettes) {
    final bg = widget.currentBg?.toUpperCase();
    if (bg == null && widget.currentAccent == null) return 'original';
    for (final p in palettes) {
      if (p.bg.toUpperCase() == bg && (p.bg2 ?? '').toUpperCase() == (widget.currentBg2 ?? '').toUpperCase()) return p.id;
    }
    return null;
  }

  Future<void> _go(CertTemplateColors colors) async {
    setState(() => _busy = true);
    await widget.apply(colors);
    if (mounted) setState(() => _busy = false);
  }

  void _custom(String hex, List<CertPalette> palettes) {
    setState(() => _pending = hex);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      // the second colour and the accent of the look in use stay
      unawaited(_go(CertTemplateColors(bg: hex, bg2: widget.currentBg2, accent: widget.currentAccent)));
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CertServerTemplate>>(
      future: _templates,
      builder: (context, snap) {
        final tp = (snap.data ?? const <CertServerTemplate>[]).where((x) => x.key == widget.templateKey).firstOrNull;
        if (tp == null || tp.palettes.isEmpty) return const SizedBox.shrink();
        final selected = _selected(tp.palettes);
        final custom = _pending ?? (selected == null ? widget.currentBg : null);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          CertPalettePicker(
            palettes: tp.palettes,
            selectedId: selected,
            customBg: custom,
            lang: widget.lang,
            onPalette: (p) {
              setState(() => _pending = null);
              unawaited(_go(certPaletteColors(p)));
            },
            onCustomBg: (hex) => _custom(hex, tp.palettes),
          ),
          if (_busy) ...[
            const SizedBox(height: AppSpace.xxs),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ]);
      },
    );
  }
}
