// lib/features/admin/admin_list.dart — generic infinite-scroll list for AdminPagedProvider.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../../utils/widget/app_loading_indicator.dart';
import 'admin_common.dart';
import 'admin_providers.dart';

class PagedList<P extends AdminPagedProvider> extends StatefulWidget {
  const PagedList({
    super.key,
    required this.itemBuilder,
    this.header,
    this.emptyText,
  });

  /// Called with the raw JSON row.
  final Widget Function(BuildContext, Map<String, dynamic>) itemBuilder;
  final Widget? header;
  final String? emptyText;

  @override
  State<PagedList<P>> createState() => _PagedListState<P>();
}

class _PagedListState<P extends AdminPagedProvider> extends State<PagedList<P>> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        context.read<P>().loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<P>();
    final c = context.colors;

    Widget body;
    if (!p.loaded && p.isLoading) {
      body = const Center(child: AppLoadingIndicator());
    } else if (p.error != null && p.rows.isEmpty) {
      body = ErrorRetry(message: p.error!, onRetry: p.refresh);
    } else if (p.rows.isEmpty) {
      body = EmptyState(widget.emptyText ?? 'admin_nothing_here_yet'.tr);
    } else {
      body = ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 90),
        itemCount: p.rows.length + 1,
        itemBuilder: (ctx, i) {
          if (i == p.rows.length) {
            return p.loadingMore
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: AppLoadingIndicator()))
                : (p.hasMore
                    ? const SizedBox(height: 40)
                    : Padding(
                        padding: const EdgeInsets.all(12),
                        child: Center(
                          child: Text('${p.total} ${'admin_items'.tr}',
                              style: TextStyle(
                                  fontFamily: 'tajawal',
                                  fontSize: 12,
                                  color: c.textLight)),
                        ),
                      ));
          }
          return widget.itemBuilder(ctx, p.rows[i]);
        },
      );
    }

    return Column(children: [
      if (widget.header != null) widget.header!,
      Expanded(
        child: RefreshIndicator(onRefresh: p.refresh, child: body),
      ),
    ]);
  }
}

/// A standard card used by list rows.
class RowCard extends StatelessWidget {
  const RowCard({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.divider),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Horizontal row of filter chips.
class FilterChips<T> extends StatelessWidget {
  const FilterChips({super.key, required this.options, required this.value, required this.onChanged});
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
                label: Text(e.value,
                    style: TextStyle(
                        fontFamily: 'tajawal',
                        fontSize: 12.5,
                        color: e.key == value ? Colors.white : c.textDark)),
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
