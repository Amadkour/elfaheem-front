/// roadmap_enrollment_screen.dart — enrol in a whole roadmap and pay for every
/// course on it in ONE checkout.
///
/// Open it from the course profile's roadmap card:
///   Navigator.of(context).push(MaterialPageRoute(
///     builder: (_) => RoadmapEnrollmentScreen(courseId: course.id, courseName: course.name)));
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/app_network_image.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import '../../org/org_levels_pages.dart' show showEnrollBlock;
import 'enrollment_models.dart';
import 'enrollment_widgets.dart';
import 'payment_flow_provider.dart' show EnrollStep;
import 'roadmap_enrollment_provider.dart';

class RoadmapEnrollmentScreen extends StatelessWidget {
  final int courseId;
  final String? courseName;
  const RoadmapEnrollmentScreen({super.key, required this.courseId, this.courseName});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RoadmapEnrollmentProvider(courseId)..scheduleLoad(),
      child: _RoadmapView(courseName: courseName),
    );
  }
}

class _RoadmapView extends StatelessWidget {
  final String? courseName;
  const _RoadmapView({required this.courseName});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<RoadmapEnrollmentProvider>();
    final count = p.quote?.activatedCount ?? 0;

    return EnrollScaffold(
      child: switch (p.step) {
        EnrollStep.method => _RoadmapBody(key: const ValueKey('body'), courseName: courseName),
        EnrollStep.verifying => const PaymentVerifyingView(key: ValueKey('verifying')),
        EnrollStep.pending => PaymentResultView(
          key: const ValueKey('pending'),
          kind: ResultKind.pending,
          title: 'payment_pending_title'.tr,
          message: 'roadmap_pending_message'.tr,
          primaryLabel: 'back_to_home'.tr,
          onPrimary: () => popToHome(context),
        ),
        EnrollStep.success => PaymentResultView(
          key: const ValueKey('success'),
          kind: ResultKind.success,
          title: 'roadmap_success_title'.tr,
          message: count > 1
              ? '$count ${'roadmap_courses_activated_suffix'.tr}'
              : 'enroll_success_message'.tr,
          primaryLabel: 'start_learning_now'.tr,
          onPrimary: () => popToHome(context),
        ),
        EnrollStep.failed => PaymentResultView(
          key: const ValueKey('failed'),
          kind: ResultKind.failed,
          title: 'payment_failed_title'.tr,
          message: p.failureReason ?? 'payment_failed_fallback'.tr,
          primaryLabel: 'try_again_payment'.tr,
          onPrimary: p.backToMethod,
          secondaryLabel: 'back_to_home'.tr,
          onSecondary: () => popToHome(context),
        ),
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════

class _RoadmapBody extends StatelessWidget {
  final String? courseName;
  const _RoadmapBody({super.key, required this.courseName});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<RoadmapEnrollmentProvider>();
    final quote = p.quote;
    final c = context.colors;
    final wide = isWideLayout(context);
    // Paid courses in the bundle + card payments closed by the admin → can't check out.
    final blocked = quote != null && quote.payableCount > 0 && !p.cardAvailable;

    // organization prerequisites (403 roadmap_prerequisites): explain once in the enrolment-blocked sheet
    final prereq = p.block;
    if (prereq != null && p.takeBlockToShow()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) showEnrollBlock(context, prereq);
      });
    }

    Widget content;
    if (prereq != null) {
      content = _PrereqBlocked(reason: prereq);
    } else if (p.loadFailed) {
      content = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('roadmap_load_failed'.tr, style: c.h3),
          const SizedBox(height: 16),
          SizedBox(width: 200, child: SoftOutlineButton(label: 'retry'.tr, onTap: p.load)),
        ]),
      );
    } else if (quote == null) {
      content = const Center(child: AppLoadingIndicator());
    } else {
      content = SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(wide ? 32 : 20, 12, wide ? 32 : 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ParentComponent(featureKey: 'roadmap_enroll.intro', child: _Intro(courseName: courseName, quote: quote)),
          if (blocked) ...[
            const SizedBox(height: 12),
            const _CardUnavailableBanner(),
          ],
          const SizedBox(height: 20),
          for (var i = 0; i < quote.items.length; i++)
            ParentComponent(
              featureKey: 'roadmap_enroll.items',
              child: _RoadmapItemTile(
                item: quote.items[i],
                isLast: i == quote.items.length - 1,
                currencySymbol: p.currencySymbol,
              ),
            ),
          if (quote.fees != null) ...[
            const SizedBox(height: 12),
            ParentComponent(
              featureKey: 'roadmap_enroll.fees',
              child: FeeBreakdownCard(quote: quote.fees, currencySymbol: p.currencySymbol),
            ),
          ],
        ]),
      );
    }

    return Center(
      child: Column(children: [
        enrollAppBar('roadmap_enrollment_title'.tr),
        Expanded(child: content),
        if (quote != null)
          EnrollConfirmBar(
            label: _label(quote, p.currencySymbol),
            loading: p.isLoading,
            onTap: (quote.nothingToDo || blocked || prereq != null) ? null : () => p.confirm(context),
          ),
      ]),
    );
  }

  String _label(RoadmapQuote q, String symbol) {
    if (q.nothingToDo) return 'roadmap_all_enrolled'.tr;
    final fees = q.fees;
    if (fees == null) return '${'roadmap_enroll_free_prefix'.tr} ${q.freeCount} ${'roadmap_course_unit'.tr}';
    return '${'roadmap_enroll_and_pay'.tr} ${fees.fmt(fees.total)} $symbol';
  }
}

