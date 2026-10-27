// Organization side of the Phase 8 exam insights: the feedback-store settings + export (org admin) and the exam
// risk dashboard (org admin / people who may view exam reports).
//
//   GET|PUT /api/v1/exam/orgs/{id}/feedback/settings   {enabled, retention_days} (+ platform_enabled, effective, inherits)
//   GET     /api/v1/exam/orgs/{id}/feedback/export     ?format=jsonl|csv&since=
//   GET     /api/v1/exam/orgs/{id}/risk                {items:[{exam_id, title, risky_attempts, max_risk, needs_review}]}
//
// Risk signals are for human review only — the screen says so and never names a student.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../admin/admin_common.dart' show asDouble, asInt, asMapList, asStr, t;
import '../admin/admin_feedback_settings.dart';

class ExamRiskItem {
  const ExamRiskItem(this.examId, this.title, this.riskyAttempts, this.maxRisk, this.needsReview);
  final int examId;
  final String title;
  final int riskyAttempts;
  final double maxRisk;
  final int needsReview;

  factory ExamRiskItem.fromJson(Map<String, dynamic> j) => ExamRiskItem(asInt(j['exam_id']), asStr(j['title']), asInt(j['risky_attempts']),
      asDouble(j['max_risk']), asInt(j['needs_review']));

  String get displayTitle => title.isEmpty ? '#$examId' : title;
}

/// Parses the risk response; the most risky exam first (the server sorts, this keeps it stable for any order).
List<ExamRiskItem> parseRisk(Map<String, dynamic> body) {
  final items = asMapList(body['items']).map(ExamRiskItem.fromJson).toList();
  items.sort((a, b) {
    final c = b.maxRisk.compareTo(a.maxRisk);
    return c != 0 ? c : b.riskyAttempts.compareTo(a.riskyAttempts);
  });
  return items;
}

/// 0–1 share of the highest risk in the list (a bar length that never divides by zero).
double riskShare(double v, double top) => top <= 0 ? 0 : (v / top).clamp(0.0, 1.0);

String riskCodeText(String? code, String fallback) => switch (code) {
      'org_admin_required' => t('لمدير المؤسسة فقط', 'Organization admin only'),
      'forbidden' => t('ليس لديك صلاحية على تقارير الامتحانات', 'You do not have access to exam reports'),
      _ => feedbackCodeText(code, fallback),
    };

/// Entry points: the org admin tiles call these.
Route<void> orgFeedbackSettingsRoute(int orgId) => MaterialPageRoute(builder: (_) => OrgFeedbackSettingsPage(orgId: orgId));
Route<void> orgExamRiskRoute(int orgId) => MaterialPageRoute(builder: (_) => OrgExamRiskPage(orgId: orgId));

class OrgFeedbackSettingsPage extends StatefulWidget {
  const OrgFeedbackSettingsPage({super.key, required this.orgId, this.api});
  final int orgId;
  final FeedbackApi? api;

  @override
  State<OrgFeedbackSettingsPage> createState() => _OrgFeedbackSettingsPageState();
}

