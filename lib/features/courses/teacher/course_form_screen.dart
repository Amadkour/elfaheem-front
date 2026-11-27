import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_errors.dart' show appSharedFix, showAppError;
import 'package:flutter_education_app/design/app_kit.dart' show AppButton, AppHeader, AppHero, showAppSheet;
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_tokens.dart' show AppWidth;
import 'package:flutter_education_app/features/courses/course_setup_views.dart' show courseAreaRequiredText;
import 'package:flutter_education_app/features/courses/roadmap/roadmap_api.dart' show RoadmapApi, kRoadmapPathKey, roadmapOff;
import 'package:flutter_education_app/features/courses/roadmap/roadmap_editor.dart' show showRoadmapEditor;
import 'package:flutter_education_app/features/courses/roadmap/roadmap_tab.dart' show roadmapAllowedHere;
import 'package:flutter_education_app/features/courses/teacher/course_form_provider.dart';
import 'package:flutter_education_app/features/courses/teacher/teacher_courses_provider.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/course_form_draft.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/step_panels.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/wizard_kit.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/wizard_steps.dart';
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart';
import 'package:flutter_education_app/features/courses/teacher/wizard/weekly_slot_sheet.dart';
import 'package:flutter_education_app/features/help/help_info_button.dart' show HelpInfoButton;
import 'package:flutter_education_app/features/home/student/models.dart' show CourseStatus;
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
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
  CourseWizardStep _step = CourseWizardStep.basics;

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
    // one rule per step (title, discount, area, code); the form shows the first step that stops the save
    final issue = wizardFirstIssue(_draft, formProvider);
    if (issue != null) {
      if (issue == CourseWizardStep.audience) formProvider.markAreaMissing();
      final text = wizardStepIssue(issue, _draft, formProvider)!;
      setState(() => _step = issue);
      WidgetsBinding.instance.addPostFrameCallback((_) => _formKey.currentState?.validate());
      _showSnack(text, context.colors.danger);
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
  // ── Weekly slots: added before the course is saved, staged until Save ─────

  /// [editIndex]: the slot being changed (a saved one is removed and added again with the new values).
  Future<void> _openSlotSheet({int? editIndex}) async {
    final formProvider = context.read<CourseFormProvider>();
    final all = wizardSlots(formProvider);
    final initial = editIndex == null ? null : all[editIndex];
    await showAppSheet<void>(
      context,
      (_) => LocalAddScheduleSheet(
        existing: [for (var i = 0; i < all.length; i++) if (i != editIndex) all[i]],
        initial: initial,
        onAdd: (day, start, end) {
          if (editIndex != null) _deleteSlot(editIndex);
          formProvider.addPendingSchedule(PendingSchedule(day: day, startTime: start, endTime: end));
        },
      ),
    );
  }

  void _deleteSlot(int i) {
    final p = context.read<CourseFormProvider>();
    final existingCount = p.form.schedules.length;
    if (i < existingCount) {
      p.removeFormSchedule(i);
    } else {
      p.removePendingSchedule(i - existingCount);
    }
  }

  /// [color] picks the notice's tone: the danger colour is an error notice, anything else a plain one.
  void _showSnack(String msg, Color color) {
    showAppNotice(msg, error: color == context.colors.danger);
  }


  // ── Moving between steps ───────────────────────────────────────────────────

  /// The step's fields and rule: shows the field errors on the visible step.
  bool _stepOk(CourseWizardStep s) {
    final p = context.read<CourseFormProvider>();
    final fieldsOk = s != _step || (_formKey.currentState?.validate() ?? true);
    final issue = wizardStepIssue(s, _draft, p);
    if (issue != null) {
      if (s == CourseWizardStep.audience) p.markAreaMissing();
      if (s != _step || fieldsOk) _showSnack(issue, context.colors.danger);
    }
    return fieldsOk && issue == null;
  }

  void _setStep(CourseWizardStep s) => setState(() => _step = s);

  /// A tap on a step or an "Edit" of the review: any step when editing a course; when creating, backwards freely and
  /// forwards through the steps in between (each must pass).
  void _goTo(CourseWizardStep target) {
    if (target == _step) return;
    if (_isEdit || target.index < _step.index) return _setStep(target);
    for (var i = _step.index; i < target.index; i++) {
      final s = CourseWizardStep.values[i];
      if (!_stepOk(s)) return _setStep(s);
    }
    _setStep(target);
  }

  void _next() {
    if (_step.index + 1 >= CourseWizardStep.values.length) return;
    if (_stepOk(_step)) _setStep(CourseWizardStep.values[_step.index + 1]);
  }

  void _back() {
    if (_step.index > 0) _setStep(CourseWizardStep.values[_step.index - 1]);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TeacherCoursesProvider listProvider = context.read<TeacherCoursesProvider>();
    final provider = context.watch<CourseFormProvider>();
    final canSave = (_draft.hasChanges(provider) || provider.listsChanged) && _draft.hasBasics;
    final last = _step == CourseWizardStep.review;
    final busy = provider.isLoading;
    final ready = canSave && !busy;

    void save({bool publish = true}) => _submit(publish: publish, listProvider: listProvider, formProvider: provider);

    final actions = WizardActions(
      removeCover: _removeCover,
      openPath: _openPathEditor,
      goTo: _goTo,
      toggleStatus: () => _toggleStatus(listProvider: listProvider),
      changeProgress: (s) => _changeProgressStatus(s, listProvider),
      addSlot: () => _openSlotSheet(),
      editSlot: (i) => _openSlotSheet(editIndex: i),
      deleteSlot: _deleteSlot,
    );

    final hero = AppHero(
      kicker: '${'t1_wz_crumb_courses'.tr}  ›  ${_isEdit ? 'edit_course_title'.tr : 't1_wz_new'.tr}',
      title: _isEdit ? 't1_wz_hero_edit'.tr : 't1_wz_hero_new'.tr,
      subtitle: _isEdit ? 't1_wz_hero_sub_edit'.tr : 't1_wz_hero_sub'.tr,
      bottom: WzBand(step: _step),
    );

    final Widget primary = last
        ? AppButton.primary(
            key: const ValueKey('wizard.publish'),
            label: canSave
                ? (_isEdit ? 'btn_save_edits'.tr : 'publish_course_btn'.tr)
                : (_isEdit ? 'no_changes_to_save'.tr : 'enter_course_title_first'.tr),
            icon: Icons.public_rounded,
            expand: true,
            busy: busy,
            onPressed: ready ? () => save() : null,
          )
        : AppButton.primary(
            key: const ValueKey('wizard.next'),
            label: 't1_wz_next'.tr,
            icon: Icons.arrow_forward_rounded,
            expand: true,
            onPressed: _next,
          );

    // the header holds the one save that is always there: a draft while creating, the edits while editing
    final headerSave = IconButton(
      key: ValueKey(_isEdit ? 'wizard.save_edits' : 'wizard.save_draft'),
      tooltip: _isEdit ? 'btn_save_edits'.tr : 'save_as_draft_btn'.tr,
      icon: Icon(_isEdit ? Icons.save_outlined : Icons.bookmark_border_rounded),
      onPressed: ready ? () => save(publish: _isEdit) : null,
    );

    return T2Scope(
      child: BasePage(
        key: const ValueKey('course_form'),
        enableFooterWidget: false,
        appBar: AppHeader(
          title: _isEdit ? 'edit_course_title'.tr : 't1_wz_new'.tr,
          actions: [headerSave, const HelpInfoButton(pageId: 'teacher.course_editor')],
        ),
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(children: [
            Expanded(
              child: Form(
                key: _formKey,
                child: T2HeroScroll(
                  // a new step opens at its top
                  key: ValueKey(_step),
                  hero: hero,
                  width: AppWidth.content,
                  children: [
                    if (_isEdit)
                      T2Steps(
                        key: const ValueKey('wizard.steps'),
                        labels: [for (final s in CourseWizardStep.values) s.label],
                        index: _step.index,
                        onTap: (i) => _goTo(CourseWizardStep.values[i]),
                      ),
                    WizardStepBody(step: _step, draft: _draft, actions: actions),
                  ],
                ),
              ),
            ),
            WzBar(
              primary: primary,
              secondary: [
                if (_step.index > 0)
                  AppButton.secondary(key: const ValueKey('wizard.back'), label: 't1_wz_back'.tr, icon: Icons.arrow_back_rounded, onPressed: _back),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}
