// lib/features/org/students/students_page.dart — the Students list of the organization dashboard (contract §4.1, §5).
//
//   OrgStudentsPage(orgId:, onOpenStudent:)   loads GET /students and owns the query; sits in the People hub (the
//                                             hub draws the header, help id `org.students`) or, with `pushed: true`,
//                                             wears its own OrgPushedPage
//   StudentsPageView(...)                     plain values (the layout harness pumps it):
//       summary cards       the whole organization's counts; a tap filters the list (`chip=`), a second tap clears it;
//                           "Awaiting acceptance" opens the Admissions page instead (§4.1)
//       toolbar             ONE search (name · student code · last 4 digits of the national ID), ONE filter
//                           (enrolment status), More (Import), the primary action "Add student" (the onboarding entry)
//       list                AppDataTable: a table on wide screens, StudentRowCard on phones; AppPagination
//       states              AppListSkeleton · AppErrorState · AppEmpty
//
// Times through AppTime, counts through countText, colours from context.colors, sizes from app_tokens.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t;
import '../onboarding/onboarding_entry.dart' show onboardingEntryOn, openOnboardingImport;
import '../onboarding/onboarding_page.dart' show OnboardingPage;
import '../org_page_header.dart' show OrgPushedPage;
import '../org_page_kit.dart' show OrgFilterButton, OrgMenuItem, OrgPageBody, OrgPrimaryAction, OrgSearchField, orgPageWideFrom;
import '../org_providers.dart' show OrgSession;
import '../org_v3.dart' show orgErrorText;
import 'add_student_sheet.dart' show showAddStudentSheet;
import 'students_api.dart';
import 'students_missing_sheet.dart';
import 'students_models.dart';
import 'students_parts.dart';

/// Opens one student (the student file, F2's `openStudentFile`).
typedef OpenStudent = void Function(BuildContext context, int orgId, StudentRow row);

class OrgStudentsPage extends StatefulWidget {
  const OrgStudentsPage({super.key, required this.orgId, this.onOpenStudent, this.api, this.pushed = false});
  final int orgId;

  /// A row tap; null = rows open nothing (the missing badge still opens its sheet).
  final OpenStudent? onOpenStudent;
  final StudentsApi? api;

  /// Pushed on top of the dashboard: wear OrgPushedPage (title + help) instead of sitting in the hub.
  final bool pushed;

  @override
  State<OrgStudentsPage> createState() => _OrgStudentsPageState();
}

class _OrgStudentsPageState extends State<OrgStudentsPage> {
  late final StudentsApi _api = widget.api ?? StudentsApi(widget.orgId);
  StudentsQuery _query = const StudentsQuery();
  StudentsPageData? _data;
  String? _error;
  bool _loading = true;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _api.list(_query);
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _data = StudentsPageData.fromJson(r.map);
      } else {
        _error = orgErrorText(r.error!);
      }
    });
  }

  void _set(StudentsQuery q) {
    _query = q;
    _load();
  }

  Widget _scope(Widget child) {
    try {
      final s = context.read<OrgSession>();
      return ChangeNotifierProvider<OrgSession>.value(value: s, child: child);
    } catch (_) {
      return child;
    }
  }

  Future<void> _add() async {
    // phase 3: pick the student type and the entry method first (full entry, basics + invite, link / QR, Excel)
    final r = await showAddStudentSheet(context, widget.orgId);
    if (mounted && r == true) _load();   // null: closed without opening anything
  }

  Future<void> _import() async {
    final r = await openOnboardingImport(context, module: 'students');
    if (!mounted) return;
    if (r == null) {
      showAppNotice(t('الاستيراد غير متاح حالياً', 'Importing is not available right now'), error: true);
    } else {
      _load();
    }
  }

  Future<void> _awaiting() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _scope(OrgPushedPage(
        title: t('الالتحاق والتعيين', 'Admissions & appointments'),
        helpPageId: 'org.onboarding',
        child: OnboardingPage(orgId: widget.orgId),
      )),
    ));
    if (mounted) _load();
  }

  Future<void> _missing(StudentRow row) async {
    await showMissingDataSheet(context, widget.orgId, row.id, name: row.name, api: _api);
  }

  @override
  Widget build(BuildContext context) {
    final open = widget.onOpenStudent;
    final can = _data?.can ?? const StudentsCan();
    final view = StudentsPageView(
      data: _data,
      loading: _loading,
      error: _error,
      query: _query,
      onRetry: _load,
      onSearch: (v) => _set(_query.copyWith(q: v)),
      onChip: (c) => _set(_query.copyWith(chip: c)),
      onEnrol: (e) => _set(_query.copyWith(enrol: e)),
      onSort: (s) => _set(_query.copyWith(sort: s)),
      onPage: (p) => _set(_query.copyWith(page: p)),
      onClearFilters: () => _set(StudentsQuery(sort: _query.sort, size: _query.size)),
      onAwaiting: onboardingEntryOn() ? _awaiting : null,
      onOpen: open == null ? null : (row) => open(context, widget.orgId, row),
      onMissing: _missing,
      onAdd: can.add ? _add : null,
      onImport: can.import ? _import : null,
    );
    if (!widget.pushed) return view;
    return OrgPushedPage(title: t('الطلاب', 'Students'), helpPageId: 'org.students', child: view);
  }
}

