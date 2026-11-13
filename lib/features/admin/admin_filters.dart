// lib/features/admin/admin_filters.dart
//
// The premium search + filter UI shared by every admin list:
//
//   AdminFilterBar        search box · filter button (with badge) · removable chips · result count
//   showAdminFilterSheet  bottom sheet built from a list of FilterSpec rows + an optional sort
//
// A page only declares WHAT can be filtered (see the `_specs` in each page);
// state, debounce, stale-response protection and the API call live in the providers.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';

import '../../utils/widget/primary_button.dart';
import 'admin_common.dart';
import 'admin_filter_models.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton;
import 'package:flutter_education_app/design/app_buttons.dart' show AppIconButton, AppIconButtonVariant;
import 'package:flutter_education_app/design/app_search_field.dart';
import 'package:flutter_education_app/design/app_username.dart' show usernameFrom;
import 'admin_money_p8.dart' show parseAmountLoose;


// ═════════════════════════════════════════════════════════════════════════════
//  helpers
// ═════════════════════════════════════════════════════════════════════════════

bool _isSet(Map<String, Object?> v, FilterSpec s) =>
    s.keys.any((k) => v[k] != null);

/// Filter rows that are currently active, not counting [quickKeys] (those have their own chips).
int activeFilterCount(
  AdminQueryHost host,
  List<FilterSpec> specs,
  Set<String> quickKeys,
) {
  final n = specs
      .where((s) => !quickKeys.contains(s.key) && _isSet(host.adv, s))
      .length;
  return n + (host.sort != null ? 1 : 0);
}

String _fmtDate(Object? v) => encodeFilterValue(v) ?? '';

/// Lookup rows are small and stable → cached for the whole session.
final Map<String, List<LookupValue>> _lookupCache = {};

Future<List<LookupValue>> _fetchLookup(
  String kind, {
  String search = '',
}) async {
  final cacheable = search.isEmpty;
  if (cacheable && _lookupCache.containsKey(kind)) return _lookupCache[kind]!;
  final r = await ApiClient().get(
    '/api/v1/admin/lookup/$kind',
    queryParams: {if (search.isNotEmpty) 'search': search},
  );
  final rows = r is Map ? asMapList(r['items']) : <Map<String, dynamic>>[];
  final out = [
    for (final m in rows)
      LookupValue(
        m['id'] as Object,
        '${m['label'] ?? m['id']}'
        '${usernameFrom(m) == null ? '' : '  ·  @${usernameFrom(m)}'}'
        '${(m['sub'] ?? '').toString().isEmpty ? '' : '  ·  ${m['sub']}'}',
      ),
  ];
  if (cacheable) _lookupCache[kind] = out;
  return out;
}

// ═════════════════════════════════════════════════════════════════════════════
//  AdminFilterBar
// ═════════════════════════════════════════════════════════════════════════════

class AdminFilterBar extends StatelessWidget {
  const AdminFilterBar({
    super.key,
    required this.host,
    required this.hintKey,
    required this.specs,
    this.sort,
    this.quickKeys = const {},
    this.padding = const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xs),
  });

  final AdminQueryHost host;

  /// Translation key of the search hint.
  final String hintKey;
  final List<FilterSpec> specs;
  final SortSpec? sort;

  /// Filters shown as quick chips by the page itself → hidden from the chip row / badge.
  final Set<String> quickKeys;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final count = activeFilterCount(host, specs, quickKeys);
    final hasQuery = host.hasActiveQuery;
    final total = host.resultCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: padding,
          child: Row(
            children: [
              Expanded(
                child: AdminSearchField(
                  hint: hintKey.tr,
                  value: host.search,
                  onChanged: host.setSearch,
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              _FilterButton(
                count: count,
                onTap: () => showAdminFilterSheet(
                  context,
                  host: host,
                  specs: specs,
                  sort: sort,
                ),
              ),
            ],
          ),
        ),
        _ActiveChips(
          host: host,
          specs: specs,
          sort: sort,
          quickKeys: quickKeys,
        ),
        if (hasQuery && total != null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, 2, AppSpace.md, 2),
            child: Row(
              children: [
                Icon(Icons.manage_search_rounded, size: 16, color: c.textLight),
                const SizedBox(width: AppSpace.xs),
                Flexible(child: Text(
                  'admin_results_count'.tr.replaceAll('{n}', '$total'),
                  style: AppType.meta(context).copyWith(color: c.textLight),
                )),
              ],
            ),
          ),
      ],
    );
  }
}