class _PrereqBlocked extends StatelessWidget {
  final Map<String, dynamic> reason;
  const _PrereqBlocked({required this.reason});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final blocked = (reason['blocked'] as List?)?.length ?? 0;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(color: c.warning.withValues(alpha: .12), shape: BoxShape.circle),
            child: Icon(Icons.lock_clock_rounded, color: c.warning, size: 36),
          ),
          const SizedBox(height: 14),
          Text('roadmap_prereq_title'.tr, style: c.h3, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            blocked > 0 ? '${'roadmap_prereq_body'.tr} ($blocked)' : 'roadmap_prereq_body'.tr,
            style: c.caption.copyWith(height: 1.6),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: 220,
            child: SoftOutlineButton(label: 'roadmap_prereq_see_why'.tr, onTap: () => showEnrollBlock(context, reason)),
          ),
        ]),
      ),
    );
  }
}

class _CardUnavailableBanner extends StatelessWidget {
  const _CardUnavailableBanner();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.danger.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.danger.withValues(alpha: .25)),
      ),
      child: Row(children: [
        Icon(Icons.info_outline_rounded, color: c.danger, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text('roadmap_card_unavailable'.tr, style: c.caption.copyWith(height: 1.5))),
      ]),
    );
  }
}

class _Intro extends StatelessWidget {
  final String? courseName;
  final RoadmapQuote quote;
  const _Intro({required this.courseName, required this.quote});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final parts = <String>[
      if (quote.payableCount > 0) '${quote.payableCount} ${'roadmap_paid'.tr}',
      if (quote.freeCount > 0) '${quote.freeCount} ${'roadmap_free'.tr}',
      if (quote.ownedCount > 0) '${quote.ownedCount} ${'roadmap_already_enrolled'.tr}',
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.primary.withValues(alpha: .08), c.cardBg],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.primary.withValues(alpha: .15)),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: c.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.map_rounded, color: c.primary, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(courseName == null ? 'roadmap_default_title'.tr : '${'roadmap_label'.tr}: $courseName',
                style: c.h3.copyWith(fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text('${quote.items.length} ${'roadmap_courses_word'.tr} · ${parts.join(' · ')}', style: c.caption),
          ]),
        ),
      ]),
    );
  }
}

class _RoadmapItemTile extends StatelessWidget {
  final RoadmapItem item;
  final bool isLast;
  final String currencySymbol;
  const _RoadmapItemTile({required this.item, required this.isLast, required this.currencySymbol});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final owned = item.state == RoadmapItemState.owned;

    final (String tag, Color tone) = switch (item.state) {
      RoadmapItemState.owned => ('enrolled'.tr, c.success),
      RoadmapItemState.free => ('free'.tr, c.success),
      RoadmapItemState.payable => ('${item.price.toStringAsFixed(2)} $currencySymbol', c.primary),
    };

    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // timeline rail
        SizedBox(
          width: 28,
          child: Column(children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: owned ? c.success : c.primary.withValues(alpha: .12),
                border: Border.all(color: owned ? c.success : c.primary, width: 1.5),
              ),
              child: Icon(owned ? Icons.check_rounded : Icons.circle,
                  size: owned ? 13 : 6, color: owned ? Colors.white : c.primary),
            ),
            if (!isLast) Expanded(child: Container(width: 2, color: c.divider)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: item.isCurrent ? c.primary : c.divider, width: item.isCurrent ? 1.6 : 1),
              boxShadow: c.cardShadow,
            ),
            child: Opacity(
              opacity: owned ? .65 : 1,
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AppNetworkImage(
                    url: item.imageUrl,
                    width: 56,
                    height: 56,
                    heroTag: 'roadmap-enroll-${item.courseId}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (item.isCurrent)
                      Text('roadmap_current_course'.tr,
                          style: c.caption.copyWith(color: c.primary, fontWeight: FontWeight.w700, fontSize: 10)),
                    Text(item.name,
                        style: c.label.copyWith(fontWeight: FontWeight.w700, fontSize: 14),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(tag,
                          style: c.caption.copyWith(color: tone, fontWeight: FontWeight.w800, fontSize: 11)),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}