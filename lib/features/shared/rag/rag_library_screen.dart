// The documents library manager screen (Phase 7/8): the documents the assistant answers from, with their status,
// upload (title · scope · optional "replaces"), archive, reindex, download, the organization's answer settings and
// the unhelpful-answers list. Shown to library managers only (the chat screen offers the entry when the list call
// answers `manager: true`). [RagDocumentCard], [RagSettingsForm], [RagFeedbackView], [RagUploadForm] and
// [RagQuotaBar] (how full the library is, when the server reports it) are presentational and tested under the
// layout harness.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import '../../admin/admin_common.dart' show asInt, asMap, asStr, shortDateTime, t;
import '../../admin/admin_money_p8.dart' show draftErrorText, p8SaveBytes;
import '../exam_engine/exam_engine_api.dart' show EngineResult;
import '../../admin/admin_feature_guide.dart' show AdminFeatureGuidePage;
import 'rag_chat_screen.dart' show RagChatScreen;
import 'rag_library.dart';
import 'rag_qa_admin.dart' show RagQaAdminPage;

Color ragStatusColor(BuildContext context, String s) {
  final c = context.colors;
  return switch (s) {
    'ready' => c.success,
    'failed' => c.danger,
    'queued' || 'processing' => c.warning,
    _ => c.textMedium,
  };
}

class RagLibraryScreen extends StatefulWidget {
  const RagLibraryScreen({super.key, this.orgId, this.courseId, this.app = false, this.title, this.api});
  final int? orgId;
  final int? courseId;

  /// the app assistant's documents (platform admins)
  final bool app;
  final String? title;
  final RagLibraryApi? api;

  @override
  State<RagLibraryScreen> createState() => _RagLibraryScreenState();
}

