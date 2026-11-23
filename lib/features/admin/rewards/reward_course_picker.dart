// lib/features/admin/rewards/reward_course_picker.dart — the rule form's "Selected courses" field (Games v4 G3):
// the chosen courses as removable chips with their names (and teachers), and an "Add courses" button that opens a
// search sheet (debounced search over `GET /api/v1/admin/courses`, multi-select with checkmarks, Done).
//
// A saved rule only holds ids: [RewardCoursesField] resolves their names through [RewardCoursesField.resolve]
// (`GET /api/v1/admin/courses/{id}`) and shows "Course #id" until a name arrives, so nothing is lost.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../admin_common.dart' show t;
import 'admin_rewards_api.dart';

/// Searches courses by text.
typedef RewardCourseSearch = Future<List<RewardsCourse>> Function(String q);

/// One course by id.
typedef RewardCourseResolve = Future<RewardsCourse> Function(int id);

/// The chip text of a course: its name and teacher, or "Course #id" while the name is unknown.
String rewardCourseLabel(int id, RewardsCourse? c) {
  final name = c?.name ?? '';
  if (name.isEmpty) return t('دورة رقم #$id', 'Course #$id');
  final teacher = c?.teacher?.trim() ?? '';
  return teacher.isEmpty ? name : '$name · $teacher';
}

/// The chosen courses as chips, plus "Add courses". [onChanged] gets the ids in the order they were chosen.
class RewardCoursesField extends StatefulWidget {
  const RewardCoursesField({
    super.key,
    required this.initialIds,
    required this.onChanged,
    required this.search,
    this.resolve,
  });

  final List<int> initialIds;
  final ValueChanged<List<int>> onChanged;
  final RewardCourseSearch search;

  /// Fetches a saved id's name (null: the chip keeps "Course #id").
  final RewardCourseResolve? resolve;

  @override
  State<RewardCoursesField> createState() => _RewardCoursesFieldState();
}

class _RewardCoursesFieldState extends State<RewardCoursesField> {
  late final List<int> _ids = List.of(widget.initialIds);
  final Map<int, RewardsCourse> _known = {};

  @override
  void initState() {
    super.initState();
    final resolve = widget.resolve;
    if (resolve == null) return;
    for (final id in _ids) {
      resolve(id).then((c) {
        if (mounted) setState(() => _known[id] = c);
      }, onError: (_) {
        // a deleted or unreachable course keeps "Course #id"
      });
    }
  }

  void _set(List<int> ids) {
    setState(() {
      _ids
        ..clear()
        ..addAll(ids);
    });
    widget.onChanged(List.of(_ids));
  }

  Future<void> _add() async {
    final picked = await showAppSheet<List<RewardsCourse>>(
      context,
      (_) => RewardCourseSearchSheet(
        search: widget.search,
        selected: [for (final id in _ids) _known[id] ?? RewardsCourse(id: id)],
      ),
    );
    if (picked == null || !mounted) return;
    for (final c in picked) {
      if (c.name.isNotEmpty || !_known.containsKey(c.id)) _known[c.id] = c;
    }
    _set([for (final c in picked) c.id]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('admin.rewards.form.course_picker'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _ids.isEmpty
              ? t('لم تُختر دورات بعد', 'No courses chosen yet')
              : countText(
                  _ids.length,
                  ar1: 'دورة واحدة مختارة',
                  ar2: 'دورتان مختارتان',
                  arFew: '${_ids.length} دورات مختارة',
                  arMany: '${_ids.length} دورة مختارة',
                  en1: '1 course chosen',
                  en: '${_ids.length} courses chosen',
                ),
          style: AppType.meta(context),
        ),
        if (_ids.isNotEmpty) ...[
          AppSpace.gapXs,
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              for (final id in _ids)
                InputChip(
                  key: ValueKey('admin.rewards.form.course_chip.$id'),
                  label: Text(rewardCourseLabel(id, _known[id]), maxLines: 1, overflow: TextOverflow.ellipsis),
                  deleteButtonTooltipMessage: t('إزالة', 'Remove'),
                  onDeleted: () => _set([for (final x in _ids) if (x != id) x]),
                ),
            ],
          ),
        ],
        AppSpace.gapXs,
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton.tonal(
            key: const ValueKey('admin.rewards.form.course_add'),
            label: t('إضافة دورات', 'Add courses'),
            icon: Icons.add_rounded,
            size: AppButtonSize.sm,
            onPressed: _add,
          ),
        ),
      ],
    );
  }
}