// ── search field ─────────────────────────────────────────────────────────────

class AdminSearchField extends StatefulWidget {
  const AdminSearchField({
    super.key,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String hint;

  /// The provider's current search text — when it changes from outside ("clear all") the box follows.
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<AdminSearchField> createState() => _AdminSearchFieldState();
}

class _AdminSearchFieldState extends State<AdminSearchField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);

  /// The last text handed to [AdminSearchField.onChanged]. [AppSearchField] already waits [kSearchDelay] after the
  /// LAST keystroke (and fires at once on clear), so this only drops repeats.
  late String _sent = widget.value.trim();

  void _send(String v) {
    final q = v.trim();
    if (q == _sent) return; // nothing new -> no request
    _sent = q;
    widget.onChanged(v);
  }

  @override
  void didUpdateWidget(covariant AdminSearchField old) {
    super.didUpdateWidget(old);
    // Follow the provider only for outside changes ("clear all filters"): while the person types, the provider's
    // value is the text we just sent (or older) and must never overwrite the field.
    final v = widget.value.trim();
    if (v != old.value.trim() && v != _sent && v != _c.text.trim()) {
      _c.text = widget.value;
      _sent = v;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AppSearchField(hint: widget.hint, controller: _c, debounce: kSearchDelay, onChanged: _send);
}

// ── filter button with badge ─────────────────────────────────────────────────

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = count > 0;
    return Tooltip(
      message: 'admin_filter_title'.tr,
      child: Material(
        color: active ? c.primary : c.inputBg,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.control),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.tune_rounded,
                  color: active ? c.onHero : c.textMedium,
                ),
                if (active)
                  PositionedDirectional(
                    top: 5,
                    end: 5,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 17),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.xxs,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: c.danger,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                      ),
                      child: Text(
                        '$count',
                        textAlign: TextAlign.center,
                        style: AppType.overline(context).copyWith(color: c.onHero),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── removable chips ──────────────────────────────────────────────────────────

class _ActiveChips extends StatelessWidget {
  const _ActiveChips({
    required this.host,
    required this.specs,
    required this.sort,
    required this.quickKeys,
  });

  final AdminQueryHost host;
  final List<FilterSpec> specs;
  final SortSpec? sort;
  final Set<String> quickKeys;

  String? _describe(FilterSpec s) {
    final v = host.adv;
    final title = s.labelKey.tr;
    switch (s.kind) {
      case FilterKind.choice:
        final raw = v[s.key];
        if (raw == null) return null;
        final k = s.options['$raw'];
        return '$title: ${k == null ? raw : k.tr}';
      case FilterKind.remoteChoice:
      case FilterKind.lookup:
        final raw = v[s.key];
        if (raw == null) return null;
        return '$title: ${raw is LookupValue ? raw.label : raw}';
      case FilterKind.tri:
        final raw = v[s.key];
        if (raw is! bool) return null;
        return '$title: ${(raw ? s.yesKey : s.noKey).tr}';
      case FilterKind.dateRange:
        final a = v[s.key], b = v[s.keyTo];
        if (a == null && b == null) return null;
        return '$title: ${a == null ? '…' : _fmtDate(a)} $dirArrow ${b == null ? '…' : _fmtDate(b)}';
      case FilterKind.numberRange:
        final a = v[s.key], b = v[s.keyTo];
        if (a == null && b == null) return null;
        return '$title: ${a == null ? '…' : encodeFilterValue(a)} – ${b == null ? '…' : encodeFilterValue(b)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final chips = <Widget>[];

    for (final s in specs) {
      if (quickKeys.contains(s.key)) continue;
      final text = _describe(s);
      if (text == null) continue;
      chips.add(_RemovableChip(text, () => host.removeAdv(s.keys)));
    }
    if (sort != null && host.sort != null) {
      final k = sort!.options[host.sort!];
      chips.add(
        _RemovableChip(
          '${'admin_filter_sort'.tr}: ${k == null ? host.sort : k.tr}',
          () => host.setSort(null),
          icon: Icons.sort_rounded,
        ),
      );
    }
    if (chips.isEmpty && host.search.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xxs),
        children: [
          ...chips,
          if (host.hasActiveQuery)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 2),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: c.danger,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.filter_alt_off_rounded, size: 17),
                label: Text(
                  'admin_filter_clear_all'.tr,
                  style: AppType.meta(context),
                ),
                onPressed: host.clearAll,
              ),
            ),
        ],
      ),
    );
  }
}

