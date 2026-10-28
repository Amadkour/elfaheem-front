// lib/features/org/governance/gov_council_settings.dart — a council's settings: the regular session (day of month,
// time, cut-off, voting deadline), the tally rules (quorum, tie, abstentions, non-voters), holidays, the chair,
// the timezone and the head's pre-processing rules (auto agenda). ONE object, saved whole with
// `PUT …/councils/{cid}/settings` (spec §5, D-057).
//
//   GovCouncilSettingsForm   presentational (plain values + callbacks) — tested by the layout harness
//   VoteRulePreview          the tally rules applied live to an editable sample (VoteTally.compute)
//   GovCouncilSettingsPage   the thin network page around the form
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/context_switcher.dart' show ContextExitButton;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show asInt, asMap, t;
import '../org_ui.dart' show orgText;
import '../org_v3.dart' show orgCall, orgDay;
import 'gov_api.dart';
import 'gov_council_ui.dart';
import 'gov_models.dart';

/// Which part of the settings a form shows: the session & tally rules, the head's auto-agenda rules, or both.
enum GovSettingsSection { all, session, rules }

String tieRuleHelp(String v) => switch (v) {
      'chair' => t('عند تساوي الأصوات يحسم صوت رئيس المجلس؛ إن لم يصوّت فالبند مرفوض.', "On a tie the chair's own vote decides; a chair who did not vote means rejected."),
      'postpone' => t('عند تساوي الأصوات يؤجَّل البند إلى الجلسة الدورية التالية.', 'On a tie the item is postponed to the next regular session.'),
      _ => t('عند تساوي الأصوات يُعدّ البند مرفوضاً.', 'On a tie the item counts as rejected.'),
    };

String holidayRuleHelp(String v) => v == 'next_week'
    ? t('إذا صادف موعد الجلسة عطلة تُعقد بعد أسبوع.', 'A session that falls on a holiday is held a week later.')
    : t('إذا صادف موعد الجلسة عطلة تُعقد في اليوم التالي.', 'A session that falls on a holiday is held the next day.');

class GovCouncilSettingsForm extends StatefulWidget {
  const GovCouncilSettingsForm({
    super.key,
    required this.settings,
    required this.onSave,
    this.members = const {},
    this.categories = const {},
    this.section = GovSettingsSection.all,
    this.busy = false,
    this.canEdit = true,
    this.headName,
  });

  final CouncilSettings settings;
  final void Function(CouncilSettings) onSave;

  /// Chair candidates: user id → name (the council entity's team).
  final Map<int, String> members;

  /// Category id → name of the parent department (the auto-agenda rules).
  final Map<int, String> categories;
  final GovSettingsSection section;
  final bool busy, canEdit;

  /// The entity head — the chair when none is chosen.
  final String? headName;

  @override
  State<GovCouncilSettingsForm> createState() => _GovCouncilSettingsFormState();
}

class _GovCouncilSettingsFormState extends State<GovCouncilSettingsForm> {
  late CouncilSettings _s = widget.settings.copy();
  late final _cutoff = TextEditingController(text: '${_s.cutoffDays}');
  late final _deadline = TextEditingController(text: '${_s.votingDeadlineHours}');
  late final _tz = TextEditingController(text: _s.timezone ?? '');

  bool get _session => widget.section != GovSettingsSection.rules;
  bool get _rules => widget.section != GovSettingsSection.session;

  @override
  void didUpdateWidget(covariant GovCouncilSettingsForm old) {
    super.didUpdateWidget(old);
    if (!identical(old.settings, widget.settings)) {
      _s = widget.settings.copy();
      _cutoff.text = '${_s.cutoffDays}';
      _deadline.text = '${_s.votingDeadlineHours}';
      _tz.text = _s.timezone ?? '';
    }
  }

  @override
  void dispose() {
    _cutoff.dispose();
    _deadline.dispose();
    _tz.dispose();
    super.dispose();
  }

  void _set(VoidCallback fn) {
    if (!widget.canEdit) return;
    setState(fn);
  }

