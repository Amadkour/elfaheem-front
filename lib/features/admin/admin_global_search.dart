// lib/features/admin/admin_global_search.dart
//
// The Super Admin dashboard's global search: ONE command palette for the whole dashboard. Opened by Ctrl+K and "/"
// (AppCommandPaletteScope around the shell, admin_dashboard_screen.dart) and by the search field at the top of the
// Overview ([AdminSearchLauncher]). A dialog on wide screens, a full-height sheet on phones.
//
//   Pages     the admin services + the shell tabs, matched in the app (instant, no call)
//   People…   GET /api/v1/admin/search?q=&limit=5 (admin_search_router.py): students · teachers · admins · courses ·
//             organizations · payments; 300 ms after typing stops, nothing under 2 characters, a stale answer is
//             ignored (request counter)
//
// Up / Down + Enter pick, Esc closes. Pure parts ([parseAdminSearch], [matchAdminPages], [AdminSearchController])
// are tested in test/ui/admin_ds/shell_global_search_test.dart.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_side_sheet.dart' show appScrimColor;
import 'package:flutter_education_app/design/app_keyboard.dart' show AppCommandPaletteScope;

import 'admin_common.dart' show isSuperNow, t;
import 'admin_recents.dart';
import 'admin_services_hub.dart' show AdminService, adminServiceGroups;
import 'admin_view_as_page.dart' show AdminViewAsPage;

const adminSearchMinChars = 2;
const adminSearchDebounce = Duration(milliseconds: 300);

// ═════════════════════════════════════════════════════════════════════════════
//  Model + pure logic
// ═════════════════════════════════════════════════════════════════════════════

/// A page the palette can open (an admin service or a shell tab).
class AdminSearchPage {
  const AdminSearchPage({required this.label, required this.icon, required this.onOpen, this.desc = '', this.group = ''});

  final String label, desc, group;
  final IconData icon;
  final VoidCallback onOpen;
}

class AdminSearchHit {
  const AdminSearchHit({required this.kind, required this.id, required this.label, this.sub, this.username, this.status});

  /// students | teachers | admins | courses | organizations | payments
  final String kind;
  final int id;
  final String label;
  final String? sub, username, status;
}

class AdminSearchGroup {
  const AdminSearchGroup({required this.kind, required this.total, required this.items});

  final String kind;
  final int total;
  final List<AdminSearchHit> items;
}

/// The response of GET /api/v1/admin/search; tolerant of every missing key.
List<AdminSearchGroup> parseAdminSearch(dynamic json) {
  if (json is! Map) return const [];
  final groups = json['groups'];
  if (groups is! List) return const [];
  String? s(dynamic v) => v == null ? null : '$v';
  return [
    for (final g in groups)
      if (g is Map && g['items'] is List && (g['items'] as List).isNotEmpty)
        AdminSearchGroup(
          kind: '${g['kind']}',
          total: g['total'] is num ? (g['total'] as num).toInt() : (g['items'] as List).length,
          items: [
            for (final i in g['items'] as List)
              if (i is Map)
                AdminSearchHit(
                  kind: '${g['kind']}',
                  id: i['id'] is num ? (i['id'] as num).toInt() : int.tryParse('${i['id']}') ?? 0,
                  label: s(i['label']) ?? '',
                  sub: s(i['sub']),
                  username: s(i['username']),
                  status: s(i['status']),
                ),
          ],
        ),
  ];
}

