// lib/features/org/advising/adv_availability_page.dart — an advisor's office hours (docs/advising/PHASE5.md
// "Availability"): weekly windows per weekday in the organization's wall clock (appointment length, ways of meeting,
// place / video link), and days off — a day off that covers booked appointments offers to cancel them with a reason.
// Reached from "My office hours" (the advisor) and the advisors page (a director, for any advisor).
//
//   AdvAvailabilityView · AdvRuleForm · AdvDayOffForm   plain values (test/ui/adv_appt_layout_test.dart)
//   AdvAvailabilityPage                                 loads and saves through AdvCommApi (the whole weekly list)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_header.dart' show OrgPageRefresh;
import '../org_v3.dart' show orgCall;
import 'adv_appt_models.dart';
import 'adv_case_parts.dart' show AdvTypedField;
import 'adv_comm_api.dart';
import 'adv_comm_parts.dart';
import 'adv_models.dart' show AdvPage, advMeetingModeLabel;
import 'adv_parts.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  The view (plain values)
// ═════════════════════════════════════════════════════════════════════════════

class AdvAvailabilityView extends StatelessWidget {
  const AdvAvailabilityView({
    super.key,
    required this.load,
    this.rules = const [],
    this.off = const [],
    this.timezone = '',
    this.advisorName,
    this.dirty = false,
    this.busy = false,
    this.error,
    this.errorText,
    this.onRetry,
    this.onAdd,
    this.onEdit,
    this.onRemove,
    this.onSave,
    this.onAddOff,
    this.onRemoveOff,
  });

  final AdvLoad load;
  final List<AdvRule> rules;
  final List<AdvDayOff> off;
  final String timezone;

  /// A director editing someone else's hours: whose they are.
  final String? advisorName;
  final bool dirty, busy;

  /// Why the rules cannot be saved (local checks or the server's answer).
  final String? error;
  final String? errorText;
  final VoidCallback? onRetry, onSave, onAddOff;
  final ValueChanged<int>? onAdd;
  final ValueChanged<int>? onEdit, onRemove;
  final ValueChanged<AdvDayOff>? onRemoveOff;

