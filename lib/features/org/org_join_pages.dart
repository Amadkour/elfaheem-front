// lib/features/org/org_join_pages.dart — joining departments (API: org_join_router.py).
//
// Both kinds of unit use the same screens; only the URL segment differs:
//   dept     an OPERATIONAL / service department (advising, student affairs, exams & control …) — joining it makes
//            you a member of that department, never a staff seat
//   program  an ACADEMIC department (IS, CS, IT …) — joining it sets your academic department (one per student)
//
// Staff
//   OrgUnitJoinHub       Policy · Codes · Requests · Members for one unit
//   OrgJoinInboxPage     every pending request I may decide, across units
// Members
//   OrgJoinUnitsTab      units I can join + "I have a code" + my requests (cancel)
//   OrgUnitJoinScreen    the unit's eligibility form → dry run → join / request; the server's answer is final
library;

import 'org_page_kit.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_buttons.dart' show AppButton, AppButtonSize;
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_access_joining.dart' show OrgAccessJoiningPage;
import 'org_dynamic_form.dart';
import 'org_page_header.dart' show OrgPushedPage;
import 'org_providers.dart';
import 'org_services_pages.dart' show fieldTypes, fieldIcons;
import 'org_ui.dart';
import 'org_v3.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/app_refresh.dart';
import 'package:flutter_education_app/design/app_icons.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_username.dart';

String unitKindLabel(String type) => type == 'program' ? t('قسم علمي', 'Academic department') : t('إدارة خدمية', 'Service department');

IconData unitKindIcon(String type) => type == 'program' ? Icons.account_tree_rounded : Icons.apartment_rounded;

/// May I configure the join policy / codes of this unit? (the server checks again)
bool canConfigureUnit(OrgSession s, String type, int id) =>
    type == 'program' ? s.can('academic', 'update') : (s.can('departments', 'update') || s.can('team', 'update', id));

/// A note dialog that insists on text when [required].
Future<String?> _askNote(BuildContext context, {required String title, required bool required}) async {
  while (true) {
    final v = await askText(context, title: title, multiline: true);
    if (v == null) return null;
    if (v.trim().isNotEmpty || !required) return v.trim();
    toast(t('اكتب الملاحظة', 'Write the note'), error: true);
    if (!context.mounted) return null;
  }
}

Widget _banner(BuildContext context, IconData icon, Color color, String text) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: orgText(context, size: 12.5))),
      ]),
    );

// ═════════════════════════════════════════════════════════════════════════════
//  Staff hub
// ═════════════════════════════════════════════════════════════════════════════

/// A pushed page's readable column: the dashboard header keeps the page's full width (its one row needs the room),
/// the content stays as narrow as the older page was.
Widget _readable(double maxWidth, Widget child) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: SizedBox.expand(child: child)),
    );

class OrgUnitJoinHub extends StatelessWidget {
  const OrgUnitJoinHub({super.key, required this.unitType, required this.unitId, required this.title, this.features, this.embedded = false});
  final String unitType;      // dept | program
  final int unitId;
  final String title;
  final List<String>? features;   // dept only — joining needs the `members` service
  final bool embedded;            // inside the department hub (no page frame)

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    final c = context.colors;
    final config = canConfigureUnit(s, unitType, unitId);
    final tabs = <(String, IconData, Widget)>[
      if (config)
        (t('سياسة الانضمام', 'Join policy'), Icons.rule_rounded,
            _PolicyTab(unitType: unitType, unitId: unitId, features: features)),
      if (config) (t('الأكواد', 'Codes'), Icons.vpn_key_rounded, _CodesTab(unitType: unitType, unitId: unitId, unitName: title)),
      (t('الطلبات', 'Requests'), Icons.how_to_reg_rounded, _RequestsTab(unitType: unitType, unitId: unitId)),
      (t('الأعضاء', 'Members'), Icons.groups_rounded, _UnitMembersTab(unitType: unitType, unitId: unitId, canRemove: config)),
    ];
    final body = DefaultTabController(
      length: tabs.length,
      child: Column(children: [
        TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: c.primary,
          indicatorColor: c.primary,
          unselectedLabelColor: c.textMedium,
          labelStyle: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800),
          tabs: [for (final x in tabs) Tab(icon: Icon(x.$2, size: 18), text: x.$1)],
        ),
        Expanded(child: TabBarView(children: [for (final x in tabs) x.$3])),
      ]),
    );
    if (embedded) return body;
    // staff only (a program's Joining from the academic pages): the dashboard's own header
    return OrgPushedPage(title: title, subtitle: t('الانضمام', 'Joining'), child: _readable(900, body));
  }
}

// ── Policy ───────────────────────────────────────────────────────────────────

class _PolicyTab extends StatefulWidget {
  const _PolicyTab({required this.unitType, required this.unitId, this.features});
  final String unitType;
  final int unitId;
  final List<String>? features;

  @override
  State<_PolicyTab> createState() => _PolicyTabState();
}

class _PolicyTabState extends State<_PolicyTab> with AutomaticKeepAliveClientMixin {
  JoinPolicyDraft? _d;
  String _saved = '';
  bool _failed = false, _busy = false;
  String? _error;
  int _members = 0;
  List<Map<String, dynamic>> _programs = [], _levels = [], _staff = [];
  bool _levelsKnown = true;
  final _capacity = TextEditingController();

  @override
  bool get wantKeepAlive => true;     // unsaved settings survive switching tabs

