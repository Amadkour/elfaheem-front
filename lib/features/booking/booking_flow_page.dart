// lib/features/booking/booking_flow_page.dart
//
// BookFlow (SCREEN_MAP "Booking", rows 1-18): book a subject in four steps, then the done step.
//
//   hero    the learn area's band: back, "احجز الرياضيات" + "خطوة ١ من ٤", the subject's small book, "تحجز الحين",
//           "الرياضيات، الصف الثاني الثانوي", the step bar (web: with the step names)
//   card    the step: 1 كيف تبي تدرس؟ (+ وين موقعك؟ for حضوري) · 2 مع مجموعة ولا فردي؟ · 3 the time (the groups, the
//           one group, the teacher's free times, or "وش الأوقات اللي تناسبك؟") · 4 راجع حجزك + طريقة الدفع · 5 تم
//   phone   "اخترت" under the card, a footer with the monthly price (M10) and the ONE forward button
//   web     the summary card ("ملخص الحجز") at the end side for steps 1-3; Back and the forward button in the card
//
// RULES §1: the wording is the client's (no subtitle under "كيف تبي تدرس؟", "وين موقعك؟" or "اختر مواعيد حصصك",
// "فردي" never "لحالك", no class counts). RULES §3: modes, centres, prices, currency, methods and VAT all come from
// the server; times are UTC and drawn through AppTime. Privacy: a group shows a seat level only.
//
// Motion (DESIGN_SYSTEM §1.3, booking): M6 between steps (AppWipeSwitcher), M3 + M9 on options, M10 on the price,
// M2 check + M11 burst on the done step. Kill switch `booking` (the whole page), `booking.in_person`,
// `booking.individual`, `booking.proposals`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/core/offline/sync/offline_reads.dart' show offlineBlocked;
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/booking/booking_api.dart';
import 'package:flutter_education_app/features/booking/booking_flow_controller.dart';
import 'package:flutter_education_app/features/booking/booking_models.dart';
import 'package:flutter_education_app/features/booking/booking_parts.dart';
import 'package:flutter_education_app/features/booking/booking_sign_in_sheet.dart';
import 'package:flutter_education_app/features/guest/guest_state.dart';
import 'package:flutter_education_app/features/payments/points/points_card_checkout.dart' show openPointsPaymentPage;
import 'package:flutter_education_app/utils/widget/base_page.dart';

/// The steps before the done step.
const int kBkSteps = 4;

/// The summary card's width on a wide window.
const double kBkAsideW = 350;

/// Opens the booking flow. True when the student booked (the caller refreshes the subject page and welcomes them).
Future<bool> openBookFlow(
  BuildContext context, {
  required int subjectId,
  required int gradeId,
  String? subjectTitle,
  String? gradeTitle,
  String? subjectKey,
  String? courseId,
  bool resume = false,
}) async {
  final r = await Navigator.of(context).push<bool>(MaterialPageRoute(
    builder: (_) => BookFlowPage(
      controller: BkFlowController(
        subjectId: subjectId,
        gradeId: gradeId,
        subjectTitle: subjectTitle,
        gradeTitle: gradeTitle,
        subjectKey: subjectKey,
        courseId: courseId,
      ),
      resume: resume,
    ),
  ));
  return r == true;
}

class BookFlowPage extends StatefulWidget {
  const BookFlowPage({super.key, required this.controller, this.resume = false, this.autoload = true});

  final BkFlowController controller;

  /// Opened again after the sign-in: the saved picks, then the review.
  final bool resume;

  /// False in goldens: the controller is filled by hand.
  final bool autoload;

  @override
  State<BookFlowPage> createState() => _BookFlowPageState();
}

class _BookFlowPageState extends State<BookFlowPage> {
  BkFlowController get c => widget.controller;
  final _details = TextEditingController();

  @override
  void initState() {
    super.initState();
    _details.text = c.details;
    if (widget.autoload) WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final restored = widget.resume && await c.restoreDraft();
    if (!mounted) return;
    _details.text = c.details;
    await c.load();
    if (restored && mounted && c.error == null) await c.resumeAtReview();
  }

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  // ── actions ────────────────────────────────────────────────────────────────

  Future<void> _forward() async {
    if (c.step < kBkSteps) {
      await c.next();
      return;
    }
    if (c.step == kBkSteps) await _confirm();
  }

  Future<void> _confirm() async {
    if (GuestState.active) {
      await c.saveDraft();
      if (mounted) await showBkSignInSheet(context, courseId: c.courseId);
      return;
    }
    if (offlineBlocked()) return; // a booking and its payment are never queued on the device (D-1351)
    try {
      final r = await c.confirm();
      if (!mounted) return;
      final b = r.booking;
      if (b.active || b.status == 'proposed' || b.status == 'scheduled') {
        await BkFlowController.clearDraft();
        c.done();
        return;
      }
      if (b.status == 'pending_payment' && r.canOpen) {
        await openPointsPaymentPage(context, r.checkoutUrl!);
        if (!mounted) return;
        if (await c.settle()) {
          await BkFlowController.clearDraft();
          c.done();
        } else if (mounted) {
          showAppNotice('bk_pay_not_yet'.tr);
        }
        return;
      }
      showAppNotice('bk_pay_not_yet'.tr);
    } catch (e) {
      if (!mounted) return;
      final code = bkErrorCode(e);
      showAppNotice(bkErrorText(e), error: true);
      if (const {'group_full', 'slot_taken', 'slots_mixed_teachers', 'group_not_found', 'slot_not_found'}.contains(code)) {
        await c.reloadTimes();
        await c.goTo(3);
      } else if (const {'gender_required', 'gender_mismatch'}.contains(code)) {
        await c.goTo(2);
      } else if (code == 'mode_unavailable' || code == 'centre_not_found') {
        await c.goTo(1);
      }
    }
  }

