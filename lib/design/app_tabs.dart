// lib/design/app_tabs.dart
//
// Tabs of the design system.
//
//   AppTabs(items: [AppTabItem('Open', count: 3), AppTabItem('Done')], index: i, onChanged: (v) => setState(() => i = v))
//   AppUnderlineTabs(...)   the lighter variant for sections of a page (same API)
//
// AppTabs is a pill track whose selected pill (brand gradient, on-hero ink) slides to the chosen tab. When the tabs do
// not fit, the strip scrolls horizontally and keeps the selected tab in view; with `expand` the tabs share the width
// when they fit. On web / desktop the arrow keys move the selection (the arrow that points "forward" follows the
// text direction). Each tab is a selected / unselected button for screen readers.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/theme/theme_config_provider.dart';
import 'app_badges.dart';
import 'app_charts.dart' show appInk;
import 'app_gradients.dart';
import 'app_tokens.dart';

class AppTabItem {
  const AppTabItem(this.label, {this.icon, this.count});

  final String label;
  final IconData? icon;
  final int? count;
}

class AppTabs extends StatelessWidget {
  const AppTabs({super.key, required this.items, required this.index, required this.onChanged, this.expand = false});

  final List<AppTabItem> items;
  final int index;
  final ValueChanged<int> onChanged;
  final bool expand;

  @override
  Widget build(BuildContext context) =>
      _TabStrip(items: items, index: index, onChanged: onChanged, expand: expand, underline: false);
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
  });

  final List<AppTabItem> items;
  final int index;
  final ValueChanged<int> onChanged;
  final bool expand;
  final bool underline;

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
        if (ctx != null) {
          Scrollable.ensureVisible(ctx, duration: AppMotion.of(context).base, curve: AppMotion.curve, alignment: 0.5);
        }
      });
    }
  }

  static const double _gap = AppSpace.xs;

  TextStyle _style(BuildContext context) => AppType.row(context).copyWith(fontWeight: FontWeight.w600, fontSize: 14, height: 1.2);

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
    return (_textWidth(context, appCountText(n), s) + AppSpace.xs + 2).clamp(20.0, double.infinity);
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
    final pad = underline ? 0.0 : 4.0;
    final index = widget.index.clamp(0, items.length - 1);
    final motion = AppMotion.of(context);

    return LayoutBuilder(builder: (context, box) {
      final widths = [for (final it in items) _natural(context, it, style)];
      final total = widths.fold<double>(0, (a, b) => a + b);
      final avail = box.hasBoundedWidth ? box.maxWidth - pad * 2 - (underline ? 0 : 2) : total;
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
        final ink = sel ? (underline ? appInk(context, c.primary) : c.onHero) : c.textMedium; // underline: readable on dark
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
              borderRadius: BorderRadius.circular(AppRadius.sheet),
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
                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      // no `alignment`: it would make the bubble fill the tab's whole height
                      padding: const EdgeInsetsDirectional.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: sel && !underline ? c.onHero.withValues(alpha: 0.22) : c.primaryTint,
                        borderRadius: BorderRadius.circular(AppRadius.sheet),
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
            top: underline ? null : 4,
            bottom: underline ? 0 : 4,
            height: underline ? 3 : null,
            child: ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: underline ? AppGradients.strip(context) : AppGradients.brand(context),
                  borderRadius: BorderRadius.circular(underline ? 3 : AppRadius.sheet),
                  boxShadow: underline ? null : c.primaryButtonShadow,
                ),
              ),
            ),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < items.length; i++) tab(i)]),
        ]),
      );

      final fits = contentW <= avail + 0.5;
      final body = fits
          ? Align(alignment: AlignmentDirectional.centerStart, child: strip)
          : SingleChildScrollView(scrollDirection: Axis.horizontal, child: strip);

      return Focus(
        onKeyEvent: _onKey,
        child: Container(
          height: AppTouch.min,
          padding: EdgeInsetsDirectional.symmetric(horizontal: pad),
          decoration: underline
              ? BoxDecoration(border: Border(bottom: BorderSide(color: c.divider, width: AppBorder.hairline)))
              : BoxDecoration(
                  color: c.inputBg,
                  borderRadius: BorderRadius.circular(AppRadius.sheet),
                  border: Border.all(color: c.divider, width: AppBorder.hairline),
                ),
          child: body,
        ),
      );
    });
  }
}