class _RagLibraryScreenState extends State<RagLibraryScreen> {
  late final RagLibraryApi _api = widget.api ?? RagLibraryApi();
  RagLibrary? _lib;
  RagLibrary? _active; // the last list without the archived filter: the app library's overview counts it
  String _filter = '';
  bool _loading = true;
  String? _error;
  EventOrPoll? _poll;
  final Set<int> _working = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final r = await _api.list(orgId: widget.orgId, courseId: widget.courseId, status: _filter == 'archived' ? 'archived' : null, app: widget.app);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _lib = RagLibrary.fromJson(r.map);
        if (_filter != 'archived') _active = _lib;
        _error = null;
      } else if (!silent) {
        _error = r.unavailable ? t('المكتبة غير متاحة بعد على هذا الخادم', 'The library is not available on this server yet') : ragResultText(r);
      }
    });
    // a document being read: `job_updated{kind: rag_ingest}` reloads at once; the poll is the fallback (5 s, 20 s
    // while the live stream is connected)
    if (_lib?.hasBusy == true) {
      (_poll ??= EventOrPoll(
              match: (e) => e.kind == 'rag_ingest' || e.kind == 'ingest',
              every: const Duration(seconds: 5),
              fallbackEvery: const Duration(seconds: 20),
              poll: () => _load(silent: true)))
          .start();
    } else {
      _poll?.stop();
    }
  }

  Future<void> _run(RagDocument d, Future<EngineResult> Function() call, {String? done}) async {
    setState(() => _working.add(d.id));
    final r = await call();
    if (!mounted) return;
    setState(() => _working.remove(d.id));
    if (r.ok) {
      if (done != null) appToast(done);
      _load(silent: true);
    } else {
      appToast(ragResultText(r), error: true);
    }
  }

  Future<void> _archive(RagDocument d) async {
    if (!await appConfirm(context,
        message: t('أرشفة «${d.displayTitle}»؟ يخرج من فهرس البحث فوراً.', 'Archive "${d.displayTitle}"? It leaves the search index at once.'), danger: true)) {
      return;
    }
    await _run(d, () => _api.archive(d.id), done: t('تمت الأرشفة', 'Archived'));
  }

  Future<void> _download(RagDocument d) async {
    setState(() => _working.add(d.id));
    try {
      final bytes = await _api.file(d.id);
      await p8SaveBytes(bytes, d.filename.isEmpty ? 'document-${d.id}' : d.filename);
    } on ApiException catch (e) {
      appToast(ragLibraryCodeText(e.code, e.message), error: true);
    } catch (e) {
      appToast('$e', error: true);
    }
    if (mounted) setState(() => _working.remove(d.id));
  }

  Future<void> _upload({RagDocument? replaces}) async {
    final done = await showAppSheet<bool>(
        context,
        (_) => replaces == null
            ? RagBatchUploadSheet(api: _api, orgId: widget.orgId, courseId: widget.courseId, app: widget.app, library: _lib)
            : RagUploadSheet(api: _api, orgId: widget.orgId, courseId: widget.courseId, library: _lib, replaces: replaces));
    if (done == true) _load(silent: true);
  }

  Future<void> _syncApp() async {
    final r = await _api.syncApp();
    if (!mounted) return;
    if (!r.ok) return appToast(ragResultText(r), error: true);
    final o = <String>[for (final k in ['added', 'updated', 'unchanged']) for (var i = 0; i < asInt(r.map[k]); i++) k];
    appToast(o.isEmpty ? t('لا جديد في صفحات التطبيق', 'Nothing new in the app\'s pages') : ragOutcomeSummary(o));
    _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lib = _lib;
    final shown = lib?.filtered(_filter == 'archived' ? '' : _filter) ?? const <RagDocument>[];
    final counts = lib?.counts() ?? const <String, int>{};
    return BasePage(
      key: const ValueKey('rag.library'),
      useWebCard: true,
      maxWith: 1000,
      appBar: ScreenAppBar(title: widget.title ?? (widget.app ? t('مستندات التطبيق', 'App documents') : t('مكتبة المستندات', 'Documents library')), actions: [
        if (widget.app && lib?.manager == true)
          IconButton(tooltip: t('تحديث من صفحات التطبيق', 'Update from the app\'s pages'), icon: const Icon(Icons.sync_rounded), onPressed: _syncApp),
        // curated Q&A (Track E.2): the app's pairs for platform admins, the organization's for its library managers
        if (lib?.manager == true && (widget.app || (widget.orgId != null && widget.courseId == null)))
          ParentComponent(
            featureKey: 'rag.qa_admin',
            child: IconButton(
                tooltip: t('الإجابات المعتمدة', 'Curated Q&A'),
                icon: const Icon(Icons.verified_outlined),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RagQaAdminPage(scope: widget.app ? 'app' : 'org', orgId: widget.app ? null : widget.orgId)))),
          ),
        if (widget.orgId != null)
          IconButton(
              tooltip: t('الإجابات غير المفيدة', 'Unhelpful answers'),
              icon: const Icon(Icons.thumb_down_alt_outlined),
              onPressed: () => showAppSheet<void>(context, (_) => RagFeedbackSheet(api: _api, orgId: widget.orgId!))),
        if (widget.orgId != null)
          IconButton(
              tooltip: t('إعدادات الإجابة', 'Answer settings'),
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => showAppSheet<void>(context, (_) => RagSettingsSheet(api: _api, orgId: widget.orgId!))),
        IconButton(tooltip: t('تحديث', 'Refresh'), icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        if (widget.orgId != null) const ContextExitButton(),
      ]),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              AppChoiceChip(label: '${t('الكل', 'All')} (${lib?.items.length ?? 0})', selected: _filter.isEmpty, onTap: () => setState(() => _filter = '')),
              for (final s in ['ready', 'processing', 'queued', 'failed'])
                if ((counts[s] ?? 0) > 0)
                  AppChoiceChip(label: '${ragStatusText(s)} (${counts[s]})', selected: _filter == s, onTap: () => setState(() => _filter = s)),
              AppChoiceChip(
                  label: ragStatusText('archived'),
                  selected: _filter == 'archived',
                  onTap: () {
                    setState(() => _filter = 'archived');
                    _load();
                  }),
            ]),
          ),
        ),
        if (lib?.quota != null) Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 4), child: RagQuotaBar(quota: lib!.quota!)),
        Expanded(
          child: _loading
              ? const AppListSkeleton()
              : _error != null
                  ? AppEmpty(icon: Icons.error_outline_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 90), children: [
                      // the platform admins' dashboard of the app assistant (the app library)
                      if (widget.app && lib?.manager == true && _active != null) ...[
                        RagLibraryOverview(
                            library: _active!,
                            onUpload: _upload,
                            onSync: _syncApp,
                            onGuide: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminFeatureGuidePage())),
                            onTry: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RagChatScreen(app: true)))),
                        const SizedBox(height: 14),
                      ],
                      if (shown.isEmpty)
                        AppEmpty(icon: Icons.folder_open_rounded, title: t('لا مستندات', 'No documents'), message: t('ارفع لائحة أو دليلاً ليجيب المساعد منه.', 'Upload a regulation or guide for the assistant to answer from.'))
                      else
                        for (final d in shown)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: RagDocumentCard(
                              doc: d,
                              working: _working.contains(d.id),
                              manager: lib?.manager == true,
                              onDownload: () => _download(d),
                              onReindex: d.canReindex ? () => _run(d, () => _api.reindex(d.id), done: t('بدأت إعادة الفهرسة', 'Reindexing started')) : null,
                              onArchive: d.archived ? null : () => _archive(d),
                              onNewVersion: d.archived ? null : () => _upload(replaces: d),
                            ),
                          ),
                    ]),
        ),
      ]),
      floatingActionButton: lib?.manager == true
          ? FloatingActionButton.extended(
              backgroundColor: c.primary,
              onPressed: _upload,
              icon: const Icon(Icons.upload_file_rounded, color: Colors.white),
              label: Text(t('رفع مستند', 'Upload'), style: const TextStyle(color: Colors.white)))
          : null,
    );
  }
}


