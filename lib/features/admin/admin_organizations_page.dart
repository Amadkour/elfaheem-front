// lib/features/admin/admin_organizations_page.dart
//
// PLATFORM admins review organizations: Waiting · Approved · Needs changes · Suspended.
// Approve (optionally trusting a university to approve its own faculties), ask for changes with a note,
// suspend / reactivate, and create organization-admin accounts.        API: /api/v1/admin/orgs
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart' show Trans;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:provider/provider.dart';

import '../org/org_common.dart' show openFileUrl, orgTypeIcons, orgTypeLabels;
import '../org/org_danger_zone.dart';
import '../org/org_providers.dart';
import '../org/org_v3.dart' show orgCall, orgErrorText;
import '../org/org_ui.dart';
import '../shared/rag/rag_quota_admin.dart' show showRagQuotaAdminSheet;
import 'admin_bulk.dart';
import 'admin_common.dart';
import 'admin_list.dart';
import 'admin_page.dart';
import 'admin_table_export.dart' show adminOrganizationsExport;
import 'package:flutter_education_app/utils/widget/phone_field.dart';
import 'package:flutter_education_app/design/app_inputs.dart';
import 'package:flutter_education_app/design/app_username.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

const _base = '/api/v1/admin/orgs';

/// Badge for the admin hub: how many organizations wait for a decision.
class AdminOrgReviewCount extends ChangeNotifier {
  int pending = 0;

