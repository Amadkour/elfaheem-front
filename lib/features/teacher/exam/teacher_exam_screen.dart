/// teacher/exam/teacher_exam_screen.dart
///
/// Full exam management for a course session:
///   ✅ Session picker step (or pre-selected from sessions_screen)
///   ✅ List exams for the selected session
///   ✅ Create exam: name, duration, marks + session picker + show_mode toggle
///   ✅ show_mode: "نشر فوري" (active) vs "جدولة" (scheduled) with date/time
///   ✅ Publish / Unpublish toggle per exam card
///   ✅ Delete exam with confirmation
///   ✅ Add / delete questions (MCQ + open-ended)
///   ✅ Results: ALL enrolled students with scores, "لم يحاول" for those who didn't
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:flutter_education_app/utils/widget/text_field.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_theme.dart';
import '../../../utils/widget/app_bar.dart';
import '../shared/exams_provider.dart';
import '../shared/live_models.dart';
import '../../../../core/api_client.dart';

// ── Local models for new fields ───────────────────────────────────────────────

class _SessionItem {
  final int id;
  final String name;
  final String? scheduledAt;

  const _SessionItem({required this.id, required this.name, this.scheduledAt});

  factory _SessionItem.fromJson(Map<String, dynamic> j) => _SessionItem(
    id: j['id'] as int,
    name: j['name'] as String,
    scheduledAt: j['scheduled_at'] as String?,
  );
}

class _RichExam {
  final int id;
  final String name;
  final String? description;
  final int courseId;
  final int? sessionId;
  final String? sessionName;
  final String showMode; // 'active' | 'scheduled'
  final String? startDate;
  final int? duration;
  final double? totalMarks;
  final double? passingScore;
  final bool isPublished;
  final int questionCount;

  const _RichExam({
    required this.id,
    required this.name,
    required this.courseId,
    required this.showMode,
    required this.isPublished,
    required this.questionCount,
    this.description,
    this.sessionId,
    this.sessionName,
    this.startDate,
    this.duration,
    this.totalMarks,
    this.passingScore,
  });

  factory _RichExam.fromJson(Map<String, dynamic> j) => _RichExam(
    id: j['id'] as int,
    name: j['name'] as String,
    description: j['description'] as String?,
    courseId: j['course_id'] as int,
    sessionId: j['session_id'] as int?,
    sessionName: j['session_name'] as String?,
    showMode: j['show_mode'] as String? ?? 'active',
    startDate: j['start_date'] as String?,
    duration: j['duration'] as int?,
    totalMarks: (j['total_marks'] as num?)?.toDouble(),
    passingScore: (j['passing_score'] as num?)?.toDouble(),
    isPublished: j['is_published'] as bool? ?? false,
    questionCount: j['question_count'] as int? ?? 0,
  );

  _RichExam copyWith({bool? isPublished}) => _RichExam(
    id: id,
    name: name,
    description: description,
    courseId: courseId,
    sessionId: sessionId,
    sessionName: sessionName,
    showMode: showMode,
    startDate: startDate,
    duration: duration,
    totalMarks: totalMarks,
    passingScore: passingScore,
    isPublished: isPublished ?? this.isPublished,
    questionCount: questionCount,
  );
}

class _StudentResult {
  final int studentId;
  final String studentName;
  final String? studentImage;
  final bool attempted;
  final double? marksObtained;
  final double totalMarks;
  final double? percentage;
  final bool? passed;

  const _StudentResult({
    required this.studentId,
    required this.studentName,
    required this.attempted,
    required this.totalMarks,
    this.studentImage,
    this.marksObtained,
    this.percentage,
    this.passed,
  });

  factory _StudentResult.fromJson(Map<String, dynamic> j) => _StudentResult(
    studentId: j['student_id'] as int,
    studentName: j['student_name'] as String,
    studentImage: j['student_image'] as String?,
    attempted: j['attempted'] as bool? ?? false,
    marksObtained: (j['marks_obtained'] as num?)?.toDouble(),
    totalMarks: (j['total_marks'] as num?)?.toDouble() ?? 0,
    percentage: (j['percentage'] as num?)?.toDouble(),
    passed: j['passed'] as bool?,
  );
}

// ── Screen ────────────────────────────────────────────────────────────────────

class TeacherExamScreen extends StatefulWidget {
  final int courseId;
  final String courseTitle;
  final int? sessionId; // pre-selected from sessions_screen
  final String? sessionName;

  const TeacherExamScreen({
    super.key,
    required this.courseId,
    required this.courseTitle,
    this.sessionId,
    this.sessionName,
  });

  @override
  State<TeacherExamScreen> createState() => _TeacherExamScreenState();
}

class _TeacherExamScreenState extends State<TeacherExamScreen> {
  final ApiClient _api = ApiClient();

