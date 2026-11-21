// lib/features/teachers/teacher_onboarding.dart — the teacher's side of Learning Hub v2 (CONTRACT.md §1; D-1620,
// D-1621, D-1622): one flow for every subject.
//
//   TeacherHubPage          GET /me/teacher-profile (+ /me/packages once approved): the status card (none / draft /
//                           pending / rejected with the reason and "Fix and resubmit" / approved) and My packages
//   TeacherStatusCard       plain values (test/ui/teachers_layout_test.dart)
//   TeacherOnboardingWizard profile (name, gender, introduction, languages, years, photo) → subjects + qualifications →
//                           attachments (type, image / PDF, size shown, remove before approval) → review & submit.
//                           "Next" saves the draft (PUT, the whole object), so a document always has a profile to
//                           hang on; "Submit" saves, then POST …/submit.
//
// Kill switch `teacher_onboarding`: the hub shows that it is switched off and opens nothing.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/auth/auth_provider.dart' show MyAuthProvider;
import 'package:flutter_education_app/features/quran/quran_api.dart' show kQuranTabKey;
import 'package:flutter_education_app/features/quran/quran_teacher_hub.dart' show QuranTeacherHubPage;
import 'package:flutter_education_app/features/teachers/package_wizard.dart';
import 'package:flutter_education_app/features/teachers/teachers_api.dart';
import 'package:flutter_education_app/features/teachers/teachers_models.dart';
import 'package:flutter_education_app/features/teachers/teachers_parts.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

// ── the hub ──────────────────────────────────────────────────────────────────

class TeacherHubPage extends StatefulWidget {
  const TeacherHubPage({super.key, this.api, this.recurrenceSlot});

  final TeachersApi? api;

  /// The package wizard's schedule slot (the shared RecurrencePicker is wired at merge).
  final RecurrenceSlotBuilder? recurrenceSlot;

  @override
  State<TeacherHubPage> createState() => _TeacherHubPageState();
}

class _TeacherHubPageState extends State<TeacherHubPage> {
  late final TeachersApi _api = widget.api ?? TeachersApi();
  TeacherProfile? _profile;
  List<TeacherPackage>? _packages;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!teacherOnboardingOff()) unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await _api.myProfile();
      List<TeacherPackage>? pk;
      if (p.approved && !packagesOff()) {
        try {
          pk = await _api.myPackages();
        } catch (e) {
          showAppNotice(teachersErrorText(e), error: true);
        }
      }
      if (!mounted) return;
      setState(() {
        _profile = p;
        _packages = pk;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = teachersErrorText(e);
      });
    }
  }

  Future<void> _openWizard({TeacherStep? at}) async {
    final p = _profile ?? TeacherProfile.empty;
    // the account's name starts the "name students see" field of a new profile (D-1658); no provider (a test) = none
    String? account;
    try {
      account = context.read<MyAuthProvider>().currentUser?.name;
    } on ProviderNotFoundException {
      account = null;
    }
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      settings: const RouteSettings(name: '/teacher/onboarding'),
      builder: (_) => TeacherOnboardingWizard(initial: p, api: _api, startAt: at, accountName: account),
    ));
    if (changed == true && mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    Widget body;
    if (teacherOnboardingOff()) {
      body = Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: AppEmpty(
          icon: Icons.lock_outline_rounded,
          title: t('التسجيل كمعلم متوقف الآن', 'Teacher sign-up is switched off right now'),
          message: t('أوقفته إدارة المنصة مؤقتاً. عد لاحقاً.', 'The platform switched it off for now. Come back later.'),
          actionLabel: t('رجوع', 'Back'),
          onAction: () => Navigator.of(context).maybePop(),
        ),
      );
    } else if (p == null) {
      body = _loading ? const AppListSkeleton(items: 4) : AppErrorState(message: _error, onRetry: _load);
    } else {
      body = AppRefresh(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
          TeacherStatusCard(
            profile: p,
            onStart: () => _openWizard(),
            onFix: () => _openWizard(at: TeacherStep.profile),
          ),
          if (!packagesOff())
            AppSection(
              title: t('باقاتي', 'My packages'),
              subtitle: t('مجموعات جلسات بسعر ومقاعد وجدول.', 'Sets of sessions with a price, seats and a schedule.'),
              child: p.approved
                  ? MyPackagesSection(
                      api: _api,
                      packages: _packages ?? const [],
                      subjects: p.subjects,
                      recurrenceSlot: widget.recurrenceSlot,
                      onChanged: _load,
                    )
                  : AppBanner(
                      key: ValueKey('teacher.hub.packages_locked.${p.status}'),
                      icon: p.status == 'pending' ? Icons.hourglass_top_rounded : Icons.info_outline_rounded,
                      text: teacherPackagesLockedText(p.status),
                    ),
            ),
          // one way in (D-1665): the Quran record sheet and programs open from here, not from a second Profile entry
          ParentComponent(
            featureKey: kQuranTabKey,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpace.md),
              child: AppActionCard(
                key: const ValueKey('teacher.hub.quran'),
                icon: Icons.menu_book_rounded,
                title: t('القرآن: سجل التسميع والبرامج', 'Quran: record sheet and programs'),
                subtitle: t('سجّل تسميع طلابك وتابع برامج القرآن', "Log your students' recitation and follow your Quran programs"),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  settings: const RouteSettings(name: '/teacher/quran'),
                  builder: (_) => const QuranTeacherHubPage(),
                )),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
        ]),
      );
    }
    return BasePage(
      width: AppWidth.reading,
      appBar: ScreenAppBar(title: t('ملفي كمعلم', 'My teacher profile')),
      child: SafeArea(child: body),
    );
  }
}

