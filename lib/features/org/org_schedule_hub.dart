// lib/features/org/org_schedule_hub.dart — the ONE thing to do next on a timetable.
//
//   Set up  →  Generate  →  Review & fix  →  Publish & share
//
//   TimetableJourney   pure: the stage the timetable is in and the next step, from what the provider already holds
//   NextStepBanner     what to do now, with its button
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../admin/admin_common.dart';

enum TimetableStage { setup, generate, review, publish }

/// What the next-step banner's button does — the studio maps it to the real action.
enum NextAction { addPeriods, addRooms, assignTeachers, generate, reviewResult, fixClashes, publish, share, wait }

String stageLabel(TimetableStage s) => switch (s) {
      TimetableStage.setup => t('الإعداد', 'Set up'),
      TimetableStage.generate => t('التوليد', 'Generate'),
      TimetableStage.review => t('المراجعة والإصلاح', 'Review & fix'),
      TimetableStage.publish => t('النشر والمشاركة', 'Publish & share'),
    };

IconData stageIcon(TimetableStage s) => switch (s) {
      TimetableStage.setup => Icons.tune_rounded,
      TimetableStage.generate => Icons.auto_awesome_rounded,
      TimetableStage.review => Icons.fact_check_rounded,
      TimetableStage.publish => Icons.campaign_rounded,
    };

class TimetableJourney {
  const TimetableJourney({required this.current, required this.done, required this.next, this.tone = 0});

  final TimetableStage current; // the step the timetable is on
  final Set<TimetableStage> done;
  final NextAction next;
  final int tone; // 0 info · 1 success · 2 warning · 3 danger

  /// [result]: the timetable's last generation report · [hard]: hard clashes now (validate) · [noTeacher]: courses
  /// of the timetable without a teacher · [active]: published · [running]: a generation is in progress.
  factory TimetableJourney.of({
    required int periods,
    required int rooms,
    required int noTeacher,
    required int slots,
    required Map<String, dynamic> result,
    required int hard,
    required bool active,
    bool running = false,
  }) {
    final stats = asMap(result['stats']);
    final required = stats['sessions_required'] == null ? null : asInt(stats['sessions_required']);
    final placed = stats['sessions_placed'] == null ? null : asInt(stats['sessions_placed']);
    final unplaced = required != null && placed != null ? (required - placed).clamp(0, 1 << 30) : 0;
    final pending = asMapList(result['broken']).where((x) => x.containsKey('decision') && x['decision'] == null).length;
    const all = {TimetableStage.setup, TimetableStage.generate, TimetableStage.review};
    if (active) {
      return const TimetableJourney(
          current: TimetableStage.publish, done: {...all, TimetableStage.publish}, next: NextAction.share, tone: 1);
    }
    if (running) {
      return const TimetableJourney(current: TimetableStage.generate, done: {TimetableStage.setup}, next: NextAction.wait);
    }
    if (periods == 0) return const TimetableJourney(current: TimetableStage.setup, done: {}, next: NextAction.addPeriods, tone: 2);
    if (rooms == 0) return const TimetableJourney(current: TimetableStage.setup, done: {}, next: NextAction.addRooms, tone: 2);
    if (noTeacher > 0 && slots == 0) {
      return const TimetableJourney(current: TimetableStage.setup, done: {}, next: NextAction.assignTeachers, tone: 2);
    }
    if (slots == 0 && result.isEmpty) {
      return const TimetableJourney(current: TimetableStage.generate, done: {TimetableStage.setup}, next: NextAction.generate);
    }
    const ready = {TimetableStage.setup, TimetableStage.generate};
    if (unplaced > 0 || pending > 0) return const TimetableJourney(current: TimetableStage.review, done: ready, next: NextAction.reviewResult, tone: 2);
    if (hard > 0) return const TimetableJourney(current: TimetableStage.review, done: ready, next: NextAction.fixClashes, tone: 3);
    return const TimetableJourney(current: TimetableStage.publish, done: all, next: NextAction.publish, tone: 1);
  }
}