  List<_RichExam> _exams = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExams());
  }

  Future<void> _loadExams() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final endpoint = widget.sessionId != null
          ? '/api/v1/sessions/${widget.sessionId}/exams'
          : '/api/v1/courses/${widget.courseId}/exams/all';
      final data = await _api.get(endpoint);
      setState(() {
        _exams = (data as List).map((e) => _RichExam.fromJson(e)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ── Publish / unpublish ───────────────────────────────────────────────────

  Future<void> _togglePublish(_RichExam exam) async {
    try {
      final path = exam.isPublished
          ? '/api/v1/exams/${exam.id}/unpublish'
          : '/api/v1/exams/${exam.id}/publish';
      await _api.post(path, body: {});
      setState(() {
        final idx = _exams.indexWhere((e) => e.id == exam.id);
        if (idx != -1) {
          _exams[idx] = exam.copyWith(isPublished: !exam.isPublished);
        }
      });
      _snack(
        exam.isPublished ? 'تم إخفاء الاختبار' : 'تم نشر الاختبار ✓',
        exam.isPublished ? AppTheme.accent : AppTheme.success,
      );
    } catch (e) {
      _snack('حدث خطأ: $e', AppTheme.danger);
    }
  }

  // ── Delete exam ───────────────────────────────────────────────────────────

  Future<void> _deleteExam(_RichExam exam) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'حذف الاختبار',
        body: 'هل تريد حذف "${exam.name}"؟ سيتم حذف جميع الأسئلة.',
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _api.delete('/api/v1/exams/${exam.id}');
      setState(() => _exams.removeWhere((e) => e.id == exam.id));
      _snack('تم الحذف', AppTheme.success);
    } catch (e) {
      _snack('فشل الحذف', AppTheme.danger);
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _openCreateSheet() => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CreateExamSheet(
      courseId: widget.courseId,
      sessionId: widget.sessionId,
      api: _api,
      onCreated: (exam) {
        setState(() => _exams.insert(0, exam));
      },
    ),
  );

  void _openQuestionsScreen(_RichExam exam) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<ExamsProvider>(),
        child: _QuestionsScreen(exam: exam, api: _api),
      ),
    ),
  ).then((_) => _loadExams()); // refresh count after returning

  void _openResultsScreen(_RichExam exam) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => _ResultsScreen(exam: exam, api: _api),
    ),
  );

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.sessionName ?? widget.courseTitle;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
            child: Column(children: [
              ScreenAppBar(
                title: 'الاختبارات — $subtitle',
                actions: [_AddBtn(onTap: _openCreateSheet)],
              ),
              Expanded(child: _buildBody()),
            ])),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(AppTheme.primary)));
    }
    if (_error != null) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 48, color: AppTheme.danger),
            const SizedBox(height: 12),
            Text(_error!, style: AppTheme.body, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: _loadExams, child: const Text('إعادة المحاولة')),
          ]));
    }
    if (_exams.isEmpty) return _EmptyState(onAdd: _openCreateSheet);

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _loadExams,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        physics: const BouncingScrollPhysics(),
        itemCount: _exams.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, i) => _ExamCard(
          exam: _exams[i],
          onPublish: () => _togglePublish(_exams[i]),
          onDelete: () => _deleteExam(_exams[i]),
          onQuestions: () => _openQuestionsScreen(_exams[i]),
          onResults: () => _openResultsScreen(_exams[i]),
        ),
      ),
    );
  }

  void _snack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg,
              style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
}

// ── Exam card ─────────────────────────────────────────────────────────────────

class _ExamCard extends StatelessWidget {
  final _RichExam exam;
  final VoidCallback onPublish, onDelete, onQuestions, onResults;

