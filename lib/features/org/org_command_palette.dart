// lib/features/org/org_command_palette.dart
//
// The organization dashboard's command palette (D-103, spec §5): Ctrl+K / ⌘K (AppCommandPaletteScope in
// app_keyboard.dart) or the header's search button. A dialog on wide screens, a full-height sheet on phones: one
// search field, results grouped Pages (the shell's sections and sub-pages, matched in the app, no call) ·
// Departments · People (GET …/search, 250 ms after typing stops, from 2 characters, the stale request cancelled),
// ↑ ↓ + Enter, Esc closes, the recent items remembered on the device per organization. Hidden when `org.search` is
// off (orgPaletteEnabled).
//
//   showOrgCommandPalette(context, orgId:, pages:, onOpenDepartment:, onOpenPerson:)
//   orgPaletteEntries(sections:, subs:, open:)        the pages from the shell's items and OrgTabs.sections
//   OrgCommandPalettePanel(controller:, onSelect:)    the panel over plain values (test/ui/org_command_palette_layout_test.dart)
// Pure part: org_command_palette_logic.dart (test/org/org_command_palette_test.dart).
library;

import 'package:flutter_education_app/design/app_side_sheet.dart';
import 'dart:convert';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart' show appInk, appText;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../admin/admin_common.dart' show t;
import 'org_command_palette_logic.dart';
import 'org_department_dashboard.dart' show openDepartmentDashboard;
import 'org_providers.dart' show orgBase;

export 'org_command_palette_logic.dart'
    show OrgPaletteEntry, OrgPaletteDept, OrgPalettePerson, OrgSearchResult, OrgPaletteController;

/// The kill switch (feature catalog: ../back/services/feature_catalog.py).
const orgSearchFeatureKey = 'org.search';

/// False while the super admin / the organization has switched the palette off (the button hides, Ctrl+K falls
/// back to the screen's search box).
bool get orgPaletteEnabled => !AppConfig.disableList.contains(orgSearchFeatureKey);

/// The pages from the shell: every section (key, label, icon) and the sub-pages of [subs] (OrgTabs.sections:
/// (key, label, icon, page)). [open] jumps there (OrgTabs.go / orgJump). Keys: `people` · `people/members` …
List<OrgPaletteEntry> orgPaletteEntries({
  required List<(String, String, IconData)> sections,
  required Map<String, List<(String, String, IconData, Widget)>> subs,
  required void Function(String section, String? sub) open,
}) {
  final label = {for (final s in sections) s.$1: s.$2};
  return [
    for (final s in sections) OrgPaletteEntry(key: s.$1, label: s.$2, icon: s.$3, onOpen: () => open(s.$1, null)),
    for (final e in subs.entries)
      for (final x in e.value)
        OrgPaletteEntry(
          key: '${e.key}/${x.$1}',
          label: x.$2,
          icon: x.$3,
          group: label[e.key],
          keywords: [x.$1.replaceAll('_', ' ')],
          onOpen: () => open(e.key, x.$1),
        ),
  ];
}

// ═════════════════════════════════════════════════════════════════════════════
//  Server search + recent items
// ═════════════════════════════════════════════════════════════════════════════

/// GET …/search with the request in flight cancelled by [cancel]. 403 (a student, a member without rights) is no
/// hits, not an error.
class OrgRemoteSearch {
  OrgRemoteSearch(this.orgId, {ApiClient? api}) : _api = api ?? ApiClient();
  final int orgId;
  final ApiClient _api;
  CancelToken? _token;

  Future<OrgSearchResult> call(String q) async {
    final token = _token = CancelToken();
    try {
      final r = await _api.get('$orgBase/orgs/$orgId/search',
          queryParams: {'q': q, 'limit': '20'}, cancelToken: token);
      return OrgSearchResult.fromJson(r);
    } catch (e) {
      final err = ApiException.from(e);
      if (err.statusCode == 403 || err.code == 'query_too_short') return OrgSearchResult.empty;
      rethrow;
    }
  }

  void cancel() {
    final t = _token;
    if (t != null && !t.isCancelled) t.cancel('superseded');
    _token = null;
  }
}

abstract final class OrgPaletteRecents {
  static String _key(int orgId) => 'org_palette_recent_$orgId';

