// "Print bubble sheets" (brief 3, D-156): what the engine will print (`GET …/omr/sheets`), then blank sheets per form ×
// copies or one named sheet per student (the forms cycle), as a PDF (`POST …/omr/sheets`) saved or shared with the
// same helpers the table exports use (data_lab_saver: a browser download on the web, Downloads on desktop, the share
// sheet on phones). Only the built-in sheets are printable: a learned template is the school's own printed sheet.
// The named sheets are chosen by name from the exam's audience (`OmrAudiencePicker`, `GET …/omr/students`), never
// typed as raw ids.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import '../../../../admin/admin_common.dart' show t;
import '../../../../teacher/data_lab/data_lab_saver_io.dart' if (dart.library.html) '../../../../teacher/data_lab/data_lab_saver_web.dart' as saver;
import '../review/omr_review.dart' show OmrReviewApi;
import 'omr_audience_picker.dart';
import 'omr_scan.dart';
import '../omr_counts.dart';

Future<void> showOmrSheetsSheet(BuildContext context, {required int examId, OmrScanApi? api}) =>
    showAppSheet<void>(context, (_) => OmrSheetsSheet(examId: examId, api: api));

String omrIdKindText(String kind) => switch (kind) {
      'shaded' => t('رقم الطالب بالتظليل', 'shaded student ID'),
      'handwritten' => t('رقم الطالب بخط اليد', 'handwritten student ID'),
      'printed' => t('رقم مطبوع', 'printed ID'),
      'qr' => t('رمز QR', 'QR code'),
      _ => t('بلا رقم طالب', 'no student ID'),
    };

/// The options, plain values (the layout harness pumps it).
class OmrSheetsOptionsView extends StatelessWidget {
  const OmrSheetsOptionsView({
    super.key,
    required this.info,
    required this.named,
    required this.onNamed,
    required this.forms,
    required this.onForm,
    required this.copiesController,
    required this.students,
    required this.onDownload,
    required this.onShare,
    this.busy = false,
    this.error,
  });

  final OmrSheetsInfo info;

  /// One sheet per student (else blank sheets × copies).
  final bool named;
  final ValueChanged<bool> onNamed;
  final Set<String> forms;
  final ValueChanged<String> onForm;
  final TextEditingController copiesController;

  /// The students to name (an `OmrAudiencePicker`, or its body under the harness), shown for named sheets.
  final Widget students;
  final VoidCallback onDownload;
  final VoidCallback onShare;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final summary = t('${omrQuestionsText(info.questions)} على ورقة من ${omrQuestionsText(info.sheetQuestions, after: true)} · ${omrIdKindText(info.idKind)}',
        '${info.questions} questions on a ${info.sheetQuestions}-question sheet · ${omrIdKindText(info.idKind)}');
    if (!info.printable) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppBanner(icon: Icons.info_outline_rounded, text: omrCodeText('template_not_printable')),
        const SizedBox(height: AppSpace.sm),
        Text(summary, style: appText(13.5, c: c.textMedium)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(summary, style: appText(13.5, c: c.textMedium, h: 1.4)),
      const SizedBox(height: AppSpace.md),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppChoiceChip(label: t('أوراق فارغة', 'Blank sheets'), icon: Icons.copy_all_rounded, selected: !named, onTap: () => onNamed(false)),
        AppChoiceChip(label: t('ورقة باسم كل طالب', 'A named sheet per student'), icon: Icons.badge_outlined, selected: named, onTap: () => onNamed(true)),
      ]),
      if (info.forms.isNotEmpty) ...[
        const SizedBox(height: AppSpace.md),
        Text(t('النماذج', 'Models'), style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final f in info.forms) AppChoiceChip(label: t('نموذج $f', 'Model $f'), selected: forms.contains(f), onTap: () => onForm(f)),
        ]),
        if (named) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(t('تتناوب النماذج المختارة على الطلاب بالترتيب', 'The chosen models alternate across the students in order'), style: appText(12.5, c: c.textMedium)),
        ],
      ],
      const SizedBox(height: AppSpace.md),
      if (!named)
        AppField(controller: copiesController, label: t('عدد النسخ لكل نموذج', 'Copies of each model'), keyboard: TextInputType.number, ltr: true)
      else ...[
        students,
        const SizedBox(height: AppSpace.xs),
        Text(t('حتى ${OmrLimits.maxStudentSheets} ورقة في المرة', 'Up to ${OmrLimits.maxStudentSheets} sheets at a time'), style: appText(12.5, c: c.textMedium)),
      ],
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, text: error!, color: c.danger),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(label: t('تنزيل PDF', 'Download PDF'), icon: Icons.download_rounded, onPressed: busy ? null : onDownload, busy: busy),
      const SizedBox(height: AppSpace.xs),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
        onPressed: busy ? null : onShare,
        icon: const Icon(Icons.share_rounded, size: 18),
        label: Text(t('مشاركة PDF', 'Share PDF')),
      ),
    ]);
  }
}

