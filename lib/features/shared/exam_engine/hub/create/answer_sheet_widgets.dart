// The paper exam's answer sheets, drawn (D-687, folded into the D-697 flow): print or already have the bubble sheets,
// academic ID or system number, the student list of an exam with no course, and Deliver's NB2 print card. One copy or
// one per student is CreateCopiesBody (offline_steps.dart).
//
// Plain-value widgets (the layout harness pumps them): CreateBubbleSourceBody · CreateIdSourceRow ·
// PeopleFileBody · AnswerSheetPrintCard. PeopleFileStep owns the upload.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../../../admin/admin_common.dart' show t;
import 'answer_sheet_plan.dart';

const _gap = SizedBox(height: AppSpace.xs);

/// Print the bubble sheets here, or the teacher already has them: above the sheet types.
class CreateBubbleSourceBody extends StatelessWidget {
  const CreateBubbleSourceBody({super.key, required this.value, required this.onPick});
  final BubbleSource value;
  final ValueChanged<BubbleSource> onPick;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final v in BubbleSource.values)
            AppChoiceChip(
              key: ValueKey('create.bubble.${bubbleSourceKey(v)}'),
              label: bubbleSourceLabel(v),
              icon: v == BubbleSource.print ? Icons.print_outlined : Icons.inventory_2_outlined,
              selected: value == v,
              onTap: () => onPick(v),
            ),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Text(bubbleSourceHint(value), style: AppType.meta(context)),
      ]);
}

/// What a personal sheet carries, above the identifier plan.
class CreateIdSourceRow extends StatelessWidget {
  const CreateIdSourceRow({super.key, required this.value, required this.onPick});
  final IdSource value;
  final ValueChanged<IdSource> onPick;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('الرقم على ورقة الإجابة', 'The number on the answer sheet'), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600)),
        _gap,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final v in IdSource.values)
            AppChoiceChip(key: ValueKey('create.id.${idSourceKey(v)}'), label: idSourceLabel(v), selected: value == v, onTap: () => onPick(v)),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Text(idSourceHint(value), style: AppType.meta(context)),
      ]);
}

/// The student list of an exam with no course: the columns it needs, the upload, what came in.
class PeopleFileBody extends StatelessWidget {
  const PeopleFileBody({super.key, this.upload, this.busy = false, this.error, required this.onPick});
  final PeopleUpload? upload;
  final bool busy;
  final String? error;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final u = upload;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppBanner(
        icon: Icons.table_rows_outlined,
        text: t('ملف CSV أو Excel: عمود للاسم وعمود للرقم (أو الأول الاسم والثاني الرقم). حتى 2000 طالب.',
            'A CSV or Excel file: a name column and a number column (or name first, number second). Up to 2000 students.'),
      ),
      const SizedBox(height: AppSpace.sm),
      if (u != null && u.total > 0)
        AppCard(
          key: const ValueKey('people.done'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.check_circle_rounded, color: c.success, size: AppIconSize.md),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: Text(t('في القائمة ${studentsCountText(u.total)}', '${studentsCountText(u.total)} on the list'), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600))),
            ]),
            if (u.added > 0 || u.updated > 0)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs),
                child: Text(t('أُضيف ${u.added} · حُدّث ${u.updated}', '${u.added} added · ${u.updated} updated'), style: AppType.meta(context)),
              ),
            if (u.names.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs),
                child: Text(u.names.join(t('، ', ', ')), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              ),
            if (u.skipped.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs),
                child: Text(
                    t('تُرك ${u.skipped.length}: ', '${u.skipped.length} skipped: ') +
                        u.skipped.take(5).map((s) => '${t('صف', 'row')} ${s.row} (${peopleSkipText(s.code)})').join(t('، ', ', ')),
                    style: AppType.meta(context).copyWith(color: appInkOn(context, c.warning, c.cardBg))),
              ),
          ]),
        ),
      if (error != null) ...[
        const SizedBox(height: AppSpace.xs),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.sm),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: AppButton.tonal(
          key: const ValueKey('people.pick'),
          label: u != null && u.total > 0 ? t('رفع قائمة أخرى', 'Upload another list') : t('رفع قائمة الطلاب', 'Upload the student list'),
          icon: Icons.upload_file_rounded,
          onPressed: busy ? null : onPick,
        ),
      ),
    ]);
  }
}

