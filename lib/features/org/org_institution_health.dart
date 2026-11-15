// lib/features/org/org_institution_health.dart
//
// Institutions v2, phase 6 (docs/institutions/V2_PLAN.md item 6, D-998 – D-999): the manager's "Institution health".
//   GET …/institution/health   {ok, score 0–100, checks: [{key, severity block|warn|info, count, text_ar, text_en,
//                              action, ids}], generated_at}; the hourly job (server) repairs headless units and
//                              flags stale requests and chairless councils.
//   InstitutionHealthCheck · InstitutionHealth · institutionHealthFixOf · institutionHealthLinkAllowed   pure (tested)
//   InstitutionHealthCard     the Home card after the launch (plain values): the score, the top issue, opens the page
//   InstitutionHealthView     the page body (plain values): a calm score ring, the checks grouped by severity, a Fix
//                             button on each (a wizard step · the filtered governance list)
//   InstitutionHealthPage · openInstitutionHealth · openInstitutionHealthLink   the page (OrgPushedPage) and the
//                             AppNavigator target `org_institution_health` {org_id}
// Tests: test/org/institutions_v2_p6_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show asInt, asMapList, asStr, t;
import 'governance/gov_dashboard.dart' show dashboardTileFilter;
import 'governance/gov_items_page.dart' show GovItemsPage;
import 'governance/gov_wiring.dart' show govEnabled;
import 'org_dashboard_home.dart' show orgPush;
import 'org_institution_wizard.dart' show OrgInstitutionWizard, institutionWizardSteps, institutionWizardTitle, wizardStepLabel;
import 'org_institutions.dart' show orgInstitutionFeatureKey;
import 'org_page_header.dart' show OrgPushedPage;
import 'org_providers.dart' show OrgDashController, OrgSession;
import 'org_v3.dart' show orgCall, orgParseUtc;

// ═════════════════════════════════════════════════════════════════════════════
//  Pure parts
// ═════════════════════════════════════════════════════════════════════════════

/// The severities, most urgent first (the page's group order).
const institutionHealthSeverities = ['block', 'warn', 'info'];

/// One finding of the health job.
class InstitutionHealthCheck {
  const InstitutionHealthCheck({
    required this.key,
    this.severity = 'warn',
    this.count = 0,
    this.textAr = '',
    this.textEn = '',
    this.action = '',
    this.ids = const [],
  });

  final String key, severity, textAr, textEn, action;
  final int count;
  final List<int> ids;

  String get text => t(textAr.isEmpty ? textEn : textAr, textEn.isEmpty ? textAr : textEn);

  factory InstitutionHealthCheck.fromJson(Map<String, dynamic> j) {
    final s = asStr(j['severity'], 'warn');
    return InstitutionHealthCheck(
      key: asStr(j['key']),
      severity: institutionHealthSeverities.contains(s) ? s : 'warn',
      count: asInt(j['count']),
      textAr: asStr(j['text_ar']),
      textEn: asStr(j['text_en']),
      action: asStr(j['action']),
      ids: [for (final v in (j['ids'] is List ? j['ids'] as List : const [])) if (asInt(v) > 0) asInt(v)],
    );
  }
}

/// The whole answer. [score] is 0–100 (clamped); an answer without one is derived from the checks.
class InstitutionHealth {
  const InstitutionHealth({this.ok = true, this.score = 100, this.checks = const [], this.generatedAt});
  final bool ok;
  final int score;
  final List<InstitutionHealthCheck> checks;
  final DateTime? generatedAt;

  factory InstitutionHealth.fromJson(Map<String, dynamic> j) {
    final checks = [
      for (final x in asMapList(j['checks']))
        if (asStr(x['key']).isNotEmpty) InstitutionHealthCheck.fromJson(x),
    ];
    final blocks = checks.where((c) => c.severity == 'block').length;
    final warns = checks.where((c) => c.severity == 'warn').length;
    final raw = j['score'] == null ? 100 - blocks * 20 - warns * 5 : asInt(j['score']);
    return InstitutionHealth(
      ok: j['ok'] == null ? blocks == 0 : j['ok'] == true,
      score: raw.clamp(0, 100),
      checks: checks,
      generatedAt: orgParseUtc(j['generated_at']),
    );
  }

  /// The checks of [severity], in the server's order.
  List<InstitutionHealthCheck> of(String severity) => [for (final c in checks) if (c.severity == severity) c];

  /// Severity → its checks, most urgent first; empty groups are left out.
  Map<String, List<InstitutionHealthCheck>> get grouped => {
        for (final s in institutionHealthSeverities)
          if (of(s).isNotEmpty) s: of(s),
      };

