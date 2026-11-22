// lib/features/org/onboarding/onboarding_page.dart — Admissions & appointments / الالتحاق والتعيين (D-1200).
//
//   OnboardingPage   the People-section page: stage tabs (To review · Needs correction · Conditional · Drafts · Done,
//                    counts from `/summary`), search, a type filter, the case cards and the primary "Add". On a wide
//                    window the picked case opens in a right pane (master-detail); on a phone it is a pushed page.
//   OnbCaseCard      one case (plain values)
//   OnbCaseList      the states + cards + "show more" over plain values (what the layout harness pumps)
//   showOnbAddSheet  "Add": one person (wizard) · from Excel · invite people (the last two arrive in phases B / C)
//
// The list reloads on the `onboarding` live event (EventOrPoll keeps a slow poll as the fallback).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/live/event_wait.dart' show EventOrPoll;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/live_events.dart' show LiveEvents;
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t, asMapList, asInt;
import '../org_page_kit.dart' show OrgMenuItem, OrgPageBody, OrgPrimaryAction, OrgSearchField;
import '../org_providers.dart' show OrgSession;
import '../org_v3.dart' show orgErrorText;
import 'onboarding_api.dart';
import 'onboarding_import.dart';
import 'onboarding_invite.dart';
import 'onboarding_models.dart';
import 'onboarding_report.dart';
import 'onboarding_review.dart';
import 'onboarding_types_page.dart';
import 'onboarding_wizard.dart';

/// Width from which the picked case opens beside the list instead of on top of it.
const _splitFrom = 1000.0;

String onbStageLabel(OnbStage s) => switch (s) {
      OnbStage.review => t('للمراجعة', 'To review'),
      OnbStage.correction => t('يحتاج تعديلاً', 'Needs correction'),
      OnbStage.conditional => t('مشروط', 'Conditional'),
      OnbStage.drafts => t('مسودات', 'Drafts'),
      OnbStage.done => t('منتهية', 'Done'),
    };

