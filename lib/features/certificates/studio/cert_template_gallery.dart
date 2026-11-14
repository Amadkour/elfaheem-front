// features/certificates/studio/cert_template_gallery.dart
//
// The certificate template gallery (D-384): a full page of real renders from the server, a category filter, an
// Arabic / English preview toggle and one tap to use a design. The body ([CertTemplateGalleryView]) takes plain values
// and a [CertTemplatePreviewLoader], so it is tested without a server. The cards' images are fetched lazily, four at a
// time, and kept for the session.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/certificates/studio/cert_engine_api.dart';
import 'package:flutter_education_app/features/certificates/studio/cert_engine_panels.dart';
import 'package:flutter_education_app/features/certificates/studio/cert_template_colours.dart';

/// What the gallery returned: a starter (a document) or a server template, with the colour the person chose.
class CertGalleryPick {
  const CertGalleryPick.starter(CertStarter this.starter) : template = null, colorHex = null, bgHex = null, bg2Hex = null;
  const CertGalleryPick.template(CertServerTemplate this.template, {this.colorHex, this.bgHex, this.bg2Hex}) : starter = null;
  final CertStarter? starter;
  final CertServerTemplate? template;

  /// "#RRGGBB" when the person chose one (sent as `theme_color`); null keeps the template's own colours.
  final String? colorHex;

  /// The background colours chosen (D-401), "#RRGGBB"; null keeps the template's own.
  final String? bgHex, bg2Hex;
}

/// One image of a gallery card or the large preview: `(key, lang, width, colorHex, bgHex:, bg2Hex:)`, null when it could not be drawn.
typedef CertTemplatePreviewLoader = Future<Uint8List?> Function(String key, String lang, int width, String? colorHex, {String? bgHex, String? bg2Hex});

/// The categories the filter offers, in order; a template's `category` is one of these keys.
const kCertTemplateCategories = <(String, String, String)>[
  ('all', 'الكل', 'All'),
  ('formal', 'رسمي', 'Formal'),
  ('academic', 'أكاديمي', 'Academic'),
  ('islamic', 'إسلامي', 'Islamic'),
  ('modern', 'عصري', 'Modern'),
  ('corporate', 'مؤسسي', 'Corporate'),
  ('kids', 'أطفال', 'Kids'),
];

/// Opens the gallery as a full page. Null when closed without a pick.
Future<CertGalleryPick?> showCertGallery(BuildContext context, {required List<CertStarter> starters, required List<CertServerTemplate> templates, required String lang, CertEngineApi? api}) {
  final previews = api ?? CertEngineApi();
  final loader = CertTemplatePreviewCache(previews.templatePreview).load;
  return Navigator.of(context).push<CertGalleryPick>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (ctx) => BasePage(
      useWebCard: true,
      width: AppWidth.wide,
      child: CertTemplateGalleryView(
        templates: templates,
        starters: [for (final s in starters) if (s.mode == 'page' || s.mode.isEmpty) s],
        initialLang: lang,
        loader: loader,
        colorSeed: certThemeHex(ctx),
        onPick: (p) => Navigator.pop(ctx, p),
        onClose: () => Navigator.pop(ctx),
      ),
    ),
  ));
}

/// The card images of one session: each one asked for once, at most four at a time.
class CertTemplatePreviewCache {
  CertTemplatePreviewCache(this._fetch, {this.maxParallel = 4, this.maxEntries = 96});
  final Future<Uint8List> Function(String key, {required String lang, int width, String? colorHex, String? bgHex, String? bg2Hex}) _fetch;
  final int maxParallel, maxEntries;
  final _entries = <String, Future<Uint8List?>>{};
  final _waiting = Queue<void Function()>();
  int _running = 0;

  Future<Uint8List?> load(String key, String lang, int width, String? colorHex, {String? bgHex, String? bg2Hex}) {
    final id = '$key|$lang|$width|$colorHex|$bgHex|$bg2Hex';
    final hit = _entries.remove(id);
    if (hit != null) return _entries[id] = hit;
    final future = _enqueue(() => _fetch(key, lang: lang, width: width, colorHex: colorHex, bgHex: bgHex, bg2Hex: bg2Hex));
    _entries[id] = future;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    return future.then((bytes) {
      if (bytes == null) _entries.remove(id); // a failed image is tried again next time
      return bytes;
    });
  }

  Future<Uint8List?> _enqueue(Future<Uint8List> Function() job) {
    final done = Completer<Uint8List?>();
    void run() {
      _running++;
      job().then<Uint8List?>((b) => b, onError: (Object _) => null).then((b) {
        _running--;
        done.complete(b);
        if (_waiting.isNotEmpty && _running < maxParallel) _waiting.removeFirst()();
      });
    }

    if (_running < maxParallel) {
      run();
    } else {
      _waiting.add(run);
    }
    return done.future;
  }
}

