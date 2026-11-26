import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_errors.dart' show appSharedFix, showAppError;
import 'package:flutter_education_app/design/app_kit.dart' show AppHeader, AppSpace, showAppSheet;
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_tokens.dart' show AppWidth;
import 'package:flutter_education_app/features/courses/course_setup_views.dart' show courseAreaRequiredText;
import 'package:flutter_education_app/features/courses/roadmap/roadmap_api.dart' show RoadmapApi, kRoadmapPathKey, roadmapOff;
import 'package:flutter_education_app/features/courses/roadmap/roadmap_editor.dart' show showRoadmapEditor;
import 'package:flutter_education_app/features/courses/roadmap/roadmap_tab.dart' show roadmapAllowedHere;
import 'package:flutter_education_app/features/courses/teacher/component/course_progress_status_card.dart';
import 'package:flutter_education_app/features/courses/teacher/course_form_provider.dart';
import 'package:flutter_education_app/features/courses/teacher/teacher_courses_provider.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/course_form_draft.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/form_parts.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/form_sections.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/weekly_slot_sheet.dart';
import 'package:flutter_education_app/features/help/help_info_button.dart' show HelpInfoButton;
import 'package:flutter_education_app/features/home/student/models.dart' show CourseStatus;
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';


// ─────────────────────────────────────────────────────────────────────────────
// Public entry point  — wraps the inner screen in a scoped provider
// ─────────────────────────────────────────────────────────────────────────────

class CourseFormScreen extends StatelessWidget {
  /// null → CREATE mode,  non-null → EDIT mode
  final TeacherCourse? course;

  /// The program type a NEW course starts with (`'quran'` from the Quran teacher hub, D-1343).
  final String programKind;

  const CourseFormScreen({super.key, this.course, this.programKind = 'course'});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => CourseFormProvider(api: ApiClient()),
    child: _CourseFormInner(course: course, programKind: programKind),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Inner stateful widget  (has access to the scoped provider)
// ─────────────────────────────────────────────────────────────────────────────

class _CourseFormInner extends StatefulWidget {
  final TeacherCourse? course;
  final String programKind;

  const _CourseFormInner({required this.course, this.programKind = 'course'});

