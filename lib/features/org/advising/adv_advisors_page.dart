// lib/features/org/advising/adv_advisors_page.dart — the advisors of an organization (Phase 3, docs/advising/PHASE3.md
// "Advisors and their profiles"): every advisor's load against their maximum (warning / over colours), status, search
// and one status filter; tap → the profile sheet (status with dates, own maximum, office, contact note, bio, the
// conflicts of interest) with "Reassign their students" → the distribution preview in reassign mode. An advisor who
// opens the page sees only their own card and edits their contact details.
//
//   AdvAdvisorsView    the list (plain values)       AdvAdvisorCard    one advisor
//   AdvProfileForm     the profile sheet's content    AdvMyProfileView  an advisor's own card
//   AdvAdvisorsPage    loads `GET …/advisors` (manage) or `GET …/advisors/me`, saves with `PUT …/advisors/{id}`
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
import 'adv_comm_entries.dart' show advAdvisorCommLinks;
import 'adv_distribute_page.dart';
import 'adv_models.dart';
import 'adv_parts.dart';

/// The status filter's choices with their counts.
Map<String, String> advAdvisorFilters(Map<String, int> facets) {
  String n(String label, String key) => facets.containsKey(key) ? '$label · ${facets[key]}' : label;
  return {
    'all': t('الكل', 'All'),
    'available': n(t('متاحون', 'Available'), 'available'),
    'away': n(t('غائبون', 'Away'), 'away'),
    'warn': n(t('قريبون من الحد', 'Near the maximum'), 'warn'),
    'over': n(t('فوق الحد', 'Over the maximum'), 'over'),
  };
}

class AdvAdvisorCard extends StatelessWidget {
  const AdvAdvisorCard({super.key, required this.advisor, this.onTap});
  final AdvAdvisor advisor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = advisor;
    final co = a.coLoad > 0 ? t('+ ${a.coLoad} مشارك', '+ ${a.coLoad} co') : null;
    final Widget? pill = a.over
        ? AppBadgePill(t('فوق الحد', 'Over max'), color: c.danger, icon: Icons.error_outline_rounded)
        : (a.away || a.status != 'available')
            ? AdvStatusPill(status: a.status, away: a.away)
            : (a.warn ? AppBadgePill(t('قريب من الحد', 'Near max'), color: c.warning, icon: Icons.trending_up_rounded) : null);
    return AdvRowCard(
      title: a.shown,
      subtitle: a.subtitle.isEmpty ? null : a.subtitle,
      avatarName: a.shown,
      trailing: pill,
      onTap: onTap,
      semanticLabel: '${a.shown}, ${t('الحمل ${a.load} من ${a.maxLoad}', 'load ${a.load} of ${a.maxLoad}')}${a.away ? ', ${a.statusText}' : ''}',
      below: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AdvLoadBar(load: a.load, max: a.maxLoad, warn: a.warn, over: a.over, trailing: co),
        if (a.status != 'available' && a.statusUntil != null) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(t('حتى ${advDate(a.statusUntil, dateOnly: true)}', 'Until ${advDate(a.statusUntil, dateOnly: true)}'), style: AppType.meta(context)),
        ],
        if (!a.eligible) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(t('خارج شروط الإعدادات — يبقى مع طلابه الحاليين ولا يأخذ جدداً', 'Outside the settings — keeps their students, gets no new ones'),
              style: AppType.meta(context)),
        ],
      ]),
    );
  }
}

class AdvAdvisorsView extends StatelessWidget {
  const AdvAdvisorsView({
    super.key,
    required this.load,
    this.page,
    this.status = 'all',
    this.sort = 'load',
    this.errorText,
    this.onRetry,
    this.onSearch,
    this.onStatus,
    this.onSort,
    this.onPage,
    this.onOpen,
    this.onDistribute,
  });

  final AdvLoad load;
  final AdvPage<AdvAdvisor>? page;
  final String status, sort;
  final String? errorText;
  final VoidCallback? onRetry, onDistribute;
  final ValueChanged<String>? onSearch, onStatus, onSort;
  final ValueChanged<int>? onPage;
  final ValueChanged<AdvAdvisor>? onOpen;

