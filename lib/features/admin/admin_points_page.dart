// lib/features/admin/admin_points_page.dart — the points admin (docs/backend/live-rooms-spec.md §9, feature key
// `admin.points`; admin / super-admin / developer). Opened from the admin services hub (Payments group).
//
//   Top-ups    pending first; approve / reject with a note; the receipt (image in the app, PDF saved)
//   Users      search, balance, grant / deduct with a note, the history
//   Settings   the six app settings: free minutes, plan price (points), plan days, point price, currency, minimum
//
// The bodies take plain values (AdminTopupsView, AdminPointsUsersView, PointsSettingsForm, PointsGrantForm) so
// test/ui/admin_points_layout_test.dart pumps them without the network.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../shared/points/points_api.dart';
import '../shared/points/points_wallet_page.dart' show LedgerTile, TopupTile;
import 'admin_common.dart' show t;
import 'admin_money_p8.dart' show p8SaveBytes;

class AdminPointsPage extends StatelessWidget {
  const AdminPointsPage({super.key, this.api = const PointsApi()});

  final PointsApi api;

  @override
  Widget build(BuildContext context) => BasePage(
        key: const ValueKey(kAdminPointsFeatureKey),
        appBar: ScreenAppBar(title: t('النقاط والمحافظ', 'Points & wallets')),
        child: DefaultTabController(
          length: 3,
          child: Column(children: [
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              tabs: [
                Tab(text: t('طلبات الشحن', 'Top-ups')),
                Tab(text: t('المستخدمون', 'Users')),
                Tab(text: t('الإعدادات', 'Settings')),
              ],
            ),
            Expanded(
              child: TabBarView(children: [
                _TopupsTab(api: api),
                _UsersTab(api: api),
                _SettingsTab(api: api),
              ]),
            ),
          ]),
        ),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Top-ups
// ═════════════════════════════════════════════════════════════════════════════

/// null = every status (pending first).
const _topupFilters = <String?>['pending', 'approved', 'rejected', null];

String _filterLabel(String? f) => switch (f) {
      'pending' => topupStatusText(TopupStatus.pending),
      'approved' => topupStatusText(TopupStatus.approved),
      'rejected' => topupStatusText(TopupStatus.rejected),
      _ => t('الكل', 'All'),
    };

class _TopupsTab extends StatefulWidget {
  const _TopupsTab({required this.api});

  final PointsApi api;

  @override
  State<_TopupsTab> createState() => _TopupsTabState();
}

class _TopupsTabState extends State<_TopupsTab> with AutomaticKeepAliveClientMixin {
  String? _filter = 'pending';
  List<PointsTopup>? _items;
  String? _error;
  int? _busyId;
  int _req = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final n = ++_req;
    setState(() => _error = null);
    try {
      final r = await widget.api.topups(status: _filter);
      if (mounted && n == _req) setState(() => _items = PointsTopup.sorted(r));
    } catch (e) {
      if (mounted && n == _req) setState(() => _error = pointsErrorText(e));
    }
  }

  Future<void> _decide(PointsTopup x, bool approve) async {
    final note = await askPointsNote(context,
        title: approve ? t('قبول طلب الشحن', 'Approve the top-up') : t('رفض طلب الشحن', 'Reject the top-up'),
        action: approve ? t('قبول وإضافة ${x.points} نقطة', 'Approve and add ${x.points} points') : t('رفض', 'Reject'),
        danger: !approve);
    if (note == null || !mounted) return;
    setState(() => _busyId = x.id);
    try {
      approve ? await widget.api.approve(x.id, note: note) : await widget.api.reject(x.id, note: note);
      appToast(approve ? t('أُضيفت النقاط', 'Points added') : t('رُفض الطلب', 'Top-up rejected'));
    } catch (e) {
      appToast(pointsErrorText(e), error: true);
    }
    if (!mounted) return;
    setState(() => _busyId = null);
    await _load();
  }

