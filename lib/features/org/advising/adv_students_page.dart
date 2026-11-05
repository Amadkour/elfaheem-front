// lib/features/org/advising/adv_students_page.dart — students and their advisors (Phase 3, docs/advising/PHASE3.md
// "Students and manual assignment"): search and one filter (without an advisor · advisor away · locked); tap → the
// student sheet: the primary advisor, co / support advisors when the settings allow several, Keep (lock), a reason,
// "assign anyway" with a reason when the advisor is at their maximum, the conflicts of interest and the history. An
// advisor sees their own advisees, read only, with the history.
//
//   AdvStudentsView   the list (plain values)        AdvStudentCard    one student
//   AdvStudentForm    the student sheet's content     AdvHistoryList    the assignment history
//   AdvStudentsPage   loads `GET …/students`, saves the whole assignment with `PUT …/students/{id}/advisors`
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_header.dart' show OrgPageRefresh, OrgPushedPage;
import '../org_page_kit.dart';
import '../org_v3.dart' show orgCall, orgErrorText;
import 'adv_api.dart';
import 'adv_distribute_page.dart';
import 'adv_models.dart';
import 'adv_parts.dart';

const advStudentFilters = ['all', 'unassigned', 'away', 'locked'];

Map<String, String> advStudentFilterLabels(Map<String, int> facets) {
  String n(String label, String key) => facets.containsKey(key) ? '$label · ${facets[key]}' : label;
  return {
    'all': t('الكل', 'All'),
    'unassigned': n(t('بلا مرشد', 'Without an advisor'), 'unassigned'),
    'away': n(t('مرشدهم غائب', 'Advisor away'), 'away'),
    'locked': n(t('مقفلون', 'Locked'), 'locked'),
  };
}

class AdvStudentCard extends StatelessWidget {
  const AdvStudentCard({super.key, required this.student, this.onTap});
  final AdvStudent student;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = student;
    final p = s.primary;
    final Widget? pill = p == null
        ? AppBadgePill(t('بلا مرشد', 'No advisor'), color: c.warning, icon: Icons.person_search_rounded)
        : p.away
            ? AppBadgePill(t('المرشد غائب', 'Advisor away'), color: c.warning, icon: Icons.person_off_rounded)
            : (p.locked ? AppBadgePill(t('مقفل', 'Locked'), color: c.textMedium, icon: Icons.lock_rounded) : null);
    final others = [for (final o in s.others) '${advAdvisorTypeLabel(o.type)}: ${o.shown}'];
    return AdvRowCard(
      title: s.shown,
      subtitle: s.subtitle.isEmpty ? null : s.subtitle,
      avatarName: s.shown,
      trailing: pill,
      onTap: onTap,
      below: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          ExcludeSemantics(child: Icon(p == null ? Icons.person_outline_rounded : Icons.co_present_rounded, size: AppIconSize.sm, color: p == null ? c.textLight : c.primary)),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(
              p == null ? t('لم يُسند له مرشد بعد', 'No advisor assigned yet') : t('المرشد: ${p.shown}', 'Advisor: ${p.shown}'),
              style: AppType.meta(context).copyWith(color: p == null ? null : c.textDark),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (p != null && p.locked && p.away) ...[
            const SizedBox(width: AppSpace.xxs),
            Tooltip(message: t('مقفل', 'Locked'), child: Icon(Icons.lock_rounded, size: AppIconSize.sm, color: c.textMedium)),
          ],
        ]),
        if (others.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(others.join(' · '), style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ]),
    );
  }
}

class AdvStudentsView extends StatelessWidget {
  const AdvStudentsView({
    super.key,
    required this.load,
    required this.manage,
    this.page,
    this.filter = 'all',
    this.errorText,
    this.onRetry,
    this.onSearch,
    this.onFilter,
    this.onPage,
    this.onOpen,
    this.onDistribute,
  });

  final AdvLoad load;