  const _ExamCard({
    required this.exam,
    required this.onPublish,
    required this.onDelete,
    required this.onQuestions,
    required this.onResults,
  });

  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          boxShadow: AppTheme.cardShadow,
          border: Border.all(
              color: exam.isPublished
                  ? AppTheme.success.withValues(alpha: 0.3)
                  : AppTheme.divider,
              width: exam.isPublished ? 1.5 : 0.5)),
      child: Column(children: [
        // ── Header ──────────────────────────────────────────────────
        Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.quiz_rounded,
                      color: Colors.white, size: 22)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(exam.name,
                            style: AppTheme.h3,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        // Session link badge
                        if (exam.sessionName != null)
                          Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(5)),
                              child: Text('🎓 ${exam.sessionName}',
                                  style: AppTheme.caption.copyWith(
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w600))),
                        Wrap(spacing: 10, children: [
                          if (exam.duration != null)
                            _Meta(Icons.timer_rounded, '${exam.duration} دقيقة'),
                          if (exam.totalMarks != null)
                            _Meta(Icons.grade_rounded,
                                '${exam.totalMarks!.toStringAsFixed(0)} درجة'),
                          _Meta(Icons.help_outline_rounded,
                              '${exam.questionCount} سؤال'),
                          // show_mode indicator
                          _Meta(
                              exam.showMode == 'scheduled'
                                  ? Icons.schedule_rounded
                                  : Icons.toggle_on_rounded,
                              exam.showMode == 'scheduled' ? 'مجدول' : 'يدوي'),
                        ]),
                      ])),
              // Published badge
              GestureDetector(
                  onTap: onPublish,
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: (exam.isPublished
                              ? AppTheme.success
                              : AppTheme.accent)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: (exam.isPublished
                                  ? AppTheme.success
                                  : AppTheme.accent)
                                  .withValues(alpha: 0.35))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                            exam.isPublished
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                            size: 12,
                            color: exam.isPublished
                                ? AppTheme.success
                                : AppTheme.accent),
                        const SizedBox(width: 4),
                        Text(exam.isPublished ? 'منشور' : 'مسودة',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10,
                                color: exam.isPublished
                                    ? AppTheme.success
                                    : AppTheme.accent,
                                fontWeight: FontWeight.w700)),
                      ]))),
            ])),

        // ── Action bar ───────────────────────────────────────────────
        Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(children: [
              Expanded(
                  child: _ActionBtn('الأسئلة', Icons.list_alt_rounded,
                      AppTheme.primaryGradient, onQuestions)),
              const SizedBox(width: 8),
              Expanded(
                  child: _ActionBtn(
                      'النتائج',
                      Icons.bar_chart_rounded,
                      const LinearGradient(
                          colors: [Color(0xFF8B6FFF), Color(0xFF5B8FFF)]),
                      onResults)),
              const SizedBox(width: 8),
              // Delete
              GestureDetector(
                  onTap: onDelete,
                  child: Container(
                      height: 36,
                      width: 40,
                      decoration: BoxDecoration(
                          color: AppTheme.danger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color: AppTheme.danger.withValues(alpha: 0.3))),
                      child: const Icon(Icons.delete_outline_rounded,
                          color: AppTheme.danger, size: 18))),
            ])),
      ]));
}

// ── Create exam bottom sheet ──────────────────────────────────────────────────

class _CreateExamSheet extends StatefulWidget {
  final int courseId;
  final int? sessionId;
  final ApiClient api;
  final void Function(_RichExam) onCreated;

  const _CreateExamSheet({
    required this.courseId,
    required this.api,
    required this.onCreated,
    this.sessionId,
  });

  @override
  State<_CreateExamSheet> createState() => _CreateExamSheetState();
}

