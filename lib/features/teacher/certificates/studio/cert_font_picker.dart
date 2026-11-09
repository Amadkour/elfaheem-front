// features/teacher/certificates/studio/cert_font_picker.dart
//
// The font control of a certificate field (D-380..D-382). The list is the renderer's own catalog, fetched once from
// `GET /exports/layout/fonts` (never a second copy here): each name drawn in its own face with the field's real text,
// grouped Arabic / Latin, with a search. A font this app build does not bundle is downloaded from the server first
// (`/fonts/{id}/file`), so the picker and the canvas still show the true face. A font that cannot draw the field's
// script says so on its row, before it is chosen.
//
// A choice applies to the selected fields (one or several) or to every text field of the design, as one undo step.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../../../../design/app_kit.dart';
import '../../../../design/app_notice.dart';
import '../../../../design/app_tokens.dart';
import '../../../../design/export/export_fonts.dart';
import '../../../../design/export_hub/export_designer.dart' show exportFlutterFont, exportFlutterFallback;
import '../../../../design/export_layout/layout_model.dart';
import '../../../../design/studio/studio.dart';
import '../../../admin/admin_common.dart' show t;
import 'cert_engine_api.dart';

/// One font of the renderer's catalog.
class CertFontInfo {
  const CertFontInfo({required this.id, required this.family, required this.scripts, this.bold = false, this.italic = false, this.arabicFallback});
  final String id, family;
  final List<String> scripts;
  final bool bold, italic;

  /// The family the renderer draws Arabic letters with when this font has none; null for an Arabic font.
  final String? arabicFallback;

  bool get arabic => scripts.contains('arabic');
  bool get latin => scripts.contains('latin');

  /// What the app calls it (its translated name when it bundles the font, else the family).
  String get label => ExportFonts.has(id) ? ExportFonts.byId(id).label : family;

  static CertFontInfo? tryParse(Object? j) {
    if (j is! Map || '${j['id'] ?? ''}'.isEmpty) return null;
    final s = j['scripts'];
    return CertFontInfo(
      id: '${j['id']}',
      family: '${j['family'] ?? j['id']}',
      scripts: s is List ? [for (final x in s) '$x'] : (j['arabic'] == false ? const ['latin'] : const ['arabic', 'latin']),
      bold: j['bold'] == true,
      italic: j['italic'] == true,
      arabicFallback: j['arabic_fallback'] is String ? j['arabic_fallback'] as String : null,
    );
  }
}

/// Fields that carry text (a shape, an image or a QR code have no font of their own).
bool certFontTextual(LayoutElement e) => e.kind == 'text' || e.kind == 'field' || e.kind == 'badge' || e.kind == 'page_number' || e.kind == 'signature';

bool certTextHasArabic(String s) => s.runes.any((r) => (r >= 0x0600 && r <= 0x06FF) || (r >= 0xFB50 && r <= 0xFDFF) || (r >= 0xFE70 && r <= 0xFEFF));
bool _hasLatin(String s) => s.runes.any((r) => (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A));

/// Why [font] cannot draw [text] as designed (shown before it is chosen), or null when it can.
String? certFontScriptNote(CertFontInfo font, String text) {
  if (!font.arabic && certTextHasArabic(text)) {
    return t('لا يحوي حروفًا عربية: ستظهر حروف هذا الحقل بخط أميري', 'Has no Arabic letters: this field’s Arabic is drawn in Amiri');
  }
  if (!font.latin && _hasLatin(text)) {
    return t('لا يحوي حروفًا لاتينية: ستظهر حروف هذا الحقل اللاتينية بخط أميري', 'Has no Latin letters: this field’s Latin text is drawn in Amiri');
  }
  return null;
}

/// The catalog, fetched once per run; a font the build lacks is downloaded and registered before it is listed.
abstract final class CertFontCatalog {
  static Future<List<CertFontInfo>>? _load;

  @visibleForTesting
  static void reset() => _load = null;