/// The app assistant's dashboard header (platform admins, app library): what the assistant answers from — ready,
/// being processed, failed — how much is indexed, and what to do: add documents, re-read the app's own pages, manage
/// the app features guide (what the assistant knows about each feature, per role), try the assistant.
class RagLibraryOverview extends StatelessWidget {
  const RagLibraryOverview({super.key, required this.library, this.onUpload, this.onSync, this.onGuide, this.onTry});
  final RagLibrary library;
  final VoidCallback? onUpload, onSync, onGuide, onTry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final counts = library.counts();
    final docs = library.items;
    final size = docs.fold<int>(0, (a, d) => a + d.size);
    final chunks = docs.fold<int>(0, (a, d) => a + d.chunks);
    final busy = (counts['queued'] ?? 0) + (counts['processing'] ?? 0);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppBanner(
          icon: Icons.smart_toy_rounded,
          color: c.primary,
          text: t('يجيب مساعد التطبيق كل المستخدمين من هذه المستندات، ومن الشروط و«عن التطبيق» و«دليل ميزات التطبيق» (تُقرأ تلقائياً). عدّل الدليل لتحدد ما يشرحه المساعد عن كل ميزة ولمن.',
              'The app assistant answers every user from these documents and from the terms, About and "App features guide" pages (read automatically). Edit the guide to decide what it explains about each feature, and for whom.')),
      const SizedBox(height: 12),
      AppGrid(padding: EdgeInsets.zero, minTile: 150, children: [
        AppStatTile(icon: Icons.task_alt_rounded, label: ragStatusText('ready'), value: counts['ready'] ?? 0, color: c.success),
        AppStatTile(icon: Icons.hourglass_top_rounded, label: ragStatusText('processing'), value: busy, color: c.warning),
        AppStatTile(icon: Icons.error_outline_rounded, label: ragStatusText('failed'), value: counts['failed'] ?? 0, color: c.danger),
        AppStatTile(icon: Icons.data_usage_rounded, label: t('الحجم', 'Size'), value: ragSizeText(size)),
        AppStatTile(icon: Icons.segment_rounded, label: t('مقاطع مفهرسة', 'Indexed passages'), value: chunks),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (onUpload != null) AppPill(icon: Icons.upload_file_rounded, label: t('رفع مستندات', 'Upload documents'), onTap: onUpload!),
        if (onSync != null) AppPill(icon: Icons.sync_rounded, label: t('تحديث من صفحات التطبيق', 'Update from the app\'s pages'), onTap: onSync!),
        if (onGuide != null) AppPill(icon: Icons.menu_book_rounded, label: t('دليل ميزات التطبيق', 'App features guide'), onTap: onGuide!),
        if (onTry != null) AppPill(icon: Icons.question_answer_outlined, label: t('جرّب المساعد', 'Try the assistant'), onTap: onTry!),
      ]),
    ]);
  }
}

/// How full the organization's library is: "12 / 200 documents · 40.0 MB / 500.0 MB", with a bar when limited.
class RagQuotaBar extends StatelessWidget {
  const RagQuotaBar({super.key, required this.quota});
  final RagQuota quota;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = quota.full ? c.danger : (quota.nearlyFull ? c.warning : c.primary);
    final fill = quota.fill;
    return Semantics(
      label: '${t('حصة المكتبة', 'Library quota')}: ${quota.docsText}, ${quota.bytesText}',
      child: ExcludeSemantics(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(Icons.inventory_2_outlined, size: 18, color: col),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(spacing: 10, runSpacing: 2, children: [
                Text(quota.docsText, style: appText(12.5, w: FontWeight.w700, c: c.textDark)),
                Text(quota.bytesText, style: appText(12.5, c: c.textMedium)),
              ]),
            ),
          ]),
          if (fill != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: fill, minHeight: 5, color: col, backgroundColor: col.withValues(alpha: 0.15)),
              ),
            ),
          if (quota.full)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(t('المكتبة ممتلئة — أرشف مستندات لتحرير مساحة', 'The library is full — archive documents to make room'),
                  style: appText(11.5, w: FontWeight.w600, c: c.danger)),
            ),
        ]),
      ),
    );
  }
}