  String get _url => '${context.read<OrgSession>().base}/units/${widget.unitType}/${widget.unitId}/join-policy';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = context.read<OrgSession>();
    final rs = await Future.wait([
      orgCall(() => s.api.get(_url), quiet: true),
      orgCall(() => s.api.get('${s.base}/academic/programs'), quiet: true),
      orgCall(() => s.api.get('${s.base}/academic/settings'), quiet: true),
      orgCall(() => s.api.get('${s.base}/members', queryParams: {'role': 'teacher,teacher_assistant,admin_assistant', 'size': 100}), quiet: true),
    ]);
    if (!mounted) return;
    setState(() {
      _failed = !rs[0].ok;
      _error = rs[0].ok ? null : orgErrorText(rs[0].error!);
      if (rs[0].ok) {
        _d = JoinPolicyDraft.fromJson(asMap(rs[0].map['policy']));
        _members = asInt(rs[0].map['members']);
        _capacity.text = _d!.capacity == null ? '' : '${_d!.capacity}';
        _saved = jsonEncode(_d!.toBody());
      }
      _programs = asMapList(rs[1].map['items']).where((p) => p['is_active'] != false).toList();
      _levelsKnown = rs[2].ok;
      _levels = asMapList(rs[2].map['levels']);
      _staff = asMapList(rs[3].map['items']);
    });
  }

  bool get _dirty => _d != null && jsonEncode((_d!..capacity = int.tryParse(_capacity.text.trim())).toBody()) != _saved;

  Future<void> _save() async {
    final d = _d!..capacity = int.tryParse(_capacity.text.trim());
    final local = d.validate();
    if (local != null) {
      setState(() => _error = local);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await orgCall(() => context.read<OrgSession>().api.put(_url, body: d.toBody()), quiet: true);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _d = JoinPolicyDraft.fromJson(asMap(r.map['policy']));
        _capacity.text = _d!.capacity == null ? '' : '${_d!.capacity}';
        _saved = jsonEncode(_d!.toBody());
        toast(t('حُفظت سياسة الانضمام', 'Join policy saved'));
      } else {
        _error = orgErrorText(r.error!);
      }
    });
  }

  /// Options of a bound field, from the institution's configuration.
  Map<String, String> _bindOptions(String? bind) => switch (bind) {
        'academic_level' => {for (final l in _levels) '${l['key']}': orgOption(l).$2},
        'cohort' => memberCohortLabels(),
        'program' => {for (final p in _programs) '${p['id']}': '${p['code']} · ${orgNameOf(p)}'},
        _ => const {},
      };

  Future<void> _editField([int? index]) async {
    final d = _d!;
    final f = index == null ? <String, dynamic>{'type': 'text', 'required': true} : {...d.fields[index]};
    final label = TextEditingController(text: '${f['label'] ?? ''}');
    final help = TextEditingController(text: '${f['help'] ?? ''}');
    final opts = TextEditingController(text: ((f['options'] as List?) ?? const []).join('\n'));
    final allowed = <String>{...((f['allowed'] as List?) ?? const []).map((e) => '$e')};
    await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final c = ctx.colors;
          final bind = f['bind'] as String?;
          final choice = f['type'] == 'select' || f['type'] == 'multiselect';
          final bound = _bindOptions(bind);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SheetHeader(index == null ? t('حقل جديد', 'New field') : t('تعديل الحقل', 'Edit field')),
              Field(controller: label, label: t('السؤال / عنوان الحقل', 'Question / field label')),
              Text(t('ربط ببيانات المؤسسة الموثّقة', 'Link to the institution\'s trusted record'), style: orgText(ctx, size: 12.5, w: FontWeight.w800, color: c.textMedium)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, children: [
                ChoiceChip(label: Text(t('بدون ربط', 'Not linked')), selected: bind == null, onSelected: (_) => set(() => f.remove('bind'))),
                for (final e in bindLabels().entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: bind == e.key,
                    onSelected: (_) => set(() {
                      f['bind'] = e.key;
                      if (!choice) f['type'] = 'select';
                      allowed.removeWhere((a) => !_bindOptions(e.key).containsKey(a));
                    }),
                  ),
              ]),
              if (bind != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      t('الخيارات تأتي من إعدادات المؤسسة، ويُقارن الخادم الإجابة بسجل الطالب الموثّق — لا يستطيع الطالب تجاوز سجله بإجابته.',
                          'Options come from the institution\'s settings, and the server compares the answer with the student\'s trusted record — an answer can\'t override the record.'),
                      style: orgText(ctx, size: 11.5, color: c.textLight)),
                ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in fieldTypes().entries)
                  if (bind == null || e.key == 'select' || e.key == 'multiselect')
                    ChoiceChip(
                      avatar: Icon(fieldIcons[e.key], size: 16, color: f['type'] == e.key ? c.onHero : c.textMedium),
                      label: Text(e.value, style: TextStyle(fontFamily: AppFonts.family, color: f['type'] == e.key ? c.onHero : c.textDark)),
                      selected: f['type'] == e.key,
                      selectedColor: c.primary,
                      showCheckmark: false,
                      onSelected: (_) => set(() => f['type'] = e.key),
                    ),
              ]),
              const SizedBox(height: 12),
              if (bind != null) ...[
                Text(t('الإجابات المقبولة (فارغ = كل الخيارات)', 'Accepted answers (none = every option)'),
                    style: orgText(ctx, size: 12.5, w: FontWeight.w800, color: c.textMedium)),
                const SizedBox(height: 6),
                if (bound.isEmpty)
                  Text(t('لا خيارات معرّفة في إعدادات المؤسسة بعد', 'No options are configured for the institution yet'),
                      style: orgText(ctx, size: 12, color: c.warning)),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  for (final e in bound.entries)
                    FilterChip(
                        label: Text(e.value), selected: allowed.contains(e.key), onSelected: (on) => set(() => on ? allowed.add(e.key) : allowed.remove(e.key))),
                ]),
                const SizedBox(height: 10),
              ] else if (choice)
                Field(controller: opts, label: t('الخيارات (خيار في كل سطر)', 'Options (one per line)'), maxLines: 5),
              Field(controller: help, label: t('توضيح يساعد المتقدم (اختياري)', 'Helper text (optional)')),
              OrgSwitchRow(title: t('إجباري', 'Required'), value: f['required'] == true, onChanged: (v) => set(() => f['required'] = v)),
              const SizedBox(height: 8),
              AppButton.primary(
                busy: false,
                label: t('تم', 'Done'),
                onPressed: () {
                  if (label.text.trim().isEmpty) return toast(t('اكتب السؤال', 'Write the question'), error: true);
                  final options = opts.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                  final isChoice = f['type'] == 'select' || f['type'] == 'multiselect';
                  if (isChoice && bind == null && options.isEmpty) return toast(t('أضف خياراً واحداً على الأقل', 'Add at least one option'), error: true);
                  f['label'] = label.text.trim();
                  f['help'] = help.text.trim().isEmpty ? null : help.text.trim();
                  // bound fields: the server fills the options from the configuration
                  f['options'] = bind != null ? <String>[] : (isChoice ? options : <String>[]);
                  if (bind != null) {
                    f['allowed'] = allowed.toList();
                  } else {
                    f.remove('allowed');
                  }
                  setState(() => index == null ? d.fields.add(f) : d.fields[index] = f);
                  Navigator.pop(ctx);
                },
              ),
            ]),
          );
        }));
  }

  Future<bool> _leave() async {
    if (!_dirty) return true;
    return confirm(context, message: t('لديك تغييرات غير محفوظة. الخروج بدون حفظ؟', 'You have unsaved changes. Leave without saving?'), danger: true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.colors;
    final d = _d;
    if (d == null) {
      return OrgAsync(loading: !_failed, failed: _failed, onRetry: _load, child: const SizedBox.shrink());
    }
    final featureOff = widget.unitType == 'dept' && widget.features != null && !widget.features!.contains('members');
    Text label(String x) => Text(x, style: orgText(context, size: 12.5, w: FontWeight.w800, color: c.textMedium));
    final assistants = {
      for (final m in _staff) asInt(asMap(m['user'])['id']): '${asMap(m['user'])['name']} · ${memberRoleLabels()['${m['role']}'] ?? m['role']}'
    };
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _leave() && context.mounted) Navigator.of(context).pop();
      },
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
        if (featureOff)
          _banner(context, Icons.toggle_off_rounded, c.warning,
              t('خدمة "الأعضاء" غير مفعّلة لهذه الإدارة — فعّلها من تعديل الإدارة ليعمل الانضمام.',
                  'The "Members" service is off for this department — switch it on in Edit department for joining to work.')),
        _banner(context, Icons.groups_rounded, c.primary,
            '${unitKindLabel(widget.unitType)} · ${t('$_members عضو حالياً', '$_members members now')}. '
            '${widget.unitType == 'program' ? t('القبول يحدد القسم العلمي للطالب (قسم واحد لكل طالب).', 'Acceptance sets the student\'s academic department (one per student).') : t('القبول يجعل الشخص عضواً في الإدارة، ولا يمنحه صلاحيات موظف.', 'Acceptance makes the person a member of the department — it never grants staff rights.')}'),
        Section(
          title: t('طريقة الانضمام', 'How people join'),
          icon: DirIcons.login,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('اختر طريقة أو أكثر — الإضافة اليدوية من تبويب الأعضاء متاحة دائماً.',
                    'Pick one or more ways — manual add from the Members tab always works.'),
                style: orgText(context, size: 12, color: c.textMedium)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final e in joinPathLabels().entries)
                FilterChip(label: Text(e.value), selected: d.paths.contains(e.key), onSelected: (on) => setState(() => d.togglePath(e.key, on))),
            ]),
            const SizedBox(height: 8),
            if (d.closed)
              Text(joinMethodHelp('closed'), style: orgText(context, size: 12, color: c.textMedium))
            else
              for (final k in joinPathLabels().keys)
                if (d.paths.contains(k))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• ${joinPathHelp(k)}', style: orgText(context, size: 12, color: c.textMedium)),
                  ),
          ]),
        ),
        if (!d.closed) ...[
          const SizedBox(height: 12),
          Section(
            title: t('من يستطيع الانضمام', 'Who can join'),
            icon: Icons.filter_alt_rounded,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              label(t('الفئات', 'Groups')),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final e in joinRoleLabels().entries)
                  FilterChip(label: Text(e.value), selected: d.roles.contains(e.key),
                      onSelected: (on) => setState(() => on ? d.roles.add(e.key) : d.roles.remove(e.key))),
              ]),
              if (d.targetsStudents) ...[
                const SizedBox(height: 12),
                label(t('الدفعة', 'Cohort')),
                ChoiceRow<String>(options: audienceCohortLabels(), value: d.cohort, onChanged: (v) => setState(() => d.cohort = v)),
                const SizedBox(height: 12),
                label(t('الفرق / المستويات (فارغ = الكل)', 'Years / levels (none = all)')),
                if (!_levelsKnown)
                  Text(t('لا تملك صلاحية عرض إعدادات المستويات', 'You can\'t view the level settings'), style: orgText(context, size: 12, color: c.textLight))
                else if (_levels.isEmpty)
                  Text(t('لم تُعرّف فرق / مستويات للمؤسسة بعد — أضفها من الهيكل الأكاديمي.', 'No years / levels are configured yet — add them in Academic structure.'),
                      style: orgText(context, size: 12, color: c.textLight)),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  for (final l in _levels)
                    FilterChip(
                        label: Text(orgOption(l).$2),
                        selected: d.levels.contains('${l['key']}'),
                        onSelected: (on) => setState(() => on ? d.levels.add('${l['key']}') : d.levels.remove('${l['key']}'))),
                ]),
              ],
              const SizedBox(height: 12),
              label(t('من الأقسام العلمية (فارغ = الكل)', 'From academic departments (none = all)')),
              if (_programs.isEmpty) Text(t('لا أقسام علمية', 'No academic departments'), style: orgText(context, size: 12, color: c.textLight)),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final p in _programs)
                  FilterChip(
                      label: Text('${p['code']} · ${orgNameOf(p)}'),
                      selected: d.programIds.contains(asInt(p['id'])),
                      onSelected: (on) => setState(() => on ? d.programIds.add(asInt(p['id'])) : d.programIds.remove(asInt(p['id'])))),
              ]),
              const SizedBox(height: 12),
              OrgNumberField(controller: _capacity, label: t('الحد الأقصى للأعضاء (اختياري)', 'Maximum members (optional)')),
            ]),
          ),
          if (d.needsApprover) ...[
            const SizedBox(height: 12),
            Section(
              title: t('من يعتمد الطلبات', 'Who approves'),
              icon: Icons.verified_user_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ChoiceRow<String>(
                  options: {'manager': t('مدير الوحدة', 'The unit manager'), 'assistants': t('مساعدون محددون', 'Chosen assistants')},
                  value: d.approver,
                  onChanged: (v) => setState(() => d.approver = v),
                ),
                const SizedBox(height: 6),
                Text(
                    d.approver == 'manager'
                        ? t('يصل كل طلب لمدير الوحدة. يستطيع مدير المؤسسة القرار أيضاً.', 'Every request goes to the unit manager. Organization admins can decide too.')
                        : t('يصل كل طلب للمساعدين المحددين فقط (ولمدير المؤسسة). لا يقرر أحد في طلبه.',
                            'Requests go only to the chosen assistants (and organization admins). Nobody decides their own request.'),
                    style: orgText(context, size: 12, color: c.textMedium)),
                if (d.approver == 'assistants') ...[
                  const SizedBox(height: 8),
                  if (assistants.isEmpty) Text(t('لا يوجد هيئة معاونة أو إداريون', 'No staff members'), style: orgText(context, size: 12, color: c.textLight)),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    for (final e in assistants.entries)
                      FilterChip(
                          label: Text(e.value),
                          selected: d.assistantIds.contains(e.key),
                          onSelected: (on) => setState(() => on ? d.assistantIds.add(e.key) : d.assistantIds.remove(e.key))),
                  ]),
                ],
              ]),
            ),
          ],
          const SizedBox(height: 12),
          Section(
            title: t('عند غياب البيانات الموثّقة', 'When the trusted record is missing'),
            icon: Icons.fact_check_rounded,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ChoiceRow<String>(
                options: {'review': t('مراجعة يدوية', 'Manual review'), 'reject': t('رفض تلقائي', 'Reject')},
                value: d.unverified,
                onChanged: (v) => setState(() => d.unverified = v),
              ),
              Text(
                  d.unverified == 'review'
                      ? t('يصبح الطلب قيد المراجعة ويكتب المعتمد ملاحظة التحقق قبل القبول (حتى مع القبول التلقائي).',
                          'The request waits for review and the approver writes a verification note before accepting (even with automatic acceptance).')
                      : t('يُرفض الطلب إن لم تكن بيانات الطالب مسجّلة.', 'The request is refused when the student\'s data isn\'t on record.'),
                  style: orgText(context, size: 12, color: c.textMedium)),
            ]),
          ),
          const SizedBox(height: 12),
          Section(
            title: t('نموذج الأهلية (${d.fields.length})', 'Eligibility form (${d.fields.length})'),
            icon: Icons.dynamic_form_rounded,
            trailing: TextButton.icon(onPressed: () => _editField(), icon: const Icon(Icons.add_rounded), label: Text(t('حقل', 'Field'))),
            child: d.fields.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(t('اختياري — أسئلة يجيب عنها المتقدم. اربطها بالفرقة أو الدفعة أو القسم ليتحقق منها الخادم.',
                        'Optional — questions the applicant answers. Link them to the year, cohort or department so the server checks them.'),
                        style: orgText(context, size: 12, color: c.textMedium)))
                : Column(children: [
                    for (var i = 0; i < d.fields.length; i++)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(fieldIcons[d.fields[i]['type']] ?? Icons.short_text_rounded, color: c.primary),
                        title: Text('${d.fields[i]['label']}', style: orgText(context, w: FontWeight.w700)),
                        subtitle: Text([
                          fieldTypes()[d.fields[i]['type']] ?? '',
                          if (d.fields[i]['required'] == true) t('إجباري', 'required'),
                          if (d.fields[i]['bind'] != null) '🔗 ${bindLabels()[d.fields[i]['bind']]}',
                        ].join(' · '), style: orgText(context, size: 12, color: c.textMedium)),
                        onTap: () => _editField(i),
                        trailing: IconButton(tooltip: t('حذف', 'Delete'), onPressed: () => setState(() => d.fields.removeAt(i)), icon: Icon(Icons.delete_outline_rounded, color: c.danger)),
                      ),
                  ]),
          ),
        ],
        const SizedBox(height: 14),
        if (_error != null) _banner(context, Icons.error_outline_rounded, c.danger, _error!),
        AppButton.primary(busy: _busy, label: t('حفظ سياسة الانضمام', 'Save join policy'), onPressed: _dirty ? _save : null),
        if (_dirty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(t('تغييرات غير محفوظة', 'Unsaved changes'), textAlign: TextAlign.center, style: orgText(context, size: 12, color: c.warning)),
          ),
      ]),
    );
  }
}

