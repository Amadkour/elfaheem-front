// lib/features/org/onboarding/onboarding_errors.dart — bilingual texts of the onboarding error codes (contract §5),
// read by `orgErrorText` (org_v3.dart) like the governance and advising codes.
library;

import '../../admin/admin_common.dart' show t;

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
    };