  static Future<List<OrgPaletteRecent>> read(int orgId) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key(orgId));
      if (raw == null) return const [];
      final j = jsonDecode(raw);
      return [if (j is List) for (final x in j) ?OrgPaletteRecent.fromJson(x)];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> write(int orgId, List<OrgPaletteRecent> list) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key(orgId), jsonEncode([for (final x in list) x.toJson()]));
    } catch (_) {}
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Opening it
// ═════════════════════════════════════════════════════════════════════════════

/// Opens the palette over [context] (the org shell: OrgSession above it for the department dashboard). Selecting a
/// row closes it, then opens the page ([OrgPaletteEntry.onOpen]), the department dashboard ([onOpenDepartment],
/// default openDepartmentDashboard) or the person ([onOpenPerson], default: the Members page when it is one of
/// [pages] — the organization has no member detail page). [search] replaces the server search (tests).
Future<void> showOrgCommandPalette(
  BuildContext context, {
  required int orgId,
  required List<OrgPaletteEntry> pages,
  void Function(OrgPaletteDept dept)? onOpenDepartment,
  void Function(OrgPalettePerson person)? onOpenPerson,
  OrgPaletteSearch? search,
}) async {
  if (!orgPaletteEnabled) return;
  final remote = search == null ? OrgRemoteSearch(orgId) : null;
  final recents = await OrgPaletteRecents.read(orgId);
  if (!context.mounted) return;
  final controller = OrgPaletteController(
    pages: pages,
    search: search ?? remote!.call,
    cancel: remote?.cancel,
    recents: recents,
  );
  final wide = MediaQuery.sizeOf(context).width >= 720;
  OrgPaletteRow? picked;
  void select(BuildContext ctx, OrgPaletteRow row) {
    picked = row;
    Navigator.of(ctx).pop();
  }

  if (wide) {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (ctx) => _PaletteDialog(child: OrgCommandPalettePanel(controller: controller, onSelect: (r) => select(ctx, r), wide: true)),
    );
  } else {
    await showAppModalSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.colors.cardBg,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
      clipBehavior: Clip.antiAlias,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.94,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: OrgCommandPalettePanel(controller: controller, onSelect: (r) => select(ctx, r), onClose: () => Navigator.of(ctx).pop()),
        ),
      ),
    );
  }
  remote?.cancel();
  final row = picked;
  if (row != null) {
    controller.remember(row);
    await OrgPaletteRecents.write(orgId, controller.recents);
  }
  controller.dispose();
  if (row == null || !context.mounted) return;
  switch (row.kind) {
    case OrgPaletteKind.page:
      row.page!.onOpen();
    case OrgPaletteKind.dept:
      final d = row.dept!;
      if (onOpenDepartment != null) {
        onOpenDepartment(d);
      } else {
        try {
          await openDepartmentDashboard(context, unitType: d.unitType, unitId: d.id, seed: d.toJson());
        } catch (_) {}
      }
    case OrgPaletteKind.person:
      if (onOpenPerson != null) {
        onOpenPerson(row.person!);
      } else {
        for (final p in pages) {
          if (p.key == 'people/members') return p.onOpen();
        }
      }
  }
}