  Future<void> load() async {
    final r = await OrgApi.i.getMap('$_base/stats');
    pending = asInt(r?['pending']);
    notifyListeners();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Pure logic (unit-tested in test/org/of_f3_admin_orgs_test.dart)
// ═════════════════════════════════════════════════════════════════════════════

/// The status filters of the list, in chip order. `all` asks the server for every live organization (C4).
const orgStatusFilters = ['pending', 'approved', 'rejected', 'suspended', 'deleted', 'all'];

/// The list query of a filter chip; an unknown value falls back to `pending`.
Map<String, dynamic> orgFilterQuery(String filter) => {'status': orgStatusFilters.contains(filter) ? filter : 'pending'};

/// The count shown on each chip, from `GET /admin/orgs/stats`. A status the server does not count is absent (the chip
/// then shows no number); `all` is the server's `total`/`all`, else the sum of the live statuses.
Map<String, int> orgFilterCounts(Map<String, dynamic>? stats) {
  if (stats == null) return const {};
  final out = <String, int>{};
  for (final k in orgStatusFilters) {
    if (k != 'all' && stats[k] != null) out[k] = asInt(stats[k]);
  }
  final total = stats['all'] ?? stats['total'];
  if (total != null) {
    out['all'] = asInt(total);
  } else if (out.isNotEmpty) {
    out['all'] = ['pending', 'approved', 'rejected', 'suspended'].fold<int>(0, (n, k) => n + (out[k] ?? 0));
  }
  return out;
}

String orgFilterLabel(String f) => switch (f) {
      'pending' => t('بانتظار المراجعة', 'Waiting'),
      'approved' => t('معتمدة', 'Approved'),
      'rejected' => t('تحتاج تعديل', 'Needs changes'),
      'suspended' => t('موقوفة', 'Suspended'),
      'deleted' => t('محذوفة', 'Deleted'),
      _ => t('الكل', 'All'),
    };

AppTone orgStatusTone(String s) => switch (s) {
      'approved' => AppTone.success,
      'pending' || 'rejected' => AppTone.warning,
      'suspended' => AppTone.danger,
      _ => AppTone.neutral,
    };

String orgStatusText(String s) => s == 'deleted' ? t('محذوفة', 'Deleted') : statusLabel(s);

/// Which actions the detail panel offers for an organization in [status] (a pure table so it can be tested).
Set<String> orgAdminActions(String status, {bool isRoot = true}) => switch (status) {
      'pending' => {'approve', 'reject', 'edit', 'delete', 'billing'},
      'approved' => {'suspend', 'edit', 'change_admin', 'open_dashboard', 'delete', 'billing'},
      'rejected' => {'edit', 'delete', 'billing'},
      'suspended' => {'reactivate', 'edit', 'change_admin', 'delete', 'billing'},
      'deleted' => {'restore'},
      _ => <String>{},
    };

// ═════════════════════════════════════════════════════════════════════════════
//  The list
// ═════════════════════════════════════════════════════════════════════════════

class AdminOrganizationsPage extends StatefulWidget {
  const AdminOrganizationsPage({super.key});

  @override
  State<AdminOrganizationsPage> createState() => _AdminOrganizationsPageState();
}

class _AdminOrganizationsPageState extends State<AdminOrganizationsPage> {
  final _p = OrgPaged(_base, orgFilterQuery('pending'));
  Map<String, int> _counts = const {};
  DateTime? _at;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    await Future.wait([_p.refresh(), _loadStats()]);
    if (mounted) setState(() => _at = DateTime.now());
  }

  Future<void> _loadStats() async {
    final r = await OrgApi.i.getMap('$_base/stats');
    if (mounted) setState(() => _counts = orgFilterCounts(r));
  }

  String get _filter => '${_p.filters['status']}';

  void _setFilter(String f) {
    _p.setFilter('status', orgFilterQuery(f)['status']);
    setState(_picked.clear);
  }

  /// The rows ticked in the table (bulk actions, D-290 phase 8).
  final Set<Object> _picked = {};

  List<Map<String, dynamic>> _pickedRows() => [
        for (final r in _p.rows)
          if (_picked.contains(asInt(r['id']))) r,
      ];

  /// Runs the panel's own decision call ([action]: approve / reactivate) for the picked rows in [from] statuses. The
  /// approval's welcome note is optional, so the bulk sends none; suspend / ask for changes / delete / restore need a
  /// reason per organization and stay on the panel.
  Future<void> _bulkDecide(String action, String label, Set<String> from) async {
    final ids = [
      for (final r in _pickedRows())
        if (from.contains('${r['status']}')) asInt(r['id']),
    ];
    if (ids.isEmpty || !await confirmAdminBulk(context, label, ids.length) || !mounted) return;
    await runAdminBulk(ids, (id) => ApiClient.instance.post('$_base/$id/$action', body: const <String, dynamic>{}), refresh: _reload);
    if (mounted) setState(_picked.clear);
  }

  List<Widget> _bulkActions() {
    final picked = _pickedRows();
    final statuses = {for (final r in picked) '${r['status']}'};
    return [
      if (statuses.contains('pending') || statuses.contains('rejected'))
        adminBulkButton(t('اعتماد', 'Approve'), Icons.verified_rounded,
            () => _bulkDecide('approve', t('اعتماد', 'Approve'), const {'pending', 'rejected'})),
      if (statuses.contains('suspended'))
        adminBulkButton(t('إعادة التفعيل', 'Reactivate'), Icons.play_circle_rounded,
            () => _bulkDecide('reactivate', t('إعادة التفعيل', 'Reactivate'), const {'suspended'})),
      adminBulkButton('md_p8_export_selected'.tr, Icons.file_download_outlined,
          () => showAppExportSheet(context, adminOrganizationsExport(picked, typeLabels: orgTypeLabels()))),
    ];
  }

  Future<void> _openAdmins() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminOrgAdminsPage()));

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      width: AppWidth.wide,
      title: t('المؤسسات', 'Organizations'),
      subtitle: t('اعتماد المؤسسات وإدارتها وتغيير مديريها', 'Approve, edit and manage organizations and their admins'),
      icon: Icons.domain_rounded,
      onRefresh: _reload,
      helpPageId: 'admin.organizations',
      updatedAt: _at,
      primaryAction: AppButton.primary(
        label: t('حساب مدير مؤسسة', 'Org-admin account'),
        icon: Icons.person_add_alt_1_rounded,
        onPressed: () => _createOrgAdmin(context),
      ),
      actions: [
        AppButton.secondary(label: t('مديرو المؤسسات', 'Organization admins'), icon: Icons.manage_accounts_rounded, onPressed: _openAdmins),
      ],
      body: ListenableBuilder(
        listenable: _p,
        builder: (context, _) {
          final g = AppSpace.gutter(MediaQuery.sizeOf(context).width);
          final failed = _p.error != null && _p.rows.isEmpty;
          final state = failed
              ? AppTableState.error
              : (!_p.loaded && _p.rows.isEmpty ? AppTableState.loading : AppTableState.ready);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: EdgeInsets.fromLTRB(g, AppSpace.sm, g, AppSpace.xs),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final f in orgStatusFilters)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
                      child: AppChoiceChip(
                        key: ValueKey('orgs.filter.$f'),
                        label: _counts[f] == null ? orgFilterLabel(f) : '${orgFilterLabel(f)} · ${_counts[f]}',
                        selected: _filter == f,
                        onTap: () => _setFilter(f),
                      ),
                    ),
                ]),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(g, 0, g, AppSpace.md),
                child: AppDataTable<Map<String, dynamic>>(
                  state: state,
                  errorText: _p.error,
                  onRetry: _reload,
                  rows: _p.rows,
                  rowId: (r) => asInt(r['id']),
                  selectable: true,
                  selected: _picked,
                  onSelectionChanged: (s) => setState(() => _picked
                    ..clear()
                    ..addAll(s)),
                  bulkActions: (_) => _bulkActions(),
                  searchHint: t('اسم المؤسسة أو رقم الترخيص', 'Name or licence number'),
                  onSearch: _p.setSearch,
                  onRowTap: (r) => _openReview(context, asInt(r['id']), _reload),
                  hasMore: _p.hasMore,
                  loadingMore: _p.loadingMore,
                  onLoadMore: _p.loadMore,
                  empty: AppEmpty(
                    icon: _filter == 'pending' ? Icons.task_alt_rounded : Icons.domain_disabled_rounded,
                    title: _filter == 'pending'
                        ? t('لا طلبات تنتظر المراجعة', 'No applications are waiting')
                        : t('لا مؤسسات هنا', 'No organizations here'),
                    message: _filter == 'all' || _filter == 'pending'
                        ? null
                        : t('جرّب فلتر «الكل» أو غيّر البحث.', 'Try the "All" filter or change the search.'),
                    actionLabel: _filter == 'all' ? null : t('عرض الكل', 'Show all'),
                    onAction: _filter == 'all' ? null : () => _setFilter('all'),
                  ),
                  columns: [
                    AppTableColumn<Map<String, dynamic>>(
                      key: 'name',
                      label: t('المؤسسة', 'Organization'),
                      primary: true,
                      flex: 4,
                      cell: (ctx, row) {
                        final parent = asMap(row['parent']);
                        return Row(children: [
                          Icon(orgTypeIcons[row['type']] ?? Icons.domain_rounded, color: hexColor(row['color'], ctx.colors.primary), size: AppIconSize.lg),
                          AppSpace.gapSm,
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                              Text(orgNameOf(row), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(ctx)),
                              Text(
                                  [
                                    orgTypeLabels()[row['type']] ?? '',
                                    if (parent.isNotEmpty) '${t('تابعة لـ', 'under')} ${orgNameOf(parent)}',
                                  ].where((s) => s.isNotEmpty).join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppType.meta(ctx)),
                            ]),
                          ),
                        ]);
                      },
                    ),
                    AppTableColumn<Map<String, dynamic>>(
                      key: 'status',
                      label: t('الحالة', 'Status'),
                      flex: 2,
                      cell: (ctx, row) => Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: AppStatusBadge(label: orgStatusText('${row['status']}'), tone: orgStatusTone('${row['status']}')),
                      ),
                    ),
                    AppTableColumn<Map<String, dynamic>>.text(
                      key: 'creator',
                      label: t('مقدم الطلب', 'Applicant'),
                      flex: 3,
                      text: (r) => '${asMap(r['creator'])['name'] ?? '—'}',
                    ),
                    AppTableColumn<Map<String, dynamic>>.text(
                      key: 'submitted',
                      label: t('أُرسل', 'Sent'),
                      flex: 2,
                      text: (r) => relTime(r['submitted_at']).isEmpty ? '—' : relTime(r['submitted_at']),
                    ),
                  ],
                  rowActions: (row) => [
                    AppRowAction<Map<String, dynamic>>(
                        icon: Icons.open_in_new_rounded, label: t('فتح', 'Open'), onTap: () => _openReview(context, asInt(row['id']), _reload)),
                  ],
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  One organization: review · edit · suspend · delete · restore · change admin
// ═════════════════════════════════════════════════════════════════════════════

