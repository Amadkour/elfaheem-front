// "Import from Google Forms" (D-291): connect Google Drive, pick a form in the system browser (the Google Picker cannot
// run in a webview), check what will arrive, import it into this draft through the Excel import's checks.
//
//   POST /me/cloud/google_drive/forms/pick            → the page to open
//   GET  /me/cloud/google_drive/forms/pick/{session}  → pending | picked | cancelled
//   GET  /me/cloud/google_drive/forms/{form_id}       → the form as question rows
//   POST /api/v1/exam/exams/{id}/questions/import-rows
//
// GoogleFormsImportBody is plain values, under the layout harness; the sheet below it holds the flow.
//
// Two ways in: the editor's button (the draft exists: [GoogleFormsImportSheet.examId]) and "New exam › Import from
// Google Forms" (D-300: [GoogleFormsImportSheet.createExam] makes the draft, named after the form, once the form is
// picked; pick form → preview → create).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show asMap, asMapList, t;
import 'package:flutter_education_app/features/live/meeting_recording.dart';
import 'package:flutter_education_app/features/live/meeting_recording_sheets.dart' show cloudConnectPoll, cloudConnectPollLive, cloudConnectTimeout, openExternalUrl;
import 'exam_authoring.dart';
import 'exam_quick.dart' show QuickExam, QuickMode, QuickResult, QuickSource, createQuickExam;

/// The kill switch (the server also adds it to the disable list while GOOGLE_PICKER_API_KEY is unset).
const kGoogleFormsImportFeatureKey = 'exam.google_forms_import';

/// The exam's name once a form is picked: the form's title, else what the creator had, else a plain default.
String formExamTitle(FormPreview p, String current) {
  final f = p.title.trim();
  if (f.isNotEmpty) return f;
  final c = current.trim();
  return c.isNotEmpty ? c : t('اختبار من Google Forms', 'Google Forms exam');
}

/// "New exam › Import from Google Forms": the draft [q] describes (course, organization, timetable slot) is created
/// empty with the form's title, online; the rows are imported into its first section next.
Future<QuickResult> createExamForForm(ExamAuthoringApi api, QuickExam q, FormPreview p) {
  q
    ..title = formExamTitle(p, q.title)
    ..mode = q.mode ?? QuickMode.online
    ..source = QuickSource.questions;
  q.questions.clear();
  return createQuickExam(api, q, publish: false);
}

/// A form as `GET /me/cloud/google_drive/forms/{id}` returns it. [rows] go back to the server as they came.
class FormPreview {
  const FormPreview({required this.title, required this.isQuiz, required this.rows, required this.skipped});

  final String title;
  final bool isQuiz;
  final List<Map<String, dynamic>> rows;
  final List<(String, String)> skipped;

  static FormPreview fromJson(Map<String, dynamic> j) => FormPreview(
        title: '${j['title'] ?? ''}',
        isQuiz: j['is_quiz'] == true,
        rows: asMapList(j['questions']),
        skipped: [for (final s in asMapList(j['skipped'])) ('${s['title'] ?? ''}', '${s['reason'] ?? ''}')],
      );

  int get needsAnswer => rows.where((r) => r['needs_answer'] == true).length;
  int get ready => rows.length - needsAnswer;
  int get imagesDropped => rows.where((r) => r['image_dropped'] == true).length;
}

/// Why a question stays behind, in words.
String formSkipText(String reason) => switch (reason) {
      'scale' => t('مقياس خطي', 'Linear scale'),
      'date' => t('تاريخ', 'Date'),
      'time' => t('وقت', 'Time'),
      'empty' => t('بلا نص', 'No text'),
      _ => t('نوع غير مدعوم', 'Unsupported type'),
    };

const _formCodes = <String, (String, String)>{
  'forms_picker_unconfigured': ('استيراد Google Forms غير مفعّل على هذا الخادم بعد.', 'Google Forms import is not set up on this server yet.'),
  'forms_api_disabled': ('واجهة Google Forms غير مفعّلة على مشروع المنصة.', 'The Google Forms API is not enabled for this platform.'),
  'form_not_accessible': ('تعذّر فتح النموذج. اختره من جديد بحساب يملك تعديله.', 'That form could not be opened. Pick it again with an account that can edit it.'),
  'forms_read_failed': ('تعذّرت قراءة النموذج. حاول مرة أخرى.', 'The form could not be read. Try again.'),
  'pick_expired': ('انتهت صلاحية الاختيار. ابدأ من جديد.', 'The choice expired. Start again.'),
};