  Future<void> _pickTime() async {
    final p = _s.sessionTime.split(':');
    final tm = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(p[0]) ?? 10, minute: p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0),
    );
    if (tm == null || !mounted) return;
    _set(() => _s.sessionTime = '${tm.hour.toString().padLeft(2, '0')}:${tm.minute.toString().padLeft(2, '0')}');
  }

  Future<void> _addHoliday() async {
    final d = await showDatePicker(context: context, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime(2100), initialDate: DateTime.now());
    if (d == null || !mounted) return;
    final day = orgDay(DateTime.utc(d.year, d.month, d.day));
    _set(() => _s.holidays = {..._s.holidays, day}.toList()..sort());
  }

  CouncilSettings _collect() {
    _s.cutoffDays = (int.tryParse(_cutoff.text.trim()) ?? _s.cutoffDays).clamp(0, 30);
    _s.votingDeadlineHours = (int.tryParse(_deadline.text.trim()) ?? _s.votingDeadlineHours).clamp(1, 24 * 30);
    final tz = _tz.text.trim();
    _s.timezone = tz.isEmpty ? null : tz;
    return _s.copy();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_session) ...[
        _Block(
          title: t('الجلسة الدورية', 'Regular session'),
          icon: Icons.event_repeat_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppDropdown<int>(
              value: _s.sessionDay ?? 0,
              decoration: InputDecoration(labelText: t('يوم الجلسة في الشهر', 'Session day of the month')),
              items: [
                DropdownMenuItem(value: 0, child: Text(t('بدون جلسة دورية', 'No regular session'))),
                for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text(t('يوم $d من كل شهر', 'Day $d of every month'))),
              ],
              onChanged: widget.canEdit ? (v) => _set(() => _s.sessionDay = (v ?? 0) == 0 ? null : v) : null,
            ),
            const SizedBox(height: 12),
            _TapField(
              label: t('وقت الجلسة', 'Session time'),
              value: AppTime.clock(_s.sessionTime),
              icon: Icons.schedule_rounded,
              onTap: widget.canEdit ? _pickTime : null,
            ),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: AppField(controller: _cutoff, label: t('إقفال الجدول قبل (أيام)', 'Agenda cut-off (days before)'), keyboard: TextInputType.number, ltr: true)),
              const SizedBox(width: 10),
              Expanded(child: AppField(controller: _deadline, label: t('مهلة التصويت (ساعات)', 'Voting deadline (hours)'), keyboard: TextInputType.number, ltr: true)),
            ]),
            Text(
              t('يُجمَّع جدول الأعمال قبل الجلسة بأيام الإقفال، ويُفتح التصويت في موعد الجلسة ويُغلق بعد المهلة تلقائياً.',
                  'The agenda is compiled the cut-off days before the session; voting opens at the session time and closes by itself after the deadline.'),
              style: orgText(context, size: 12, color: c.textMedium),
            ),
            if (_s.sessionDay != null) ...[
              const SizedBox(height: 8),
              AppBanner(
                icon: Icons.event_available_rounded,
                text: t('الجلسة الدورية القادمة: ${govWhen(nextRegularDate(_s.sessionDay!, _s.sessionTime))}', 'Next regular session: ${govWhen(nextRegularDate(_s.sessionDay!, _s.sessionTime))}'),
              ),
            ],
          ]),
        ),
        _Block(
          title: t('قواعد الاحتساب', 'Tally rules'),
          icon: Icons.rule_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('النصاب: ${_s.quorumPct}% من الأعضاء', 'Quorum: ${_s.quorumPct}% of the members'), style: orgText(context, w: FontWeight.w800)),
            Slider(
              value: _s.quorumPct.toDouble(),
              min: 0,
              max: 100,
              divisions: 20,
              label: '${_s.quorumPct}%',
              onChanged: widget.canEdit ? (v) => _set(() => _s.quorumPct = v.round()) : null,
            ),
            Text(t('إن صوّت أقل من النصاب لا يُحتسب البند ويُرحَّل إلى الجلسة التالية.', 'When fewer than the quorum vote, the item is not counted and carries to the next session.'),
                style: orgText(context, size: 12, color: c.textMedium)),
            const SizedBox(height: 12),
            _Choice(
              label: t('عند التعادل', 'On a tie'),
              options: {for (final r in tieRules) r: tieRuleLabel(r)},
              value: _s.tieRule,
              help: tieRuleHelp(_s.tieRule),
              onChanged: widget.canEdit ? (v) => _set(() => _s.tieRule = v) : null,
            ),
            AppSwitchTile(
              title: t('الامتناع يُحتسب في المقام', 'Abstentions count in the denominator'),
              subtitle: t('النسبة = الموافقون ÷ (موافق + رافض + ممتنع)', 'Percentage = approve ÷ (approve + reject + abstain)'),
              value: _s.abstainCounts,
              onChanged: widget.canEdit ? (v) => _set(() => _s.abstainCounts = v) : null,
            ),
            AppSwitchTile(
              title: t('من لم يصوّت يُعدّ ممتنعاً', 'Non-voters count as abstaining'),
              subtitle: _s.noVoteRule == 'abstain' ? noVoteRuleLabel('abstain') : noVoteRuleLabel('ignore'),
              value: _s.noVoteRule == 'abstain',
              onChanged: widget.canEdit ? (v) => _set(() => _s.noVoteRule = v ? 'abstain' : 'ignore') : null,
            ),
            const SizedBox(height: 8),
            VoteRulePreview(settings: _s),
          ]),
        ),
        _Block(
          title: t('العطلات', 'Holidays'),
          icon: Icons.beach_access_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final h in _s.holidays)
                InputChip(
                  label: Text(h, textDirection: TextDirection.ltr, style: orgText(context, size: 12, w: FontWeight.w700)),
                  onDeleted: widget.canEdit ? () => _set(() => _s.holidays = [..._s.holidays]..remove(h)) : null,
                ),
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 18),
                label: Text(t('إضافة تاريخ', 'Add a date'), style: orgText(context, size: 12, w: FontWeight.w700)),
                onPressed: widget.canEdit ? _addHoliday : null,
              ),
            ]),
            if (_s.holidays.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(t('لا عطلات مسجّلة', 'No holidays yet'), style: orgText(context, size: 12, color: c.textMedium)),
              ),
            const SizedBox(height: 12),
            _Choice(
              label: t('إذا صادفت الجلسة عطلة', 'When the session falls on a holiday'),
              options: {for (final r in holidayRules) r: holidayRuleLabel(r)},
              value: _s.holidayRule,
              help: holidayRuleHelp(_s.holidayRule),
              onChanged: widget.canEdit ? (v) => _set(() => _s.holidayRule = v) : null,
            ),
          ]),
        ),
        _Block(
          title: t('الرئاسة والمنطقة الزمنية', 'Chair and timezone'),
          icon: Icons.person_pin_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppDropdown<int>(
              value: _s.chairUserId ?? 0,
              decoration: InputDecoration(labelText: t('رئيس المجلس', 'Council chair')),
              items: [
                DropdownMenuItem(value: 0, child: Text(widget.headName == null || widget.headName!.isEmpty ? t('رئيس الجهة', 'The entity head') : t('رئيس الجهة (${widget.headName})', 'The entity head (${widget.headName})'))),
                for (final e in widget.members.entries)
                  if (e.key != 0) DropdownMenuItem(value: e.key, child: Text(e.value)),
                if (_s.chairUserId != null && _s.chairUserId != 0 && !widget.members.containsKey(_s.chairUserId))
                  DropdownMenuItem(value: _s.chairUserId, child: Text(t('العضو #${_s.chairUserId}', 'Member #${_s.chairUserId}'))),
              ],
              onChanged: widget.canEdit ? (v) => _set(() => _s.chairUserId = (v ?? 0) == 0 ? null : v) : null,
            ),
            const SizedBox(height: 12),
            AppField(controller: _tz, label: t('المنطقة الزمنية', 'Timezone'), hint: t('فارغ = منطقة المؤسسة، مثل Africa/Cairo', 'Empty = the organization zone, e.g. Africa/Cairo'), ltr: true),
          ]),
        ),
      ],
      if (_rules)
        _Block(
          title: t('المعالجة المسبقة لرئيس القسم', "The head's pre-processing"),
          icon: Icons.auto_awesome_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppSwitchTile(
              title: t('جدول الأعمال التلقائي', 'Automatic agenda'),
              subtitle: t('تُنشأ الجلسة الدورية ويُجمَّع جدولها ويُفتح التصويت ويُغلق تلقائياً', 'The regular session is created, its agenda compiled, voting opened and closed by itself'),
              value: _s.autoAgenda,
              onChanged: widget.canEdit ? (v) => _set(() => _s.autoAgenda = v) : null,
            ),
            const SizedBox(height: 6),
            AppBanner(
              icon: Icons.alt_route_rounded,
              text: t('المعاملات من هذه الأنواع أو التصنيفات التي تصل إلى القسم تُحال إلى المجلس للتصويت تلقائياً دون انتظار رئيس القسم.',
                  'Items of these types or categories that arrive at the department are routed to the council for a vote automatically, without waiting for the head.'),
            ),
            const SizedBox(height: 12),
            Text(t('الأنواع', 'Types'), style: orgText(context, size: 12.5, color: c.textLight)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final ty in itemTypes)
                FilterChip(
                  label: Text(itemTypeLabel(ty), style: orgText(context, size: 12, w: FontWeight.w700)),
                  selected: _s.autoAgendaTypes.contains(ty),
                  onSelected: widget.canEdit
                      ? (on) => _set(() => _s.autoAgendaTypes = on ? [..._s.autoAgendaTypes, ty] : ([..._s.autoAgendaTypes]..remove(ty)))
                      : null,
                ),
            ]),
            const SizedBox(height: 12),
            Text(t('التصنيفات', 'Categories'), style: orgText(context, size: 12.5, color: c.textLight)),
            const SizedBox(height: 6),
            if (widget.categories.isEmpty)
              Text(t('لا تصنيفات في القسم بعد — كل التصنيفات مشمولة', 'The department has no categories yet — every category is included'), style: orgText(context, size: 12, color: c.textMedium))
            else
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final e in widget.categories.entries)
                  FilterChip(
                    label: Text(e.value, style: orgText(context, size: 12, w: FontWeight.w700)),
                    selected: _s.autoAgendaCategoryIds.contains(e.key),
                    onSelected: widget.canEdit
                        ? (on) => _set(() => _s.autoAgendaCategoryIds = on ? [..._s.autoAgendaCategoryIds, e.key] : ([..._s.autoAgendaCategoryIds]..remove(e.key)))
                        : null,
                  ),
              ]),
            const SizedBox(height: 4),
            Text(t('قائمة فارغة = لا قيد على هذا المحور', 'An empty list = no restriction on that axis'), style: orgText(context, size: 11.5, color: c.textLight)),
          ]),
        ),
      if (widget.canEdit)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: AppPrimaryButton(
            label: t('حفظ الإعدادات', 'Save settings'),
            icon: Icons.save_rounded,
            busy: widget.busy,
            onPressed: widget.busy ? null : () => widget.onSave(_collect()),
          ),
        ),
    ]);
  }
}

