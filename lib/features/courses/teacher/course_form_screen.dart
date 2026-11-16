import 'package:flutter_education_app/design/app_kit.dart' show AppBlock, AppBlockTone, AppBorder, AppButton, AppButtonSize, AppFieldLabel, AppHeader, AppIconSize, AppMotion, AppNumberField, AppRadius, AppSheetContent, AppSpace, AppStatusBadge, AppTone, AppTouch, AppType, showAppSheet;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppEase;
import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'dart:typed_data';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/help/help_info_button.dart' show HelpInfoButton;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/courses/teacher/teacher_courses_provider.dart';
import 'package:flutter_education_app/utils/widget/editable_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/primary_menue.dart';
import 'package:flutter_education_app/utils/widget/text_field.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart';
import 'package:flutter_education_app/features/home/student/models.dart' show CourseStatus;
import 'package:flutter_education_app/features/home/teacher/schedules/schedules_provider.dart'
    show kDayOrder, kDayLabels, slotDayLabel;
import 'package:flutter_education_app/features/courses/teacher/component/add_item_dialog.dart';
import 'package:flutter_education_app/features/courses/teacher/component/number_pair.dart';
import 'package:flutter_education_app/features/courses/teacher/component/section_card.dart';
import 'package:flutter_education_app/features/courses/teacher/component/currency_selector.dart';
import 'package:flutter_education_app/features/courses/teacher/component/course_progress_status_card.dart';
import 'package:flutter_education_app/features/courses/teacher/component/recommended_courses_field.dart';
import 'package:flutter_education_app/features/courses/teacher/component/next_courses_field.dart';
import 'package:flutter_education_app/features/courses/teacher/course_form_provider.dart';
import 'package:flutter_education_app/features/courses/teacher/course_reel_field.dart';
import 'package:flutter_education_app/features/courses/teacher/course_privacy_card.dart';
import 'package:flutter_education_app/features/courses/roadmap/roadmap_api.dart' show RoadmapApi, kRoadmapPathKey, roadmapOff;
import 'package:flutter_education_app/features/courses/roadmap/roadmap_editor.dart' show RoadmapLevelChips, RoadmapTagsInput, showRoadmapEditor;
import 'package:flutter_education_app/features/courses/roadmap/roadmap_tab.dart' show roadmapAllowedHere;
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_errors.dart' show appSharedFix, showAppError;
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_tokens.dart' show AppWidth;

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

// ─────────────────────────────────────────────────────────────────────────────
// Public entry point  — wraps the inner screen in a scoped provider
// ─────────────────────────────────────────────────────────────────────────────

class CourseFormScreen extends StatelessWidget {
  /// null → CREATE mode,  non-null → EDIT mode
  final TeacherCourse? course;

  const CourseFormScreen({super.key, this.course});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => CourseFormProvider(api: ApiClient()),
    child: _CourseFormInner(course: course),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Inner stateful widget  (has access to the scoped provider)
// ─────────────────────────────────────────────────────────────────────────────

class _CourseFormInner extends StatefulWidget {
  final TeacherCourse? course;

  const _CourseFormInner({required this.course});

  @override
  State<_CourseFormInner> createState() => _CourseFormInnerState();
}

class _CourseFormInnerState extends State<_CourseFormInner>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late bool _isPrivate;
  final _accessCodeCtrl = TextEditingController();
  late final TextEditingController _titleArCtrl,
      _titleEnCtrl,
      _descArCtrl,
      _descEnCtrl;
  bool _advancedOpen = false;
  bool _optionalOpen = false;

  bool get _hasBasics =>
      (_titleArCtrl.text.trim().isNotEmpty ||
          _titleEnCtrl.text.trim().isNotEmpty);
  late final TextEditingController _priceCtrl; // YEARLY price
  late final TextEditingController _priceMonthlyCtrl;
  late final TextEditingController _priceSixMonthsCtrl;
  late final TextEditingController _hoursCtrl;
  final ExpansibleController _categoryCtrl = ExpansibleController();
  final ExpansibleController _typeCtrl = ExpansibleController();
  late final TextEditingController _discountPercentCtrl;
  late final TextEditingController _discountDaysCtrl;
  bool _removeDiscount = false;
  XFile? _logoFile;
  Uint8List? _logoBytes;

  /// The stored cover was removed on this visit (D-880): the form shows the default cover from now on.
  bool _coverRemoved = false;

  String? get _coverUrl => _coverRemoved ? null : widget.course?.imageUrl;

  // Optional course reel (عرض أولي) — shown instead of the course image on
  // the course profile when set. Uploads itself directly (see
  // CourseReelController); the form only calls commit() once the course id
  // is known (after create, or immediately in edit mode).
  late final CourseReelController _reelCtrl;

  // Optional certificate template — create mode only. A title with no file
  // is ignored (see CourseFormProvider.submitCreate).
  XFile? _certTemplateFile;
  late final TextEditingController _certTitleCtrl;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  // Edit-mode publish/draft status (kept in local state since widget.course
  // is a snapshot passed into the constructor, not reactive to provider
  // changes).
  late bool _isPublished;
  bool _statusLoading = false;

  // Course *content* status (in_progress / completed) — separate from
  // publish/draft above. Edit mode only.
  late CourseStatus _progressStatus;
  bool _progressStatusLoading = false;

  bool get _isEdit => widget.course != null;

  /// The course's Path editor, from the form (edit mode, personal course).
  Future<void> _openPathEditor() async {
    final id = widget.course!.id;
    final p = context.read<CourseFormProvider>();
    try {
      final r = await const RoadmapApi().roadmap(id);
      if (!mounted) return;
      final saved = await showRoadmapEditor(context, courseId: id, roadmap: r);
      if (saved != null) p.applyRoadmap(saved.course.level, saved.course.tags);
    } catch (e) {
      showAppNotice(ApiException.from(e).message, error: true);
    }
  }

