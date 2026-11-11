// lib/design/app_states.dart
//
// The three states every data screen has besides "data": failed, loading and empty (Warm Editorial, system.md).
//
//   AppErrorState(message: ApiException.from(e).message, onRetry: _load)      plate, editorial title, message, Retry
//   AppErrorState(compact: true, …)                                           the same as one inline row (in a card)
//   AppLoadingState(shape: AppLoadingShape.cards)                            skeletons of the page's shape, no spinner
//   AppEmpty(icon:, title:, message:, actionLabel:, onAction:)               an editorial headline, one action and a
//                                                                            drawn plate (AppStatePlate), no stock art
//   AppStateView<T>(loading:, error:, data:, builder:, onRetry:)             THE switch between them
//
// AppStateView never wipes good data: when a refresh fails and data is already on screen, the data stays and a slim
// error banner sits above it. The skeleton shows only while there is no data yet. An error that is not an
// ApiException is never printed (its toString looks like a stack trace): the generic ds_error_body text is shown.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';

import 'app_badges.dart';
import 'app_blocks.dart';
import 'app_buttons.dart';
import 'app_gradients.dart' show AppGradientIcon;
import 'app_kit.dart' show AppListSkeleton, AppShimmer, AppSkeletonBox;
import 'app_motion_kit.dart';
import 'app_tokens.dart';

/// The text to show for a failed load: an [ApiException]'s own (safe) message, else the generic one.
String appErrorMessage(Object? error) {
  if (error is ApiException && error.message.trim().isNotEmpty) return error.message;
  return 'ds_error_body'.tr;
}

// ─────────────────────────────────────────────────────────────────────────────
// The plate: the one drawn illustration of the empty and error states
// ─────────────────────────────────────────────────────────────────────────────

/// A small vector plate for an empty or failed state: a tinted block (a round of the tone) with two sheets of
/// paper on it, the front one carrying [icon] and three faint text lines — "a page with nothing written on it yet".
/// Pure CustomPaint in the theme's colours, no stock art, no emoji; it settles in once (AppPopIn, from 0.96, never
/// from nothing) and is still under Reduce motion.
class AppStatePlate extends StatelessWidget {
  const AppStatePlate({super.key, required this.icon, this.tone = AppBlockTone.peach, this.accent, this.size = 120});

  final IconData icon;

  /// The block tone behind the sheets (peach for empty states; a failed load passes [accent] = danger).
  final AppBlockTone tone;

  /// The icon's colour and the chip under it: the primary by default, the danger tone on an error plate.
  final Color? accent;

  /// The plate's width; its height is 4 : 5 of it.
  final double size;