  @override
  Widget build(BuildContext context) {
    final p = page;
    final c = context.colors;
    Widget body;
    if (load != AdvLoad.ready || p == null) {
      body = AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry);
    } else if (p.items.isEmpty) {
      body = AppEmpty(
        icon: Icons.supervisor_account_rounded,
        title: status == 'all' ? t('لا يوجد مرشدون بعد', 'No advisors yet') : t('لا أحد هنا', 'Nobody here'),
        message: status == 'all'
            ? t('المرشدون هم أعضاء هيئة التدريس الذين تسمح بهم الإعدادات.', 'Advisors are the staff the settings allow.')
            : t('جرّب تصفية أخرى.', 'Try another filter.'),
      );
    } else {
      final warn = p.facet('warn'), over = p.facet('over');
      body = AdvPageFrame(children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Text(
            [
              countText(p.total, ar1: 'مرشد واحد', ar2: 'مرشدان', arFew: '${p.total} مرشدين', arMany: '${p.total} مرشداً', en1: '1 advisor', en: '${p.total} advisors'),
              if (warn > 0) t('$warn قريب من الحد', '$warn near the maximum'),
              if (over > 0) t('$over فوق الحد', '$over over the maximum'),
            ].join(' · '),
            style: AppType.meta(context),
          ),
        ),
        if (over > 0 && onDistribute != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AppBanner(
              icon: Icons.balance_rounded,
              color: c.danger,
              text: t('بعض المرشدين فوق الحد الأقصى — وازن الأحمال.', 'Some advisors are over their maximum — rebalance the loads.'),
              action: TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
                onPressed: onDistribute,
                child: Text(t('موازنة', 'Rebalance')),
              ),
            ),
          ),
        for (final a in p.items) AdvAdvisorCard(advisor: a, onTap: onOpen == null ? null : () => onOpen!(a)),
        if (p.pages > 1 && onPage != null) ...[
          const SizedBox(height: AppSpace.sm),
          AppPagination(page: p.page, pageCount: p.pages, total: p.total, pageSize: p.size, onPage: onPage!),
        ],
      ]);
    }
    return OrgPageBody(
      search: onSearch == null ? null : OrgSearchField(hint: t('ابحث عن مرشد', 'Search advisors'), onChanged: onSearch!),
      filter: onStatus == null
          ? null
          : OrgFilterButton<String>(
              value: status,
              defaultValue: 'all',
              label: t('الحالة', 'Status'),
              options: advAdvisorFilters(p?.facets ?? const {}),
              onChanged: onStatus!,
            ),
      more: [
        if (onSort != null)
          sort == 'load'
              ? OrgMenuItem(icon: Icons.sort_by_alpha_rounded, label: t('ترتيب بالاسم', 'Sort by name'), onTap: () => onSort!('name'))
              : OrgMenuItem(icon: Icons.stacked_bar_chart_rounded, label: t('ترتيب بالحمل', 'Sort by load'), onTap: () => onSort!('load')),
      ],
      child: body,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Profile sheet
// ═════════════════════════════════════════════════════════════════════════════

class AdvProfileForm extends StatelessWidget {
  const AdvProfileForm({
    super.key,
    required this.advisor,
    required this.draft,
    required this.manage,
    required this.office,
    required this.contact,
    required this.bio,
    required this.onDraft,
    required this.onSubmit,
    this.onPickFrom,
    this.onPickUntil,
    this.onReassign,
    this.conflicts,
    this.onAddConflict,
    this.onRemoveConflict,
    this.busy = false,
    this.error,
  });

  final AdvAdvisor advisor;
  final AdvProfileDraft draft;

  /// An org admin / the advising director: every field. Else (the advisor themself) office, contact note and bio.
  final bool manage;
  final TextEditingController office, contact, bio;
  final ValueChanged<AdvProfileDraft> onDraft;
  final VoidCallback onSubmit;
  final VoidCallback? onPickFrom, onPickUntil, onReassign;

  /// Manage only (null = loading; hidden without [onAddConflict]).
  final List<AdvConflict>? conflicts;
  final VoidCallback? onAddConflict;
  final ValueChanged<AdvConflict>? onRemoveConflict;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = advisor, d = draft;
    final policyMax = a.maxLoadOverride == null ? a.maxLoad : null;
    final err = error ?? d.error;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        AppAvatar(name: a.shown, size: 48),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.shown, style: AppType.section(context), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (a.subtitle.isNotEmpty) Text(a.subtitle, style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
      const SizedBox(height: AppSpace.sm),
      AdvLoadBar(load: a.load, max: a.maxLoad, warn: a.warn, over: a.over, trailing: a.coLoad > 0 ? t('+ ${a.coLoad} مشارك', '+ ${a.coLoad} co') : null),
      if (manage) ...[
        AdvSectionTitle(t('الحالة', 'Status'), subtitle: t('من في إجازة أو غادر لا يأخذ طلاباً جدداً', 'Nobody on leave or gone gets new students')),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final s in advStatuses)
            AppChoiceChip(label: advStatusLabel(s), selected: d.status == s, onTap: () => onDraft(d.copyWith(status: s))),
        ]),
        if (d.dated) ...[
          const SizedBox(height: AppSpace.sm),
          LayoutBuilder(builder: (context, box) {
            final from = AdvPersonField(
              label: t('من', 'From'),
              name: d.statusFrom == null ? null : advDate(d.statusFrom, dateOnly: true),
              placeholder: t('الآن', 'Now'),
              icon: Icons.event_rounded,
              avatar: false,
              onPick: busy ? null : onPickFrom,
              onClear: () => onDraft(d.copyWith(statusFrom: () => null)),
            );
            final until = AdvPersonField(
              label: t('حتى', 'Until'),
              name: d.statusUntil == null ? null : advDate(d.statusUntil, dateOnly: true),
              placeholder: d.status == 'left' ? t('دائم', 'For good') : t('غير محدد', 'Open-ended'),
              icon: Icons.event_busy_rounded,
              avatar: false,
              onPick: busy ? null : onPickUntil,
              onClear: () => onDraft(d.copyWith(statusUntil: () => null)),
            );
            if (box.maxWidth < 420) return Column(children: [from, const SizedBox(height: AppSpace.xs), until]);
            return Row(children: [Expanded(child: from), const SizedBox(width: AppSpace.xs), Expanded(child: until)]);
          }),
        ],
        if (d.dated && a.load > 0) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(
            icon: Icons.swap_horiz_rounded,
            color: c.warning,
            text: countText(a.load,
                ar1: 'طالبه الوحيد يبقى معه حتى تنقله.', ar2: 'طالباه يبقيان معه حتى تنقلهما.', arFew: 'طلابه الـ${a.load} يبقون معه حتى تنقلهم.',
                arMany: 'طلابه الـ${a.load} يبقون معه حتى تنقلهم.', en1: 'Their student stays with them until you move them.',
                en: 'Their ${a.load} students stay with them until you move them.'),
            action: onReassign == null
                ? null
                : TextButton(style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)), onPressed: busy ? null : onReassign, child: Text(t('نقل', 'Move'))),
          ),
        ],
        AdvSectionTitle(t('الحد الأقصى', 'Maximum'), subtitle: t('عدد الطلاب الذي لا يتجاوزه هذا المرشد', 'How many students this advisor takes at most')),
        AppSwitchTile(
          title: t('حد خاص بهذا المرشد', 'Own maximum'),
          subtitle: d.maxLoadOverride == null
              ? t('يتبع الإعدادات: ${policyMax ?? a.maxLoad} طالباً', 'Follows the settings: ${policyMax ?? a.maxLoad} students')
              : null,
          value: d.maxLoadOverride != null,
          onChanged: busy ? null : (v) => onDraft(d.copyWith(maxLoadOverride: () => v ? (a.maxLoadOverride ?? a.maxLoad) : null)),
        ),
        if (d.maxLoadOverride != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AdvStepper(
              label: t('الحد الأقصى لهذا المرشد', 'This advisor\'s maximum'),
              value: d.maxLoadOverride!,
              step: d.maxLoadOverride! >= 20 ? 5 : 1,
              onChanged: busy ? null : (v) => onDraft(d.copyWith(maxLoadOverride: () => v)),
            ),
          ),
      ],
      AdvSectionTitle(t('للطلاب', 'For students'), subtitle: t('يظهر لطلابه مع اسمه', 'Shown to their students with their name')),
      AppField(controller: office, label: t('المكتب', 'Office'), hint: t('مثال: مبنى ب، غرفة 214', 'e.g. Building B, room 214')),
      const SizedBox(height: AppSpace.sm),
      AppField(controller: contact, label: t('طريقة التواصل', 'How to reach me'), hint: t('مثال: الساعات المكتبية الأحد ١٠–١٢', 'e.g. Office hours Sunday 10–12'), maxLines: 2),
      const SizedBox(height: AppSpace.sm),
      AppField(controller: bio, label: t('نبذة (اختياري)', 'About (optional)'), maxLines: 3),
      if (manage && onAddConflict != null) AdvConflictList(conflicts: conflicts, ofAdvisor: true, onAdd: busy ? null : onAddConflict, onRemove: busy ? null : onRemoveConflict),
      if (err != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: err),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(icon: Icons.check_rounded, label: t('حفظ', 'Save'), busy: busy, onPressed: d.error == null ? onSubmit : null),
    ]);
  }
}