/// A titled card of the form.
class _Block extends StatelessWidget {
  const _Block({required this.title, required this.icon, required this.child});
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: c.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: orgText(context, size: 15, w: FontWeight.w800))),
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      ),
    );
  }
}

/// Field-looking row that opens a picker on tap.
class _TapField extends StatelessWidget {
  const _TapField({required this.label, required this.value, required this.icon, this.onTap});
  final String label, value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: InputDecorator(
          isEmpty: value.isEmpty,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, color: c.textLight),
            suffixIcon: Icon(Icons.edit_rounded, color: c.textLight, size: 18),
            enabled: onTap != null,
          ),
          child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, w: FontWeight.w700)),
        ),
      ),
    );
  }
}

/// One-of-N chips with an explanation of the chosen option under them.
class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.options, required this.value, required this.onChanged, this.help});
  final String label, value;
  final Map<String, String> options;
  final ValueChanged<String>? onChanged;
  final String? help;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: orgText(context, size: 12.5, color: c.textLight)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final e in options.entries)
            AppChoiceChip(label: e.value, selected: e.key == value, onTap: () => onChanged?.call(e.key)),
        ]),
        if (help != null) ...[
          const SizedBox(height: 6),
          Text(help!, style: orgText(context, size: 12, color: c.textMedium)),
        ],
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Rule preview
// ═════════════════════════════════════════════════════════════════════════════

