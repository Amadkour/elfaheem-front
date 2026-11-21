// lib/features/org/students/student_settings_page.dart — the institution's student lifecycle settings in plain words
// (student lifecycle contract §6.4, PLAN §3.8): who decides what, what happens when a student stops studying, the
// reminders, what the student sees, struggling students, the file's access log and students already enrolled in a
// sibling organization. Backed by LifecycleSettings (GET / PUT …/students/settings, the WHOLE object on save).
//
//   openStudentSettings(context, orgId, {canEdit})   THE opener (the lead wires it into Settings / People)
//   OrgStudentSettingsPage(orgId:)                   loads, edits a draft, one Save, "Back to the usual settings"
//   StudentSettingsView(…)                           plain values: every group (the layout harness pumps it)
//
// "Who decides what" opens student_matrix_page.dart with the draft and takes the edited matrix back, so one Save keeps
// both. A caller without academic:update sees the values read only (the server refuses the PUT anyway). The limits of
// a suspension in years belong to the study rules (phase 5), not to this object.
library;

import 'dart:convert' show jsonEncode;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t, asMap, asBool, asInt, asStr;
import '../org_page_header.dart' show OrgPushedPage;
import '../org_v3.dart' show orgErrorText;
import 'student_file_page.dart' show pushStudentPage;
import 'student_matrix_page.dart';
import 'student_status_models.dart';
import 'students_api.dart';
import 'students_models.dart' show standingLabel;

/// The kill switch of these settings (§12); off → 403 `rules_disabled`.
const kStudentsRulesKey = 'org.students.rules';

/// The help page (§12).
const kStudentSettingsHelpId = 'org.students.rules';

String studentSettingsTitle() => t('الطلاب وقواعد الدراسة', 'Students & study rules');

/// Opens the settings page for organization [orgId]. [canEdit] false shows the values read only.
Future<void> openStudentSettings(BuildContext context, int orgId, {bool canEdit = true, StudentsApi? api}) => pushStudentPage<void>(
      context,
      OrgPushedPage(
        title: studentSettingsTitle(),
        subtitle: t('الحالات والتذكيرات', 'Statuses and reminders'),
        helpPageId: kStudentSettingsHelpId,
        width: AppWidth.form,
        child: OrgStudentSettingsPage(orgId: orgId, canEdit: canEdit, api: api),
      ),
    );

/// The standings a "struggling" rule may name (the server's STANDINGS minus `regular`).
const struggleStandings = ['warning', 'final_chance', 'repeating', 'carrying'];

/// The day choices of "remind before a request is due".
const askReminderDays = [14, 7, 3, 2, 1, 0];

/// `sibling_duplicate` values.
const siblingModes = ['off', 'warn', 'block'];

String siblingModeLabel(String m) => switch (m) {
      'off' => t('لا تتحقق', 'Do not check'),
      'block' => t('أوقف التسجيل حتى يُراجع', 'Stop until someone checks'),
      _ => t('نبّه ثم اسمح', 'Warn, then allow'),
    };

String _dayText(int d) => d == 0 ? t('في اليوم نفسه', 'On the day') : t('قبل ${daysText(d)}', '${daysText(d)} before');

// ═════════════════════════════════════════════════════════════════════════════
//  The page
// ═════════════════════════════════════════════════════════════════════════════

class OrgStudentSettingsPage extends StatefulWidget {
  const OrgStudentSettingsPage({super.key, required this.orgId, this.canEdit = true, this.api});

  final int orgId;
  final bool canEdit;
  final StudentsApi? api;

  @override
  State<OrgStudentSettingsPage> createState() => _OrgStudentSettingsPageState();
}

class _OrgStudentSettingsPageState extends State<OrgStudentSettingsPage> {
  late final StudentsApi _api = widget.api ?? StudentsApi(widget.orgId);
  LifecycleSettings? _saved, _draft, _defaults;
  String? _error;
  bool _busy = false;

  /// Bumped when the draft is replaced from outside the fields (load, save, reset): the number fields re-read it.
  int _generation = 0;

