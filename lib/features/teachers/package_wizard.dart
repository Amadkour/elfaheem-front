// lib/features/teachers/package_wizard.dart — an approved teacher's packages (CONTRACT.md §2 + Corrections v2 C3;
// D-1625 .. D-1628).
//
//   PackageWizardPage    three steps with sensible defaults: Basics (subject, title, description, goal, level,
//                        delivery + location) → Schedule (sessions, minutes, start date, the recurrence slot) → Price
//                        & seats (price, currency, discount, max students, overbooking none / allow (+ a limit,
//                        blank = none) / waiting list); the live summary beside the form on wide windows, under it
//                        on phones. Save = POST /packages (a draft) or PUT /packages/{id} (the whole object);
//                        "Save and publish" adds POST /packages/{id}/status {published}. Once anyone joined, the
//                        sessions, schedule and start date are read only (the server's `package_locked`).
//   PackageWizardForm    the plain-values form (test/ui/teachers_layout_test.dart)
//   MyPackagesSection    the teacher's list: Edit, Duplicate, Publish / Pause / Resume, Close, Roster
//
// The recurrence slot: [RecurrenceSlotBuilder], by default the shared RecurrencePicker (D-1570). A test can pass
// [packageRecurrencePlaceholder], which edits nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;
import 'package:flutter_education_app/features/calendar/recurrence/recurrence_picker.dart' show RecurrencePicker;
import 'package:flutter_education_app/features/calendar/recurrence/recurrence_rule.dart' show RecurrenceRule;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/teachers/teachers_api.dart';
import 'package:flutter_education_app/features/teachers/teachers_models.dart';
import 'package:flutter_education_app/features/teachers/teachers_parts.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart';

/// The package's repeat rule after the start date changes to [day] (D-1642): the series follows the rule's
/// `start_date`, so the two must agree. No rule (or an unreadable one) → [schedule] unchanged.
Map<String, dynamic>? packageScheduleStartingOn(Map<String, dynamic>? schedule, DateTime day) =>
    RecurrenceRule.fromJson(schedule)?.startingOn(day).toJson() ?? schedule;

/// The package's repeat rule kept in step with its numbers (D-1647): it ends after [sessionsCount] dates (the
/// server sets `count` the same way, contract C6), and each date lasts [sessionMinutes] from its start time, so a
/// changed length moves the end. An any-time rule keeps no clock. No rule (or an unreadable one) → unchanged.
Map<String, dynamic>? packageScheduleSynced(Map<String, dynamic>? schedule, {required int sessionsCount, required int sessionMinutes}) {
  final r = RecurrenceRule.fromJson(schedule);
  if (r == null) return schedule;
  final start = r.startTime;
  final timed = !r.allDay && start != null && sessionMinutes > 0;
  return r
      .copyWith(
        count: sessionsCount > 0 ? sessionsCount : null,
        clearCount: sessionsCount <= 0,
        clearEnd: true,
        endTime: timed ? (start + sessionMinutes) % 1440 : null,
      )
      .toJson();
}

/// How far a locked field fades (the disabled buttons' look, as the Repeat section's).
const double kPackageLockedOpacity = 0.45;

/// The schedule step's recurrence editor: (context, the rule or null, set it).
typedef RecurrenceSlotBuilder = Widget Function(
    BuildContext context, Map<String, dynamic>? rule, ValueChanged<Map<String, dynamic>?> onChanged);

/// The default slot: says what happens and edits nothing.
Widget packageRecurrencePlaceholder(BuildContext context, Map<String, dynamic>? rule, ValueChanged<Map<String, dynamic>?> onChanged) {
  final c = context.colors;
  return AppCard(
    key: const ValueKey('package.recurrence.placeholder'),
    child: Row(children: [
      Icon(Icons.event_repeat_rounded, color: c.textMedium, size: AppIconSize.lg),
      const SizedBox(width: AppSpace.sm),
      Expanded(
        child: Text(
          rule == null
              ? t('التكرار الأسبوعي يُضبط قريباً من هنا. حتى ذلك الحين تتفق على المواعيد مع طلابك.',
                  'A weekly repeat is set here soon. Until then you agree the times with your students.')
              : t('للباقة جدول محفوظ.', 'The package has a saved schedule.'),
          style: AppType.body(context).copyWith(color: c.textMedium),
        ),
      ),
    ]),
  );
}