  Future<void> _receipt(PointsTopup x) async {
    setState(() => _busyId = x.id);
    try {
      final bytes = await widget.api.receipt(x.id);
      if (!mounted) return;
      setState(() => _busyId = null);
      await showPointsReceipt(context, bytes, '${t('إيصال', 'Receipt')} #${x.id}');
    } catch (e) {
      if (mounted) setState(() => _busyId = null);
      appToast(pointsErrorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AppRefresh(
      onRefresh: _load,
      child: AdminTopupsView(
        items: _items,
        error: _error,
        filter: _filter,
        busyId: _busyId,
        onFilter: (f) {
          setState(() {
            _filter = f;
            _items = null;
          });
          _load();
        },
        onRetry: _load,
        onApprove: (x) => _decide(x, true),
        onReject: (x) => _decide(x, false),
        onReceipt: _receipt,
      ),
    );
  }
}

/// The top-ups list with plain values. [items] null = loading (with no [error]).
class AdminTopupsView extends StatelessWidget {
  const AdminTopupsView({
    super.key,
    required this.items,
    this.error,
    this.filter = 'pending',
    this.busyId,
    this.onFilter,
    this.onRetry,
    this.onApprove,
    this.onReject,
    this.onReceipt,
  });

  final List<PointsTopup>? items;
  final String? error;
  final String? filter;
  final int? busyId;
  final ValueChanged<String?>? onFilter;
  final VoidCallback? onRetry;
  final ValueChanged<PointsTopup>? onApprove, onReject, onReceipt;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = items;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in _topupFilters)
            AppChoiceChip(label: _filterLabel(f), selected: filter == f, onTap: () => onFilter?.call(f)),
        ]),
        const SizedBox(height: 12),
        if (list == null && error == null)
          const AppListSkeleton(items: 4)
        else if (error != null)
          AppBanner(
              icon: Icons.error_outline_rounded,
              text: error!,
              color: c.danger,
              action: onRetry == null
                  ? null
                  : IconButton(tooltip: t('أعد المحاولة', 'Try again'), onPressed: onRetry, icon: const Icon(Icons.refresh_rounded)))
        else if (list!.isEmpty)
          AppEmpty(
              icon: Icons.inbox_rounded,
              title: filter == 'pending' ? t('لا طلبات بانتظار المراجعة', 'No top-ups waiting') : t('لا طلبات', 'No top-ups'))
        else
          for (final x in list)
            TopupTile(
              topup: x,
              showUser: true,
              trailing: Wrap(spacing: 8, runSpacing: 8, children: [
                AppPill(
                    icon: Icons.receipt_long_rounded,
                    label: t('الإيصال', 'Receipt'),
                    onTap: busyId == x.id || onReceipt == null ? null : () => onReceipt!(x)),
                if (x.isPending) ...[
                  AppPill(
                      icon: Icons.check_rounded,
                      label: t('قبول', 'Approve'),
                      color: c.success,
                      onTap: busyId == x.id || onApprove == null ? null : () => onApprove!(x)),
                  AppPill(
                      icon: Icons.close_rounded,
                      label: t('رفض', 'Reject'),
                      color: c.danger,
                      onTap: busyId == x.id || onReject == null ? null : () => onReject!(x)),
                ],
              ]),
            ),
      ],
    );
  }
}

/// Asks for an optional note; null = cancelled, '' = no note.
Future<String?> askPointsNote(BuildContext context, {required String title, required String action, bool danger = false}) =>
    showAppSheet<String>(context, (ctx) => _NoteSheet(title: title, action: action, danger: danger));

class _NoteSheet extends StatefulWidget {
  const _NoteSheet({required this.title, required this.action, this.danger = false});

  final String title, action;
  final bool danger;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          AppSheetHeader(widget.title),
          AppField(controller: _note, label: t('ملاحظة (اختياري)', 'Note (optional)'), maxLines: 3),
          const SizedBox(height: 16),
          AppPrimaryButton(
              label: widget.action,
              icon: widget.danger ? Icons.close_rounded : Icons.check_rounded,
              onPressed: () => Navigator.pop(context, _note.text.trim())),
        ]),
      );
}

/// An image opens in a zoomable dialog; a PDF is saved / shared (the platform's own viewer opens it).
Future<void> showPointsReceipt(BuildContext context, Uint8List bytes, String title) async {
  if (bytes.isEmpty) {
    appToast(t('لا يوجد إيصال', 'No receipt available'), error: true);
    return;
  }
  if (isPdfBytes(bytes)) {
    await p8SaveBytes(bytes, '${title.replaceAll('#', '')}.pdf', mime: 'application/pdf');
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 4, 0),
          child: Row(children: [
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(15, w: FontWeight.w700, c: ctx.colors.textDark))),
            IconButton(tooltip: t('إغلاق', 'Close'), onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
          ]),
        ),
        Flexible(
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.memory(bytes,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(t('تعذّر عرض الإيصال', 'Could not show the receipt')),
                    )),
          ),
        ),
      ]),
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Users
// ═════════════════════════════════════════════════════════════════════════════