/// The banner text for a step — counts come from the same inputs as [TimetableJourney.of].
(String, String, String) nextStepText(NextAction a, {int unplaced = 0, int hard = 0, int pending = 0, int noTeacher = 0}) => switch (a) {
      NextAction.addPeriods => (
          t('ابدأ بفترات اليوم الدراسي', 'Start with the periods of the day'),
          t('حدّد أوقات الحصص (مثل الأولى والثانية) — يُبنى عليها كل جدول.', 'Set when lessons happen (first, second …) — every timetable is built on them.'),
          t('أضف الفترات', 'Add periods')),
      NextAction.addRooms => (
          t('أضف القاعات والمعامل', 'Add your rooms and labs'),
          t('سعة كل مكان ونوعه يحددان أين تُعقد كل حصة.', 'Each room\'s size and kind decide where every session can go.'),
          t('أضف مكاناً', 'Add a room')),
      NextAction.assignTeachers => (
          t('$noTeacher مقرر بلا مدرس', '$noTeacher course(s) have no teacher'),
          t('المقرر بلا مدرس لا يُجدول أبداً. عيّن المدرسين من "المقررات والهيئة".', 'A course without a teacher is never scheduled. Assign teachers in "Courses & staff".'),
          t('عيّن المدرسين', 'Assign teachers')),
      NextAction.generate => (
          t('كل شيء جاهز للتوليد', 'Everything is ready to generate'),
          t('سيضع النظام كل الحصص دون أي حجز مزدوج، ويحترم الأوقات المتاحة قدر الإمكان.', 'The system places every session with no double booking and respects availability wherever it can.'),
          t('ولّد الجدول', 'Generate the timetable')),
      NextAction.reviewResult => (
          unplaced > 0
              ? t('$unplaced حصة بلا موعد', '$unplaced session(s) unplaced')
              : t('$pending اقتراح بانتظار قرارك', '$pending proposal(s) await your decision'),
          t('راجع سبب كل حصة والحل المقترح، واقبل أو ارفض كل قاعدة مرنة كُسرت.', 'See why each session is unplaced and the suggested fix; accept or reject every flexible rule that was broken.'),
          t('راجع النتيجة', 'Review the result')),
      NextAction.fixClashes => (
          t('$hard تعارض يجب حله قبل النشر', '$hard clash(es) to fix before publishing'),
          t('اطّلع على كل تعارض واختر الحل المقترح أو انقل الحصة بالسحب.', 'Open each clash and pick a suggested fix, or drag the session elsewhere.'),
          t('اعرض التعارضات', 'Show the clashes')),
      NextAction.publish => (
          t('الجدول جاهز للنشر', 'The timetable is ready to publish'),
          t('كل الحصص في أماكنها ولا تعارضات. بعد النشر يراه المدرسون والطلاب.', 'Every session is placed with no clashes. Once published, teachers and students see it.'),
          t('انشر الجدول', 'Publish')),
      NextAction.share => (
          t('الجدول منشور', 'The timetable is published'),
          t('صدّره (إكسل · وورد · PDF) أو وزّع نسخة لكل مدرس ومجموعة. لتعديله أوقف النشر أولاً.', 'Export it (Excel · Word · PDF) or send each teacher and group their copy. To edit it, unpublish first.'),
          t('صدّر وشارك', 'Export & share')),
      NextAction.wait => (
          t('جارٍ التوليد…', 'Generating…'),
          t('يمكنك متابعة العمل؛ سيظهر الجدول هنا عند الانتهاء.', 'You can keep working; the timetable appears here when it is done.'),
          ''),
    };

class NextStepBanner extends StatelessWidget {
  const NextStepBanner({super.key, required this.title, required this.body, required this.action, required this.tone, this.onAction, this.secondary, this.onSecondary, this.secondaryIcon = Icons.auto_fix_high_rounded});
  final String title, body, action;
  final int tone;
  final VoidCallback? onAction;

  /// An optional second way (e.g. "Fix automatically" next to "Review the result").
  final String? secondary;
  final VoidCallback? onSecondary;
  final IconData secondaryIcon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = switch (tone) { 1 => c.success, 2 => c.warning, 3 => c.danger, _ => c.primary };
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: col.withValues(alpha: 0.35)),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final text = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(t('الخطوة التالية', 'Next step'), style: AppType.overline(context).copyWith(color: col)),
          const SizedBox(height: AppSpace.xxs / 2),
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
          const SizedBox(height: AppSpace.xxs / 2),
          Text(body, style: AppType.label(context).copyWith(color: c.textMedium)),
        ]);
        final button = action.isEmpty || onAction == null
            ? null
            : AppPrimaryButton(label: action, icon: Icons.arrow_forward_rounded, onPressed: onAction);
        final second = secondary == null || onSecondary == null
            ? null
            : OutlinedButton.icon(onPressed: onSecondary, icon: Icon(secondaryIcon, size: AppIconSize.md), label: Text(secondary!, maxLines: 1, overflow: TextOverflow.ellipsis));
        // AppPrimaryButton fills its width: it always sits in a bounded box
        final buttons = Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (second != null) second,
          if (button != null) ConstrainedBox(constraints: const BoxConstraints(maxWidth: 260, minWidth: 160), child: button),
        ]);
        if (box.maxWidth < 560 || (button == null && second == null)) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.flag_rounded, color: col),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: text),
            ]),
            if (button != null || second != null) ...[const SizedBox(height: AppSpace.sm), Align(alignment: AlignmentDirectional.centerEnd, child: buttons)],
          ]);
        }
        return Row(children: [
          Icon(Icons.flag_rounded, color: col),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: text),
          const SizedBox(width: AppSpace.sm),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: buttons),
        ]);
      }),
    );
  }
}