class _CreateExamSheetState extends State<_CreateExamSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _durCtrl = TextEditingController(text: '30');
  final _totCtrl = TextEditingController(text: '10');
  final _passCtrl = TextEditingController(text: '5');
  final _key = GlobalKey<FormState>();

  // Session picker state
  List<_SessionItem> _sessions = [];
  _SessionItem? _selectedSession;
  bool _loadingSessions = false;

  // Show mode
  String _showMode = 'active'; // 'active' | 'scheduled'
  DateTime? _scheduledAt;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.sessionId == null) _loadSessions();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _durCtrl.dispose();
    _totCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    setState(() => _loadingSessions = true);
    try {
      final data =
      await widget.api.get('/api/v1/courses/${widget.courseId}/sessions');
      setState(() {
        _sessions = (data as List)
            .map((e) => _SessionItem.fromJson(e as Map<String, dynamic>))
            .toList();
        _loadingSessions = false;
      });
    } catch (_) {
      setState(() => _loadingSessions = false);
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(hours: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time =
    await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    setState(() => _scheduledAt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _submit() async {
    if (!_key.currentState!.validate()) return;
    if (_showMode == 'scheduled' && _scheduledAt == null) {
      _snack('اختر وقت بدء الاختبار', AppTheme.accent);
      return;
    }
    setState(() => _submitting = true);
    try {
      final body = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'course_id': widget.courseId,
        'show_mode': _showMode,
        if (_descCtrl.text.trim().isNotEmpty)
          'description': _descCtrl.text.trim(),
        if (_durCtrl.text.isNotEmpty) 'duration': int.tryParse(_durCtrl.text),
        if (_totCtrl.text.isNotEmpty)
          'total_marks': double.tryParse(_totCtrl.text),
        if (_passCtrl.text.isNotEmpty)
          'passing_score': double.tryParse(_passCtrl.text),
        if (widget.sessionId != null) 'session_id': widget.sessionId,
        if (_selectedSession != null) 'session_id': _selectedSession!.id,
        if (_scheduledAt != null) 'start_date': _scheduledAt!.toIso8601String(),
      };

      final data = await widget.api.post('/api/v1/exams', body: body);
      final created = _RichExam.fromJson(data as Map<String, dynamic>);
      if (mounted) {
        Navigator.pop(context);
        widget.onCreated(created);
        _snack('تم إنشاء الاختبار ✓', AppTheme.success);
      }
    } catch (e) {
      _snack('حدث خطأ: $e', AppTheme.danger);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 32),
        decoration: const BoxDecoration(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: SingleChildScrollView(
          child: Form(
            key: _key,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                      child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                              color: AppTheme.divider,
                              borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  Text('اختبار جديد', style: AppTheme.h2),
                  const SizedBox(height: 18),

                  // Name
                  MyTextField(
                      controller: _nameCtrl,
                      label: 'اسم الاختبار',
                      validator: (v) =>
                      v?.isEmpty ?? true ? 'أدخل اسم الاختبار' : null),
                  const SizedBox(height: 12),
                  MyTextField(
                      controller: _descCtrl,
                      label: 'الوصف (اختياري)',
                      maxLine: 2),
                  const SizedBox(height: 12),

                  // Duration / marks / passing
                  Row(children: [
                    Expanded(
                        child: MyTextField(
                            controller: _durCtrl,
                            label: 'المدة (دقيقة)',
                            keyboard: TextInputType.number)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: MyTextField(
                            controller: _totCtrl,
                            label: 'الدرجة الكاملة',
                            keyboard: TextInputType.number)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: MyTextField(
                            controller: _passCtrl,
                            label: 'درجة النجاح',
                            keyboard: TextInputType.number)),
                  ]),
                  const SizedBox(height: 16),

                  // ── Session picker (only when not pre-selected) ──
                  if (widget.sessionId == null) ...[
                    Text('الحصة (اختياري)', style: AppTheme.label),
                    const SizedBox(height: 8),
                    _loadingSessions
                        ? const LinearProgressIndicator()
                        : _sessions.isEmpty
                        ? Text('لا توجد حصص في هذا الكورس',
                        style: AppTheme.caption)
                        : Container(
                        decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.divider),
                            borderRadius: BorderRadius.circular(
                                AppTheme.radiusMedium)),
                        child: DropdownButtonHideUnderline(
                            child: DropdownButton<_SessionItem?>(
                              value: _selectedSession,
                              isExpanded: true,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12),
                              hint: Text('اختر حصة (اختياري)',
                                  style: AppTheme.caption),
                              items: [
                                const DropdownMenuItem<_SessionItem?>(
                                    value: null,
                                    child: Text('— بدون تحديد حصة',
                                        style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 13))),
                                ..._sessions.map((s) =>
                                    DropdownMenuItem<_SessionItem?>(
                                        value: s,
                                        child: Text(s.name,
                                            style: const TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 13))))
                              ],
                              onChanged: (v) =>
                                  setState(() => _selectedSession = v),
                            ))),
                    const SizedBox(height: 16),
                  ],

                  // ── Show mode toggle ──
                  Text('طريقة الإظهار', style: AppTheme.label),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                        child: _ModeBtn(
                            label: '⚡ نشر فوري',
                            subtitle: 'ظهر للطلاب حين تضغط نشر',
                            active: _showMode == 'active',
                            onTap: () => setState(() {
                              _showMode = 'active';
                              _scheduledAt = null;
                            }))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _ModeBtn(
                            label: '🕐 جدولة',
                            subtitle: 'يظهر تلقائياً في وقت محدد',
                            active: _showMode == 'scheduled',
                            onTap: () =>
                                setState(() => _showMode = 'scheduled'))),
                  ]),

                  // Date/time picker for scheduled mode
                  if (_showMode == 'scheduled') ...[
                    const SizedBox(height: 12),
                    GestureDetector(
                        onTap: _pickDateTime,
                        child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                                border: Border.all(
                                    color: _scheduledAt != null
                                        ? AppTheme.primary
                                        : AppTheme.divider),
                                borderRadius: BorderRadius.circular(
                                    AppTheme.radiusMedium),
                                color: _scheduledAt != null
                                    ? AppTheme.primary.withValues(alpha: 0.05)
                                    : AppTheme.background),
                            child: Row(children: [
                              Icon(Icons.calendar_today_rounded,
                                  size: 18,
                                  color: _scheduledAt != null
                                      ? AppTheme.primary
                                      : AppTheme.textLight),
                              const SizedBox(width: 10),
                              Text(
                                  _scheduledAt != null
                                      ? '${_scheduledAt!.year}/${_scheduledAt!.month.toString().padLeft(2, '0')}/${_scheduledAt!.day.toString().padLeft(2, '0')} — ${_scheduledAt!.hour.toString().padLeft(2, '0')}:${_scheduledAt!.minute.toString().padLeft(2, '0')}'
                                      : 'اختر تاريخ ووقت البدء',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 13,
                                      color: _scheduledAt != null
                                          ? AppTheme.primary
                                          : AppTheme.textLight)),
                            ]))),
                  ],

                  const SizedBox(height: 24),
                  MyPrimaryButton(
                      label: 'إنشاء الاختبار',
                      isLoading: _submitting,
                      onPressed: _submitting ? null : _submit),
                ]),
          ),
        ),
      ),
    );
  }

  void _snack(String msg, Color c) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg,
              style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          backgroundColor: c,
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
}

// ── Questions screen ──────────────────────────────────────────────────────────

class _QuestionsScreen extends StatefulWidget {
  final _RichExam exam;
  final ApiClient api;

