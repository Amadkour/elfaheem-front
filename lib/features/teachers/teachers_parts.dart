// lib/features/teachers/teachers_parts.dart — small pieces the teacher and package screens share (plain values, no
// API): choice chips, subject badges, the rating line, the counts in both languages, a package's card and the
// package wizard's live summary.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/calendar/recurrence/recurrence_rule.dart' show RecurrenceRule, describeRule;
import 'package:flutter_education_app/features/teachers/teachers_models.dart';

// ── counts ───────────────────────────────────────────────────────────────────

String sessionsText(int n) =>
    countText(n, ar1: 'جلسة واحدة', ar2: 'جلستان', arFew: '{n} جلسات', arMany: '{n} جلسة', en1: '1 session', en: '{n} sessions');

String minutesText(int n) =>
    countText(n, ar1: 'دقيقة واحدة', ar2: 'دقيقتان', arFew: '{n} دقائق', arMany: '{n} دقيقة', en1: '1 minute', en: '{n} minutes');

String seatsLeftText(int n) => countText(n,
    ar0: 'لا مقاعد متبقية',
    en0: 'No seats left',
    ar1: 'مقعد واحد متبقٍ',
    ar2: 'مقعدان متبقيان',
    arFew: '{n} مقاعد متبقية',
    arMany: '{n} مقعداً متبقياً',
    en1: '1 seat left',
    en: '{n} seats left');

String studentsText(int n) =>
    countText(n, ar1: 'طالب واحد', ar2: 'طالبان', arFew: '{n} طلاب', arMany: '{n} طالباً', en1: '1 student', en: '{n} students');

String reviewsText(int n) => countText(n,
    ar0: 'لا تقييمات بعد', en0: 'No reviews yet', ar1: 'تقييم واحد', ar2: 'تقييمان', arFew: '{n} تقييمات', arMany: '{n} تقييماً', en1: '1 review', en: '{n} reviews');

String packagesText(int n) =>
    countText(n, ar0: 'لا باقات', en0: 'No packages', ar1: 'باقة واحدة', ar2: 'باقتان', arFew: '{n} باقات', arMany: '{n} باقة', en1: '1 package', en: '{n} packages');

String yearsText(int n) =>
    countText(n, ar1: 'سنة واحدة', ar2: 'سنتان', arFew: '{n} سنوات', arMany: '{n} سنة', en1: '1 year', en: '{n} years');

String teachersText(int n) =>
    countText(n, ar1: 'معلم واحد', ar2: 'معلمان', arFew: '{n} معلمين', arMany: '{n} معلماً', en1: '1 teacher', en: '{n} teachers');

/// "3 of 10 seats": the noun follows the total.
String seatsTakenText(int taken, int max) => countText(max,
    ar1: '$taken من مقعد واحد', ar2: '$taken من مقعدين', arFew: '$taken من {n} مقاعد', arMany: '$taken من {n} مقعداً', en1: '$taken of 1 seat', en: '$taken of {n} seats');

String waitingText(int n) => countText(n,
    ar1: 'طالب واحد في الانتظار', ar2: 'طالبان في الانتظار', arFew: '{n} طلاب في الانتظار', arMany: '{n} طالباً في الانتظار', en1: '1 waiting', en: '{n} waiting');

/// Languages a teacher can tick (codes are what the profile stores).
const List<String> kTeacherLanguages = ['ar', 'en', 'fr', 'ur', 'tr', 'id'];

String teacherLanguageLabel(String code) => switch (code) {
      'ar' => t('العربية', 'Arabic'),
      'en' => t('الإنجليزية', 'English'),
      'fr' => t('الفرنسية', 'French'),
      'ur' => t('الأردية', 'Urdu'),
      'tr' => t('التركية', 'Turkish'),
      'id' => t('الإندونيسية', 'Indonesian'),
      _ => code,
    };

AppTone teacherStatusTone(String s) => switch (s) {
      'approved' => AppTone.success,
      'pending' => AppTone.warning,
      'rejected' => AppTone.danger,
      _ => AppTone.neutral,
    };

AppTone packageStatusTone(String s) => switch (s) {
      'published' => AppTone.success,
      'paused' => AppTone.warning,
      'closed' => AppTone.danger,
      _ => AppTone.neutral,
    };

IconData teacherSubjectIcon(String s) => switch (s) {
      'tajweed' => Icons.record_voice_over_rounded,
      'fiqh' => Icons.balance_rounded,
      'nahw' => Icons.spellcheck_rounded,
      _ => Icons.menu_book_rounded,
    };

