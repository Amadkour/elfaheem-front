// "Print the exam paper": pick a design (Auto · Classic · Modern · Minimal · your own Word template), PDF or Word, then
// the paper or the teacher's answer key. Institution, date, instructions and the small switches sit under Advanced
// with sensible defaults; the last design, institution and custom template are remembered on this device.
// Writers: exam_paper_pdf.dart / exam_paper_docx.dart over the model in exam_paper.dart.
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../../admin/admin_common.dart' show asInt, asMap, t;
import '../../org/org_ui.dart' show orgFileUrl;
import '../../teacher/data_lab/data_lab_saver_io.dart' if (dart.library.html) '../../teacher/data_lab/data_lab_saver_web.dart' as saver;
import 'exam_authoring.dart';
import 'exam_paper.dart';
import 'exam_paper_docx.dart';
import 'exam_paper_pdf.dart';
import 'exam_quick.dart' show paperFileOf;

const _kTemplate = 'exam_paper.template', _kInstitution = 'exam_paper.institution', _kCustom = 'exam_paper.custom', _kCustomName = 'exam_paper.custom_name';
const _maxCustomBytes = 1500000;

/// Loads the exam and opens the sheet. [course]: the course's name when the caller knows it.
Future<void> openExamPaper(BuildContext context, {required int examId, String course = ''}) async {
  final api = ExamAuthoringApi();
  final r = await api.exam(examId);
  if (!context.mounted) return;
  if (!r.ok) return appToast(authoringError(r), error: true);
  final view = ExamView.fromJson(r.map);
  if (paperFileOf(r.map) != null) {
    return appToast(t('هذا الامتحان ملف مرفوع — نزّله واطبعه من صفحة النتائج', 'This exam is an uploaded file — download and print it from the results'));
  }
  if (view.questionCount == 0) return appToast(t('أضف أسئلة أولاً', 'Add questions first'), error: true);
  final org = _orgOf(view.exam.orgId);
  final brand = '${org['color'] ?? ''}'.replaceAll('#', '');
  await showAppSheet<void>(
      context,
      (_) => ExamPaperSheet(
            view: view,
            course: course,
            orgName: AppConfig.lang == 'ar' ? '${org['name_ar'] ?? org['name_en'] ?? ''}' : '${org['name_en'] ?? org['name_ar'] ?? ''}',
            logoUrl: org['logo_url'] as String?,
            accentHex: RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(brand)
                ? brand.toUpperCase()
                : (context.colors.primary.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase(),
          ));
}

Map<String, dynamic> _orgOf(int? orgId) {
  if (orgId == null) return const {};
  for (final e in AppModeController.instance.entries) {
    final o = asMap(e['organization']);
    if (asInt(o['id'], -1) == orgId) return o;
  }
  return const {};
}

/// PDF keeps PNG / JPEG only: anything else is re-encoded as PNG (null when it cannot be read).
Uint8List? printableImage(Uint8List? b) {
  if (b == null || b.length < 4) return null;
  final png = b[0] == 0x89 && b[1] == 0x50, jpg = b[0] == 0xFF && b[1] == 0xD8;
  if (png || jpg) return b;
  final decoded = img.decodeImage(b);
  return decoded == null ? null : Uint8List.fromList(img.encodePng(decoded));
}

class ExamPaperSheet extends StatefulWidget {
  const ExamPaperSheet({super.key, required this.view, this.course = '', this.orgName = '', this.logoUrl, this.accentHex = '0F7B5F'});
  final ExamView view;
  final String course, orgName;
  final String? logoUrl;
  final String accentHex;

  @override
  State<ExamPaperSheet> createState() => _ExamPaperSheetState();
}

class _ExamPaperSheetState extends State<ExamPaperSheet> {
  PaperTemplate _tpl = PaperTemplate.auto;
  bool _word = false;
  bool _points = true, _seat = true;
  Uint8List? _custom;
  String? _customName;
  String? _busy;                 // 'paper' | 'key'
  late final _institution = TextEditingController(text: widget.orgName);
  late final _date = TextEditingController(text: widget.view.exam.startsAt == null ? '' : AppTime.date(widget.view.exam.startsAt!));
  late final _course = TextEditingController(text: widget.course);
  late final _instructions = TextEditingController(
      text: defaultPaperInstructions(
              rtl: AppConfig.lang == 'ar',
              questions: widget.view.questionCount,
              duration: widget.view.exam.durationMinutes == null ? '' : t('${widget.view.exam.durationMinutes} دقيقة', '${widget.view.exam.durationMinutes} minutes'))
          .join('\n'));

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    for (final c in [_institution, _date, _course, _instructions]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final name = p.getString(_kTemplate);
      final custom = p.getString(_kCustom);
      if (!mounted) return;
      setState(() {
        _tpl = PaperTemplate.values.firstWhere((x) => x.name == name, orElse: () => PaperTemplate.auto);
        if (widget.orgName.isEmpty) _institution.text = p.getString(_kInstitution) ?? '';
        if (custom != null) {
          _custom = base64Decode(custom);
          _customName = p.getString(_kCustomName);
        }
        if (_tpl == PaperTemplate.custom && _custom == null) _tpl = PaperTemplate.auto;
        if (_tpl == PaperTemplate.custom) _word = true;
      });
    } catch (_) {}
  }

  Future<void> _remember() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kTemplate, _tpl.name);
      if (_institution.text.trim().isNotEmpty) await p.setString(_kInstitution, _institution.text.trim());
      if (_custom != null && _custom!.length <= _maxCustomBytes) {
        await p.setString(_kCustom, base64Encode(_custom!));
        await p.setString(_kCustomName, _customName ?? 'template.docx');
      }
    } catch (_) {}
  }

  Future<void> _pickCustom() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['docx']);
    if (f == null) return;
    final b = await f.readAsBytes();
    if (!templateHasQuestions(b)) {
      return appToast(t('ضع {{questions}} في سطر مستقل داخل القالب، ثم ارفعه', 'Put {{questions}} on a line of its own in the template, then upload it'), error: true);
    }
    setState(() {
      _custom = b;
      _customName = f.name;
      _tpl = PaperTemplate.custom;
      _word = true;
    });
  }

  Future<Uint8List?> _logo() async {
    final u = widget.logoUrl;
    if (u == null || u.isEmpty) return null;
    try {
      final res = await http.get(Uri.parse(orgFileUrl(u))).timeout(const Duration(seconds: 20));
      return res.statusCode == 200 ? printableImage(res.bodyBytes) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _make({required bool answerKey}) async {
    if (_tpl == PaperTemplate.custom && _custom == null) return _pickCustom();
    setState(() => _busy = answerKey ? 'key' : 'paper');
    try {
      final rtl = AppConfig.lang == 'ar';
      final d = ExamPaperDoc.fromView(widget.view,
          institution: _institution.text,
          course: _course.text,
          dateText: _date.text.trim(),
          instructions: _instructions.text.split('\n'),
          rtl: rtl,
          logo: _tpl == PaperTemplate.custom ? null : await _logo(),
          accentHex: widget.accentHex,
          showPoints: _points,
          seatNumber: _seat,
          answerKey: answerKey);
      final tpl = resolvePaperTemplate(_tpl, highStakes: widget.view.exam.highStakes);
      final word = _word || tpl == PaperTemplate.custom;
      final Uint8List bytes;
      if (tpl == PaperTemplate.custom) {
        bytes = fillExamTemplate(_custom!, d);
      } else if (word) {
        bytes = examPaperDocx(d, tpl);
      } else {
        final s = PaperStyle.of(tpl);
        bytes = await examPaperPdf(d, tpl, regular: await rootBundle.load(s.regular), bold: await rootBundle.load(s.bold));
      }
      final base = '${d.title}${answerKey ? ' - ${t('نموذج الإجابة', 'answer key')}' : ''}'.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      final path = await saver.dlSaveBytes(bytes, '$base.${word ? 'docx' : 'pdf'}',
          word ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' : 'application/pdf');
      await _remember();
      appToast(path == null ? t('جاهز للطباعة', 'Ready to print') : '${t('حُفظ في', 'Saved to')} $path');
    } catch (e) {
      debugPrint('exam paper failed: $e');
      appToast(t('تعذّر إنشاء الملف', 'Could not create the file'), error: true);
    }
    if (mounted) setState(() => _busy = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final resolved = resolvePaperTemplate(_tpl, highStakes: widget.view.exam.highStakes);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSheetHeader(t('ورقة الامتحان للطباعة', 'Printable exam paper')),
      Text(t('اختر التصميم', 'Pick a design'), style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final p in PaperTemplate.values)
          PaperTemplateCard(
            template: p,
            selected: _tpl == p,
            accentHex: widget.accentHex,
            subtitle: p == PaperTemplate.custom && _customName != null ? _customName : null,
            onTap: () {
              if (p == PaperTemplate.custom && _custom == null) {
                _pickCustom();
                return;
              }
              setState(() {
                _tpl = p;
                if (p == PaperTemplate.custom) _word = true;
              });
            },
          ),
      ]),
      const SizedBox(height: 8),
      Text(
        _tpl == PaperTemplate.auto ? '${paperTemplateHint(_tpl)} → ${paperTemplateLabel(resolved)}' : paperTemplateHint(_tpl),
        style: appText(12.5, c: c.textMedium),
      ),
      if (_tpl == PaperTemplate.custom)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
            Text('{{institution}} {{course}} {{title}} {{date}} {{duration}} {{total}} {{instructions}} {{questions}}',
                style: appText(11.5, c: c.textLight)),
            TextButton(onPressed: _pickCustom, child: Text(t('ملف آخر', 'Another file'))),
          ]),
        ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        AppChoiceChip(label: 'PDF', icon: Icons.picture_as_pdf_rounded, selected: !_word && _tpl != PaperTemplate.custom,
            onTap: () => setState(() {
                  _word = false;
                  if (_tpl == PaperTemplate.custom) _tpl = PaperTemplate.auto;
                })),
        AppChoiceChip(label: 'Word', icon: Icons.description_rounded, selected: _word || _tpl == PaperTemplate.custom, onTap: () => setState(() => _word = true)),
      ]),
      const SizedBox(height: 6),
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(t('متقدم', 'Advanced'), style: appText(14, w: FontWeight.w700, c: c.textDark)),
          subtitle: Text(t('المؤسسة، التاريخ، التعليمات', 'Institution, date, instructions'), style: appText(12, c: c.textMedium)),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppField(controller: _institution, label: t('اسم المدرسة / الجامعة', 'School / university')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: AppField(controller: _course, label: t('المقرر', 'Course'))),
              const SizedBox(width: 8),
              Expanded(child: AppField(controller: _date, label: t('التاريخ', 'Date'))),
            ]),
            const SizedBox(height: 8),
            AppField(controller: _instructions, label: t('التعليمات (سطر لكل تعليمة)', 'Instructions (one per line)'), maxLines: 5),
            AppSwitchTile(title: t('إظهار درجة كل سؤال', 'Show each question\'s marks'), value: _points, dense: true, onChanged: (v) => setState(() => _points = v)),
            AppSwitchTile(title: t('خانة رقم الجلوس', 'Seat number box'), value: _seat, dense: true, onChanged: (v) => setState(() => _seat = v)),
          ],
        ),
      ),
      const SizedBox(height: 6),
      AppPrimaryButton(
          label: t('ورقة الامتحان', 'Exam paper'),
          icon: Icons.print_rounded,
          busy: _busy == 'paper',
          onPressed: _busy != null ? null : () => _make(answerKey: false)),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _busy != null ? null : () => _make(answerKey: true),
        icon: _busy == 'key' ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.key_rounded, size: 18),
        label: Text(t('نموذج الإجابة (نسخة المعلم)', 'Answer key (teacher\'s copy)')),
      ),
    ]);
  }
}

