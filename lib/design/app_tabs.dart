// lib/design/app_tabs.dart
//
// Tabs of the design system (D-612).
//
//   AppTabs(items: [AppTabItem('Open', count: 3), AppTabItem('Done')], index: i, onChanged: (v) => setState(() => i = v))
//   AppUnderlineTabs(...)   the lighter variant for sections of a page (same API)
//
// AppTabs is a pill track (the input surface with a warm hairline) whose selected pill — solid emerald, the primary,
// with the on-hero ink — slides to the chosen tab; it never walks into the gradient's teal. AppUnderlineTabs draws
// the labels in ink with a 2 px ink rule under the chosen one. When the tabs do not fit, the strip scrolls
// horizontally and keeps the selected tab in view; with `expand` the tabs share the width when they fit. On web /
// desktop the arrow keys move the selection (the arrow that points "forward" follows the text direction) and the
// strip shows the focus ring. Each tab is a selected / unselected button for screen readers.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/theme/theme_config_provider.dart';
import 'app_badges.dart';
import 'app_tokens.dart';

class AppTabItem {
  const AppTabItem(this.label, {this.icon, this.count});

  final String label;
  final IconData? icon;
  final int? count;
}

class AppTabs extends StatelessWidget {
  const AppTabs({super.key, required this.items, required this.index, required this.onChanged, this.expand = false, this.hug = false});

  final List<AppTabItem> items;
  final int index;
  final ValueChanged<int> onChanged;
  final bool expand;

  /// The track as wide as its pills (at the start) instead of the full width: a small period switch in a card's
  /// header ([AppSectionCard.tabs]). Only while the pills fit; a strip that scrolls keeps the full width.
  final bool hug;

  @override
  Widget build(BuildContext context) =>
      _TabStrip(items: items, index: index, onChanged: onChanged, expand: expand, underline: false, hug: hug);
}

class AppUnderlineTabs extends StatelessWidget {
  const AppUnderlineTabs({super.key, required this.items, required this.index, required this.onChanged, this.expand = false});

  final List<AppTabItem> items;
  final int index;
  final ValueChanged<int> onChanged;
  final bool expand;

  @override
  Widget build(BuildContext context) =>
      _TabStrip(items: items, index: index, onChanged: onChanged, expand: expand, underline: true);
}

class _TabStrip extends StatefulWidget {
  const _TabStrip({
    required this.items,
    required this.index,
    required this.onChanged,
    required this.expand,
    required this.underline,
    this.hug = false,
  });

  final List<AppTabItem> items;
  final int index;
  final ValueChanged<int> onChanged;
  final bool expand;
  final bool underline;
  final bool hug;

  @override
  State<_TabStrip> createState() => _TabStripState();
}

class _TabStripState extends State<_TabStrip> {
  late List<GlobalKey> _keys = List.generate(widget.items.length, (_) => GlobalKey());

