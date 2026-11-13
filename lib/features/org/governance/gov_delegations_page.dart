// lib/features/org/governance/gov_delegations_page.dart — delegation of an entity head's decisions (spec §3
// "Delegation"): scoped (item types · categories · forms · council) or global, with dates, revoke and the log.
//
//   GovDelegationsPage(deptId)   active / past lists, "Delegate" (scoped) + the prominent "Global delegation"
//   GovDelegationForm            the presentational form (layout-tested)
//   GovDelegationCard            one delegation with its scope chips, dates and log line
//   GovActingBanner              "You are acting for … (until …)" from GET …/me/delegations — put on item lists
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/context_switcher.dart' show ContextExitButton;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show dirArrow, SheetHeader, asInt, asMapList, t;
import '../../admin/admin_list.dart' show AdminAvatar;
import '../org_page_header.dart' show OrgPushedPage, orgUsesDashboardHeader;
import '../org_providers.dart' show OrgApi, OrgSession, orgBase;
import '../org_v3.dart' show orgCall, orgErrorText;
import 'gov_api.dart';
import 'gov_models.dart';
import 'gov_ui.dart';

/// A form the delegation may be limited to (id · title) — from `GET …/forms?dept_id=`.
typedef GovFormRef = ({int id, String title});

// ═════════════════════════════════════════════════════════════════════════════
//  Presentational
// ═════════════════════════════════════════════════════════════════════════════

class GovDelegationForm extends StatelessWidget {
  const GovDelegationForm({
    super.key,
    required this.mode,
    required this.person,
    required this.types,
    required this.categoryIds,
    required this.formIds,
    required this.council,
    required this.startsAt,
    required this.endsAt,
    required this.note,
    required this.onPickPerson,
    required this.onTypes,
    required this.onCategories,
    required this.onForms,
    required this.onCouncil,
    required this.onStarts,
    required this.onEnds,
    required this.onSubmit,
    this.categories = const [],
    this.forms = const [],
    this.hasCouncil = false,
    this.busy = false,
    this.error,
  });

