// lib/features/self_learning/self_learning_page.dart — the student's daily learning (Learning Hub v2 §5, D-1601,
// D-1603; kill switch `student_tab_self_learning`):
//
//   SelfLearningSection(subjects:)  the section at the top of the Quran tab (quran / tajweed / fiqh) and the Nahw tab
//                                   (nahw): the progress ring, today's first lesson and the review questions, and
//                                   "See all". Nothing at all while the admin has it off, for a guest, or on an error
//                                   (the tab's own content comes first); an invitation row while the student has it off
//   SelfLearningPage                "My daily learning" (route /learn/daily, a push tap): the control, progress per
//                                   subject, every lesson of today and the review round
//   SlDailyView                     the page's body over plain values (test/ui/self_learning_test.dart)
//   SlReviewRunner                  one review round over a list (SlReviewSession): answer → feedback → next
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart' show Trans;
import 'package:flutter_education_app/features/profile/sd_area.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/guest/guest_state.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import 'sl_api.dart';
import 'sl_models.dart';
import 'sl_review_session.dart';
import 'sl_store.dart';
import 'sl_widgets.dart';

String slReviewsText(int n) => countText(n,
    ar1: 'سؤال مراجعة واحد',
    ar2: 'سؤالا مراجعة',
    arFew: '$n أسئلة مراجعة',
    arMany: '$n سؤال مراجعة',
    en1: '1 review question',
    en: '$n review questions');

/// Opens the daily learning page (the section's "See all", AppNavigator's push target).
Future<void> openSelfLearning(BuildContext context, {SlStore? store}) => Navigator.of(context).push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/learn/daily'),
      builder: (_) => SelfLearningPage(store: store),
    ));

// ═════════════════════════════════════════════════════════════════════════════
//  The review round
// ═════════════════════════════════════════════════════════════════════════════

/// One review round over [items]: the card of the current question, then [done] once every one is answered.
class SlReviewRunner extends StatefulWidget {
  const SlReviewRunner({super.key, required this.items, required this.submit, this.onReviewed, this.done});

  final List<SlItem> items;
  final SlSubmit submit;

  /// After Next: the item and whether it was right (the store drops it from today's list).
  final void Function(SlItem item, bool right)? onReviewed;

  /// Drawn when the round is over (nothing by default).
  final Widget? done;

  @override
  State<SlReviewRunner> createState() => _SlReviewRunnerState();
}

class _SlReviewRunnerState extends State<SlReviewRunner> {
  late SlReviewSession _s = SlReviewSession(items: widget.items, submit: widget.submit);

  @override
  void initState() {
    super.initState();
    _s.addListener(_changed);
  }

  @override
  void didUpdateWidget(SlReviewRunner old) {
    super.didUpdateWidget(old);
    // a fresh list (a reload) restarts a round that has not been touched yet
    final ids = [for (final i in widget.items) i.id].join(','), was = [for (final i in old.items) i.id].join(',');
    if (ids != was && _s.index == 0 && _s.right == null) {
      _s.removeListener(_changed);
      _s.dispose();
      _s = SlReviewSession(items: widget.items, submit: widget.submit)..addListener(_changed);
    }
  }

