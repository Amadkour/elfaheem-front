// lib/features/org/advising/adv_workspace_page.dart — the advisor's workspace (docs/advising/PHASE4.md "Workspace
// list", #21): my students (a director: every student), sorted by risk; a debounced search and ONE filter control (a
// sheet with cohort, level, program, standing, category, priority, flags, the order, and — directors — one advisor's
// students); each card shows the risk score as a calm meter with its top reason, the highest open-flag priority and
// the last contact. Tapping a card opens the student 360 (adv_student_page.dart). The registrar's advising cases keep
// their screen (OrgAdvisingScreen), linked here as "Registration cases"; directors also reach the categories.
//
//   AdvCaseCard             one student                  AdvWorkspaceView     the list (plain values)
//   AdvWorkspaceFilterForm  the filter sheet's content   AdvFiltersButton     the one filter control
//   AdvWorkspacePage        loads `GET …/workspace`
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/offline/app_connectivity.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/live_events.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_header.dart' show OrgPageRefresh, OrgPushedPage;
import '../org_page_kit.dart';
import '../org_registrar.dart' show standingText;
import '../org_registrar_member.dart' show openAdvising;
import '../org_v3.dart' show orgCall;
import 'adv_api.dart';
import 'adv_case_parts.dart';
import 'adv_categories_page.dart';
import 'adv_draft_store.dart';
import 'adv_models.dart';
import 'adv_parts.dart';
import 'adv_student_page.dart';

/// A standing's label (the registrar's, else the value itself).
String advStandingLabel(String s) {
  final l = standingText(s);
  return l.isEmpty ? s : l;
}

class AdvCaseCard extends StatelessWidget {
  const AdvCaseCard({super.key, required this.item, this.categoryNames = const {}, this.showAdvisor = false, this.onTap, this.now});
  final AdvCaseItem item;

  /// Category key → name (the categories list); an unknown key shows its built-in name.
  final Map<String, String> categoryNames;

  /// Directors: the student's primary advisor under the card.
  final bool showAdvisor;
  final VoidCallback? onTap;

  /// The clock for "last contact" (tests pin it).
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = item;
    final top = s.topReason;
    final reason = top == null ? null : advRiskReasonText(top, flags: s.openFlags);
    final highest = s.openFlags.highest;
    final days = advDaysSince(s.lastContactAt, now: now);
    final stale = days == null || days > 30;
    final cats = [for (final k in s.categories) categoryNames[k] ?? advCategoryKeyLabel(k)];
    final contact = advLastContactText(s.lastContactAt, now: now);
    return AdvRowCard(
      title: s.shown,
      subtitle: s.subtitle.isEmpty ? null : s.subtitle,
      avatarName: s.shown,
      semanticLabel: [
        s.shown,
        t('درجة الخطر ${s.riskScore}', 'risk ${s.riskScore}'),
        ?reason,
        if (highest != null) t('أعلى تنبيه ${advPriorityLabel(highest)}', 'highest flag ${advPriorityLabel(highest)}'),
        contact,
      ].join('، '),
      trailing: highest == null ? null : AdvPriorityPill(priority: highest, count: s.openFlags.of(highest)),
      onTap: onTap,
      below: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AdvRiskMeter(score: s.riskScore, reason: reason),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _Fact(icon: Icons.forum_outlined, text: contact, tone: stale ? c.warning : null),
          if (s.cgpa != null) _Fact(icon: Icons.school_outlined, text: t('المعدل ${advGpa(s.cgpa)}', 'CGPA ${advGpa(s.cgpa)}')),
          if (showAdvisor)
            _Fact(icon: Icons.co_present_outlined, text: s.primary == null ? t('بلا مرشد', 'No advisor') : s.primary!.shown, tone: s.primary == null ? c.warning : null),
        ]),
        if (cats.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
            for (final n in cats.take(3)) AppTag(n, c.textMedium),
            if (cats.length > 3) AppTag('+${cats.length - 3}', c.textMedium),
          ]),
        ],
      ]),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text, this.tone});
  final IconData icon;
  final String text;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = tone == null ? c.textMedium : appInk(context, tone!);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ExcludeSemantics(child: Icon(icon, size: AppIconSize.sm, color: ink)),
      const SizedBox(width: AppSpace.xxs),
      Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: tone == null ? null : ink))),
    ]);
  }
}

