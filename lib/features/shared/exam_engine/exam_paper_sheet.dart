// "Print the exam paper": pick a design (Auto · Classic · Modern · Minimal · your own Word template), PDF or Word, then
// the paper or the teacher's answer key. Institution, date, instructions and the small switches sit under Advanced
// with sensible defaults; the last design, institution and custom template are remembered on this device.
// Writers: exam_paper_pdf.dart / exam_paper_docx.dart over the model in exam_paper.dart.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
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
import 'exam_media.dart' show bankQuestionBytes;
import 'exam_paper.dart';
import 'exam_paper_docx.dart';
import 'exam_paper_pdf.dart';
import 'exam_quick.dart' show paperFileOf;
import 'exam_versions.dart';
import 'exam_versions_sheet.dart';
import 'paper/exam_setup.dart' show ExamSetup, ExamSetupApi, formatBody, setupErrorText;
import 'paper/omr_counts.dart';
import 'paper/scan/omr_audience_picker.dart';

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
  const ExamPaperSheet(
      {super.key, required this.view, this.course = '', this.orgName = '', this.logoUrl, this.accentHex = '0F7B5F', this.versionsApi, this.setupApi});
  final ExamView view;
  final ExamVersionsApi? versionsApi;
  final ExamSetupApi? setupApi;
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
  String? _busy;                 // 'paper' | 'key' | 'copies'

  // versions, answer area, per-student copies
  late final ExamVersionsApi _vApi = widget.versionsApi ?? ExamVersionsApi();
  late final ExamSetupApi _sApi = widget.setupApi ?? ExamSetupApi();
  ExamVersions _versions = const ExamVersions();
  String? _version;              // the version code to print; null = the exam's own order
  AnswerTablePlace _table = AnswerTablePlace.none;
  ExamSetup? _setup;             // loaded when the exam is a paper exam (the answer-area choice is kept in sync with it)
  bool _named = true;
  Set<int> _students = {};
  int _blank = 30;
  late final _institution = TextEditingController(text: widget.orgName);
  late final _date = TextEditingController(text: widget.view.exam.startsAt == null ? '' : AppTime.date(widget.view.exam.startsAt!));
  late final _course = TextEditingController(text: widget.course);
  late final _instructions = TextEditingController(
      text: defaultPaperInstructions(
              rtl: AppConfig.lang == 'ar',
              questions: widget.view.questionCount,
              duration: widget.view.exam.durationMinutes == null ? '' : omrMinutesText(widget.view.exam.durationMinutes!))
          .join('\n'));

  @override
  void initState() {
    super.initState();
    _restore();
    _loadExtras();
  }

  Future<void> _loadExtras() async {
    final id = widget.view.exam.id;
    if (id == null) return;
    final v = await _vApi.versions(id);
    final s = await _sApi.setup(id);
    if (!mounted) return;
    setState(() {
      if (v.ok) _versions = ExamVersions.fromJson(v.map);
      if (s.ok) {
        final x = ExamSetup.fromJson(s.map);
        if (x.delivery == 'paper') _setup = x;
      }
    });
  }

  Future<void> _editVersions() async {
    final id = widget.view.exam.id;
    if (id == null) return;
    await openExamVersions(context, examId: id, current: _versions, api: _vApi, bubble: _setup?.paperFormat == 'bubble' || _setup?.paperFormat == 'both');
    // whatever the sheet returned (or a swipe away after a generate with warnings): the server holds the truth
    if (!mounted) return;
    await _loadExtras();
    if (mounted && _version != null && _versions.byCode(_version) == null) setState(() => _version = null);
  }

  /// The paper's answer area follows the exam's paper | bubble | both setting.
  Future<void> _pickArea(String format) async {
    final cur = _setup;
    final id = widget.view.exam.id;
    if (cur == null || id == null || cur.paperFormat == format) return;
    final r = await _sApi.putSetup(id, formatBody(cur, format));
    if (!mounted) return;
    if (!r.ok) return appToast(setupErrorText(r), error: true);
    final s = await _sApi.setup(id);
    if (mounted && s.ok) setState(() => _setup = ExamSetup.fromJson(s.map));
  }

  Future<void> _pickStudents() async {
    final id = widget.view.exam.id;
    if (id == null) return;
    await showAppSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          return AppSheetContent(title: t('اختر الطلاب', 'Pick students'), children: [
            OmrAudiencePicker(examId: id, selected: _students, onChanged: (v) {
              set(() {});
              setState(() => _students = v);
            }),
            const SizedBox(height: 8),
            AppPrimaryButton(label: t('تم', 'Done'), onPressed: () => Navigator.of(ctx).pop()),
          ]);
        }));
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

  Future<ExamPaperDoc> _baseDoc({required bool answerKey}) async => attachPaperImages(await _plainDoc(answerKey: answerKey), bankQuestionBytes);

  Future<ExamPaperDoc> _plainDoc({required bool answerKey}) async => ExamPaperDoc.fromView(widget.view,
      institution: _institution.text,
      course: _course.text,
      dateText: _date.text.trim(),
      instructions: _instructions.text.split('\n'),
      rtl: AppConfig.lang == 'ar',
      logo: _tpl == PaperTemplate.custom ? null : await _logo(),
      accentHex: widget.accentHex,
      showPoints: _points,
      seatNumber: _seat,
      answerKey: answerKey,
      answerTable: _setup?.paperFormat == 'bubble' ? AnswerTablePlace.none : _table);

  /// One copy per student (or blank), a QR on every page: pages are counted by laying each version out once.
  Future<void> _printCopies() async {
    final id = widget.view.exam.id;
    if (id == null) return;
    if (_versions.stale) return appToast(versionsStaleText, error: true);
    if (_named && _students.isEmpty) return appToast(t('اختر الطلاب أولاً', 'Pick the students first'), error: true);
    setState(() => _busy = 'copies');
    try {
      final base = await _baseDoc(answerKey: false);
      final word = _word;
      var tpl = resolvePaperTemplate(_tpl, highStakes: widget.view.exam.highStakes);
      if (tpl == PaperTemplate.custom) tpl = resolvePaperTemplate(PaperTemplate.auto, highStakes: widget.view.exam.highStakes);
      final style = PaperStyle.of(tpl);
      final regular = await rootBundle.load(style.regular), bold = await rootBundle.load(style.bold);
      final res = await buildPaperCopies(
          base: base, versions: _versions, api: _vApi, examId: id, tpl: tpl, regular: regular, bold: bold, named: _named,
          studentIds: _students.toList(), blank: _blank, form: _version, word: word);
      if (res.error != null) {
        appToast(res.error!, error: true);
      } else {
        final name = '${base.title} - ${t('نسخ الطلاب', 'student copies')}'.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
        final path = await saver.dlSaveBytes(res.bytes!, '$name.${word ? 'zip' : 'pdf'}', word ? 'application/zip' : 'application/pdf');
        appToast(path == null ? t('جاهز للطباعة', 'Ready to print') : '${t('حُفظ في', 'Saved to')} $path');
        if (res.warning != null) appToast(res.warning!, error: true);
      }
    } catch (e) {
      debugPrint('exam copies failed: $e');
      appToast(t('تعذّر إنشاء الملف', 'Could not create the file'), error: true);
    }
    if (mounted) setState(() => _busy = null);
  }

  Future<void> _make({required bool answerKey}) async {
    if (_tpl == PaperTemplate.custom && _custom == null) return _pickCustom();
    setState(() => _busy = answerKey ? 'key' : 'paper');
    try {
      final v = _versions.byCode(_version);
      if (v != null && v.stale) {
        appToast(versionsStaleText, error: true);
        setState(() => _busy = null);
        return;
      }
      var d = await _baseDoc(answerKey: answerKey);
      if (_tpl == PaperTemplate.custom && d.hasImages) appToast(wordNoImagesText);
      if (v != null) {
        d = applyVersion(d, v);
        final id = widget.view.exam.id;
        if (answerKey && id != null) {
          final k = await _vApi.answerKey(id, form: v.code);
          if (!k.ok) {
            appToast(versionsErrorText(k), error: true);
            setState(() => _busy = null);
            return;
          }
          d = d.copyWith(keySummary: keyLinesForPaper(d, answerKeyItems(k.map)));
        }
      }
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
      final base = '${d.title}${v == null ? '' : ' - ${v.code}'}${answerKey ? ' - ${t('نموذج الإجابة', 'answer key')}' : ''}'.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
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
    return AppSheetContent(title: t('ورقة الامتحان للطباعة', 'Printable exam paper'), children: [
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
        _tpl == PaperTemplate.auto ? '${paperTemplateHint(_tpl)} ${t('← الآن:', '→ now:')} ${paperTemplateLabel(resolved)}' : paperTemplateHint(_tpl),
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
      PaperVersionsSection(
        versions: _versions,
        selected: _version,
        onSelect: (v) => setState(() => _version = v),
        onEdit: _editVersions,
      ),
      PaperAnswerAreaSection(
        format: _setup?.paperFormat,
        syncable: _setup != null,
        onFormat: _pickArea,
        table: _table,
        onTable: (v) => setState(() => _table = v),
      ),
      PaperCopiesSection(
        named: _named,
        onNamed: (v) => setState(() => _named = v),
        picked: _students.length,
        onPick: _pickStudents,
        blank: _blank,
        onBlank: (v) => setState(() => _blank = v),
        busy: _busy == 'copies',
        wordNote: _word,
        onPrint: _busy != null ? null : _printCopies,
      ),
      const SizedBox(height: 10),
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
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12.5, w: FontWeight.w700, c: c.textDark))),
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


/// A creator's own .docx template is filled with text only: a "[image: …]" line stands where a question has a picture.
String get wordNoImagesText => t('القالب المخصص (ملف .docx) لا يتضمن صور الأسئلة (يظهر سطر بدلاً منها). استخدم تصميماً جاهزاً أو PDF لطباعة الصور.', 'A custom .docx template does not include question images (a placeholder line shows instead). Use a built-in design or PDF to print the images.');

/// The most pages per copy the print plan gives a QR to.
const kMaxQrPages = 40;

String get qrPagesWarningText => t('بعض صفحات النسخ بلا رمز QR (عدد الصفحات تغيّر أو تجاوز $kMaxQrPages). راجع الملف قبل الطباعة.',
    'Some pages have no QR code (a copy has more pages than planned, or over $kMaxQrPages). Check the file before printing.');

/// What a per-student print produced: the file, or the reason it could not be made.
class PaperCopiesResult {
  const PaperCopiesResult({this.bytes, this.error, this.copies = 0, this.pages = 0, this.warning});
  final Uint8List? bytes;
  final String? error;

  /// The file was made but some pages may have no QR (a copy's real page count differs from the plan's, or it is over [kMaxQrPages]).
  final String? warning;
  final int copies, pages;
}

/// Per-student copies (D-print): lays each version out once to count its pages, asks `POST …/print-plan` for the QR
/// payloads of that many pages, then renders one paper per plan item with the student's name and a QR on EVERY page,
/// merged into one PDF. [word]: a zip of Word files instead (the name in every page header; one section per planned page, each with its own QR in its footer).
Future<PaperCopiesResult> buildPaperCopies({
  required ExamPaperDoc base,
  required ExamVersions versions,
  required ExamVersionsApi api,
  required int examId,
  required PaperTemplate tpl,
  required ByteData regular,
  required ByteData bold,
  required bool named,
  List<int> studentIds = const [],
  int blank = 1,
  String? form,
  bool word = false,
}) async {
  final codes = <String?>[
    if (form != null) form else if (versions.items.isEmpty) null else ...versions.items.map((v) => v.code),
  ];
  final pagesOf = <String?, int>{};
  for (final code in codes) {
    final v = versions.byCode(code);
    final doc = (v == null ? base : applyVersion(base, v)).copyWith(qrSlots: 1);
    // Word lays itself out: its page count is the writer's own split, not the PDF's
    pagesOf[code] = word ? wordPageCount(doc, tpl) : (await examPaperPdfMany([doc], tpl, regular: regular, bold: bold)).pages.first;
  }
  final maxPages = pagesOf.values.fold(1, (m, x) => x > m ? x : m);
  final r = await api.printPlan(examId, printPlanBody(named: named, studentIds: named ? studentIds : null, copies: blank, pages: maxPages, form: form));
  if (!r.ok) return PaperCopiesResult(error: versionsErrorText(r));
  final plan = PrintPlan.fromJson(r.map);
  if (plan.items.isEmpty) return PaperCopiesResult(error: t('لا توجد نسخ للطباعة', 'There are no copies to print'));
  final docs = copiesFor(base, plan, versions, pagesOf: pagesOf);
  if (word) {
    final zip = Archive();
    for (var i = 0; i < docs.length; i++) {
      final n = docs[i].studentName.isEmpty ? '${plan.items[i].copyNo}' : '${plan.items[i].copyNo} - ${docs[i].studentName}'.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      zip.add(ArchiveFile.bytes('$n.docx', examPaperDocx(docs[i], tpl)));
    }
    return PaperCopiesResult(bytes: Uint8List.fromList(ZipEncoder().encodeBytes(zip)), copies: docs.length);
  }
  final out = await examPaperPdfMany(docs, tpl, regular: regular, bold: bold);
  var mismatch = out.pages.length != plan.items.length || out.pages.any((p) => p > kMaxQrPages);
  for (var i = 0; !mismatch && i < out.pages.length; i++) {
    if (out.pages[i] != docs[i].qrPages.length) mismatch = true; // the QRs the copy got (plan.items[i].pages cut to its own count)
  }
  return PaperCopiesResult(bytes: out.bytes, copies: docs.length, pages: out.pages.fold(0, (a, b) => a + b), warning: mismatch ? qrPagesWarningText : null);
}

/// Versions of the paper: which one to print, and the sheet that makes them.
class PaperVersionsSection extends StatelessWidget {
  const PaperVersionsSection({super.key, required this.versions, required this.selected, required this.onSelect, required this.onEdit});
  final ExamVersions versions;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('النماذج', 'Versions'), style: appText(14, w: FontWeight.w700, c: c.textDark)),
        const SizedBox(height: 6),
        if (versions.stale)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppBanner(
                key: const ValueKey('paper.versions.stale'),
                icon: Icons.warning_amber_rounded,
                text: versionsStaleText,
                action: TextButton(onPressed: onEdit, child: Text(t('إعادة الإنشاء', 'Regenerate')))),
          ),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (versions.items.isNotEmpty) AppChoiceChip(label: t('ترتيب الاختبار', 'Exam order'), selected: selected == null, onTap: () => onSelect(null)),
          for (final v in versions.items)
            AppChoiceChip(label: '${t('نموذج', 'Version')} ${v.code}', selected: selected == v.code, onTap: () {
                  if (v.stale) {
                    appToast(versionsStaleText, error: true);
                  } else {
                    onSelect(v.code);
                  }
                }),
          OutlinedButton.icon(
            key: const ValueKey('paper.versions.edit'),
            onPressed: onEdit,
            icon: const Icon(Icons.shuffle_rounded, size: 18),
            label: Text(versions.items.isEmpty ? t('إنشاء نماذج', 'Make versions') : t('تعديل النماذج', 'Edit versions')),
          ),
        ]),
      ]),
    );
  }
}