// ── Codes ────────────────────────────────────────────────────────────────────

class _CodesTab extends StatefulWidget {
  const _CodesTab({required this.unitType, required this.unitId, required this.unitName});
  final String unitType, unitName;
  final int unitId;

  @override
  State<_CodesTab> createState() => _CodesTabState();
}

class _CodesTabState extends State<_CodesTab> {
  List<Map<String, dynamic>>? _rows;
  bool _failed = false;

  String get _url => '${context.read<OrgSession>().base}/units/${widget.unitType}/${widget.unitId}/codes';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final r = await orgCall(() => context.read<OrgSession>().api.get(_url));
    if (!mounted) return;
    setState(() {
      _rows = r.ok ? asMapList(r.map['items']) : _rows;
      _failed = !r.ok && _rows == null;
    });
  }

  /// The plain code — shown once, right after the server created it.
  Future<void> _showPlain(String code) => showAdminSheet<void>(context, (ctx) {
        final c = ctx.colors;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SheetHeader(t('كود الانضمام الجديد', 'New join code')),
            SelectableText(code,
                textDirection: TextDirection.ltr,
                style: TextStyle(fontFamily: AppFonts.display, fontSize: 30, letterSpacing: 5, fontWeight: FontWeight.w800, color: c.primary)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                toast(t('نُسخ الكود', 'Code copied'));
              },
              icon: const Icon(Icons.copy_rounded),
              label: Text(t('نسخ', 'Copy')),
            ),
            const SizedBox(height: 10),
            Text(
                t('يظهر الكود مرة واحدة فقط — انسخه الآن. يصلح للانضمام إلى «${widget.unitName}» فقط في هذه المؤسسة، ولا يتجاوز شروط الأهلية أو السعة.',
                    'Shown once only — copy it now. It works only for joining "${widget.unitName}" in this organization and never bypasses the eligibility rules or capacity.'),
                textAlign: TextAlign.center,
                style: orgText(ctx, size: 12.5, color: c.textMedium)),
          ]),
        );
      });

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final s = context.read<OrgSession>();
    final labelC = TextEditingController(text: '${row?['label'] ?? ''}');
    final maxC = TextEditingController(text: row?['max_uses'] == null ? '' : '${row!['max_uses']}');
    DateTime? from = orgParseUtc(row?['valid_from']), until = orgParseUtc(row?['valid_until']);
    bool oneTime = false, busy = false;
    String? err;
    await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final c = ctx.colors;
          Future<void> pick(bool isFrom) async {
            final d = await showDatePicker(context: ctx, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime(2100),
                initialDate: (isFrom ? from : until) ?? DateTime.now());
            if (d == null) return;
            set(() => isFrom ? from = DateTime(d.year, d.month, d.day) : until = DateTime(d.year, d.month, d.day, 23, 59, 59));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SheetHeader(row == null ? t('كود جديد', 'New code') : t('تعديل الكود', 'Edit code')),
              Field(controller: labelC, label: t('وصف داخلي (مثلاً: دفعة 2026)', 'Internal label (e.g. Class of 2026)')),
              Text(t('مدة الصلاحية (اختياري)', 'Validity (optional)'), style: orgText(ctx, size: 12.5, w: FontWeight.w800, color: c.textMedium)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: () => pick(true),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(from == null ? t('من الآن', 'From now') : shortDate(from!.toIso8601String())))),
                const SizedBox(width: 8),
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: () => pick(false),
                        icon: const Icon(Icons.flag_rounded),
                        label: Text(until == null ? t('بلا انتهاء', 'No end') : shortDate(until!.toIso8601String())))),
              ]),
              if (from != null || until != null)
                TextButton(onPressed: () => set(() => from = until = null), child: Text(t('بلا حدود زمنية', 'No time limits'))),
              const SizedBox(height: 8),
              if (row == null)
                OrgSwitchRow(
                    title: t('استخدام واحد فقط', 'One use only'),
                    subtitle: t('للدعوات الفردية', 'For a personal invitation'),
                    value: oneTime,
                    onChanged: (v) => set(() => oneTime = v)),
              if (!oneTime)
                OrgNumberField(controller: maxC, label: t('أقصى عدد استخدامات (فارغ = بلا حد)', 'Maximum uses (empty = unlimited)')),
              if (err != null) _banner(ctx, Icons.error_outline_rounded, c.danger, err!),
              AppButton.primary(
                busy: busy,
                label: row == null ? t('إنشاء الكود', 'Create code') : t('حفظ', 'Save'),
                onPressed: () async {
                  if (from != null && until != null && !from!.isBefore(until!)) {
                    return set(() => err = orgCodeText('bad_window'));
                  }
                  final body = {
                    'label': labelC.text.trim().isEmpty ? null : labelC.text.trim(),
                    'valid_from': orgUtc(from),
                    'valid_until': orgUtc(until),
                    if (row == null) 'one_time': oneTime,
                    if (!oneTime) 'max_uses': int.tryParse(maxC.text.trim()),
                  };
                  set(() {
                    busy = true;
                    err = null;
                  });
                  final r = await orgCall(() => row == null ? s.api.post(_url, body: body) : s.api.put('$_url/${row['id']}', body: body), quiet: true);
                  if (!ctx.mounted) return;
                  set(() => busy = false);
                  if (!r.ok) return set(() => err = orgErrorText(r.error!));
                  Navigator.pop(ctx);
                  if (r.map['code'] != null) await _showPlain('${r.map['code']}');
                  if (row != null) toast(t('تم الحفظ', 'Saved'));
                },
              ),
            ]),
          );
        }));
    _load();
  }

  Future<void> _act(Map<String, dynamic> row, String action) async {
    final s = context.read<OrgSession>();
    final id = row['id'];
    OrgCall r;
    switch (action) {
      case 'on' || 'off':
        r = await orgCall(() => s.api.put('$_url/$id', body: {'status': action == 'on' ? 'active' : 'inactive'}),
            ok: action == 'on' ? t('الكود فعّال', 'Code switched on') : t('أُوقف الكود — من انضموا به يبقون أعضاء', 'Code switched off — people who joined with it stay'));
      case 'revoke':
        if (!await confirm(context,
            message: t('إلغاء الكود نهائياً؟ لن يعمل بعد الآن، ولا يُخرج من انضموا به.', 'Revoke this code for good? It stops working; people who joined with it stay.'),
            danger: true)) {
          return;
        }
        r = await orgCall(() => s.api.post('$_url/$id/revoke'), ok: t('أُلغي الكود', 'Code revoked'));
      default:
        if (!await confirm(context, message: t('إصدار كود جديد يلغي الكود الحالي. متابعة؟', 'A new code revokes the current one. Continue?'))) return;
        r = await orgCall(() => s.api.post('$_url/$id/regenerate'));
        if (r.ok && r.map['code'] != null && mounted) await _showPlain('${r.map['code']}');
    }
    if (r.ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = _rows;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'unit_code_new',
        backgroundColor: c.primary,
        onPressed: () => _edit(),
        icon: Icon(Icons.add_rounded, color: c.onHero),
        label: Text(t('كود جديد', 'New code'), style: TextStyle(fontFamily: AppFonts.family, color: c.onHero)),
      ),
      body: OrgAsync(
        loading: rows == null && !_failed,
        failed: _failed,
        onRetry: _load,
        child: rows == null
            ? const SizedBox.shrink()
            : AppRefresh(
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 100), children: [
                  _banner(context, Icons.info_outline_rounded, c.primary,
                      t('الأكواد تُنشأ على الخادم ولا تُعرض كاملة إلا مرة واحدة. الكود يخص هذه الوحدة فقط ولا يتجاوز شروط الأهلية.',
                          'Codes are created by the server and shown in full only once. A code is for this unit only and never bypasses eligibility.')),
                  if (rows.isEmpty) OrgEmpty(icon: Icons.vpn_key_rounded, title: t('لا أكواد بعد', 'No codes yet')),
                  for (final r in rows) _codeCard(context, r),
                ]),
              ),
      ),
    );
  }

  Widget _codeCard(BuildContext context, Map<String, dynamic> r) {
    final c = context.colors;
    final state = '${r['state']}';
    final live = state == 'active';
    final revoked = r['status'] == 'revoked';
    final from = orgParseUtc(r['valid_from']), until = orgParseUtc(r['valid_until']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RowCard(
        accent: live ? c.success : null,
        child: Row(children: [
          IconBadge(Icons.vpn_key_rounded, live ? c.success : c.textLight, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r['hint'] ?? ''}${'${r['label'] ?? ''}'.isEmpty ? '' : ' · ${r['label']}'}', textDirection: TextDirection.ltr,
                  style: orgText(context, w: FontWeight.w800)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                StatusChip(codeStateLabels()[state] ?? state, live ? c.success : (revoked ? c.danger : c.warning)),
                OrgPill(r['max_uses'] == null ? t('${r['uses']} استخدام', '${r['uses']} uses') : '${r['uses']} / ${r['max_uses']}',
                    icon: Icons.how_to_reg_rounded),
                if (from != null) OrgPill('${t('من', 'from')} ${shortDate(from.toIso8601String())}', icon: Icons.play_arrow_rounded),
                if (until != null) OrgPill('${t('حتى', 'until')} ${shortDate(until.toIso8601String())}', icon: Icons.timer_rounded, color: c.warning),
              ]),
            ]),
          ),
          if (!revoked)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'edit' ? _edit(r) : _act(r, v),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(t('تعديل المدة والحد', 'Edit validity & limit'))),
                if (r['status'] == 'active') PopupMenuItem(value: 'off', child: Text(t('إيقاف مؤقت', 'Switch off'))),
                if (r['status'] == 'inactive') PopupMenuItem(value: 'on', child: Text(t('تفعيل', 'Switch on'))),
                PopupMenuItem(value: 'regenerate', child: Text(t('إصدار كود بديل', 'Issue a replacement'))),
                PopupMenuItem(value: 'revoke', child: Text(t('إلغاء نهائي', 'Revoke'), style: TextStyle(color: c.danger))),
              ],
            ),
        ]),
      ),
    );
  }
}

