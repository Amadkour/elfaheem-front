// lib/features/admin/admin_list.dart
// ONE list language for the whole admin area:
//   • PagedList        – server-paged infinite scroll (+ "Showing X of Y" progress card + footer)
//   • AdminSimpleList  – same look for lists that are loaded in one go (categories, versions …)
//   • RowCard          – the premium card every row uses (accent stripe, soft shadow)
//   • InfoChip / IconBadge / AdminAvatar – small building blocks so rows look alike
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../../utils/widget/paged_progress.dart';
import 'admin_common.dart';
import 'admin_premium_widgets.dart';
import 'admin_providers.dart';
import 'admin_table_export.dart' show AppExportPill, exportPagedList;
import '../../design/app_table_export.dart' show AppTableExport;
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton, AppRefresh;
import 'package:flutter_education_app/core/display/app_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Paged list (same pagination progress as the user lists)
// ─────────────────────────────────────────────────────────────────────────────

class PagedList<P extends AdminPagedProvider> extends StatefulWidget {
  const PagedList({
    super.key,
    this.itemBuilder,
    this.indexedBuilder,
    this.header,
    this.emptyText,
    this.countIcon,
    this.showCountFrom = 20,
    this.export,
  }) : assert(
  itemBuilder != null || indexedBuilder != null,
  'give itemBuilder or indexedBuilder',
  );

  /// Called with the raw JSON row.
  final Widget Function(BuildContext, Map<String, dynamic>)? itemBuilder;

  /// Use instead of [itemBuilder] when the provider exposes typed items
  /// (e.g. `(ctx, p, i) => _Card(p.items[i])`).
  final Widget Function(BuildContext, P provider, int index)? indexedBuilder;
  final Widget? header;
  final String? emptyText;

  /// Icon on the "Showing X of Y" card.
  final IconData? countIcon;

  /// The progress card appears once the total is bigger than this (one page).
  final int showCountFrom;

  /// Builds the export table from EVERY row (all pages are fetched first) — shows an Excel · Word · PDF pill.
  final AppTableExport Function(List<Map<String, dynamic>> rows)? export;

  @override
  State<PagedList<P>> createState() => _PagedListState<P>();
}