  /// What deserves a look (block + warn); info lines never count as issues.
  int get issueCount => checks.where((c) => c.severity != 'info').length;

  /// The first block, else the first warn; null when nothing needs a look.
  InstitutionHealthCheck? get top => of('block').firstOrNull ?? of('warn').firstOrNull;

  /// Nothing to show on the Home.
  bool get calm => issueCount == 0;
}

/// Where a check's Fix button goes.
enum InstitutionHealthFixKind { wizard, items, none }

class InstitutionHealthFix {
  const InstitutionHealthFix(this.kind, {this.step, this.tile});
  final InstitutionHealthFixKind kind;

  /// [InstitutionHealthFixKind.wizard]: the wizard step (`basics` … `review`).
  final String? step;

  /// [InstitutionHealthFixKind.items]: the governance dashboard tile whose filter opens the list (`overdue` ·
  /// `pending` · `all`), see `dashboardTileFilter`.
  final String? tile;

  @override
  bool operator ==(Object other) => other is InstitutionHealthFix && other.kind == kind && other.step == step && other.tile == tile;

  @override
  int get hashCode => Object.hash(kind, step, tile);

  @override
  String toString() => 'InstitutionHealthFix($kind, step: $step, tile: $tile)';
}

/// A wizard step (heads → the heads step) when the action names one; stale / orphan requests → the governance list
/// on that filter (overdue · still open); the module switched off or an unknown action → no button.
InstitutionHealthFix institutionHealthFixOf(InstitutionHealthCheck c, {bool governance = true}) {
  final a = c.action;
  if (institutionWizardSteps.contains(a)) return InstitutionHealthFix(InstitutionHealthFixKind.wizard, step: a);
  if (a == 'launch') return const InstitutionHealthFix(InstitutionHealthFixKind.wizard, step: 'review');
  final k = '${c.key} $a';
  bool has(List<String> words) => words.any(k.contains);
  final itemsLike = a == 'items' || a == 'governance' || has(const ['stale', 'overdue', 'orphan', 'unassigned', 'unrouted']);
  if (!itemsLike || !governance) return const InstitutionHealthFix(InstitutionHealthFixKind.none);
  final tile = has(const ['stale', 'overdue'])
      ? 'overdue'
      : has(const ['orphan', 'unassigned', 'unrouted'])
          ? 'pending'
          : 'all';
  return InstitutionHealthFix(InstitutionHealthFixKind.items, tile: tile);
}

/// The `org_institution_health` notification opens the page only for a manager of an organization while
/// organizations and the institution feature are on; anyone else lands on the notifications list.
bool institutionHealthLinkAllowed({required int? orgId, required bool orgsEnabled, required List<String> disabled, required bool manages}) =>
    orgId != null && orgsEnabled && manages && !disabled.contains(orgInstitutionFeatureKey);

String institutionHealthTitle() => t('صحة المؤسسة', 'Institution health');

/// One word for the score.
String institutionHealthVerdict(int score) => score >= 80
    ? t('بصحة جيدة', 'Healthy')
    : score >= 50
        ? t('تحتاج عناية', 'Needs care')
        : t('في خطر', 'At risk');

AppBlockTone _toneOf(int score) => score >= 80
    ? AppBlockTone.emerald
    : score >= 50
        ? AppBlockTone.gold
        : AppBlockTone.peach;

String institutionHealthGroupTitle(String severity, int n) => switch (severity) {
      'block' => countText(n, ar1: 'أمر يجب إصلاحه', ar2: 'أمران يجب إصلاحهما', arFew: '{n} أمور يجب إصلاحها', arMany: '{n} أمراً يجب إصلاحه',
          en1: '1 thing to fix', en: '{n} things to fix'),
      'warn' => countText(n, ar1: 'ملاحظة تستحق النظر', ar2: 'ملاحظتان تستحقان النظر', arFew: '{n} ملاحظات تستحق النظر', arMany: '{n} ملاحظة تستحق النظر',
          en1: '1 thing worth a look', en: '{n} things worth a look'),
      _ => countText(n, ar1: 'معلومة للاطلاع', ar2: 'معلومتان للاطلاع', arFew: '{n} معلومات للاطلاع', arMany: '{n} معلومة للاطلاع',
          en1: '1 note for you', en: '{n} notes for you'),
    };

/// Where a fix goes, said under the check ("Heads" · "Requests").
String? institutionHealthFixPlace(InstitutionHealthFix f) => switch (f.kind) {
      InstitutionHealthFixKind.wizard => wizardStepLabel(f.step ?? 'review'),
      InstitutionHealthFixKind.items => t('الطلبات والمعاملات', 'Requests'),
      InstitutionHealthFixKind.none => null,
    };

