// lib/design/master_detail/entity_search_palette.dart — Ctrl+K / ⌘+K for every role without a palette of its own
// (teacher, student, parent; D-290 phase 8). The admin dashboard and the organization dashboard keep theirs.
//
//   EntitySearchScope(child: AppShell(…))   Ctrl+K opens the palette while the shell is the top route
//   showEntitySearch(context)               the palette: a dialog on wide screens, a full-height sheet on phones
//
// One call, GET /entities/search (what the viewer may open, grouped by kind), 300 ms after typing stops, nothing
// under 2 characters, a stale answer ignored. ↑ / ↓ + Enter pick, Esc closes; a pick opens the full page of that
// student, course, teacher or category (EntityNavigator: no panel is under a palette).
library;

import 'package:flutter_education_app/design/app_side_sheet.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';

import '../app_keyboard.dart' show AppCommandPaletteScope;
import '../app_kit.dart';
import 'entity_chip.dart' show entityKindIcon;
import 'entity_detail_view.dart' show entityErrorText;
import 'entity_navigator.dart';
import 'entity_specs.dart' show mdText;

const entitySearchMinChars = 2;
const entitySearchDebounce = Duration(milliseconds: 300);

/// Ctrl+K opens [showEntitySearch] while [child] is on the top route.
class EntitySearchScope extends StatelessWidget {
  const EntitySearchScope({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) =>
      AppCommandPaletteScope(enabled: enabled, onOpen: () => showEntitySearch(context), child: child);
}

/// The search palette; a pick opens its full page.
Future<void> showEntitySearch(BuildContext context) async {
  EntityRef? picked;
  void select(BuildContext ctx, EntityRef ref) {
    picked = ref;
    Navigator.of(ctx).pop();
  }

  final wide = MediaQuery.sizeOf(context).width >= 720;
  if (wide) {
    await showDialog<void>(
      context: context,
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: context.colors.isDark ? 0.5 : 0.32),
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height;
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: (h * 0.12).clamp(24, 120), left: AppSpace.md, right: AppSpace.md),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 640, maxHeight: (h * 0.72).clamp(320, 600)),
              child: Material(
                color: ctx.colors.cardBg,
                borderRadius: BorderRadius.circular(AppRadius.sheet),
                clipBehavior: Clip.antiAlias,
                child: EntitySearchPanel(onSelect: (r) => select(ctx, r)),
              ),
            ),
          ),
        );
      },
    );
  } else {
    await showAppModalSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.colors.cardBg,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.92,
        child: EntitySearchPanel(onSelect: (r) => select(ctx, r)),
      ),
    );
  }
  final ref = picked;
  if (ref != null && context.mounted) EntityNavigator.open(context, ref);
}

/// The palette's body (a field, then the hits grouped by kind). [search] replaces the server (tests).
class EntitySearchPanel extends StatefulWidget {
  const EntitySearchPanel({super.key, required this.onSelect, this.search});

  final ValueChanged<EntityRef> onSelect;
  final Future<EntitySearchResult> Function(String q)? search;

  @override
  State<EntitySearchPanel> createState() => _EntitySearchPanelState();
}

class _EntitySearchPanelState extends State<EntitySearchPanel> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  int _ticket = 0;
  EntitySearchResult? _result;
  Object? _error;
  bool _loading = false;
  int _active = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q.length < entitySearchMinChars) {
      _ticket++;
      setState(() {
        _result = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(entitySearchDebounce, () => _run(q));
  }

  Future<void> _run(String q) async {
    final t = ++_ticket;
    try {
      final r = await (widget.search ?? EntitiesApi.instance.search)(q);
      if (!mounted || t != _ticket) return;
      setState(() {
        _result = r;
        _error = null;
        _loading = false;
        _active = 0;
      });
    } catch (e) {
      if (!mounted || t != _ticket) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final hits = _result?.flat ?? const [];
    if (e.logicalKey == LogicalKeyboardKey.arrowDown && hits.isNotEmpty) {
      setState(() => _active = (_active + 1) % hits.length);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp && hits.isNotEmpty) {
      setState(() => _active = (_active - 1 + hits.length) % hits.length);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter && hits.isNotEmpty) {
      widget.onSelect(hits[_active.clamp(0, hits.length - 1)].ref);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Focus(
          onKeyEvent: _key,
          child: TextField(
            key: const ValueKey('md.search.field'),
            controller: _field,
            focusNode: _focus,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _changed,
            decoration: InputDecoration(
              hintText: 'md_p8_search_hint'.tr,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpace.sm),
                      child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
            ),
          ),
        ),
      ),
      Divider(height: 1, color: c.divider),
      Expanded(child: _body(context)),
    ]);
  }

  Widget _body(BuildContext context) {
    final r = _result;
    if (_error != null) {
      return AppErrorState(message: entityErrorText(_error), onRetry: () => _run(_field.text.trim()), compact: true);
    }
    if (r == null) {
      return _hint(context, Icons.manage_search_rounded, 'md_p8_search_start'.tr);
    }
    if (r.isEmpty) {
      return _hint(context, Icons.search_off_rounded, mdText('md_p8_search_none', {'q': r.query}));
    }
    var index = 0;
    final children = <Widget>[];
    for (final g in r.groups) {
      children.add(Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxs),
        child: Semantics(
          header: true,
          child: Text(
            g.total > g.items.length
                ? '${'md_p8_kind_${g.kind.name}'.tr} · ${mdText('md_p8_search_more', {'n': '${g.total}'})}'
                : 'md_p8_kind_${g.kind.name}'.tr,
            style: AppType.meta(context),
          ),
        ),
      ));
      for (final h in g.items) {
        final i = index++;
        children.add(_row(context, h, i == _active));
      }
    }
    return ListView(padding: const EdgeInsets.only(bottom: AppSpace.md), children: children);
  }

  Widget _row(BuildContext context, EntitySearchHit h, bool active) {
    final c = context.colors;
    final name = h.ref.name.isEmpty ? '#${h.ref.id}' : h.ref.name;
    return Material(
      color: active ? c.primaryTint : Colors.transparent,
      child: ListTile(
        key: ValueKey('md.search.${h.ref.toToken()}'),
        minTileHeight: AppTouch.min,
        leading: h.ref.isPerson
            ? AppAvatar(name: name, url: h.ref.imageUrl, size: 32)
            : Icon(entityKindIcon(h.ref.kind), color: c.primary),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: h.sub == null ? null : Text(h.sub!, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => widget.onSelect(h.ref),
      ),
    );
  }

  Widget _hint(BuildContext context, IconData icon, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 40, color: context.colors.textMedium),
            const SizedBox(height: AppSpace.sm),
            Text(text, textAlign: TextAlign.center, style: AppType.meta(context)),
          ]),
        ),
      );
}