class _RemovableChip extends StatelessWidget {
  const _RemovableChip(this.text, this.onRemove, {this.icon});

  final String text;
  final VoidCallback onRemove;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
      child: InputChip(
        avatar: icon == null ? null : Icon(icon, size: 16, color: c.primary),
        label: Text(
          text,
          style: AppType.meta(context).copyWith(color: c.primary, fontWeight: FontWeight.w600),
        ),
        backgroundColor: c.primary.withValues(alpha: 0.10),
        side: BorderSide(color: c.primary.withValues(alpha: 0.35)),
        deleteIconColor: c.primary,
        visualDensity: VisualDensity.compact,
        onDeleted: onRemove,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Filter sheet
// ═════════════════════════════════════════════════════════════════════════════

Future<void> showAdminFilterSheet(
  BuildContext context, {
  required AdminQueryHost host,
  required List<FilterSpec> specs,
  SortSpec? sort,
}) => showAdminSheet(
  context,
  (ctx) => _FilterSheet(host: host, specs: specs, sort: sort),
);

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.host,
    required this.specs,
    required this.sort,
  });

  final AdminQueryHost host;
  final List<FilterSpec> specs;
  final SortSpec? sort;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final Map<String, Object?> draft = Map.of(widget.host.adv);
  late String? draftSort = widget.host.sort;

  int get _count =>
      widget.specs.where((s) => _isSet(draft, s)).length +
      (draftSort != null ? 1 : 0);

  void _set(String key, Object? v) =>
      setState(() => v == null ? draft.remove(key) : draft[key] = v);

  void _reset() => setState(() {
    for (final s in widget.specs) {
      for (final k in s.keys) {
        draft.remove(k);
      }
    }
    draftSort = null;
  });

  void _apply() {
    // keep filters this sheet does not own, replace the ones it does
    final owned = widget.specs.expand((s) => s.keys).toSet();
    final merged = <String, Object?>{
      for (final e in widget.host.adv.entries)
        if (!owned.contains(e.key)) e.key: e.value,
      for (final e in draft.entries)
        if (owned.contains(e.key) && e.value != null) e.key: e.value,
    };
    widget.host.applyAdv(
      merged,
      sortKey: draftSort == widget.sort?.defaultKey ? null : draftSort,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader('admin_filter_title'.tr),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.sort != null)
                  _Section(
                    title: 'admin_filter_sort'.tr,
                    child: _Chips<String>(
                      anyLabel: null,
                      value: draftSort ?? widget.sort!.defaultKey,
                      options: {
                        for (final e in widget.sort!.options.entries)
                          e.key: e.value.tr,
                      },
                      onChanged: (v) => setState(() => draftSort = v),
                    ),
                  ),
                for (final s in widget.specs)
                  _Section(title: s.labelKey.tr, child: _build(s)),
                const SizedBox(height: AppSpace.xs),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: c.danger,
                          side: BorderSide(
                            color: c.danger.withValues(alpha: 0.5),
                          ),
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.control),
                          ),
                        ),
                        icon: const Icon(Icons.restart_alt_rounded, size: 19),
                        label: Text(
                          'admin_filter_reset'.tr,
                          style: AppType.body(context),
                        ),
                        onPressed: _count == 0 ? null : _reset,
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      flex: 2,
                      child: PrimaryButton(
                        label: _count == 0
                            ? 'admin_filter_apply'.tr
                            : '${'admin_filter_apply'.tr} ($_count)',
                        onPressed: _apply,
                        isLoading: false,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _build(FilterSpec s) {
    switch (s.kind) {
      case FilterKind.choice:
        return _Chips<String>(
          anyLabel: 'admin_filter_any'.tr,
          value: draft[s.key] as String?,
          options: {for (final e in s.options.entries) e.key: e.value.tr},
          onChanged: (v) => _set(s.key, v),
        );
      case FilterKind.remoteChoice:
        return FutureBuilder<List<LookupValue>>(
          future: _fetchLookup(s.lookup!),
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done)
              return const _MiniLoader();
            final items = snap.data ?? const <LookupValue>[];
            if (items.isEmpty) return Text('admin_filter_no_options'.tr);
            final cur = draft[s.key];
            return _Chips<String>(
              anyLabel: 'admin_filter_any'.tr,
              value: cur is LookupValue ? '${cur.id}' : null,
              options: {for (final i in items) '${i.id}': i.label},
              onChanged: (v) => _set(
                s.key,
                v == null ? null : items.firstWhere((i) => '${i.id}' == v),
              ),
            );
          },
        );
      case FilterKind.tri:
        return _Chips<String>(
          anyLabel: 'admin_filter_any'.tr,
          value: draft[s.key] is bool
              ? ((draft[s.key] as bool) ? 'yes' : 'no')
              : null,
          options: {'yes': s.yesKey.tr, 'no': s.noKey.tr},
          onChanged: (v) => _set(s.key, v == null ? null : v == 'yes'),
        );
      case FilterKind.dateRange:
        return _DateRange(
          from: draft[s.key] as DateTime?,
          to: draft[s.keyTo] as DateTime?,
          onChanged: (a, b) => setState(() {
            a == null ? draft.remove(s.key) : draft[s.key] = a;
            b == null ? draft.remove(s.keyTo) : draft[s.keyTo!] = b;
          }),
        );
      case FilterKind.numberRange:
        return _NumberRange(
          min: draft[s.key] as num?,
          max: draft[s.keyTo] as num?,
          onChanged: (a, b) => setState(() {
            a == null ? draft.remove(s.key) : draft[s.key] = a;
            b == null ? draft.remove(s.keyTo) : draft[s.keyTo!] = b;
          }),
        );
      case FilterKind.lookup:
        return _LookupTile(
          kind: s.lookup!,
          value: draft[s.key] as LookupValue?,
          onChanged: (v) => _set(s.key, v),
        );
    }
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpace.xs),
          child,
        ],
      ),
    );
  }
}

