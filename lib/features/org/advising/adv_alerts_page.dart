// lib/features/org/advising/adv_alerts_page.dart — the early-warning alerts (docs/advising/PHASE6.md "Alerts", #7,
// #20): two tabs, Alerts (newest first, ONE filter control: priority, rule, since, the flag's state) and Graduation
// (`GET …/graduation`, delayed first, with status counts). An alert card names the student, the rule, the
// explanation in the app language, when it fired, its flag's state, and offers "Open student" · "Propose a meeting".
// The header's "Alert delivery" opens the advisor's own digest choice (AdvAlertPrefsView).
//
//   AdvAlertsView         the page's content (plain values)     AdvAlertFilterForm   the filter sheet's content
//   AdvAlertsPage         loads the two lists through AdvWarningApi
//   showAdvAlertPrefsSheet   `GET / PUT …/alerts/prefs`
//   advProposeMeeting     "Propose a meeting": the 360's note composer set to log a contact (Phase 5's booking
//                         sheet takes its place once merged)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_header.dart' show OrgHeaderButton, OrgPageRefresh, OrgPushedPage;
import '../org_page_kit.dart';
import '../org_v3.dart' show orgCall;
import 'adv_models.dart';
import 'adv_parts.dart';
import 'adv_student_page.dart' show AdvStudentPage;
import 'adv_warning_api.dart';
import 'adv_warning_models.dart';
import 'adv_warning_parts.dart';
import 'adv_workspace_page.dart' show AdvFiltersButton;

/// The page's tabs.
const advAlertTabs = ['alerts', 'graduation'];

/// Opens [memberId]'s 360 ready to log a contact (the note composer with "log as contact" on).
Future<void> advProposeMeeting(BuildContext context, {required int orgId, required int memberId, String? name}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvStudentPage(orgId: orgId, memberId: memberId, name: name, section: 'meetings')));

class _AlertFacets extends StatelessWidget {
  const _AlertFacets({required this.page});
  final AdvPage<AdvAlert> page;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final urgent = page.facet('urgent'), high = page.facet('high'), week = page.facet('last_7d');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(countText(page.total, ar1: 'تنبيه واحد', ar2: 'تنبيهان', arFew: '${page.total} تنبيهات', arMany: '${page.total} تنبيهاً', en1: '1 alert', en: '${page.total} alerts'), style: AppType.meta(context)),
        if (urgent > 0) AppBadgePill(t('عاجلة · $urgent', 'Urgent · $urgent'), color: c.danger, icon: Icons.priority_high_rounded),
        if (high > 0) AppBadgePill(t('عالية · $high', 'High · $high'), color: c.warning, icon: Icons.flag_rounded),
        if (week > 0) AppBadgePill(t('آخر 7 أيام · $week', 'Last 7 days · $week'), color: c.textMedium, icon: Icons.schedule_rounded),
      ]),
    );
  }
}

class _GradFacets extends StatelessWidget {
  const _GradFacets({required this.page});
  final AdvPage<AdvGraduationItem> page;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final s in const ['delayed', 'at_risk', 'on_track', 'unknown'])
            if (page.facet(s) > 0) AppBadgePill('${advGraduationStatusLabel(s)} · ${page.facet(s)}', color: advGraduationColor(context, s)),
        ]),
      );
}

class AdvAlertsView extends StatelessWidget {
  const AdvAlertsView({
    super.key,
    required this.tab,
    required this.manage,
    this.alertsLoad = AdvLoad.loading,
    this.alerts,
    this.alertQuery = const AdvAlertQuery(),
    this.alertsError,
    this.gradLoad = AdvLoad.loading,
    this.graduation,
    this.gradQuery = const AdvGraduationQuery(),
    this.gradError,
    this.studentName,
    this.onTab,
    this.onRetry,
    this.onFilters,
    this.onClearFilters,
    this.onAlertsPage,
    this.onOpenStudent,
    this.onPropose,
    this.onGradStatus,
    this.onGradSearch,
    this.onGradPage,
    this.onOpenGrad,
  });

  final String tab;

  /// A director (every student: the advisor shows in the graduation list).
  final bool manage;
  final AdvLoad alertsLoad;
  final AdvPage<AdvAlert>? alerts;
  final AdvAlertQuery alertQuery;
  final String? alertsError;
  final AdvLoad gradLoad;
  final AdvPage<AdvGraduationItem>? graduation;
  final AdvGraduationQuery gradQuery;
  final String? gradError;

