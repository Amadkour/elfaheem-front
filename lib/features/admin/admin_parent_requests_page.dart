// lib/features/admin/admin_parent_requests_page.dart
// Admin / super-admin: parent ⇄ student link requests — list, filters, detail with the answers and the
// attached documents, approve / reject (the decision, its author and the note are recorded server-side).
// Documents are private: each "open" asks the server for a 5-minute signed link.
// Needs: url_launcher (to open PDFs).
//
//   Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminParentRequestsPage()));
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/core/share/external_link.dart';

import '../../config/app_config.dart';
import '../parent/parent_link_providers.dart';
import '../parent/parent_widgets.dart' show plDateTime, plLabel, plList;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart' show EntityKind;
import 'admin_common.dart' show adminEntityCell, t;
import 'admin_labels.dart';
import 'admin_page.dart';

AppTone _statusTone(String s) => switch (s) {
      'approved' => AppTone.success,
      'rejected' || 'failed' => AppTone.danger,
      'cancelled' => AppTone.neutral,
      _ => AppTone.warning,
    };

class AdminParentRequestsPage extends StatelessWidget {
  const AdminParentRequestsPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => AdminParentLinkProvider()..loadRequests(),
        child: const _List(),
      );
}

class _List extends StatefulWidget {
  const _List();

  @override
  State<_List> createState() => _ListState();
}

class _ListState extends State<_List> {
  DateTime? _loadedAt;

  Future<void> _reload() async {
    await context.read<AdminParentLinkProvider>().loadRequests();
    if (mounted) setState(() => _loadedAt = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminParentLinkProvider>();
    return AdminPage(
      width: AppWidth.wide,
      title: 'pl_requests_title'.tr,
      icon: Icons.family_restroom_rounded,
      onRefresh: p.isLoading ? null : _reload,
      updatedAt: _loadedAt,
      body: const ParentRequestsBody(),
    );
  }
}

/// The requests table (search, status filter, load more, the detail page on a row tap) without a page header, so it
/// sits under [AdminParentRequestsPage]'s own header or inside a tab of the Parent linking page. Reads the
/// [AdminParentLinkProvider] above it.
class ParentRequestsBody extends StatelessWidget {
  const ParentRequestsBody({super.key});