/// The one filter control of the toolbar: "Filters · 2" (tinted while any is on); opens the filter sheet.
class AdvFiltersButton extends StatelessWidget {
  const AdvFiltersButton({super.key, required this.count, required this.onTap, this.sortLabel});
  final int count;
  final VoidCallback onTap;

  /// The current order when it is not the default ("Name").
  final String? sortLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = count > 0 || sortLabel != null;
    final ink = active ? orgInk(context) : c.textMedium;
    final label = [
      count > 0 ? t('التصفية · $count', 'Filters · $count') : t('التصفية', 'Filters'),
      ?sortLabel,
    ].join(' · ');
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: active ? c.primaryTint : c.cardBg,
        borderRadius: AppRadius.chipAll,
        child: InkWell(
          key: const ValueKey('adv.workspace.filters'),
          borderRadius: AppRadius.chipAll,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
            decoration: BoxDecoration(borderRadius: AppRadius.chipAll, border: Border.all(color: active ? orgInk(context).withValues(alpha: 0.45) : c.divider)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.tune_rounded, size: AppIconSize.sm, color: ink),
              const SizedBox(width: AppSpace.xs),
              Flexible(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: active ? orgInk(context) : c.textDark)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The filter sheet's content (plain values). Every change goes to [onChanged]; [onApply] closes the sheet.
class AdvWorkspaceFilterForm extends StatelessWidget {
  const AdvWorkspaceFilterForm({
    super.key,
    required this.query,
    required this.choices,
    required this.manage,
    required this.onChanged,
    this.onPickAdvisor,
    this.onApply,
  });

  final AdvWorkspaceQuery query;
  final AdvWorkspaceChoices choices;
  final bool manage;
  final ValueChanged<AdvWorkspaceQuery> onChanged;
  final VoidCallback? onPickAdvisor, onApply;

  @override
  Widget build(BuildContext context) {
    final q = query;
    Widget dropdown<T>({required String label, required T? value, required List<(T, String)> options, required ValueChanged<T?> onPick}) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppDropdown<T?>(
            value: value,
            decoration: InputDecoration(labelText: label),
            items: [
              DropdownMenuItem<T?>(value: null, child: Text(t('الكل', 'All'))),
              for (final (v, l) in options) DropdownMenuItem<T?>(value: v, child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: onPick,
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AdvFieldLabel(t('الترتيب', 'Order')),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final s in advWorkspaceSorts)
          AppChoiceChip(label: advWorkspaceSortLabel(s), selected: q.sort == s, onTap: () => onChanged(q.copyWith(sort: s, page: 1))),
      ]),
      const SizedBox(height: AppSpace.md),
      AdvFieldLabel(t('التنبيهات', 'Flags')),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final f in advFlagFilters) AppChoiceChip(label: advFlagFilterLabel(f), selected: q.flag == f, onTap: () => onChanged(q.copyWith(flag: f, page: 1))),
      ]),
      const SizedBox(height: AppSpace.md),
      AdvFieldLabel(t('الأولوية', 'Priority')),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppChoiceChip(label: t('الكل', 'Any'), selected: q.priority == null, onTap: () => onChanged(q.copyWith(priority: () => null, page: 1))),
        for (final p in advPriorities)
          AppChoiceChip(label: advPriorityLabel(p), selected: q.priority == p, onTap: () => onChanged(q.copyWith(priority: () => p, page: 1))),
      ]),
      const SizedBox(height: AppSpace.md),
      if (manage) ...[
        AdvPersonField(
          label: t('المرشد', 'Advisor'),
          name: q.advisor?.shown,
          placeholder: t('كل المرشدين', 'Every advisor'),
          onPick: onPickAdvisor,
          onClear: () => onChanged(q.copyWith(advisor: () => null, page: 1)),
        ),
        const SizedBox(height: AppSpace.sm),
      ],
      if (choices.categories.isNotEmpty)
        dropdown<int>(
          label: t('تصنيف تنبيه مفتوح', 'Category of an open flag'),
          value: q.categoryId,
          options: [for (final c in choices.categories) (c.id, c.name)],
          onPick: (v) => onChanged(q.copyWith(categoryId: () => v, page: 1)),
        ),
      if (choices.programs.isNotEmpty)
        dropdown<int>(
          label: t('البرنامج', 'Program'),
          value: q.programId,
          options: [for (final p in choices.programs) (p.id, p.name)],
          onPick: (v) => onChanged(q.copyWith(programId: () => v, page: 1)),
        ),
      if (choices.levels.isNotEmpty)
        dropdown<String>(
          label: t('المستوى', 'Level'),
          value: q.level,
          options: [for (final l in choices.levels) (l, l)],
          onPick: (v) => onChanged(q.copyWith(level: () => v, page: 1)),
        ),
      if (choices.cohorts.isNotEmpty)
        dropdown<String>(
          label: t('الدفعة', 'Cohort'),
          value: q.cohort,
          options: [for (final c in choices.cohorts) (c, c)],
          onPick: (v) => onChanged(q.copyWith(cohort: () => v, page: 1)),
        ),
      dropdown<String>(
        label: t('الوضع الأكاديمي', 'Academic standing'),
        value: q.standing,
        options: [for (final s in choices.standings) (s, advStandingLabel(s))],
        onPick: (v) => onChanged(q.copyWith(standing: () => v, page: 1)),
      ),
      const SizedBox(height: AppSpace.xs),
      if (onApply != null) AppPrimaryButton(icon: Icons.check_rounded, label: t('عرض النتائج', 'Show results'), onPressed: onApply),
      if (q.activeFilters > 0 || q.sort != 'risk')
        TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
          onPressed: () => onChanged(AdvWorkspaceQuery(q: q.q, size: q.size)),
          icon: const Icon(Icons.filter_alt_off_rounded, size: AppIconSize.md),
          label: Text(t('مسح التصفية والترتيب', 'Clear the filters and the order')),
        ),
    ]);
  }
}