  /// The student the list is limited to (a deep link), shown as a removable filter.
  final String? studentName;
  final ValueChanged<String>? onTab;
  final VoidCallback? onRetry, onFilters, onClearFilters;
  final ValueChanged<int>? onAlertsPage, onGradPage;
  final ValueChanged<AdvAlert>? onOpenStudent, onPropose;
  final ValueChanged<String>? onGradStatus, onGradSearch;
  final ValueChanged<AdvGraduationItem>? onOpenGrad;

  @override
  Widget build(BuildContext context) {
    final top = OrgSegmented<String>(
      value: tab,
      options: [('alerts', t('التنبيهات', 'Alerts')), ('graduation', t('التخرج', 'Graduation'))],
      onChanged: (v) => onTab?.call(v),
    );
    if (tab == 'graduation') {
      return OrgPageBody(
        top: top,
        search: onGradSearch == null ? null : OrgSearchField(hint: t('ابحث بالاسم أو الرقم', 'Search by name or ID'), onChanged: onGradSearch!),
        filter: onGradStatus == null
            ? null
            : OrgFilterButton<String>(
                value: gradQuery.status,
                defaultValue: 'all',
                label: t('حالة التخرج', 'Graduation status'),
                icon: Icons.school_outlined,
                options: {for (final v in advGraduationViews) v: advGraduationViewLabel(v)},
                onChanged: onGradStatus!,
              ),
        child: _graduationBody(context),
      );
    }
    return OrgPageBody(
      top: top,
      filter: onFilters == null ? null : AdvFiltersButton(count: alertQuery.activeFilters, onTap: onFilters!),
      child: _alertsBody(context),
    );
  }

  Widget _alertsBody(BuildContext context) {
    final c = context.colors;
    final p = alerts;
    if (alertsLoad != AdvLoad.ready || p == null) {
      return AdvLoadState(state: alertsLoad == AdvLoad.ready ? AdvLoad.loading : alertsLoad, errorText: alertsError, onRetry: onRetry);
    }
    final filtered = alertQuery.activeFilters > 0;
    if (p.items.isEmpty && p.restricted == 0) {
      return filtered
          ? AppEmpty(
              icon: Icons.filter_alt_off_rounded,
              title: t('لا تنبيهات تطابق', 'No alerts match'),
              message: t('جرّب تصفية أخرى أو امسحها.', 'Try another filter or clear it.'),
              actionLabel: onClearFilters == null ? null : t('مسح التصفية', 'Clear the filters'),
              onAction: onClearFilters,
            )
          : AppEmpty(
              icon: Icons.notifications_none_rounded,
              title: t('لا تنبيهات بعد', 'No alerts yet'),
              message: manage
                  ? t('حين يطابق طالب إحدى القواعد يظهر التنبيه هنا مع سببه.', 'When a student matches a rule, the alert shows here with its reason.')
                  : t('حين يطابق أحد طلابك إحدى القواعد يظهر التنبيه هنا مع سببه.', 'When one of your students matches a rule, the alert shows here with its reason.'),
            );
    }
    return AdvPageFrame(maxWidth: 1440, children: [
      if (studentName != null)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: AppBanner(icon: Icons.person_outline_rounded, text: t('تنبيهات $studentName فقط', 'Only $studentName\'s alerts')),
        ),
      _AlertFacets(page: p),
      for (final a in p.items)
        AdvAlertCard(
          alert: a,
          onOpenStudent: onOpenStudent == null ? null : () => onOpenStudent!(a),
          onProposeMeeting: onPropose == null ? null : () => onPropose!(a),
        ),
      if (p.restricted > 0)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          child: Row(children: [
            ExcludeSemantics(child: Icon(Icons.lock_outline_rounded, size: AppIconSize.sm, color: c.textMedium)),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Text(
                countText(p.restricted,
                    ar1: 'تنبيه حساس واحد لا يظهر لك — يراه المرشد الأساسي ومديرو الإرشاد', ar2: 'تنبيهان حساسان لا يظهران لك — يراهما المرشد الأساسي ومديرو الإرشاد',
                    arFew: '${p.restricted} تنبيهات حساسة لا تظهر لك — يراها المرشد الأساسي ومديرو الإرشاد', arMany: '${p.restricted} تنبيهاً حساساً لا يظهر لك — يراها المرشد الأساسي ومديرو الإرشاد',
                    en1: '1 sensitive alert is hidden from you — the primary advisor and the directors see it',
                    en: '${p.restricted} sensitive alerts are hidden from you — the primary advisor and the directors see them'),
                style: AppType.meta(context),
              ),
            ),
          ]),
        ),
      if (p.pages > 1 && onAlertsPage != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppPagination(page: p.page, pageCount: p.pages, total: p.total, pageSize: p.size, onPage: onAlertsPage!),
      ],
    ]);
  }

  Widget _graduationBody(BuildContext context) {
    final p = graduation;
    if (gradLoad != AdvLoad.ready || p == null) {
      return AdvLoadState(state: gradLoad == AdvLoad.ready ? AdvLoad.loading : gradLoad, errorText: gradError, onRetry: onRetry);
    }
    if (p.items.isEmpty) {
      final searching = gradQuery.q.trim().isNotEmpty;
      return AppEmpty(
        icon: searching ? Icons.search_off_rounded : Icons.verified_rounded,
        title: searching
            ? t('لا طلاب يطابقون البحث', 'No students match the search')
            : switch (gradQuery.status) {
                'delayed' => t('لا أحد متأخر عن التخرج', 'Nobody is behind for graduation'),
                'at_risk' => t('لا أحد معرّض للتأخر', 'Nobody is at risk of graduating late'),
                _ => t('لا طلاب بعد', 'No students yet'),
              },
        message: searching ? null : t('يُحسب موعد التخرج لكل طالب مع كل فحص.', 'Each student\'s graduation is projected with every check.'),
      );
    }
    return AdvPageFrame(maxWidth: 1440, children: [
      _GradFacets(page: p),
      for (final x in p.items) AdvGraduationRow(item: x, showAdvisor: manage, onTap: onOpenGrad == null ? null : () => onOpenGrad!(x)),
      if (p.pages > 1 && onGradPage != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppPagination(page: p.page, pageCount: p.pages, total: p.total, pageSize: p.size, onPage: onGradPage!),
      ],
    ]);
  }
}