/// The upload itself: reads what the exam already holds, sends a picked file, reports the count.
class PeopleFileStep extends StatefulWidget {
  const PeopleFileStep({super.key, required this.examId, required this.onCount, this.api});
  final int examId;
  final ValueChanged<int> onCount;
  final AnswerSheetApi? api;

  @override
  State<PeopleFileStep> createState() => _PeopleFileStepState();
}

class _PeopleFileStepState extends State<PeopleFileStep> {
  late final AnswerSheetApi _api = widget.api ?? AnswerSheetApi();
  PeopleUpload? _upload;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _count() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onCount(_upload?.total ?? 0);
      });

  Future<void> _load() async {
    final r = await _api.people(widget.examId);
    if (!mounted || !r.ok) return;
    setState(() => _upload = PeopleUpload.fromJson(r.map));
    _count();
  }

  Future<void> _pick() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: kPeopleFileExtensions);
    if (f == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final bytes = await f.readAsBytes();
    if (!mounted) return;
    if (bytes.length > kPeopleFileMaxBytes) {
      setState(() {
        _busy = false;
        _error = t('الملف أكبر من 2 ميجابايت', 'The file is larger than 2 MB');
      });
      return;
    }
    final r = await _api.uploadPeople(widget.examId, f.name, bytes);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _upload = PeopleUpload.fromJson(r.map);
      } else {
        _error = answerSheetErrorText(r);
      }
    });
    _count();
  }

  @override
  Widget build(BuildContext context) => PeopleFileBody(upload: _upload, busy: _busy, error: _error, onPick: _pick);
}

/// Deliver's card for the written-answer sheets: what is planned, the copies for generic sheets, Download.
class AnswerSheetPrintCard extends StatelessWidget {
  const AnswerSheetPrintCard({super.key, required this.plan, required this.blank, required this.onBlank, required this.onDownload, this.busy = false, this.error});
  final SheetPlan plan;
  final int blank;
  final ValueChanged<int> onBlank;
  final VoidCallback? onDownload;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final what = plan.personal
        ? (plan.fromFile
            ? t('ورقة لكل طالب في القائمة المرفوعة', 'One for each student on the uploaded list')
            : t('ورقة لكل طالب في المقرر · ${idSourceLabel(plan.idSource)}', 'One for each student of the course · ${idSourceLabel(plan.idSource)}'))
        : t('أوراق عامة: يكتب الطالب اسمه ورقمه', 'Generic: students write their name and number');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('يكتب الطلاب إجاباتهم الكتابية في مربعات وأسطر ثابتة، فاطبعها مع ورقة الأسئلة.', 'Students write their written answers in fixed boxes and lines, so print these with the question paper.'),
          style: AppType.meta(context).copyWith(height: 1.4)),
      const SizedBox(height: AppSpace.xs),
      Text(what, style: AppType.label(context).copyWith(color: c.textDark)),
      if (!plan.personal) ...[
        const SizedBox(height: AppSpace.xs),
        AppNumberField(
          key: const ValueKey('nb2.blank'),
          initialValue: blank,
          label: t('عدد النسخ', 'Copies'),
          min: 1,
          max: kMaxGenericSheets,
          onChanged: (v) => onBlank((v ?? blank).toInt()),
        ),
      ],
      if (error != null) ...[
        const SizedBox(height: AppSpace.xs),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.xs),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: AppButton.tonal(
          key: const ValueKey('nb2.download'),
          label: t('تنزيل أوراق الإجابة', 'Download the answer sheets'),
          icon: Icons.download_rounded,
          onPressed: busy ? null : onDownload,
        ),
      ),
    ]);
  }
}
