// lib/features/shared/certificates_issue/cert_issue_lists.dart
//
// Saved recipient lists ("October batch"): the list of lists, one list's people, add one new person and issue to
// that person only (POST lists/{id}/people {issue: true} → a batch of one), issue the whole list again, rename,
// delete. Plus the picker sheet the issuing flow opens ("Open a saved list").
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_chip.dart' show EntityGuardedChip;

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../design/app_kit.dart';
import '../../../design/app_notice.dart';
import '../../../design/app_tokens.dart';
import '../../../core/api_client.dart';
import '../../../core/api_error_text.dart';
import '../../../utils/widget/parent_component.dart';
import 'cert_issue_actions.dart';
import 'cert_issue_api.dart';
import 'cert_issue_history.dart';
import 'cert_issue_logic.dart';
import 'cert_issue_photos.dart';
import 'cert_issue_parts.dart';

/// The flow's "Open a saved list": the lists in a sheet; the tapped one (without its rows) or null.
Future<RecipientListInfo?> pickCertSavedList(BuildContext context, {required CertIssueApi api, int? orgId}) {
  final future = api.lists(orgId: orgId);
  return showAppSheet<RecipientListInfo>(context, (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.md),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSheetHeader('ci_open_list'.tr),
          Flexible(
            child: FutureBuilder<List<RecipientListInfo>>(
              future: future,
              builder: (ctx, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const AppListSkeleton(items: 3, withAvatar: false, padding: EdgeInsets.zero);
                }
                if (snap.hasError) return IssueErrorBox(message: certIssueErrorText(snap.error!));
                final items = snap.data ?? const [];
                if (items.isEmpty) {
                  return AppEmpty(icon: Icons.groups_2_outlined, title: 'ci_lists_empty'.tr, message: 'ci_lists_empty_sub'.tr);
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpace.xs),
                  itemBuilder: (ctx, i) => IssueSavedListTile(list: items[i], onTap: () => Navigator.pop(ctx, items[i])),
                );
              },
            ),
          ),
        ]),
      ));
}

class CertSavedListsPage extends StatefulWidget {
  const CertSavedListsPage({super.key, this.designId, this.orgId, this.langs, this.api});

  /// The design new issues use (a list remembers its own; this one wins when given).
  final int? designId;
  final int? orgId;
  final List<String>? langs;
  final CertIssueApi? api;

  @override
  State<CertSavedListsPage> createState() => _CertSavedListsPageState();
}

class _CertSavedListsPageState extends State<CertSavedListsPage> {
  late final CertIssueApi _api = widget.api ?? CertIssueApi();
  List<RecipientListInfo> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.lists(orgId: widget.orgId);
      if (!mounted) return;
      setState(() {
        _items = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = certIssueErrorText(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget body;
    if (_loading && _items.isEmpty) {
      body = const AppListSkeleton(withAvatar: false);
    } else if (_error != null && _items.isEmpty) {
      body = Padding(padding: AppSpace.card, child: Align(alignment: Alignment.topCenter, child: IssueErrorBox(message: _error!, onRetry: _load)));
    } else if (_items.isEmpty) {
      body = AppEmpty(icon: Icons.groups_2_outlined, title: 'ci_lists_empty'.tr, message: 'ci_lists_empty_sub'.tr);
    } else {
      body = AppRefresh(
        onRefresh: _load,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpace.md),
          itemCount: _items.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpace.xs),
          itemBuilder: (context, i) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: IssueSavedListTile(
                list: _items[i],
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => CertListDetailPage(
                        listId: _items[i].id, designId: widget.designId, langs: widget.langs, api: _api, initial: _items[i]),
                  ));
                  if (mounted) _load();
                },
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppHeader(title: 'ci_saved_lists'.tr, actions: [AppRefreshAction(onRefresh: _load)]),
      body: ParentComponent(featureKey: kCertIssueFeature, child: SafeArea(child: body)),
    );
  }
}

class CertListDetailPage extends StatefulWidget {
  const CertListDetailPage({super.key, required this.listId, this.designId, this.langs, this.api, this.initial});

  final int listId;
  final int? designId;
  final List<String>? langs;
  final CertIssueApi? api;
  final RecipientListInfo? initial;

  @override
  State<CertListDetailPage> createState() => _CertListDetailPageState();
}

class _CertListDetailPageState extends State<CertListDetailPage> {
  late final CertIssueApi _api = widget.api ?? CertIssueApi();
  late RecipientListInfo? _list = widget.initial;
  bool _loading = true;
  String? _error;
  bool _busy = false;