  @override
  void dispose() {
    _s.removeListener(_changed);
    _s.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _next() {
    final item = _s.current;
    final right = _s.right ?? false;
    _s.next();
    if (item != null) widget.onReviewed?.call(item, right);
  }

  @override
  Widget build(BuildContext context) {
    final item = _s.current;
    if (item == null) return widget.done ?? const SizedBox.shrink();
    final last = _s.index + 1 >= _s.total;
    return SlReviewCard(
      key: ValueKey('sl.runner.${item.id}'),
      item: item,
      picked: _s.picked,
      right: _s.right,
      explanation: _s.explanation,
      queued: _s.queued,
      error: _s.error,
      index: _s.index,
      total: _s.total,
      onPick: _s.answer,
      onNext: _next,
      nextLabel: last ? t('تم', 'Done') : t('التالي', 'Next'),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The tab section
// ═════════════════════════════════════════════════════════════════════════════

class SelfLearningSection extends StatefulWidget {
  const SelfLearningSection({super.key, required this.subjects, this.store});

  /// The subjects this tab shows.
  final Set<String> subjects;
  final SlStore? store;

  @override
  State<SelfLearningSection> createState() => _SelfLearningSectionState();
}

class _SelfLearningSectionState extends State<SelfLearningSection> {
  late final SlStore _store = widget.store ?? SlStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_changed);
    if (!slOff() && !GuestState.active) _store.load();
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _gotIt(SlItem item) async {
    final err = await _store.gotIt(item);
    if (err != null) showAppNotice(err, error: true);
  }

  @override
  Widget build(BuildContext context) {
    if (slOff() || GuestState.active) return const SizedBox.shrink();
    final all = _store.state;
    if (all == null) {
      return _store.loading
          ? const Padding(padding: EdgeInsets.only(bottom: AppSpace.md), child: AppListSkeleton(items: 1, padding: EdgeInsets.zero))
          : const SizedBox.shrink();
    }
    if (!all.available) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: SlTodaySection(
        state: all.forSubjects(widget.subjects),
        busyLessons: {for (final l in all.lessons) if (_store.seenBusy(l.id)) l.id},
        onGotIt: _gotIt,
        submit: (id, choice, clientId) => _store.api.review(id, choice: choice, clientId: clientId),
        onReviewed: (item, right) => _store.reviewed(item, right: right),
        onSeeAll: () => openSelfLearning(context, store: widget.store),
      ),
    );
  }
}

/// The section over plain values: a header with the ring, today's first lesson, the review round, "See all".
class SlTodaySection extends StatelessWidget {
  const SlTodaySection({
    super.key,
    required this.state,
    required this.submit,
    this.busyLessons = const {},
    this.onGotIt,
    this.onReviewed,
    this.onSeeAll,
  });

  final SlState state;
  final Set<int> busyLessons;
  final ValueChanged<SlItem>? onGotIt;
  final SlSubmit submit;
  final void Function(SlItem item, bool right)? onReviewed;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (!state.enabled) {
      if (!state.canToggle) return const SizedBox.shrink();
      return AppActionCard(
        key: const ValueKey('sl.invite'),
        icon: Icons.auto_stories_rounded,
        title: t('الدروس اليومية', 'Daily lessons'),
        subtitle: t('درس قصير أو سؤال مراجعة بضع مرات في اليوم. شغّلها من هنا.',
            'A short lesson or a review question a few times a day. Switch them on here.'),
        onTap: onSeeAll,
      );
    }
    final lesson = state.lessons.isEmpty ? null : state.lessons.first;
    final reviews = [for (final r in state.reviews) if (r.question?.valid == true) r];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        padding: AppSpace.card,
        onTap: onSeeAll,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(t('تعلّمي اليومي', 'My daily learning'), style: AppType.section(context))),
            if (onSeeAll != null) Icon(Icons.chevron_right_rounded, size: AppIconSize.md, color: c.textLight),
          ]),
          AppSpace.gapSm,
          SlProgressRing(progress: state.progress, compact: true),
          if (lesson == null && reviews.isEmpty) ...[
            AppSpace.gapSm,
            Text(t('لا جديد الآن. يصلك الدرس التالي لاحقاً اليوم.', 'Nothing new right now. The next one comes later today.'),
                style: AppType.meta(context)),
          ],
        ]),
      ),
      if (lesson != null) ...[
        AppSpace.gapSm,
        SlLessonCard(item: lesson, short: true, busy: busyLessons.contains(lesson.id), onGotIt: onGotIt == null ? null : () => onGotIt!(lesson)),
      ],
      if (reviews.isNotEmpty) ...[
        AppSpace.gapSm,
        SlReviewRunner(items: reviews, submit: submit, onReviewed: onReviewed),
      ],
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The page
// ═════════════════════════════════════════════════════════════════════════════

class SelfLearningPage extends StatefulWidget {
  const SelfLearningPage({super.key, this.store});

  final SlStore? store;

  @override
  State<SelfLearningPage> createState() => _SelfLearningPageState();
}

class _SelfLearningPageState extends State<SelfLearningPage> {
  late final SlStore _store = widget.store ?? SlStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_changed);
    _store.load(force: true);
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _prefs({bool? enabled, List<String>? subjects}) async {
    final s = _store.state;
    if (s == null) return;
    final err = await _store.setPrefs(
        enabled: enabled ?? s.enabled, subjects: subjects ?? (s.subjects.isEmpty ? [...kSlSubjects] : s.subjects));
    if (err != null) showAppNotice(err, error: true);
  }

  Future<void> _gotIt(SlItem item) async {
    final err = await _store.gotIt(item);
    if (err != null) showAppNotice(err, error: true);
  }

  @override
  Widget build(BuildContext context) {
    final s = _store.state;
    return SdArea(area: AppArea.quran, child: BasePage(
      width: AppWidth.reading,
      appBar: ScreenAppBar(title: t('تعلّمي اليومي', 'My daily learning')),
      child: SdHeroColumn(title: 'sd_h_daily'.tr, subtitle: 'sd_h_daily_d'.tr, icon: Icons.today_rounded, child: SafeArea(
        child: AppRefresh(
          onRefresh: () => _store.load(force: true),
          child: SlDailyView(
            state: s,
            error: s == null ? _store.error : null,
            onRetry: () => _store.load(force: true),
            saving: _store.saving,
            busyLessons: {for (final l in s?.lessons ?? const <SlItem>[]) if (_store.seenBusy(l.id)) l.id},
            onEnabled: (v) => _prefs(enabled: v),
            onSubjects: (v) => _prefs(subjects: v),
            onGotIt: _gotIt,
            submit: (id, choice, clientId) => _store.api.review(id, choice: choice, clientId: clientId),
            onReviewed: (item, right) => _store.reviewed(item, right: right),
          ),
        ),
      )),
    ));
  }
}