/// One document: title, status chip, meta and the manager's actions.
class RagDocumentCard extends StatelessWidget {
  const RagDocumentCard(
      {super.key, required this.doc, this.manager = false, this.working = false, this.onDownload, this.onReindex, this.onArchive, this.onNewVersion});
  final RagDocument doc;
  final bool manager, working;
  final VoidCallback? onDownload, onReindex, onArchive, onNewVersion;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = ragStatusColor(context, doc.status);
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.description_outlined, color: c.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(doc.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14.5, w: FontWeight.w800, c: c.textDark))),
          const SizedBox(width: 8),
          AppBadgePill(ragStatusText(doc.status), color: col),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          AppBadgePill(ragScopeText(doc.scope), color: c.textMedium),
          AppBadgePill('v${doc.version}', color: c.textMedium),
          if (doc.pages != null) AppBadgePill('${doc.pages} ${t('صفحة', 'pages')}', color: c.textMedium),
          if (doc.chunks > 0) AppBadgePill('${doc.chunks} ${t('مقطع', 'chunks')}', color: c.textMedium),
          if (doc.size > 0) AppBadgePill(ragSizeText(doc.size), color: c.textMedium),
          if (doc.ocrPages > 0) AppBadgePill('OCR ${doc.ocrPages}', color: c.textMedium),
        ]),
        if (doc.createdAt != null)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(shortDateTime(doc.createdAt), style: appText(11.5, c: c.textLight))),
        if (doc.status == 'failed' && (doc.error ?? '').isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 8), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: doc.error!)),
        if (doc.busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator(minHeight: 3)),
        const SizedBox(height: 6),
        Wrap(spacing: 4, runSpacing: 0, children: [
          TextButton.icon(onPressed: working ? null : onDownload, icon: const Icon(Icons.download_rounded, size: 18), label: Text(t('تنزيل', 'Download'))),
          if (manager && onNewVersion != null)
            TextButton.icon(onPressed: working ? null : onNewVersion, icon: const Icon(Icons.library_add_rounded, size: 18), label: Text(t('نسخة جديدة', 'New version'))),
          if (manager && onReindex != null)
            TextButton.icon(onPressed: working ? null : onReindex, icon: const Icon(Icons.refresh_rounded, size: 18), label: Text(t('إعادة فهرسة', 'Reindex'))),
          if (manager && onArchive != null)
            TextButton.icon(
                onPressed: working ? null : onArchive,
                style: TextButton.styleFrom(foregroundColor: c.danger),
                icon: const Icon(Icons.archive_outlined, size: 18),
                label: Text(t('أرشفة', 'Archive'))),
        ]),
      ]),
    );
  }
}

// ── upload ────────────────────────────────────────────────────────────────────────────────────────────────────

class RagUploadSheet extends StatefulWidget {
  const RagUploadSheet({super.key, required this.api, this.orgId, this.courseId, this.library, this.replaces});
  final RagLibraryApi api;
  final int? orgId;
  final int? courseId;
  final RagLibrary? library;
  final RagDocument? replaces;

  @override
  State<RagUploadSheet> createState() => _RagUploadSheetState();
}

class _RagUploadSheetState extends State<RagUploadSheet> {
  bool _busy = false;
  String? _err;

  Future<void> _submit(RagUploadDraft d) async {
    setState(() {
      _busy = true;
      _err = null;
    });
    final r = await widget.api.upload(d, orgId: widget.orgId, courseId: widget.courseId);
    if (!mounted) return;
    if (r.ok) {
      appToast(t('رُفع المستند وسيُفهرس قريباً', 'Uploaded — it will be indexed shortly'));
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _err = ragResultText(r);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader(widget.replaces == null ? t('رفع مستند', 'Upload a document') : t('نسخة جديدة من المستند', 'New version of the document')),
        RagUploadForm(
            orgId: widget.orgId, courseId: widget.courseId, library: widget.library, replaces: widget.replaces, busy: _busy, error: _err, onSubmit: _submit),
      ]),
    );
  }
}

/// Title · scope · (course) · replaces · file. Presentational: [onSubmit] gets a validated draft.
class RagUploadForm extends StatefulWidget {
  const RagUploadForm({super.key, required this.onSubmit, this.orgId, this.courseId, this.library, this.replaces, this.busy = false, this.error, this.pickFile});
  final void Function(RagUploadDraft draft) onSubmit;
  final int? orgId;
  final int? courseId;
  final RagLibrary? library;
  final RagDocument? replaces;
  final bool busy;
  final String? error;

  /// test hook / platform seam: returns (name, bytes) or null
  final Future<(String, Uint8List)?> Function()? pickFile;

  @override
  State<RagUploadForm> createState() => _RagUploadFormState();
}

