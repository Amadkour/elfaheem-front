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
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppFill;
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMap, asStr, shortDateTime, t;
import 'package:flutter_education_app/features/admin/admin_money_p8.dart' show draftErrorText, p8SaveBytes;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult;
import 'package:flutter_education_app/features/admin/admin_feature_guide.dart' show AdminFeatureGuidePage;
import 'package:flutter_education_app/features/rag/admin/rag_feedback_review.dart' show RagFeedbackReviewPage;
import 'package:flutter_education_app/features/rag/library/rag_doc_status.dart';
import 'package:flutter_education_app/features/rag/library/rag_upload_scope.dart';
import 'package:flutter_education_app/features/rag/rag_chat_screen.dart' show RagChatScreen;
import 'package:flutter_education_app/features/rag/rag_library.dart';
import 'package:flutter_education_app/features/rag/rag_learning_page.dart' show RagLearningPage;
import 'package:flutter_education_app/features/rag/rag_qa_admin.dart' show RagQaAdminPage;

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
            ? RagBatchUploadSheet(api: _api, orgId: widget.orgId, courseId: widget.courseId, app: widget.app, library: _lib, ocrScanned: _lib?.ocrScanned, maxMb: _lib?.maxMb)
            : RagUploadSheet(api: _api, orgId: widget.orgId, courseId: widget.courseId, library: _lib, replaces: replaces, ocrScanned: _lib?.ocrScanned, maxMb: _lib?.maxMb));
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
      width: AppWidth.wide,
      appBar: ScreenAppBar(helpPageId: 'rag.library', title: widget.title ?? (widget.app ? t('مستندات التطبيق', 'App documents') : t('مكتبة المستندات', 'Documents library')), actions: [
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
        // learning from feedback (Track F): the organization's suggestions and its opt-in (platform admins: the console)
        if (lib?.manager == true && !widget.app && widget.orgId != null && widget.courseId == null)
          ParentComponent(
            featureKey: 'rag.learning',
            child: IconButton(
                tooltip: t('التعلّم من الملاحظات', 'Learning from feedback'),
                icon: const Icon(Icons.school_outlined),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RagLearningPage(orgId: widget.orgId)))),
          ),
        if (widget.orgId != null)
          IconButton(
              tooltip: t('الإجابات غير المفيدة', 'Unhelpful answers'),
              icon: const Icon(Icons.thumb_down_alt_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RagFeedbackReviewPage(orgId: widget.orgId)))),
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
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xxs),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
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
        if (lib?.quota != null) Padding(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.xxs), child: RagQuotaBar(quota: lib!.quota!)),
        Expanded(
          child: _loading
              ? const AppListSkeleton()
              : _error != null
                  ? AppEmpty(icon: Icons.error_outline_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
                  : ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xxxl + AppSpace.lg), children: [
                      // the platform admins' dashboard of the app assistant (the app library)
                      if (widget.app && lib?.manager == true && _active != null) ...[
                        RagLibraryOverview(
                            library: _active!,
                            onUpload: _upload,
                            onSync: _syncApp,
                            onGuide: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminFeatureGuidePage())),
                            onTry: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RagChatScreen(app: true)))),
                        const SizedBox(height: AppSpace.md),
                      ],
                      if (shown.isEmpty)
                        AppEmpty(icon: Icons.folder_open_rounded, title: t('لا مستندات', 'No documents'), message: t('ارفع لائحة أو دليلاً ليجيب المساعد منه.', 'Upload a regulation or guide for the assistant to answer from.'))
                      else
                        for (final d in shown)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpace.sm),
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
              foregroundColor: c.onHero,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.card))),
              icon: const Icon(Icons.upload_file_rounded),
              label: Text(t('رفع مستند', 'Upload'), style: AppType.label(context).copyWith(color: c.onHero)))
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
          color: appInk(context, c.primary),
          text: t('يجيب مساعد التطبيق كل المستخدمين من هذه المستندات، ومن الشروط و«عن التطبيق» و«دليل ميزات التطبيق» (تُقرأ تلقائياً). عدّل الدليل لتحدد ما يشرحه المساعد عن كل ميزة ولمن.',
              'The app assistant answers every user from these documents and from the terms, About and "App features guide" pages (read automatically). Edit the guide to decide what it explains about each feature, and for whom.')),
      const SizedBox(height: AppSpace.sm),
      AppGrid(padding: EdgeInsets.zero, minTile: 150, children: [
        AppStatTile(icon: Icons.task_alt_rounded, label: ragStatusText('ready'), value: counts['ready'] ?? 0, color: c.success),
        AppStatTile(icon: Icons.hourglass_top_rounded, label: ragStatusText('processing'), value: busy, color: c.warning),
        AppStatTile(icon: Icons.error_outline_rounded, label: ragStatusText('failed'), value: counts['failed'] ?? 0, color: c.danger),
        AppStatTile(icon: Icons.data_usage_rounded, label: t('الحجم', 'Size'), value: ragSizeText(size)),
        AppStatTile(icon: Icons.segment_rounded, label: t('مقاطع مفهرسة', 'Indexed passages'), value: chunks),
      ]),
      const SizedBox(height: AppSpace.sm),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
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
            Icon(Icons.inventory_2_outlined, size: AppIconSize.md, color: appInk(context, col)),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs / 2, children: [
                Text(quota.docsText, style: AppType.label(context).copyWith(color: c.textDark)),
                Text(quota.bytesText, style: AppType.meta(context).copyWith(color: c.textMedium)),
              ]),
            ),
          ]),
          if (fill != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: AppFill(
                  value: fill,
                  builder: (context, v) => LinearProgressIndicator(value: v, minHeight: AppSpace.xs - AppSpace.xxs / 2, color: col, backgroundColor: c.inputBg),
                ),
              ),
            ),
          if (quota.full)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text(t('المكتبة ممتلئة — أرشف مستندات لتحرير مساحة', 'The library is full — archive documents to make room'),
                  style: AppType.label(context).copyWith(color: c.danger)),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ExcludeSemantics(
            child: SizedBox.square(
              dimension: AppIconSize.hero,
              child: DecoratedBox(
                decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.chip)),
                child: Icon(Icons.description_outlined, size: AppIconSize.md, color: appInk(context, c.primary)),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text(doc.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: c.textDark))),
          const SizedBox(width: AppSpace.xs),
          AppBadgePill(ragStatusText(doc.status), color: col),
        ]),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppBadgePill(ragScopeText(doc.scope), color: c.textMedium),
          AppBadgePill('v${doc.version}', color: c.textMedium),
          if (doc.pages != null) AppBadgePill('${doc.pages} ${t('صفحة', 'pages')}', color: c.textMedium),
          if (doc.chunks > 0) AppBadgePill('${doc.chunks} ${t('مقطع', 'chunks')}', color: c.textMedium),
          if (doc.size > 0) AppBadgePill(ragSizeText(doc.size), color: c.textMedium),
          if (doc.ocrPages > 0) AppBadgePill('OCR ${doc.ocrPages}', color: c.textMedium),
        ]),
        if (doc.createdAt != null)
          Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text(shortDateTime(doc.createdAt), style: AppType.meta(context).copyWith(color: c.textLight))),
        if (doc.status == 'failed' && ragDocErrorText(doc.error).isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: ragDocErrorText(doc.error))),
        RagWarningChips(warnings: doc.warnings),
        RagExcludedText(excluded: doc.excluded),
        if (doc.showProgress)
          RagProgressRow(done: doc.progressDone, total: doc.progressTotal)
        else if (doc.busy)
          const Padding(padding: EdgeInsets.only(top: AppSpace.sm), child: LinearProgressIndicator(minHeight: 3)),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xxs, runSpacing: 0, children: [
          TextButton.icon(onPressed: working ? null : onDownload, icon: const Icon(Icons.download_rounded, size: AppIconSize.md), label: Text(t('تنزيل', 'Download'))),
          if (manager && onNewVersion != null)
            TextButton.icon(onPressed: working ? null : onNewVersion, icon: const Icon(Icons.library_add_rounded, size: AppIconSize.md), label: Text(t('نسخة جديدة', 'New version'))),
          if (manager && onReindex != null)
            TextButton.icon(onPressed: working ? null : onReindex, icon: const Icon(Icons.refresh_rounded, size: AppIconSize.md), label: Text(t('إعادة فهرسة', 'Reindex'))),
          if (manager && onArchive != null)
            TextButton.icon(
                onPressed: working ? null : onArchive,
                style: TextButton.styleFrom(foregroundColor: c.danger),
                icon: const Icon(Icons.archive_outlined, size: AppIconSize.md),
                label: Text(t('أرشفة', 'Archive'))),
        ]),
      ]),
    );
  }
}