/// The calm counts above the list: how many students, open flags, urgent, no contact in 30 days.
class _Facets extends StatelessWidget {
  const _Facets({required this.page});
  final AdvPage<AdvCaseItem> page;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = page.facets.containsKey('total') ? page.facet('total') : page.total;
    final open = page.facet('open'), urgent = page.facet('urgent'), quiet = page.facet('no_contact_30d');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(
          countText(page.total, ar1: 'طالب واحد', ar2: 'طالبان', arFew: '${page.total} طلاب', arMany: '${page.total} طالباً', en1: '1 student', en: '${page.total} students') +
              (total != page.total ? t(' من $total', ' of $total') : ''),
          style: AppType.meta(context),
        ),
        if (urgent > 0) AppBadgePill(t('عاجل · $urgent', 'Urgent · $urgent'), color: c.danger, icon: Icons.priority_high_rounded),
        if (open > 0) AppBadgePill(t('لهم تنبيهات · $open', 'With open flags · $open'), color: c.warning, icon: Icons.flag_rounded),
        if (quiet > 0) AppBadgePill(t('بلا تواصل منذ 30 يوماً · $quiet', 'No contact in 30 days · $quiet'), color: c.textMedium, icon: Icons.forum_outlined),
      ]),
    );
  }
}

class AdvWorkspaceView extends StatelessWidget {
  const AdvWorkspaceView({
    super.key,
    required this.load,
    required this.manage,
    required this.query,
    this.page,
    this.errorText,
    this.categoryNames = const {},
    this.now,
    this.onRetry,
    this.onSearch,
    this.onFilters,
    this.onClearFilters,
    this.onPage,
    this.onOpen,
    this.onRegistrationCases,
    this.onCategories,
  });

  final AdvLoad load;

  /// A director (every student; the advisor shows on each card).
  final bool manage;
  final AdvWorkspaceQuery query;
  final AdvPage<AdvCaseItem>? page;
  final String? errorText;
  final Map<String, String> categoryNames;
  final DateTime? now;
  final VoidCallback? onRetry, onFilters, onClearFilters, onRegistrationCases, onCategories;
  final ValueChanged<String>? onSearch;
  final ValueChanged<int>? onPage;
  final ValueChanged<AdvCaseItem>? onOpen;