  @override
  State<_CourseFormInner> createState() => _CourseFormInnerState();
}

class _CourseFormInnerState extends State<_CourseFormInner>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final CourseFormDraft _draft;
  bool _advancedOpen = false;
  bool _optionalOpen = false;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

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
    _draft = CourseFormDraft(widget.course)..addListener(_rebuild);

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
        await p.initCreate(context, programKind: widget.programKind);
      }
      _draft.address.text = p.address;
      _draft.address.addListener(() => p.setAddress(_draft.address.text));
      _fadeCtrl.forward();
    });
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _draft.removeListener(_rebuild);
    _draft.dispose();
    _fadeCtrl.dispose();
    super.dispose();
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
    if (formProvider.deliveryMode != 'online' && formProvider.area1 == null) {
      // in person needs an area: say so before any request (the server refuses it too, `course_area_required`)
      formProvider.markAreaMissing();
      _showSnack(courseAreaRequiredText(), context.colors.danger);
      return;
    }
    final type =
        (formProvider.selectedTeachingType?['text'] as String?) ?? 'recorded';

    TeacherCourse? result;
    final d = _draft;
    final discountPercentage = double.tryParse(d.discountPercent.text);
    final discountDays = int.tryParse(d.discountDays.text);

    if (_isEdit) {
      result = await formProvider.submitUpdate(
        widget.course!,
        titleAr: d.titleAr.text,
        titleEn: d.titleEn.text,
        descriptionAr: d.descAr.text,
        descriptionEn: d.descEn.text,
        type: type,
        isPrivate: d.isPrivate,
        accessCode: d.accessCode.text,
        fees: double.tryParse(d.price.text),
        priceMonthly: double.tryParse(d.priceMonthly.text),
        priceSixMonths: double.tryParse(d.priceSixMonths.text),
        totalHours: double.tryParse(d.hours.text),
        discountPercentage: discountPercentage,
        discountDays: discountDays,
        clearDiscount:
        discountPercentage == null &&
            (d.removeDiscount || (widget.course!.discountPercentage ?? 0) > 0),
        logoFile: d.logoFile,
      );
    } else {
      result = await formProvider.submitCreate(
        titleAr: d.titleAr.text,
        titleEn: d.titleEn.text,
        descriptionAr: d.descAr.text,
        descriptionEn: d.descEn.text,
        type: type,
        isPrivate: d.isPrivate,
        accessCode: d.accessCode.text,
        fees: double.tryParse(d.price.text) ?? 0,
        priceMonthly: double.tryParse(d.priceMonthly.text),
        priceSixMonths: double.tryParse(d.priceSixMonths.text),
        totalHours: double.tryParse(d.hours.text),
        discountPercentage: discountPercentage,
        discountDays: discountDays,
        logoFile: d.logoFile,
        certificateTemplateTitle: d.certTemplateFile != null
            ? d.certTitle.text.trim()
            : null,
        certificateTemplateFile: d.certTemplateFile,
        publish: publish,
      );
    }

    if (!mounted) return;

    if (result != null) {
      // The reel is uploaded/removed directly against the now-known course
      // id — a failure here never rolls back the course save itself (the
      // teacher can always retry from Edit), it only changes which message
      // is shown.
      final reelOk = await d.reelCtrl.commit(result.id);
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
          d.reelCtrl.error ?? 'course_reel_upload_failed'.tr,
          context.colors.danger,
        );
      }
      Navigator.pop(context, result);
    } else if (formProvider.lastApiError != null && appSharedFix(formProvider.lastApiError!) != null) {
      // e.g. 403 personal_off (UX v3 phase 3): one tap turns the personal account on, then saves again
      showAppError(context, formProvider.lastApiError!,
          text: formProvider.errorMessage,
          onRetry: () => _submit(publish: publish, listProvider: listProvider, formProvider: formProvider));
    } else if (formProvider.lastApiError?.code == 'course_area_required') {
      formProvider.markAreaMissing();
      _showSnack(courseAreaRequiredText(), context.colors.danger);
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
    final stored = (_draft.coverUrl ?? '').isNotEmpty;
    _draft.logoFile = null;
    _draft.logoBytes = null;
    _draft.touch();
    if (!stored || widget.course == null) return;
    final list = context.read<TeacherCoursesProvider>();
    try {
      final updated = await context.read<CourseFormProvider>().removeImage(widget.course!.id);
      list.onCourseUpdated(updated);
      if (mounted) {
        _draft.coverRemoved = true;
        _draft.touch();
      }
      showAppNotice('cover_removed'.tr);
    } catch (e) {
      showAppNotice(ApiException.from(e).message, error: true);
    }
  }

  // ── Edit-mode status toggle (publish / unpublish) ──────────────────────────

  Future<void> _toggleStatus({
    required TeacherCoursesProvider listProvider,
  }) async {
    if (_draft.statusLoading || widget.course == null) return;
    final target = !_draft.isPublished;
    _draft.statusLoading = true;
    _draft.touch();

    final ok = await (target
        ? listProvider.publishCourse(widget.course!.id)
        : listProvider.unpublishCourse(widget.course!.id));

    if (!mounted) return;
    _draft.statusLoading = false;
    _draft.touch();

    if (ok) {
      _draft.isPublished = target;
      _draft.touch();
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
    if (_draft.progressStatusLoading ||
        widget.course == null ||
        status == _draft.progressStatus) {
      return;
    }
    _draft.progressStatusLoading = true;
    _draft.touch();

    final formProvider = context.read<CourseFormProvider>();
    final result = await formProvider.updateStatus(widget.course!.id, status);

    if (!mounted) return;
    _draft.progressStatusLoading = false;
    _draft.touch();

    if (result != null) {
      _draft.progressStatus = status;
      _draft.touch();
      provider.onCourseUpdated(result);
      _showSnack('course_status_updated_success'.tr, context.colors.success);
    } else {
      _showSnack(
        formProvider.errorMessage ?? 'error_please_retry'.tr,
        context.colors.danger,
      );
    }
  }

  // ── Add a weekly appointment before the course is saved ────────────────────

  Future<void> _showAddAppointmentSheet() async {
    final formProvider = context.read<CourseFormProvider>();
    final existingDays = {
      ...formProvider.form.schedules.map((s) => s.day),
      ...formProvider.pendingSchedules.map((s) => s.day),
    };
    await showAppSheet<void>(
      context,
      (_) => LocalAddScheduleSheet(
        existingDays: existingDays,
        onAdd: (day, start, end) => formProvider.addPendingSchedule(
          PendingSchedule(day: day, startTime: start, endTime: end),
        ),
      ),
    );
  }

  /// [color] picks the notice's tone: the danger colour is an error notice, anything else a plain one.
  void _showSnack(String msg, Color color) {
    showAppNotice(msg, error: color == context.colors.danger);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TeacherCoursesProvider listProvider = context
        .read<TeacherCoursesProvider>();
    final provider = context.watch<CourseFormProvider>();
    final canSave = (_draft.hasChanges(provider) || provider.listsChanged) && _draft.hasBasics;

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
                      CfCoverSection(draft: _draft, onRemove: _removeCover),
                      // Basic info (always visible)
                      ParentComponent(
                          featureKey: 'course_form.basic_info',
                          child: CfFormCard(
                            icon: Icons.info_outline_rounded,
                            title: 'cf_basic_info'.tr,
                            children: [
                              CfBasicsFields(draft: _draft),
                              const SizedBox(height: AppSpace.md),
                              CfPricingFields(draft: _draft),
                            ],
                          )),
                      const SizedBox(height: AppSpace.md),

                      // Who it's for / Where (D-1314)
                      ParentComponent(
                          featureKey: 'course_form.audience',
                          child: CfFormCard(
                            icon: Icons.groups_2_outlined,
                            title: AppConfig.lang == 'ar' ? 'لمن هذا الكورس وأين' : "Who it's for / Where",
                            children: [CfAudienceFields(draft: _draft)],
                          )),
                      const SizedBox(height: AppSpace.md),

                      // edit mode: publish / progress status stay visible
                      if (_isEdit) ...[
                        ParentComponent(
                            featureKey: 'course_form.publish_status',
                            child: CfStatusCard(
                              isPublished: _draft.isPublished,
                              isLoading: _draft.statusLoading,
                              onToggle: () =>
                                  _toggleStatus(listProvider: listProvider),
                            )),
                        const SizedBox(height: AppSpace.md),
                        CourseProgressStatusCard(
                          status: _draft.progressStatus,
                          isLoading: _draft.progressStatusLoading,
                          onChanged: (s) =>
                              _changeProgressStatus(s, listProvider),
                        ),
                        const SizedBox(height: AppSpace.md),
                      ],

                      // ═══ ADVANCED — collapsed ════════════════════════════════════════
                      ParentComponent(
                          featureKey: 'course_form.advanced',
                          child: CfCollapsibleSection(
                            icon: Icons.tune_rounded,
                            title: 'cf_advanced'.tr,
                            subtitle: 'cf_advanced_sub'.tr,
                            expanded: _advancedOpen,
                            onToggle: () =>
                                setState(() => _advancedOpen = !_advancedOpen),
                            children: [
                              CfHoursDiscountFields(draft: _draft),
                              const SizedBox(height: AppSpace.sm),
                              CfPrivacyField(draft: _draft),
                              const SizedBox(height: AppSpace.md),
                              ParentComponent(
                                  featureKey: 'course_form.relations',
                                  child: CfFormCard(
                                    icon: Icons.route_rounded,
                                    title: 'course_relations_title'.tr,
                                    children: [CfRelationsFields(draft: _draft, onOpenPath: _openPathEditor)],
                                  )),
                              const SizedBox(height: AppSpace.md),
                              // Appointments (both modes). Existing, already-saved
                              // appointments come from provider.form.schedules (edit
                              // mode) and are staged for removal on save, same as
                              // certificates/tools/prerequisites. Newly added ones
                              // aren't sent to the server until save is pressed.
                              CfScheduleSection(onAdd: _showAddAppointmentSheet),
                            ],
                          )),
                      const SizedBox(height: AppSpace.md),

                      // ═══ OPTIONAL — collapsed ═════════════════════════════════════════════
                      ParentComponent(
                          featureKey: 'course_form.optional',
                          child: CfCollapsibleSection(
                            icon: Icons.add_circle_outline_rounded,
                            title: 'cf_optional'.tr,
                            subtitle: 'cf_optional_sub'.tr,
                            expanded: _optionalOpen,
                            onToggle: () =>
                                setState(() => _optionalOpen = !_optionalOpen),
                            children: [CfExtrasFields(draft: _draft)],
                          )),
                      const SizedBox(height: AppSpace.lg),
                    ],
                  ),
                ),
              ),
            ),

            // ── Sticky footer ──────────────────────────────────────────────
            CfStickyFooter(
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
