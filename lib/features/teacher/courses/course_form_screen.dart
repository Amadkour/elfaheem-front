import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'dart:typed_data';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/teacher/courses/teacher_courses_provider.dart';
import 'package:flutter_education_app/utils/widget/editable_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/api_client.dart';
import '../../../design/app_switch.dart';
import '../../../utils/widget/base_page.dart';
import '../../../utils/widget/primary_menue.dart';
import '../../../utils/widget/text_field.dart';
import '../home/teacher_models.dart';
import '../../student/models.dart' show CourseStatus;
import '../schedules/schedules_provider.dart'
    show kDayOrder, kDayLabels, slotDayLabel;
import 'component/add_item_dialog.dart';
import 'component/gradient_button.dart';
import 'component/section_card.dart';
import 'component/currency_selector.dart';
import 'component/course_progress_status_card.dart';
import 'component/recommended_courses_field.dart';
import 'component/next_courses_field.dart';
import 'course_form_provider.dart';
import 'course_reel_field.dart';
import 'course_privacy_card.dart';
import '../../shared/roadmap/roadmap_api.dart' show RoadmapApi, kRoadmapPathKey, roadmapOff;
import '../../shared/roadmap/roadmap_editor.dart' show RoadmapLevelChips, RoadmapTagsInput, showRoadmapEditor;
import '../../shared/roadmap/roadmap_tab.dart' show roadmapAllowedHere;
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

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
    _reelCtrl = CourseReelController();

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
    } else {
      _showSnack(
        formProvider.errorMessage ?? 'error_please_retry'.tr,
        context.colors.danger,
      );
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
    await showModalBottomSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LocalAddScheduleSheet(
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
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Column(
          children: [
            // ── Gradient hero header ───────────────────────────────────────
            _HeroHeader(
              isEdit: _isEdit,
              logoBytes: _logoBytes,
              imageUrl: widget.course?.imageUrl,
              logoFile: _logoFile,
              onChange: (XFile file) async {
                _logoBytes = await file.readAsBytes();
                setState(() {
                  _logoFile = file;
                });
              },
            ),
            // ── Scrollable form ────────────────────────────────────────────
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                              const SizedBox(height: 14),
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
                              const SizedBox(height: 14),
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
                              const SizedBox(height: 14),
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
                              const SizedBox(height: 16),
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
                              const SizedBox(height: 14),
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
                              const SizedBox(height: 14),
                              // Yearly = the existing price field; the other two
                              // plans are optional (empty = not offered).
                              Row(
                                children: [
                                  Expanded(
                                    child: _LabeledField(
                                      label: 'price_yearly_label'.tr,
                                      child: MyTextField(
                                        controller: _priceCtrl,
                                        label: 'price_yearly_label'.tr,
                                        keyboard:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: _LabeledField(
                                      label: 'price_six_months_label'.tr,
                                      child: MyTextField(
                                        controller: _priceSixMonthsCtrl,
                                        label: 'price_six_months_label'.tr,
                                        keyboard:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _LabeledField(
                                      label: 'price_monthly_label'.tr,
                                      child: MyTextField(
                                        controller: _priceMonthlyCtrl,
                                        label: 'price_monthly_label'.tr,
                                        keyboard:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'price_plans_hint'.tr,
                                style: TextStyle(
                                  fontFamily: AppFonts.family,
                                  fontSize: 11.5,
                                  color: context.colors.textLight,
                                ),
                              ),
                              const SizedBox(height: 14),
                              // Plan students see first (course profile + home).
                              _LabeledField(
                                label: 'default_plan_label'.tr,
                                child: Wrap(
                                  spacing: 8,
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
                              const SizedBox(height: 14),
                              CurrencySelector(
                                label: 'currency_label'.tr,
                                selected: provider.selectedCurrency,
                                onChanged: provider.onChangeCurrency,
                              ),
                            ],
                          )),
                      const SizedBox(height: 16),

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
                        const SizedBox(height: 16),
                        CourseProgressStatusCard(
                          status: _progressStatus,
                          isLoading: _progressStatusLoading,
                          onChanged: (s) =>
                              _changeProgressStatus(s, listProvider),
                        ),
                        const SizedBox(height: 16),
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
                              _LabeledField(
                                label: 'expected_hours_label'.tr,
                                child: MyTextField(
                                  controller: _hoursCtrl,
                                  label: 'hours_label'.tr,
                                  keyboard: TextInputType.number,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'discount_section_title'.tr,
                                // e.g. "Discount (optional)"
                                style: TextStyle(
                                  fontFamily: AppFonts.display,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: context.colors.heroShade.withValues(alpha: 0.55),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'discount_section_hint'.tr,
                                // e.g. "Leave empty for no discount"
                                style: TextStyle(
                                  fontFamily: AppFonts.family,
                                  fontSize: 11,
                                  color: context.colors.textLight,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: _LabeledField(
                                      label: 'discount_percentage_label'.tr,
                                      // "Discount %"
                                      child: MyTextField(
                                        controller: _discountPercentCtrl,
                                        label: 'discount_percentage_label'.tr,
                                        keyboard:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                        validator: (v) {
                                          final n = double.tryParse(v ?? '');
                                          if (v != null &&
                                              v.trim().isNotEmpty &&
                                              (n == null || n <= 0 || n > 100)) {
                                            return 'discount_percentage_validator'
                                                .tr; // "0–100"
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _LabeledField(
                                      label: 'discount_days_label'.tr,
                                      // "Days (optional)"
                                      child: MyTextField(
                                        controller: _discountDaysCtrl,
                                        label: 'discount_days_label'.tr,
                                        keyboard: TextInputType.number,
                                        validator: (v) {
                                          final n = int.tryParse(v ?? '');
                                          if (v != null &&
                                              v.trim().isNotEmpty &&
                                              (n == null || n <= 0)) {
                                            return 'discount_days_validator'
                                                .tr; // "must be a positive number of days"
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_isEdit &&
                                  (widget.course?.discountActive ?? false) &&
                                  _discountPercentCtrl.text.trim().isNotEmpty) ...[
                                const SizedBox(height: 8),
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
                                      style: TextStyle(
                                        fontFamily: AppFonts.display,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: context.colors.danger,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              CoursePrivacyCard(
                                isPrivate: _isPrivate,
                                codeCtrl: _accessCodeCtrl,
                                courseId: widget.course?.id,
                                // edit → loads the current code
                                onChanged: (v) => setState(() => _isPrivate = v),
                              ),
                              const SizedBox(height: 16),
                              ParentComponent(
                                  featureKey: 'course_form.relations',
                                  child: _FormCard(
                                    icon: Icons.route_rounded,
                                    title: 'course_relations_title'.tr,
                                    children: [
                                      Text(
                                        'next_course_label'.tr,
                                        style: TextStyle(
                                          fontFamily: AppFonts.display,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: context.colors.heroShade.withValues(alpha: 0.55),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      if (provider.nextCoursesInPath) ...[
                                        // ONE place to edit the path: the course's Path tab (D-120)
                                        Text(
                                          _t('تُحدَّد الكورسات التالية والمتطلبات السابقة في تبويب «المسار» للكورس.',
                                              'Next courses and prerequisites are set in the course’s Path tab.'),
                                          style: TextStyle(fontFamily: AppFonts.family, fontSize: 11, color: context.colors.textLight),
                                        ),
                                        const SizedBox(height: 4),
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
                                          style: TextStyle(
                                            fontFamily: AppFonts.family,
                                            fontSize: 11,
                                            color: context.colors.textLight,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
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
                                        const SizedBox(height: 18),
                                        Text(
                                          _t('المستوى', 'Level'),
                                          style: TextStyle(
                                            fontFamily: AppFonts.display,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: context.colors.heroShade.withValues(alpha: 0.55),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        RoadmapLevelChips(value: provider.level, onChanged: provider.setLevel),
                                        const SizedBox(height: 18),
                                        Text(
                                          _t('كلمات مفتاحية', 'Topic words'),
                                          style: TextStyle(
                                            fontFamily: AppFonts.display,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: context.colors.heroShade.withValues(alpha: 0.55),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _t('تساعد على اقتراح كورسك للطلاب المهتمين.', 'They help suggest your course to interested students.'),
                                          style: TextStyle(fontFamily: AppFonts.family, fontSize: 11, color: context.colors.textLight),
                                        ),
                                        const SizedBox(height: 8),
                                        RoadmapTagsInput(tags: provider.tags, onAdd: provider.addTag, onRemove: provider.removeTag),
                                      ],
                                      const SizedBox(height: 18),
                                      Text(
                                        'recommended_courses_label'.tr,
                                        style: TextStyle(
                                          fontFamily: AppFonts.display,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: context.colors.heroShade.withValues(alpha: 0.55),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      RecommendedCoursesField(
                                        options: provider.otherCourses,
                                        selectedIds:
                                        provider.selectedRecommendedCourseIds,
                                        onToggle: provider.toggleRecommendedCourse,
                                      ),
                                    ],
                                  )),
                              const SizedBox(height: 16),
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
                      const SizedBox(height: 16),

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
                                    : widget.course?.imageUrl,
                              ),
                              const SizedBox(height: 16),
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
                              const SizedBox(height: 12),
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
                              const SizedBox(height: 12),
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
                              const SizedBox(height: 12),
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
                      const SizedBox(height: 24),
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

class _HeroHeader extends StatelessWidget {
  final bool isEdit;
  final Uint8List? logoBytes;
  final XFile? logoFile;
  final String? imageUrl;
  final Future<void> Function(XFile file) onChange;

  const _HeroHeader({
    required this.isEdit,
    required this.logoBytes,
    required this.imageUrl,
    this.logoFile,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final unit = context.height / 12;
    return SizedBox(
      height: (3 * unit) + top,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Gradient background
          Positioned(
            top: 0,
            right: 0,
            left: 0,
            child: Container(
              height: unit * 2,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    context.colors.primaryDark,
                    context.colors.primary,
                    context.colors.primaryLight,
                  ],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            left: 0,
            child: Container(height: unit, color: context.colors.background),
          ),
          // Decorative circles
          Positioned(
            top: -30,
            left: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.colors.onHero.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: 30,
            right: -20,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.colors.onHero.withValues(alpha: 0.08),
              ),
            ),
          ),
          // Back button + title
          Positioned(
            top: top + 12,
            right: 16,
            left: 16,
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 38,
                    height: 38,
                    margin: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: context.colors.onHero.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.arrow_back_ios_rounded,
                      color: context.colors.onHero,
                      size: 16,
                      semanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    isEdit
                        ? 'edit_course_title'.tr
                        : 'create_new_course_title'.tr,
                    style: TextStyle(
                      color: context.colors.onHero,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      fontFamily: AppFonts.display,
                    ),
                  ),
                ),
                // Mode badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.onHero.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: context.colors.onHero.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    isEdit ? 'edit_badge'.tr : 'new_badge'.tr,
                    style: TextStyle(
                      color: context.colors.onHero,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFamily: AppFonts.display,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: AlignmentGeometry.bottomCenter,
            child: EditableImage(
              onChange: onChange,
              imageUrl: imageUrl,
              imageByte: logoBytes,
              imageFile: logoFile,
              size: context.height / 6,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable form card with icon + title
// ─────────────────────────────────────────────────────────────────────────────

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
    decoration: BoxDecoration(
      color: context.colors.cardBg,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: context.colors.heroShade.withValues(alpha: 0.06),
          blurRadius: 18,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: context.colors.primaryGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: context.colors.onHero),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  fontFamily: AppFonts.display,
                  color: context.colors.textDark,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: context.colors.heroShade.withValues(alpha: 0.06)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    ),
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

    final img = await cropImageWithName(context, await file.readAsBytes(), file.name);
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
      file: file,
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
          style: TextStyle(
            fontFamily: AppFonts.family,
            fontSize: 12,
            color: context.colors.textMedium,
          ),
        ),
        const SizedBox(height: 14),
        if (hasExisting)
          _LabeledField(
            label: 'certificate_title_label'.tr,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.colors.divider, width: 1.2),
              ),
              child: Text(
                _existingCert!.title,
                style: TextStyle(
                  fontFamily: AppFonts.family,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textDark,
                ),
              ),
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
        const SizedBox(height: 14),
        GestureDetector(
          onTap: _uploading ? null : _pick,
          child: AspectRatio(
            aspectRatio: 1.6,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.colors.divider, width: 1.2),
                color: context.colors.background,
              ),
              clipBehavior: Clip.antiAlias,
              child: _uploading
                  ? const Center(child: AppLoadingIndicator())
                  : _pickedBytes != null
                  ? Image.memory(_pickedBytes!, fit: BoxFit.cover)
                  : _templateUrl != null
                  ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(_templateUrl!, fit: BoxFit.cover),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: context.colors.textMedium,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'change_template_btn'.tr,
                        style: TextStyle(
                          fontFamily: AppFonts.family,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: context.colors.onHero,
                        ),
                      ),
                    ),
                  ),
                ],
              )
                  : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_rounded,
                      size: 28,
                      color: context.colors.textLight,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'upload_template_btn'.tr,
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textMedium,
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

// ─────────────────────────────────────────────────────────────────────────────
// Labeled field
// ─────────────────────────────────────────────────────────────────────────────

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;

  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          fontFamily: AppFonts.display,
          color: context.colors.heroShade.withValues(alpha: 0.55),
        ),
      ),
      const SizedBox(height: 6),
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
            for (final (value, icon, label) in items)
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: GestureDetector(
                    onTap: () => onChanged(value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        gradient: selected == value
                            ? context.colors.primaryGradient
                            : null,
                        color: selected == value
                            ? null
                            : context.colors.background,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected == value
                              ? Colors.transparent
                              : context.colors.heroShade.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            icon,
                            size: 20,
                            color: selected == value
                                ? context.colors.onHero
                                : context.colors.textMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            label,
                            style: TextStyle(
                              fontFamily: AppFonts.display,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: selected == value
                                  ? context.colors.onHero
                                  : context.colors.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          hint,
          style: TextStyle(
            fontFamily: AppFonts.family,
            fontSize: 11,
            color: context.colors.textLight,
          ),
        ),
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
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.colors.cardBg,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: context.colors.heroShade.withValues(alpha: 0.06),
          blurRadius: 18,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: context.colors.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 17, color: context.colors.onHero),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          fontFamily: AppFonts.display,
                          color: context.colors.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontFamily: AppFonts.family,
                          fontSize: 11,
                          color: context.colors.textLight,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: context.colors.textMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: Visibility(
            visible: expanded,
            maintainState: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
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
    final bottom = MediaQuery.of(context).padding.bottom;
    final showDraftBtn = !isEdit && onSaveDraft != null;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + bottom),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        boxShadow: [
          BoxShadow(
            color: context.colors.heroShade.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Save as draft (create mode only)
          if (showDraftBtn) ...[
            Expanded(
              child: GestureDetector(
                onTap: (canSave && !isLoading) ? onSaveDraft : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 52,
                  decoration: BoxDecoration(
                    color: canSave
                        ? context.colors.primary.withValues(alpha: 0.08)
                        : context.colors.inputBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: canSave
                          ? context.colors.primary.withValues(alpha: 0.35)
                          : context.colors.divider,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'save_as_draft_btn'.tr,
                      style: TextStyle(
                        color: canSave
                            ? context.colors.primary
                            : context.colors.textLight,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        fontFamily: AppFonts.display,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],

          // Primary save/publish button
          Expanded(
            child: GestureDetector(
              onTap: (canSave && !isLoading) ? onSave : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                height: 52,
                decoration: BoxDecoration(
                  gradient: canSave
                      ? context.colors.primaryGradient
                      : LinearGradient(
                    colors: [context.colors.divider, context.colors.divider],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: canSave ? context.colors.primaryShadow : null,
                ),
                child: Center(
                  child: isLoading
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: AppLoadingIndicator(),
                  )
                      : Text(
                    canSave
                        ? (isEdit
                        ? 'btn_save_edits'.tr
                        : (showDraftBtn
                        ? 'publish_course_btn'.tr
                        : 'create_course_btn'.tr))
                        : (isEdit
                        ? 'no_changes_to_save'.tr
                        : 'enter_course_title_first'.tr),
                    style: TextStyle(
                      color: context.colors.onHero,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      fontFamily: AppFonts.display,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Schedule button (edit mode only)
          // if (isEdit && course != null) ...[
          //   const SizedBox(width: 10),
          //   GestureDetector(
          //     onTap: () => Navigator.of(context).push(MaterialPageRoute(
          //         builder: (_) => TeacherSchedulesScreen(course: course!))),
          //     child: Container(
          //       width: 52, height: 52,
          //       decoration: BoxDecoration(
          //         color: context.colors.primary.withValues(alpha: 0.1),
          //         borderRadius: BorderRadius.circular(14),
          //         border: Border.all(
          //             color: context.colors.primary.withValues(alpha: 0.3)),
          //       ),
          //       child: Icon(Icons.calendar_month_rounded,
          //           size: 22, color: context.colors.primary),
          //     ),
          //   ),
          // ],
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
    final statusColor = isPublished
        ? context.colors.accent2
        : context.colors.warning;
    return _FormCard(
      icon: Icons.visibility_rounded,
      title: 'course_status_title'.tr,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isPublished ? 'status_published'.tr : 'status_draft'.tr,
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ),
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
        const SizedBox(height: 2),
        Text(
          isPublished
              ? 'course_status_published_hint'.tr
              : 'course_status_draft_hint'.tr,
          style: TextStyle(
            fontFamily: AppFonts.display,
            fontSize: 11,
            color: context.colors.textLight,
          ),
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
          textDirection: TextDirection.rtl,
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
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text('add-weekly-appointment'.tr, style: context.colors.h2),
          const SizedBox(height: 20),
          Text(
            'today'.tr,
            style: context.colors.label.copyWith(
              color: context.colors.textDark,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _days.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final (v, l) = _days[i];
                final sel = _day == v;
                return GestureDetector(
                  onTap: () => setState(() => _day = v),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: sel ? context.colors.primaryGradient : null,
                      color: sel ? null : context.colors.background,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: sel
                            ? Colors.transparent
                            : context.colors.divider,
                      ),
                      boxShadow: sel ? context.colors.primaryShadow : null,
                    ),
                    child: Text(
                      l,
                      style: context.colors.label.copyWith(
                        color: sel ? context.colors.onHero : context.colors.textMedium,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _TimeField(
                  label: 'start-time'.tr,
                  time: _start,
                  onTap: () => _pick(true),
                ),
              ),
              const SizedBox(width: 12),
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
            const SizedBox(height: 6),
            Text(
              'end-time-must-be-after-start-time'.tr,
              style: context.colors.caption.copyWith(
                color: context.colors.danger,
              ),
            ),
          ],
          const SizedBox(height: 24),
          GradientButton(
            label: 'add-appointment'.tr,
            isLoading: false,
            enable: _valid,
            onTap: _submit,
          ),
        ],
      ),
    ),
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: context.colors.label.copyWith(
          color: context.colors.textDark,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: context.colors.background,
            borderRadius: BorderRadius.circular(context.colors.radiusMedium),
            border: Border.all(
              color: hasError ? context.colors.danger : context.colors.divider,
              width: hasError ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.access_time_rounded,
                size: 18,
                color: hasError
                    ? context.colors.danger
                    : context.colors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                AppTime.clockMinutes(time.hour * 60 + time.minute),
                style: context.colors.h3.copyWith(fontSize: 18),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// Certificates are designed once (Profile → My certificate designs) and assigned to all or some courses —
/// no per-course template inputs here any more.
class _CertificateDesignsLink extends StatelessWidget {
  const _CertificateDesignsLink();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.cardBg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => deferredCertificateDesigns())),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.divider),
            gradient: LinearGradient(colors: [c.accent2.withValues(alpha: 0.12), c.cardBg]),
          ),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: c.accent2.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.workspace_premium_rounded, color: c.accent2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('cert_designs_link_title'.tr, style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800, color: c.textDark)),
                Text('cert_designs_link_sub'.tr, style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, color: c.textMedium)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: c.textLight),
          ]),
        ),
      ),
    );
  }
}
