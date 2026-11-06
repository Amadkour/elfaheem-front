// lib/features/org/org_page_kit.dart
//
// THE anatomy of every page of the organization dashboard, under the shell's OrgPageHeader (D-103):
//   title (the header) · ONE primary action · at most ONE search and ONE filter · the content.
//
//   OrgPageBody(primary:, search:, filter:, more:, top:, child:)
//       top       an optional control above the toolbar (OrgSegmented for a kind, OrgPartPicker for a page's parts)
//       toolbar   search · filter ("Active ▾") · More (⋯, the secondary actions with text labels) · the primary
//                 action. Wide (≥ 600 px): one row, the primary action a filled button at its end. Phones: the primary
//                 action is ONE extended FAB at the bottom end (never both); a narrow phone or a large text size puts
//                 the search on its own row.
//       child     the content (Expanded): lists of cards, never wide tables on phones.
//   OrgPrimaryAction(icon:, label:, onTap:)   the page's one primary action
//   OrgFilterButton<T>   ONE dropdown filter: shows the chosen option; ▾ lists them with a check on the chosen one;
//                        tinted while it is not the default value
//   OrgMoreMenu          "More" (⋯): secondary actions, each icon + text; phones draw the 48 px ⋯ square + tooltip
//   OrgSegmented<T>      2 – 4 equal choices (Students · Teachers · Staff)
//   OrgPartPicker        a page's parts (Calendar · Levels · …): chips when they fit, else ONE "part ▾" button
//   OrgSectionChips      the section hub's sub-page chips: one row that scrolls, with a fade at the hidden edge(s)
//
// Every size, gap, radius and duration comes from app_tokens.dart; colours from context.colors.
// Layout test: test/ui/org_pages_layout_test.dart; renders: test/visual/org_pages_golden_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppChoiceChip, AppSheetHeader, showAppSheet;
import 'package:flutter_education_app/design/app_tokens.dart';

import '../admin/admin_common.dart' show SearchBox, t;

/// The page's ONE primary action.
class OrgPrimaryAction {
  const OrgPrimaryAction({required this.icon, required this.label, required this.onTap, this.id = 'primary'});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Keys the button / FAB (`org.page.<id>`) and the FAB's hero tag.
  final String id;
}

/// A secondary action in the "More" menu.
class OrgMenuItem {
  const OrgMenuItem({required this.icon, required this.label, required this.onTap, this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
}

/// The horizontal padding of a row inside a PagedList / AdminSimpleList (which already insets its rows by 14 px):
/// the cards then line up with the header and the toolbar, AppSpace.md from the edge.
const double orgListInset = AppSpace.md - 14;

/// From this width the toolbar is one row with the primary action at its end (below it: a FAB).
const double orgPageWideFrom = 600;

/// A section title inside a page's content (16 w600 + one muted line, D-102), lined up with the toolbar.
class OrgSectionHeading extends StatelessWidget {
  const OrgSectionHeading(this.title, {super.key, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xs),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: Text(title, style: AppType.section(context))),
            if (sub != null && sub.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ],
          ]),
        ),
        ?action,
      ]),
    );
  }
}

/// The search box of a page's toolbar (debounced; Ctrl+K / "/" focus it).
class OrgSearchField extends StatelessWidget {
  const OrgSearchField({super.key, required this.hint, required this.onChanged});
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SearchBox(hint: hint, onChanged: onChanged);
}

class OrgPageBody extends StatelessWidget {
  const OrgPageBody({
    super.key,
    required this.child,
    this.primary,
    this.search,
    this.filter,
    this.more = const [],
    this.top,
  });

