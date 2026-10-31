// lib/features/shared/roadmap/journey_page.dart
//
// The home journey card's page (D-120): the whole path of the student's field — what they took · the next step
// ("Your next step") · what follows — from GET /api/v1/me/journey. A course opens its page.
library;

import 'package:flutter/material.dart';

import '../../../config/theme/theme_config_provider.dart';
import '../../../design/app_kit.dart';
import '../../../utils/widget/app_navigator.dart' show AppNavigator;
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/base_page.dart';
import '../../admin/admin_common.dart' show t;
import 'roadmap_api.dart';
import 'roadmap_path.dart';

class JourneyPage extends StatefulWidget {
  const JourneyPage({super.key, this.api = const RoadmapApi()});

  final RoadmapApi api;

  @override
  State<JourneyPage> createState() => _JourneyPageState();
}

class _JourneyPageState extends State<JourneyPage> {
  Journey? _j;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final j = await widget.api.journey();
      if (mounted) setState(() => (_j = j, _loaded = true));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loaded = roadmapHiddenError(e);
        _error = _loaded ? null : t('تعذّر تحميل رحلتك', 'Could not load your journey');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final j = _j;
    return BasePage(
      key: const ValueKey(kRoadmapJourneyKey),
      appBar: ScreenAppBar(title: t('رحلتي', 'My journey')),
      child: AppRefresh(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (j != null)
              JourneyContent(journey: j, onOpenCourse: (c) => AppNavigator.openCourse(c.id))
            else if (_error != null)
              AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
            else if (_loaded)
              AppEmpty(
                icon: Icons.route_rounded,
                title: t('لا رحلة بعد', 'No journey yet'),
                message: t('أكمل كورساً أو اختر اهتماماتك ليظهر طريقك هنا.', 'Complete a course or pick your interests and your way shows here.'),
              )
            else
              const AppListSkeleton(items: 4),
          ],
        ),
      ),
    );
  }
}

/// The page's content from plain values.
class JourneyContent extends StatelessWidget {
  const JourneyContent({super.key, required this.journey, required this.onOpenCourse});

  final Journey journey;
  final ValueChanged<RmCourse> onOpenCourse;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final j = journey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(j.title, style: appText(20, w: FontWeight.w600, c: c.textDark, h: 1.3)),
        const SizedBox(height: 12),
        AppProgressBar(value: j.fraction * 100, height: 6, color: appInk(context, c.primary)),
        const SizedBox(height: 2),
        Text(j.doneLine, style: appText(13, w: FontWeight.w500, c: c.textMedium)),
        if (j.source == 'interest') ...[
          const SizedBox(height: 8),
          Text(
            t('اقتراح من اهتماماتك والكورسات التي أكملتها.', 'Suggested from your interests and the courses you completed.'),
            style: appText(13, w: FontWeight.w400, c: c.textMedium),
          ),
        ],
        const SizedBox(height: 20),
        RoadmapPathView(
          stops: j.steps.isEmpty ? [RoadmapStop(j.next, RoadmapStopRole.here)] : journeyStops(j),
          hereLabel: t('خطوتك التالية', 'Your next step'),
          onTap: onOpenCourse,
        ),
      ],
    );
  }
}