/// A calendar day ("YYYY-MM-DD" on the wire) in the reader's words; drawn at noon UTC so no zone moves the day.
String packageDayLabel(DateTime day) => AppTime.date(DateTime.utc(day.year, day.month, day.day, 12));

/// The package's days and times in one sentence ("Every day except Fri and Sat, 10:00 AM to 11:00 AM, for 8
/// sessions"), the wizard's own words (describeRule, D-1648). The rule always ends after [sessionsCount] dates, and
/// the clock is the teacher's zone, named when it is not the reader's. Null: no schedule (times agreed with the
/// teacher).
String? packageScheduleText(Map<String, dynamic>? schedule, int sessionsCount) {
  final r = RecurrenceRule.fromJson(schedule);
  if (r == null) return null;
  final fixed = sessionsCount > 0 ? r.copyWith(count: sessionsCount, clearEnd: true) : r;
  return describeRule(fixed, AppConfig.lang, sessions: true, withZone: true);
}

/// The first session's day: the rule's first REAL date (a skipped start date moves on, D-1649), else [startDate].
DateTime? packageFirstDay(Map<String, dynamic>? schedule, DateTime? startDate) =>
    RecurrenceRule.fromJson(schedule)?.firstDate() ?? startDate;

/// "Starts Sun 29 Nov 2026" with the weekday, so the first day reads at a glance.
String packageStartsText(DateTime day) =>
    '${t('تبدأ', 'Starts')} ${AppTime.date(DateTime.utc(day.year, day.month, day.day, 12), pattern: 'EEE d MMM y')}';

/// A list in the reader's language: "Arabic, English" / "العربية، الإنجليزية" (D-1650).
String teachersJoin(Iterable<String> items) => items.join(t('، ', ', '));

/// The Arabic form for the teacher's gender (a woman reads "المعلمة"); English has one form.
String teacherG(String? gender, String ar, String arFemale, String en) => t(gender == 'female' ? arFemale : ar, en);

/// The text direction of text a person typed (a name, a bio): from its first strong letter, so Arabic reads right to
/// left in the English app and the other way round (D-1651). Null: no letters, the page's own direction.
TextDirection? userTextDirection(String text) {
  for (final r in text.runes) {
    if ((r >= 0x0590 && r <= 0x08FF) || (r >= 0xFB1D && r <= 0xFDFF) || (r >= 0xFE70 && r <= 0xFEFF)) return TextDirection.rtl;
    if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A) || (r >= 0xC0 && r <= 0x24F)) return TextDirection.ltr;
  }
  return null;
}

/// A [Text] of user-typed content laid out in its own direction and, as a paragraph, aligned to its own start
/// (D-1651). [block] false (a name, a title): only the direction; the line keeps its place in the page's layout, next
/// to its avatar.
class UserText extends StatelessWidget {
  const UserText(this.text, {super.key, this.style, this.maxLines, this.overflow, this.block = true});

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool block;

  @override
  Widget build(BuildContext context) {
    final dir = userTextDirection(text);
    final page = Directionality.of(context);
    if (!block && dir != null && dir != page) {
      // a name keeps the page's side (next to its avatar) and reads in its own direction
      return Text(text, style: style, maxLines: maxLines, overflow: overflow, textDirection: dir,
          textAlign: page == TextDirection.ltr ? TextAlign.left : TextAlign.right);
    }
    final own = Text(text, style: style, maxLines: maxLines, overflow: overflow, textDirection: dir, textAlign: TextAlign.start);
    if (!block || dir == null || dir == page) return own;
    // the other direction from the page's: its start is the other side, so the block sits there too
    return Directionality(textDirection: dir, child: Align(alignment: AlignmentDirectional.centerStart, child: own));
  }
}

/// A title with a status chip at the line's trailing edge (D-1650): the chip keeps its own width (up to half the
/// line, then it ellipsizes) and the title takes the rest. A `Flexible` chip beside an `Expanded` title split the
/// line in half and left the chip floating mid-card on a wide window.
class TitleWithStatus extends StatelessWidget {
  const TitleWithStatus({super.key, required this.title, required this.status});

  final Widget title, status;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: title),
          const SizedBox(width: AppSpace.xs),
          ConstrainedBox(constraints: BoxConstraints(maxWidth: box.maxWidth / 2), child: status),
        ]),
      );
}