class _OrgFeedbackSettingsPageState extends State<OrgFeedbackSettingsPage> {
  late final FeedbackApi _api = widget.api ?? FeedbackApi();
  FeedbackSettings? _s;
  bool _loading = true, _busy = false, _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.org(widget.orgId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = r.ok ? null : (r.unavailable ? t('غير متاح على هذا الخادم بعد', 'Not available on this server yet') : riskCodeText(r.code, r.message));
      _s = r.ok ? FeedbackSettings.fromJson(r.map) : null;
    });
  }

  Future<void> _save(FeedbackDraft d) async {
    setState(() => _busy = true);
    final r = await _api.saveOrg(widget.orgId, d);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) _s = FeedbackSettings.fromJson(r.map);
    });
    if (r.ok) {
      appToast(t('تم الحفظ', 'Saved'));
    } else {
      appToast(riskCodeText(r.code, r.message), error: true);
    }
  }

  Future<void> _export(String format, String? since) async {
    setState(() => _exporting = true);
    await saveFeedbackExport(() => _api.exportOrg(widget.orgId, format: format, since: since), format, orgId: widget.orgId);
    if (mounted) setState(() => _exporting = false);
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      key: const ValueKey('org.feedback_settings'),
      useWebCard: true,
      maxWith: 800,
      appBar: ScreenAppBar(title: t('ملاحظات الامتحانات', 'Exam feedback'), actions: const [ContextExitButton()]),
      child: _loading
          ? const AppListSkeleton(items: 3, withAvatar: false)
          : _s == null
              ? AppEmpty(icon: Icons.error_outline_rounded, title: _error ?? '', actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  AppCard(child: FeedbackSettingsForm(settings: _s!, busy: _busy, onSave: _save)),
                  AppSectionTitle(t('تصدير', 'Export')),
                  AppCard(child: FeedbackExportBar(onExport: _export, busy: _exporting)),
                ]),
    );
  }
}

class OrgExamRiskPage extends StatefulWidget {
  const OrgExamRiskPage({super.key, required this.orgId, this.api});
  final int orgId;
  final FeedbackApi? api;

  @override
  State<OrgExamRiskPage> createState() => _OrgExamRiskPageState();
}

class _OrgExamRiskPageState extends State<OrgExamRiskPage> {
  late final FeedbackApi _api = widget.api ?? FeedbackApi();
  List<ExamRiskItem>? _items;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _api.risk(widget.orgId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = r.ok ? null : (r.unavailable ? t('غير متاح على هذا الخادم بعد', 'Not available on this server yet') : riskCodeText(r.code, r.message));
      _items = r.ok ? parseRisk(r.map) : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      key: const ValueKey('org.exam_risk'),
      useWebCard: true,
      maxWith: 900,
      appBar: ScreenAppBar(title: t('مخاطر الامتحانات', 'Exam risk'), actions: [
        IconButton(tooltip: t('تحديث', 'Refresh'), onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        const ContextExitButton(),
      ]),
      child: _loading
          ? const AppListSkeleton()
          : _items == null
              ? AppEmpty(icon: Icons.error_outline_rounded, title: _error ?? '', actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
              : RiskList(items: _items!),
    );
  }
}

/// The risk list (presentational): a note that these are signals for a human, then one card per exam.
class RiskList extends StatelessWidget {
  const RiskList({super.key, required this.items});
  final List<ExamRiskItem> items;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = items.fold<double>(0, (m, e) => e.maxRisk > m ? e.maxRisk : m);
    return ListView(padding: const EdgeInsets.all(16), children: [
      AppBanner(
          icon: Icons.policy_outlined,
          text: t('إشارات للمراجعة البشرية فقط — لا تعني أن الطالب غشّ.', 'Signals for human review only — they do not mean a student cheated.')),
      const SizedBox(height: 10),
      if (items.isEmpty)
        AppEmpty(icon: Icons.verified_user_outlined, title: t('لا امتحانات ذات مخاطر', 'No exams with risk signals'))
      else
        for (final e in items)
          AppCard(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14.5, w: FontWeight.w800, c: c.textDark)),
              const SizedBox(height: 8),
              AppProgressBar(value: riskShare(e.maxRisk, top) * 100, color: e.needsReview > 0 ? c.warning : c.primary),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                AppBadgePill('${t('محاولات مشبوهة', 'Risky attempts')}: ${e.riskyAttempts}', icon: Icons.flag_outlined),
                AppBadgePill('${t('أعلى درجة خطورة', 'Highest risk')}: ${e.maxRisk.toStringAsFixed(1)}', color: c.warning),
                if (e.needsReview > 0) AppBadgePill('${t('تحتاج مراجعة', 'Need review')}: ${e.needsReview}', color: c.danger, icon: Icons.rate_review_outlined),
              ]),
            ]),
          ),
    ]);
  }
}