String packageStepTitle(PackageStep s) => switch (s) {
      PackageStep.basics => t('الأساسيات', 'Basics'),
      PackageStep.schedule => t('الجدول', 'Schedule'),
      PackageStep.price => t('السعر والمقاعد', 'Price & seats'),
    };

class PackageWizardPage extends StatefulWidget {
  const PackageWizardPage({super.key, this.api, this.initial, this.subjects = const [], this.recurrenceSlot});

  final TeachersApi? api;

  /// null = a new package.
  final TeacherPackage? initial;

  /// The teacher's subjects (the first is the default; any subject may be picked).
  final List<String> subjects;
  final RecurrenceSlotBuilder? recurrenceSlot;

  @override
  State<PackageWizardPage> createState() => _PackageWizardPageState();
}

class _PackageWizardPageState extends State<PackageWizardPage> {
  late final TeachersApi _api = widget.api ?? TeachersApi();
  late final PackageDraft _d = widget.initial == null ? PackageDraft.defaults(subjects: widget.subjects) : PackageDraft.of(widget.initial!);
  bool _busy = false;
  String? _error;

  bool get _locked => (widget.initial?.seatsTaken ?? 0) > 0;

  Future<void> _save({required bool publish}) async {
    final errs = packageDraftErrors(_d, locked: _locked);
    if (errs.isNotEmpty) {
      setState(() => _error = errs.values.first);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var p = widget.initial == null ? await _api.createPackage(_d) : await _api.updatePackage(widget.initial!.id, _d);
      if (publish && p.status != 'published') p = await _api.setPackageStatus(p.id, 'published');
      if (!mounted) return;
      showAppNotice(publish ? t('نُشرت الباقة', 'The package is published') : t('حُفظت الباقة', 'The package is saved'));
      Navigator.of(context).pop(p);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = teachersErrorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return T2Scope(
      child: BasePage(
      appBar: AppHeader(title: widget.initial == null ? t('باقة جديدة', 'New package') : t('تعديل الباقة', 'Edit the package')),
      child: SafeArea(
        child: PackageWizardForm(
          draft: _d,
          locked: _locked,
          busy: _busy,
          error: _error,
          recurrenceSlot: widget.recurrenceSlot,
          published: widget.initial?.status == 'published',
          onSave: _save,
        ),
      ),
      ),
    );
  }
}

/// The wizard over a [PackageDraft] it edits in place.
class PackageWizardForm extends StatefulWidget {
  const PackageWizardForm({
    super.key,
    required this.draft,
    required this.onSave,
    this.locked = false,
    this.busy = false,
    this.error,
    this.recurrenceSlot,
    this.published = false,
    this.initialStep = PackageStep.basics,
    this.today,
  });

  final PackageDraft draft;
  final void Function({required bool publish}) onSave;
  final bool locked, busy, published;
  final String? error;
  final RecurrenceSlotBuilder? recurrenceSlot;
  final PackageStep initialStep;
  final DateTime? today;

  @override
  State<PackageWizardForm> createState() => _PackageWizardFormState();
}

class _PackageWizardFormState extends State<PackageWizardForm> {
  PackageDraft get _d => widget.draft;
  late PackageStep _step = widget.initialStep;
  Map<String, String> _errs = const {};
  late final _title = TextEditingController(text: _d.title);
  late final _desc = TextEditingController(text: _d.description);
  late final _goal = TextEditingController(text: _d.goal);
  late final _location = TextEditingController(text: _d.location);

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _goal.dispose();
    _location.dispose();
    super.dispose();
  }

