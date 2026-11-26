// lib/features/admin/admin_recs_page.dart
//
// The super admin's "Recommendations" page (D-120): how the "Recommended for you" lists do — students reached, shown,
// opened, dismissed and the enrolments that followed, per reason ("Because you completed…", "Students like you" …)
// over 7 / 30 / 90 days — and the four weights of the engine (similar students · field, topics and level · same
// instructor · popularity), saved normalized; every student's list is rebuilt on their next visit.
//   GET /api/v1/admin/recommendations/stats?days · PUT /api/v1/admin/recommendations/settings
// Kill switch `admin.recommendations`. [RecsAdminView] draws plain values (test/ui/roadmap_layout_test.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart' show Trans;

import '../../config/theme/theme_config_provider.dart';
import '../../core/api_client.dart';
import '../../design/app_kit.dart';
import 'admin_page.dart';
import 'cfg_common.dart';
import 'package:flutter_education_app/features/courses/roadmap/roadmap_api.dart';
import 'admin_common.dart' show t;
import 'sup/sup_kit.dart';

class AdminRecommendationsPage extends StatefulWidget {
  const AdminRecommendationsPage({super.key, this.api = const RoadmapApi()});

  final RoadmapApi api;

  @override
  State<AdminRecommendationsPage> createState() => _AdminRecommendationsPageState();
}

class _AdminRecommendationsPageState extends State<AdminRecommendationsPage> {
  int _days = 30;
  RecStats? _stats;
  Map<String, double> _weights = {};
  Map<String, double> _saved = {}; // what the server holds: the baseline of the unsaved-changes guard
  Object? _error;
  bool _saving = false;
  bool _loadingStats = false;

  bool get _dirty {
    for (final k in recWeightKeys) {
      if ((_weights[k] ?? 0) != (_saved[k] ?? 0)) return true;
    }
    return false;
  }

  double get _total => _weights.values.fold<double>(0, (a, b) => a + b);

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// First load / pull-to-refresh: stats AND the weights (a refresh while the weights are edited asks first).
  Future<void> _load() async {
    if (_stats != null && _dirty) {
      final ok = await appConfirm(context,
          message: t('لديك أوزان لم تُحفظ. التحديث سيتجاهلها. متابعة؟', 'You have unsaved weights. Refreshing discards them. Continue?'));
      if (!ok || !mounted) return;
    }
    await _fetch(takeWeights: true);
  }

  /// Switching 7 / 30 / 90 days reloads the statistics only: the weights being edited stay.
  Future<void> _setDays(int d) async {
    if (d == _days || _loadingStats) return;
    final prev = _days;
    setState(() => _days = d);
    final ok = await _fetch(takeWeights: false);
    if (!ok && mounted) setState(() => _days = prev);
  }

