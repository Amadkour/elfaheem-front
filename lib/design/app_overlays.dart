// lib/design/app_overlays.dart
//
// The overlays of the dashboards: a dialog, a side drawer and the "unsaved changes" guard. Every one of them is
// paper (cardBg) with the sheet radius (28), an editorial title, the warm scrim (`appScrimColor`) and the modal
// shadow in the theme's warm tone (D-612); the dialog settles in with `AppPopIn`, the drawer slides in from the end
// edge on `AppEase.out` (280 ms in, 200 ms out) like the side sheet.
//
//   showAppDialog(context, title:, body:, actions: [...], icon:, danger:)   centred, max 520 wide, modal elevation
//   showAppDrawer(context, title:, builder: (ctx) => form, actions: [Save]) slides in from the END edge (right in
//       LTR, left in RTL) from 700 px wide; phones get the same content in showAppSheet. Scrim, Esc, focus trapped.
//   appConfirmDiscard(context)                                              "Discard your changes?" -> true = discard
//   AppUnsavedGuard(dirty: _dirty, child: …)                                 asks before the page is left dirty
//
// Buttons in `actions` are plain widgets (FilledButton / TextButton …); close with `Navigator.pop(context, value)`
// from a Builder / the button's own context.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_kit.dart';
import 'app_motion_kit.dart';
import 'app_responsive.dart';

// ── Dialog ──────────────────────────────────────────────────────────────────

Future<T?> showAppDialog<T>(
  BuildContext context, {
  required String title,
  required Widget body,
  List<Widget> actions = const [],
  bool dismissible = true,
  IconData? icon,
  bool danger = false,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierColor: appScrimColor(context),
    builder: (ctx) => _AppDialog(title: title, body: body, actions: actions, icon: icon, danger: danger),
  );
}

/// The dialog's panel: paper, radius 28, the modal shadow, an editorial headline beside an optional icon in a
/// tinted square, the body in the body role, the actions at the end. Max 520 wide; long bodies scroll inside.
class _AppDialog extends StatelessWidget {
  const _AppDialog({required this.title, required this.body, required this.actions, this.icon, this.danger = false});

  final String title;
  final Widget body;
  final List<Widget> actions;
  final IconData? icon;
  final bool danger;

  /// The widest a dialog gets: a comfortable reading measure for a question and two buttons.
  static const double maxWidth = 520;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = danger ? c.danger : (c.isDark ? c.primaryLight : c.primary);
    final badge = danger ? c.dangerTint : c.primaryTint;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(AppSpace.md),
      child: AppPopIn(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sheet),
              boxShadow: AppElevation.of(context, 4),
            ),
            child: Material(
              color: c.cardBg,
              surfaceTintColor: Colors.transparent,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sheet),
                side: AppElevation.border(context, 4)?.top ?? BorderSide.none,
              ),
              child: Semantics(
                scopesRoute: true,
                explicitChildNodes: true,
                namesRoute: true,
                label: title,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      if (icon != null) ...[
                        SizedBox(
                          width: AppTouch.min - AppSpace.xs,
                          height: AppTouch.min - AppSpace.xs,
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: badge, borderRadius: AppRadius.controlAll),
                            child: Icon(icon, size: AppIconSize.lg, color: tint),
                          ),
                        ),
                        AppSpace.gapSm,
                      ],
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(title, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.headline(context)),
                        ),
                      ),
                    ]),
                    AppSpace.gapSm,
                    Flexible(
                      child: SingleChildScrollView(
                        child: DefaultTextStyle.merge(style: AppType.body(context), child: body),
                      ),
                    ),
                    if (actions.isNotEmpty) ...[
                      AppSpace.gapLg,
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, alignment: WrapAlignment.end, children: actions),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Drawer ──────────────────────────────────────────────────────────────────

/// The drawer's entrance: 280 ms on [AppEase.out]; the exit rests after its first 200 ms (a dialog route has one
/// duration both ways, so the reverse curve ends early).
const Duration _drawerIn = Duration(milliseconds: 280);
const Curve _drawerOut = Interval(1 - 200 / 280, 1, curve: AppEase.outReversed);

