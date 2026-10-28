// lib/features/admin/admin_theme_page.dart — built-in themes + custom themes with live preview.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/app_theme.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../../utils/widget/app_bar.dart';
import '../../utils/widget/base_page.dart';
import '../../utils/widget/outline_button.dart';
import '../../utils/widget/primary_button.dart';
import 'admin_common.dart';
import 'admin_models.dart';
import 'admin_providers.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton, AppRefresh;

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

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminThemesProvider>();
    final c = context.colors;

    Widget body;
    if (p.items.isEmpty && p.isLoading) {
      body = const AppListSkeleton();
    } else if (p.items.isEmpty) {
      body = ErrorRetry(
        message: p.error ?? 'admin_could_not_load_data'.tr,
        onRetry: p.load,
      );
    } else {
      body = AppRefresh(
        onRefresh: p.load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
          children: [
            Text(
              'admin_pick_a_ready_theme_or_build_your_own'.tr,
              style: TextStyle(
                fontFamily: 'tajawal',
                fontSize: 12.5,
                color: c.textMedium,
              ),
            ),
            const SizedBox(height: 12),
            for (final th in p.items)
              _ThemeCard(th, active: th.key == p.activeKey),
          ],
        ),
      );
    }

    return BasePage(
      useWebCard: true,
      maxWith: 1100,
      appBar: ScreenAppBar(title: 'theme'.tr),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: "theme_float",
        key: ValueKey("theme_float"),
        backgroundColor: c.primary,
        onPressed: p.items.isEmpty ? null : () => _openEditor(context, p),
        icon: Icon(Icons.palette_rounded, color: c.onHero),
        label: Text(
          'admin_custom_theme'.tr,
          style: TextStyle(fontFamily: 'tajawal', color: c.onHero),
        ),
      ),
      child: body,
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard(this.th, {required this.active});

  final ThemePresetModel th;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminThemesProvider>();
    final col = th.colors;
    Color sw(String k) => _parseHex(col[k] ?? '') ?? context.colors.textLight;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? c.primary : c.divider,
          width: active ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  th.name,
                  style: TextStyle(
                    fontFamily: 'tajawal',
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: c.textDark,
                  ),
                ),
              ),
              if (active) StatusChip('admin_active_2'.tr, c.success),
              if (!th.isBuiltin) StatusChip('admin_custom'.tr, c.purple),
            ],
          ),
          const SizedBox(height: 10),
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
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: active ? c.textLight : c.primary,
                  ),
                  icon: Icon(Icons.check_rounded, color: c.onHero),
                  label: Text(
                    active ? 'admin_currently_active'.tr : 'admin_activate'.tr,
                    style: TextStyle(
                      color: c.onHero,
                      fontFamily: 'tajawal',
                    ),
                  ),
                  onPressed: active
                      ? null
                      : () async {
                          final ok = await confirm(
                            context,
                            message: trp('admin_activate_for_all_users', {
                              'name': th.name,
                            }),
                          );
                          if (ok) await p.activate(th.id);
                        },
                ),
              ),
              const SizedBox(width: 8),
              OutlineButton(
                icon: th.isBuiltin ? Icons.copy_rounded : Icons.edit_rounded,
                label: th.isBuiltin ? 'admin_copy'.tr : 'btn_edit'.tr,
                onPressed: () =>
                    _openEditor(context, p, base: th, edit: !th.isBuiltin),
                color: context.colors.primary,
              ),
              if (!th.isBuiltin && !active)
                IconButton(tooltip: t('حذف', 'Delete'), 
                  icon: Icon(Icons.delete_outline_rounded, color: c.danger),
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
    );
  }
}

/// Mini mock screen painted with the theme colours (used in the list and the editor).
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

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 110,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (final col in [primary, dark, light, accent1, accent2])
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(bottom: 3),
                decoration: BoxDecoration(
                  color: col,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          Container(
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [primary, accent2]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Container(
              height: 5,
              width: 40,
              decoration: BoxDecoration(
                color: context.colors.onHero,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
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

  @override
  void initState() {
    super.initState();
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(
          widget.edit ? 'admin_edit_theme'.tr : 'admin_new_custom_theme'.tr,
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
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
                const SizedBox(height: 14),
                Field(controller: _ar, label: 'admin_arabic_name_2'.tr),
                Field(
                  controller: _en,
                  label: 'admin_english_name_2'.tr,
                  ltr: true,
                ),
                for (final e in _editable.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => _pickPalette(e.key),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: col(e.key),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: context.colors.divider),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _ctrls[e.key],
                            textDirection: TextDirection.ltr,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: e.value.tr,
                              hintText: '#RRGGBB',
                              errorText: _validHex(_ctrls[e.key]!.text)
                                  ? null
                                  : 'admin_use_rrggbb'.tr,
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  'admin_all_other_colours_success_danger_dark'.tr,
                  style: const TextStyle(fontFamily: 'tajawal', fontSize: 12),
                ),
                const SizedBox(height: 14),
                PrimaryButton(
                  label: 'save'.tr,
                  isLoading: busy,
                  onPressed: _save,
                ),
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
          title: Text(
            'admin_pick_a_colour'.tr,
            style: const TextStyle(fontFamily: 'tajawal'),
          ),
          content: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in _swatches)
                GestureDetector(
                  onTap: () => Navigator.pop(ctx, c),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.colors.divider),
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
