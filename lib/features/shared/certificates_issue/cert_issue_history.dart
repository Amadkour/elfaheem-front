// lib/features/shared/certificates_issue/cert_issue_history.dart
//
// "Issued history": every batch the person may see (theirs; an organization's for its managers — GET batches),
// newest first. A batch opens its issued certificates with search and an Issued / Revoked filter, the ZIP / PDF
// downloads, and per certificate: view, copy the verification link, revoke (with a reason), re-issue (edit the
// values; the old one is revoked and linked). Wide windows: the list and the open batch side by side.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/api_client.dart';
import '../../../core/api_error_text.dart';
import '../../../core/live/event_wait.dart';
import '../../../design/app_kit.dart';
import '../../../design/app_notice.dart';
import '../../../design/app_tokens.dart';
import '../../teacher/data_lab/data_lab_saver_io.dart' if (dart.library.html) '../../teacher/data_lab/data_lab_saver_web.dart' as saver;
import '../../../utils/widget/parent_component.dart';
import '../../auth/auth_provider.dart';
import 'cert_issue_actions.dart';
import 'cert_issue_api.dart';
import 'cert_issue_logic.dart';
import 'cert_issue_photos.dart';
import 'cert_issue_parts.dart';
import 'cert_issue_word.dart';

int? _meId(BuildContext context) {
  try {
    return Provider.of<MyAuthProvider>(context, listen: false).currentUser?.id;
  } catch (_) {
    return null;
  }
}

class CertIssueHistoryPage extends StatefulWidget {
  const CertIssueHistoryPage({super.key, this.orgId, this.api});

  final int? orgId;
  final CertIssueApi? api;

  @override
  State<CertIssueHistoryPage> createState() => _CertIssueHistoryPageState();
}

class _CertIssueHistoryPageState extends State<CertIssueHistoryPage> {
  late final CertIssueApi _api = widget.api ?? CertIssueApi();

  final List<IssueBatch> _items = [];
  int _total = 0;
  int _page = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int? _openId;

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
      final r = await _api.batches(orgId: widget.orgId, page: 1);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(r.items);
        _total = r.total;
        _page = 1;
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

  Future<void> _more() async {
    if (_loadingMore || _items.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final r = await _api.batches(orgId: widget.orgId, page: _page + 1);
      if (!mounted) return;
      setState(() {
        final seen = {for (final b in _items) b.id};
        _items.addAll(r.items.where((b) => seen.add(b.id)));
        _total = r.total;
        _page += 1;
      });
    } catch (e) {
      showAppNotice(certIssueErrorText(e), error: true);
    }
    if (mounted) setState(() => _loadingMore = false);
  }

  void _updated(IssueBatch b) {
    final i = _items.indexWhere((x) => x.id == b.id);
    if (i >= 0 && mounted) setState(() => _items[i] = b);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppHeader(title: 'ci_history'.tr, actions: [AppRefreshAction(onRefresh: _load)]),
      body: ParentComponent(
        featureKey: kCertIssueFeature,
        child: SafeArea(
          child: LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 960;
            final list = CertBatchList(
              items: _items,
              total: _total,
              loading: _loading,
              loadingMore: _loadingMore,
              error: _error,
              onRetry: _load,
              onMore: _more,
              onRefresh: _load,
              selectedId: wide ? _openId : null,
              meId: _meId(context),
              onOpen: (b) {
                if (wide) {
                  setState(() => _openId = b.id);
                } else {
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => CertBatchPage(batchId: b.id, initial: b, api: _api, onChanged: _updated),
                  ));
                }
              },
            );
            if (!wide) return list;
            final open = _items.where((b) => b.id == _openId).firstOrNull;
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 400, child: list),
              VerticalDivider(width: 1, color: c.divider),
              Expanded(
                child: open == null
                    ? Center(child: AppEmpty(icon: Icons.touch_app_outlined, title: 'ci_pick_batch'.tr))
                    : CertBatchView(key: ValueKey(open.id), batchId: open.id, initial: open, api: _api, onChanged: _updated),
              ),
            ]);
          }),
        ),
      ),
    );
  }
}

/// The history list (plain values: the layout test pumps it).
class CertBatchList extends StatelessWidget {
  const CertBatchList({
    super.key,
    required this.items,
    required this.onOpen,
    this.total = 0,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.onRetry,
    this.onMore,
    this.onRefresh,
    this.selectedId,
    this.meId,
  });

  final List<IssueBatch> items;
  final ValueChanged<IssueBatch> onOpen;
  final int total;
  final bool loading;
  final bool loadingMore;
  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onMore;
  final Future<void> Function()? onRefresh;
  final int? selectedId;
  final int? meId;