  Future<void> _notifyFull(int groupId) async {
    if (!GuestGuard.ensure(context, reasonKey: 'guest_reason_enroll')) return;
    final err = await c.notifyFull(groupId);
    showAppNotice(err ?? 'bk_seats_notified'.tr, error: err != null);
  }

  Future<void> _notifyOther() async {
    if (!GuestGuard.ensure(context, reasonKey: 'guest_reason_enroll')) return;
    final err = await c.notifyOther();
    showAppNotice(err ?? 'bk_other_time_done'.tr, error: err != null);
  }

  void _leave() => Navigator.of(context).maybePop(c.step == 5);

  void _back() {
    if (c.step > 1 && c.step < 5) {
      c.back();
    } else {
      _leave();
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => BasePage(
        key: const ValueKey(kBookingKey),
        child: AppAreaScope(
          area: AppArea.learn,
          child: PopScope(
            canPop: c.step == 1 || c.step == 5,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) c.back();
            },
            child: ListenableBuilder(
              listenable: c,
              builder: (context, _) => LayoutBuilder(builder: (context, box) {
                final width = box.maxWidth.isFinite ? box.maxWidth : MediaQuery.sizeOf(context).width;
                final phone = width < Breakpoints.mobile;
                final aside = width >= Breakpoints.desktop && c.step < kBkSteps;
                return phone ? _phone(context) : _wide(context, aside: aside, width: width);
              }),
            ),
          ),
        ),
      );