class _UsersTab extends StatefulWidget {
  const _UsersTab({required this.api});

  final PointsApi api;

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> with AutomaticKeepAliveClientMixin {
  final _q = TextEditingController();
  Timer? _debounce;
  List<PointsUserRow>? _rows;
  int _total = 0, _page = 1, _req = 0;
  String? _error;
  bool _more = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load({bool next = false}) async {
    final n = ++_req;
    final page = next ? _page + 1 : 1;
    setState(() {
      _error = null;
      _more = next;
    });
    try {
      final (rows, total) = await widget.api.users(q: _q.text, page: page);
      if (!mounted || n != _req) return;
      setState(() {
        _rows = next ? [...?_rows, ...rows] : rows;
        _total = total;
        _page = page;
        _more = false;
      });
    } catch (e) {
      if (mounted && n == _req) setState(() { _error = pointsErrorText(e); _more = false; });
    }
  }

  Future<void> _grant(PointsUserRow r) async {
    final balance = await showAppSheet<int>(
        context,
        (ctx) => PointsGrantForm(
              user: r.user,
              balance: r.balance,
              submit: (points, note) => widget.api.grant(userId: r.user.id, points: points, note: note),
            ));
    if (balance == null || !mounted) return;
    appToast(t('الرصيد الآن $balance نقطة', 'Balance is now $balance points'));
    setState(() => _rows = [
          for (final x in _rows ?? const <PointsUserRow>[]) x.user.id == r.user.id ? PointsUserRow(user: x.user, balance: balance) : x
        ]);
  }

  Future<void> _history(PointsUserRow r) =>
      showAppSheet<void>(context, (ctx) => _HistorySheet(api: widget.api, row: r));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AppRefresh(
      onRefresh: _load,
      child: AdminPointsUsersView(
        search: _q,
        rows: _rows,
        total: _total,
        error: _error,
        loadingMore: _more,
        onSearch: (_) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 400), _load);
        },
        onMore: (_rows?.length ?? 0) < _total ? () => _load(next: true) : null,
        onRetry: _load,
        onGrant: _grant,
        onHistory: _history,
      ),
    );
  }
}

/// The users list with plain values. [rows] null = loading (with no [error]).
class AdminPointsUsersView extends StatelessWidget {
  const AdminPointsUsersView({
    super.key,
    required this.search,
    required this.rows,
    this.total = 0,
    this.error,
    this.loadingMore = false,
    this.onSearch,
    this.onMore,
    this.onRetry,
    this.onGrant,
    this.onHistory,
  });

  final TextEditingController search;
  final List<PointsUserRow>? rows;
  final int total;
  final String? error;
  final bool loadingMore;
  final ValueChanged<String>? onSearch;
  final VoidCallback? onMore, onRetry;
  final ValueChanged<PointsUserRow>? onGrant, onHistory;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = rows;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        TextField(
          controller: search,
          onChanged: onSearch,
          decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: t('ابحث بالاسم أو البريد أو الهاتف', 'Search by name, e-mail or phone')),
        ),
        const SizedBox(height: 12),
        if (list == null && error == null)
          const AppListSkeleton(items: 5)
        else if (error != null && list == null)
          AppBanner(
              icon: Icons.error_outline_rounded,
              text: error!,
              color: c.danger,
              action: onRetry == null
                  ? null
                  : IconButton(tooltip: t('أعد المحاولة', 'Try again'), onPressed: onRetry, icon: const Icon(Icons.refresh_rounded)))
        else if (list!.isEmpty)
          AppEmpty(icon: Icons.person_search_rounded, title: t('لا نتائج', 'No results'))
        else ...[
          for (final r in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    AppAvatar(name: r.user.name, size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: c.textDark)),
                        if (r.user.contact.isNotEmpty)
                          Text(r.user.contact, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textLight)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${r.balance}', style: appText(17, w: FontWeight.w800, c: c.primary)),
                      Text(t('نقطة', 'points'), style: appText(11, c: c.textLight)),
                    ]),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    AppPill(
                        icon: Icons.add_circle_outline_rounded,
                        label: t('منح / خصم', 'Grant / deduct'),
                        onTap: onGrant == null ? null : () => onGrant!(r)),
                    AppPill(
                        icon: Icons.history_rounded,
                        label: t('السجل', 'History'),
                        onTap: onHistory == null ? null : () => onHistory!(r)),
                  ]),
                ]),
              ),
            ),
          if (error != null) AppBanner(icon: Icons.error_outline_rounded, text: error!, color: c.danger),
          if (onMore != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: loadingMore
                  ? const AppListSkeleton(items: 1)
                  : TextButton(onPressed: onMore, child: Text(t('المزيد (${list.length} من $total)', 'More (${list.length} of $total)'))),
            ),
        ],
      ],
    );
  }
}