/// The search sheet: a debounced search box, the results with checkmarks, Done (pops the chosen courses).
class RewardCourseSearchSheet extends StatefulWidget {
  const RewardCourseSearchSheet({super.key, required this.search, this.selected = const []});

  final RewardCourseSearch search;
  final List<RewardsCourse> selected;

  @override
  State<RewardCourseSearchSheet> createState() => _RewardCourseSearchSheetState();
}

class _RewardCourseSearchSheetState extends State<RewardCourseSearchSheet> {
  // insertion order = the order the admin chose them
  late final Map<int, RewardsCourse> _chosen = {for (final c in widget.selected) c.id: c};
  List<RewardsCourse> _results = const [];
  bool _loading = true;
  bool _failed = false;
  String _q = '';
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String q) async {
    final req = ++_req;
    setState(() {
      _q = q;
      _loading = true;
      _failed = false;
    });
    try {
      final r = await widget.search(q);
      if (!mounted || req != _req) return;
      setState(() {
        _results = r;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || req != _req) return;
      setState(() {
        _results = const [];
        _failed = true;
        _loading = false;
      });
    }
  }

  void _toggle(RewardsCourse c) {
    setState(() {
      if (_chosen.remove(c.id) == null) _chosen[c.id] = c;
    });
  }

  Widget _resultsView() {
    if (_loading) {
      return const AppListSkeleton(items: 4, withAvatar: false, padding: EdgeInsets.zero);
    }
    if (_failed) {
      return AppEmpty(
        icon: Icons.cloud_off_rounded,
        title: t('تعذّر تحميل الدورات', 'Could not load the courses'),
        actionLabel: t('إعادة المحاولة', 'Try again'),
        onAction: () => _load(_q),
      );
    }
    if (_results.isEmpty) {
      return AppEmpty(
        icon: Icons.search_off_rounded,
        title: _q.isEmpty ? t('لا توجد دورات', 'No courses yet') : t('لا توجد دورات مطابقة', 'No matching courses'),
        message: _q.isEmpty ? null : t('جرّب اسماً آخر أو اسم المعلم.', 'Try another name or the teacher\'s name.'),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in _results)
          CheckboxListTile(
            key: ValueKey('admin.rewards.course.${c.id}'),
            value: _chosen.containsKey(c.id),
            onChanged: (_) => _toggle(c),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(c.name.isEmpty ? t('دورة رقم #${c.id}', 'Course #${c.id}') : c.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [if ((c.teacher ?? '').trim().isNotEmpty) c.teacher!.trim(), '#${c.id}'].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta(context),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = _chosen.length;
    return AppSheetContent(
      title: t('اختيار الدورات', 'Choose courses'),
      icon: Icons.menu_book_rounded,
      children: [
        AppSearchField(
          key: const ValueKey('admin.rewards.course_search'),
          hint: t('ابحث باسم الدورة أو المعلم أو رقمها', 'Search by course, teacher or number'),
          onChanged: _load,
        ),
        AppSpace.gapSm,
        _resultsView(),
        AppSpace.gapLg,
        AppButton.primary(
          key: const ValueKey('admin.rewards.course_done'),
          label: n == 0
              ? t('تم', 'Done')
              : t('تم ($n)', 'Done ($n)'),
          icon: Icons.check_rounded,
          expand: true,
          onPressed: () => Navigator.of(context).pop(_chosen.values.toList()),
        ),
      ],
    );
  }
}