class _RagUploadFormState extends State<RagUploadForm> {
  late final RagUploadDraft _d = RagUploadDraft(
      title: widget.replaces?.title ?? '',
      scope: widget.replaces?.scope ?? (widget.orgId == null ? 'course' : 'org'),
      replaces: widget.replaces?.id);
  late final _title = TextEditingController(text: _d.title);
  final _course = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _title.dispose();
    _course.dispose();
    super.dispose();
  }

  Future<(String, Uint8List)?> _pick() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ragUploadExtensions);
    if (f == null) return null;
    return (f.name, await f.readAsBytes());
  }

  Future<void> _choose() async {
    final got = await (widget.pickFile ?? _pick)();
    if (got == null || !mounted) return;
    setState(() {
      _d.fileName = got.$1;
      _d.fileBytes = got.$2;
      if (_title.text.trim().isEmpty) {
        final dot = got.$1.lastIndexOf('.');
        _title.text = dot > 0 ? got.$1.substring(0, dot) : got.$1;
      }
    });
  }

  void _submit() {
    _d
      ..title = _title.text
      ..courseId = _course.text;
    final e = _d.validate(orgId: widget.orgId, fixedCourseId: widget.courseId);
    setState(() => _err = e == null ? null : _codeText(e));
    if (e == null) widget.onSubmit(_d);
  }

  static String _codeText(String e) => switch (e) {
        'file_required' || 'course_required' => draftErrorText(e),
        _ => ragLibraryCodeText(e, draftErrorText(e)),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scopes = widget.replaces?.scope == 'app' ? const ['app'] : (widget.orgId == null ? const ['course'] : ragScopes);
    final replaceable = widget.library?.replaceable(_d.scope, courseId: widget.courseId ?? _d.courseIdValue) ?? const <RagDocument>[];
    final locked = widget.replaces != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppField(controller: _title, label: t('العنوان', 'Title')),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in scopes)
          AppChoiceChip(
              label: ragScopeText(s),
              selected: _d.scope == s,
              onTap: locked ? () {} : () => setState(() {
                    _d.scope = s;
                    _d.replaces = null;
                  })),
      ]),
      const SizedBox(height: 12),
      if (_d.scope == 'course' && widget.courseId == null)
        AppField(controller: _course, label: t('رقم المقرر', 'Course id'), keyboard: TextInputType.number),
      if (!locked && replaceable.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppDropdown<int>(
            value: _d.replaces ?? 0,
            decoration: InputDecoration(labelText: t('يستبدل مستنداً (اختياري)', 'Replaces a document (optional)')),
            items: [
              DropdownMenuItem(value: 0, child: Text(t('مستند جديد', 'A new document'))),
              for (final r in replaceable) DropdownMenuItem(value: r.id, child: Text('${r.displayTitle} · v${r.version}', maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _d.replaces = (v == null || v == 0) ? null : v),
          ),
        ),
      OutlinedButton.icon(
          onPressed: widget.busy ? null : _choose,
          icon: const Icon(Icons.attach_file_rounded, size: 18),
          label: Text(_d.fileName ?? t('اختر ملفاً (PDF, DOCX, TXT, MD, HTML, صور)', 'Pick a file (PDF, DOCX, TXT, MD, HTML, images)'), maxLines: 2, overflow: TextOverflow.ellipsis)),
      if (_d.fileBytes != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(ragSizeText(_d.fileBytes!.length), style: appText(11.5, c: c.textLight))),
      if (_err != null || widget.error != null)
        Padding(padding: const EdgeInsets.only(top: 10), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _err ?? widget.error!)),
      const SizedBox(height: 14),
      AppPrimaryButton(label: t('رفع', 'Upload'), icon: Icons.upload_rounded, busy: widget.busy, onPressed: widget.busy ? null : _submit),
    ]);
  }
}

// ── organization answer settings ──────────────────────────────────────────────────────────────────────────────

class RagSettingsSheet extends StatefulWidget {
  const RagSettingsSheet({super.key, required this.api, required this.orgId});
  final RagLibraryApi api;
  final int orgId;

  @override
  State<RagSettingsSheet> createState() => _RagSettingsSheetState();
}

class _RagSettingsSheetState extends State<RagSettingsSheet> {
  RagOrgSettings? _s;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.api.settings(widget.orgId);
    if (!mounted) return;
    setState(() {
      _s = r.ok ? RagOrgSettings.fromJson(r.map) : null;
      _error = r.ok ? null : ragResultText(r);
    });
  }

  Future<void> _save(String generator, bool external) async {
    setState(() => _busy = true);
    final r = await widget.api.saveSettings(widget.orgId, generator, external);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) _s = RagOrgSettings.fromJson(r.map);
    });
    if (r.ok) {
      appToast(t('تم الحفظ', 'Saved'));
    } else {
      appToast(ragResultText(r), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AppSheetHeader(t('إعدادات الإجابة', 'Answer settings')),
      Flexible(
        child: _s == null
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: _error == null ? const SizedBox(height: 100, child: AppListSkeleton(items: 2)) : AppBanner(icon: Icons.error_outline_rounded, color: context.colors.danger, text: _error!))
            : SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: RagSettingsForm(settings: _s!, busy: _busy, onSave: _save)),
      ),
    ]);
  }
}

class RagSettingsForm extends StatefulWidget {
  const RagSettingsForm({super.key, required this.settings, required this.onSave, this.busy = false});
  final RagOrgSettings settings;
  final bool busy;
  final void Function(String generator, bool allowExternal) onSave;

  @override
  State<RagSettingsForm> createState() => _RagSettingsFormState();
}