  @override
  Widget build(BuildContext context) {
    final p = page;
    final filtered = query.activeFilters > 0 || query.q.trim().isNotEmpty;
    Widget body;
    if (load != AdvLoad.ready || p == null) {
      body = AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry);
    } else if (p.items.isEmpty) {
      body = filtered
          ? AppEmpty(
              icon: Icons.filter_alt_off_rounded,
              title: t('لا طلاب يطابقون', 'No students match'),
              message: t('جرّب بحثاً آخر أو امسح التصفية.', 'Try another search or clear the filters.'),
              actionLabel: query.activeFilters > 0 && onClearFilters != null ? t('مسح التصفية', 'Clear the filters') : null,
              onAction: query.activeFilters > 0 ? onClearFilters : null,
            )
          : AppEmpty(
              icon: Icons.groups_rounded,
              title: manage ? t('لا طلاب بعد', 'No students yet') : t('لم يُسند إليك طلاب بعد', 'No students are assigned to you yet'),
              message: manage
                  ? t('يظهر الطلاب هنا بعد توزيعهم على المرشدين.', 'Students show here once they are assigned to advisors.')
                  : t('يظهر طلابك هنا حين يسندهم إليك مدير الإرشاد.', 'Your students show here when the advising director assigns them to you.'),
            );
    } else {
      body = AdvPageFrame(maxWidth: 960, children: [
        _Facets(page: p),
        for (final s in p.items) AdvCaseCard(item: s, categoryNames: categoryNames, showAdvisor: manage, now: now, onTap: onOpen == null ? null : () => onOpen!(s)),
        if (p.pages > 1 && onPage != null) ...[
          const SizedBox(height: AppSpace.sm),
          AppPagination(page: p.page, pageCount: p.pages, total: p.total, pageSize: p.size, onPage: onPage!),
        ],
      ]);
    }
    return OrgPageBody(
      search: onSearch == null ? null : OrgSearchField(hint: t('ابحث بالاسم أو الرقم', 'Search by name or ID'), onChanged: onSearch!),
      filter: onFilters == null
          ? null
          : AdvFiltersButton(count: query.activeFilters, sortLabel: query.sort == 'risk' ? null : advWorkspaceSortLabel(query.sort), onTap: onFilters!),
      more: [
        if (onRegistrationCases != null) OrgMenuItem(icon: Icons.assignment_outlined, label: t('حالات التسجيل', 'Registration cases'), onTap: onRegistrationCases!),
        if (onCategories != null) OrgMenuItem(icon: Icons.label_outline_rounded, label: t('التصنيفات', 'Categories'), onTap: onCategories!),
      ],
      child: body,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class AdvWorkspacePage extends StatelessWidget {
  const AdvWorkspacePage({super.key, required this.orgId, required this.manage, this.sort = 'risk'});
  final int orgId;

  /// An org admin / advising director (else an advisor's own students).
  final bool manage;

  /// The first order (Phase 6: a "no contact" reminder opens it by last contact).
  final String sort;

  @override
  Widget build(BuildContext context) => OrgPushedPage(
        title: manage ? t('مساحة الإرشاد', 'Advising workspace') : t('طلابي', 'My students'),
        helpPageId: 'org.advising',
        maxWidth: 960,
        child: _AdvWorkspaceBody(orgId: orgId, manage: manage, sort: sort),
      );
}

class _AdvWorkspaceBody extends StatefulWidget {
  const _AdvWorkspaceBody({required this.orgId, required this.manage, this.sort = 'risk'});
  final int orgId;
  final bool manage;
  final String sort;

  @override
  State<_AdvWorkspaceBody> createState() => _AdvWorkspaceBodyState();
}

class _AdvWorkspaceBodyState extends State<_AdvWorkspaceBody> {
  late final AdvApi _api = AdvApi(widget.orgId);
  OrgPageRefresh? _refresh;
  StreamSubscription<LiveEvent>? _live;
  AdvPage<AdvCaseItem>? _page;
  AdvLoad _load = AdvLoad.loading;
  String? _error;
  late AdvWorkspaceQuery _query = AdvWorkspaceQuery(sort: advWorkspaceSorts.contains(widget.sort) ? widget.sort : 'risk');
  int _seq = 0;
  List<AdvCategory> _categories = const [];
  AdvPolicyOptions? _options;

  /// Every student listed so far (an advisor's filter choices come from them).
  final Map<int, AdvCaseItem> _seen = {};

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _reload);
    _live = LiveEvents.instance.listen({LiveEvents.connectivity}, (_) {
      if (mounted && AppConnectivity.instance.isOnline && _load != AdvLoad.ready) _reload();
    });
    _reload();
    _loadChoices();
    AdvDraftStore.instance.flush();
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    _live?.cancel();
    super.dispose();
  }