  Widget _phone(BuildContext context) {
    final gutter = AppSpace.gutter(MediaQuery.sizeOf(context).width);
    final body = Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _card(context, phone: true),
        if (c.step == 2 || c.step == 3) ...[
          const SizedBox(height: AppSpace.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
            child: BkPickedRow(items: _picked()),
          ),
        ],
        const SizedBox(height: AppSpace.xl),
      ]),
    );
    return Column(children: [
      Expanded(
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: AppHeroOverlap(hero: _hero(context, phone: true), body: body)),
        ]),
      ),
      _footer(context),
    ]);
  }

  Widget _wide(BuildContext context, {required bool aside, required double width}) {
    final gutter = AppSpace.gutter(width);
    final card = _card(context, phone: false);
    final body = Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppWidth.content.max),
          child: aside
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: card),
                  const SizedBox(width: AppSpace.lg),
                  SizedBox(width: kBkAsideW, child: _summary(context)),
                ])
              : card,
        ),
      ),
    );
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: AppHeroOverlap(hero: _hero(context, phone: false), body: body)),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xxl)),
    ]);
  }

  // ── hero ───────────────────────────────────────────────────────────────────

  String get _stepsLine => c.step == 5
      ? 'bk_booked'.tr
      : bkFill('bk_step_of', {'n': appDigits('${c.step}'), 'total': appDigits('$kBkSteps')});

  Widget _hero(BuildContext context, {required bool phone}) {
    final col = context.colors;
    final title = c.subjectLabel;
    final head = bkFill('bk_book_subject', {'subject': title});
    final whole = [title, c.gradeLabel].where((s) => s.isNotEmpty).join(bkComma);
    final bar = Row(children: [
      AppBackButton(onPressed: _back, onHero: true),
      const SizedBox(width: AppSpace.sm),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(head, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppType.bodyStrong(context).copyWith(color: col.onHero)),
          Text(_stepsLine, style: AppType.meta(context).copyWith(color: col.onHeroMuted)),
        ]),
      ),
    ]);
    final band = Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      BkMiniBook(subject: c.subjectKey ?? c.options?.subject.en ?? title),
      const SizedBox(width: AppSpace.md),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(c.step == 5 ? 'bk_kicker_done'.tr : 'bk_kicker'.tr,
              style: AppType.label(context).copyWith(color: col.kit.warmOnDark)),
          const SizedBox(height: AppSpace.xxs),
          Text(whole, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: AppType.pageTitle(context).copyWith(color: col.onHero)),
        ]),
      ),
    ]);
    return AppHeroSurface(
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            phone ? AppSpace.md : AppSpace.lg,
            AppSpace.xs,
            phone ? AppSpace.md : AppSpace.lg,
            (phone ? AppHeroMetrics.overlapStudentPhone : AppHeroMetrics.overlapWide) + AppSpace.md,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: AppWidth.content.max),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                bar,
                const SizedBox(height: AppSpace.md),
                band,
                if (c.step < 5) ...[
                  const SizedBox(height: AppSpace.md),
                  BkStepBar(step: c.step, total: kBkSteps, labels: phone ? null : _stepNames),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }

  List<String> get _stepNames => ['bk_step_how'.tr, 'bk_step_kind'.tr, 'bk_step_time'.tr, 'bk_step_confirm'.tr];

  // ── the card ───────────────────────────────────────────────────────────────

  Widget _card(BuildContext context, {required bool phone}) {
    final Widget content;
    if (c.loading && c.options == null) {
      content = const Padding(padding: EdgeInsets.all(AppSpace.md), child: AppListSkeleton(items: 3, withAvatar: false));
    } else if (c.options == null) {
      content = AppErrorState(message: c.error, onRetry: c.load);
    } else {
      content = switch (c.step) {
        1 => _ModeStep(c: c, details: _details, wide: !phone),
        2 => _KindStep(c: c),
        3 => c.kind == 'group'
            ? _GroupStep(c: c, onNotifyFull: _notifyFull, onNotifyOther: _notifyOther)
            : _SlotsStep(c: c),
        4 => _ReviewStep(c: c, wide: !phone),
        _ => _DoneStep(c: c),
      };
    }
    return AppCard(
      padding: EdgeInsets.all(phone ? AppSpace.md : AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppWipeSwitcher(switchKey: c.step, child: KeyedSubtree(key: ValueKey(c.step), child: content)),
        if (!phone && c.options != null) ...[
          const SizedBox(height: AppSpace.lg),
          _wideActions(context),
        ],
      ]),
    );
  }

  String get _forwardLabel {
    if (c.step == 5) return 'bk_open_subject'.tr;
    if (c.step < kBkSteps) return 'bk_next'.tr;
    if (c.quote?.payNow == false || (c.kind == 'individual' && c.proposing)) return 'bk_send_times'.tr;
    final p = c.price;
    return p == null ? 'bk_confirm'.tr : bkFill('bk_confirm_pay', {'price': bkMoney(p, c.currency)});
  }

  Widget _forwardButton({bool expand = false}) => AppButton.hot(
        label: _forwardLabel,
        trailingIcon: Icons.arrow_forward_rounded,
        size: AppButtonSize.lg,
        expand: expand,
        busy: c.busy,
        onPressed: c.step == 5 ? _leave : (c.canNext ? _forward : null),
      );

  Widget _wideActions(BuildContext context) => Row(children: [
        _forwardButton(),
        const Spacer(),
        if (c.step > 1 && c.step < 5) AppButton.secondary(label: 'bk_back'.tr, onPressed: c.back),
      ]);

  Widget _footer(BuildContext context) {
    final col = context.colors;
    final p = c.price;
    final showPrice = c.step < 5 && p != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: col.cardBg,
        border: Border(top: BorderSide(color: col.kit.line, width: AppBorder.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
          child: Row(children: [
            if (showPrice && c.step < kBkSteps) ...[
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('bk_per_month'.tr, style: AppType.meta(context)),
                  AppOdometer(bkMoney(p, c.currency), memoryKey: 'bk_price',
                      style: AppType.figure(context).copyWith(color: col.textDark)),
                ]),
              ),
              const SizedBox(width: AppSpace.sm),
              Flexible(child: _forwardButton()),
            ] else
              Expanded(child: _forwardButton(expand: true)),
          ]),
        ),
      ),
    );
  }

  // ── "اخترت" and the summary ────────────────────────────────────────────────

  String get _modeWord {
    if (c.mode == 'in_person') {
      final d = c.district?.name.label;
      return d == null || d.isEmpty ? 'bk_mode_in_person'.tr : bkFill('bk_in_person_at', {'place': d});
    }
    return c.mode == 'remote' ? 'bk_mode_remote'.tr : '';
  }

  String get _kindWord => switch (c.kind) { 'group' => 'bk_kind_group_short'.tr, 'individual' => 'bk_kind_individual_short'.tr, _ => '' };

  List<BkPicked> _picked() => [
        if (c.mode != null)
          BkPicked(
            icon: c.mode == 'in_person' ? Icons.apartment_rounded : Icons.laptop_rounded,
            label: _modeWord,
            onEdit: () => c.goTo(1),
            editLabel: 'bk_edit_how'.tr,
          ),
        if (c.step == 3 && c.kind != null)
          BkPicked(
            icon: c.kind == 'group' ? Icons.groups_outlined : Icons.person_outline_rounded,
            label: _kindWord,
            onEdit: () => c.goTo(2),
            editLabel: 'bk_edit_kind'.tr,
          ),
      ];

  Widget _summary(BuildContext context) {
    final col = context.colors;
    final set = AppAreaScope.of(context);
    final none = 'bk_not_yet'.tr;
    final rows = <(String, String)>[
      ('bk_row_subject'.tr, c.subjectLabel),
      ('bk_step_how'.tr, _modeWord.isEmpty ? none : _modeWord),
      ('bk_step_kind'.tr, _kindWord.isEmpty ? none : _kindWord),
      ('bk_row_when'.tr, bkWhenText(c) ?? none),
      ('bk_row_teacher'.tr, bkTeacherText(c) ?? '—'),
    ];
    final p = c.price;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: col.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.cardWide),
        boxShadow: AppElevation.of(context, 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(gradient: set.button),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('bk_summary'.tr, style: AppType.meta(context).copyWith(color: set.btnFg)),
            Text(c.subjectLabel, style: AppType.section(context).copyWith(color: set.btnFg)),
            if (c.gradeLabel.isNotEmpty) Text(c.gradeLabel, style: AppType.meta(context).copyWith(color: set.btnFg)),
          ]),
        ),
        for (final (l, v) in rows) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
            child: Row(children: [
              Text(l, style: AppType.meta(context)),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(v, textAlign: TextAlign.end, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: AppType.label(context).copyWith(color: col.textDark, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: col.kit.line),
        ],
        Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(children: [
            Text('bk_per_month'.tr, style: AppType.meta(context)),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: p == null
                      ? Text('—', style: AppType.figure(context))
                      : AppOdometer(bkMoney(p, c.currency), memoryKey: 'bk_price_side',
                          style: AppType.figure(context).copyWith(color: col.textDark)),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// "مجموعة أ: الأحد والثلاثاء، 7:30 إلى 8:20 م", the picked times, or the proposal; null before step 3.
String? bkWhenText(BkFlowController c) {
  if (c.kind == 'group') {
    final g = c.group;
    if (g == null) return null;
    final when = [bkDaysOf(g.times), if (g.times.isNotEmpty) bkTimeRange(g.times.first, c.classMinutes)].join(bkComma);
    return '${bkGroupName(g.label)}: $when';
  }
  if (c.kind == 'individual') {
    if (c.proposing) {
      if (c.proposalDays.isEmpty) return null;
      final days = bkJoinDays([
        for (final d in c.proposalDays.toList()..sort((a, b) => bkWeekdayOrder(a).compareTo(bkWeekdayOrder(b)))) bkWeekdayName(d),
      ]);
      final periods = [for (final p in kBkPeriods) if (c.proposalPeriods.contains(p.$1)) 'bk_period_${p.$1}'.tr];
      return periods.isEmpty ? days : '$days$bkComma${periods.join(' ${'bk_or'.tr} ')}';
    }
    final s = c.chosenSlots..sort((a, b) => (AppTime.toZone(a.startsAt).weekday % 7).compareTo(AppTime.toZone(b.startsAt).weekday % 7));
    if (s.isEmpty) return null;
    return bkJoinDays([for (final x in s) '${AppTime.date(x.startsAt, pattern: 'EEEE')} ${appDigits(AppTime.time(x.startsAt))}']);
  }
  return null;
}

String? bkTeacherText(BkFlowController c) {
  if (c.kind == 'group') return c.group?.teacher?.name ?? (c.quote?.teacher?.name);
  if (c.kind == 'individual') return c.proposing ? 'bk_teacher_by_team'.tr : c.slotTeacher?.teacher.name;
  return null;
}

// ═════════════════════════════════════════════════════════════════════════════
// Steps
// ═════════════════════════════════════════════════════════════════════════════

class _StepTitle extends StatelessWidget {
  const _StepTitle(this.title, {this.sub});

  final String title;
  final String? sub;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true, child: Text(title, style: AppType.headline(context))),
          if (sub != null) ...[
            const SizedBox(height: AppSpace.xs),
            Text(sub!, style: AppType.body(context).copyWith(color: context.colors.textMedium)),
          ],
        ]),
      );
}