String formsErrorText(Object e) {
  final pair = _formCodes[ApiException.from(e).code ?? ''];
  return pair != null ? t(pair.$1, pair.$2) : meetingRecordingErrorText(e);
}

class GoogleFormsApi {
  GoogleFormsApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const _base = '/api/v1/me/cloud/google_drive/forms';

  Future<(String, String)> startPick() async {
    final r = asMap(await _api.post('$_base/pick'));
    return ('${r['session'] ?? ''}', '${r['picker_url'] ?? ''}');
  }

  Future<Map<String, dynamic>> pickState(String session) async => asMap(await _api.get('$_base/pick/$session'));
  Future<FormPreview> read(String formId) async => FormPreview.fromJson(asMap(await _api.get('$_base/$formId')));
}

/// What an import created and the rows it refused (Excel and Google Forms).
class ImportReportPanel extends StatelessWidget {
  const ImportReportPanel({super.key, required this.report});
  final ImportReport report;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = report;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppBanner(
          key: const ValueKey('exam.import.result'),
          icon: r.created > 0 ? Icons.task_alt_rounded : Icons.info_outline_rounded,
          color: r.created > 0 ? c.success : c.warning,
          text: r.created > 0 ? t('أُضيف ${r.created} سؤالاً', '${r.created} questions added') : t('لم يُضف أي سؤال', 'No question was added')),
      if (r.errors.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        Text(t('صفوف لم تُقبل (${r.errors.length})', 'Rows not accepted (${r.errors.length})'), style: appText(13, w: FontWeight.w700, c: c.danger)),
        const SizedBox(height: AppSpace.xs),
        for (final e in r.errors)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppBadgePill(t('صف ${e.row}', 'Row ${e.row}'), color: c.danger),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: Text(importRowText(e), style: appText(12.5, c: c.textDark))),
            ]),
          ),
      ],
    ]);
  }
}

class GoogleFormsImportBody extends StatelessWidget {
  const GoogleFormsImportBody({
    super.key,
    required this.loading,
    required this.connected,
    required this.waiting,
    required this.preview,
    required this.sections,
    required this.sectionId,
    required this.onSection,
    required this.report,
    required this.busy,
    required this.error,
    required this.onConnect,
    required this.onPick,
    required this.onImport,
    required this.onDone,
    this.creating = false,
  });

  /// "New exam": the import makes the draft first (the intro and the button say so).
  final bool creating;
  final bool loading;
  final bool connected;