  static Future<List<CertFontInfo>> of(CertEngineApi api) => _load ??= () async {
        try {
          final fonts = await api.fonts();
          for (final f in fonts) {
            if (!ExportFonts.has(f.id)) await _fetchMissing(api, f);
          }
          return fonts;
        } catch (_) {
          _load = null; // the next open tries again
          rethrow;
        }
      }();

  static Future<void> _fetchMissing(CertEngineApi api, CertFontInfo f) async {
    final regular = base64Decode(await api.fontFile(f.id));
    final bold = f.bold ? base64Decode(await api.fontFile(f.id, variant: 'bold')) : null;
    await ExportFonts.addRemote(id: f.id, family: f.family, arabic: f.arabic, regular: regular, bold: bold, arabicFallback: f.arabicFallback);
  }
}

/// What a text would look like in font [id]: the renderer's family, shown by the app.
TextStyle certFontStyle(String id, double size, Color color) => TextStyle(
      fontFamily: exportFlutterFont(id),
      fontFamilyFallback: exportFlutterFallback(id),
      fontSize: size,
      color: color,
      height: 1.35,
    );

/// The result of the sheet: the font, and whether it goes to every text field of the design.
class CertFontChoice {
  const CertFontChoice(this.id, {this.all = false});
  final String id;
  final bool all;
}

// ── the sheet ─────────────────────────────────────────────────────────────────────────────────────────────────────

/// The picker: plain values in, a [CertFontChoice] out. [sample] is the field's real text.
class CertFontPickerBody extends StatefulWidget {
  const CertFontPickerBody({
    super.key,
    required this.fonts,
    required this.value,
    required this.sample,
    required this.lang,
    required this.selected,
    required this.total,
    required this.onPick,
  });

  final List<CertFontInfo> fonts;
  final String? value;
  final String sample, lang;

  /// How many fields the pick applies to / how many text fields the design has.
  final int selected, total;
  final ValueChanged<CertFontChoice> onPick;

  @override
  State<CertFontPickerBody> createState() => _CertFontPickerBodyState();
}

class _CertFontPickerBodyState extends State<CertFontPickerBody> {
  final _search = TextEditingController();
  bool _all = false;
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(CertFontInfo f) => _q.isEmpty || f.family.toLowerCase().contains(_q) || f.label.toLowerCase().contains(_q);

  Widget _heading(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.sm, bottom: AppSpace.xxs),
        child: Text(text, style: appText(13, w: FontWeight.w700, c: context.colors.textMedium)),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = widget.fonts.where(_matches).toList();
    final arabic = [for (final f in shown) if (f.arabic) f];
    final latin = [for (final f in shown) if (!f.arabic) f];
    final sections = widget.lang == 'ar' ? [(t('عربي', 'Arabic'), arabic), (t('لاتيني', 'Latin'), latin)] : [(t('لاتيني', 'Latin'), latin), (t('عربي', 'Arabic'), arabic)];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        key: const ValueKey('cert-font-search'),
        controller: _search,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search_rounded, size: 20), hintText: t('ابحث عن خط', 'Search fonts')),
        onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
      ),
      if (widget.total > 1) ...[
        const SizedBox(height: AppSpace.xs),
        StudioSegmented<bool>(
          segments: [
            StudioSegment(value: false, label: widget.selected > 1 ? t('المحدد (${widget.selected})', 'Selected (${widget.selected})') : t('هذا الحقل', 'This field')),
            StudioSegment(value: true, label: t('كل الحقول (${widget.total})', 'All fields (${widget.total})')),
          ],
          value: _all,
          onChanged: (v) => setState(() => _all = v),
        ),
      ],
      const SizedBox(height: AppSpace.xxs),
      Expanded(
        child: shown.isEmpty
            ? AppEmpty(icon: Icons.font_download_off_outlined, title: t('لا يوجد خط بهذا الاسم', 'No font with that name'))
            : ListView(
                key: const ValueKey('cert-font-list'),
                children: [
                  for (final (name, list) in sections)
                    if (list.isNotEmpty) ...[
                      _heading(context, name),
                      for (final f in list)
                        _FontRow(
                          key: ValueKey('cert-font-${f.id}'),
                          font: f,
                          sample: widget.sample,
                          selected: f.id == widget.value,
                          note: certFontScriptNote(f, widget.sample),
                          onTap: () => widget.onPick(CertFontChoice(f.id, all: _all)),
                        ),
                    ],
                  const SizedBox(height: AppSpace.md),
                ],
              ),
      ),
      if (_all)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs),
          child: Text(t('يُطبَّق على كل نصوص هذا التصميم.', 'Applied to every text of this design.'), style: appText(12, c: c.textMedium)),
        ),
    ]);
  }
}