  final String mode; // global | scoped
  final GovUser? person;
  final List<String> types;
  final List<int> categoryIds, formIds;
  final bool council, hasCouncil, busy;
  final DateTime? startsAt, endsAt;
  final TextEditingController note;
  final List<Category> categories;
  final List<GovFormRef> forms;
  final VoidCallback onPickPerson;
  final ValueChanged<List<String>> onTypes;
  final ValueChanged<List<int>> onCategories, onForms;
  final ValueChanged<bool> onCouncil;
  final ValueChanged<DateTime?> onStarts, onEnds;
  final VoidCallback? onSubmit;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final global = mode == 'global';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppBanner(
        icon: global ? Icons.all_inclusive_rounded : Icons.tune_rounded,
        color: global ? c.warning : c.primary,
        text: global
            ? t('تفويض كامل: يقرر المفوَّض في كل معاملات هذه الجهة كأنه رئيسها، ويدير مجلسها إن وُجد.', 'Global: the delegate decides on every item of this entity as its head would, and manages its council if any.')
            : t('تفويض محدد: يقرر المفوَّض فقط في المعاملات التي تطابق كل محور تحدده (محور فارغ = بلا قيد).', 'Scoped: the delegate decides only on items matching every axis you set (an empty axis = no restriction).'),
      ),
      const SizedBox(height: AppSpace.sm),
      GovPersonField(label: t('المفوَّض إليه', 'Delegate to'), person: person, onPick: onPickPerson),
      if (!global) ...[
        const SizedBox(height: AppSpace.md),
        GovChipSelect(
          label: t('أنواع المعاملات', 'Item types'),
          icon: Icons.category_outlined,
          options: {for (final x in itemTypes) x: itemTypeLabel(x)},
          selected: types,
          onChanged: onTypes,
        ),
        if (categories.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Text(t('التصنيفات', 'Categories'), style: AppType.meta(context).copyWith(color: c.textLight)),
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final cat in categories)
              AppChoiceChip(
                label: cat.name,
                selected: categoryIds.contains(cat.id),
                onTap: () => onCategories(categoryIds.contains(cat.id) ? categoryIds.where((x) => x != cat.id).toList() : [...categoryIds, cat.id]),
              ),
          ]),
        ],
        if (forms.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Text(t('النماذج', 'Forms'), style: AppType.meta(context).copyWith(color: c.textLight)),
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            for (final f in forms)
              AppChoiceChip(
                label: f.title,
                icon: Icons.assignment_rounded,
                selected: formIds.contains(f.id),
                onTap: () => onForms(formIds.contains(f.id) ? formIds.where((x) => x != f.id).toList() : [...formIds, f.id]),
              ),
          ]),
        ],
        if (hasCouncil) ...[
          const SizedBox(height: AppSpace.xs),
          AppSwitchTile(
            icon: Icons.groups_2_rounded,
            title: t('إدارة المجلس', 'Council management'),
            subtitle: t('الجلسات والتصويت وإغلاق النتائج', 'Sessions, voting and closing the results'),
            value: council,
            onChanged: onCouncil,
          ),
        ],
      ],
      const SizedBox(height: AppSpace.sm),
      LayoutBuilder(builder: (context, box) {
        final from = GovDateField(
          label: t('يبدأ (اختياري)', 'Starts (optional)'),
          value: startsAt,
          withTime: true,
          onPick: () async {
            final d = await pickGovDateTime(context, initial: startsAt, first: DateTime.now().subtract(const Duration(days: 1)));
            if (d != null) onStarts(d);
          },
          onClear: () => onStarts(null),
        );
        final to = GovDateField(
          label: t('ينتهي (اختياري)', 'Ends (optional)'),
          value: endsAt,
          withTime: true,
          icon: Icons.event_busy_rounded,
          onPick: () async {
            final d = await pickGovDateTime(context, initial: endsAt ?? startsAt?.add(const Duration(days: 7)));
            if (d != null) onEnds(d);
          },
          onClear: () => onEnds(null),
        );
        if (box.maxWidth < 420) return Column(children: [from, const SizedBox(height: AppSpace.sm), to]);
        return Row(children: [Expanded(child: from), const SizedBox(width: AppSpace.sm), Expanded(child: to)]);
      }),
      const SizedBox(height: AppSpace.sm),
      AppField(controller: note, label: t('ملاحظة (اختياري)', 'Note (optional)'), maxLines: 2),
      if (error != null) ...[const SizedBox(height: AppSpace.sm), AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!)],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(
        label: global ? t('منح التفويض الكامل', 'Grant global delegation') : t('منح التفويض', 'Grant delegation'),
        icon: Icons.swap_horiz_rounded,
        busy: busy,
        onPressed: person == null ? null : onSubmit,
      ),
    ]);
  }
}