int? onbStageCount(OnbSummary? s, OnbStage st) => s == null
    ? null
    : switch (st) {
        OnbStage.review => s.toReview,
        OnbStage.correction => s.needsCorrection,
        OnbStage.conditional => s.conditional,
        OnbStage.drafts => s.drafts,
        OnbStage.done => s.done,
      };

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.orgId, this.api, this.can, this.live = true, this.initialStage = OnbStage.review, this.places});
  final int orgId;
  final OnboardingApi? api;

  /// `(module, action) → allowed`; null reads the [OrgSession] above.
  final bool Function(String module, String action)? can;

  /// Listen to the live event (tests switch it off).
  final bool live;
  final OnbStage initialStage;
  final OnbPlaces? places;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  late final OnboardingApi _api = widget.api ?? OnboardingApi();
  EventOrPoll? _poll;
  late OnbStage _stage = widget.initialStage;
  String _q = '', _type = '';
  final _items = <OnbCase>[];
  List<OnbType> _types = const [];
  OnbSummary? _summary;
  int _page = 0, _total = 0, _seq = 0;
  bool _loading = true, _more = false;
  ApiException? _error;
  int? _open;

  @override
  void initState() {
    super.initState();
    _loadTypes();
    _load(reset: true);
    if (widget.live) {
      _poll = EventOrPoll(poll: () => _load(reset: true, quiet: true), every: const Duration(seconds: 45), names: {LiveEvents.onboarding})..start();
    }
  }

  @override
  void dispose() {
    _poll?.dispose();
    super.dispose();
  }

  bool _can(String module, String action) {
    final f = widget.can;
    if (f != null) return f(module, action);
    try {
      return context.read<OrgSession>().can(module, action);
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadTypes() async {
    final r = await _api.types(widget.orgId);
    if (!mounted || !r.ok) return;
    final raw = r.data is List ? r.data as List : r.map['items'];
    setState(() => _types = asMapList(raw).map(OnbType.fromJson).toList());
  }

  Future<void> _load({bool reset = false, bool quiet = false}) async {
    final seq = ++_seq;
    if (reset) {
      if (!quiet) {
        setState(() {
          _loading = true;
          _error = null;
        });
      }
    } else {
      setState(() => _more = true);
    }
    final next = reset ? 1 : _page + 1;
    final rs = await Future.wait([
      _api.cases(widget.orgId, stage: _stage, type: _type, q: _q, page: next),
      if (reset) _api.summary(widget.orgId),
    ]);
    if (!mounted || seq != _seq) return;
    final r = rs.first;
    setState(() {
      _loading = false;
      _more = false;
      if (!r.ok) {
        if (!quiet) _error = r.error;
        return;
      }
      if (reset) _items.clear();
      _items.addAll(asMapList(r.map['items']).map(OnbCase.fromJson));
      _total = asInt(r.map['total'], _items.length);
      _page = next;
      _error = null;
      if (rs.length > 1 && rs[1].ok) _summary = OnbSummary.fromJson(rs[1].map);
    });
  }

  void _changed(OnbCase c) {
    final k = _items.indexWhere((x) => x.id == c.id);
    if (k >= 0 && mounted) setState(() => _items[k] = c);
    _load(reset: true, quiet: true);
  }

  // ── actions ────────────────────────────────────────────────────────────────

  Widget _scope(Widget child) {
    try {
      final s = context.read<OrgSession>();
      return ChangeNotifierProvider<OrgSession>.value(value: s, child: child);
    } catch (_) {
      return child;
    }
  }

  Future<void> _add() async {
    final insertable = [for (final ty in _types) if (ty.active && _can(ty.module, 'insert')) ty];
    final pick = await showOnbAddSheet(context, types: insertable, canImport: _importable(insertable).isNotEmpty, canInvite: _invitable(insertable).isNotEmpty);
    if (pick == null || !mounted) return;
    switch (pick.kind) {
      case OnbAddKind.one:
        await _openWizard(pick.type!);
      case OnbAddKind.excel:
        await _openImport(_importable(insertable), initial: pick.type);
      case OnbAddKind.invite:
        await _inviteGuided(_invitable(insertable), pick.type!);
    }
  }

  /// Types the person may import into: the kill switch and the module's import right.
  List<OnbType> _importable(List<OnbType> l) =>
      AppConfig.disableList.contains(onboardingImportKey) ? const [] : [for (final ty in l) if (_can(ty.module, 'import') || _can(ty.module, 'insert')) ty];

  /// Types the person may invite for: the kill switch and the module's update right.
  List<OnbType> _invitable(List<OnbType> l) =>
      AppConfig.disableList.contains(onboardingInviteKey) ? const [] : [for (final ty in l) if (_can(ty.module, 'update')) ty];

  Future<void> _openImport(List<OnbType> types, {OnbType? initial, String mode = 'draft'}) async {
    if (types.isEmpty) return;
    await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _scope(OnbImportPage(orgId: widget.orgId, types: types, initialType: initial, initialMode: mode, canInvite: _invitable(types).isNotEmpty, api: _api)),
    ));
    if (mounted) _load(reset: true);
  }

  /// "Invite people": [type] is chosen; pick existing drafts or import a list with the `invite` mode.
  Future<void> _inviteGuided(List<OnbType> types, OnbType type) async {
    final how = await showAppSheet<String>(
      context,
      (ctx) => AppSheetContent(title: t('دعوة أشخاص', 'Invite people'), subtitle: type.label, children: [
        _Choice(
            key: const ValueKey('onb.invite.drafts'),
            icon: Icons.drafts_outlined,
            title: t('من المسودات', 'From the drafts'),
            text: t('اختر مسودات موجودة لدعوة أصحابها.', 'Pick existing drafts and invite their owners.'),
            onTap: () => Navigator.of(ctx).pop('drafts')),
        AppSpace.gapXs,
        if (!AppConfig.disableList.contains(onboardingImportKey))
          _Choice(
              key: const ValueKey('onb.invite.import'),
              icon: Icons.upload_file_rounded,
              title: t('استيراد قائمة', 'Import a list'),
              text: t('ارفع ملف Excel وادعُ أصحابه مباشرة.', 'Upload an Excel file and invite everyone in it.'),
              onTap: () => Navigator.of(ctx).pop('import')),
      ]),
    );
    if (how == null || !mounted) return;
    if (how == 'import') {
      await _openImport(types, initial: type, mode: 'invite');
    } else {
      await _pickDrafts(type);
    }
  }

  Future<void> _pickDrafts(OnbType? type) async {
    await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _scope(OnbDraftPickerPage(orgId: widget.orgId, type: type, api: _api))));
    if (mounted) _load(reset: true);
  }

  Future<void> _openWizard(OnbType type, {OnbCase? initial}) async {
    final saved = await Navigator.of(context).push<OnbCase?>(MaterialPageRoute(
      builder: (_) => _scope(OnbWizardPage(orgId: widget.orgId, type: type, initial: initial, api: _api, places: widget.places, canApproveNow: _can(type.module, 'approve'))),
    ));
    if (!mounted) return;
    _load(reset: true);
    if (saved != null) _show(saved);
  }

  Future<void> _edit(OnbCase c) async {
    final type = c.type ?? _types.where((x) => x.key == c.typeKey).firstOrNull;
    if (type == null) return;
    await _openWizard(type, initial: c);
  }

  void _openCaseById(int id) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _scope(OnbReviewPage(orgId: widget.orgId, caseId: id, api: _api, onChanged: _changed, onEdit: _edit)),
      ));

  void _show(OnbCase c) {
    if (MediaQuery.sizeOf(context).width >= _splitFrom) {
      setState(() => _open = c.id);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _scope(OnbReviewPage(orgId: widget.orgId, caseId: c.id, api: _api, title: c.fullName, onChanged: _changed, onEdit: _edit)),
    ));
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final canAdd = [for (final ty in _types) if (ty.active && _can(ty.module, 'insert')) ty].isNotEmpty;
    final canConfigure = _can('onboarding', 'update');
    final canReport = _can('students', 'view') || _can('teachers', 'view') || _can('staff', 'view');
    final stages = OnbStage.values;
    final list = ParentComponent(
      featureKey: onboardingFeatureKey,
      child: OrgPageBody(
        primary: canAdd ? OrgPrimaryAction(id: 'onb_add', icon: Icons.person_add_alt_1_rounded, label: t('إضافة', 'Add'), onTap: _add) : null,
        search: OrgSearchField(
            hint: t('بحث بالاسم أو الهاتف أو البريد أو الرقم القومي', 'Name, phone, e-mail or national ID'),
            onChanged: (v) {
              _q = v;
              _load(reset: true);
            }),
        more: [
          if (_stage == OnbStage.drafts && _invitable([for (final ty in _types) if (ty.active) ty]).isNotEmpty)
            OrgMenuItem(icon: Icons.mail_outline_rounded, label: t('دعوة لاستكمال البيانات', 'Invite to complete'), onTap: () => _pickDrafts(_types.where((x) => x.key == _type).firstOrNull)),
          if (canReport)
            OrgMenuItem(
              icon: Icons.insights_rounded,
              label: t('التقرير', 'Report'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => _scope(OnbReportPage(orgId: widget.orgId, api: _api, types: _types, onOpenCase: (id) => _openCaseById(id))))),
            ),
          if (canConfigure)
            OrgMenuItem(
              icon: Icons.tune_rounded,
              label: t('الأنواع والمتطلبات', 'Types & requirements'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _scope(OnbTypesPage(orgId: widget.orgId, api: _api)))).then((_) {
                if (mounted) _loadTypes();
              }),
            ),
        ],
        top: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppTabs(
            key: const ValueKey('onb.stages'),
            index: stages.indexOf(_stage),
            items: [for (final s in stages) AppTabItem(onbStageLabel(s), count: onbStageCount(_summary, s))],
            onChanged: (i) {
              _stage = stages[i];
              _open = null;
              _load(reset: true);
            },
          ),
          if (_types.length > 1) ...[
            AppSpace.gapXs,
            AppDropdown<String>(
              key: const ValueKey('onb.typefilter'),
              value: _type,
              items: [
                DropdownMenuItem(value: '', child: Text(t('كل الأنواع', 'All types'))),
                for (final ty in _types) DropdownMenuItem(value: ty.key, child: Text(ty.label, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                _type = v ?? '';
                _load(reset: true);
              },
            ),
          ],
        ]),
        child: OnbCaseList(
          items: _items,
          loading: _loading,
          error: _error,
          total: _total,
          loadingMore: _more,
          selectedId: _open,
          filtered: _q.isNotEmpty || _type.isNotEmpty,
          stage: _stage,
          onRetry: () => _load(reset: true),
          onMore: () => _load(),
          onOpen: _show,
          onAdd: canAdd ? _add : null,
        ),
      ),
    );
    return LayoutBuilder(builder: (context, box) {
      final open = _open;
      if (box.maxWidth < _splitFrom || open == null) return list;
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(flex: 5, child: list),
        VerticalDivider(width: AppBorder.hairline, color: context.colors.divider),
        Expanded(
          flex: 6,
          child: OnbReviewPane(key: ValueKey('onb.pane.$open'), orgId: widget.orgId, caseId: open, api: _api, onChanged: _changed, onEdit: _edit),
        ),
      ]);
    });
  }
}

