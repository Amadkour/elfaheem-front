// lib/features/org/advising/adv_accommodations.dart — accommodations (docs/advising/PHASE7.md "Accommodations", #24):
// an approved accommodation request grants one row per accommodation; the advising director may also grant or end
// one by hand. Staff see the note; the student sees labels and dates (adv_support_hub.dart). The organization-wide
// list (directors) is what exams and teaching follow up on.
//
//   AdvAccommodationCard · AdvGrantForm · AdvAccommodationsView   (plain values)
//   showAdvGrantSheet · showAdvEndAccommodationSheet · AdvAccommodationsPage   (through AdvSupportApi)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_header.dart' show OrgPageRefresh, OrgPushedPage;
import '../org_page_kit.dart';
import '../org_v3.dart' show orgCall;
import 'adv_case_parts.dart' show AdvTypedField, AdvTypedText;
import 'adv_models.dart' show AdvCategory, AdvPage, advNoteMaxLength;
import 'adv_parts.dart';
import 'adv_student_page.dart' show AdvStudentPage;
import 'adv_support_api.dart';
import 'adv_support_models.dart';
import 'adv_support_parts.dart';
import 'adv_support_texts.dart';

/// The categories a grant may use: active, with accommodations defined.
List<AdvCategory> advGrantCategories(List<AdvCategory> all) => [for (final c in all) if (c.active && c.accommodations.isNotEmpty) c];

/// "From 1 Nov · until 31 Jan" · "Since 1 Nov" · "".
String advAccommodationDates(AdvAccommodationGrant a) {
  final s = a.startsOn, e = a.endsOn;
  if (s != null && e != null) return t('من ${advDate(s, dateOnly: true)} حتى ${advDate(e, dateOnly: true)}', 'From ${advDate(s, dateOnly: true)} until ${advDate(e, dateOnly: true)}');
  if (e != null) return t('حتى ${advDate(e, dateOnly: true)}', 'Until ${advDate(e, dateOnly: true)}');
  if (s != null) return t('منذ ${advDate(s, dateOnly: true)}', 'Since ${advDate(s, dateOnly: true)}');
  return t('بلا تاريخ نهاية', 'No end date');
}

class AdvAccommodationCard extends StatelessWidget {
  const AdvAccommodationCard({super.key, required this.accommodation, this.student = false, this.showStudent = false, this.onEnd, this.onOpenStudent});
  final AdvAccommodationGrant accommodation;

  /// The student's own view: no note, no source details.
  final bool student;

  /// The organization-wide list: the student's name is the title.
  final bool showStudent;
  final VoidCallback? onEnd, onOpenStudent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = accommodation;
    final col = a.active ? c.primary : c.textMedium;
    final source = a.source == 'request' ? t('من طلب معتمد', 'from an approved request') : t('مُنح يدوياً', 'granted by hand');
    final meta = [
      advAccommodationDates(a),
      if (!student) source,
      if (!student && a.grantedBy != null) advIso(a.grantedBy!.shown),
      if (!a.active && a.endedAt != null) t('انتهى ${advDate(a.endedAt)}', 'ended ${advDate(a.endedAt)}'),
    ].join(' · ');
    final title = showStudent ? (a.studentName.isEmpty ? '#${a.memberId}' : a.studentName) : a.label;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppCard(
        onTap: onOpenStudent,
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ExcludeSemantics(
              child: Container(
                width: AppTouch.min - AppSpace.xs,
                height: AppTouch.min - AppSpace.xs,
                decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: AppRadius.chipAll),
                child: Icon(Icons.accessible_rounded, size: AppIconSize.md, color: appInk(context, col)),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                if (showStudent) Text(a.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: c.textDark)),
                Text(meta, style: AppType.meta(context)),
              ]),
            ),
            if (!a.active) ...[const SizedBox(width: AppSpace.xs), AppBadgePill(t('انتهى', 'Ended'), color: c.textMedium, icon: Icons.history_rounded)],
          ]),
          if (!student && a.note != null) ...[
            const SizedBox(height: AppSpace.xs),
            AdvTypedText(a.note!, maxLines: 4),
          ],
          if (!student && !a.active && a.endReason != null) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(t('سبب الإنهاء: ${a.endReason}', 'Why it ended: ${a.endReason}'), style: AppType.meta(context)),
          ],
          if (onEnd != null && a.active)
            Align(alignment: AlignmentDirectional.centerEnd, child: AdvSmallAction(icon: Icons.event_busy_rounded, label: t('إنهاء', 'End'), onTap: onEnd)),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Grant