class _MiniLoader extends StatelessWidget {
  const _MiniLoader();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: AppSpace.xs),
    child: SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );
}

/// Single-select chips. [anyLabel] != null adds a leading "Any" chip that sets null.
class _Chips<T> extends StatelessWidget {
  const _Chips({
    required this.anyLabel,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String? anyLabel;
  final T? value;
  final Map<T, String> options;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget chip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
      label: Text(
        label,
        style: AppType.meta(context).copyWith(color: selected ? c.primary : c.textMedium, fontWeight: FontWeight.w600),
      ),
      selected: selected,
      showCheckmark: false,
      selectedColor: c.primaryWash,
      backgroundColor: c.inputBg,
      side: BorderSide(color: selected ? c.primary : c.divider),
      onSelected: (_) => onTap(),
    );

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        if (anyLabel != null)
          chip(anyLabel!, value == null, () => onChanged(null)),
        for (final e in options.entries)
          chip(e.value, value == e.key, () => onChanged(e.key)),
      ],
    );
  }
}

// ── date range with presets ──────────────────────────────────────────────────

class _DateRange extends StatelessWidget {
  const _DateRange({
    required this.from,
    required this.to,
    required this.onChanged,
  });

  final DateTime? from;
  final DateTime? to;
  final void Function(DateTime? from, DateTime? to) onChanged;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<DateTime?> _pick(BuildContext context, DateTime? initial) =>
      showDatePicker(
        context: context,
        initialDate: initial ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );

