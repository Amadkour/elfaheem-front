// lib/design/app_side_sheet.dart — THE modal sheet of the app (D-360, restyled for the editorial theme D-612,
// sized to its content D-710).
//
// Where a sheet opens is its [AppSheetMode]:
//   auto    (the default) phones: a paper sheet from the bottom (radius 28, a drag handle, survives the keyboard);
//           from Breakpoints.mobile up: a centred paper dialog. Both size to their content (at most 85 % of the
//           window on wide screens, 92 % on phones) and scroll inside once they reach it.
//   side    a full-height floating panel from the END side (left in Arabic) on wide windows, the bottom sheet on
//           phones. ONLY for real detail / editor panels (a long form, a record viewer): two buttons in a
//           full-height panel was the bug D-710 fixed.
//   dialog  the centred dialog on every width.
//   bottom  the bottom sheet on every width (at most 640 wide).
//
//   showAppSheet(context, (ctx) => AppSheetContent(title: …, tone: …, children: […]))   the normal way (app_kit)
//   showAppSheet(context, builder, mode: AppSheetMode.side)                              an editor panel
//   showAppModalSheet(context: context, builder: …)                            the same arguments as
//       showModalBottomSheet, for a builder that draws its own content
//   appScrimColor(context)                                                     the scrim of every overlay: the
//       theme's warm shadow tone, never a neutral black
//
// A sheet opens on the nearest Navigator, as showModalBottomSheet did, so providers scoped to a shell tab stay
// readable from inside it. Close it with `Navigator.pop(ctx, value)`.
//
// Motion (D-621): the phone sheet rises in 280 ms on the iOS sheet curve and leaves in 200 ms (`AppEase.sheet`); a
// drag follows the finger, can catch the sheet while it is still moving, settles on the same curve from where it was
// let go, and a fast fling down (or a drop past half) dismisses it. The side panel slides in 280 ms on `AppEase.out`
// and leaves in about 200 ms; the dialog fades and grows from 96 % in 220 ms. Reduce motion: no slide or growth
// (the drag itself still follows the finger).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_motion_kit.dart' show AppEase;
import 'app_responsive.dart';
import 'app_tokens.dart';

/// Whether a sheet at this window width is a side panel.
bool appSheetIsSide(BuildContext context) => MediaQuery.sizeOf(context).width >= Breakpoints.mobile;

/// The side panel's width in a window [screen] wide.
double appSideSheetWidth(double screen, {double preferred = 520}) =>
    preferred.clamp(320.0, (screen - AppSpace.xxl).clamp(320.0, double.infinity)).toDouble();

/// The scrim under every sheet, drawer and dialog (system.md §4): the theme's warm shadow tone (`card_shadow_color`,
/// charcoal) at 42 %, 64 % in dark mode — never a neutral black over the warm canvas.
Color appScrimColor(BuildContext context) {
  final c = context.colors;
  return c.shadowTone.withValues(alpha: c.isDark ? 0.64 : 0.42);
}

/// Where a sheet opens (see the file header).
enum AppSheetMode { auto, dialog, side, bottom }

/// The concrete place [mode] opens at this window width: [AppSheetMode.dialog], [AppSheetMode.side] or
/// [AppSheetMode.bottom] (never auto).
AppSheetMode appSheetPlacement(BuildContext context, AppSheetMode mode) {
  final wide = appSheetIsSide(context);
  return switch (mode) {
    AppSheetMode.auto => wide ? AppSheetMode.dialog : AppSheetMode.bottom,
    AppSheetMode.side => wide ? AppSheetMode.side : AppSheetMode.bottom,
    AppSheetMode.dialog => AppSheetMode.dialog,
    AppSheetMode.bottom => AppSheetMode.bottom,
  };
}

/// The dialog's preferred width.
const double appSheetDialogWidth = 560;

/// The share of the window's height a dialog sheet may take before its content scrolls.
const double appSheetDialogMaxHeight = 0.85;

