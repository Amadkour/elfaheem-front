// lib/features/org/governance/gov_council_s2.dart — Institutions S2 (D-965 – D-970) on the council screens: the
// result chip of an agenda row, the named results sheet, "Write an item", the meeting step and the roster card
// (member weights 1 – 3 under the 40 % cap, the secretary). Contract: docs/institutions/CONTRACT_S2.md.
//
// Every widget takes plain values and is pumped by test/org/institutions_s2_test.dart (layout harness):
//   AgendaResultChip · AgendaResultsView · WriteAgendaItemBody · GovMeetingStep · CouncilRosterCard
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show SheetHeader, t;
import '../org_unit_rules.dart' show CouncilSecretaryActingHint;
import 'gov_council_ui.dart';
import 'gov_institutions_s3.dart' show DecisionTemplate, DecisionTemplatePicker, WriteItemDraft;
import 'gov_models.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Result chip
// ═════════════════════════════════════════════════════════════════════════════

Color agendaResultColor(BuildContext context, String v) {
  final c = context.colors;
  return switch (v) {
    'approved_full' => c.success,
    'approved_partial' => c.success,
    'rejected' => c.danger,
    'no_quorum' => c.warning,
    'pending' => c.primary,
    _ => agendaStatusColor(context, v),
  };
}

IconData agendaResultIcon(String v) => switch (v) {
      'approved_full' => Icons.verified_rounded,
      'approved_partial' => Icons.check_circle_outline_rounded,
      'rejected' => Icons.cancel_outlined,
      'no_quorum' => Icons.group_off_rounded,
      'pending' => Icons.hourglass_top_rounded,
      'postponed' => Icons.update_rounded,
      _ => Icons.circle_outlined,
    };