Future<void> _openReview(BuildContext context, int id, Future<void> Function() reload) async {
  final d = await OrgApi.i.getMap('$_base/$id');
  if (d == null || !context.mounted) return;
  await showAppDrawer<void>(context, title: orgNameOf(d), width: 560, builder: (ctx) => OrgReviewPanel(org: d, onChanged: reload));
}

/// The detail panel of one organization (also pumped on its own by the tests).
class OrgReviewPanel extends StatefulWidget {
  const OrgReviewPanel({super.key, required this.org, required this.onChanged});
  final Map<String, dynamic> org;
  final Future<void> Function() onChanged;

  @override
  State<OrgReviewPanel> createState() => _OrgReviewPanelState();
}

class _OrgReviewPanelState extends State<OrgReviewPanel> {
  late Map<String, dynamic> d = Map<String, dynamic>.from(widget.org);
  late bool trustChildren = asMap(d['settings'])['child_approval'] == 'parent';
  late bool sharingOn = asMap(asMap(d['settings'])['sharing'])['enabled'] != false;
  bool busy = false;

  int get id => asInt(d['id']);
  String get status => '${d['status']}';

  /// Re-reads the organization after an action that keeps the panel open.
  Future<void> _refresh() async {
    final r = await OrgApi.i.getMap('$_base/$id');
    if (r != null && mounted) setState(() => d = r);
    await widget.onChanged();
  }