/// The tally rules on an editable sample: eligible · approve · reject · abstain (+ the chair's vote for the chair
/// tie rule) → quorum, percentage and outcome, exactly as the server will count (VoteTally.compute).
class VoteRulePreview extends StatefulWidget {
  const VoteRulePreview({super.key, required this.settings, this.eligible = 9, this.approve = 4, this.reject = 3, this.abstain = 1});
  final CouncilSettings settings;
  final int eligible, approve, reject, abstain;

  @override
  State<VoteRulePreview> createState() => _VoteRulePreviewState();
}

class _VoteRulePreviewState extends State<VoteRulePreview> {
  late int _eligible = widget.eligible, _approve = widget.approve, _reject = widget.reject, _abstain = widget.abstain;
  String? _chair;

  int get _voted => _approve + _reject + _abstain;

  Widget _stepper(String label, int value, ValueChanged<int> set, {int min = 0, int? max, Color? color}) {
    final c = context.colors;
    return Row(children: [
      Expanded(child: Text(label, style: orgText(context, size: 12.5, w: FontWeight.w700, color: color))),
      IconButton(tooltip: t('تقليل', 'Decrease'), 
        visualDensity: VisualDensity.compact,
        onPressed: value > min ? () => set(value - 1) : null,
        icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
      ),
      SizedBox(width: 26, child: Text('$value', textAlign: TextAlign.center, style: orgText(context, size: 14, w: FontWeight.w800, color: c.textDark))),
      IconButton(tooltip: t('زيادة', 'Increase'), 
        visualDensity: VisualDensity.compact,
        onPressed: max == null || value < max ? () => set(value + 1) : null,
        icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = widget.settings;
    final tally = VoteTally.compute(approve: _approve, reject: _reject, abstain: _abstain, eligible: _eligible, s: s, chairVote: _chair);
    final col = agendaStatusColor(context, tally.outcome);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.primary.withValues(alpha: 0.18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.science_rounded, size: 18, color: c.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(t('معاينة القواعد', 'Rule preview'), style: orgText(context, size: 14, w: FontWeight.w800))),
        ]),
        Text(t('جرّب عيّنة لترى ما ستكون عليه النتيجة بهذه القواعد', 'Try a sample to see what these rules produce'), style: orgText(context, size: 11.5, color: c.textMedium)),
        const SizedBox(height: 8),
        _stepper(t('الأعضاء المؤهلون', 'Eligible members'), _eligible, (v) => setState(() {
              _eligible = v;
              if (_voted > v) {
                _abstain = (v - _approve - _reject).clamp(0, v);
                if (_approve + _reject > v) _reject = (v - _approve).clamp(0, v);
                if (_approve > v) _approve = v;
              }
            }), min: 1),
        _stepper(voteLabel('approve'), _approve, (v) => setState(() => _approve = v), max: _eligible - _reject - _abstain, color: c.success),
        _stepper(voteLabel('reject'), _reject, (v) => setState(() => _reject = v), max: _eligible - _approve - _abstain, color: c.danger),
        _stepper(voteLabel('abstain'), _abstain, (v) => setState(() => _abstain = v), max: _eligible - _approve - _reject, color: c.textMedium),
        if (s.tieRule == 'chair') ...[
          const SizedBox(height: 6),
          Text(t('صوت الرئيس (في العيّنة)', "The chair's vote (in the sample)"), style: orgText(context, size: 12, color: c.textLight)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: [
            AppChoiceChip(label: t('لم يصوّت', 'Did not vote'), selected: _chair == null, onTap: () => setState(() => _chair = null)),
            AppChoiceChip(label: voteLabel('approve'), selected: _chair == 'approve', onTap: () => setState(() => _chair = 'approve')),
            AppChoiceChip(label: voteLabel('reject'), selected: _chair == 'reject', onTap: () => setState(() => _chair = 'reject')),
          ]),
        ],
        const SizedBox(height: 10),
        Divider(color: c.divider, height: 1),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AppBadgePill(voteOutcomeLabel(tally.outcome), color: col, icon: tally.quorumMet ? Icons.gavel_rounded : Icons.hourglass_empty_rounded),
          AppBadgePill(
            tally.quorumMet ? t('النصاب مكتمل: $_voted من ${tally.needed}', 'Quorum met: $_voted of ${tally.needed}') : t('النصاب غير مكتمل: $_voted من ${tally.needed}', 'No quorum: $_voted of ${tally.needed}'),
            color: tally.quorumMet ? c.success : c.warning,
          ),
          AppBadgePill(t('${tally.approvePct.toStringAsFixed(0)}% موافقة', '${tally.approvePct.toStringAsFixed(0)}% approve'), color: c.primary),
        ]),
        const SizedBox(height: 8),
        AppProgressBar(value: tally.approvePct, color: col),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

/// Loads the council, its team (chair candidates) and the parent department's categories, shows the form and
/// saves the whole object. [orgId] is only needed when no `OrgSession` sits above the page.
class GovCouncilSettingsPage extends StatefulWidget {
  const GovCouncilSettingsPage({super.key, required this.councilId, this.section = GovSettingsSection.all, this.orgId, this.embedded = false});
  final int councilId;
  final GovSettingsSection section;
  final int? orgId;