  const _QuestionsScreen({required this.exam, required this.api});

  @override
  State<_QuestionsScreen> createState() => _QuestionsScreenState();
}

class _QuestionsScreenState extends State<_QuestionsScreen> {
  final ExamsProvider _prov = ExamsProvider();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _prov.fetchQuestions(widget.exam.id));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ChangeNotifierProvider.value(
        value: _prov,
        child: Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
              child: Column(children: [
                ScreenAppBar(
                  title: 'أسئلة — ${widget.exam.name}',
                  actions: [_AddBtn(onTap: () => _openAddSheet(context))],
                ),
                Expanded(child: Consumer<ExamsProvider>(
                  builder: (_, prov, __) {
                    if (prov.isLoadingExam && prov.questions.isEmpty) {
                      return const Center(
                          child: CircularProgressIndicator(
                              valueColor:
                              AlwaysStoppedAnimation(AppTheme.primary)));
                    }
                    if (prov.questions.isEmpty) {
                      return Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.help_outline_rounded,
                                size: 64, color: AppTheme.textLight),
                            const SizedBox(height: 12),
                            Text('لا توجد أسئلة بعد', style: AppTheme.body),
                            const SizedBox(height: 16),
                            GestureDetector(
                                onTap: () => _openAddSheet(context),
                                child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24, vertical: 12),
                                    decoration: BoxDecoration(
                                        gradient: AppTheme.primaryGradient,
                                        borderRadius: BorderRadius.circular(20)),
                                    child: const Text('أضف أول سؤال',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontFamily: 'Cairo')))),
                          ]));
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      physics: const BouncingScrollPhysics(),
                      itemCount: prov.questions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final q = prov.questions[i];
                        return _QuestionCard(
                          question: q,
                          index: i,
                          onDelete: () async {
                            final ok = await _prov.deleteQuestion(q.id);
                            if (context.mounted) {
                              _snack(context, ok ? 'تم حذف السؤال' : 'فشل الحذف',
                                  ok ? AppTheme.success : AppTheme.danger);
                            }
                          },
                        );
                      },
                    );
                  },
                )),
              ])),
        ),
      ),
    );
  }

  void _openAddSheet(BuildContext ctx) => showModalBottomSheet(
    context: ctx,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChangeNotifierProvider.value(
        value: _prov, child: _AddQuestionSheet(exam: widget.exam)),
  );
}

class _QuestionCard extends StatelessWidget {
  final dynamic question; // QuestionModel from exams_provider.dart
  final int index;
  final VoidCallback onDelete;

  const _QuestionCard(
      {required this.question, required this.index, required this.onDelete});

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          boxShadow: AppTheme.cardShadow),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(7)),
            child: Center(
                child: Text('${index + 1}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Cairo')))),
        const SizedBox(width: 10),
        Expanded(
            child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(question.title,
                  style: AppTheme.body.copyWith(fontWeight: FontWeight.w600)),
              if (question.options != null &&
                  (question.options as List).isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: (question.options as List).map<Widget>((opt) {
                      final isCorrect = opt == question.correctAnswer;
                      return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                              color: isCorrect
                                  ? AppTheme.success.withValues(alpha: 0.1)
                                  : AppTheme.background,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: isCorrect
                                      ? AppTheme.success.withValues(alpha: 0.5)
                                      : AppTheme.divider)),
                          child: Text(opt.toString(),
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: isCorrect
                                      ? AppTheme.success
                                      : AppTheme.textMedium,
                                  fontWeight: isCorrect
                                      ? FontWeight.w600
                                      : FontWeight.normal)));
                    }).toList()),
              ],
              const SizedBox(height: 4),
              Text('${question.marks} درجة', style: AppTheme.caption),
            ])),
        IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppTheme.danger, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints()),
      ]));
}

// ── Add question bottom sheet ─────────────────────────────────────────────────

class _AddQuestionSheet extends StatefulWidget {
  final _RichExam exam;

  const _AddQuestionSheet({required this.exam});

  @override
  State<_AddQuestionSheet> createState() => _AddQuestionSheetState();
}

