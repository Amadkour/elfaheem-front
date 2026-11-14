// lib/features/admin/landing/landing_admin_widgets.dart
//
// The plain-value pieces of the super admin's "Landing page" screen: data + callbacks in, no provider, no network,
// so the layout harness can pump every one of them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppCountUp;

import '../admin_common.dart' show t;
import 'landing_admin_api.dart';

// ── small shared bits ────────────────────────────────────────────────────────

class _StarRow extends StatelessWidget {
  const _StarRow(this.stars);
  final int stars;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: t('$stars من 5 نجوم', '$stars out of 5 stars'),
      child: ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 1; i <= 5; i++)
            Icon(i <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 16, color: i <= stars ? c.warning : c.textLight),
        ]),
      ),
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: AppTouch.min - AppSpace.xs,
          height: AppTouch.min - AppSpace.xs,
          decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.controlAll),
          child: Icon(icon, size: AppIconSize.md, color: c.textDark),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppType.section(context)),
            const SizedBox(height: AppSpace.xxs),
            Text(subtitle, style: AppType.meta(context).copyWith(height: 1.45)),
          ]),
        ),
      ]),
    );
  }
}

/// "Course" / "Teacher" chip with the subject: the same line visitors see under a testimonial.
Widget _subjectChip(BuildContext context, LandingReview r) {
  final s = r.subject;
  if (s == null) return const SizedBox.shrink();
  final c = context.colors;
  final color = r.kind == 'teacher' ? c.warning : c.primary;
  // AppTag's look, with the course / teacher name in its own language's direction and font (_ownText)
  final tint = appTintOn(context, color);
  final ink = appInkOn(context, color, tint);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
    decoration: BoxDecoration(color: tint, borderRadius: const BorderRadius.all(Radius.circular(AppRadius.pill))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(r.kind == 'teacher' ? Icons.person_rounded : Icons.menu_book_rounded, size: AppIconSize.xs, color: ink),
      const SizedBox(width: AppSpace.xxs),
      Flexible(child: _ownText(s, AppType.overline(context).copyWith(letterSpacing: 0, color: ink), maxLines: 1)),
    ]),
  );
}

// ── 1. the rate limit ───────────────────────────────────────────────────────

class LandingRateLimitCard extends StatelessWidget {
  const LandingRateLimitCard({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.dirty,
    required this.saving,
    required this.onChanged,
    required this.onSave,
  });

  final LandingRateLimit value;
  final int min;
  final int max;
  final bool dirty;
  final bool saving;
  final ValueChanged<LandingRateLimit> onChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = value.perMinute.clamp(min, max);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SectionHead(
          icon: Icons.shield_outlined,
          title: t('حماية أرقام الصفحة الرئيسية', 'Public numbers protection'),
          subtitle: t(
              'تحمي الأرقام العامة التي تظهر في الصفحة الرئيسية: عند تجاوز الزائر الحد في الدقيقة يرد الخادم بخطأ 429 حتى تنتهي الدقيقة.',
              'Protects the public numbers on the landing page: a visitor above the limit per minute gets a 429 until the minute ends.'),
        ),
        AppSwitchTile(
          icon: Icons.speed_rounded,
          title: t('تحديد عدد الطلبات', 'Limit requests'),
          subtitle: value.enabled
              ? t('مفعّل: يُحسب الحد لكل عنوان زائر.', 'On: the limit is counted per visitor.')
              : t('متوقف: لا يوجد حد على الطلبات.', 'Off: requests are not limited.'),
          value: value.enabled,
          onChanged: saving ? null : (on) => onChanged(value.copyWith(enabled: on)),
        ),
        const SizedBox(height: AppSpace.xxs),
        Opacity(
          opacity: value.enabled ? 1 : 0.45,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: AppSpace.xs, children: [
              AppCountUp('$v', memoryKey: 'landing.rate_limit', style: AppType.figureLarge(context)),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xxs),
                child: Text(t('طلب في الدقيقة لكل زائر', 'requests per minute per visitor'),
                    style: AppType.meta(context).copyWith(color: c.textMedium)),
              ),
            ]),
            Slider(
              min: min.toDouble(),
              max: max.toDouble(),
              value: v.toDouble(),
              label: '$v',
              onChanged: (value.enabled && !saving) ? (x) => onChanged(value.copyWith(perMinute: x.round())) : null,
            ),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('$min', style: AppType.meta(context).copyWith(color: c.textLight)),
              Text('$max', style: AppType.meta(context).copyWith(color: c.textLight)),
            ]),
          ]),
        ),
        const SizedBox(height: AppSpace.md),
        AppButton.primary(
          label: t('حفظ', 'Save'),
          icon: Icons.check_rounded,
          busy: saving,
          expand: true,
          onPressed: dirty && !saving ? onSave : null,
        ),
      ]),
    );
  }
}

