// lib/features/courses/admin/course_students/cs_pages.dart
//
// The Super Admin's "Courses & students" pages: the courses list (with the "find a student" lookup) and a course's
// student roster. Data comes from CourseStudentsApi; the drawing is in cs_widgets.dart / cs_profile.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/config/app_config.dart' show Trans;
import 'package:flutter_education_app/features/admin/adm_kit.dart' show admRole;
import 'package:flutter_education_app/features/admin/sup/sup_kit.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show Debouncer, t;
import 'package:flutter_education_app/features/admin/admin_money_p8.dart' show p8SaveBytes;
import 'package:flutter_education_app/features/courses/admin/course_students/cs_api.dart';
import 'package:flutter_education_app/features/courses/admin/course_students/cs_models.dart';
import 'package:flutter_education_app/features/courses/admin/course_students/cs_profile.dart';
import 'package:flutter_education_app/features/courses/admin/course_students/cs_widgets.dart';

String _err(Object e) {
  final ex = ApiException.from(e);
  return csErrorText(ex.code, ex.message);
}

/// A filter dropdown with an "All" first item; ids travel as strings.
class _Filter extends StatelessWidget {
  const _Filter({required this.label, required this.value, required this.options, required this.onChanged});
  final String label;
  final String? value;
  final Map<String, String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => AppDropdown<String?>(
        value: options.containsKey(value) ? value : null,
        decoration: InputDecoration(labelText: label),
        items: [
          DropdownMenuItem<String?>(value: null, child: Text(t('الكل', 'All'))),
          for (final e in options.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onChanged,
      );
}

/// Filters laid out in a wrap: one per row on a phone, fixed-width on wide windows.
class _FilterWrap extends StatelessWidget {
  const _FilterWrap(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth < 600 ? box.maxWidth : 220.0;
        return Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [for (final c in children) SizedBox(width: w, child: c)]);
      });
}

// ── courses ─────────────────────────────────────────────────────────────────

class CourseStudentsPage extends StatefulWidget {
  const CourseStudentsPage({super.key, this.api});
  final CourseStudentsApi? api;

  @override
  State<CourseStudentsPage> createState() => _CourseStudentsPageState();
}

class _CourseStudentsPageState extends State<CourseStudentsPage> {
  late final CourseStudentsApi _api = widget.api ?? CourseStudentsApi();
  final _search = TextEditingController();
  final _lookup = TextEditingController();
  final _searchDelay = Debouncer();
  final _lookupDelay = Debouncer();

  CsQuery _q = const CsQuery(sort: 'name');
  CsCoursesPage _data = const CsCoursesPage();
  bool _loading = true;
  String? _error;
  int _seq = 0;