  @override
  Widget build(BuildContext context) {
    if (load != AdvLoad.ready) return AdvLoadState(state: load, errorText: errorText, onRetry: onRetry);
    final c = context.colors;
    final err = error;
    final weekly = rules.fold<int>(0, (n, r) => n + r.slots);
    return AdvPageFrame(maxWidth: 820, children: [
      AppBanner(
        icon: Icons.public_rounded,
        text: [
          if (advisorName != null) t('الساعات المكتبية لـ $advisorName', 'Office hours of $advisorName'),
          t('الأوقات بتوقيت المؤسسة${timezone.isEmpty ? '' : ' ($timezone)'}، ويحجز الطلاب من الأوقات الحرة فقط.',
              'Times are in the organization\'s time${timezone.isEmpty ? '' : ' ($timezone)'}; students book free times only.'),
        ].join(' · '),
      ),
      AdvSectionTitle(
        t('الأسبوع', 'The week'),
        subtitle: rules.isEmpty
            ? t('لم تحدد ساعات بعد — أضف فترة ليوم ليبدأ الطلاب الحجز', 'No hours yet — add a window to a day so students can book')
            : countText(weekly, ar1: 'موعد واحد أسبوعياً', ar2: 'موعدان أسبوعياً', arFew: '$weekly مواعيد أسبوعياً', arMany: '$weekly موعداً أسبوعياً', en1: '1 appointment a week', en: '$weekly appointments a week'),
      ),
      for (final wd in advWeekOrder()) _DayCard(weekday: wd, rules: rules, busy: busy, onAdd: onAdd, onEdit: onEdit, onRemove: onRemove),
      if (err != null) ...[
        const SizedBox(height: AppSpace.xs),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: err),
      ],
      if (dirty) ...[
        const SizedBox(height: AppSpace.sm),
        AppPrimaryButton(icon: Icons.check_rounded, label: t('حفظ الساعات المكتبية', 'Save the office hours'), busy: busy, onPressed: onSave),
      ],
      AdvSectionTitle(
        t('أيام الإجازة', 'Days off'),
        subtitle: t('لا يُحجز فيها شيء؛ المواعيد المحجوزة فيها تبقى حتى تلغيها', 'Nothing can be booked on them; appointments already booked stay until you cancel them'),
        trailing: onAddOff == null
            ? null
            : TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
                onPressed: busy ? null : onAddOff,
                icon: const Icon(Icons.add_rounded, size: AppIconSize.md),
                label: Text(t('إضافة', 'Add')),
              ),
      ),
      if (off.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          child: Text(t('لا إجازات قادمة', 'No days off coming up'), style: AppType.body(context)),
        )
      else
        for (final o in off)
          AdvRowCard(
            leading: CircleAvatar(backgroundColor: c.warning.withValues(alpha: 0.14), child: Icon(Icons.beach_access_rounded, color: appInk(context, c.warning), size: AppIconSize.md)),
            title: o.rangeText,
            subtitle: [countText(o.days, ar1: 'يوم واحد', ar2: 'يومان', arFew: '${o.days} أيام', arMany: '${o.days} يوماً', en1: '1 day', en: '${o.days} days'), ?o.reason].join(' · '),
            trailing: onRemoveOff == null
                ? null
                : IconButton(
                    tooltip: t('حذف الإجازة', 'Remove the day off'),
                    onPressed: busy ? null : () => onRemoveOff!(o),
                    constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                    icon: Icon(Icons.delete_outline_rounded, color: appInk(context, c.danger)),
                  ),
          ),
    ]);
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.weekday, required this.rules, required this.busy, this.onAdd, this.onEdit, this.onRemove});
  final int weekday;
  final List<AdvRule> rules;
  final bool busy;
  final ValueChanged<int>? onAdd, onEdit, onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mine = [for (var i = 0; i < rules.length; i++) if (rules[i].weekday == weekday) i]..sort((a, b) => rules[a].startMin - rules[b].startMin);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppCard(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.xxs, AppSpace.xs),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(advWeekdayLabel(weekday),
                  style: AppType.row(context).copyWith(fontWeight: FontWeight.w700, color: mine.isEmpty ? c.textMedium : null)),
            ),
            if (mine.isEmpty) Text(t('لا ساعات', 'No hours'), style: AppType.meta(context)),
            if (onAdd != null)
              IconButton(
                tooltip: t('إضافة فترة يوم ${advWeekdayLabel(weekday)}', 'Add a window on ${advWeekdayLabel(weekday)}'),
                onPressed: busy ? null : () => onAdd!(weekday),
                constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                icon: Icon(Icons.add_circle_outline_rounded, color: c.primary),
              ),
          ]),
          for (final i in mine)
            Semantics(
              button: onEdit != null,
              label: '${advWeekdayLabel(weekday)} ${rules[i].timeText}',
              child: InkWell(
                borderRadius: AppRadius.chipAll,
                onTap: onEdit == null || busy ? null : () => onEdit!(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(rules[i].timeText, style: AppType.body(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
                        const SizedBox(height: AppSpace.xxs),
                        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                          AppBadgePill(t('${rules[i].slotMinutes} دقيقة', '${rules[i].slotMinutes} min'), color: c.textMedium, icon: Icons.timelapse_rounded),
                          for (final m in rules[i].modes) AppBadgePill(advMeetingModeLabelShort(m), color: c.primary, icon: advModeIcon(m)),
                        ]),
                        if (rules[i].location != null) AdvInfoLine(icon: Icons.place_outlined, text: rules[i].location!, typed: true, maxLines: 1),
                        if (rules[i].validFrom != null || rules[i].validTo != null)
                          AdvInfoLine(
                            icon: Icons.date_range_rounded,
                            text: [
                              if (rules[i].validFrom != null) t('من ${advDayLabel(rules[i].validFrom!, pattern: 'd MMM y')}', 'from ${advDayLabel(rules[i].validFrom!, pattern: 'd MMM y')}'),
                              if (rules[i].validTo != null) t('حتى ${advDayLabel(rules[i].validTo!, pattern: 'd MMM y')}', 'until ${advDayLabel(rules[i].validTo!, pattern: 'd MMM y')}'),
                            ].join(' '),
                          ),
                      ]),
                    ),
                    if (onRemove != null)
                      IconButton(
                        tooltip: t('حذف الفترة', 'Remove the window'),
                        onPressed: busy ? null : () => onRemove!(i),
                        constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                        icon: Icon(Icons.close_rounded, color: c.textMedium, size: AppIconSize.md),
                      ),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The window form (plain values)
