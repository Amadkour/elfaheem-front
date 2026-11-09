// features/teacher/certificates/studio/cert_font_picker.dart
//
// The font control of a certificate field (D-380..D-382). The list is the renderer's own catalog, fetched once from
// `GET /exports/layout/fonts?include=all` (never a second copy here): Arabic / English tabs, grouped by style, each row
// in its own face with the field's real text or a sample of the font's language, with a search across both tabs.
// Nothing is downloaded when the list opens (D-410): the catalog is names only, and a row loads its font's regular file
// when it scrolls into view, a few at a time, cancelled if it scrolls away first. A font that cannot draw the field's
// script says so on its row, before it is chosen.
//
// A choice applies to the selected fields (one or several) or to every text field of the design, as one undo step.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart' show AppConfig;
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
  const CertFontInfo({required this.id, required this.family, required this.scripts, this.bold = false, this.italic = false, this.arabicFallback, this.style = '', this.labelAr = '', this.labelEn = '', this.bundled = true});
  final String id, family;

  /// The catalog's grouping: naskh, kufi, calligraphic, display, sans, serif, engraved, script, blackletter ('' = older server).
  final String style;

  /// The server's own names of a font the app build does not carry ('' = the app's name, or the family).
  final String labelAr, labelEn;

  /// Whether the app ships this font's files (older builds only list these).
  final bool bundled;
  final List<String> scripts;
  final bool bold, italic;

  /// The family the renderer draws Arabic letters with when this font has none; null for an Arabic font.
  final String? arabicFallback;

  bool get arabic => scripts.contains('arabic');
  bool get latin => scripts.contains('latin');

  /// What the person sees: the server's name for the language, else the app's translated one, else the family.
  String get label {
    final own = AppConfig.lang == 'ar' ? labelAr : labelEn;
    if (own.isNotEmpty) return own;
    return ExportFonts.has(id) ? ExportFonts.byId(id).label : family;
  }

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
      style: '${j['style'] ?? ''}',
      labelAr: '${j['label_ar'] ?? ''}',
      labelEn: '${j['label_en'] ?? ''}',
      bundled: j['bundled'] != false,
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

/// The style groups in the order the picker shows them; an unknown style comes last.
const certFontStyleOrder = ['naskh', 'serif', 'kufi', 'calligraphic', 'engraved', 'script', 'display', 'blackletter', 'sans'];

String certFontStyleLabel(String style) => switch (style) {
      'naskh' => t('نسخ', 'Naskh'),
      'serif' => t('كلاسيكي', 'Classic serif'),
      'kufi' => t('كوفي', 'Kufi'),
      'calligraphic' => t('خطوط يدوية', 'Calligraphic'),
      'engraved' => t('منقوش', 'Engraved'),
      'script' => t('توقيع وأسماء', 'Script'),
      'display' => t('عناوين', 'Display'),
      'blackletter' => t('قوطي', 'Blackletter'),
      'sans' => t('عصري', 'Modern'),
      _ => t('خطوط أخرى', 'Other fonts'),
    };

/// A row's preview text: the field's own text when the font can draw it, else a sample in the font's own language.
String certFontSample(CertFontInfo f, String fieldText) {
  final ar = certTextHasArabic(fieldText), latin = _hasLatin(fieldText);
  if (f.arabic ? ar : (latin && !ar)) return fieldText;
  if (f.arabic) return 'شهادة تقدير وتميّز';
  return f.style == 'script' ? 'Sarah Al-Mansouri' : 'Certificate of Achievement';
}

/// The catalog, fetched once per run. Only names: a font the build lacks is announced to [ExportFonts], and its files
/// come from the server when something draws it (D-410).
abstract final class CertFontCatalog {
  static Future<List<CertFontInfo>>? _load;

  @visibleForTesting
  static void reset() => _load = null;

  static Future<List<CertFontInfo>> of(CertEngineApi api) => _load ??= () async {
        try {
          final fonts = await api.fonts();
          ExportFonts.remoteFetch = (id, variant) async => base64Decode(await api.fontFile(id, variant: variant));
          for (final f in fonts) {
            ExportFonts.declareRemote(
              id: f.id,
              family: f.family,
              arabic: f.arabic,
              bold: f.bold,
              italic: f.italic,
              arabicFallback: f.arabicFallback,
              labelAr: f.labelAr.isEmpty ? null : f.labelAr,
              labelEn: f.labelEn.isEmpty ? null : f.labelEn,
            );
          }
          return fonts;
        } catch (_) {
          _load = null; // the next open tries again
          rethrow;
        }
      }();
}