// ── Requests ─────────────────────────────────────────────────────────────────

class _RequestsTab extends StatelessWidget {
  const _RequestsTab({required this.unitType, required this.unitId});
  final String unitType;
  final int unitId;

  @override
  Widget build(BuildContext context) {
    final s = context.read<OrgSession>();
    return ChangeNotifierProvider(
      create: (_) => OrgPaged('${s.base}/units/$unitType/$unitId/join-requests', {'status': 'pending'})..refresh(),
      child: Builder(builder: (context) {
        final p = context.watch<OrgPaged>();
        return PagedList<OrgPaged>(
          header: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilterChips<String>(
              value: '${p.filters['status'] ?? ''}',
              options: {...requestStatusLabels(), '': t('الكل', 'All')},
              onChanged: (v) => p.setFilter('status', v.isEmpty ? null : v),
            ),
          ),
          emptyText: t('لا طلبات هنا', 'No requests here'),
          itemBuilder: (context, row) => JoinRequestCard(row: row, onChanged: p.refresh),
        );
      }),
    );
  }
}

/// The organization's joining inbox: people asking to join the organization AND its departments (select many →
/// accept / reject), plus — for org admins — join codes and "how people join" (org_access_joining.dart).
class OrgJoinInboxPage extends StatelessWidget {
  const OrgJoinInboxPage({super.key});