/// Why the packages are not open yet, in the profile's own state (D-1659): a profile under review is not told to
/// send it again.
String teacherPackagesLockedText(String status) => switch (status) {
      'pending' => t('ملفك قيد المراجعة الآن. تُفتح باقاتك فور اعتماده، ونرسل لك إشعاراً.',
          'Your profile is under review now. Your packages open as soon as it is approved, and we will let you know.'),
      'rejected' => t('عدّل ملفك حسب ملاحظة المراجعة وأرسله من جديد: تُفتح الباقات بعد اعتماده.',
          'Change your profile as the review asks and send it again: packages open once it is approved.'),
      _ => t('تُفتح الباقات بعد اعتماد ملفك من المنصة: أكمل ملفك وأرسله للمراجعة أولاً.',
          'Packages open once the platform approves your profile: complete it and send it for review first.'),
    };

/// The profile's state and its one next step.
class TeacherStatusCard extends StatelessWidget {
  const TeacherStatusCard({super.key, required this.profile, this.onStart, this.onFix});

  final TeacherProfile profile;

  /// Start / continue / edit the profile.
  final VoidCallback? onStart;

  /// A rejected profile: "Fix and resubmit".
  final VoidCallback? onFix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = profile;
    final (String title, String line, String? action, VoidCallback? onTap) = switch (p.status) {
      'none' => (
          t('علّم على المنصة', 'Teach on the platform'),
          t('أنشئ ملفك: موادك ومؤهلاتك ومستنداتك. تراجعه المنصة ثم تفتح باقاتك للطلاب.',
              'Create your profile: your subjects, qualifications and documents. The platform reviews it, then your packages open to students.'),
          t('ابدأ ملفي', 'Start my profile'),
          onStart,
        ),
      'draft' => (
          t('ملفك مسودة', 'Your profile is a draft'),
          t('أكمل الخطوات وأرسله للمراجعة.', 'Finish the steps and send it for review.'),
          t('أكمل ملفي', 'Continue my profile'),
          onStart,
        ),
      'pending' => (
          t('ملفك قيد المراجعة', 'Your profile is under review'),
          p.submittedAt == null
              ? t('سنرسل لك إشعاراً عند انتهاء المراجعة.', 'We will notify you when the review ends.')
              : t('أُرسل في ${AppTime.date(p.submittedAt!)}. سنرسل لك إشعاراً عند انتهاء المراجعة.',
                  'Sent on ${AppTime.date(p.submittedAt!)}. We will notify you when the review ends.'),
          null,
          null,
        ),
      'rejected' => (
          t('ملفك يحتاج تعديلاً', 'Your profile needs changes'),
          t('عدّل ما طلبته المنصة ثم أعد الإرسال.', 'Change what the platform asked for, then send it again.'),
          t('عدّل وأعد الإرسال', 'Fix and resubmit'),
          onFix,
        ),
      _ => (
          t('ملفك معتمد', 'Your profile is approved'),
          t('يراك الطلاب في قائمة المعلمين. تعديل الجنس أو المواد أو المؤهلات يعيده للمراجعة.',
              'Students see you in the teachers list. Changing your gender, subjects or qualifications sends it back to review.'),
          t('عدّل ملفي', 'Edit my profile'),
          onStart,
        ),
    };
    return AppCard(
      key: ValueKey('teacher.status.${p.status}'),
      highlight: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          AppAvatar(name: p.name.isEmpty ? '?' : p.name, url: p.avatarUrl, size: AppTouch.min),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: c.textDark)),
          ),
          if (p.exists) ...[
            const SizedBox(width: AppSpace.xs),
            Flexible(child: AppStatusBadge(label: teacherStatusLabel(p.status), tone: teacherStatusTone(p.status), dense: true)),
          ],
        ]),
        const SizedBox(height: AppSpace.sm),
        Text(line, style: AppType.body(context).copyWith(color: c.textMedium)),
        if (p.rejected && (p.rejectionReason ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(
            key: const ValueKey('teacher.status.reason'),
            icon: Icons.feedback_outlined,
            color: c.danger,
            text: '${t('سبب المنصة', 'The platform\'s reason')}: ${p.rejectionReason!.trim()}',
          ),
        ],
        if (p.exists && p.subjects.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          TeacherSubjectBadges(subjects: p.subjects),
        ],
        if (action != null) ...[
          const SizedBox(height: AppSpace.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.primary(
              key: const ValueKey('teacher.status.action'),
              label: action,
              icon: p.rejected ? Icons.edit_rounded : Icons.arrow_forward_rounded,
              onPressed: onTap,
            ),
          ),
        ],
      ]),
    );
  }
}