class _FontRow extends StatelessWidget {
  const _FontRow({super.key, required this.font, required this.sample, required this.selected, required this.note, required this.onTap});
  final CertFontInfo font;
  final String sample;
  final bool selected;
  final String? note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xxs),
      child: Material(
        color: selected ? Color.alphaBlend(c.primary.withValues(alpha: .12), c.cardBg) : c.cardBg,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: BorderSide(color: selected ? c.primary : c.divider)),
        child: InkWell(
          borderRadius: AppRadius.cardAll,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(font.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: certFontStyle(font.id, 17, c.textDark)),
                    Text(
                      sample,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: certTextHasArabic(sample) ? TextDirection.rtl : TextDirection.ltr,
                      style: certFontStyle(font.id, 15, c.textMedium),
                    ),
                    if (note != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpace.xxs),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.info_outline_rounded, size: 15, color: c.danger),
                          const SizedBox(width: AppSpace.xxs),
                          Expanded(child: Text(note!, key: ValueKey('cert-font-note-${font.id}'), style: appText(12, c: c.danger))),
                        ]),
                      ),
                  ]),
                ),
                if (selected) Icon(Icons.check_circle_rounded, size: 20, color: c.primary),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the sheet; null when it is closed without a choice.
Future<CertFontChoice?> showCertFontPicker(
  BuildContext context, {
  required List<CertFontInfo> fonts,
  required String? value,
  required String sample,
  required String lang,
  required int selected,
  required int total,
}) {
  return showAppSheet<CertFontChoice>(context, (ctx) {
    final height = (MediaQuery.sizeOf(ctx).height * .78).clamp(360.0, 720.0);
    return SizedBox(
      height: height,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader(t('خط النص', 'Text font')),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md + AppSpace.xxs),
            child: CertFontPickerBody(
              fonts: fonts,
              value: value,
              sample: sample,
              lang: lang,
              selected: selected,
              total: total,
              onPick: (p) => Navigator.pop(ctx, p),
            ),
          ),
        ),
      ]),
    );
  });
}

// ── the control in the properties panel ───────────────────────────────────────────────────────────────────────────

/// The panel's font row for [targets] (one field or a multi-selection): the current font in its own face, opens the
/// sheet; bold / italic of the selection. Every change is one undo step and lands in the document at once, so the
/// draft, the save, the preview and the issued file all read the same value.
class CertFontControl extends StatefulWidget {
  const CertFontControl({super.key, required this.ctl, required this.targets, required this.sampleOf, required this.lang, required this.api, this.loader});

  final StudioController<LayoutElement> ctl;
  final List<LayoutElement> targets;
  final String Function(LayoutElement) sampleOf;
  final String lang;
  final CertEngineApi api;

  /// Tests pass the catalog straight in.
  final Future<List<CertFontInfo>> Function()? loader;

  @override
  State<CertFontControl> createState() => _CertFontControlState();
}

class _CertFontControlState extends State<CertFontControl> {
  List<CertFontInfo>? _fonts;
  bool _opening = false;

  Future<List<CertFontInfo>> _load() => widget.loader?.call() ?? CertFontCatalog.of(widget.api);

  @override
  void initState() {
    super.initState();
    unawaited(_load().then((f) {
      if (mounted) setState(() => _fonts = f);
    }).catchError((Object _) {}));
  }

  List<LayoutElement> get _all => [for (final it in widget.ctl.items) if (certFontTextual(it.payload)) it.payload];

