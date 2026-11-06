// lib/features/org/advising/adv_texts.dart — the Academic Advising module's server error codes → bilingual text
// (the backend's services/organization/advising/text.py). Merged into `orgErrorText` (org_v3.dart) like
// `govCodeTexts()`, so `orgCall` toasts them.
library;

import '../../admin/admin_common.dart' show t;
import 'adv_support_texts.dart' show advSupportCodeTexts;

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
      // Phase 4: categories, flags, notes
      'advising_category_in_use': t('لا يمكن حذف التصنيف ما دامت تنبيهات مفتوحة تستخدمه — أغلقها أو أوقف التصنيف بدلاً من حذفه',
          'The category cannot be deleted while open flags use it — close them, or switch the category off instead'),
      'advising_bad_accommodation': t('التسهيلات المختارة لا تتبع تصنيف هذا التنبيه', 'The chosen accommodations do not belong to this flag\'s category'),
      'advising_bad_transition': t('لا يمكن نقل التنبيه إلى هذه الحالة من حالته الحالية — حدّث الصفحة', 'The flag cannot move to that status from where it is now — refresh the page'),
      'advising_outcome_required': t('اكتب نتيجة المعالجة قبل إغلاق التنبيه', 'Write the outcome before resolving the flag'),
      'advising_bad_visibility': t('الملاحظة الحساسة لا تُعرض على الطالب — اختر «خاصة» أو «فريق الإرشاد»',
          'A sensitive note is never shown to the student — choose Private or Advising team'),
      'advising_rate_limited': t('كتابات كثيرة في وقت قصير — انتظر بضع دقائق ثم أعد المحاولة', 'Too many changes in a short time — wait a few minutes, then try again'),
      'advising_bad_category': t('التصنيف المختار متوقف أو لا يتبع هذه المؤسسة — اختر تصنيفاً آخر', 'The chosen category is switched off or belongs to another organization — choose another one'),
      'advising_category_system': t('تصنيفات النظام لا تُحذف ولا تتغير حساسيتها — يمكن إعادة تسميتها أو إيقافها',
          'Built-in categories cannot be deleted or change their sensitivity — rename or switch them off instead'),
      'advising_bad_contact_at': t('وقت التواصل لا يكون في المستقبل', 'The contact time cannot be in the future'),
      'advising_bad_cursor': t('تعذّر متابعة السجل الزمني من هذا الموضع — حدّث الصفحة', 'The timeline cannot continue from that point — refresh the page'),
      'advising_client_id_conflict': t('رقم الملاحظة المحفوظة استُخدم لطالب آخر — تُرسل برقم جديد', 'That saved note\'s id was used for another student — it is sent with a new id'),
      // Phase 6: early warning (rules, engine runs)
      'advising_bad_rule': t('إعدادات القاعدة غير صالحة — راجع القيم وحدودها', 'The rule\'s settings are not valid — check the values and their limits'),
      'advising_rule_system': t('قواعد النظام لا تُحذف — أوقفها بدلاً من ذلك', 'Built-in rules cannot be deleted — switch them off instead'),
      'advising_rule_limit': t('بلغت المؤسسة الحد الأقصى: 50 قاعدة — احذف قاعدة أو عدّل قاعدة قائمة', 'The organization has the most rules allowed (50) — delete one or edit an existing rule'),
      'advising_run_busy': t('فحص القواعد يعمل الآن — تظهر نتيجته هنا حين ينتهي', 'A rule check is running now — its result shows here when it ends'),
      // Phase 7: requests, referrals, the approval chain, support plans, accommodations (adv_support_texts.dart)
      ...advSupportCodeTexts(),
    };

/// The risk-reason codes of the workspace (`score.py`); `advRiskReasonText` in adv_models.dart writes each one.
const advRiskReasonCodes = ['cgpa_low', 'gpa_drop', 'absence_high', 'failed_courses', 'open_flags', 'no_contact'];

/// Phase 6: what a rule kind checks, for an alert or a hit that came without its explanation (an older server).
/// Only the sentence: the numbers stay in the evidence, which the server words.
String advWarningKindFallback(String kind) => switch (kind) {
      'gpa_below' => t('المعدل التراكمي أقل من حد القاعدة', 'The CGPA is below the rule\'s limit'),
      'gpa_drop' => t('معدل آخر فصل تراجع عن المعدل التراكمي أكثر من حد القاعدة', 'The last term GPA fell further below the CGPA than the rule allows'),
      'failed_courses' => t('عدد المقررات الراسبة بلغ حد القاعدة', 'The number of failed courses reached the rule\'s limit'),
      'repeated_fail' => t('رسوب متكرر في المقرر نفسه', 'The same course was failed again'),
      'absence_pct' => t('نسبة الغياب في أحد المقررات الحالية بلغت حد القاعدة', 'Absence in a current course reached the rule\'s limit'),
      'absence_count' => t('عدد المحاضرات الفائتة في أحد المقررات الحالية بلغ حد القاعدة', 'Missed sessions in a current course reached the rule\'s limit'),
      'no_contact' => t('لا تواصل مع الطالب منذ مدة أطول من حد القاعدة', 'No contact with the student for longer than the rule allows'),
      'graduation_delay' => t('التخرج في موعده لم يعد ممكناً بالخطة الحالية', 'Graduating on time is no longer possible at the current pace'),
      'midterm_fail' => t('درجة منتصف الفصل دون حد القاعدة في مقرر أو أكثر', 'A midterm mark is below the rule\'s limit in one course or more'),
      _ => t('الطالب يطابق إحدى قواعد الإنذار المبكر', 'The student matches an early-warning rule'),
    };