// ═════════════════════════════════════════════════════════════════════════════

class AdvRuleForm extends StatelessWidget {
  const AdvRuleForm({
    super.key,
    required this.rule,
    required this.location,
    required this.link,
    this.error,
    this.onWeekday,
    this.onStart,
    this.onEnd,
    this.onSlot,
    this.onMode,
    this.onValidFrom,
    this.onValidTo,
    this.onSubmit,
    this.editing = false,
  });

  final AdvRule rule;
  final TextEditingController location, link;
  final String? error;
  final ValueChanged<int>? onWeekday, onSlot;
  final VoidCallback? onStart, onEnd, onValidFrom, onValidTo, onSubmit;
  final ValueChanged<String>? onMode;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = rule;
    Widget timeField(String label, String value, VoidCallback? on) => Expanded(
          child: AdvPersonField(label: label, name: AppTime.clock(value), icon: Icons.schedule_rounded, avatar: false, onPick: on),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AdvFieldLabel(t('اليوم', 'Day')),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final wd in advWeekOrder()) AppChoiceChip(label: advWeekdayLabel(wd, short: true), selected: wd == r.weekday, onTap: onWeekday == null ? () {} : () => onWeekday!(wd)),
      ]),
      const SizedBox(height: AppSpace.md),
      Row(children: [
        timeField(t('من', 'From'), r.start, onStart),
        const SizedBox(width: AppSpace.sm),
        timeField(t('إلى', 'To'), r.end, onEnd),
      ]),
      const SizedBox(height: AppSpace.sm),
      AdvFieldLabel(t('مدة الموعد', 'Appointment length'),
          hint: r.slots > 0 ? countText(r.slots, ar1: 'موعد واحد في هذه الفترة', ar2: 'موعدان في هذه الفترة', arFew: '${r.slots} مواعيد في هذه الفترة', arMany: '${r.slots} موعداً في هذه الفترة', en1: '1 appointment in this window', en: '${r.slots} appointments in this window') : null),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final m in advSlotLengths) AppChoiceChip(label: t('$m د', '$m min'), selected: m == r.slotMinutes, onTap: onSlot == null ? () {} : () => onSlot!(m)),
      ]),
      const SizedBox(height: AppSpace.md),
      AdvFieldLabel(t('طرق اللقاء', 'Ways to meet'), hint: t('اختر واحدة أو أكثر', 'Choose one or more')),
      AdvModeChips(modes: advApptModes, selected: null, multi: true, selection: r.modes, onChanged: onMode),
      const SizedBox(height: AppSpace.md),
      if (r.modes.contains('in_person')) ...[
        AppField(controller: location, label: t('المكان (المكتب أو القاعة)', 'Place (office or room)')),
        const SizedBox(height: AppSpace.sm),
      ],
      if (r.modes.contains('video')) ...[
        AppField(controller: link, label: t('رابط الاجتماع (اختياري)', 'Meeting link (optional)'), keyboard: TextInputType.url, ltr: true),
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs, bottom: AppSpace.sm),
          child: Text(t('دونه يُنشأ اجتماع مرئي على المنصة تلقائياً لكل موعد', 'Without one, each appointment gets a video meeting on the platform'), style: AppType.meta(context)),
        ),
      ],
      AdvFieldLabel(t('مدة الصلاحية (اختياري)', 'Valid between (optional)')),
      Row(children: [
        Expanded(child: AdvPersonField(label: t('من', 'From'), name: r.validFrom == null ? t('الآن', 'Now') : advDayLabel(r.validFrom!, pattern: 'd MMM y'), icon: Icons.event_rounded, avatar: false, onPick: onValidFrom)),
        const SizedBox(width: AppSpace.sm),
        Expanded(child: AdvPersonField(label: t('حتى', 'Until'), name: r.validTo == null ? t('دون نهاية', 'No end') : advDayLabel(r.validTo!, pattern: 'd MMM y'), icon: Icons.event_rounded, avatar: false, onPick: onValidTo)),
      ]),
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(icon: Icons.check_rounded, label: editing ? t('تحديث الفترة', 'Update the window') : t('إضافة الفترة', 'Add the window'), onPressed: onSubmit),
    ]);
  }
}