  @override
  Widget build(BuildContext context) {
    if (loading && items.isEmpty) return const AppListSkeleton();
    if (error != null && items.isEmpty) {
      return Padding(padding: AppSpace.card, child: Align(alignment: Alignment.topCenter, child: IssueErrorBox(message: error!, onRetry: onRetry)));
    }
    if (items.isEmpty) {
      return AppEmpty(icon: Icons.workspace_premium_outlined, title: 'ci_history_empty'.tr, message: 'ci_history_empty_sub'.tr);
    }
    final more = items.length < total;
    final view = ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpace.md),
      itemCount: items.length + (more ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: AppSpace.xs),
      itemBuilder: (context, i) {
        if (i == items.length) {
          return Center(
            child: TextButton.icon(
              onPressed: loadingMore ? null : onMore,
              icon: loadingMore
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.expand_more_rounded),
              label: Text('ci_load_more'.tr),
            ),
          );
        }
        final b = items[i];
        return IssueBatchTile(
          batch: b,
          selected: b.id == selectedId,
          byYou: meId != null && b.createdBy == meId,
          onTap: () => onOpen(b),
        );
      },
    );
    return onRefresh == null ? view : AppRefresh(onRefresh: onRefresh!, child: view);
  }
}

/// One batch on its own page (phones).
class CertBatchPage extends StatelessWidget {
  const CertBatchPage({super.key, required this.batchId, this.initial, this.api, this.onChanged});

  final int batchId;
  final IssueBatch? initial;
  final CertIssueApi? api;
  final ValueChanged<IssueBatch>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppHeader(title: initial?.title ?? 'ci_batch'.tr),
      body: SafeArea(child: CertBatchView(batchId: batchId, initial: initial, api: api, onChanged: onChanged)),
    );
  }
}

/// A batch: its progress / downloads and its issued certificates.
class CertBatchView extends StatefulWidget {
  const CertBatchView({super.key, required this.batchId, this.initial, this.api, this.onChanged});

  final int batchId;
  final IssueBatch? initial;
  final CertIssueApi? api;
  final ValueChanged<IssueBatch>? onChanged;

  @override
  State<CertBatchView> createState() => _CertBatchViewState();
}

class _CertBatchViewState extends State<CertBatchView> {
  late final CertIssueApi _api = widget.api ?? CertIssueApi();
  late IssueBatch? _batch = widget.initial;
  EventOrPoll? _watch;
  String? _downloading;