/// The states and the cards, over plain values.
class OnbCaseList extends StatelessWidget {
  const OnbCaseList({
    super.key,
    required this.items,
    required this.loading,
    this.error,
    this.total = 0,
    this.loadingMore = false,
    this.selectedId,
    this.filtered = false,
    this.stage = OnbStage.review,
    this.onRetry,
    this.onMore,
    this.onOpen,
    this.onAdd,
  });

  final List<OnbCase> items;
  final bool loading, loadingMore, filtered;
  final Object? error;
  final int total;
  final int? selectedId;
  final OnbStage stage;
  final VoidCallback? onRetry, onMore, onAdd;
  final void Function(OnbCase)? onOpen;

  @override
  Widget build(BuildContext context) {
    return AppStateView<List<OnbCase>>(
      loading: loading,
      error: error,
      data: loading || error != null ? null : items,
      onRetry: onRetry,
      isEmpty: (l) => l.isEmpty,
      empty: AppEmpty(
        icon: Icons.how_to_reg_outlined,
        title: filtered ? t('لا نتائج مطابقة', 'No matching cases') : _emptyTitle(stage),
        message: filtered || stage != OnbStage.review ? null : t('أضف أول شخص أو انتظر وصول الطلبات.', 'Add the first person or wait for applications to arrive.'),
        actionLabel: !filtered && onAdd != null && stage == OnbStage.review ? t('إضافة', 'Add') : null,
        onAction: onAdd,
      ),
      builder: (context, list) => ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xxxl + AppSpace.xl),
        children: [
          for (final c in list)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: OnbCaseCard(item: c, selected: c.id == selectedId, onTap: onOpen == null ? null : () => onOpen!(c)),
            ),
          if (list.length < total) Align(child: AppButton.secondary(label: t('عرض المزيد', 'Show more'), busy: loadingMore, onPressed: loadingMore ? null : onMore)),
        ],
      ),
    );
  }

  String _emptyTitle(OnbStage s) => switch (s) {
        OnbStage.review => t('لا طلبات للمراجعة', 'Nothing to review'),
        OnbStage.correction => t('لا طلبات تنتظر تعديلاً', 'Nothing waits for a correction'),
        OnbStage.conditional => t('لا حالات قبول مشروط', 'No conditional admissions'),
        OnbStage.drafts => t('لا مسودات', 'No drafts'),
        OnbStage.done => t('لا طلبات منتهية', 'No finished cases'),
      };
}