/// Opens [builder]'s content as the app's sheet: a content-sized dialog on wide windows and a bottom sheet on
/// phones by default, the full-height side panel with [AppSheetMode.side]. [width] is the dialog's or the panel's
/// preferred width (560 / 520).
Future<T?> showAppSideSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  AppSheetMode mode = AppSheetMode.auto,
  double? width,
  bool dismissible = true,
  bool withCloseBar = false,
  bool useRootNavigator = false,
  RouteSettings? routeSettings,
}) {
  final place = appSheetPlacement(context, mode);
  if (place == AppSheetMode.bottom) {
    return _showPhoneSheet<T>(context, builder, dismissible: dismissible, useRootNavigator: useRootNavigator, routeSettings: routeSettings);
  }
  final motion = AppMotion.of(context);
  if (place == AppSheetMode.dialog) {
    return showGeneralDialog<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
      barrierDismissible: dismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: appScrimColor(context),
      transitionDuration: motion.off ? Duration.zero : _dialogIn,
      pageBuilder: (ctx, _, _) =>
          AppDialogSheetFrame(width: width ?? appSheetDialogWidth, withCloseBar: withCloseBar, builder: builder),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: AppEase.out, reverseCurve: _dialogOut);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween<double>(begin: 0.96, end: 1).animate(curved), child: child),
        );
      },
    );
  }
  final rtl = Directionality.of(context) == TextDirection.rtl;
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    barrierDismissible: dismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: appScrimColor(context),
    transitionDuration: motion.off ? Duration.zero : _sideIn,
    pageBuilder: (ctx, _, _) => AppSideSheetFrame(width: width ?? 520, withCloseBar: withCloseBar, builder: builder),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: AppEase.out, reverseCurve: _sideOut);
      return SlideTransition(
        position: Tween<Offset>(begin: Offset(rtl ? -0.6 : 0.6, 0), end: Offset.zero).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

const Duration _dialogIn = Duration(milliseconds: 220);
const Curve _dialogOut = Interval(1 - 160 / 220, 1, curve: AppEase.outReversed);

/// The centred dialog sheet: a paper card [width] wide (never wider than the window less its gutters) that takes
/// its content's height up to [appSheetDialogMaxHeight] of the window. Public so a layout test can pump it.
class AppDialogSheetFrame extends StatelessWidget {
  const AppDialogSheetFrame({super.key, required this.width, required this.builder, this.withCloseBar = false});

  final double width;
  final WidgetBuilder builder;
  final bool withCloseBar;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.sheet);
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return _SheetScope(
      child: LayoutBuilder(builder: (context, box) {
        final gutter = box.maxWidth < Breakpoints.mobile ? AppSpace.md : AppSpace.lg;
        final w = width.clamp(0.0, (box.maxWidth - 2 * gutter).clamp(0.0, double.infinity)).toDouble();
        final room = (box.maxHeight - insets - 2 * AppSpace.lg).clamp(0.0, double.infinity).toDouble();
        final cap = box.maxHeight * appSheetDialogMaxHeight;
        final h = room < cap ? room : cap;
        return Padding(
          padding: EdgeInsets.only(bottom: insets),
          child: Center(
            child: ConstrainedBox(
              key: const ValueKey('app.dialog_sheet.panel'),
              constraints: BoxConstraints(minWidth: w, maxWidth: w, maxHeight: h),
              child: DecoratedBox(
                decoration: BoxDecoration(borderRadius: radius, boxShadow: AppElevation.of(context, 4)),
                child: Material(
                  color: c.cardBg,
                  surfaceTintColor: Colors.transparent,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.divider, width: AppBorder.hairline)),
                  child: _SheetBody(withCloseBar: withCloseBar, builder: builder, fill: false),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Esc closes, focus stays inside.
class _SheetScope extends StatelessWidget {
  const _SheetScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
        child: FocusScope(autofocus: true, child: FocusTraversalGroup(child: child)),
      );
}

/// The content of a dialog or side sheet: no view insets (the frame already lifted itself), no system padding, and
/// the optional close bar over [builder]'s content. [fill]: the column takes the whole height (the side panel).
class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.withCloseBar, required this.builder, required this.fill});

  final bool withCloseBar;
  final WidgetBuilder builder;
  final bool fill;

  @override
  Widget build(BuildContext context) => Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        child: MediaQuery.removeViewInsets(
          context: context,
          removeBottom: true,
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            removeBottom: true,
            child: Column(
              mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (withCloseBar) const _CloseBar(),
                Flexible(child: Builder(builder: builder)),
              ],
            ),
          ),
        ),
      );
}

/// The side panel's entrance. A dialog route has one duration both ways, so the exit is made faster by its curve:
/// it reaches the closed place after the first 200 ms of the 280 and rests there.
const Duration _sideIn = Duration(milliseconds: 280);
const Curve _sideOut = Interval(1 - 200 / 280, 1, curve: AppEase.outReversed);

/// The floating panel. Public so a layout test can pump it on its own.
class AppSideSheetFrame extends StatelessWidget {
  const AppSideSheetFrame({super.key, required this.width, required this.builder, this.withCloseBar = false});