class _PaletteDialog extends StatelessWidget {
  const _PaletteDialog({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final h = MediaQuery.sizeOf(context).height;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(top: (h * 0.12).clamp(24, 120), left: AppSpace.md, right: AppSpace.md),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 640, maxHeight: (h * 0.7).clamp(320, 600)),
          child: Material(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(AppRadius.sheet - 4),
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.sheet - 4),
                border: Border.all(color: c.divider),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The panel
// ═════════════════════════════════════════════════════════════════════════════

class OrgCommandPalettePanel extends StatefulWidget {
  const OrgCommandPalettePanel({super.key, required this.controller, required this.onSelect, this.onClose, this.wide = false, this.autofocus = true});

  final OrgPaletteController controller;
  final void Function(OrgPaletteRow row) onSelect;

  /// The phone sheet's close button (the dialog closes with Esc or a tap outside).
  final VoidCallback? onClose;

  /// Desktop: the keyboard hints in the footer.
  final bool wide;
  final bool autofocus;

  @override
  State<OrgCommandPalettePanel> createState() => _OrgCommandPalettePanelState();
}

class _OrgCommandPalettePanelState extends State<OrgCommandPalettePanel> {
  final _field = TextEditingController();
  final _activeKey = GlobalKey();
  final _scroll = ScrollController();

  OrgPaletteController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
  }

  @override
  void didUpdateWidget(OrgCommandPalettePanel old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    _field.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _move(int delta) {
    _c.move(delta);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _activeKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx, duration: AppMotion.of(context).fast, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
        Scrollable.ensureVisible(ctx, duration: AppMotion.of(context).fast, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart);
      }
    });
  }

  void _submit() {
    final row = _c.activeRow;
    if (row != null) widget.onSelect(row);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = _c.rows;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xs, AppSpace.xs, AppSpace.xs),
        child: Row(children: [
          Icon(Icons.search_rounded, size: 22, color: c.textMedium),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
              },
              child: TextField(
                controller: _field,
                autofocus: widget.autofocus,
                textInputAction: TextInputAction.go,
                onChanged: _c.setQuery,
                onSubmitted: (_) => _submit(),
                style: appText(16, w: FontWeight.w500, c: c.textDark),
                decoration: InputDecoration(
                  hintText: t('ابحث في الصفحات والأقسام والأشخاص', 'Search pages, departments and people'),
                  hintStyle: appText(16, w: FontWeight.w400, c: c.textLight),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          if (_c.searching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary)),
            ),
          if (widget.onClose != null)
            IconButton(
              tooltip: t('إغلاق', 'Close'),
              onPressed: widget.onClose,
              icon: Icon(Icons.close_rounded, color: c.textMedium),
            )
          else
            Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs), child: _KeyCap('Esc')),
        ]),
      ),
      Divider(height: 1, thickness: 1, color: c.divider),
      Expanded(child: _results(context, rows)),
      if (widget.wide && rows.isNotEmpty) ...[
        Divider(height: 1, thickness: 1, color: c.divider),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
          child: Wrap(spacing: AppSpace.md, runSpacing: AppSpace.xxs, children: [
            _Hint(keys: const ['↑', '↓'], label: t('للتنقل', 'to move')),
            _Hint(keys: const ['Enter'], label: t('للفتح', 'to open')),
            _Hint(keys: const ['Esc'], label: t('للإغلاق', 'to close')),
          ]),
        ),
      ],
    ]);
  }

  Widget _results(BuildContext context, List<OrgPaletteRow> rows) {
    final c = context.colors;
    final q = _c.query.trim();
    if (rows.isEmpty) {
      final String title, line;
      final IconData icon;
      if (_c.showingRecent) {
        icon = Icons.manage_search_rounded;
        title = t('اكتب للبحث في الصفحات والأقسام والأشخاص', 'Type to search pages, departments and people');
        line = t('مثلاً: «الجدول» أو اسم قسم أو اسم شخص', 'For example: “timetable”, a department or a person’s name');
      } else if (_c.searching) {
        return const SizedBox.shrink();
      } else if (orgPaletteNormalize(q).length < orgPaletteMinQuery) {
        icon = Icons.keyboard_rounded;
        title = t('تابع الكتابة', 'Keep typing');
        line = t('حرفان على الأقل للبحث عن الأقسام والأشخاص', 'Two letters or more also find departments and people');
      } else {
        icon = Icons.search_off_rounded;
        title = t('لا نتائج لـ «$q»', 'Nothing matches “$q”');
        line = _c.searchFailed
            ? t('تعذّر البحث عن الأقسام والأشخاص الآن — حاول بعد قليل', 'Couldn’t search departments and people right now — try again shortly')
            : t('جرّب كلمة أخرى أو جزءاً من الاسم', 'Try another word or part of the name');
      }
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: c.primary.withValues(alpha: c.isDark ? 0.18 : 0.08), shape: BoxShape.circle),
              child: Icon(icon, size: 26, color: appInk(context, c.primary)),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(title, textAlign: TextAlign.center, style: AppType.row(context)),
            const SizedBox(height: AppSpace.xxs),
            Text(line, textAlign: TextAlign.center, style: AppType.meta(context)),
          ]),
        ),
      );
    }
    final children = <Widget>[];
    OrgPaletteKind? last;
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (_c.showingRecent ? i == 0 : r.kind != last) {
        children.add(_GroupTitle(_c.showingRecent ? t('فتحتها مؤخراً', 'Recent') : orgPaletteGroupLabel(r.kind)));
        last = r.kind;
      }
      final active = i == _c.active;
      children.add(KeyedSubtree(
        key: active ? _activeKey : null,
        child: _PaletteRowTile(
          row: r,
          active: active,
          wide: widget.wide,
          onTap: () => widget.onSelect(r),
          onHover: () => _c.setActive(i),
        ),
      ));
    }
    if (!_c.showingRecent && (_c.searching || _c.searchFailed) && orgPaletteNormalize(q).length >= orgPaletteMinQuery) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xs),
        child: Text(
          _c.searching
              ? t('جارٍ البحث عن الأقسام والأشخاص…', 'Looking for departments and people…')
              : t('تعذّر البحث عن الأقسام والأشخاص الآن', 'Couldn’t search departments and people right now'),
          style: AppType.meta(context),
        ),
      ));
    }
    return ListView(controller: _scroll, padding: const EdgeInsets.only(bottom: AppSpace.xs), children: children);
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxs),
        child: Semantics(header: true, child: Text(text, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600))),
      );
}