// ── 2. the featured testimonials ────────────────────────────────────────────

bool _hasArabic(String s) => s.codeUnits.any((u) =>
    (u >= 0x0600 && u <= 0x06FF) || (u >= 0x0750 && u <= 0x077F) || (u >= 0x08A0 && u <= 0x08FF) ||
    (u >= 0xFB50 && u <= 0xFDFF) || (u >= 0xFE70 && u <= 0xFEFF));

/// A review's text or name in its OWN language, whatever the UI language: its direction (an English review in the
/// Arabic UI keeps its full stop at the end, and starts on the left as on the landing page) and that language's chosen
/// font (a Latin UI font has no Arabic glyphs). [fill] stretches it so a short line still starts on its own side.
Widget _ownText(String s, TextStyle style, {int? maxLines, bool fill = false}) {
  final ar = _hasArabic(s);
  final text = Text(s,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      style: style.copyWith(
          fontFamily: ar ? AppFonts.arabicChoice.family : AppFonts.latinChoice.family,
          fontFamilyFallback: AppFonts.fallback));
  return fill ? SizedBox(width: double.infinity, child: text) : text;
}

/// Exactly what a visitor will see: the public name, stars, text and the course / teacher chip.
class LandingReviewPreview extends StatelessWidget {
  const LandingReviewPreview({super.key, required this.review});
  final LandingReview review;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: AppRadius.cardAll,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _StarRow(review.stars),
        const SizedBox(height: AppSpace.xs),
        _ownText(review.text, AppType.body(context).copyWith(color: c.textDark, height: 1.55), maxLines: 8, fill: true),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _ownText(review.displayName, AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
          _subjectChip(context, review),
        ]),
      ]),
    );
  }
}

class LandingTestimonialsCard extends StatelessWidget {
  const LandingTestimonialsCard({
    super.key,
    required this.reviews,
    required this.dirty,
    required this.saving,
    required this.onReorder,
    required this.onRemove,
    required this.onAdd,
    required this.onSave,
  });