/// The alerts filter sheet's content: priority, rule, since, the flag's state.
class AdvAlertFilterForm extends StatelessWidget {
  const AdvAlertFilterForm({super.key, required this.query, required this.rules, required this.onChanged, this.onApply});
  final AdvAlertQuery query;

  /// The rules to filter by (`GET …/rules`); empty: the rule filter is not offered.
  final List<AdvRule> rules;
  final ValueChanged<AdvAlertQuery> onChanged;
  final VoidCallback? onApply;

  int _sinceDays(DateTime? since) {
    if (since == null) return 0;
    final d = DateTime.now().difference(since).inHours;
    for (final x in advSinceDays.skip(1)) {
      if (d <= x * 24 + 1) return x;
    }
    return 30;
  }

  @override
  Widget build(BuildContext context) {
    final q = query;
    final since = _sinceDays(q.since);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AdvFieldLabel(t('الأولوية', 'Priority')),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppChoiceChip(label: t('الكل', 'Any'), selected: q.priority == null, onTap: () => onChanged(q.copyWith(priority: () => null, page: 1))),
        for (final p in advPriorities.reversed) AppChoiceChip(label: advPriorityLabel(p), selected: q.priority == p, onTap: () => onChanged(q.copyWith(priority: () => p, page: 1))),
      ]),
      const SizedBox(height: AppSpace.md),
      AdvFieldLabel(t('منذ', 'Since')),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final d in advSinceDays)
          AppChoiceChip(
            label: advSinceLabel(d),
            selected: since == d,
            onTap: () => onChanged(q.copyWith(since: () => d == 0 ? null : DateTime.now().subtract(Duration(days: d)), page: 1)),
          ),
      ]),
      const SizedBox(height: AppSpace.md),
      AdvFieldLabel(t('تنبيه المتابعة', 'The follow-up flag')),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final v in advAlertFlagViews) AppChoiceChip(label: advAlertFlagViewLabel(v), selected: q.flag == v, onTap: () => onChanged(q.copyWith(flag: v, page: 1))),
      ]),
      if (rules.isNotEmpty) ...[
        const SizedBox(height: AppSpace.md),
        AppDropdown<int?>(
          value: rules.any((r) => r.id == q.ruleId) ? q.ruleId : null,
          decoration: InputDecoration(labelText: t('القاعدة', 'Rule')),
          items: [
            DropdownMenuItem<int?>(value: null, child: Text(t('كل القواعد', 'Every rule'))),
            for (final r in rules) DropdownMenuItem<int?>(value: r.id, child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => onChanged(q.copyWith(ruleId: () => v, page: 1)),
        ),
      ],
      const SizedBox(height: AppSpace.md),
      if (onApply != null) AppPrimaryButton(icon: Icons.check_rounded, label: t('عرض النتائج', 'Show results'), onPressed: onApply),
      if (q.activeFilters > 0)
        TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
          onPressed: () => onChanged(AdvAlertQuery(size: q.size)),
          icon: const Icon(Icons.filter_alt_off_rounded, size: AppIconSize.md),
          label: Text(t('مسح التصفية', 'Clear the filters')),
        ),
    ]);
  }
}

