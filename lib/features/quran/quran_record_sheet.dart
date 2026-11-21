// lib/features/quran/quran_record_sheet.dart — the record sheet (Learning Hub Phase 6, D-1347): one entry of
// surah + ayah range + kind + grade, POST /api/v1/quran/progress.
//
//   showQuranRecordSheet   the teacher (a student picked from one of HIS quran courses, or given) or the student
//                          himself (only while `self_log` is on; the caller checks it, the server says 403
//                          `quran_self_log_off` otherwise)
//   QuranRecordForm        plain values (test/ui/quran_layout_test.dart)
//
// Offline-safe: the entry gets its `client_id` when the form opens and keeps it on every retry; a network failure
// puts the entry in [QuranOutbox], which sends it again with the same id (the server answers `duplicate: true`).
// No Quran text: the surah is picked by name and the ayahs by number.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/quran/quran_api.dart';
import 'package:flutter_education_app/features/quran/quran_models.dart';

/// Opens the sheet; true when an entry was saved (or kept on the device for later).
///
/// [student] given → the teacher records for that student. [courses] (the teacher's quran programs) → the teacher
/// picks a program and one of its students. [selfLog] → the student records for himself.
Future<bool> showQuranRecordSheet(
  BuildContext context, {
  required QuranMeta meta,
  QuranApi? api,
  QuranStudentRef? student,
  List<QuranCourse> courses = const [],
  bool selfLog = false,
}) async {
  final a = api ?? QuranApi();
  final r = await showAppSheet<bool>(
    context,
    (_) => AppSheetContent(
      title: selfLog ? t('سجّل ما حفظت', 'Log what I memorized') : t('سجل التسميع', 'Record sheet'),
      icon: Icons.edit_note_rounded,
      children: [
        QuranRecordForm(
          meta: meta,
          student: student,
          courses: courses,
          selfLog: selfLog,
          loadStudents: a.courseStudents,
          onSubmit: (body) => _submit(a, body),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// null = saved; `''` = kept on the device for later; any other text = the server's refusal.
Future<String?> _submit(QuranApi api, Map<String, dynamic> body) async {
  try {
    final r = await api.record(body);
    showAppNotice(r.duplicate ? t('سُجّل هذا من قبل', 'This was already recorded') : t('تم التسجيل', 'Recorded'));
    return null;
  } catch (e) {
    if (quranDefiniteAnswer(e)) return quranErrorText(e);
    await QuranOutbox.add(body);
    showAppNotice(t('لا اتصال الآن: حُفظ التسجيل على هذا الجهاز وسيُرسل عند عودة الاتصال.',
        'No connection now: the entry is kept on this device and sent when you are back online.'));
    return '';
  }
}

class QuranRecordForm extends StatefulWidget {
  const QuranRecordForm({
    super.key,
    required this.meta,
    required this.onSubmit,
    this.student,
    this.courses = const [],
    this.selfLog = false,
    this.loadStudents,
    this.initialSurah,
  });

  final QuranMeta meta;

  /// The body (with its `client_id`) → null saved · `''` kept for later · a refusal's text.
  final Future<String?> Function(Map<String, dynamic> body) onSubmit;
  final QuranStudentRef? student;
  final List<QuranCourse> courses;
  final bool selfLog;
  final Future<List<QuranStudentRef>> Function(int courseId)? loadStudents;
  final int? initialSurah;

  @override
  State<QuranRecordForm> createState() => _QuranRecordFormState();
}

class _QuranRecordFormState extends State<QuranRecordForm> {
  String _clientId = newQuranClientId();
  late int _surah = widget.initialSurah ?? 1;
  final _from = TextEditingController(text: '1');
  final _to = TextEditingController();
  final _note = TextEditingController();
  String _kind = 'memorization';
  int? _grade;

  int? _courseId;
  QuranStudentRef? _student;
  List<QuranStudentRef> _students = const [];
  bool _loadingStudents = false;

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _student = widget.student;
    _to.text = '${widget.meta.surah(_surah)?.ayahs ?? 1}';
    if (widget.student == null && !widget.selfLog && widget.courses.length == 1) _pickCourse(widget.courses.first.id);
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _note.dispose();
    super.dispose();
  }

  int get _ayahs => widget.meta.surah(_surah)?.ayahs ?? 1;

  Future<void> _pickCourse(int? id) async {
    setState(() {
      _courseId = id;
      _student = null;
      _students = const [];
      _loadingStudents = id != null;
    });
    if (id == null || widget.loadStudents == null) return;
    try {
      final s = await widget.loadStudents!(id);
      if (!mounted || _courseId != id) return;
      setState(() {
        _students = s;
        _loadingStudents = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingStudents = false;
        _error = quranErrorText(e);
      });
    }
  }

  void _pickSurah(int? n) {
    if (n == null) return;
    setState(() {
      _surah = n;
      _from.text = '1';
      _to.text = '${widget.meta.surah(n)?.ayahs ?? 1}';
    });
  }

  String? _check() {
    final from = int.tryParse(_from.text.trim()), to = int.tryParse(_to.text.trim());
    if (!widget.selfLog && _student == null) return quranCodeText('quran_student_required');
    if (from == null || to == null || from < 1 || to < from || to > _ayahs) {
      return quranCodeText('quran_bad_range', {'ayahs': _ayahs});
    }
    return null;
  }

  Future<void> _save() async {
    final bad = _check();
    if (bad != null) {
      setState(() => _error = bad);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = <String, dynamic>{
      'client_id': _clientId,
      if (!widget.selfLog) 'student_id': _student!.id,
      'course_id': ?_courseId,
      'surah': _surah,
      'from_ayah': int.parse(_from.text.trim()),
      'to_ayah': int.parse(_to.text.trim()),
      'kind': _kind,
      'grade': ?_grade,
      if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
    };
    final r = await widget.onSubmit(body);
    if (!mounted) return;
    if (r == null || r.isEmpty) {
      _clientId = newQuranClientId(); // the next entry is a new one
      Navigator.of(context).maybePop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = r;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final teacherPicks = !widget.selfLog && widget.student == null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (widget.student != null) ...[
        AppInfoRow(Icons.person_rounded, widget.student!.name),
        const SizedBox(height: AppSpace.sm),
      ],
      if (teacherPicks) ...[
        AppDropdown<int>(
          key: const ValueKey('quran.record.course'),
          decoration: InputDecoration(labelText: t('البرنامج', 'Program')),
          value: _courseId,
          hint: Text(t('اختر البرنامج', 'Choose the program'), overflow: TextOverflow.ellipsis),
          items: [
            for (final p in widget.courses) DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: _pickCourse,
        ),
        const SizedBox(height: AppSpace.sm),
        AppDropdown<int>(
          key: const ValueKey('quran.record.student'),
          decoration: InputDecoration(labelText: t('الطالب', 'Student')),
          enabled: _students.isNotEmpty,
          value: _student?.id,
          hint: Text(
              _loadingStudents
                  ? t('جارٍ التحميل…', 'Loading…')
                  : _courseId != null && _students.isEmpty
                      ? t('لا طلاب في هذا البرنامج', 'No students in this program')
                      : t('اختر الطالب', 'Choose the student'),
              overflow: TextOverflow.ellipsis),
          items: [
            for (final s in _students) DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (id) => setState(() => _student = _students.where((s) => s.id == id).firstOrNull),
        ),
        const SizedBox(height: AppSpace.sm),
      ],
      AppDropdown<int>(
        key: const ValueKey('quran.record.surah'),
        decoration: InputDecoration(labelText: t('السورة', 'Surah')),
        value: _surah,
        items: [
          for (final s in widget.meta.surahs)
            DropdownMenuItem(value: s.number, child: Text('${s.number}. ${s.name}', overflow: TextOverflow.ellipsis)),
        ],
        onChanged: _pickSurah,
      ),
      const SizedBox(height: AppSpace.sm),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: AppNumberField(
            key: ValueKey('quran.record.from.$_surah'),
            controller: _from,
            label: t('من آية', 'From ayah'),
            min: 1,
            max: _ayahs,
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: AppNumberField(
            key: ValueKey('quran.record.to.$_surah'),
            controller: _to,
            label: t('إلى آية', 'To ayah'),
            min: 1,
            max: _ayahs,
          ),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: AppSpace.xxs),
        child: Text('${t('عدد آيات السورة', 'Ayahs in the surah')}: $_ayahs', style: AppType.meta(context).copyWith(color: c.textMedium)),
      ),
      const SizedBox(height: AppSpace.md),
      AppFieldLabel(t('النوع', 'Kind')),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final k in quranKinds)
          AppChoiceChip(key: ValueKey('quran.record.kind.$k'), label: quranGoalLabel(k), selected: _kind == k, onTap: () => setState(() => _kind = k)),
      ]),
      const SizedBox(height: AppSpace.md),
      AppFieldLabel(t('التقدير (اختياري)', 'Grade (optional)')),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (var g = 1; g <= 5; g++)
          AppChoiceChip(
            key: ValueKey('quran.record.grade.$g'),
            label: quranGradeLabel(g),
            selected: _grade == g,
            onTap: () => setState(() => _grade = _grade == g ? null : g),
          ),
      ]),
      const SizedBox(height: AppSpace.md),
      AppField(
        controller: _note,
        label: t('ملاحظة (اختيارية)', 'Note (optional)'),
        maxLines: 3,
        maxLength: 500,
      ),
      if (_error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!),
      ],
      const SizedBox(height: AppSpace.md),
      AppButtonRow(
        primary: AppButton.primary(
          key: const ValueKey('quran.record.save'),
          label: t('حفظ', 'Save'),
          icon: Icons.check_rounded,
          busy: _busy,
          onPressed: _busy ? null : _save,
        ),
      ),
    ]);
  }
}