  @override
  Widget build(BuildContext context) => const OrgAccessJoiningPage();
}

class JoinRequestCard extends StatelessWidget {
  const JoinRequestCard({super.key, required this.row, required this.onChanged, this.showUnit = false});
  final Map<String, dynamic> row;
  final Future<void> Function() onChanged;
  final bool showUnit;

  Future<void> _decide(BuildContext context, bool approve) async {
    final s = context.read<OrgSession>();
    final verify = row['needs_verification'] == true;
    String? note;
    if (!approve) {
      note = await _askNote(context, title: t('سبب الرفض (يصل للمتقدم)', 'Reason for rejecting (sent to the applicant)'), required: true);
      if (note == null) return;
    } else if (verify) {
      note = await _askNote(context,
          title: t('ملاحظة التحقق — كيف تحققت من بيانات المتقدم؟', 'Verification note — how did you check the applicant\'s data?'), required: true);
      if (note == null) return;
    } else if (!context.mounted || !await confirm(context, message: t('قبول الطلب؟ يعيد الخادم التحقق من الأهلية الآن.', 'Accept? The server re-checks eligibility now.'))) {
      return;
    }
    final r = await orgCall(() => s.api.post('${s.base}/join-requests/${row['id']}/${approve ? 'approve' : 'reject'}', body: {'note': ?note}),
        ok: approve ? t('تم القبول', 'Accepted') : t('تم الرفض', 'Rejected'), quiet: true);
    if (!r.ok && context.mounted) {
      final reasons = asMapList(r.detail['reasons']);
      toast([orgErrorText(r.error!), for (final x in reasons) joinReasonText(x)].join(' — '), error: true);
    }
    // a decision conflict means someone else decided — reload either way
    await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final u = asMap(row['user']);
    final unit = asMap(row['unit']);
    final status = '${row['status']}';
    final pending = status == 'pending';
    final verify = row['needs_verification'] == true;
    final answers = asMap(row['answers']);
    final checks = asMap(row['checks']);
    final missingCourses = (asMap(checks['entry_courses'])['missing'] as List?) ?? const [];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: RowCard(
        accent: pending ? (verify ? c.warning : c.primary) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AdminAvatar(name: '${u['name'] ?? ''}', url: u['image_url'] as String?),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${u['name'] ?? '#${row['user_id']}'}', maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                if (showUnit && unit.isNotEmpty)
                  Text('${unitKindLabel('${unit['unit_type']}')} · ${orgNameOf(unit)}', style: orgText(context, size: 12, color: c.textMedium)),
                Text(relTime(row['created_at']), style: orgText(context, size: 11.5, color: c.textLight)),
                // the status under the name: beside it, a narrow phone had no room left for the name
                if (!pending) ...[
                  const SizedBox(height: AppSpace.xxs),
                  StatusChip(requestStatusLabels()[status] ?? status, statusColor(context, status)),
                ],
              ]),
            ),
          ]),
          if (row['code_verified'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: OrgPill(t('✓ الكود صحيح', '✓ Code verified'), color: c.success),
            ),
          if (verify && pending)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _banner(context, Icons.fact_check_rounded, c.warning,
                  t('بعض بيانات المتقدم غير مسجّلة لدى المؤسسة — تحقق منها واكتب ملاحظة قبل القبول.',
                      'Some of the applicant\'s data is not on record — verify it and write a note before accepting.')),
            ),
          if (missingCourses.isNotEmpty)
            Text(t('لم يجتز ${missingCourses.length} من متطلبات الالتحاق', '${missingCourses.length} entry course(s) not passed'),
                style: orgText(context, size: 12, color: c.danger)),
          if (answers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                // the form field's own label (`answer_labels`, sent by the server); an older server sends only the key
                for (final e in answers.entries)
                  OrgPill('${asMap(row['answer_labels'])[e.key] ?? e.key}: ${e.value is List ? (e.value as List).join('، ') : e.value}',
                      color: c.textMedium),
              ]),
            ),
          if ('${row['note'] ?? ''}'.isNotEmpty) Text('💬 ${row['note']}', style: orgText(context, size: 12.5)),
          if (pending)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 8, children: [
                AppButton.secondary(size: AppButtonSize.sm, onPressed: () => _decide(context, true), icon: Icons.check_rounded, label: t('قبول', 'Accept')),
                AppButton.ghost(size: AppButtonSize.sm, onPressed: () => _decide(context, false), icon: Icons.close_rounded, label: t('رفض', 'Reject')),
              ]),
            ),
        ]),
      ),
    );
  }
}

// ── Unit members ─────────────────────────────────────────────────────────────

class _UnitMembersTab extends StatefulWidget {
  const _UnitMembersTab({required this.unitType, required this.unitId, required this.canRemove});
  final String unitType;
  final int unitId;
  final bool canRemove;

  @override
  State<_UnitMembersTab> createState() => _UnitMembersTabState();
}

class _UnitMembersTabState extends State<_UnitMembersTab> {
  List<Map<String, dynamic>>? _rows;
  bool _failed = false;

