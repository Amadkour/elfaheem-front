// lib/features/parent/parent_widgets.dart
// Small shared widgets / helpers for the Parent role screens (and the two admin parent-link pages).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

// re-exported so every parent screen gets `.tr`, `context.colors` and Helpers with ONE import
export 'package:flutter_education_app/config/theme/theme_config_provider.dart';
export '../../utils/helpers.dart';

import '../../config/app_config.dart';
import '../../utils/helpers.dart';

bool get plIsAr => AppConfig.lang.toString().toLowerCase().startsWith('ar');

/// `label_ar` / `label_en` of a server map in the current language.
String plLabel(Map m, [String base = 'label']) =>
    ((plIsAr ? m['${base}_ar'] : m['${base}_en']) ?? m['${base}_en'] ?? m['${base}_ar'] ?? m['key'] ?? '')
        .toString();

/// ISO string (UTC, ends with Z) -> local "yyyy-MM-dd HH:mm".
String plDateTime(dynamic iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.toString())?.toLocal();
  if (d == null) return '—';
  String t(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${t(d.month)}-${t(d.day)} ${t(d.hour)}:${t(d.minute)}';
}

String plDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String plMinutes(dynamic m) {
  final v = (m is num) ? m.toInt() : int.tryParse('$m') ?? 0;
  if (v < 60) return '$v ${'pl_min'.tr}';
  return '${v ~/ 60}${'pl_h'.tr} ${v % 60}${'pl_min'.tr}';
}

/// Translation with `{name}` placeholders:  plFmt('pl_ins_streak', {'days': 4}).
String plFmt(String key, [Map<String, dynamic> params = const {}]) {
  var t = key.tr;
  params.forEach((k, v) => t = t.replaceAll('{$k}', '$v'));
  return t;
}

List<Map<String, dynamic>> plList(dynamic r) => r is List
    ? r.map((e) => Map<String, dynamic>.from(e as Map)).toList()
    : <Map<String, dynamic>>[];

Color plStatusColor(BuildContext context, String s) {
  final c = context.colors;
  switch (s) {
    case 'approved':
      return c.success;
    case 'rejected':
    case 'failed':
      return c.danger;
    case 'cancelled':
      return Colors.grey;
    default:
      return c.warning; // pending
  }
}

class PlStatusChip extends StatelessWidget {
  const PlStatusChip(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final col = plStatusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: col.withAlpha(35),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('pl_status_$status'.tr,
          style: TextStyle(color: col, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

class PlEmpty extends StatelessWidget {
  const PlEmpty(this.text, {super.key, this.icon = Icons.inbox_rounded, this.action});

  final String text;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: c.primary.withAlpha(150)),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: c.caption),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

class PlError extends StatelessWidget {
  const PlError(this.message, {super.key, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => PlEmpty(
    message,
    icon: Icons.cloud_off_rounded,
    action: FilledButton.icon(
        onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: Text('pl_retry'.tr)),
  );
}

class PlCard extends StatelessWidget {
  const PlCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.primary.withAlpha(30)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Shows an error from a provider as a snackbar-style message (uses the project's Helpers).
void plToast(String? m) {
  if (m == null || m.isEmpty) return;
  Helpers.showMessage(m);
}

Future<String?> plAskText(BuildContext context, String title,
    {String hint = '', bool required = false}) async {
  final ctrl = TextEditingController();
  final res = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        maxLines: 3,
        decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('pl_cancel'.tr)),
        FilledButton(
          onPressed: () {
            if (required && ctrl.text.trim().length < 3) return;
            Navigator.pop(ctx, ctrl.text.trim());
          },
          child: Text('pl_confirm'.tr),
        ),
      ],
    ),
  );
  ctrl.dispose();
  return res;
}