/// The advisor's own alert delivery; true when it was saved.
Future<bool> showAdvAlertPrefsSheet(BuildContext context, AdvWarningApi api) async {
  AdvAlertPrefs? prefs;
  String chosen = 'inherit';
  var busy = false, started = false;
  String? error;
  final saved = await showAppSheet<bool>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        if (!started) {
          started = true;
          orgCall(() => api.prefs(), quiet: true).then((r) {
            if (!ctx.mounted) return;
            set(() {
              if (r.ok) {
                prefs = r.data as AdvAlertPrefs;
                chosen = prefs!.digest;
              } else {
                error = advWarningErrorText(r.error!);
              }
            });
          });
        }

        Future<void> save() async {
          set(() {
            busy = true;
            error = null;
          });
          final r = await orgCall(() => api.savePrefs(chosen), quiet: true);
          if (!ctx.mounted) return;
          if (!r.ok) {
            set(() {
              busy = false;
              error = advWarningErrorText(r.error!);
            });
            return;
          }
          final p = r.data as AdvAlertPrefs;
          showAppNotice(t('حُفظ: ${advDigestLabel(p.digest == 'inherit' ? p.effective : p.digest)}', 'Saved: ${advDigestLabel(p.digest == 'inherit' ? p.effective : p.digest)}'));
          Navigator.pop(ctx, true);
        }

        final p = prefs;
        return AppSheetContent(
          title: t('وصول التنبيهات', 'Alert delivery'),
          children: [
            if (p == null && error != null)
              AppBanner(icon: Icons.error_outline_rounded, color: ctx.colors.danger, text: error!)
            else if (p == null)
              const AppListSkeleton(items: 4, withAvatar: false, padding: EdgeInsets.zero)
            else
              AdvAlertPrefsView(prefs: p, chosen: chosen, busy: busy, error: error, onChoose: (d) => set(() => chosen = d), onSave: save),
          ],
        );
      }));
  return saved ?? false;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class AdvAlertsPage extends StatelessWidget {
  const AdvAlertsPage({super.key, required this.orgId, required this.manage, this.since, this.memberId, this.studentName, this.tab = 'alerts'});
  final int orgId;
  final bool manage;

  /// A digest's deep link: the alerts since then.
  final DateTime? since;

  /// One student's alerts (a flag's "alerts" link).
  final int? memberId;
  final String? studentName;
  final String tab;

  @override
  Widget build(BuildContext context) => Builder(builder: (context) {
        final api = AdvWarningApi(orgId);
        return OrgPushedPage(
          title: t('تنبيهات الإنذار المبكر', 'Early-warning alerts'),
          helpPageId: 'org.advising',
          maxWidth: 1440,
          primaryAction: OrgHeaderButton(icon: Icons.tune_rounded, label: t('وصول التنبيهات', 'Alert delivery'), onTap: () => showAdvAlertPrefsSheet(context, api)),
          child: _AdvAlertsBody(orgId: orgId, manage: manage, since: since, memberId: memberId, studentName: studentName, tab: advAlertTabs.contains(tab) ? tab : 'alerts'),
        );
      });
}

class _AdvAlertsBody extends StatefulWidget {
  const _AdvAlertsBody({required this.orgId, required this.manage, this.since, this.memberId, this.studentName, required this.tab});
  final int orgId;
  final bool manage;
  final DateTime? since;
  final int? memberId;
  final String? studentName;
  final String tab;

  @override
  State<_AdvAlertsBody> createState() => _AdvAlertsBodyState();
}

class _AdvAlertsBodyState extends State<_AdvAlertsBody> {
  late final AdvWarningApi _api = AdvWarningApi(widget.orgId);
  OrgPageRefresh? _refresh;
  late String _tab = widget.tab;

  late AdvAlertQuery _query = AdvAlertQuery(since: widget.since, memberId: widget.memberId);
  AdvPage<AdvAlert>? _alerts;
  AdvLoad _alertsLoad = AdvLoad.loading;
  String? _alertsError;
  int _alertSeq = 0;
  List<AdvRule> _rules = const [];