// ── the wizard ───────────────────────────────────────────────────────────────

String teacherStepTitle(TeacherStep s) => switch (s) {
      TeacherStep.profile => t('الملف', 'Profile'),
      TeacherStep.subjects => t('المواد', 'Subjects'),
      TeacherStep.documents => t('المستندات', 'Documents'),
      TeacherStep.review => t('المراجعة', 'Review'),
    };

class TeacherOnboardingWizard extends StatefulWidget {
  const TeacherOnboardingWizard({super.key, required this.initial, this.api, this.startAt, this.accountName});

  final TeacherProfile initial;
  final TeachersApi? api;
  final TeacherStep? startAt;

  /// The account's name: the "name students see" starts with it while the profile has none.
  final String? accountName;

  @override
  State<TeacherOnboardingWizard> createState() => _TeacherOnboardingWizardState();
}

class _TeacherOnboardingWizardState extends State<TeacherOnboardingWizard> {
  late final TeachersApi _api = widget.api ?? TeachersApi();
  late TeacherProfile _saved = widget.initial;
  late final TeacherProfileDraft _d = TeacherProfileDraft.of(widget.initial)
    ..name = widget.initial.name.trim().isEmpty ? (widget.accountName ?? '').trim() : widget.initial.name;
  late List<TeacherDoc> _docs = [...widget.initial.documents];
  late TeacherStep _step = widget.startAt ?? TeacherStep.profile;
  late final _name = TextEditingController(text: _d.name);
  late final _bio = TextEditingController(text: _d.bio);
  late final _quals = TextEditingController(text: _d.qualifications);
  String _docType = 'ijazah';
  String? _error;
  bool _busy = false, _changed = false, _photoBusy = false;
  int? _deleting;

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _quals.dispose();
    super.dispose();
  }

  void _sync() {
    _d
      ..name = _name.text
      ..bio = _bio.text
      ..qualifications = _quals.text;
  }

  bool get _locked => _saved.pending;

  Future<bool> _saveDraft() async {
    _sync();
    try {
      final r = await _api.saveProfile(_d);
      _saved = r;
      if (r.documents.isNotEmpty || _docs.isEmpty) _docs = [...r.documents];
      _changed = true;
      return true;
    } catch (e) {
      if (mounted) setState(() => _error = teachersErrorText(e));
      return false;
    }
  }

  Future<void> _next() async {
    _sync();
    final e = teacherStepError(_step, _d, documents: _docs.length);
    if (e != null) {
      setState(() => _error = e);
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    final ok = _step == TeacherStep.documents ? true : await _saveDraft();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _step = TeacherStep.values[_step.index + 1];
    });
  }

  void _back() {
    _sync();
    if (_step.index == 0) {
      Navigator.of(context).pop(_changed);
      return;
    }
    setState(() {
      _error = null;
      _step = TeacherStep.values[_step.index - 1];
    });
  }

  void _goTo(int i) {
    _sync();
    // back freely; forward only past steps that pass
    if (i > _step.index) {
      for (var s = 0; s < i; s++) {
        final e = teacherStepError(TeacherStep.values[s], _d, documents: _docs.length);
        if (e != null) {
          setState(() {
            _step = TeacherStep.values[s];
            _error = e;
          });
          return;
        }
      }
    }
    setState(() {
      _error = null;
      _step = TeacherStep.values[i];
    });
  }

  Future<void> _submit() async {
    _sync();
    final bad = teacherFirstBadStep(_d, documents: _docs.length);
    if (bad != null) {
      setState(() {
        _step = bad;
        _error = teacherStepError(bad, _d, documents: _docs.length);
      });
      return;
    }
    if (_d.reReviewsAgainst(_saved)) {
      final ok = await appConfirm(context,
          message: t('تغيير الجنس أو المواد أو المؤهلات يعيد ملفك للمراجعة، فتختفي من قائمة المعلمين حتى يُعتمد من جديد. أتابع؟',
              'Changing your gender, subjects or qualifications sends your profile back to review, and you leave the teachers list until it is approved again. Go on?'),
          confirmLabel: t('أرسل للمراجعة', 'Send for review'));
      if (ok != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    if (!await _saveDraft()) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      // an approved profile that changed nothing review-worthy is simply saved
      if (!_saved.approved) _saved = await _api.submit();
      if (!mounted) return;
      showAppNotice(_saved.approved ? t('حُفظ ملفك', 'Your profile is saved') : t('أُرسل ملفك للمراجعة', 'Your profile was sent for review'));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = teachersErrorText(e);
        });
      }
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final f = await FilePicker.pickFile(type: FileType.image);
      if (f == null || !mounted) return;
      final raw = await f.readAsBytes();
      if (!mounted) return;
      final picked = await cropImageWithName(context, raw, f.name, shape: CropShape.circle);
      if (picked == null || !mounted) return;
      setState(() => _photoBusy = true);
      final url = await _api.uploadPhoto(picked.bytes, picked.name);
      if (!mounted) return;
      setState(() {
        _photoBusy = false;
        if (url != null) {
          _d.avatarUrl = url;
          _changed = true;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _photoBusy = false);
      showAppNotice(teachersErrorText(e), error: true);
    }
  }

  Future<void> _addDocument() async {
    try {
      final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: kTeacherDocExtensions);
      if (f == null || !mounted) return;
      final Uint8List bytes = await f.readAsBytes();
      final err = teacherDocPickError(f.name, bytes.length);
      if (err != null) {
        showAppNotice(err, error: true);
        return;
      }
      if (!mounted) return;
      setState(() => _busy = true);
      final doc = await _api.uploadDocument(docType: _docType, fileName: f.name, bytes: bytes);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _docs = [..._docs, doc];
        _changed = true;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      showAppNotice(teachersErrorText(e), error: true);
    }
  }

  Future<void> _removeDocument(TeacherDoc d) async {
    final ok = await appConfirm(context,
        message: t('حذف "${d.fileName}"؟', 'Remove "${d.fileName}"?'), danger: true, confirmLabel: t('حذف', 'Remove'));
    if (ok != true || !mounted) return;
    setState(() => _deleting = d.id);
    try {
      await _api.deleteDocument(d.id);
      if (!mounted) return;
      setState(() {
        _deleting = null;
        _docs = [for (final x in _docs) if (x.id != d.id) x];
        _changed = true;
      });
    } catch (e) {
      if (mounted) setState(() => _deleting = null);
      showAppNotice(teachersErrorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: BasePage(
        width: AppWidth.form,
        appBar: ScreenAppBar(title: _saved.exists ? t('ملفي كمعلم', 'My teacher profile') : t('ملف معلم جديد', 'New teacher profile')),
        child: SafeArea(
          child: TeacherWizardBody(
            step: _step,
            onStep: _goTo,
            locked: _locked,
            error: _error,
            busy: _busy,
            onBack: _back,
            onNext: _step == TeacherStep.review ? _submit : _next,
            nextLabel: _step == TeacherStep.review
                ? (_saved.approved ? t('احفظ', 'Save') : t('أرسل للمراجعة', 'Send for review'))
                : t('التالي', 'Next'),
            child: switch (_step) {
              TeacherStep.profile => _profileStep(context),
              TeacherStep.subjects => _subjectsStep(context),
              TeacherStep.documents => _documentsStep(context),
              TeacherStep.review => TeacherReviewSummary(
                  draft: (_d..name = _name.text..bio = _bio.text..qualifications = _quals.text),
                  documents: _docs,
                  onEdit: (s) => _goTo(s.index),
                ),
            },
          ),
        ),
      ),
    );
  }

  Widget _profileStep(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        AppAvatar(name: _name.text.isEmpty ? '?' : _name.text, url: _d.avatarUrl, size: AppTouch.primary + AppSpace.md),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(t('صورتك', 'Your photo'), style: AppType.label(context).copyWith(color: c.textDark)),
            const SizedBox(height: AppSpace.xxs),
            AppButton.secondary(
              key: const ValueKey('teacher.wizard.photo'),
              label: _d.avatarUrl == null ? t('أضف صورة', 'Add a photo') : t('غيّر الصورة', 'Change the photo'),
              icon: Icons.photo_camera_rounded,
              size: AppButtonSize.sm,
              busy: _photoBusy,
              onPressed: _locked ? null : _pickPhoto,
            ),
          ]),
        ),
      ]),
      const SizedBox(height: AppSpace.md),
      AppField(
        key: const ValueKey('teacher.wizard.name'),
        controller: _name,
        label: t('الاسم كما يراه الطلاب', 'Your name as students see it'),
        icon: Icons.person_rounded,
        required: true,
        maxLength: 120,
        enabled: !_locked,
      ),
      const SizedBox(height: AppSpace.sm),
      TeachersChoiceRow(
        label: t('أنا', 'I am'),
        required: true,
        keyPrefix: 'teacher.wizard.gender',
        values: kTeacherGenders,
        selected: (v) => _d.gender == v,
        labelOf: teacherGenderLabel,
        enabled: !_locked,
        onTap: (v) => setState(() => _d.gender = v),
      ),
      const SizedBox(height: AppSpace.md),
      AppField(
        key: const ValueKey('teacher.wizard.bio'),
        controller: _bio,
        label: t('نبذة عنك', 'About you'),
        hint: t('خبرتك وطريقتك في التدريس ولمن تناسب', 'Your experience, how you teach and who it suits'),
        maxLines: 5,
        maxLength: 4000,
        required: true,
        enabled: !_locked,
      ),
      const SizedBox(height: AppSpace.sm),
      TeachersChoiceRow(
        label: t('لغات التدريس', 'Teaching languages'),
        keyPrefix: 'teacher.wizard.lang',
        values: kTeacherLanguages,
        selected: _d.languages.contains,
        labelOf: teacherLanguageLabel,
        enabled: !_locked,
        onTap: (v) => setState(() => _d.languages = _d.languages.contains(v) ? [for (final x in _d.languages) if (x != v) x] : [..._d.languages, v]),
      ),
      const SizedBox(height: AppSpace.md),
      AppNumberField(
        key: const ValueKey('teacher.wizard.years'),
        initialValue: _d.yearsExperience,
        label: t('سنوات الخبرة', 'Years of experience'),
        min: 0,
        max: 70,
        enabled: !_locked,
        onChanged: (v) => _d.yearsExperience = (v ?? 0).toInt(),
      ),
    ]);
  }

  Widget _subjectsStep(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        TeachersChoiceRow(
          label: t('ما المواد التي تدرّسها؟', 'Which subjects do you teach?'),
          required: true,
          keyPrefix: 'teacher.wizard.subject',
          values: kTeacherSubjects,
          selected: _d.subjects.contains,
          labelOf: teacherSubjectLabel,
          enabled: !_locked,
          helper: _saved.approved ? t('تغيير المواد يعيد ملفك للمراجعة', 'Changing the subjects sends your profile back to review') : null,
          onTap: (v) => setState(() => _d.subjects = _d.subjects.contains(v) ? [for (final x in _d.subjects) if (x != v) x] : [..._d.subjects, v]),
        ),
        const SizedBox(height: AppSpace.md),
        TeachersChoiceRow(
          label: t('نوع الجلسات', 'Session types'),
          keyPrefix: 'teacher.wizard.session',
          values: kTeacherSessionTypes,
          selected: _d.sessionTypes.contains,
          labelOf: teacherSessionTypeLabel,
          enabled: !_locked,
          onTap: (v) => setState(() => _d.sessionTypes = _d.sessionTypes.contains(v) ? [for (final x in _d.sessionTypes) if (x != v) x] : [..._d.sessionTypes, v]),
        ),
        const SizedBox(height: AppSpace.md),
        TeachersChoiceRow(
          label: t('أين تدرّس؟', 'Where do you teach?'),
          keyPrefix: 'teacher.wizard.delivery',
          values: kTeacherDeliveryModes,
          selected: _d.delivery.contains,
          labelOf: packageDeliveryLabel,
          enabled: !_locked,
          onTap: (v) => setState(() => _d.delivery = _d.delivery.contains(v) ? [for (final x in _d.delivery) if (x != v) x] : [..._d.delivery, v]),
        ),
        const SizedBox(height: AppSpace.md),
        AppField(
          key: const ValueKey('teacher.wizard.quals'),
          controller: _quals,
          label: t('المؤهلات', 'Qualifications'),
          hint: t('الإجازات والشهادات والدراسة، سطر لكل واحدة', 'Ijazahs, certificates and study, one per line'),
          maxLines: 5,
          maxLength: 2000,
          enabled: !_locked,
        ),
      ]);

  Widget _documentsStep(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(t('أرفق ما يثبت مؤهلاتك: صورة أو PDF حتى 10 ميجابايت لكل ملف. تراها إدارة المنصة فقط.',
              'Attach proof of your qualifications: an image or a PDF up to 10 MB each. Only the platform\'s reviewers see them.'),
          style: AppType.body(context).copyWith(color: c.textMedium)),
      const SizedBox(height: AppSpace.md),
      if (!_locked) ...[
        AppDropdown<String>(
          key: const ValueKey('teacher.wizard.doctype'),
          decoration: InputDecoration(labelText: t('نوع المستند', 'Document type')),
          value: _docType,
          items: [for (final d in kTeacherDocTypes) DropdownMenuItem(value: d, child: Text(teacherDocTypeLabel(d), overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _docType = v ?? 'other'),
        ),
        const SizedBox(height: AppSpace.sm),
        AppButton.secondary(
          key: const ValueKey('teacher.wizard.adddoc'),
          label: t('اختر ملفاً', 'Choose a file'),
          icon: Icons.upload_file_rounded,
          busy: _busy,
          onPressed: _busy ? null : _addDocument,
        ),
        const SizedBox(height: AppSpace.md),
      ],
      if (_docs.isEmpty)
        AppEmpty(
          icon: Icons.description_outlined,
          title: t('لا مستندات بعد', 'No documents yet'),
          message: t('أضف إجازتك أو شهادتك لتُراجع.', 'Add your ijazah or certificate to be reviewed.'),
          actionLabel: _locked ? null : t('اختر ملفاً', 'Choose a file'),
          onAction: _locked ? null : _addDocument,
        )
      else
        for (final d in _docs) ...[
          TeacherDocRow(
            doc: d,
            busy: _deleting == d.id,
            onRemove: !_locked && _saved.docsEditable && d.status != 'approved' ? () => _removeDocument(d) : null,
          ),
          const SizedBox(height: AppSpace.xs),
        ],
    ]);
  }
}

