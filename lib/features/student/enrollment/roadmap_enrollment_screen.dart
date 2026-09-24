/// roadmap_enrollment_screen.dart — enrol in a whole roadmap and pay for every
/// course on it in ONE checkout.
///
/// Open it from the course profile's roadmap card:
///   Navigator.of(context).push(MaterialPageRoute(
///     builder: (_) => RoadmapEnrollmentScreen(courseId: course.id, courseName: course.name)));
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/theme/app_theme.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/app_network_image.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
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
            title: ResultCopy.pendingTitle,
            message: 'تم استلام طلبك. سيتم تفعيل كورسات المسار تلقائياً خلال دقائق.',
            primaryLabel: 'العودة للرئيسية',
            onPrimary: () => popToHome(context),
          ),
        EnrollStep.success => PaymentResultView(
            key: const ValueKey('success'),
            kind: ResultKind.success,
            title: 'تم التسجيل في المسار! 🎉',
            message: count > 1
                ? 'تم تفعيل $count كورسات. يمكنك البدء الآن!'
                : 'تم تفعيل الكورس. يمكنك البدء الآن!',
            primaryLabel: 'ابدأ التعلم الآن',
            onPrimary: () => popToHome(context),
          ),
        EnrollStep.failed => PaymentResultView(
            key: const ValueKey('failed'),
            kind: ResultKind.failed,
            title: ResultCopy.failedTitle,
            message: p.failureReason ?? ResultCopy.failedFallback,
            primaryLabel: 'حاول مرة أخرى',
            onPrimary: p.backToMethod,
            secondaryLabel: 'العودة للرئيسية',
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

    Widget content;
    if (p.loadFailed) {
      content = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('تعذّر تحميل المسار', style: c.h3),
          const SizedBox(height: 16),
          SizedBox(width: 200, child: SoftOutlineButton(label: 'إعادة المحاولة', onTap: p.load)),
        ]),
      );
    } else if (quote == null) {
      content = const Center(child: AppLoadingIndicator());
    } else {
      content = SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(wide ? 32 : 20, 12, wide ? 32 : 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Intro(courseName: courseName, quote: quote),
          const SizedBox(height: 20),
          for (var i = 0; i < quote.items.length; i++)
            _RoadmapItemTile(
              item: quote.items[i],
              isLast: i == quote.items.length - 1,
              currencySymbol: p.currencySymbol,
            ),
          if (quote.fees != null) ...[
            const SizedBox(height: 12),
            FeeBreakdownCard(quote: quote.fees, currencySymbol: p.currencySymbol),
          ],
        ]),
      );
    }

    return CenteredBody(
      child: Column(children: [
        enrollAppBar('التسجيل في المسار'),
        Expanded(child: content),
        if (quote != null)
          EnrollConfirmBar(
            label: _label(quote, p.currencySymbol),
            loading: p.isLoading,
            onTap: quote.nothingToDo ? null : () => p.confirm(context),
          ),
      ]),
    );
  }

  String _label(RoadmapQuote q, String symbol) {
    if (q.nothingToDo) return 'أنت مسجّل في كل كورسات المسار';
    final fees = q.fees;
    if (fees == null) return 'سجّل مجاناً في ${q.freeCount} كورس';
    return 'سجّل وادفع ${fees.fmt(fees.total)} $symbol';
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
      if (quote.payableCount > 0) '${quote.payableCount} مدفوع',
      if (quote.freeCount > 0) '${quote.freeCount} مجاني',
      if (quote.ownedCount > 0) '${quote.ownedCount} مسجّل بالفعل',
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
            Text(courseName == null ? 'المسار التعليمي' : 'مسار: $courseName',
                style: c.h3.copyWith(fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text('${quote.items.length} كورسات · ${parts.join(' · ')}', style: c.caption),
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
      RoadmapItemState.owned => ('مسجّل', c.success),
      RoadmapItemState.free => ('مجاني', c.success),
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
                      Text('الكورس الحالي',
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