// ═════════════════════════════════════════════════════════════════════════════

class AdvGrantForm extends StatelessWidget {
  const AdvGrantForm({
    super.key,
    required this.categories,
    required this.draft,
    required this.note,
    this.activeKeys = const {},
    this.busy = false,
    this.error,
    this.onCategory,
    this.onKey,
    this.onPickStart,
    this.onClearStart,
    this.onPickEnd,
    this.onClearEnd,
    this.onSubmit,
  });

  /// Active categories with accommodations ([advGrantCategories]).
  final List<AdvCategory> categories;
  final AdvGrantDraft draft;
  final TextEditingController note;

  /// Keys the student already has active (shown, not offered).
  final Set<String> activeKeys;
  final bool busy;
  final String? error;
  final ValueChanged<AdvCategory>? onCategory;
  final ValueChanged<String>? onKey;
  final VoidCallback? onPickStart, onClearStart, onPickEnd, onClearEnd, onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cat = categories.where((x) => x.id == draft.categoryId).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AdvFieldLabel(t('التصنيف', 'Category')),
      if (categories.isEmpty)
        Text(t('لا تصنيف معرّف فيه تسهيلات — أضفها من التصنيفات.', 'No category defines accommodations — add them under Categories.'), style: AppType.body(context))
      else
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final x in categories) AppChoiceChip(label: x.name, selected: x.id == draft.categoryId, onTap: busy || onCategory == null ? () {} : () => onCategory!(x)),
        ]),
      if (cat != null) ...[
        const SizedBox(height: AppSpace.md),
        AdvFieldLabel(t('التسهيلات', 'Accommodations')),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final a in cat.accommodations)
            activeKeys.contains(a.key)
                ? AppBadgePill('${a.label} · ${t('نشط', 'active')}', color: c.success, icon: Icons.check_rounded)
                : AppChoiceChip(
                    label: a.label,
                    icon: draft.keys.contains(a.key) ? Icons.check_rounded : Icons.add_rounded,
                    selected: draft.keys.contains(a.key),
                    onTap: busy || onKey == null ? () {} : () => onKey!(a.key),
                  ),
        ]),
      ],
      const SizedBox(height: AppSpace.md),
      AdvPersonField(
        label: t('من', 'From'),
        name: draft.startsOn == null ? null : advDate(draft.startsOn, dateOnly: true),
        placeholder: t('من اليوم', 'From today'),
        icon: Icons.event_available_rounded,
        avatar: false,
        onPick: busy ? null : onPickStart,
        onClear: busy ? null : onClearStart,
      ),
      const SizedBox(height: AppSpace.xs),
      AdvPersonField(
        label: t('حتى', 'Until'),
        name: draft.endsOn == null ? null : advDate(draft.endsOn, dateOnly: true),
        placeholder: t('بلا تاريخ نهاية', 'No end date'),
        icon: Icons.event_busy_rounded,
        avatar: false,
        onPick: busy ? null : onPickEnd,
        onClear: busy ? null : onClearEnd,
      ),
      const SizedBox(height: AppSpace.md),
      AdvTypedField(controller: note, label: t('ملاحظة للفريق (اختيارية)', 'Note for the team (optional)'), hint: t('لا يراها الطالب', 'The student does not see it'), minLines: 2, maxLength: advNoteMaxLength, enabled: !busy),
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(icon: Icons.accessible_rounded, label: t('منح التسهيلات', 'Grant the accommodations'), busy: busy, onPressed: draft.keys.isEmpty ? null : onSubmit),
    ]);
  }
}