/// The wizard's frame: the step tabs, the body, the error and Back / Next (plain values; the layout test draws it).
class TeacherWizardBody extends StatelessWidget {
  const TeacherWizardBody({
    super.key,
    required this.step,
    required this.onStep,
    required this.child,
    required this.onBack,
    required this.onNext,
    required this.nextLabel,
    this.error,
    this.busy = false,
    this.locked = false,
  });

  final TeacherStep step;
  final ValueChanged<int> onStep;
  final Widget child;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final String nextLabel;
  final String? error;
  final bool busy, locked;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
      AppTabs(
        key: const ValueKey('teacher.wizard.steps'),
        items: [for (final s in TeacherStep.values) AppTabItem(teacherStepTitle(s))],
        index: step.index,
        onChanged: onStep,
      ),
      const SizedBox(height: AppSpace.xs),
      Text(t('الخطوة ${step.index + 1} من ${TeacherStep.values.length}', 'Step ${step.index + 1} of ${TeacherStep.values.length}'),
          style: AppType.meta(context).copyWith(color: c.textMedium)),
      if (locked) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(
          icon: Icons.hourglass_top_rounded,
          color: c.warning,
          text: t('ملفك قيد المراجعة: تراه هنا ولا يتغير حتى تنتهي.', 'Your profile is under review: you can see it here, and it cannot change until the review ends.'),
        ),
      ],
      const SizedBox(height: AppSpace.md),
      AppCard(child: child),
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(key: const ValueKey('teacher.wizard.error'), icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.md),
      AppButtonRow(
        primary: AppButton.primary(
          key: const ValueKey('teacher.wizard.next'),
          label: nextLabel,
          icon: step == TeacherStep.review ? Icons.send_rounded : Icons.arrow_forward_rounded,
          busy: busy,
          onPressed: busy || locked ? null : onNext,
        ),
        secondary: [
          AppButton.ghost(
            key: const ValueKey('teacher.wizard.back'),
            label: step.index == 0 ? t('إغلاق', 'Close') : t('السابق', 'Back'),
            onPressed: busy ? null : onBack,
          ),
        ],
      ),
      const SizedBox(height: AppSpace.lg),
    ]);
  }
}