class _Link extends StatelessWidget {
  const _Link({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.kit.warmTone.ink;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
        child: Text(label,
            style: AppType.bodyStrong(context).copyWith(
              color: onTap == null ? context.colors.kit.ok.ink : ink,
              decoration: onTap == null ? null : TextDecoration.underline,
              decorationColor: ink,
            )),
      ),
    );
  }
}

// ── 1 · كيف تبي تدرس؟ ─────────────────────────────────────────────────────────

class _ModeStep extends StatelessWidget {
  const _ModeStep({required this.c, required this.details, required this.wide});

  final BkFlowController c;
  final TextEditingController details;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final kit = context.colors.kit;
    final cards = [
      for (final m in c.modes)
        BkOptionCard(
          key: ValueKey('bk_mode_${m.key}'),
          stacked: wide,
          icon: m.key == 'in_person' ? Icons.apartment_rounded : Icons.laptop_rounded,
          tone: m.key == 'in_person' ? kit.warmTone : kit.accent(AppAccent.sky),
          title: m.key == 'in_person' ? 'bk_mode_in_person'.tr : 'bk_mode_remote'.tr,
          text: m.key == 'in_person' ? 'bk_mode_in_person_text'.tr : 'bk_mode_remote_text'.tr,
          selected: c.mode == m.key,
          onTap: () => c.pickMode(m.key),
        ),
    ];
    final noCentre = c.options?.mode('in_person')?.available == false && c.options?.mode('in_person')?.reason == 'no_centre_here';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _StepTitle('bk_how_q'.tr),
      if (wide && cards.length > 1)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, w) in cards.indexed) ...[
              if (i > 0) const SizedBox(width: AppSpace.md),
              Expanded(child: w),
            ],
          ]),
        )
      else
        for (final (i, w) in cards.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpace.md),
          w,
        ],
      if (noCentre && c.inPersonOn) ...[
        const SizedBox(height: AppSpace.sm),
        Row(children: [
          Icon(Icons.info_outline_rounded, size: AppIconSize.sm, color: context.colors.textMedium),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text('bk_in_person_unavailable'.tr, style: AppType.meta(context))),
        ]),
      ],
      if (c.mode == 'in_person') ...[
        const SizedBox(height: AppSpace.lg),
        _Location(c: c, details: details),
      ],
    ]);
  }
}

class _Location extends StatelessWidget {
  const _Location({required this.c, required this.details});