  Future<void> _decide(String action, {bool needNote = false}) async {
    String? note;
    if (needNote || action == 'approve') {
      note = await askText(context,
          title: switch (action) {
            'reject' => t('ما الذي يحتاج تعديلاً؟', 'What needs to change?'),
            'suspend' => t('سبب الإيقاف', 'Reason for suspension'),
            _ => t('رسالة ترحيب (اختياري)', 'Welcome message (optional)'),
          },
          multiline: true);
      if (note == null) return;
      if (needNote && note.trim().isEmpty) {
        showAppNotice(t('اكتب السبب ليعرف المتقدم ما المطلوب', 'Write the reason so they know what to do'), error: true);
        return;
      }
    }
    setState(() => busy = true);
    final r = await OrgApi.i.post('$_base/$id/$action', {
      'note': note,
      if (action == 'approve' && d['parent_id'] == null) 'child_approval': trustChildren ? 'parent' : 'platform',
    }, t('تم، وأُبلغ مدير المؤسسة', 'Done — the organization admin was notified'));
    if (!mounted) return;
    setState(() => busy = false);
    if (r != null) {
      await widget.onChanged();
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _edit() async {
    final ok = await showAppSheet<bool>(context, (ctx) => OrgProfileEditSheet(org: d));
    if (ok == true) await _refresh();
  }

  Future<void> _delete() async {
    final reason = await askTypedNameConfirm(context,
        org: d,
        title: t('حذف المؤسسة', 'Delete the organization'),
        body: t('تُخفى المؤسسة عن أعضائها وتبقى بياناتها محفوظة، ويمكن استعادتها لاحقاً.',
            'The organization is hidden from its members; its data is kept and it can be restored later.'),
        confirmLabel: t('حذف المؤسسة', 'Delete the organization'));
    if (reason == null || !mounted) return;
    setState(() => busy = true);
    final r = await orgCall(
        () => ApiClient().delete('$_base/$id', body: {'reason': reason, 'confirm_name': orgNameOf(d)}),
        ok: t('حُذفت المؤسسة', 'The organization was deleted'));
    if (!mounted) return;
    setState(() => busy = false);
    if (r.ok) {
      await widget.onChanged();
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _restore() async {
    final reason = await askText(context, title: t('سبب الاستعادة', 'Reason for restoring'), multiline: true);
    if (reason == null || !mounted) return;
    if (!orgReasonOk(reason)) {
      showAppNotice(t('اكتب سبباً من 5 أحرف على الأقل', 'Write a reason of at least 5 characters'), error: true);
      return;
    }
    setState(() => busy = true);
    final r = await orgCall(() => ApiClient().post('$_base/$id/restore', body: {'reason': reason.trim()}),
        ok: t('استُعيدت المؤسسة', 'The organization was restored'));
    if (!mounted) return;
    setState(() => busy = false);
    if (r.ok) {
      await widget.onChanged();
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _changeAdmin() async {
    final done = await showOrgTransferAdmin(context, orgId: id, orgName: orgNameOf(d), platform: true);
    if (done) await _refresh();
  }

  void _openDashboard() {
    // the platform admin's own organization list holds this one (my_role platform_admin)
    final nav = Navigator.of(context, rootNavigator: true);
    context.read<OrgSession>().open(id);
    Navigator.pop(context);
    nav.pushNamed('/org_dashboard'); // ROUTE: home.org
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final counts = asMap(d['counts']);
    final acts = orgAdminActions(status, isRoot: d['parent_id'] == null);
    Widget action(String label, IconData icon, VoidCallback onTap, {bool danger = false, bool tonal = false}) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: danger
              ? AppButton.danger(label: label, icon: icon, expand: true, onPressed: busy ? null : onTap)
              : tonal
                  ? AppButton.tonal(label: label, icon: icon, expand: true, onPressed: busy ? null : onTap)
                  : AppButton.secondary(label: label, icon: icon, expand: true, onPressed: busy ? null : onTap),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppStatusBadge(label: orgStatusText(status), tone: orgStatusTone(status)),
        AppStatusBadge(label: orgTypeLabels()[d['type']] ?? '${d['type']}'),
      ]),
      AppSpace.gapSm,
      if ('${d['description'] ?? ''}'.isNotEmpty) Text('${d['description']}', style: AppType.body(context)),
      AppSpace.gapXs,
      KeyValue(t('رقم الترخيص', 'Licence no.'), '${d['license_no'] ?? ''}'),
      KeyValue(t('البريد', 'E-mail'), '${d['contact_email'] ?? ''}'),
      KeyValue(t('الهاتف', 'Phone'), '${d['contact_phone'] ?? ''}'),
      KeyValue(t('الموقع', 'Website'), '${d['website'] ?? ''}'),
      KeyValue(t('العنوان', 'Address'), '${d['address'] ?? ''}'),
      KeyValue(t('مقدم الطلب', 'Applicant'), '${asMap(d['creator'])['name'] ?? ''} ${asMap(d['creator'])['email'] ?? ''}'),
      if (asMapList(d['admins']).isNotEmpty)
        KeyValue(t('مدير المؤسسة', 'Organization admin'), asMapList(d['admins']).map((a) => '${a['name'] ?? a['email'] ?? ''}').join('، ')),
      if (asMap(d['parent']).isNotEmpty) KeyValue(t('المؤسسة الأم', 'Parent'), orgNameOf(asMap(d['parent']))),
      KeyValue(t('الحجم', 'Size'),
          t('${counts['members']} عضو · ${counts['departments']} إدارة · ${counts['sub_organizations']} فرع',
              '${counts['members']} members · ${counts['departments']} departments · ${counts['sub_organizations']} branches')),
      for (final doc in asMapList(d['documents']))
        AppButton.ghost(label: '${doc['name']}', icon: Icons.description_rounded, onPressed: () => openFileUrl('${doc['url']}')),
      if ('${d['review_note'] ?? ''}'.isNotEmpty) KeyValue(t('آخر ملاحظة', 'Last note'), '${d['review_note']}'),
      if (status != 'deleted') ...[
        const Divider(height: AppSpace.lg),
        if (d['parent_id'] == null && status != 'rejected')
          AppSwitchTile(
            title: t('الثقة بالمؤسسة لاعتماد فروعها', 'Trust it to approve its own branches'),
            subtitle: t('الكليات والأقسام التي ينشئها مديرها تعمل مباشرة دون مراجعة المنصة',
                'Faculties and departments its admins create go live without platform review'),
            value: trustChildren,
            onChanged: (v) async {
              setState(() => trustChildren = v);
              if (status == 'approved') {
                await OrgApi.i.put('$_base/$id/policy', {'child_approval': v ? 'parent' : 'platform'}, t('تم', 'Done'));
              }
            },
          ),
        if (d['parent_id'] == null && status == 'approved')
          AppSwitchTile(
            key: const ValueKey('org.sharing'),
            title: t('مشاركة البيانات مع المؤسسات الأخرى', 'Data sharing with other organizations'),
            subtitle: t('إيقافها يمنع هذه المؤسسة من عرض أي مشاركة أو التحقق من خريجيها',
                'Off: this organization cannot offer shares or answer graduate verification'),
            value: sharingOn,
            onChanged: (v) async {
              setState(() => sharingOn = v);
              await OrgApi.i.put('$_base/$id/sharing', {'enabled': v}, t('تم', 'Done'));
            },
          ),
      ],
      AppSpace.gapSm,
      if (acts.contains('approve'))
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: AppButton.primary(label: t('اعتماد المؤسسة', 'Approve'), icon: Icons.verified_rounded, expand: true, busy: busy, onPressed: busy ? null : () => _decide('approve')),
        ),
      if (acts.contains('reject')) action(t('طلب تعديلات', 'Ask for changes'), Icons.edit_note_rounded, () => _decide('reject', needNote: true)),
      if (acts.contains('reactivate'))
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: AppButton.primary(label: t('إعادة التفعيل', 'Reactivate'), icon: Icons.play_circle_rounded, expand: true, busy: busy, onPressed: busy ? null : () => _decide('reactivate')),
        ),
      if (acts.contains('restore'))
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: AppButton.primary(label: t('استعادة المؤسسة', 'Restore the organization'), icon: Icons.restore_from_trash_rounded, expand: true, busy: busy, onPressed: busy ? null : _restore),
        ),
      if (acts.contains('open_dashboard')) action(t('فتح لوحة المؤسسة', 'Open the organization dashboard'), Icons.dashboard_rounded, _openDashboard, tonal: true),
      if (acts.contains('edit')) action(t('تعديل البيانات', 'Edit profile'), Icons.edit_rounded, _edit),
      if (acts.contains('change_admin')) action(t('تغيير مدير المؤسسة', 'Change the organization admin'), Icons.swap_horiz_rounded, _changeAdmin),
      if (acts.contains('billing')) action(t('رسوم العضوية', 'Membership fees'), Icons.payments_rounded, () => _billingSheet(context, id, orgNameOf(d))),
      // the assistant library's per-organization quota: the Super Admin's override (PUT /rag/orgs/{id}/quota)
      if (acts.contains('billing') && isSuperNow(context))
        Padding(
          key: const ValueKey('org.rag_quota'),
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: AppButton.secondary(
              label: t('حصة مكتبة المساعد', 'Assistant library quota'),
              icon: Icons.inventory_2_outlined,
              expand: true,
              onPressed: () => showRagQuotaAdminSheet(context, orgId: id, orgName: orgNameOf(d))),
        ),
      if (acts.contains('suspend')) action(t('إيقاف مؤقت', 'Suspend'), Icons.pause_circle_rounded, () => _decide('suspend', needNote: true), danger: true),
      if (acts.contains('delete')) ...[
        const Divider(height: AppSpace.lg),
        Text(t('منطقة الخطر', 'Danger zone'), style: AppType.section(context).copyWith(color: c.danger)),
        AppSpace.gapXs,
        action(t('حذف المؤسسة', 'Delete the organization'), Icons.delete_outline_rounded, _delete, danger: true),
      ],
    ]);
  }
}