  final Widget child;
  final OrgPrimaryAction? primary;
  final Widget? search;
  final Widget? filter;
  final List<OrgMenuItem> more;
  final Widget? top;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= orgPageWideFrom;
      final p = primary;
      final hasTools = search != null || filter != null || more.isNotEmpty || (wide && p != null);
      final column = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (top != null)
          Padding(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, 0), child: top),
        if (hasTools)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xs),
            child: _Toolbar(width: box.maxWidth, wide: wide, search: search, filter: filter, more: more, primary: wide ? p : null),
          ),
        Expanded(child: child),
      ]);
      if (wide || p == null) return column;
      return Stack(children: [
        Positioned.fill(child: column),
        PositionedDirectional(end: AppSpace.md, bottom: AppSpace.md, child: _Fab(action: p)),
      ]);
    });
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.width, required this.wide, this.search, this.filter, this.more = const [], this.primary});
  final double width;
  final bool wide;
  final Widget? search, filter;
  final List<OrgMenuItem> more;
  final OrgPrimaryAction? primary;

  @override
  Widget build(BuildContext context) {
    final p = primary;
    // a phone: search + filter + ⋯ on one row when there is room, else the search on its own row
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final tight = width < 340 * scale;
    // phones show "More" as the ⋯ square (like the header's icon buttons) next to a search or when space is short
    final moreBtn = more.isEmpty ? null : OrgMoreMenu(items: more, compact: !wide && (search != null || tight));
    if (wide) {
      return Row(children: [
        Expanded(
          child: Row(children: [
            if (search != null) Flexible(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: search)),
            if (search != null && filter != null) AppSpace.gapXs,
            if (filter != null) Flexible(child: filter!),
          ]),
        ),
        if (moreBtn != null) ...[AppSpace.gapXs, moreBtn],
        if (p != null) ...[AppSpace.gapXs, OrgPrimaryButton(action: p)],
      ]);
    }
    // the filter at the start, ⋯ at the end
    Widget filterAndMore() => Row(children: [
          Expanded(
            child: filter == null ? const SizedBox.shrink() : Align(alignment: AlignmentDirectional.centerStart, child: filter),
          ),
          if (moreBtn != null) ...[AppSpace.gapXs, moreBtn],
        ]);
    if (search == null) return filterAndMore();
    if (tight && (filter != null || moreBtn != null)) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [search!, AppSpace.gapXs, filterAndMore()]);
    }
    return Row(children: [
      Expanded(flex: 3, child: search!),
      if (filter != null) ...[AppSpace.gapXs, Flexible(flex: 2, child: filter!)],
      if (moreBtn != null) ...[AppSpace.gapXs, moreBtn],
    ]);
  }
}

/// The primary action as a filled button (wide toolbars).
class OrgPrimaryButton extends StatelessWidget {
  const OrgPrimaryButton({super.key, required this.action});
  final OrgPrimaryAction action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return FilledButton.icon(
      key: ValueKey('org.page.${action.id}'),
      onPressed: action.onTap,
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.onHero,
        minimumSize: const Size(0, AppTouch.min),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll),
        textStyle: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w600, fontSize: 14),
      ),
      icon: Icon(action.icon, size: 20),
      label: Text(action.label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class _Fab extends StatelessWidget {
  const _Fab({required this.action});
  final OrgPrimaryAction action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // the brand gradient (D-136) behind a transparent FAB: its ripple, hover and focus overlays draw on top
    final r = BorderRadius.circular(18);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: r, gradient: c.primaryGradient, boxShadow: c.primaryButtonShadow),
      child: FloatingActionButton.extended(
        key: ValueKey('org.page.${action.id}'),
        heroTag: 'org.page.${action.id}',
        backgroundColor: Colors.transparent,
        foregroundColor: c.onHero,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: r),
        onPressed: action.onTap,
        icon: Icon(action.icon),
        label: Text(action.label, style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// A quiet bordered surface of the toolbar's controls (filter, More): 48 px high, card colour, hairline.
class _ToolSurface extends StatelessWidget {
  const _ToolSurface({required this.child, this.active = false, this.square = false});
  final Widget child;
  final bool active, square;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // sized by its content (never stretched by a Flexible parent), at least 48 px high, the content centred in it
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: AppTouch.min, minWidth: square ? AppTouch.min : 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: active ? c.primaryTint : c.cardBg,
          borderRadius: AppRadius.chipAll,
          border: Border.all(color: active ? orgInk(context).withValues(alpha: 0.45) : c.divider),
        ),
        child: Padding(
          padding: square ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: AppSpace.sm),
          child: Center(widthFactor: 1, heightFactor: 1, child: child),
        ),
      ),
    );
  }
}

