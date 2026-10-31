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

import '../../config/theme/theme_config_provider.dart';
import '../../core/api_client.dart';
import '../../design/app_kit.dart';
import '../../design/app_notice.dart';
import '../../utils/widget/app_bar.dart';
import '../../utils/widget/base_page.dart';
import '../shared/roadmap/roadmap_api.dart';
import 'admin_common.dart' show t;

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
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await widget.api.stats(days: _days);
      if (!mounted) return;
      setState(() {
        _stats = s;
        _weights = {...s.weights};
      });
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final w = await widget.api.saveWeights(_weights);
      if (!mounted) return;
      setState(() => _weights = w);
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
    return BasePage(
      key: const ValueKey(kRecsAdminKey),
      appBar: ScreenAppBar(title: t('التوصيات', 'Recommendations')),
      child: AppRefresh(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (_error != null)
              AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
            else if (s == null)
              const AppListSkeleton(items: 5, withAvatar: false)
            else
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: RecsAdminView(
                    stats: s,
                    days: _days,
                    weights: _weights,
                    saving: _saving,
                    onDays: (d) {
                      setState(() => _days = d);
                      _load();
                    },
                    onWeight: (k, v) => setState(() => _weights = {..._weights, k: v}),
                    onReset: () => setState(() => _weights = {...s.defaults}),
                    onSave: _save,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The page's content from plain values.
class RecsAdminView extends StatelessWidget {
  const RecsAdminView({
    super.key,
    required this.stats,
    required this.days,
    required this.weights,
    required this.onDays,
    required this.onWeight,
    required this.onReset,
    required this.onSave,
    this.saving = false,
  });

  final RecStats stats;
  final int days;
  final Map<String, double> weights;
  final ValueChanged<int> onDays;
  final void Function(String key, double value) onWeight;
  final VoidCallback onReset, onSave;
  final bool saving;

  static String _pct(double v) => '${(v * 100).toStringAsFixed(v * 100 < 10 && v > 0 ? 1 : 0)}%';

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
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final d in const [7, 30, 90])
              AppChoiceChip(label: t('آخر $d يوماً', 'Last $d days'), selected: days == d, onTap: () => onDays(d)),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, box) {
            final cols = box.maxWidth >= 640 ? 4 : 2;
            final w = (box.maxWidth - 12 * (cols - 1)) / cols;
            final tiles = [
              (t('طلاب وصلتهم', 'Students reached'), '${s.students}', null),
              (t('مرات العرض', 'Shown'), '${tot.shown}', null),
              (t('فُتحت', 'Opened'), '${tot.opened}', _pct(rate(tot.opened))),
              (t('اشتراكات بعدها', 'Enrolled after'), '${tot.enrolled}', _pct(rate(tot.enrolled))),
            ];
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final (label, value, sub) in tiles)
                  SizedBox(
                    width: w,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.divider)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, w: FontWeight.w400, c: c.textMedium)),
                          const SizedBox(height: 4),
                          Text(value, style: appText(22, w: FontWeight.w600, c: c.textDark)),
                          if (sub != null) Text(sub, style: appText(12, w: FontWeight.w500, c: appInk(context, c.primary))),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        Text(t('حسب السبب', 'By reason'), style: appText(16, w: FontWeight.w600, c: c.textDark)),
        const SizedBox(height: 2),
        Text(t('السبب الذي ظهر تحت الكورس، وما فعله الطلاب بعده.', 'The reason shown under the course, and what students did next.'),
            style: appText(12.5, w: FontWeight.w400, c: c.textMedium)),
        const SizedBox(height: 10),
        if (s.byReason.isEmpty)
          Text(t('لا أرقام بعد في هذه الفترة.', 'No numbers yet for this period.'), style: appText(13, w: FontWeight.w400, c: c.textLight))
        else
          for (final r in s.byReason)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.divider)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(recReasonLabel(r.reason), style: appText(14, w: FontWeight.w600, c: c.textDark)),
                  const SizedBox(height: 4),
                  Text(
                    t(
                      'عُرض ${r.shown} · فُتح ${r.opened} (${_pct(r.openRate)}) · اشتراك ${r.enrolled} (${_pct(r.enrollRate)}) · غير مهتم ${r.dismissed}',
                      'Shown ${r.shown} · opened ${r.opened} (${_pct(r.openRate)}) · enrolled ${r.enrolled} (${_pct(r.enrollRate)}) · not interested ${r.dismissed}',
                    ),
                    style: appText(12.5, w: FontWeight.w400, c: c.textMedium),
                  ),
                  const SizedBox(height: 8),
                  AppProgressBar(value: r.openRate * 100, height: 4, color: appInk(context, c.primary)),
                ],
              ),
            ),
        const SizedBox(height: 24),
        Text(t('أوزان المحرّك', 'Engine weights'), style: appText(16, w: FontWeight.w600, c: c.textDark)),
        const SizedBox(height: 2),
        Text(
          t('كم يؤثر كل عامل في الترتيب. تُحفظ بعد ضبطها لتكون مجموعها 100٪.', 'How much each signal counts. Saved scaled to add up to 100%.'),
          style: appText(12.5, w: FontWeight.w400, c: c.textMedium),
        ),
        const SizedBox(height: 8),
        for (final k in recWeightKeys)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(flex: 4, child: Text(recWeightLabel(k), style: appText(13.5, c: c.textDark))),
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
                    style: appText(12.5, w: FontWeight.w500, c: c.textMedium),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: onReset,
              style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
              child: Text(t('الافتراضي', 'Defaults')),
            ),
            SizedBox(
              width: 160,
              child: AppPrimaryButton(label: t('حفظ', 'Save'), icon: Icons.check_rounded, busy: saving, onPressed: total > 0 ? onSave : () {}),
            ),
          ],
        ),
      ],
    );
  }
}