  /// The browser is open: waiting for the connection or the choice.
  final bool waiting;
  final FormPreview? preview;
  final List<(int, String)> sections;
  final int? sectionId;
  final ValueChanged<int?> onSection;
  final ImportReport? report;
  final bool busy;
  final String? error;
  final VoidCallback? onConnect;
  final VoidCallback? onPick;
  final VoidCallback? onImport;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = preview;
    const gap = SizedBox(height: AppSpace.md);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(
          creating
              ? t('اختر نموذجاً من حسابك على Google: يصبح اختباراً جديداً باسمه، بأسئلته ودرجاته وإجاباته الصحيحة، ويبقى النموذج نفسه كما هو.',
                  'Pick a form from your Google account: it becomes a new draft exam with its name, questions, points and correct answers, and the form itself stays as it is.')
              : t('اختر نموذجاً من حسابك على Google: تصبح أسئلته ودرجاته وإجاباته الصحيحة أسئلة في هذه المسودة، ويبقى النموذج نفسه كما هو.',
                  'Pick a form from your Google account: its questions, points and correct answers become questions in this draft, and the form itself stays as it is.'),
          style: appText(13, c: c.textMedium, h: 1.4)),
      gap,
      if (loading)
        const AppListSkeleton(items: 1)
      else if (!connected)
        OutlinedButton.icon(
            key: const ValueKey('exam.forms.connect'),
            onPressed: waiting ? null : onConnect,
            icon: const Icon(Icons.add_to_drive_rounded, size: 18),
            label: Text(t('ربط Google Drive', 'Connect Google Drive')))
      else
        OutlinedButton.icon(
            key: const ValueKey('exam.forms.pick'),
            onPressed: waiting || busy ? null : onPick,
            icon: const Icon(Icons.quiz_outlined, size: 18),
            label: Text(p == null ? t('اختيار نموذج', 'Choose a form') : t('اختيار نموذج آخر', 'Choose another form'))),
      if (waiting) ...[
        gap,
        AppBanner(icon: Icons.open_in_browser_rounded, color: c.primary, text: t('أكمل في المتصفح ثم عد إلى هنا.', 'Finish in the browser, then come back here.')),
      ],
      if (p != null) ...[
        gap,
        AppCard(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(p.title.isEmpty ? t('نموذج بلا عنوان', 'Untitled form') : p.title,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(15, w: FontWeight.w700, c: c.textDark)),
            const SizedBox(height: AppSpace.sm),
            Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [
              AppBadgePill(t('جاهز: ${p.ready}', 'Ready: ${p.ready}'), icon: Icons.task_alt_rounded, color: c.success),
              if (p.needsAnswer > 0) AppBadgePill(t('بلا إجابة: ${p.needsAnswer}', 'No answer: ${p.needsAnswer}'), icon: Icons.help_outline_rounded, color: c.warning),
              if (p.skipped.isNotEmpty) AppBadgePill(t('لن يُستورد: ${p.skipped.length}', 'Left out: ${p.skipped.length}'), icon: Icons.remove_circle_outline_rounded, color: c.danger),
            ]),
          ]),
        ),
        if (p.needsAnswer > 0) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(
              key: const ValueKey('exam.forms.no_answers'),
              icon: Icons.help_outline_rounded,
              color: c.warning,
              text: t('أسئلة الاختيار بلا إجابة صحيحة لن تُستورد. فعّل «اختبار» في إعدادات النموذج وحدد الإجابات، ثم اختره من جديد.',
                  'Choice questions without a correct answer will not be imported. Turn on "Make this a quiz" in the form, set the answers, then choose it again.')),
        ],
        if (p.imagesDropped > 0) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(icon: Icons.image_not_supported_outlined, color: c.warning, text: t('الصور لا تُنقل: أضفها من محرر السؤال.', 'Images are not copied: add them in the question editor.')),
        ],
        for (final s in p.skipped)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Text('${formSkipText(s.$2)}: ${s.$1}', maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium)),
          ),
        if (sections.length > 1) ...[
          gap,
          AppDropdown<int?>(
            value: sectionId ?? sections.first.$1,
            decoration: InputDecoration(labelText: t('القسم', 'Section')),
            items: [for (final s in sections) DropdownMenuItem<int?>(value: s.$1, child: Text(s.$2, overflow: TextOverflow.ellipsis))],
            onChanged: onSection,
          ),
        ],
      ],
      if (error != null) ...[gap, AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!)],
      if (report != null) ...[gap, ImportReportPanel(report: report!)],
      gap,
      Row(children: [
        Expanded(child: TextButton(onPressed: busy ? null : onDone, child: Text(creating ? t('إلغاء', 'Cancel') : t('تم', 'Done')))),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          flex: 2,
          child: AppPrimaryButton(
              key: const ValueKey('exam.forms.import'),
              label: creating ? t('إنشاء الاختبار', 'Create the exam') : t('استيراد', 'Import'),
              icon: creating ? Icons.add_task_rounded : Icons.download_rounded,
              busy: busy,
              onPressed: p != null && p.ready > 0 && report == null ? onImport : null),
        ),
      ]),
    ]);
  }
}

class GoogleFormsImportSheet extends StatefulWidget {
  const GoogleFormsImportSheet({super.key, required this.api, this.examId, this.sections = const [], this.createExam})
      : assert(examId != null || createExam != null);
  final ExamAuthoringApi api;

  /// The draft the questions go into; null = [createExam] makes it when "Create the exam" is pressed.
  final int? examId;
  final List<(int, String)> sections;

  /// "New exam": makes the draft for the picked form (its id, or the error to show). Called once: a retry of the
  /// import after a failure goes into the draft already made. The sheet closes by itself after a clean import.
  final Future<QuickResult> Function(FormPreview form)? createExam;

  @override
  State<GoogleFormsImportSheet> createState() => _GoogleFormsImportSheetState();
}

class _GoogleFormsImportSheetState extends State<GoogleFormsImportSheet> {
  final _cloud = RemoteMeetingRecordingApi();
  final _forms = GoogleFormsApi();
  EventOrPoll? _poll;
  DateTime? _since;
  bool _loading = true, _connected = false, _waiting = false, _busy = false;
  FormPreview? _preview;
  ImportReport? _report;
  int? _section;
  String? _error;
  late int? _examId = widget.examId;