  /// Org admin / advising director (else an advisor's own advisees, read only).
  final bool manage;
  final AdvPage<AdvStudent>? page;
  final String filter;
  final String? errorText;
  final VoidCallback? onRetry, onDistribute;
  final ValueChanged<String>? onSearch, onFilter;
  final ValueChanged<int>? onPage;
  final ValueChanged<AdvStudent>? onOpen;

  @override
  Widget build(BuildContext context) {
    final p = page;
    final c = context.colors;
    final primary = manage && onDistribute != null
        ? OrgPrimaryAction(id: 'distribute', icon: Icons.call_split_rounded, label: t('توزيع', 'Distribute'), onTap: onDistribute!)
        : null;
    Widget body;
    if (load != AdvLoad.ready || p == null) {
      body = AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry);
    } else if (p.items.isEmpty) {
      body = AppEmpty(
        icon: filter == 'unassigned' ? Icons.how_to_reg_rounded : Icons.school_rounded,
        title: switch (filter) {
          'unassigned' => t('لكل طالب مرشد', 'Every student has an advisor'),
          'away' => t('لا طلاب مرشدهم غائب', 'No student\'s advisor is away'),
          'locked' => t('لا طلاب مقفلون', 'No locked students'),
          _ => manage ? t('لا طلاب بعد', 'No students yet') : t('لم يُسند إليك طلاب بعد', 'No students are assigned to you yet'),
        },
      );
    } else {
      final unassigned = p.facet('unassigned'), away = p.facet('away');
      body = AdvPageFrame(fab: primary != null, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Text(
            countText(p.total, ar1: 'طالب واحد', ar2: 'طالبان', arFew: '${p.total} طلاب', arMany: '${p.total} طالباً', en1: '1 student', en: '${p.total} students'),
            style: AppType.meta(context),
          ),
        ),
        if (manage && filter == 'all' && (unassigned > 0 || away > 0))
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AppBanner(
              icon: Icons.person_search_rounded,
              color: c.warning,
              text: [
                if (unassigned > 0)
                  countText(unassigned, ar1: 'طالب واحد بلا مرشد', ar2: 'طالبان بلا مرشد', arFew: '$unassigned طلاب بلا مرشد', arMany: '$unassigned طالباً بلا مرشد',
                      en1: '1 student has no advisor', en: '$unassigned students have no advisor'),
                if (away > 0)
                  countText(away, ar1: 'طالب واحد مرشده غائب', ar2: 'طالبان مرشدهما غائب', arFew: '$away طلاب مرشدوهم غائبون', arMany: '$away طالباً مرشدوهم غائبون',
                      en1: '1 student\'s advisor is away', en: '$away students\' advisors are away'),
              ].join(t('، و', ' · ')),
            ),
          ),
        for (final s in p.items) AdvStudentCard(student: s, onTap: onOpen == null ? null : () => onOpen!(s)),
        if (p.pages > 1 && onPage != null) ...[
          const SizedBox(height: AppSpace.sm),
          AppPagination(page: p.page, pageCount: p.pages, total: p.total, pageSize: p.size, onPage: onPage!),
        ],
      ]);
    }
    return OrgPageBody(
      primary: primary,
      search: onSearch == null ? null : OrgSearchField(hint: t('ابحث بالاسم أو الرقم', 'Search by name or ID'), onChanged: onSearch!),
      filter: onFilter == null
          ? null
          : OrgFilterButton<String>(
              value: filter,
              defaultValue: 'all',
              label: t('التصفية', 'Filter'),
              options: advStudentFilterLabels(p?.facets ?? const {}),
              onChanged: onFilter!,
            ),
      child: body,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Student sheet
// ═════════════════════════════════════════════════════════════════════════════

/// The assignment history, newest first (null = loading).
class AdvHistoryList extends StatelessWidget {
  const AdvHistoryList({super.key, required this.entries});
  final List<AdvHistoryEntry>? entries;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = entries;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AdvSectionTitle(t('السجل', 'History'), subtitle: t('كل من أرشد هذا الطالب', 'Everyone who advised this student')),
      if (list == null)
        const AppListSkeleton(items: 2, withAvatar: false, padding: EdgeInsets.zero)
      else if (list.isEmpty)
        Text(t('لا سجل بعد.', 'No history yet.'), style: AppType.body(context))
      else
        for (var i = 0; i < list.length; i++)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: AppSpace.md,
                child: Column(children: [
                  const SizedBox(height: AppSpace.xxs + 2),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: list[i].active ? c.success : c.divider, border: Border.all(color: list[i].active ? c.success : c.textLight)),
                  ),
                  if (i < list.length - 1) Expanded(child: Container(width: AppBorder.hairline, color: c.divider)),
                ]),
              ),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${list[i].name.isEmpty ? '#${list[i].userId}' : list[i].name} · ${advAdvisorTypeLabel(list[i].type)}',
                        style: AppType.row(context), maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text(_line(list[i]), style: AppType.meta(context)),
                  ]),
                ),
              ),
            ]),
          ),
    ]);
  }

  static String _line(AdvHistoryEntry e) {
    final from = advDate(e.startedAt), to = advDate(e.endedAt);
    final when = e.active ? t('منذ $from', 'Since $from') : '$from – $to';
    return [
      if (from.isNotEmpty) when,
      if (e.source.isNotEmpty) advSourceLabel(e.source),
      if (e.locked) t('مقفل', 'locked'),
      if (e.endReason != null) advEndReasonLabel(e.endReason!),
      if (e.actor != null) t('بواسطة ${e.actor}', 'by ${e.actor}'),
    ].join(' · ');
  }
}