// ═════════════════════════════════════════════════════════════════════════════
//  The Home card
// ═════════════════════════════════════════════════════════════════════════════

/// The post-launch Home card: the score ring, the top issue, a tap opens the page.
class InstitutionHealthCard extends StatelessWidget {
  const InstitutionHealthCard({super.key, required this.health, required this.onOpen});
  final InstitutionHealth health;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final top = health.top;
    return Column(key: const ValueKey('inst.health.card'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppRingStat(
        label: institutionHealthTitle(),
        value: institutionHealthVerdict(health.score),
        progress: health.score / 100,
        tone: _toneOf(health.score),
        caption: top == null
            ? t('لا شيء يحتاج انتباهك', 'Nothing needs a look')
            : health.issueCount > 1
                ? '${top.text} · ${countText(health.issueCount - 1, ar1: 'وأمر آخر', ar2: 'وأمران آخران', arFew: 'و{n} أمور أخرى', arMany: 'و{n} أمراً آخر', en1: '1 more', en: '{n} more')}'
                : top.text,
        onTap: onOpen,
      ),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: AppButton.ghost(
            key: const ValueKey('inst.health.open'),
            label: top == null ? t('افتح صحة المؤسسة', 'Open institution health') : t('أصلح الآن', 'Fix it now'),
            trailingIcon: Icons.arrow_forward_rounded,
            onPressed: onOpen),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The page
// ═════════════════════════════════════════════════════════════════════════════

/// One check: what is wrong, where it is fixed, how many, Fix.
class InstitutionHealthRow extends StatelessWidget {
  const InstitutionHealthRow({super.key, required this.check, required this.fix, this.onFix});
  final InstitutionHealthCheck check;
  final InstitutionHealthFix fix;
  final VoidCallback? onFix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (icon, tone, word) = switch (check.severity) {
      'block' => (Icons.error_outline_rounded, c.danger, t('يجب إصلاحه', 'Must fix')),
      'warn' => (Icons.warning_amber_rounded, c.warning, t('يستحق النظر', 'Worth a look')),
      _ => (Icons.info_outline_rounded, c.textMedium, t('للاطلاع', 'For your information')),
    };
    final place = institutionHealthFixPlace(fix);
    final canFix = onFix != null && fix.kind != InstitutionHealthFixKind.none;
    return Material(
      color: c.cardBg,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: BorderSide(color: c.divider, width: AppBorder.hairline)),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.sm),
        child: Row(children: [
          Semantics(label: word, child: Icon(icon, color: appInk(context, tone), size: AppIconSize.lg)),
          AppSpace.gapSm,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(check.text, style: AppType.row(context)),
              if (place != null) ...[
                const SizedBox(height: AppSpace.xxs),
                Text(place, style: AppType.meta(context).copyWith(color: c.textMedium)),
              ],
            ]),
          ),
          if (check.count > 0) ...[AppSpace.gapXs, AppBadgePill('${check.count}', color: tone)],
          if (canFix) ...[
            AppSpace.gapXs,
            AppButton.ghost(
                key: ValueKey('health.fix.${check.key}'),
                size: AppButtonSize.sm,
                label: check.severity == 'info' ? t('افتح', 'Open') : t('أصلح', 'Fix'),
                onPressed: onFix),
          ],
        ]),
      ),
    );
  }
}

/// The page body, plain values (layout-tested): the score, then the checks grouped by severity.
class InstitutionHealthView extends StatelessWidget {
  const InstitutionHealthView({super.key, required this.health, this.onFix, this.governance = true});
  final InstitutionHealth health;
  final void Function(InstitutionHealthCheck check, InstitutionHealthFix fix)? onFix;

  /// The governance module is on (stale / orphan requests get their Fix button).
  final bool governance;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final at = health.generatedAt;
    final groups = health.grouped;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
          t('نفحص المؤسسة كل ساعة: الوحدات بلا رئيس، والطلبات المتأخرة، والمجالس بلا رئيس. ابدأ بما يجب إصلاحه.',
              'We check the institution every hour: units without a head, late requests, councils without a chair. Start with what must be fixed.'),
          style: AppType.body(context).copyWith(color: c.textMedium)),
      AppSpace.gapSm,
      AppRingStat(
        key: const ValueKey('inst.health.score'),
        label: t('درجة الصحة', 'Health score'),
        value: institutionHealthVerdict(health.score),
        progress: health.score / 100,
        tone: _toneOf(health.score),
        caption: at == null ? null : t('آخر فحص ${AppTime.dateTime(at)}', 'Checked ${AppTime.dateTime(at)}'),
      ),
      if (groups.isEmpty) ...[
        AppSpace.gapLg,
        AppEmpty(
          key: const ValueKey('inst.health.empty'),
          icon: Icons.health_and_safety_rounded,
          tone: AppBlockTone.emerald,
          title: t('كل شيء على ما يرام', 'All healthy'),
          message: t('لا توجد ملاحظات الآن. سنخبرك إن ظهر شيء.', 'Nothing to look at right now. We will tell you if something comes up.'),
        ),
      ],
      for (final e in groups.entries) ...[
        AppSpace.gapLg,
        Semantics(
          header: true,
          child: Text(institutionHealthGroupTitle(e.key, e.value.length),
              key: ValueKey('health.group.${e.key}'), style: AppType.section(context)),
        ),
        AppSpace.gapXs,
        for (final x in e.value)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: () {
              final fix = institutionHealthFixOf(x, governance: governance);
              return InstitutionHealthRow(
                  key: ValueKey('health.check.${x.key}'), check: x, fix: fix, onFix: onFix == null ? null : () => onFix!(x, fix));
            }(),
          ),
      ],
    ]);
  }
}