/// The page over plain values.
class StudentsPageView extends StatelessWidget {
  const StudentsPageView({
    super.key,
    this.data,
    this.loading = false,
    this.error,
    this.query = const StudentsQuery(),
    this.selectedId,
    this.onRetry,
    this.onSearch,
    this.onChip,
    this.onEnrol,
    this.onSort,
    this.onPage,
    this.onClearFilters,
    this.onAwaiting,
    this.onOpen,
    this.onMissing,
    this.onAdd,
    this.onImport,
  });

  /// null = nothing loaded yet.
  final StudentsPageData? data;
  final bool loading;

  /// The text to show (already `orgErrorText`).
  final String? error;
  final StudentsQuery query;

  /// The open student (a detail panel); null = none.
  final int? selectedId;
  final VoidCallback? onRetry, onClearFilters, onAwaiting, onAdd, onImport;
  final ValueChanged<String>? onSearch;

  /// A summary card was tapped: the `chip=` filter, null = clear it.
  final ValueChanged<String?>? onChip;

  /// The enrolment filter, null = every status.
  final ValueChanged<String?>? onEnrol;
  final ValueChanged<String>? onSort;
  final ValueChanged<int>? onPage;
  final ValueChanged<StudentRow>? onOpen, onMissing;

  @override
  Widget build(BuildContext context) {
    final d = data;
    final add = onAdd;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= orgPageWideFrom;
      return OrgPageBody(
        primary: add == null ? null : OrgPrimaryAction(id: 'students_add', icon: Icons.person_add_alt_1_rounded, label: t('إضافة طالب', 'Add student'), onTap: add),
        search: onSearch == null
            ? null
            : OrgSearchField(hint: t('الاسم أو الرقم الجامعي أو آخر 4 أرقام من الرقم القومي', 'Name, student code or last 4 ID digits'), onChanged: onSearch!),
        filter: onEnrol == null
            ? null
            : OrgFilterButton<String>(
                label: t('حالة القيد', 'Enrolment status'),
                value: query.enrol ?? '',
                defaultValue: '',
                options: {'': t('كل الحالات', 'All statuses'), for (final s in enrolStatuses) s: enrolLabel(s)},
                onChanged: (v) => onEnrol!(v.isEmpty ? null : v),
              ),
        more: [
          if (onImport != null) OrgMenuItem(icon: Icons.upload_file_rounded, label: t('استيراد من Excel', 'Import from Excel'), onTap: onImport!),
        ],
        top: d == null ? null : StudentsSummaryBar(summary: d.summary, selected: query.chip, onChip: onChip, onAwaiting: onAwaiting),
        child: Padding(
          // phones: room under the list for the Add button that floats at the bottom end
          padding: EdgeInsets.only(bottom: !wide && add != null ? AppTouch.primary + AppSpace.md : 0),
          child: _body(context),
        ),
      );
    });
  }

  Widget _body(BuildContext context) {
    final d = data;
    const pad = EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.md);
    if (d == null) {
      if (error != null) return Padding(padding: pad, child: AppErrorState(message: error, onRetry: onRetry));
      return const AppListSkeleton(padding: pad);
    }
    if (error != null && !loading) return Padding(padding: pad, child: AppErrorState(message: error, onRetry: onRetry));
    if (!loading && d.items.isEmpty) {
      final filtered = query.filtered;
      return SingleChildScrollView(
        padding: pad,
        child: AppEmpty(
          icon: Icons.school_outlined,
          title: filtered ? t('لا يوجد طلاب مطابقون', 'No matching students') : t('لا يوجد طلاب بعد', 'No students yet'),
          message: filtered
              ? t('جرّب كلمة أخرى أو امسح التصفية.', 'Try another word or clear the filter.')
              : t('أضف أول طالب أو استورد قائمة من Excel.', 'Add the first student or import a list from Excel.'),
          actionLabel: filtered ? (onClearFilters == null ? null : t('مسح التصفية', 'Clear filters')) : (onAdd == null ? null : t('إضافة طالب', 'Add student')),
          onAction: filtered ? onClearFilters : onAdd,
        ),
      );
    }
    final missing = onMissing;
    final open = onOpen;
    return Padding(
      padding: pad,
      child: AppDataTable<StudentRow>(
        key: const ValueKey('students.table'),
        rows: d.items,
        state: loading ? AppTableState.loading : AppTableState.ready,
        rowId: (r) => r.id,
        selectedRowId: selectedId,
        sortKey: query.sort == 'recent' ? null : query.sort,
        onSort: onSort == null ? null : (k, _) => onSort!(k),
        onRowTap: open,
        mobileCard: (context, r) => StudentRowCard(
          row: r,
          selected: r.id == selectedId,
          onTap: open == null ? null : () => open(r),
          onMissing: missing == null ? null : () => missing(r),
        ),
        columns: [
          AppTableColumn<StudentRow>(
            key: 'name',
            label: t('الطالب', 'Student'),
            primary: true,
            sortable: true,
            flex: 4,
            cell: (context, r) => _NameCell(row: r),
          ),
          AppTableColumn<StudentRow>(
            key: 'code',
            label: t('الرقم الجامعي', 'Student code'),
            sortable: true,
            flex: 2,
            cell: (context, r) => Text(r.studentCode ?? '—', textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
          ),
          AppTableColumn<StudentRow>(
            key: 'status',
            label: t('الحالة', 'Status'),
            flex: 3,
            cell: (context, r) => Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
              StudentStatusChip(r.chip),
              if (r.flags.isNotEmpty) StudentFlagChips(r.flags, max: 1),
            ]),
          ),
          AppTableColumn<StudentRow>(
            key: 'missing',
            label: t('النواقص', 'Missing'),
            flex: 2,
            hideBelow: Breakpoints.desktop,
            cell: (context, r) => r.hasMissing && missingBadgeOn()
                ? MissingBadge(count: r.missingCount, onTap: missing == null ? null : () => missing(r))
                : Text('—', style: AppType.meta(context)),
          ),
        ],
        pagination: d.pages > 1 && onPage != null
            ? AppPagination(page: d.page, pageCount: d.pages, total: d.total, pageSize: d.size, onPage: onPage!)
            : null,
      ),
    );
  }
}