  final BkFlowController c;
  final TextEditingController details;

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    final centres = c.centres;
    final Widget body;
    if (c.centresLoading && centres == null) {
      body = const AppListSkeleton(items: 2, withAvatar: false);
    } else if (centres == null || centres.cities.isEmpty) {
      body = Text('bk_in_person_unavailable'.tr, style: AppType.body(context));
    } else {
      final city = c.city;
      final district = c.district;
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('bk_area'.tr, style: AppType.label(context).copyWith(color: col.textDark, fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
          for (final x in centres.cities)
            AppChip(label: x.name.label, selected: x.id == c.cityId, onTap: () => c.pickCity(x.id)),
        ]),
        if (city != null && city.districts.isNotEmpty && (city.districts.length > 1 || city.districts.first.id != null)) ...[
          const SizedBox(height: AppSpace.md),
          Text('bk_district'.tr, style: AppType.label(context).copyWith(color: col.textDark, fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpace.sm),
          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
            for (final (i, d) in city.districts.indexed)
              AppChip(
                icon: Icons.place_outlined,
                label: d.id == null ? city.name.label : d.name.label,
                selected: i == c.districtIndex,
                onTap: () => c.pickDistrict(i),
              ),
          ]),
        ],
        if (district != null && district.centres.length > 1) ...[
          const SizedBox(height: AppSpace.md),
          Text('bk_branch'.tr, style: AppType.label(context).copyWith(color: col.textDark, fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpace.sm),
          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
            for (final x in district.centres)
              AppChip(label: x.name.label, selected: x.id == c.centreId, onTap: () => c.pickCentre(x.id)),
          ]),
        ],
        if (c.centre != null && (c.centre!.address?.label ?? '').isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          Row(children: [
            Icon(Icons.place_rounded, size: AppIconSize.sm, color: col.kit.live.color),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Text(
                [city?.name.label, c.centre!.name.label, c.centre!.address!.label].whereType<String>().where((s) => s.isNotEmpty).join(bkComma),
                style: AppType.label(context).copyWith(color: col.textDark),
              ),
            ),
          ]),
        ],
        const SizedBox(height: AppSpace.md),
        AppField(
          controller: details,
          label: 'bk_details'.tr,
          hint: 'bk_details_hint'.tr,
          maxLength: 500,
          onChanged: c.setDetails,
        ),
      ]);
    }
    return BkWell(title: 'bk_where_q'.tr, child: body);
  }
}

// ── 2 · مع مجموعة ولا فردي؟ ──────────────────────────────────────────────────

class _KindStep extends StatelessWidget {
  const _KindStep({required this.c});

  final BkFlowController c;

  @override
  Widget build(BuildContext context) {
    final kit = context.colors.kit;
    final o = c.options!;
    final minutes = bkFill('bk_class_minutes', {'n': appDigits('${o.classMinutes}')});
    String? price(String kind) {
      final p = c.mode == null ? null : o.price(kind, c.mode!);
      return p == null ? null : bkMoney(p, o.currency);
    }

    final cards = [
      for (final k in c.kinds)
        BkOptionCard(
          key: ValueKey('bk_kind_${k.key}'),
          icon: k.key == 'group' ? Icons.groups_outlined : Icons.person_outline_rounded,
          tone: k.key == 'group' ? kit.accent(AppAccent.sky) : kit.accent(AppAccent.grape),
          title: k.key == 'group' ? 'bk_kind_group'.tr : 'bk_kind_individual'.tr,
          text: k.key == 'group'
              ? bkFill('bk_kind_group_text', {'min': appDigits('${o.groupMin}'), 'max': appDigits('${o.groupMax}')})
              : 'bk_kind_individual_text'.tr,
          price: price(k.key),
          priceNote: price(k.key) == null ? null : 'bk_per_month'.tr,
          meta: minutes,
          selected: c.kind == k.key,
          onTap: () => c.pickKind(k.key),
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _StepTitle('bk_kind_q'.tr),
      if (o.gender == null) ...[
        BkWell(
          title: 'bk_gender_q'.tr,
          child: Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
            BkPickChip(label: 'bk_gender_boy'.tr, selected: c.gender == 'boys', onTap: () => c.pickGender('boys')),
            BkPickChip(label: 'bk_gender_girl'.tr, selected: c.gender == 'girls', onTap: () => c.pickGender('girls')),
          ]),
        ),
        const SizedBox(height: AppSpace.md),
      ],
      for (final (i, w) in cards.indexed) ...[
        if (i > 0) const SizedBox(height: AppSpace.md),
        w,
      ],
    ]);
  }
}

// ── 3 · the group ────────────────────────────────────────────────────────────

class _GroupStep extends StatelessWidget {
  const _GroupStep({required this.c, required this.onNotifyFull, required this.onNotifyOther});

  final BkFlowController c;
  final ValueChanged<int> onNotifyFull;
  final VoidCallback onNotifyOther;