class _RagSettingsFormState extends State<RagSettingsForm> {
  late String _gen = widget.settings.generator;
  late bool _ext = widget.settings.allowExternal;

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!s.llmAvailable)
        Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppBanner(icon: Icons.info_outline_rounded, text: t('نموذج الصياغة غير مفعّل على الخادم؛ الإجابات مقتطفة من المستندات مباشرة.', 'No language model is set up on the server; answers are extracted straight from the documents.'))),
      AppDropdown<String>(
        value: _gen,
        decoration: InputDecoration(labelText: t('طريقة صياغة الإجابة', 'How answers are written')),
        items: [
          DropdownMenuItem(
              value: 'default',
              child: Text(
                  s.platformGenerator == 'llm'
                      ? t('حسب إعداد المنصة (يكتبها النموذج)', 'Follow the platform (written by the model)')
                      : t('حسب إعداد المنصة (اقتباس مباشر)', 'Follow the platform (quoted directly)'),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
          DropdownMenuItem(value: 'extractive', child: Text(t('اقتباس مباشر من المستندات', 'Quote the documents directly'), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (s.llmAvailable || _gen == 'llm') DropdownMenuItem(value: 'llm', child: Text(t('صياغة بنموذج لغوي', 'Written by a language model'), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => setState(() => _gen = v ?? 'default'),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Text(
            s.effectiveGenerator == 'llm'
                ? t('الآن: يكتب النموذج الإجابات من مستنداتكم ويراجعها مع المصادر.', 'Now: the model writes the answers from your documents and checks them against the sources.')
                : t('الآن: الإجابات مقتطفة من المستندات مباشرة.', 'Now: answers are quoted straight from the documents.'),
            style: appText(12, c: c.textMedium)),
      ),
      const SizedBox(height: 4),
      if (s.llmAvailable)
        AppSwitchTile(
            title: t('السماح بمزوّد خارجي', 'Allow an external provider'),
            subtitle: s.llmExternal
                ? t('يُرسل مقتطفات المستندات إلى مزوّد خارج المؤسسة — قرار مدير المؤسسة.', 'Document excerpts are sent to a provider outside the organization — the organization admin\'s decision.')
                : t('النموذج داخلي؛ لا تغادر المستندات الخادم.', 'The model is internal; documents do not leave the server.'),
            value: _gen == 'llm' && _ext,
            onChanged: _gen == 'llm' ? (v) => setState(() => _ext = v) : null),
      const SizedBox(height: 10),
      AppPrimaryButton(label: t('حفظ', 'Save'), icon: Icons.check_rounded, busy: widget.busy, onPressed: widget.busy ? null : () => widget.onSave(_gen, _ext)),
      const SizedBox(height: 4),
      Text(t('التغيير يسري على الأسئلة الجديدة فقط.', 'A change applies to new questions only.'), style: appText(11.5, c: c.textLight)),
    ]);
  }
}

// ── unhelpful answers ─────────────────────────────────────────────────────────────────────────────────────────

class RagFeedbackSheet extends StatefulWidget {
  const RagFeedbackSheet({super.key, required this.api, required this.orgId});
  final RagLibraryApi api;
  final int orgId;

  @override
  State<RagFeedbackSheet> createState() => _RagFeedbackSheetState();
}

class _RagFeedbackSheetState extends State<RagFeedbackSheet> {
  RagAnswerFeedback? _f;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.api.answersFeedback(widget.orgId).then((r) {
      if (!mounted) return;
      setState(() {
        _f = r.ok ? RagAnswerFeedback.fromJson(asMap(r.map)) : null;
        _error = r.ok ? null : ragResultText(r);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AppSheetHeader(t('الإجابات غير المفيدة', 'Unhelpful answers')),
      Flexible(
        child: _f == null
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: _error == null ? const SizedBox(height: 100, child: AppListSkeleton(items: 2)) : AppBanner(icon: Icons.error_outline_rounded, color: context.colors.danger, text: _error!))
            : SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: RagFeedbackView(feedback: _f!)),
      ),
    ]);
  }
}

class RagFeedbackView extends StatelessWidget {
  const RagFeedbackView({super.key, required this.feedback});
  final RagAnswerFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = feedback;
    final share = f.helpfulShare;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 10, runSpacing: 10, children: [
        _Stat(t('أُجيب', 'Answered'), '${f.answered}'),
        _Stat(t('قُيّم', 'Rated'), '${f.rated}'),
        _Stat(t('مفيد', 'Helpful'), share == null ? '—' : '${(share * 100).round()}%'),
        _Stat(t('لم يوجد في المستندات', 'Not found'), '${f.notFound}'),
      ]),
      const SizedBox(height: 8),
      Text(t('الأسئلة التي لم تُفِد (بلا أسماء) — أضف مستنداً أو صحّح الموجود.', 'Questions that did not help (no names) — add a document or fix an existing one.'), style: appText(12, c: c.textMedium)),
      const SizedBox(height: 8),
      if (f.unhelpful.isEmpty)
        AppEmpty(icon: Icons.thumb_up_alt_outlined, title: t('لا إجابات غير مفيدة', 'No unhelpful answers'))
      else
        for (final u in f.unhelpful)
          AppCard(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u.question, style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
              if (u.comment.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('«${u.comment}»', style: appText(12.5, c: c.textMedium))),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (u.found == false) AppBadgePill(t('لم يجد جواباً', 'No answer found'), color: c.warning),
                for (final s in u.sources) AppBadgePill(s, color: c.textMedium),
                if (u.at != null) AppBadgePill(shortDateTime(u.at), color: c.textLight),
              ]),
            ]),
          ),
    ]);
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 220),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: appText(20, w: FontWeight.w800, c: c.textDark)),
          Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(11.5, c: c.textLight)),
        ]),
      ),
    );
  }
}