  Future<void> _loadChoices() async {
    final cats = await orgCall(() => _api.categories(), quiet: true);
    if (mounted && cats.ok) setState(() => _categories = cats.data as List<AdvCategory>);
    if (!widget.manage) return;
    final pol = await orgCall(() => _api.policy(), quiet: true);
    if (mounted && pol.ok) setState(() => _options = (pol.data as AdvPolicyBundle).options);
  }

  Future<void> _reload() async {
    final seq = ++_seq;
    if (!AppConnectivity.instance.isOnline && _page == null) {
      setState(() => _load = AdvLoad.offline);
      return;
    }
    final r = await orgCall(() => _api.workspace(_query, manage: widget.manage), quiet: true);
    if (!mounted || seq != _seq) return;
    setState(() {
      if (r.ok) {
        final p = r.data as AdvPage<AdvCaseItem>;
        _page = p;
        _load = AdvLoad.ready;
        for (final s in p.items) {
          _seen[s.memberId] = s;
        }
      } else {
        _load = advFailLoad(r);
        _error = advErrorText(r.error!);
        _page = null;
      }
    });
    if (r.ok && mounted) OrgPageRefresh.reportUpdated(context);
  }

  void _set(AdvWorkspaceQuery q) {
    setState(() {
      _query = q;
      _load = AdvLoad.loading;
    });
    _reload();
  }

  AdvWorkspaceChoices get _choices => AdvWorkspaceChoices.from(options: _options, seen: _seen.values, categories: _categories);

  Future<void> _filters() async {
    var draft = _query;
    final apply = await showAppSheet<bool>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          Future<void> pickAdvisor() async {
            final a = await pickAdvAdvisor(ctx, _api, title: t('طلاب مرشد', 'One advisor\'s students'), allowAway: true);
            if (a != null) set(() => draft = draft.copyWith(advisor: () => AdvRef(userId: a.userId, name: a.name), page: 1));
          }

          return AppSheetContent(
            title: t('التصفية والترتيب', 'Filter and order'),
            children: [
              AdvWorkspaceFilterForm(
                query: draft,
                choices: _choices,
                manage: widget.manage,
                onChanged: (q) => set(() => draft = q),
                onPickAdvisor: widget.manage ? pickAdvisor : null,
                onApply: () => Navigator.pop(ctx, true),
              ),
            ],
          );
        }));
    if (apply == true && mounted) _set(draft.copyWith(page: 1));
  }

  Future<void> _open(AdvCaseItem s) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvStudentPage(orgId: widget.orgId, memberId: s.memberId, name: s.shown)));
    if (mounted) _reload();
  }

  Future<void> _openCategories() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvCategoriesPage(orgId: widget.orgId)));
    if (mounted) _loadChoices();
  }

  @override
  Widget build(BuildContext context) => AdvWorkspaceView(
        load: _load,
        manage: widget.manage,
        query: _query,
        page: _page,
        errorText: _error,
        categoryNames: {for (final c in _categories) c.key: c.name},
        onRetry: () => _set(_query),
        onSearch: (q) => _set(_query.copyWith(q: q, page: 1)),
        onFilters: _filters,
        onClearFilters: () => _set(_query.cleared()),
        onPage: (p) => _set(_query.copyWith(page: p)),
        onOpen: _open,
        onRegistrationCases: () => openAdvising(context, widget.orgId),
        onCategories: widget.manage ? _openCategories : null,
      );
}