class _AddQuestionSheetState extends State<_AddQuestionSheet> {
  final _titleCtrl = TextEditingController();
  final _correctCtrl = TextEditingController();
  final List<TextEditingController> _optCtrls =
  List.generate(4, (_) => TextEditingController());
  double _marks = 1;
  bool _isMcq = true;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _correctCtrl.dispose();
    for (final c in _optCtrls) c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    final options = _isMcq
        ? _optCtrls
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList()
        : <String>[];
    final r = await context.read<ExamsProvider>().addQuestion(
      examId: widget.exam.id,
      title: _titleCtrl.text.trim(),
      options: _isMcq ? options : null,
      correctAnswer: _isMcq && _correctCtrl.text.trim().isNotEmpty
          ? _correctCtrl.text.trim()
          : null,
      marks: _marks,
    );
    if (mounted) {
      Navigator.pop(context);
      _snack(context, r != null ? 'تم إضافة السؤال ✓' : 'حدث خطأ',
          r != null ? AppTheme.success : AppTheme.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<ExamsProvider>().isLoading;
    return _Sheet(
        title: 'إضافة سؤال',
        isLoading: loading,
        onSubmit: _submit,
        child: Column(children: [
          MyTextField(controller: _titleCtrl, label: 'نص السؤال', maxLine: 3),
          const SizedBox(height: 12),
          Row(children: [
            const Text('النوع:',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            _TypeToggle(
                'اختيار متعدد', _isMcq, () => setState(() => _isMcq = true)),
            const SizedBox(width: 8),
            _TypeToggle('مقالي', !_isMcq, () => setState(() => _isMcq = false)),
          ]),
          const SizedBox(height: 12),
          if (_isMcq) ...[
            ...List.generate(
                4,
                    (i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: MyTextField(
                        controller: _optCtrls[i], label: 'خيار ${i + 1}'))),
            const SizedBox(height: 4),
            MyTextField(
                controller: _correctCtrl, label: 'الإجابة الصحيحة (اختياري)'),
            const SizedBox(height: 12),
          ],
          Row(children: [
            const Text('الدرجة:',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
            Expanded(
                child: Slider(
                    value: _marks,
                    min: 0.5,
                    max: 10,
                    divisions: 19,
                    activeColor: AppTheme.primary,
                    onChanged: (v) => setState(() => _marks = v))),
            Container(
                width: 36,
                alignment: Alignment.center,
                child: Text(_marks.toStringAsFixed(1),
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.w700))),
          ]),
        ]));
  }
}

// ── Combined Results + Attendance screen ──────────────────────────────────────
// Each student row shows: attendance flag + check-in/out + exam score

class _CombinedStudentResult {
  final int studentId;
  final String studentName;
  final String? studentImage;
  // attendance
  final bool isAttended;
  final String? checkInDate;
  final String? checkOutDate;
  final double? durationMinutes;
  // exam
  final bool attempted;
  final double? marksObtained;
  final double totalMarks;
  final double? percentage;
  final bool? passed;
  final int questionCount;

  const _CombinedStudentResult({
    required this.studentId, required this.studentName,
    required this.isAttended, required this.attempted,
    required this.totalMarks, required this.questionCount,
    this.studentImage, this.checkInDate, this.checkOutDate,
    this.durationMinutes, this.marksObtained, this.percentage, this.passed,
  });

  factory _CombinedStudentResult.fromJson(Map<String, dynamic> j) =>
      _CombinedStudentResult(
        studentId:       j['student_id']       as int,
        studentName:     j['student_name']     as String,
        studentImage:    j['student_image']    as String?,
        isAttended:      j['is_attended']      as bool? ?? false,
        checkInDate:     j['check_in_date']    as String?,
        checkOutDate:    j['check_out_date']   as String?,
        durationMinutes: (j['duration_minutes'] as num?)?.toDouble(),
        attempted:       j['attempted']        as bool? ?? false,
        marksObtained:   (j['marks_obtained']  as num?)?.toDouble(),
        totalMarks:      (j['total_marks']     as num?)?.toDouble() ?? 0,
        percentage:      (j['percentage']      as num?)?.toDouble(),
        passed:          j['passed']           as bool?,
        questionCount:   j['question_count']   as int? ?? 0,
      );

  String _timeOf(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    } catch (_) { return '—'; }
  }

  String get checkInLabel  => _timeOf(checkInDate);
  String get checkOutLabel => _timeOf(checkOutDate);
}

class _ResultsScreen extends StatefulWidget {
  final _RichExam exam;
  final ApiClient api;

  const _ResultsScreen({required this.exam, required this.api});