  final _q = TextEditingController();
  Timer? _debounce;
  String? _status; // null · issued · revoked
  final List<IssuedCert> _items = [];
  int _total = 0;
  int _page = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _refreshBatch();
    _loadItems();
  }

  @override
  void dispose() {
    _watch?.dispose();
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _refreshBatch() async {
    try {
      final b = await _api.batch(widget.batchId);
      if (!mounted) return;
      final wasRunning = _batch != null && !_batch!.finished;
      setState(() => _batch = b);
      widget.onChanged?.call(b);
      if (!b.finished) {
        _watch ??= EventOrPoll(
          kind: 'certificate_batch',
          id: '${b.id}',
          every: const Duration(seconds: 3),
          fallbackEvery: const Duration(seconds: 4),
          poll: _refreshBatch,
        )..start();
      } else {
        _watch?.stop();
        if (wasRunning) _loadItems();
      }
    } catch (e) {
      if (mounted && _batch == null) setState(() => _error = certIssueErrorText(e));
    }
  }

  Future<void> _loadItems() async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.items(widget.batchId, status: _status, q: _q.text, page: 1);
      if (!mounted || gen != _gen) return;
      setState(() {
        _items
          ..clear()
          ..addAll(r.items);
        _total = r.total;
        _page = 1;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = certIssueErrorText(e);
        _loading = false;
      });
    }
  }

  Future<void> _more() async {
    if (_loadingMore || _items.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final r = await _api.items(widget.batchId, status: _status, q: _q.text, page: _page + 1);
      if (!mounted) return;
      setState(() {
        final seen = {for (final x in _items) x.id};
        _items.addAll(r.items.where((x) => seen.add(x.id)));
        _total = r.total;
        _page += 1;
      });
    } catch (e) {
      showAppNotice(certIssueErrorText(e), error: true);
    }
    if (mounted) setState(() => _loadingMore = false);
  }

  void _onQuery(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _loadItems);
  }

  Future<void> _download(String kind) async {
    setState(() => _downloading = kind);
    try {
      await certOpenUrl(await _api.download(widget.batchId, kind));
    } catch (e) {
      showAppNotice(certIssueErrorText(e), error: true);
    }
    if (mounted) setState(() => _downloading = null);
  }

  /// The certificate as Word file(s), one per issued language, saved like every export.
  Future<void> _word(IssuedCert cert) async {
    final b = _batch;
    if (b == null || b.designId == null) return;
    setState(() => _downloading = 'word');
    try {
      for (final (name, bytes) in await issuedCertificateWordFiles(cert, b)) {
        await saver.dlSaveBytes(bytes, name, AppExportFormat.docx.mime);
      }
      showAppNotice('ci_word_done'.tr);
    } catch (e) {
      showAppNotice(certIssueErrorText(e), error: true);
    }
    if (mounted) setState(() => _downloading = null);
  }

  Future<void> _revoke(IssuedCert cert) async {
    final reason = await certAskText(context,
        title: 'ci_revoke_title'.tr,
        label: 'ci_reason'.tr,
        message: 'ci_revoke_sub'.tr.replaceAll('{name}', cert.recipientName),
        confirm: 'ci_revoke'.tr,
        danger: true);
    if (reason == null || reason.isEmpty || !mounted) return;
    try {
      final r = await _api.revoke(cert.id, reason);
      if (!mounted) return;
      setState(() {
        final i = _items.indexWhere((x) => x.id == cert.id);
        if (i >= 0) _items[i] = r;
      });
      showAppNotice('ci_revoked_done'.tr);
    } catch (e) {
      showAppNotice(certIssueErrorText(e), error: true);
    }
  }

  Future<void> _reissue(IssuedCert cert) async {
    final keys = <String>{'student_name', ...cert.values.keys.where((k) => k != 'email')};
    final columns = [
      for (final k in keys)
        IssueColumn(key: k, labelAr: _label(k, 'ar'), labelEn: _label(k, 'en'), required: k == 'student_name'),
      IssueColumn(key: 'email', labelAr: 'البريد الإلكتروني', labelEn: 'Email', required: false),
    ];
    final before = {...cert.values, 'student_name': cert.values['student_name'] ?? cert.recipientName};
    final res = await certEditValues(
      context,
      title: 'ci_reissue_title'.tr,
      columns: columns,
      initial: {...before, 'email': cert.recipientEmail ?? ''},
      confirm: 'ci_reissue'.tr,
      sendEmailLabel: 'ci_reissue_email'.tr,
      askReason: true,
    );
    if (res == null || !mounted) return;
    final email = res.values['email'];
    if ((email ?? '').isNotEmpty && !certValidEmail(email!)) {
      showAppNotice('ci_bad_email'.tr, error: true);
      return;
    }
    try {
      await _api.reissue(cert.id, certReissueBody(
        before: before,
        after: res.values,
        email: email,
        emailBefore: cert.recipientEmail,
        sendEmail: res.sendEmail,
        reason: res.reason,
      ));
      showAppNotice('ci_reissued_done'.tr);
      await _loadItems();
    } catch (e) {
      final x = ApiException.from(e);
      if ((x.code ?? '${apiErrorDetail(x)['code'] ?? ''}') == 'photos_required' && mounted) {
        final url = await certAskOnePhoto(context, _api, cert.recipientName);
        if (url == null || !mounted) return;
        try {
          await _api.reissue(cert.id, certReissueBody(before: before, after: res.values, email: email,
              emailBefore: cert.recipientEmail, sendEmail: res.sendEmail, reason: res.reason, photoUrl: url));
          showAppNotice('ci_reissued_done'.tr);
          await _loadItems();
        } catch (e2) {
          showAppNotice(certIssueErrorText(e2), error: true);
        }
        return;
      }
      showAppNotice(certIssueErrorText(e), error: true);
    }
  }

  static String _label(String key, String lang) {
    const ar = {'student_name': 'اسم الطالب', 'course_name': 'اسم الدورة', 'grade': 'التقدير', 'score': 'الدرجة', 'hours': 'عدد الساعات'};
    const en = {'student_name': 'Student name', 'course_name': 'Course name', 'grade': 'Grade', 'score': 'Score', 'hours': 'Hours'};
    final m = lang == 'ar' ? ar : en;
    final s = key.replaceAll('_', ' ');
    return m[key] ?? (s.isEmpty ? key : s[0].toUpperCase() + s.substring(1));
  }

  @override
  Widget build(BuildContext context) {
    final b = _batch;
    return CertBatchBody(
      batch: b,
      downloading: _downloading,
      onZip: () => _download('zip'),
      onPdf: () => _download('pdf'),
      query: _q,
      onQuery: _onQuery,
      status: _status,
      onStatus: (s) {
        setState(() => _status = s);
        _loadItems();
      },
      items: _items,
      total: _total,
      loading: _loading,
      loadingMore: _loadingMore,
      error: _error,
      onRetry: _loadItems,
      onMore: _more,
      onView: (x) => certShowImage(context, x),
      onCopyLink: (x) => certCopy(x.verifyUrl),
      onRevoke: _revoke,
      onReissue: _reissue,
      onWord: _batch?.designId == null || _downloading != null ? null : _word,
    );
  }
}