/// An advisor's own page: their load, status and what their students see; Edit opens the contact details.
class AdvMyProfileView extends StatelessWidget {
  const AdvMyProfileView({super.key, required this.load, this.me, this.errorText, this.onRetry, this.onEdit});
  final AdvLoad load;
  final AdvAdvisor? me;
  final String? errorText;
  final VoidCallback? onRetry, onEdit;

  @override
  Widget build(BuildContext context) {
    final a = me;
    if (load != AdvLoad.ready || a == null) {
      return AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry, items: 3);
    }
    final c = context.colors;
    Widget info(IconData icon, String label, String? value) => Padding(
          padding: const EdgeInsets.only(top: AppSpace.sm),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ExcludeSemantics(child: Icon(icon, size: AppIconSize.md, color: c.primary)),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: AppType.meta(context)),
                Text(value ?? t('لم تُكتب بعد', 'Not written yet'),
                    textDirection: value == null ? null : advTextDirection(value),
                    style: value == null ? AppType.body(context) : AppType.row(context)),
              ]),
            ),
          ]),
        );
    return OrgPageBody(
      primary: onEdit == null ? null : OrgPrimaryAction(id: 'edit', icon: Icons.edit_rounded, label: t('تعديل بيانات التواصل', 'Edit contact details'), onTap: onEdit!),
      child: AdvPageFrame(fab: onEdit != null, children: [
        AppCard(
          padding: AppSpace.card,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              AppAvatar(name: a.shown, size: 48),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Semantics(header: true, child: Text(a.shown, style: AppType.section(context), maxLines: 2, overflow: TextOverflow.ellipsis)),
                  if (a.subtitle.isNotEmpty) Text(a.subtitle, style: AppType.meta(context)),
                ]),
              ),
              const SizedBox(width: AppSpace.xs),
              AdvStatusPill(status: a.status, away: a.away),
            ]),
            const SizedBox(height: AppSpace.md),
            Text(
              a.load == 0
                  ? t('لم يُسند إليك طلاب بعد.', 'No students are assigned to you yet.')
                  : countText(a.load,
                      ar1: 'ترشد طالباً واحداً', ar2: 'ترشد طالبين', arFew: 'ترشد ${a.load} طلاب', arMany: 'ترشد ${a.load} طالباً',
                      en1: 'You advise 1 student', en: 'You advise ${a.load} students'),
              style: AppType.row(context),
            ),
            const SizedBox(height: AppSpace.xs),
            AdvLoadBar(load: a.load, max: a.maxLoad, warn: a.warn, over: a.over, trailing: a.coLoad > 0 ? t('+ ${a.coLoad} مشارك', '+ ${a.coLoad} co') : null),
          ]),
        ),
        AdvSectionTitle(t('ما يراه طلابك', 'What your students see'), subtitle: t('مع اسمك في صفحة الإرشاد ورسالة الترحيب', 'With your name on their advising page and in the welcome')),
        AppCard(
          padding: AppSpace.card,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            info(Icons.meeting_room_outlined, t('المكتب', 'Office'), a.officeLocation),
            info(Icons.forum_outlined, t('طريقة التواصل', 'How to reach me'), a.contactNote),
            if (a.bio != null) info(Icons.person_outline_rounded, t('نبذة', 'About'), a.bio),
          ]),
        ),
        if (a.status != 'available') ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(icon: Icons.event_busy_rounded, color: c.warning, text: t('حالتك: ${a.statusText}. يغيّرها مدير الإرشاد.', 'Your status: ${a.statusText}. The advising director changes it.')),
        ],
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page
// ═════════════════════════════════════════════════════════════════════════════