  @override
  Widget build(BuildContext context) {
    final today = _day(DateTime.now());
    final presets = <String, (DateTime, DateTime)>{
      'admin_filter_today': (today, today),
      'admin_filter_last_7_days': (
        today.subtract(const Duration(days: 6)),
        today,
      ),
      'admin_filter_last_30_days': (
        today.subtract(const Duration(days: 29)),
        today,
      ),
      'admin_filter_this_month': (DateTime(today.year, today.month), today),
    };
    final c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final e in presets.entries)
              ActionChip(
                label: Text(
                  e.key.tr,
                  style: AppType.meta(context).copyWith(color: c.textMedium),
                ),
                backgroundColor: c.inputBg,
                side: BorderSide(color: c.divider),
                onPressed: () => onChanged(e.value.$1, e.value.$2),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        Row(
          children: [
            Expanded(
              child: _DateTile(
                label: 'admin_filter_from'.tr,
                value: from,
                onTap: () async {
                  final d = await _pick(context, from ?? to);
                  if (d != null)
                    onChanged(
                      _day(d),
                      to != null && to!.isBefore(d) ? _day(d) : to,
                    );
                },
                onClear: () => onChanged(null, to),
              ),
            ),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: _DateTile(
                label: 'admin_filter_to'.tr,
                value: to,
                onTap: () async {
                  final d = await _pick(context, to ?? from);
                  if (d != null)
                    onChanged(
                      from != null && from!.isAfter(d) ? _day(d) : from,
                      _day(d),
                    );
                },
                onClear: () => onChanged(from, null),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.control),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.xxs, AppSpace.xs),
        decoration: BoxDecoration(
          color: c.inputBg,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: value == null ? c.divider : c.primary),
        ),
        child: Row(
          children: [
            Icon(
              Icons.event_rounded,
              size: 18,
              color: value == null ? c.textLight : c.primary,
            ),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppType.overline(context).copyWith(color: c.textLight),
                  ),
                  Text(
                    value == null ? '—' : _fmtDate(value),
                    textDirection: TextDirection.ltr,
                    style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if (value != null)
              IconButton(tooltip: t('مسح', 'Clear'), 
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, size: 16, color: c.textLight),
                onPressed: onClear,
              ),
          ],
        ),
      ),
    );
  }
}

// ── number range ─────────────────────────────────────────────────────────────

class _NumberRange extends StatefulWidget {
  const _NumberRange({
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final num? min;
  final num? max;
  final void Function(num? min, num? max) onChanged;

  @override
  State<_NumberRange> createState() => _NumberRangeState();
}

class _NumberRangeState extends State<_NumberRange> {
  late final TextEditingController _min = TextEditingController(
    text: encodeFilterValue(widget.min) ?? '',
  );
  late final TextEditingController _max = TextEditingController(
    text: encodeFilterValue(widget.max) ?? '',
  );

  @override
  void didUpdateWidget(covariant _NumberRange old) {
    super.didUpdateWidget(old);
    // "Reset" in the sheet clears the draft → clear the boxes too
    if (widget.min == null &&
        _min.text.isNotEmpty &&
        num.tryParse(_min.text) != null)
      _min.clear();
    if (widget.max == null &&
        _max.text.isNotEmpty &&
        num.tryParse(_max.text) != null)
      _max.clear();
  }

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(
    parseAmountLoose(_min.text),
    parseAmountLoose(_max.text),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    InputDecoration deco(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: AppType.label(context).copyWith(color: c.textLight),
      isDense: true,
      filled: true,
      fillColor: c.inputBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: c.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: c.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: c.primary),
      ),
    );

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _min,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            decoration: deco('admin_filter_min'.tr),
            onChanged: (_) => _emit(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
          child: Text('–', style: TextStyle(color: c.textLight)),
        ),
        Expanded(
          child: TextField(
            controller: _max,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            decoration: deco('admin_filter_max'.tr),
            onChanged: (_) => _emit(),
          ),
        ),
      ],
    );
  }
}

// ── lookup picker ────────────────────────────────────────────────────────────

