// lib/features/org/org_timetable_wizard.dart — building a timetable step by step.
//
//   A details & dates · B courses (or a new course right here) · C facilities · D days & periods · E sessions ·
//   F staff · G availability & preferences · H review & generate · I results · J save / publish
//
// The configuration lives on the server: the schedule scope is saved (PUT = full replacement) when leaving A, B, D
// and before generating; course needs, staff and preferences are saved by their own forms. Re-opening the wizard
// restores everything from the server. The algorithm is the server's — this screen never claims a result it didn't send.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_availability_pages.dart' show openAvailabilityRequests;
import 'org_page_header.dart' show OrgPageRefresh, OrgPushedPage, orgUsesDashboardHeader;
import 'org_common.dart' show dayLabels;
import 'org_courses_page.dart' show showOrgCourseForm;
import 'org_schedule_generate.dart' show GenerationLivePanel, showGenerationResult;
import 'org_schedule_ladder.dart' show LadderLive;
import 'org_schedule_ladder_ui.dart' show LadderLivePanel;
import 'org_providers.dart';
import 'org_schedule_pages.dart' show showAvailabilitySheet, showPeriodForm, showPublishConflicts, publishWithConsent;
import 'org_schedule_planning.dart' show applyStudentCount, coursePlanApi, termCourseIds;
import 'org_timetable_parts.dart';
import 'org_ui.dart';
import 'org_v3.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/design/context_switcher.dart' show ContextExitButton;
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

class TimetableWizard extends StatefulWidget {
  const TimetableWizard({super.key, this.scheduleId});
  final int? scheduleId;

  /// Opens the wizard over the studio; returns the schedule id when one was saved.
  static Future<int?> open(BuildContext context, OrgScheduleProvider p, {int? scheduleId}) => Navigator.of(context).push<int>(MaterialPageRoute(
      builder: (_) => MultiProvider(providers: [
            ChangeNotifierProvider.value(value: p),
            ChangeNotifierProvider.value(value: context.read<OrgSession>()),
          ], child: TimetableWizard(scheduleId: scheduleId))));

  @override
  State<TimetableWizard> createState() => _TimetableWizardState();
}

class _TimetableWizardState extends State<TimetableWizard> {
  ScheduleDraft? _d;
  String _saved = '';
  int _step = 0;
  bool _busy = false, _failed = false;
  String? _error;
  String _courseQuery = '';
  // generation options (sent with generate; the stored settings keep them too)
  bool _keepLocked = true;
  // org courses (GET /courses): term_id links a course to the term it is planned for; null = could not be read
  List<Map<String, dynamic>>? _orgCourses;
  // students to plan for, for every selected course: enrolled (subscribed) or a manual count — saved as course plans
  String _countMode = 'enrolled';
  int? _manualCount;
  bool _countDirty = false;

  OrgScheduleProvider get _p => context.read<OrgScheduleProvider>();

  List<(String, IconData)> get _steps => [
        (t('البيانات', 'Details'), Icons.edit_calendar_rounded),
        (t('المقررات', 'Courses'), Icons.menu_book_rounded),
        (t('الأماكن', 'Facilities'), Icons.meeting_room_rounded),
        (t('الأيام والفترات', 'Days & periods'), Icons.view_week_rounded),
        (t('الحصص', 'Sessions'), Icons.timer_rounded),
        (t('الهيئة', 'Staff'), Icons.groups_rounded),
        (t('التفضيلات', 'Preferences'), Icons.tune_rounded),
        (t('المراجعة والتوليد', 'Review & generate'), Icons.auto_awesome_rounded),
        (t('النتيجة', 'Results'), Icons.fact_check_rounded),
        (t('الحفظ والنشر', 'Save & publish'), Icons.publish_rounded),
      ];

  /// The dashboard header's Refresh (D-103): reloads a saved, unchanged timetable in place; it never throws away
  /// unsaved edits, a step in flight or a timetable created in this visit (it only says so).
  final _refresh = OrgPageRefresh();