/// Grant (positive) or deduct (negative) with a note; pops the new balance.
class PointsGrantForm extends StatefulWidget {
  const PointsGrantForm({super.key, required this.user, required this.balance, required this.submit});

  final PointsUser user;
  final int balance;
  final Future<int> Function(int points, String note) submit;

  @override
  State<PointsGrantForm> createState() => _PointsGrantFormState();
}

class _PointsGrantFormState extends State<PointsGrantForm> {
  final _points = TextEditingController();
  final _note = TextEditingController();
  bool _deduct = false, _saving = false;
  String? _error;

  @override
  void dispose() {
    _points.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final n = parsePoints(_points.text);
    if (n == null || n <= 0) return setState(() => _error = t('اكتب عدد النقاط', 'Enter the number of points'));
    if (_deduct && n > widget.balance) return setState(() => _error = pointsCodeText('points_negative_balance'));
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final b = await widget.submit(_deduct ? -n : n, _note.text.trim());
      if (mounted) Navigator.pop(context, b);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = pointsErrorText(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppSheetHeader(widget.user.name),
        Text('${t('الرصيد الحالي', 'Current balance')}: ${widget.balance} ${t('نقطة', 'points')}', style: appText(13, c: c.textMedium)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          AppChoiceChip(label: t('منح', 'Grant'), icon: Icons.add_rounded, selected: !_deduct, onTap: () => setState(() => _deduct = false)),
          AppChoiceChip(label: t('خصم', 'Deduct'), icon: Icons.remove_rounded, selected: _deduct, onTap: () => setState(() => _deduct = true)),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _points,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9٠-٩]'))],
          decoration: InputDecoration(labelText: t('عدد النقاط', 'Points'), prefixIcon: const Icon(Icons.stars_rounded)),
        ),
        const SizedBox(height: 12),
        AppField(controller: _note, label: t('ملاحظة', 'Note'), maxLines: 2),
        if (_error != null) ...[
          const SizedBox(height: 10),
          AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: c.danger),
        ],
        const SizedBox(height: 16),
        AppPrimaryButton(
            label: _deduct ? t('خصم النقاط', 'Deduct points') : t('منح النقاط', 'Grant points'),
            icon: Icons.check_rounded,
            busy: _saving,
            onPressed: _saving ? null : _save),
      ]),
    );
  }
}

class _HistorySheet extends StatefulWidget {
  const _HistorySheet({required this.api, required this.row});

  final PointsApi api;
  final PointsUserRow row;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  List<PointsLedgerEntry>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await widget.api.history(widget.row.user.id);
      if (mounted) setState(() => _items = r);
    } catch (e) {
      if (mounted) setState(() => _error = pointsErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(children: [
            AppSheetHeader('${t('سجل', 'History')} · ${widget.row.user.name}'),
            Expanded(child: PointsHistoryView(items: _items, error: _error, onRetry: _load)),
          ]),
        ),
      );
}

/// A ledger list with plain values. [items] null = loading (with no [error]).
class PointsHistoryView extends StatelessWidget {
  const PointsHistoryView({super.key, required this.items, this.error, this.onRetry});

  final List<PointsLedgerEntry>? items;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final list = items;
    if (list == null && error == null) return const AppListSkeleton(items: 5);
    if (error != null) {
      return AppBanner(
          icon: Icons.error_outline_rounded,
          text: error!,
          color: context.colors.danger,
          action: onRetry == null
              ? null
              : IconButton(tooltip: t('أعد المحاولة', 'Try again'), onPressed: onRetry, icon: const Icon(Icons.refresh_rounded)));
    }
    if (list!.isEmpty) return AppEmpty(icon: Icons.receipt_long_rounded, title: t('لا حركات بعد', 'No activity yet'));
    return ListView(children: [for (final e in list) LedgerTile(entry: e)]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Settings
// ═════════════════════════════════════════════════════════════════════════════

class _SettingsTab extends StatefulWidget {
  const _SettingsTab({required this.api});

  final PointsApi api;

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> with AutomaticKeepAliveClientMixin {
  PointsSettings? _s;
  String? _error;
  int _version = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await widget.api.settings();
      if (mounted) setState(() { _s = s; _version++; });
    } catch (e) {
      if (mounted) setState(() => _error = pointsErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = _s;
    if (s == null) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        if (_error == null)
          const AppListSkeleton(items: 6, withAvatar: false)
        else
          AppBanner(
              icon: Icons.error_outline_rounded,
              text: _error!,
              color: context.colors.danger,
              action: IconButton(tooltip: t('أعد المحاولة', 'Try again'), onPressed: _load, icon: const Icon(Icons.refresh_rounded))),
      ]);
    }
    return PointsSettingsForm(
      key: ValueKey('points_settings.$_version'),
      initial: s,
      save: (v) async {
        final saved = await widget.api.saveSettings(v);
        appToast(t('حُفظت الإعدادات', 'Settings saved'));
        return saved;
      },
    );
  }
}