  @override
  void didUpdateWidget(_TabStrip old) {
    super.didUpdateWidget(old);
    if (_keys.length != widget.items.length) _keys = List.generate(widget.items.length, (_) => GlobalKey());
    if (old.index != widget.index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.index >= _keys.length) return;
        final ctx = _keys[widget.index].currentContext;
        final box = ctx?.findRenderObject();
        // the strip's own scroll only: Scrollable.ensureVisible would also move the page the tabs sit on
        final strip = ctx == null ? null : Scrollable.maybeOf(ctx);
        if (box != null && strip != null && strip.position.axis == Axis.horizontal) {
          strip.position.ensureVisible(box, duration: AppMotion.of(context).base, curve: AppMotion.curve, alignment: 0.5);
        }
      });
    }
  }

  static const double _gap = AppSpace.xs;

  /// The pill track's inset around the pills.
  static const double _trackPad = AppSpace.xxs;

  /// The ink rule under the chosen underline tab.
  static const double _rule = 2;

  /// The smallest count bubble (a round one-digit pill).
  static const double _bubble = AppIconSize.md;

  TextStyle _style(BuildContext context) => AppType.row(context).copyWith(fontWeight: FontWeight.w600, height: 1.2);

  double _textWidth(BuildContext context, String text, TextStyle style) {
    final p = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return p.width.ceilToDouble() + 1;
  }

  double _countWidth(BuildContext context, int n) {
    final s = AppType.overline(context);
    return (_textWidth(context, appCountText(n), s) + AppSpace.xs + 2).clamp(_bubble, double.infinity);
  }

  double _natural(BuildContext context, AppTabItem it, TextStyle style) {
    var w = (widget.underline ? AppSpace.sm : AppSpace.md) * 2 + _textWidth(context, it.label, style);
    if (it.icon != null) w += AppIconSize.md + _gap;
    if (it.count != null) w += _gap + _countWidth(context, it.count!);
    return w < AppTouch.min ? AppTouch.min : w;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    int? next;
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
      next = widget.index + (rtl ? -1 : 1);
    } else if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      next = widget.index + (rtl ? 1 : -1);
    } else if (e.logicalKey == LogicalKeyboardKey.home) {
      next = 0;
    } else if (e.logicalKey == LogicalKeyboardKey.end) {
      next = widget.items.length - 1;
    }
    if (next == null) return KeyEventResult.ignored;
    if (next < 0 || next >= widget.items.length) return KeyEventResult.handled;
    widget.onChanged(next);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    if (_keys.length != items.length) _keys = List.generate(items.length, (_) => GlobalKey());
    final style = _style(context);
    final underline = widget.underline;
    final pad = underline ? 0.0 : _trackPad;
    final index = widget.index.clamp(0, items.length - 1);
    final motion = AppMotion.of(context);

    return LayoutBuilder(builder: (context, box) {
      final widths = [for (final it in items) _natural(context, it, style)];
      final total = widths.fold<double>(0, (a, b) => a + b);
      final avail = box.hasBoundedWidth ? box.maxWidth - pad * 2 - (underline ? 0 : 2 * AppBorder.hairline) : total;
      if (widget.expand && total < avail) {
        final each = avail / items.length;
        for (var i = 0; i < widths.length; i++) {
          widths[i] = each > widths[i] ? each : widths[i];
        }
      }
      final offsets = <double>[];
      var acc = 0.0;
      for (final w in widths) {
        offsets.add(acc);
        acc += w;
      }
      final contentW = acc;

      Widget tab(int i) {
        final it = items[i];
        final sel = i == index;
        final ink = sel ? (underline ? c.textDark : c.onHero) : c.textMedium;
        final ts = style.copyWith(color: ink);
        return Semantics(
          button: true,
          selected: sel,
          label: it.count == null ? it.label : '${it.label}, ${it.count}',
          excludeSemantics: true,
          onTap: () => widget.onChanged(i),
          child: SizedBox(
            key: _keys[i],
            width: widths[i],
            height: AppTouch.min,
            child: InkWell(
              onTap: () => widget.onChanged(i),
              borderRadius: BorderRadius.circular(underline ? AppRadius.chip : AppRadius.pill),
              splashFactory: NoSplash.splashFactory,
              mouseCursor: SystemMouseCursors.click,
              child: Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (it.icon != null) ...[
                    Icon(it.icon, size: AppIconSize.md, color: ink),
                    const SizedBox(width: _gap),
                  ],
                  Text(it.label, maxLines: 1, softWrap: false, overflow: TextOverflow.visible, style: ts),
                  if (it.count != null) ...[
                    const SizedBox(width: _gap),
                    AnimatedContainer(
                      duration: motion.base,
                      constraints: const BoxConstraints(minWidth: _bubble, minHeight: _bubble),
                      // no `alignment`: it would make the bubble fill the tab's whole height
                      padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpace.xxs + 1, vertical: 2),
                      decoration: BoxDecoration(
                        color: sel && !underline ? c.onHero.withValues(alpha: 0.22) : c.primaryTint,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(appCountText(it.count!),
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: AppType.overline(context).copyWith(color: sel && !underline ? c.onHero : c.primary)),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        );
      }

      final strip = SizedBox(
        width: contentW,
        height: AppTouch.min,
        child: Stack(children: [
          AnimatedPositionedDirectional(
            duration: motion.base,
            curve: AppMotion.curve,
            start: offsets[index],
            width: widths[index],
            top: underline ? null : _trackPad,
            bottom: underline ? 0 : _trackPad,
            height: underline ? _rule : null,
            child: ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: underline ? c.textDark : c.primary,
                  borderRadius: BorderRadius.circular(underline ? _rule / 2 : AppRadius.pill),
                ),
              ),
            ),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < items.length; i++) tab(i)]),
        ]),
      );

      final fits = contentW <= avail + 0.5;
      final hug = widget.hug && fits && !widget.expand;
      final body = hug
          ? strip
          : fits
              ? Align(alignment: AlignmentDirectional.centerStart, child: strip)
              : SingleChildScrollView(scrollDirection: Axis.horizontal, child: strip);

      final track = Focus(
        onKeyEvent: _onKey,
        child: Builder(builder: (context) {
          final focused = Focus.of(context).hasFocus;
          final edge = focused ? c.primary : c.divider;
          final width = focused ? AppBorder.focus : AppBorder.hairline;
          return AnimatedContainer(
            duration: motion.fast,
            // the border sits inside this height: leave room for the focus border so every tab keeps a full
            // 48 px target and the bar does not jump when it takes focus
            height: AppTouch.min + (underline ? AppBorder.focus : 2 * AppBorder.focus),
            padding: EdgeInsetsDirectional.symmetric(horizontal: pad),
            decoration: underline
                ? BoxDecoration(border: Border(bottom: BorderSide(color: edge, width: width)))
                : BoxDecoration(
                    color: c.inputBg,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: edge, width: width),
                  ),
            child: body,
          );
        }),
      );
      return hug ? Align(alignment: AlignmentDirectional.centerStart, widthFactor: 1, heightFactor: 1, child: track) : track;
    });
  }
}