/// Manage: grants accommodations to [memberId]; returns the new rows.
Future<List<AdvAccommodationGrant>?> showAdvGrantSheet(BuildContext context, AdvSupportApi api,
    {required int memberId, required List<AdvCategory> categories, Set<String> activeKeys = const {}}) {
  final note = TextEditingController();
  final cats = advGrantCategories(categories);
  var draft = AdvGrantDraft(categoryId: cats.length == 1 ? cats.first.id : cats.where((c) => c.key == 'accessibility').firstOrNull?.id);
  var busy = false;
  String? error;
  return showAppSheet<List<AdvAccommodationGrant>>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> submit() async {
          final d = draft.copyWith(note: note.text);
          final why = d.error;
          if (why != null) {
            set(() => error = why);
            return;
          }
          set(() {
            busy = true;
            error = null;
          });
          final r = await orgCall(() => api.grant(memberId, d), quiet: true);
          if (!ctx.mounted) return;
          if (!r.ok) {
            set(() {
              busy = false;
              error = advSupportErrorText(r.error!);
            });
            return;
          }
          showAppNotice(t('مُنحت التسهيلات وأُبلغ الطالب', 'Accommodations granted — the student is told'));
          Navigator.pop(ctx, r.data as List<AdvAccommodationGrant>);
        }

        Future<void> pick(DateTime? initial, void Function(DateTime) apply, {DateTime? first}) async {
          final d = await pickAdvDate(ctx, initial, first: first, days: 0);
          if (d != null) set(() => apply(d));
        }

        return AppSheetContent(
          title: t('منح تسهيلات', 'Grant accommodations'),
          children: [
            AdvGrantForm(
              categories: cats,
              draft: draft,
              note: note,
              activeKeys: activeKeys,
              busy: busy,
              error: error,
              onCategory: (c) => set(() => draft = draft.copyWith(categoryId: () => c.id, keys: const [])),
              onKey: (k) => set(() => draft = draft.toggle(k)),
              onPickStart: () => pick(draft.startsOn, (d) => draft = draft.copyWith(startsOn: () => d)),
              onClearStart: () => set(() => draft = draft.copyWith(startsOn: () => null)),
              onPickEnd: () => pick(draft.endsOn, (d) => draft = draft.copyWith(endsOn: () => d), first: draft.startsOn),
              onClearEnd: () => set(() => draft = draft.copyWith(endsOn: () => null)),
              onSubmit: submit,
            ),
          ],
        );
      }));
}

/// Manage: ends [a] now; returns the ended row.
Future<AdvAccommodationGrant?> showAdvEndAccommodationSheet(BuildContext context, AdvSupportApi api, AdvAccommodationGrant a) {
  final reason = TextEditingController();
  var busy = false;
  String? error;
  return showAppSheet<AdvAccommodationGrant>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> submit() async {
          set(() {
            busy = true;
            error = null;
          });
          final r = await orgCall(() => api.endAccommodation(a.id, reason: reason.text), quiet: true);
          if (!ctx.mounted) return;
          if (!r.ok) {
            set(() {
              busy = false;
              error = advSupportErrorText(r.error!);
            });
            return;
          }
          showAppNotice(t('انتهى التسهيل وأُبلغ الطالب', 'Accommodation ended — the student is told'));
          Navigator.pop(ctx, r.data as AdvAccommodationGrant);
        }

        final c = ctx.colors;
        return AppSheetContent(
          title: t('إنهاء التسهيل', 'End the accommodation'),
          children: [
            Text(a.label, style: AppType.section(ctx)),
            Text(advAccommodationDates(a), style: AppType.meta(ctx)),
            const SizedBox(height: AppSpace.md),
            AdvTypedField(controller: reason, label: t('السبب (اختياري)', 'Why (optional)'), minLines: 2, maxLength: 500, enabled: !busy),
            if (error != null) ...[
              const SizedBox(height: AppSpace.sm),
              AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
            ],
            const SizedBox(height: AppSpace.md),
            AppPrimaryButton(icon: Icons.event_busy_rounded, label: t('إنهاء الآن', 'End it now'), busy: busy, onPressed: submit),
          ],
        );
      }));
}

// ═════════════════════════════════════════════════════════════════════════════
//  The organization's accommodations (manage)
// ═════════════════════════════════════════════════════════════════════════════

class AdvAccommodationsView extends StatelessWidget {
  const AdvAccommodationsView({super.key, required this.load, this.page, this.status = 'active', this.errorText, this.onRetry, this.onStatus, this.onSearch, this.onPage, this.onOpen});
  final AdvLoad load;
  final AdvPage<AdvAccommodationGrant>? page;

  /// `active` · `ended` · '' (all).
  final String status;
  final String? errorText;
  final VoidCallback? onRetry;
  final ValueChanged<String>? onStatus, onSearch;
  final ValueChanged<int>? onPage;
  final ValueChanged<AdvAccommodationGrant>? onOpen;