  List<CsStudent> _found = const [];
  bool _lookingUp = false;
  String? _lookupError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _lookup.dispose();
    _searchDelay.dispose();
    _lookupDelay.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _api.courses(_q);
      if (!mounted || seq != _seq) return;
      setState(() {
        // the filter lists come with every answer; keep the last non-empty ones if a page omits them
        _data = CsCoursesPage(
          items: d.items, total: d.total, page: d.page, pageSize: d.pageSize,
          teachers: d.teachers.isEmpty ? _data.teachers : d.teachers,
          categories: d.categories.isEmpty ? _data.categories : d.categories,
          orgs: d.orgs.isEmpty ? _data.orgs : d.orgs,
        );
      });
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = _err(e));
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  void _setQuery(CsQuery q) {
    _q = q;
    _load();
  }

  void _setExtra(String k, String? v) => _setQuery(_q.copyWith(page: 1, extra: {..._q.extra, k: v}));

  Future<void> _doLookup() async {
    final text = _lookup.text.trim();
    if (text.length < 2) {
      setState(() {
        _found = const [];
        _lookupError = null;
      });
      return;
    }
    setState(() {
      _lookingUp = true;
      _lookupError = null;
    });
    try {
      final r = await _api.lookup(text);
      if (mounted && _lookup.text.trim() == text) setState(() => _found = r);
    } catch (e) {
      if (mounted) setState(() => _lookupError = _err(e));
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ex = _q.extra;
    // redesign A1 (AdmStudents enrol): the role's hero; the page's own pull-to-refresh stays on the list
    return SupPage(
      role: admRole(context),
      width: AppWidth.wide,
      title: t('الدورات والطلاب', 'Courses & students'),
      kicker: 'admin_students'.tr,
      headline: t('اشتراك كل طالب في كل دورة', 'Every student’s place in every course'),
      line: t('سبب الوصول بالضبط، والتمديد أو المنح أو الإلغاء مع السجل.', 'Exactly why they have access; extend, grant or cancel, with the log.'),
      body: AppRefresh(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.all(AppSpace.gutter(MediaQuery.sizeOf(context).width)),
          children: [
            Text(t('ابحث عن طالب', 'Find a student'), style: AppType.section(context)),
            const SizedBox(height: AppSpace.xs),
            AppField(
              controller: _lookup,
              label: t('الرقم الأكاديمي · الرقم القومي · البريد · الهاتف · @المستخدم · الرقم', 'Academic ID · national ID · e-mail · phone · @username · id'),
              ltr: true,
              onChanged: (_) => _lookupDelay.run(_doLookup),
              onSubmitted: (_) => _lookupDelay.flush(_doLookup),
            ),
            if (_lookingUp) const Padding(padding: EdgeInsets.only(top: AppSpace.xs), child: LinearProgressIndicator()),
            if (_lookupError != null) Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: AppBanner(icon: Icons.error_outline_rounded, text: _lookupError!, color: c.danger)),
            if (_found.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xs),
              CsLookupResults(items: _found, onOpen: (s) => showCsProfileDrawer(context, s.id, title: s.name, api: _api, onChanged: _load)),
            ] else if (!_lookingUp && _lookup.text.trim().length >= 2 && _lookupError == null)
              Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text(t('لا نتائج', 'No match'), style: AppType.meta(context))),
            const SizedBox(height: AppSpace.lg),
            Text(t('الدورات', 'Courses'), style: AppType.section(context)),
            const SizedBox(height: AppSpace.xs),
            AppField(
              controller: _search,
              label: t('بحث باسم الدورة', 'Search by course name'),
              onChanged: (v) => _searchDelay.run(() => _setQuery(_q.copyWith(search: v, page: 1))),
              onSubmitted: (v) => _searchDelay.flush(() => _setQuery(_q.copyWith(search: v, page: 1))),
            ),
            const SizedBox(height: AppSpace.sm),
            _FilterWrap([
              _Filter(label: t('التصنيف', 'Category'), value: ex['category_id'], options: {for (final x in _data.categories) '${x.id}': x.name}, onChanged: (v) => _setExtra('category_id', v)),
              _Filter(label: t('المدرّس', 'Teacher'), value: ex['teacher_id'], options: {for (final x in _data.teachers) '${x.id}': x.name}, onChanged: (v) => _setExtra('teacher_id', v)),
              _Filter(
                label: t('الحالة', 'Status'),
                value: ex['status'],
                options: {for (final s in const ['published', 'draft', 'archived']) s: csCourseStatusLabel(s)},
                onChanged: (v) => _setExtra('status', v),
              ),
              if (_data.orgs.isNotEmpty) _Filter(label: t('المؤسسة', 'Organization'), value: ex['org_id'], options: {for (final x in _data.orgs) '${x.id}': x.name}, onChanged: (v) => _setExtra('org_id', v)),
              _SortPicker(
                value: _q.sort,
                desc: _q.desc,
                options: {
                  'name': t('الاسم', 'Name'),
                  'active': t('النشطون', 'Active students'),
                  'expired': t('المنتهون', 'Expired'),
                  'revenue': t('الإيراد', 'Revenue'),
                  'issues': t('المشاكل', 'Issues'),
                },
                onChanged: (s, d) => _setQuery(_q.copyWith(sort: s, desc: d, page: 1)),
              ),
            ]),
            const SizedBox(height: AppSpace.md),
            CsAsyncBody(
              loading: _loading,
              error: _error,
              empty: _data.items.isEmpty,
              onRetry: _load,
              emptyTitle: t('لا دورات مطابقة', 'No matching courses'),
              builder: (_) => Column(children: [
                CsCourseList(items: _data.items, onOpen: (r) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CourseRosterPage(courseId: r.id, courseName: r.name, api: _api)))),
                CsPager(page: _data.page, pages: _data.pages, total: _data.total, onPage: (p) => _setQuery(_q.copyWith(page: p))),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sort field + direction toggle in one field.
class _SortPicker extends StatelessWidget {
  const _SortPicker({required this.value, required this.desc, required this.options, required this.onChanged});
  final String? value;
  final bool desc;
  final Map<String, String> options;
  final void Function(String? sort, bool desc) onChanged;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: AppDropdown<String?>(
            value: options.containsKey(value) ? value : null,
            decoration: InputDecoration(labelText: t('الترتيب', 'Sort by')),
            items: [for (final e in options.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => onChanged(v, desc),
          ),
        ),
        IconButton(
          tooltip: desc ? t('تنازلي', 'Descending') : t('تصاعدي', 'Ascending'),
          onPressed: () => onChanged(value, !desc),
          icon: Icon(desc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded),
        ),
      ]);
}

// ── roster ──────────────────────────────────────────────────────────────────

class CourseRosterPage extends StatefulWidget {
  const CourseRosterPage({super.key, required this.courseId, required this.courseName, this.api});
  final int courseId;
  final String courseName;
  final CourseStudentsApi? api;

  @override
  State<CourseRosterPage> createState() => _CourseRosterPageState();
}

class _CourseRosterPageState extends State<CourseRosterPage> {
  late final CourseStudentsApi _api = widget.api ?? CourseStudentsApi();
  final _search = TextEditingController();
  final _delay = Debouncer();

  CsQuery _q = const CsQuery(sort: 'name');
  CsRoster _data = const CsRoster();
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _delay.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _api.roster(widget.courseId, _q);
      if (mounted && seq == _seq) setState(() => _data = d);
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = _err(e));
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  void _setQuery(CsQuery q) {
    _q = q;
    _load();
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final bytes = await _api.rosterCsv(widget.courseId, _q);
      await p8SaveBytes(bytes, 'course-${widget.courseId}-students.csv', mime: 'text/csv');
      showAppNotice(t('تم حفظ الملف', 'File saved'));
    } catch (e) {
      showAppNotice(_err(e), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _data.courseName.isNotEmpty ? _data.courseName : widget.courseName;
    final selected = _q.status == null ? null : csFilterStatuses.where((s) => csStatusWire(s) == _q.status).firstOrNull;
    return SupPage(
      role: admRole(context),
      width: AppWidth.wide,
      title: title,
      kicker: t('الدورات والطلاب', 'Courses & students'),
      headline: title,
      line: _data.teacherName.isEmpty ? null : _data.teacherName,
      body: AppRefresh(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.all(AppSpace.gutter(MediaQuery.sizeOf(context).width)),
          children: [
            Row(children: [
              Expanded(child: Text(t('الطلاب', 'Students') + (_data.teacherName.isEmpty ? '' : ' · ${_data.teacherName}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context))),
              OutlinedButton.icon(
                onPressed: _exporting ? null : _export,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text(t('تصدير CSV', 'Export CSV')),
                style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
              ),
            ]),
            const SizedBox(height: AppSpace.sm),
            CsStatusChips(roster: _data, selected: selected, onSelect: (s) => _setQuery(_q.copyWith(status: s == null ? null : csStatusWire(s), page: 1))),
            const SizedBox(height: AppSpace.sm),
            AppField(
              controller: _search,
              label: t('الاسم · الهاتف · البريد · الرقم الأكاديمي · الرقم القومي', 'Name · phone · e-mail · academic ID · national ID'),
              onChanged: (v) => _delay.run(() => _setQuery(_q.copyWith(search: v, page: 1))),
              onSubmitted: (v) => _delay.flush(() => _setQuery(_q.copyWith(search: v, page: 1))),
            ),
            const SizedBox(height: AppSpace.sm),
            _SortPicker(
              value: _q.sort,
              desc: _q.desc,
              options: {
                'name': t('الاسم', 'Name'),
                'start': t('البداية', 'Start'),
                'expiry': t('الانتهاء', 'Expiry'),
                'days_left': t('المتبقي', 'Days left'),
                'status': t('الحالة', 'Status'),
              },
              onChanged: (s, d) => _setQuery(_q.copyWith(sort: s, desc: d, page: 1)),
            ),
            const SizedBox(height: AppSpace.md),
            CsAsyncBody(
              loading: _loading,
              error: _error,
              empty: _data.items.isEmpty,
              onRetry: _load,
              emptyTitle: t('لا طلاب مطابقون', 'No matching students'),
              builder: (_) => Column(children: [
                CsRosterList(items: _data.items, onOpen: (r) => showCsProfileDrawer(context, r.student.id, title: r.student.name, api: _api, onChanged: _load)),
                CsPager(page: _data.page, pages: _data.pages, total: _data.total, onPage: (p) => _setQuery(_q.copyWith(page: p))),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