/// The name a person's avatar takes its letter from: without the titles ("الشيخ", "الأستاذة", "د.") and the article
/// "ال", so "الأستاذة منى" shows "م", not "ا" (D-1652).
String teacherInitialName(String name) {
  const titles = {
    'الشيخ', 'الشيخة', 'الأستاذ', 'الأستاذة', 'الاستاذ', 'الاستاذة', 'أ.', 'د.', 'دكتور', 'دكتورة', 'الدكتور',
    'الدكتورة', 'المعلم', 'المعلمة', 'Sheikh', 'Dr.', 'Mr.', 'Mrs.', 'Ms.',
  };
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final rest = words.where((w) => !titles.contains(w)).toList();
  var w = rest.isNotEmpty ? rest.first : (words.isNotEmpty ? words.first : '');
  if (w.startsWith('ال') && w.length > 3) w = w.substring(2);
  return w.isEmpty ? (name.trim().isEmpty ? '?' : name) : w;
}

// ── chips ────────────────────────────────────────────────────────────────────

/// A labelled row of choice chips (one or many). [keyPrefix] names each chip's ValueKey.
class TeachersChoiceRow extends StatelessWidget {
  const TeachersChoiceRow({
    super.key,
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onTap,
    this.keyPrefix = 'chip',
    this.enabled = true,
    this.required = false,
    this.helper,
  });

  final String label;
  final List<String> values;
  final bool Function(String v) selected;
  final String Function(String v) labelOf;
  final ValueChanged<String> onTap;
  final String keyPrefix;
  final bool enabled, required;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppFieldLabel(label, required: required),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final v in values)
          AppChoiceChip(
            key: ValueKey('$keyPrefix.$v'),
            label: labelOf(v),
            selected: selected(v),
            onTap: enabled ? () => onTap(v) : () {},
          ),
      ]),
      if (helper != null) ...[
        const SizedBox(height: AppSpace.xxs),
        Text(helper!, style: AppType.meta(context).copyWith(color: c.textMedium)),
      ],
    ]);
  }
}

class TeacherSubjectBadges extends StatelessWidget {
  const TeacherSubjectBadges({super.key, required this.subjects});

  final List<String> subjects;

  @override
  Widget build(BuildContext context) => Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final s in subjects) AppStatusBadge(label: teacherSubjectLabel(s), tone: AppTone.brand, icon: teacherSubjectIcon(s), dense: true),
      ]);
}

/// "★ 4.8 · 12 reviews" (or "No reviews yet").
class TeacherRatingLine extends StatelessWidget {
  const TeacherRatingLine({super.key, required this.rating, required this.count, this.color});

  final double? rating;
  final int count;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = color ?? c.textMedium;
    final r = rating;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.star_rounded, size: AppIconSize.sm, color: r == null ? ink : c.accent2),
      const SizedBox(width: AppSpace.xxs),
      Flexible(
        child: Text(
          r == null || count == 0 ? reviewsText(0) : '${r.toStringAsFixed(1)} · ${reviewsText(count)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.meta(context).copyWith(color: ink),
        ),
      ),
    ]);
  }
}

/// The price with the original struck through when a discount applies.
class PackagePriceText extends StatelessWidget {
  const PackagePriceText({super.key, required this.price, required this.finalPrice, required this.currency, this.discountPercent});

  final double price, finalPrice;
  final String currency;
  final int? discountPercent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final discounted = (discountPercent ?? 0) > 0 && price > 0;
    return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text(packagePriceLabel(finalPrice, currency),
          style: AppType.figure(context).copyWith(color: finalPrice <= 0 ? c.success : c.textDark)),
      if (discounted) ...[
        Text(packagePriceLabel(price, currency),
            style: AppType.meta(context).copyWith(color: c.textLight, decoration: TextDecoration.lineThrough)),
        AppStatusBadge(label: t('خصم $discountPercent٪', '$discountPercent% off'), tone: AppTone.warning, dense: true),
      ],
    ]);
  }
}

// ── package card (student side) ──────────────────────────────────────────────

/// One package on a teacher's page / list: title, the facts, seats left, the price and the join state.
class PackageCard extends StatelessWidget {
  const PackageCard({super.key, required this.package, this.onTap, this.showTeacher = false});