// ── upload ────────────────────────────────────────────────────────────────────────────────────────────────────

class RagUploadSheet extends StatefulWidget {
  const RagUploadSheet({super.key, required this.api, this.orgId, this.courseId, this.library, this.replaces, this.ocrScanned, this.maxMb});
  final bool? ocrScanned;
  final int? maxMb;
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
    if (r.ok && asStr(r.map['status']) == 'failed') {
      final e = ragDocErrorText(asStr(r.map['error']));
      setState(() {
        _busy = false;
        _err = e.isEmpty ? ragStatusText('failed') : e;
      });
    } else if (r.ok) {
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
      padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader(widget.replaces == null ? t('رفع مستند', 'Upload a document') : t('نسخة جديدة من المستند', 'New version of the document')),
        RagUploadForm(
            ocrScanned: widget.ocrScanned,
            maxMb: widget.maxMb,
            orgId: widget.orgId, courseId: widget.courseId, library: widget.library, replaces: widget.replaces, busy: _busy, error: _err, onSubmit: _submit),
      ]),
    );
  }
}

/// Title · scope · (course) · replaces · file. Presentational: [onSubmit] gets a validated draft.
class RagUploadForm extends StatefulWidget {
  const RagUploadForm({super.key, required this.onSubmit, this.orgId, this.courseId, this.library, this.replaces, this.busy = false, this.error, this.pickFile, this.ocrScanned, this.maxMb});
  final bool? ocrScanned;
  final int? maxMb;
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
      scope: widget.replaces?.scope ?? (widget.orgId == null || widget.courseId != null ? 'course' : 'org'),
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
    final scopes = widget.replaces != null && (widget.replaces!.scope == 'app' || widget.replaces!.scope == 'global')
        ? [widget.replaces!.scope]
        : ragScopeOptions(ragUploaderRole(manager: true, orgId: widget.orgId, courseId: widget.courseId ?? (widget.orgId == null ? 0 : null)));
    final replaceable = widget.library?.replaceable(_d.scope, courseId: widget.courseId ?? _d.courseIdValue) ?? const <RagDocument>[];
    final locked = widget.replaces != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppField(controller: _title, label: t('العنوان', 'Title')),
      RagScopePicker(
          options: scopes,
          scope: _d.scope,
          busy: locked,
          onScope: (s) => setState(() {
                _d.scope = s;
                _d.replaces = null;
              }),
          roles: _d.roles,
          onRoles: locked ? null : (r) => setState(() => _d.roles.contains(r) ? _d.roles.remove(r) : _d.roles.add(r)),
          fixedCourse: widget.courseId != null,
          courseField: AppField(controller: _course, label: t('رقم المقرر', 'Course id'), keyboard: TextInputType.number)),
      if (!locked && replaceable.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
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
          icon: const Icon(Icons.attach_file_rounded, size: AppIconSize.md),
          label: Text(_d.fileName ?? t('اختر ملفاً (PDF, DOCX, TXT, MD, HTML, صور)', 'Pick a file (PDF, DOCX, TXT, MD, HTML, images)'), maxLines: 2, overflow: TextOverflow.ellipsis)),
      RagUploadHint(ocrScanned: widget.ocrScanned, maxMb: widget.maxMb),
      if (_d.fileBytes != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: Text(ragSizeText(_d.fileBytes!.length), style: AppType.meta(context).copyWith(color: c.textLight))),
      if (_err != null || widget.error != null)
        Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _err ?? widget.error!)),
      const SizedBox(height: AppSpace.md),
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
                padding: const EdgeInsets.all(AppSpace.lg),
                child: _error == null ? const SizedBox(height: AppSpace.xxxl + AppSpace.xl, child: AppListSkeleton(items: 2)) : AppBanner(icon: Icons.error_outline_rounded, color: context.colors.danger, text: _error!))
            : SingleChildScrollView(padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md), child: RagSettingsForm(settings: _s!, busy: _busy, onSave: _save)),
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
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
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
        padding: const EdgeInsets.only(top: AppSpace.xxs, bottom: AppSpace.xxs),
        child: Text(
            s.effectiveGenerator == 'llm'
                ? t('الآن: يكتب النموذج الإجابات من مستنداتكم ويراجعها مع المصادر.', 'Now: the model writes the answers from your documents and checks them against the sources.')
                : t('الآن: الإجابات مقتطفة من المستندات مباشرة.', 'Now: answers are quoted straight from the documents.'),
            style: AppType.meta(context).copyWith(color: c.textMedium)),
      ),
      const SizedBox(height: AppSpace.xxs),
      if (s.llmAvailable)
        AppSwitchTile(
            title: t('السماح بمزوّد خارجي', 'Allow an external provider'),
            subtitle: s.llmExternal
                ? t('يُرسل مقتطفات المستندات إلى مزوّد خارج المؤسسة — قرار مدير المؤسسة.', 'Document excerpts are sent to a provider outside the organization — the organization admin\'s decision.')
                : t('النموذج داخلي؛ لا تغادر المستندات الخادم.', 'The model is internal; documents do not leave the server.'),
            value: _gen == 'llm' && _ext,
            onChanged: _gen == 'llm' ? (v) => setState(() => _ext = v) : null),
      const SizedBox(height: AppSpace.sm),
      AppPrimaryButton(label: t('حفظ', 'Save'), icon: Icons.check_rounded, busy: widget.busy, onPressed: widget.busy ? null : () => widget.onSave(_gen, _ext)),
      const SizedBox(height: AppSpace.xxs),
      Text(t('التغيير يسري على الأسئلة الجديدة فقط.', 'A change applies to new questions only.'), style: AppType.meta(context).copyWith(color: c.textLight)),
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
                padding: const EdgeInsets.all(AppSpace.lg),
                child: _error == null ? const SizedBox(height: AppSpace.xxxl + AppSpace.xl, child: AppListSkeleton(items: 2)) : AppBanner(icon: Icons.error_outline_rounded, color: context.colors.danger, text: _error!))
            : SingleChildScrollView(padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md), child: RagFeedbackView(feedback: _f!)),
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
      Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
        _Stat(t('أُجيب', 'Answered'), '${f.answered}'),
        _Stat(t('قُيّم', 'Rated'), '${f.rated}'),
        _Stat(t('مفيد', 'Helpful'), share == null ? '—' : '${(share * 100).round()}%'),
        _Stat(t('لم يوجد في المستندات', 'Not found'), '${f.notFound}'),
      ]),
      const SizedBox(height: AppSpace.xs),
      Text(t('الأسئلة التي لم تُفِد (بلا أسماء) — أضف مستنداً أو صحّح الموجود.', 'Questions that did not help (no names) — add a document or fix an existing one.'), style: AppType.meta(context).copyWith(color: c.textMedium)),
      const SizedBox(height: AppSpace.xs),
      if (f.unhelpful.isEmpty)
        // a calm line rather than the full empty plate: the stats above already carry the sheet
        AppCard(
          child: Row(children: [
            Icon(Icons.thumb_up_alt_outlined, size: AppIconSize.md, color: appInk(context, c.success)),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(t('لا إجابات غير مفيدة', 'No unhelpful answers'), style: AppType.bodyStrong(context).copyWith(color: c.textDark))),
          ]),
        )
      else
        for (final u in f.unhelpful)
          AppCard(
            margin: const EdgeInsets.only(bottom: AppSpace.xs),
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u.question, style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
              if (u.comment.isNotEmpty) Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: Text('«${u.comment}»', style: AppType.meta(context).copyWith(color: c.textMedium))),
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
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
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: AppType.figure(context).copyWith(color: c.textDark)),
          Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
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
  const RagBatchUploadSheet({super.key, required this.api, this.orgId, this.courseId, this.app = false, this.library, this.pickFiles, this.ocrScanned, this.maxMb});
  final int? maxMb;
  final RagLibraryApi api;
  final int? orgId;
  final int? courseId;
  final bool app;
  final RagLibrary? library;

  /// test hook / platform seam: the picked (name, bytes)
  final Future<List<(String, Uint8List)>> Function()? pickFiles;

  /// reading scanned pages is on (null = not known): changes the hint
  final bool? ocrScanned;

  @override
  State<RagBatchUploadSheet> createState() => _RagBatchUploadSheetState();
}