  String get _url => '${context.read<OrgSession>().base}/units/${widget.unitType}/${widget.unitId}/members';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final r = await orgCall(() => context.read<OrgSession>().api.get(_url));
    if (!mounted) return;
    setState(() {
      _rows = r.ok ? asMapList(r.map['items']) : _rows;
      _failed = !r.ok && _rows == null;
    });
  }

  Future<void> _addManually() async {
    final already = {for (final r in _rows ?? const <Map<String, dynamic>>[]) asInt(asMap(r['user'])['id'])};
    final ids = await showAdminSheet<Set<int>>(context, (_) => _ManualAddSheet(exclude: already));
    if (ids == null || ids.isEmpty || !mounted) return;
    final r = await orgCall(() => context.read<OrgSession>().api.post(_url, body: {'user_ids': ids.toList()}));
    if (!mounted || !r.ok) return;
    final added = (r.map['added'] as List? ?? const []).length, skipped = (r.map['skipped'] as List? ?? const []).length;
    toast(skipped == 0 ? t('أُضيف $added', '$added added') : t('أُضيف $added · تُخطّي $skipped (ليس عضواً / موجود / مكتمل)', '$added added · $skipped skipped (not a member / already in / full)'));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = _rows;
    return OrgAsync(
      loading: rows == null && !_failed,
      failed: _failed,
      onRetry: _load,
      child: rows == null
          ? const SizedBox.shrink()
          : rows.isEmpty && !widget.canRemove
              ? OrgEmpty(icon: Icons.groups_rounded, title: t('لا أعضاء بعد', 'No members yet'))
              : AppRefresh(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
                    if (widget.canRemove)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AppButton.tonal(size: AppButtonSize.sm, onPressed: _addManually, icon: Icons.person_add_alt_1_rounded, label: t('إضافة يدوية', 'Add manually')),
                        ),
                      ),
                    if (rows.isEmpty) OrgEmpty(icon: Icons.groups_rounded, title: t('لا أعضاء بعد', 'No members yet')),
                    for (final r in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: RowCard(
                          child: Row(children: [
                            AdminAvatar(name: '${asMap(r['user'])['name']}', url: asMap(r['user'])['image_url'] as String?),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${asMap(r['user'])['name']}', style: orgText(context, w: FontWeight.w800)),
                                Text(
                                    [
                                      if (r['stage'] != null) '${r['stage']}',
                                      if (r['joined_via'] != null) '${r['joined_via']}',
                                      if (r['joined_at'] != null) shortDate('${r['joined_at']}'),
                                    ].join(' · '),
                                    style: orgText(context, size: 12, color: c.textMedium)),
                              ]),
                            ),
                            if (widget.canRemove)
                              IconButton(
                                tooltip: t('إخراج', 'Remove'),
                                icon: Icon(Icons.person_remove_rounded, color: c.danger),
                                onPressed: () async {
                                  if (!await confirm(context, message: t('إخراج ${asMap(r['user'])['name']} من الوحدة؟', 'Remove ${asMap(r['user'])['name']} from the unit?'), danger: true)) return;
                                  final res = await orgCall(() => context.read<OrgSession>().api.delete('$_url/${asMap(r['user'])['id']}'), ok: t('تم', 'Done'));
                                  if (res.ok) _load();
                                },
                              ),
                          ]),
                        ),
                      ),
                  ]),
                ),
    );
  }
}

/// Picks organization members (any member type) to add to a unit by hand. Pops the chosen user ids.
class _ManualAddSheet extends StatefulWidget {
  const _ManualAddSheet({required this.exclude});
  final Set<int> exclude;

  @override
  State<_ManualAddSheet> createState() => _ManualAddSheetState();
}