class CertTemplateGalleryView extends StatefulWidget {
  const CertTemplateGalleryView({super.key, required this.templates, required this.starters, required this.initialLang, required this.loader, required this.colorSeed, required this.onPick, required this.onClose});

  final List<CertServerTemplate> templates;
  final List<CertStarter> starters;
  final String initialLang;
  final CertTemplatePreviewLoader loader;

  /// The app's theme colour, offered first in the large preview.
  final String colorSeed;
  final ValueChanged<CertGalleryPick> onPick;
  final VoidCallback onClose;

  @override
  State<CertTemplateGalleryView> createState() => _CertTemplateGalleryViewState();
}

class _CertTemplateGalleryViewState extends State<CertTemplateGalleryView> {
  String _category = 'all';
  late String _lang = widget.initialLang == 'en' ? 'en' : 'ar';

  List<CertServerTemplate> get _shown => _category == 'all' ? widget.templates : [for (final x in widget.templates) if (x.category == _category) x];

  Set<String> get _cats => {for (final x in widget.templates) x.category};

  Future<void> _openLarge(CertServerTemplate tp) async {
    final pick = await Navigator.of(context).push<CertGalleryPick>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => BasePage(
        useWebCard: true,
        width: AppWidth.reading,
        child: _LargePreview(template: tp, initialLang: _lang, loader: widget.loader, colorSeed: widget.colorSeed, onPick: (p) => Navigator.pop(ctx, p), onClose: () => Navigator.pop(ctx)),
      ),
    ));
    if (pick != null && mounted) widget.onPick(pick);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = _shown;
    final chips = [
      for (final (key, ar, en) in kCertTemplateCategories)
        if (key == 'all' || _cats.contains(key)) AppChoiceChip(label: t(ar, en), selected: _category == key, onTap: () => setState(() => _category = key)),
    ];
    return LayoutBuilder(builder: (context, box) {
      final pad = box.maxWidth > 700 ? AppSpace.xl : AppSpace.md;
      final cols = (box.maxWidth - 2 * pad + AppSpace.md) ~/ 300;
      return CustomScrollView(slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, AppSpace.md, pad, AppSpace.sm),
          sliver: SliverToBoxAdapter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(t('اختر تصميم شهادتك', 'Choose your certificate design'), style: AppType.pageTitle(context))),
                IconButton(tooltip: t('إغلاق', 'Close'), onPressed: widget.onClose, icon: Icon(Icons.close_rounded, color: c.textMedium)),
              ]),
              Text(t('تصاميم جاهزة بعناية. اضغط على تصميم لتبدأ به، ثم عدّل كل عنصر فيه كما تشاء.', 'Ready-made designs, drawn with care. Tap one to start, then edit every part of it.'), style: appText(13.5, c: c.textMedium)),
              const SizedBox(height: AppSpace.md),
              Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
                ...chips,
                Container(width: 1, height: 24, color: c.divider),
                AppChoiceChip(label: t('عربي', 'Arabic'), selected: _lang == 'ar', onTap: () => setState(() => _lang = 'ar')),
                AppChoiceChip(label: t('إنجليزي', 'English'), selected: _lang == 'en', onTap: () => setState(() => _lang = 'en')),
              ]),
            ]),
          ),
        ),
        if (widget.templates.isEmpty && widget.starters.isEmpty)
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(AppSpace.xl), child: AppEmpty(icon: Icons.dashboard_customize_outlined, title: t('لا توجد تصاميم جاهزة الآن', 'No ready designs right now'))))
        else ...[
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pad, vertical: AppSpace.sm),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols.clamp(1, 4), mainAxisSpacing: AppSpace.md, crossAxisSpacing: AppSpace.md, childAspectRatio: 1.06),
              itemCount: shown.length,
              itemBuilder: (context, i) => _TemplateCard(key: ValueKey('cert-template-${shown[i].key}'), template: shown[i], lang: _lang, loader: widget.loader, onUse: () => widget.onPick(CertGalleryPick.template(shown[i])), onLarge: () => _openLarge(shown[i])),
            ),
          ),
          if (widget.starters.isNotEmpty) ...[
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, AppSpace.md, pad, 0),
              sliver: SliverToBoxAdapter(child: Text(t('نماذج بسيطة للبدء', 'Plain starters'), style: AppType.section(context))),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, AppSpace.sm, pad, AppSpace.xl),
              sliver: SliverList.separated(
                itemCount: widget.starters.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
                itemBuilder: (context, i) {
                  final s = widget.starters[i];
                  return _StarterTile(key: ValueKey('cert-starter-${s.key}'), title: s.name(_lang), subtitle: s.description(_lang), landscape: (s.document.designs[_lang] ?? (s.document.designs.values.isEmpty ? null : s.document.designs.values.first))?.page.landscape ?? true, onTap: () => widget.onPick(CertGalleryPick.starter(s)));
                },
              ),
            ),
          ] else
            const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xl)),
        ],
      ]);
    });
  }
}