/// The status chip of one agenda row: موافقة بالإجماع · موافقة بالأغلبية · رفض · لم يكتمل النصاب · قيد التصويت
/// (postponed and withdrawn keep their own labels). Tappable when [onTap] opens the results.
class AgendaResultChip extends StatelessWidget {
  const AgendaResultChip({super.key, required this.agenda, this.onTap});
  final AgendaItem agenda;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final v = agenda.chip;
    final pill = AppBadgePill(agendaResultLabel(v), color: agendaResultColor(context, v), icon: agendaResultIcon(v));
    if (onTap == null) return pill;
    return Semantics(
      button: true,
      label: t('عرض النتيجة', 'Show the result'),
      child: InkWell(borderRadius: BorderRadius.circular(AppRadius.chip), onTap: onTap, child: pill),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Named results
// ═════════════════════════════════════════════════════════════════════════════

/// The results of one row: the chip and the decision number, the weighted sums, then approved / rejected / not
/// responded (+ abstained when any), each name with its weight when not 1, the note and the time.
class AgendaResultsView extends StatelessWidget {
  const AgendaResultsView({super.key, required this.agenda});
  final AgendaItem agenda;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = agenda;
    final g = AgendaResultGroups.of(a);
    final w = a.weights;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(a.item.title, style: AppType.bodyStrong(context)),
      const SizedBox(height: AppSpace.xs),
      GovPillRow([
        AgendaResultChip(agenda: a),
        if (a.decisionNo != null) AppBadgePill(t('قرار رقم ${a.decisionNo}', 'Decision no. ${a.decisionNo}'), icon: Icons.tag_rounded, color: c.charcoal),
        if (a.coiCount > 0)
          AppBadgePill(
            countText(a.coiCount, ar1: 'عضو أعلن تعارض مصالح', ar2: 'عضوان أعلنا تعارض مصالح', arFew: '{n} أعضاء أعلنوا تعارض مصالح', arMany: '{n} عضواً أعلنوا تعارض مصالح', en1: '1 member declared a conflict', en: '{n} members declared a conflict'),
            icon: Icons.front_hand_rounded,
            color: c.purple,
          ),
      ]),
      if (w != null) ...[
        const SizedBox(height: AppSpace.sm),
        Text(
          t('الأوزان: موافق ${w.approveW} · رافض ${w.rejectW} · ممتنع ${w.abstainW} — صوّت ${w.votedW} من ${w.eligibleW}${w.neededW == null ? '' : ' (النصاب ${w.neededW})'}',
              'Weights: approve ${w.approveW} · reject ${w.rejectW} · abstain ${w.abstainW} — ${w.votedW} of ${w.eligibleW} voted${w.neededW == null ? '' : ' (quorum ${w.neededW})'}'),
          style: AppType.meta(context).copyWith(color: c.textMedium),
        ),
      ],
      if (!a.resultsVisible) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.visibility_off_outlined, text: t('تظهر الأسماء بعد إغلاق الجلسة', 'The names show once the session is closed')),
      ] else if (g.isEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        Text(t('لا أصوات بعد', 'No votes yet'), style: AppType.meta(context).copyWith(color: c.textMedium)),
      ] else ...[
        _Group(title: t('موافق', 'Approved'), icon: voteIcon('approve'), color: c.success, people: g.approved),
        _Group(title: t('رافض', 'Rejected'), icon: voteIcon('reject'), color: c.danger, people: g.rejected),
        if (g.abstained.isNotEmpty) _Group(title: t('ممتنع', 'Abstained'), icon: voteIcon('abstain'), color: c.textMedium, people: g.abstained),
        _Group(title: t('لم يصوّت', 'Not responded'), icon: Icons.schedule_rounded, color: c.warning, people: g.notResponded),
      ],
    ]);
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.icon, required this.color, required this.people});
  final String title;
  final IconData icon;
  final Color color;
  final List<AgendaVoter> people;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: AppIconSize.sm, color: color),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text('$title (${people.length})', style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: color))),
        ]),
        if (people.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: AppSpace.lg, top: AppSpace.xxs),
            child: Text(t('لا أحد', 'Nobody'), style: AppType.meta(context).copyWith(color: c.textLight)),
          ),
        for (final p in people)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppAvatar(name: p.name, url: p.user?.avatar, size: 28),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(p.name, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
                    if (p.weight != 1) AppBadgePill(t('وزن ${p.weight}', 'weight ${p.weight}'), color: c.primary),
                    if (p.at != null) Text(govWhen(p.at), style: AppType.meta(context).copyWith(color: c.textLight)),
                  ]),
                  if (p.note != null) Text(p.note!, style: AppType.meta(context).copyWith(color: c.textMedium)),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// The results sheet of one row. [fetch] reloads the row (`GET …/agenda/{aid}/results`); the row given is shown
/// meanwhile and when the reload fails.
Future<void> showAgendaResultsSheet(BuildContext context, AgendaItem agenda, {Future<AgendaItem?> Function()? fetch}) async {
  var shown = agenda;
  var asked = false;
  await showAppSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        if (!asked && fetch != null) {
          asked = true;
          fetch().then((a) {
            if (a != null && ctx.mounted) set(() => shown = a);
          });
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.md),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SheetHeader(t('نتيجة البند', 'Item result')),
            Flexible(child: SingleChildScrollView(child: AgendaResultsView(agenda: shown))),
          ]),
        );
      }));
}

// ═════════════════════════════════════════════════════════════════════════════
//  Write an item
// ═════════════════════════════════════════════════════════════════════════════

/// Title + text of an item the chair or secretary writes straight onto the agenda; with [templates] (S3, D-973) a
/// decision template pre-fills both and shows its suggested decision ([WriteItemDraft.pick] keeps typed text).
class WriteAgendaItemBody extends StatefulWidget {
  const WriteAgendaItemBody({super.key, required this.onSave, this.busy = false, this.templates = const []});
  final void Function(WriteItemDraft draft) onSave;
  final bool busy;
  final List<DecisionTemplate> templates;

  @override
  State<WriteAgendaItemBody> createState() => _WriteAgendaItemBodyState();
}

