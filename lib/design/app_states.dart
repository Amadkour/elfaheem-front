// lib/design/app_states.dart
//
// The three states every data screen has besides "data": failed, loading and (via AppEmpty) empty.
//
//   AppErrorState(message: ApiException.from(e).message, onRetry: _load)      icon, title, message, Retry
//   AppErrorState(compact: true, …)                                           the same as one inline row (in a card)
//   AppLoadingState(shape: AppLoadingShape.cards)                            skeletons of the page's shape, no spinner
//   AppStateView<T>(loading:, error:, data:, builder:, onRetry:)             THE switch between them
//
// AppStateView never wipes good data: when a refresh fails and data is already on screen, the data stays and a slim
// error banner sits above it. The skeleton shows only while there is no data yet. An error that is not an
// ApiException is never printed (its toString looks like a stack trace): the generic ds_error_body text is shown.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';

import 'app_kit.dart';
import 'app_tokens.dart';

/// The text to show for a failed load: an [ApiException]'s own (safe) message, else the generic one.
String appErrorMessage(Object? error) {
  if (error is ApiException && error.message.trim().isNotEmpty) return error.message;
  return 'ds_error_body'.tr;
}

class AppErrorState extends StatelessWidget {
  const AppErrorState({super.key, this.title, this.message, this.onRetry, this.compact = false});

  /// Default: "Couldn't load this".
  final String? title;

  /// Pass `ApiException.from(e).message`. Default: "Check your connection and try again."
  final String? message;
  final VoidCallback? onRetry;

  /// One inline row for the inside of a card.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final head = title ?? 'ds_error_title'.tr;
    final body = message ?? 'ds_error_body'.tr;
    if (compact) {
      return Semantics(
        liveRegion: true,
        container: true,
        child: Container(
          padding: const EdgeInsetsDirectional.only(
              start: AppSpace.sm, end: AppSpace.xxs, top: AppSpace.xxs, bottom: AppSpace.xxs),
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          decoration: BoxDecoration(
            color: c.danger.withValues(alpha: 0.10),
            borderRadius: AppRadius.cardAll,
            border: Border.all(color: c.danger.withValues(alpha: 0.30), width: AppBorder.hairline),
          ),
          child: Row(children: [
            Icon(Icons.error_outline_rounded, size: AppIconSize.md, color: c.danger),
            AppSpace.gapXs,
            Expanded(
              child: Text(message ?? head,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label(context).copyWith(color: c.textDark)),
            ),
            if (onRetry != null)
              Flexible(
                child: TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
                  child: Text('retry'.tr, textAlign: TextAlign.center),
                ),
              ),
          ]),
        ),
      );
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Semantics(
            liveRegion: true,
            container: true,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: c.danger.withValues(alpha: 0.10), shape: BoxShape.circle),
                child: Icon(Icons.cloud_off_rounded, size: AppIconSize.xl, color: c.danger),
              ),
              AppSpace.gapMd,
              Text(head, textAlign: TextAlign.center, style: AppType.section(context)),
              const SizedBox(height: AppSpace.xxs),
              Text(body, textAlign: TextAlign.center, style: AppType.body(context)),
              if (onRetry != null) ...[
                AppSpace.gapMd,
                FilledButton.icon(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
                  icon: const Icon(Icons.refresh_rounded, size: AppIconSize.md),
                  label: Text('retry'.tr),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// The shape of the page the skeleton stands in for.
enum AppLoadingShape { list, cards, form, table, kpis }

class AppLoadingState extends StatelessWidget {
  const AppLoadingState({super.key, this.items = 6, this.shape = AppLoadingShape.list});

  /// Rows / cards / fields (kpis: the number of tiles).
  final int items;
  final AppLoadingShape shape;

  @override
  Widget build(BuildContext context) {
    // a placeholder never overflows: in a box shorter than the skeleton it is clipped (a non-scrolling scroll view),
    // in an unbounded one it takes its own height
    Widget clip(Widget w) => SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: w);
    final Widget body = switch (shape) {
      AppLoadingShape.list => AppListSkeleton(items: items),
      AppLoadingShape.cards => clip(AppShimmer(child: _grid(context, items, 240, _card(context, tall: true)))),
      AppLoadingShape.kpis => clip(AppShimmer(child: _grid(context, items, 160, _card(context)))),
      AppLoadingShape.form => clip(AppShimmer(child: _form(context))),
      AppLoadingShape.table => clip(AppShimmer(child: _table(context))),
    };
    return Semantics(label: 'ds_loading'.tr, container: true, liveRegion: true, child: ExcludeSemantics(child: body));
  }

  static Widget _box(double? w, double h, [double r = AppRadius.chip]) => AppSkeletonBox(width: w, height: h, radius: r);

  Widget _card(BuildContext context, {bool tall = false}) {
    final c = context.colors;
    return Container(
      padding: AppSpace.card,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (tall) ...[_box(double.infinity, 72), AppSpace.gapSm],
        Row(children: [_box(AppIconSize.xl, AppIconSize.xl), const Spacer(), _box(48, 20)]),
        AppSpace.gapSm,
        _box(96, 12),
        const SizedBox(height: AppSpace.xs),
        _box(64, 24),
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
            _box(88.0 + (i * 29) % 70, 12),
            const SizedBox(height: AppSpace.xs),
            _box(double.infinity, AppTouch.min),
            AppSpace.gapMd,
          ],
        ]),
      );

  Widget _table(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _box(double.infinity, 36),
        for (var i = 0; i < items; i++)
          Container(
            height: AppTouch.min,
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.divider.withValues(alpha: 0.6)))),
            child: Row(children: [
              _box(AppIconSize.lg, AppIconSize.lg, AppIconSize.lg / 2),
              AppSpace.gapSm,
              Expanded(
                  flex: 3,
                  child: Align(alignment: AlignmentDirectional.centerStart, child: _box(60.0 + (i * 23) % 60, 11))),
              AppSpace.gapSm,
              Expanded(
                  flex: 2,
                  child: Align(alignment: AlignmentDirectional.centerStart, child: _box(40.0 + (i * 17) % 30, 11))),
              AppSpace.gapSm,
              Expanded(flex: 2, child: Align(alignment: AlignmentDirectional.centerStart, child: _box(32, 11))),
            ]),
          ),
      ]),
    );
  }
}

/// loading / error / empty / data in one place. [builder] only ever sees real data.
///
///   no data yet + loading           -> skeleton ([loadingShape])
///   no data yet + error             -> [AppErrorState] with Retry
///   data, [isEmpty] says empty      -> [empty] (default: AppEmpty "No data")
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

  @override
  Widget build(BuildContext context) {
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