/// Where the choice answers go: on the paper (with an optional answer table), on the bubble sheet, or both.
class PaperAnswerAreaSection extends StatelessWidget {
  const PaperAnswerAreaSection({super.key, required this.format, required this.syncable, required this.onFormat, required this.table, required this.onTable});

  /// The exam's paper | bubble | both setting (null when not a paper exam).
  final String? format;
  final bool syncable;
  final ValueChanged<String> onFormat;
  final AnswerTablePlace table;
  final ValueChanged<AnswerTablePlace> onTable;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final onPaper = format != 'bubble';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('أين يجيب الطالب عن الاختيارات؟', 'Where do students answer the choices?'), style: appText(14, w: FontWeight.w700, c: c.textDark)),
        const SizedBox(height: 6),
        if (syncable)
          Wrap(spacing: 8, runSpacing: 8, children: [
            AppChoiceChip(label: t('على الورقة', 'On the paper'), selected: format == 'paper', onTap: () => onFormat('paper')),
            AppChoiceChip(label: t('ورقة التظليل', 'Bubble sheet'), selected: format == 'bubble', onTap: () => onFormat('bubble')),
            AppChoiceChip(label: t('كلاهما', 'Both'), selected: format == 'both', onTap: () => onFormat('both')),
          ]),
        if (onPaper) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            AppChoiceChip(label: t('دوائر داخل الأسئلة', 'Circles in the questions'), selected: table == AnswerTablePlace.none, onTap: () => onTable(AnswerTablePlace.none)),
            AppChoiceChip(label: t('جدول إجابة في البداية', 'Answer table at the start'), selected: table == AnswerTablePlace.start, onTap: () => onTable(AnswerTablePlace.start)),
            AppChoiceChip(label: t('جدول إجابة في النهاية', 'Answer table at the end'), selected: table == AnswerTablePlace.end, onTap: () => onTable(AnswerTablePlace.end)),
          ]),
        ],
      ]),
    );
  }
}