class _WriteAgendaItemBodyState extends State<WriteAgendaItemBody> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  DecisionTemplate? _template;

  WriteItemDraft get _draft => WriteItemDraft(title: _title.text, body: _body.text, template: _template);

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _pick(DecisionTemplate? tpl) {
    final d = _draft.pick(tpl);
    setState(() {
      _template = d.template;
      if (_title.text != d.title) _title.text = d.title;
      if (_body.text != d.body) _body.text = d.body;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final draft = _draft;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.templates.isNotEmpty) ...[
        DecisionTemplatePicker(templates: widget.templates, selected: _template, enabled: !widget.busy, onChanged: _pick),
        const SizedBox(height: AppSpace.sm),
      ],
      AppField(controller: _title, label: t('عنوان البند', 'Item title'), required: true, maxLength: 255),
      AppField(controller: _body, label: t('نص البند', 'Item text'), hint: t('ما المطلوب من المجلس؟', 'What is the council asked to decide?'), maxLines: 5),
      Text(t('يُضاف البند إلى جدول الأعمال ويصوّت عليه الأعضاء ومنهم كاتبه.', 'The item joins the agenda; every member votes on it, its writer too.'),
          style: AppType.meta(context).copyWith(color: c.textMedium)),
      const SizedBox(height: AppSpace.sm),
      AppPrimaryButton(
        label: t('إضافة إلى جدول الأعمال', 'Add to the agenda'),
        icon: Icons.edit_note_rounded,
        busy: widget.busy,
        onPressed: widget.busy || !draft.canSave ? null : () => widget.onSave(draft),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Meeting step (council settings)
// ═════════════════════════════════════════════════════════════════════════════

/// How the council meets: not set · online (an https link, or the platform's meeting room when empty) · in person
/// (a place). [onChanged] gets (mode, location, link) on every change.
class GovMeetingStep extends StatefulWidget {
  const GovMeetingStep({super.key, this.mode, this.location, this.link, this.enabled = true, required this.onChanged});
  final String? mode, location, link;
  final bool enabled;
  final void Function(String? mode, String? location, String? link) onChanged;

  @override
  State<GovMeetingStep> createState() => _GovMeetingStepState();
}

class _GovMeetingStepState extends State<GovMeetingStep> {
  late String? _mode = widget.mode;
  late final _location = TextEditingController(text: widget.location ?? '');
  late final _link = TextEditingController(text: widget.link ?? '');

  @override
  void initState() {
    super.initState();
    _location.addListener(_emit);
    _link.addListener(_emit);
  }

  @override
  void dispose() {
    _location.dispose();
    _link.dispose();
    super.dispose();
  }

  void _emit() {
    final loc = _location.text.trim(), link = AppUrlField.normalize(_link.text);
    widget.onChanged(_mode, loc.isEmpty ? null : loc, link.isEmpty ? null : link);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final link = AppUrlField.normalize(_link.text);
    final badLink = link.isNotEmpty && !link.toLowerCase().startsWith('https://');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final m in <String?>[null, ...meetingModes])
          AppChoiceChip(
            label: meetingModeLabel(m),
            selected: _mode == m,
            onTap: widget.enabled
                ? () {
                    setState(() => _mode = m);
                    _emit();
                  }
                : () {},
          ),
      ]),
      const SizedBox(height: AppSpace.sm),
      if (_mode == 'in_person') AppField(controller: _location, label: t('مكان الانعقاد', 'Where it meets'), hint: t('مثل: قاعة مجلس الكلية', 'e.g. the faculty council hall'), enabled: widget.enabled, maxLength: 255),
      if (_mode == 'online') ...[
        AppUrlField(controller: _link, label: t('رابط الاجتماع (اختياري)', 'Meeting link (optional)')),
        if (badLink) AppBanner(icon: Icons.link_off_rounded, color: c.danger, text: t('رابط الاجتماع يبدأ بـ https://', 'The meeting link starts with https://')),
      ],
      Text(
        switch (_mode) {
          'online' => t('تُنشأ لكل جلسة دعوة في تقويم الأعضاء؛ إن تركت الرابط فارغاً تُعقد في غرفة اجتماعات المنصة.',
              "Each session puts a meeting in the members' calendars; with no link it uses the platform's meeting room."),
          'in_person' => t('يظهر المكان في دعوة الجلسة في تقويم الأعضاء.', "The place shows on the session's calendar invitation."),
          _ => t('اختر طريقة الانعقاد لتصل الدعوة إلى تقويم الأعضاء.', "Choose how the council meets so the invitation reaches the members' calendars."),
        },
        style: AppType.meta(context).copyWith(color: c.textMedium),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Roster: weights + secretary
// ═════════════════════════════════════════════════════════════════════════════

/// The council's members with their vote weights (1 – 3) and the secretary. Read-only without `can.roster`.
/// [onSave] gets the weights when they changed (null otherwise) and the secretary (null = none).
class CouncilRosterCard extends StatefulWidget {
  const CouncilRosterCard({super.key, required this.roster, required this.onSave, this.busy = false, this.errors, this.errorBox});
  final CouncilRoster roster;
  final void Function(Map<int, int>? weights, int? secretaryUserId) onSave;
  final bool busy;

  /// The last save's field errors (UX v3): `secretary` marks the secretary field.
  final FieldErrors? errors;

  /// The last save's error card (with its one-tap fix), drawn above the Save button.
  final Widget? errorBox;

  @override
  State<CouncilRosterCard> createState() => _CouncilRosterCardState();
}

class _CouncilRosterCardState extends State<CouncilRosterCard> {
  late Map<int, int> _w = _weightsOf(widget.roster);
  late int? _secretary = widget.roster.secretaryUserId;

  static Map<int, int> _weightsOf(CouncilRoster r) => {for (final m in r.members) m.userId: m.weight};

  @override
  void didUpdateWidget(covariant CouncilRosterCard old) {
    super.didUpdateWidget(old);
    if (!identical(old.roster, widget.roster)) {
      _w = _weightsOf(widget.roster);
      _secretary = widget.roster.secretaryUserId;
    }
  }

  bool get _weightsChanged => widget.roster.members.any((m) => _w[m.userId] != m.weight);
  bool get _changed => _weightsChanged || _secretary != widget.roster.secretaryUserId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = widget.roster;
    final edit = r.canEdit;
    final total = _w.values.fold<int>(0, (a, b) => a + b);
    final capUser = weightCapUser(_w, capPct: r.capPct);
    final capName = capUser == null ? null : r.members.firstWhere((m) => m.userId == capUser).name;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppDropdown<int>(
        key: widget.errors?.keyFor('secretary'),
        value: _secretary ?? 0,
        decoration: InputDecoration(labelText: t('أمين المجلس', 'Council secretary'), errorText: widget.errors?.errorFor('secretary'), errorMaxLines: 3),
        items: [
          DropdownMenuItem(value: 0, child: Text(t('بدون أمين', 'No secretary'))),
          for (final m in r.members) DropdownMenuItem(value: m.userId, child: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: edit
            ? (v) {
                widget.errors?.clear('secretary');
                setState(() => _secretary = (v ?? 0) == 0 ? null : v);
              }
            : null,
      ),
      // Institutions v2 (D-982): no secretary yet, so the chair covers
      if (r.secretaryActing && _secretary == null) ...[
        const SizedBox(height: AppSpace.xs),
        const CouncilSecretaryActingHint(),
      ],
      const SizedBox(height: AppSpace.xxs),
      Text(t('للأمين صلاحيات الرئيس على هذا المجلس: الجلسات وجدول الأعمال والتذكير.', "The secretary has the chair's powers on this council: sessions, the agenda and reminders."),
          style: AppType.meta(context).copyWith(color: c.textMedium)),
      const SizedBox(height: AppSpace.sm),
      Text(t('أوزان التصويت (مجموعها $total)', 'Vote weights (total $total)'), style: AppType.label(context).copyWith(color: c.textLight)),
      if (r.members.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs),
          child: Text(t('لا أعضاء في المجلس بعد', 'The council has no members yet'), style: AppType.meta(context).copyWith(color: c.textMedium)),
        ),
      for (final m in r.members)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(m.name, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
              if (m.isChair) AppBadgePill(t('الرئيس', 'Chair'), color: c.primary),
              if (m.userId == _secretary) AppBadgePill(t('الأمين', 'Secretary'), color: c.purple),
            ]),
            const SizedBox(height: AppSpace.xxs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (var w = 1; w <= 3; w++)
                AppChoiceChip(
                  label: t('وزن $w', 'Weight $w'),
                  selected: _w[m.userId] == w,
                  onTap: edit ? () => setState(() => _w = {..._w, m.userId: w}) : () {},
                ),
            ]),
          ]),
        ),
      if (widget.errors?.errorFor('members') case final err?) ...[
        const SizedBox(height: AppSpace.xs),
        Text(err, key: widget.errors?.keyFor('members'), style: AppType.label(context).copyWith(color: c.danger)),
      ],
      if (capName != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(
          icon: Icons.balance_rounded,
          color: c.danger,
          text: t('وزن $capName يتجاوز ${r.capPct}٪ من مجموع الأوزان — خفّضه أو ارفع أوزان غيره.',
              "$capName holds more than ${r.capPct}% of the total weight — lower it or raise the others'."),
        ),
      ] else ...[
        const SizedBox(height: AppSpace.xs),
        Text(t('عند اختلاف الأوزان لا يتجاوز عضو واحد ${r.capPct}٪ من المجموع.', 'Once weights differ, no member may exceed ${r.capPct}% of the total.'),
            style: AppType.meta(context).copyWith(color: c.textMedium)),
      ],
      if (edit) ...[
        if (widget.errorBox != null) ...[
          const SizedBox(height: AppSpace.sm),
          widget.errorBox!,
        ],
        const SizedBox(height: AppSpace.sm),
        AppPrimaryButton(
          label: t('حفظ الأعضاء والأمين', 'Save members and secretary'),
          icon: Icons.save_rounded,
          busy: widget.busy,
          onPressed: widget.busy || !_changed || capName != null ? null : () => widget.onSave(_weightsChanged ? {..._w} : null, _secretary),
        ),
      ] else ...[
        const SizedBox(height: AppSpace.xs),
        Text(t('يحدد الأعضاء وأوزانهم والأمين مدير المؤسسة (مجلس الكلية) أو رئيس القسم.', "The organization admin (faculty council) or the department head sets the members, their weights and the secretary."),
            style: AppType.meta(context).copyWith(color: c.textLight)),
      ],
    ]);
  }
}

