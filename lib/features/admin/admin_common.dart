// lib/features/admin/admin_common.dart
//
// Small shared helpers + widgets for the admin dashboard.
// Uses ONLY things that already exist in the app:
//   • ApiClient / BaseProvider          (core/)
//   • context.colors (ThemeConfigX)     (config/theme/theme_config_provider.dart)
//   • AppConfig.lang                    (config/app_config.dart)
//   • Helpers.showMessage / pageDirection (utils/helpers.dart)
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/utils/widget/view_as_state.dart';

import 'admin_premium_widgets.dart';
import 'package:flutter_education_app/design/app_notice.dart';


/// How long every admin search box waits after the LAST keystroke before it
/// sends a request. Change it here to change all of them.
const Duration kSearchDelay = Duration(seconds: 1);

/// Runs [run] only after [delay] of silence: every new call cancels the pending
/// one, so typing "ahmed" sends ONE request (1 s after the last letter), not five.
/// [flush] runs it now (Enter key / clear button); always [dispose] it.
class Debouncer {
  Debouncer([this.delay = kSearchDelay]);

  final Duration delay;
  Timer? _t;

  bool get isPending => _t?.isActive ?? false;

  void run(VoidCallback action) {
    _t?.cancel();
    _t = Timer(delay, action);
  }

  void flush(VoidCallback action) {
    _t?.cancel();
    action();
  }

  void cancel() => _t?.cancel();

  void dispose() => _t?.cancel();
}

/// Arabic / English inline text (the admin screens ship with both).
String t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// Translates [key] with `.tr`, then fills `{name}` placeholders from [params].
String trp(String key, Map<String, Object?> params) {
  var s = key.tr;
  params.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
  return s;
}

TextDirection get dir => Helpers.pageDirection;

/// True for a super-admin who is NOT currently "viewing as" a plain admin.
/// While viewing as an admin the server treats the session as that admin, so
/// the super-only UI (Admins, view-as buttons) must disappear too.
bool isSuperNow(BuildContext context) =>
    context.read<MyAuthProvider>().isSuper &&
        !(ViewAsState.active && ViewAsState.instance.role == 'admin');

// ── toast ────────────────────────────────────────────────────────────────────

/// Global messenger key. Put it on the app's MaterialApp:
///     MaterialApp(scaffoldMessengerKey: rootMessengerKey, ...)
/// Snackbars shown through it never depend on a widget BuildContext, so they
/// are safe to show after a dialog / bottom sheet has already closed (the cause
/// of "Looking up a deactivated widget's ancestor is unsafe").
final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
GlobalKey<ScaffoldMessengerState>();

void toast(String message, {bool error = false}) {
  // 0) above EVERY route (sheets / dialogs included) — a SnackBar sat behind open overlays
  if (showAppNotice(message, error: error)) return;
  // 1) fallback: the app-level messenger (no BuildContext involved)
  final messenger = rootMessengerKey.currentState;
  if (messenger != null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: (error ? AdminPalette.rose : AdminPalette.green).last,
          content: Row(children: [
            Icon(error ? Icons.error_rounded : Icons.check_circle_rounded,
                color: AdminPalette.ink, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: TextStyle(
                      fontFamily: 'tajawal', color: AdminPalette.ink, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      );
    return;
  }
  // 2) fallback: the old helper, but never let a stale context crash the caller
  try {
    Helpers.showMessage(message, isError: error);
  } catch (e) {
    debugPrint('toast skipped (stale context): $message');
  }
}

String money(num v, [String? currency]) {
  final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  return currency == null || currency.isEmpty ? s : '$s $currency';
}

/// "2026-10-28". A UTC instant ("…Z" / an offset) is shown on the platform / organization's calendar (AppTime);
/// a naive string (a picked local date, a calendar day) is shown as it is, never shifted.
String shortDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso);
  if (d == null) return '—';
  final l = d.isUtc ? AppTime.toZone(d) : d;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)}';
}

/// "2026-10-28 2:05 PM" — the AppTime zone and its 12h / 24h choice.
String shortDateTime(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso);
  if (d == null) return '—';
  final l = d.isUtc ? AppTime.toZone(d) : d;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${AppTime.clockMinutes(l.hour * 60 + l.minute)}';
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
        // long messages / big text scale / 320 px: scroll inside the dialog instead of overflowing
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: ServiceIcon(
          icon: danger ? Icons.warning_amber_rounded : Icons.help_outline_rounded,
          colors: danger ? AdminPalette.rose : AdminPalette.blue,
          size: 54,
        ),
        content: Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'tajawal', height: 1.5)),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(110, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              side: BorderSide(color: c.divider),
            ),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('exam_cancel'.tr,
                style: TextStyle(fontFamily: 'tajawal', color: c.textMedium)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(110, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              backgroundColor: danger ? c.danger : c.primary,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel ?? 'confirm'.tr,
                style: TextStyle(
                    fontFamily: 'tajawal', color: c.onHero, fontWeight: FontWeight.w800)),
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
    }) {
  return showDialog<String>(
    context: context,
    builder: (_) => _AskTextDialog(
      title: title,
      hint: hint,
      multiline: multiline,
    ),
  );
}

/// The controller lives in this State, so it is disposed only after the dialog's
/// closing animation has finished (disposing right after showDialog returns
/// caused "TextEditingController was used after being disposed").
class _AskTextDialog extends StatefulWidget {
  const _AskTextDialog({
    required this.title,
    required this.hint,
    required this.multiline,
  });

  final String title;
  final String? hint;
  final bool multiline;

  @override
  State<_AskTextDialog> createState() => _AskTextDialogState();
}

