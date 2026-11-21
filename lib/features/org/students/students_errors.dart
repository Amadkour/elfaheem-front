// lib/features/org/students/students_errors.dart — bilingual texts of the Students section's error codes (student
// lifecycle contract §4.7, §6.3 and the later phases' codes named in §12), read by `orgErrorText` (org_v3.dart) like
// the onboarding, governance and advising codes (the lead merges the lookup there).
library;

import '../../admin/admin_common.dart' show t;

Map<String, String> studentsCodeTexts() => {
      // phase 1
      'students_disabled': t('قسم الطلاب غير مفعّل لهذه المؤسسة', 'The Students section is not switched on for this organization'),
      'student_not_found': t('الطالب غير موجود في هذه المؤسسة', 'This student was not found in this organization'),
      'bad_filter': t('قيمة تصفية غير معروفة، أعد ضبط التصفية', 'Unknown filter value; reset the filter'),
      // later phases (kill switches, §12)
      'status_disabled': t('تغيير حالات الطلاب غير مفعّل لهذه المؤسسة', 'Changing student statuses is not switched on for this organization'),
      'asks_disabled': t('طلب البيانات أو الاجتماع من الطالب غير مفعّل', 'Asking students for data or a meeting is not switched on'),
      'rules_disabled': t('إعدادات الطلاب وقواعد الدراسة غير مفعّلة', 'Students and study rules settings are not switched on'),
    };
