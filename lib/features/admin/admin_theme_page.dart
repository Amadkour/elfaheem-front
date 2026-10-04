// lib/features/admin/admin_theme_page.dart — built-in themes + custom themes with live preview.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../../utils/widget/app_bar.dart';
import '../../utils/widget/base_page.dart';
import 'admin_common.dart';
import 'admin_models.dart';
import 'admin_providers.dart';

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
      body = const Center(child: CircularProgressIndicator());
    } else if (p.items.isEmpty) {
      body = ErrorRetry(message: p.error ?? t('تعذر تحميل البيانات', 'Could not load data'), onRetry: p.load);
    } else {
      body = RefreshIndicator(
        onRefresh: p.load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 90), children: [
          Text(
            t('اختر ثيماً جاهزاً أو أنشئ ثيماً مخصصاً. يُطبَّق على كل المنصات ويصل للمستخدمين عند فتح التطبيق.',
                'Pick a ready theme or build your own. It applies to all platforms and reaches users the next time they open the app.'),
            style: TextStyle(fontFamily: 'tajawal', fontSize: 12.5, color: c.textMedium),
          ),
          const SizedBox(height: 12),
          for (final th in p.items) _ThemeCard(th, active: th.key == p.activeKey),
        ]),
      );
    }

    return BasePage(

      useWebCard: true,
      maxWith: 1100,
      appBar: ScreenAppBar(title: 'theme'.tr),floatingActionButton: FloatingActionButton.extended(
          backgroundColor: c.primary,
          onPressed: p.items.isEmpty ? null : () => _openEditor(context, p),
          icon: const Icon(Icons.palette_rounded, color: Colors.white),
          label: Text(t('ثيم مخصص', 'Custom theme'), style: const TextStyle(fontFamily: 'tajawal', color: Colors.white)),
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
    Color sw(String k) => _parseHex(col[k] ?? '') ?? Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: active ? c.primary : c.divider, width: active ? 2 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(th.name,
                style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, fontSize: 16, color: c.textDark)),
          ),
          if (active) StatusChip(t('مفعّل', 'Active'), c.success),
          if (!th.isBuiltin) StatusChip(t('مخصص', 'Custom'), c.purple),
        ]),
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
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: active ? c.textLight : c.primary),
              icon: const Icon(Icons.check_rounded, color: Colors.white),
              label: Text(active ? t('مفعّل حالياً', 'Currently active') : t('تفعيل', 'Activate'),
                  style: const TextStyle(color: Colors.white, fontFamily: 'tajawal')),
              onPressed: active
                  ? null
                  : () async {
                      final ok = await confirm(context,
                          message: t('تفعيل "${th.name}" لكل المستخدمين؟', 'Activate "${th.name}" for all users?'));
                      if (ok) await p.activate(th.id);
                    },
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: Icon(th.isBuiltin ? Icons.copy_rounded : Icons.edit_rounded, size: 18),
            label: Text(th.isBuiltin ? t('نسخ وتعديل', 'Copy') : t('تعديل', 'Edit')),
            onPressed: () => _openEditor(context, p, base: th, edit: !th.isBuiltin),
          ),
          if (!th.isBuiltin && !active)
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: c.danger),
              onPressed: () async {
                final ok = await confirm(context, message: t('حذف هذا الثيم؟', 'Delete this theme?'), danger: true);
                if (ok) await p.remove(th.id);
              },
            ),
        ]),
      ]),
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
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(height: 8, width: 70, decoration: BoxDecoration(color: text, borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 6),
              Container(height: 6, width: 110, decoration: BoxDecoration(color: text.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(4))),
              const Spacer(),
              Container(
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [primary, accent2]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Container(height: 5, width: 40, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3))),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: Column(children: [
            for (final col in [primary, dark, light, accent1, accent2])
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 3),
                  decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(5)),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Custom theme editor
// ═════════════════════════════════════════════════════════════════════════════

const _editable = <String, List<String>>{
  // key → [arabic label, english label]
  'primary_hex': ['اللون الأساسي', 'Primary'],
  'primary_dark_hex': ['الأساسي الداكن', 'Primary dark'],
  'primary_light_hex': ['الأساسي الفاتح', 'Primary light'],
  'accent1_hex': ['لون مميز 1', 'Accent 1'],
  'accent2_hex': ['لون مميز 2', 'Accent 2'],
  'background_hex': ['الخلفية', 'Background'],
  'text_dark': ['لون النص', 'Text'],
  'text_action': ['نص الأزرار/الروابط', 'Action text'],
  'dark_background': ['خلفية الوضع الليلي', 'Dark background'],
  'dark_card': ['بطاقة الوضع الليلي', 'Dark card'],
};