/// ONE dropdown filter: "Active ▾".
class OrgFilterButton<T> extends StatelessWidget {
  const OrgFilterButton({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.defaultValue,
    this.label,
    this.icon = Icons.filter_list_rounded,
  });

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  /// The unfiltered value: any other value tints the button (a filter is on).
  final T? defaultValue;

  /// What is filtered ("Status"), for the tooltip and screen readers.
  final String? label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = defaultValue != null && value != defaultValue;
    final ink = active ? orgInk(context) : c.textMedium;
    final current = options[value] ?? '';
    final name = label ?? t('تصفية', 'Filter');
    return Semantics(
      button: true,
      label: '$name: $current',
      excludeSemantics: true,
      child: PopupMenuButton<T>(
        key: const ValueKey('org.page.filter'),
        tooltip: name,
        initialValue: value,
        onSelected: onChanged,
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
        itemBuilder: (_) => [
          for (final e in options.entries)
            PopupMenuItem<T>(
              value: e.key,
              height: AppTouch.min,
              child: Row(children: [
                SizedBox(
                  width: 24,
                  child: e.key == value ? Icon(Icons.check_rounded, size: 20, color: orgInk(context)) : null,
                ),
                AppSpace.gapXs,
                Flexible(child: Text(e.value, style: AppType.row(context))),
              ]),
            ),
        ],
        child: _ToolSurface(
          active: active,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: ink),
            const SizedBox(width: AppSpace.xs - 2),
            Flexible(
              child: Text(current,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.row(context).copyWith(color: active ? orgInk(context) : c.textDark)),
            ),
            const SizedBox(width: AppSpace.xxs),
            Icon(Icons.expand_more_rounded, size: 20, color: ink),
          ]),
        ),
      ),
    );
  }
}

/// "More" (⋯): the page's secondary actions, each with its icon AND text.
class OrgMoreMenu extends StatelessWidget {
  const OrgMoreMenu({super.key, required this.items, this.compact = false});
  final List<OrgMenuItem> items;

  /// Phones: the ⋯ square only (tooltip + screen-reader label "More").
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = t('المزيد', 'More');
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: PopupMenuButton<int>(
        key: const ValueKey('org.page.more'),
        tooltip: label,
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
        onSelected: (i) => items[i].onTap(),
        itemBuilder: (_) => [
          for (var i = 0; i < items.length; i++)
            PopupMenuItem<int>(
              value: i,
              height: AppTouch.min,
              child: Row(children: [
                Icon(items[i].icon, size: 20, color: items[i].danger ? c.danger : c.textMedium),
                AppSpace.gapSm,
                Flexible(
                  child: Text(items[i].label,
                      style: AppType.row(context).copyWith(color: items[i].danger ? c.danger : c.textDark)),
                ),
              ]),
            ),
        ],
        child: _ToolSurface(
          square: compact,
          child: compact
              ? Icon(Icons.more_horiz_rounded, size: 22, color: c.textMedium)
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.more_horiz_rounded, size: 20, color: c.textMedium),
                  const SizedBox(width: AppSpace.xs - 2),
                  Text(label, style: AppType.row(context)),
                ]),
        ),
      ),
    );
  }
}