  void _set(VoidCallback f) => setState(() {
        f();
        if (_errs.isNotEmpty) _errs = packageStepErrors(_step, _d, today: widget.today, locked: widget.locked);
      });

  void _goTo(int i) {
    if (i > _step.index) {
      for (var s = 0; s < i; s++) {
        final e = packageStepErrors(PackageStep.values[s], _d, today: widget.today, locked: widget.locked);
        if (e.isNotEmpty) {
          setState(() {
            _step = PackageStep.values[s];
            _errs = e;
          });
          return;
        }
      }
    }
    setState(() {
      _errs = const {};
      _step = PackageStep.values[i];
    });
  }

  void _save(bool publish) {
    final all = packageDraftErrors(_d, today: widget.today, locked: widget.locked);
    if (all.isNotEmpty) {
      for (final s in PackageStep.values) {
        final e = packageStepErrors(s, _d, today: widget.today, locked: widget.locked);
        if (e.isNotEmpty) {
          setState(() {
            _step = s;
            _errs = e;
          });
          return;
        }
      }
    }
    widget.onSave(publish: publish);
  }

  Future<void> _pickDate() async {
    final now = widget.today ?? DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final init = _d.startDate == null || _d.startDate!.isBefore(first) ? first : _d.startDate!;
    final picked = await showDatePicker(context: context, initialDate: init, firstDate: first, lastDate: DateTime(now.year + 2, 12, 31));
    if (picked != null && mounted) {
      _set(() {
        _d.startDate = picked;
        _d.schedule = packageScheduleStartingOn(_d.schedule, picked);
      });
    }
  }

  Widget _gap() => const SizedBox(height: AppSpace.md);