/// The page body over plain values.
class SlDailyView extends StatelessWidget {
  const SlDailyView({
    super.key,
    required this.state,
    required this.submit,
    this.error,
    this.onRetry,
    this.saving = false,
    this.busyLessons = const {},
    this.onEnabled,
    this.onSubjects,
    this.onGotIt,
    this.onReviewed,
  });

  /// null = loading.
  final SlState? state;
  final String? error;
  final VoidCallback? onRetry;
  final bool saving;
  final Set<int> busyLessons;
  final ValueChanged<bool>? onEnabled;
  final ValueChanged<List<String>>? onSubjects;
  final ValueChanged<SlItem>? onGotIt;
  final SlSubmit submit;
  final void Function(SlItem item, bool right)? onReviewed;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final children = <Widget>[];
    if (s == null) {
      children.add(error != null ? AppErrorState(message: error, onRetry: onRetry) : const AppListSkeleton(items: 3, padding: EdgeInsets.zero));
    } else if (!s.available) {
      children.add(const SlOffState());
    } else {
      final subjects = s.subjects.isEmpty ? kSlSubjects : s.subjects;
      children.add(SlSettingsCard(
        enabled: s.enabled,
        subjects: subjects,
        canToggle: s.canToggle,
        busy: saving,
        onEnabled: onEnabled,
        onSubjects: onSubjects,
      ));
      if (!s.enabled) {
        children.addAll([
          if (s.canToggle) AppSpace.gapMd,
          AppEmpty(
            key: const ValueKey('sl.paused'),
            icon: Icons.notifications_paused_rounded,
            title: t('الدروس اليومية متوقفة عندك', 'Your daily lessons are off'),
            message: s.canToggle
                ? t('شغّلها من الأعلى ليصلك درس قصير أو سؤال مراجعة بضع مرات في اليوم.',
                    'Switch them on above to get a short lesson or a review question a few times a day.')
                : t('تديرها إدارة المنصة أو مدرستك.', 'The platform or your school manages them.'),
          ),
        ]);
      } else {
        if (s.canToggle) children.add(AppSpace.gapMd);
        children.add(AppCard(
          padding: AppSpace.card,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('تقدّمي', 'My progress'), style: AppType.section(context)),
            AppSpace.gapSm,
            SlProgressRing(progress: s.progress),
            AppSpace.gapMd,
            SlSubjectBars(progress: s.progress, subjects: subjects),
          ]),
        ));
        final reviews = [for (final r in s.reviews) if (r.question?.valid == true) r];
        if (s.lessons.isEmpty && reviews.isEmpty) {
          children.addAll([
            AppSpace.gapMd,
            AppEmpty(
              key: const ValueKey('sl.caught_up'),
              icon: Icons.task_alt_rounded,
              title: t('أنهيت ما لديك الآن', "You're all caught up"),
              message: t('يصلك الدرس التالي لاحقاً اليوم، في أوقات النشاط.', 'The next one comes later today, during active hours.'),
            ),
          ]);
        }
        if (s.lessons.isNotEmpty) {
          children.add(AppSection(
            title: t('دروس اليوم', "Today's lessons"),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < s.lessons.length; i++) ...[
                if (i > 0) AppSpace.gapSm,
                SlLessonCard(
                  item: s.lessons[i],
                  index: i,
                  busy: busyLessons.contains(s.lessons[i].id),
                  onGotIt: onGotIt == null ? null : () => onGotIt!(s.lessons[i]),
                ),
              ],
            ]),
          ));
        }
        if (reviews.isNotEmpty) {
          children.add(AppSection(
            title: t('المراجعة', 'Review'),
            // no count here: the list shrinks as answers go in, while the runner keeps counting "2 of 2" (N16)
            child: SlReviewRunner(
              items: reviews,
              submit: submit,
              onReviewed: onReviewed,
              done: AppEmpty(
                icon: Icons.task_alt_rounded,
                title: t('أنهيت المراجعة', 'Review done'),
                message: t('أحسنت. تعود الأسئلة في موعدها لتثبت ما تعلّمته.', 'Well done. The questions come back on time to make it stick.'),
              ),
            ),
          ));
        }
      }
    }
    return ListView(padding: AppSpace.card, children: [...children, AppSpace.gapLg]);
  }
}