class AdvStudentForm extends StatelessWidget {
  const AdvStudentForm({
    super.key,
    required this.student,
    required this.draft,
    required this.multi,
    required this.manage,
    required this.reason,
    this.overCapacity = false,
    this.history,
    this.conflicts,
    this.busy = false,
    this.error,
    this.onPickPrimary,
    this.onClearPrimary,
    this.onLocked,
    this.onAddOther,
    this.onRemoveOther,
    this.onForce,
    this.onSubmit,
    this.onAddConflict,
    this.onRemoveConflict,
  });

  final AdvStudent student;
  final AdvAdvisorsDraft draft;

  /// The settings allow co / support advisors.
  final bool multi;

  /// Org admin / advising director (an advisor sees the history only).
  final bool manage;
  final TextEditingController reason;

  /// The last save answered `advising_over_capacity`: "assign anyway" is offered.
  final bool overCapacity;
  final List<AdvHistoryEntry>? history;
  final List<AdvConflict>? conflicts;
  final bool busy;
  final String? error;
  final VoidCallback? onPickPrimary, onClearPrimary, onSubmit, onAddConflict;
  final ValueChanged<bool>? onLocked, onForce;
  final ValueChanged<String>? onAddOther;
  final ValueChanged<int>? onRemoveOther;
  final ValueChanged<AdvConflict>? onRemoveConflict;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = student, d = draft;
    final p = s.primary;
    final err = error;
    final head = Row(children: [
      AppAvatar(name: s.shown, size: 48),
      const SizedBox(width: AppSpace.sm),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.shown, style: AppType.section(context), maxLines: 2, overflow: TextOverflow.ellipsis),
          if (s.subtitle.isNotEmpty) Text(s.subtitle, style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
        ]),
      ),
    ]);
    if (!manage) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head,
        if (p != null) ...[
          const SizedBox(height: AppSpace.sm),
          AppInfoRow(Icons.co_present_rounded, t('المرشد: ${p.shown} · ${advSourceLabel(p.source)}', 'Advisor: ${p.shown} · ${advSourceLabel(p.source)}')),
        ],
        for (final o in s.others) AppInfoRow(Icons.person_outline_rounded, '${advAdvisorTypeLabel(o.type)}: ${o.shown}'),
        AdvHistoryList(entries: history),
      ]);
    }
    final chosen = d.primary;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      head,
      const SizedBox(height: AppSpace.md),
      AdvPersonField(
        label: t('المرشد الأساسي', 'Primary advisor'),
        name: chosen?.shown,
        detail: p != null && chosen?.userId == p.userId ? [advSourceLabel(p.source), if (p.since != null) t('منذ ${advDate(p.since)}', 'since ${advDate(p.since)}')].join(' · ') : null,
        placeholder: t('اختر مرشداً', 'Choose an advisor'),
        onPick: busy ? null : onPickPrimary,
        onClear: busy ? null : onClearPrimary,
      ),
      if (p != null && p.away && chosen?.userId == p.userId) ...[
        const SizedBox(height: AppSpace.xs),
        AppBanner(icon: Icons.person_off_rounded, color: c.warning, text: t('هذا المرشد غائب — اختر مرشداً آخر للطالب.', 'This advisor is away — choose another advisor for the student.')),
      ],
      if (chosen != null)
        AppSwitchTile(
          icon: Icons.lock_outline_rounded,
          title: t('إبقاء هذا المرشد', 'Keep this advisor'),
          subtitle: t('لا يغيّره التوزيع التلقائي ولا الموازنة', 'Distribution and rebalancing never change it'),
          value: d.locked,
          onChanged: busy ? null : onLocked,
        ),
      if (multi) ...[
        AdvSectionTitle(t('مرشدون آخرون', 'Other advisors'), subtitle: t('مرشد مشارك أو داعم بجانب الأساسي', 'A co or support advisor next to the primary')),
        for (final o in d.others)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Container(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xxs, AppSpace.xxs, AppSpace.xxs),
              decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
              child: Row(children: [
                AppAvatar(name: o.shown, size: 32),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(o.shown, style: AppType.row(context), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(advAdvisorTypeLabel(o.type), style: AppType.meta(context)),
                  ]),
                ),
                IconButton(
                  tooltip: t('إزالة', 'Remove'),
                  constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                  onPressed: busy || onRemoveOther == null ? null : () => onRemoveOther!(o.userId),
                  icon: Icon(Icons.close_rounded, size: AppIconSize.md, color: c.textMedium),
                ),
              ]),
            ),
          ),
        Wrap(spacing: AppSpace.xs, children: [
          for (final type in const ['co', 'support'])
            TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
              onPressed: busy || chosen == null || onAddOther == null ? null : () => onAddOther!(type),
              icon: const Icon(Icons.add_rounded, size: AppIconSize.md),
              label: Text(type == 'co' ? t('مرشد مشارك', 'Co-advisor') : t('مرشد داعم', 'Support advisor')),
            ),
        ]),
      ] else if (s.others.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xs),
        AppBanner(
          icon: Icons.info_outline_rounded,
          text: t('الإعدادات على مرشد واحد؛ يُزال المرشدون الآخرون عند الحفظ.', 'The settings allow one advisor; the other advisors are removed when you save.'),
        ),
      ],
      if (overCapacity) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.warning_amber_rounded, color: c.warning, text: t('المرشد بلغ حده الأقصى.', 'This advisor is at their maximum.')),
        AppSwitchTile(
          icon: Icons.priority_high_rounded,
          title: t('الإسناد رغم الحد الأقصى', 'Assign anyway'),
          subtitle: t('يُسجّل مع سببك', 'Recorded with your reason'),
          value: d.force,
          onChanged: busy ? null : onForce,
        ),
      ],
      const SizedBox(height: AppSpace.sm),
      AppField(controller: reason, label: overCapacity && d.force ? t('السبب (مطلوب)', 'Reason (required)') : t('السبب (اختياري)', 'Reason (optional)'), hint: t('يُحفظ في السجل', 'Kept in the history'), maxLines: 2),
      if (err != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: err),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(
        icon: Icons.check_rounded,
        label: t('حفظ', 'Save'),
        busy: busy,
        onPressed: onSubmit == null || (!d.changedFrom(s) && !d.force) ? null : onSubmit,
      ),
      if (onAddConflict != null) AdvConflictList(conflicts: conflicts, ofAdvisor: false, onAdd: busy ? null : onAddConflict, onRemove: busy ? null : onRemoveConflict),
      AdvHistoryList(entries: history),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class AdvStudentsPage extends StatelessWidget {
  const AdvStudentsPage({super.key, required this.orgId, required this.manage, this.filter = 'all'});
  final int orgId;
  final bool manage;

  /// The filter the page opens with (e.g. `away` from the advising page's banner).
  final String filter;

  @override
  Widget build(BuildContext context) => OrgPushedPage(
        title: manage ? t('الطلاب ومرشدوهم', 'Students and advisors') : t('طلابي', 'My students'),
        helpPageId: 'org.advising',
        maxWidth: 1000,
        child: _AdvStudentsBody(orgId: orgId, manage: manage, filter: filter),
      );
}

