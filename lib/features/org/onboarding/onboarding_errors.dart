// lib/features/org/onboarding/onboarding_errors.dart — bilingual texts of the onboarding error codes (contract §5),
// read by `orgErrorText` (org_v3.dart) like the governance and advising codes.
library;

import 'package:flutter_education_app/core/api_client.dart' show ApiException;

import '../../admin/admin_common.dart' show t;
import '../org_v3.dart' show orgParseUtc;

Map<String, String> onbCodeTexts() => {
      'nid_invalid': t('الرقم القومي غير صحيح', 'The national ID is not valid'),
      'nid_mismatch': t('الرقم القومي لا يطابق تاريخ الميلاد أو النوع', 'The national ID does not match the birth date or gender'),
      'phone_invalid': t('رقم الهاتف غير صالح', 'The phone number is not valid'),
      'email_invalid': t('البريد الإلكتروني غير صالح', 'The e-mail address is not valid'),
      'missing_required': t('ينقص بعض الحقول أو المستندات المطلوبة', 'Some required fields or documents are missing'),
      'duplicate_case': t('يوجد طلب مفتوح بنفس الرقم القومي', 'There is already an open case with this national ID'),
      'duplicate_member': t('هذا الشخص عضو في المؤسسة بالفعل', 'This person is already a member of the organization'),
      'bad_transition': t('لا يمكن تنفيذ هذا الإجراء في حالة الطلب الحالية', 'This action is not possible in the case\'s current state'),
      'step_forbidden': t('هذه المرحلة ليست من اختصاصك', 'This approval step is not yours to decide'),
      'doc_type': t('نوع الملف غير مسموح لهذا المستند', 'This file type is not allowed for this document'),
      'doc_too_large': t('حجم الملف أكبر من المسموح', 'The file is larger than allowed'),
      'type_inactive': t('هذا النوع غير مفعّل', 'This type is not active'),
      'type_not_found': t('النوع غير موجود', 'The type was not found'),
      'case_not_found': t('الطلب غير موجود — ربما حُذف', 'The case was not found: it may have been removed'),
      'batch_expired': t('انتهت صلاحية ملف الاستيراد، ارفعه من جديد', 'The import file expired; upload it again'),
      'intake_closed': t('باب التقديم مغلق', 'Applications are closed'),
      'onboarding_disabled': t('الالتحاق والتعيين غير مفعّل لهذه المؤسسة', 'Admissions & appointments is not switched on for this organization'),
'batch_not_found': t('ملف الاستيراد غير موجود، ارفعه من جديد', 'The import file was not found; upload it again'),      'batch_confirmed': t('تم تأكيد هذا الاستيراد من قبل', 'This import was already confirmed'),      'columns_missing': t('الملف لا يحوي أعمدة هذا النوع، استخدم القالب', 'The file lacks the columns of this type; use the template'),      'file_empty': t('الملف فارغ', 'The file is empty'),      'file_invalid': t('تعذرت قراءة الملف، استخدم xlsx أو csv', 'The file could not be read; use xlsx or csv'),      'file_too_large': t('الملف أكبر من المسموح (8 ميجابايت)', 'The file is larger than allowed (8 MB)'),      'too_many_rows': t('الملف يزيد عن 5000 صف', 'The file has more than 5000 rows'),      'duplicate_in_file': t('الرقم القومي مكرر داخل الملف', 'The national ID appears twice in the file'),      'no_contact': t('لا بريد ولا هاتف للدعوة', 'No e-mail or phone to invite'),      'intake_full': t('اكتملت سعة رابط التقديم', 'The intake link is full'),      'invalid_value': t('قيمة غير صالحة في أحد الحقول', 'A field has an invalid value'),      'field_locked': t('هذا الحقل مقفل ولا يعدّله المتقدم', 'This field is locked and cannot be edited by the applicant'),
      'row_not_found': t('الصف غير موجود في هذا الاستيراد، حدّث المعاينة', 'The row is not in this import any more; refresh the preview'),
      'batch_not_staged': t('تم تأكيد هذا الاستيراد، فلا تُعدَّل صفوفه', 'This import was confirmed, so its rows cannot be edited'),
      'decision_no_required': t('اكتب رقم القرار وتاريخه لاعتماد هذه المرحلة', 'Enter the decision number and date to approve this step'),
      'reminded_recently': t('ذُكِّر الطالب خلال آخر 24 ساعة، حاول لاحقاً', 'The student was reminded in the last 24 hours; try later'),
      'enrolled_in_sibling_org': t('الطالب مقيد في كلية أخرى بنفس الجامعة', 'The student is enrolled in another faculty of the same university'),
    };

/// When "Remind the student" may be pressed again, from a 429 `reminded_recently` (`next_at`, naive UTC); null otherwise.
DateTime? onbRemindNextAt(ApiException? e) {
  if (e == null || e.code != 'reminded_recently') return null;
  return orgParseUtc(e.detail['next_at']);
}