class _LookupTile extends StatelessWidget {
  const _LookupTile({
    required this.kind,
    required this.value,
    required this.onChanged,
  });

  final String kind;
  final LookupValue? value;
  final ValueChanged<LookupValue?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.control),
      onTap: () => showAdminSheet(
        context,
        (ctx) => _LookupPicker(kind: kind, onPick: (v) => onChanged(v)),
      ),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.xxs, AppSpace.xs),
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(
          color: c.inputBg,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: value == null ? c.divider : c.primary),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              size: 18,
              color: value == null ? c.textLight : c.primary,
            ),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Text(
                value?.label ?? 'admin_filter_any'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.label(context).copyWith(color: value == null ? c.textLight : c.textDark),
              ),
            ),
            if (value != null)
              IconButton(tooltip: t('مسح', 'Clear'), 
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close_rounded, size: 18, color: c.textLight),
                onPressed: () => onChanged(null),
              )
            else
              Icon(Icons.keyboard_arrow_down_rounded, color: c.textLight),
            const SizedBox(width: AppSpace.xxs),
          ],
        ),
      ),
    );
  }
}

class _LookupPicker extends StatefulWidget {
  const _LookupPicker({required this.kind, required this.onPick});

  final String kind;
  final ValueChanged<LookupValue> onPick;

  @override
  State<_LookupPicker> createState() => _LookupPickerState();
}

class _LookupPickerState extends State<_LookupPicker> {
  final _c = TextEditingController();
  Timer? _t;
  int _gen = 0;
  bool _loading = true;
  bool _failed = false;
  List<LookupValue> _items = [];

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final r = await _fetchLookup(widget.kind, search: q.trim());
      if (!mounted || gen != _gen) return;
      setState(() {
        _items = r;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader('admin_filter_pick'.tr),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
          child: AdminSearchField(
            hint: 'admin_filter_search_hint'.tr,
            value: _c.text,
            // AdminSearchField already waits 1 s after the last key.
            onChanged: (v) {
              _c.text = v;
              _load(v);
            },
          ),
        ),
        SizedBox(
          height: 340,
          child: _loading
              ? const AppListSkeleton()
              : _failed
              ? Center(child: Text('admin_could_not_load_data'.tr))
              : _items.isEmpty
              ? Center(
                  child: Text(
                    'admin_filter_no_results'.tr,
                    style: TextStyle(color: c.textLight),
                  ),
                )
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: c.divider),
                  itemBuilder: (ctx, i) {
                    final it = _items[i];
                    return ListTile(
                      title: Text(
                        it.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.body(context).copyWith(color: c.textDark),
                      ),
                      onTap: () {
                        widget.onPick(it);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
        ),
        const SizedBox(height: AppSpace.sm),
      ],
    );
  }
}

/// The "Filters" button with its active-count badge, for pages that lay their own header out (the people tables).
class AdminFilterButton extends StatelessWidget {
  const AdminFilterButton({super.key, required this.host, required this.specs, this.sort, this.quickKeys = const {}});

  final AdminQueryHost host;
  final List<FilterSpec> specs;
  final SortSpec? sort;
  final Set<String> quickKeys;

  @override
  Widget build(BuildContext context) => AppIconButton(
        icon: Icons.tune_rounded,
        tooltip: 'admin_filter_title'.tr,
        badge: activeFilterCount(host, specs, quickKeys),
        variant: activeFilterCount(host, specs, quickKeys) > 0 ? AppIconButtonVariant.tonal : AppIconButtonVariant.standard,
        onPressed: () => showAdminFilterSheet(context, host: host, specs: specs, sort: sort),
      );
}

/// The removable chips of the active filters (what [AdminFilterBar] shows under its search box).
class AdminActiveFilterChips extends StatelessWidget {
  const AdminActiveFilterChips({super.key, required this.host, required this.specs, this.sort, this.quickKeys = const {}});

  final AdminQueryHost host;
  final List<FilterSpec> specs;
  final SortSpec? sort;
  final Set<String> quickKeys;

  @override
  Widget build(BuildContext context) =>
      _ActiveChips(host: host, specs: specs, sort: sort, quickKeys: quickKeys);
}
