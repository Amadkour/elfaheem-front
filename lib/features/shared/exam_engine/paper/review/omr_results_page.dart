// The results of a scanned bubble-sheet exam (brief 4.5, S.1): the grades per student, per-question statistics,
// the score distribution, export (Excel / Word / PDF through the Export Studio, both languages) and publishing.
// Publishing is the server's decision: with review items open it answers 409 `review_items_open`, and only then the
// page offers the server's explicit `graded_only` option behind a clear confirmation. Students then see only their
// own result, and only once it is graded and published (the engine's rule).
//
// Live: `job_updated {kind: omr_scan, exam_id}` reloads through EventOrPoll (the timer is the slow fallback).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_responsive.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../../../admin/admin_common.dart' show asInt, t;
import '../exam_setup.dart' show kExamOmrFeatureKey;
import 'omr_results_parts.dart';
import 'omr_review.dart';
import 'omr_review_page.dart';

class OmrResultsPage extends StatefulWidget {
  const OmrResultsPage({super.key, required this.examId, this.api, this.liveStream, this.liveBus});
  final int examId;
  final OmrReviewApi? api;
  final LiveStreamHandle? liveStream;
  final LiveEvents? liveBus;

  @override
  State<OmrResultsPage> createState() => _OmrResultsPageState();
}