  @override
  State<_ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<_ResultsScreen> {
  List<_CombinedStudentResult> _students = [];
  Map<String, dynamic> _summary = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Use the combined endpoint: attendance + exam results per student
      final data = await widget.api
          .get('/api/v1/exams/${widget.exam.id}/attendance-results');
      final map = data as Map<String, dynamic>;
      setState(() {
        _summary  = map;
        _students = (map['students'] as List? ?? [])
            .map((e) => _CombinedStudentResult.fromJson(e as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final total     = _students.length;
    final attended  = _summary['attended_count']  as int? ?? 0;
    final attempted = _summary['attempted_count'] as int? ?? 0;
    final passed    = _summary['passed_count']    as int? ?? 0;
    final avg       = (_summary['average_score']  as num?)?.toDouble() ?? 0.0;
    final sessionLinked = _summary['session_id'] != null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(child: Column(children: [
          ScreenAppBar(title: 'نتائج — ${widget.exam.name}'),

          // ── Summary stats ─────────────────────────────────────────
          if (!_loading && _error == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Row(children: [
                _StatCard2('المسجلون', '$total', AppTheme.primary),
                const SizedBox(width: 6),
                if (sessionLinked) ...[
                  _StatCard2('حضروا', '$attended', const Color(0xFF185FA5)),
                  const SizedBox(width: 6),
                ],
                _StatCard2('أجروا', '$attempted', AppTheme.accent),
                const SizedBox(width: 6),
                _StatCard2('ناجح', '$passed', AppTheme.success),
              ]),
            ),

          if (!_loading && _error == null && attempted > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(children: [
                const Icon(Icons.bar_chart_rounded, size: 13, color: AppTheme.textLight),
                const SizedBox(width: 4),
                Text('متوسط الدرجات: ${avg.toStringAsFixed(1)}%', style: AppTheme.caption),
                if (sessionLinked) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.how_to_reg_outlined, size: 13, color: AppTheme.textLight),
                  const SizedBox(width: 4),
                  Text('مرتبط بالحصة', style: AppTheme.caption),
                ],
              ]),
            ),

          Expanded(child: _loading
              ? const Center(child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(AppTheme.primary)))
              : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 48, color: AppTheme.danger),
            const SizedBox(height: 12),
            Text(_error!, style: AppTheme.body),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load,
                child: const Text('إعادة', style: TextStyle(fontFamily: 'Cairo'))),
          ]))
              : _students.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.people_outline, size: 64, color: AppTheme.textLight),
            const SizedBox(height: 12),
            Text('لا يوجد طلاب مسجلون في الكورس', style: AppTheme.body),
          ]))
              : RefreshIndicator(color: AppTheme.primary, onRefresh: _load,
              child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  physics: const BouncingScrollPhysics(),
                  itemCount: _students.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _CombinedResultCard(
                      result: _students[i],
                      showAttendance: sessionLinked)))),
        ])),
      ),
    );
  }
}

class _CombinedResultCard extends StatelessWidget {
  final _CombinedStudentResult result;
  final bool showAttendance;

  const _CombinedResultCard({required this.result, required this.showAttendance});

  @override
  Widget build(BuildContext ctx) {
    final examColor = !result.attempted
        ? AppTheme.textLight
        : (result.passed == true ? AppTheme.success : AppTheme.danger);
    final attColor = result.isAttended ? AppTheme.success : AppTheme.danger;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          boxShadow: AppTheme.cardShadow,
          border: Border.all(color: examColor.withValues(alpha: 0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Top row: avatar + name + badges ────────────────────────
        Row(children: [
          CircleAvatar(
              radius: 21,
              backgroundImage: result.studentImage != null
                  ? NetworkImage(result.studentImage!)
                  : null,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
              child: result.studentImage == null
                  ? Text(result.studentName.isNotEmpty ? result.studentName[0] : '?',
                  style: TextStyle(color: AppTheme.primary,
                      fontWeight: FontWeight.bold, fontFamily: 'Cairo'))
                  : null),
          const SizedBox(width: 10),
          Expanded(child: Text(result.studentName,
              style: AppTheme.h3.copyWith(fontSize: 14),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 6),
          // Attendance badge (only when linked to session)
          if (showAttendance)
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                    color: attColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(result.isAttended ? Icons.check_circle_outline : Icons.cancel_outlined,
                      size: 11, color: attColor),
                  const SizedBox(width: 3),
                  Text(result.isAttended ? 'حاضر' : 'غائب',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 10,
                          fontWeight: FontWeight.w700, color: attColor)),
                ])),
          const SizedBox(width: 6),
          // Exam badge
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                  color: examColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(
                  !result.attempted ? 'لم يحاول' : (result.passed == true ? 'ناجح' : 'راسب'),
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 10,
                      fontWeight: FontWeight.w700, color: examColor))),
        ]),

        // ── Attendance row (check-in / out / duration) ──────────────
        if (showAttendance && result.isAttended) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              _AttChip(Icons.login_rounded, result.checkInLabel, AppTheme.success),
              const SizedBox(width: 12),
              _AttChip(Icons.logout_rounded, result.checkOutLabel, AppTheme.danger),
              if (result.durationMinutes != null) ...[
                const SizedBox(width: 12),
                _AttChip(Icons.timer_outlined,
                    '${result.durationMinutes!.toStringAsFixed(0)} د', AppTheme.primary),
              ],
            ]),
          ),
        ],

        // ── Exam score bar ──────────────────────────────────────────
        if (result.attempted && result.percentage != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                    value: (result.percentage! / 100).clamp(0.0, 1.0),
                    backgroundColor: AppTheme.divider,
                    valueColor: AlwaysStoppedAnimation(examColor),
                    minHeight: 5))),
            const SizedBox(width: 8),
            Text(
                '${result.marksObtained?.toStringAsFixed(1) ?? '—'} / ${result.totalMarks.toStringAsFixed(1)} (${result.percentage!.toStringAsFixed(0)}%)',
                style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600)),
          ]),
        ] else if (!result.attempted) ...[
          const SizedBox(height: 6),
          Text('لم يجرِ الاختبار بعد',
              style: AppTheme.caption.copyWith(color: AppTheme.textLight)),
        ],
      ]),
    );
  }
}