class _ManualAddSheetState extends State<_ManualAddSheet> {
  final _q = TextEditingController();
  final _picked = <int>{};
  List<Map<String, dynamic>>? _items;
  bool _failed = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final s = context.read<OrgSession>(), seq = ++_seq;
    final r = await orgCall(
        () => s.api.get('${s.base}/members', queryParams: {'size': 50, if (_q.text.trim().isNotEmpty) 'search': _q.text.trim()}),
        quiet: true);
    if (!mounted || seq != _seq) return;
    setState(() {
      _items = r.ok ? asMapList(r.map['items']) : _items;
      _failed = !r.ok && _items == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = [for (final m in _items ?? const <Map<String, dynamic>>[]) if (!widget.exclude.contains(asInt(asMap(m['user'])['id']))) m];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('إضافة أعضاء يدوياً', 'Add members manually'), style: orgText(context, size: 16, w: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(t('أي عضو في المؤسسة: طلاب، مدرسون، معيدون، إداريون.', 'Any organization member: students, teachers, assistants, staff.'),
            style: orgText(context, size: 12, color: c.textMedium)),
        const SizedBox(height: 10),
        TextField(
          controller: _q,
          onChanged: (_) => _search(),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: t('ابحث بالاسم أو البريد أو الكود أو @اسم المستخدم', 'Name, e-mail, code or @username'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: OrgAsync(
            loading: _items == null && !_failed,
            failed: _failed,
            onRetry: _search,
            child: items.isEmpty
                ? OrgEmpty(icon: Icons.person_search_rounded, title: t('لا نتائج', 'No results'))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final u = asMap(items[i]['user']), id = asInt(u['id']);
                      return CheckboxListTile(
                        value: _picked.contains(id),
                        onChanged: (on) => setState(() => on == true ? _picked.add(id) : _picked.remove(id)),
                        secondary: AdminAvatar(name: '${u['name']}', url: u['image_url'] as String?),
                        title: Text('${u['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          AppUsernameLine(usernameFrom(u)),
                          Text(memberRoleLabels()['${items[i]['role']}'] ?? '${items[i]['role'] ?? ''}',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ]),
                        controlAffinity: ListTileControlAffinity.trailing,
                        contentPadding: EdgeInsets.zero,
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 8),
        AppButton.primary(
          busy: false,
          label: t('إضافة (${_picked.length})', 'Add (${_picked.length})'),
          onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, {..._picked}),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Member side
// ═════════════════════════════════════════════════════════════════════════════

const _pub = '$orgBase/public';

class OrgJoinUnitsTab extends StatefulWidget {
  const OrgJoinUnitsTab({super.key, required this.orgId});
  final int orgId;

  @override
  State<OrgJoinUnitsTab> createState() => _OrgJoinUnitsTabState();
}

class _OrgJoinUnitsTabState extends State<OrgJoinUnitsTab> {
  List<Map<String, dynamic>>? _units;
  List<Map<String, dynamic>> _mine = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final api = OrgApi.i.api;
    final rs = await Future.wait([
      orgCall(() => api.get('$_pub/${widget.orgId}/units'), quiet: true),
      orgCall(() => api.get('$_pub/me/unit-requests'), quiet: true),
    ]);
    if (!mounted) return;
    setState(() {
      _error = rs[0].ok ? null : orgErrorText(rs[0].error!);
      _units = rs[0].ok ? asMapList(rs[0].map['items']) : (_units ?? []);
      _mine = asMapList(rs[1].map['items']).where((x) => asInt(x['org_id']) == widget.orgId).toList();
    });
  }

  Map<String, dynamic>? _unitOf(Map<String, dynamic> req) {
    for (final u in _units ?? const <Map<String, dynamic>>[]) {
      if (u['unit_type'] == req['unit_type'] && asInt(u['unit_id']) == asInt(req['unit_id'])) return u;
    }
    return null;
  }

  Future<void> _open(Map<String, dynamic> unit) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => OrgUnitJoinScreen(orgId: widget.orgId, unit: unit)));
    if (changed == true) _load();
  }

  Future<void> _byCode() async {
    final code = TextEditingController();
    bool busy = false;
    String? err;
    await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final c = ctx.colors;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              SheetHeader(t('لدي كود انضمام', 'I have a join code')),
              Text(t('الكود يخص إدارة أو قسماً واحداً. إن كان لها نموذج أهلية فافتحها من القائمة لتعبئته.',
                  'A code belongs to one unit. If that unit has an eligibility form, open it from the list to fill it in.'),
                  style: orgText(ctx, size: 12.5, color: c.textMedium)),
              const SizedBox(height: 10),
              TextField(
                controller: code,
                textCapitalization: TextCapitalization.characters,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(hintText: 'ABCD234567', errorText: err, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
              ),
              const SizedBox(height: 12),
              AppButton.primary(
                busy: busy,
                label: t('انضمام', 'Join'),
                onPressed: () async {
                  if (code.text.trim().length < 4) return set(() => err = t('أدخل الكود', 'Enter the code'));
                  set(() {
                    busy = true;
                    err = null;
                  });
                  final r = await orgCall(() => OrgApi.i.api.post('$_pub/units/join-by-code', body: {'code': code.text.trim(), 'answers': <String, dynamic>{}}),
                      quiet: true);
                  if (!ctx.mounted) return;
                  set(() => busy = false);
                  if (!r.ok) {
                    final reasons = asMapList(r.detail['reasons']);
                    final field = r.detail['field'] != null || const {'field_required', 'field_option', 'field_number', 'field_email'}.contains(r.code);
                    return set(() => err = [
                          orgErrorText(r.error!),
                          for (final x in reasons) joinReasonText(x),
                          if (field) t('افتح الوحدة من القائمة لتعبئة النموذج.', 'Open the unit from the list to fill in its form.'),
                        ].join(' — '));
                  }
                  Navigator.pop(ctx);
                  final joined = r.map['joined'] == true;
                  toast(joined
                      ? t('انضممت إلى ${orgNameOf(asMap(r.map['unit']))} 🎉', 'You joined ${orgNameOf(asMap(r.map['unit']))} 🎉')
                      : r.map['code_verified'] == true
                          ? t('تم التحقق من الكود — طلبك بانتظار الموافقة', 'Code verified — request submitted, awaiting approval')
                          : t('أُرسل طلبك وهو قيد المراجعة', 'Your request was sent and is being reviewed'));
                  _load();
                },
              ),
            ]),
          );
        }));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final units = _units;
    if (units == null) return const OrgAsync(loading: true, failed: false, onRetry: _noop, child: SizedBox.shrink());
    final service = units.where((u) => u['unit_type'] == 'dept').toList();
    final academic = units.where((u) => u['unit_type'] == 'program').toList();
    Widget card(Map<String, dynamic> u) {
      final pol = asMap(u['policy']);
      final my = u['my_status'] as String?;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: OrgActionCard(
          icon: unitKindIcon('${u['unit_type']}'),
          color: my == 'member' ? c.success : (u['full'] == true ? c.textLight : c.primary),
          title: orgNameOf(u),
          subtitle: [
            joinPathsText(pol),
            if (my == 'member') t('أنت عضو ✓', 'You are a member ✓'),
            if (my == 'pending') t('طلبك قيد المراجعة', 'Your request is pending'),
            if (u['full'] == true && my == null) t('اكتمل العدد', 'Full'),
          ].where((x) => x.isNotEmpty).join(' · '),
          onTap: () => _open(u),
        ),
      );
    }

    return AppRefresh(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(top: 8, bottom: 40), children: [
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _banner(context, Icons.error_outline_rounded, c.danger, _error!)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: OrgActionCard(
            icon: Icons.vpn_key_rounded,
            color: c.accent2,
            title: t('لدي كود انضمام', 'I have a join code'),
            subtitle: t('من إدارة أو قسم علمي', 'From a department or academic department'),
            onTap: _byCode,
          ),
        ),
        if (units.isEmpty && _error == null)
          OrgEmpty(icon: Icons.apartment_rounded, title: t('لا يوجد ما يمكن الانضمام إليه الآن', 'Nothing to join right now')),
        if (academic.isNotEmpty) ...[
          OrgSectionTitle(t('الأقسام العلمية', 'Academic departments'), subtitle: t('قسم واحد لكل طالب', 'One per student')),
          for (final u in academic) card(u),
        ],
        if (service.isNotEmpty) ...[
          OrgSectionTitle(t('الإدارات والخدمات', 'Service departments'), subtitle: t('الإرشاد، شؤون الطلاب، الكنترول…', 'Advising, student affairs, exams…')),
          for (final u in service) card(u),
        ],
        if (_mine.isNotEmpty) ...[
          OrgSectionTitle(t('طلباتي', 'My requests')),
          for (final r in _mine)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: RowCard(
                child: Row(children: [
                  IconBadge(unitKindIcon('${r['unit_type']}'), statusColor(context, '${r['status']}'), size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_unitOf(r) == null ? unitKindLabel('${r['unit_type']}') : orgNameOf(_unitOf(r)), style: orgText(context, w: FontWeight.w800)),
                      Text(relTime(r['created_at']), style: orgText(context, size: 12, color: c.textMedium)),
                      if (r['status'] == 'pending' && r['needs_verification'] == true)
                        Text(t('ينتظر التحقق من بياناتك', 'Waiting for your data to be verified'), style: orgText(context, size: 12, color: c.warning)),
                      if ('${r['note'] ?? ''}'.isNotEmpty) Text('💬 ${r['note']}', style: orgText(context, size: 12.5)),
                    ]),
                  ),
                  StatusChip(requestStatusLabels()['${r['status']}'] ?? '${r['status']}', statusColor(context, '${r['status']}')),
                  if (r['status'] == 'pending')
                    IconButton(
                      tooltip: t('إلغاء الطلب', 'Cancel request'),
                      icon: Icon(Icons.cancel_outlined, color: c.danger),
                      onPressed: () async {
                        if (!await confirm(context, message: t('إلغاء طلب الانضمام؟', 'Cancel this join request?'), danger: true)) return;
                        final res = await orgCall(() => OrgApi.i.api.post('$_pub/me/unit-requests/${r['id']}/cancel'), ok: t('أُلغي الطلب', 'Request cancelled'));
                        if (res.ok || res.code == 'not_pending') _load();
                      },
                    ),
                ]),
              ),
            ),
        ],
      ]),
    );
  }
}

void _noop() {}

class OrgUnitJoinScreen extends StatefulWidget {
  const OrgUnitJoinScreen({super.key, required this.orgId, required this.unit});
  final int orgId;
  final Map<String, dynamic> unit;

  @override
  State<OrgUnitJoinScreen> createState() => _OrgUnitJoinScreenState();
}

class _OrgUnitJoinScreenState extends State<OrgUnitJoinScreen> {
  final _answers = OrgFormAnswers();
  final _code = TextEditingController();
  bool _busy = false, _changed = false;
  String? _codeError, _error;
  Map<String, String> _fieldErrors = {};
  Map<String, dynamic>? _check;     // eligibility dry run
  Map<String, dynamic>? _done;      // join response

  Map<String, dynamic> get _policy => asMap(widget.unit['policy']);
  List<Map<String, dynamic>> get _fields => asMapList(_policy['fields']);
  String get _base => '$_pub/${widget.orgId}/units/${widget.unit['unit_type']}/${widget.unit['unit_id']}';
  String? get _my => widget.unit['my_status'] as String?;

  @override
  void dispose() {
    _answers.dispose();
    _code.dispose();
    super.dispose();
  }

  bool _validateLocal() {
    _answers.collect(_fields);
    final miss = _answers.missing(_fields);
    setState(() {
      _fieldErrors = {for (final k in miss) k: t('مطلوب', 'Required')};
      _codeError = unitNeedsCode(_policy) && _code.text.trim().isEmpty ? t('أدخل الكود', 'Enter the code') : null;
    });
    return miss.isEmpty && _codeError == null;
  }

  void _applyError(OrgCall r) {
    final d = r.detail;
    final field = d['field']?.toString();
    setState(() {
      _error = orgErrorText(r.error!);
      if (field != null) _fieldErrors = {field: _error!};
      if ('${r.code}'.startsWith('code_') || r.code == 'bad_code' || r.code == 'too_many_attempts') _codeError = _error;
      if (d['reasons'] is List) _check = {'status': 'ineligible', 'reasons': d['reasons']};
    });
  }