  final List<LandingReview> reviews;
  final bool dirty;
  final bool saving;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<int> onRemove;
  final VoidCallback onAdd;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SectionHead(
          icon: Icons.format_quote_rounded,
          title: t('آراء الطلاب في الصفحة الرئيسية', 'Testimonials on the landing page'),
          subtitle: t(
              'تقييمات حقيقية كتبها الطلاب فقط، وتظهر بالاسم الأول مع حرف من اسم العائلة. اسحب لإعادة الترتيب.',
              'Only real reviews students wrote, shown as first name + initial. Drag to reorder.'),
        ),
        if (reviews.isEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: c.inputBg,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: c.divider),
            ),
            child: Column(children: [
              Icon(Icons.rate_review_outlined, size: 30, color: c.textLight),
              const SizedBox(height: AppSpace.xs),
              Text(
                t('لم تُختر أي تقييمات — يبقى هذا القسم مخفياً في الصفحة الرئيسية حتى تختار تقييمات حقيقية.',
                    'No reviews chosen — the section stays hidden on the landing page until you pick real reviews.'),
                textAlign: TextAlign.center,
                style: AppType.meta(context).copyWith(color: c.textMedium, height: 1.5),
              ),
            ]),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: reviews.length,
            onReorderItem: saving ? (_, _) {} : onReorder,
            proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
            itemBuilder: (context, i) {
              final r = reviews[i];
              return Padding(
                key: ValueKey('landing_review_${r.id}'),
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: LandingReviewPreview(review: r)),
                  Column(children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: SizedBox(
                        width: AppTouch.min,
                        height: AppTouch.min,
                        child: Icon(Icons.drag_indicator_rounded, color: c.textMedium, semanticLabel: t('اسحب لإعادة الترتيب', 'Drag to reorder')),
                      ),
                    ),
                    IconButton(
                      tooltip: t('إزالة', 'Remove'),
                      icon: Icon(Icons.close_rounded, color: c.danger),
                      onPressed: saving ? null : () => onRemove(r.id),
                    ),
                  ]),
                ]),
              );
            },
          ),
        const SizedBox(height: AppSpace.xs),
        Text(
          countText(reviews.length,
                  ar1: 'تقييم واحد مختار',
                  ar2: 'تقييمان مختاران',
                  arFew: '${reviews.length} تقييمات مختارة',
                  arMany: '${reviews.length} تقييماً مختاراً',
                  ar0: 'لا تقييمات مختارة',
                  en1: '1 review chosen',
                  en: '${reviews.length} reviews chosen',
                  en0: 'No reviews chosen') +
              t(' (الحد الأقصى $kLandingMaxTestimonials)', ' (max $kLandingMaxTestimonials)'),
          style: AppType.meta(context).copyWith(color: c.textMedium),
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppButton.secondary(
            label: t('إضافة تقييمات', 'Add reviews'),
            icon: Icons.add_rounded,
            onPressed: saving ? null : onAdd,
          ),
          AppButton.primary(
            label: t('حفظ الترتيب', 'Save testimonials'),
            icon: Icons.check_rounded,
            busy: saving,
            onPressed: dirty && !saving ? onSave : null,
          ),
        ]),
      ]),
    );
  }
}

/// The page content once loaded: both cards under a short intro.
class LandingAdminBody extends StatelessWidget {
  const LandingAdminBody({
    super.key,
    required this.rate,
    required this.minPerMinute,
    required this.maxPerMinute,
    required this.rateDirty,
    required this.savingRate,
    required this.onRate,
    required this.onSaveRate,
    required this.reviews,
    required this.listDirty,
    required this.savingList,
    required this.onReorder,
    required this.onRemove,
    required this.onAdd,
    required this.onSaveList,
  });

  final LandingRateLimit rate;
  final int minPerMinute;
  final int maxPerMinute;
  final bool rateDirty;
  final bool savingRate;
  final ValueChanged<LandingRateLimit> onRate;
  final VoidCallback onSaveRate;
  final List<LandingReview> reviews;
  final bool listDirty;
  final bool savingList;
  final void Function(int, int) onReorder;
  final ValueChanged<int> onRemove;
  final VoidCallback onAdd;
  final VoidCallback onSaveList;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LandingRateLimitCard(
        value: rate,
        min: minPerMinute,
        max: maxPerMinute,
        dirty: rateDirty,
        saving: savingRate,
        onChanged: onRate,
        onSave: onSaveRate,
      ),
      const SizedBox(height: AppSpace.md),
      LandingTestimonialsCard(
        reviews: reviews,
        dirty: listDirty,
        saving: savingList,
        onReorder: onReorder,
        onRemove: onRemove,
        onAdd: onAdd,
        onSave: onSaveList,
      ),
    ]);
  }
}

// ── 3. the candidates sheet ─────────────────────────────────────────────────

class LandingCandidatesBody extends StatelessWidget {
  const LandingCandidatesBody({
    super.key,
    required this.items,
    required this.selectedIds,
    required this.total,
    required this.loading,
    required this.loadingMore,
    required this.hasMore,
    required this.error,
    required this.minStars,
    required this.kind,
    required this.onQuery,
    required this.onMinStars,
    required this.onKind,
    required this.onToggle,
    required this.onMore,
    required this.onRetry,
    required this.onDone,
  });