/// Edit the profile of an organization as a platform admin: `PATCH /admin/orgs/{id}` with only the changed fields (C4).
class OrgProfileEditSheet extends StatefulWidget {
  const OrgProfileEditSheet({super.key, required this.org});
  final Map<String, dynamic> org;

  @override
  State<OrgProfileEditSheet> createState() => _OrgProfileEditSheetState();
}

class _OrgProfileEditSheetState extends State<OrgProfileEditSheet> {
  static const _keys = ['name_ar', 'name_en', 'description', 'contact_email', 'contact_phone', 'timezone'];
  late final Map<String, TextEditingController> _c = {
    for (final k in _keys) k: TextEditingController(text: '${widget.org[k] ?? ''}'),
  };
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Only what changed (the server leaves the other fields alone).
  Map<String, dynamic> diff() => orgProfileDiff(widget.org, {for (final k in _keys) k: _c[k]!.text});

  Future<void> _save() async {
    final body = diff();
    if (body.isEmpty) return Navigator.pop(context, false);
    if (body.containsKey('name_ar') || body.containsKey('name_en')) {
      final ar = (body['name_ar'] ?? _c['name_ar']!.text).toString().trim();
      final en = (body['name_en'] ?? _c['name_en']!.text).toString().trim();
      if (ar.isEmpty && en.isEmpty) return setState(() => _error = t('اكتب اسم المؤسسة', 'Enter the organization\'s name'));
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await orgCall(() => ApiClient().patch('$_base/${widget.org['id']}', body: body), quiet: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) return setState(() => _error = orgErrorText(r.error!));
    showAppNotice(t('تم الحفظ', 'Saved'));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget f(String k, String label, {bool ltr = false, int lines = 1}) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: TextField(
            controller: _c[k],
            minLines: lines,
            maxLines: lines + (lines > 1 ? 2 : 0),
            textDirection: ltr ? TextDirection.ltr : null,
            decoration: InputDecoration(labelText: label),
          ),
        );
    return AppSheetContent(title: t('تعديل بيانات المؤسسة', 'Edit organization profile'), children: [
      f('name_ar', t('الاسم بالعربية', 'Arabic name')),
      f('name_en', t('الاسم بالإنجليزية', 'English name'), ltr: true),
      f('description', t('نبذة', 'About'), lines: 3),
      f('contact_email', t('البريد الرسمي', 'Official e-mail'), ltr: true),
      f('contact_phone', t('هاتف التواصل', 'Contact phone'), ltr: true),
      f('timezone', t('المنطقة الزمنية (مثل Africa/Cairo)', 'Time zone (e.g. Africa/Cairo)'), ltr: true),
      if (_error != null) Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: Text(_error!, style: AppType.meta(context).copyWith(color: c.danger))),
      AppButton.primary(label: t('حفظ', 'Save'), icon: Icons.check_rounded, expand: true, busy: _busy, onPressed: _busy ? null : _save),
    ]);
  }
}