/// 2 – 4 equal choices in one calm control (the chosen one raised on a card surface).
class OrgSegmented<T> extends StatelessWidget {
  const OrgSegmented({super.key, required this.value, required this.options, required this.onChanged});
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // never wider than it reads well: a 1200 px wide switch of three words looks empty
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 160.0 * options.length),
        child: _segments(context, c),
      ),
    );
  }

  Widget _segments(BuildContext context, ThemeConfigProvider c) {
    // The track's inset belongs to each segment's touch area (a cell is the full 48 high, the pill inside it 40), so
    // the tap target meets the 48 x 48 guideline while the pills look the same.
    final last = options.length - 1;
    return Container(
      decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.chip + AppSpace.xxs)),
      child: Row(children: [
        for (final (i, (v, label)) in options.indexed)
          Expanded(
            child: Semantics(
              button: true,
              selected: v == value,
              onTap: v == value ? null : () => onChanged(v),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: v == value ? null : () => onChanged(v),
                child: Padding(
                  padding: EdgeInsetsDirectional.only(top: AppSpace.xxs, bottom: AppSpace.xxs, start: i == 0 ? AppSpace.xxs : 0, end: i == last ? AppSpace.xxs : 0),
                  child: Material(
                color: v == value ? c.cardBg : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.chipAll,
                  side: v == value ? BorderSide(color: c.divider) : BorderSide.none,
                ),
                child: InkWell(
                  key: ValueKey('org.segment.$v'),
                  borderRadius: AppRadius.chipAll,
                  excludeFromSemantics: true,
                  onTap: v == value ? null : () => onChanged(v),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: AppTouch.min - 2 * AppSpace.xxs),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: AppType.row(context).copyWith(
                            fontWeight: v == value ? FontWeight.w600 : FontWeight.w500,
                            color: v == value ? c.textDark : c.textMedium,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// The estimated width of an AppChoiceChip (12.5 w700 text + 12 px padding each side + a 16 px icon + 6).
double _chipWidth(BuildContext context, String label, {bool icon = true}) {
  final tp = TextPainter(
    text: TextSpan(text: label, style: TextStyle(fontFamily: AppFonts.family, fontSize: 14, fontWeight: FontWeight.w600)),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final w = tp.width + 2 * 12 + 2 + (icon ? 22 : 0);
  tp.dispose();
  return w;
}

class _PartTab extends StatelessWidget {
  const _PartTab({super.key, required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = selected ? orgInk(context) : c.textMedium;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: selected ? null : onTap,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.chip)),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: selected ? orgInk(context) : Colors.transparent, width: 2)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: ink),
            const SizedBox(width: AppSpace.xs - 2),
            Text(label,
                maxLines: 1,
                style: AppType.row(context).copyWith(
                    color: selected ? orgInk(context) : c.textMedium, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}

/// A page's parts (Calendar · Levels · Departments …): quiet underlined tabs when they all fit, else ONE full-width button
/// with the current part and ▾ that lists them all — never a row that runs off the edge.
class OrgPartPicker extends StatelessWidget {
  const OrgPartPicker({super.key, required this.parts, required this.index, required this.onChanged});
  final List<(String, IconData)> parts;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      var need = 0.0;
      for (final p in parts) {
        need += _chipWidth(context, p.$1) + AppSpace.xs;
      }
      if (need * 1.08 <= box.maxWidth) {
        // quiet underlined tabs: one level below the section's pill chips, so the two rows never look alike
        return DecoratedBox(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.divider))),
          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            for (var i = 0; i < parts.length; i++)
              _PartTab(key: ValueKey('org.part.$i'), label: parts[i].$1, icon: parts[i].$2, selected: i == index, onTap: () => onChanged(i)),
          ])),
        );
      }
      final cur = parts[index.clamp(0, parts.length - 1)];
      return Semantics(
        button: true,
        label: '${t('القسم', 'Part')}: ${cur.$1}',
        excludeSemantics: true,
        // a bottom sheet (thumb-friendly on a phone; a full-width anchored menu was placed off-screen)
        child: InkWell(
          key: const ValueKey('org.part.picker'),
          borderRadius: AppRadius.chipAll,
          onTap: () async {
            final picked = await showAppSheet<int>(
              context,
              (ctx) => SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    AppSheetHeader(t('اختر الجزء', 'Choose a part')),
                    for (var i = 0; i < parts.length; i++)
                      ListTile(
                        key: ValueKey('org.part.option.$i'),
                        minTileHeight: AppTouch.min,
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll),
                        selected: i == index,
                        selectedTileColor: c.primaryTint,
                        leading: Icon(parts[i].$2, color: i == index ? orgInk(context) : c.textMedium),
                        title: Text(parts[i].$1,
                            style: AppType.row(ctx).copyWith(
                                color: i == index ? orgInk(context) : c.textDark, fontWeight: i == index ? FontWeight.w600 : FontWeight.w500)),
                        trailing: i == index ? Icon(Icons.check_rounded, color: orgInk(context)) : null,
                        onTap: () => Navigator.pop(ctx, i),
                      ),
                  ]),
                ),
              ),
            );
            if (picked != null && picked != index) onChanged(picked);
          },
          child: _ToolSurface(
            child: Row(children: [
              Icon(cur.$2, size: 20, color: orgInk(context)),
              AppSpace.gapXs,
              Expanded(
                child: Text(cur.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
              ),
              Text('${index + 1}/${parts.length}', style: AppType.meta(context)),
              const SizedBox(width: AppSpace.xxs),
              Icon(Icons.expand_more_rounded, size: 22, color: c.textMedium),
            ]),
          ),
        ),
      );
    });
  }
}