String _norm(String x) => x.toLowerCase().replaceAll(RegExp(r'[ً-ْـ]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

/// The pages whose label + description contain every word of [q] (label hits first).
List<AdminSearchPage> matchAdminPages(List<AdminSearchPage> pages, String q) {
  final words = _norm(q).split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  final hits = <(int, AdminSearchPage)>[];
  for (final p in pages) {
    final label = _norm(p.label);
    final all = '$label ${_norm(p.desc)} ${_norm(p.group)}';
    if (!words.every(all.contains)) continue;
    hits.add((words.every(label.contains) ? 0 : 1, p));
  }
  hits.sort((a, b) => a.$1.compareTo(b.$1)); // stable
  return [for (final h in hits) h.$2];
}

typedef AdminRemoteSearch = Future<List<AdminSearchGroup>> Function(String q);

/// GET /api/v1/admin/search through the shared ApiClient.
Future<List<AdminSearchGroup>> adminRemoteSearch(String q) async {
  final r = await ApiClient().get('/api/v1/admin/search', queryParams: {'q': q, 'limit': '5'});
  return parseAdminSearch(r);
}

/// One selectable row of the palette (a header is not selectable).
class AdminSearchRow {
  const AdminSearchRow.header(this.title, {this.total}) : page = null, hit = null;
  const AdminSearchRow.page(AdminSearchPage this.page) : hit = null, title = null, total = null;
  const AdminSearchRow.hit(AdminSearchHit this.hit) : page = null, title = null, total = null;

  final String? title;
  final int? total;
  final AdminSearchPage? page;
  final AdminSearchHit? hit;

  bool get isHeader => title != null;
}

String adminSearchGroupTitle(String kind) => switch (kind) {
      'students' => t('الطلاب', 'Students'),
      'teachers' => t('المعلمون', 'Teachers'),
      'admins' => t('المشرفون', 'Admins'),
      'courses' => t('الدورات', 'Courses'),
      'categories' => t('التصنيفات', 'Categories'),
      'organizations' => t('المؤسسات', 'Organizations'),
      'payments' => t('المدفوعات', 'Payments'),
      _ => kind,
    };

IconData adminSearchGroupIcon(String kind) => switch (kind) {
      'students' => Icons.school_rounded,
      'teachers' => Icons.co_present_rounded,
      'admins' => Icons.admin_panel_settings_rounded,
      'courses' => Icons.auto_stories_rounded,
      'categories' => Icons.category_rounded,
      'organizations' => Icons.domain_rounded,
      'payments' => Icons.receipt_long_rounded,
      _ => Icons.search_rounded,
    };

class AdminSearchController extends ChangeNotifier {
  AdminSearchController({required this.pages, this.recents = const [], AdminRemoteSearch? search, this.debounce = adminSearchDebounce})
      : _search = search ?? adminRemoteSearch;

  final List<AdminSearchPage> pages;

  /// The pages this person opened last (newest first): the first group while the query is empty.
  final List<AdminSearchPage> recents;
  final AdminRemoteSearch _search;
  final Duration debounce;

  String _query = '';
  List<AdminSearchPage> _pageHits = const [];
  List<AdminSearchGroup> _groups = const [];
  bool _loading = false;
  Object? _error;
  int _request = 0;
  int _active = 0;
  Timer? _timer;
  bool _disposed = false;

  /// Requests sent so far (tests).
  int sent = 0;

  String get query => _query;
  bool get loading => _loading;
  Object? get error => _error;
  bool get isIdle => _query.trim().isEmpty;
  bool get tooShort => _query.trim().length < adminSearchMinChars;
  List<AdminSearchGroup> get groups => _groups;

  List<AdminSearchRow> get rows => [
        if (isIdle && recents.isNotEmpty) ...[
          AdminSearchRow.header(t('الأحدث', 'Recent')),
          for (final p in recents) AdminSearchRow.page(p),
        ],
        if (_pageHits.isNotEmpty) ...[
          AdminSearchRow.header(t('الصفحات', 'Pages')),
          for (final p in _pageHits.take(8)) AdminSearchRow.page(p),
        ],
        for (final g in _groups) ...[
          AdminSearchRow.header(adminSearchGroupTitle(g.kind), total: g.total > g.items.length ? g.total : null),
          for (final h in g.items) AdminSearchRow.hit(h),
        ],
      ];

  List<AdminSearchRow> get selectable => [for (final r in rows) if (!r.isHeader) r];
  int get active => _active;
  AdminSearchRow? get activeRow {
    final s = selectable;
    return s.isEmpty ? null : s[_active.clamp(0, s.length - 1)];
  }

  void setQuery(String q) {
    _query = q;
    _active = 0;
    _pageHits = matchAdminPages(pages, q);
    _timer?.cancel();
    if (tooShort) {
      _request++; // whatever is in flight is now stale
      _groups = const [];
      _loading = false;
      _error = null;
    } else {
      _loading = true;
      _error = null;
      _timer = Timer(debounce, run);
    }
    _notify();
  }

  /// Sends the request now (also the Retry button).
  Future<void> run() async {
    final q = _query.trim();
    if (q.length < adminSearchMinChars) return;
    final id = ++_request;
    _timer?.cancel();
    sent++;
    _loading = true;
    _error = null;
    _notify();
    try {
      final g = await _search(q);
      if (id != _request) return; // a newer keystroke owns the screen
      _groups = g;
      _loading = false;
    } catch (e) {
      if (id != _request) return;
      _groups = const [];
      _loading = false;
      _error = e;
    }
    _notify();
  }

  void move(int delta) {
    final n = selectable.length;
    if (n == 0) return;
    _active = (_active + delta) % n;
    if (_active < 0) _active += n;
    _notify();
  }

  void setActive(int i) {
    _active = i;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

/// What the palette shows beyond the caller's [pages]: the "View as a user" command (super admin only; not added when
/// the services already list it), page openings that feed [AdminRecents], and the recent pages themselves.
({List<AdminSearchPage> pages, List<AdminSearchPage> recents}) adminPaletteSetup(BuildContext context, List<AdminSearchPage> pages) {
  final byKey = <String, AdminService>{};
  try {
    for (final g in adminServiceGroups(context, watch: false)) {
      for (final s in g.visibleServices) {
        if (s.featureKey != null && AppConfig.disableList.contains(s.featureKey)) continue;
        byKey.putIfAbsent(s.labelKey, () => s);
      }
    }
  } catch (_) {} // no providers above (a preview): the caller's pages only
  final keyOfLabel = {for (final e in byKey.entries) e.value.labelText: e.key};

  AdminSearchPage tracked(AdminSearchPage p) {
    final key = keyOfLabel[p.label];
    if (key == null) return p;
    return AdminSearchPage(
        label: p.label,
        desc: p.desc,
        group: p.group,
        icon: p.icon,
        onOpen: () {
          AdminRecents.instance.record(key);
          p.onOpen();
        });
  }

  var superNow = false;
  try {
    superNow = isSuperNow(context);
  } catch (_) {}
  final all = [for (final p in pages) tracked(p)];
  // the hub has no View-as tile any more (R1): this command is its path besides the user rows and sheet
  final viewAsLabel = t('عرض كمستخدم', 'View as a user');
  if (superNow && !pages.any((p) => p.label == viewAsLabel)) {
    all.add(AdminSearchPage(
      label: t('عرض كمستخدم', 'View as a user'),
      desc: t('افتح التطبيق كما يراه مستخدم آخر', 'Open the app as another user sees it'),
      group: t('الأشخاص', 'People'),
      icon: Icons.supervised_user_circle_rounded,
      onOpen: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminViewAsPage())),
    ));
  }
  final recents = [
    for (final k in AdminRecents.instance.keys)
      if (byKey[k] != null)
        tracked(AdminSearchPage(
            label: byKey[k]!.labelText, desc: byKey[k]!.descText, icon: byKey[k]!.icon, onOpen: byKey[k]!.onTap)),
  ].take(AdminRecents.shown).toList();
  return (pages: all, recents: recents);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Opening it
// ═════════════════════════════════════════════════════════════════════════════

/// Opens the palette over [context]. Picking a row closes it first, then runs the page's [AdminSearchPage.onOpen] or
/// [onOpenHit]. [search] replaces the server call (tests).
Future<void> showAdminGlobalSearch(
  BuildContext context, {
  required List<AdminSearchPage> pages,
  required void Function(AdminSearchHit hit) onOpenHit,
  AdminRemoteSearch? search,
}) async {
  final setup = adminPaletteSetup(context, pages);
  final controller = AdminSearchController(pages: setup.pages, recents: setup.recents, search: search);
  AdminSearchRow? picked;
  void select(BuildContext ctx, AdminSearchRow row) {
    picked = row;
    Navigator.of(ctx).pop();
  }

  final wide = MediaQuery.sizeOf(context).width >= 720;
  if (wide) {
    await showDialog<void>(
      context: context,
      barrierColor: appScrimColor(context),
      builder: (ctx) {
        final h = MediaQuery.sizeOf(ctx).height;
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: (h * 0.12).clamp(24, 120), left: AppSpace.md, right: AppSpace.md),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 680, maxHeight: (h * 0.72).clamp(320, 640)),
              child: Material(
                color: ctx.colors.cardBg,
                borderRadius: BorderRadius.circular(AppRadius.sheet),
                clipBehavior: Clip.antiAlias,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.sheet),
                    border: Border.all(color: ctx.colors.divider),
                  ),
                  child: AdminSearchPanel(controller: controller, wide: true, onSelect: (r) => select(ctx, r)),
                ),
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
      shape: RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
      clipBehavior: Clip.antiAlias,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 1,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: AdminSearchPanel(controller: controller, onSelect: (r) => select(ctx, r), onClose: () => Navigator.of(ctx).pop()),
        ),
      ),
    );
  }
  controller.dispose();
  final row = picked;
  if (row == null || !context.mounted) return;
  if (row.page != null) {
    row.page!.onOpen();
  } else if (row.hit != null) {
    onOpenHit(row.hit!);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The field at the top of the Overview
// ═════════════════════════════════════════════════════════════════════════════

/// Looks like a search field; a tap (or Enter / Space on it) opens the palette of the nearest
/// [AppCommandPaletteScope]. Without a scope (a test, a preview) it does nothing.
class AdminSearchLauncher extends StatelessWidget {
  const AdminSearchLauncher({super.key, this.onOpen, this.glass = false});

  /// Overrides the scope's opener.
  final VoidCallback? onOpen;

  /// The hero's look (redesign A1): a glass pill with the on-hero ink and the design's question as the hint.
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hint = glass ? 'a1_search_hint'.tr : t('ابحث عن طالب أو معلم أو دورة أو صفحة…', 'Search a student, teacher, course or page…');
    final open = onOpen ?? AppCommandPaletteScope.openerOf(context);
    final radius = glass ? BorderRadius.circular(AppRadius.pill) : AppRadius.controlAll;
    return Semantics(
      button: true,
      label: hint,
      excludeSemantics: true,
      onTap: open,
      // paper on the home's sky block: a well that reads as the one thing to type into
      child: Material(
        color: glass ? c.heroGlass : c.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: glass ? c.heroGlassBorder : c.divider, width: AppBorder.hairline),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: open,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.primary),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: Row(children: [
                Icon(Icons.search_rounded, size: AppIconSize.lg, color: glass ? c.onHero : c.textMedium),
                AppSpace.gapSm,
                Expanded(
                  child: Text(hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.body(context).copyWith(color: glass ? c.onHeroMuted : c.textLight)),
                ),
                if (MediaQuery.sizeOf(context).width >= 720) const _KeyCap('Ctrl K'),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyCap extends StatelessWidget {
  const _KeyCap(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
      decoration: BoxDecoration(
        color: c.cardBg2,
        borderRadius: BorderRadius.circular(AppRadius.chip / 2),
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Text(text, textDirection: TextDirection.ltr, style: AppType.overline(context).copyWith(color: c.textMedium)),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The panel
// ═════════════════════════════════════════════════════════════════════════════

class AdminSearchPanel extends StatefulWidget {
  const AdminSearchPanel({super.key, required this.controller, required this.onSelect, this.onClose, this.wide = false});

  final AdminSearchController controller;
  final void Function(AdminSearchRow row) onSelect;

  /// The phone sheet's close button (the dialog closes with Esc or a tap outside).
  final VoidCallback? onClose;
  final bool wide;

  @override
  State<AdminSearchPanel> createState() => _AdminSearchPanelState();
}

class _AdminSearchPanelState extends State<AdminSearchPanel> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  final _activeKey = GlobalKey();

  AdminSearchController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _move(int d) {
    _c.move(d);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _activeKey.currentContext;
      if (ctx != null && ctx.mounted) Scrollable.ensureVisible(ctx, duration: AppMotion.of(context).fast);
    });
  }

  void _submit() {
    final r = _c.activeRow;
    if (r != null) widget.onSelect(r);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xs, AppSpace.xs, AppSpace.xs),
        child: Row(children: [
          Icon(Icons.search_rounded, size: AppIconSize.lg, color: c.textMedium),
          AppSpace.gapSm,
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
              },
              child: TextField(
                controller: _field,
                focusNode: _focus,
                autofocus: true,
                textInputAction: TextInputAction.go,
                onChanged: _c.setQuery,
                onSubmitted: (_) => _submit(),
                style: AppType.section(context).copyWith(fontWeight: FontWeight.w500, color: c.textDark),
                decoration: InputDecoration(
                  hintText: t('ابحث في الصفحات والطلاب والمعلمين والدورات', 'Search pages, students, teachers and courses'),
                  hintStyle: AppType.section(context).copyWith(fontWeight: FontWeight.w400, color: c.textLight),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                ),
              ),
            ),
          ),
          if (widget.onClose != null)
            IconButton(tooltip: t('إغلاق', 'Close'), onPressed: widget.onClose, icon: Icon(Icons.close_rounded, color: c.textMedium))
          else
            const Padding(padding: EdgeInsets.symmetric(horizontal: AppSpace.xs), child: _KeyCap('Esc')),
        ]),
      ),
      Divider(height: 1, thickness: 1, color: c.divider),
      Expanded(child: _results(context)),
      if (widget.wide) ...[
        Divider(height: 1, thickness: 1, color: c.divider),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
          child: Wrap(spacing: AppSpace.md, runSpacing: AppSpace.xxs, children: [
            _Hint(const ['↑', '↓'], t('للتنقل', 'to move')),
            _Hint(const ['Enter'], t('للفتح', 'to open')),
            _Hint(const ['Esc'], t('للإغلاق', 'to close')),
          ]),
        ),
      ],
    ]);
  }

  Widget _results(BuildContext context) {
    final rows = _c.rows;
    final children = <Widget>[];
    var sel = -1;
    for (final r in rows) {
      if (r.isHeader) {
        children.add(_GroupHeader(title: r.title!, total: r.total));
        continue;
      }
      sel++;
      final index = sel;
      final active = index == _c.active;
      children.add(_ResultRow(
        key: active ? _activeKey : null,
        row: r,
        active: active,
        onTap: () => widget.onSelect(r),
        onHover: () => _c.setActive(index),
      ));
    }
    if (_c.isIdle && rows.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Text(t('اكتب للبحث في الصفحات والطلاب والمعلمين والدورات', 'Type to search pages, students, teachers and courses'),
            textAlign: TextAlign.center, style: AppType.meta(context)),
      ));
    }
    if (_c.loading) {
      children.add(const _SkeletonRows());
    } else if (_c.error != null) {
      children.add(Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: AppErrorState(compact: true, message: appErrorMessage(_c.error), onRetry: _c.run),
      ));
    } else if (rows.isEmpty) {
      final q = _c.query.trim();
      final idle = _c.isIdle;
      // scrollable: with the keyboard open on a phone this area is short
      return ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          AppEmpty(
            icon: idle ? Icons.manage_search_rounded : (_c.tooShort ? Icons.keyboard_rounded : Icons.search_off_rounded),
            title: idle
                ? t('اكتب للبحث في لوحة التحكم', 'Type to search the dashboard')
                : _c.tooShort
                    ? t('تابع الكتابة', 'Keep typing')
                    : t('لا نتائج لـ «$q»', 'Nothing matches “$q”'),
            message: idle
                ? t('الصفحات والطلاب والمعلمون والدورات والمؤسسات. رقم الدفع يبدأ بـ #', 'Pages, students, teachers, courses and organizations. Start a payment number with #')
                : _c.tooShort
                    ? t('حرفان على الأقل للبحث عن الأشخاص والدورات', 'Two letters or more also find people and courses')
                    : t('جرّب كلمة أخرى أو جزءاً من الاسم', 'Try another word or part of the name'),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      children: children,
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, this.total});
  final String title;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxs),
      child: Row(children: [
        Expanded(child: Semantics(header: true, child: Text(title, style: AppType.overline(context).copyWith(color: c.textMedium)))),
        if (total != null) Text('$total', style: AppType.meta(context)),
      ]),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({super.key, required this.row, required this.active, required this.onTap, required this.onHover});

  final AdminSearchRow row;
  final bool active;
  final VoidCallback onTap, onHover;

  static AppTone _tone(String? s) => switch (s) {
        'active' || 'published' || 'approved' => AppTone.success,
        'pending' || 'pending_approval' => AppTone.warning,
        'suspended' || 'rejected' || 'blocked' => AppTone.danger,
        _ => AppTone.neutral,
      };

  static String _statusText(String s) => switch (s) {
        'active' => t('نشط', 'Active'),
        'inactive' => t('غير نشط', 'Inactive'),
        'published' => t('منشورة', 'Published'),
        'draft' => t('مسودة', 'Draft'),
        'pending' => t('بانتظار', 'Pending'),
        'approved' => t('معتمدة', 'Approved'),
        'rejected' => t('مرفوضة', 'Rejected'),
        'suspended' => t('موقوفة', 'Suspended'),
        _ => s,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final page = row.page;
    final hit = row.hit;
    final IconData icon = page?.icon ?? adminSearchGroupIcon(hit!.kind);
    final title = page?.label ?? hit!.label;
    final sub = page != null
        ? (page.group.isEmpty ? page.desc : page.group)
        : [if (hit!.username != null && hit.username!.isNotEmpty) '@${hit.username}', if (hit.sub != null && hit.sub!.isNotEmpty) hit.sub!].join(' · ');
    final status = hit?.status;
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: Semantics(
        button: true,
        selected: active,
        label: '$title${sub.isEmpty ? '' : ', $sub'}',
        excludeSemantics: true,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
          child: Material(
            color: active ? c.primaryWash : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.chip),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.min),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
                  child: Row(children: [
                    Container(
                      width: AppTouch.min - AppSpace.sm,
                      height: AppTouch.min - AppSpace.sm,
                      decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.chip)),
                      child: Icon(icon, size: AppIconSize.md, color: c.primary),
                    ),
                    AppSpace.gapSm,
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                        if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                      ]),
                    ),
                    if (status != null && status.isNotEmpty) ...[
                      AppSpace.gapSm,
                      AppStatusBadge(label: _statusText(status), tone: _tone(status)),
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

class _SkeletonRows extends StatelessWidget {
  const _SkeletonRows();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(child: AppListSkeleton(items: 3, padding: const EdgeInsets.symmetric(horizontal: AppSpace.md)));
}

class _Hint extends StatelessWidget {
  const _Hint(this.keys, this.label);
  final List<String> keys;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (final k in keys) ...[_KeyCap(k), const SizedBox(width: AppSpace.xxs)],
        Text(label, style: AppType.meta(context)),
      ]);
}
