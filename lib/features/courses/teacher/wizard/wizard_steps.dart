// features/courses/teacher/wizard/wizard_steps.dart — the seven steps of the course wizard (Tea1Wizard) and what the
// form says about each: the issue that stops Next, the one-line summary of the review step, "ready n of 5".
// Plain functions over the draft and the provider, so the shell, the steps and the tests share one answer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/features/courses/course_setup_views.dart' show courseAreaRequiredText, courseDeliveryLabel;
import 'package:flutter_education_app/features/courses/teacher/course_form_provider.dart';
import 'package:flutter_education_app/features/courses/teacher/course_privacy_card.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/course_form_draft.dart';
import 'package:flutter_education_app/features/home/student/models.dart' show AppCurrencyX;
import 'package:flutter_education_app/features/calendar/recurrence/recurrence_rule.dart' show recurrenceDayName;
import 'package:flutter_education_app/features/home/teacher/schedules/schedules_provider.dart' show kDayOrder;

enum CourseWizardStep {
  basics(Icons.notes_rounded, 't1_wz_s_basics'),
  pricing(Icons.account_balance_wallet_outlined, 't1_wz_s_pricing'),
  audience(Icons.school_outlined, 't1_wz_s_audience'),
  privacy(Icons.shield_outlined, 't1_wz_s_privacy'),
  schedule(Icons.calendar_month_outlined, 't1_wz_s_schedule'),
  extras(Icons.add_circle_outline_rounded, 't1_wz_s_extras'),
  review(Icons.fact_check_outlined, 't1_wz_s_review');

  const CourseWizardStep(this.icon, this.labelKey);

  final IconData icon;
  final String labelKey;

  String get label => labelKey.tr;
}

/// The "Step n of 7: Basics" line.
String wizardStepLine(CourseWizardStep s) =>
    '${'t1_wz_step_word'.tr} ${s.index + 1} ${'t1_wz_of'.tr} ${CourseWizardStep.values.length}: ${s.label}';

/// The "Next: Pricing" line (the last step says Publish).
String wizardNextLine(CourseWizardStep s) {
  final next = s.index + 1 < CourseWizardStep.values.length ? CourseWizardStep.values[s.index + 1].label : 't1_wz_publish_word'.tr;
  return '${'t1_wz_next_is'.tr}: $next';
}

/// What stops the teacher leaving [step] (null: nothing). Field validators show their own text on the visible step;
/// this is the same rule for a step that is not on screen (the final save checks every step).
String? wizardStepIssue(CourseWizardStep step, CourseFormDraft d, CourseFormProvider p) {
  switch (step) {
    case CourseWizardStep.basics:
      return d.hasBasics ? null : 'cf_title_required'.tr;
    case CourseWizardStep.pricing:
      final v = d.discountPercent.text.trim();
      if (v.isEmpty) return null;
      final n = double.tryParse(v);
      return (n == null || n <= 0 || n > 100) ? 'discount_percentage_validator'.tr : null;
    case CourseWizardStep.audience:
      return p.deliveryMode != 'online' && p.area1 == null ? courseAreaRequiredText() : null;
    case CourseWizardStep.privacy:
      return CoursePrivacyCard.validateCode(d.isPrivate, d.accessCode.text);
    case CourseWizardStep.schedule:
    case CourseWizardStep.extras:
    case CourseWizardStep.review:
      return null;
  }
}

/// The first step with an issue, or null.
CourseWizardStep? wizardFirstIssue(CourseFormDraft d, CourseFormProvider p) {
  for (final s in CourseWizardStep.values) {
    if (wizardStepIssue(s, d, p) != null) return s;
  }
  return null;
}

/// The five things the review counts: title, price, audience, privacy, weekly times.
List<bool> wizardReadiness(CourseFormDraft d, CourseFormProvider p) => [
      d.hasBasics,
      (double.tryParse(d.price.text) ?? 0) > 0,
      p.targets.isNotEmpty && wizardStepIssue(CourseWizardStep.audience, d, p) == null,
      wizardStepIssue(CourseWizardStep.privacy, d, p) == null,
      p.form.schedules.isNotEmpty || p.pendingSchedules.isNotEmpty,
    ];