/// Pushes an org page from the dashboard (its header and providers) or, from a notification tap where no dashboard
/// is open, as a plain route carrying the organization session.
Future<void> _orgPushAnywhere(BuildContext context, String title, Widget page, {AppWidth? width, String? helpPageId}) {
  try {
    context.read<OrgDashController>();
    return orgPush(context, title, page, width: width, helpPageId: helpPageId);
  } on ProviderNotFoundException {
    final s = context.read<OrgSession>();
    return Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider<OrgSession>.value(
            value: s, child: OrgPushedPage(title: title, width: width, helpPageId: helpPageId, child: page))));
  }
}

class InstitutionHealthPage extends StatefulWidget {
  const InstitutionHealthPage({super.key, required this.orgId, this.initial});
  final int orgId;

  /// The Home's answer (no request on open); asked again after a fix.
  final InstitutionHealth? initial;

  @override
  State<InstitutionHealthPage> createState() => _InstitutionHealthPageState();
}

class _InstitutionHealthPageState extends State<InstitutionHealthPage> {
  InstitutionHealth? _health;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _health = widget.initial;
    if (_health == null) _load();
  }

  Future<void> _load() async {
    final r = await orgCall(() => ApiClient().get('/api/v1/org/orgs/${widget.orgId}/institution/health'), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) _health = InstitutionHealth.fromJson(r.map);
      _failed = !r.ok && _health == null;
    });
  }

  Future<void> _fix(InstitutionHealthCheck check, InstitutionHealthFix fix) async {
    switch (fix.kind) {
      case InstitutionHealthFixKind.wizard:
        await _orgPushAnywhere(context, institutionWizardTitle(), OrgInstitutionWizard(initialStep: fix.step),
            width: AppWidth.content, helpPageId: 'org.settings');
      case InstitutionHealthFixKind.items:
        final s = context.read<OrgSession>();
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider<OrgSession>.value(
                value: s,
                child: GovItemsPage(orgId: widget.orgId, initial: dashboardTileFilter(fix.tile ?? 'all'), title: check.text))));
      case InstitutionHealthFixKind.none:
        return;
    }
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final h = _health;
    return AppRefresh(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xl),
        children: [
          if (h != null)
            InstitutionHealthView(health: h, onFix: _fix, governance: govEnabled())
          else if (_failed)
            AppErrorState(onRetry: _load)
          else
            const AppListSkeleton(items: 4),
        ],
      ),
    );
  }
}

/// Pushes the page (from the Home card: with its answer, no second request).
Future<void> openInstitutionHealth(BuildContext context, int orgId, {InstitutionHealth? initial}) => _orgPushAnywhere(
    context, institutionHealthTitle(), InstitutionHealthPage(orgId: orgId, initial: initial),
    width: AppWidth.reading, helpPageId: 'org.settings');

/// AppNavigator `org_institution_health` {org_id}: the page for a manager, else false (the caller opens the
/// notifications list).
Future<bool> openInstitutionHealthLink(NavigatorState nav, BuildContext ctx, int? orgId) async {
  var manages = false;
  try {
    manages = orgId != null && ctx.read<OrgSession>().items.any((o) => asInt(o['id']) == orgId);
  } catch (_) {}
  if (!institutionHealthLinkAllowed(orgId: orgId, orgsEnabled: AppConfig.orgsEnabled, disabled: AppConfig.disableList, manages: manages)) {
    return false;
  }
  final s = ctx.read<OrgSession>();
  await nav.push(MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider<OrgSession>.value(
          value: s,
          child: OrgPushedPage(
              title: institutionHealthTitle(), width: AppWidth.reading, helpPageId: 'org.settings', child: InstitutionHealthPage(orgId: orgId!)))));
  return true;
}