class _TemplateCard extends StatefulWidget {
  const _TemplateCard({super.key, required this.template, required this.lang, required this.loader, required this.onUse, required this.onLarge});
  final CertServerTemplate template;
  final String lang;
  final CertTemplatePreviewLoader loader;
  final VoidCallback onUse, onLarge;

  @override
  State<_TemplateCard> createState() => _TemplateCardState();
}

class _TemplateCardState extends State<_TemplateCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    final tp = widget.template;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: motion.fast,
        curve: AppMotion.curve,
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: _hover ? c.primary : c.divider, width: _hover ? AppBorder.strong : AppBorder.hairline),
          boxShadow: _hover ? AppShadow.raised(context) : AppShadow.card(context),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: AppRadius.cardAll,
            onTap: widget.onUse,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.sm),
                  child: Stack(fit: StackFit.expand, children: [
                    Container(
                      decoration: BoxDecoration(color: c.primaryWash, borderRadius: BorderRadius.circular(AppRadius.chip)),
                      child: _Preview(template: tp, lang: widget.lang, width: 720, loader: widget.loader),
                    ),
                    PositionedDirectional(
                      end: AppSpace.xs,
                      top: AppSpace.xs,
                      child: _RoundIcon(icon: Icons.zoom_out_map_rounded, label: t('عرض بحجم أكبر', 'See it larger'), onTap: widget.onLarge),
                    ),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.sm),
                child: Row(children: [
                  Expanded(child: Text(tp.name(widget.lang), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: c.textDark))),
                  const SizedBox(width: AppSpace.xs),
                  AnimatedOpacity(
                    duration: motion.fast,
                    opacity: _hover ? 1 : .0,
                    child: Text(t('استخدم', 'Use this'), style: appText(12.5, w: FontWeight.w700, c: c.primary)),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: SizedBox(
          width: AppTouch.min,
          height: AppTouch.min,
          child: Center(
            child: Material(
              color: c.cardBg.withValues(alpha: .92),
              shape: CircleBorder(side: BorderSide(color: c.divider)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.all(AppSpace.xs), child: Icon(icon, size: AppIconSize.sm, color: c.textMedium))),
            ),
          ),
        ),
      ),
    );
  }
}

/// One rendered page: a skeleton while it loads, then the image; a failure shows the page's shape.
class _Preview extends StatefulWidget {
  const _Preview({super.key, required this.template, required this.lang, required this.width, required this.loader, this.colorHex, this.bgHex, this.bg2Hex});
  final CertServerTemplate template;
  final String lang;
  final int width;
  final String? colorHex, bgHex, bg2Hex;
  final CertTemplatePreviewLoader loader;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  late Future<Uint8List?> _image = _load();

  Future<Uint8List?> _load() {
    final plain = widget.colorHex == null && widget.bgHex == null && widget.bg2Hex == null;
    final inline = plain && widget.width <= 720 ? widget.template.preview(widget.lang) : null;
    return inline != null ? Future.value(inline) : widget.loader(widget.template.key, widget.lang, widget.width, widget.colorHex, bgHex: widget.bgHex, bg2Hex: widget.bg2Hex);
  }