  Widget _basics(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppDropdown<String>(
          key: const ValueKey('package.subject'),
          decoration: InputDecoration(labelText: t('المادة', 'Subject'), errorText: _errs['subject']),
          value: _d.subject,
          items: [for (final s in kTeacherSubjects) DropdownMenuItem(value: s, child: Text(teacherSubjectLabel(s), overflow: TextOverflow.ellipsis))],
          onChanged: (v) => _set(() => _d.subject = v),
        ),
        _gap(),
        AppField(
          key: const ValueKey('package.title'),
          controller: _title,
          label: t('العنوان', 'Title'),
          hint: t('مثال: حفظ جزء عمّ في 8 أسابيع', 'e.g. Memorise Juz Amma in 8 weeks'),
          required: true,
          maxLength: 200,
          errorText: _errs['title'],
          onChanged: (v) => _set(() => _d.title = v),
        ),
        const SizedBox(height: AppSpace.sm),
        AppField(
          key: const ValueKey('package.description'),
          controller: _desc,
          label: t('الوصف', 'Description'),
          hint: t('ماذا يحدث في الجلسات ولمن تناسب', 'What happens in the sessions and who it suits'),
          maxLines: 4,
          maxLength: 4000,
          errorText: _errs['description'],
          onChanged: (v) => _set(() => _d.description = v),
        ),
        const SizedBox(height: AppSpace.sm),
        AppField(
          key: const ValueKey('package.goal'),
          controller: _goal,
          label: t('الهدف', 'Goal'),
          hint: t('ما سيصل إليه الطالب في النهاية', 'Where the student gets to by the end'),
          maxLength: 300,
          onChanged: (v) => _set(() => _d.goal = v),
        ),
        const SizedBox(height: AppSpace.sm),
        TeachersChoiceRow(
          label: t('المستوى', 'Level'),
          keyPrefix: 'package.level',
          values: kPackageLevels,
          selected: (v) => _d.level == v,
          labelOf: packageLevelLabel,
          onTap: (v) => _set(() => _d.level = v),
        ),
        _gap(),
        TeachersChoiceRow(
          label: t('طريقة الحضور', 'Delivery'),
          keyPrefix: 'package.delivery',
          values: kPackageDeliveries,
          selected: (v) => _d.delivery == v,
          labelOf: packageDeliveryLabel,
          onTap: (v) => _set(() => _d.delivery = v),
        ),
        if (_d.needsLocation) ...[
          _gap(),
          AppField(
            key: const ValueKey('package.location'),
            controller: _location,
            label: t('المكان', 'Location'),
            hint: t('المسجد أو المركز والحي', 'The mosque or centre and the area'),
            icon: Icons.place_rounded,
            required: true,
            maxLength: 300,
            errorText: _errs['location'],
            onChanged: (v) => _set(() => _d.location = v),
          ),
        ],
      ]);

  /// The shared Repeat section (D-1570). Its first date is the package's start date, and picking a first date in
  /// it moves the start date with it, so the two never disagree. The rule ends after `sessions_count` dates (the
  /// server's contract C6), so "Ends" reads "After 8 sessions", and a new rule's window is one session long
  /// (D-1647). Locked (someone joined): drawn disabled.
  Widget _pickerSlot(BuildContext context, Map<String, dynamic>? rule, ValueChanged<Map<String, dynamic>?> onChanged) {
    final s = _d.startDate ?? DateTime.now();
    final start = DateTime(s.year, s.month, s.day, 17);
    return RecurrencePicker(
      rule: RecurrenceRule.fromJson(rule),
      start: start,
      end: start.add(Duration(minutes: _d.sessionMinutes > 0 ? _d.sessionMinutes : 60)),
      fixedCount: _d.sessionsCount > 0 ? _d.sessionsCount : null,
      enabled: !widget.locked,
      label: t('التكرار', 'Repeat'),
      onChanged: (r) {
        if (r != null) _d.startDate = r.startDate;
        onChanged(r?.toJson());
      },
    );
  }

  /// The numbers changed: the rule follows them, unless it is locked (any schedule change is refused then).
  void _syncSchedule() {
    if (!widget.locked) {
      _d.schedule = packageScheduleSynced(_d.schedule, sessionsCount: _d.sessionsCount, sessionMinutes: _d.sessionMinutes);
    }
  }

  Widget _schedule(BuildContext context) {
    final c = context.colors;
    final slot = widget.recurrenceSlot ?? _pickerSlot;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (widget.locked) ...[
        AppBanner(
          icon: Icons.lock_outline_rounded,
          color: c.warning,
          text: t('انضم طلاب لهذه الباقة: عدد الجلسات والجدول وتاريخ البدء لا تتغير.',
              'Students have joined: the sessions, the schedule and the start date no longer change.'),
        ),
        _gap(),
      ],
      // locked: the numbers fade like the Repeat section below, matching the banner (QA S5)
      Opacity(
        opacity: widget.locked ? kPackageLockedOpacity : 1,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          AppNumberField(
            key: const ValueKey('package.sessions'),
            initialValue: _d.sessionsCount,
            label: t('عدد الجلسات', 'Number of sessions'),
            min: 1,
            max: 200,
            required: true,
            enabled: !widget.locked,
            helper: _errs['sessions_count'],
            onChanged: (v) => _set(() {
              _d.sessionsCount = (v ?? 0).toInt();
              _syncSchedule();
            }),
          ),
          _gap(),
          AppNumberField(
            key: const ValueKey('package.minutes'),
            initialValue: _d.sessionMinutes,
            label: t('مدة الجلسة بالدقائق', 'Minutes per session'),
            min: 15,
            max: 240,
            step: 15,
            required: true,
            enabled: !widget.locked,
            helper: _errs['session_minutes'],
            onChanged: (v) => _set(() {
              _d.sessionMinutes = (v ?? 0).toInt();
              _syncSchedule();
            }),
          ),
        ]),
      ),
      _gap(),
      AppFieldLabel(t('تاريخ البدء', 'Start date'), required: true),
      AppButton.secondary(
        key: const ValueKey('package.start'),
        label: _d.startDate == null ? t('اختر التاريخ', 'Choose the date') : packageDayLabel(_d.startDate!),
        icon: Icons.event_rounded,
        onPressed: widget.locked ? null : _pickDate,
      ),
      if (_errs['start_date'] != null) ...[
        const SizedBox(height: AppSpace.xxs),
        Text(_errs['start_date']!, style: AppType.meta(context).copyWith(color: c.danger)),
      ],
      _gap(),
      // the slot labels itself ("Repeat"): no second label here
      IgnorePointer(
        ignoring: widget.locked,
        child: slot(context, _d.schedule, (r) => _set(() => _d.schedule = r)),
      ),
    ]);
  }

  Widget _price(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppNumberField(
        key: const ValueKey('package.price'),
        initialValue: _d.price,
        label: t('السعر (0 = مجانية)', 'Price (0 = free)'),
        min: 0,
        max: 1000000,
        decimals: 2,
        helper: _errs['price'],
        onChanged: (v) => _set(() => _d.price = (v ?? 0).toDouble()),
      ),
      _gap(),
      AppDropdown<String>(
        key: const ValueKey('package.currency'),
        decoration: InputDecoration(labelText: t('العملة', 'Currency')),
        value: kPackageCurrencies.contains(_d.currency) ? _d.currency : kPackageCurrencies.first,
        items: [for (final cur in kPackageCurrencies) DropdownMenuItem(value: cur, child: Text(cur, overflow: TextOverflow.ellipsis))],
        onChanged: (v) => _set(() => _d.currency = v ?? 'EGP'),
      ),
      _gap(),
      AppNumberField(
        key: const ValueKey('package.discount'),
        initialValue: _d.discountPercent,
        label: t('الخصم ٪ (اختياري)', 'Discount % (optional)'),
        min: 0,
        max: 90,
        step: 5,
        helper: _errs['discount_percent'],
        onChanged: (v) => _set(() => _d.discountPercent = (v ?? 0).toInt()),
      ),
      _gap(),
      AppNumberField(
        key: const ValueKey('package.seats'),
        initialValue: _d.maxStudents,
        label: t('أقصى عدد للطلاب', 'Most students'),
        min: 1,
        max: 500,
        required: true,
        helper: _errs['max_students'],
        onChanged: (v) => _set(() => _d.maxStudents = (v ?? 0).toInt()),
      ),
      _gap(),
      AppFieldLabel(t('عند اكتمال المقاعد', 'When the seats are full')),
      for (final o in kPackageOverbook)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: AppCard(
            key: ValueKey('package.overbook.$o'),
            onTap: () => _set(() => _d.overbook = o),
            child: Row(children: [
              Icon(_d.overbook == o ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: _d.overbook == o ? c.primary : c.textLight, size: AppIconSize.md),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Semantics(
                  selected: _d.overbook == o,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(packageOverbookLabel(o), style: AppType.row(context).copyWith(color: c.textDark)),
                    Text(packageOverbookHelp(o), style: AppType.meta(context).copyWith(color: c.textMedium)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      if (_d.overbook == 'allow') ...[
        const SizedBox(height: AppSpace.xs),
        AppNumberField(
          key: const ValueKey('package.overbook_limit'),
          initialValue: _d.overbookLimit,
          label: t('مقاعد إضافية (فارغ = بلا حد)', 'Extra seats (blank = no limit)'),
          min: 1,
          max: 500,
          helper: _errs['overbook_limit'],
          onChanged: (v) => _set(() => _d.overbookLimit = v?.toInt()),
        ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final form = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppCard(
        child: switch (_step) {
          PackageStep.basics => _basics(context),
          PackageStep.schedule => _schedule(context),
          PackageStep.price => _price(context),
        },
      ),
      if (widget.error != null || _errs.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(
          key: const ValueKey('package.error'),
          icon: Icons.error_outline_rounded,
          color: c.danger,
          text: widget.error ?? _errs.values.first,
        ),
      ],
      const SizedBox(height: AppSpace.md),
      AppButtonRow(
        primary: _step == PackageStep.price
            ? AppButton.primary(
                key: const ValueKey('package.publish'),
                label: widget.published ? t('احفظ', 'Save') : t('احفظ وانشر', 'Save and publish'),
                icon: Icons.public_rounded,
                busy: widget.busy,
                onPressed: widget.busy ? null : () => _save(true),
              )
            : AppButton.primary(
                key: const ValueKey('package.next'),
                label: t('التالي', 'Next'),
                icon: Icons.arrow_forward_rounded,
                onPressed: () => _goTo(_step.index + 1),
              ),
        secondary: [
          if (!widget.published)
            AppButton.secondary(
              key: const ValueKey('package.save_draft'),
              label: t('احفظ كمسودة', 'Save as draft'),
              onPressed: widget.busy ? null : () => _save(false),
            ),
          if (_step.index > 0)
            AppButton.ghost(key: const ValueKey('package.back'), label: t('السابق', 'Back'), onPressed: () => _goTo(_step.index - 1)),
        ],
      ),
    ]);
    final steps = T2Steps(
      key: const ValueKey('package.steps'),
      labels: [for (final s in PackageStep.values) packageStepTitle(s)],
      index: _step.index,
      onTap: _goTo,
    );
    final hero = AppHero(
      title: switch (_step) {
        PackageStep.basics => t('وش الباقة؟', 'What is the package?'),
        PackageStep.schedule => t('متى الحصص؟', 'When are the classes?'),
        PackageStep.price => t('السعر والمقاعد', 'Price and seats'),
      },
      subtitle: t('الباقة مجموعة حصص بعدد وسعر ثابت، يحجزها الطالب من ملفك.',
          'A package is a set number of classes at a fixed price that students book from your profile.'),
    );
    return LayoutBuilder(builder: (context, box) {
      final summary = PackageSummaryCard(draft: _d);
      if (box.maxWidth >= Breakpoints.desktop) {
        return T2HeroScroll(hero: hero, width: AppWidth.content, children: [
          steps,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: form),
            const SizedBox(width: AppSpace.lg),
            Expanded(flex: 2, child: summary),
          ]),
        ]);
      }
      return T2HeroScroll(hero: hero, children: [steps, form, summary]);
    });
  }
}

// ── My packages ──────────────────────────────────────────────────────────────

class MyPackagesSection extends StatefulWidget {
  const MyPackagesSection({
    super.key,
    required this.packages,
    this.api,
    this.subjects = const [],
    this.recurrenceSlot,
    this.onChanged,
  });

  final List<TeacherPackage> packages;
  final TeachersApi? api;
  final List<String> subjects;
  final RecurrenceSlotBuilder? recurrenceSlot;
  final Future<void> Function()? onChanged;

  @override
  State<MyPackagesSection> createState() => _MyPackagesSectionState();
}

class _MyPackagesSectionState extends State<MyPackagesSection> {
  late final TeachersApi _api = widget.api ?? TeachersApi();
  int? _busy;

  Future<void> _open([TeacherPackage? p]) async {
    final r = await Navigator.of(context).push<TeacherPackage>(MaterialPageRoute(
      settings: RouteSettings(name: p == null ? '/teacher/packages/new' : '/teacher/packages/${p.id}'),
      builder: (_) => PackageWizardPage(api: _api, initial: p, subjects: widget.subjects, recurrenceSlot: widget.recurrenceSlot),
    ));
    if (r != null) await widget.onChanged?.call();
  }

  Future<void> _run(TeacherPackage p, Future<void> Function() fn, String done) async {
    setState(() => _busy = p.id);
    try {
      await fn();
      showAppNotice(done);
      await widget.onChanged?.call();
    } catch (e) {
      showAppNotice(teachersErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _close(TeacherPackage p) async {
    final ok = await appConfirm(context,
        message: t('إغلاق "${p.title}"؟ لا ينضم إليها أحد بعد ذلك، ويبقى المشتركون.',
            'Close "${p.title}"? Nobody can join after this; the students in it stay.'),
        danger: true,
        confirmLabel: t('أغلق', 'Close'));
    if (ok != true || !mounted) return;
    await _run(p, () => _api.setPackageStatus(p.id, 'closed'), t('أُغلقت الباقة', 'The package is closed'));
  }

  Future<void> _roster(TeacherPackage p) => showAppSheet<void>(
        context,
        (_) => AppSheetContent(
          title: p.title,
          icon: Icons.groups_rounded,
          children: [PackageRosterList(load: () => _api.roster(p.id))],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l = widget.packages;
    if (l.isEmpty) {
      return AppEmpty(
        icon: Icons.inventory_2_outlined,
        title: t('لا باقات بعد', 'No packages yet'),
        message: t('أنشئ باقتك الأولى: عدد جلسات بسعر ومقاعد.', 'Create your first package: a number of sessions with a price and seats.'),
        actionLabel: t('باقة جديدة', 'New package'),
        onAction: () => _open(),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: AppButton.primary(key: const ValueKey('package.new'), label: t('باقة جديدة', 'New package'), icon: Icons.add_rounded, onPressed: () => _open()),
      ),
      const SizedBox(height: AppSpace.sm),
      for (final p in l) ...[
        MyPackageCard(
          package: p,
          busy: _busy == p.id,
          onEdit: () => _open(p),
          onDuplicate: () => _run(p, () => _api.duplicatePackage(p.id), t('أُنشئت نسخة مسودة', 'A draft copy was made')),
          onStatus: (s) => _run(p, () => _api.setPackageStatus(p.id, s), packageStatusLabel(s)),
          onClose: () => _close(p),
          onRoster: () => _roster(p),
        ),
        const SizedBox(height: AppSpace.sm),
      ],
    ]);
  }
}

/// One of my packages with its actions (plain values).
class MyPackageCard extends StatelessWidget {
  const MyPackageCard({
    super.key,
    required this.package,
    this.busy = false,
    this.onEdit,
    this.onDuplicate,
    this.onStatus,
    this.onClose,
    this.onRoster,
  });

  final TeacherPackage package;
  final bool busy;
  final VoidCallback? onEdit, onDuplicate, onClose, onRoster;
  final ValueChanged<String>? onStatus;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = package;
    final closed = p.status == 'closed';
    final (String? next, String? nextLabel, IconData nextIcon) = switch (p.status) {
      'draft' => ('published', t('انشر', 'Publish'), Icons.public_rounded),
      'published' => ('paused', t('أوقف مؤقتاً', 'Pause'), Icons.pause_rounded),
      'paused' => ('published', t('استأنف', 'Resume'), Icons.play_arrow_rounded),
      _ => (null, null, Icons.block_rounded),
    };
    return AppCard(
      key: ValueKey('mypackage.${p.id}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        TitleWithStatus(
          title: UserText(block: false, p.title.isEmpty ? t('بلا عنوان', 'Untitled') : p.title,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: c.textDark)),
          status: AppStatusBadge(label: packageStatusLabel(p.status), tone: packageStatusTone(p.status), dense: true),
        ),
        const SizedBox(height: AppSpace.xxs),
        Text('${teacherSubjectLabel(p.subject)} · ${packageDeliveryLabel(p.delivery)} · ${sessionsText(p.sessionsCount)}',
            maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
        if (packageScheduleText(p.schedule, p.sessionsCount) case final sched?) ...[
          const SizedBox(height: AppSpace.xxs),
          AppInfoRow(Icons.event_repeat_rounded, sched),
        ],
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          PackagePriceText(price: p.price, finalPrice: p.finalPrice, currency: p.currency, discountPercent: p.discountPercent),
          Text(seatsTakenText(p.seatsTaken, p.maxStudents),
              style: AppType.meta(context).copyWith(color: c.textMedium)),
          if (p.waitlistCount > 0) Text(waitingText(p.waitlistCount), style: AppType.meta(context).copyWith(color: c.textMedium)),
        ]),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          if (!closed)
            AppButton.tonal(key: ValueKey('mypackage.edit.${p.id}'), label: t('تعديل', 'Edit'), icon: Icons.edit_rounded, size: AppButtonSize.sm, onPressed: busy ? null : onEdit),
          if (next != null)
            AppButton.secondary(
                key: ValueKey('mypackage.status.${p.id}'), label: nextLabel!, icon: nextIcon, size: AppButtonSize.sm, busy: busy, onPressed: busy ? null : () => onStatus?.call(next)),
          AppButton.ghost(
              key: ValueKey('mypackage.roster.${p.id}'), label: t('الطلاب', 'Roster'), icon: Icons.groups_rounded, size: AppButtonSize.sm, onPressed: onRoster),
          AppButton.ghost(
              key: ValueKey('mypackage.duplicate.${p.id}'), label: t('نسخ', 'Duplicate'), icon: Icons.copy_rounded, size: AppButtonSize.sm, onPressed: busy ? null : onDuplicate),
          if (!closed)
            AppButton.ghost(
                key: ValueKey('mypackage.close.${p.id}'), label: t('إغلاق', 'Close'), icon: Icons.block_rounded, size: AppButtonSize.sm, onPressed: busy ? null : onClose),
        ]),
      ]),
    );
  }
}