class GovDelegationCard extends StatelessWidget {
  const GovDelegationCard({super.key, required this.delegation, this.onRevoke, this.categoryName, this.formTitle, this.showEntity = false});
  final Delegation delegation;
  final VoidCallback? onRevoke;
  final String Function(int)? categoryName, formTitle;
  final bool showEntity;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = delegation;
    final now = DateTime.now();
    final live = d.revokedAt == null && d.activeAt(now);
    final upcoming = d.revokedAt == null && d.startsAt != null && d.startsAt!.isAfter(now);
    final col = d.revokedAt != null ? c.danger : (live ? c.success : c.textLight);
    final state = d.revokedAt != null
        ? t('ملغى', 'Revoked')
        : live
            ? t('ساري', 'Active')
            : upcoming
                ? t('لاحقاً', 'Upcoming')
                : t('منتهٍ', 'Ended');
    return AppCard(
      margin: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.xxs),
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AdminAvatar(name: d.to.name, url: d.to.avatar, size: 40),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.to.name, style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
              if (showEntity && d.dept != null) Text(d.dept!.name, style: AppType.meta(context).copyWith(color: c.textMedium)),
              const SizedBox(height: AppSpace.xxs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                AppBadgePill(state, color: col),
                AppBadgePill(delegationModeLabel(d.mode), color: d.isGlobal ? c.warning : c.primary, icon: d.isGlobal ? Icons.all_inclusive_rounded : Icons.tune_rounded),
                if (!d.isGlobal) ...[
                  for (final x in d.scope.types) AppBadgePill(itemTypeLabel(x), color: c.textMedium, icon: govTypeIcon(x)),
                  for (final id in d.scope.categoryIds) AppBadgePill(categoryName?.call(id) ?? '#$id', color: c.textMedium, icon: Icons.label_outline_rounded),
                  for (final id in d.scope.formIds) AppBadgePill(formTitle?.call(id) ?? '#$id', color: c.textMedium, icon: Icons.assignment_rounded),
                  if (d.scope.council) AppBadgePill(t('المجلس', 'Council'), color: c.purple, icon: Icons.groups_2_rounded),
                  if (d.scope.isEmpty) AppBadgePill(t('كل المعاملات', 'Every item'), color: c.textMedium),
                ],
              ]),
            ]),
          ),
          if (onRevoke != null && d.revokedAt == null)
            IconButton(tooltip: t('إلغاء التفويض', 'Revoke'), onPressed: onRevoke, icon: Icon(Icons.cancel_outlined, color: c.danger)),
        ]),
        const SizedBox(height: AppSpace.xs),
        Text(
          [
            if (d.startsAt != null || d.endsAt != null) '${d.startsAt == null ? '…' : govWhen(d.startsAt)} $dirArrow ${d.endsAt == null ? t('مفتوح', 'open') : govWhen(d.endsAt)}',
            if ((d.note ?? '').isNotEmpty) d.note!,
          ].join(' · '),
          style: AppType.meta(context).copyWith(color: c.textMedium, height: 1.4),
        ),
        Text(
          [
            '${t('أُنشئ', 'Created')} ${govWhen(d.createdAt)}${d.from == null ? '' : ' · ${d.from!.name}'}',
            if (d.revokedAt != null) '${t('أُلغي', 'Revoked')} ${govWhen(d.revokedAt)}',
          ].join(' — '),
          style: AppType.meta(context).copyWith(color: c.textLight),
        ),
      ]),
    );
  }
}