class _OmrResultsPageState extends State<OmrResultsPage> {
  late final OmrReviewApi _api = widget.api ?? OmrReviewApi();
  EventOrPoll? _watch;
  OmrResults? _r;
  String? _error;
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    _load();
    _watch = omrScanWatch(widget.examId, () => _load(silent: true), stream: widget.liveStream, bus: widget.liveBus)..start();
  }

  @override
  void dispose() {
    _watch?.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final r = await _api.results(widget.examId);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _r = OmrResults.fromJson(r.map);
        _error = null;
      } else if (!silent) {
        _error = omrErrorText(r);
      }
    });
  }

  void _export() {
    final r = _r;
    if (r == null || r.students.isEmpty) return;
    showAppExportSheet(context, bilingualExport(() => omrResultsExport(r)));
  }

  Future<void> _openReview() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => OmrReviewPage(examId: widget.examId, liveStream: widget.liveStream, liveBus: widget.liveBus)));
    if (mounted) _load(silent: true);
  }

  Future<void> _publish() async {
    final ok = await appConfirm(context,
        message: t('يرى كل طالب نتيجته فقط، ولا يرى نتائج غيره. نشر النتائج الآن؟', 'Each student will see only their own result. Publish the results now?'),
        confirmLabel: t('نشر', 'Publish'));
    if (!ok || !mounted) return;
    setState(() => _publishing = true);
    final r = await _api.publish(widget.examId);
    if (!mounted) return;
    setState(() => _publishing = false);
    if (r.ok) {
      final p = OmrPublishReply.fromJson(r.map);
      showAppNotice(omrPublishedText(p.visibleAttempts));
      return _load(silent: true);
    }
    if (r.code != 'review_items_open') {
      showAppNotice(omrErrorText(r), error: true);
      return;
    }
    final open = asInt(r.detail['open'], _r?.openReviewItems ?? 0);
    final choice = await showAppSheet<String>(context, (ctx) => _OpenItemsSheet(serverText: omrErrorText(r), open: open, graded: _r?.graded ?? 0));
    if (!mounted || choice == null) return;
    if (choice == 'review') return _openReview();
    final graded = _r?.graded ?? 0, waiting = _r?.inReview ?? 0;
    final sure = await appConfirm(context,
        message: omrGradedOnlyConfirm(graded, waiting),
        confirmLabel: t('نشر المصحّح فقط', 'Publish the graded ones'));
    if (!sure || !mounted) return;
    setState(() => _publishing = true);
    final g = await _api.publish(widget.examId, gradedOnly: true);
    if (!mounted) return;
    setState(() => _publishing = false);
    if (!g.ok) {
      showAppNotice(omrErrorText(g), error: true);
      return;
    }
    final p = OmrPublishReply.fromJson(g.map);
    showAppNotice(omrGradedOnlyText(p.visibleAttempts, p.openReviewItems));
    _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = _r;
    return BasePage(
      key: const ValueKey(kExamOmrFeatureKey),
      appBar: AppHeader(
        title: r == null || r.title.isEmpty ? t('نتائج الاختبار الورقي', 'Paper exam results') : r.title,
        actions: [
          IconButton(
            key: const ValueKey('omr.export'),
            tooltip: t('تصدير Excel / Word / PDF', 'Export Excel / Word / PDF'),
            onPressed: r == null || r.students.isEmpty ? null : _export,
            icon: const Icon(Icons.file_download_outlined),
          ),
          AppRefreshAction(onRefresh: _load),
        ],
      ),
      child: LayoutBuilder(builder: (context, box) {
        final pad = AppSpace.gutter(box.maxWidth);
        final wide = box.maxWidth >= Breakpoints.desktop;
        return AppRefresh(
          onRefresh: _load,
          child: ListView(padding: EdgeInsets.fromLTRB(pad, AppSpace.md, pad, AppSpace.xl), children: [
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: AppWidth.wide.max),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (_error != null)
                    AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!, action: TextButton(onPressed: _load, child: Text(t('إعادة المحاولة', 'Try again')))),
                  if (r == null && _error == null) const AppListSkeleton(items: 5, withAvatar: false),
                  if (r != null) ..._body(context, r, wide),
                ]),
              ),
            ),
          ]),
        );
      }),
    );
  }

  List<Widget> _body(BuildContext context, OmrResults r, bool wide) {
    final c = context.colors;
    return [
      OmrResultsSummary(results: r, onReview: _openReview),
      if (r.openReviewItems > 0) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(
          icon: Icons.rate_review_rounded,
          color: c.warning,
          text: omrItemsWaitText(r.openReviewItems),
          action: TextButton(key: const ValueKey('omr.results.review'), onPressed: _openReview, child: Text(t('مراجعة', 'Review'))),
        ),
      ],
      const SizedBox(height: AppSpace.md),
      OmrPublishCard(results: r, busy: _publishing, onPublish: _publish),
      const SizedBox(height: AppSpace.md),
      OmrDistributionCard(results: r),
      const SizedBox(height: AppSpace.lg),
      AppSectionTitle(t('الدرجات', 'Grades'),
          subtitle: omrPapersText(r.students.length),
          trailing: r.students.isEmpty
              ? null
              : TextButton.icon(onPressed: _export, icon: const Icon(Icons.file_download_outlined, size: 18), label: Text(t('تصدير', 'Export')))),
      const SizedBox(height: AppSpace.xs),
      OmrGradesView(results: r, wide: wide),
      if (r.questions.isNotEmpty) ...[
        const SizedBox(height: AppSpace.lg),
        AppSectionTitle(t('إحصاءات الأسئلة', 'Question statistics'), subtitle: t('الصعوبة = نسبة من أجابوا صحيحًا', 'Difficulty = the share who answered right')),
        const SizedBox(height: AppSpace.xs),
        OmrQuestionStatsView(questions: r.questions, wide: wide),
      ],
    ];
  }
}

/// The server refused (409 review_items_open): review the items, or — explicitly — publish the graded ones only.
class _OpenItemsSheet extends StatelessWidget {
  const _OpenItemsSheet({required this.serverText, required this.open, required this.graded});
  final String serverText;
  final int open;
  final int graded;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppSheetContent(title: t('لم تُنشر النتائج بعد', 'Not published yet'), children: [
      AppBanner(icon: Icons.rate_review_rounded, color: c.warning, text: serverText),
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(
        key: const ValueKey('omr.publish.review'),
        label: t('مراجعة العناصر ($open)', 'Review the items ($open)'),
        icon: Icons.rate_review_rounded,
        onPressed: () => Navigator.of(context).pop('review'),
      ),
      const SizedBox(height: AppSpace.sm),
      OutlinedButton.icon(
        key: const ValueKey('omr.publish.gradedOnly'),
        onPressed: graded == 0 ? null : () => Navigator.of(context).pop('graded'),
        icon: const Icon(Icons.done_all_rounded, size: 18),
        label: Text(t('نشر المصحّح فقط ($graded)', 'Publish the graded ones ($graded)')),
      ),
    ]);
  }
}