Future<TimeOfDay?> _pickTime(BuildContext context, String hhmm) {
  final m = advMinutes(hhmm) ?? 9 * 60;
  return showTimePicker(context: context, initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60));
}

Future<DateTime?> _pickDay(BuildContext context, DateTime? initial, {DateTime? first}) {
  final today = advZoneToday();
  final f = first ?? today;
  final init = initial == null || initial.isBefore(f) ? f : initial;
  return showDatePicker(context: context, initialDate: init, firstDate: f, lastDate: DateTime(today.year + 2, 12, 31));
}

/// Adds or edits one weekly window. Returns it (null when closed).
Future<AdvRule?> showAdvRuleSheet(BuildContext context, {AdvRule? rule, int weekday = 0, List<AdvRule> others = const []}) {
  var r = rule ?? AdvRule(weekday: weekday);
  final location = TextEditingController(text: r.location ?? '');
  final link = TextEditingController(text: r.videoLink ?? '');
  String? error;
  return showAppSheet<AdvRule>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        void submit() {
          final out = r.copyWith(location: () => location.text.trim().isEmpty ? null : location.text.trim(), videoLink: () => link.text.trim().isEmpty ? null : link.text.trim());
          final why = advRulesError([...others, out]);
          if (why != null) {
            set(() => error = why);
            return;
          }
          Navigator.pop(ctx, out);
        }

        return AppSheetContent(
          title: rule == null ? t('فترة ساعات مكتبية', 'Office-hours window') : t('تعديل الفترة', 'Edit the window'),
          children: [
            AdvRuleForm(
              rule: r,
              location: location,
              link: link,
              error: error,
              editing: rule != null,
              onWeekday: (wd) => set(() => r = r.copyWith(weekday: wd)),
              onStart: () async {
                final x = await _pickTime(ctx, r.start);
                if (x != null) set(() => r = r.copyWith(start: advHhmm(x.hour * 60 + x.minute)));
              },
              onEnd: () async {
                final x = await _pickTime(ctx, r.end);
                if (x != null) set(() => r = r.copyWith(end: advHhmm(x.hour * 60 + x.minute)));
              },
              onSlot: (m) => set(() => r = r.copyWith(slotMinutes: m)),
              onMode: (m) => set(() => r = r.copyWith(modes: r.modes.contains(m) ? [for (final x in r.modes) if (x != m) x] : [...r.modes, m])),
              onValidFrom: () async {
                final d = await _pickDay(ctx, r.validFrom);
                set(() => r = r.copyWith(validFrom: () => d));
              },
              onValidTo: () async {
                final d = await _pickDay(ctx, r.validTo, first: r.validFrom);
                set(() => r = r.copyWith(validTo: () => d));
              },
              onSubmit: submit,
            ),
          ],
        );
      }));
}