String _num(double? v) {
  if (v == null) return '';
  return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

/// A price per month of a plan of [months] months, "37.5" (empty when the price is not a number).
String wizardPerMonth(String priceText, int months) {
  final v = double.tryParse(priceText);
  if (v == null || v <= 0) return '';
  final per = v / months;
  return per == per.roundToDouble() ? per.toStringAsFixed(0) : per.toStringAsFixed(1);
}

/// "Sunday" of the server's day key ('sunday').
String wizardDayName(String key) {
  final i = kDayOrder.indexOf(key);
  return i < 0 ? key : recurrenceDayName(i);
}

/// "7:30 PM – 8:20 PM".
String wizardRange(String start, String end) => '${AppTime.clock(start)} – ${AppTime.clock(end)}';

/// Minutes between two "HH:MM" strings (0 when they do not parse or run backwards).
int wizardMinutes(String start, String end) {
  int? m(String s) {
    final p = s.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]), mi = int.tryParse(p[1]);
    return h == null || mi == null ? null : h * 60 + mi;
  }

  final a = m(start), b = m(end);
  return a == null || b == null || b <= a ? 0 : b - a;
}

/// The review's lines for [step]: (title, one or two sentences).
String wizardSummary(CourseWizardStep step, CourseFormDraft d, CourseFormProvider p) {
  final cur = p.selectedCurrency.symbol;
  final ar = AppConfig.lang == 'ar';
  String join(List<String> parts) => parts.where((e) => e.trim().isNotEmpty).join(ar ? '، ' : ', ');
  switch (step) {
    case CourseWizardStep.basics:
      final title = (ar ? d.titleAr.text : d.titleEn.text).trim();
      final fallback = (ar ? d.titleEn.text : d.titleAr.text).trim();
      final type = switch ((p.selectedTeachingType?['text'] as String?) ?? 'recorded') {
        'live' => 'cf_type_live'.tr,
        'both' => 'cf_type_both'.tr,
        _ => 'cf_type_recorded'.tr,
      };
      final spec = '${p.selectedSpecialization?['text'] ?? ''}';
      return join([title.isEmpty ? fallback : title, type, spec]);
    case CourseWizardStep.pricing:
      final y = double.tryParse(d.price.text);
      final six = double.tryParse(d.priceSixMonths.text);
      final mo = double.tryParse(d.priceMonthly.text);
      final def = p.defaultPlanIndex;
      final parts = <String>[
        if (y != null) '${'t1_wz_plan_year'.tr} ${_num(y)} $cur${def == 0 ? ' (${'t1_wz_default_short'.tr})' : ''}',
        if (six != null) '${'t1_wz_plan_six'.tr} ${_num(six)}${def == 1 ? ' (${'t1_wz_default_short'.tr})' : ''}',
        if (mo != null) '${'t1_wz_plan_month'.tr} ${_num(mo)}${def == 2 ? ' (${'t1_wz_default_short'.tr})' : ''}',
      ];
      final dp = double.tryParse(d.discountPercent.text);
      if (dp != null && dp > 0) {
        final days = int.tryParse(d.discountDays.text);
        parts.add('${'t1_wz_discount_short'.tr} ${_num(dp)}%${days == null ? '' : ' ${'t1_wz_for'.tr} $days ${'t1_wz_days_short'.tr}'}');
      }
      return parts.isEmpty ? 't1_wz_none'.tr : join(parts);
    case CourseWizardStep.audience:
      final targets = p.targets.map((t) => t.label).toList();
      return join([...targets, courseDeliveryLabel(p.deliveryMode), if (p.area1 != null) '${p.area1!.name}${p.area2 == null ? '' : ' / ${p.area2!.name}'}']);
    case CourseWizardStep.privacy:
      final hrs = double.tryParse(d.hours.text);
      return join([
        d.isPrivate ? 't1_wz_private_short'.tr + (d.accessCode.text.isEmpty ? '' : ' ${d.accessCode.text}') : 't1_wz_public_short'.tr,
        if (hrs != null && hrs > 0) '${_num(hrs)} ${'t1_wz_hours_short'.tr}',
      ]);
    case CourseWizardStep.schedule:
      final all = [
        ...p.form.schedules.map((s) => '${wizardDayName(s.day)} ${AppTime.clock(s.startTime)}'),
        ...p.pendingSchedules.map((s) => '${wizardDayName(s.day)} ${AppTime.clock(s.startTime)}'),
      ];
      return all.isEmpty ? 't1_wz_no_slots_short'.tr : join(all);
    case CourseWizardStep.extras:
      final parts = [
              if (d.reelCtrl.hasPending || d.reelCtrl.existingUrl != null) 't1_wz_video'.tr,
              if (p.form.certificates.isNotEmpty) 'certificates_section'.tr,
              if (p.form.tools.isNotEmpty) 'tools_section'.tr,
              if (p.form.prerequisites.isNotEmpty) 'prerequisites_section'.tr,
      ];
      return parts.isEmpty ? 't1_wz_none'.tr : join(parts);
    case CourseWizardStep.review:
      return '';
  }
}