/// A batch's page body (plain values: the layout test pumps it).
class CertBatchBody extends StatelessWidget {
  const CertBatchBody({
    super.key,
    required this.batch,
    required this.query,
    required this.onQuery,
    required this.status,
    required this.onStatus,
    required this.items,
    this.total = 0,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.onRetry,
    this.onMore,
    this.downloading,
    this.onZip,
    this.onPdf,
    this.onView,
    this.onCopyLink,
    this.onRevoke,
    this.onReissue,
    this.onWord,
  });

  final IssueBatch? batch;
  final TextEditingController query;
  final ValueChanged<String> onQuery;
  final String? status;
  final ValueChanged<String?> onStatus;
  final List<IssuedCert> items;
  final int total;
  final bool loading;
  final bool loadingMore;
  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onMore;
  final String? downloading;
  final VoidCallback? onZip;
  final VoidCallback? onPdf;
  final ValueChanged<IssuedCert>? onView;
  final ValueChanged<IssuedCert>? onCopyLink;
  final ValueChanged<IssuedCert>? onRevoke;
  final ValueChanged<IssuedCert>? onReissue;
  final ValueChanged<IssuedCert>? onWord;

  @override
  Widget build(BuildContext context) {
    final more = items.length < total;
    final header = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (batch != null) ...[
        _BatchFacts(batch: batch!),
        const SizedBox(height: AppSpace.sm),
        IssueBatchProgressCard(batch: batch!, downloading: downloading, onZip: onZip, onPdf: onPdf),
        const SizedBox(height: AppSpace.md),
      ],
      Text('ci_issued_title'.tr, style: AppType.section(context)),
      const SizedBox(height: AppSpace.xs),
      TextField(
        controller: query,
        onChanged: onQuery,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: 'ci_issued_search'.tr, isDense: true),
      ),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppChoiceChip(label: 'ci_filter_all'.tr, selected: status == null, onTap: () => onStatus(null)),
        AppChoiceChip(label: 'ci_valid'.tr, selected: status == 'issued', onTap: () => onStatus('issued')),
        AppChoiceChip(label: 'ci_revoked'.tr, selected: status == 'revoked', onTap: () => onStatus('revoked')),
      ]),
      const SizedBox(height: AppSpace.sm),
    ]);
    final extra = loading && items.isEmpty
        ? 1
        : (error != null && items.isEmpty ? 1 : (items.isEmpty ? 1 : items.length + (more ? 1 : 0)));
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpace.md),
      itemCount: 1 + extra,
      itemBuilder: (context, i) {
        if (i == 0) return header;
        if (loading && items.isEmpty) return const AppListSkeleton(items: 4, padding: EdgeInsets.zero);
        if (error != null && items.isEmpty) return IssueErrorBox(message: error!, onRetry: onRetry);
        if (items.isEmpty) {
          return AppEmpty(
            icon: Icons.inbox_outlined,
            title: batch != null && !batch!.finished ? 'ci_issued_wait'.tr : 'ci_issued_empty'.tr,
          );
        }
        final k = i - 1;
        if (k == items.length) {
          return Center(
            child: TextButton.icon(
              onPressed: loadingMore ? null : onMore,
              icon: loadingMore
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.expand_more_rounded),
              label: Text('ci_load_more'.tr),
            ),
          );
        }
        final x = items[k];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: IssuedCertTile(
            cert: x,
            onView: x.imageUrl == null || onView == null ? null : () => onView!(x),
            onCopyLink: x.verifyUrl == null || onCopyLink == null ? null : () => onCopyLink!(x),
            onRevoke: onRevoke == null ? null : () => onRevoke!(x),
            onReissue: onReissue == null ? null : () => onReissue!(x),
            onWord: onWord == null ? null : () => onWord!(x),
          ),
        );
      },
    );
  }
}

class _BatchFacts extends StatelessWidget {
  const _BatchFacts({required this.batch});
  final IssueBatch batch;

  @override
  Widget build(BuildContext context) {
    final langs = batch.langs.map(certLangLabel).join(' · ');
    return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
      AppBadgePill(certModeLabel(batch.mode), icon: batch.isCourse ? Icons.school_rounded : Icons.workspace_premium_rounded),
      if (batch.createdAt != null) AppBadgePill(AppTime.dateTime(batch.createdAt!), icon: Icons.event_outlined),
      if (langs.isNotEmpty) AppBadgePill(langs, icon: Icons.translate_rounded),
      if (batch.email) AppBadgePill('ci_by_email'.tr, icon: Icons.mail_outline_rounded),
    ]);
  }
}