/// The plain-words text of a 422 `weight_cap` naming the member (from the error's `user_id`).
String weightCapText(CouncilRoster roster, int? userId, {int? capPct}) {
  final pct = capPct ?? roster.capPct;
  final name = userId == null ? null : roster.members.where((m) => m.userId == userId).map((m) => m.name).firstOrNull;
  return name == null || name.isEmpty
      ? t('لا يجوز أن يتجاوز وزن عضو واحد $pct٪ من مجموع أوزان المجلس.', "No member may hold more than $pct% of the council's total weight.")
      : t('وزن $name يتجاوز $pct٪ من مجموع أوزان المجلس — خفّضه أو ارفع أوزان غيره.', "$name would hold more than $pct% of the council's total weight — lower it or raise the others'.");
}

/// The notice after "Remind non-voters".
String remindDoneText(int n) => n == 0
    ? t('صوّت الجميع — لا أحد يحتاج تذكيراً', 'Everyone has voted — nobody to remind')
    : countText(n, ar1: 'ذُكِّر عضو واحد', ar2: 'ذُكِّر عضوان', arFew: 'ذُكِّر {n} أعضاء', arMany: 'ذُكِّر {n} عضواً', en1: 'Reminded 1 member', en: 'Reminded {n} members');

/// The notice of a 429 `remind_too_soon` (or the client's own once-an-hour check).
String remindWaitText(Duration wait) {
  final m = (wait.inSeconds / 60).ceil().clamp(1, 60);
  final when = countText(m, ar1: 'دقيقة واحدة', ar2: 'دقيقتين', arFew: '{n} دقائق', arMany: '{n} دقيقة', en1: '1 minute', en: '{n} minutes');
  return t('أُرسل تذكير منذ أقل من ساعة — يمكنك التذكير مجدداً بعد $when', 'A reminder went out less than an hour ago — you can remind again in $when');
}