  /// The icon's chip on the front sheet, as a share of [size].
  static const double _chipScale = 0.3;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final block = AppBlockColors.of(context, tone);
    final ink = accent ?? c.primary;
    final chip = size * _chipScale;
    final tint = appTintOn(context, ink, surface: c.cardBg);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return ExcludeSemantics(
      child: AppPopIn(
        from: 0.96,
        child: SizedBox(
          width: size,
          height: size * 0.8,
          child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _PlatePainter(
                  block: block.surface,
                  paper: c.cardBg,
                  line: c.divider,
                  faint: Color.lerp(c.divider, c.textLight, c.isDark ? 0.25 : 0.1)!,
                  chip: tint,
                  chipSize: chip,
                  rtl: rtl,
                ),
              ),
            ),
            // the icon sits on the chip the painter drew, at the sheet's top-start corner
            Align(
              alignment: const AlignmentDirectional(_PlatePainter.chipAlignX, _PlatePainter.chipAlignY),
              // D-650 r3: the brand plate's glyph wears the gradient; an error plate keeps its danger ink
              child: accent == null
                  ? AppGradientIcon(icon, size: chip * 0.55, on: [Color.alphaBlend(tint, c.cardBg)])
                  : Icon(icon, size: chip * 0.55, color: appInkOn(context, ink, tint)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _PlatePainter extends CustomPainter {
  const _PlatePainter({
    required this.block,
    required this.paper,
    required this.line,
    required this.faint,
    required this.chip,
    required this.chipSize,
    required this.rtl,
  });

  final Color block, paper, line, faint, chip;
  final double chipSize;
  final bool rtl;

  /// Where the icon chip sits (AlignmentDirectional coordinates, so the widget layer can put the icon on it).
  static const double chipAlignX = -0.42;
  static const double chipAlignY = -0.26;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (rtl) {
      // the plate reads from the start: mirror the whole drawing for Arabic
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
    }
    // the tinted round behind everything: a block, off-centre, larger than the sheets
    final round = Rect.fromCenter(center: Offset(w * 0.5, h * 0.52), width: w * 0.86, height: h * 0.96);
    canvas.drawRRect(RRect.fromRectAndRadius(round, Radius.circular(w * 0.2)), Paint()..color = block);

    final sheet = Rect.fromLTWH(w * 0.2, h * 0.12, w * 0.6, h * 0.8);
    final radius = Radius.circular(w * 0.07);
    final hairline = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppBorder.hairline;

    // the back sheet, turned a little
    canvas.save();
    canvas.translate(sheet.center.dx, sheet.center.dy);
    canvas.rotate(-math.pi / 28);
    canvas.translate(-sheet.center.dx + w * 0.07, -sheet.center.dy - h * 0.03);
    final backRect = RRect.fromRectAndRadius(sheet, radius);
    canvas.drawRRect(backRect, Paint()..color = paper);
    canvas.drawRRect(backRect, hairline);
    canvas.restore();

    // the front sheet
    final front = RRect.fromRectAndRadius(sheet, radius);
    canvas.drawRRect(front, Paint()..color = paper);
    canvas.drawRRect(front, hairline);

    // the chip the icon sits on (top-start of the sheet)
    // Alignment(x, y) centres a child of size s at (w + x · (w − s)) / 2
    final cx = w * 0.5 + chipAlignX * (w * 0.5 - chipSize / 2);
    final cy = h * 0.5 + chipAlignY * (h * 0.5 - chipSize / 2);
    final chipRect = Rect.fromCenter(center: Offset(cx, cy), width: chipSize, height: chipSize);
    canvas.drawRRect(RRect.fromRectAndRadius(chipRect, Radius.circular(chipSize * 0.3)), Paint()..color = chip);

    // three faint lines of "text" under it, the last one shorter
    final linePaint = Paint()
      ..color = faint
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(2, h * 0.035);
    final x0 = sheet.left + w * 0.09;
    final x1 = sheet.right - w * 0.09;
    final y0 = chipRect.bottom + h * 0.12;
    final step = h * 0.11;
    for (var i = 0; i < 3; i++) {
      final y = y0 + i * step;
      final end = i == 2 ? x0 + (x1 - x0) * 0.55 : x1;
      canvas.drawLine(Offset(x0, y), Offset(end, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(_PlatePainter o) =>
      o.block != block ||
      o.paper != paper ||
      o.line != line ||
      o.faint != faint ||
      o.chip != chip ||
      o.chipSize != chipSize ||
      o.rtl != rtl;
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

  /// The widest the text block gets (a comfortable measure for a two-line sentence).
  static const double _measure = 360;

  @override
  Widget build(BuildContext context) {
    // in a box shorter than itself (a table's body on a small phone with large text) it scrolls instead of overflowing
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _measure),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AppStatePlate(icon: icon, tone: tone),
            const SizedBox(height: AppSpace.lg),
            Text(title, textAlign: TextAlign.center, style: AppType.section(context)),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xs),
              Text(message!, textAlign: TextAlign.center, style: AppType.body(context)),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpace.lg),
              AppButton.primary(label: actionLabel!, onPressed: onAction),
            ],
          ]),
        ),
      ),
    );
  }
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
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _measure),
          child: Semantics(
            liveRegion: true,
            container: true,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AppStatePlate(icon: Icons.cloud_off_rounded, tone: AppBlockTone.paper, accent: c.danger),
              const SizedBox(height: AppSpace.lg),
              Text(head, textAlign: TextAlign.center, style: AppType.section(context)),
              const SizedBox(height: AppSpace.xs),
              Text(body, textAlign: TextAlign.center, style: AppType.body(context)),
              if (onRetry != null) ...[
                const SizedBox(height: AppSpace.lg),
                AppButton.primary(label: 'retry'.tr, icon: Icons.refresh_rounded, onPressed: onRetry),
              ],
            ]),
          ),
        ),
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
    return Container(
      padding: AppSpace.card,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
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