  AdvGraduationQuery _gq = const AdvGraduationQuery();
  AdvPage<AdvGraduationItem>? _grad;
  AdvLoad _gradLoad = AdvLoad.loading;
  String? _gradError;
  int _gradSeq = 0;
  bool _gradStarted = false;

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _reload);
    _loadAlerts();
    _loadRules();
    if (_tab == 'graduation') _loadGrad();
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    await Future.wait([_loadAlerts(), if (_gradStarted) _loadGrad()]);
    if (mounted) OrgPageRefresh.reportUpdated(context);
  }

  Future<void> _loadRules() async {
    final r = await orgCall(() => _api.rules(), quiet: true);
    if (mounted && r.ok) setState(() => _rules = (r.data as AdvRulesBundle).rules);
  }

  Future<void> _loadAlerts() async {
    final seq = ++_alertSeq;
    final q = _query;
    final r = await orgCall(() => _api.alerts(q), quiet: true);
    if (!mounted || seq != _alertSeq) return;
    setState(() {
      if (r.ok) {
        _alerts = r.data as AdvPage<AdvAlert>;
        _alertsLoad = AdvLoad.ready;
      } else {
        _alerts = null;
        _alertsLoad = advFailLoad(r);
        _alertsError = advWarningErrorText(r.error!);
      }
    });
  }

  Future<void> _loadGrad() async {
    _gradStarted = true;
    final seq = ++_gradSeq;
    final q = _gq;
    final r = await orgCall(() => _api.graduation(q), quiet: true);
    if (!mounted || seq != _gradSeq) return;
    setState(() {
      if (r.ok) {
        _grad = r.data as AdvPage<AdvGraduationItem>;
        _gradLoad = AdvLoad.ready;
      } else {
        _grad = null;
        _gradLoad = advFailLoad(r);
        _gradError = advWarningErrorText(r.error!);
      }
    });
  }

  void _setQuery(AdvAlertQuery q) {
    setState(() {
      _query = q;
      _alertsLoad = AdvLoad.loading;
    });
    _loadAlerts();
  }

  void _setGrad(AdvGraduationQuery q) {
    setState(() {
      _gq = q;
      _gradLoad = AdvLoad.loading;
    });
    _loadGrad();
  }

  Future<void> _filters() async {
    var q = _query;
    final apply = await showAppSheet<bool>(context, (ctx) => StatefulBuilder(builder: (ctx, set) => AppSheetContent(
          title: t('تصفية التنبيهات', 'Filter the alerts'),
          children: [AdvAlertFilterForm(query: q, rules: _rules, onChanged: (x) => set(() => q = x), onApply: () => Navigator.pop(ctx, true))],
        )));
    if (apply == true && mounted) _setQuery(q);
  }

  Future<void> _openStudent(int memberId, String name) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvStudentPage(orgId: widget.orgId, memberId: memberId, name: name)));
    if (mounted) _loadAlerts();
  }

  @override
  Widget build(BuildContext context) => AdvAlertsView(
        tab: _tab,
        manage: widget.manage,
        alertsLoad: _alertsLoad,
        alerts: _alerts,
        alertQuery: _query,
        alertsError: _alertsError,
        gradLoad: _gradLoad,
        graduation: _grad,
        gradQuery: _gq,
        gradError: _gradError,
        studentName: _query.memberId != null ? widget.studentName : null,
        onTab: (v) {
          setState(() => _tab = v);
          if (v == 'graduation' && !_gradStarted) _loadGrad();
        },
        onRetry: () {
          if (_tab == 'graduation') {
            _setGrad(_gq);
          } else {
            _setQuery(_query);
          }
        },
        onFilters: _filters,
        onClearFilters: () => _setQuery(AdvAlertQuery(size: _query.size)),
        onAlertsPage: (p) => _setQuery(_query.copyWith(page: p)),
        onOpenStudent: (a) => _openStudent(a.memberId, a.studentShown),
        onPropose: (a) async {
          await advProposeMeeting(context, orgId: widget.orgId, memberId: a.memberId, name: a.studentShown);
          if (mounted) _loadAlerts();
        },
        onGradStatus: (s) => _setGrad(_gq.copyWith(status: s, page: 1)),
        onGradSearch: (s) => _setGrad(_gq.copyWith(q: s, page: 1)),
        onGradPage: (p) => _setGrad(_gq.copyWith(page: p)),
        onOpenGrad: (x) => _openStudent(x.memberId, x.shown),
      );
}