/// The six settings of §9. [save] returns what the server stored.
class PointsSettingsForm extends StatefulWidget {
  const PointsSettingsForm({super.key, required this.initial, required this.save});

  final PointsSettings initial;
  final Future<PointsSettings> Function(PointsSettings) save;

  @override
  State<PointsSettingsForm> createState() => _PointsSettingsFormState();
}

class _PointsSettingsFormState extends State<PointsSettingsForm> {
  late final _free = TextEditingController(text: '${widget.initial.freeMinutes}');
  late final _price = TextEditingController(text: '${widget.initial.pricePoints}');
  late final _days = TextEditingController(text: '${widget.initial.planDays}');
  late final _point = TextEditingController(text: moneyText(widget.initial.pointPrice, ''));
  late final _currency = TextEditingController(text: widget.initial.currency);
  late final _min = TextEditingController(text: '${widget.initial.topupMin}');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_free, _price, _days, _point, _currency, _min]) {
      c.dispose();
    }
    super.dispose();
  }

  PointsSettings get _value => PointsSettings(
        freeMinutes: parsePoints(_free.text) ?? -1,
        pricePoints: parsePoints(_price.text) ?? 0,
        planDays: parsePoints(_days.text) ?? 0,
        pointPrice: double.tryParse(_point.text.trim().replaceAll(',', '.')) ?? 0,
        currency: _currency.text.trim().toUpperCase(),
        topupMin: parsePoints(_min.text) ?? 0,
      );

  Future<void> _save() async {
    final v = _value;
    if (v.error != null) return setState(() => _error = v.error);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(v);
      if (mounted) setState(() => _saving = false);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = pointsErrorText(e); });
    }
  }

  Widget _num(TextEditingController c, String label, {String? helper, bool decimal = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? '[0-9.,٠-٩]' : '[0-9٠-٩]'))],
          onChanged: (_) => setState(() => _error = null),
          decoration: InputDecoration(labelText: label, helperText: helper, helperMaxLines: 2),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = _value;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
      AppSectionTitle(t('باقة الاجتماعات المباشرة للطلاب', 'Student live-meeting plan')),
      _num(_free, t('الدقائق المجانية لكل اجتماع', 'Free minutes per meeting'),
          helper: t('وقت البث المجاني لاجتماع ينشئه طالب بلا باقة', 'Live time a student without the plan gets per meeting')),
      _num(_price, t('سعر الباقة (نقاط)', 'Plan price (points)')),
      _num(_days, t('مدة الباقة (أيام)', 'Plan length (days)')),
      AppSectionTitle(t('النقاط', 'Points')),
      _num(_point, t('سعر النقطة', 'Price of one point'), decimal: true),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AppField(controller: _currency, label: t('العملة', 'Currency'), hint: 'SAR', ltr: true),
      ),
      _num(_min, t('أقل عدد نقاط للشحن', 'Minimum top-up (points)')),
      if (v.error == null)
        AppBanner(
          icon: Icons.calculate_rounded,
          color: c.primary,
          text: t('الباقة = ${v.pricePoints} نقطة ≈ ${moneyText(v.planMoney, v.currency)} لـ ${v.planDays} يوماً',
              'The plan = ${v.pricePoints} points ≈ ${moneyText(v.planMoney, v.currency)} for ${v.planDays} days'),
        ),
      if (_error != null) ...[
        const SizedBox(height: 10),
        AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: c.danger),
      ],
      const SizedBox(height: 16),
      AppPrimaryButton(label: t('حفظ', 'Save'), icon: Icons.save_rounded, busy: _saving, onPressed: _saving ? null : _save),
    ]);
  }
}
