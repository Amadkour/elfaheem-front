// lib/features/parent/parent_widgets.dart
// Small shared widgets / helpers for the Parent role screens (and the two admin parent-link pages).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

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
      return c.textLight;
    default:
      return c.warning; // pending
  }
}

AppTone _statusTone(String s) => switch (s) {
      'approved' => AppTone.success,
      'rejected' || 'failed' => AppTone.danger,
      'cancelled' => AppTone.neutral,
      _ => AppTone.warning, // pending
    };

/// The tone a child wears on every parent screen (the home's legacy card, the report's hero): stable per child, among
/// the category tones (peach / sky), so a parent learns each child's colour.
AppBlockTone parentChildTone(int childId) => AppBlockTone.forKey('child-$childId');

class PlStatusChip extends StatelessWidget {
  const PlStatusChip(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) => AppStatusBadge(label: 'pl_status_$status'.tr, tone: _statusTone(status), dot: true);
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
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: AppTouch.min + AppSpace.md,
            height: AppTouch.min + AppSpace.md,
            decoration: BoxDecoration(color: c.inputBg, shape: BoxShape.circle),
            child: Icon(icon, size: AppIconSize.xl, color: c.textMedium),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(text, textAlign: TextAlign.center, style: AppType.body(context)),
          if (action != null) ...[const SizedBox(height: AppSpace.md), action!],
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
    action: AppButton.primary(onPressed: onRetry, icon: Icons.refresh_rounded, label: 'pl_retry'.tr),
  );
}

/// A paper card (the kit's AppCard: the card surface on a warm hairline, no resting shadow) with the parent screens'
/// list spacing under it.
class PlCard extends StatelessWidget {
  const PlCard({super.key, required this.child, this.padding = AppSpace.card, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) =>
      AppCard(margin: const EdgeInsets.only(bottom: AppSpace.sm), padding: padding, onTap: onTap, child: child);
}

/// Shows an error from a provider as a toast (above sheets and dialogs); `error: false` for a success message.
void plToast(String? m, {bool error = true}) {
  if (m == null || m.isEmpty) return;
  Helpers.showMessage(m, isError: error);
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
        style: appFieldTextStyle(ctx),
        decoration: appFieldDecoration(ctx, hint: hint),
      ),
      actions: [
        AppButton.ghost(onPressed: () => Navigator.pop(ctx), label: 'pl_cancel'.tr),
        AppButton.primary(
          onPressed: () {
            if (required && ctrl.text.trim().length < 3) return;
            Navigator.pop(ctx, ctrl.text.trim());
          },
          label: 'pl_confirm'.tr,
        ),
      ],
    ),
  );
  ctrl.dispose();
  return res;
}