  void _runSearch(BuildContext context, String v) {
    final p = context.read<AdminParentLinkProvider>();
    if (p.search == v.trim()) return;
    p.search = v.trim();
    p.loadRequests();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminParentLinkProvider>();
    final first = p.items.isEmpty;
    return Padding(
        padding: AdminPage.bodyPadding(context),
        child: AppDataTable<Map<String, dynamic>>(
          state: p.isLoading && first
              ? AppTableState.loading
              : p.hasError && first
                  ? AppTableState.error
                  : AppTableState.ready,
          errorText: p.errorMessage,
          onRetry: p.loadRequests,
          rows: p.items,
          searchHint: 'pl_search_hint'.tr,
          onSearch: (v) => _runSearch(context, v),
          filters: [
            AppTableFilter(
              label: t('الحالة', 'Status'),
              value: p.status.isEmpty ? null : p.status,
              options: [
                for (final s in ['pending', 'approved', 'rejected', 'failed', 'cancelled'])
                  (s, '${'pl_status_$s'.tr}${s == 'pending' && p.pendingTotal > 0 ? ' (${p.pendingTotal})' : ''}'),
              ],
              onChanged: (v) => p.setFilter(status: v ?? ''),
            ),
          ],
          empty: AppEmpty(icon: Icons.family_restroom_rounded, title: 'pl_no_requests'.tr),
          hasMore: p.page < p.pages,
          loadingMore: p.loadingMore,
          onLoadMore: p.loadMore,
          onRowTap: (r) => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider.value(value: p, child: _Detail(id: (r['id'] as num).toInt())),
          )),
          columns: [
            AppTableColumn<Map<String, dynamic>>(
              key: 'who',
              label: t('الطلب', 'Request'),
              primary: true,
              flex: 3,
              // the parent is not an entity (plain text); the student opens the panel / full page (D-290)
              cell: (ctx, r) => Wrap(spacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${r['parent_name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(ctx)),
                Icon(Icons.arrow_forward_rounded, size: AppIconSize.xs, color: ctx.colors.textMedium),
                adminEntityCell(ctx, EntityKind.student, {'id': r['student_id'], 'name': r['student_name']}),
              ]),
            ),
            AppTableColumn<Map<String, dynamic>>.text(
              key: 'mode',
              label: t('الطريقة', 'Method'),
              text: (r) => 'pl_mode_${r['mode']}'.tr,
            ),
            AppTableColumn<Map<String, dynamic>>(
              key: 'status',
              label: t('الحالة', 'Status'),
              cell: (context, r) => AppStatusBadge(label: 'pl_status_${r['status']}'.tr, tone: _statusTone('${r['status']}')),
            ),
            AppTableColumn<Map<String, dynamic>>.text(
              key: 'docs',
              label: t('المستندات', 'Documents'),
              numeric: true,
              text: (r) => '${r['documents_count'] ?? 0}',
            ),
            AppTableColumn<Map<String, dynamic>>.text(
              key: 'created_at',
              label: t('التاريخ', 'Date'),
              text: (r) => plDateTime(r['created_at']),
            ),
          ],
        ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
class _Detail extends StatefulWidget {
  const _Detail({required this.id});

  final int id;

  @override
  State<_Detail> createState() => _DetailState();
}

class _DetailState extends State<_Detail> {
  Map<String, dynamic>? _d;
  bool _busy = false, _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final p = context.read<AdminParentLinkProvider>();
    setState(() {
      _loading = true;
      _error = null;
    });
    final d = await p.detail(widget.id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _d = d;
      if (d == null) _error = p.errorMessage ?? 'ds_error_body'.tr;
    });
  }

  /// The note sheet of an approve / reject (its controller leaves with the sheet).
  Future<String?> _askNote(String title, String hint, {required bool required}) async {
    final ctrl = TextEditingController();
    bool tooShort = false;
    final res = await showAppSheet<String>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          return AppSheetContent(title: title, children: [
            AppField(controller: ctrl, label: hint, maxLines: 3),
            if (tooShort)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: Text(t('اكتب السبب (3 أحرف على الأقل)', 'Write the reason (at least 3 characters)'),
                    style: AppType.meta(ctx).copyWith(color: ctx.colors.danger)),
              ),
            AppButton.primary(
              label: 'pl_confirm'.tr,
              expand: true,
              onPressed: () {
                if (required && ctrl.text.trim().length < 3) {
                  set(() => tooShort = true);
                  return;
                }
                Navigator.pop(ctx, ctrl.text.trim());
              },
            ),
          ]);
        }));
    disposeAfterRoute([ctrl]);
    return res;
  }

  Future<void> _decide(bool approve) async {
    final note = await _askNote(approve ? 'pl_approve'.tr : 'pl_reject'.tr, approve ? 'pl_note_optional'.tr : 'pl_reject_reason'.tr,
        required: !approve);
    if (note == null || !mounted) return;
    setState(() => _busy = true);
    final p = context.read<AdminParentLinkProvider>();
    final r = await p.decide(widget.id, approve: approve, note: note);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r != null) _d = r;
    });
    showAppNotice(r == null ? (p.errorMessage ?? 'ds_error_body'.tr) : 'pl_decision_saved'.tr, error: r == null);
  }

  Future<void> _openDoc(Map<String, dynamic> doc) async {
    final p = context.read<AdminParentLinkProvider>();
    final link = await p.documentLink((doc['id'] as num).toInt());
    if (link == null || !mounted) {
      showAppNotice(p.errorMessage ?? 'ds_error_body'.tr, error: true);
      return;
    }
    final url = p.absoluteUrl('${link['path']}');
    if (doc['file_type'] == 'pdf') {
      await openExternalLink(url);
      return;
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(AppSpace.sm),
        child: Stack(children: [
          InteractiveViewer(
            child: Image.network(url, fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Padding(padding: const EdgeInsets.all(AppSpace.xl), child: Text('pl_file_load_failed'.tr))),
          ),
          PositionedDirectional(
              top: AppSpace.xxs,
              end: AppSpace.xxs,
              child: AppIconButton(icon: Icons.close_rounded, tooltip: t('إغلاق', 'Close'), onPressed: () => Navigator.pop(ctx))),
        ]),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(k, style: AppType.meta(context))),
          Expanded(child: SelectableText(v.isEmpty ? '—' : v, style: AppType.body(context))),
        ]),
      );

  Widget _block(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: AppType.section(context)),
            AppSpace.gapXs,
            ...children,
          ]),
        ),
      );

  Widget _person(String title, Map m, {bool student = false}) => _block(title, [
        if (student)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
            child: Row(children: [
              SizedBox(width: 120, child: Text('pl_name'.tr, style: AppType.meta(context))),
              Flexible(child: adminEntityCell(context, EntityKind.student, m)),
            ]),
          )
        else
          _kv('pl_name'.tr, '${m['name'] ?? ''}'),
        _kv(t('البريد', 'E-mail'), '${m['email'] ?? ''}'),
        _kv('pl_phone'.tr, '${m['phone'] ?? ''}'),
      ]);

  Widget _content(Map<String, dynamic> d) {
    final c = context.colors;
    final answers = plList(d['answers']);
    final docs = plList(d['documents']);
    final ver = d['verification_result'];
    return ListView(padding: AdminPage.bodyPadding(context), children: [
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AppStatusBadge(label: 'pl_status_${d['status']}'.tr, tone: _statusTone('${d['status']}')),
          Text('${'pl_mode_${d['mode']}'.tr} · ${plDateTime(d['created_at'])}', style: AppType.meta(context)),
        ]),
      ),
      _person('pl_parent'.tr, d['parent'] as Map? ?? {}),
      _person('pl_student'.tr, d['student'] as Map? ?? {}, student: true),
      if (answers.isNotEmpty) _block('pl_answers'.tr, [for (final a in answers) _kv(plLabel(a), '${a['value']}')]),
      if (docs.isNotEmpty)
        _block('pl_documents'.tr, [
          for (final x in docs)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(x['file_type'] == 'pdf' ? Icons.picture_as_pdf_rounded : Icons.image_rounded, color: c.primary),
              title: Text(plLabel(x)),
              subtitle: Text('${x['file_name'] ?? ''} · ${((x['file_size'] as num?) ?? 0) ~/ 1024} KB'),
              trailing: const Icon(Icons.open_in_new_rounded),
              onTap: () => _openDoc(x),
            ),
        ]),
      if (ver is Map)
        _block('pl_verification'.tr, [
          _kv('pl_verified'.tr, ver['verified'] == true ? t('نعم', 'Yes') : t('لا', 'No')),
          _kv('pl_reason'.tr, '${ver['reason'] ?? ''}'),
          _kv(t('رمز استجابة الخادم', 'Server response code'), '${ver['http_status'] ?? '—'}'),
        ]),
      if (d['status'] != 'pending' && d['reviewed_at'] != null)
        _block('pl_decision'.tr, [
          _kv('pl_by'.tr, '${d['reviewer_name'] ?? '—'}'),
          _kv('pl_at'.tr, plDateTime(d['reviewed_at'])),
          _kv('pl_admin_note'.tr, '${d['decision_note'] ?? ''}'),
        ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final pending = d != null && d['status'] == 'pending';
    return AdminPage(
      title: 'pl_request_details'.tr,
      icon: Icons.family_restroom_rounded,
      onRefresh: _loading || _busy ? null : _load,
      // approve is THE action; reject sits beside it as a danger outline
      primaryAction: pending ? AppButton.primary(label: 'pl_approve'.tr, icon: Icons.check_rounded, busy: _busy, onPressed: _busy ? null : () => _decide(true)) : null,
      actions: pending
          ? [AppButton.danger(label: 'pl_reject'.tr, icon: Icons.close_rounded, dangerOutline: true, onPressed: _busy ? null : () => _decide(false))]
          : const [],
      body: _loading
          ? const AppListSkeleton()
          : d == null
              ? Center(child: AppErrorState(message: _error, onRetry: _load))
              : _content(d),
    );
  }
}