Future<void> _openEditor(BuildContext context, AdminThemesProvider p, {ThemePresetModel? base, bool edit = false}) {
  final source = base ?? p.items.firstWhere((x) => x.key == p.activeKey, orElse: () => p.items.first);
  return showAdminSheet(context, (ctx) => _Editor(provider: p, source: source, edit: edit));
}

class _Editor extends StatefulWidget {
  const _Editor({required this.provider, required this.source, required this.edit});
  final AdminThemesProvider provider;
  final ThemePresetModel source;
  final bool edit;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final Map<String, String> colors = Map.of(widget.source.colors);
  late final _ar = TextEditingController(text: widget.edit ? widget.source.nameAr : '${widget.source.nameAr} (نسخة)');
  late final _en = TextEditingController(text: widget.edit ? widget.source.nameEn : '${widget.source.nameEn} copy');
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

  Color col(String k) => _parseHex(_ctrls[k]!.text) ?? Colors.grey;

  Future<void> _save() async {
    if (_ar.text.trim().isEmpty || _en.text.trim().isEmpty) {
      toast(t('أدخل اسم الثيم بالعربية والإنجليزية', 'Enter the theme name in both languages'), error: true);
      return;
    }
    for (final e in _ctrls.entries) {
      if (!_validHex(e.value.text)) {
        toast('${t('لون غير صحيح', 'Invalid colour')}: ${t(_editable[e.key]![0], _editable[e.key]![1])} (#RRGGBB)', error: true);
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
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SheetHeader(widget.edit ? t('تعديل الثيم', 'Edit theme') : t('ثيم مخصص جديد', 'New custom theme')),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Preview(
              primary: col('primary_hex'),
              dark: col('primary_dark_hex'),
              light: col('primary_light_hex'),
              accent1: col('accent1_hex'),
              accent2: col('accent2_hex'),
              background: col('background_hex'),
              text: col('text_dark'),
              card: _parseHex(colors['surface_card'] ?? '') ?? Colors.white,
            ),
            const SizedBox(height: 14),
            Field(controller: _ar, label: t('اسم الثيم بالعربية', 'Arabic name')),
            Field(controller: _en, label: t('اسم الثيم بالإنجليزية', 'English name'), ltr: true),
            for (final e in _editable.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => _pickPalette(e.key),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: col(e.key),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black26),
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
                        labelText: t(e.value[0], e.value[1]),
                        hintText: '#RRGGBB',
                        errorText: _validHex(_ctrls[e.key]!.text) ? null : t('صيغة #RRGGBB', 'Use #RRGGBB'),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ]),
              ),
            Text(
              t('باقي الألوان (النجاح، الخطر، الوضع الليلي…) تُنسخ من الثيم الأصلي.',
                  'All other colours (success, danger, dark mode…) are copied from the source theme.'),
              style: const TextStyle(fontFamily: 'tajawal', fontSize: 12),
            ),
            const SizedBox(height: 14),
            PrimaryButton(label: t('حفظ', 'Save'), busy: busy, onPressed: _save),
          ]),
        ),
      ),
    ]);
  }

  static const _swatches = <Color>[
    Color(0xFF24B1B1), Color(0xFF2F3E9E), Color(0xFF0F7B5F), Color(0xFF7A1F3D), Color(0xFF22306B),
    Color(0xFFF4C542), Color(0xFFFF6F61), Color(0xFF8B6FFF), Color(0xFF34C270), Color(0xFFFF3B5C),
    Color(0xFF1A1A1A), Color(0xFF2E2E2E), Color(0xFFFFFFFF), Color(0xFFF8F4EF), Color(0xFFD4FEFD),
    Color(0xFFFAF4EE), Color(0xFFF2F4FF), Color(0xFF0F1224), Color(0xFF0C1511), Color(0xFF1A0F13),
  ];

  Future<void> _pickPalette(String key) async {
    final r = await showDialog<Color>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: dir,
        child: AlertDialog(
          title: Text(t('اختر لوناً', 'Pick a colour'), style: const TextStyle(fontFamily: 'tajawal')),
          content: Wrap(spacing: 10, runSpacing: 10, children: [
            for (final c in _swatches)
              GestureDetector(
                onTap: () => Navigator.pop(ctx, c),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.black26)),
                ),
              ),
          ]),
        ),
      ),
    );
    if (r != null) {
      final hex = '#${(r.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
      setState(() => _ctrls[key]!.text = hex);
    }
  }
}