/// One preview font to load; [cancelled] when its row scrolled away first.
class _FontFaceJob {
  _FontFaceJob(this.id, this.done);
  final String id;
  final VoidCallback done;
  bool cancelled = false;
}

/// The picker's rows ask for their font here: at most [_max] downloads at a time, in the order the rows appeared.
abstract final class _FontFaceQueue {
  static const _max = 3;
  static int _running = 0;
  static final _waiting = <_FontFaceJob>[];

  static _FontFaceJob request(String id, VoidCallback done) {
    final job = _FontFaceJob(id, done);
    _waiting.add(job);
    _pump();
    return job;
  }

  static void cancel(_FontFaceJob job) {
    job.cancelled = true;
    _waiting.remove(job);
  }

  static void _pump() {
    while (_running < _max && _waiting.isNotEmpty) {
      final job = _waiting.removeAt(0);
      _running++;
      unawaited(ExportFonts.ensureFace(job.id).whenComplete(() {
        _running--;
        if (!job.cancelled) job.done();
        _pump();
      }));
    }
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
  late bool _arabicTab = certTextHasArabic(widget.sample) || (widget.lang == 'ar' && !_sampleLatin);

  /// The chosen style chip; null = every style of the tab.
  String? _style;

  bool get _sampleLatin => RegExp('[A-Za-z]').hasMatch(widget.sample);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(CertFontInfo f) =>
      f.family.toLowerCase().contains(_q) || f.label.toLowerCase().contains(_q) || certFontStyleLabel(f.style).toLowerCase().contains(_q);

  Widget _heading(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.sm, bottom: AppSpace.xxs),
        child: Text(text, style: appText(13, w: FontWeight.w700, c: context.colors.textMedium)),
      );

  List<CertFontInfo> _sorted(Iterable<CertFontInfo> fonts) {
    int rank(String s) {
      final i = certFontStyleOrder.indexOf(s);
      return i < 0 ? certFontStyleOrder.length : i;
    }

    return fonts.toList()..sort((a, b) => rank(a.style).compareTo(rank(b.style)));
  }

  /// The list's rows, in order: a heading is a String, a font row a [CertFontInfo].
  List<Object> _rows() {
    final out = <Object>[];
    if (_q.isNotEmpty) {
      // a search looks in both languages, the field's language first
      final hits = widget.fonts.where(_matches).toList();
      final sections = [(true, t('عربي', 'Arabic')), (false, t('إنجليزي', 'English'))];
      if (!_arabicTab) sections.setAll(0, [sections[1], sections[0]]);
      for (final (arabic, name) in sections) {
        final list = _sorted(hits.where((f) => f.arabic == arabic));
        if (list.isEmpty) continue;
        out.add(name);
        out.addAll(list);
      }
      return out;
    }
    String? last;
    for (final f in _sorted(widget.fonts.where((f) => f.arabic == _arabicTab && (_style == null || f.style == _style)))) {
      if (f.style != last) {
        out.add(certFontStyleLabel(f.style));
        last = f.style;
      }
      out.add(f);
    }
    return out;
  }

