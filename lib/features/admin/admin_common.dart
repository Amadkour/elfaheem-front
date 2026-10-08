// lib/features/admin/admin_common.dart
//
// Small shared helpers + widgets for the admin dashboard.
// Uses ONLY things that already exist in the app:
//   • ApiClient / BaseProvider          (core/)
//   • context.colors (ThemeConfigX)     (config/theme/theme_config_provider.dart)
//   • AppConfig.lang                    (config/app_config.dart)
//   • Helpers.showMessage / pageDirection (utils/helpers.dart)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:provider/provider.dart';

import '../shared/profile/profile_provider.dart';

/// Arabic / English inline text (the admin screens ship with both).
String t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// Translates [key] with `.tr`, then fills `{name}` placeholders from [params].
String trp(String key, Map<String, Object?> params) {
  var s = key.tr;
  params.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
  return s;
}

TextDirection get dir => Helpers.pageDirection;

void toast(String message, {bool error = false}) =>
    Helpers.showMessage(message, isError: error);

String money(num v, [String? currency]) {
  final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  return currency == null || currency.isEmpty ? s : '$s $currency';
}

String shortDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso);
  if (d == null) return '—';
  final l = d.isUtc ? d.toLocal() : d;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)}';
}

String shortDateTime(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso);
  if (d == null) return '—';
  final l = d.isUtc ? d.toLocal() : d;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

// ── tolerant JSON readers ────────────────────────────────────────────────────
int asInt(dynamic v, [int d = 0]) =>
    v is num ? v.toInt() : (int.tryParse('$v') ?? d);
double asDouble(dynamic v, [double d = 0]) =>
    v is num ? v.toDouble() : (double.tryParse('$v') ?? d);
bool asBool(dynamic v, [bool d = false]) => v is bool ? v : d;
String? asStrOrNull(dynamic v) => v == null ? null : '$v';
String asStr(dynamic v, [String d = '']) => v == null ? d : '$v';
Map<String, dynamic> asMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> asMapList(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];

// ── dialogs ──────────────────────────────────────────────────────────────────

Future<bool> confirm(
  BuildContext context, {
  required String message,
  String? confirmLabel,
  bool danger = false,
}) async {
  final c = context.colors;
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: dir,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Text(message, style: const TextStyle(fontFamily: 'tajawal')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('exam_cancel'.tr,
                style: TextStyle(fontFamily: 'tajawal', color: c.textMedium)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: danger ? c.danger : c.primary,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel ?? 'confirm'.tr,
                style: const TextStyle(
                    fontFamily: 'tajawal', color: Colors.white)),
          ),
        ],
      ),
    ),
  );
  return r ?? false;
}

Future<String?> askText(
  BuildContext context, {
  required String title,
  String? hint,
  bool multiline = false,
}) async {
  final ctrl = TextEditingController();
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: dir,
      child: AlertDialog(
        title: Text(title, style: const TextStyle(fontFamily: 'tajawal')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: multiline ? 4 : 1,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('exam_cancel'.tr)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text('admin_ok'.tr)),
        ],
      ),
    ),
  );
  ctrl.dispose();
  return r;
}

/// Full-height modal sheet that survives the keyboard.
Future<T?> showAdminSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Directionality(
      textDirection: dir,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.92),
          decoration: BoxDecoration(
            color: ctx.colors.cardBg,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: builder(ctx),
        ),
      ),
    ),
  );
}

// ── small widgets ────────────────────────────────────────────────────────────

class SheetHeader extends StatelessWidget {
  const SheetHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(children: [
        Expanded(
          child: Text(title,
              style: TextStyle(
                  fontFamily: 'tajawal',
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: c.textDark)),
        ),
        if (trailing != null) trailing!,
        IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close_rounded, color: c.textMedium)),
      ]),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, this.color, {super.key});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontFamily: 'tajawal',
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color)),
      );
}

class Section extends StatelessWidget {
  const Section({super.key, required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(title,
                style: TextStyle(
                    fontFamily: 'tajawal',
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: c.textDark)),
          ),
          if (trailing != null) trailing!,
        ]),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }
}

class KeyValue extends StatelessWidget {
  const KeyValue(this.k, this.v, {super.key});
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 110,
          child: Text(k,
              style: TextStyle(
                  fontFamily: 'tajawal', fontSize: 12.5, color: c.textLight)),
        ),
        Expanded(
          child: Text(v.isEmpty ? '—' : v,
              style: TextStyle(
                  fontFamily: 'tajawal',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.textDark)),
        ),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {super.key, this.icon = Icons.inbox_rounded});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        IconButton(onPressed: () async {
          final ok = await Helpers.confirmDialog(context);
          if (ok == true && context.mounted) {
            await context.read<ProfileProvider>().logout(
              context,
            );
          }
        }, icon: Icon(Icons.logout)),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 52, color: c.textLight),
              const SizedBox(height: 10),
              Text(message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'tajawal', color: c.textMedium)),
            ]),
          ),
        ),
      ],
    );
  }
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded, size: 48, color: c.danger),
          const SizedBox(height: 10),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'tajawal', color: c.textMedium)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text('retry'.tr),
          ),
        ]),
      ),
    );
  }
}

/// Labelled text field used by every form in the dashboard.
class Field extends StatelessWidget {
  const Field({
    super.key,
    required this.controller,
    required this.label,
    this.keyboard,
    this.obscure = false,
    this.maxLines = 1,
    this.hint,
    this.enabled = true,
    this.ltr = false,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboard;
  final bool obscure;
  final int maxLines;
  final String? hint;
  final bool enabled;
  final bool ltr;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboard,
        obscureText: obscure,
        maxLines: obscure ? 1 : maxLines,
        textDirection: ltr ? TextDirection.ltr : null,
        validator: validator,
        style: const TextStyle(fontFamily: 'tajawal'),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: c.inputBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.divider),
          ),
        ),
      ),
    );
  }
}

/// One-of-N selector built from ChoiceChips (no Dropdown / Radio so it works
/// on every Flutter 3.x version regardless of API deprecations).
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.label,
  });

  /// value → display label
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label!,
                style: TextStyle(
                    fontFamily: 'tajawal', fontSize: 12.5, color: c.textLight)),
          ),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final e in options.entries)
            ChoiceChip(
              label: Text(e.value,
                  style: TextStyle(
                      fontFamily: 'tajawal',
                      color: e.key == value ? Colors.white : c.textDark)),
              selected: e.key == value,
              selectedColor: c.primary,
              onSelected: (_) => onChanged(e.key),
            ),
        ]),
      ]),
    );
  }
}

/// Debounced search box.
class SearchBox extends StatefulWidget {
  const SearchBox({super.key, required this.onChanged, this.hint});
  final ValueChanged<String> onChanged;
  final String? hint;

  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  final _ctrl = TextEditingController();
  DateTime _last = DateTime.now();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _changed(String v) {
    final stamp = _last = DateTime.now();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted && stamp == _last) widget.onChanged(v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TextField(
      controller: _ctrl,
      onChanged: _changed,
      style: const TextStyle(fontFamily: 'tajawal'),
      decoration: InputDecoration(
        hintText: widget.hint ?? 'admin_search'.tr,
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: c.inputBg,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.divider),
        ),
      ),
    );
  }
}
