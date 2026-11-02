// Exam Engine exams of a course, as the student sees them under the legacy course exams (Phase 5, D-018).
//
// Loads `GET /api/v1/exam/student/exams?course_id=` once; shows nothing when the engine is not deployed yet
// (`EngineResult.unavailable`) or when the course has no engine exams, so the legacy flow is untouched.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show asInt, asMapList, t;
import 'exam_engine_api.dart';
import 'exam_result_screen.dart';
import 'exam_taking_screen.dart';
import 'offline/offline_exam_screen.dart';
import 'offline/offline_exam_service.dart';

/// Plain-values card for one engine exam (under the layout harness).
class EngineExamCard extends StatelessWidget {
  const EngineExamCard({super.key, required this.exam, required this.onOpen, this.offlineSaved = false});
  final Map<String, dynamic> exam;
  final VoidCallback? onOpen;
  final bool offlineSaved;                 // the encrypted copy for a sitting without internet is on this phone

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // sat in class on paper (every section is a paper one): never started here — the server refuses with `paper_exam`
    final paper = exam['paper_only'] == true;
    final canStart = exam['can_start'] == true && !paper;
    final open = exam['open_attempt_id'] != null && !paper;
    final used = asInt(exam['attempts_used']), allowed = asInt(exam['attempts_allowed']);
    final results = asMapList(exam['results']);
    final last = results.isEmpty ? null : results.last;
    final duration = exam['duration_minutes'];
    final status = '${exam['status'] ?? ''}';
    final String action;
    if (open) {
      action = t('متابعة المحاولة', 'Resume attempt');
    } else if (canStart) {
      action = used == 0 ? t('ابدأ الاختبار', 'Start exam') : t('محاولة جديدة', 'New attempt');
    } else if (last != null) {
      action = last['visible'] == true ? t('عرض النتيجة', 'View result') : t('النتيجة قيد النشر', 'Result pending');
    } else if (paper) {
      action = paperExamLine;
    } else {
      action = status == 'closed' ? t('انتهى', 'Closed') : t('غير متاح', 'Unavailable');
    }
    return AppCard(
      onTap: onOpen,
      child: Row(children: [
        Container(
          width: 42, height: 42, alignment: Alignment.center,
          decoration: BoxDecoration(color: c.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
          child: Icon(open ? Icons.play_circle_outline_rounded : (paper ? Icons.edit_note_rounded : Icons.fact_check_outlined), color: c.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${exam['title'] ?? ''}', style: appText(14.5, w: FontWeight.w700, c: c.textDark), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Wrap(spacing: 10, runSpacing: 4, children: [
              if (duration != null) Text(t('$duration دقيقة', '$duration min'), style: appText(12, c: c.textMedium)),
              if (!paper) Text(t('المحاولات $used/$allowed', 'Attempts $used/$allowed'), style: appText(12, c: c.textMedium)),
              if (exam['starts_at'] != null) Text(AppTime.dateTime(DateTime.parse('${exam['starts_at']}Z')), style: appText(12, c: c.textMedium)),
              if (last != null && last['visible'] == true && last['percentage'] != null)
                Text('${last['percentage']}%', style: appText(12, w: FontWeight.w700, c: last['passed'] == true ? c.success : c.warning)),
            ]),
            const SizedBox(height: 6),
            // the action sits under the texts, not beside them: at 320 px with large text a trailing pill left the
            // title column 26 px wide (layout harness)
            Wrap(spacing: 6, runSpacing: 6, children: [
              AppBadgePill(action, color: canStart || open ? c.primary : c.textLight),
              if (paper && last != null) AppBadgePill(t('اختبار ورقي', 'Paper exam'), color: c.textLight, icon: Icons.edit_note_rounded),
              if (offlineSaved) AppBadgePill(t('محفوظ للحل دون اتصال', 'Saved for offline'), color: c.success, icon: Icons.offline_pin_rounded),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// The calm line a paper-only exam shows instead of a Start button.
String get paperExamLine => t('اختبار ورقي — يُؤدّى في الفصل', 'Paper exam — sat in class');

class EngineExamsSection extends StatefulWidget {
  const EngineExamsSection({super.key, this.courseId, this.orgId});
  final int? courseId;
  final int? orgId;

  @override
  State<EngineExamsSection> createState() => _EngineExamsSectionState();
}

class _EngineExamsSectionState extends State<EngineExamsSection> {
  final _api = ExamEngineApi();
  List<Map<String, dynamic>>? _items;
  bool _hidden = false;
  bool _offline = false;                   // no connection: the exams kept on this phone are shown instead
  final Set<int> _saved = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.courseId == null && widget.orgId == null) return;
    final r = await _api.studentExams(courseId: widget.courseId, orgId: widget.orgId);
    if (!mounted) return;
    setState(() {
      if (!r.ok) {
        _hidden = true;                    // not deployed, not routed, not a student here: the legacy list stands alone
        _offline = r.status == 0 && offlineExamsSupported;
        return;
      }
      _items = asMapList(r.map['items']);
      _hidden = _items!.isEmpty;
    });
    if (r.ok) _warmOffline();
  }

  /// Online: keep the encrypted copy (and its key once the exam opens) of every offline-enabled exam on the phone.
  Future<void> _warmOffline() async {
    final offline = (_items ?? const []).where((e) => e['offline'] == true).toList();
    if (offline.isEmpty || !offlineExamsSupported) return;
    await OfflineExamSync.instance.warmOnce();
    for (final e in offline) {
      final p = await OfflineExamSync.instance.warmExam(e);
      if (p != null && mounted) setState(() => _saved.add(p.examId));
    }
  }

  Future<void> _open(Map<String, dynamic> exam) async {
    final results = asMapList(exam['results']);
    if (exam['offline'] == true) {
      final begun = await offlineSittingFor(asInt(exam['id']));       // begun offline on this phone: continue there
      if (!mounted) return;
      if (begun != null) {
        await openOfflineExam(context, begun);
        if (mounted) await _load();
        return;
      }
    }
    if (exam['paper_only'] != true && (exam['can_start'] == true || exam['open_attempt_id'] != null)) {
      String? passcode;
      if (exam['has_passcode'] == true && exam['open_attempt_id'] == null) {
        passcode = await _askPasscode();
        if (passcode == null || !mounted) return;
      }
      await openEngineExam(context, exam, passcode: passcode);
      if (mounted) await _load();
      return;
    }
    if (results.isNotEmpty && mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ExamResultScreen(result: results.last, examTitle: '${exam['title'] ?? ''}')));
    }
  }

  Future<String?> _askPasscode() async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('رمز الدخول', 'Passcode')),
        content: TextField(controller: ctl, autofocus: true, obscureText: true, decoration: InputDecoration(labelText: t('أدخل الرمز الذي أعطاه المعلم', 'Enter the code your teacher gave'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('متابعة', 'Continue'))),
        ],
      ),
    );
    final value = ctl.text.trim();
    ctl.dispose();
    return ok == true ? value : null;
  }

  @override
  Widget build(BuildContext context) {
    if (_offline) return Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: OfflineExamsList(courseId: widget.courseId, shrinkWrap: true));
    if (_hidden || _items == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // embedded in the host's scroll view (its pull does not reach this section): a refresh button on every platform
        AppSectionTitle(t('اختبارات المقرر', 'Course exams'),
            subtitle: t('اختبارات بتوقيت الخادم وحفظ تلقائي', 'Server-timed exams with autosave'),
            trailing: AppRefreshAction(onRefresh: _load, always: true, size: 20)),
        for (final e in _items!)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            // a paper exam without a result has nothing to open
            child: EngineExamCard(exam: e, onOpen: e['paper_only'] == true && asMapList(e['results']).isEmpty ? null : () => _open(e),
                offlineSaved: _saved.contains(asInt(e['id']))),
          ),
      ]),
    );
  }
}