  @override
  void didUpdateWidget(_Preview old) {
    super.didUpdateWidget(old);
    if (old.lang != widget.lang || old.template.key != widget.template.key || old.colorHex != widget.colorHex || old.bgHex != widget.bgHex || old.bg2Hex != widget.bg2Hex || old.width != widget.width) {
      _image = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final landscape = widget.template.orientation != 'portrait';
    return ExcludeSemantics(
      child: Center(
        child: AspectRatio(
          aspectRatio: landscape ? 1000 / 707 : 707 / 1000,
          child: FutureBuilder<Uint8List?>(
            future: _image,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return AppShimmer(child: AppSkeletonBox(height: double.infinity, radius: AppRadius.chip));
              }
              final bytes = snap.data;
              if (bytes == null) return Center(child: Icon(landscape ? Icons.crop_landscape_rounded : Icons.crop_portrait_rounded, color: c.textMedium));
              return ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.chip / 2),
                child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true, filterQuality: FilterQuality.medium),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LargePreview extends StatefulWidget {
  const _LargePreview({required this.template, required this.initialLang, required this.loader, required this.colorSeed, required this.onPick, required this.onClose});
  final CertServerTemplate template;
  final String initialLang, colorSeed;
  final CertTemplatePreviewLoader loader;
  final ValueChanged<CertGalleryPick> onPick;
  final VoidCallback onClose;

  @override
  State<_LargePreview> createState() => _LargePreviewState();
}

class _LargePreviewState extends State<_LargePreview> {
  late String _lang = widget.initialLang;

  /// The palette in use; null with a custom background.
  CertPalette? _palette;

  /// The curated palettes when the server sent them, else the older "brand colour" alone.
  String? _customBg;
  String? _accent;
  CertTemplateColors _colors = const CertTemplateColors();
  Timer? _debounce;

  bool get _hasPalettes => widget.template.palettes.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_hasPalettes) _palette = widget.template.palettes.first;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _usePalette(CertPalette p) {
    _debounce?.cancel();
    setState(() {
      _palette = p;
      _customBg = null;
      _accent = null;
      _colors = certPaletteColors(p);
    });
  }

  /// A custom background keeps the look's second colour and accent. Debounced: the field fires per keystroke.
  void _useCustom(String hex) {
    setState(() {
      _customBg = hex;
      _palette = null;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final base = _colors;
      if (mounted) setState(() => _colors = CertTemplateColors(bg: hex, bg2: base.bg2, accent: base.accent));
    });
  }

  void _useAccent(String hex) {
    _debounce?.cancel();
    setState(() {
      _accent = hex;
      _colors = CertTemplateColors(bg: _colors.bg, bg2: _colors.bg2, accent: hex);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tp = widget.template;
    final colors = _colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(tp.name(_lang), style: AppType.pageTitle(context))),
          IconButton(tooltip: t('رجوع', 'Back'), onPressed: widget.onClose, icon: Icon(Icons.close_rounded, color: c.textMedium)),
        ]),
        const SizedBox(height: AppSpace.sm),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .62),
          child: Container(
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(color: c.primaryWash, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider)),
            child: _Preview(key: ValueKey('$_lang-${colors.bg}-${colors.bg2}-${colors.accent}'), template: tp, lang: _lang, width: 1200, colorHex: colors.accent, bgHex: colors.bg, bg2Hex: colors.bg2, loader: widget.loader),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
          AppChoiceChip(label: t('عربي', 'Arabic'), selected: _lang == 'ar', onTap: () => setState(() => _lang = 'ar')),
          AppChoiceChip(label: t('إنجليزي', 'English'), selected: _lang == 'en', onTap: () => setState(() => _lang = 'en')),
          if (!_hasPalettes)
            AppChoiceChip(label: t('ألوان التصميم الأصلية', 'Original colours'), selected: colors.isOriginal, onTap: () => setState(() => _colors = const CertTemplateColors())),
        ]),
        if (_hasPalettes) ...[
          const SizedBox(height: AppSpace.md),
          Text(t('ألوان الخلفية', 'Background colours'), style: AppType.section(context)),
          const SizedBox(height: AppSpace.xs),
          CertPalettePicker(palettes: tp.palettes, selectedId: _palette?.id, customBg: _customBg, lang: _lang, onPalette: _usePalette, onCustomBg: _useCustom),
        ],
        const SizedBox(height: AppSpace.sm),
        CertThemeColorField(label: t('لون التمييز (اختياري)', 'Accent colour (optional)'), hex: _accent ?? colors.accent ?? widget.colorSeed, onChanged: _useAccent),
        const SizedBox(height: AppSpace.md),
        AppPrimaryButton(label: t('استخدم هذا التصميم', 'Use this design'), onPressed: () => widget.onPick(CertGalleryPick.template(tp, colorHex: colors.accent, bgHex: colors.bg, bg2Hex: colors.bg2))),
      ]),
    );
  }
}

class _StarterTile extends StatelessWidget {
  const _StarterTile({super.key, required this.title, required this.subtitle, required this.landscape, required this.onTap});
  final String title, subtitle;
  final bool landscape;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.cardBg,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: BorderSide(color: c.divider)),
      child: InkWell(
        borderRadius: AppRadius.cardAll,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Row(children: [
              Icon(landscape ? Icons.crop_landscape_rounded : Icons.crop_portrait_rounded, color: c.primary),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14.5, w: FontWeight.w700, c: c.textDark)),
                  if (subtitle.isNotEmpty) Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
