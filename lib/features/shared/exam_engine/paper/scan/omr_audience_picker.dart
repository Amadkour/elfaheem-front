// Choosing students of the exam by name for "A named sheet per student": the exam's audience from the engine
// (`GET …/omr/students?q=&limit=`, the course roster with the exam identifier masked except its last 4 characters),
// searched by a part of the name or 3+ characters of the ID, with "Select all" over what is listed. The selection
// survives a new search, so a teacher can pick across several searches. The server lists at most
// [kOmrAudiencePage] students per answer; a larger class is told to search for the others.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import '../../../../admin/admin_common.dart' show t;
import '../review/omr_review.dart' show OmrAudience, OmrReviewApi, OmrStudent, omrErrorText, omrLtr;

/// The most students `GET …/omr/students` answers at once (services/omr_review.students caps `limit` at 50).
const kOmrAudiencePage = 50;

/// "12 students selected" with the Arabic forms.
String omrSelectedText(int n) => countText(n,
    ar1: 'طالب واحد مختار', ar2: 'طالبان مختاران', arFew: '{n} طلاب مختارين', arMany: '{n} طالبًا مختارًا', en1: '1 student selected', en: '{n} students selected');

/// The picker's body, plain values (the layout harness pumps it).
class OmrAudiencePickerBody extends StatelessWidget {
  const OmrAudiencePickerBody({
    super.key,
    required this.queryController,
    required this.onQuery,
    required this.students,
    required this.total,
    required this.selected,
    required this.onToggle,
    required this.onSelectAll,
    required this.onClear,
    this.identifierLabel,
    this.error,
    this.noCourse = false,
    this.maxListHeight = 320,
  });

  final TextEditingController queryController;
  final ValueChanged<String> onQuery;

  /// null = loading.
  final List<OmrStudent>? students;

  /// How many students match the search on the server (may be more than listed).
  final int total;
  final Set<int> selected;
  final ValueChanged<OmrStudent> onToggle;

  /// Selects every listed student.
  final VoidCallback onSelectAll;
  final VoidCallback onClear;

  /// "Academic ID" (null when the exam identifies students by name).
  final String? identifierLabel;
  final String? error;

