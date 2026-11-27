// features/courses/teacher/wizard/form_sections.dart — the sections of the course form as widgets of their own (they
// were inline in course_form_screen.dart's build). Each reads the [CourseFormDraft] and the scoped
// [CourseFormProvider]; a callback hands back what only the screen can do (submit, remove the cover, open the editor).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart' show EduGeoLabels;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/courses/course_setup_views.dart';
import 'package:flutter_education_app/features/courses/roadmap/roadmap_editor.dart' show RoadmapLevelChips, RoadmapTagsInput;
import 'package:flutter_education_app/features/courses/roadmap/roadmap_tab.dart' show roadmapAllowedHere;
import 'package:flutter_education_app/features/courses/teacher/component/next_courses_field.dart';
import 'package:flutter_education_app/features/courses/teacher/component/number_pair.dart';
import 'package:flutter_education_app/features/courses/teacher/component/recommended_courses_field.dart';
import 'package:flutter_education_app/features/courses/teacher/course_form_provider.dart';
import 'package:flutter_education_app/features/courses/teacher/course_privacy_card.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/course_form_draft.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/form_parts.dart';
import 'package:flutter_education_app/features/quran/quran_api.dart' show quranOff;
import 'package:flutter_education_app/utils/widget/primary_menue.dart';
import 'package:flutter_education_app/utils/widget/text_field.dart';
import 'package:provider/provider.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// Titles, descriptions, course type and specialization.
class CfBasicsFields extends StatelessWidget {
  const CfBasicsFields({super.key, required this.draft});

  final CourseFormDraft draft;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseFormProvider>();
    String? titleRule(String? _) =>
        (draft.titleAr.text.trim().isEmpty && draft.titleEn.text.trim().isEmpty) ? 'cf_title_required'.tr : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CfLabeledField(
        label: 'cf_title_ar'.tr,
        child: MyTextField(controller: draft.titleAr, label: 'cf_title_ar'.tr, validator: titleRule),
      ),
      const SizedBox(height: AppSpace.md),
      CfLabeledField(
        label: 'cf_title_en'.tr,
        child: MyTextField(controller: draft.titleEn, label: 'cf_title_en'.tr, validator: titleRule),
      ),
      const SizedBox(height: AppSpace.md),
      CfLabeledField(
        label: 'cf_desc_ar'.tr,
        child: MyTextField(controller: draft.descAr, label: 'cf_desc_ar'.tr, maxLine: 4),
      ),
      const SizedBox(height: AppSpace.md),
      CfLabeledField(
        label: 'cf_desc_en'.tr,
        child: MyTextField(controller: draft.descEn, label: 'cf_desc_en'.tr, maxLine: 4),
      ),
      const SizedBox(height: AppSpace.md),
      CfLabeledField(
        label: 'course_type_label'.tr,
        child: CfCourseTypeSelector(
          selected: (provider.selectedTeachingType?['text'] as String?) ?? 'recorded',
          onChanged: (s) => provider.onChangeTeachingType(s, draft.typeCtrl),
        ),
      ),
      const SizedBox(height: AppSpace.md),
      CfLabeledField(
        label: 'Specialization'.tr,
        child: MyPrimaryMenu(
          controller: draft.categoryCtrl,
          initValue: provider.selectedSpecialization,
          options: provider.specializations,
          haveLogo: false,
          onChange: (i) => provider.onChangeSpecialization(i, draft.categoryCtrl),
          label: 'choose_specialization'.tr,
        ),
      ),
    ]);
  }
}

/// Who it's for and where (D-1314): the program type, stages and grades, subject, delivery mode, area and address.
class CfAudienceFields extends StatelessWidget {
  const CfAudienceFields({super.key, required this.draft});

  final CourseFormDraft draft;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseFormProvider>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // the program type (D-1343), only while the Quran tab is on
      if (!quranOff() && !provider.setupLoadFailed) ...[
        CourseProgramKindField(value: provider.programKind, locked: provider.programKindLocked, onChanged: provider.setProgramKind),
        const SizedBox(height: AppSpace.lg),
      ],
      if (provider.setupLoadFailed)
        CourseSetupLoadError(onRetry: () async {
          await provider.retrySetup();
          draft.address.text = provider.address;
        })
      else
        CourseSetupSection(
          stages: provider.eduCatalog?.stages ?? const [],
          subjects: provider.eduCatalog?.subjects ?? const [],
          targets: provider.targets,
          onToggleTarget: provider.toggleTarget,
          subjectId: provider.subjectId,
          onSubject: provider.setSubject,
          deliveryMode: provider.deliveryMode,
          onDeliveryMode: provider.setDeliveryMode,
          loadAreas: provider.loadAreas,
          onArea: provider.setArea,
          area1: provider.area1,
          area2: provider.area2,
          labels: provider.eduCatalog?.geoLabels ?? const EduGeoLabels(),
          address: draft.address,
          areaMissing: provider.areaMissing,
        ),
    ]);
  }
}

