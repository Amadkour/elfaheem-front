// Exam Engine exams of a course, as the student sees them under the legacy course exams (Phase 5, D-018).
//
// Loads `GET /api/v1/exam/student/exams?course_id=` once; shows nothing when the engine is not deployed yet
// (`EngineResult.unavailable`) or when the course has no engine exams, so the legacy flow is untouched.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart' show AppFonts;

import 'package:flutter_education_app/design/app_notice.dart' show showAppNotice;

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMapList, t;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';
import 'package:flutter_education_app/features/exams/exam_result_screen.dart';
import 'package:flutter_education_app/features/exams/exam_taking.dart' show examOpensAt, examOpensText, examStartBlockText;
import 'package:flutter_education_app/features/exams/exam_taking_screen.dart';
import 'package:flutter_education_app/features/exams/offline/offline_exam_screen.dart';
import 'package:flutter_education_app/features/exams/offline/offline_exam_service.dart';

/// Plain-values card for one engine exam (under the layout harness).
class EngineExamCard extends StatelessWidget {
  const EngineExamCard({super.key, required this.exam, required this.onOpen, this.offlineSaved = false, this.now});
  final Map<String, dynamic> exam;
  final VoidCallback? onOpen;
  final bool offlineSaved;                 // the encrypted copy for a sitting without internet is on this phone
  final DateTime? now;                     // the clock an older server's `starts_at` is judged by (tests)

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // sat in class on paper (every section is a paper one): never started here — the server refuses with `paper_exam`
    final paper = exam['paper_only'] == true;
    final open = exam['open_attempt_id'] != null && !paper;
    // not open yet: "Opens Thu 5 Nov, 11:00 AM" instead of a Start the server would refuse (409 exam_not_started)
    final opensAt = paper || open ? null : examOpensAt(exam, now: now);
    final canStart = engineExamStartable(exam, now: now);
    final block = exam['start_block'] is Map ? '${(exam['start_block'] as Map)['code'] ?? ''}' : '';
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
    } else if (opensAt != null) {
      action = examOpensText(opensAt);
    } else if (block == 'no_attempts_left') {
      action = t('لا محاولات متبقية', 'No attempts left');
    } else {
      action = status == 'closed' || block == 'exam_ended' ? t('انتهى', 'Closed') : t('غير متاح', 'Unavailable');
    }
    final live = canStart || open;
    final mark = open ? Icons.play_arrow_rounded : (paper ? Icons.edit_note_rounded : Icons.fact_check_rounded);
    final markTint = live ? appTintOn(context, c.primary) : c.inputBg;
    final metaStyle = AppType.meta(context);
    final pct = last != null && last['visible'] == true && last['percentage'] != null ? last['percentage'] : null;
    return AppCard(
      onTap: onOpen,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: AppTouch.min, height: AppTouch.min, alignment: Alignment.center,
          decoration: BoxDecoration(color: markTint, borderRadius: AppRadius.controlAll),
          child: Icon(mark, size: AppIconSize.lg, color: live ? appInkOn(context, c.primary, markTint) : c.textMedium),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${exam['title'] ?? ''}', style: AppType.section(context).copyWith(fontFamilyFallback: AppFonts.fallback), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: AppSpace.xxs),
            Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (duration != null) _MetaItem(icon: Icons.timer_outlined, text: t('$duration دقيقة', '$duration min'), style: metaStyle),
              if (!paper) _MetaItem(icon: Icons.replay_rounded, text: t('المحاولات $used/$allowed', 'Attempts $used/$allowed'), style: metaStyle),
              if (exam['starts_at'] != null && opensAt == null)
                _MetaItem(icon: Icons.event_rounded, text: AppTime.dateTime(DateTime.parse('${exam['starts_at']}Z')), style: metaStyle),
              if (pct != null)
                Text('$pct%', style: metaStyle.copyWith(fontWeight: FontWeight.w600,
                    color: last!['passed'] == true ? appInkOn(context, c.success, c.cardBg) : appInkOn(context, c.warning, c.cardBg))),
            ]),
            const SizedBox(height: AppSpace.sm),
            // the action sits under the texts, not beside them: at 320 px with large text a trailing pill left the
            // title column 26 px wide (layout harness)
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              AppStatusBadge(label: action, tone: live ? AppTone.brand : AppTone.neutral,
                  icon: opensAt != null ? Icons.schedule_rounded : (live ? (open ? Icons.play_arrow_rounded : Icons.arrow_forward_rounded) : null)),
              if (paper && last != null) AppStatusBadge(label: t('اختبار ورقي', 'Paper exam'), icon: Icons.edit_note_rounded),
              if (offlineSaved) AppStatusBadge(label: t('محفوظ للحل دون اتصال', 'Saved for offline'), tone: AppTone.success, icon: Icons.offline_pin_rounded),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// A meta line of the exam card: a small glyph and its text.
class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.icon, required this.text, required this.style});
  final IconData icon;
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: AppIconSize.xs, color: context.colors.textLight),
        const SizedBox(width: AppSpace.xxs),
        Flexible(child: Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]);
}

/// Whether the list offers a start (or a new attempt) of [exam] now: the server's `can_start`, never on paper, never
/// before the window opens (an older server without `start_block` said can_start true there).
bool engineExamStartable(Map<String, dynamic> exam, {DateTime? now}) =>
    exam['can_start'] == true && exam['paper_only'] != true && examOpensAt(exam, now: now) == null;

/// The calm line a paper-only exam shows instead of a Start button.
String get paperExamLine => t('اختبار ورقي — يُؤدّى في الفصل', 'Paper exam — sat in class');

class EngineExamsSection extends StatefulWidget {
  const EngineExamsSection({super.key, this.courseId, this.orgId, this.onCount});
  final int? courseId;
  final int? orgId;

  /// How many engine exams the section shows once loaded (0 when hidden): the host drops its own "no exams" line
  /// when there are some (the student's course Exams tab said "No exams for this course yet" under five exams).
  final ValueChanged<int>? onCount;

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
    widget.onCount?.call(r.ok ? _items!.length : 0);
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
    if (exam['paper_only'] != true && (engineExamStartable(exam) || exam['open_attempt_id'] != null)) {
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
      return;
    }
    // nothing to open yet: say why (when it opens, no attempt left, ended) — never a silent tap
    showAppNotice(examStartBlockText(exam) ?? t('هذا الاختبار غير متاح الآن', 'This exam is not available now'));
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