/// The fields of [now] that differ from [org] (trimmed); an emptied optional field is sent as ''.
Map<String, dynamic> orgProfileDiff(Map<String, dynamic> org, Map<String, String> now) {
  final out = <String, dynamic>{};
  for (final e in now.entries) {
    final before = '${org[e.key] ?? ''}'.trim();
    final after = e.value.trim();
    if (before != after) out[e.key] = after;
  }
  return out;
}

Future<void> _createOrgAdmin(BuildContext context) async {
  final name = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  bool busy = false, verify = true;
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(t('حساب مدير مؤسسة', 'Organization-admin account')),
            Text(t('يستطيع صاحب الحساب إنشاء جامعته أو كليته وإرسالها للمراجعة.', 'The account owner can create their university or faculty and send it for review.'),
                style: orgText(ctx, size: 12.5, color: ctx.colors.textMedium)),
            const SizedBox(height: 12),
            Field(controller: name, label: t('الاسم', 'Name')),
            AppEmailField(controller: email, label: t('البريد', 'E-mail')),
            PhoneInputField(controller: phone, label: t('الهاتف (اختياري)', 'Phone (optional)')),   // same field as registration
            OrgSwitchRow(
              title: t('تأكيد البريد الإلكتروني', 'Verify the e-mail'),
              subtitle: t('نرسل رمزاً للبريد ويؤكّده المدير عند أول دخول', 'We e-mail a code; the admin confirms it at first sign-in'),
              value: verify,
              onChanged: (v) => set(() => verify = v),
            ),
            const SizedBox(height: 6),
            PrimaryButton(
              isLoading: busy,
              label: t('إنشاء الحساب', 'Create account'),
              onPressed: () async {
                set(() => busy = true);
                final r = await OrgApi.i.post('$_base/org-admins',
                    {'name': name.text.trim(), 'email': email.text.trim(), 'send_verification': verify,
                      if (phone.text.trim().isNotEmpty) 'phone': phone.text.trim()});
                if (!ctx.mounted) return;
                set(() => busy = false);
                if (r is Map) {
                  Navigator.pop(ctx);
                  if (r['generated_password'] != null && context.mounted) {
                    await showDialog<void>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text(t('بيانات الدخول (تظهر مرة واحدة)', 'Login details (shown once)')),
                        content: SelectableText('${r['email']}\n${r['generated_password']}', textDirection: TextDirection.ltr),
                      ),
                    );
                  } else {
                    toast(t('الحساب موجود وجاهز', 'The account exists and is ready'));
                  }
                }
              },
            ),
          ]),
        );
      }));
}

// ═════════════════════════════════════════════════════════════════════════════
//  Organization admins — the platform manages the people who run organizations
// ═════════════════════════════════════════════════════════════════════════════