  Widget _styleChips() {
    final styles = _sorted(widget.fonts.where((f) => f.arabic == _arabicTab)).map((f) => f.style).toSet().toList();
    if (styles.length < 2) return const SizedBox.shrink();
    Widget chip(String? value, String label) => Padding(
          padding: const EdgeInsetsDirectional.only(end: AppSpace.xxs),
          child: ChoiceChip(
            key: ValueKey('cert-font-style-${value ?? 'all'}'),
            label: Text(label),
            selected: _style == value,
            onSelected: (_) => setState(() => _style = value),
          ),
        );
    return SizedBox(
      height: AppTouch.min,
      child: ListView(
        key: const ValueKey('cert-font-styles'),
        scrollDirection: Axis.horizontal,
        children: [chip(null, t('الكل', 'All')), for (final s in styles) chip(s, certFontStyleLabel(s))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = _rows();
    final searching = _q.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        key: const ValueKey('cert-font-search'),
        controller: _search,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search_rounded, size: 20), hintText: t('ابحث عن خط', 'Search fonts')),
        onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
      ),
      if (!searching) ...[
        const SizedBox(height: AppSpace.xs),
        StudioSegmented<bool>(
          key: const ValueKey('cert-font-language'),
          segments: [StudioSegment(value: true, label: t('عربي', 'Arabic')), StudioSegment(value: false, label: t('إنجليزي', 'English'))],
          value: _arabicTab,
          onChanged: (v) => setState(() {
            _arabicTab = v;
            _style = null;
          }),
        ),
      ],
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
        child: rows.isEmpty
            ? AppEmpty(icon: Icons.font_download_off_outlined, title: t('لا يوجد خط بهذا الاسم', 'No font with that name'))
            : ListView.builder(
                key: const ValueKey('cert-font-list'),
                // only the rows near the screen exist, so only their fonts load
                itemCount: rows.length + (searching ? 1 : 2),
                itemBuilder: (ctx, i) {
                  if (!searching && i == 0) return _styleChips();
                  final at = i - (searching ? 0 : 1);
                  if (at >= rows.length) return const SizedBox(height: AppSpace.md);
                  final row = rows[at];
                  if (row is String) return _heading(ctx, row);
                  final f = row as CertFontInfo;
                  return _FontRow(
                    key: ValueKey('cert-font-${f.id}'),
                    font: f,
                    sample: certFontSample(f, widget.sample),
                    selected: f.id == widget.value,
                    note: certFontScriptNote(f, widget.sample),
                    onTap: () => widget.onPick(CertFontChoice(f.id, all: _all)),
                  );
                },
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

class _FontRow extends StatefulWidget {
  const _FontRow({super.key, required this.font, required this.sample, required this.selected, required this.note, required this.onTap});
  final CertFontInfo font;
  final String sample;
  final bool selected;
  final String? note;
  final VoidCallback onTap;

  @override
  State<_FontRow> createState() => _FontRowState();
}

class _FontRowState extends State<_FontRow> {
  _FontFaceJob? _job;

  bool get _ready => ExportFonts.faceReady(widget.font.id);

  @override
  void initState() {
    super.initState();
    if (!_ready) {
      _job = _FontFaceQueue.request(widget.font.id, () {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    final job = _job;
    if (job != null) _FontFaceQueue.cancel(job);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final font = widget.font;
    final rtl = certTextHasArabic(widget.sample);
    final preview = TextStyle(
      fontFamily: ExportFonts.byId(font.id).previewFamily,
      fontFamilyFallback: exportFlutterFallback(font.id),
      fontSize: rtl ? 22 : 24,
      color: c.textDark,
      height: rtl ? 1.7 : 1.35,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xxs),
      child: Material(
        color: widget.selected ? Color.alphaBlend(c.primary.withValues(alpha: .12), c.cardBg) : c.cardBg,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: BorderSide(color: widget.selected ? c.primary : c.divider)),
        child: InkWell(
          borderRadius: AppRadius.cardAll,
          onTap: widget.onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(font.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w600, c: c.textMedium)),
                    if (_ready)
                      Text(widget.sample, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, style: preview)
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                        child: FractionallySizedBox(
                          widthFactor: .6,
                          alignment: rtl ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                          child: Container(height: 14, decoration: BoxDecoration(color: c.textMedium.withValues(alpha: .14), borderRadius: AppRadius.cardAll)),
                        ),
                      ),
                    if (widget.note != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpace.xxs),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.info_outline_rounded, size: 15, color: c.danger),
                          const SizedBox(width: AppSpace.xxs),
                          Expanded(child: Text(widget.note!, key: ValueKey('cert-font-note-${font.id}'), style: appText(12, c: c.danger))),
                        ]),
                      ),
                  ]),
                ),
                if (widget.selected) Icon(Icons.check_circle_rounded, size: 20, color: c.primary),
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
    final height = (MediaQuery.sizeOf(ctx).height * .82).clamp(360.0, 760.0);
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