// ── upload several files, with the one question about the documents already there ─────────────────────────────

/// Upload one or several files. When the library already holds documents, ONE question: keep both (the default,
/// nothing is touched) · merge (same name → new version) · replace (the old ones are archived only after every upload
/// succeeded, so a failed upload never empties the library). [RagBatchUploadForm] is the presentational part.
class RagBatchUploadSheet extends StatefulWidget {
  const RagBatchUploadSheet({super.key, required this.api, this.orgId, this.courseId, this.app = false, this.library, this.pickFiles});
  final RagLibraryApi api;
  final int? orgId;
  final int? courseId;
  final bool app;
  final RagLibrary? library;

  /// test hook / platform seam: the picked (name, bytes)
  final Future<List<(String, Uint8List)>> Function()? pickFiles;

  @override
  State<RagBatchUploadSheet> createState() => _RagBatchUploadSheetState();
}

class _RagBatchUploadSheetState extends State<RagBatchUploadSheet> {
  final List<(String, Uint8List)> _files = [];
  late String _scope = widget.app ? 'app' : (widget.orgId == null ? 'course' : 'org');
  RagConflictMode _mode = ragConflictDefault;
  bool _busy = false;
  int _done = 0;
  String? _err;

  List<RagDocument> get _existing => widget.library?.replaceable(_scope, courseId: widget.courseId) ?? const [];

  Future<List<(String, Uint8List)>> _pick() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ragUploadExtensions);
    return [for (final f in picked) (f.name, await f.readAsBytes())];
  }

  Future<void> _choose() async {
    final got = await (widget.pickFiles ?? _pick)();
    if (got.isEmpty || !mounted) return;
    setState(() {
      for (final f in got) {
        if (!_files.any((x) => x.$1 == f.$1)) _files.add(f);
      }
      _err = null;
    });
  }

  Future<void> _submit() async {
    if (_files.isEmpty) return setState(() => _err = draftErrorText('file_required'));
    final plan = RagConflictPlan.of(_existing, [for (final f in _files) f.$1]);
    final drafts = [
      for (final f in _files)
        RagUploadDraft(
            title: ragTitleOf(f.$1),
            scope: _scope,
            fileName: f.$1,
            fileBytes: f.$2,
            onConflict: plan.ask ? _mode : null),
    ];
    for (final d in drafts) {
      final e = d.validate(orgId: widget.orgId, fixedCourseId: widget.courseId);
      if (e != null) return setState(() => _err = '${d.fileName}: ${ragLibraryCodeText(e, draftErrorText(e))}');
    }
    setState(() {
      _busy = true;
      _done = 0;
      _err = null;
    });
    final outcomes = <String>[];
    final kept = <int>{};
    for (final d in drafts) {
      final r = await widget.api.upload(d, orgId: widget.app ? null : widget.orgId, courseId: widget.courseId);
      if (!mounted) return;
      if (!r.ok) {
        // stop here: nothing old is archived after a failed upload
        setState(() {
          _busy = false;
          _err = '${d.fileName}: ${ragResultText(r)}';
          _files.removeRange(0, _done);
        });
        if (outcomes.isNotEmpty) appToast(ragOutcomeSummary(outcomes));
        return;
      }
      outcomes.add(asStr(r.map['outcome'], 'added'));
      kept.add(asInt(r.map['id']));
      setState(() => _done++);
    }
    var archived = 0;
    if (plan.ask && _mode == RagConflictMode.replace) {
      for (final old in _existing.where((x) => !kept.contains(x.id))) {
        if ((await widget.api.archive(old.id)).ok) archived++;
      }
    }
    if (!mounted) return;
    appToast([ragOutcomeSummary(outcomes), if (archived > 0) t('$archived مؤرشف', '$archived archived')].join(' · '));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final scopes = widget.app ? const ['app'] : (widget.orgId == null ? const ['course'] : ragScopes);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader(t('رفع مستندات', 'Upload documents')),
        RagBatchUploadForm(
          files: [for (final f in _files) (f.$1, f.$2.length)],
          scopes: scopes,
          scope: _scope,
          plan: RagConflictPlan.of(_existing, [for (final f in _files) f.$1]),
          mode: _mode,
          busy: _busy,
          done: _done,
          error: _err,
          onPick: _choose,
          onRemove: (i) => setState(() => _files.removeAt(i)),
          onScope: (s) => setState(() {
            _scope = s;
            _mode = ragConflictDefault;
          }),
          onMode: (m) => setState(() => _mode = m),
          onSubmit: _submit,
        ),
      ]),
    );
  }
}