  final TeacherPackage package;
  final VoidCallback? onTap;
  final bool showTeacher;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = package;
    final state = packageJoinState(p);
    final mine = packageJoinMine(state);
    return AppCard(
      key: ValueKey('package.card.${p.id}'),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(teacherSubjectIcon(p.subject), size: AppIconSize.lg, color: c.primary),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              UserText(p.title, block: false, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: c.textDark)),
              const SizedBox(height: AppSpace.xxs),
              Text(
                [
                  teacherSubjectLabel(p.subject),
                  packageLevelLabel(p.level),
                  packageDeliveryLabel(p.delivery),
                  if (showTeacher && (p.teacher?.name ?? '').isNotEmpty) p.teacher!.name,
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.meta(context).copyWith(color: c.textMedium),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.sm),
        AppInfoRow(Icons.event_repeat_rounded, '${sessionsText(p.sessionsCount)} × ${minutesText(p.sessionMinutes)}'),
        if (packageScheduleText(p.schedule, p.sessionsCount) case final sched?)
          KeyedSubtree(key: ValueKey('package.card.schedule.${p.id}'), child: AppInfoRow(Icons.schedule_rounded, sched)),
        if (packageFirstDay(p.schedule, p.startDate) case final first?) AppInfoRow(Icons.event_rounded, packageStartsText(first)),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.xs,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PackagePriceText(price: p.price, finalPrice: p.finalPrice, currency: p.currency, discountPercent: p.discountPercent),
            AppStatusBadge(
              label: mine
                  ? packageJoinLabel(state, position: p.myEnrollment?.position)
                  // full with an open waiting list is still a way in, not a dead end (D-1653)
                  : state == PackageJoinState.joinWaitlist
                      ? t('قائمة انتظار مفتوحة', 'Waiting list open')
                      : seatsLeftText(p.seatsLeft),
              tone: mine
                  ? switch (state) {
                      PackageJoinState.active => AppTone.success,
                      PackageJoinState.offered => AppTone.gold,
                      _ => AppTone.warning,
                    }
                  : state == PackageJoinState.joinWaitlist
                      ? AppTone.warning
                      : p.isFull
                          ? AppTone.danger
                          : AppTone.info,
              dense: true,
            ),
          ],
        ),
      ]),
    );
  }
}

// ── the package wizard's live summary ────────────────────────────────────────

class PackageSummaryCard extends StatelessWidget {
  const PackageSummaryCard({super.key, required this.draft});

  final PackageDraft draft;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = draft;
    final total = d.finalPrice;
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: AppInfoRow(icon, text),
        );
    return AppCard(
      key: const ValueKey('package.summary'),
      highlight: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(t('ملخص الباقة', 'Package summary'), style: AppType.overline(context).copyWith(color: c.textMedium)),
        const SizedBox(height: AppSpace.xs),
        Text(d.title.trim().isEmpty ? t('بلا عنوان بعد', 'No title yet') : d.title.trim(),
            maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: c.textDark)),
        const SizedBox(height: AppSpace.sm),
        line(Icons.menu_book_rounded,
            '${d.subject == null ? t('المادة لم تُختر', 'No subject yet') : teacherSubjectLabel(d.subject!)} · ${packageLevelLabel(d.level)}'),
        line(Icons.place_rounded,
            d.needsLocation && d.location.trim().isNotEmpty ? '${packageDeliveryLabel(d.delivery)} · ${d.location.trim()}' : packageDeliveryLabel(d.delivery)),
        line(Icons.event_repeat_rounded, '${sessionsText(d.sessionsCount)} × ${minutesText(d.sessionMinutes)}'),
        line(Icons.schedule_rounded,
            packageScheduleText(d.schedule, d.sessionsCount) ?? t('بلا جدول: تتفق على المواعيد مع طلابك', 'No schedule: you agree the times with your students')),
        if (packageFirstDay(d.schedule, d.startDate) case final first?) line(Icons.event_rounded, packageStartsText(first)),
        line(Icons.groups_rounded, [
          studentsText(d.maxStudents),
          packageOverbookLabel(d.overbook),
          if (d.overbook == 'allow') d.overbookLimit == null ? t('بلا حد', 'no limit') : t('حتى ${d.overbookLimit} إضافية', 'up to ${d.overbookLimit} extra'),
        ].join(' · ')),
        const SizedBox(height: AppSpace.xs),
        PackagePriceText(price: d.price, finalPrice: total, currency: d.currency, discountPercent: d.discountPercent),
        if (d.maxStudents > 0 && total > 0) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(
            '${t('عند الاكتمال', 'When full')}: ${packagePriceLabel(packageFinalPrice(total * d.maxStudents, 0), d.currency)}',
            style: AppType.meta(context).copyWith(color: c.textMedium),
          ),
        ],
      ]),
    );
  }
}