  @override
  Widget build(BuildContext context) {
    final g = c.groups;
    if (c.timesLoading && g == null) return const AppListSkeleton(items: 3, withAvatar: false);
    if (g == null) return AppErrorState(message: c.timesError, onRetry: c.reloadTimes, compact: true);
    final branch = c.mode == 'in_person'
        ? [c.city?.name.label, c.district?.name.label].whereType<String>().where((s) => s.isNotEmpty).join(bkComma)
        : '';
    final other = _Link(
      label: c.notifiedOtherTime ? 'bk_other_time_done'.tr : 'bk_other_time'.tr,
      onTap: c.notifiedOtherTime ? null : onNotifyOther,
    );
    if (g.items.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _StepTitle('bk_pick_group'.tr),
        AppEmpty(icon: Icons.event_busy_rounded, title: 'bk_no_groups'.tr, message: 'bk_no_groups_text'.tr),
        other,
      ]);
    }
    String time(BkGroup x) => x.times.isEmpty ? '' : bkTimeRange(x.times.first, c.classMinutes);
    String? starts(BkGroup x) => x.startsAt == null ? null : bkFill('bk_starts', {'date': bkDay(x.startsAt!)});
    if (g.single) {
      final x = g.items.first;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _StepTitle('bk_one_group'.tr, sub: 'bk_one_group_text'.tr),
        BkOneGroupCard(
          label: x.label,
          days: bkDaysOf(x.times),
          time: time(x),
          availability: x.availability,
          teacher: x.teacher?.name,
          starts: starts(x),
          mode: c.mode == 'in_person' ? (branch.isEmpty ? 'bk_mode_in_person'.tr : branch) : 'bk_mode_remote'.tr,
        ),
        const SizedBox(height: AppSpace.md),
        if (x.full)
          _Link(
            label: c.notifiedGroups.contains(x.id) ? 'bk_seats_notified'.tr : 'bk_seats_full_notify'.tr,
            onTap: c.notifiedGroups.contains(x.id) ? null : () => onNotifyFull(x.id),
          ),
        other,
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _StepTitle(
        'bk_pick_group'.tr,
        sub: branch.isEmpty ? 'bk_fixed_times'.tr : bkFill('bk_fixed_times_at', {'place': branch}),
      ),
      for (final (i, x) in g.items.indexed) ...[
        if (i > 0) const SizedBox(height: AppSpace.md),
        BkGroupCard(
          key: ValueKey('bk_group_${x.id}'),
          label: x.label,
          days: bkDaysOf(x.times),
          time: time(x),
          teacher: x.teacher?.name,
          starts: starts(x),
          tone: bkGroupTone(context, i),
          availability: x.availability,
          selected: x.id == c.groupId,
          onTap: () => c.pickGroup(x.id),
          onNotify: () => onNotifyFull(x.id),
          notified: c.notifiedGroups.contains(x.id) || x.mineStatus == 'waitlisted',
        ),
      ],
    ]);
  }
}

// ── 3 · فردي: the teacher's free times, or propose ───────────────────────────

class _SlotsStep extends StatelessWidget {
  const _SlotsStep({required this.c});

  final BkFlowController c;

  @override
  Widget build(BuildContext context) {
    final list = c.slotTeachers;
    if (c.timesLoading && list == null) return const AppListSkeleton(items: 4, withAvatar: false);
    if (list == null) return AppErrorState(message: c.timesError, onRetry: c.reloadTimes, compact: true);
    final hasSlots = list.any((t) => t.slots.isNotEmpty);
    if (c.proposing) return _Proposal(c: c, canGoBack: hasSlots);
    if (!hasSlots) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _StepTitle('bk_pick_times'.tr),
        AppEmpty(icon: Icons.event_busy_rounded, title: 'bk_no_slots'.tr),
      ]);
    }
    final col = context.colors;
    final t = c.slotTeacher!;
    // one row per local weekday, Sunday first; inside a row the times in order
    final byDay = <int, List<BkSlot>>{};
    for (final s in t.slots) {
      (byDay[AppTime.toZone(s.startsAt).weekday] ??= []).add(s);
    }
    final days = byDay.keys.toList()..sort((a, b) => (a % 7).compareTo(b % 7));
    final n = c.pickedSlots.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _StepTitle('bk_pick_times'.tr),
      if (list.length > 1) ...[
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
          for (final (i, x) in list.indexed)
            if (x.slots.isNotEmpty)
              AppChip(label: x.teacher.name, icon: Icons.person_outline_rounded, selected: i == c.teacherIndex, onTap: () => c.pickTeacher(i)),
        ]),
        const SizedBox(height: AppSpace.md),
      ],
      for (final (i, d) in days.indexed) ...[
        if (i > 0) const SizedBox(height: AppSpace.sm),
        BkDayRow(
          day: AppTime.date(byDay[d]!.first.startsAt, pattern: 'EEEE'),
          times: [
            for (final s in byDay[d]!..sort((a, b) => a.startsAt.compareTo(b.startsAt)))
              BkTimeOption(
                id: s.id,
                label: appDigits(AppTime.time(s.startsAt)),
                selected: c.pickedSlots[d] == s.id,
                blocked: c.pickedSlots.containsKey(d) && c.pickedSlots[d] != s.id,
              ),
          ],
          onPick: (id) => c.toggleSlot(byDay[d]!.firstWhere((s) => s.id == id)),
        ),
      ],
      const SizedBox(height: AppSpace.md),
      Row(children: [
        if (n > 0) ...[Icon(Icons.check_rounded, size: AppIconSize.md, color: col.kit.ok.ink), const SizedBox(width: AppSpace.xs)],
        Expanded(
          child: Text(
            n == 0
                ? 'bk_pick_times_hint'.tr
                : appDigits(countText(n,
                    ar1: 'اخترت موعد واحد', ar2: 'اخترت موعدين', arFew: 'اخترت {n} مواعيد', arMany: 'اخترت {n} موعد',
                    en1: 'You picked 1 time', en: 'You picked {n} times')),
            style: AppType.bodyStrong(context).copyWith(color: n == 0 ? col.textMedium : col.kit.ok.ink),
          ),
        ),
      ]),
      if (c.proposalsOn) ...[
        const SizedBox(height: AppSpace.md),
        _Link(label: 'bk_propose_link'.tr, onTap: () => c.setProposing(true)),
      ],
    ]);
  }
}

