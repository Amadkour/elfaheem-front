// lib/features/admin/admin_theme_page.dart — built-in themes + custom themes with live preview.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/app_theme.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_contrast.dart';
import 'package:provider/provider.dart';

import 'admin_common.dart';
import 'admin_page.dart';
import 'admin_models.dart';
import 'admin_providers.dart';
import 'package:flutter_education_app/design/app_kit.dart'
    show AppListSkeleton, AppRefresh, AppButton, AppIconButton, AppCard, AppSpace, AppType, AppStatusBadge, AppTone, AppErrorState, AppUnsavedGuard, AppTouch, AppRadius, AppGrid, AppBorder, AppIconSize, appInk, appFieldDecoration, appFieldTextStyle;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppReveal, AppTilt;
import 'sup/sup_kit.dart';

Color? _parseHex(String s) {
  final h = s.trim().replaceFirst('#', '');
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

bool _validHex(String s) => RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(s.trim());

class AdminThemePage extends StatelessWidget {
  const AdminThemePage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => AdminThemesProvider()..load(),
    child: const _View(),
  );
}

class _View extends StatelessWidget {
  const _View();

  /// A preset card is never narrower than this: the mock screen and its three actions stay readable.
  static const double _cardMinWidth = AppSpace.xxxl * 5;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminThemesProvider>();

    Widget body;
    if (p.items.isEmpty && p.isLoading) {
      body = const AppListSkeleton();
    } else if (p.items.isEmpty) {
      body = AppErrorState(message: p.error ?? 'admin_could_not_load_data'.tr, onRetry: p.load);
    } else {
      body = AppRefresh(
        onRefresh: p.load,
        child: ListView(
          padding: AdminPage.bodyPadding(context),
          children: [
            // the presets side by side on wide screens, so they compare at a glance; one column on phones
            AppGrid(
              minTile: _View._cardMinWidth,
              padding: EdgeInsets.zero,
              children: [
                for (final (i, th) in p.items.indexed)
                  AppReveal(index: i, group: 'admin_themes', child: _ThemeCard(th, active: th.key == p.activeKey)),
              ],
            ),
          ],
        ),
      );
    }

    return SupPage(
        kicker: 'a2_site_kicker'.tr, headline: 'a2_theme_head'.tr,
        title: 'theme'.tr,
        onRefresh: p.load,
        body: body,
        actions: [AppButton.primary(
        key: const ValueKey('theme_float'),
        label: 'admin_custom_theme'.tr,
        icon: Icons.palette_rounded,
        onPressed: p.items.isEmpty ? null : () => _openEditor(context, p),
      )],
      );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard(this.th, {required this.active});

  final ThemePresetModel th;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.read<AdminThemesProvider>();
    final col = th.colors;
    Color sw(String k) => _parseHex(col[k] ?? '') ?? context.colors.textLight;

    final card = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: AppRadius.cardAll,
        border: active ? Border.all(color: context.colors.primary, width: AppBorder.focus) : null,
      ),
      child: AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(th.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
              ),
              if (active) AppStatusBadge(label: 'admin_active_2'.tr, tone: AppTone.success),
              if (!th.isBuiltin) ...[
                AppSpace.gapXs,
                AppStatusBadge(label: 'admin_custom'.tr, tone: AppTone.brand),
              ],
            ],
          ),
          AppSpace.gapSm,
          _Preview(
            primary: sw('primary_hex'),
            dark: sw('primary_dark_hex'),
            light: sw('primary_light_hex'),
            accent1: sw('accent1_hex'),
            accent2: sw('accent2_hex'),
            background: sw('background_hex'),
            text: sw('text_dark'),
            card: sw('surface_card'),
          ),
          AppSpace.gapSm,
          // wraps: three actions never overflow a 320 px phone
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppButton.primary(
                icon: Icons.check_rounded,
                label: active ? 'admin_currently_active'.tr : 'admin_activate'.tr,
                onPressed: active
                    ? null
                    : () async {
                        final ok = await confirm(
                          context,
                          message: trp('admin_activate_for_all_users', {'name': th.name}),
                        );
                        if (ok) await p.activate(th.id);
                      },
              ),
              AppButton.secondary(
                icon: th.isBuiltin ? Icons.copy_rounded : Icons.edit_rounded,
                label: th.isBuiltin ? 'admin_copy'.tr : 'btn_edit'.tr,
                onPressed: () => _openEditor(context, p, base: th, edit: !th.isBuiltin),
              ),
              if (!th.isBuiltin && !active)
                AppIconButton(
                  tooltip: t('حذف', 'Delete'),
                  icon: Icons.delete_outline_rounded,
                  onPressed: () async {
                    final ok = await confirm(
                      context,
                      message: 'admin_delete_this_theme'.tr,
                      danger: true,
                    );
                    if (ok) await p.remove(th.id);
                  },
                ),
            ],
          ),
        ],
      ),
    ));
    return active ? AppTilt.subtle(radius: AppRadius.card, child: card) : card;
  }
}

