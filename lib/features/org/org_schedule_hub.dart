// lib/features/org/org_schedule_hub.dart — the timetable as one guided journey.
//
//   Set up  →  Generate  →  Review & fix  →  Publish & share
//
// A first-time organization admin sees where the timetable stands, the ONE thing to do next (a banner with its
// button), and only the tools of the step they are on; every other tool stays one tap away in "More".
//
//   TimetableJourney   pure: the stage each step is in and the next step, from what the provider already holds
//   TimetableStepper   the four steps (tap one to see its tools)        NextStepBanner   what to do now
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../admin/admin_common.dart';
import 'org_ui.dart';

enum TimetableStage { setup, generate, review, publish }

/// What the next-step banner's button does — the studio maps it to the real action.
enum NextAction { addPeriods, addRooms, assignTeachers, generate, completeCoverage, fixClashes, compareRules, publish, share, wait }

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
    final broken = asMapList(result['broken']).length;
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
    if (unplaced > 0) return const TimetableJourney(current: TimetableStage.review, done: ready, next: NextAction.completeCoverage, tone: 2);
    if (hard > 0) return const TimetableJourney(current: TimetableStage.review, done: ready, next: NextAction.fixClashes, tone: 3);
    if (broken > 0) return const TimetableJourney(current: TimetableStage.publish, done: all, next: NextAction.compareRules);
    return const TimetableJourney(current: TimetableStage.publish, done: all, next: NextAction.publish, tone: 1);
  }
}

/// The banner text for a step — counts come from the same inputs as [TimetableJourney.of].
(String, String, String) nextStepText(NextAction a, {int unplaced = 0, int hard = 0, int broken = 0, int noTeacher = 0}) => switch (a) {
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
      NextAction.completeCoverage => (
          t('$unplaced حصة تحتاج موعداً', '$unplaced session(s) still need a time'),
          t('"التوليد حتى الاكتمال" يجرّب ويقترح حلولاً حتى توضع كل الحصص — وتوافق أنت على كل خطوة.', '"Generate until complete" keeps trying and suggesting fixes until every session is placed — you approve each step.'),
          t('أكمل الجدول', 'Complete the timetable')),
      NextAction.fixClashes => (
          t('$hard تعارض يجب حله قبل النشر', '$hard clash(es) to fix before publishing'),
          t('اطّلع على كل تعارض واختر الحل المقترح أو انقل الحصة بالسحب.', 'Open each clash and pick a suggested fix, or drag the session elsewhere.'),
          t('اعرض التعارضات', 'Show the clashes')),
      NextAction.compareRules => (
          t('الجدول مكتمل بكسر $broken قاعدة', 'Complete, with $broken rule(s) bent'),
          t('يمكنك النشر الآن، أو مقارنة بدائل تكسر قاعدة واحدة فقط لاختيار الأنسب.', 'You can publish now, or compare alternatives that bend one rule only and pick the best.'),
          t('قارن البدائل', 'Compare alternatives')),
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

class TimetableStepper extends StatelessWidget {
  const TimetableStepper({super.key, required this.journey, required this.selected, required this.onSelect});
  final TimetableJourney journey;
  final TimetableStage selected;
  final ValueChanged<TimetableStage> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      final narrow = box.maxWidth < 520;
      return Row(children: [
        for (final s in TimetableStage.values) ...[
          if (s.index > 0)
            Container(width: narrow ? 6 : 14, height: 2, color: journey.done.contains(TimetableStage.values[s.index - 1]) ? c.success : c.divider),
          Expanded(
            child: Semantics(
              button: true,
              selected: s == selected,
              label: stageLabel(s),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onSelect(s),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: narrow ? 4 : 10),
                  decoration: BoxDecoration(
                    color: s == selected ? c.primary.withValues(alpha: 0.10) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: s == selected ? c.primary : Colors.transparent),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    _Dot(stage: s, done: journey.done.contains(s), current: journey.current == s),
                    const SizedBox(height: 4),
                    Text('${s.index + 1}. ${stageLabel(s)}',
                        maxLines: narrow ? 2 : 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: orgText(context, size: narrow ? 10.5 : 12, w: s == selected || journey.current == s ? FontWeight.w800 : FontWeight.w600,
                            color: journey.current == s ? c.primary : c.textMedium)),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ]);
    });
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.stage, required this.done, required this.current});
  final TimetableStage stage;
  final bool done, current;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = done ? c.success : current ? c.primary : c.textLight;
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done || current ? col.withValues(alpha: 0.14) : Colors.transparent,
        border: Border.all(color: col, width: current ? 2 : 1.2),
      ),
      child: Icon(done ? Icons.check_rounded : stageIcon(stage), size: 16, color: col),
    );
  }
}