  @override
  void initState() {
    super.initState();
    _refresh.attach(_refreshNow);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  Future<void> _refreshNow() async {
    final d = _d;
    if (d == null) return _load();
    if (_busy || (_dirty && !_locked)) {
      toast(t('احفظ تغييراتك أولاً — التحديث يعيد ما على الخادم.', 'Save your changes first — Refresh reloads what the server has.'));
      return;
    }
    if (widget.scheduleId == null || d.id != widget.scheduleId) return;
    await _load();
    if (mounted) _refresh.markUpdated();
  }

  Future<void> _load() async {
    final p = _p;
    if (!p.loaded) await p.loadSetup();
    final all = p.loads.map((l) => asInt(l['course_id']));
    unawaited(_loadOrgCourses());
    if (widget.scheduleId == null) {
      setState(() {
        _d = ScheduleDraft()..courseIds.addAll(all);
        _saved = '';
      });
      return;
    }
    final r = await orgCall(() => p.api.get('${p.base}/schedules/${widget.scheduleId}'));
    if (!mounted) return;
    if (!r.ok) return setState(() => _failed = true);
    final d = ScheduleDraft.fromJson(r.map, allCourses: all);
    await p.open(d.id!);          // results / conflicts / runs of this schedule
    await p.resumeRunIfAny();
    if (!mounted) return;
    setState(() {
      _d = d;
      _saved = jsonEncode(d.toBody());
    });
  }

  /// Every page of the org's courses (≤ 100 per page). A user without courses.view reads the term from GET /loads
  /// (`course.term_id`, servers since v3.4); without either the selection stays manual.
  Future<void> _loadOrgCourses() async {
    List<Map<String, dynamic>>? out = [];
    for (var page = 1; page <= 20; page++) {
      final r = await orgCall(() => _p.api.get('${_p.base}/courses', queryParams: {'size': 100, 'page': page}), quiet: true);
      if (!r.ok) {
        final fromLoads = [for (final l in _p.loads) {...asMap(l['course']), 'id': asInt(l['course_id'])}];
        out = fromLoads.any((c) => c.containsKey('term_id')) ? fromLoads : null;
        break;
      }
      out!.addAll(asMapList(r.map['items']));
      if (page >= asInt(r.map['pages'], 1)) break;
    }
    if (mounted && out != null) setState(() => _orgCourses = out);
    final id = _d?.id;
    if (id == null) return;
    // the count already chosen for this timetable: manual when every selected course has the same manual count
    final plans = (await coursePlanApi(_p).list(id)).items;
    final sel = [for (final c in _d!.courseIds) plans[c]];
    if (mounted && sel.isNotEmpty && sel.every((x) => x?.countSource == 'manual' && x?.expectedStudents == sel.first?.expectedStudents)) {
      setState(() {
        _countMode = 'manual';
        _manualCount = sel.first!.expectedStudents;
      });
    }
  }

  Set<int> _termCourses(int? termId) => termId == null || _orgCourses == null ? const {} : termCourseIds(_orgCourses!, termId).intersection({for (final l in _p.loads) asInt(l['course_id'])});

  /// Selects exactly the courses planned for the chosen term; returns false when the term has none (selection kept).
  bool _selectTermCourses(ScheduleDraft d) {
    final ids = _termCourses(d.termId);
    if (ids.isEmpty) return false;
    d.courseIds
      ..clear()
      ..addAll(ids);
    return true;
  }

  Future<bool> _saveStudentCount() async {
    final d = _d!;
    if (!_countDirty || _locked || d.id == null) return true;
    if (_countMode == 'manual' && (_manualCount == null || _manualCount! < 1)) {
      setState(() => _error = t('اكتب عدد الطلاب (1 أو أكثر)', 'Type the number of students (1 or more)'));
      return false;
    }
    setState(() => _busy = true);
    try {
      final api = coursePlanApi(_p);
      final existing = (await api.list(d.id!)).items;
      await api.saveAll(d.id!, applyStudentCount(existing, d.courseIds, source: _countMode, count: _manualCount));
      _countDirty = false;
      return true;
    } catch (e) {
      if (mounted) setState(() => _error = orgErrorText(ApiException.from(e)));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _dirty => _d != null && jsonEncode(_d!.toBody()) != _saved;
  bool get _locked => _d?.published == true;

  Future<bool> _persist() async {
    final d = _d!;
    if (_locked) return true;
    if (!_dirty && d.id != null) return true;
    final local = d.validate();
    if (local != null) {
      setState(() => _error = local);
      return false;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _p.saveDraft(d);
    if (!mounted) return false;
    setState(() {
      _busy = false;
      if (r.ok) {
        _saved = jsonEncode(d.toBody());
      } else {
        final ids = (r.detail['ids'] as List?)?.join('، ');
        _error = '${orgErrorText(r.error!)}${ids == null ? '' : ' ($ids)'}';
      }
    });
    return r.ok;
  }

  Future<void> _go(int to) async {
    if (to > _step && const {0, 1, 3}.contains(_step)) {
      if (_step == 0 && (_d!.name.trim().isEmpty)) return setState(() => _error = t('اكتب اسماً للجدول', 'Give the timetable a name'));
      // a new timetable is first saved when leaving the courses step — so courses can still be created there
      final firstSaveLater = _step == 0 && _d!.id == null;
      if (!firstSaveLater && !await _persist()) return;
      if (_step == 1 && !await _saveStudentCount()) return;
    }
    setState(() {
      _error = null;
      _step = to.clamp(0, _steps.length - 1);
    });
  }

  Future<void> _generate() async {
    if (!await _persist()) return;
    final p = _p;
    final d = _d!;
    setState(() => _busy = true);
    await p.open(d.id!);
    // the ladder run (D-013) when the server has it; the wizard's settings are already saved on the draft by _persist
    final ladder = await p.loadLadder(d.id!);
    final r = ladder != null ? await p.startLadder(d.id!, auto: false) : await p.startGeneration(settings: d.settings, keepLocked: _keepLocked, complete: true);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok || r.code == 'generation_running') {
        _step = 8;
        _error = null;
      } else {
        _error = orgErrorText(r.error!);
      }
    });
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty || _locked) return true;
    return confirm(context, message: t('لم تُحفظ بعض التغييرات. الخروج بدونها؟', 'Some changes are not saved. Leave without them?'), danger: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = _d;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.of(context).pop(_d?.id);
      },
      child: _frame(
        context,
        d,
        d == null
            ? OrgAsync(loading: !_failed, failed: _failed, onRetry: _load, child: const SizedBox.shrink())
            : Column(children: [
                SizedBox(
                  height: 56,
                  child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs), children: [
                    for (var i = 0; i < _steps.length; i++)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
                        child: ChoiceChip(
                          avatar: Icon(_steps[i].$2, size: AppIconSize.sm, color: i == _step ? c.onHero : c.textMedium),
                          label: Text('${i + 1}. ${_steps[i].$1}', style: TextStyle(fontFamily: AppFonts.family, color: i == _step ? c.onHero : c.textDark)),
                          selected: i == _step,
                          selectedColor: c.primary,
                          showCheckmark: false,
                          // jumping ahead needs a saved timetable
                          onSelected: _busy || (i > 0 && d.id == null) ? null : (_) => _go(i),
                        ),
                      ),
                  ]),
                ),
                if (_locked)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
                    child: RowCard(
                      accent: c.warning,
                      child: Text(t('هذا الجدول منشور — أوقف نشره من الاستوديو لتعديل إعداده. النسخة المنشورة لا تتغير.',
                          'This timetable is published — unpublish it in the studio to edit its setup. The published version stays as it is.')),
                    ),
                  ),
                Expanded(
                  child: ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg), children: [
                    Builder(builder: (context) => _body(context, d)),
                  ]),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.xs),
                    child: Text(_error!, style: AppType.label(context).copyWith(color: c.danger)),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.sm),
                  child: Row(children: [
                    if (_step > 0)
                      OutlinedButton.icon(onPressed: _busy ? null : () => _go(_step - 1), icon: const Icon(Icons.arrow_back_rounded), label: Text(t('السابق', 'Back'))),
                    const Spacer(),
                    if (_dirty && !_locked) Text(t('غير محفوظ', 'Unsaved'), style: AppType.meta(context).copyWith(color: c.warning)),
                    const SizedBox(width: AppSpace.xs),
                    if (_step < 7)
                      SizedBox(
                        width: 160,
                        child: PrimaryButton(isLoading: _busy, label: t('التالي', 'Next'), onPressed: () => _go(_step + 1)),
                      ),
                  ]),
                ),
              ]),
      ),
    );
  }

  /// The dashboard's header (D-103: Back · title · the step · Refresh · calendar · bell · switcher) when I work in
  /// the organization; else the older bar with its exit button. The step chips and Back / Next stay in the body.
  Widget _frame(BuildContext context, ScheduleDraft? d, Widget body) {
    final title = d?.id == null ? t('جدول جديد', 'New timetable') : (d!.name.isEmpty ? t('الجدول', 'Timetable') : d.name);
    if (!orgUsesDashboardHeader(context, _p.session.currentId)) {
      return BasePage(
        useWebCard: true,
        maxWith: 1000,
        appBar: ScreenAppBar(title: title, actions: const [ContextExitButton()]),
        child: body,
      );
    }
    return OrgPushedPage(helpPageId: 'org.timetable', 
      title: title,
      subtitle: d == null ? null : '${t('الخطوة', 'Step')} ${_step + 1}/${_steps.length} · ${_steps[_step].$1}',
      refresh: _refresh,
      maxWidth: 1000,
      child: body,
    );
  }

  Widget _body(BuildContext context, ScheduleDraft d) => switch (_step) {
        0 => _details(context, d),
        1 => _courses(context, d),
        2 => _facilities(context),
        3 => _days(context, d),
        4 => _sessions(context, d),
        5 => _staff(context, d),
        6 => _prefs(context, d),
        7 => _review(context, d),
        8 => _results(context),
        _ => _finish(context, d),
      };

  Text _hint(BuildContext context, String s) => Text(s, style: AppType.meta(context).copyWith(color: context.colors.textMedium));

  // ── A ──
  Widget _details(BuildContext context, ScheduleDraft d) {
    final p = context.watch<OrgScheduleProvider>();
    Future<void> pick(bool isStart) async {
      final x = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDate: (isStart ? d.start : d.end) ?? DateTime.now());
      if (x != null) setState(() => isStart ? d.start = x : d.end = x);
    }

    return Section(
      title: t('بيانات الجدول', 'Timetable details'),
      icon: Icons.edit_calendar_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _TextIn(value: d.name, label: t('الاسم — مثلاً: جدول الفصل الثاني', 'Name — e.g. Term 2 timetable'), enabled: !_locked, onChanged: (v) => setState(() => d.name = v)),
        OrgPickField<int>(
          label: t('الفصل الدراسي', 'Academic term'),
          icon: Icons.event_note_rounded,
          value: d.termId,
          allowNone: true,
          noneLabel: t('بدون فصل محدد', 'No specific term'),
          options: {for (final x in p.terms) asInt(x['id']): t('${x['label_ar'] ?? x['year_label']}', '${x['label_en'] ?? x['year_label']}')},
          onChanged: _locked
              ? (_) {}
              : (v) => setState(() {
                    d.termId = v;
                    // a new timetable starts with exactly the term's courses; an existing one keeps its selection
                    // (the courses step offers the same switch)
                    if (d.id == null) _selectTermCourses(d);
                    final term = p.terms.where((x) => asInt(x['id']) == v).firstOrNull;
                    // the dates must fall inside the term — start from its dates
                    if (term != null) {
                      d.start ??= DateTime.tryParse('${term['start_date']}');
                      d.end ??= DateTime.tryParse('${term['end_date']}');
                    }
                  }),
        ),
        const SizedBox(height: AppSpace.sm),
        _TextIn(value: d.termLabel, label: t('وصف الفصل (اختياري)', 'Term label (optional)'), enabled: !_locked, onChanged: (v) => setState(() => d.termLabel = v)),
        Text(t('الفترة التي يغطيها', 'The dates it covers'), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.textMedium)),
        const SizedBox(height: AppSpace.xs),
        Row(children: [
          Expanded(
              child: OutlinedButton.icon(
                  onPressed: _locked ? null : () => pick(true),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(d.start == null ? t('من', 'From') : shortDate(d.start!.toIso8601String())))),
          const SizedBox(width: AppSpace.xs),
          Expanded(
              child: OutlinedButton.icon(
                  onPressed: _locked ? null : () => pick(false),
                  icon: const Icon(Icons.flag_rounded),
                  label: Text(d.end == null ? t('إلى', 'To') : shortDate(d.end!.toIso8601String())))),
        ]),
        if (d.termId != null) _hint(context, t('يجب أن تقع التواريخ داخل الفصل المختار.', 'The dates must fall inside the chosen term.')),
      ]),
    );
  }

  // ── B ──
  Widget _courses(BuildContext context, ScheduleDraft d) {
    final p = context.watch<OrgScheduleProvider>();
    final s = context.watch<OrgSession>();
    final c = context.colors;
    final q = _courseQuery.trim().toLowerCase();
    final shown = p.loads.where((l) => q.isEmpty || '${courseName(l)} ${asMap(l['course'])['code'] ?? ''}'.toLowerCase().contains(q)).toList();
    final termIds = _termCourses(d.termId);
    return Section(
      title: t('المقررات (${d.courseIds.length})', 'Courses (${d.courseIds.length})'),
      icon: Icons.menu_book_rounded,
      trailing: s.can('courses', 'insert') && !_locked
          ? TextButton.icon(
              onPressed: () async {
                // the timetable selection stays as it is underneath; the new course is selected once the server saved it
                final row = await showOrgCourseForm(context);
                if (row == null || !mounted) return;
                await _p.loadSetup();
                setState(() => _d!.courseIds.add(asInt(row['id'])));
              },
              icon: const Icon(Icons.add_rounded),
              label: Text(t('مقرر جديد', 'New course')),
            )
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: t('بحث بالاسم أو الكود', 'Search by name or code'), isDense: true),
          onChanged: (v) => setState(() => _courseQuery = v),
        ),
        Row(children: [
          const Spacer(),
          TextButton(
            onPressed: _locked
                ? null
                : () => setState(() => d.courseIds.length == p.loads.length ? d.courseIds.clear() : d.courseIds.addAll(p.loads.map((l) => asInt(l['course_id'])))),
            child: Text(d.courseIds.length == p.loads.length ? t('إلغاء الكل', 'None') : t('الكل', 'All')),
          ),
        ]),
        if (p.loads.isEmpty) OrgEmpty(icon: Icons.menu_book_rounded, title: t('لا مقررات في المؤسسة بعد', 'No courses yet')),
        if (d.termId != null) _termBar(context, d, termIds),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          // the term's courses first, then the rest — every course stays selectable
          for (final l in [...shown.where((l) => termIds.contains(asInt(l['course_id']))), ...shown.where((l) => !termIds.contains(asInt(l['course_id'])))])
            FilterChip(
              avatar: termIds.contains(asInt(l['course_id'])) ? Icon(Icons.event_available_rounded, size: AppIconSize.sm, color: c.primary) : null,
              label: Text('${'${asMap(l['course'])['code'] ?? ''}'.isEmpty ? '' : '${asMap(l['course'])['code']} · '}${courseName(l)}',
                  style: AppType.label(context).copyWith(color: context.colors.textDark)),
              selected: d.courseIds.contains(asInt(l['course_id'])),
              onSelected: _locked ? null : (on) => setState(() => on ? d.courseIds.add(asInt(l['course_id'])) : d.courseIds.remove(asInt(l['course_id']))),
            ),
        ]),
        if (d.courseIds.isEmpty) Text(t('اختر مقرراً واحداً على الأقل', 'Pick at least one course'), style: AppType.meta(context).copyWith(color: c.warning)),
        const SizedBox(height: AppSpace.md),
        _studentCount(context, d),
      ]),
    );
  }

  Widget _termBar(BuildContext context, ScheduleDraft d, Set<int> termIds) {
    final c = context.colors;
    final exact = termIds.isNotEmpty && d.courseIds.length == termIds.length && d.courseIds.containsAll(termIds);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Row(children: [
        Icon(Icons.event_available_rounded, size: AppIconSize.md, color: c.primary),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Text(
            _orgCourses == null
                ? t('تعذّر قراءة فصول المقررات — اختر المقررات يدوياً.', 'Could not read the courses\' terms — pick the courses by hand.')
                : termIds.isEmpty
                    ? t('لا مقرر مخطط لهذا الفصل — اختر المقررات يدوياً.', 'No course is planned for this term — pick the courses by hand.')
                    : t('${termIds.length} مقرر مخطط لهذا الفصل${exact ? ' — مختارة كلها فقط' : ''}', '${termIds.length} course(s) planned for this term${exact ? ' — exactly these are selected' : ''}'),
            style: AppType.label(context).copyWith(color: c.textMedium),
          ),
        ),
        if (termIds.isNotEmpty && !exact && !_locked)
          TextButton(onPressed: () => setState(() => _selectTermCourses(d)), child: Text(t('مقررات الفصل فقط', 'Only the term\'s courses'))),
      ]),
    );
  }

  /// How many students each selected course is planned for: its subscribed (enrolled) students or one typed count.
  /// Saved as the courses' plans when leaving this step; per-course changes stay in "Enrollment & groups".
  Widget _studentCount(BuildContext context, ScheduleDraft d) {
    final c = context.colors;
    void set(String mode) => setState(() {
          _countMode = mode;
          _countDirty = true;
        });
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t('عدد الطلاب لكل مقرر', 'Students per course'), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.textDark)),
      const SizedBox(height: AppSpace.xs),
      SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'enrolled', icon: const Icon(Icons.how_to_reg_rounded), label: Text(t('الطلاب المشتركون', 'Subscribed students'))),
          ButtonSegment(value: 'manual', icon: const Icon(Icons.edit_rounded), label: Text(t('عدد يدوي', 'Manual count'))),
        ],
        selected: {_countMode},
        onSelectionChanged: _locked ? null : (v) => set(v.first),
      ),
      if (_countMode == 'manual') ...[
        const SizedBox(height: AppSpace.xs),
        SizedBox(
          width: 220,
          child: TextFormField(
            initialValue: _manualCount?.toString() ?? '',
            enabled: !_locked,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: t('عدد الطلاب', 'Number of students'), isDense: true, prefixIcon: const Icon(Icons.groups_rounded)),
            onChanged: (v) => setState(() {
              _manualCount = int.tryParse(v.trim());
              _countDirty = true;
            }),
          ),
        ),
      ],
      const SizedBox(height: AppSpace.xxs),
      Text(
          _countMode == 'manual'
              ? t('يُطبَّق على كل المقررات المختارة (${d.courseIds.length})، وتُحسب المجموعات منه وفق سعة الأماكن.',
                  'Applied to every selected course (${d.courseIds.length}); groups are sized from it by room capacity.')
              : t('يُستخدم عدد المشتركين الفعليين في كل مقرر.', 'Each course uses its actual number of subscribed students.'),
          style: AppType.meta(context).copyWith(color: c.textMedium)),
    ]);
  }

  // ── C ──
  Widget _facilities(BuildContext context) {
    final p = context.watch<OrgScheduleProvider>();
    final s = context.watch<OrgSession>();
    final c = context.colors;
    final active = p.rooms.where((r) => r['is_active'] != false).length;
    return Section(
      title: t('الأماكن المتاحة ($active نشط من ${p.rooms.length})', 'Facilities ($active active of ${p.rooms.length})'),
      icon: Icons.meeting_room_rounded,
      trailing: s.can('schedule', 'insert')
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: t('أنواع الأماكن', 'Facility types'), onPressed: () => showFacilityTypes(context, p), icon: const Icon(Icons.category_rounded)),
              IconButton(tooltip: t('إضافة قاعة', 'Add a room'), onPressed: () => showRoomForm(context, p, null), icon: Icon(Icons.add_circle_rounded, color: c.primary)),
            ])
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _hint(context,
            t('يستخدم التوليد كل الأماكن النشطة المطابقة للنوع والسعة والإمكانات. الأماكن الموقوفة لا تُستخدم، والمتاحية النهائية يحددها الخادم.',
                'Generation uses every active facility that matches the type, capacity and capabilities. Inactive ones are skipped; the server decides final availability.')),
        if (active == 0) Text(t('لا يوجد مكان نشط — أضف قاعة أولاً', 'No active facility — add a room first'), style: AppType.row(context).copyWith(color: c.warning)),
        for (final r in p.rooms)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: IconBadge(r['kind'] == 'lab' ? Icons.science_rounded : r['kind'] == 'office' ? Icons.chair_rounded : Icons.meeting_room_rounded,
                r['is_active'] == false ? c.textLight : c.primary, size: 38),
            title: Text('${'${r['code'] ?? ''}'.isEmpty ? '' : '${r['code']} · '}${r['name']}', style: AppType.bodyStrong(context)),
            subtitle: Text(
                [
                  p.kindLabels['${r['kind']}'] ?? '${r['kind']}',
                  t('سعة ${r['capacity']}', 'capacity ${r['capacity']}'),
                  if (r['exclusive'] == false) t('مشترك', 'shared'),
                  if (((r['capabilities'] as List?) ?? const []).isNotEmpty) (r['capabilities'] as List).join(', '),
                  if (r['is_active'] == false) t('موقوف', 'inactive'),
                ].join(' · '),
                style: AppType.meta(context).copyWith(color: c.textMedium)),
            onTap: s.can('schedule', 'update') ? () => showRoomForm(context, p, r) : null,
          ),
      ]),
    );
  }

  // ── D ──
  Widget _days(BuildContext context, ScheduleDraft d) {
    final p = context.watch<OrgScheduleProvider>();
    final s = context.watch<OrgSession>();
    final c = context.colors;
    final avoidDays = {...((d.settings['avoid_days'] as List?) ?? const []).map((e) => '$e')};
    final avoidPeriods = {...((d.settings['avoid_period_ids'] as List?) ?? const []).map((e) => asInt(e))};
    final maxPer = d.settings['max_periods_per_day_teacher'];
    return Column(children: [
      Section(
        title: t('أيام الدراسة', 'Teaching days'),
        icon: Icons.view_week_rounded,
        child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final day in scheduleDays)
            FilterChip(
              label: Text(dayLabels()[day] ?? day),
              selected: d.days.contains(day),
              onSelected: _locked ? null : (on) => setState(() => d.days = on ? [...d.days, day] : d.days.where((x) => x != day).toList()),
            ),
        ]),
      ),
      const SizedBox(height: AppSpace.sm),
      Section(
        title: t('الفترات اليومية (${p.periods.length})', 'Daily periods (${p.periods.length})'),
        icon: Icons.schedule_rounded,
        trailing: s.can('schedule', 'insert') ? IconButton(tooltip: t('إضافة فترة', 'Add a period'), onPressed: () => showPeriodForm(context, p, null), icon: Icon(Icons.add_circle_rounded, color: c.primary)) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _hint(context, t('الفترات مشتركة بين كل جداول المؤسسة. يمكن تمييز فترات يتجنبها التوليد إن أمكن.', 'Periods are shared by every timetable. Mark the ones generation should avoid when it can.')),
          if (p.periods.isEmpty) Text(t('أضف فترات اليوم الدراسي', 'Add the teaching periods'), style: AppType.row(context).copyWith(color: c.warning)),
          for (final x in p.periods)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: avoidPeriods.contains(asInt(x['id'])),
              onChanged: _locked
                  ? null
                  : (on) => setState(() {
                        on == true ? avoidPeriods.add(asInt(x['id'])) : avoidPeriods.remove(asInt(x['id']));
                        d.settings['avoid_period_ids'] = avoidPeriods.toList()..sort();
                      }),
              title: Text('${x['label']}  ${AppTime.clockRange('${x['start_time']}', '${x['end_time']}')}', style: AppType.bodyStrong(context)),
              subtitle: Text(t('يُتجنب إن أمكن', 'avoid if possible'), style: AppType.meta(context).copyWith(color: c.textLight)),
            ),
        ]),
      ),
      const SizedBox(height: AppSpace.sm),
      Section(
        title: t('قواعد التوزيع', 'Distribution rules'),
        icon: Icons.rule_rounded,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          OrgSwitchRow(
              title: t('توزيع المقرر على أيام مختلفة', 'Spread a course over different days'),
              value: d.settings['spread_days'] != false,
              onChanged: (v) => setState(() => d.settings['spread_days'] = v)),
          _TextIn(
            value: maxPer == null ? '' : '$maxPer',
            label: t('أقصى فترات للمدرس يومياً (اختياري)', 'Max periods per teacher per day (optional)'),
            number: true,
            enabled: !_locked,
            onChanged: (v) => setState(() => int.tryParse(v) == null ? d.settings.remove('max_periods_per_day_teacher') : d.settings['max_periods_per_day_teacher'] = int.parse(v)),
          ),
          Text(t('أيام يتجنبها التوليد إن أمكن', 'Days to avoid if possible'), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textMedium)),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final day in d.days)
              FilterChip(
                label: Text(dayLabels()[day] ?? day),
                selected: avoidDays.contains(day),
                onSelected: _locked
                    ? null
                    : (on) => setState(() {
                          on ? avoidDays.add(day) : avoidDays.remove(day);
                          d.settings['avoid_days'] = [for (final x in scheduleDays) if (avoidDays.contains(x)) x];
                        }),
              ),
          ]),
        ]),
      ),
    ]);
  }

  List<Map<String, dynamic>> _selected(OrgScheduleProvider p, ScheduleDraft d) => p.loads.where((l) => d.courseIds.contains(asInt(l['course_id']))).toList();

  // ── E ──
  Widget _sessions(BuildContext context, ScheduleDraft d) {
    final p = context.watch<OrgScheduleProvider>();
    final c = context.colors;
    final canEdit = context.watch<OrgSession>().can('schedule', 'update') && !_locked;
    return Section(
      title: t('متطلبات الحصص', 'Session requirements'),
      icon: Icons.timer_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _hint(context, t('لكل مقرر: عدد المحاضرات والسكاشن ومدتها ونوع المكان والإمكانات المطلوبة.', 'For each course: lectures and labs, their length, the room type and required capabilities.')),
        for (final l in _selected(p, d))
          ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: canEdit ? () => showLoadForm(context, p, l, onStudentAvailability: () => showAvailabilitySheet(context, p, 'course', asInt(l['course_id']), courseName(l))) : null,
            leading: IconBadge(Icons.menu_book_rounded, loadHints(l).isEmpty ? c.primary : c.warning, size: 38),
            title: Text(courseName(l), style: AppType.bodyStrong(context)),
            subtitle: Text(
                [
                  t('${asInt(l['sessions_per_week'], 1)} محاضرة × ${asInt(l['periods_per_session'], 1)} فترة', '${asInt(l['sessions_per_week'], 1)} lectures × ${asInt(l['periods_per_session'], 1)} period(s)'),
                  if (asInt(l['lab_sessions_per_week']) > 0)
                    t('${l['lab_sessions_per_week']} سكشن × ${asInt(l['lab_periods_per_session'], 1)}', '${l['lab_sessions_per_week']} labs × ${asInt(l['lab_periods_per_session'], 1)}'),
                  ...loadHints(l),
                ].join(' · '),
                style: AppType.meta(context).copyWith(color: c.textMedium)),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
      ]),
    );
  }

  // ── F ──
  Widget _staff(BuildContext context, ScheduleDraft d) {
    final p = context.watch<OrgScheduleProvider>();
    final c = context.colors;
    final canEdit = context.watch<OrgSession>().can('schedule', 'update') && !_locked;
    final people = {for (final m in p.staff) asInt(asMap(m['user'])['id']): '${asMap(m['user'])['name']}'};
    Future<void> assign(Map<String, dynamic> l, String kind) async {
      final cid = asInt(l['course_id']);
      final cur = <int>{if (l['teacher_id'] != null) asInt(l['teacher_id']), ...((l['assistant_ids'] as List?) ?? const []).map(asInt)};
      final id = await showStaffCandidates(context, p, cid, kind, current: cur);
      if (id == null) return;
      final isTeacher = p.staff.any((m) => asInt(asMap(m['user'])['id']) == id && m['role'] == 'teacher');
      final body = {
        'teacher_id': kind == 'lecture' || isTeacher ? id : l['teacher_id'],
        'assistant_ids': [...((l['assistant_ids'] as List?) ?? const []).map(asInt), if (kind == 'lab' && !isTeacher && !cur.contains(id)) id],
        'admin_assistant_id': l['admin_assistant_id'],
        'sessions_per_week': asInt(l['sessions_per_week'], 1),
        'periods_per_session': asInt(l['periods_per_session'], 1),
        'room_kind': l['room_kind'],
        'lab_sessions_per_week': asInt(l['lab_sessions_per_week']),
        'lab_periods_per_session': asInt(l['lab_periods_per_session'], 1),
        'lab_room_kind': l['lab_room_kind'] ?? 'lab',
        'required_capabilities': l['required_capabilities'] ?? const [],
        'lab_required_capabilities': l['lab_required_capabilities'] ?? const [],
      };
      final r = await orgCall(() => p.api.put('${p.base}/loads/$cid', body: body), ok: t('تم التعيين', 'Assigned'), quiet: true);
      if (r.ok) {
        await p.loadSetup();
      } else {
        toast('${orgErrorText(r.error!)}${r.detail['message'] == null ? '' : ': ${r.detail['message']}'}', error: true);
      }
    }

    return Section(
      title: t('المدرسون والمعيدون', 'Teachers & assistants'),
      icon: Icons.groups_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _hint(context, t('المرشحون يرتبهم الخادم حسب الأهلية والتفضيل والحمل. يُقترح معيد للسكشن، ويُسمح للمدرس حسب الإعدادات.',
            'Candidates are ranked by the server by eligibility, preference and load. Labs suggest an assistant; teachers are allowed by the settings.')),
        for (final l in _selected(p, d))
          Container(
            margin: const EdgeInsets.only(top: AppSpace.xs),
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.control)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(courseName(l), style: AppType.bodyStrong(context)),
              Text(
                  '${t('المدرس', 'Teacher')}: ${l['teacher_id'] == null ? t('—  لم يُعيَّن', '— not assigned') : people[asInt(l['teacher_id'])] ?? '#${l['teacher_id']}'}',
                  style: AppType.label(context).copyWith(color: l['teacher_id'] == null ? c.warning : c.textMedium)),
              if (asInt(l['lab_sessions_per_week']) > 0)
                Text(
                    '${t('المعيدون', 'Assistants')}: ${((l['assistant_ids'] as List?) ?? const []).isEmpty ? '—' : (l['assistant_ids'] as List).map((i) => people[asInt(i)] ?? '#$i').join('، ')}',
                    style: AppType.label(context).copyWith(color: c.textMedium)),
              if (canEdit)
                Wrap(spacing: AppSpace.xs, children: [
                  TextButton.icon(onPressed: () => assign(l, 'lecture'), icon: const Icon(Icons.person_search_rounded, size: AppIconSize.md), label: Text(t('مرشحو المحاضرة', 'Lecture candidates'))),
                  if (asInt(l['lab_sessions_per_week']) > 0)
                    TextButton.icon(onPressed: () => assign(l, 'lab'), icon: const Icon(Icons.science_rounded, size: AppIconSize.md), label: Text(t('مرشحو السكشن', 'Lab candidates'))),
                  TextButton.icon(onPressed: () => showLoadForm(context, p, l), icon: const Icon(Icons.edit_rounded, size: AppIconSize.md), label: Text(t('تعديل', 'Edit'))),
                ]),
            ]),
          ),
      ]),
    );
  }

  // ── G ──
  Widget _prefs(BuildContext context, ScheduleDraft d) {
    final p = context.watch<OrgScheduleProvider>();
    final s = context.watch<OrgSession>();
    final c = context.colors;
    final involved = <int>{
      for (final l in _selected(p, d)) ...[if (l['teacher_id'] != null) asInt(l['teacher_id']), ...((l['assistant_ids'] as List?) ?? const []).map(asInt)],
    };
    final staff = p.staff.where((m) => involved.contains(asInt(asMap(m['user'])['id']))).toList();
    return Section(
      title: t('الإتاحة والتفضيلات', 'Availability & preferences'),
      icon: Icons.tune_rounded,
      trailing: s.can('schedule', 'update')
          ? TextButton.icon(
              onPressed: () => openAvailabilityRequests(context),
              icon: const Icon(Icons.send_rounded, size: AppIconSize.md),
              label: Text(t('اطلبها منهم', 'Ask them')),
            )
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _hint(context,
            t('"أوقات التواجد" و"غير متاح" قيود إلزامية. "مفضّل" و"يتجنبه" مرنة وقد تُخفَّف بعد احترام كل القيود الإلزامية.',
                '"Available periods" and "unavailable" are hard rules. "Preferred" and "avoid" are soft and may be relaxed once every hard rule holds.')),
        if (staff.isEmpty) Text(t('عيّن مدرسين ومعيدين للمقررات أولاً (خطوة الهيئة).', 'Assign teachers and assistants first (Staff step).'), style: AppType.row(context).copyWith(color: c.warning)),
        for (final m in staff)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: AdminAvatar(name: '${asMap(m['user'])['name']}', url: asMap(m['user'])['image_url'] as String?, size: 36),
            title: Text('${asMap(m['user'])['name']}', style: AppType.bodyStrong(context)),
            subtitle: Text(m['role'] == 'teacher' ? t('مدرس', 'Teacher') : t('معيد', 'Teaching assistant'), style: AppType.meta(context).copyWith(color: c.textMedium)),
            trailing: Wrap(children: [
              IconButton(
                tooltip: t('أوقات التواجد', 'Available periods'),
                icon: const Icon(Icons.event_available_rounded),
                onPressed: () => showAvailabilitySheet(context, p, 'user', asInt(asMap(m['user'])['id']), '${asMap(m['user'])['name']}'),
              ),
              IconButton(
                tooltip: t('التفضيلات', 'Preferences'),
                icon: Icon(Icons.tune_rounded, color: c.primary),
                onPressed: () => showStaffPrefs(context, p, asInt(asMap(m['user'])['id']), '${asMap(m['user'])['name']}'),
              ),
            ]),
          ),
      ]),
    );
  }

  // ── H ──
  Widget _review(BuildContext context, ScheduleDraft d) {
    final p = context.watch<OrgScheduleProvider>();
    final s = context.watch<OrgSession>();
    final c = context.colors;
    final sel = _selected(p, d);
    final lectures = sel.fold<int>(0, (a, l) => a + asInt(l['sessions_per_week'], 1));
    final labs = sel.fold<int>(0, (a, l) => a + asInt(l['lab_sessions_per_week']));
    final hints = [
      if (p.periods.isEmpty) t('لا توجد فترات — التوليد يحتاجها', 'No periods — generation needs them'),
      if (!p.rooms.any((r) => r['is_active'] != false)) t('لا يوجد مكان نشط', 'No active facility'),
      for (final l in sel)
        if (loadHints(l).isNotEmpty) '${courseName(l)}: ${loadHints(l).join('، ')}',
    ];
    final running = runIsOpen(p.genRun) && p.schedule?['id'] == d.id;
    return Column(children: [
      Section(
        title: t('ملخص الإعداد', 'Setup summary'),
        icon: Icons.summarize_rounded,
        child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          OrgPill(t('${sel.length} مقرر', '${sel.length} courses'), icon: Icons.menu_book_rounded),
          OrgPill(t('$lectures محاضرة و$labs سكشن أسبوعياً', '$lectures lectures + $labs labs / week'), icon: Icons.timer_rounded),
          OrgPill(t('${d.days.length} أيام × ${p.periods.length} فترات', '${d.days.length} days × ${p.periods.length} periods'), icon: Icons.view_week_rounded),
          OrgPill(t('${p.rooms.where((r) => r['is_active'] != false).length} مكان نشط', '${p.rooms.where((r) => r['is_active'] != false).length} active facilities'),
              icon: Icons.meeting_room_rounded),
        ]),
      ),
      if (hints.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        RowCard(
          accent: c.warning,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('قد يمنع هذا وضع بعض الحصص:', 'This may keep some sessions from being placed:'), style: AppType.bodyStrong(context)),
            for (final h in hints) Text('• $h', style: AppType.label(context).copyWith(color: context.colors.textDark)),
          ]),
        ),
      ],
      const SizedBox(height: AppSpace.sm),
      Section(
        title: t('خيارات التوليد', 'Generation options'),
        icon: Icons.settings_suggest_rounded,
        child: Column(children: [
          OrgSwitchRow(
              title: t('تقديم تفضيلات الأقدم خبرة', 'Favor more experienced staff\'s preferences'),
              subtitle: t('يعتمد فقط على سنوات الخبرة المسجّلة، ويؤثر على التفضيلات المرنة فقط', 'Uses only recorded experience and affects soft preferences only'),
              value: d.settings['prefer_senior_preferences'] == true,
              onChanged: _locked ? (_) {} : (v) => setState(() => d.settings['prefer_senior_preferences'] = v)),
          OrgSwitchRow(
              title: t('الإبقاء على الحصص المثبّتة', 'Keep locked sessions'),
              subtitle: t('الحصص اليدوية المثبّتة لا تتحرك', 'Pinned manual sessions don\'t move'),
              value: _keepLocked,
              onChanged: (v) => setState(() => _keepLocked = v)),
          _TextIn(
            value: '${d.settings['time_limit_s'] ?? 8}',
            label: t('أقصى مدة للبحث (ثوانٍ)', 'Search time limit (seconds)'),
            number: true,
            enabled: !_locked,
            onChanged: (v) => setState(() => d.settings['time_limit_s'] = int.tryParse(v) ?? 8),
          ),
          _TextIn(
            value: '${d.settings['attempts'] ?? 8}',
            label: t('عدد المحاولات (حتى 50)', 'Attempts (up to 50)'),
            number: true,
            enabled: !_locked,
            onChanged: (v) => setState(() => d.settings['attempts'] = (int.tryParse(v) ?? 8).clamp(1, 50)),
          ),
        ]),
      ),
      const SizedBox(height: AppSpace.md),
      if (s.can('schedule', 'update') && !_locked)
        PrimaryButton(
          isLoading: _busy || running,
          label: running ? t('جارٍ التوليد…', 'Generating…') : t('حفظ وتوليد الجدول', 'Save & generate'),
          icon: Icons.auto_awesome_rounded,
          iconBefore: true,
          onPressed: _busy || running ? null : _generate,
        ),
      if (running) TextButton(onPressed: () => setState(() => _step = 8), child: Text(t('متابعة التقدم', 'Follow progress'))),
    ]);
  }

  // ── I ──
  Widget _results(BuildContext context) {
    final p = context.watch<OrgScheduleProvider>();
    final c = context.colors;
    final run = p.genRun;
    final sch = p.schedule;
    final courseNames = {for (final l in p.loads) asInt(l['course_id']): courseName(l)};
    final people = {for (final m in p.staff) asInt(asMap(m['user'])['id']): '${asMap(m['user'])['name']}'};
    if (sch == null) return OrgEmpty(icon: Icons.auto_awesome_rounded, title: t('لم يُولَّد بعد', 'Not generated yet'));
    final running = runIsOpen(run);
    final result = asMap(sch['result']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (run != null && (running || run['status'] == 'failed'))
        LadderLive.of(run) != null ? LadderLivePanel(p: p, inlineDecision: true) : GenerationLivePanel(run: run, onCancel: running ? () => p.cancelGeneration() : null),
      const SizedBox(height: AppSpace.sm),
      if (!running && run?['status'] == 'failed')
        RowCard(accent: c.danger, child: Text(t('فشل التوليد ولم يتغير شيء في الجدول. ${run?['error'] ?? ''}', 'Generation failed and nothing in the timetable changed. ${run?['error'] ?? ''}'))),
      if (!running && run?['status'] == 'cancelled')
        RowCard(accent: c.warning, child: Text(t('أُلغي التوليد — الجدول كما كان.', 'Generation cancelled — the timetable is as it was.'))),
      if (!running && result.isNotEmpty) ScheduleResultView(result: result, courseNames: courseNames, people: people),
      if (!running && result.isNotEmpty && sch['status'] != 'active')
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.sm),
          child: FilledButton.tonalIcon(
            onPressed: () => showGenerationResult(context, p, courseNames, canEdit: context.read<OrgSession>().can('schedule', 'update')),
            icon: const Icon(Icons.fact_check_rounded),
            label: Text(t('النتيجة والاقتراحات', 'Result & proposals')),
          ),
        ),
      if (!running && p.conflicts.isNotEmpty) ...[
        OrgSectionTitle(t('التعارضات الحالية', 'Current clashes'), padding: const EdgeInsets.fromLTRB(AppSpace.xxs, AppSpace.md, AppSpace.xxs, AppSpace.xs)),
        ConflictList(conflicts: p.conflicts, courseNames: courseNames),
      ],
      if (!running) ...[
        const SizedBox(height: AppSpace.sm),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: () => setState(() => _step = 4), icon: const Icon(Icons.tune_rounded), label: Text(t('تعديل الإعداد', 'Adjust setup')))),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: FilledButton.icon(onPressed: () => setState(() => _step = 9), icon: const Icon(Icons.arrow_forward_rounded), label: Text(t('متابعة', 'Continue')))),
        ]),
      ],
    ]);
  }

  // ── J ──
  Widget _finish(BuildContext context, ScheduleDraft d) {
    final p = context.watch<OrgScheduleProvider>();
    final s = context.watch<OrgSession>();
    final c = context.colors;
    final errors = p.conflicts.where((x) => x['severity'] == 'error').length;
    final st = '${asMap(p.schedule?['result'])['status'] ?? ''}';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Section(
        title: t('الحفظ والنشر', 'Save & publish'),
        icon: Icons.publish_rounded,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              d.published
                  ? t('الجدول منشور ويراه الطلاب والهيئة.', 'The timetable is published; students and staff see it.')
                  : t('الجدول محفوظ كمسودة — لا يراه الطلاب حتى يُنشر.', 'The timetable is saved as a draft — students don\'t see it until it is published.'),
              style: AppType.row(context).copyWith(color: c.textMedium)),
          if (st == 'partial' || st == 'infeasible')
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text(t('تنبيه: النتيجة ${resultStatusLabels()[st]} — راجع الحصص غير المجدولة قبل النشر.', 'Note: the result is "${resultStatusLabels()[st]}" — review the unplaced sessions before publishing.'),
                  style: AppType.label(context).copyWith(color: c.warning)),
            ),
          if (errors > 0)
            Text(t('$errors تعارض إلزامي يمنع النشر.', '$errors hard clash(es) block publishing.'), style: AppType.label(context).copyWith(color: c.danger)),
          const SizedBox(height: AppSpace.sm),
          PrimaryButton(isLoading: false, label: t('إبقاؤه مسودة وفتح الاستوديو', 'Keep as draft & open the studio'), onPressed: () => Navigator.of(context).pop(d.id)),
          if (!d.published && s.can('schedule', 'approve') && p.schedule != null) ...[
            const SizedBox(height: AppSpace.xs),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      final res = await publishWithConsent(context, p);
                      if (!mounted) return;
                      setState(() => _busy = false);
                      if (res == null) {
                        setState(() => d.status = 'active');
                        _saved = jsonEncode(d.toBody());
                      } else if (res.isNotEmpty && context.mounted) {
                        await showPublishConflicts(context, res, {for (final l in p.loads) asInt(l['course_id']): courseName(l)});
                      }
                    },
              icon: Icon(Icons.publish_rounded, color: c.success),
              label: Text(t('نشر للجميع', 'Publish to everyone')),
            ),
            _hint(context, t('النشر يحتاج صلاحية الاعتماد، ويرفضه الخادم إن وُجد أي تعارض إلزامي. ينقل الجداول المنشورة الأخرى للأرشيف.',
                'Publishing needs approval rights and the server refuses it while any hard clash remains. Other published timetables are archived.')),
          ],
        ]),
      ),
    ]);
  }
}

/// A text input that keeps its own controller (so typing never loses the cursor) and reports changes.
class _TextIn extends StatefulWidget {
  const _TextIn({required this.value, required this.label, required this.onChanged, this.number = false, this.enabled = true});
  final String value, label;
  final ValueChanged<String> onChanged;
  final bool number, enabled;

  @override
  State<_TextIn> createState() => _TextInState();
}

class _TextInState extends State<_TextIn> {
  late final _c = TextEditingController(text: widget.value);

  @override
  void initState() {
    super.initState();
    _c.addListener(() => widget.onChanged(_c.text));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Field(controller: _c, label: widget.label, enabled: widget.enabled, keyboard: widget.number ? TextInputType.number : null, ltr: widget.number);
}

/// The server's generation job: status · progress · cancel.
