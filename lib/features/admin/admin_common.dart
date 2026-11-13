// lib/features/admin/admin_common.dart
//
// Small shared helpers + widgets for the admin dashboard.
// Uses ONLY things that already exist in the app:
//   • ApiClient / BaseProvider          (core/)
//   • context.colors (ThemeConfigX)     (config/theme/theme_config_provider.dart)
//   • AppConfig.lang                    (config/app_config.dart)
//   • Helpers.showMessage / pageDirection (utils/helpers.dart)
library;

import 'package:flutter_education_app/design/app_side_sheet.dart';
import 'package:flutter_education_app/design/app_sheet_header.dart';
export 'package:flutter_education_app/design/app_badges.dart' show AppTone;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/master_detail/entity_chip.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/utils/widget/view_as_state.dart';

import 'admin_premium_widgets.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_search_field.dart';
import 'package:flutter_education_app/design/app_blocks.dart';
import 'package:flutter_education_app/design/app_buttons.dart';
import 'package:flutter_education_app/design/app_inputs.dart';
import 'package:flutter_education_app/design/app_states.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';


/// How long every admin search box waits after the LAST keystroke before it
/// sends a request. Change it here to change all of them.
const Duration kSearchDelay = Duration(milliseconds: 400);

/// Runs [run] only after [delay] of silence: every new call cancels the pending
/// one, so typing "ahmed" sends ONE request (400 ms after the last letter), not five.
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
          margin: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
          backgroundColor: (error ? AdminPalette.rose : AdminPalette.green).last,
          content: Row(children: [
            Icon(error ? Icons.error_rounded : Icons.check_circle_rounded,
                color: AdminPalette.ink, size: AppIconSize.md),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Text(message,
                  style: TextStyle(
                      fontFamily: AppFonts.family, color: AdminPalette.ink, fontWeight: FontWeight.w600)),
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

/// THE money formatter: Latin digits with thousands separators ("12,480", "1,234.50"), two decimals only when the
/// amount has a fraction, then the currency code when given.
String money(num v, [String? currency]) {
  final fixed = v.abs().toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
  final dot = fixed.indexOf('.');
  final intPart = dot < 0 ? fixed : fixed.substring(0, dot);
  final frac = dot < 0 ? '' : fixed.substring(dot);
  final grouped = intPart.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  final neg = v < 0 && fixed.replaceAll(RegExp(r'[0.]'), '').isNotEmpty ? '-' : '';
  final s = '$neg$grouped$frac';
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

/// The confirm dialog's mark (54 px: a 48 px target plus its own breathing room, test/org/omr_r2_ui_test.dart).
const double _confirmMark = AppTouch.min + AppSpace.xxs + 2;

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
        insetPadding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.lg),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet)),
        // centred: a scrollable dialog stretches its icon slot, which drew the badge as a full-width bar; the theme's
        // primary (AdminPalette.blue is the success gradient, off-theme in most palettes)
        icon: Center(
          child: ServiceIcon(
            icon: danger ? Icons.warning_amber_rounded : Icons.help_outline_rounded,
            colors: danger ? AdminPalette.rose : [c.primaryLight, c.primary],
            size: _confirmMark,
          ),
        ),
        content: Text(message, textAlign: TextAlign.center, style: AppType.body(ctx).copyWith(height: 1.5)),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(AppSpace.xxxl * 2, AppTouch.min),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.controlAll),
              side: BorderSide(color: c.divider),
            ),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('exam_cancel'.tr, style: AppType.label(ctx).copyWith(color: c.textMedium)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(AppSpace.xxxl * 2, AppTouch.min),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.controlAll),
              backgroundColor: danger ? c.danger : c.primary,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel ?? 'confirm'.tr,
                style: AppType.label(ctx).copyWith(color: c.onHero, fontWeight: FontWeight.w600)),
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
        insetPadding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.lg),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet)),
        title: Text(widget.title, style: AppType.headline(context)),
        content: TextField(
          controller: _ctrl,
          autofocus: true,
          maxLines: widget.multiline ? 4 : 1,
          // Enter answers (a multi-line box: Ctrl+Enter on web / desktop, design/app_keyboard.dart)
          onSubmitted: (_) => Navigator.pop(context, _ctrl.text.trim()),
          style: appFieldTextStyle(context),
          decoration: appFieldDecoration(context, hint: widget.hint),
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

/// The app's sheet (D-710): a content-sized dialog on wide windows, a bottom sheet on phones, the full-height side
/// panel with [AppSheetMode.side] (editors and detail panels only). Survives the keyboard.
Future<T?> showAdminSheet<T>(BuildContext context, WidgetBuilder builder, {AppSheetMode mode = AppSheetMode.auto, double? width}) =>
    showAppSideSheet<T>(context,
        mode: mode, width: width, builder: (ctx) => Directionality(textDirection: dir, child: Builder(builder: builder)));

// ── small widgets ────────────────────────────────────────────────────────────

/// The admin pages' sheet header: the kit's [AppSheetHeader] (a tinted band in [tone], an optional [icon]).
class SheetHeader extends StatelessWidget {
  const SheetHeader(this.title, {super.key, this.trailing, this.tone = AppTone.brand, this.icon, this.subtitle});
  final String title;
  final Widget? trailing;
  final AppTone tone;
  final IconData? icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => AppSheetHeader(title,
      trailing: trailing, tone: tone, icon: icon, subtitle: subtitle, closeTooltip: t('إغلاق', 'Close'));
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, this.color, {super.key});
  final String label;
  final Color color;

  /// A full pill on an opaque tint of [color]; the label keeps AA on it and ellipsizes instead of clipping.
  @override
  Widget build(BuildContext context) {
    final tint = Color.alphaBlend(color.withValues(alpha: 0.14), context.colors.cardBg);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs / 2),
      decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.overline(context).copyWith(color: context.colors.blockAccentInk(color, tint))),
    );
  }
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

  /// Optional icon shown before the title, in a faint well of [colors]' base tone.
  final IconData? icon;
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Paper on a warm hairline, no resting shadow (D-612). Material (not a decorated Container) so ListTile /
    // SwitchListTile children paint their background + ink splash on it.
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Material(
        color: c.cardBg,
        clipBehavior: Clip.antiAlias, // keeps splashes inside the rounded corners
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: BorderSide(color: c.divider, width: AppBorder.hairline),
        ),
        child: Padding(
          padding: AppSpace.card,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // the trailing widget keeps its own width up to half the row (a long status ellipsizes, never overflows)
            LayoutBuilder(
              builder: (context, box) => Row(children: [
                if (icon != null) ...[
                  ServiceIcon(icon: icon!, colors: colors ?? AdminPalette.blue, size: AppIconSize.hero),
                  const SizedBox(width: AppSpace.sm),
                ],
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpace.xs),
                  ConstrainedBox(constraints: BoxConstraints(maxWidth: box.maxWidth / 2), child: trailing!),
                ],
              ]),
            ),
            const SizedBox(height: AppSpace.sm),
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

  /// The key column: room for "Created at" at 12 px beside a value.
  static const double _keyWidth = AppSpace.xxxl + AppSpace.xxl - AppSpace.xxs / 2;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: _keyWidth,
          child: Text(k, style: AppType.meta(context).copyWith(color: c.textLight)),
        ),
        Expanded(child: Text(v.isEmpty ? '—' : v, style: AppType.row(context).copyWith(color: c.textDark))),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {super.key, this.icon = Icons.inbox_rounded});
  final String message;
  final IconData icon;

  /// The kit's drawn plate with the message as its one line (scrolls when the slot is short).
  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AppStatePlate(icon: icon, tone: AppBlockTone.sky, size: AppSpace.xxxl + AppSpace.xl),
            const SizedBox(height: AppSpace.md),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: AppWidth.form.max),
              child: Text(message,
                  textAlign: TextAlign.center,
                  style: AppType.body(context).copyWith(height: 1.5, color: context.colors.textMedium)),
            ),
          ]),
        ),
      );
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
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppStatePlate(
              icon: Icons.cloud_off_rounded, tone: AppBlockTone.peach, accent: c.danger, size: AppSpace.xxxl + AppSpace.xl),
          const SizedBox(height: AppSpace.md),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: AppWidth.form.max),
            child: Text(message,
                textAlign: TextAlign.center, style: AppType.body(context).copyWith(height: 1.5, color: c.textMedium)),
          ),
          const SizedBox(height: AppSpace.md),
          AppButton.primary(label: 'retry'.tr, icon: Icons.refresh_rounded, onPressed: onRetry),
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
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboard,
        obscureText: obscure,
        maxLines: obscure ? 1 : maxLines,
        textDirection: ltr ? TextDirection.ltr : null,
        validator: validator,
        style: appFieldTextStyle(context),
        // the kit's well (warm fill, radius 14, hairline, the 2 px focus ring); the label stays inside the well so the
        // many admin forms keep their compact rhythm
        decoration: appFieldDecoration(context, hint: hint, enabled: enabled).copyWith(
          labelText: label,
          labelStyle: AppType.label(context).copyWith(color: c.textMedium),
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
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: AppFieldLabel(label!),
          ),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final e in options.entries)
            ChoiceChip(
              label: Text(e.value, style: AppType.label(context).copyWith(color: e.key == value ? c.onHero : c.textDark)),
              selected: e.key == value,
              showCheckmark: false,
              selectedColor: c.primary,
              backgroundColor: c.inputBg,
              side: BorderSide(color: e.key == value ? c.primary : c.divider),
              shape: const StadiumBorder(),
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
  String _sent = '';

  void _send(String v) {
    final q = v.trim();
    if (!mounted || q == _sent) return; // nothing new -> no request
    _sent = q;
    widget.onChanged(q);
  }

  @override
  Widget build(BuildContext context) =>
      AppSearchField(hint: widget.hint ?? 'admin_search'.tr, debounce: kSearchDelay, onChanged: _send);
}

/// A student / teacher / course named by an admin row, as a link to its detail (`{id, name}` or `{id, name_ar,
/// name_en}`, D-290); the row keeps its own tap. A dash when the row has none.
Widget adminEntityCell(BuildContext context, EntityKind kind, Object? json) {
  final j = asMap(json);
  final id = asInt(j['id']);
  if (id <= 0) return Text('—', style: AppType.row(context));
  return EntityChip(EntityRef(kind, id,
      label: asStrOrNull(j['name']) ?? asStrOrNull(j['name_ar']),
      labelEn: asStrOrNull(j['name_en']),
      imageUrl: asStrOrNull(j['image_url'])));
}