class _Proposal extends StatelessWidget {
  const _Proposal({required this.c, required this.canGoBack});

  final BkFlowController c;
  final bool canGoBack;

  String _hours(int from, int to) {
    String h(int m) {
      final hh = (m ~/ 60) % 12 == 0 ? 12 : (m ~/ 60) % 12;
      return m % 60 == 0 ? '$hh' : '$hh:${(m % 60).toString().padLeft(2, '0')}';
    }

    return appDigits(bkFill('bk_time_range', {'from': h(from), 'to': h(to)}));
  }

  @override
  Widget build(BuildContext context) {
    final hours = c.options?.proposalHours ?? 24;
    final week = List<int>.generate(7, (i) => (i + 6) % 7); // Sunday first (Python numbering)
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _StepTitle('bk_propose_q'.tr, sub: bkFill('bk_propose_text', {'h': appDigits('$hours')})),
      BkWell(
        title: 'bk_days'.tr,
        child: Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
          for (final d in week)
            BkPickChip(label: bkWeekdayName(d), selected: c.proposalDays.contains(d), onTap: () => c.toggleProposalDay(d)),
        ]),
      ),
      const SizedBox(height: AppSpace.md),
      BkWell(
        title: 'bk_period'.tr,
        child: Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
          for (final p in kBkPeriods)
            BkPickChip(
              label: 'bk_period_${p.$1}'.tr,
              note: _hours(p.$2, p.$3),
              selected: c.proposalPeriods.contains(p.$1),
              onTap: () => c.toggleProposalPeriod(p.$1),
            ),
        ]),
      ),
      if (canGoBack) ...[
        const SizedBox(height: AppSpace.md),
        _Link(label: 'bk_back_to_slots'.tr, onTap: () => c.setProposing(false)),
      ],
    ]);
  }
}

// ── 4 · راجع حجزك ─────────────────────────────────────────────────────────────

String _brandOf(BkPayMethod m) => switch (m.key) {
      'mada' => 'mada',
      'apple_pay' => 'Pay',
      'google_pay' => 'G Pay',
      'stc_pay' => 'stc pay',
      'card' => 'VISA',
      _ => m.label,
    };

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({required this.c, required this.wide});

  final BkFlowController c;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final col = context.colors;
    final kit = col.kit;
    final user = GuestState.active ? null : context.read<MyAuthProvider?>()?.currentUser?.name;
    final payNow = c.quote?.payNow ?? !(c.kind == 'individual' && c.proposing);
    final modeWord = c.mode == 'in_person'
        ? [
            'bk_mode_in_person'.tr,
            c.city?.name.label,
            c.district?.id == null ? null : bkFill('bk_district_named', {'name': c.district!.name.label}),
          ].whereType<String>().where((s) => s.isNotEmpty).join(bkComma)
        : 'bk_mode_remote'.tr;
    final p = c.price;
    final info = c.payInfo;
    final notes = <String>[
      if (info?.vatApplies == true && info?.vatLabel != null) info!.vatLabel!,
      if (info?.approx != null) '≈ ${info!.approx!}',
      if (info?.approxNote != null) info!.approxNote!,
      if (info?.approx == null && info?.chargeNote != null && (info!.chargeCurrency ?? '') != (c.currency ?? '')) info.chargeNote!,
    ];
    final table = BkReviewTable(
      rows: [
        BkReviewRow(label: 'bk_row_subject'.tr, value: c.subjectLabel),
        BkReviewRow(label: 'bk_step_how'.tr, value: modeWord, onEdit: () => c.goTo(1), editLabel: 'bk_edit_how'.tr),
        BkReviewRow(
          label: 'bk_step_kind'.tr,
          value: c.kind == 'group' ? 'bk_kind_group_short'.tr : 'bk_kind_individual_short'.tr,
          onEdit: () => c.goTo(2),
          editLabel: 'bk_edit_kind'.tr,
        ),
        BkReviewRow(label: 'bk_row_when'.tr, value: bkWhenText(c) ?? '—', onEdit: () => c.goTo(3), editLabel: 'bk_edit_when'.tr),
        BkReviewRow(label: 'bk_row_teacher'.tr, value: bkTeacherText(c) ?? '—'),
      ],
      totalLabel: 'bk_monthly'.tr,
      total: p == null ? '—' : bkMoney(p, c.currency),
      note: notes,
    );
    final methods = info?.bookable ?? const <BkPayMethod>[];
    final Widget pay;
    if (!payNow) {
      pay = Row(children: [
        Icon(Icons.schedule_rounded, size: AppIconSize.md, color: kit.warmTone.ink),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Text(bkFill('bk_pay_after_fix', {'h': appDigits('${c.options?.proposalHours ?? 24}')}),
              style: AppType.body(context)),
        ),
      ]);
    } else {
      pay = BkWell(
        title: 'bk_pay_method'.tr,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (info == null)
            const AppListSkeleton(items: 2, withAvatar: false)
          else if (methods.isEmpty)
            Text('bk_pay_none'.tr, style: AppType.body(context))
          else
            for (final (i, m) in methods.indexed) ...[
              if (i > 0) const SizedBox(height: AppSpace.sm),
              BkPayMethodTile(
                label: m.label,
                brand: _brandOf(m),
                selected: c.method == m.key,
                tone: switch (m.key) {
                  'apple_pay' => null,
                  'card' => kit.accent(AppAccent.sun),
                  _ => kit.primaryTone,
                },
                onTap: () => c.pickMethod(m.key),
              ),
            ],
          const SizedBox(height: AppSpace.sm),
          Row(children: [
            Icon(Icons.verified_user_outlined, size: AppIconSize.sm, color: kit.ok.ink),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text('bk_pay_safe'.tr, style: AppType.label(context).copyWith(color: kit.ok.ink))),
          ]),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _StepTitle('bk_review'.tr, sub: user == null || user.isEmpty ? null : bkFill('bk_booked_as', {'name': user})),
      if (c.timesError != null) ...[
        Text(c.timesError!, style: AppType.body(context).copyWith(color: kit.error.color)),
        const SizedBox(height: AppSpace.sm),
      ],
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: table),
          const SizedBox(width: AppSpace.lg),
          Expanded(flex: 2, child: pay),
        ])
      else ...[
        table,
        const SizedBox(height: AppSpace.md),
        pay,
      ],
    ]);
  }
}

