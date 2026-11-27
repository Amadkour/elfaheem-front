// lib/features/live/room/widgets/live_teacher_ended.dart
//
// What the teacher sees when a course class ends (Tea1Live screen=ended): "انتهى البث، الله يعطيك العافية", the
// class line, a paper card with how long it ran / who came / guests, the recording that is getting ready, the note
// that attendance was taken, and "ارجع للدورة". Plain values only (the golden and test/ui/t1_live_layout_test.dart
// pump it alone).
//
// RoomPage records a [LiveEndSummary] in [LiveEndHandoff] when the teacher ends a course class; PreJoinPage, which
// stays under the full-screen room, shows this page in its place once the room closes (live_room_host.dart's
// `closed`). Nothing else changes in the end flow (recorder drain, onEnd call, companion shutdown).
//
// Teacher motion: M10 (the card rises); no loop.
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppReveal;
import 'package:flutter_education_app/features/live/room/student/student_live_parts.dart' show StudentLiveSurface;

/// What the page needs from a finished class.
class LiveEndSummary {
  const LiveEndSummary({
    required this.title,
    required this.duration,
    required this.attended,
    this.guests = 0,
    this.recorded = false,
    this.subtitle,
  });

  /// The lesson ("المتتابعات الهندسية").
  final String title;

  /// The class line ("الرياضيات ٣ ثانوي، مجموعة أ"); null shows the lesson only.
  final String? subtitle;
  final Duration duration;

  /// Students who came (the roster's present count); guests are counted apart.
  final int attended;
  final int guests;

  /// A recording was made on this device and is being finished in the background.
  final bool recorded;
}

/// The one hand-off between the room (which ends the class) and the pre-join page (which shows the summary).
class LiveEndHandoff {
  LiveEndHandoff._();

  static LiveEndSummary? _pending;

  static void put(LiveEndSummary s) => _pending = s;

  /// The summary of the class that just ended, once.
  static LiveEndSummary? take() {
    final s = _pending;
    _pending = null;
    return s;
  }
}

/// "٥٠ د" / "١ س ٠٥ د": [d] for the stat tile, in the app's digits.
String liveDurationText(Duration d) {
  final m = d.inMinutes;
  final text = m >= 60
      ? 'lr_duration_hm'.tr.replaceAll('{h}', '${m ~/ 60}').replaceAll('{m}', '${m % 60}')
      : 'lr_duration_m'.tr.replaceAll('{m}', '${m < 1 ? 1 : m}');
  return appDigits(text);
}

class TeacherEndedView extends StatelessWidget {
  const TeacherEndedView({
    super.key,
    required this.summary,
    required this.onBack,
    this.onAddMaterials,
  });

  final LiveEndSummary summary;

  /// "ارجع للدورة".
  final VoidCallback onBack;

  /// "أضف مواد للحصة"; null hides it.
  final VoidCallback? onAddMaterials;

  @override
  Widget build(BuildContext context) => AppAreaScope.role(
        role: AppRoleAccent.teacher,
        child: StudentLiveSurface(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, box) {
                final gutter = AppSpace.gutter(box.maxWidth);
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(gutter, AppSpace.xxl, gutter, AppSpace.xl),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: AppWidth.form.max),
                      child: _body(context),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

  Widget _body(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    final s = summary;
    final line = [s.title, if ((s.subtitle ?? '').trim().isNotEmpty) s.subtitle!.trim()].join('، ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: AppDashSize.ring * 2,
            height: AppDashSize.ring * 2,
            decoration: BoxDecoration(
              color: c.heroGlass,
              borderRadius: BorderRadius.circular(AppRadius.hero),
              border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
            ),
            child: Icon(Icons.check_rounded, size: AppIconSize.hero, color: c.onHero),
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        Semantics(
          header: true,
          child: Text(
            't1_lv_end_title'.tr,
            textAlign: TextAlign.center,
            style: AppType.headline(context).copyWith(color: c.onHero),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          line,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: AppType.body(context).copyWith(color: c.onHeroMuted),
        ),
        const SizedBox(height: AppSpace.xl),
        AppReveal(
          index: 0,
          group: 'live_end',
          rise: AppSpace.xs,
          child: Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.hero)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Stats(summary: s),
                if (s.recorded) ...[
                  const SizedBox(height: AppSpace.md),
                  _RecordingRow(set: set),
                ],
                const SizedBox(height: AppSpace.md),
                Container(
                  key: const ValueKey('live_end.attendance'),
                  padding: const EdgeInsets.all(AppSpace.md),
                  decoration: BoxDecoration(color: set.tint, borderRadius: BorderRadius.circular(AppRadius.tile)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.fact_check_outlined, size: AppIconSize.md, color: set.ink),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Text(
                          appDigits('t1_lv_end_att'.tr.replaceAll('{n}', '${s.attended}')),
                          style: AppType.meta(context).copyWith(color: set.ink, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  alignment: WrapAlignment.end,
                  children: [
                    if (onAddMaterials != null)
                      AppButton.secondary(
                        key: const ValueKey('live_end.materials'),
                        label: 't1_lv_end_materials'.tr,
                        icon: Icons.attach_file_rounded,
                        size: AppButtonSize.lg,
                        onPressed: onAddMaterials,
                      ),
                    AppButton.primary(
                      key: const ValueKey('live_end.back'),
                      label: 't1_lv_end_back'.tr,
                      size: AppButtonSize.lg,
                      onPressed: onBack,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.summary});

  final LiveEndSummary summary;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      (liveDurationText(summary.duration), 't1_lv_end_len'.tr),
      (appDigits('${summary.attended}'), 't1_lv_end_came'.tr),
      (appDigits('${summary.guests}'), 't1_lv_end_guests'.tr),
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, t) in tiles.indexed) ...[
            if (i > 0) const SizedBox(width: AppSpace.sm),
            Expanded(child: _StatTile(value: t.$1, label: t.$2)),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});

  final String value, label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: c.kit.well,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(color: c.kit.line, width: AppBorder.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value, style: AppType.headline(context).copyWith(color: c.textDark)),
          ),
          const SizedBox(height: AppSpace.xxs),
          Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
        ],
      ),
    );
  }
}

class _RecordingRow extends StatelessWidget {
  const _RecordingRow({required this.set});

  final KitSet set;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      key: const ValueKey('live_end.recording'),
      children: [
        Container(
          width: AppTouch.min,
          height: AppTouch.min,
          decoration: BoxDecoration(color: c.kit.live.tint, borderRadius: BorderRadius.circular(AppRadius.tile)),
          child: Icon(Icons.fiber_manual_record_outlined, size: AppIconSize.md, color: c.kit.live.ink),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text('t1_lv_end_rec'.tr, style: AppType.row(context).copyWith(color: c.textDark)),
        ),
      ],
    );
  }
}

/// The page itself: [TeacherEndedView] with "ارجع للدورة" popping it (back to where the teacher came from).
class TeacherEndedPage extends StatelessWidget {
  const TeacherEndedPage({super.key, required this.summary});

  final LiveEndSummary summary;

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('live_ended'),
        backgroundColor: context.colors.kit.deep,
        body: TeacherEndedView(summary: summary, onBack: () => Navigator.of(context).maybePop()),
      );
}