class _AttChip extends StatelessWidget {
  final IconData icon; final String label; final Color color;
  const _AttChip(this.icon, this.label, this.color);
  @override
  Widget build(BuildContext _) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 11, color: color), const SizedBox(width: 3),
    Text(label, style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: color)),
  ]);
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _ModeBtn extends StatelessWidget {
  final String label, subtitle;
  final bool active;
  final VoidCallback onTap;

  const _ModeBtn(
      {required this.label,
        required this.subtitle,
        required this.active,
        required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              color: active
                  ? AppTheme.primary.withValues(alpha: 0.08)
                  : AppTheme.background,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(
                  color: active ? AppTheme.primary : AppTheme.divider,
                  width: active ? 2 : 1)),
          child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: AppTheme.label.copyWith(
                    color: active ? AppTheme.primary : AppTheme.textMedium,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
            const SizedBox(height: 2),
            Text(subtitle, style: AppTheme.caption.copyWith(fontSize: 10)),
          ])));
}

class _Sheet extends StatelessWidget {
  final String title;
  final bool isLoading;
  final Future<void> Function()? onSubmit;
  final Widget child;

  const _Sheet(
      {required this.title,
        required this.isLoading,
        required this.onSubmit,
        required this.child});

  @override
  Widget build(BuildContext ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
          padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 32),
          decoration: const BoxDecoration(
              color: AppTheme.cardBg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: AppTheme.divider,
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Text(title, style: AppTheme.h2),
                const SizedBox(height: 18),
                child,
                const SizedBox(height: 20),
                MyPrimaryButton(
                    label: 'حفظ', isLoading: isLoading, onPressed: onSubmit),
              ])));
}

class _Meta extends StatelessWidget {
  final IconData i;
  final String l;

  const _Meta(this.i, this.l);

  @override
  Widget build(BuildContext ctx) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 12, color: AppTheme.textLight),
        const SizedBox(width: 4),
        Text(l, style: AppTheme.caption),
      ]);
}

class _TypeToggle extends StatelessWidget {
  final String l;
  final bool a;
  final VoidCallback t;

  const _TypeToggle(this.l, this.a, this.t);

  @override
  Widget build(BuildContext ctx) => GestureDetector(
      onTap: t,
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: a
                  ? AppTheme.primary.withValues(alpha: 0.1)
                  : AppTheme.background,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(
                  color: a ? AppTheme.primary : AppTheme.divider,
                  width: a ? 2 : 1)),
          child: Text(l,
              style: AppTheme.label.copyWith(
                  color: a ? AppTheme.primary : AppTheme.textMedium,
                  fontWeight: a ? FontWeight.w700 : FontWeight.w500))));
}

class _AddBtn extends StatelessWidget {
  final VoidCallback onTap;

  const _AddBtn({required this.onTap});

  @override
  Widget build(BuildContext ctx) => GestureDetector(
      onTap: onTap,
      child: Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: AppTheme.primaryShadow),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 22)));
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext ctx) => Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.quiz_outlined, size: 64, color: AppTheme.textLight),
        const SizedBox(height: 12),
        Text('لا توجد اختبارات بعد', style: AppTheme.body),
        const SizedBox(height: 16),
        GestureDetector(
            onTap: onAdd,
            child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(20)),
                child: const Text('إنشاء أول اختبار',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Cairo'))))
      ]));
}

class _ActionBtn extends StatelessWidget {
  final String l;
  final IconData i;
  final LinearGradient g;
  final VoidCallback t;

  const _ActionBtn(this.l, this.i, this.g, this.t);

  @override
  Widget build(BuildContext ctx) => GestureDetector(
      onTap: t,
      child: Container(
          height: 36,
          decoration: BoxDecoration(
              gradient: g, borderRadius: BorderRadius.circular(18)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(i, color: Colors.white, size: 15),
            const SizedBox(width: 5),
            Text(l,
                style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ])));
}

class _StatCard2 extends StatelessWidget {
  final String l, v;
  final Color c;

  const _StatCard2(this.l, this.v, this.c);

  @override
  Widget build(BuildContext ctx) => Expanded(
      child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
              color: c.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: c.withValues(alpha: 0.25))),
          child: Column(children: [
            Text(v,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: c)),
            Text(l, style: AppTheme.caption.copyWith(fontSize: 10)),
          ])));
}

class _ConfirmDialog extends StatelessWidget {
  final String title, body;

  const _ConfirmDialog({required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title,
              style: const TextStyle(
                  fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          content: Text(body, style: const TextStyle(fontFamily: 'Cairo')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Cairo', color: AppTheme.textMedium))),
            ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.danger,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('حذف',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: Colors.white,
                        fontWeight: FontWeight.w700))),
          ]));
}

void _snack(BuildContext ctx, String msg, Color c) =>
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(msg,
            style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
        backgroundColor: c,
        behavior: SnackBarBehavior.floating,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));