/// A mini editorial screen painted with the theme's colours (used in the list and the editor): the canvas, a tinted
/// block (accent 1) with a headline, a paper card with an achievement dot (accent 2) and the solid primary button,
/// then the primary family as swatches.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.primary,
    required this.dark,
    required this.light,
    required this.accent1,
    required this.accent2,
    required this.background,
    required this.text,
    required this.card,
  });

  final Color primary, dark, light, accent1, accent2, background, text, card;

  static const double _height = AppSpace.xxxl * 2 + AppSpace.lg;
  static const double _bar = AppSpace.xxs + 2;

  Widget _line(Color color, double widthFactor, [double height = _bar]) => FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: widthFactor,
        child: Container(
          height: height,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppRadius.pill)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final muted = text.withValues(alpha: 0.35);
    return ExcludeSemantics(
      child: Container(
        height: _height,
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadius.controlAll,
          border: Border.all(color: context.colors.divider, width: AppBorder.hairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // the block: headline + one line in the theme's ink
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(AppSpace.xs + AppSpace.xxs),
                      decoration: BoxDecoration(color: accent1, borderRadius: AppRadius.controlAll),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _line(text, 0.7, AppSpace.xs),
                          const SizedBox(height: AppSpace.xxs + 2),
                          _line(muted, 0.45),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  // the primary button
                  Container(
                    height: AppSpace.lg,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: primary, borderRadius: AppRadius.chipAll),
                    child: FractionallySizedBox(
                      widthFactor: 0.4,
                      child: Container(
                        height: AppSpace.xxs + 1,
                        decoration: BoxDecoration(
                          color: context.colors.onHero,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // a paper card: a gold achievement dot and two lines
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(AppSpace.xs),
                      decoration: BoxDecoration(color: card, borderRadius: AppRadius.chipAll),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: AppSpace.sm,
                            height: AppSpace.sm,
                            decoration: BoxDecoration(color: accent2, shape: BoxShape.circle),
                          ),
                          const SizedBox(height: AppSpace.xs),
                          _line(muted, 0.85),
                          const SizedBox(height: AppSpace.xxs),
                          _line(muted, 0.55),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  // the primary family
                  SizedBox(
                    height: AppSpace.lg,
                    child: Row(
                      children: [
                        for (final (i, col) in [dark, primary, light].indexed) ...[
                          if (i > 0) const SizedBox(width: AppSpace.xxs),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(color: col, borderRadius: AppRadius.chipAll),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Custom theme editor
// ═════════════════════════════════════════════════════════════════════════════

const _editable = <String, String>{
  // colour key → translation key
  'primary_hex': 'admin_color_primary',
  'primary_dark_hex': 'admin_color_primary_dark',
  'primary_light_hex': 'admin_color_primary_light',
  'accent1_hex': 'admin_color_accent1',
  'accent2_hex': 'admin_color_accent2',
  'background_hex': 'admin_color_background',
  'text_dark': 'admin_color_text_dark',
  'text_action': 'admin_color_text_action',
  'dark_background': 'admin_color_dark_background',
  'dark_card': 'admin_color_dark_card',
};

/// A secondary text colour of a theme that misses WCAG AA (4.5:1) on one of its surfaces.
typedef MutedContrastIssue = ({bool dark, String hex, double ratio, Color adjusted});

/// The secondary text colours (`text_light`, `dark_text_light`) of the flat theme [colors] that read below 4.5:1 on a
/// surface they are drawn on, with the colour the app will use instead (the live palette is guarded the same way,
/// `ThemeConfigModel.readableText`). Surfaces the theme does not carry are skipped.
List<MutedContrastIssue> mutedContrastIssues(Map<String, String> colors) {
  List<Color> on(List<String> keys) => [for (final k in keys) ?_parseHex(colors[k] ?? '')];
  const light = ['background_hex', 'surface_card', 'card_bg_hexa', 'card_bg', 'text_field_background', 'input_bg'];
  const dark = ['dark_background', 'dark_surface', 'dark_card', 'dark_input', 'input_bg_dark'];
  return [
    for (final (isDark, key, surfaces) in [(false, 'text_light', on(light)), (true, 'dark_text_light', on(dark))])
      if (_parseHex(colors[key] ?? '') case final fg?)
        if (surfaces.isNotEmpty && !passesContrast(fg, surfaces))
          (
            dark: isDark,
            hex: colors[key]!.trim().toUpperCase(),
            ratio: minContrast(fg, surfaces),
            adjusted: ensureContrast(fg, surfaces),
          ),
  ];
}

String _hexOf(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Future<void> _openEditor(
  BuildContext context,
  AdminThemesProvider p, {
  ThemePresetModel? base,
  bool edit = false,
}) {
  final source =
      base ??
      p.items.firstWhere(
        (x) => x.key == p.activeKey,
        orElse: () => p.items.first,
      );
  return showAdminSheet(
    context,
    (ctx) => _Editor(provider: p, source: source, edit: edit),
  );
}

class _Editor extends StatefulWidget {
  const _Editor({
    required this.provider,
    required this.source,
    required this.edit,
  });

  final AdminThemesProvider provider;
  final ThemePresetModel source;
  final bool edit;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final Map<String, String> colors = Map.of(widget.source.colors);
  late final _ar = TextEditingController(
    text: widget.edit ? widget.source.nameAr : '${widget.source.nameAr} (نسخة)',
  );
  late final _en = TextEditingController(
    text: widget.edit ? widget.source.nameEn : '${widget.source.nameEn} copy',
  );
  final Map<String, TextEditingController> _ctrls = {};
  bool busy = false;

  /// Unsaved edits: the names or any colour differ from the theme this editor started from.
  bool get _dirty {
    final src = widget.source;
    if (_ar.text != (widget.edit ? src.nameAr : '${src.nameAr} (نسخة)')) return true;
    if (_en.text != (widget.edit ? src.nameEn : '${src.nameEn} copy')) return true;
    for (final e in _ctrls.entries) {
      if (e.value.text.trim().toUpperCase() != (src.colors[e.key] ?? '#000000').toUpperCase()) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _ar.addListener(_redraw);
    _en.addListener(_redraw);
    for (final k in _editable.keys) {
      _ctrls[k] = TextEditingController(text: colors[k] ?? '#000000');
    }
  }

  @override
  void dispose() {
    _ar.dispose();
    _en.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  Color col(String k) => _parseHex(_ctrls[k]!.text) ?? context.colors.textLight;

  Future<void> _save() async {
    if (_ar.text.trim().isEmpty || _en.text.trim().isEmpty) {
      toast('admin_enter_the_theme_name_in_both_languages'.tr, error: true);
      return;
    }
    for (final e in _ctrls.entries) {
      if (!_validHex(e.value.text)) {
        toast(
          '${'admin_invalid_colour'.tr}: ${_editable[e.key]!.tr} (#RRGGBB)',
          error: true,
        );
        return;
      }
      colors[e.key] = e.value.text.trim().toUpperCase();
    }
    setState(() => busy = true);
    final ok = await widget.provider.save(
      id: widget.edit ? widget.source.id : null,
      nameAr: _ar.text.trim(),
      nameEn: _en.text.trim(),
      colors: colors,
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AppUnsavedGuard(
      dirty: _dirty && !busy,
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(
          widget.edit ? 'admin_edit_theme'.tr : 'admin_new_custom_theme'.tr,
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Preview(
                  primary: col('primary_hex'),
                  dark: col('primary_dark_hex'),
                  light: col('primary_light_hex'),
                  accent1: col('accent1_hex'),
                  accent2: col('accent2_hex'),
                  background: col('background_hex'),
                  text: col('text_dark'),
                  card: _parseHex(colors['surface_card'] ?? '') ?? AppTheme.surfaceCard,
                ),
                const SizedBox(height: AppSpace.lg),
                Field(controller: _ar, label: 'admin_arabic_name_2'.tr),
                Field(
                  controller: _en,
                  label: 'admin_english_name_2'.tr,
                  ltr: true,
                ),
                for (final e in _editable.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          button: true,
                          label: '${e.value.tr} ${_ctrls[e.key]!.text}',
                          child: InkWell(
                            borderRadius: AppRadius.controlAll,
                            onTap: () => _pickPalette(e.key),
                            child: Container(
                              width: AppTouch.min,
                              height: AppTouch.min,
                              decoration: BoxDecoration(
                                color: col(e.key),
                                borderRadius: AppRadius.controlAll,
                                border: Border.all(color: context.colors.divider, width: AppBorder.hairline),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpace.sm),
                        Expanded(
                          child: TextField(
                            controller: _ctrls[e.key],
                            textDirection: TextDirection.ltr,
                            onChanged: (_) => setState(() {}),
                            style: appFieldTextStyle(context),
                            decoration: appFieldDecoration(
                              context,
                              hint: '#RRGGBB',
                              errorText: _validHex(_ctrls[e.key]!.text) ? null : 'admin_use_rrggbb'.tr,
                              dense: true,
                            ).copyWith(labelText: e.value.tr),
                          ),
                        ),
                      ],
                    ),
                  ),
                for (final w in mutedContrastIssues({
                  ...colors,
                  for (final e in _ctrls.entries)
                    if (_validHex(e.value.text)) e.key: e.value.text.trim(),
                }))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.contrast_rounded, size: AppIconSize.sm, color: appInk(context, context.colors.warning)),
                        const SizedBox(width: AppSpace.xs),
                        Expanded(
                          child: Text(
                            t(
                              'النص الثانوي ${w.dark ? '(الوضع الداكن) ' : ''}${w.hex} تباينه ${w.ratio.toStringAsFixed(1)}:1 فقط مع الخلفية (المطلوب 4.5:1) — سيعرضه التطبيق بلون ${_hexOf(w.adjusted)}',
                              'Secondary text ${w.dark ? '(dark mode) ' : ''}${w.hex} reaches only ${w.ratio.toStringAsFixed(1)}:1 on its background (4.5:1 needed) — the app will show it as ${_hexOf(w.adjusted)}',
                            ),
                            style: AppType.meta(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  'admin_all_other_colours_success_danger_dark'.tr,
                  style: AppType.meta(context),
                ),
                const SizedBox(height: AppSpace.lg),
                AppButton.primary(label: 'save'.tr, busy: busy, expand: true, onPressed: _save),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static const _swatches = <Color>[
    Color(0xFF24B1B1),
    Color(0xFF2F3E9E),
    Color(0xFF0F7B5F),
    Color(0xFF7A1F3D),
    Color(0xFF22306B),
    Color(0xFFF4C542),
    Color(0xFFFF6F61),
    Color(0xFF8B6FFF),
    Color(0xFF34C270),
    Color(0xFFFF3B5C),
    Color(0xFF1A1A1A),
    Color(0xFF2E2E2E),
    Color(0xFFFFFFFF),
    Color(0xFFF8F4EF),
    Color(0xFFD4FEFD),
    Color(0xFFFAF4EE),
    Color(0xFFF2F4FF),
    Color(0xFF0F1224),
    Color(0xFF0C1511),
    Color(0xFF1A0F13),
  ];

  Future<void> _pickPalette(String key) async {
    final r = await showDialog<Color>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: dir,
        child: AlertDialog(
          scrollable: true,
          title: Text('admin_pick_a_colour'.tr),
          content: Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              for (final c in _swatches)
                Semantics(
                  button: true,
                  label: _hexOf(c),
                  child: InkWell(
                    borderRadius: AppRadius.controlAll,
                    onTap: () => Navigator.pop(ctx, c),
                    child: Container(
                      width: AppTouch.min,
                      height: AppTouch.min,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: AppRadius.controlAll,
                        border: Border.all(color: context.colors.divider, width: AppBorder.hairline),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (r != null) {
      final hex =
          '#${(r.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
      setState(() => _ctrls[key]!.text = hex);
    }
  }
}