class AdvAdvisorsPage extends StatelessWidget {
  const AdvAdvisorsPage({super.key, required this.orgId, required this.manage});
  final int orgId;

  /// Org admin / advising director: every advisor. Else my own profile only.
  final bool manage;

  @override
  Widget build(BuildContext context) => OrgPushedPage(
        title: manage ? t('المرشدون', 'Advisors') : t('ملفي كمرشد', 'My advisor profile'),
        helpPageId: 'org.advising',
        maxWidth: 1440,
        child: _AdvAdvisorsBody(orgId: orgId, manage: manage),
      );
}

class _AdvAdvisorsBody extends StatefulWidget {
  const _AdvAdvisorsBody({required this.orgId, required this.manage});
  final int orgId;
  final bool manage;

  @override
  State<_AdvAdvisorsBody> createState() => _AdvAdvisorsBodyState();
}

class _AdvAdvisorsBodyState extends State<_AdvAdvisorsBody> {
  late final AdvApi _api = AdvApi(widget.orgId);
  OrgPageRefresh? _refresh;
  AdvPage<AdvAdvisor>? _page;
  AdvAdvisor? _me;
  AdvLoad _load = AdvLoad.loading;
  String? _error;
  String _q = '', _status = 'all', _sort = 'load';
  int _pageNo = 1;
  int _seq = 0;

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
    final seq = ++_seq;
    final r = widget.manage
        ? await orgCall(() => _api.advisors(q: _q, status: _status, sort: _sort, page: _pageNo), quiet: true)
        : await orgCall(() => _api.myAdvisor(), quiet: true);
    if (!mounted || seq != _seq) return;
    setState(() {
      if (r.ok) {
        if (widget.manage) {
          _page = r.data as AdvPage<AdvAdvisor>;
        } else {
          _me = r.data as AdvAdvisor;
        }
        _load = AdvLoad.ready;
      } else {
        _load = r.endpointMissing ? AdvLoad.missing : AdvLoad.failed;
        _error = orgErrorText(r.error!);
      }
    });
    if (r.ok && mounted) OrgPageRefresh.reportUpdated(context);
  }

  void _query({String? q, String? status, String? sort, int page = 1}) {
    setState(() {
      _q = q ?? _q;
      _status = status ?? _status;
      _sort = sort ?? _sort;
      _pageNo = page;
      _load = AdvLoad.loading;
    });
    _reload();
  }

  Future<DateTime?> _pickDate(BuildContext ctx, DateTime? initial) {
    final now = DateTime.now();
    return showDatePicker(context: ctx, initialDate: initial ?? now, firstDate: DateTime(now.year - 2), lastDate: DateTime(now.year + 5));
  }

  Future<void> _open(AdvAdvisor a) async {
    final office = TextEditingController(text: a.officeLocation ?? '');
    final contact = TextEditingController(text: a.contactNote ?? '');
    final bio = TextEditingController(text: a.bio ?? '');
    var draft = AdvProfileDraft.of(a);
    var busy = false;
    String? error;
    List<AdvConflict>? conflicts;
    var started = false;
    final manage = widget.manage;
    final saved = await showAppSheet<AdvAdvisor>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          Future<void> loadConflicts() async {
            final r = await orgCall(() => _api.conflicts(advisorUserId: a.userId), quiet: true);
            if (ctx.mounted) set(() => conflicts = r.ok ? (r.data as AdvPage<AdvConflict>).items : const []);
          }

          if (manage && !started) {
            started = true;
            loadConflicts();
          }

          Future<void> submit() async {
            set(() {
              busy = true;
              error = null;
            });
            final body = draft.copyWith(officeLocation: office.text, contactNote: contact.text, bio: bio.text);
            final r = await orgCall(() => _api.saveProfile(a.userId, body), quiet: true);
            if (!ctx.mounted) return;
            if (!r.ok) {
              set(() {
                busy = false;
                error = orgErrorText(r.error!);
              });
              return;
            }
            showAppNotice(t('حُفظ الملف', 'Profile saved'));
            Navigator.pop(ctx, r.data as AdvAdvisor);
          }

          Future<void> addConflict() async {
            final x = await showAdvConflictSheet(ctx, _api, advisor: AdvRef(userId: a.userId, name: a.name));
            if (x == null || !ctx.mounted) return;
            set(() => conflicts = [...?conflicts, x]);
            if (x.assignedNow && mounted) {
              final move = await appConfirm(
                ctx,
                confirmLabel: t('نقل الطالب', 'Move the student'),
                message: t('${a.shown} يرشد ${x.studentName} الآن. نقل الطالب إلى مرشد آخر؟', '${a.shown} advises ${x.studentName} right now. Move the student to another advisor?'),
              );
              if (move && ctx.mounted) {
                Navigator.pop(ctx);
                _distribute(AdvPlanRequest(mode: 'reassign', from: AdvRef(userId: a.userId, name: a.name), memberIds: [x.memberId]));
              }
            }
          }

          Future<void> removeConflict(AdvConflict x) async {
            if (!await appConfirm(ctx, danger: true, confirmLabel: t('إزالة', 'Remove'), message: t('إزالة تعارض المصالح مع ${x.studentName}؟', 'Remove the conflict of interest with ${x.studentName}?'))) {
              return;
            }
            final r = await orgCall(() => _api.removeConflict(x.id), ok: t('أُزيل التعارض', 'Conflict removed'));
            if (r.ok && ctx.mounted) set(() => conflicts = [for (final y in conflicts ?? const <AdvConflict>[]) if (y.id != x.id) y]);
          }

          return AppSheetContent(
            title: manage ? t('ملف المرشد', 'Advisor profile') : t('بيانات التواصل', 'Contact details'),
            children: [
              AdvProfileForm(
                advisor: a,
                draft: draft,
                manage: manage,
                office: office,
                contact: contact,
                bio: bio,
                busy: busy,
                error: error,
                conflicts: conflicts,
                onDraft: (d) => set(() => draft = d),
                onPickFrom: () async {
                  final d = await _pickDate(ctx, draft.statusFrom);
                  if (d != null) set(() => draft = draft.copyWith(statusFrom: () => d));
                },
                onPickUntil: () async {
                  final d = await _pickDate(ctx, draft.statusUntil ?? draft.statusFrom);
                  if (d != null) set(() => draft = draft.copyWith(statusUntil: () => d));
                },
                onReassign: manage && a.load > 0
                    ? () {
                        Navigator.pop(ctx);
                        _distribute(AdvPlanRequest(mode: 'reassign', from: AdvRef(userId: a.userId, name: a.name)));
                      }
                    : null,
                onAddConflict: manage ? addConflict : null,
                onRemoveConflict: manage ? removeConflict : null,
                onSubmit: submit,
              ),
              ...advAdvisorCommLinks(ctx, orgId: widget.orgId, advisor: a, manage: manage), // Phase 5: office hours, ratings
            ],
          );
        }));
    if (saved == null || !mounted) return;
    if (!manage) {
      setState(() => _me = saved);
      return;
    }
    _reload();
    // newly away with students: offer to move them now
    if (saved.away && !a.away && saved.load > 0) {
      final move = await appConfirm(
        context,
        confirmLabel: t('نقل الطلاب', 'Move the students'),
        message: countText(saved.load,
            ar1: '${saved.shown} غائب الآن وله طالب واحد. نقله إلى مرشد آخر؟', ar2: '${saved.shown} غائب الآن وله طالبان. نقلهما إلى مرشدين آخرين؟',
            arFew: '${saved.shown} غائب الآن وله ${saved.load} طلاب. نقلهم إلى مرشدين آخرين؟',
            arMany: '${saved.shown} غائب الآن وله ${saved.load} طالباً. نقلهم إلى مرشدين آخرين؟',
            en1: '${saved.shown} is away now and has 1 student. Move them to another advisor?',
            en: '${saved.shown} is away now and has ${saved.load} students. Move them to other advisors?'),
      );
      if (move && mounted) _distribute(AdvPlanRequest(mode: 'reassign', from: AdvRef(userId: saved.userId, name: saved.name)));
    }
  }

  Future<void> _distribute(AdvPlanRequest request) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvDistributePage(orgId: widget.orgId, initial: request)));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.manage) {
      final me = _me;
      return AdvMyProfileView(
        load: _load,
        me: me,
        errorText: _error,
        onRetry: () => _query(),
        onEdit: me == null ? null : () => _open(me),
      );
    }
    return AdvAdvisorsView(
      load: _load,
      page: _page,
      status: _status,
      sort: _sort,
      errorText: _error,
      onRetry: () => _query(),
      onSearch: (q) => _query(q: q),
      onStatus: (s) => _query(status: s),
      onSort: (s) => _query(sort: s),
      onPage: (p) => _query(page: p),
      onOpen: _open,
      onDistribute: () => _distribute(const AdvPlanRequest(mode: 'rebalance')),
    );
  }
}