class NextStepBanner extends StatelessWidget {
  const NextStepBanner({super.key, required this.title, required this.body, required this.action, required this.tone, this.onAction});
  final String title, body, action;
  final int tone;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = switch (tone) { 1 => c.success, 2 => c.warning, 3 => c.danger, _ => c.primary };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: col.withValues(alpha: 0.35)),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final text = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(t('الخطوة التالية', 'Next step'), style: orgText(context, size: 11, w: FontWeight.w800, color: col)),
          const SizedBox(height: 2),
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: orgText(context, size: 15, w: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(body, style: orgText(context, size: 12.5, color: c.textMedium)),
        ]);
        final button = action.isEmpty || onAction == null
            ? null
            : AppPrimaryButton(label: action, icon: Icons.arrow_forward_rounded, onPressed: onAction);
        if (box.maxWidth < 560 || button == null) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.flag_rounded, color: col),
              const SizedBox(width: 10),
              Expanded(child: text),
            ]),
            if (button != null) ...[const SizedBox(height: 10), Align(alignment: AlignmentDirectional.centerEnd, child: button)],
          ]);
        }
        return Row(children: [
          Icon(Icons.flag_rounded, color: col),
          const SizedBox(width: 10),
          Expanded(child: text),
          const SizedBox(width: 12),
          // AppPrimaryButton fills its width: an unbounded Row slot would throw
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 260), child: button),
        ]);
      }),
    );
  }
}

/// One tool of the studio, shown under the step it belongs to.
class StudioAction {
  const StudioAction(this.stage, this.icon, this.label, this.onPressed, {this.color, this.busy = false});
  final TimetableStage stage;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final bool busy;
}

/// The selected step's tools as chips + "More" with every other step's tools (nothing is ever out of reach).
class StudioActionBar extends StatelessWidget {
  const StudioActionBar({super.key, required this.actions, required this.stage});
  final List<StudioAction> actions;
  final TimetableStage stage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final here = actions.where((a) => a.stage == stage).toList();
    final rest = actions.where((a) => a.stage != stage).toList();
    return Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (final a in here)
        ActionChip(
          avatar: a.busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(a.icon, size: 18, color: a.onPressed == null ? c.textLight : (a.color ?? c.primary)),
          label: Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          onPressed: a.onPressed,
        ),
      if (here.isEmpty) Text(t('لا أدوات في هذه الخطوة الآن', 'No tools for this step right now'), style: orgText(context, size: 12, color: c.textMedium)),
      if (rest.isNotEmpty)
        PopupMenuButton<int>(
          tooltip: t('كل الأدوات', 'All tools'),
          onSelected: (i) => rest[i].onPressed?.call(),
          itemBuilder: (_) => [
            for (var i = 0; i < rest.length; i++)
              PopupMenuItem<int>(
                value: i,
                enabled: rest[i].onPressed != null,
                child: Row(children: [
                  Icon(rest[i].icon, size: 18, color: rest[i].color ?? c.primary),
                  const SizedBox(width: 10),
                  Flexible(child: Text(rest[i].label, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  Text(stageLabel(rest[i].stage), style: orgText(context, size: 10.5, color: c.textLight)),
                ]),
              ),
          ],
          child: Chip(avatar: Icon(Icons.more_horiz_rounded, size: 18, color: c.textMedium), label: Text(t('المزيد', 'More'))),
        ),
    ]);
  }
}