/// One copy per student (named, a QR on every page) or a number of blank copies.
class PaperCopiesSection extends StatelessWidget {
  const PaperCopiesSection({super.key, required this.named, required this.onNamed, required this.picked, required this.onPick, required this.blank,
      required this.onBlank, required this.busy, required this.wordNote, required this.onPrint});
  final bool named, busy, wordNote;
  final ValueChanged<bool> onNamed;
  final int picked, blank;
  final VoidCallback onPick;
  final ValueChanged<int> onBlank;
  final VoidCallback? onPrint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('نسخ مطبوعة لكل طالب', 'Printed copy per student'), style: appText(14, w: FontWeight.w700, c: c.textDark)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          AppChoiceChip(label: t('باسم الطالب', 'Named'), selected: named, onTap: () => onNamed(true)),
          AppChoiceChip(label: t('فارغة', 'Blank'), selected: !named, onTap: () => onNamed(false)),
        ]),
        const SizedBox(height: 8),
        if (named)
          OutlinedButton.icon(
              key: const ValueKey('paper.copies.pick'),
              onPressed: onPick,
              icon: const Icon(Icons.groups_rounded, size: 18),
              label: Text(picked == 0 ? t('اختر الطلاب', 'Pick students') : omrSelectedText(picked)))
        else
          Row(children: [
            Expanded(child: Text(t('عدد النسخ', 'Number of copies'), style: appText(13, c: c.textMedium))),
            IconButton(onPressed: blank > 1 ? () => onBlank(blank - 1) : null, icon: const Icon(Icons.remove_circle_outline_rounded), tooltip: t('أقل', 'Less')),
            SizedBox(width: 40, child: Text('$blank', textAlign: TextAlign.center, style: appText(16, w: FontWeight.w800, c: c.textDark))),
            IconButton(onPressed: blank < 500 ? () => onBlank(blank + 1) : null, icon: const Icon(Icons.add_circle_outline_rounded), tooltip: t('أكثر', 'More')),
          ]),
        if (wordNote)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(t('في Word: ملف لكل طالب داخل ملف مضغوط، والاسم في كل صفحة (الرمز QR في PDF فقط).',
                'Word: one file per student in a zip, the name on every page (the QR code is in PDF only).'), style: appText(11.5, c: c.textLight)),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('paper.copies.print'),
          onPressed: onPrint,
          icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.qr_code_2_rounded, size: 18),
          label: Text(t('طباعة النسخ', 'Print the copies')),
        ),
      ]),
    );
  }
}