class AdminOrgAdminsPage extends StatelessWidget {
  const AdminOrgAdminsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => OrgPaged('$_base/org-admins')..refresh(),
      child: Builder(builder: (context) {
        final p = context.watch<OrgPaged>();
        final c = context.colors;
        return BasePage(
          useWebCard: true,
          width: AppWidth.wide,
          appBar: ScreenAppBar(title: t('مديرو المؤسسات', 'Organization admins'), actions: [
            IconButton(
              tooltip: t('حساب جديد', 'New account'),
              onPressed: () async {
                await _createOrgAdmin(context);
                p.refresh();
              },
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
          ]),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: SearchBox(hint: t('الاسم أو البريد أو الهاتف', 'Name, e-mail or phone'), onChanged: p.setSearch),
            ),
            Expanded(
              child: PagedList<OrgPaged>(
                emptyText: t('لا يوجد مديرو مؤسسات بعد', 'No organization admins yet'),
                itemBuilder: (context, row) {
                  final verified = row['email_verified'] == true;
                  final active = row['is_active'] != false;
                  final orgs = asMapList(row['organizations']);
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
                    child: RowCard(
                      accent: active ? null : c.danger,
                      onTap: () => _manageOrgAdmin(context, row),
                      child: Row(children: [
                        AdminAvatar(name: '${row['name']}', url: row['image_url'] as String?),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${row['name']}', style: orgText(context, w: FontWeight.w800)),
                            AppUsernameLine(usernameFrom(row)),
                            Text('${row['email']}', textDirection: TextDirection.ltr,
                                style: orgText(context, size: 12, color: c.textMedium)),
                            const SizedBox(height: 4),
                            Wrap(spacing: 6, runSpacing: 4, children: [
                              OrgPill(verified ? t('بريد مؤكَّد', 'E-mail verified') : t('بريد غير مؤكَّد', 'E-mail not verified'),
                                  color: verified ? c.success : c.warning,
                                  icon: verified ? Icons.verified_rounded : Icons.mark_email_unread_rounded),
                              if (!active) OrgPill(t('معطَّل', 'Disabled'), color: c.danger, icon: Icons.block_rounded),
                              for (final o in orgs.take(2)) OrgPill(orgNameOf(o), icon: Icons.domain_rounded, color: c.textMedium),
                            ]),
                          ]),
                        ),
                        Icon(Icons.chevron_right_rounded, color: c.textLight),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ]),
        );
      }),
    );
  }
}

Future<void> _manageOrgAdmin(BuildContext context, Map<String, dynamic> row) async {
  final p = context.read<OrgPaged>();
  final name = TextEditingController(text: '${row['name'] ?? ''}');
  final email = TextEditingController(text: '${row['email'] ?? ''}');
  final phone = TextEditingController(text: '${row['phone'] ?? ''}');
  bool active = row['is_active'] != false, busy = false;
  final url = '$_base/org-admins/${row['id']}';
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        Future<void> showPassword(String pwd) => showDialog<void>(
              context: ctx,
              builder: (_) => AlertDialog(
                title: Text(t('كلمة المرور الجديدة (تظهر مرة واحدة)', 'New password (shown once)')),
                content: SelectableText(pwd, textDirection: TextDirection.ltr),
              ),
            );
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader('${row['name']}'),
            Field(controller: name, label: t('الاسم', 'Name')),
            AppEmailField(controller: email, label: t('البريد الإلكتروني', 'E-mail')),
            PhoneInputField(controller: phone, label: t('الهاتف', 'Phone')),
            OrgSwitchRow(
              title: t('الحساب مفعّل', 'Account active'),
              subtitle: t('عند التعطيل لا يستطيع تسجيل الدخول', 'When disabled they cannot sign in'),
              value: active,
              onChanged: (v) => set(() => active = v),
            ),
            const SizedBox(height: 8),
            PrimaryButton(
              isLoading: busy,
              label: t('حفظ', 'Save'),
              onPressed: () async {
                set(() => busy = true);
                final r = await OrgApi.i.put(url, {
                  'name': name.text.trim(),
                  'email': email.text.trim(),
                  'phone': phone.text.trim(),
                  'is_active': active,
                }, email.text.trim().toLowerCase() != '${row['email']}'.toLowerCase()
                    ? t('تم الحفظ — أُرسل رمز تأكيد للبريد الجديد', 'Saved — a verification code was sent to the new e-mail')
                    : t('تم الحفظ', 'Saved'));
                if (!ctx.mounted) return;
                set(() => busy = false);
                if (r != null) {
                  p.refresh();
                  Navigator.pop(ctx);
                }
              },
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    // type a password, or leave it empty to generate a strong one — they are signed out everywhere
                    final pwd = TextEditingController();
                    final go = await showDialog<bool>(
                      context: ctx,
                      builder: (dc) => AlertDialog(
                        scrollable: true,
                        title: Text(t('كلمة مرور جديدة', 'New password')),
                        content: Column(mainAxisSize: MainAxisSize.min, children: [
                          AppPasswordField(controller: pwd, label: t('اكتبها أو اتركها فارغة لتوليد واحدة قوية', 'Type it, or leave empty to generate a strong one'),
                              required: false, showStrength: true, minLength: 8),
                          Text(t('سيُسجَّل خروجه من كل الأجهزة.', 'They will be signed out on every device.'), style: TextStyle(fontFamily: AppFonts.family, fontSize: 12)),
                        ]),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(dc, false), child: Text(t('إلغاء', 'Cancel'))),
                          FilledButton(onPressed: () => Navigator.pop(dc, true), child: Text(t('حفظ', 'Save'))),
                        ],
                      ),
                    );
                    if (go != true) return;
                    final r = await OrgApi.i.post('$url/reset-password', {if (pwd.text.isNotEmpty) 'password': pwd.text});
                    if (r is Map && ctx.mounted) await showPassword('${r['generated_password']}');
                  },
                  icon: const Icon(Icons.key_rounded),
                  label: Text(t('كلمة مرور جديدة', 'New password')),
                ),
              ),
              const SizedBox(width: 8),
              if (row['email_verified'] != true)
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: c.warning),
                    onPressed: () async {
                      final r = await OrgApi.i.post('$url/send-verification');
                      if (r is Map) {
                        toast(r['sent'] == true
                            ? t('أُرسل رمز التأكيد إلى البريد ✉️', 'Verification code sent ✉️')
                            : t('تعذّر الإرسال الآن — حاول لاحقاً', 'Could not send now — try later'), error: r['sent'] != true);
                      }
                    },
                    icon: const Icon(Icons.mark_email_read_rounded),
                    label: Text(t('إرسال تأكيد البريد', 'Send e-mail verification')),
                  ),
                ),
            ]),
          ]),
        );
      }));
}