/// One attached document: its type, name and size, its review state and Remove (until approval).
class TeacherDocRow extends StatelessWidget {
  const TeacherDocRow({super.key, required this.doc, this.onRemove, this.onOpen, this.busy = false});

  final TeacherDoc doc;
  final VoidCallback? onRemove;
  final VoidCallback? onOpen;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = doc;
    final meta = [teacherDocTypeLabel(d.docType), if ((d.size ?? 0) > 0) fileSizeLabel(d.size)].join(' · ');
    return Semantics(
      container: true,
      child: AppCard(
        key: ValueKey('teacher.doc.${d.id}'),
        onTap: onOpen,
        child: Row(children: [
          Icon(d.isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded, color: c.primary, size: AppIconSize.lg),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(d.fileName.isEmpty ? teacherDocTypeLabel(d.docType) : d.fileName,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.textDark)),
              const SizedBox(height: AppSpace.xxs),
              Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
              if (d.status == 'rejected' && (d.rejectionReason ?? '').isNotEmpty) ...[
                const SizedBox(height: AppSpace.xxs),
                Text(d.rejectionReason!, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.danger)),
              ],
            ]),
          ),
          const SizedBox(width: AppSpace.xs),
          Flexible(child: AppStatusBadge(label: teacherStatusLabel(d.status), tone: teacherStatusTone(d.status), dense: true)),
          if (onRemove != null)
            busy
                ? const SizedBox(width: AppTouch.min, height: AppTouch.min, child: Center(child: SizedBox.square(dimension: AppIconSize.md, child: CircularProgressIndicator(strokeWidth: 2))))
                : AppIconButton(
                    key: ValueKey('teacher.doc.remove.${d.id}'),
                    icon: Icons.delete_outline_rounded,
                    tooltip: t('حذف ${d.fileName}', 'Remove ${d.fileName}'),
                    onPressed: onRemove,
                  ),
        ]),
      ),
    );
  }
}

