// lib/features/courses/admin/course_trash/trash_page.dart
//
// The Super Admin's "Deleted courses" page (D-260): the trash (restore / delete permanently) and the permanently
// deleted record. Data comes from CourseTrashApi; the drawing is in trash_widgets.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppReveal;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show Debouncer, t;
import 'package:flutter_education_app/features/courses/admin/course_students/cs_widgets.dart' show CsAsyncBody, CsPager;
import 'package:flutter_education_app/features/courses/admin/course_trash/trash_api.dart';
import 'package:flutter_education_app/features/courses/admin/course_trash/trash_models.dart';
import 'package:flutter_education_app/features/courses/admin/course_trash/trash_widgets.dart';

String _err(Object e) {
  final ex = ApiException.from(e);
  return trashErrorText(ex.code, ex.message);
}

class CourseTrashPage extends StatefulWidget {
  const CourseTrashPage({super.key, this.api});
  final CourseTrashApi? api;

  @override
  State<CourseTrashPage> createState() => _CourseTrashPageState();
}

class _CourseTrashPageState extends State<CourseTrashPage> {
  late final CourseTrashApi _api = widget.api ?? CourseTrashApi();
  final _search = TextEditingController();
  final _delay = Debouncer();

  int _tab = 0; // 0 trash · 1 permanently deleted
  String _q = '';
  int _pageNo = 1;
  TrashPage<TrashItem> _trash = const TrashPage();
  TrashPage<PurgedItem> _purged = const TrashPage();
  bool _loading = true;
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
      if (_tab == 0) {
        final d = await _api.trash(q: _q, page: _pageNo);
        if (mounted && seq == _seq) setState(() => _trash = d);
      } else {
        final d = await _api.purged(q: _q, page: _pageNo);
        if (mounted && seq == _seq) setState(() => _purged = d);
      }
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = _err(e));
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  void _setTab(int i) {
    if (i == _tab) return;
    _tab = i;
    _pageNo = 1;
    _load();
  }

  void _setPage(int p) {
    _pageNo = p;
    _load();
  }

  void _setSearch(String v) {
    _q = v;
    _pageNo = 1;
    _load();
  }

  Future<void> _open(TrashItem item) async {
    await showAppDrawer<void>(
      context,
      title: t('كورس محذوف', 'Deleted course'),
      width: 560,
      builder: (ctx) => _TrashDetailLoader(item: item, api: _api, onChanged: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _tab == 0 ? _trash.items.length : _purged.items.length;
    final total = _tab == 0 ? _trash : _purged;
    return BasePage(
      width: AppWidth.wide,
      appBar: ScreenAppBar(title: t('الكورسات المحذوفة', 'Deleted courses')),
      child: AppRefresh(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.all(AppSpace.gutter(MediaQuery.sizeOf(context).width)),
          children: [
            AppTabs(
              index: _tab,
              onChanged: _setTab,
              items: [
                AppTabItem(t('في السلة', 'In the trash'), count: _tab == 0 ? _trash.total : null),
                AppTabItem(t('محذوف نهائياً', 'Permanently deleted'), count: _tab == 1 ? _purged.total : null),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            AppField(
              controller: _search,
              label: t('بحث باسم الكورس أو رقمه', 'Search by course name or id'),
              onChanged: (v) => _delay.run(() => _setSearch(v)),
              onSubmitted: (v) => _delay.flush(() => _setSearch(v)),
            ),
            const SizedBox(height: AppSpace.sm),
            CsAsyncBody(
              loading: _loading,
              error: _error,
              empty: items == 0,
              onRetry: _load,
              emptyIcon: _tab == 0 ? Icons.delete_outline_rounded : Icons.delete_forever_outlined,
              emptyTitle: _q.trim().isNotEmpty
                  ? t('لا نتائج مطابقة', 'No matching courses')
                  : (_tab == 0 ? t('السلة فارغة', 'The trash is empty') : t('لا كورسات محذوفة نهائياً', 'No permanently deleted courses')),
              builder: (_) => Column(children: [
                LayoutBuilder(builder: (context, box) {
                  final cols = box.maxWidth >= 900 ? 2 : 1;
                  final w = (box.maxWidth - AppSpace.sm * (cols - 1)) / cols;
                  final cards = _tab == 0
                      ? [for (final it in _trash.items) TrashCourseCard(item: it, onTap: () => _open(it))]
                      : [for (final it in _purged.items) TrashPurgedCard(item: it)];
                  // one entrance: the first cards settle in once per tab
                  return Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
                    for (final (i, c) in cards.indexed)
                      SizedBox(width: w, child: AppReveal(index: i, group: 'trash.$_tab', cap: 6, child: c)),
                  ]);
                }),
                CsPager(page: total.page, pages: total.pages, total: total.total, onPage: _setPage),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loads a trashed course's detail (history + purge plan) and offers restore / delete permanently.
class _TrashDetailLoader extends StatefulWidget {
  const _TrashDetailLoader({required this.item, required this.api, required this.onChanged});
  final TrashItem item;
  final CourseTrashApi api;
  final VoidCallback onChanged;

  @override
  State<_TrashDetailLoader> createState() => _TrashDetailLoaderState();
}

class _TrashDetailLoaderState extends State<_TrashDetailLoader> {
  TrashDetail? _detail;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await widget.api.detail(widget.item.courseId);
      if (mounted) setState(() => _detail = d);
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  Future<void> _restore(TrashDetail d) async {
    final reason = await showAppDialog<String>(
      context,
      title: t('استرجاع الكورس', 'Restore the course'),
      icon: Icons.restore_from_trash_rounded,
      body: Builder(
        builder: (ctx) => TrashRestoreForm(item: d.item, onCancel: () => Navigator.pop(ctx), onConfirm: (r) => Navigator.pop(ctx, r)),
      ),
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await widget.api.restore(d.item.courseId, reason: reason);
      var text = r.legacy
          ? t('تم استرجاع الكورس (دون طلابه)', 'The course was restored (without its students)')
          : t('تم استرجاع الكورس و${r.studentsRestored} طالب', 'The course was restored with ${r.studentsRestored} students');
      if (r.expiredMeanwhile > 0) {
        text += t('. انتهى اشتراك ${r.expiredMeanwhile} طالب أثناء حذف الكورس ويمكن تمديده من «الدورات والطلاب».',
            '. ${r.expiredMeanwhile} subscriptions ended while the course was deleted; they can be extended from Courses & students.');
      }
      showAppNotice(text);
      widget.onChanged();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      showAppNotice(_err(e), error: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _purge(TrashDetail d) async {
    final reason = await showAppDialog<String>(
      context,
      title: t('حذف الكورس نهائياً', 'Delete the course permanently'),
      icon: Icons.delete_forever_outlined,
      danger: true,
      body: Builder(
        builder: (ctx) => TrashPurgeForm(courseId: d.item.courseId, plan: d.plan, onCancel: () => Navigator.pop(ctx), onConfirm: (r) => Navigator.pop(ctx, r)),
      ),
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await widget.api.purge(d.item.courseId, reason: reason, confirm: '${d.item.courseId}');
      showAppNotice(t('تم الحذف النهائي (${r.rowsRemoved} سجل)', 'Permanently deleted (${r.rowsRemoved} records)'));
      widget.onChanged();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      showAppNotice(_err(e), error: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    if (_error != null) {
      return AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load);
    }
    if (d == null) return const SizedBox(height: 220, child: AppListSkeleton());
    return IgnorePointer(
      ignoring: _busy,
      child: AnimatedOpacity(
        opacity: _busy ? 0.5 : 1,
        duration: AppMotion.of(context).fast,
        child: TrashDetailBody(detail: d, onRestore: () => _restore(d), onPurge: () => _purge(d)),
      ),
    );
  }
}