  @override
  void initState() {
    super.initState();
    final c = widget.course;
    _isPrivate = widget.course?.isPrivate ?? false;
    _reelCtrl = CourseReelController(courseId: c?.id);
    if (c != null) _reelCtrl.loadExisting(); // the stored reel, so it can be watched, replaced or removed

    _titleArCtrl = TextEditingController(
      text: (c?.titleAr ??c?.titleEn)??'',

    );
    _titleEnCtrl = TextEditingController(
      text: (c?.titleEn ??c?.titleAr)??'',

    );
    _descArCtrl = TextEditingController(
      text:( c?.descriptionAr??c?.descriptionEn)??'',

    );
    _descEnCtrl = TextEditingController(
      text:( c?.descriptionEn??c?.descriptionAr)??'',
    );
    _priceCtrl = TextEditingController(
      text: c != null ? (c.priceYearly ?? c.price).toString() : '',
    );
    _priceMonthlyCtrl = TextEditingController(
      text: c?.priceMonthly != null ? c!.priceMonthly.toString() : '',
    );
    _priceSixMonthsCtrl = TextEditingController(
      text: c?.priceSixMonths != null ? c!.priceSixMonths.toString() : '',
    );
    _hoursCtrl = TextEditingController(
      text: c != null ? c.expectedHours.toString() : '',
    );
    _discountPercentCtrl = TextEditingController(
      text: c?.discountPercentage != null && c!.discountPercentage! > 0
          ? c.discountPercentage.toString()
          : '',
    );
    _discountDaysCtrl = TextEditingController(
      text: c?.discountDays?.toString() ?? '',
    );

    for (final ctrl in [
      _titleArCtrl,
      _titleEnCtrl,
      _descArCtrl,
      _descEnCtrl,
      _priceCtrl,
      _priceMonthlyCtrl,
      _priceSixMonthsCtrl,
      _hoursCtrl,
      _discountPercentCtrl,
      _discountDaysCtrl,
    ]) {
      ctrl.addListener(_rebuild);
    }
    // Rebuild on pick/replace/remove so the Save button and the preview
    // update immediately (mirrors how the text controllers use _rebuild).
    _reelCtrl.addListener(_rebuild);
    _isPublished = c?.isPublished ?? false;
    _progressStatus = c?.status ?? CourseStatus.inProgress;
    _certTitleCtrl = TextEditingController(
      text: 'default_certificate_title'.tr,
    );

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final p = context.read<CourseFormProvider>();
      if (_isEdit) {
        // a personal course of a personal account: next courses are edited in its Path tab (D-120)
        p.nextCoursesInPath = widget.course!.org == null && roadmapAllowedHere(context) && !roadmapOff(kRoadmapPathKey);
        await p.initUpdate(context, widget.course!);
      } else {
        await p.initCreate(context);
      }
      _fadeCtrl.forward();
    });
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _reelCtrl.removeListener(_rebuild);
    _reelCtrl.dispose();
    for (final ctrl in [
      _titleArCtrl,
      _titleEnCtrl,
      _descEnCtrl,
      _descArCtrl,
      _priceCtrl,
      _priceMonthlyCtrl,
      _priceSixMonthsCtrl,
      _hoursCtrl,
      _discountPercentCtrl,
      _discountDaysCtrl,
    ]) {
      ctrl.removeListener(_rebuild);
      ctrl.dispose();
    }
    _certTitleCtrl.dispose();
    _fadeCtrl.dispose();
    _accessCodeCtrl.dispose();
    super.dispose();
  }

  // ── Dirty check — enable Save button ─────────────────────────────────────

  bool get _hasChanges {
    if (!_isEdit) return _hasBasics;
    final c = widget.course!;
    final oldYearly = c.priceYearly ?? c.price;
    final newPrice = double.tryParse(_priceCtrl.text) ?? oldYearly;
    final newMonthly = double.tryParse(_priceMonthlyCtrl.text);
    final newSixMonths = double.tryParse(_priceSixMonthsCtrl.text);
    final newHours = double.tryParse(_hoursCtrl.text) ?? c.expectedHours;
    final newDiscount = double.tryParse(_discountPercentCtrl.text);
    final oldDiscount = c.discountPercentage;
    final newDays = int.tryParse(_discountDaysCtrl.text);
    final oldDays = c.discountDays;
    return _titleArCtrl.text.trim() != (c.titleAr ?? '') ||
        _titleEnCtrl.text.trim() != (c.titleEn ?? '') ||
        newPrice != oldYearly ||
        newMonthly != c.priceMonthly ||
        newSixMonths != c.priceSixMonths ||
        newHours != c.expectedHours ||
        newDiscount != oldDiscount ||
        newDays != oldDays ||
        context.read<CourseFormProvider>().defaultPlanIndex !=
            c.defaultPricePlanIndex ||
        _removeDiscount ||
        _logoFile != null ||
        _reelCtrl.hasChanges;
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  /// [publish] only matters in CREATE mode: true = publish immediately,
  /// false = save as draft. Ignored in EDIT mode (status is changed via the
  /// dedicated status toggle instead).
  Future<void> _submit({
    bool publish = true,
    required TeacherCoursesProvider listProvider,
    required CourseFormProvider formProvider,
  }) async {
    if (!_formKey.currentState!.validate()) {
      setState(() => _advancedOpen = true); // an invalid discount may be hidden
      return;
    }
    final type =
        (formProvider.selectedTeachingType?['text'] as String?) ?? 'recorded';

    TeacherCourse? result;
    final discountPercentage = double.tryParse(_discountPercentCtrl.text);
    final discountDays = int.tryParse(_discountDaysCtrl.text);

    if (_isEdit) {
      result = await formProvider.submitUpdate(
        widget.course!,
        titleAr: _titleArCtrl.text,
        titleEn: _titleEnCtrl.text,
        descriptionAr: _descArCtrl.text,
        descriptionEn: _descEnCtrl.text,
        type: type,
        isPrivate: _isPrivate,
        accessCode: _accessCodeCtrl.text,
        fees: double.tryParse(_priceCtrl.text),
        priceMonthly: double.tryParse(_priceMonthlyCtrl.text),
        priceSixMonths: double.tryParse(_priceSixMonthsCtrl.text),
        totalHours: double.tryParse(_hoursCtrl.text),
        discountPercentage: discountPercentage,
        discountDays: discountDays,
        clearDiscount:
        discountPercentage == null &&
            (_removeDiscount || (widget.course!.discountPercentage ?? 0) > 0),
        logoFile: _logoFile,
      );
    } else {
      final type =
          (formProvider.selectedTeachingType?['text'] as String?) ?? 'recorded';
      result = await formProvider.submitCreate(
        titleAr: _titleArCtrl.text,
        titleEn: _titleEnCtrl.text,
        descriptionAr: _descArCtrl.text,
        descriptionEn: _descEnCtrl.text,
        type: type,
        isPrivate: _isPrivate,
        accessCode: _accessCodeCtrl.text,
        fees: double.tryParse(_priceCtrl.text) ?? 0,
        priceMonthly: double.tryParse(_priceMonthlyCtrl.text),
        priceSixMonths: double.tryParse(_priceSixMonthsCtrl.text),
        totalHours: double.tryParse(_hoursCtrl.text),
        discountPercentage: discountPercentage,
        discountDays: discountDays,
        logoFile: _logoFile,
        certificateTemplateTitle: _certTemplateFile != null
            ? _certTitleCtrl.text.trim()
            : null,
        certificateTemplateFile: _certTemplateFile,
        publish: publish,
      );
    }

    if (!mounted) return;

    if (result != null) {
      // The reel is uploaded/removed directly against the now-known course
      // id — a failure here never rolls back the course save itself (the
      // teacher can always retry from Edit), it only changes which message
      // is shown.
      final reelOk = await _reelCtrl.commit(result.id);
      if (!mounted) return;

      if (_isEdit) {
        listProvider.onCourseUpdated(result);
      } else {
        listProvider.onCourseCreated(result);
      }
      if (reelOk) {
        _showSnack(
          _isEdit
              ? 'course_updated_success'.tr
              : (publish
              ? 'course_created_success'.tr
              : 'course_draft_saved_success'.tr),
          context.colors.success,
        );
      } else {
        _showSnack(
          _reelCtrl.error ?? 'course_reel_upload_failed'.tr,
          context.colors.danger,
        );
      }
      Navigator.pop(context, result);
    } else if (formProvider.lastApiError != null && appSharedFix(formProvider.lastApiError!) != null) {
      // e.g. 403 personal_off (UX v3 phase 3): one tap turns the personal account on, then saves again
      showAppError(context, formProvider.lastApiError!,
          text: formProvider.errorMessage,
          onRetry: () => _submit(publish: publish, listProvider: listProvider, formProvider: formProvider));
    } else {
      _showSnack(
        formProvider.errorMessage ?? 'error_please_retry'.tr,
        context.colors.danger,
      );
    }
  }

  // ── Remove the cover (D-880) ────────────────────────────────────────────────

  /// After EditableImage's confirm: drops an unsaved pick and, when editing a course with a stored cover, deletes it
  /// at once; the course list takes the answer, the form and every card show the default cover.
  Future<void> _removeCover() async {
    final stored = (_coverUrl ?? '').isNotEmpty;
    setState(() {
      _logoFile = null;
      _logoBytes = null;
    });
    if (!stored || widget.course == null) return;
    final list = context.read<TeacherCoursesProvider>();
    try {
      final updated = await context.read<CourseFormProvider>().removeImage(widget.course!.id);
      list.onCourseUpdated(updated);
      if (mounted) setState(() => _coverRemoved = true);
      showAppNotice('cover_removed'.tr);
    } catch (e) {
      showAppNotice(ApiException.from(e).message, error: true);
    }
  }

  // ── Edit-mode status toggle (publish / unpublish) ──────────────────────────

  Future<void> _toggleStatus({
    required TeacherCoursesProvider listProvider,
  }) async {
    if (_statusLoading || widget.course == null) return;
    final target = !_isPublished;
    setState(() => _statusLoading = true);

    final ok = await (target
        ? listProvider.publishCourse(widget.course!.id)
        : listProvider.unpublishCourse(widget.course!.id));

    if (!mounted) return;
    setState(() => _statusLoading = false);

    if (ok) {
      setState(() => _isPublished = target);
      _showSnack(
        target
            ? 'course_published_success'.tr
            : 'course_unpublished_success'.tr,
        context.colors.success,
      );
    } else {
      _showSnack('error_please_retry'.tr, context.colors.danger);
    }
  }

  // ── Edit-mode content status toggle (in_progress / completed) ─────────────

  Future<void> _changeProgressStatus(
      CourseStatus status,
      TeacherCoursesProvider provider,
      ) async {
    if (_progressStatusLoading ||
        widget.course == null ||
        status == _progressStatus) {
      return;
    }
    setState(() => _progressStatusLoading = true);

    final formProvider = context.read<CourseFormProvider>();
    final result = await formProvider.updateStatus(widget.course!.id, status);

    if (!mounted) return;
    setState(() => _progressStatusLoading = false);

    if (result != null) {
      setState(() => _progressStatus = status);
      provider.onCourseUpdated(result);
      _showSnack('course_status_updated_success'.tr, context.colors.success);
    } else {
      _showSnack(
        formProvider.errorMessage ?? 'error_please_retry'.tr,
        context.colors.danger,
      );
    }
  }

  // ── Create-mode: add a weekly appointment before the course is saved ──────

  Future<void> _showAddAppointmentSheet() async {
    final formProvider = context.read<CourseFormProvider>();
    final existingDays = {
      ...formProvider.form.schedules.map((s) => s.day),
      ...formProvider.pendingSchedules.map((s) => s.day),
    };
    await showAppSheet<void>(
      context,
      (_) => _LocalAddScheduleSheet(
        existingDays: existingDays,
        onAdd: (day, start, end) => formProvider.addPendingSchedule(
          PendingSchedule(day: day, startTime: start, endTime: end),
        ),
      ),
    );
  }

  void _showSnack(String msg, Color color) {
    showAppNotice(msg);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TeacherCoursesProvider listProvider = context
        .read<TeacherCoursesProvider>();
    final provider = context.watch<CourseFormProvider>();
    final canSave = (_hasChanges || provider.listsChanged) && _hasBasics;

    return BasePage(
      key: const ValueKey('course_form'),
      useWebCard: true,
      width: AppWidth.reading,
      appBar: AppHeader(
        title: _isEdit ? 'edit_course_title'.tr : 'create_new_course_title'.tr,
        subtitle: _isEdit ? 'edit_badge'.tr : 'new_badge'.tr,
        actions: const [HelpInfoButton(pageId: 'teacher.course_editor')],
      ),
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Column(
          children: [
            // ── Scrollable form ────────────────────────────────────────────
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CoverPicker(
                        logoBytes: _logoBytes,
                        imageUrl: _coverUrl,
                        logoFile: _logoFile,
                        onRemove: _removeCover,
                        onChange: (XFile file) async {
                          _logoBytes = await file.readAsBytes();
                          setState(() {
                            _logoFile = file;
                          });
                        },
                      ),
                      // Basic info (always visible)
                      ParentComponent(
                          featureKey: 'course_form.basic_info',
                          child: _FormCard(
                            icon: Icons.info_outline_rounded,
                            title: 'cf_basic_info'.tr,
                            children: [
                              _LabeledField(
                                label: 'cf_title_ar'.tr,
                                child: MyTextField(
                                  controller: _titleArCtrl,
                                  label: 'cf_title_ar'.tr,
                                  validator: (_) =>
                                  (_titleArCtrl.text.trim().isEmpty &&
                                      _titleEnCtrl.text.trim().isEmpty)
                                      ? 'cf_title_required'.tr
                                      : null,
                                ),
                              ),
                              const SizedBox(height: AppSpace.md),
                              _LabeledField(
                                label: 'cf_title_en'.tr,
                                child: MyTextField(
                                  controller: _titleEnCtrl,
                                  label: 'cf_title_en'.tr,
                                  validator: (_) =>
                                  (_titleArCtrl.text.trim().isEmpty &&
                                      _titleEnCtrl.text.trim().isEmpty)
                                      ? 'cf_title_required'.tr
                                      : null,
                                ),
                              ),
                              const SizedBox(height: AppSpace.md),
                              _LabeledField(
                                label: 'cf_desc_ar'.tr,
                                child: MyTextField(
                                  controller: _descArCtrl,
                                  label: 'cf_desc_ar'.tr,
                                  maxLine: 4,
                                  // validator: (_) =>
                                  //     (_descArCtrl.text.trim().isEmpty &&
                                  //         _descEnCtrl.text.trim().isEmpty)
                                  //     ? gt(
                                  //         'أدخل وصفاً واحداً على الأقل (عربي أو إنجليزي)',
                                  //         'Enter at least one description (Arabic or English)',
                                  //       )
                                  //     : null,
                                ),
                              ),
                              const SizedBox(height: AppSpace.md),
                              _LabeledField(
                                label: 'cf_desc_en'.tr,
                                child: MyTextField(
                                  controller: _descEnCtrl,
                                  label: 'cf_desc_en'.tr,
                                  maxLine: 4,
                                  // validator: (_) =>
                                  //     (_descArCtrl.text.trim().isEmpty &&
                                  //         _descEnCtrl.text.trim().isEmpty)
                                  //     ? gt(
                                  //         'أدخل وصفاً واحداً على الأقل (عربي أو إنجليزي)',
                                  //         'Enter at least one description (Arabic or English)',
                                  //       )
                                  //     : null,
                                ),
                              ),
                              const SizedBox(height: AppSpace.md),
                              _LabeledField(
                                label: 'course_type_label'.tr,
                                child: _CourseTypeSelector(
                                  selected:
                                  (provider.selectedTeachingType?['text']
                                  as String?) ??
                                      'recorded',
                                  onChanged: (s) =>
                                      provider.onChangeTeachingType(s, _typeCtrl),
                                ),
                              ),
                              const SizedBox(height: AppSpace.md),
                              _LabeledField(
                                label: 'Specialization'.tr,
                                child: MyPrimaryMenu(
                                  controller: _categoryCtrl,
                                  initValue: provider.selectedSpecialization,
                                  options: provider.specializations,
                                  haveLogo: false,
                                  onChange: (i) => provider.onChangeSpecialization(
                                    i,
                                    _categoryCtrl,
                                  ),
                                  label: 'choose_specialization'.tr,
                                ),
                              ),
                              const SizedBox(height: AppSpace.md),
                              // Yearly = the existing price field; the other two
                              // plans are optional (empty = not offered).
                              AppNumberField(
                                controller: _priceCtrl,
                                label: 'price_yearly_label'.tr,
                                min: 0,
                                step: 10,
                                decimals: 2,
                              ),
                              const SizedBox(height: AppSpace.md),
                              NumberPair(
                                first: AppNumberField(
                                  controller: _priceSixMonthsCtrl,
                                  label: 'price_six_months_label'.tr,
                                  min: 0,
                                  step: 10,
                                  decimals: 2,
                                ),
                                second: AppNumberField(
                                  controller: _priceMonthlyCtrl,
                                  label: 'price_monthly_label'.tr,
                                  min: 0,
                                  step: 10,
                                  decimals: 2,
                                ),
                              ),
                              const SizedBox(height: AppSpace.xs),
                              Text(
                                'price_plans_hint'.tr,
                                style: AppType.meta(context),
                              ),
                              const SizedBox(height: AppSpace.md),
                              // Plan students see first (course profile + home).
                              _LabeledField(
                                label: 'default_plan_label'.tr,
                                child: Wrap(
                                  spacing: AppSpace.xs,
                                  children: [
                                    for (final e in {
                                      0: 'price_yearly_label'.tr,
                                      1: 'price_six_months_label'.tr,
                                      2: 'price_monthly_label'.tr,
                                    }.entries)
                                      ChoiceChip(
                                        label: Text(
                                          e.value,
                                          style: TextStyle(fontFamily: AppFonts.family),
                                        ),
                                        selected: provider.defaultPlanIndex == e.key,
                                        onSelected: (_) =>
                                            provider.onChangeDefaultPlan(e.key),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSpace.md),
                              CurrencySelector(
                                label: 'currency_label'.tr,
                                selected: provider.selectedCurrency,
                                onChanged: provider.onChangeCurrency,
                              ),
                            ],
                          )),
                      const SizedBox(height: AppSpace.md),

                      // edit mode: publish / progress status stay visible
                      if (_isEdit) ...[
                        ParentComponent(
                            featureKey: 'course_form.publish_status',
                            child: _StatusCard(
                              isPublished: _isPublished,
                              isLoading: _statusLoading,
                              onToggle: () =>
                                  _toggleStatus(listProvider: listProvider),
                            )),
                        const SizedBox(height: AppSpace.md),
                        CourseProgressStatusCard(
                          status: _progressStatus,
                          isLoading: _progressStatusLoading,
                          onChanged: (s) =>
                              _changeProgressStatus(s, listProvider),
                        ),
                        const SizedBox(height: AppSpace.md),
                      ],

                      // ═══ ADVANCED — collapsed ════════════════════════════════════════
                      ParentComponent(
                          featureKey: 'course_form.advanced',
                          child: _CollapsibleSection(
                            icon: Icons.tune_rounded,
                            title: 'cf_advanced'.tr,
                            subtitle: 'cf_advanced_sub'.tr,
                            expanded: _advancedOpen,
                            onToggle: () =>
                                setState(() => _advancedOpen = !_advancedOpen),
                            children: [
                              AppNumberField(
                                controller: _hoursCtrl,
                                label: 'expected_hours_label'.tr,
                                min: 0,
                                decimals: 1,
                              ),
                              const SizedBox(height: AppSpace.lg),
                              Text(
                                'discount_section_title'.tr,
                                // e.g. "Discount (optional)"
                                style: AppType.label(context),
                              ),
                              const SizedBox(height: AppSpace.xxs),
                              Text(
                                'discount_section_hint'.tr,
                                // e.g. "Leave empty for no discount"
                                style: AppType.meta(context),
                              ),
                              const SizedBox(height: AppSpace.xs),
                              NumberPair(
                                first: AppNumberField(
                                  controller: _discountPercentCtrl,
                                  label: 'discount_percentage_label'.tr, // "Discount %"
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
                                second: AppNumberField(
                                  controller: _discountDaysCtrl,
                                  label: 'discount_days_label'.tr, // "Days (optional)"
                                  min: 1,
                                ),
                              ),
                              if (_isEdit &&
                                  (widget.course?.discountActive ?? false) &&
                                  _discountPercentCtrl.text.trim().isNotEmpty) ...[
                                const SizedBox(height: AppSpace.xs),
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: TextButton(
                                    onPressed: () => setState(() {
                                      _discountPercentCtrl.clear();
                                      _discountDaysCtrl.clear();
                                      _removeDiscount = true;
                                    }),
                                    child: Text(
                                      'remove_discount_btn'.tr, // "Remove discount"
                                      style: AppType.label(context).copyWith(color: context.colors.danger, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: AppSpace.sm),
                              CoursePrivacyCard(
                                isPrivate: _isPrivate,
                                codeCtrl: _accessCodeCtrl,
                                courseId: widget.course?.id,
                                // edit → loads the current code
                                onChanged: (v) => setState(() => _isPrivate = v),
                              ),
                              const SizedBox(height: AppSpace.md),
                              ParentComponent(
                                  featureKey: 'course_form.relations',
                                  child: _FormCard(
                                    icon: Icons.route_rounded,
                                    title: 'course_relations_title'.tr,
                                    children: [
                                      Text(
                                        'next_course_label'.tr,
                                        style: AppType.label(context),
                                      ),
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
                                            onPressed: _openPathEditor,
                                            style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
                                            icon: const Icon(Icons.route_rounded, size: 18),
                                            label: Text(_t('تعديل المسار', 'Edit path')),
                                          ),
                                        ),
                                      ] else ...[
                                        Text(
                                          'next_course_hint'.tr,
                                          style: AppType.meta(context),
                                        ),
                                        const SizedBox(height: AppSpace.xs),
                                        NextCoursesField(
                                          selected: provider.selectedNextCourses,
                                          availableOptions:
                                          provider.availableNextCourseOptions,
                                          onAdd: provider.addNextCourse,
                                          onRemoveAt: provider.removeNextCourseAt,
                                          onReorder: provider.moveNextCourse,
                                        ),
                                      ],
                                      if (roadmapAllowedHere(context) && widget.course?.org == null) ...[
                                        const SizedBox(height: AppSpace.lg),
                                        Text(
                                          _t('المستوى', 'Level'),
                                          style: AppType.label(context),
                                        ),
                                        const SizedBox(height: AppSpace.xs),
                                        RoadmapLevelChips(value: provider.level, onChanged: provider.setLevel),
                                        const SizedBox(height: AppSpace.lg),
                                        Text(
                                          _t('كلمات مفتاحية', 'Topic words'),
                                          style: AppType.label(context),
                                        ),
                                        const SizedBox(height: AppSpace.xxs),
                                        Text(
                                          _t('تساعد على اقتراح كورسك للطلاب المهتمين.', 'They help suggest your course to interested students.'),
                                          style: AppType.meta(context),
                                        ),
                                        const SizedBox(height: AppSpace.xs),
                                        RoadmapTagsInput(tags: provider.tags, onAdd: provider.addTag, onRemove: provider.removeTag),
                                      ],
                                      const SizedBox(height: AppSpace.lg),
                                      Text(
                                        'recommended_courses_label'.tr,
                                        style: AppType.label(context),
                                      ),
                                      const SizedBox(height: AppSpace.xs),
                                      RecommendedCoursesField(
                                        options: provider.otherCourses,
                                        selectedIds:
                                        provider.selectedRecommendedCourseIds,
                                        onToggle: provider.toggleRecommendedCourse,
                                      ),
                                    ],
                                  )),
                              const SizedBox(height: AppSpace.md),
                              // Appointments (both modes). Existing, already-saved
                              // appointments come from provider.form.schedules (edit
                              // mode) and are staged for removal on save, same as
                              // certificates/tools/prerequisites. Newly added ones
                              // aren't sent to the server until save is pressed.
                              SectionCard(
                                featureKey: 'course_details.schedule',
                                icon: Icons.event_available_rounded,
                                title: 'weekly_schedule'.tr,
                                items: [
                                  ...provider.form.schedules.map(
                                        (s) =>
                                    '${slotDayLabel(s.day)} • ${AppTime.clock(s.startTime)} – ${AppTime.clock(s.endTime)}',
                                  ),
                                  ...provider.pendingSchedules.map(
                                        (s) =>
                                    '${slotDayLabel(s.day)} • ${AppTime.clock(s.startTime)} – ${AppTime.clock(s.endTime)}',
                                  ),
                                ],
                                onAdd: _showAddAppointmentSheet,
                                onRemove: (i) {
                                  final existingCount =
                                      provider.form.schedules.length;
                                  if (i < existingCount) {
                                    provider.removeFormSchedule(i);
                                  } else {
                                    provider.removePendingSchedule(
                                      i - existingCount,
                                    );
                                  }
                                },
                              ),
                            ],
                          )),
                      const SizedBox(height: AppSpace.md),

                      // ═══ OPTIONAL — collapsed ═════════════════════════════════════════════
                      ParentComponent(
                          featureKey: 'course_form.optional',
                          child: _CollapsibleSection(
                            icon: Icons.add_circle_outline_rounded,
                            title: 'cf_optional'.tr,
                            subtitle: 'cf_optional_sub'.tr,
                            expanded: _optionalOpen,
                            onToggle: () =>
                                setState(() => _optionalOpen = !_optionalOpen),
                            children: [
                              // Course reel (عرض أولي) — optional intro video shown
                              // instead of the course image on the course profile.
                              CourseReelField(
                                controller: _reelCtrl,
                                posterUrl: _logoBytes != null
                                    ? null
                                    : _coverUrl,
                              ),
                              const SizedBox(height: AppSpace.md),
                              // Certificate template: the create-mode "optional
                              // setup" card, or — when editing — a card that lets
                              // the teacher view/replace the template on their
                              // existing certificate (or set one up for the first
                              // time) directly, uploading immediately since the
                              // course already exists.
                              ParentComponent(
                                featureKey: 'course_form.certificate_template',
                                child: const _CertificateDesignsLink(),
                              ),
                              const SizedBox(height: AppSpace.sm),
                              SectionCard(
                                featureKey: 'course_details.certificates',
                                icon: Icons.workspace_premium_rounded,
                                title: 'certificates_section'.tr,
                                items: provider.form.certificates,
                                onAdd: () => addItemDialog(
                                  'add_certificate'.tr,
                                  provider.addFormCertificate,
                                  context,
                                ),
                                onRemove: provider.removeFormCertificate,
                              ),
                              const SizedBox(height: AppSpace.sm),
                              SectionCard(
                                featureKey: 'course_details.tools',
                                icon: Icons.build_rounded,
                                title: 'tools_section'.tr,
                                items: provider.form.tools,
                                onAdd: () => addItemDialog(
                                  'add_tool'.tr,
                                  provider.addFormTool,
                                  context,
                                ),
                                onRemove: provider.removeFormTool,
                              ),
                              const SizedBox(height: AppSpace.sm),
                              SectionCard(
                                featureKey: 'course_details.prerequisites',
                                icon: Icons.checklist_rounded,
                                title: 'prerequisites_section'.tr,
                                items: provider.form.prerequisites,
                                onAdd: () => addItemDialog(
                                  'add_prerequisite'.tr,
                                  provider.addFormPrerequisite,
                                  context,
                                ),
                                onRemove: provider.removeFormPrerequisite,
                              ),
                            ],
                          )),
                      const SizedBox(height: AppSpace.lg),
                    ],
                  ),
                ),
              ),
            ),

            // ── Sticky footer ──────────────────────────────────────────────
            _StickyFooter(
              isEdit: _isEdit,
              canSave: canSave,
              isLoading: provider.isLoading,
              onSave: () => _submit(
                publish: true,
                listProvider: listProvider,
                formProvider: provider,
              ),
              onSaveDraft: _isEdit
                  ? null
                  : () => _submit(
                publish: false,
                listProvider: listProvider,
                formProvider: provider,
              ),
              course: widget.course,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero header with gradient + image picker
// ─────────────────────────────────────────────────────────────────────────────

/// The course's cover at the top of the form.
class _CoverPicker extends StatelessWidget {
  final Uint8List? logoBytes;
  final XFile? logoFile;
  final String? imageUrl;
  final Future<void> Function(XFile file) onChange;
  final Future<void> Function()? onRemove;

  const _CoverPicker({
    required this.logoBytes,
    required this.imageUrl,
    this.logoFile,
    required this.onChange,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: EditableImage(
        onChange: onChange,
        imageUrl: imageUrl,
        imageByte: logoBytes,
        imageFile: logoFile,
        size: context.height / 6,
        onRemove: onRemove,
        removeMessage: 'cover_remove_confirm'.tr,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable form card with icon + title
// ─────────────────────────────────────────────────────────────────────────────

/// A group of the form on paper (the card surface on a warm hairline, no shadow): a quiet glyph and the group's name
/// in the editorial section face, then its fields.
class _FormCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _FormCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: context.colors.cardBg,
      borderRadius: AppRadius.cardAll,
      border: Border.all(color: context.colors.divider, width: AppBorder.hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.sm),
          child: _GroupTitle(icon: icon, title: title),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    ),
  );
}

/// A form group's heading: a quiet glyph in the medium ink and the name in the editorial section face.
class _GroupTitle extends StatelessWidget {
  const _GroupTitle({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: AppSpace.xxs),
        child: Icon(icon, size: AppIconSize.md, color: context.colors.textMedium),
      ),
      const SizedBox(width: AppSpace.sm),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
            ),
            if (subtitle != null && subtitle!.isNotEmpty)
              Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ],
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Certificate template — EDIT mode: uploads immediately (the course already
// exists), shows the existing template if there is one.
// ─────────────────────────────────────────────────────────────────────────────

class _EditCertificateTemplateCard extends StatefulWidget {
  final TeacherCourse course;

  const _EditCertificateTemplateCard({required this.course});

  @override
  State<_EditCertificateTemplateCard> createState() =>
      _EditCertificateTemplateCardState();
}

class _EditCertificateTemplateCardState
    extends State<_EditCertificateTemplateCard> {
  late final TextEditingController _titleCtrl;
  String? _templateUrl;
  Uint8List? _pickedBytes;
  bool _uploading = false;

  CourseCertificate? get _existingCert => widget.course.certificates.isNotEmpty
      ? widget.course.certificates.first
      : null;

  @override
  void initState() {
    super.initState();
    _templateUrl = _existingCert?.templateUrl;
    _titleCtrl = TextEditingController(
      text: _existingCert?.title ?? 'default_certificate_title'.tr,
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (file == null || !mounted) return;

    final img = await cropImageWithName(context, await file.readAsBytes(), file.name, allowBackground: false); // a certificate page, not a photo
    if (img == null) return;
    final bytes = img.bytes;
    setState(() {
      _pickedBytes = bytes;
      _uploading = true;
    });

    final provider = context.read<CourseFormProvider>();
    final url = await provider.updateCertificateTemplate(
      courseId: widget.course.id,
      existingCertificateId: _existingCert?.id,
      title: _titleCtrl.text.trim().isEmpty
          ? 'default_certificate_title'.tr
          : _titleCtrl.text.trim(),
      // what the person cropped and saw in the preview, not the file they first picked
      file: XFile.fromData(bytes, name: img.name, path: img.name),
    );

    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (url != null) {
        _templateUrl = url;
      } else {
        _pickedBytes = null;
      }
    });

    if (url == null && mounted) {
      showAppNotice('certificate_template_upload_failed'.tr, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasExisting = _existingCert != null;

    return _FormCard(
      icon: Icons.workspace_premium_rounded,
      title: 'certificate_template_card_title'.tr,
      children: [
        Text(
          hasExisting
              ? 'certificate_template_card_hint_edit'.tr
              : 'certificate_template_card_hint'.tr,
          style: AppType.meta(context),
        ),
        const SizedBox(height: AppSpace.md),
        if (hasExisting)
          _LabeledField(
            label: 'certificate_title_label'.tr,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: AppRadius.controlAll,
                border: Border.all(color: context.colors.divider, width: AppBorder.strong),
              ),
              child: Text(_existingCert!.title, style: AppType.bodyStrong(context)),
            ),
          )
        else
          _LabeledField(
            label: 'certificate_title_label'.tr,
            child: MyTextField(
              controller: _titleCtrl,
              label: 'certificate_title_label'.tr,
            ),
          ),
        const SizedBox(height: AppSpace.md),
        // a real button (keyboard, screen reader), not a bare GestureDetector
        Semantics(
          button: true,
          label: (_templateUrl != null || _pickedBytes != null) ? 'change_template_btn'.tr : 'upload_template_btn'.tr,
          child: Material(
            color: context.colors.background,
            borderRadius: AppRadius.cardAll,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _uploading ? null : _pick,
              child: AspectRatio(
                aspectRatio: 1.6,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.cardAll,
                    border: Border.all(color: context.colors.divider, width: AppBorder.strong),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _uploading
                      ? const Center(child: AppLoadingIndicator())
                      : _pickedBytes != null
                          ? Image.memory(_pickedBytes!, fit: BoxFit.cover, excludeFromSemantics: true)
                          : _templateUrl != null
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(_templateUrl!, fit: BoxFit.cover, excludeFromSemantics: true,
                                        // a dead link shows the calm well, not Flutter's broken-image glyph
                                        errorBuilder: (_, _, _) => Center(child: Icon(Icons.image_not_supported_outlined, color: context.colors.textLight))),
                                    // the corner that reads first in either direction (was a fixed right: in RTL too)
                                    PositionedDirectional(
                                      bottom: AppSpace.xs,
                                      end: AppSpace.xs,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
                                        decoration: BoxDecoration(
                                          color: context.colors.textMedium,
                                          borderRadius: BorderRadius.circular(AppRadius.pill),
                                        ),
                                        child: Text(
                                          'change_template_btn'.tr,
                                          style: AppType.meta(context).copyWith(fontWeight: FontWeight.w700, color: context.colors.onHero),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.add_photo_alternate_rounded, size: AppIconSize.xl - 4, color: context.colors.textLight),
                                      const SizedBox(height: AppSpace.xs),
                                      Text('upload_template_btn'.tr, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Labeled field
// ─────────────────────────────────────────────────────────────────────────────

/// A field with the kit's label above its well.
class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;

  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppFieldLabel(label),
      child,
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Live / Recorded / Both selector
// ─────────────────────────────────────────────────────────────────────────────

class _CourseTypeSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _CourseTypeSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'course_form.course_type',
    child: _buildContent(context),
  );

  /// One choice: solid emerald when chosen (the on-hero ink), a quiet well otherwise.
  Widget _choice(BuildContext context, String value, IconData icon, String label) {
    final c = context.colors;
    final on = selected == value;
    final motion = AppMotion.of(context);
    return Semantics(
      button: true,
      selected: on,
      child: AnimatedContainer(
        duration: motion.fast,
        curve: AppEase.out,
        decoration: BoxDecoration(
          color: on ? c.primary : c.inputBg,
          borderRadius: AppRadius.controlAll,
          border: Border.all(color: on ? c.primary : c.divider, width: AppBorder.hairline),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: AppRadius.controlAll,
            onTap: () => onChanged(value),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.primary),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.sm, horizontal: AppSpace.xxs),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: AppIconSize.md, color: on ? c.onHero : c.textMedium),
                    const SizedBox(height: AppSpace.xxs),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.label(context).copyWith(
                        fontWeight: FontWeight.w600,
                        color: on ? c.onHero : c.textDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final items = <(String, IconData, String)>[
      ('live', Icons.sensors_rounded, 'cf_type_live'.tr),
      ('recorded', Icons.play_circle_outline_rounded, 'cf_type_recorded'.tr),
      ('both', Icons.all_inclusive_rounded, 'cf_type_both'.tr),
    ];
    final hint = switch (selected) {
      'live' => 'cf_hint_live'.tr,
      'both' => 'cf_hint_both'.tr,
      _ => 'cf_hint_recorded'.tr,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final (i, (value, icon, label)) in items.indexed) ...[
              if (i > 0) const SizedBox(width: AppSpace.xs),
              Expanded(child: _choice(context, value, icon, label)),
            ],
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        Text(hint, style: AppType.meta(context)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Collapsible card (children stay mounted, so validators still run)
// ─────────────────────────────────────────────────────────────────────────────

class _CollapsibleSection extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  const _CollapsibleSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    return Material(
      color: c.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardAll,
        side: BorderSide(color: c.divider, width: AppBorder.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            child: InkWell(
              onTap: onToggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.primary),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.md, AppSpace.sm, AppSpace.md),
                  child: Row(
                    children: [
                      Expanded(child: _GroupTitle(icon: icon, title: title, subtitle: subtitle)),
                      const SizedBox(width: AppSpace.xs),
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: motion.base,
                        curve: AppEase.out,
                        child: Icon(Icons.keyboard_arrow_down_rounded, color: c.textMedium, size: AppIconSize.lg),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // children stay mounted while folded, so their validators still run
          AnimatedSize(
            duration: motion.slow,
            curve: AppEase.out,
            alignment: Alignment.topCenter,
            child: Visibility(
              visible: expanded,
              maintainState: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sticky footer
// ─────────────────────────────────────────────────────────────────────────────

class _StickyFooter extends StatelessWidget {
  final bool isEdit;
  final bool canSave;
  final bool isLoading;

  /// Edit mode: save edits. Create mode: publish immediately.
  final VoidCallback onSave;

  /// Create mode only: save the new course as a draft.
  final VoidCallback? onSaveDraft;

  final TeacherCourse? course;

  const _StickyFooter({
    required this.isEdit,
    required this.canSave,
    required this.isLoading,
    required this.onSave,
    this.onSaveDraft,
    required this.course,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bottom = MediaQuery.of(context).padding.bottom;
    final showDraftBtn = !isEdit && onSaveDraft != null;
    final ready = canSave && !isLoading;

    // the bar sits on paper under a warm hairline (it is part of the page, not a floating layer)
    return Container(
      padding: EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.sm + bottom),
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border(top: BorderSide(color: c.divider, width: AppBorder.hairline)),
      ),
      child: Row(
        children: [
          // Save as draft (create mode only)
          if (showDraftBtn) ...[
            Expanded(
              flex: 2,
              child: AppButton.secondary(
                label: 'save_as_draft_btn'.tr,
                size: AppButtonSize.lg,
                expand: true,
                onPressed: ready ? onSaveDraft : null,
              ),
            ),
            const SizedBox(width: AppSpace.sm),
          ],

          // Primary save/publish button: while it cannot save it says why (the wider of the two)
          Expanded(
            flex: 3,
            child: AppButton.primary(
              label: canSave
                  ? (isEdit
                      ? 'btn_save_edits'.tr
                      : (showDraftBtn ? 'publish_course_btn'.tr : 'create_course_btn'.tr))
                  : (isEdit ? 'no_changes_to_save'.tr : 'enter_course_title_first'.tr),
              size: AppButtonSize.lg,
              expand: true,
              busy: isLoading,
              onPressed: ready ? onSave : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status card (edit mode) — toggle published / draft
// ─────────────────────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final bool isPublished;
  final bool isLoading;
  final VoidCallback onToggle;

  const _StatusCard({
    required this.isPublished,
    required this.isLoading,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return _FormCard(
      icon: Icons.visibility_rounded,
      title: 'course_status_title'.tr,
      children: [
        Row(
          children: [
            Flexible(
              child: AppStatusBadge(
                label: isPublished ? 'status_published'.tr : 'status_draft'.tr,
                tone: isPublished ? AppTone.success : AppTone.warning,
                dot: true,
              ),
            ),
            const Spacer(),
            if (isLoading)
              AppLoadingIndicator()
            else
              AppSwitch(
                value: isPublished,
                semanticLabel: 'status_published'.tr,
                onChanged: (_) => onToggle(),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          isPublished
              ? 'course_status_published_hint'.tr
              : 'course_status_draft_hint'.tr,
          style: AppType.meta(context),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Local "add appointment" sheet (create mode) — writes to CourseFormProvider
// instead of hitting the network, since the course doesn't exist yet.
// ─────────────────────────────────────────────────────────────────────────────

class _LocalAddScheduleSheet extends StatefulWidget {
  final Set<String> existingDays;
  final void Function(String day, String startTime, String endTime) onAdd;

  const _LocalAddScheduleSheet({
    required this.existingDays,
    required this.onAdd,
  });

  @override
  State<_LocalAddScheduleSheet> createState() => _LocalAddScheduleSheetState();
}

class _LocalAddScheduleSheetState extends State<_LocalAddScheduleSheet> {
  static final List<(String, String)> _days = kDayOrder
      .map((d) => (d, kDayLabels[d] ?? d))
      .toList();

  String _day = kDayOrder.first;
  TimeOfDay _start = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 12, minute: 0);

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  bool get _valid =>
      _end.hour * 60 + _end.minute > _start.hour * 60 + _start.minute;

  Future<void> _pick(bool isStart) async {
    final p = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
    );
    if (p == null || !mounted) return;
    setState(() => isStart ? _start = p : _end = p);
  }

  Future<void> _submit() async {
    if (!_valid) return;

    if (widget.existingDays.contains(_day)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => Directionality(
          textDirection: Directionality.of(context),
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'duplicate-schedule'.tr,
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: Text(
              'same-day-schedule-exists'.tr,
              style: TextStyle(fontFamily: AppFonts.display),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'cancel'.tr,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    color: context.colors.textMedium,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  'add'.tr,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    color: context.colors.onHero,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      if (ok != true || !mounted) return;
    }

    widget.onAdd(_day, _fmt(_start), _fmt(_end));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AppSheetContent(
    title: 'add-weekly-appointment'.tr,
    children: [
          Text(
            'today'.tr,
            style: AppType.label(context),
          ),
          const SizedBox(height: AppSpace.xs),
          SizedBox(
            height: AppTouch.min,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _days.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpace.xs),
              itemBuilder: (_, i) {
                final (v, l) = _days[i];
                final sel = _day == v;
                return GestureDetector(
                  onTap: () => setState(() => _day = v),
                  child: AnimatedContainer(
                    duration: AppMotion.of(context).fast,
                    curve: AppEase.out,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                    decoration: BoxDecoration(
                      color: sel ? context.colors.primary : context.colors.inputBg,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(
                        color: sel ? context.colors.primary : context.colors.divider,
                        width: AppBorder.hairline,
                      ),
                    ),
                    child: Text(
                      l,
                      style: context.colors.label.copyWith(
                        color: sel ? context.colors.onHero : context.colors.textMedium,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              Expanded(
                child: _TimeField(
                  label: 'start-time'.tr,
                  time: _start,
                  onTap: () => _pick(true),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: _TimeField(
                  label: 'end-time'.tr,
                  time: _end,
                  onTap: () => _pick(false),
                  hasError: !_valid,
                ),
              ),
            ],
          ),
          if (!_valid) ...[
            const SizedBox(height: AppSpace.xs),
            Text(
              'end-time-must-be-after-start-time'.tr,
              style: context.colors.caption.copyWith(
                color: context.colors.danger,
              ),
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          AppButton.primary(
            label: 'add-appointment'.tr,
            expand: true,
            onPressed: _valid ? _submit : null,
          ),
    ],
  );
}

class _TimeField extends StatelessWidget {
  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;
  final bool hasError;

  const _TimeField({
    required this.label,
    required this.time,
    required this.onTap,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppFieldLabel(label),
        Material(
          color: c.inputBg,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.controlAll,
            side: BorderSide(
              color: hasError ? c.danger : c.divider,
              width: hasError ? AppBorder.strong : AppBorder.hairline,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.primary),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                child: Row(
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: AppIconSize.md,
                      color: hasError ? c.danger : c.textMedium,
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          AppTime.clockMinutes(time.hour * 60 + time.minute),
                          style: AppType.figure(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Certificates are designed once (Profile → My certificate designs) and assigned to all or some courses —
/// no per-course template inputs here any more. A certificate is an achievement: the gold block.
class _CertificateDesignsLink extends StatelessWidget {
  const _CertificateDesignsLink();

  @override
  Widget build(BuildContext context) {
    return AppBlock(
      tone: AppBlockTone.gold,
      padding: AppSpace.card,
      semanticLabel: 'cert_designs_link_title'.tr,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => deferredCertificateDesigns())),
      child: Builder(builder: (context) {
        final b = AppBlock.colorsOf(context);
        return Row(children: [
          Container(
            width: AppTouch.min - AppSpace.xxs,
            height: AppTouch.min - AppSpace.xxs,
            decoration: BoxDecoration(color: Color.lerp(b.surface, b.ink, 0.06), borderRadius: AppRadius.chipAll),
            child: Icon(Icons.workspace_premium_rounded, color: b.accentInk(context.colors.accent2), size: AppIconSize.lg),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('cert_designs_link_title'.tr, style: AppType.bodyStrong(context).copyWith(color: b.ink)),
              Text('cert_designs_link_sub'.tr, style: AppType.meta(context).copyWith(color: b.muted)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: b.muted),
        ]);
      }),
    );
  }
}