class OnbCaseCard extends StatelessWidget {
  const OnbCaseCard({super.key, required this.item, this.onTap, this.selected = false});
  final OnbCase item;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = item;
    final colors = context.colors;
    final contact = [c.phone, c.email].where((e) => e.isNotEmpty).join(' · ');
    return AppCard(
      key: ValueKey('onb.case.${c.id}'),
      highlight: selected,
      padding: const EdgeInsets.all(AppSpace.sm),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.fullName.isEmpty ? t('بدون اسم', 'No name yet') : c.fullName, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
        AppSpace.gapXs,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AppStatusBadge(label: onbStatusLabel(c.status), tone: onbStatusTone(c.status), dense: true),
          AppStatusBadge(label: c.typeLabel.isEmpty ? c.typeKey : c.typeLabel, tone: AppTone.brand, dense: true),
          if (c.stepLabel.isNotEmpty && (c.status == 'submitted' || c.status == 'under_review')) AppStatusBadge(label: c.stepLabel, tone: AppTone.info, dense: true),
          if (c.missingCount > 0) AppStatusBadge(label: t('ناقص ${c.missingCount}', '${c.missingCount} missing'), tone: AppTone.warning, dense: true),
          if (c.conditional) AppStatusBadge(label: t('مشروط', 'Conditional'), tone: AppTone.warning, dense: true),
          if (c.overdue) AppStatusBadge(label: t('متأخر', 'Overdue'), tone: AppTone.danger, dense: true),
        ]),
        if (c.nidMasked.isNotEmpty || contact.isNotEmpty) ...[
          AppSpace.gapXs,
          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, children: [
            if (c.nidMasked.isNotEmpty) Text(c.nidMasked, textDirection: TextDirection.ltr, style: AppType.meta(context).copyWith(color: colors.textMedium)),
            if (contact.isNotEmpty) Text(contact, textDirection: TextDirection.ltr, style: AppType.meta(context)),
          ]),
        ],
      ]),
    );
  }
}