  final List<LandingReview> items;
  final Set<int> selectedIds;
  final int total;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? error;
  final int minStars;
  final String? kind;
  final ValueChanged<String> onQuery;
  final ValueChanged<int> onMinStars;
  final ValueChanged<String?> onKind;
  final ValueChanged<LandingReview> onToggle;
  final VoidCallback onMore;
  final VoidCallback onRetry;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = selectedIds.length;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppBanner(
        icon: Icons.verified_outlined,
        text: t(
            'التقييمات الحقيقية التي كتبها الطلاب فقط. تظهر الأسماء للزوار بالاسم الأول وحرف من اسم العائلة. الحد الأقصى $kLandingMaxTestimonials تقييماً.',
            'Only real reviews students wrote. Visitors see names as first name + initial. At most $kLandingMaxTestimonials reviews.'),
      ),
      const SizedBox(height: AppSpace.sm),
      AppSearchField(hint: t('ابحث بالنص أو الطالب أو الدورة', 'Search text, student or course'), onChanged: onQuery),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
        for (final s in const [5, 4, 3])
          ChoiceChip(
            showCheckmark: false,
            label: Text(s == 5 ? t('5 نجوم', '5 stars') : '$s+ ★'),
            selected: minStars == s,
            onSelected: (_) => onMinStars(s),
          ),
        ChoiceChip(
            showCheckmark: false,
            label: Text(t('الكل', 'All')),
            selected: kind == null,
            onSelected: (_) => onKind(null)),
        ChoiceChip(
            showCheckmark: false,
            label: Text(t('دورات', 'Courses')),
            selected: kind == 'course',
            onSelected: (_) => onKind('course')),
        ChoiceChip(
            showCheckmark: false,
            label: Text(t('معلمون', 'Teachers')),
            selected: kind == 'teacher',
            onSelected: (_) => onKind('teacher')),
      ]),
      const SizedBox(height: AppSpace.xs),
      Text(
        t('$n من $kLandingMaxTestimonials مختار', '$n of $kLandingMaxTestimonials chosen'),
        style: AppType.overline(context).copyWith(letterSpacing: 0, color: c.textMedium),
      ),
      const SizedBox(height: AppSpace.xs),
      if (loading)
        const AppListSkeleton(items: 3, withAvatar: false, padding: EdgeInsets.zero)
      else if (error != null)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
          const SizedBox(height: AppSpace.xs),
          Align(child: AppButton.tonal(label: t('إعادة المحاولة', 'Try again'), onPressed: onRetry)),
        ])
      else if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
          child: Text(t('لا توجد تقييمات مطابقة.', 'No matching reviews.'),
              textAlign: TextAlign.center, style: AppType.meta(context).copyWith(color: c.textMedium)),
        )
      else ...[
        for (final r in items) _CandidateRow(review: r, selected: selectedIds.contains(r.id), onTap: () => onToggle(r)),
        if (hasMore)
          Align(
            child: AppButton.tonal(
              label: t('عرض المزيد', 'Load more'),
              busy: loadingMore,
              onPressed: loadingMore ? null : onMore,
            ),
          ),
      ],
      const SizedBox(height: AppSpace.md),
      AppButton.primary(label: t('تم', 'Done'), icon: Icons.check_rounded, expand: true, onPressed: onDone),
    ]);
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({required this.review, required this.selected, required this.onTap});
  final LandingReview review;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = review;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Material(
        color: selected ? c.primaryTint : c.inputBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: selected ? c.primary : c.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Semantics(
            selected: selected,
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: AppBorder.focus),
                  child: Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: selected ? c.primary : c.textLight),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      _ownText(r.displayName, AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
                      if (r.studentName.isNotEmpty)
                        _ownText(r.studentName, AppType.meta(context).copyWith(color: c.textMedium)),
                    ]),
                    const SizedBox(height: AppSpace.xxs),
                    Wrap(spacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      _StarRow(r.stars),
                      if (r.createdAt != null) Text(AppTime.date(r.createdAt!), style: AppType.meta(context).copyWith(color: c.textLight)),
                    ]),
                    const SizedBox(height: AppSpace.xs),
                    _ownText(r.text, AppType.meta(context).copyWith(color: c.textDark, height: 1.5), maxLines: 5, fill: true),
                    if (r.subject != null) ...[
                      const SizedBox(height: AppSpace.xs),
                      _subjectChip(context, r),
                    ],
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