  Future<void> _dryRun() async {
    if (!_validateLocal()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await orgCall(() => OrgApi.i.api.post('$_base/eligibility', body: {'answers': _answers.collect(_fields)}), quiet: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      setState(() => _check = r.map);
    } else {
      _applyError(r);
    }
  }

  Future<void> _join() async {
    if (_busy || !_validateLocal()) return;     // no double submit
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await orgCall(
        () => OrgApi.i.api.post('$_base/join', body: {
              'answers': _answers.collect(_fields),
              if (unitAcceptsCode(_policy) && _code.text.trim().isNotEmpty) 'code': _code.text.trim(),
            }),
        quiet: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      setState(() {
        _done = r.map;
        _changed = true;
      });
    } else {
      _applyError(r);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final u = widget.unit;
    final pol = _policy;
    final method = '${pol['method']}';
    final done = _done;
    final full = u['full'] == true;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: BasePage(
        useWebCard: true,
        maxWith: 720,
        appBar: ScreenAppBar(title: orgNameOf(u)),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
          RowCard(
            child: Row(children: [
              IconBadge(unitKindIcon('${u['unit_type']}'), c.primary, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(orgNameOf(u), style: orgText(context, size: 16, w: FontWeight.w800)),
                  Text('${unitKindLabel('${u['unit_type']}')} · ${joinPathsText(pol)}', style: orgText(context, size: 12.5, color: c.textMedium)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          if (done != null)
            _result(context, done)
          else if (_my == 'member')
            _banner(context, Icons.check_circle_rounded, c.success, t('أنت عضو في هذه الوحدة بالفعل.', 'You are already a member of this unit.'))
          else if (_my == 'pending')
            _banner(context, Icons.hourglass_top_rounded, c.warning, t('طلبك قيد المراجعة — ستصلك النتيجة عند القرار.', 'Your request is being reviewed — you\'ll be told when it\'s decided.'))
          else if (full)
            _banner(context, Icons.block_rounded, c.danger, t('اكتمل العدد في هذه الوحدة.', 'This unit is full.'))
          else ...[
            _banner(
                context,
                Icons.info_outline_rounded,
                c.primary,
                joinPathsOf(pol).length > 1
                    ? t('يمكنك الانضمام بأي طريقة متاحة: ${joinPathsText(pol)}. أدخل الكود إن كان لديك.',
                        'You can join any available way: ${joinPathsText(pol)}. Enter the code if you have one.')
                    : switch (method) {
                  'auto' => t('إذا انطبقت عليك الشروط تنضم مباشرة بعد تحقق الخادم.', 'If you meet the conditions you join right away, after the server checks.'),
                  'approval' => t('يُرسل طلبك للمسؤول ليقبله أو يرفضه، وتصلك النتيجة.', 'Your request goes to the person in charge, who accepts or rejects it — you\'ll be told.'),
                  'code' => t('تحتاج كود الانضمام الذي أعطته لك الإدارة.', 'You need the join code the department gave you.'),
                  'code_req' => t('تحتاج كود الانضمام وموافقة المسؤول معاً: الكود الصحيح يرسل طلبك، ثم يقرر المسؤول.',
                      'You need the join code AND an approval: a valid code sends your request, then the person in charge decides.'),
                  _ => '',
                }),
            if (_fields.isNotEmpty) ...[
              OrgSectionTitle(t('بيانات الأهلية', 'Eligibility details'), padding: const EdgeInsets.fromLTRB(4, 6, 4, 6)),
              Text(t('تُقارن إجاباتك بسجلك لدى المؤسسة، والقرار النهائي للخادم.', 'Your answers are compared with your record at the institution; the server decides.'),
                  style: orgText(context, size: 12, color: c.textLight)),
              const SizedBox(height: 8),
              for (final f in _fields)
                OrgDynamicField(
                  field: f,
                  answers: _answers,
                  error: _fieldErrors['${f['key']}'],
                  onChanged: () => setState(() {
                    _check = null;
                    _fieldErrors.remove('${f['key']}');
                  }),
                  onUpload: () => orgPickAndUpload('$_pub/uploads'),
                ),
            ],
            if (unitAcceptsCode(pol)) ...[
              const SizedBox(height: 6),
              TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                textDirection: TextDirection.ltr,
                onChanged: (_) => setState(() => _codeError = null),
                decoration: InputDecoration(
                  labelText: unitNeedsCode(pol) ? t('كود الانضمام', 'Join code') : t('كود الانضمام (اختياري)', 'Join code (optional)'),
                  errorText: _codeError,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (_check != null) _checkCard(context, _check!),
            if (_error != null && _check == null) _banner(context, Icons.error_outline_rounded, c.danger, _error!),
            const SizedBox(height: 6),
            if (_fields.isNotEmpty)
              OutlinedButton.icon(
                onPressed: _busy ? null : _dryRun,
                icon: const Icon(Icons.rule_rounded),
                label: Text(t('هل أستطيع الانضمام؟', 'Can I join?')),
              ),
            const SizedBox(height: 8),
            AppButton.primary(
              busy: _busy,
              label: unitNeedsApproval(pol) ? t('إرسال الطلب', 'Send request') : t('انضمام', 'Join'),
              onPressed: _busy || _check?['status'] == 'ineligible' ? null : _join,
            ),
          ],
        ]),
      ),
    );
  }

  Widget _checkCard(BuildContext context, Map<String, dynamic> r) {
    final c = context.colors;
    final st = '${r['status']}';
    final reasons = asMapList(r['reasons']);
    final (IconData icon, Color col, String text) = switch (st) {
      'eligible' => (Icons.check_circle_rounded, c.success, t('تنطبق عليك الشروط حالياً — أرسل لتأكيد الانضمام.', 'You meet the conditions now — send to confirm.')),
      'needs_verification' => (Icons.fact_check_rounded, c.warning,
          t('يمكنك الإرسال، لكن بعض بياناتك غير مسجّلة لدى المؤسسة فسيتحقق منها مسؤول أولاً.', 'You can send it, but some of your data isn\'t on record, so a staff member verifies it first.')),
      _ => (Icons.block_rounded, c.danger, t('لا تنطبق عليك الشروط:', 'You don\'t meet the conditions:')),
    };
    return _banner(context, icon, col, [text, for (final x in reasons) '• ${joinReasonText(x)}'].join('\n'));
  }

  Widget _result(BuildContext context, Map<String, dynamic> r) {
    final c = context.colors;
    final joined = r['joined'] == true;
    final req = asMap(r['request']);
    final verify = req['needs_verification'] == true;
    return Column(children: [
      IconBadge(joined ? Icons.celebration_rounded : Icons.hourglass_top_rounded, joined ? c.success : c.warning, size: 64),
      const SizedBox(height: 12),
      Text(
          joined
              ? t('تم الانضمام 🎉', 'You\'re in 🎉')
              : r['code_verified'] == true
                  ? t('تم التحقق من الكود — طلبك بانتظار الموافقة', 'Code verified — request submitted, awaiting approval')
                  : t('أُرسل طلبك', 'Your request was sent'),
          style: orgText(context, size: 18, w: FontWeight.w800), textAlign: TextAlign.center),
      const SizedBox(height: 6),
      Text(
          joined
              ? (widget.unit['unit_type'] == 'program'
                  ? t('أصبح هذا قسمك العلمي.', 'This is now your academic department.')
                  : t('أصبحت عضواً في هذه الإدارة.', 'You are now a member of this department.'))
              : verify
                  ? t('بعض بياناتك غير مسجّلة لدى المؤسسة، لذا سيتحقق منها مسؤول ثم يقرر. تابع الحالة من "طلباتي".',
                      'Some of your data isn\'t on record, so a staff member will verify it, then decide. Follow it in "My requests".')
                  : t('سيراجعه المسؤول وتصلك النتيجة. تابع الحالة من "طلباتي".', 'The person in charge will review it and you\'ll be told. Follow it in "My requests".'),
          textAlign: TextAlign.center,
          style: orgText(context, color: c.textMedium)),
      const SizedBox(height: 16),
      AppButton.primary(busy: false, label: t('تم', 'Done'), onPressed: () => Navigator.of(context).pop(true)),
    ]);
  }
}