  /// Inside a tab (no app bar / BasePage of its own).
  final bool embedded;

  @override
  State<GovCouncilSettingsPage> createState() => _GovCouncilSettingsPageState();
}

class _GovCouncilSettingsPageState extends State<GovCouncilSettingsPage> {
  Council? _council;
  Map<int, String> _members = const {};
  Map<int, String> _categories = const {};
  bool _failed = false, _missing = false, _busy = false;

  int? get _orgId => govOrgId(context, widget.orgId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final oid = _orgId;
    if (oid == null) {
      setState(() => _failed = true);
      return;
    }
    final api = GovApi(oid);
    final r = await orgCall(() => api.council(widget.councilId), quiet: true);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _failed = true;
        _missing = r.endpointMissing;
      });
      return;
    }
    final council = r.data as Council;
    final team = await GovTeamApi(oid).team(council.dept.id) ?? const <Map<String, dynamic>>[];
    var cats = const <Category>[];
    if (council.parentDept != null) {
      final cr = await orgCall(() => api.categories(council.parentDept!.id), quiet: true);
      if (cr.ok) cats = (cr.data as List).cast<Category>();
    }
    if (!mounted) return;
    setState(() {
      _council = council;
      _failed = false;
      _members = {for (final m in team) asInt(asMap(m['user'])['id']): '${asMap(m['user'])['name'] ?? ''}'};
      _categories = {for (final c in cats) c.id: c.name};
    });
  }

  Future<void> _save(CouncilSettings s) async {
    final oid = _orgId;
    if (oid == null) return;
    setState(() => _busy = true);
    final r = await orgCall(() => GovApi(oid).saveCouncilSettings(widget.councilId, s), ok: t('تم حفظ الإعدادات', 'Settings saved'));
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    final council = _council;
    final Widget body;
    if (_missing) {
      body = const GovNeedsServer();
    } else if (council == null) {
      body = _failed
          ? AppEmpty(icon: Icons.error_outline_rounded, title: t('تعذّر التحميل', 'Could not load'), actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
          : const AppListSkeleton(items: 4, withAvatar: false);
    } else {
      final canEdit = council.can['manage'] || govIsOrgAdmin(context);
      body = SingleChildScrollView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!canEdit)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: AppBanner(icon: Icons.lock_outline_rounded, text: t('للاطلاع فقط — يعدّل الإعدادات رئيس المجلس أو مدير المؤسسة', 'Read-only — the chair or the organization admin edits these settings')),
            ),
          GovCouncilSettingsForm(
            settings: council.settings ?? CouncilSettings(),
            onSave: _save,
            members: _members,
            categories: _categories,
            section: widget.section,
            busy: _busy,
            canEdit: canEdit,
            headName: council.chair?.name,
          ),
        ]),
      );
    }
    if (widget.embedded) return body;
    return BasePage(
      useWebCard: true,
      maxWith: 900,
      appBar: ScreenAppBar(title: council?.name ?? t('إعدادات المجلس', 'Council settings'), actions: const [ContextExitButton()]),
      child: body,
    );
  }
}