  /// The exam is linked to no course: there is no student list.
  final bool noCourse;
  final double maxListHeight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = students;
    if (noCourse) {
      return AppBanner(
          icon: Icons.info_outline_rounded,
          text: t('الاختبار غير مرتبط بمقرر، فلا توجد قائمة طلاب. اربطه بمقرر من محرر الاختبار.',
              'The exam is linked to no course, so there is no student list. Link it to a course in the exam editor.'));
    }
    final allShown = list != null && list.isNotEmpty && list.every((s) => selected.contains(s.id));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      // a Wrap: at 320 px with large text the count goes under the title instead of overflowing
      Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(t('طلاب الاختبار', 'Students of the exam'), style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
        if (selected.isNotEmpty)
          AppBadgePill(omrSelectedText(selected.length), color: c.primary, icon: Icons.check_circle_outline_rounded),
      ]),
      const SizedBox(height: AppSpace.xs),
      TextField(
        key: const ValueKey('omr.aud.search'),
        controller: queryController,
        onChanged: onQuery,
        onSubmitted: onQuery,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded),
          hintText: identifierLabel == null
              ? t('ابحث باسم الطالب', 'Search by the student\'s name')
              : t('ابحث بالاسم أو $identifierLabel', 'Search by name or $identifierLabel'),
        ),
      ),
      const SizedBox(height: AppSpace.xxs),
      Wrap(spacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        TextButton.icon(
          key: const ValueKey('omr.aud.all'),
          onPressed: list == null || list.isEmpty || allShown ? null : onSelectAll,
          icon: const Icon(Icons.done_all_rounded, size: 18),
          label: Text(list != null && list.length < total
              ? t('اختيار المعروضين (${list.length})', 'Select the ${list.length} shown')
              : t('اختيار الكل', 'Select all')),
        ),
        if (selected.isNotEmpty)
          TextButton.icon(
            key: const ValueKey('omr.aud.clear'),
            onPressed: onClear,
            icon: const Icon(Icons.clear_rounded, size: 18),
            label: Text(t('إلغاء الاختيار', 'Clear')),
          ),
      ]),
      if (error != null) AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      if (error == null && list == null) const AppListSkeleton(items: 3, padding: EdgeInsets.zero),
      if (error == null && list != null && list.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
          child: Text(
              queryController.text.trim().isEmpty ? t('لا يوجد طلاب في مقرر هذا الاختبار بعد', 'This exam\'s course has no students yet') : t('لا يوجد طالب يطابق البحث', 'No student matches'),
              style: appText(13, c: c.textMedium)),
        ),
      if (error == null && list != null && list.isNotEmpty)
        DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: c.divider), borderRadius: BorderRadius.circular(AppRadius.chip)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxListHeight),
            child: ListView.builder(
              key: const ValueKey('omr.aud.list'),
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
              itemCount: list.length,
              itemBuilder: (_, i) => _PickRow(student: list[i], selected: selected.contains(list[i].id), onTap: () => onToggle(list[i])),
            ),
          ),
        ),
      if (error == null && list != null && list.isNotEmpty && total > list.length) ...[
        const SizedBox(height: AppSpace.xxs),
        Text(t('يظهر ${list.length} من $total — ابحث بالاسم لتجد الباقين', 'Showing ${list.length} of $total — search by name to find the others'),
            style: appText(12, c: c.textMedium)),
      ],
    ]);
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({required this.student, required this.selected, required this.onTap});
  final OmrStudent student;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final id = student.identifier;
    return Semantics(
      checked: selected,
      button: true,
      label: id == null ? student.label : '${student.label}, ${omrLtr(id)}',
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('omr.aud.student.${student.id}'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
            child: Row(children: [
              Icon(selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, color: selected ? c.primary : c.textLight),
              const SizedBox(width: AppSpace.xs),
              AppAvatar(name: student.label, size: 32),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(student.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w600, c: c.textDark)),
                  if (id != null && id.isNotEmpty) Text(omrLtr(id), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The picker wired to `GET …/omr/students` (a search waits 300 ms for the typing to stop).
class OmrAudiencePicker extends StatefulWidget {
  const OmrAudiencePicker({super.key, required this.examId, required this.selected, required this.onChanged, this.api});
  final int examId;
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;
  final OmrReviewApi? api;

  @override
  State<OmrAudiencePicker> createState() => _OmrAudiencePickerState();
}

class _OmrAudiencePickerState extends State<OmrAudiencePicker> {
  late final OmrReviewApi _api = widget.api ?? OmrReviewApi();
  final _query = TextEditingController();
  Timer? _debounce;
  OmrAudience? _aud;
  String? _error;
  bool _loading = true;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _load(q.trim()));
  }

  Future<void> _load(String q) async {
    final seq = ++_seq;
    setState(() => _loading = true);
    final r = await _api.audience(widget.examId, q, limit: kOmrAudiencePage);
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      _error = r.ok ? null : omrErrorText(r);
      if (r.ok) _aud = OmrAudience.fromJson(r.map);
    });
  }

  void _toggle(OmrStudent s) {
    final next = {...widget.selected};
    next.contains(s.id) ? next.remove(s.id) : next.add(s.id);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final a = _aud;
    return OmrAudiencePickerBody(
      queryController: _query,
      onQuery: _onQuery,
      students: _loading && a == null ? null : (a?.items ?? const []),
      total: a?.total ?? 0,
      selected: widget.selected,
      onToggle: _toggle,
      onSelectAll: () => widget.onChanged({...widget.selected, for (final s in a?.items ?? const <OmrStudent>[]) s.id}),
      onClear: () => widget.onChanged(<int>{}),
      identifierLabel: a?.label,
      error: _error,
      noCourse: a?.reason == 'no_course',
    );
  }
}