class _AdvStudentsBody extends StatefulWidget {
  const _AdvStudentsBody({required this.orgId, required this.manage, required this.filter});
  final int orgId;
  final bool manage;
  final String filter;

  @override
  State<_AdvStudentsBody> createState() => _AdvStudentsBodyState();
}

class _AdvStudentsBodyState extends State<_AdvStudentsBody> {
  late final AdvApi _api = AdvApi(widget.orgId);
  OrgPageRefresh? _refresh;
  AdvPage<AdvStudent>? _page;
  AdvLoad _load = AdvLoad.loading;
  String? _error;
  String _q = '';
  late String _filter = advStudentFilters.contains(widget.filter) ? widget.filter : 'all';
  int _pageNo = 1;
  int _seq = 0;

  /// The settings allow co / support advisors (read once, manage only).
  bool _multi = false;

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _reload);
    _reload();
    if (widget.manage) _loadMode();
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    super.dispose();
  }

  Future<void> _loadMode() async {
    final r = await orgCall(() => _api.policy(), quiet: true);
    if (mounted && r.ok) setState(() => _multi = (r.data as AdvPolicyBundle).effective.multi);
  }

  Future<void> _reload() async {
    final seq = ++_seq;
    final r = await orgCall(() => _api.students(q: _q, filter: _filter, page: _pageNo), quiet: true);
    if (!mounted || seq != _seq) return;
    setState(() {
      if (r.ok) {
        _page = r.data as AdvPage<AdvStudent>;
        _load = AdvLoad.ready;
      } else {
        _load = r.endpointMissing ? AdvLoad.missing : AdvLoad.failed;
        _error = orgErrorText(r.error!);
      }
    });
    if (r.ok && mounted) OrgPageRefresh.reportUpdated(context);
  }

  void _query({String? q, String? filter, int page = 1}) {
    setState(() {
      _q = q ?? _q;
      _filter = filter ?? _filter;
      _pageNo = page;
      _load = AdvLoad.loading;
    });
    _reload();
  }

  Future<void> _open(AdvStudent s) async {
    final reason = TextEditingController();
    var draft = AdvAdvisorsDraft.of(s);
    var busy = false, overCapacity = false, started = false;
    String? error;
    List<AdvHistoryEntry>? history;
    List<AdvConflict>? conflicts;
    final manage = widget.manage, multi = _multi;
    final saved = await showAppSheet<AdvStudent>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          if (!started) {
            started = true;
            orgCall(() => _api.history(s.memberId), quiet: true).then((r) {
              if (ctx.mounted) set(() => history = r.ok ? r.data as List<AdvHistoryEntry> : const []);
            });
            if (manage) {
              orgCall(() => _api.conflicts(memberId: s.memberId), quiet: true).then((r) {
                if (ctx.mounted) set(() => conflicts = r.ok ? (r.data as AdvPage<AdvConflict>).items : const []);
              });
            }
          }

          Future<void> pickPrimary() async {
            final a = await pickAdvAdvisor(ctx, _api, title: t('المرشد الأساسي', 'Primary advisor'), exclude: {for (final o in draft.others) o.userId});
            if (a != null) {
              set(() {
                draft = draft.copyWith(primary: () => AdvRef(userId: a.userId, name: a.name), force: false);
                overCapacity = false;
                error = null;
              });
            }
          }

          Future<void> addOther(String type) async {
            final a = await pickAdvAdvisor(ctx, _api,
                title: type == 'co' ? t('مرشد مشارك', 'Co-advisor') : t('مرشد داعم', 'Support advisor'),
                exclude: {if (draft.primary != null) draft.primary!.userId, for (final o in draft.others) o.userId});
            if (a != null) set(() => draft = draft.addOther(AdvRef(userId: a.userId, name: a.name), type));
          }

          Future<void> submit() async {
            final body = draft.copyWith(reason: reason.text);
            final why = body.error(multi: multi);
            if (why != null) {
              set(() => error = why);
              return;
            }
            set(() {
              busy = true;
              error = null;
            });
            final r = await orgCall(() => _api.saveAdvisors(s.memberId, body, multi: multi), quiet: true);
            if (!ctx.mounted) return;
            if (!r.ok) {
              set(() {
                busy = false;
                if (r.code == 'advising_over_capacity') overCapacity = true;
                error = r.code == 'advising_over_capacity'
                    ? t('المرشد بلغ حده الأقصى. اختر مرشداً آخر، أو فعّل «الإسناد رغم الحد الأقصى» مع سبب.',
                        'The advisor is at their maximum. Choose another advisor, or turn on "Assign anyway" with a reason.')
                    : orgErrorText(r.error!);
              });
              return;
            }
            showAppNotice(t('حُفظ مرشدو الطالب', 'Advisors saved'));
            Navigator.pop(ctx, r.data as AdvStudent);
          }

          Future<void> addConflict() async {
            final x = await showAdvConflictSheet(ctx, _api, student: s);
            if (x == null || !ctx.mounted) return;
            set(() => conflicts = [...?conflicts, x]);
            if (x.assignedNow) {
              showAppNotice(t('${x.advisor.shown} يرشد هذا الطالب الآن — اختر له مرشداً آخر.', '${x.advisor.shown} advises this student now — choose another advisor.'));
            }
          }

          Future<void> removeConflict(AdvConflict x) async {
            if (!await appConfirm(ctx, danger: true, confirmLabel: t('إزالة', 'Remove'), message: t('إزالة تعارض المصالح مع ${x.advisor.shown}؟', 'Remove the conflict of interest with ${x.advisor.shown}?'))) {
              return;
            }
            final r = await orgCall(() => _api.removeConflict(x.id), ok: t('أُزيل التعارض', 'Conflict removed'));
            if (r.ok && ctx.mounted) set(() => conflicts = [for (final y in conflicts ?? const <AdvConflict>[]) if (y.id != x.id) y]);
          }

          return AppSheetContent(
            title: manage ? t('مرشدو الطالب', 'Student\'s advisors') : t('الطالب', 'Student'),
            children: [
              AdvStudentForm(
                student: s,
                draft: draft,
                multi: multi,
                manage: manage,
                reason: reason,
                overCapacity: overCapacity,
                history: history,
                conflicts: conflicts,
                busy: busy,
                error: error,
                onPickPrimary: pickPrimary,
                onClearPrimary: () => set(() => draft = draft.copyWith(primary: () => null, locked: false, others: const [])),
                onLocked: (v) => set(() => draft = draft.copyWith(locked: v)),
                onAddOther: addOther,
                onRemoveOther: (id) => set(() => draft = draft.removeOther(id)),
                onForce: (v) => set(() => draft = draft.copyWith(force: v)),
                onSubmit: submit,
                onAddConflict: manage ? addConflict : null,
                onRemoveConflict: manage ? removeConflict : null,
              ),
            ],
          );
        }));
    if (saved != null && mounted) _reload();
  }

  Future<void> _distribute() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvDistributePage(orgId: widget.orgId)));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => AdvStudentsView(
        load: _load,
        manage: widget.manage,
        page: _page,
        filter: _filter,
        errorText: _error,
        onRetry: () => _query(),
        onSearch: (q) => _query(q: q),
        onFilter: (f) => _query(filter: f),
        onPage: (p) => _query(page: p),
        onOpen: _open,
        onDistribute: widget.manage ? _distribute : null,
      );
}