/// Membership fees of one organization (platform admins): staff · admins · students (free / per course / per account
/// with this organization's own plans and prices).
Future<void> _billingSheet(BuildContext context, int orgId, String orgName) async {
  final url = '$_base/$orgId/billing';
  final b = await OrgApi.i.getMap(url);
  if (b == null || !context.mounted) return;
  bool staffFree = b['staff_free'] != false, adminsFree = b['admins_free'] != false, busy = false;
  String students = '${b['students'] ?? 'per_account'}';
  final platform = asMapList(b['platform_plans']);
  final chosen = Map<String, dynamic>.from(asMap(b['plans']));
  final prices = {for (final p in platform) '${p['code']}': TextEditingController(text: '${chosen['${p['code']}'] ?? p['price']}')};
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        Widget mode(String key, IconData icon, String title, String sub) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => set(() => students = key),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: students == key ? c.primary.withValues(alpha: 0.08) : c.cardBg,
                    border: Border.all(color: students == key ? c.primary : c.divider, width: students == key ? 1.6 : 1),
                  ),
                  child: Row(children: [
                    Icon(icon, color: students == key ? c.primary : c.textMedium),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: orgText(ctx, w: FontWeight.w800)),
                      Text(sub, style: orgText(ctx, size: 12, color: c.textMedium)),
                    ])),
                    if (students == key) Icon(Icons.check_circle_rounded, color: c.primary),
                  ]),
                ),
              ),
            );
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader('${t('رسوم العضوية', 'Membership fees')} · $orgName'),
            OrgSwitchRow(title: t('مجاني لهيئة التدريس والموظفين', 'Free for teaching & admin staff'),
                subtitle: t('عند الإيقاف يلزمهم اشتراك', 'When off they need a subscription'), value: staffFree, onChanged: (v) => set(() => staffFree = v)),
            OrgSwitchRow(title: t('مجاني لمديري المؤسسة', 'Free for organization admins'), value: adminsFree, onChanged: (v) => set(() => adminsFree = v)),
            const SizedBox(height: 10),
            Text(t('الطلاب', 'Students'), style: orgText(ctx, w: FontWeight.w800)),
            const SizedBox(height: 8),
            mode('free', Icons.volunteer_activism_rounded, t('مجاني', 'Free'), t('بدون اشتراك، ومقررات المؤسسة بدون رسوم', 'No subscription; the organization\'s courses at no cost')),
            mode('per_course', Icons.menu_book_rounded, t('بالمقرر', 'Per course'), t('بدون اشتراك حساب — يدفع الطالب لكل مقرر', 'No account subscription — each course is paid')),
            mode('per_account', Icons.account_circle_rounded, t('بالحساب (اشتراك)', 'Per account (subscription)'), t('اشتراك بخطط وأسعار هذه المؤسسة', 'A subscription with this organization\'s plans & prices')),
            if (students == 'per_account') ...[
              const SizedBox(height: 6),
              Text(t('الخطط المتاحة وأسعارها لهذه المؤسسة', 'Plans offered & their prices for this organization'),
                  style: orgText(ctx, size: 12.5, w: FontWeight.w700, color: c.textMedium)),
              for (final p in platform)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Checkbox(value: chosen.containsKey('${p['code']}'),
                        onChanged: (v) => set(() => v == true ? chosen['${p['code']}'] = p['price'] : chosen.remove('${p['code']}'))),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t('${p['name_ar']}', '${p['name_en']}'), style: orgText(ctx, w: FontWeight.w700)),
                      Text('${t('سعر المنصة', 'Platform price')}: ${p['price']} ${p['currency']}', style: orgText(ctx, size: 11.5, color: c.textLight)),
                    ])),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: prices['${p['code']}'],
                        enabled: chosen.containsKey('${p['code']}'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(isDense: true, suffixText: '${p['currency']}'),
                      ),
                    ),
                  ]),
                ),
            ],
            const SizedBox(height: 16),
            PrimaryButton(isLoading: busy, label: t('حفظ', 'Save'), onPressed: () async {
              set(() => busy = true);
              final r = await OrgApi.i.put(url, {
                'staff_free': staffFree, 'admins_free': adminsFree, 'students': students,
                'plans': students == 'per_account'
                    ? {for (final k in chosen.keys) k: double.tryParse(prices[k]?.text ?? '') ?? 0}
                    : <String, double>{},
              }, t('تم الحفظ — يطبَّق فوراً', 'Saved — applies right away'));
              if (!ctx.mounted) return;
              set(() => busy = false);
              if (r != null) Navigator.pop(ctx);
            }),
          ]),
        );
      }));
}
