// lib/features/org/advising/adv_texts.dart — the Academic Advising module's server error codes → bilingual text
// (the backend's services/organization/advising/text.py). Merged into `orgErrorText` (org_v3.dart) like
// `govCodeTexts()`, so `orgCall` toasts them.
library;

import '../../admin/admin_common.dart' show t;

Map<String, String> advCodeTexts() => {
      'advising_not_available': t('الإرشاد الأكاديمي متاح للجامعات والكليات والأقسام التابعة لها فقط',
          'Academic advising is available to universities, faculties and the units under them only'),
      'advising_disabled': t('الإرشاد الأكاديمي غير مفعّل في هذه المؤسسة', 'Academic advising is not switched on in this organization'),
      'feature_disabled': t('هذه الميزة متوقفة على المنصة حالياً', 'This feature is switched off on this platform'),
      'advising_forbidden': t('ليست لديك صلاحية في الإرشاد الأكاديمي لهذه المؤسسة', 'You have no academic advising rights in this organization'),
      'advising_admin_only': t('تفعيل الإرشاد الأكاديمي وإيقافه لمدير المؤسسة فقط', 'Only the organization admin can switch academic advising on or off'),
      'advising_bad_dept': t('الإدارة المختارة لا تتبع هذه المؤسسة أو غير مفعّلة', 'The chosen department does not belong to this organization or is inactive'),
      'advising_bad_student': t('الطالب ليس عضواً نشطاً في هذه المؤسسة', 'The student is not a live member of this organization'),
      'advising_bad_advisor': t('المرشد يجب أن يكون عضو هيئة تدريس نشطاً في هذه المؤسسة', 'The advisor must be a live teaching member of this organization'),
      'advising_self_advisor': t('لا يمكن أن يكون الطالب مرشد نفسه', 'A student cannot advise themselves'),
      'advising_primary_exists': t('للطالب مرشد أساسي بالفعل — حدّث الصفحة وأعد المحاولة', 'The student already has a primary advisor — refresh and try again'),
      'advising_bad_policy': t('إعدادات الإرشاد غير صالحة', 'The advising settings are not valid'),
    };