  final double width;
  final WidgetBuilder builder;
  final bool withCloseBar;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.sheet);
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return _SheetScope(
      child: LayoutBuilder(builder: (context, box) {
        return Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, AppSpace.sm, AppSpace.sm + insets),
            child: SizedBox(
              key: const ValueKey('app.side_sheet.panel'),
              width: appSideSheetWidth(box.maxWidth - AppSpace.lg, preferred: width),
              child: DecoratedBox(
                decoration: BoxDecoration(borderRadius: radius, boxShadow: AppElevation.of(context, 4)),
                child: Material(
                  color: c.cardBg,
                  surfaceTintColor: Colors.transparent,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: radius,
                    side: BorderSide(color: c.divider, width: AppBorder.hairline),
                  ),
                  child: _SheetBody(withCloseBar: withCloseBar, builder: builder, fill: true),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _CloseBar extends StatelessWidget {
  const _CloseBar();

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xxs),
          child: IconButton(
            tooltip: 'close'.tr,
            constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
            style: IconButton.styleFrom(backgroundColor: context.colors.inputBg),
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.close_rounded, size: AppIconSize.md, color: context.colors.textMedium),
          ),
        ),
      );
}

/// The phone sheet's grab bar: a short pill in muted ink, centred under the sheet's top edge. Pointer only (the
/// header's close button and the scrim are the accessible ways out), so it stays out of the semantics tree.
class AppSheetDragHandle extends StatelessWidget {
  const AppSheetDragHandle({super.key});

  static const double width = AppSpace.xl + AppSpace.xxs;
  static const double height = AppSpace.xxs;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpace.sm, bottom: AppSpace.xxs),
          child: SizedBox(
            width: width,
            height: height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.colors.textLight.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          ),
        ),
      );
}

Future<T?> _showPhoneSheet<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool dismissible = true,
  bool useRootNavigator = false,
  RouteSettings? routeSettings,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    sheetAnimationStyle: appSheetAnimationStyle(context),
    barrierColor: appScrimColor(context),
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      // The height left ABOVE the keyboard (not the screen height): with the keyboard open a
      // `size.height * 0.92` box was taller than the space and the sheet overflowed.
      child: LayoutBuilder(
        builder: (ctx, box) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: box.maxHeight.isFinite
                ? box.maxHeight * (MediaQuery.viewInsetsOf(ctx).bottom > 0 ? 1 : 0.92)
                : MediaQuery.sizeOf(ctx).height * 0.92,
          ),
          // A Material (not a coloured Container): ListTiles inside paint their tileColor / ink on the nearest Material.
          child: Material(
            color: ctx.colors.cardBg,
            surfaceTintColor: Colors.transparent,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.sheetTop,
              // the warm scrim carries the depth; dark mode adds the hairline a floating surface wears there
              side: AppElevation.border(ctx, 4)?.top ?? BorderSide.none,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const AppSheetDragHandle(),
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
        ),
      ),
    ),
  );
}

/// The phone sheet's motion (D-621): [AppEase.sheet], or none under Reduce motion.
AnimationStyle appSheetAnimationStyle(BuildContext context) =>
    AppMotion.of(context).off ? AnimationStyle.noAnimation : AppEase.sheet;

/// [showModalBottomSheet]'s arguments, drawn as the app's sheet. On phones it IS a modal bottom sheet (the builder's
/// own look is kept; the sheet's corners, scrim and motion are the kit's unless the caller passes its own), on wide
/// windows the content-sized dialog with a close button ([mode] as in [showAppSideSheet]).
Future<T?> showAppModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  AppSheetMode mode = AppSheetMode.auto,
  bool isDismissible = true,
  bool enableDrag = true,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool useRootNavigator = false,
  bool? showDragHandle,
  Color? backgroundColor,
  Color? barrierColor,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  RouteSettings? routeSettings,
}) {
  if (appSheetPlacement(context, mode) != AppSheetMode.bottom) {
    return showAppSideSheet<T>(
      context,
      builder: builder,
      mode: mode,
      dismissible: isDismissible,
      withCloseBar: true,
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    useRootNavigator: useRootNavigator,
    showDragHandle: showDragHandle,
    sheetAnimationStyle: appSheetAnimationStyle(context),
    backgroundColor: backgroundColor,
    barrierColor: barrierColor ?? appScrimColor(context),
    elevation: elevation,
    shape: shape ?? const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
    clipBehavior: clipBehavior,
    constraints: constraints,
    routeSettings: routeSettings,
  );
}