/// A design's card with a small drawn preview (plain values; under the layout harness).
class PaperTemplateCard extends StatelessWidget {
  const PaperTemplateCard({super.key, required this.template, required this.selected, required this.onTap, this.accentHex = '0F7B5F', this.subtitle});
  final PaperTemplate template;
  final bool selected;
  final VoidCallback onTap;
  final String accentHex;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: 132,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? c.primary : c.divider, width: selected ? 2 : 1),
            color: selected ? c.primary.withValues(alpha: .06) : null,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AspectRatio(aspectRatio: 0.78, child: PaperPreview(template: template, accent: Color(0xFF000000 | int.parse(accentHex, radix: 16)))),
            const SizedBox(height: 6),
            Row(children: [
              if (selected) Icon(Icons.check_circle_rounded, size: 15, color: c.primary),
              if (selected) const SizedBox(width: 4),
              Expanded(
                  child: Text(paperTemplateLabel(template),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, w: FontWeight.w700, c: c.textDark))),
            ]),
            if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(10.5, c: c.textLight)),
          ]),
        ),
      ),
    );
  }
}

/// A miniature page in the template's look.
class PaperPreview extends StatelessWidget {
  const PaperPreview({super.key, required this.template, required this.accent});
  final PaperTemplate template;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ink = template == PaperTemplate.minimal ? const Color(0xFF1F2933) : accent;
    Widget bar(double w, {double h = 3, Color? color}) => FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: w,
        child: Container(height: h, margin: const EdgeInsets.only(top: 4), decoration: BoxDecoration(color: color ?? const Color(0xFFD7DDE3), borderRadius: BorderRadius.circular(2))));
    final lines = [bar(.9), bar(.7), bar(.82), bar(.6)];
    final Widget inner = switch (template) {
      PaperTemplate.classic => Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(border: Border.all(color: ink, width: 1.4)),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(border: Border.all(color: ink, width: .5)),
            child: Column(children: [
              Container(width: 16, height: 16, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ink, width: 1.2))),
              const SizedBox(height: 3),
              bar(.5, color: ink),
              Container(height: 1.2, margin: const EdgeInsets.only(top: 4), color: ink),
              ...lines,
            ]),
          ),
        ),
      PaperTemplate.modern => Padding(
          padding: const EdgeInsets.all(5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(height: 20, decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(5))),
            Row(children: [
              for (var i = 0; i < 3; i++)
                Expanded(child: Container(height: 6, margin: const EdgeInsets.fromLTRB(1, 4, 1, 0), decoration: BoxDecoration(color: ink.withValues(alpha: .15), borderRadius: BorderRadius.circular(3)))),
            ]),
            Container(height: 14, margin: const EdgeInsets.only(top: 4), decoration: BoxDecoration(color: ink.withValues(alpha: .08), borderRadius: BorderRadius.circular(4))),
            ...lines,
          ]),
        ),
      PaperTemplate.minimal => Padding(
          padding: const EdgeInsets.all(6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [bar(.55, color: ink), Container(height: 1, margin: const EdgeInsets.only(top: 4), color: ink), ...lines, ...lines]),
        ),
      PaperTemplate.custom => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.upload_file_rounded, color: accent, size: 26),
          Text('{{ }}', style: appText(11, w: FontWeight.w700, c: accent)),
        ])),
      PaperTemplate.auto => Stack(children: [
          Positioned.fill(child: PaperPreview(template: PaperTemplate.classic, accent: accent)),
          PositionedDirectional(
            top: 2, end: 2,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              child: const Icon(Icons.auto_awesome_rounded, size: 12, color: Colors.white),
            ),
          ),
        ]),
    };
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))]),
      clipBehavior: Clip.antiAlias,
      child: template == PaperTemplate.auto ? inner : Padding(padding: const EdgeInsets.all(3), child: inner),
    );
  }
}