/// Expected hours.
class CfHoursField extends StatelessWidget {
  const CfHoursField({super.key, required this.draft});

  final CourseFormDraft draft;

  @override
  Widget build(BuildContext context) =>
      AppNumberField(controller: draft.hours, label: 'expected_hours_label'.tr, min: 0, decimals: 1);
}

/// The discount (percent, days, remove).
class CfDiscountFields extends StatelessWidget {
  const CfDiscountFields({super.key, required this.draft});

  final CourseFormDraft draft;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('discount_section_title'.tr, style: AppType.label(context)),
      const SizedBox(height: AppSpace.xxs),
      Text('discount_section_hint'.tr, style: AppType.meta(context)),
      const SizedBox(height: AppSpace.xs),
      NumberPair(
        first: AppNumberField(
          controller: draft.discountPercent,
          label: 'discount_percentage_label'.tr,
          min: 0,
          max: 100,
          step: 5,
          decimals: 2,
          validator: (v) {
            final n = double.tryParse(v ?? '');
            if (v != null && v.trim().isNotEmpty && (n == null || n <= 0 || n > 100)) {
              return 'discount_percentage_validator'.tr; // "0–100"
            }
            return null;
          },
        ),
        second: AppNumberField(controller: draft.discountDays, label: 'discount_days_label'.tr, min: 1),
      ),
      if (draft.isEdit && (draft.course?.discountActive ?? false) && draft.discountPercent.text.trim().isNotEmpty) ...[
        const SizedBox(height: AppSpace.xs),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            onPressed: () {
              draft.discountPercent.clear();
              draft.discountDays.clear();
              draft.removeDiscount = true;
              draft.touch();
            },
            child: Text('remove_discount_btn'.tr,
                style: AppType.label(context).copyWith(color: context.colors.danger, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    ]);
  }
}

/// Course relations: next courses (or the Path tab's editor), level, topic words and recommended courses.
class CfRelationsFields extends StatelessWidget {
  const CfRelationsFields({super.key, required this.draft, required this.onOpenPath});

  final CourseFormDraft draft;
  final VoidCallback onOpenPath;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseFormProvider>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('next_course_label'.tr, style: AppType.label(context)),
      const SizedBox(height: AppSpace.xxs),
      if (provider.nextCoursesInPath) ...[
        // ONE place to edit the path: the course's Path tab (D-120)
        Text(
          _t('تُحدَّد الكورسات التالية والمتطلبات السابقة في تبويب «المسار» للكورس.',
              'Next courses and prerequisites are set in the course’s Path tab.'),
          style: AppType.meta(context),
        ),
        const SizedBox(height: AppSpace.xxs),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: onOpenPath,
            style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
            icon: const Icon(Icons.route_rounded, size: 18),
            label: Text(_t('تعديل المسار', 'Edit path')),
          ),
        ),
      ] else ...[
        Text('next_course_hint'.tr, style: AppType.meta(context)),
        const SizedBox(height: AppSpace.xs),
        NextCoursesField(
          selected: provider.selectedNextCourses,
          availableOptions: provider.availableNextCourseOptions,
          onAdd: provider.addNextCourse,
          onRemoveAt: provider.removeNextCourseAt,
          onReorder: provider.moveNextCourse,
        ),
      ],
      if (roadmapAllowedHere(context) && draft.course?.org == null) ...[
        const SizedBox(height: AppSpace.lg),
        Text(_t('المستوى', 'Level'), style: AppType.label(context)),
        const SizedBox(height: AppSpace.xs),
        RoadmapLevelChips(value: provider.level, onChanged: provider.setLevel),
        const SizedBox(height: AppSpace.lg),
        Text(_t('كلمات مفتاحية', 'Topic words'), style: AppType.label(context)),
        const SizedBox(height: AppSpace.xxs),
        Text(_t('تساعد على اقتراح كورسك للطلاب المهتمين.', 'They help suggest your course to interested students.'),
            style: AppType.meta(context)),
        const SizedBox(height: AppSpace.xs),
        RoadmapTagsInput(tags: provider.tags, onAdd: provider.addTag, onRemove: provider.removeTag),
      ],
      const SizedBox(height: AppSpace.lg),
      Text('recommended_courses_label'.tr, style: AppType.label(context)),
      const SizedBox(height: AppSpace.xs),
      RecommendedCoursesField(
        options: provider.otherCourses,
        selectedIds: provider.selectedRecommendedCourseIds,
        onToggle: provider.toggleRecommendedCourse,
      ),
    ]);
  }
}

/// The public / private switch and its six-digit code.
class CfPrivacyField extends StatelessWidget {
  const CfPrivacyField({super.key, required this.draft});

  final CourseFormDraft draft;

  @override
  Widget build(BuildContext context) => CoursePrivacyCard(
        isPrivate: draft.isPrivate,
        codeCtrl: draft.accessCode,
        courseId: draft.course?.id,
        // edit → loads the current code
        onChanged: (v) {
          draft.isPrivate = v;
          draft.touch();
        },
      );
}