// ═════════════════════════════════════════════════════════════════════════════
//  Days off
// ═════════════════════════════════════════════════════════════════════════════

class AdvDayOffForm extends StatelessWidget {
  const AdvDayOffForm({super.key, required this.from, required this.to, required this.reason, this.busy = false, this.error, this.onFrom, this.onTo, this.onSubmit});
  final DateTime from, to;
  final TextEditingController reason;
  final bool busy;
  final String? error;
  final VoidCallback? onFrom, onTo, onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: AdvPersonField(label: t('من', 'From'), name: advDayLabel(from, pattern: 'EEE d MMM y'), icon: Icons.event_rounded, avatar: false, onPick: busy ? null : onFrom)),
        const SizedBox(width: AppSpace.sm),
        Expanded(child: AdvPersonField(label: t('إلى', 'To'), name: advDayLabel(to, pattern: 'EEE d MMM y'), icon: Icons.event_rounded, avatar: false, onPick: busy ? null : onTo)),
      ]),
      const SizedBox(height: AppSpace.sm),
      AppField(controller: reason, label: t('السبب (اختياري، لا يراه الطلاب)', 'Reason (optional, students do not see it)')),
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(icon: Icons.beach_access_rounded, label: t('إضافة الإجازة', 'Add the day off'), busy: busy, onPressed: onSubmit),
    ]);
  }
}

Future<AdvOffResult?> _showDayOffSheet(BuildContext context, AdvCommApi api, int advisorUserId) {
  final today = advZoneToday();
  var from = today, to = today;
  final reason = TextEditingController();
  var busy = false;
  String? error;
  return showAppSheet<AdvOffResult>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> submit() async {
          set(() {
            busy = true;
            error = null;
          });
          final r = await orgCall(() => api.addOff(advisorUserId, from, to, reason.text), quiet: true);
          if (!ctx.mounted) return;
          if (!r.ok) {
            set(() {
              busy = false;
              error = advCommErrorText(r.error!);
            });
            return;
          }
          showAppNotice(t('أُضيفت الإجازة — لا يُحجز فيها شيء', 'Day off added — nothing can be booked on it'));
          Navigator.pop(ctx, r.data as AdvOffResult);
        }

        return AppSheetContent(
          title: t('إجازة', 'Day off'),
          children: [
            AdvDayOffForm(
              from: from,
              to: to,
              reason: reason,
              busy: busy,
              error: error,
              onFrom: () async {
                final d = await _pickDay(ctx, from);
                if (d != null) {
                  set(() {
                    from = d;
                    if (to.isBefore(d)) to = d;
                  });
                }
              },
              onTo: () async {
                final d = await _pickDay(ctx, to, first: from);
                if (d != null) set(() => to = d);
              },
              onSubmit: submit,
            ),
          ],
        );
      }));
}

// ═════════════════════════════════════════════════════════════════════════════
//  The page
// ═════════════════════════════════════════════════════════════════════════════

class AdvAvailabilityPage extends StatelessWidget {
  const AdvAvailabilityPage({super.key, required this.orgId, required this.advisorUserId, this.advisorName});
  final int orgId, advisorUserId;

  /// A director editing someone else's hours.
  final String? advisorName;

  @override
  Widget build(BuildContext context) => AdvCommScaffold(
        orgId: orgId,
        title: advisorName == null ? t('ساعاتي المكتبية', 'My office hours') : t('الساعات المكتبية', 'Office hours'),
        subtitle: advisorName,
        maxWidth: 820,
        child: _AdvAvailabilityBody(orgId: orgId, advisorUserId: advisorUserId, advisorName: advisorName),
      );
}