  @override
  void initState() {
    super.initState();
    _loadCloud();
  }

  @override
  void dispose() {
    _poll?.dispose();
    super.dispose();
  }

  Future<bool> _isConnected() async => (await _cloud.cloud()).any((a) => a.provider == CloudProvider.googleDrive && a.connected);

  Future<void> _loadCloud() async {
    try {
      final connected = await _isConnected();
      if (mounted) setState(() => _connected = connected);
    } catch (e) {
      if (mounted) setState(() => _error = formsErrorText(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  void _wait(String kind, String id, Future<bool> Function() check) {
    _since = DateTime.now();
    _poll?.dispose();
    setState(() {
      _waiting = true;
      _error = null;
    });
    Future<void> tick() async {
      if (!mounted) return _poll?.stop();
      var done = false;
      try {
        done = await check();
      } catch (e) {
        done = true;
        if (mounted) setState(() => _error = formsErrorText(e));
      }
      final late = DateTime.now().difference(_since!) > cloudConnectTimeout;
      if (!done && !late) return;
      _poll?.stop();
      if (mounted) setState(() => _waiting = false);
    }

    _poll = EventOrPoll(kind: kind, id: id, every: cloudConnectPoll, fallbackEvery: cloudConnectPollLive, poll: tick)..start();
  }

  Future<void> _connect() async {
    try {
      final url = await _cloud.connect(CloudProvider.googleDrive);
      if (url.isEmpty || !await openExternalUrl(url)) throw const ApiException(statusCode: 0, message: '', code: 'cloud_auth_failed');
      _wait('cloud', CloudProvider.googleDrive.wire, () async {
        final connected = await _isConnected();
        if (connected && mounted) setState(() => _connected = true);
        return connected;
      });
    } catch (e) {
      if (mounted) setState(() => _error = formsErrorText(e));
    }
  }

  Future<void> _pick() async {
    setState(() => _error = null);
    try {
      final (session, url) = await _forms.startPick();
      if (url.isEmpty || !await openExternalUrl(url)) throw const ApiException(statusCode: 0, message: '', code: 'cloud_auth_failed');
      _wait('forms_pick', session, () async {
        final s = await _forms.pickState(session);
        final status = '${s['status'] ?? ''}';
        if (status == 'pending') return false;
        if (status == 'picked') {
          final preview = await _forms.read('${s['form_id'] ?? ''}');
          if (mounted) {
            setState(() {
              _preview = preview;
              _report = null;
            });
          }
        }
        return true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = formsErrorText(e));
    }
  }

  Future<void> _import() async {
    final p = _preview;
    if (p == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    var id = _examId;
    if (id == null) {
      final made = await widget.createExam!(p);
      if (!mounted) return;
      id = _examId = made.examId;
      if (id == null) {
        return setState(() {
          _busy = false;
          _error = made.error;
        });
      }
    }
    final r = await widget.api.importRows(id, p.rows, sectionId: widget.sections.length > 1 ? (_section ?? widget.sections.first.$1) : null);
    if (!mounted) return;
    final report = r.ok ? ImportReport.fromJson(r.map) : null;
    // a new exam that came in whole: straight on to it (the editor opens behind the sheet)
    if (widget.examId == null && report != null && report.created > 0 && report.errors.isEmpty) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      if (r.ok) {
        _report = report;
      } else {
        _error = authoringError(r);
      }
    });
  }

  @override
  Widget build(BuildContext context) => AppSheetContent(tone: AppTone.info, icon: Icons.dynamic_form_outlined, title: t('استيراد من Google Forms', 'Import from Google Forms'), children: [
        GoogleFormsImportBody(
          loading: _loading,
          connected: _connected,
          waiting: _waiting,
          preview: _preview,
          sections: widget.sections,
          sectionId: _section,
          onSection: (v) => setState(() => _section = v),
          report: _report,
          busy: _busy,
          error: _error,
          onConnect: _connect,
          onPick: _pick,
          onImport: _import,
          onDone: () => Navigator.pop(context, (_report?.created ?? 0) > 0 || (widget.examId == null && _examId != null)),
          creating: widget.examId == null && _examId == null,
        ),
      ]);
}