class _NameCell extends StatelessWidget {
  const _NameCell({required this.row});
  final StudentRow row;

  @override
  Widget build(BuildContext context) {
    final meta = studentMetaLine(row);
    return Row(children: [
      StudentAvatar(user: row.user, size: AppIconSize.xl),
      AppSpace.gapSm,
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(row.name.isEmpty ? t('بدون اسم', 'No name') : row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
          if (meta.isNotEmpty) Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
        ]),
      ),
    ]);
  }
}

/// One summary card: what it counts and the `chip=` it filters by (`awaiting` opens Admissions instead).
class _SummaryKind {
  const _SummaryKind(this.key, this.icon, this.tone, this.label);
  final String key;
  final IconData icon;
  final AppTone tone;
  final String label;
}

/// The whole organization's counts as the list's filter (contract §4.1 `summary`).
class StudentsSummaryBar extends StatelessWidget {
  const StudentsSummaryBar({super.key, required this.summary, this.selected, this.onChip, this.onAwaiting});
  final StudentsSummary summary;

  /// The active `chip=` filter.
  final String? selected;
  final ValueChanged<String?>? onChip;
  final VoidCallback? onAwaiting;

  @override
  Widget build(BuildContext context) {
    final kinds = [
      _SummaryKind('enrolled', Icons.how_to_reg_outlined, AppTone.success, t('مقيدون', 'Enrolled')),
      if (missingBadgeOn()) _SummaryKind('missing', Icons.assignment_late_outlined, AppTone.warning, t('بيانات ناقصة', 'Missing data')),
      if (onAwaiting != null) _SummaryKind('awaiting', Icons.hourglass_top_rounded, AppTone.info, t('في انتظار القبول', 'Awaiting acceptance')),
      _SummaryKind('attention', Icons.flag_outlined, AppTone.danger, t('يحتاجون متابعة', 'Need attention')),
      _SummaryKind('suspended', Icons.pause_circle_outline_rounded, AppTone.warning, t('موقوف أو مؤجل', 'Paused')),
    ];
    Widget card(_SummaryKind k) => _SummaryCard(
          kind: k,
          count: summary.of(k.key),
          selected: selected == k.key,
          onTap: k.key == 'awaiting'
              ? onAwaiting
              : (onChip == null ? null : () => onChip!(selected == k.key ? null : k.key)),
        );
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth >= Breakpoints.mobile) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < kinds.length; i++) ...[
            if (i > 0) AppSpace.gapXs,
            Expanded(child: card(kinds[i])),
          ],
        ]);
      }
      // phones: one row that scrolls sideways (never squeezed, never wrapped into a tall block)
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < kinds.length; i++) ...[
            if (i > 0) AppSpace.gapXs,
            card(kinds[i]),
          ],
        ]),
      );
    });
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.kind, required this.count, this.selected = false, this.onTap});
  final _SummaryKind kind;
  final int count;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = appToneInk(context, kind.tone);
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: '${kind.label}: $count',
      excludeSemantics: true,
      child: AppCard(
        key: ValueKey('students.summary.${kind.key}'),
        highlight: selected,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
        onTap: onTap,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(AppSpace.xxs + 2),
            decoration: BoxDecoration(color: appTintOn(context, appToneColor(context, kind.tone)), borderRadius: AppRadius.chipAll),
            child: Icon(kind.icon, size: AppIconSize.md, color: ink),
          ),
          AppSpace.gapSm,
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('$count', style: AppType.figure(context)),
              Text(kind.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: selected ? c.textDark : c.textMedium)),
            ]),
          ),
          if (kind.key == 'awaiting' && onTap != null) ...[
            const SizedBox(width: AppSpace.xxs),
            Icon(Icons.chevron_right_rounded, size: AppIconSize.sm, color: c.textMedium),
          ],
        ]),
      ),
    );
  }
}
