// lib/features/games/admin/v4/import_wizard.dart — Games v4 T66: the question import wizard (CONTRACT §10).
// Four plain steps on one page: 1 pick the subject, 2 download the template (CSV / XLSX / JSON, one type or all),
// 3 upload the filled file (the server checks it without saving: a dry run), 4 read the row errors and add the good
// rows. Rows of a subject that requires review land as "pending review", the others as drafts.
// `ImportWizardBody` is the plain-values body (the layout test); `GamesImportPage` wires it to the server.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/admin/admin_money_p8.dart' show p8SaveBytes;
import 'package:flutter_education_app/features/admin/admin_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/items_api.dart' show itemFieldName, itemWhyText;
import 'package:flutter_education_app/features/games/admin/v4/items_review_api.dart';

const _mimes = {'csv': 'text/csv', 'json': 'application/json', 'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'};

class GamesImportPage extends StatefulWidget {
  const GamesImportPage({super.key, this.api});
  final ItemsReviewApi? api;

  @override
  State<GamesImportPage> createState() => _GamesImportPageState();
}

class _GamesImportPageState extends State<GamesImportPage> {
  late final ItemsReviewApi _api = widget.api ?? ItemsReviewApi();
  List<GameSubjectRow>? _subjects;
  String? _loadError;
  int? _subjectId;
  String? _type; // null = every type
  String _format = 'xlsx';
  bool _downloading = false;
  String? _fileName;
  Uint8List? _bytes;
  bool _checking = false;
  bool _committing = false;
  ImportReport? _report; // the dry run
  ImportReport? _done; // the commit

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final s = await _api.subjects();
      if (mounted) setState(() => _subjects = s);
    } catch (e) {
      if (mounted) setState(() => _loadError = reviewErrorText(e));
    }
  }

  Future<void> _download() async {
    setState(() => _downloading = true);
    try {
      final bytes = await _api.template(type: _type, format: _format);
      await p8SaveBytes(bytes, 'questions-${_type ?? 'all'}-template.$_format', mime: _mimes[_format]!);
      showAppNotice(t('تم حفظ القالب', 'Template saved'));
    } catch (e) {
      showAppNotice(reviewErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _pick() async {
    try {
      final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['csv', 'xlsx', 'json']);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      setState(() {
        _fileName = f.name;
        _bytes = bytes;
        _report = null;
        _done = null;
      });
      await _check();
    } catch (_) {
      showAppNotice(t('تعذّر اختيار الملف', 'Could not pick the file'), error: true);
    }
  }

  Future<void> _check() async {
    if (_subjectId == null || _bytes == null) return;
    setState(() => _checking = true);
    try {
      final r = await _api.import(_subjectId!, _bytes!, _fileName ?? 'import.csv', dryRun: true);
      if (mounted) setState(() => _report = r);
    } catch (e) {
      showAppNotice(reviewErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _commit() async {
    final r = _report;
    if (r == null || r.ok == 0) return;
    final ok = await appConfirm(context,
        message: r.errors.isEmpty
            ? t('إضافة ${r.ok} سؤالًا؟', 'Add ${r.ok} questions?')
            : t('إضافة ${r.ok} سؤالًا صحيحًا وتجاهل ${r.errors.length} خطأ؟', 'Add ${r.ok} valid questions and skip ${r.errors.length} with errors?'),
        confirmLabel: t('إضافة', 'Add'));
    if (!ok) return;
    setState(() => _committing = true);
    try {
      final d = await _api.import(_subjectId!, _bytes!, _fileName ?? 'import.csv', dryRun: false);
      if (mounted) setState(() => _done = d);
    } catch (e) {
      showAppNotice(reviewErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _committing = false);
    }
  }

  void _again() => setState(() {
        _fileName = null;
        _bytes = null;
        _report = null;
        _done = null;
      });

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      helpPageId: 'admin.games.import',
      width: AppWidth.reading,
      title: t('استيراد أسئلة', 'Import questions'),
      subtitle: t('أضف عشرات الأسئلة دفعة واحدة من ملف.', 'Add many questions at once from a file.'),
      icon: Icons.upload_file_rounded,
      onRefresh: _load,
      body: ListView(
        padding: AdminPage.bodyPadding(context),
        children: [
          ImportWizardBody(
            subjects: _subjects,
            loadError: _loadError,
            subjectId: _subjectId,
            type: _type,
            format: _format,
            downloading: _downloading,
            fileName: _fileName,
            checking: _checking,
            committing: _committing,
            report: _report,
            done: _done,
            onSubject: (v) => setState(() {
              _subjectId = v;
              _report = null;
              _done = null;
              if (_bytes != null) _check();
            }),
            onType: (v) => setState(() => _type = v),
            onFormat: (v) => setState(() => _format = v),
            onDownload: _download,
            onPick: _pick,
            onCommit: _commit,
            onAgain: _again,
            onRetry: _load,
          ),
        ],
      ),
    );
  }
}

/// The wizard over plain values. [subjects] null = loading.
class ImportWizardBody extends StatelessWidget {
  const ImportWizardBody({
    super.key,
    required this.subjects,
    required this.subjectId,
    required this.type,
    required this.format,
    required this.onSubject,
    required this.onType,
    required this.onFormat,
    required this.onDownload,
    required this.onPick,
    required this.onCommit,
    required this.onAgain,
    this.onRetry,
    this.loadError,
    this.downloading = false,
    this.fileName,
    this.checking = false,
    this.committing = false,
    this.report,
    this.done,
  });

  final List<GameSubjectRow>? subjects;
  final String? loadError;
  final int? subjectId;
  final String? type;
  final String format;
  final bool downloading;
  final String? fileName;
  final bool checking;
  final bool committing;
  final ImportReport? report;
  final ImportReport? done;
  final ValueChanged<int?> onSubject;
  final ValueChanged<String?> onType;
  final ValueChanged<String> onFormat;
  final VoidCallback onDownload;
  final VoidCallback onPick;
  final VoidCallback onCommit;
  final VoidCallback onAgain;
  final VoidCallback? onRetry;

  /// How many rows show in the error table before "and N more".
  static const int maxErrorRows = 50;

  @override
  Widget build(BuildContext context) {
    final subs = subjects;
    if (loadError != null && subs == null) {
      return AppEmpty(icon: Icons.cloud_off_rounded, title: loadError!, actionLabel: t('إعادة المحاولة', 'Try again'), onAction: onRetry);
    }
    if (subs == null) return const AppListSkeleton();
    GameSubjectRow? subject;
    for (final s in subs) {
      if (s.id == subjectId) subject = s;
    }
    final gap = const SizedBox(height: AppSpace.md);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Step(
        n: 1,
        title: t('اختر المادة', 'Pick the subject'),
        child: AppPicker<int>(
          label: t('المادة', 'Subject'),
          value: subjectId,
          options: {for (final s in subs) s.id: gameSubjectName(s)},
          onChanged: onSubject,
          hint: t('اختر المادة', 'Choose a subject'),
        ),
        note: subject == null
            ? null
            : subject.requiresReview
                ? t('أسئلة هذه المادة تُحفظ «بانتظار المراجعة» حتى يعتمدها مراجع.',
                    'Questions of this subject are saved as "waiting for review" until a reviewer approves them.')
                : t('أسئلة هذه المادة تُحفظ كمسودات.', 'Questions of this subject are saved as drafts.'),
      ),
      gap,
      _Step(
        n: 2,
        title: t('حمّل القالب', 'Download the template'),
        note: t('املأ القالب بأسئلتك ثم ارفعه في الخطوة التالية. فيه صفّان كمثال.',
            'Fill the template with your questions, then upload it in the next step. It has two example rows.'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppPicker<String>(
            label: t('نوع السؤال', 'Question type'),
            value: type ?? '',
            options: {'': t('كل الأنواع', 'All types'), for (final k in kGameItemTypes) k: gameItemTypeName(k)},
            onChanged: (v) => onType(v == null || v.isEmpty ? null : v),
          ),
          const SizedBox(height: AppSpace.sm),
          AppTabs(
            items: const [AppTabItem('XLSX'), AppTabItem('CSV'), AppTabItem('JSON')],
            index: const ['xlsx', 'csv', 'json'].indexOf(format),
            onChanged: (i) => onFormat(const ['xlsx', 'csv', 'json'][i]),
            expand: true,
          ),
          const SizedBox(height: AppSpace.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton(
                label: t('تنزيل القالب', 'Download template'),
                icon: Icons.download_rounded,
                variant: AppButtonVariant.tonal,
                busy: downloading,
                onPressed: downloading ? null : onDownload),
          ),
        ]),
      ),
      gap,
      _Step(
        n: 3,
        title: t('ارفع الملف', 'Upload the file'),
        note: subjectId == null ? t('اختر المادة أولًا.', 'Pick the subject first.') : t('الحد الأقصى 5 ميغابايت و2000 صف. لن يُحفظ شيء قبل موافقتك.', 'Up to 5 MB and 2000 rows. Nothing is saved before you agree.'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppButton(
              label: fileName == null ? t('اختيار ملف', 'Choose a file') : t('تغيير الملف', 'Change the file'),
              icon: Icons.attach_file_rounded,
              variant: AppButtonVariant.secondary,
              busy: checking,
              onPressed: subjectId == null || checking ? null : onPick),
          if (fileName != null) ...[
            const SizedBox(height: AppSpace.xs),
            Text(fileName!, style: AppType.meta(context), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ]),
      ),
      if (report != null) ...[
        gap,
        done != null
            ? _DoneCard(done: done!, onAgain: onAgain)
            : _ResultStep(report: report!, committing: committing, onCommit: onCommit, pendingSubject: subject?.requiresReview ?? false),
      ],
    ]);
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.title, required this.child, this.note});
  final int n;
  final String title;
  final String? note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: AppTouch.min - AppSpace.sm,
            height: AppTouch.min - AppSpace.sm,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.primaryTint, shape: BoxShape.circle),
            child: Text('$n', style: AppType.bodyStrong(context).copyWith(color: c.primary)),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text(title, style: AppType.section(context))),
        ]),
        if (note != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text(note!, style: AppType.meta(context)),
        ],
        const SizedBox(height: AppSpace.sm),
        child,
      ]),
    );
  }
}