class _PagedListState<P extends AdminPagedProvider> extends State<PagedList<P>> {
  final _scroll = ScrollController();
  int _fillRows = -1; // rows count at the last "fill the screen" attempt

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// Near the bottom → append the next page.
  void _onScroll() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 320) {
      context.read<P>().loadMore();
    }
  }

  /// Too few rows to scroll → keep loading until the screen is full.
  /// Runs once per row-count so a failing request can never loop.
  void _fillViewport(P p) {
    if (!p.hasMore || p.loadingMore || p.isLoading || p.error != null) return;
    if (p.rows.length == _fillRows) return;
    _fillRows = p.rows.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_scroll.position.maxScrollExtent <= 0) p.loadMore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<P>();

    Widget body;
    if (!p.loaded && p.isLoading) {
      body = const AppListSkeleton();
    } else if (p.error != null && p.rows.isEmpty) {
      body = ErrorRetry(message: p.error!, onRetry: p.refresh);
    } else if (p.rows.isEmpty) {
      body = AppRefresh(
        onRefresh: p.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 320,
              child: EmptyState(widget.emptyText ?? 'admin_nothing_here_yet'.tr),
            ),
          ],
        ),
      );
    } else {
      _fillViewport(p);
      body = AppRefresh(
        onRefresh: p.refresh,
        child: ListView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 90),
          itemCount: p.rows.length + 1,
          itemBuilder: (ctx, i) {
            if (i == p.rows.length) {
              return PagedListFooter(
                loadingMore: p.loadingMore,
                hasMore: p.hasMore,
              );
            }
            return widget.indexedBuilder != null
                ? widget.indexedBuilder!(ctx, p, i)
                : widget.itemBuilder!(ctx, p.rows[i]);
          },
        ),
      );
    }

    return Column(
      children: [
        if (widget.header != null) widget.header!,
        if (widget.export != null && p.rows.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 2, 14, 8),
            child: Align(alignment: AlignmentDirectional.centerEnd, child: AppExportPill(onTap: () => exportPagedList(context, p, widget.export!))),
          ),
        // pinned "Showing 20 of 134" progress
        if (p.rows.isNotEmpty && p.total > widget.showCountFrom)
          PagedCountCard(
            loaded: p.rows.length,
            total: p.total,
            loadingMore: p.loadingMore,
            done: !p.hasMore,
            icon: widget.countIcon ?? Icons.format_list_numbered_rounded,
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          ),
        Expanded(child: body),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Simple (non-paged) list — identical states, spacing and footer
// ─────────────────────────────────────────────────────────────────────────────

class AdminSimpleList extends StatelessWidget {
  const AdminSimpleList({
    super.key,
    required this.loading,
    required this.error,
    required this.isEmpty,
    required this.emptyText,
    required this.onRefresh,
    required this.children,
    this.header,
    this.emptyIcon = Icons.inbox_rounded,
    this.countIcon,
  });

  final bool loading;
  final String? error;
  final bool isEmpty;
  final String emptyText;
  final IconData emptyIcon;
  final Future<void> Function() onRefresh;
  final List<Widget> children;
  final Widget? header;
  final IconData? countIcon;

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (isEmpty && loading) {
      body = const AppListSkeleton();
    } else if (isEmpty && error != null) {
      body = ErrorRetry(message: error!, onRetry: onRefresh);
    } else if (isEmpty) {
      body = AppRefresh(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: 320, child: EmptyState(emptyText, icon: emptyIcon)),
          ],
        ),
      );
    } else {
      body = AppRefresh(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 90),
          children: [
            ...children,
            const PagedListFooter(loadingMore: false, hasMore: false),
          ],
        ),
      );
    }
    return Column(
      children: [
        ?header,
        if (children.length > 20)
          PagedCountCard(
            loaded: children.length,
            total: children.length,
            loadingMore: false,
            done: true,
            icon: countIcon ?? Icons.format_list_numbered_rounded,
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          ),
        Expanded(child: body),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Row card
// ─────────────────────────────────────────────────────────────────────────────

/// The standard card for every list row.
/// [accent] paints a slim stripe on the start edge (status colour).
class RowCard extends StatelessWidget {
  const RowCard({super.key, required this.child, this.onTap, this.accent});

  final Widget child;
  final VoidCallback? onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(c.radiusLarge - 4);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: radius,
          border: Border.all(color: c.divider),
          boxShadow: c.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (accent != null) Container(width: 4, color: accent),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: child,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tinted rounded-square icon (leading icon of a row).
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, this.color, {super.key, this.size = 44});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => ServiceIcon(
    icon: icon,
    size: size,
    // light → your theme colour (the colour passed in is already a theme colour)
    colors: AdminPalette.soft(color),
  );
}

/// Round avatar: photo when [url] is set, otherwise the first letter.
class AdminAvatar extends StatelessWidget {
  const AdminAvatar({super.key, required this.name, this.url, this.size = 44});

  final String name;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [c.primary.withValues(alpha: 0.22), c.primary.withValues(alpha: 0.10)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Text(
        name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase(),
        style: TextStyle(
          fontFamily: AppFonts.family,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.4,
          color: c.primary,
        ),
      ),
    );
    if (url == null || url!.isEmpty) return fallback;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          url!,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        ),
      ),
    );
  }
}

/// Small pill with an icon: method, date, plan, count …
class InfoChip extends StatelessWidget {
  const InfoChip(this.icon, this.label, this.color, {super.key});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.22)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppFonts.family,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter chips
// ─────────────────────────────────────────────────────────────────────────────

/// Horizontal row of filter chips.
class FilterChips<T> extends StatelessWidget {
  const FilterChips({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          for (final e in options.entries)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                showCheckmark: false,
                shape: const StadiumBorder(),
                side: BorderSide(
                  color: e.key == value ? c.primary : c.divider,
                ),
                backgroundColor: c.cardBg,
                label: Text(
                  e.value,
                  style: TextStyle(
                    fontFamily: AppFonts.family,
                    fontSize: 12.5,
                    fontWeight: e.key == value ? FontWeight.w800 : FontWeight.w600,
                    color: e.key == value ? c.onHero : c.textDark,
                  ),
                ),
                selected: e.key == value,
                selectedColor: c.primary,
                onSelected: (_) => onChanged(e.key),
              ),
            ),
        ],
      ),
    );
  }
}