/// The "acting for" banner body with plain values (the state widget below feeds it).
class GovActingBannerBody extends StatelessWidget {
  const GovActingBannerBody({super.key, required this.delegations});
  final List<Delegation> delegations;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    final live = delegations.where((d) => d.activeAt(now)).toList();
    if (live.isEmpty) return const SizedBox.shrink();
    final lines = [
      for (final d in live)
        '${d.from?.name ?? d.dept?.name ?? ''}${d.dept != null && d.from != null ? ' (${d.dept!.name})' : ''}${d.endsAt == null ? '' : ' · ${t('حتى', 'until')} ${govWhen(d.endsAt)}'}${d.isGlobal ? '' : ' · ${delegationModeLabel(d.mode)}'}',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, 0),
      child: AppBanner(
        icon: Icons.swap_horiz_rounded,
        color: c.warning,
        text: '${t('أنت تنوب عن', 'You are acting for')}: ${lines.join(' • ')}',
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Network widgets
// ═════════════════════════════════════════════════════════════════════════════

class GovActingBanner extends StatefulWidget {
  const GovActingBanner({super.key, this.orgId, this.member = false});
  final int? orgId;
  final bool member;
  @override
  State<GovActingBanner> createState() => _GovActingBannerState();
}

class _GovActingBannerState extends State<GovActingBanner> {
  List<Delegation> _rows = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final orgId = widget.orgId ?? (() {
          try {
            return context.read<OrgSession>().currentId;
          } catch (_) {
            return null;
          }
        })();
    final r = await orgCall(() => widget.member || orgId == null ? GovApi.memberDelegations() : GovApi(orgId).myDelegations(), quiet: true);
    if (!mounted || !r.ok) return;
    setState(() => _rows = r.data as List<Delegation>);
  }

  @override
  Widget build(BuildContext context) => GovActingBannerBody(delegations: _rows);
}

/// Opens the delegation sheet for [deptId] in [mode]; true when one was created.
Future<bool> showGovDelegationSheet(
  BuildContext context,
  GovApi api,
  int deptId, {
  required String mode,
  List<Category> categories = const [],
  List<GovFormRef> forms = const [],
  bool hasCouncil = false,
  Set<int> excludeIds = const {},
}) async {
  GovUser? person;
  var types = <String>[];
  var categoryIds = <int>[], formIds = <int>[];
  var council = false, busy = false;
  DateTime? starts, ends;
  String? error;
  final note = TextEditingController();
  final r = await showAppSheet<bool>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SheetHeader(mode == 'global' ? t('تفويض كامل', 'Global delegation') : t('تفويض محدد', 'Scoped delegation')),
            GovDelegationForm(
              mode: mode,
              person: person,
              types: types,
              categoryIds: categoryIds,
              formIds: formIds,
              council: council,
              startsAt: starts,
              endsAt: ends,
              note: note,
              categories: categories,
              forms: forms,
              hasCouncil: hasCouncil,
              busy: busy,
              error: error,
              onPickPerson: () async {
                final p = await pickGovPerson(ctx, api.orgId, title: t('المفوَّض إليه', 'Delegate to'), excludeIds: excludeIds, selectedId: person?.id);
                if (p != null) set(() => person = p);
              },
              onTypes: (v) => set(() => types = v),
              onCategories: (v) => set(() => categoryIds = v),
              onForms: (v) => set(() => formIds = v),
              onCouncil: (v) => set(() => council = v),
              onStarts: (v) => set(() => starts = v),
              onEnds: (v) => set(() => ends = v),
              onSubmit: () async {
                if (starts != null && ends != null && !ends!.isAfter(starts!)) {
                  set(() => error = t('تاريخ الانتهاء قبل البداية', 'The end is before the start'));
                  return;
                }
                set(() {
                  busy = true;
                  error = null;
                });
                final res = await orgCall(
                    () => api.createDelegation(
                        deptId,
                        delegationBody(
                          toUserId: person!.id,
                          mode: mode,
                          scope: DelegationScope(types: types, categoryIds: categoryIds, formIds: formIds, council: council),
                          startsAt: starts,
                          endsAt: ends,
                          note: note.text,
                        )),
                    quiet: true);
                if (!ctx.mounted) return;
                if (!res.ok) {
                  set(() {
                    busy = false;
                    error = govCodeTexts()[res.code] ?? orgErrorText(res.error!);
                  });
                  return;
                }
                appToast(t('مُنح التفويض', 'Delegation granted'));
                Navigator.pop(ctx, true);
              },
            ),
          ]),
        );
      }));
  return r == true;
}

class GovDelegationsPage extends StatefulWidget {
  const GovDelegationsPage(this.deptId, {super.key, this.entity, this.embedded = false, this.orgId});
  final int deptId;
  final Entity? entity;
  final bool embedded;
  final int? orgId;

  @override
  State<GovDelegationsPage> createState() => _GovDelegationsPageState();
}

class _GovDelegationsPageState extends State<GovDelegationsPage> {
  late GovApi _api;
  List<Delegation>? _rows;
  List<Category> _cats = const [];
  List<GovFormRef> _forms = const [];
  bool _failed = false, _missing = false;