String packageEnrollmentStatusLabel(String s) => switch (s) {
      'active' => t('مشترك', 'Active'),
      'waitlisted' => t('في الانتظار', 'Waiting'),
      'pending_payment' => t('بانتظار الدفع', 'Waiting for payment'),
      'offered' => t('عُرض عليه مقعد', 'Offered a seat'),
      'expired' => t('انتهت المهلة', 'Expired'),
      'cancelled' => t('انسحب', 'Left'),
      _ => s,
    };

class PackageRosterList extends StatefulWidget {
  const PackageRosterList({super.key, required this.load});

  final Future<List<PackageRosterRow>> Function() load;

  @override
  State<PackageRosterList> createState() => _PackageRosterListState();
}

class _PackageRosterListState extends State<PackageRosterList> {
  late final Future<List<PackageRosterRow>> _f = widget.load();

  @override
  Widget build(BuildContext context) => FutureBuilder<List<PackageRosterRow>>(
        future: _f,
        builder: (context, s) {
          if (s.connectionState != ConnectionState.done) return const AppListSkeleton(items: 3, padding: EdgeInsets.zero);
          if (s.hasError) return AppErrorState(message: teachersErrorText(s.error!));
          final l = s.data ?? const [];
          if (l.isEmpty) {
            return AppEmpty(icon: Icons.groups_rounded, title: t('لم ينضم أحد بعد', 'Nobody has joined yet'));
          }
          final c = context.colors;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            for (final r in l)
              ListTile(
                key: ValueKey('roster.${r.studentId}'),
                minTileHeight: AppTouch.min,
                leading: AppAvatar(name: r.name.isEmpty ? '?' : r.name, url: r.avatarUrl, size: AppTouch.min - AppSpace.xs),
                title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.textDark)),
                trailing: AppStatusBadge(
                  label: r.status == 'waitlisted' && r.position != null ? '${packageEnrollmentStatusLabel(r.status)} · ${r.position}' : packageEnrollmentStatusLabel(r.status),
                  tone: r.status == 'active' ? AppTone.success : AppTone.neutral,
                  dense: true,
                ),
              ),
          ]);
        },
      );
}