enum OnbAddKind { one, excel, invite }

/// What the Add dialog resolved to: the way and the chosen type (null for "Excel" until the import page asks).
class OnbAddChoice {
  const OnbAddChoice(this.kind, this.type);
  final OnbAddKind kind;
  final OnbType? type;
}

/// "Add": the three entry methods (one person, from Excel, invite people). Excel and invite are offered only when
/// [canImport] / [canInvite] (kill switch + right) allow; the type is asked first when there are several.
Future<OnbAddChoice?> showOnbAddSheet(BuildContext context, {required List<OnbType> types, bool canImport = true, bool canInvite = true}) async {
  final way = await showAppSheet<OnbAddKind>(
    context,
    (ctx) => AppSheetContent(title: t('إضافة', 'Add'), children: [
      _Choice(
        key: const ValueKey('onb.add.one'),
        icon: Icons.person_add_alt_1_rounded,
        title: t('شخص واحد', 'One person'),
        text: t('أدخل بياناته خطوة بخطوة، بدءاً بالرقم القومي.', 'Enter the details step by step, starting with the national ID.'),
        onTap: types.isEmpty ? null : () => Navigator.of(ctx).pop(OnbAddKind.one),
      ),
      AppSpace.gapXs,
      _Choice(
        key: const ValueKey('onb.add.excel'),
        icon: Icons.upload_file_rounded,
        title: t('من ملف Excel', 'From Excel'),
        text: t('استيراد قائمة كاملة مع مراجعة الأخطاء قبل الحفظ.', 'Import a whole list, with the errors reviewed before saving.'),
        onTap: types.isEmpty || !canImport ? null : () => Navigator.of(ctx).pop(OnbAddKind.excel),
      ),
      AppSpace.gapXs,
      _Choice(
        key: const ValueKey('onb.add.invite'),
        icon: Icons.mail_outline_rounded,
        title: t('دعوة أشخاص', 'Invite people'),
        text: t('أرسل رابطاً ليُكمل كل شخص بياناته بنفسه.', 'Send a link so each person completes their own details.'),
        onTap: types.isEmpty || !canInvite ? null : () => Navigator.of(ctx).pop(OnbAddKind.invite),
      ),
    ]),
  );
  if (way == null || !context.mounted) return null;
  if (way == OnbAddKind.excel) return OnbAddChoice(way, types.length == 1 ? types.first : null);
  if (types.length == 1) return OnbAddChoice(way, types.first);
  final ty = await showAppSheet<OnbType>(
    context,
    (ctx) => AppSheetContent(title: t('اختر النوع', 'Choose the type'), children: [
      for (final ty in types)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: _Choice(key: ValueKey('onb.add.type.${ty.key}'), icon: Icons.badge_outlined, title: ty.label, text: onbModuleLabel(ty.module), onTap: () => Navigator.of(ctx).pop(ty)),
        ),
    ]),
  );
  return ty == null ? null : OnbAddChoice(way, ty);
}

class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.icon, required this.title, required this.text, this.onTap});
  final IconData icon;
  final String title, text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final off = onTap == null;
    return Opacity(
      opacity: off ? 0.6 : 1,
      child: AppCard(
        onTap: off ? null : onTap,
        child: Row(children: [
          Icon(icon, color: off ? c.textMedium : c.primary),
          AppSpace.gapSm,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppType.bodyStrong(context)),
              Text(text, style: AppType.meta(context)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Used by tests and the deep link: the error text of a failed load.
String onbLoadError(ApiException e) => orgErrorText(e);