class _PaletteRowTile extends StatelessWidget {
  const _PaletteRowTile({required this.row, required this.active, required this.onTap, required this.onHover, this.wide = false});
  final OrgPaletteRow row;
  final bool active;

  /// The Enter hint on the highlighted row (keyboards are a desktop thing).
  final bool wide;
  final VoidCallback onTap, onHover;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (String title, String? sub, Widget lead) = switch (row.kind) {
      OrgPaletteKind.page => (row.page!.label, row.page!.group, _IconBox(row.page!.icon)),
      OrgPaletteKind.dept => (
          row.dept!.name,
          row.dept!.unitType == 'program' ? t('برنامج أكاديمي', 'Academic program') : t('قسم', 'Department'),
          _IconBox(row.dept!.unitType == 'program' ? Icons.school_outlined : Icons.apartment_rounded),
        ),
      OrgPaletteKind.person => (
          row.person!.name,
          orgPaletteRoleLabel(row.person!.memberRole),
          _PersonAvatar(name: row.person!.name, url: row.person!.avatarUrl),
        ),
    };
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: Semantics(
        button: true,
        selected: active,
        label: sub == null ? title : '$title, $sub',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
          child: Material(
            color: active ? c.primary.withValues(alpha: c.isDark ? 0.18 : 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: 6),
                  child: Row(children: [
                    lead,
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                        if (sub != null && sub.isNotEmpty)
                          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                      ]),
                    ),
                    if (active && wide) ...[
                      const SizedBox(width: AppSpace.xs),
                      Icon(Icons.keyboard_return_rounded, size: 16, color: c.textLight),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The person's photo, else the first letter — readable in both modes (the letter wears appInk of the primary).
class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({required this.name, this.url});
  final String name;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final letter = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    final fallback = Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.primary.withValues(alpha: c.isDark ? 0.24 : 0.12), shape: BoxShape.circle),
      child: Text(letter, style: appText(15, w: FontWeight.w600, c: appInk(context, c.primary))),
    );
    final u = url;
    if (u == null || u.isEmpty) return fallback;
    return ClipOval(
      child: SizedBox(
        width: 36,
        height: 36,
        child: Image.network(u, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.chip), border: Border.all(color: c.divider)),
      child: Icon(icon, size: 18, color: c.textMedium),
    );
  }
}

class _KeyCap extends StatelessWidget {
  const _KeyCap(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(6), border: Border.all(color: c.divider)),
      child: Text(label, textDirection: TextDirection.ltr, style: appText(11.5, w: FontWeight.w600, c: c.textMedium)),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.keys, required this.label});
  final List<String> keys;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (final k in keys) ...[_KeyCap(k), const SizedBox(width: 4)],
        const SizedBox(width: 2),
        Text(label, style: AppType.meta(context)),
      ]);
}