class OmrSheetsSheet extends StatefulWidget {
  const OmrSheetsSheet({super.key, required this.examId, this.api, this.audienceApi});
  final int examId;
  final OmrScanApi? api;
  final OmrReviewApi? audienceApi;

  @override
  State<OmrSheetsSheet> createState() => _OmrSheetsSheetState();
}

class _OmrSheetsSheetState extends State<OmrSheetsSheet> {
  late final OmrScanApi _api = widget.api ?? OmrScanApi();
  final _copies = TextEditingController(text: '1');
  Set<int> _selected = {};
  final Set<String> _forms = {};
  OmrSheetsInfo? _info;
  String? _loadError;
  String? _error;
  bool _named = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _copies.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await _api.sheetsInfo(widget.examId);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _info = OmrSheetsInfo.fromJson(r.map);
        _forms
          ..clear()
          ..addAll(_info!.forms);
      } else {
        _loadError = omrErrorText(r);
      }
    });
  }

  Future<Uint8List?> _make() async {
    final ids = _named ? (_selected.toList()..sort()) : <int>[];
    final copies = int.tryParse(_copies.text.trim()) ?? 0;
    if (_named && ids.isEmpty) {
      setState(() => _error = t('اختر طالبًا واحدًا على الأقل', 'Choose at least one student'));
      return null;
    }
    if (_named && ids.length > OmrLimits.maxStudentSheets) {
      setState(() => _error = omrCodeText('too_many_sheets'));
      return null;
    }
    if (!_named && (copies < 1 || copies > OmrLimits.maxCopies)) {
      setState(() => _error = t('عدد النسخ من 1 إلى ${OmrLimits.maxCopies}', 'Copies: 1 to ${OmrLimits.maxCopies}'));
      return null;
    }
    final info = _info!;
    final forms = [for (final f in info.forms) if (_forms.contains(f)) f];
    if (info.forms.isNotEmpty && forms.isEmpty) {
      setState(() => _error = t('اختر نموذجًا واحدًا على الأقل', 'Choose at least one model'));
      return null;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final (bytes, fail) = await _api.sheetsPdf(widget.examId, omrSheetsBody(forms: forms, copies: copies, studentIds: ids));
    if (!mounted) return null;
    setState(() {
      _busy = false;
      if (fail != null) _error = omrErrorText(fail);
    });
    return bytes;
  }

  String get _name => 'bubble-sheets-${widget.examId}.pdf';

  Future<void> _download() async {
    final bytes = await _make();
    if (bytes == null) return;
    try {
      await saver.dlSaveBytes(bytes, _name, 'application/pdf');
      showAppNotice(t('حُفظ الملف', 'File saved'));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      showAppNotice(t('تعذّر حفظ الملف', 'Could not save the file'), error: true);
    }
  }

  Future<void> _share() async {
    final bytes = await _make();
    if (bytes == null) return;
    try {
      await saver.dlShareBytes(bytes, _name, 'application/pdf');
    } catch (_) {
      showAppNotice(t('تعذّرت المشاركة', 'Could not share'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return AppSheetContent(title: t('طباعة أوراق التظليل', 'Print bubble sheets'), children: [
      if (info == null && _loadError == null) const AppListSkeleton(items: 2, padding: EdgeInsets.zero),
      if (_loadError != null) AppBanner(icon: Icons.error_outline_rounded, text: _loadError!, color: context.colors.danger),
      if (info != null)
        OmrSheetsOptionsView(
          info: info,
          named: _named,
          onNamed: (v) => setState(() {
            _named = v;
            _error = null;
          }),
          forms: _forms,
          onForm: (f) => setState(() => _forms.contains(f) ? _forms.remove(f) : _forms.add(f)),
          copiesController: _copies,
          students: OmrAudiencePicker(
            examId: widget.examId,
            api: widget.audienceApi,
            selected: _selected,
            onChanged: (s) => setState(() {
              _selected = s;
              _error = null;
            }),
          ),
          onDownload: _download,
          onShare: _share,
          busy: _busy,
          error: _error,
        ),
    ]);
  }
}