  Future<bool> _fetch({required bool takeWeights}) async {
    setState(() {
      _loadingStats = true;
      if (_stats == null) _error = null;
    });
    try {
      final s = await widget.api.stats(days: _days);
      if (!mounted) return false;
      setState(() {
        _stats = s;
        _error = null;
        if (takeWeights || _saved.isEmpty) {
          _weights = {...s.weights};
          _saved = {...s.weights};
        }
      });
      return true;
    } catch (e) {
      if (mounted) {
        // a failed reload keeps the numbers that are on screen
        if (_stats == null) {
          setState(() => _error = ApiException.from(e));
        } else {
          showAppNotice(ApiException.from(e).message, error: true);
        }
      }
      return false;
    } finally {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _total <= 0) return;
    setState(() => _saving = true);
    try {
      final w = await widget.api.saveWeights(_weights);
      if (!mounted) return;
      setState(() {
        _weights = w;
        _saved = {...w};
      });
      showAppNotice(t('تم الحفظ — تُحدَّث قوائم الطلاب في زيارتهم التالية', 'Saved — students’ lists refresh on their next visit'));
    } catch (e) {
      showAppNotice(ApiException.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    return SupPage(
        kicker: 'a2_recs_kicker'.tr, headline: 'a2_recs_head'.tr,
        key: const ValueKey(kRecsAdminKey),
        title: t('التوصيات', 'Recommendations'),
        onRefresh: _load,
        dirty: _dirty,
        body: _error != null && s == null
          ? cfgErrorState(_error, onRetry: _load)
          : s == null
              ? const AppListSkeleton(items: 5, withAvatar: false)
              : AppRefresh(
                  onRefresh: _load,
                  child: ListView(
                    padding: AdminPage.bodyPadding(context),
                    children: [
                      RecsAdminView(
                        stats: s,
                        days: _days,
                        weights: _weights,
                        saving: _saving,
                        loadingStats: _loadingStats,
                        onDays: _setDays,
                        onWeight: (k, v) => setState(() => _weights = {..._weights, k: v}),
                        onReset: () => setState(() => _weights = {...s.defaults}),
                      ),
                    ],
                  ),
                ),
        actions: [?(s == null
          ? null
          : cfgSaveButton(dirty: _dirty, busy: _saving, enabled: _total > 0, onSave: _save))],
      );
  }
}

/// The page's content from plain values. [onSave] (optional) draws a Save button under the weights; the page itself
/// puts Save in its header instead.
class RecsAdminView extends StatelessWidget {
  const RecsAdminView({
    super.key,
    required this.stats,
    required this.days,
    required this.weights,
    required this.onDays,
    required this.onWeight,
    required this.onReset,
    this.onSave,
    this.saving = false,
    this.loadingStats = false,
  });

  final RecStats stats;
  final int days;
  final Map<String, double> weights;
  final ValueChanged<int> onDays;
  final void Function(String key, double value) onWeight;
  final VoidCallback onReset;
  final VoidCallback? onSave;
  final bool saving;

  /// The statistics of another period are loading (the numbers on screen stay, dimmed).
  final bool loadingStats;

  static String _pct(double v) => '${(v * 100).toStringAsFixed(v * 100 < 10 && v > 0 ? 1 : 0)}%';

  static String _weightHelp(String k) => switch (k) {
        'similar_students' => t('ما درسه طلاب يشبهونه في الاهتمامات والمسار.', 'What students with similar interests and paths took.'),
        'content' => t('قرب المجال والمواضيع والمستوى من اهتمامات الطالب.', 'How close the field, topics and level are to the student’s interests.'),
        'same_teacher' => t('كورسات مدرّسين سبق للطالب أن درس معهم.', 'Courses by instructors the student already learned from.'),
        _ => t('الكورسات الأكثر اشتراكاً هذه الفترة.', 'The courses most students enrolled in lately.'),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = stats;
    final total = weights.values.fold<double>(0, (a, b) => a + b);
    final tot = s.total;
    double rate(int n) => tot.shown == 0 ? 0 : n / tot.shown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xs,
          children: [
            for (final d in const [7, 30, 90])
              AppChoiceChip(label: t('آخر $d يوماً', 'Last $d days'), selected: days == d, onTap: () => onDays(d)),
          ],
        ),
        AppSpace.gapMd,
        Opacity(
          opacity: loadingStats ? 0.5 : 1,
          child: AppKpiGrid(children: [
            AppStatCard(label: t('طلاب وصلتهم', 'Students reached'), value: '${s.students}', icon: Icons.groups_rounded),
            AppStatCard(label: t('مرات العرض', 'Shown'), value: '${tot.shown}', icon: Icons.visibility_rounded),
            AppStatCard(
                label: t('فُتحت', 'Opened'),
                value: '${tot.opened}',
                footer: _pct(rate(tot.opened)),
                icon: Icons.touch_app_rounded),
            AppStatCard(
                label: t('اشتراكات بعدها', 'Enrolled after'),
                value: '${tot.enrolled}',
                footer: _pct(rate(tot.enrolled)),
                icon: Icons.how_to_reg_rounded),
          ]),
        ),
        AppSpace.gapLg,
        AppSection(
          title: t('حسب السبب', 'By reason'),
          subtitle: t('السبب الذي ظهر تحت الكورس، وما فعله الطلاب بعده.', 'The reason shown under the course, and what students did next.'),
          child: s.byReason.isEmpty
              ? Text(t('لا أرقام بعد في هذه الفترة.', 'No numbers yet for this period.'), style: AppType.body(context).copyWith(color: c.textLight))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final r in s.byReason)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.xs),
                      child: AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(recReasonLabel(r.reason), style: AppType.label(context)),
                            const SizedBox(height: AppSpace.xxs),
                            Text(
                              t(
                                'عُرض ${r.shown} · فُتح ${r.opened} (${_pct(r.openRate)}) · اشتراك ${r.enrolled} (${_pct(r.enrollRate)}) · غير مهتم ${r.dismissed}',
                                'Shown ${r.shown} · opened ${r.opened} (${_pct(r.openRate)}) · enrolled ${r.enrolled} (${_pct(r.enrollRate)}) · not interested ${r.dismissed}',
                              ),
                              style: AppType.meta(context),
                            ),
                            AppSpace.gapXs,
                            AppProgressBar(value: r.openRate * 100, height: 4, color: appInk(context, c.primary)),
                          ],
                        ),
                      ),
                    ),
                ]),
        ),
        AppSpace.gapLg,
        AppSection(
          title: t('أوزان المحرّك', 'Engine weights'),
          subtitle: t('كم يؤثر كل عامل في الترتيب. تُحفظ بعد ضبطها لتكون مجموعها 100٪.', 'How much each signal counts. Saved scaled to add up to 100%.'),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final k in recWeightKeys)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.xs),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(
                      children: [
                        Expanded(flex: 4, child: Text(recWeightLabel(k), style: AppType.label(context))),
                        Expanded(
                          flex: 6,
                          child: Slider(
                            value: (weights[k] ?? 0).clamp(0, 1).toDouble(),
                            divisions: 20,
                            label: _pct(weights[k] ?? 0),
                            semanticFormatterCallback: (v) => '${recWeightLabel(k)} ${_pct(v)}',
                            onChanged: (v) => onWeight(k, v),
                          ),
                        ),
                        SizedBox(
                          width: 52,
                          child: Text(
                            total == 0 ? '0%' : _pct((weights[k] ?? 0) / total),
                            textAlign: TextAlign.end,
                            style: AppType.label(context).copyWith(color: c.textMedium),
                          ),
                        ),
                      ],
                    ),
                    Text(_weightHelp(k), style: AppType.meta(context)),
                  ]),
                ),
              if (total <= 0)
                AppBanner(
                    icon: Icons.warning_amber_rounded,
                    color: c.warning,
                    text: t('كل الأوزان صفر — ارفع وزناً واحداً على الأقل ليمكن الحفظ.', 'Every weight is 0 — raise at least one to be able to save.')),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: [
                  // neutral ink: the brand teal on the dark card is under 4.5:1
                  TextButton.icon(
                      onPressed: onReset,
                      style: TextButton.styleFrom(foregroundColor: c.textDark, minimumSize: const Size(AppTouch.min, AppTouch.min)),
                      icon: const Icon(Icons.restart_alt_rounded, size: AppIconSize.md),
                      label: Text(t('الافتراضي', 'Defaults'))),
                  if (onSave != null)
                    AppButton.primary(label: t('حفظ', 'Save'), icon: Icons.check_rounded, busy: saving, onPressed: total > 0 && !saving ? onSave : null),
                ],
              ),
            ]),
          ),
        ),
      ],
    );
  }
}