  int? get _designId => widget.designId ?? _list?.designId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final l = await _api.list(widget.listId);
      if (!mounted) return;
      setState(() {
        _list = l;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = certIssueErrorText(e);
        _loading = false;
      });
    }
  }

  List<IssueColumn> get _columns {
    final cols = _list?.columns ?? const <IssueColumn>[];
    final out = <IssueColumn>[
      if (!cols.any((c) => c.key == 'student_name'))
        const IssueColumn(key: 'student_name', labelAr: 'اسم الطالب', labelEn: 'Student name'),
      ...cols,
    ];
    if (!out.any((c) => c.key == 'email')) {
      out.add(const IssueColumn(key: 'email', labelAr: 'البريد الإلكتروني', labelEn: 'Email', required: false));
    }
    return out;
  }

  void _openBatch(IssueBatch b) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => CertBatchPage(batchId: b.id, initial: b, api: _api),
      ));

  Future<void> _addPerson() async {
    final canIssue = _designId != null;
    final res = await certEditValues(
      context,
      title: 'ci_add_person'.tr,
      columns: [for (final c in _columns) IssueColumn(key: c.key, labelAr: c.labelAr, labelEn: c.labelEn, required: c.key == 'student_name')],
      confirm: 'ci_add'.tr,
      issueNowLabel: canIssue ? 'ci_issue_now'.tr : null,
      sendEmailLabel: canIssue ? 'ci_send_email'.tr : null,
    );
    if (res == null || !mounted) return;
    final email = res.values['email'] ?? '';
    if (email.isNotEmpty && !certValidEmail(email)) {
      showAppNotice('ci_bad_email'.tr, error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final issue = canIssue && res.issueNow;
      String? photo;
      if (issue) {
        final tpl = await _api.columns(_designId!, orgId: _list?.orgId);
        if (!mounted) return;
        if (tpl.photo == 'required') {
          photo = await certAskOnePhoto(context, _api, res.values['student_name'] ?? '');
          if (!mounted) return;
          if (photo == null) {
            setState(() => _busy = false);
            return;
          }
        }
      }
      final r = await _api.addPerson(widget.listId, certPersonBody(
        values: res.values,
        issue: issue,
        designId: _designId,
        langs: widget.langs,
        sendEmail: res.sendEmail,
        photoUrl: photo,
      ));
      if (!mounted) return;
      showAppNotice(issue ? 'ci_person_issued'.tr : 'ci_person_added'.tr);
      await _load();
      if (r.batch != null && mounted) _openBatch(r.batch!);
    } catch (e) {
      showAppNotice(certIssueErrorText(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _issueAll() async {
    final ok = await appConfirm(context,
        message: 'ci_issue_list_confirm'.tr.replaceAll('{n}', '${_list?.rows.length ?? _list?.count ?? 0}'),
        confirmLabel: 'ci_issue_list'.tr);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final b = await _api.issueList(widget.listId, designId: widget.designId, langs: widget.langs);
      if (mounted) _openBatch(b);
    } catch (e) {
      final x = ApiException.from(e);
      final d = apiErrorDetail(x);
      if ((x.code ?? '${d['code'] ?? ''}') == 'photos_required' && d['missing'] is List && mounted) {
        await _fillPhotos([for (final m in d['missing'] as List) if (m is Map) m.cast<String, dynamic>()]);
      } else {
        showAppNotice(certIssueErrorText(e), error: true);
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  /// The server named who lacks a photo: collect them, write them into the list, then issue again.
  Future<void> _fillPhotos(List<Map<String, dynamic>> missing) async {
    final photos = await certCollectPhotos(context, _api, missing);
    if (photos == null || !mounted) return;
    try {
      final rows = [...?_list?.rows];
      for (final e in photos.entries) {
        if (e.key >= 0 && e.key < rows.length) rows[e.key] = {...rows[e.key], 'photo_url': e.value};
      }
      final l = await _api.updateList(widget.listId, {'rows': rows});
      if (!mounted) return;
      setState(() => _list = l);
      final b = await _api.issueList(widget.listId, designId: widget.designId, langs: widget.langs);
      if (mounted) _openBatch(b);
    } catch (e) {
      showAppNotice(certIssueErrorText(e), error: true);
    }
  }

  Future<void> _rename() async {
    final name = await certAskText(context, title: 'ci_rename'.tr, label: 'ci_list_name'.tr, initial: _list?.name);
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final l = await _api.updateList(widget.listId, {'name': name});
      if (mounted) setState(() => _list = l);
    } catch (e) {
      showAppNotice(certIssueErrorText(e), error: true);
    }
  }

  Future<void> _removePerson(int index) async {
    final rows = [...?_list?.rows]..removeAt(index);
    try {
      final l = await _api.updateList(widget.listId, {'rows': rows});
      if (mounted) setState(() => _list = l);
    } catch (e) {
      showAppNotice(certIssueErrorText(e), error: true);
    }
  }

  Future<void> _delete() async {
    final ok = await appConfirm(context, message: 'ci_delete_list_confirm'.tr, danger: true, confirmLabel: 'delete'.tr);
    if (!ok || !mounted) return;
    try {
      await _api.deleteList(widget.listId);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      showAppNotice(certIssueErrorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = _list;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppHeader(
        title: l?.name ?? 'ci_saved_lists'.tr,
        actions: [
          PopupMenuButton<String>(
            tooltip: 'ci_more'.tr,
            onSelected: (v) {
              if (v == 'rename') _rename();
              if (v == 'delete') _delete();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'rename', child: Text('ci_rename'.tr)),
              PopupMenuItem(value: 'delete', child: Text('delete'.tr)),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: CertListBody(
          list: l,
          columns: _columns,
          loading: _loading,
          error: _error,
          onRetry: _load,
          busy: _busy,
          canIssue: _designId != null,
          onAddPerson: _addPerson,
          onIssueAll: _issueAll,
          onRemove: _removePerson,
        ),
      ),
    );
  }
}

/// One list's page body (plain values: the layout test pumps it).
class CertListBody extends StatelessWidget {
  const CertListBody({
    super.key,
    required this.list,
    required this.columns,
    this.loading = false,
    this.error,
    this.onRetry,
    this.busy = false,
    this.canIssue = true,
    this.onAddPerson,
    this.onIssueAll,
    this.onRemove,
  });

  final RecipientListInfo? list;
  final List<IssueColumn> columns;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final bool busy;
  final bool canIssue;
  final VoidCallback? onAddPerson;
  final VoidCallback? onIssueAll;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = list?.rows ?? const <Map<String, dynamic>>[];
    final header = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text('ci_people_n'.tr.replaceAll('{n}', '${rows.isEmpty ? (list?.count ?? 0) : rows.length}'), style: AppType.meta(context)),
      const SizedBox(height: AppSpace.sm),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        FilledButton.icon(
          onPressed: busy ? null : onAddPerson,
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
          label: Text('ci_add_person'.tr),
        ),
        OutlinedButton.icon(
          onPressed: busy || !canIssue || rows.isEmpty ? null : onIssueAll,
          icon: const Icon(Icons.workspace_premium_outlined, size: 18),
          label: Text('ci_issue_list'.tr),
        ),
      ]),
      if (!canIssue) ...[
        const SizedBox(height: AppSpace.xs),
        AppBanner(icon: Icons.info_outline_rounded, text: 'ci_list_no_design'.tr),
      ],
      const SizedBox(height: AppSpace.md),
    ]);
    final extra = loading && rows.isEmpty ? 1 : (error != null && rows.isEmpty ? 1 : (rows.isEmpty ? 1 : rows.length));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView.builder(
          padding: const EdgeInsets.all(AppSpace.md),
          itemCount: 1 + extra,
          itemBuilder: (context, i) {
            if (i == 0) return header;
            if (loading && rows.isEmpty) return const AppListSkeleton(items: 4, padding: EdgeInsets.zero);
            if (error != null && rows.isEmpty) return IssueErrorBox(message: error!, onRetry: onRetry);
            if (rows.isEmpty) return AppEmpty(icon: Icons.person_outline_rounded, title: 'ci_list_empty_people'.tr);
            final k = i - 1;
            final r = rows[k];
            final values = r['values'] is Map ? (r['values'] as Map).map((a, b) => MapEntry('$a', '${b ?? ''}')) : const <String, String>{};
            final name = values['student_name'] ?? '';
            final others = [
              for (final col in columns)
                if (col.key != 'student_name' && (values[col.key] ?? '').isNotEmpty) '${col.label}: ${values[col.key]}',
              if ((r['email'] ?? '').toString().isNotEmpty) '${r['email']}',
            ];
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: Container(
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.xxs, AppSpace.xs),
                decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
                child: Row(children: [
                  AppAvatar(name: name.isEmpty ? '?' : name, size: 34),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // on the platform: the student's record, when the server lets this issuer open it (D-290)
                      if (r['student_id'] is num && (r['student_id'] as num) > 0)
                        EntityGuardedChip(EntityRef(EntityKind.student, (r['student_id'] as num).toInt(), label: name), maxWidth: 360)
                      else
                        Text(name.isEmpty ? 'ci_no_name'.tr : name, style: AppType.row(context), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (others.isNotEmpty)
                        Text(others.join(' · '), style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (r['student_id'] != null)
                        Text('ci_on_platform'.tr, style: appText(11, w: FontWeight.w500, c: c.success)),
                    ]),
                  ),
                  if (onRemove != null)
                    IconButton(
                      tooltip: 'ci_remove'.tr,
                      onPressed: busy ? null : () => onRemove!(k),
                      icon: Icon(Icons.delete_outline_rounded, size: 20, color: c.textMedium),
                    ),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}