// ── 5 · تم، حجزك تأكد ─────────────────────────────────────────────────────────

class _DoneStep extends StatefulWidget {
  const _DoneStep({required this.c});

  final BkFlowController c;

  @override
  State<_DoneStep> createState() => _DoneStepState();
}

class _DoneStepState extends State<_DoneStep> {
  final _mark = GlobalKey();
  Timer? _burst;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // M11 once, after the ink check (nothing under Reduce motion: AppBurst checks it too)
      if (!mounted || appMotionOff(context)) return;
      _burst = Timer(AppSuccess.burstAt, () {
        if (mounted) AppBurst.fire(context, BurstMoment.bookingConfirmed, anchor: _mark);
      });
    });
  }

  @override
  void dispose() {
    _burst?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final col = context.colors;
    final b = c.booked;
    final proposal = (b?.status == 'proposed') || (c.kind == 'individual' && c.proposing);
    final groupLabel = b?.group?.label ?? c.group?.label ?? '';
    final message = proposal
        ? bkFill('bk_done_proposal', {'h': appDigits('${c.options?.proposalHours ?? 24}')})
        : c.kind == 'group'
            ? bkFill('bk_done_group', {'label': groupLabel})
            : 'bk_done_individual'.tr;
    final first = b?.nextClassAt ??
        (c.kind == 'group' ? c.group?.startsAt : (c.chosenSlots.isEmpty ? null : (c.chosenSlots..sort((a, b) => a.startsAt.compareTo(b.startsAt))).first.startsAt));
    final teacher = b?.teacher?.name ?? bkTeacherText(c) ?? '';
    final place = c.mode == 'in_person'
        ? bkFill('bk_in_person_at', {'place': [c.city?.name.label, c.district?.name.label].whereType<String>().where((s) => s.isNotEmpty).join(bkComma)})
        : 'bk_mode_remote'.tr;
    final meta = [
      c.kind == 'group' ? bkGroupName(groupLabel) : 'bk_kind_individual_short'.tr,
      place,
      bkFill('bk_class_minutes', {'n': appDigits('${c.classMinutes}')}),
    ].join(bkComma);
    final ticket = BkTicket(
      label: proposal ? 'bk_your_times'.tr : 'bk_first_class'.tr,
      time: proposal || first == null ? (bkWhenText(c) ?? '') : bkTimeRange(first, c.classMinutes),
      teacher: teacher,
      meta: meta,
      month: proposal || first == null ? null : AppTime.date(first, pattern: 'MMMM'),
      day: proposal || first == null ? null : appDigits(AppTime.date(first, pattern: 'd')),
      weekday: proposal || first == null ? null : AppTime.date(first, pattern: 'EEEE'),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(
        child: AppPop(
          child: Container(
            key: _mark,
            width: AppSuccess.circle,
            height: AppSuccess.circle,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: col.kit.ok.tint),
            child: const AppInkCheck(size: AppDashSize.disc),
          ),
        ),
      ),
      const SizedBox(height: AppSpace.md),
      Text('bk_done_title'.tr, textAlign: TextAlign.center, style: AppType.headline(context)),
      const SizedBox(height: AppSpace.xs),
      Text(message, textAlign: TextAlign.center, style: AppType.body(context).copyWith(color: col.textMedium)),
      const SizedBox(height: AppSpace.lg),
      ticket,
      const SizedBox(height: AppSpace.lg),
      if (!proposal) ...[
        BkPerk(icon: Icons.receipt_long_outlined, text: 'bk_perk_receipt'.tr),
        const SizedBox(height: AppSpace.sm),
      ],
      BkPerk(
        icon: c.mode == 'in_person' ? Icons.place_outlined : Icons.laptop_rounded,
        text: c.mode == 'in_person' ? 'bk_perk_place'.tr : 'bk_perk_link'.tr,
      ),
      const SizedBox(height: AppSpace.sm),
      BkPerk(icon: Icons.notifications_none_rounded, text: 'bk_perk_reminder'.tr),
    ]);
  }
}