class _ResultStep extends StatelessWidget {
  const _ResultStep({required this.report, required this.committing, required this.onCommit, required this.pendingSubject});
  final ImportReport report;
  final bool committing;
  final VoidCallback onCommit;
  final bool pendingSubject;

  @override
  Widget build(BuildContext context) {
    final errs = report.errors;
    final shown = errs.take(ImportWizardBody.maxErrorRows).toList();
    return _Step(
      n: 4,
      title: t('راجع النتيجة', 'Check the result'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppStatusBadge(label: t('${report.rows} صفًا', '${report.rows} rows')),
          AppStatusBadge(label: t('${report.ok} صحيح', '${report.ok} valid'), tone: AppTone.success, icon: Icons.check_rounded),
          if (errs.isNotEmpty) AppStatusBadge(label: t('${errs.length} فيها خطأ', '${errs.length} with errors'), tone: AppTone.danger),
        ]),
        if (report.ok > 0 && pendingSubject) ...[
          const SizedBox(height: AppSpace.xs),
          Text(
              t('ستُحفظ ${report.pending > 0 ? report.pending : report.ok} من الأسئلة «بانتظار المراجعة».',
                  '${report.pending > 0 ? report.pending : report.ok} questions will be saved as "waiting for review".'),
              style: AppType.body(context)),
        ],
        if (errs.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Text(t('أخطاء الصفوف', 'Row errors'), style: AppType.bodyStrong(context)),
          const SizedBox(height: AppSpace.xxs),
          for (final e in shown) _ErrorRow(e: e),
          if (errs.length > shown.length)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text(t('و${errs.length - shown.length} أخرى', 'and ${errs.length - shown.length} more'), style: AppType.meta(context)),
            ),
          const SizedBox(height: AppSpace.xs),
          Text(t('صحّح الملف وارفعه مرة أخرى، أو أضف الصفوف الصحيحة فقط.', 'Fix the file and upload it again, or add only the valid rows.'),
              style: AppType.meta(context)),
        ],
        const SizedBox(height: AppSpace.md),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton(
              label: t('إضافة ${report.ok} سؤالًا', 'Add ${report.ok} questions'),
              icon: Icons.playlist_add_check_rounded,
              busy: committing,
              onPressed: report.ok == 0 || committing ? null : onCommit),
        ),
      ]),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.e});
  final ImportRowError e;

  @override
  Widget build(BuildContext context) {
    final danger = appToneColor(context, AppTone.danger);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${t('صف', 'Row')} ${e.row}', style: AppType.row(context).copyWith(color: danger), softWrap: false),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text(e.field.isEmpty ? itemWhyText(e.why) : '${itemFieldName(e.field)}: ${itemWhyText(e.why)}', style: AppType.body(context)),
        ),
      ]),
    );
  }
}

class _DoneCard extends StatelessWidget {
  const _DoneCard({required this.done, required this.onAgain});
  final ImportReport done;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      highlight: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.check_circle_rounded, color: appToneColor(context, AppTone.success)),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(t('تمت إضافة ${done.created} سؤالًا', '${done.created} questions added'), style: AppType.section(context))),
        ]),
        if (done.pending > 0) ...[
          const SizedBox(height: AppSpace.xs),
          Text(t('${done.pending} منها بانتظار المراجعة قبل أن تظهر للطلاب.', '${done.pending} of them wait for review before students see them.'),
              style: AppType.body(context)),
        ],
        const SizedBox(height: AppSpace.md),
        AppButton(label: t('استيراد ملف آخر', 'Import another file'), variant: AppButtonVariant.tonal, onPressed: onAgain),
      ]),
    );
  }
}