class _AskTextDialogState extends State<_AskTextDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: dir,
      child: AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(widget.title,
            style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800)),
        content: TextField(
          controller: _ctrl,
          autofocus: true,
          maxLines: widget.multiline ? 4 : 1,
          // Enter answers (a multi-line box: Ctrl+Enter on web / desktop, design/app_keyboard.dart)
          onSubmitted: (_) => Navigator.pop(context, _ctrl.text.trim()),
          style: const TextStyle(fontFamily: 'tajawal'),
          decoration: InputDecoration(
            hintText: widget.hint,
            filled: true,
            fillColor: context.colors.inputBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.colors.divider),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('exam_cancel'.tr)),
          TextButton(
              onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
              child: Text('admin_ok'.tr)),
        ],
      ),
    );
  }
}

/// Full-height modal sheet that survives the keyboard.
Future<T?> showAdminSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (ctx) => Directionality(
      textDirection: dir,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        // The height left ABOVE the keyboard (not the screen height): with the keyboard open a
        // `size.height * 0.92` box was taller than the space and the sheet overflowed.
        child: LayoutBuilder(builder: (ctx, box) => ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: box.maxHeight.isFinite
                  ? box.maxHeight * (MediaQuery.viewInsetsOf(ctx).bottom > 0 ? 1 : 0.92)
                  : MediaQuery.sizeOf(ctx).height * 0.92),
          // A Material (not a coloured Container): ListTiles inside paint their tileColor / ink on
          // the nearest Material. A coloured box in between hid them and made Flutter report
          // "ListTile background color or ink splashes may be invisible" for every tappable row.
          child: Material(
          color: ctx.colors.cardBg,
          surfaceTintColor: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // grab handle
            Container(
              width: 42,
              height: 5,
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: ctx.colors.divider,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            // bottom safe area: content never sits under the home indicator / gesture bar
            // The sheet is already lifted above the keyboard, so the content sees no view insets
            // (content that padded itself by viewInsets again got squeezed twice and overflowed).
            Flexible(
              child: MediaQuery.removeViewInsets(
                context: ctx,
                removeBottom: true,
                child: SafeArea(top: false, child: Builder(builder: builder)),
              ),
            ),
          ]),
          ),
        )),
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
      padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 12, 8),
      child: Row(children: [
        Expanded(
          child: Text(title,
              style: TextStyle(
                  fontFamily: 'tajawal',
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: c.textDark)),
        ),
        ?trailing,
        IconButton(tooltip: t('إغلاق', 'Close'), 
            style: IconButton.styleFrom(backgroundColor: c.inputBg),
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close_rounded, color: c.textMedium, size: 20)),
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
      border: Border.all(color: color.withValues(alpha: 0.28)),
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
  const Section({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.icon,
    this.colors,
  });
  final String title;
  final Widget child;
  final Widget? trailing;

  /// Optional gradient icon shown before the title (premium look).
  final IconData? icon;
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Material (not a decorated Container) so ListTile / SwitchListTile children
    // can paint their background + ink splash on it. A Container's own colour sits
    // between them and the Material ancestor and hides the effects (Flutter asserts).
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: c.cardShadow,
      ),
      child: Material(
        color: c.cardBg,
        clipBehavior: Clip.antiAlias, // keeps splashes inside the rounded corners
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: c.divider),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (icon != null) ...[
                ServiceIcon(icon: icon!, colors: colors ?? AdminPalette.blue, size: 36),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontFamily: 'tajawal',
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                        color: c.textDark)),
              ),
              ?trailing,
            ]),
            const SizedBox(height: 12),
            child,
          ]),
        ),
      ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.primary.withValues(alpha: 0.10),
            ),
            child: Icon(icon, size: 44, color: c.primary),
          ),
          const SizedBox(height: 14),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'tajawal', height: 1.5, color: c.textMedium)),
        ]),
      ),
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
    // scrolls when the space is short (a fixed-height slot, a phone in landscape, a large text scale)
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.danger.withValues(alpha: 0.10),
            ),
            child: Icon(Icons.cloud_off_rounded, size: 40, color: c.danger),
          ),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'tajawal', color: c.textMedium)),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: c.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
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
          labelStyle: TextStyle(fontFamily: 'tajawal', color: c.textMedium),
          filled: true,
          fillColor: c.inputBg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: c.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: c.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: c.primary, width: 1.6),
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
                      fontWeight: FontWeight.w700,
                      color: e.key == value ? c.onHero : c.textDark)),
              selected: e.key == value,
              showCheckmark: false,
              selectedColor: c.primary,
              backgroundColor: c.inputBg,
              side: BorderSide(color: e.key == value ? c.primary : c.divider),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
  final _debounce = Debouncer();
  String _sent = '';

  @override
  void dispose() {
    _debounce.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _send(String v) {
    final q = v.trim();
    if (!mounted || q == _sent) return; // nothing new → no request
    _sent = q;
    widget.onChanged(q);
  }

  void _changed(String v) {
    setState(() {}); // shows / hides the clear button
    _debounce.run(() => _send(v));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TextField(
      controller: _ctrl,
      onChanged: _changed,
      onSubmitted: (v) => _debounce.flush(() => _send(v)),
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontFamily: 'tajawal'),
      decoration: InputDecoration(
        hintText: widget.hint ?? 'admin_search'.tr,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _ctrl.text.isEmpty
            ? null
            : IconButton(tooltip: t('مسح', 'Clear'), 
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _ctrl.clear();
                  _debounce.flush(() => _send(''));
                  setState(() {});
                },
              ),
        filled: true,
        fillColor: c.inputBg,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: c.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: c.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: c.primary, width: 1.6),
        ),
      ),
    );
  }
}