  @override
  Widget build(BuildContext context) {
    final p = page;
    Widget body;
    if (load != AdvLoad.ready || p == null) {
      body = AdvPageFrame(children: [AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry, items: 4)]);
    } else if (p.items.isEmpty) {
      body = AdvPageFrame(children: [
        AppEmpty(
        icon: Icons.accessible_rounded,
        title: status == 'active' ? t('لا تسهيلات نشطة', 'No active accommodations') : t('لا تسهيلات', 'No accommodations'),
        message: t('تُمنح التسهيلات عند الموافقة على طلب تسهيلات، أو يمنحها مدير الإرشاد من ملف الطالب.',
            'Accommodations are granted when an accommodation request is approved, or by the advising director from the student\'s record.'),
        ),
      ]);
    } else {
      body = AdvPageFrame(children: [
        AdvSectionTitle(
          t('التسهيلات', 'Accommodations'),
          subtitle: t('لمتابعة الامتحانات والتدريس: من يحتاج ماذا، وحتى متى', 'For exams and teaching: who needs what, and until when'),
          first: true,
        ),
        for (final a in p.items) AdvAccommodationCard(accommodation: a, showStudent: true, onOpenStudent: onOpen == null ? null : () => onOpen!(a)),
        if (p.pages > 1 && onPage != null) ...[
          const SizedBox(height: AppSpace.sm),
          AppPagination(page: p.page, pageCount: p.pages, total: p.total, pageSize: p.size, onPage: onPage!),
        ],
      ]);
    }
    return OrgPageBody(
      search: onSearch == null ? null : OrgSearchField(hint: t('ابحث باسم الطالب', 'Search by student name'), onChanged: onSearch!),
      filter: onStatus == null
          ? null
          : OrgFilterButton<String>(
              value: status,
              defaultValue: 'active',
              label: t('الحالة', 'Status'),
              options: {'active': t('النشطة', 'Active'), 'ended': t('المنتهية', 'Ended'), '': t('الكل', 'All')},
              onChanged: onStatus!,
            ),
      child: body,
    );
  }
}

class AdvAccommodationsPage extends StatelessWidget {
  const AdvAccommodationsPage({super.key, required this.orgId});
  final int orgId;

  @override
  Widget build(BuildContext context) => OrgPushedPage(
        title: t('التسهيلات', 'Accommodations'),
        helpPageId: 'org.advising',
        maxWidth: AppWidth.wide.max,
        child: _AdvAccommodationsBody(orgId: orgId),
      );
}

class _AdvAccommodationsBody extends StatefulWidget {
  const _AdvAccommodationsBody({required this.orgId});
  final int orgId;

  @override
  State<_AdvAccommodationsBody> createState() => _AdvAccommodationsBodyState();
}

class _AdvAccommodationsBodyState extends State<_AdvAccommodationsBody> {
  late final AdvSupportApi _api = AdvSupportApi(widget.orgId);
  OrgPageRefresh? _refresh;
  AdvPage<AdvAccommodationGrant>? _page;
  AdvLoad _load = AdvLoad.loading;
  String? _error;
  String _status = 'active', _q = '';
  int _pageNo = 1, _seq = 0;

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
    final r = await orgCall(() => _api.orgAccommodations(status: _status, q: _q, page: _pageNo), quiet: true);
    if (!mounted || seq != _seq) return;
    setState(() {
      if (r.ok) {
        _page = r.data as AdvPage<AdvAccommodationGrant>;
        _load = AdvLoad.ready;
      } else {
        _load = advFailLoad(r);
        _error = advSupportErrorText(r.error!);
      }
    });
    if (r.ok && mounted) OrgPageRefresh.reportUpdated(context);
  }

  void _set({String? status, String? q, int page = 1}) {
    setState(() {
      _status = status ?? _status;
      _q = q ?? _q;
      _pageNo = page;
      _load = AdvLoad.loading;
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) => AdvAccommodationsView(
        load: _load,
        page: _page,
        status: _status,
        errorText: _error,
        onRetry: () => _set(page: _pageNo),
        onStatus: (s) => _set(status: s),
        onSearch: (q) => _set(q: q),
        onPage: (p) => _set(page: p),
        onOpen: (a) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdvStudentPage(orgId: widget.orgId, memberId: a.memberId, name: a.studentName))),
      );
}