/// The section hub's sub-page chips: one row that scrolls sideways when it does not fit, with a soft fade on the
/// edge(s) that hide more chips; the chosen chip is scrolled into view.
class OrgSectionChips extends StatefulWidget {
  const OrgSectionChips({super.key, required this.items, required this.index, required this.onChanged});
  final List<(String, IconData)> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  State<OrgSectionChips> createState() => _OrgSectionChipsState();
}

class _OrgSectionChipsState extends State<OrgSectionChips> {
  final _scroll = ScrollController();
  late List<GlobalKey> _keys;
  bool _fadeStart = false, _fadeEnd = false;
  bool _shown = false; // the first reveal jumps

  @override
  void initState() {
    super.initState();
    _keys = [for (final _ in widget.items) GlobalKey()];
    _scroll.addListener(_edges);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _edges();
      _reveal();
    });
  }

  @override
  void didUpdateWidget(OrgSectionChips old) {
    super.didUpdateWidget(old);
    if (old.items.length != widget.items.length) _keys = [for (final _ in widget.items) GlobalKey()];
    if (old.index != widget.index) WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _edges() {
    if (!mounted || !_scroll.hasClients) return;
    final p = _scroll.position;
    final s = p.pixels > 1;
    final e = p.pixels < p.maxScrollExtent - 1;
    if (s != _fadeStart || e != _fadeEnd) {
      setState(() {
        _fadeStart = s;
        _fadeEnd = e;
      });
    }
  }

  void _reveal() {
    if (!mounted) return;
    final i = widget.index;
    final ctx = i >= 0 && i < _keys.length ? _keys[i].currentContext : null;
    if (ctx != null) {
      // jump when no ticker runs (an offstage tab, the first frame): an animation would stall there
      final animate = _shown && TickerMode.valuesOf(context).enabled;
      Scrollable.ensureVisible(ctx, alignment: 0.5, duration: animate ? AppMotion.of(context).base : Duration.zero, curve: AppMotion.curve);
      _shown = true;
    }
    _edges();
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final row = SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      child: Row(children: [
        for (var k = 0; k < widget.items.length; k++)
          Padding(
            key: _keys[k],
            padding: EdgeInsetsDirectional.only(end: k == widget.items.length - 1 ? 0 : AppSpace.xs),
            child: AppChoiceChip(
              key: ValueKey('org.section.chip.$k'),
              label: widget.items[k].$1,
              icon: widget.items[k].$2,
              selected: k == widget.index,
              onTap: () => widget.onChanged(k),
            ),
          ),
      ]),
    );
    // ONE tree shape whether or not it fades: swapping the parent would rebuild the scroll view and lose its offset
    // the fade sits on the hidden edge(s): start = left in LTR, right in RTL
    final left = rtl ? _fadeEnd : _fadeStart;
    final right = rtl ? _fadeStart : _fadeEnd;
    return Align(alignment: AlignmentDirectional.centerStart, child: ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => LinearGradient(
        colors: [
          left ? Colors.transparent : Colors.black,
          Colors.black,
          Colors.black,
          right ? Colors.transparent : Colors.black,
        ],
        stops: const [0, 0.16, 0.84, 1],
      ).createShader(r),
      child: row,
    ));
  }
}

/// The primary colour as ink for text, icons and lines on a card: on a dark theme it is lifted toward white, since
/// the server's primary (a deep blue by default) on a dark card fails WCAG AA.
Color orgInk(BuildContext context) {
  final c = context.colors;
  return c.isDark ? Color.lerp(c.primary, Colors.white, 0.5)! : c.primary;
}