class _AdvAvailabilityBody extends StatefulWidget {
  const _AdvAvailabilityBody({required this.orgId, required this.advisorUserId, this.advisorName});
  final int orgId, advisorUserId;
  final String? advisorName;

  @override
  State<_AdvAvailabilityBody> createState() => _AdvAvailabilityBodyState();
}

class _AdvAvailabilityBodyState extends State<_AdvAvailabilityBody> {
  late final AdvCommApi _api = AdvCommApi(widget.orgId);
  OrgPageRefresh? _refresh;
  AdvAvailability? _saved;
  List<AdvRule> _rules = const [];
  AdvLoad _load = AdvLoad.loading;
  bool _busy = false;
  String? _error, _loadError;

  int get _uid => widget.advisorUserId;
  bool get _dirty => _saved != null && !_same(_saved!.rules, _rules);

  static bool _same(List<AdvRule> a, List<AdvRule> b) => a.length == b.length && [for (var i = 0; i < a.length; i++) '${a[i].toJson()}' == '${b[i].toJson()}'].every((x) => x);

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _reload);
    _reload();
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final r = await orgCall(() => _api.availability(_uid), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _saved = r.data as AdvAvailability;
        _rules = [..._saved!.rules];
        _load = AdvLoad.ready;
        _error = null;
      } else if (_saved == null) {
        _load = advFailLoad(r);
        _loadError = advCommErrorText(r.error!);
      }
    });
    if (r.ok && mounted) OrgPageRefresh.reportUpdated(context);
  }

  Future<void> _add(int weekday) async {
    final r = await showAdvRuleSheet(context, weekday: weekday, others: _rules);
    if (r != null && mounted) setState(() => _rules = [..._rules, r]..sort(advRuleOrder));
  }

  Future<void> _edit(int i) async {
    final others = [for (var j = 0; j < _rules.length; j++) if (j != i) _rules[j]];
    final r = await showAdvRuleSheet(context, rule: _rules[i], others: others);
    if (r != null && mounted) setState(() => _rules = [...others, r]..sort(advRuleOrder));
  }

  Future<void> _save() async {
    final why = advRulesError(_rules);
    if (why != null) {
      setState(() => _error = why);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await orgCall(() => _api.saveRules(_uid, _rules), quiet: true);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _saved = r.data as AdvAvailability;
        _rules = [..._saved!.rules];
      } else {
        _error = advCommErrorText(r.error!);
      }
    });
    if (r.ok) showAppNotice(t('حُفظت الساعات المكتبية', 'Office hours saved'));
  }

  Future<void> _addOff() async {
    final res = await _showDayOffSheet(context, _api, _uid);
    if (res == null || !mounted) return;
    await _reload();
    if (res.affected.isNotEmpty && mounted) await _offerCancel(res);
  }

  /// A day off over booked appointments: list them and offer to cancel them all with one reason.
  Future<void> _offerCancel(AdvOffResult res) async {
    final r = await orgCall(() => _api.appointments(advisorUserId: _uid, status: 'booked', from: DateTime.utc(res.off.from.year, res.off.from.month, res.off.from.day).subtract(const Duration(days: 1)), size: 100), quiet: true);
    if (!mounted) return;
    final ids = res.affected.toSet();
    final list = r.ok ? [for (final a in (r.data as AdvPage<AdvAppointment>).items) if (ids.contains(a.id)) a] : <AdvAppointment>[];
    final reason = TextEditingController(text: t('المرشد في إجازة في هذا اليوم', 'The advisor is off on that day'));
    var busy = false;
    String? error;
    final n = res.affected.length;
    await showAppSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          Future<void> cancelAll() async {
            set(() {
              busy = true;
              error = null;
            });
            var done = 0;
            String? fail;
            for (final id in res.affected) {
              final x = await orgCall(() => _api.cancel(id, reason.text), quiet: true);
              if (x.ok) {
                done++;
              } else {
                fail ??= advCommErrorText(x.error!);
              }
            }
            if (!ctx.mounted) return;
            if (fail != null) {
              set(() {
                busy = false;
                error = fail;
              });
            } else {
              Navigator.pop(ctx);
            }
            if (done > 0) {
              showAppNotice(countText(done,
                  ar1: 'أُلغي موعد واحد وأُبلغ الطالب', ar2: 'أُلغي موعدان وأُبلغ الطالبان', arFew: 'أُلغيت $done مواعيد وأُبلغ الطلاب', arMany: 'أُلغي $done موعداً وأُبلغ الطلاب',
                  en1: '1 appointment cancelled — the student was told', en: '$done appointments cancelled — the students were told'));
            }
          }

          return AppSheetContent(
            title: countText(n, ar1: 'موعد محجوز في الإجازة', ar2: 'موعدان محجوزان في الإجازة', arFew: '$n مواعيد محجوزة في الإجازة', arMany: '$n موعداً محجوزاً في الإجازة', en1: '1 appointment is booked on that day off', en: '$n appointments are booked on that day off'),
            children: [
              Text(t('لم تُلغَ تلقائياً. ألغها الآن ليُبلَّغ الطلاب، أو أبقها.', 'They were not cancelled. Cancel them now so the students are told, or keep them.'), style: AppType.body(context)),
              const SizedBox(height: AppSpace.sm),
              for (final a in list) AdvInfoLine(icon: advModeIcon(a.mode), text: '${a.studentShown} · ${a.whenText} · ${advMeetingModeLabel(a.mode)}'),
              const SizedBox(height: AppSpace.sm),
              AdvTypedField(controller: reason, label: t('سبب الإلغاء (يراه الطلاب)', 'Why (the students see it)'), minLines: 2, maxLines: 3, maxLength: 500, enabled: !busy),
              if (error != null) ...[
                const SizedBox(height: AppSpace.sm),
                AppBanner(icon: Icons.error_outline_rounded, color: context.colors.danger, text: error!),
              ],
              const SizedBox(height: AppSpace.md),
              AppButton.danger(label: t('إلغاء هذه المواعيد', 'Cancel these appointments'), icon: Icons.event_busy_rounded, expand: true, busy: busy, onPressed: cancelAll),
              const SizedBox(height: AppSpace.xs),
              AppButton.secondary(label: t('إبقاؤها', 'Keep them'), expand: true, onPressed: busy ? null : () => Navigator.pop(ctx)),
            ],
          );
        }));
  }

  Future<void> _removeOff(AdvDayOff o) async {
    final yes = await appConfirm(context, message: t('حذف إجازة ${o.rangeText}؟ يعود الحجز متاحاً فيها.', 'Remove the day off ${o.rangeText}? Booking opens again on it.'), confirmLabel: t('حذف', 'Remove'));
    if (!yes || !mounted) return;
    final r = await orgCall(() => _api.removeOff(_uid, o.id), quiet: true);
    if (!mounted) return;
    if (!r.ok) {
      showAppNotice(advCommErrorText(r.error!), error: true);
      return;
    }
    showAppNotice(t('حُذفت الإجازة', 'Day off removed'));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = _saved;
    return AdvAvailabilityView(
      load: _load,
      rules: _rules,
      off: s?.off ?? const [],
      timezone: s?.timezone ?? '',
      advisorName: widget.advisorName,
      dirty: _dirty,
      busy: _busy,
      error: _error,
      errorText: _loadError,
      onRetry: () {
        setState(() => _load = AdvLoad.loading);
        _reload();
      },
      onAdd: _add,
      onEdit: _edit,
      onRemove: (i) => setState(() => _rules = [for (var j = 0; j < _rules.length; j++) if (j != i) _rules[j]]),
      onSave: _save,
      onAddOff: _addOff,
      onRemoveOff: _removeOff,
    );
  }
}