/// The review step: everything the profile says, each part with Edit, and what still blocks submitting.
class TeacherReviewSummary extends StatelessWidget {
  const TeacherReviewSummary({super.key, required this.draft, required this.documents, required this.onEdit});

  final TeacherProfileDraft draft;
  final List<TeacherDoc> documents;
  final ValueChanged<TeacherStep> onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = draft;
    final bad = teacherFirstBadStep(d, documents: documents.length);
    Widget part(TeacherStep s, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: Text(teacherStepTitle(s), style: AppType.section(context).copyWith(color: c.textDark))),
              AppButton.ghost(
                key: ValueKey('teacher.review.edit.${s.name}'),
                label: t('تعديل', 'Edit'),
                size: AppButtonSize.sm,
                onPressed: () => onEdit(s),
              ),
            ]),
            ...children,
          ]),
        );
    String or(String v) => v.trim().isEmpty ? '—' : v.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (bad != null) ...[
        AppBanner(
          icon: Icons.error_outline_rounded,
          color: c.warning,
          text: '${teacherStepTitle(bad)}: ${teacherStepError(bad, d, documents: documents.length)}',
          action: AppButton.tonal(label: t('أصلح', 'Fix'), size: AppButtonSize.sm, onPressed: () => onEdit(bad)),
        ),
        const SizedBox(height: AppSpace.md),
      ],
      part(TeacherStep.profile, [
        AppInfoRow(Icons.person_rounded, '${or(d.name)} · ${teacherGenderLabel(d.gender)}'),
        AppInfoRow(Icons.translate_rounded, d.languages.isEmpty ? '—' : teachersJoin(d.languages.map(teacherLanguageLabel))),
        AppInfoRow(Icons.workspace_premium_rounded, yearsText(d.yearsExperience)),
        const SizedBox(height: AppSpace.xxs),
        Text(or(d.bio), maxLines: 6, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: c.textMedium)),
      ]),
      part(TeacherStep.subjects, [
        if (d.subjects.isEmpty) Text('—', style: AppType.body(context).copyWith(color: c.textMedium)) else TeacherSubjectBadges(subjects: d.subjects),
        const SizedBox(height: AppSpace.xs),
        Text(or(d.qualifications), maxLines: 6, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: c.textMedium)),
        // what step 2 also asked: how and where the sessions are held
        if (d.sessionTypes.isNotEmpty || d.delivery.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          AppInfoRow(Icons.groups_rounded,
              [...d.sessionTypes.map(teacherSessionTypeLabel), ...d.delivery.map(packageDeliveryLabel)].join(' · ')),
        ],
      ]),
      part(TeacherStep.documents, [
        if (documents.isEmpty)
          Text(t('لا مستندات', 'No documents'), style: AppType.body(context).copyWith(color: c.textMedium))
        else
          for (final doc in documents) AppInfoRow(doc.isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded, '${teacherDocTypeLabel(doc.docType)} · ${doc.fileName}'),
      ]),
    ]);
  }
}
