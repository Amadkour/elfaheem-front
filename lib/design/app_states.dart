// lib/design/app_states.dart
//
// The three states every data screen has besides "data": failed, loading and empty (Warm Editorial, system.md).
//
//   AppErrorState(message: ApiException.from(e).message, onRetry: _load)      plate, editorial title, message, Retry
//   AppErrorState(compact: true, …)                                           the same as one inline row (in a card)
//   AppLoadingState(shape: AppLoadingShape.cards)                            skeletons of the page's shape, no spinner
//   AppEmpty(icon:, title:, message:, actionLabel:, onAction:)               an editorial headline, one action and a
//                                                                            drawn plate (AppStatePlate), no stock art
//   AppNeedsConnection(onRetry: _load)                                       a page that can not load offline (D-1351):
//                                                                            "needs a connection", never an error
//   AppStateView<T>(loading:, error:, data:, builder:, onRetry:)             THE switch between them
//
// AppStateView never wipes good data: when a refresh fails and data is already on screen, the data stays and a slim
// error banner sits above it. The skeleton shows only while there is no data yet. An error that is not an
// ApiException is never printed (its toString looks like a stack trace): the generic ds_error_body text is shown.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/offline/sync/offline_reads.dart' show needsConnectionText;

import 'app_area.dart';
import 'app_badges.dart';
import 'app_blocks.dart';
import 'app_buttons.dart';
import 'app_kit.dart' show AppListSkeleton, AppShimmer, AppSkeletonBox;
import 'app_motion_kit.dart';
import 'app_responsive.dart' show Breakpoints;
import 'app_tokens.dart';

/// The text to show for a failed load: an [ApiException]'s own (safe) message, else the generic one.
String appErrorMessage(Object? error) {
  if (error is ApiException && error.message.trim().isNotEmpty) return error.message;
  return 'ds_error_body'.tr;
}

// ─────────────────────────────────────────────────────────────────────────────
// The plate: the one drawn illustration of the empty and error states
// ─────────────────────────────────────────────────────────────────────────────

/// The plate of an empty or failed state (KIT_SPEC §5.9): a 120 × 96 tinted plate with three round corners and one
/// tight one ([AppRadius.plate]), the [icon] large in the matching ink. Under an area / role scope it takes the
/// scope's tint; otherwise the block [tone] (or [fill] / [ink] when given). It pops in once (AppPop) and is still
/// under Reduce motion.
class AppStatePlate extends StatelessWidget {
  const AppStatePlate({
    super.key,
    required this.icon,
    this.tone = AppBlockTone.peach,
    this.accent,
    this.size = 120,
    this.fill,
    this.ink,
  });

  final IconData icon;

  /// The plate's block tone when there is no area scope (a category keeps its tone).
  final AppBlockTone tone;

  /// The icon's colour (kept for existing callers; [ink] wins).
  final Color? accent;

  /// The plate's width; its height is 4 : 5 of it.
  final double size;

  /// The plate's fill and the icon's ink, when the caller knows them (error, offline).
  final Color? fill, ink;

