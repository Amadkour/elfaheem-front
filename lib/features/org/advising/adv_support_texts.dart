// lib/features/org/advising/adv_support_texts.dart — the server error codes of Academic Advising Phase 7 (the backend's
// services/organization/advising/request_texts.py) → bilingual text. Spread into `advCodeTexts()` (adv_texts.dart),
// so `orgErrorText` toasts them; [advSupportErrorText] adds the numbers and the governance codes a request answers
// with in its own words.
library;

import 'package:flutter_education_app/core/api_client.dart' show ApiException;

import '../../admin/admin_common.dart' show asInt, asMap, asStr, t;
import 'adv_parts.dart' show advErrorText;
import 'adv_support_models.dart' show advChainProblemText, advPlanStatusLabel, advStageLabel;

Map<String, String> advSupportCodeTexts() => {
      'advising_request_not_draft': t('الطلب أُرسل بالفعل — لا يُعدَّل ولا يُحذف بعد الإرسال', 'The request was already sent — it cannot be edited or deleted after sending'),
      'advising_request_closed': t('هذا الطلب مغلق', 'This request is closed'),
      'advising_request_stage': t('الطلب انتقل إلى مرحلة أخرى — حدّث الصفحة', 'The request moved to another stage — refresh the page'),
      'advising_no_department': t('لا توجد إدارة إرشاد أكاديمي نشطة لاستقبال الطلبات — يفعّلها مدير المؤسسة',
          'There is no active Academic Advising department to receive requests — the organization admin switches it on'),
      'advising_stale': t('غيّر شخص آخر هذا العنصر — حمّلنا أحدث نسخة، أعد المحاولة', 'Someone else changed this — the latest version is loaded, try again'),
      'advising_bad_support_type': t('نوع الطلب غير معروف', 'That type of request is not known'),
      'advising_bad_target': t('الجهة المختارة لا تستقبل الإحالات — اختر إدارة خدمية نشطة', 'That department does not take referrals — choose an active service department'),
      'advising_accommodations_required': t('اختر التسهيلات المطلوبة', 'Choose the accommodations requested'),
      'advising_note_required': t('اكتب ملاحظة من ثلاثة أحرف على الأقل', 'Write a note of at least three characters'),
      'advising_chain_invalid': t('سلسلة الاعتماد غير صالحة', 'The approval chain is not valid'),
      'advising_plan_transition': t('لا يمكن نقل الخطة إلى هذه الحالة من حالتها الحالية — حدّث الصفحة', 'The plan cannot move to that status from where it is now — refresh the page'),
      'advising_bad_measure': t('مقياس الخطة غير صالح', 'The plan\'s measure is not valid'),
      'advising_accommodation_active': t('للطالب هذا التسهيل نشطاً بالفعل', 'The student already has this accommodation active'),
      'advising_bad_plan': t('الخطة تحتاج عنواناً وبنداً واحداً على الأقل (حتى 30 بنداً)، ولكل بند هدف', 'A plan needs a title and 1 to 30 items, each with a goal'),
    };

/// The text of an error answered by a request / plan / accommodation route: the chain's reason and step, the stage a
/// request moved to, a governance decision that came first; else [advErrorText].
String advSupportErrorText(ApiException e) {
  final d = asMap(ApiException.asMap(e.body)?['detail']);
  switch (e.code) {
    case 'advising_chain_invalid':
      final reason = asStr(d['reason']);
      if (reason.isNotEmpty) return advChainProblemText(reason, index: d.containsKey('index') ? asInt(d['index']) : null);
    case 'advising_request_stage':
      final stage = asStr(d['stage']);
      if (stage.isNotEmpty) {
        return t('الطلب الآن في مرحلة «${advStageLabel(stage)}» — حدّث الصفحة', 'The request is now at "${advStageLabel(stage)}" — refresh the page');
      }
    case 'already_decided':
      return t('صدر قرار في هذا الطلب بالفعل — حدّث الصفحة', 'This request has already been decided — refresh the page');
    case 'stale_version':
      return t('تغيّر الطلب منذ فتحه — حمّلنا أحدث نسخة، أعد المحاولة', 'The request changed since you opened it — the latest version is loaded, try again');
    case 'advising_client_id_conflict':
      return t('رقم المسودة استُخدم لطالب آخر — أعد الإرسال', 'That draft\'s id was used for another student — send it again');
    case 'advising_plan_transition':
      final current = asStr(d['current']);
      if (current.isNotEmpty) {
        return t('الخطة الآن «${advPlanStatusLabel(current)}» — حدّث الصفحة', 'The plan is now "${advPlanStatusLabel(current)}" — refresh the page');
      }
    case 'advising_bad_dates':
      return t('راجع التواريخ: لا يكون تاريخ النهاية أو المتابعة في الماضي ولا قبل تاريخ البداية',
          'Check the dates: an end or follow-up date cannot be in the past or before the start date');
    // Phase 4 codes worded for flags: here they are about a request / a plan / a grant
    case 'advising_bad_accommodation':
      return t('التسهيلات المختارة لا تتبع التصنيف المختار', 'The chosen accommodations do not belong to the chosen category');
    case 'advising_outcome_required':
      return t('اكتب خلاصة الخطة قبل إكمالها', 'Write the plan\'s outcome before completing it');
  }
  return advErrorText(e);
}

/// The codes a request answers that mean "someone else moved it first": the sheet closes and the page reloads.
const advSupportStaleCodes = {'already_decided', 'stale_version', 'advising_stale', 'advising_request_stage', 'advising_request_closed', 'advising_plan_transition'};
