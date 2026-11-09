// lib/design/app_side_sheet.dart — THE modal sheet of the app (D-360).
//
// From Breakpoints.mobile up it is a floating panel that slides in from the END side (left in Arabic) over a scrim.
// Below that it is a rounded sheet from the bottom that survives the keyboard.
//
//   showAppSheet(context, (ctx) => AppSheetContent(title: …, children: […]))   the normal way (app_kit.dart)
//   showAppModalSheet(context: context, builder: …)                            the same arguments as
//       showModalBottomSheet, for a builder that draws its own content
//
// A sheet opens on the nearest Navigator, as showModalBottomSheet did, so providers scoped to a shell tab stay
// readable from inside it. Close it with `Navigator.pop(ctx, value)`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_responsive.dart';
import 'app_tokens.dart';

/// Whether a sheet at this window width is a side panel.
bool appSheetIsSide(BuildContext context) => MediaQuery.sizeOf(context).width >= Breakpoints.mobile;

/// The side panel's width in a window [screen] wide.
double appSideSheetWidth(double screen, {double preferred = 520}) =>
    preferred.clamp(320.0, (screen - AppSpace.xxl).clamp(320.0, double.infinity)).toDouble();

/// Opens [builder]'s content as a side panel on wide windows and a bottom sheet on phones.
Future<T?> showAppSideSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double width = 520,
  bool dismissible = true,
  bool withCloseBar = false,
  bool useRootNavigator = false,
  RouteSettings? routeSettings,
}) {
  if (!appSheetIsSide(context)) {
    return _showPhoneSheet<T>(context, builder, dismissible: dismissible, useRootNavigator: useRootNavigator, routeSettings: routeSettings);
  }
  final rtl = Directionality.of(context) == TextDirection.rtl;
  final motion = AppMotion.of(context);
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    barrierDismissible: dismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: context.colors.isDark ? 0.6 : 0.4),
    transitionDuration: motion.slow,
    pageBuilder: (ctx, _, _) => AppSideSheetFrame(width: width, withCloseBar: withCloseBar, builder: builder),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: AppMotion.curve, reverseCurve: Curves.easeInCubic);
      return SlideTransition(
        position: Tween<Offset>(begin: Offset(rtl ? -0.6 : 0.6, 0), end: Offset.zero).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

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
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
      child: FocusScope(
        autofocus: true,
        child: FocusTraversalGroup(
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
                      child: Semantics(
                        scopesRoute: true,
                        explicitChildNodes: true,
                        child: MediaQuery.removeViewInsets(
                          context: context,
                          removeBottom: true,
                          child: MediaQuery.removePadding(
                            context: context,
                            removeTop: true,
                            removeBottom: true,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              if (withCloseBar) const _CloseBar(),
                              Flexible(child: Builder(builder: builder)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
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
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.close_rounded, size: AppIconSize.lg, color: context.colors.textMedium),
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
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: AppSpace.xxl - AppSpace.xxs,
                height: AppSpace.xxs,
                margin: const EdgeInsets.only(top: AppSpace.sm),
                decoration: BoxDecoration(color: ctx.colors.divider, borderRadius: BorderRadius.circular(AppSpace.xxs)),
              ),
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

/// [showModalBottomSheet]'s arguments, drawn as the app's sheet. On phones it IS a modal bottom sheet (the builder's
/// own look is kept), on wide windows the side panel with a close button.
Future<T?> showAppModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
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
  if (appSheetIsSide(context)) {
    return showAppSideSheet<T>(
      context,
      builder: builder,
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
    backgroundColor: backgroundColor,
    barrierColor: barrierColor,
    elevation: elevation,
    shape: shape ?? const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
    clipBehavior: clipBehavior,
    constraints: constraints,
    routeSettings: routeSettings,
  );
}