  @override
  Widget build(BuildContext context) {
    final scoped = AppAreaScope.areaOf(context) != null || AppAreaScope.roleOf(context) != null;
    final Color bg;
    final Color fg;
    if (fill != null) {
      bg = fill!;
      fg = ink ?? accent ?? context.colors.textDark;
    } else if (scoped) {
      final set = AppAreaScope.of(context);
      bg = set.tint;
      fg = ink ?? set.ink;
    } else {
      final block = AppBlockColors.of(context, tone);
      bg = block.surface;
      fg = ink ?? (accent == null ? block.ink : appInkOn(context, accent!, block.surface));
    }
    return ExcludeSemantics(
      child: AppPop(
        group: 'plate',
        child: Container(
          width: size,
          height: size * 0.8,
          decoration: BoxDecoration(color: bg, borderRadius: AppRadius.plate),
          alignment: Alignment.center,
          child: Icon(icon, size: AppIconSize.hero, color: fg),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty
// ─────────────────────────────────────────────────────────────────────────────

/// An empty state with direction, not mood: the plate, an editorial headline, one line that says what to do, and
/// one action (shown only with both [actionLabel] and [onAction]).
class AppEmpty extends StatelessWidget {
  const AppEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.tone = AppBlockTone.peach,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// The plate's block tone (a category keeps its tone: `AppBlockTone.forKey(id)`).
  final AppBlockTone tone;

  /// The widest the message gets (a comfortable measure for a two-line sentence).
  static const double _measure = 300;

  @override
  Widget build(BuildContext context) => AppStateLayout(
        plate: AppStatePlate(icon: icon, tone: tone),
        title: title,
        message: message,
        action: actionLabel != null && onAction != null
            ? (bool phone) => AppButton.primary(label: actionLabel!, onPressed: onAction, expand: phone)
            : null,
        measure: _measure,
      );
}

/// The shared layout of the empty, error and success states (KIT_SPEC §5.9): the plate, the title in the section
/// role, the message in body text at most [measure] wide, and the one action: full width on phones, hugging its
/// label from 700 px. Centred in the free height; scrolls inside a box shorter than itself.
class AppStateLayout extends StatelessWidget {
  const AppStateLayout({
    super.key,
    required this.plate,
    required this.title,
    this.message,
    this.action,
    this.secondary,
    this.measure = 300,
    this.titleStyle,
  });

  final Widget plate;
  final String title;
  final String? message;

  /// Built with `phone` (true below 700 px).
  final Widget Function(bool phone)? action;
  final Widget? secondary;
  final double measure;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < Breakpoints.mobile;
    final msg = message;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: phone ? AppSpace.md : AppSpace.lg, vertical: AppSpace.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: phone ? double.infinity : AppWidth.form.max),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            plate,
            const SizedBox(height: AppSpace.lg),
            Text(title, textAlign: TextAlign.center, style: titleStyle ?? AppType.section(context)),
            if (msg != null && msg.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xs),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: measure),
                child: Text(msg, textAlign: TextAlign.center, style: AppType.body(context)),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpace.lg),
              phone ? SizedBox(width: double.infinity, child: action!(true)) : action!(false),
            ],
            if (secondary != null) ...[const SizedBox(height: AppSpace.xs), secondary!],
          ]),
        ),
      ),
    );
  }
}

