// The grade log of an exam (D-246): every change to a mark — who, when, old → new, why. Opened from the review screen,
// the results list and a student's attempt. Filters: a student (an attempt) and a question; paged with `before_id`.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show t;
import 'exam_authoring.dart' show authoringError;
import 'exam_grading.dart';
import 'exam_grading_widgets.dart';

/// The list body (plain values for the layout harness): rows, an empty state, "load more".
class GradeLogBody extends StatelessWidget {
  const GradeLogBody({super.key, required this.items, this.names = const {}, this.hasMore = false, this.loadingMore = false, this.onMore});
  final List<GradeLogEntry> items;

  /// attempt id → the student's name
  final Map<int, String> names;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return AppEmpty(
          icon: Icons.history_rounded,
          title: t('لا توجد تغييرات في الدرجات', 'No grade changes'),
          message: t('كل تعديل على درجة يظهر هنا مع من فعله ولماذا.', 'Every change to a mark shows up here with who made it and why.'));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final e in items) GradeLogRow(entry: e, studentName: e.attemptId == null ? null : names[e.attemptId]),
      if (hasMore)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Center(
            child: loadingMore
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                : OutlinedButton(key: const ValueKey('gradeLog.more'), onPressed: onMore, child: Text(t('عرض الأقدم', 'Show older'))),
          ),
        ),
    ]);
  }
}

class ExamGradeLogScreen extends StatefulWidget {
  const ExamGradeLogScreen({super.key, required this.examId, required this.examTitle, this.attemptId, this.questionId, this.attemptNames = const {}});
  final int examId;
  final String examTitle;

  /// A fixed starting filter (a student's attempt / a question).
  final int? attemptId;
  final int? questionId;

  /// attempt id → student name (the student filter's choices and the rows' names)
  final Map<int, String> attemptNames;

  @override
  State<ExamGradeLogScreen> createState() => _ExamGradeLogScreenState();
}

class _ExamGradeLogScreenState extends State<ExamGradeLogScreen> {
  final _api = ExamGradingApi();
  final _question = TextEditingController();
  late int? _attempt = widget.attemptId;
  int? _questionId;
  final List<GradeLogEntry> _items = [];
  int? _next;
  bool _loaded = false;
  bool _more = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _questionId = widget.questionId;
    if (_questionId != null) _question.text = '$_questionId';
    _load();
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more) setState(() => _more = true);
    final r = await _api.gradeLog(widget.examId, attemptId: _attempt, questionId: _questionId, beforeId: more ? _next : null);
    if (!mounted) return;
    setState(() {
      _more = false;
      _loaded = true;
      _error = r.ok ? null : authoringError(r);
      if (r.ok) {
        final page = GradeLogPage.fromJson(r.map);
        if (!more) _items.clear();
        _items.addAll(page.items);
        _next = page.nextBeforeId;
      } else if (!more) {
        _items.clear();
        _next = null;
      }
    });
  }

  void _setQuestion(String v) {
    final n = int.tryParse(v.trim());
    _questionId = n;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final names = widget.attemptNames;
    final choices = names.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    return BasePage(
      key: const ValueKey('exam.gradeLog'),
      appBar: AppHeader(title: t('سجل الدرجات', 'Grade log')),
      child: AppRefresh(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          AppHero(title: widget.examTitle, subtitle: t('كل تغيير في درجة مسجَّل: من، ومتى، ولماذا', 'Every change to a mark is recorded: who, when and why'), icon: Icons.history_rounded),
          const SizedBox(height: 4),
          if (choices.isNotEmpty)
            AppDropdown<int?>(
              key: const ValueKey('gradeLog.student'),
              value: _attempt,
              decoration: InputDecoration(labelText: t('الطالب', 'Student')),
              items: [
                DropdownMenuItem<int?>(value: null, child: Text(t('كل الطلاب', 'All students'))),
                for (final e in choices) DropdownMenuItem<int?>(value: e.key, child: Text(e.value, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) { _attempt = v; _load(); },
            ),
          const SizedBox(height: 10),
          AppField(
              key: const ValueKey('gradeLog.question'),
              controller: _question,
              label: t('رقم السؤال (اختياري)', 'Question number (optional)'),
              keyboard: TextInputType.number,
              ltr: true,
              onSubmitted: _setQuestion,
              onChanged: (v) { if (v.trim().isEmpty && _questionId != null) _setQuestion(''); }),
          const SizedBox(height: 12),
          if (_error != null) AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!),
          if (!_loaded) const AppListSkeleton(items: 4),
          if (_loaded) GradeLogBody(items: _items, names: names, hasMore: _next != null, loadingMore: _more, onMore: () => _load(more: true)),
        ]),
      ),
    );
  }
}