/// Files · scope (organization libraries) · the conflict question when the library has documents · Upload.
class RagBatchUploadForm extends StatelessWidget {
  const RagBatchUploadForm({
    super.key,
    required this.files,
    required this.scopes,
    required this.scope,
    required this.plan,
    required this.mode,
    required this.onPick,
    required this.onRemove,
    required this.onScope,
    required this.onMode,
    required this.onSubmit,
    this.busy = false,
    this.done = 0,
    this.error,
  });

  /// (name, size in bytes)
  final List<(String, int)> files;
  final List<String> scopes;
  final String scope;
  final RagConflictPlan plan;
  final RagConflictMode mode;
  final bool busy;
  final int done;
  final String? error;
  final VoidCallback onPick;
  final ValueChanged<int> onRemove;
  final ValueChanged<String> onScope;
  final ValueChanged<RagConflictMode> onMode;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (scopes.length > 1) ...[
        Text(t('من يرى هذه المستندات؟', 'Who sees these documents?'), style: appText(13, w: FontWeight.w700, c: c.textDark)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in scopes) AppChoiceChip(label: ragScopeText(s), selected: scope == s, onTap: busy ? () {} : () => onScope(s)),
        ]),
        const SizedBox(height: 12),
      ],
      for (var i = 0; i < files.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Icon(i < done ? Icons.check_circle_rounded : Icons.insert_drive_file_outlined, size: 20, color: i < done ? c.success : c.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(files[i].$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, c: c.textDark))),
            const SizedBox(width: 6),
            Text(ragSizeText(files[i].$2), style: appText(11.5, c: c.textLight)),
            if (!busy) IconButton(tooltip: t('إزالة', 'Remove'), onPressed: () => onRemove(i), icon: Icon(Icons.close_rounded, size: 18, color: c.textLight)),
          ]),
        ),
      OutlinedButton.icon(
          onPressed: busy ? null : onPick,
          icon: const Icon(Icons.attach_file_rounded, size: 18),
          label: Text(files.isEmpty ? t('اختر ملفاً أو أكثر', 'Choose one or more files') : t('أضف ملفات', 'Add files'))),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(t('الأفضل: Word أو PDF نصي — يُقرأ بدقة. الصور والملفات الممسوحة تُقرأ بالتعرف الضوئي وقد تفقد كلمات.',
            'Best: Word or a text PDF — read exactly. Photos and scans go through OCR and may lose words.'), style: appText(11.5, c: c.textLight)),
      ),
      if (files.isNotEmpty && plan.ask) ...[
        const SizedBox(height: 14),
        RagConflictQuestion(plan: plan, mode: mode, onMode: busy ? null : onMode),
      ],
      if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!)),
      const SizedBox(height: 14),
      AppPrimaryButton(
          label: busy && files.isNotEmpty ? t('جارٍ الرفع ${done + 1} من ${files.length}', 'Uploading ${done + 1} of ${files.length}') : t('رفع', 'Upload'),
          icon: Icons.upload_rounded,
          busy: busy,
          onPressed: busy || files.isEmpty ? null : onSubmit),
    ]);
  }
}

/// The one question when a library already holds documents (keep both is preselected: nothing is touched).
class RagConflictQuestion extends StatelessWidget {
  const RagConflictQuestion({super.key, required this.plan, required this.mode, this.onMode});
  final RagConflictPlan plan;
  final RagConflictMode mode;
  final ValueChanged<RagConflictMode>? onMode;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('توجد ${plan.existing} مستندات هنا مسبقاً. ماذا نفعل بها؟', 'There are already ${plan.existing} documents here. What should we do with them?'),
            style: appText(13.5, w: FontWeight.w800, c: c.textDark)),
        const SizedBox(height: 6),
        for (final m in RagConflictMode.values)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onMode == null ? null : () => onMode!(m),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(mode == m ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, size: 20,
                    color: mode == m ? c.primary : c.textLight),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m == ragConflictDefault ? '${plan.title(m)} ${t('(موصى به)', '(recommended)')}' : plan.title(m),
                        style: appText(13.5, w: FontWeight.w700, c: m == RagConflictMode.replace ? c.danger : c.textDark)),
                    Text(plan.detail(m), style: appText(12, c: c.textMedium)),
                  ]),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}