  bool get _dirty => _saved != null && _draft != null && jsonEncode(_saved!.raw) != jsonEncode(_draft!.raw);

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _take(Map<String, dynamic> m) {
    _saved = LifecycleSettings.fromJson(m['lifecycle']);
    _draft = _saved;
    _defaults = m['defaults'] is Map ? LifecycleSettings.fromJson(m['defaults']) : null;
    _generation++;
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final r = await _api.settings();
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _take(r.map);
      } else {
        _error = orgErrorText(r.error!);
      }
    });
  }

  Future<void> _save() async {
    final d = _draft;
    if (d == null) return;
    setState(() => _busy = true);
    final r = await _api.saveSettings(d.toJson());
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) _take(r.map);
    });
    showAppNotice(r.ok ? t('حُفظت إعدادات الطلاب', 'Student settings saved') : studentSettingsErrorText(r.error, r.detail), error: !r.ok);
  }

  Future<void> _reset() async {
    final dflt = _defaults;
    if (dflt == null) return;
    final ok = await appConfirm(context,
        message: t('إرجاع كل إعدادات الطلاب إلى المعتاد؟ لن يُحفظ شيء قبل أن تضغط «حفظ».',
            'Put every student setting back to the usual? Nothing is saved until you press Save.'),
        confirmLabel: t('إرجاع', 'Put back'));
    if (!ok || !mounted) return;
    setState(() {
      _draft = LifecycleSettings({..._draft!.raw, ...dflt.raw});
      _generation++;
    });
  }

  Future<void> _openMatrix() async {
    final d = _draft;
    if (d == null) return;
    final next = await pushStudentPage<LifecycleSettings>(
      context,
      OrgPushedPage(
        title: studentMatrixTitle(),
        subtitle: t('من يقترح ومن يعتمد', 'Who proposes, who approves'),
        helpPageId: kStudentSettingsHelpId,
        width: AppWidth.reading,
        child: StudentMatrixPage(orgId: widget.orgId, initial: d, defaults: _defaults, canEdit: widget.canEdit, api: _api),
      ),
    );
    if (next == null || !mounted) return;
    setState(() => _draft = next);
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    if (d == null) {
      if (_error == null) return const AppListSkeleton(items: 6);
      return AppErrorState(message: _error, onRetry: _load);
    }
    return AppUnsavedGuard(
      dirty: _dirty,
      child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
        StudentSettingsView(
          key: ValueKey('student-settings-$_generation'),
          settings: d,
          onChanged: widget.canEdit ? (s) => setState(() => _draft = s) : null,
          onOpenMatrix: _openMatrix,
        ),
        if (widget.canEdit) ...[
          AppSpace.gapLg,
          AppButtonRow(
            primary: AppButton.primary(
              key: const ValueKey('student-settings-save'),
              label: t('حفظ', 'Save'),
              icon: Icons.check_rounded,
              busy: _busy,
              onPressed: _dirty && !_busy ? _save : null,
            ),
            secondary: [
              if (_defaults != null)
                AppButton.ghost(label: t('الرجوع إلى المعتاد', 'Back to the usual'), icon: Icons.restart_alt_rounded, onPressed: _busy ? null : _reset),
            ],
          ),
        ],
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The view
// ═════════════════════════════════════════════════════════════════════════════

/// Every group from plain values. [onChanged] null = read only. Re-key the view when [settings] is replaced from
/// outside (the number fields keep what was typed).
class StudentSettingsView extends StatelessWidget {
  const StudentSettingsView({super.key, required this.settings, this.onChanged, this.onOpenMatrix});

  final LifecycleSettings settings;
  final ValueChanged<LifecycleSettings>? onChanged;
  final VoidCallback? onOpenMatrix;

  Map<String, dynamic> _sec(String k) => asMap(settings.raw[k]);

  void _set(String section, String key, dynamic v) => onChanged?.call(settings.withSection(section, {key: v}));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final edit = onChanged != null;
    final side = _sec('side_effects'), sees = _sec('student_sees'), rem = _sec('reminders');
    final strug = _sec('struggling_rule'), log = _sec('file_log');
    final seesStatus = asBool(sees['status']);
    final strugAuto = asBool(strug['auto']);
    final standings = [for (final s in (strug['standings'] is List ? strug['standings'] as List : const [])) '$s'];
    final askDays = [for (final d in (rem['ask_before_days'] is List ? rem['ask_before_days'] as List : const [])) asInt(d)];
    final sibling = asStr(settings.raw['sibling_duplicate'], 'warn');

    Widget number(String section, String key, String label, {required int max, String? helper}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          child: AppNumberField(
            key: ValueKey('student-settings-$section.$key'),
            label: label,
            helper: helper,
            initialValue: asInt(_sec(section)[key]),
            min: 0,
            max: max,
            enabled: edit,
            onChanged: (v) {
              if (v == null) return;
              final n = v.toInt();
              if (n < 0 || n > max) return;
              _set(section, key, n);
            },
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        t('هذه الإعدادات تخص مؤسستك وحدها. القيم المختارة مسبقاً هي المعتاد في الجامعات المصرية، ويمكنك تغييرها.',
            'These settings are your institution\'s own. What is picked already is the usual in Egyptian universities; change what differs.'),
        style: AppType.body(context).copyWith(color: c.textMedium),
      ),
      if (!edit) ...[
        AppSpace.gapSm,
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppStatusBadge(label: t('للعرض فقط', 'View only'), icon: Icons.visibility_outlined, tone: AppTone.neutral),
        ),
      ],
      AppSection(
        title: studentMatrixTitle(),
        child: AppActionCard(
          key: const ValueKey('student-settings-matrix'),
          icon: Icons.gavel_rounded,
          title: t('من يقرر كل تغيير في حالة الطالب', 'Who decides each change to a student\'s status'),
          subtitle: matrixSummary(settings),
          onTap: onOpenMatrix,
        ),
      ),
      AppSection(
        title: t('عندما يتوقف الطالب عن الدراسة', 'When a student stops studying'),
        subtitle: t('إيقاف القيد، التأجيل، الانسحاب، الفصل', 'Suspension, postponement, withdrawal, dismissal'),
        child: AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSwitchTile(
              icon: Icons.block_rounded,
              title: t('منع التسجيل في مقررات جديدة', 'Stop registration for new courses'),
              subtitle: t('ما دام الطالب غير مقيد (موقوف، مؤجل، منسحب…) لا يسجل مقررات جديدة.',
                  'While a student is not enrolled (suspended, postponed, withdrawn…) he cannot register for new courses.'),
              value: asBool(side['block_registration']),
              onChanged: edit ? (v) => _set('side_effects', 'block_registration', v) : null,
            ),
            AppSwitchTile(
              icon: Icons.playlist_remove_rounded,
              title: t('السؤال عن مقررات الفصل الحالي', 'Ask about this term\'s courses'),
              subtitle: t('يسأل نموذج التغيير: هل يُسحب الطالب أيضاً من المقررات التي يدرسها الآن؟',
                  'The change form asks whether to withdraw the student from the courses he is taking now.'),
              value: asBool(side['ask_drop_current']),
              onChanged: edit ? (v) => _set('side_effects', 'ask_drop_current', v) : null,
            ),
            number('side_effects', 'access_after_leaving_days', t('أيام بقاء الدخول إلى التطبيق بعد مغادرة الطالب', 'Days the student keeps the app after leaving'),
                max: 3650, helper: t('صفر = ينتهي الدخول يوم القرار', '0 = access ends on the day of the decision')),
            number('reminders', 'suspension_ending_days', t('تذكير الموظفين قبل انتهاء الإيقاف (بالأيام)', 'Remind staff before a suspension ends (days)'),
                max: 365, helper: t('صفر = بلا تذكير', '0 = no reminder')),
          ]),
        ),
      ),
      AppSection(
        title: t('التذكيرات', 'Reminders'),
        child: AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            number('reminders', 'incomplete_every_days', t('تذكير الطالب ببياناته الناقصة كل (يوم)', 'Remind a student of missing data every (days)'),
                max: 365, helper: t('صفر = بلا تذكير', '0 = no reminder')),
            number('reminders', 'incomplete_max', t('أقصى عدد للتذكيرات', 'At most this many reminders'), max: 50),
            AppSpace.gapSm,
            Text(t('تذكير الطالب قبل موعد طلب بيانات أو اجتماع', 'Remind the student before a data or meeting request is due'),
                style: AppType.label(context)),
            AppSpace.gapXs,
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final d in {...askReminderDays, ...askDays}.toList()..sort((a, b) => b.compareTo(a)))
                AppChoiceChip(
                  label: _dayText(d),
                  selected: askDays.contains(d),
                  onTap: () {
                    if (!edit) return;
                    final next = askDays.contains(d) ? [for (final x in askDays) if (x != d) x] : [...askDays, d];
                    if (next.length > 10) return;
                    next.sort((a, b) => b.compareTo(a));
                    _set('reminders', 'ask_before_days', next);
                  },
                ),
            ]),
          ]),
        ),
      ),
      AppSection(
        title: t('ما يراه الطالب', 'What the student sees'),
        subtitle: t('على بطاقة حالته في التطبيق', 'On his status card in the app'),
        child: AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSwitchTile(
              icon: Icons.badge_outlined,
              title: t('حالته الحالية', 'His current status'),
              subtitle: t('مقيد، موقوف، إنذار… العلامات الداخلية للموظفين لا تظهر له أبداً.',
                  'Enrolled, suspended, warning… Staff-only marks never show to him.'),
              value: seesStatus,
              onChanged: edit ? (v) => _set('student_sees', 'status', v) : null,
            ),
            AppSwitchTile(
              icon: Icons.notes_rounded,
              title: t('سبب آخر تغيير', 'The reason of the last change'),
              value: seesStatus && asBool(sees['reason']),
              onChanged: edit && seesStatus ? (v) => _set('student_sees', 'reason', v) : null,
            ),
            AppSwitchTile(
              icon: Icons.tag_rounded,
              title: t('رقم القرار وتاريخه', 'The decision number and date'),
              value: seesStatus && asBool(sees['decision_no']),
              onChanged: edit && seesStatus ? (v) => _set('student_sees', 'decision_no', v) : null,
            ),
          ]),
        ),
      ),
      AppSection(
        title: t('الطلاب المتعثرون', 'Struggling students'),
        child: AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSwitchTile(
              icon: Icons.support_rounded,
              title: t('وضع علامة «متعثر» تلقائياً', 'Mark struggling students automatically'),
              subtitle: t('من النتائج المعتمدة، ليتابعه المرشد. يمكن دائماً وضعها أو إزالتها يدوياً.',
                  'From approved results, so his advisor follows him up. Staff can always add or remove it by hand.'),
              value: strugAuto,
              onChanged: edit ? (v) => _set('struggling_rule', 'auto', v) : null,
            ),
            if (strugAuto) ...[
              AppSpace.gapSm,
              Text(t('عندما يكون وضعه الأكاديمي', 'When his standing is'), style: AppType.label(context)),
              AppSpace.gapXs,
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (final s in struggleStandings)
                  AppChoiceChip(
                    label: standingLabel(s),
                    selected: standings.contains(s),
                    onTap: () {
                      if (!edit) return;
                      final next = standings.contains(s) ? [for (final x in standings) if (x != s) x] : [...standings, s];
                      _set('struggling_rule', 'standings', next);
                    },
                  ),
              ]),
              number('struggling_rule', 'repeat_same_level_times', t('أو عندما يعيد الفرقة نفسها هذا العدد من المرات', 'Or when he repeats the same year this many times'),
                  max: 20, helper: t('صفر = لا تستخدم هذه القاعدة', '0 = do not use this rule')),
            ],
          ]),
        ),
      ),
      AppSection(
        title: t('خصوصية ملف الطالب', 'Privacy of the student file'),
        child: AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            number('file_log', 'window_minutes', t('اعتبار الفتح المتكرر من الشخص نفسه مرة واحدة خلال (دقيقة)', 'Count repeated opens by the same person as one within (minutes)'),
                max: 1440, helper: t('صفر = تسجيل كل فتح', '0 = record every open')),
            AppSwitchTile(
              icon: Icons.visibility_outlined,
              title: t('تنبيه الموظف أن فتح الملف يُسجَّل', 'Tell staff that opening a file is recorded'),
              value: asBool(log['tell_staff']),
              onChanged: edit ? (v) => _set('file_log', 'tell_staff', v) : null,
            ),
          ]),
        ),
      ),
      AppSection(
        title: t('طالب مقيد في كلية أخرى', 'A student enrolled in another faculty'),
        subtitle: t('عند إضافة طالب مقيد بالفعل في مؤسسة شقيقة من الجامعة نفسها',
            'When adding a student already enrolled in a sibling organization of the same university'),
        child: AppDropdown<String>(
          key: ValueKey('student-settings-sibling-$sibling'),
          decoration: InputDecoration(labelText: t('ماذا يحدث؟', 'What happens?')),
          value: siblingModes.contains(sibling) ? sibling : 'warn',
          enabled: edit,
          items: [for (final m in siblingModes) DropdownMenuItem(value: m, child: Text(siblingModeLabel(m)))],
          onChanged: edit ? (v) => v == null ? null : onChanged!(LifecycleSettings({...settings.raw, 'sibling_duplicate': v})) : null,
        ),
      ),
    ]);
  }
}
