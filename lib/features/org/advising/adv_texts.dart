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
      // Phase 3: settings, profiles, conflicts, assignment, distribution, handovers
      'advising_bad_scope': t('نطاق الإعدادات غير صالح لهذه المؤسسة', 'That settings scope is not valid for this organization'),
      'advising_single_mode': t('المؤسسة على وضع المرشد الواحد — لا مرشدين مشاركين أو داعمين', 'The organization uses one advisor per student — no co or support advisors'),
      'advising_conflict': t('بين هذا المرشد والطالب تعارض مصالح مسجّل', 'A conflict of interest is recorded between this advisor and the student'),
      'advising_conflict_exists': t('هذا التعارض مسجّل بالفعل', 'This conflict is already recorded'),
      'advising_over_capacity': t('المرشد بلغ حده الأقصى من الطلاب', 'The advisor is at their maximum number of students'),
      'advising_reason_required': t('اكتب سبب تجاوز الحد الأقصى', 'Give the reason for going over the maximum'),
      'advising_not_found': t('العنصر غير موجود في الإرشاد الأكاديمي لهذه المؤسسة — حدّث الصفحة', 'That item no longer exists in this organization\'s academic advising — refresh the page'),
      'advising_bad_dates': t('تاريخ النهاية يجب أن يكون بعد تاريخ البداية', 'The end date must be after the start date'),
      'advising_bad_request': t('الطلب غير مكتمل: اختر المرشد الذي يُنقل طلابه', 'The request is incomplete: choose the advisor whose students move'),
      'plan_stale': t('تغيّرت البيانات منذ المعاينة — عاين من جديد', 'The data changed since the preview — preview again'),
    };