  String get _sample {
    final s = widget.sampleOf(widget.targets.first).trim();
    return s.isNotEmpty ? s : (widget.lang == 'ar' ? 'شهادة تقدير' : 'Certificate of Award');
  }

  /// The one font of the targets, or null when they differ / use the page font.
  String? get _value {
    final set = {for (final e in widget.targets) e.style.font};
    return set.length == 1 ? set.first : null;
  }

  CertFontInfo? _info(String? id) {
    for (final f in _fonts ?? const <CertFontInfo>[]) {
      if (f.id == id) return f;
    }
    return null;
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    List<CertFontInfo> fonts;
    try {
      fonts = _fonts ?? await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _opening = false);
        showAppNotice(certErrorText(e), error: true);
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _fonts = fonts;
      _opening = false;
    });
    final choice = await showCertFontPicker(context, fonts: fonts, value: _value, sample: _sample, lang: widget.lang, selected: widget.targets.length, total: _all.length);
    if (choice == null || !mounted) return;
    final targets = choice.all ? _all : widget.targets;
    widget.ctl.record('font', () {
      for (final e in targets) {
        e.style.font = choice.id;
      }
    });
    setState(() {});
  }

  void _toggle(String label, void Function(LayoutElement, bool) apply, bool on) {
    final targets = widget.targets;
    widget.ctl.record(label, () {
      for (final e in targets) {
        apply(e, on);
      }
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final id = _value;
    final info = _info(id);
    final mixed = id == null && widget.targets.length > 1 && {for (final e in widget.targets) e.style.font}.length > 1;
    final label = mixed ? t('خطوط مختلفة', 'Mixed fonts') : (info?.label ?? (id == null ? t('خط الصفحة', 'Page font') : (ExportFonts.has(id) ? ExportFonts.byId(id).label : id)));
    final allBold = widget.targets.every((e) => e.style.bold), allItalic = widget.targets.every((e) => e.style.italic);
    final note = info == null ? null : certFontScriptNote(info, _sample);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StudioPropField(
        label: widget.targets.length > 1 ? t('الخط (${widget.targets.length} حقول)', 'Font (${widget.targets.length} fields)') : t('الخط', 'Font'),
        child: Row(children: [
          Expanded(
            child: OutlinedButton(
              key: const ValueKey('cert-font-open'),
              onPressed: _opening ? null : () => unawaited(_open()),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min), alignment: AlignmentDirectional.centerStart),
              child: Row(children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: id == null ? appText(14, w: FontWeight.w600, c: c.textDark) : certFontStyle(id, 15, c.textDark),
                  ),
                ),
                if (_opening)
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Icon(Icons.unfold_more_rounded, size: 18, color: c.textMedium),
              ]),
            ),
          ),
          if (widget.targets.length > 1)
            IconButton(
              key: const ValueKey('cert-font-bold'),
              tooltip: t('عريض', 'Bold'),
              isSelected: allBold,
              icon: Icon(Icons.format_bold_rounded, color: allBold ? c.primary : c.textMedium),
              onPressed: () => _toggle('bold', (e, on) => e.style.weight = on ? 400 : 700, allBold),
            ),
          IconButton(
            key: const ValueKey('cert-font-italic'),
            tooltip: t('مائل', 'Italic'),
            isSelected: allItalic,
            icon: Icon(Icons.format_italic_rounded, color: allItalic ? c.primary : c.textMedium),
            onPressed: () => _toggle('italic', (e, on) => e.style.italic = !on, allItalic),
          ),
        ]),
      ),
      if (note != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs),
          child: Text(note, key: const ValueKey('cert-font-field-note'), style: appText(12, c: c.danger)),
        ),
      if (widget.targets.any((e) => e.style.font != null))
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey('cert-font-page'),
            onPressed: () {
              widget.ctl.record('font', () {
                for (final e in widget.targets) {
                  e.style.font = null;
                }
              });
              setState(() {});
            },
            icon: const Icon(Icons.format_clear_rounded, size: AppIconSize.sm + 2),
            label: Text(t('خط الصفحة', "The page's font")),
          ),
        ),
    ]);
  }
}
