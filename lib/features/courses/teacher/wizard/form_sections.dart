// features/courses/teacher/wizard/form_sections.dart — the sections of the course form as widgets of their own (they
// were inline in course_form_screen.dart's build). Each reads the [CourseFormDraft] and the scoped
// [CourseFormProvider]; a callback hands back what only the screen can do (submit, remove the cover, open the editor).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart' show EduGeoLabels;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/courses/course_setup_views.dart';
import 'package:flutter_education_app/features/courses/roadmap/roadmap_editor.dart' show RoadmapLevelChips, RoadmapTagsInput;
import 'package:flutter_education_app/features/courses/roadmap/roadmap_tab.dart' show roadmapAllowedHere;
import 'package:flutter_education_app/features/courses/teacher/component/add_item_dialog.dart';
import 'package:flutter_education_app/features/courses/teacher/component/currency_selector.dart';
import 'package:flutter_education_app/features/courses/teacher/component/next_courses_field.dart';
import 'package:flutter_education_app/features/courses/teacher/component/number_pair.dart';
import 'package:flutter_education_app/features/courses/teacher/component/recommended_courses_field.dart';
import 'package:flutter_education_app/features/courses/teacher/component/section_card.dart';
import 'package:flutter_education_app/features/courses/teacher/course_form_provider.dart';
import 'package:flutter_education_app/features/courses/teacher/course_privacy_card.dart';
import 'package:flutter_education_app/features/courses/teacher/course_reel_field.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/course_form_draft.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/form_parts.dart';
import 'package:flutter_education_app/features/home/teacher/schedules/schedules_provider.dart' show slotDayLabel;
import 'package:flutter_education_app/features/quran/quran_api.dart' show quranOff;
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/utils/widget/primary_menue.dart';
import 'package:flutter_education_app/utils/widget/text_field.dart';
import 'package:image_picker/image_picker.dart';
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

/// Yearly / six-month / monthly price, the default plan and the currency.
class CfPricingFields extends StatelessWidget {
  const CfPricingFields({super.key, required this.draft});

  final CourseFormDraft draft;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseFormProvider>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Yearly = the existing price field; the other two plans are optional (empty = not offered).
      AppNumberField(controller: draft.price, label: 'price_yearly_label'.tr, min: 0, step: 10, decimals: 2),
      const SizedBox(height: AppSpace.md),
      NumberPair(
        first: AppNumberField(controller: draft.priceSixMonths, label: 'price_six_months_label'.tr, min: 0, step: 10, decimals: 2),
        second: AppNumberField(controller: draft.priceMonthly, label: 'price_monthly_label'.tr, min: 0, step: 10, decimals: 2),
      ),
      const SizedBox(height: AppSpace.xs),
      Text('price_plans_hint'.tr, style: AppType.meta(context)),
      const SizedBox(height: AppSpace.md),
      // Plan students see first (course profile + home).
      CfLabeledField(
        label: 'default_plan_label'.tr,
        child: Wrap(spacing: AppSpace.xs, children: [
          for (final e in {
            0: 'price_yearly_label'.tr,
            1: 'price_six_months_label'.tr,
            2: 'price_monthly_label'.tr,
          }.entries)
            ChoiceChip(
              label: Text(e.value, style: TextStyle(fontFamily: AppFonts.family)),
              selected: provider.defaultPlanIndex == e.key,
              onSelected: (_) => provider.onChangeDefaultPlan(e.key),
            ),
        ]),
      ),
      const SizedBox(height: AppSpace.md),
      CurrencySelector(label: 'currency_label'.tr, selected: provider.selectedCurrency, onChanged: provider.onChangeCurrency),
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

/// Expected hours and the discount (percent, days, remove).
class CfHoursDiscountFields extends StatelessWidget {
  const CfHoursDiscountFields({super.key, required this.draft});

  final CourseFormDraft draft;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppNumberField(controller: draft.hours, label: 'expected_hours_label'.tr, min: 0, decimals: 1),
      const SizedBox(height: AppSpace.lg),
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

/// The weekly appointments: the saved ones (edit mode) and the new ones, staged until Save.
class CfScheduleSection extends StatelessWidget {
  const CfScheduleSection({super.key, required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseFormProvider>();
    return SectionCard(
      featureKey: 'course_details.schedule',
      icon: Icons.event_available_rounded,
      title: 'weekly_schedule'.tr,
      items: [
        ...provider.form.schedules.map((s) => '${slotDayLabel(s.day)} • ${AppTime.clock(s.startTime)} – ${AppTime.clock(s.endTime)}'),
        ...provider.pendingSchedules.map((s) => '${slotDayLabel(s.day)} • ${AppTime.clock(s.startTime)} – ${AppTime.clock(s.endTime)}'),
      ],
      onAdd: onAdd,
      onRemove: (i) {
        final existingCount = provider.form.schedules.length;
        if (i < existingCount) {
          provider.removeFormSchedule(i);
        } else {
          provider.removePendingSchedule(i - existingCount);
        }
      },
    );
  }
}

/// The reel, the certificate designs link and the certificates / tools / prerequisites lists.
class CfExtrasFields extends StatelessWidget {
  const CfExtrasFields({super.key, required this.draft});

  final CourseFormDraft draft;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseFormProvider>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Course reel (عرض أولي): an optional intro video shown instead of the course image on the course profile.
      CourseReelField(controller: draft.reelCtrl, posterUrl: draft.logoBytes != null ? null : draft.coverUrl),
      const SizedBox(height: AppSpace.md),
      const ParentComponent(featureKey: 'course_form.certificate_template', child: CfCertificateDesignsLink()),
      const SizedBox(height: AppSpace.sm),
      SectionCard(
        featureKey: 'course_details.certificates',
        icon: Icons.workspace_premium_rounded,
        title: 'certificates_section'.tr,
        items: provider.form.certificates,
        onAdd: () => addItemDialog('add_certificate'.tr, provider.addFormCertificate, context),
        onRemove: provider.removeFormCertificate,
      ),
      const SizedBox(height: AppSpace.sm),
      SectionCard(
        featureKey: 'course_details.tools',
        icon: Icons.build_rounded,
        title: 'tools_section'.tr,
        items: provider.form.tools,
        onAdd: () => addItemDialog('add_tool'.tr, provider.addFormTool, context),
        onRemove: provider.removeFormTool,
      ),
      const SizedBox(height: AppSpace.sm),
      SectionCard(
        featureKey: 'course_details.prerequisites',
        icon: Icons.checklist_rounded,
        title: 'prerequisites_section'.tr,
        items: provider.form.prerequisites,
        onAdd: () => addItemDialog('add_prerequisite'.tr, provider.addFormPrerequisite, context),
        onRemove: provider.removeFormPrerequisite,
      ),
    ]);
  }
}

/// The cover at the top of the form (a thin wrapper that hands the pick to the draft).
class CfCoverSection extends StatelessWidget {
  const CfCoverSection({super.key, required this.draft, required this.onRemove});

  final CourseFormDraft draft;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) => CfCoverPicker(
        logoBytes: draft.logoBytes,
        imageUrl: draft.coverUrl,
        logoFile: draft.logoFile,
        onRemove: onRemove,
        onChange: (XFile file) async {
          draft.logoBytes = await file.readAsBytes();
          draft.logoFile = file;
          draft.touch();
        },
      );
}