Future<T?> showAppDrawer<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext) builder,
  double width = 480,
  List<Widget>? actions,
}) {
  if (MediaQuery.sizeOf(context).width < Breakpoints.mobile) {
    return showAppSheet<T>(
      context,
      (ctx) => AppSheetContent(title: title, children: [
        builder(ctx),
        if (actions != null && actions.isNotEmpty) ...[
          AppSpace.gapMd,
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, alignment: WrapAlignment.end, children: actions),
        ],
      ]),
    );
  }
  final rtl = Directionality.of(context) == TextDirection.rtl;
  final label = MaterialLocalizations.of(context).modalBarrierDismissLabel;
  final motion = AppMotion.of(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: label,
    barrierColor: appScrimColor(context),
    transitionDuration: motion.off ? Duration.zero : _drawerIn,
    pageBuilder: (ctx, _, _) => _DrawerPanel(title: title, width: width, actions: actions, builder: builder),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: AppEase.out, reverseCurve: _drawerOut);
      return SlideTransition(
        position: Tween<Offset>(begin: Offset(rtl ? -0.6 : 0.6, 0), end: Offset.zero).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

/// The floating panel: paper, radius 28, a hairline and the modal shadow; an editorial headline with the close
/// button, the scrolling body, and the actions under a hairline when there are any.
class _DrawerPanel extends StatelessWidget {
  const _DrawerPanel({required this.title, required this.width, required this.builder, this.actions});

  final String title;
  final double width;
  final List<Widget>? actions;
  final Widget Function(BuildContext) builder;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final screen = MediaQuery.sizeOf(context).width;
    final w = width.clamp(0.0, screen - AppSpace.xxl).toDouble();
    final hasActions = actions != null && actions!.isNotEmpty;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
      child: FocusScope(
        autofocus: true,
        child: FocusTraversalGroup(
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: SizedBox(
                width: w,
                child: DecoratedBox(
                  key: const ValueKey('app.drawer.panel'),
                  decoration: BoxDecoration(
                    color: c.cardBg,
                    borderRadius: BorderRadius.circular(AppRadius.sheet),
                    boxShadow: AppElevation.of(context, 4),
                  ),
                  child: Material(
                    color: c.cardBg,
                    surfaceTintColor: Colors.transparent,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sheet),
                      side: BorderSide(color: c.divider, width: AppBorder.hairline),
                    ),
                    child: SafeArea(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.lg, AppSpace.md, AppSpace.sm, AppSpace.sm),
                          child: Row(children: [
                            Expanded(
                              child: Semantics(
                                header: true,
                                child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.headline(context)),
                              ),
                            ),
                            AppSpace.gapSm,
                            IconButton(
                              tooltip: 'close'.tr,
                              constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                              style: IconButton.styleFrom(backgroundColor: c.inputBg),
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: Icon(Icons.close_rounded, size: AppIconSize.md, color: c.textMedium),
                            ),
                          ]),
                        ),
                        Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(AppSpace.lg),
                            child: Builder(builder: builder),
                          ),
                        ),
                        if (hasActions) ...[
                          Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: c.divider),
                          Padding(
                            padding: const EdgeInsets.all(AppSpace.md),
                            child: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: Wrap(
                                  spacing: AppSpace.xs, runSpacing: AppSpace.xs, alignment: WrapAlignment.end, children: actions!),
                            ),
                          ),
                        ],
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Unsaved changes ─────────────────────────────────────────────────────────

/// "Discard your changes?" - true = leave and discard, false = keep editing (or dismissed).
Future<bool> appConfirmDiscard(BuildContext context) async {
  final r = await showAppDialog<bool>(
    context,
    title: 'ds_unsaved_title'.tr,
    icon: Icons.edit_note_rounded,
    body: Text('ds_unsaved_body'.tr),
    actions: [
      Builder(builder: (ctx) => TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
            child: Text('ds_keep_editing'.tr),
          )),
      Builder(builder: (ctx) => TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                minimumSize: const Size(AppTouch.min, AppTouch.min), foregroundColor: ctx.colors.danger),
            child: Text('ds_discard'.tr),
          )),
    ],
  );
  return r ?? false;
}

/// Wraps a form page: while [dirty], leaving it (back button, swipe, Esc) asks [appConfirmDiscard] first.
class AppUnsavedGuard extends StatelessWidget {
  const AppUnsavedGuard({super.key, required this.dirty, required this.child});

  final bool dirty;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !dirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final leave = await appConfirmDiscard(context);
          if (leave && context.mounted) Navigator.of(context).pop();
        },
        child: child,
      );
}