  int get _orgId => widget.orgId ?? context.read<OrgSession>().currentId ?? 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _api = GovApi(_orgId);
      _load();
      _loadScope();
    });
  }

  Future<void> _load() async {
    final r = await orgCall(() => _api.delegations(widget.deptId), quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _rows = r.data as List<Delegation>;
        _failed = false;
      } else {
        _failed = _rows == null;
        _missing = r.endpointMissing;
      }
    });
  }

  Future<void> _loadScope() async {
    final cats = await orgCall(() => _api.categories(widget.deptId), quiet: true);
    if (mounted && cats.ok) setState(() => _cats = cats.data as List<Category>);
    final forms = await OrgApi.i.getMap('$orgBase/orgs/$_orgId/forms', {'dept_id': widget.deptId, 'size': 100});
    if (mounted && forms != null) {
      setState(() => _forms = [for (final f in asMapList(forms['items'])) (id: asInt(f['id']), title: '${f['title'] ?? f['name'] ?? '#${f['id']}'}')]);
    }
  }

  Future<void> _delegate(String mode) async {
    final ok = await showGovDelegationSheet(
      context,
      _api,
      widget.deptId,
      mode: mode,
      categories: _cats,
      forms: _forms,
      hasCouncil: widget.entity?.councilId != null || widget.entity?.isCouncil == true,
      excludeIds: {if (widget.entity?.head != null) widget.entity!.head!.id},
    );
    if (ok) _load();
  }

  Future<void> _revoke(Delegation d) async {
    if (!await appConfirm(context, message: t('إلغاء تفويض ${d.to.name}؟', 'Revoke the delegation to ${d.to.name}?'), danger: true)) return;
    final r = await orgCall(() => _api.revokeDelegation(d.id), ok: t('أُلغي التفويض', 'Delegation revoked'));
    if (r.ok) _load();
  }

  String _catName(int id) => _cats.where((c) => c.id == id).map((c) => c.name).firstOrNull ?? '#$id';
  String _formTitle(int id) => _forms.where((f) => f.id == id).map((f) => f.title).firstOrNull ?? '#$id';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.watch<OrgSession>();
    final canManage = widget.entity?.can['manage'] == true || s.isOrgAdmin || s.can('departments', 'update', widget.deptId);
    final now = DateTime.now();
    final rows = _rows ?? const <Delegation>[];
    final active = rows.where((d) => d.revokedAt == null && (d.endsAt == null || d.endsAt!.isAfter(now))).toList();
    final past = rows.where((d) => !active.contains(d)).toList();
    Widget body;
    if (_rows == null && !_failed) {
      body = const AppListSkeleton(items: 4);
    } else if (_missing) {
      body = const GovNeedsServer();
    } else if (_rows == null) {
      body = AppEmpty(icon: Icons.cloud_off_rounded, title: t('تعذّر التحميل', 'Could not load'), actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load);
    } else {
      body = AppRefresh(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.only(top: AppSpace.xs, bottom: AppSpace.xxl), children: [
          if (canManage)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xs),
              child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                AppPill(icon: Icons.tune_rounded, label: t('تفويض محدد', 'Delegate (scoped)'), onTap: () => _delegate('scoped')),
                AppPill(icon: Icons.all_inclusive_rounded, label: t('تفويض كامل', 'Global delegation'), color: c.warning, onTap: () => _delegate('global')),
              ]),
            ),
          if (rows.isEmpty)
            AppEmpty(
              icon: Icons.swap_horiz_rounded,
              title: t('لا تفويضات', 'No delegations'),
              message: t('يفوّض رئيس الجهة شخصاً ليقرر بدلاً عنه في كل المعاملات أو بعضها', 'The entity head lets someone decide in their place, on every item or some of them'),
            ),
          if (active.isNotEmpty) ...[
            AppSectionTitle(t('سارية', 'Active'), subtitle: '${active.length}'),
            for (final d in active) GovDelegationCard(delegation: d, onRevoke: canManage ? () => _revoke(d) : null, categoryName: _catName, formTitle: _formTitle),
          ],
          if (past.isNotEmpty) ...[
            AppSectionTitle(t('السجل', 'Log'), subtitle: '${past.length}'),
            for (final d in past) GovDelegationCard(delegation: d, categoryName: _catName, formTitle: _formTitle),
          ],
        ]),
      );
    }
    if (widget.embedded) return body;
    // staff of this organization (the delegation notification): the dashboard's header, Back first; otherwise the
    // screen's own app bar
    if (orgUsesDashboardHeader(context, _orgId)) {
      final name = widget.entity?.name ?? '';
      return OrgPushedPage(helpPageId: 'org.governance', title: t('التفويض', 'Delegation'), subtitle: name.isEmpty ? null : name, child: body);
    }
    return BasePage(
      useWebCard: true,
      maxWith: 900,
      appBar: ScreenAppBar(title: '${t('التفويض', 'Delegation')} · ${widget.entity?.name ?? ''}', actions: const [ContextExitButton()]),
      child: body,
    );
  }
}