/// A page whose data needs the server, opened offline or after the connection went (QA_PHASE7 W-4): the D-1351
/// sentence and Retry, never an error and never a skeleton that waits forever. Pick it with `isConnectionFailure(e)`.
class AppNeedsConnection extends StatelessWidget {
  const AppNeedsConnection({super.key, this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        container: true,
        child: AppStateLayout(
          key: const ValueKey('app.needsConnection'),
          plate: Builder(builder: (context) {
            final warn = context.colors.kit.warn;
            return AppStatePlate(icon: Icons.cloud_off_rounded, fill: warn.tint, ink: warn.ink);
          }),
          title: AppConfig.lang == 'ar' ? 'لا يوجد اتصال' : 'You are offline',
          message: needsConnectionText(),
          action: onRetry == null
              ? null
              : (phone) => AppButton.secondary(
                  label: AppConfig.lang == 'ar' ? 'أعد المحاولة' : 'Try again', onPressed: onRetry, expand: phone),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Error
// ─────────────────────────────────────────────────────────────────────────────

class AppErrorState extends StatelessWidget {
  const AppErrorState({super.key, this.title, this.message, this.onRetry, this.compact = false});

  /// Default: "Couldn't load this".
  final String? title;

  /// Pass `ApiException.from(e).message`. Default: "Check your connection and try again."
  final String? message;
  final VoidCallback? onRetry;

  /// One inline row for the inside of a card.
  final bool compact;

  /// The widest the text block gets.
  static const double _measure = 420;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final head = title ?? 'ds_error_title'.tr;
    final body = message ?? 'ds_error_body'.tr;
    if (compact) {
      final tint = appTintOn(context, c.danger);
      return Semantics(
        liveRegion: true,
        container: true,
        child: Container(
          padding: const EdgeInsetsDirectional.only(
              start: AppSpace.sm, end: AppSpace.xxs, top: AppSpace.xxs, bottom: AppSpace.xxs),
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          decoration: BoxDecoration(
            color: tint,
            borderRadius: AppRadius.cardAll,
            border: Border.all(color: Color.lerp(tint, c.danger, 0.35)!, width: AppBorder.hairline),
          ),
          child: Row(children: [
            Icon(Icons.error_outline_rounded, size: AppIconSize.md, color: appInkOn(context, c.danger, tint)),
            AppSpace.gapXs,
            Expanded(
              child: Text(message ?? head,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label(context).copyWith(color: c.textDark)),
            ),
            if (onRetry != null)
              Flexible(child: AppButton.ghost(label: 'retry'.tr, onPressed: onRetry, size: AppButtonSize.sm)),
          ]),
        ),
      );
    }
    final err = c.kit.error;
    return Semantics(
      liveRegion: true,
      container: true,
      child: AppStateLayout(
        plate: AppStatePlate(icon: Icons.cloud_off_rounded, fill: err.tint, ink: err.color),
        title: head,
        message: body,
        measure: _measure,
        action: onRetry == null
            ? null
            : (phone) =>
                AppButton.secondary(label: 'retry'.tr, icon: Icons.refresh_rounded, onPressed: onRetry, expand: phone),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Success
// ─────────────────────────────────────────────────────────────────────────────

/// A finished step (KIT_SPEC §5.9): a 96 px circle in the ok tint with the drawn tick (it pops in), the title in the
/// page-title role, a message, ONE primary action and an optional [secondary] (an AppButton.ghost) under it.
/// [burst] fires the confetti once from the circle's centre, 150 ms after the tick starts (student areas only).
class AppSuccess extends StatefulWidget {
  const AppSuccess({
    super.key,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.burst,
    this.secondary,
  });

  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final BurstMoment? burst;
  final Widget? secondary;

  /// The circle's size.
  static const double circle = 96;

  /// When the burst fires: the tick starts 700 ms in, the burst 150 ms after it.
  static const Duration burstAt = Duration(milliseconds: 850);

  @override
  State<AppSuccess> createState() => _AppSuccessState();
}

class _AppSuccessState extends State<AppSuccess> {
  final GlobalKey _anchor = GlobalKey();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.burst != null) {
      _timer = Timer(AppSuccess.burstAt, () {
        final ctx = _anchor.currentContext;
        if (mounted && ctx != null) AppBurst.fire(ctx, widget.burst!, anchor: _anchor);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = context.colors.kit.ok;
    final w = widget;
    return Semantics(
      liveRegion: true,
      container: true,
      child: AppStateLayout(
        plate: AppPop(
          group: 'success',
          child: Container(
            key: _anchor,
            width: AppSuccess.circle,
            height: AppSuccess.circle,
            decoration: BoxDecoration(color: ok.tint, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: AppInkCheck(size: AppSuccess.circle * .75, color: ok.ink),
          ),
        ),
        title: w.title,
        titleStyle: AppType.pageTitle(context),
        message: w.message,
        action: w.actionLabel != null && w.onAction != null
            ? (phone) => AppButton.primary(label: w.actionLabel!, onPressed: w.onAction, expand: phone)
            : null,
        secondary: w.secondary,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading
// ─────────────────────────────────────────────────────────────────────────────

/// The shape of the page the skeleton stands in for.
enum AppLoadingShape { list, cards, form, table, kpis }

class AppLoadingState extends StatelessWidget {
  const AppLoadingState({super.key, this.items = 6, this.shape = AppLoadingShape.list});

  /// Rows / cards / fields (kpis: the number of tiles).
  final int items;
  final AppLoadingShape shape;

  /// The narrowest a skeleton card / KPI tile gets before the grid drops a column.
  static const double _cardMin = 240, _kpiMin = 160;

  /// The bones (the skeleton's lines), by role.
  static const double _boneText = 12, _boneMeta = 10, _boneFigure = 24, _boneHead = 36, _boneCover = 72;
  static const double _boneLabelWidth = 96, _boneFigureWidth = 64, _bonePillWidth = 48, _bonePillHeight = 20;

  @override
  Widget build(BuildContext context) {
    // a placeholder never overflows: in a box shorter than the skeleton it is clipped (a non-scrolling scroll view),
    // in an unbounded one it takes its own height
    Widget clip(Widget w) => SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: w);
    final Widget body = switch (shape) {
      AppLoadingShape.list => AppListSkeleton(items: items),
      AppLoadingShape.cards => clip(AppShimmer(child: _grid(context, items, _cardMin, _card(context, tall: true)))),
      AppLoadingShape.kpis => clip(AppShimmer(child: _grid(context, items, _kpiMin, _card(context)))),
      AppLoadingShape.form => clip(AppShimmer(child: _form(context))),
      AppLoadingShape.table => clip(AppShimmer(child: _table(context))),
    };
    return Semantics(label: 'ds_loading'.tr, container: true, liveRegion: true, child: ExcludeSemantics(child: body));
  }

  static Widget _box(double? w, double h, [double r = AppRadius.chip]) => AppSkeletonBox(width: w, height: h, radius: r);

  Widget _card(BuildContext context, {bool tall = false}) {
    final c = context.colors;
    final width = MediaQuery.sizeOf(context).width;
    return Container(
      padding: width < Breakpoints.mobile ? AppSpace.card : AppSpace.cardWide,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.cardFor(width)),
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (tall) ...[_box(double.infinity, _boneCover), AppSpace.gapSm],
        Row(children: [
          _box(AppTouch.min - AppSpace.xs, AppTouch.min - AppSpace.xs),
          const Spacer(),
          _box(_bonePillWidth, _bonePillHeight, AppRadius.pill),
        ]),
        AppSpace.gapSm,
        _box(_boneLabelWidth, _boneText),
        const SizedBox(height: AppSpace.xs),
        _box(_boneFigureWidth, _boneFigure),
      ]),
    );
  }

  Widget _grid(BuildContext context, int n, double minTile, Widget tile) => Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: LayoutBuilder(builder: (context, box) {
          final cols = (box.maxWidth / minTile).floor().clamp(1, 4);
          final rows = (n / cols).ceil();
          return Column(mainAxisSize: MainAxisSize.min, children: [
            for (var r = 0; r < rows; r++) ...[
              if (r > 0) AppSpace.gapSm,
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (var i = 0; i < cols; i++) ...[
                  if (i > 0) AppSpace.gapSm,
                  Expanded(child: r * cols + i < n ? tile : const SizedBox.shrink()),
                ],
              ]),
            ],
          ]);
        }),
      );

  Widget _form(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < items; i++) ...[
            _box(88.0 + (i * 29) % 70, _boneText),
            const SizedBox(height: AppSpace.xs),
            _box(double.infinity, AppTouch.min, AppRadius.control),
            AppSpace.gapMd,
          ],
        ]),
      );

  Widget _table(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _box(double.infinity, _boneHead),
        for (var i = 0; i < items; i++)
          Container(
            height: AppTouch.min,
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.divider, width: AppBorder.hairline))),
            child: Row(children: [
              _box(AppIconSize.lg, AppIconSize.lg, AppIconSize.lg / 2),
              AppSpace.gapSm,
              Expanded(
                  flex: 3,
                  child: Align(alignment: AlignmentDirectional.centerStart, child: _box(60.0 + (i * 23) % 60, _boneMeta))),
              AppSpace.gapSm,
              Expanded(
                  flex: 2,
                  child: Align(alignment: AlignmentDirectional.centerStart, child: _box(40.0 + (i * 17) % 30, _boneMeta))),
              AppSpace.gapSm,
              Expanded(flex: 2, child: Align(alignment: AlignmentDirectional.centerStart, child: _box(AppIconSize.xl, _boneMeta))),
            ]),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The switch
// ─────────────────────────────────────────────────────────────────────────────

/// loading / error / empty / data in one place. [builder] only ever sees real data.
///
///   no data yet + loading           -> skeleton ([loadingShape])
///   no data yet + error             -> [AppErrorState] with Retry
///   data, [isEmpty] says empty      -> [empty] (default: AppEmpty "Nothing here yet")
///   data + error (a failed refresh) -> the data stays, a slim error banner with Retry above it
///   data (refreshing or not)        -> [builder]
class AppStateView<T> extends StatelessWidget {
  const AppStateView({
    super.key,
    required this.loading,
    this.error,
    this.data,
    required this.builder,
    this.isEmpty,
    this.empty,
    this.onRetry,
    this.loadingShape = AppLoadingShape.list,
  });

  final bool loading;
  final Object? error;
  final T? data;
  final Widget Function(BuildContext, T) builder;
  final bool Function(T)? isEmpty;
  final Widget? empty;
  final VoidCallback? onRetry;
  final AppLoadingShape loadingShape;

  Widget _empty() => empty ?? AppEmpty(icon: Icons.inbox_rounded, title: 'ds_no_data'.tr);

  // the skeleton crossfades into whatever replaces it (D-582); a change inside the content never remounts it
  @override
  Widget build(BuildContext context) => AppSkeletonSwitch(loading: data == null && loading, child: _body(context));

  Widget _body(BuildContext context) {
    final d = data;
    if (d == null) {
      if (loading) return AppLoadingState(shape: loadingShape);
      if (error != null) return AppErrorState(message: appErrorMessage(error), onRetry: onRetry);
      return _empty();
    }
    if (isEmpty?.call(d) ?? false) {
      if (error == null) return _empty();
      return Column(mainAxisSize: MainAxisSize.min, children: [_banner(), _empty()]);
    }
    final content = builder(context, d);
    if (error == null) return content;
    return LayoutBuilder(builder: (context, box) {
      final bounded = box.maxHeight.isFinite;
      return Column(
        mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_banner(), if (bounded) Expanded(child: content) else content],
      );
    });
  }

  Widget _banner() => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xs),
        child: AppErrorState(compact: true, message: appErrorMessage(error), onRetry: onRetry),
      );
}