class _RagBatchUploadSheetState extends State<RagBatchUploadSheet> {
  final List<(String, Uint8List)> _files = [];
  late final RagUploaderRole _role = ragUploaderRole(manager: widget.library?.manager ?? true, app: widget.app, orgId: widget.orgId, courseId: widget.courseId);
  late final List<String> _options = ragScopeOptions(_role);
  late String _scope = _options.isEmpty ? 'course' : _options.first;
  final Set<String> _roles = {};
  int? _pickedCourse;
  List<RagCourseChoice> _courses = const [];
  RagConflictMode _mode = ragConflictDefault;
  bool _busy = false;
  int _done = 0;
  String? _err;

  List<RagDocument> get _existing => widget.library?.replaceable(_scope, courseId: widget.courseId ?? _pickedCourse) ?? const [];

  @override
  void initState() {
    super.initState();
    if (_role == RagUploaderRole.orgAdmin && widget.orgId != null) {
      widget.api.orgCourses(widget.orgId!).then((c) {
        if (mounted) setState(() => _courses = c);
      });
    }
  }

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
            courseId: _pickedCourse == null ? '' : '$_pickedCourse',
            roles: _scope == 'org' ? _roles : null,
            fileName: f.$1,
            fileBytes: f.$2,
            onConflict: plan.ask ? _mode : null),
    ];
    if (_options.isEmpty) return setState(() => _err = ragLibraryCodeText('not_library_manager', ''));
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
      // an identical file that failed before comes back as that failed document: say why, don't say "uploaded"
      if (asStr(r.map['status']) == 'failed') {
        final why = ragDocErrorText(asStr(r.map['error']));
        setState(() {
          _busy = false;
          _err = '${d.fileName}: ${why.isEmpty ? ragStatusText('failed') : why}';
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
    final scopes = _options;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader(t('رفع مستندات', 'Upload documents')),
        RagBatchUploadForm(
          files: [for (final f in _files) (f.$1, f.$2.length)],
          scopes: scopes,
          scope: _scope,
          roles: _roles,
          onRoles: (r) => setState(() => _roles.contains(r) ? _roles.remove(r) : _roles.add(r)),
          courses: _courses,
          courseId: _pickedCourse,
          onCourse: (v) => setState(() => _pickedCourse = v),
          fixedCourse: widget.courseId != null,
          ocrScanned: widget.ocrScanned,
          maxMb: widget.maxMb,
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
    this.roles = const {},
    this.onRoles,
    this.courses = const [],
    this.courseId,
    this.onCourse,
    this.fixedCourse = false,
    this.ocrScanned,
    this.maxMb,
  });

  final Set<String> roles;
  final ValueChanged<String>? onRoles;
  final List<RagCourseChoice> courses;
  final int? courseId;
  final ValueChanged<int?>? onCourse;
  final bool fixedCourse;
  final bool? ocrScanned;
  final int? maxMb;

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
      RagScopePicker(
          options: scopes,
          scope: scope,
          onScope: onScope,
          roles: roles,
          onRoles: onRoles,
          courses: courses,
          courseId: courseId,
          onCourse: onCourse,
          fixedCourse: fixedCourse,
          busy: busy),
      for (var i = 0; i < files.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Row(children: [
            Icon(i < done ? Icons.check_circle_rounded : Icons.insert_drive_file_outlined, size: 20, color: appInk(context, i < done ? c.success : c.primary)),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(files[i].$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: c.textDark))),
            const SizedBox(width: AppSpace.xs),
            Text(ragSizeText(files[i].$2), style: AppType.meta(context).copyWith(color: c.textLight)),
            if (!busy) IconButton(tooltip: t('إزالة', 'Remove'), onPressed: () => onRemove(i), icon: Icon(Icons.close_rounded, size: AppIconSize.md, color: c.textLight)),
          ]),
        ),
      OutlinedButton.icon(
          onPressed: busy ? null : onPick,
          icon: const Icon(Icons.attach_file_rounded, size: AppIconSize.md),
          label: Text(files.isEmpty ? t('اختر ملفاً أو أكثر', 'Choose one or more files') : t('أضف ملفات', 'Add files'))),
      RagUploadHint(ocrScanned: ocrScanned, maxMb: maxMb),
      if (files.isNotEmpty && plan.ask) ...[
        const SizedBox(height: AppSpace.md),
        RagConflictQuestion(plan: plan, mode: mode, onMode: busy ? null : onMode),
      ],
      if (error != null) Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!)),
      const SizedBox(height: AppSpace.md),
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
      padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.sm, AppSpace.sm, AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('توجد ${plan.existing} مستندات هنا مسبقاً. ماذا نفعل بها؟', 'There are already ${plan.existing} documents here. What should we do with them?'),
            style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
        const SizedBox(height: AppSpace.xs),
        for (final m in RagConflictMode.values)
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            onTap: onMode == null ? null : () => onMode!(m),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(mode == m ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, size: 20,
                    color: mode == m ? appInk(context, c.primary) : c.textLight),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m == ragConflictDefault ? '${plan.title(m)} ${t('(موصى به)', '(recommended)')}' : plan.title(m),
                        style: AppType.bodyStrong(context).copyWith(color: m == RagConflictMode.replace ? c.danger : c.textDark)),
                    Text(plan.detail(m), style: AppType.meta(context).copyWith(color: c.textMedium)),
                  ]),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}
