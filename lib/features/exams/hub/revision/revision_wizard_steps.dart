// The steps of the revision wizard, as plain-values widgets: what to compare with, the sheet's columns, the paper
// template, how to match a paper to a student, the sample read, and how the paper is written.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/marks/mark_sessions_api.dart' show markNumberText;
import 'package:flutter_education_app/features/exams/marks/mark_templates_api.dart' show MarkBuiltin, MarkTemplate, identifierSourceLabel, qualityCodeText;
import 'package:flutter_education_app/features/exams/marks/review/grade_review_start.dart' show GradeColumn, gradeConversionText;
import 'package:flutter_education_app/features/exams/marks/templates/mark_strip.dart';
import 'package:flutter_education_app/features/exams/marks/templates/mark_template_common.dart' show confColor, kindIcon, pct;
import 'package:flutter_education_app/features/exams/hub/revision/revision_builtin.dart';
import 'package:flutter_education_app/features/exams/hub/revision/revision_models.dart';

// ── small shared pieces ───────────────────────────────────────────────────────────────────────────────────────────

/// The brand colour that stays readable on the current surface (the one the text buttons use; in dark mode the raw primary is too dark).
Color revisionAccent(BuildContext context) => Theme.of(context).textButtonTheme.style?.foregroundColor?.resolve(const {}) ?? context.colors.primary;

class RevisionChoiceCard extends StatelessWidget {
  const RevisionChoiceCard({super.key, required this.icon, required this.title, required this.subtitle, required this.selected, required this.onTap, this.recommended = false});
  final IconData icon;
  final String title, subtitle;
  final bool selected, recommended;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: (selected ? c.primary : c.textLight).withValues(alpha: .14), borderRadius: AppRadius.cardAll),
          child: Icon(icon, color: selected ? revisionAccent(context) : c.textMedium),
        ),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(title, style: AppType.section(context)),
              if (recommended) AppBadgePill(t('موصى به', 'Recommended'), color: c.success),
            ]),
            Text(subtitle, style: AppType.meta(context)),
          ]),
        ),
        Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: selected ? revisionAccent(context) : c.textLight),
      ]),
    );
  }
}

// ── step 1: what to compare with ──────────────────────────────────────────────────────────────────────────────────

typedef RevisionCourse = ({int id, String name, int? orgId});

class RevisionSourceStep extends StatelessWidget {
  const RevisionSourceStep({
    super.key,
    required this.setup,
    required this.onSource,
    required this.onCourse,
    required this.onColumn,
    required this.onUpload,
    required this.onMatchColumn,
    required this.onDegreeColumn,
    required this.onSheetMax,
    this.courses = const [],
    this.columns = const [],
    this.courseLocked = false,
    this.courseName,
    this.loadingColumns = false,
    this.uploading = false,
    this.onImportInstead,
  });

  final RevisionSetup setup;
  final ValueChanged<RevisionSource> onSource;
  final ValueChanged<int> onCourse;
  final ValueChanged<GradeColumn> onColumn;
  final VoidCallback onUpload;
  final ValueChanged<String> onMatchColumn, onDegreeColumn;
  final ValueChanged<double?> onSheetMax;
  final List<RevisionCourse> courses;
  final List<GradeColumn> columns;

  /// The course comes from the exam or the Data Lab: shown, not asked.
  final bool courseLocked;
  final String? courseName;
  final bool loadingColumns, uploading;

  /// Mark import keeps its own short form.
  final VoidCallback? onImportInstead;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final source = setup.source;
    final sheet = setup.sheet;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      RevisionChoiceCard(
        key: const ValueKey('rv.source.gradebook'),
        icon: Icons.table_chart_outlined,
        title: t('عمود في Data Lab', 'A course Data Lab column'),
        subtitle: t('نقارن كل ورقة بالدرجة المسجّلة في المقرر.', 'Each paper is compared with the grade recorded in the course.'),
        selected: source == RevisionSource.gradebook,
        recommended: true,
        onTap: () => onSource(RevisionSource.gradebook),
      ),
      AppSpace.gapXs,
      RevisionChoiceCard(
        key: const ValueKey('rv.source.excel'),
        icon: Icons.upload_file_rounded,
        title: t('ملف Excel', 'An Excel sheet'),
        subtitle: t('ارفع كشف الدرجات، وفي النهاية تنزّل نسخة مصحّحة منه.', 'Upload your grade sheet and download a corrected copy at the end.'),
        selected: source == RevisionSource.excel,
        onTap: () => onSource(RevisionSource.excel),
      ),
      AppSpace.gapMd,
      if (source == RevisionSource.gradebook) ...[
        if (courseLocked && courseName != null)
          Text('${t('المقرر', 'Course')}: $courseName', style: AppType.bodyStrong(context))
        else if (courses.isEmpty)
          AppBanner(icon: Icons.info_outline_rounded, color: c.warning, text: t('لا نجد مقررات تدرّسها. جرّب ملف Excel بدلًا من ذلك.', 'No courses you teach were found. Try an Excel sheet instead.'))
        else
          AppPicker<int>(label: t('المقرر', 'Course'), value: setup.courseId, options: {for (final x in courses) x.id: x.name}, onChanged: (v) => v == null ? null : onCourse(v)),
        AppSpace.gapSm,
        if (setup.courseId != null)
          if (loadingColumns)
            const AppListSkeleton(items: 2)
          else if (columns.isEmpty)
            AppBanner(icon: Icons.info_outline_rounded, color: c.warning, text: t('لا يوجد في Data Lab عمود رقمي قابل للتعديل. أضف عمودًا أولًا، أو استخدم ملف Excel.', 'The Data Lab has no editable number column. Add one first, or use an Excel sheet.'))
          else
            AppPicker<String>(
              key: const ValueKey('rv.column'),
              label: t('عمود الدرجة', 'Grade column'),
              value: setup.column?.key,
              options: {for (final col in columns) col.key: '${col.label} · ${t('من', 'out of')} ${markNumberText(col.max)}'},
              onChanged: (k) {
                final col = columns.where((e) => e.key == k).firstOrNull;
                if (col != null) onColumn(col);
              },
            ),
      ],
      if (source == RevisionSource.excel) ...[
        if (sheet == null)
          AppPrimaryButton(key: const ValueKey('rv.sheet.upload'), label: t('رفع ملف Excel', 'Upload the Excel file'), icon: Icons.upload_file_rounded, busy: uploading, onPressed: uploading ? null : onUpload)
        else
          RevisionSheetMapping(sheet: sheet, matchColumn: setup.matchColumn, degreeColumn: setup.degreeColumn, sheetMax: setup.sheetMax, onMatch: onMatchColumn, onDegree: onDegreeColumn, onMax: onSheetMax, onReplace: onUpload, uploading: uploading),
      ],
      if (onImportInstead != null) ...[
        AppSpace.gapMd,
        Center(child: TextButton.icon(key: const ValueKey('rv.import'), onPressed: onImportInstead, icon: const Icon(Icons.document_scanner_outlined), label: Text(t('استيراد درجات من الورق بدلًا من المراجعة', 'Import marks from paper instead')))),
      ],
    ]);
  }
}

/// The columns of an uploaded sheet with their samples; the server's guesses arrive already chosen.
class RevisionSheetMapping extends StatefulWidget {
  const RevisionSheetMapping({super.key, required this.sheet, required this.matchColumn, required this.degreeColumn, required this.sheetMax, required this.onMatch, required this.onDegree, required this.onMax, required this.onReplace, this.uploading = false});
  final RevisionSheetPreview sheet;
  final String? matchColumn, degreeColumn;
  final double? sheetMax;
  final ValueChanged<String> onMatch, onDegree;
  final ValueChanged<double?> onMax;
  final VoidCallback onReplace;
  final bool uploading;

  @override
  State<RevisionSheetMapping> createState() => _RevisionSheetMappingState();
}

class _RevisionSheetMappingState extends State<RevisionSheetMapping> {
  late final _max = TextEditingController(text: widget.sheetMax == null ? '' : markNumberText(widget.sheetMax));

  @override
  void dispose() {
    _max.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = widget.sheet;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(Icons.description_outlined, color: c.success),
        AppSpace.gapXs,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.fileName.isEmpty ? t('الملف', 'The file') : s.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
            Text(countText(s.rows, ar1: 'صف واحد', ar2: 'صفان', arFew: '${s.rows} صفوف', arMany: '${s.rows} صفًا', en1: '1 row', en: '${s.rows} rows'), style: AppType.meta(context)),
          ]),
        ),
        TextButton(onPressed: widget.uploading ? null : widget.onReplace, child: Text(t('تغيير', 'Change'))),
      ]),
      AppSpace.gapSm,
      Text(t('حدّدنا الأعمدة التي بدت مناسبة. صحّحها إن لزم.', 'We picked the columns that looked right. Correct them if needed.'), style: AppType.meta(context)),
      AppSpace.gapXs,
      for (final col in s.columns)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: AppCard(
            key: ValueKey('rv.sheet.col.${col.name}'),
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(col.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              if (col.samples.isNotEmpty) Text(col.samples.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              AppSpace.gapXs,
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                AppChoiceChip(key: ValueKey('rv.sheet.match.${col.name}'), label: t('للمطابقة', 'Match by this'), icon: Icons.badge_outlined, selected: widget.matchColumn == col.name, onTap: () => widget.onMatch(col.name)),
                AppChoiceChip(key: ValueKey('rv.sheet.degree.${col.name}'), label: t('الدرجة', 'Degree'), icon: Icons.grading_rounded, selected: widget.degreeColumn == col.name, onTap: () => widget.onDegree(col.name)),
              ]),
            ]),
          ),
        ),
      AppSpace.gapXs,
      Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: AppNumberField(controller: _max, label: t('الدرجة العظمى في الملف (اتركها فارغة لتساوي درجة الورقة)', "The sheet's full mark (leave empty to use the paper's total)"), min: 0, decimals: 2, onChanged: (v) {
          final x = v?.toDouble();
          widget.onMax(x != null && x > 0 ? x : null);
        })),
    ]);
  }
}

// ── step 2: the template ──────────────────────────────────────────────────────────────────────────────────────────

class RevisionTemplateStep extends StatelessWidget {
  const RevisionTemplateStep({super.key, required this.setup, required this.templates, required this.onPick, required this.onCreate, required this.onEdit, required this.onStep, this.loading = false, this.loadingId, this.builtins = const [], this.onBuiltin, this.loadBuiltinImage, this.builtinBusy});

  final RevisionSetup setup;
  final List<MarkTemplate> templates;
  final ValueChanged<MarkTemplate> onPick;
  final VoidCallback onCreate, onEdit;
  final ValueChanged<double> onStep;
  final bool loading;
  final int? loadingId;

  /// Ready-made covers, offered first.
  final List<MarkBuiltin> builtins;
  final ValueChanged<MarkBuiltin>? onBuiltin;
  final RevisionBuiltinImage? loadBuiltinImage;

  /// The built-in being copied right now.
  final String? builtinBusy;

  Widget _ready(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('أغلفة جاهزة', 'Ready-made covers'), key: const ValueKey('rv.builtins'), style: AppType.section(context)),
        Text(t('ابدأ فورًا دون تحديد أي خانة.', 'Start at once, nothing to mark out.'), style: AppType.meta(context)),
        AppSpace.gapXs,
        for (final b in builtins)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: RevisionBuiltinCard(key: ValueKey('rv.builtin.${b.key}'), builtin: b, load: loadBuiltinImage, busy: builtinBusy == b.key, selected: setup.template != null && b.isCopy(setup.template!.name), onTap: builtinBusy == null && onBuiltin != null ? () => onBuiltin!(b) : null),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (loading) return const AppListSkeleton(items: 3);
    if (templates.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (builtins.isNotEmpty) ...[_ready(context), AppSpace.gapSm],
        AppCard(
          key: const ValueKey('rv.template.first'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Icon(Icons.document_scanner_outlined, size: AppIconSize.hero, color: c.primary),
            AppSpace.gapSm,
            Text(builtins.isEmpty ? t('لنعرّف ورقتك مرة واحدة', "Let's set up your paper once") : t('ورقتك مختلفة؟', 'Is your paper different?'), textAlign: TextAlign.center, style: AppType.section(context)),
            const SizedBox(height: AppSpace.xxs),
            Text(t('صوّر ورقة فارغة وسنحدد أماكن الدرجات ورقم الطالب. تأخذ دقيقة، وتستخدمها في كل مرة بعد ذلك.', "Photograph a blank paper and we find where the marks and the student's number go. It takes a minute, and you reuse it every time after."), textAlign: TextAlign.center, style: AppType.meta(context)),
            AppSpace.gapMd,
            builtins.isEmpty
                ? AppPrimaryButton(key: const ValueKey('rv.template.new'), label: t('إعداد الورقة', 'Set up my paper'), icon: Icons.add_a_photo_outlined, onPressed: onCreate)
                : OutlinedButton.icon(key: const ValueKey('rv.template.new'), onPressed: onCreate, icon: const Icon(Icons.add_a_photo_outlined), label: Text(t('إعداد ورقتي', 'Set up my paper'))),
          ]),
        ),
      ]);
    }
    final current = setup.template;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (builtins.isNotEmpty) ...[
        _ready(context),
        AppSpace.gapSm,
        Text(t('قوالبك', 'Your templates'), style: AppType.section(context)),
        AppSpace.gapXs,
      ],
      for (final x in templates)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: RevisionChoiceCard(
            key: ValueKey('rv.template.${x.id}'),
            icon: kindIcon(x.kind),
            title: x.name,
            subtitle: [if (x.kind != null) x.kind!.label, countText(x.fieldsCount, ar1: 'حقل واحد', ar2: 'حقلان', arFew: '${x.fieldsCount} حقول', arMany: '${x.fieldsCount} حقلًا', en1: '1 field', en: '${x.fieldsCount} fields'), if (x.totalMax != null) '${t('من', 'out of')} ${markNumberText(x.totalMax)}'].join(' · '),
            selected: current?.id == x.id,
            onTap: loadingId == null ? () => onPick(x) : null,
          ),
        ),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
        TextButton.icon(key: const ValueKey('rv.template.new'), onPressed: onCreate, icon: const Icon(Icons.add_rounded), label: Text(t('قالب جديد', 'New template'))),
        if (current != null) TextButton.icon(key: const ValueKey('rv.template.edit'), onPressed: onEdit, icon: const Icon(Icons.edit_outlined), label: Text(t('تعديل القالب', 'Edit this template'))),
      ]),
      if (setup.converts) ...[
        AppSpace.gapSm,
        AppBanner(key: const ValueKey('rv.convert'), icon: Icons.swap_horiz_rounded, text: gradeConversionText(setup.template!.totalMax, setup.targetMax!), color: c.primary),
        AppSpace.gapXs,
        Text(t('تقريب الدرجة إلى أقرب', 'Round the mark to the nearest'), style: AppType.meta(context)),
        const SizedBox(height: AppSpace.xxs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final s in const [0.25, 0.5, 1.0]) AppChoiceChip(key: ValueKey('rv.step.$s'), label: markNumberText(s), selected: setup.step == s, onTap: () => onStep(s)),
        ]),
      ],
    ]);
  }
}

// ── step 3: how a paper is linked to a student ────────────────────────────────────────────────────────────────────

/// What a paper can be matched by: the template's own identifier first, then the other lists and the Data Lab columns.
class RevisionMatchStep extends StatelessWidget {
  const RevisionMatchStep({super.key, required this.setup, required this.options, required this.onPick, this.recommended, this.identifiers = 0, this.onSheetColumn});
  final RevisionSetup setup;
  final Map<RevisionMatch?, String> options;
  final ValueChanged<RevisionMatch?> onPick;

  /// What the teacher's own data says this number is (a seat number on a slanted line).
  final RevisionMatch? recommended;

  /// How many Data Lab rows hold a student number.
  final int identifiers;

  /// A sheet and a slanted line: the column to match on can still be chosen here.
  final ValueChanged<String>? onSheetColumn;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tpl = setup.template;
    final strip = setup.usesStrip;
    final note = strip
        ? t('رقم مكتوب بخط اليد قد لا يكون واضحًا: حين لا نتأكد نسألك عن الطالب بلمسة واحدة.', "A handwritten number isn't always clear: when we aren't sure, we ask you for the student in one tap.")
        : t('الاسم وحده لا يربط أي ورقة تلقائيًا: كل ورقة باسم مكتوب تنتظر تأكيدك.', 'A name alone never links a paper by itself: a paper with only a written name waits for you to confirm it.');
    if (setup.source == RevisionSource.excel && strip && setup.sheet != null && onSheetColumn != null) {
      final seat = revisionSeatColumn(setup.sheet, degreeColumn: setup.degreeColumn);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('أي عمود يحوي رقم الجلوس؟', 'Which column holds the seat number?'), style: AppType.section(context)),
        AppSpace.gapXs,
        for (final col in setup.sheet!.columns)
          if (col.name != setup.degreeColumn)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: RevisionChoiceCard(key: ValueKey('rv.match.sheet.${col.name}'), icon: Icons.view_column_outlined, title: col.name, subtitle: col.samples.isEmpty ? t('عمود في ملفك', 'A column of your file') : col.samples.take(3).join(' · '), selected: setup.matchColumn == col.name, recommended: col.name == seat, onTap: () => onSheetColumn!(col.name)),
            ),
        AppSpace.gapXs,
        Text(note, style: AppType.meta(context)),
      ]);
    }
    if (setup.source == RevisionSource.excel) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppBanner(icon: Icons.badge_outlined, color: c.primary, text: t('سنطابق كل ورقة بعمود «${setup.matchColumn ?? ''}» من ملفك.', 'Each paper is matched by your column "${setup.matchColumn ?? ''}".')),
        AppSpace.gapSm,
        Text(note, style: AppType.meta(context)),
      ]);
    }
    if (tpl == null) return const SizedBox.shrink();
    if (setup.matchIsFixed) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppBanner(icon: Icons.badge_outlined, color: c.primary, text: tpl.identifierSource == 'qr' ? t('الورقة تحمل رمز QR، فتُربط بصاحبها مباشرة.', 'The paper carries a QR code, so it links to its student directly.') : t('هذا القالب يقرأ الاسم المكتوب. ستؤكد صاحب كل ورقة.', 'This template reads a written name. You confirm whose paper each one is.')),
        AppSpace.gapSm,
        Text(note, style: AppType.meta(context)),
      ]);
    }
    final rowId = identifiers > 0 ? t('من Data Lab · ${countText(identifiers, ar1: 'طالب واحد له رقم', ar2: 'طالبان لهما رقم', arFew: '$identifiers طلاب لهم أرقام', arMany: '$identifiers طالبًا لهم أرقام', en1: '1 student has one', en: '$identifiers students have one')}', 'From Data Lab · ${countText(identifiers, ar1: 'طالب واحد له رقم', ar2: 'طالبان لهما رقم', arFew: '$identifiers طلاب لهم أرقام', arMany: '$identifiers طالبًا لهم أرقام', en1: '1 student has one', en: '$identifiers students have one')}') : t('من Data Lab · لا أرقام مسجّلة بعد', 'From Data Lab · no numbers saved yet');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (strip && recommended == null) ...[
        AppBanner(key: const ValueKey('rv.match.steer'), icon: Icons.table_chart_outlined, color: c.primary, text: t('الرقم على هذا الغلاف رقم جلوس. اختر العمود الذي يحويه في Data Lab، أو أضفه هناك أولًا. الأرقام الأكاديمية كثيرًا ما تكون غير مسجّلة.', "The number on this cover is a seat number. Choose the Data Lab column that holds it, or add one there first. Academic numbers are often not saved.")),
        AppSpace.gapSm,
      ],
      for (final e in options.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: RevisionChoiceCard(
            key: ValueKey('rv.match.${e.key?.source ?? 'template'}.${e.key?.key ?? ''}'),
            icon: e.key?.source == 'datalab' ? Icons.table_chart_outlined : Icons.badge_outlined,
            title: e.value,
            subtitle: e.key == null ? t('كما هو محدد في القالب', 'As the template is set up') : (e.key == kRevisionDataLabIdentifier ? rowId : (e.key!.source == 'datalab' ? t('عمود في Data Lab', 'A Data Lab column') : t('من بيانات الطلاب', "From the students' records"))),
            selected: setup.match == e.key,
            recommended: strip ? e.key == recommended && recommended != null : e.key == null,
            onTap: () => onPick(e.key),
          ),
        ),
      AppSpace.gapXs,
      Text(note, style: AppType.meta(context)),
    ]);
  }
}

String revisionTemplateMatchLabel(String source) => identifierSourceLabel(source);

// ── step 4: the sample read ───────────────────────────────────────────────────────────────────────────────────────

class RevisionSampleView extends StatelessWidget {
  const RevisionSampleView({super.key, required this.sample, required this.aspect, this.identifierBox, this.nameOnly = false, this.strip, this.onChangeMatch});
  final RevisionSample sample;
  final double aspect;
  final Rect? identifierBox;
  final bool nameOnly;

  /// The identifier's slanted line, when the template has one.
  final MarkStrip? strip;

  /// Nobody in the course has this kind of number: offer to match on another column.
  final VoidCallback? onChangeMatch;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.mobile;
    final results = _Results(sample: sample, nameOnly: nameOnly, strip: strip != null, onChangeMatch: onChangeMatch);
    if (sample.preview == null) return results;
    final picture = RevisionPagePreview(sample: sample, aspect: aspect, identifierBox: identifierBox, strip: strip);
    if (!wide) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [ConstrainedBox(constraints: const BoxConstraints(maxHeight: 360), child: Center(child: picture)), AppSpace.gapSm, results]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 5, child: picture),
      AppSpace.gapMd,
      Expanded(flex: 6, child: results),
    ]);
  }
}

/// The straightened photo with the read boxes drawn over it.
class RevisionPagePreview extends StatelessWidget {
  const RevisionPagePreview({super.key, required this.sample, required this.aspect, this.identifierBox, this.strip});
  final RevisionSample sample;
  final double aspect;
  final Rect? identifierBox;
  final MarkStrip? strip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final idColor = sample.matched ? c.primary : c.warning;
    final boxes = <(Rect, Color)>[
      if (identifierBox != null && strip == null) (identifierBox!, idColor),
      for (final f in sample.fields)
        if (f.box != null && !f.emptyAllowed) (f.box!, confColor(context, f.conf, ok: f.ok)),
    ];
    return AspectRatio(
      aspectRatio: aspect,
      child: ClipRRect(
        borderRadius: AppRadius.cardAll,
        child: Stack(fit: StackFit.expand, children: [
          Image.memory(sample.preview!, key: const ValueKey('rv.sample.photo'), fit: BoxFit.fill, gaplessPlayback: true, excludeFromSemantics: true),
          CustomPaint(painter: _BoxesPainter(boxes, band: strip?.band(aspect), bandColor: idColor)),
        ]),
      ),
    );
  }
}

class _BoxesPainter extends CustomPainter {
  _BoxesPainter(this.boxes, {this.band, this.bandColor});
  final List<(Rect, Color)> boxes;

  /// The slanted writing band, page fractions.
  final List<Offset>? band;
  final Color? bandColor;

  @override
  void paint(Canvas canvas, Size size) {
    final b = band, col = bandColor;
    if (b != null && col != null) {
      final path = Path()..addPolygon([for (final p in b) Offset(p.dx * size.width, p.dy * size.height)], true);
      canvas.drawPath(path, Paint()..color = col.withValues(alpha: .18));
      canvas.drawPath(path, Paint()..color = col..style = PaintingStyle.stroke..strokeWidth = AppBorder.strong);
    }
    for (final (b, col) in boxes) {
      final r = Rect.fromLTWH(b.left * size.width, b.top * size.height, b.width * size.width, b.height * size.height);
      canvas.drawRect(r, Paint()..color = col.withValues(alpha: .18));
      canvas.drawRect(r, Paint()..color = col..style = PaintingStyle.stroke..strokeWidth = AppBorder.strong);
    }
  }

  @override
  bool shouldRepaint(_BoxesPainter old) => old.boxes != boxes || old.band != band;
}

class _Results extends StatelessWidget {
  const _Results({required this.sample, required this.nameOnly, this.strip = false, this.onChangeMatch});
  final RevisionSample sample;
  final bool nameOnly, strip;
  final VoidCallback? onChangeMatch;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = sample;
    final verdict = s.verdict(nameOnly: nameOnly, strip: strip);
    final read = [for (final f in s.fields) if (!f.emptyAllowed) f];
    final empties = s.fields.length - read.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      switch (verdict) {
        SampleVerdict.good => AppBanner(key: const ValueKey('rv.verdict.good'), icon: Icons.check_circle_outline_rounded, color: c.success, text: t('قراءة جيدة: تعرّفنا على الطالب وكل الدرجات.', 'A good read: the student and every mark were recognised.')),
        SampleVerdict.willAsk => AppBanner(key: const ValueKey('rv.verdict.ask'), icon: Icons.person_search_outlined, color: revisionAccent(context), text: t('قرأنا الدرجات. سنطلب منك اختيار الطالب، وهذا طبيعي مع الأرقام المكتوبة باليد ويأخذ لمسة واحدة لكل ورقة.', "The marks were read. We'll ask you to choose the student. That's normal for handwritten numbers and takes one tap per paper.")),
        SampleVerdict.partial => AppBanner(key: const ValueKey('rv.verdict.partial'), icon: Icons.warning_amber_rounded, color: c.warning, text: _partialText(s)),
        SampleVerdict.bad => AppBanner(key: const ValueKey('rv.verdict.bad'), icon: Icons.error_outline_rounded, color: c.danger, text: s.message.isNotEmpty ? s.message : qualityCodeText(s.code)),
      },
      if (s.ok) ...[
        AppSpace.gapSm,
        if (s.rosterEmpty && onChangeMatch != null) ...[
          AppBanner(key: const ValueKey('rv.sample.steer'), icon: Icons.table_chart_outlined, color: c.primary, text: t('لا يوجد هذا النوع من الأرقام عند طلاب هذا المقرر، فلن نجد أحدًا لتطابقه.', "No student in this course has this kind of number saved, so nothing can match it.")),
          Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(key: const ValueKey('rv.sample.change_match'), onPressed: onChangeMatch, icon: const Icon(Icons.table_chart_outlined), label: Text(t('المطابقة بعمود في Data Lab', 'Match on a Data Lab column')))),
          AppSpace.gapXs,
        ],
        if (s.stripImage != null || s.candidates.isNotEmpty) RevisionStripRead(sample: s) else AppCard(
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Row(children: [
            Icon(Icons.badge_outlined, color: s.matched ? revisionAccent(context) : c.warning),
            AppSpace.gapSm,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('هوية الطالب', 'Student identifier'), style: AppType.meta(context)),
                Text(s.identifierMasked.isEmpty ? '—' : s.identifierMasked, textDirection: TextDirection.ltr, style: AppType.bodyStrong(context)),
                Text(s.matched ? s.studentName ?? '' : t('لم يُطابَق بطالب', 'Not matched to a student'), key: const ValueKey('rv.sample.student'), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: s.matched ? c.success : c.warning)),
              ]),
            ),
            if (s.identifierConf != null) AppBadgePill(pct(s.identifierConf!), color: confColor(context, s.identifierConf!, ok: s.matched)),
          ]),
        ),
        AppSpace.gapSm,
        AppSectionTitle(t('الدرجات المقروءة', 'Degrees read')),
        for (final f in read)
          Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: _FieldRow(field: f)),
        if (empties > 0)
          Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: Text(countText(empties, ar1: 'خانة فارغة تُحسب صفرًا', ar2: 'خانتان فارغتان تُحسبان صفرًا', arFew: '$empties خانات فارغة تُحسب صفرًا', arMany: '$empties خانة فارغة تُحسب صفرًا', en1: '1 empty box counts as 0', en: '$empties empty boxes count as 0'), key: const ValueKey('rv.sample.empties'), style: AppType.meta(context))),
        if (s.fields.isEmpty) Text(t('لم تُقرأ أي درجة.', 'No degree was read.'), style: AppType.meta(context)),
        if (s.sum != null) ...[
          AppSpace.gapSm,
          Row(children: [
            Expanded(child: Text(t('المجموع', 'The sum'), style: AppType.bodyStrong(context))),
            Text(markNumberText(s.sum), key: const ValueKey('rv.sample.sum'), style: AppType.figure(context)),
          ]),
          if (s.consistent == false) Text(t('المجموع المكتوب لا يطابق الأجزاء: سنستخدم مجموع الأجزاء.', 'The written total differs from the parts: the sum of the parts is used.'), style: AppType.meta(context).copyWith(color: c.warning)),
        ],
      ],
    ]);
  }

  String _partialText(RevisionSample s) {
    final bad = s.problems.length;
    if (!s.matched && !nameOnly && bad == 0) return t('قُرئت الدرجات، لكن لم نجد طالبًا بهذا الرقم. تأكد أن الورقة من هذه المجموعة.', 'The marks were read, but no student has this number. Check the paper belongs to this group.');
    final n = countText(bad, ar1: 'درجة واحدة تحتاج', ar2: 'درجتان تحتاجان', arFew: '$bad درجات تحتاج', arMany: '$bad درجة تحتاج', en1: '1 degree needs', en: '$bad degrees need');
    return t('$n نظرة. جرّب إعدادًا آخر، أو تابع وستصلك هذه الأوراق لتصحيحها.', '$n a look. Try another setting, or continue and these papers come to you to correct.');
  }
}

/// The number as the reader saw it: the straightened strip, large, with what was read and what happens next.
class RevisionStripRead extends StatelessWidget {
  const RevisionStripRead({super.key, required this.sample});
  final RevisionSample sample;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = sample;
    final accent = revisionAccent(context);
    return AppCard(
      key: const ValueKey('rv.sample.strip'),
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('الرقم المكتوب على الورقة', 'The number written on the paper'), style: AppType.meta(context)),
        if (s.stripImage != null) ...[
          AppSpace.gapXs,
          Container(
            height: 112,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.chip), border: Border.all(color: c.divider)),
            child: Image.memory(s.stripImage!, fit: BoxFit.contain, gaplessPlayback: true, excludeFromSemantics: true),
          ),
        ],
        AppSpace.gapXs,
        Row(children: [
          Expanded(child: Text(t('قرأناه', 'We read'), style: AppType.row(context))),
          Flexible(child: Text(s.identifierMasked.isEmpty ? '—' : s.identifierMasked, key: const ValueKey('rv.sample.read'), maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.figure(context))),
        ]),
        if (s.ruleFound == false) Text(t('لم نجد الخط المطبوع في هذه الصورة، فقرأنا المكان الذي حددته.', "We couldn't find the printed line in this photo, so we read the place you marked."), style: AppType.meta(context)),
        Divider(height: AppSpace.md, thickness: AppBorder.hairline, color: c.divider),
        if (s.matched)
          Row(children: [
            Icon(Icons.check_circle_rounded, size: AppIconSize.md, color: c.success),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(s.studentName ?? '', key: const ValueKey('rv.sample.student'), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context).copyWith(color: c.success))),
          ])
        else ...[
          Row(children: [
            Icon(Icons.person_search_outlined, size: AppIconSize.md, color: accent),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(t('سنطلب منك اختيار الطالب', "We'll ask you to choose the student"), key: const ValueKey('rv.sample.student'), style: AppType.bodyStrong(context))),
          ]),
          if (s.candidates.isNotEmpty) ...[
            AppSpace.gapXs,
            Text(t('الأقرب إلى ما كُتب', 'Closest to what was written'), style: AppType.meta(context)),
            const SizedBox(height: AppSpace.xxs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
              for (final x in s.candidates) AppTag(x.name, x.alreadyMatched ? c.textMedium : accent, icon: Icons.person_outline_rounded),
            ]),
          ],
        ],
      ]),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.field});
  final RevisionSampleField field;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = field;
    final color = confColor(context, f.conf, ok: f.ok);
    return Row(children: [
      if (f.crop != null) ...[
        Container(
          width: 72,
          height: 36,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.chip), border: Border.all(color: c.divider)),
          clipBehavior: Clip.antiAlias,
          child: Image.memory(f.crop!, fit: BoxFit.contain, excludeFromSemantics: true),
        ),
        AppSpace.gapSm,
      ],
      Expanded(child: Text(f.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
      Text('${f.value ?? '—'}${f.max == null ? '' : ' / ${markNumberText(f.max)}'}', textDirection: TextDirection.ltr, style: AppType.bodyStrong(context).copyWith(color: f.ok ? null : c.danger)),
      AppSpace.gapXs,
      AppBadgePill(pct(f.conf), color: color),
    ]);
  }
}

// ── step 5: how the paper is written ──────────────────────────────────────────────────────────────────────────────

class RevisionStyleStep extends StatelessWidget {
  const RevisionStyleStep({super.key, required this.styles, required this.onChanged, this.sample, this.previous, this.loading = false, this.onRestore, this.hasPhoto = false, this.identifierTitle});

  final RevisionStyles styles;
  final ValueChanged<RevisionStyles> onChanged;

  /// The read with the current choice, and the one before it (for side by side).
  final RevisionSample? sample, previous;
  final bool loading, hasPhoto;
  final VoidCallback? onRestore;

  /// What this paper's number is called, when it is more than "the student's number".
  final String? identifierTitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.desktop;
    final cards = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _StyleGroup(key: const ValueKey('rv.style.degree'), title: t('الدرجات', 'The degrees'), style: styles.degree, onChanged: (v) => onChanged(styles.copyWith(degree: v))),
      AppSpace.gapMd,
      _StyleGroup(key: const ValueKey('rv.style.identifier'), title: identifierTitle ?? t('رقم الطالب', "The student's number"), style: styles.identifier, onChanged: (v) => onChanged(styles.copyWith(identifier: v))),
      if (styles.anyPrinted) ...[
        AppSpace.gapSm,
        AppBanner(key: const ValueKey('rv.style.warn'), icon: Icons.info_outline_rounded, color: c.warning, text: t('«مطبوعة» للأرقام المكتوبة بالآلة فقط. اختيارها على خط اليد يزيد احتمال الأخطاء.', '"Printed" is for typed numbers only. Choosing it on handwriting makes mistakes more likely.')),
      ],
    ]);
    final compare = !hasPhoto
        ? Text(t('صوّر ورقة واحدة أولًا لترى أثر كل اختيار.', 'Scan one paper first to see what each choice changes.'), style: AppType.meta(context))
        : loading
            ? const AppListSkeleton(items: 3)
            : sample == null
                ? const SizedBox.shrink()
                : _Compare(now: sample!, before: previous, onRestore: onRestore);
    if (wide) return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 6, child: cards), AppSpace.gapLg, Expanded(flex: 5, child: compare)]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [cards, AppSpace.gapMd, compare]);
  }
}

class _StyleGroup extends StatelessWidget {
  const _StyleGroup({super.key, required this.title, required this.style, required this.onChanged});
  final String title;
  final RevisionStyle style;
  final ValueChanged<RevisionStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = (box.maxWidth - AppSpace.xs * 2) / 3;
      final kw = (box.maxWidth - AppSpace.xs) / 2;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: AppType.section(context)),
        AppSpace.gapXs,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final s in DigitScript.values)
            SizedBox(
              width: w,
              child: RevisionStyleCard(
                key: ValueKey('rv.script.${s.name}'),
                visual: _ScriptVisual(script: s),
                label: digitScriptLabel(s),
                note: s == DigitScript.auto ? t('للأوراق المختلطة', 'For mixed papers') : null,
                selected: style.script == s,
                onTap: () => onChanged(style.copyWith(script: s)),
              ),
            ),
        ]),
        AppSpace.gapXs,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final k in WriteKind.values)
            SizedBox(
              width: kw,
              child: RevisionStyleCard(
                key: ValueKey('rv.kind.${k.name}'),
                visual: _KindVisual(kind: k, script: style.script),
                label: writeKindLabel(k),
                note: k == WriteKind.handwritten ? t('الأنسب عادة', 'Usually right') : t('للأرقام المطبوعة فقط', 'Typed numbers only'),
                selected: style.kind == k,
                onTap: () => onChanged(style.copyWith(kind: k)),
              ),
            ),
        ]),
      ]);
    });
  }
}

class RevisionStyleCard extends StatelessWidget {
  const RevisionStyleCard({super.key, required this.visual, required this.label, this.note, required this.selected, required this.onTap});
  final Widget visual;
  final String label;
  final String? note;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = revisionAccent(context);
    return Semantics(
      selected: selected,
      button: true,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpace.xs),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            height: 56,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
            decoration: BoxDecoration(color: selected ? fg.withValues(alpha: .14) : c.background, borderRadius: BorderRadius.circular(AppRadius.chip)),
            child: FittedBox(fit: BoxFit.scaleDown, child: visual),
          ),
          const SizedBox(height: AppSpace.xxs),
          Row(children: [
            Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context).copyWith(color: selected ? fg : null))),
            Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: AppIconSize.md, color: selected ? fg : c.textLight),
          ]),
          if (note != null) Align(alignment: AlignmentDirectional.centerStart, child: Text(note!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context))),
        ]),
      ),
    );
  }
}

class _ScriptVisual extends StatelessWidget {
  const _ScriptVisual({required this.script});
  final DigitScript script;

  @override
  Widget build(BuildContext context) {
    final s = AppType.figureLarge(context).copyWith(fontFamily: AppFonts.family, fontFamilyFallback: AppFonts.fallback);
    if (script == DigitScript.auto) {
      return Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.ltr, children: [Text('12', style: s), const SizedBox(width: AppSpace.xs), Text('١٢', style: s)]);
    }
    return Text(script == DigitScript.western ? '123' : '١٢٣', textDirection: TextDirection.ltr, maxLines: 1, style: s);
  }
}

class _KindVisual extends StatelessWidget {
  const _KindVisual({required this.kind, required this.script});
  final WriteKind kind;
  final DigitScript script;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.textDark;
    if (kind == WriteKind.printed) return Text(script == DigitScript.arabic ? '٧٥' : '75', textDirection: TextDirection.ltr, style: AppType.figureLarge(context).copyWith(color: color, fontFamily: AppFonts.family, fontFamilyFallback: AppFonts.fallback));
    return CustomPaint(size: const Size(72, 40), painter: _HandPainter(color, arabic: script == DigitScript.arabic));
  }
}

/// Two digits drawn as a pen would, so the "handwritten" card looks handwritten without a special font.
class _HandPainter extends CustomPainter {
  _HandPainter(this.color, {this.arabic = false});
  final Color color;
  final bool arabic;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final p = Path();
    if (arabic) {
      // ٧
      p.moveTo(w * .08, h * .12);
      p.quadraticBezierTo(w * .22, h * .78, w * .28, h * .92);
      p.quadraticBezierTo(w * .36, h * .6, w * .46, h * .16);
      // ٥
      p.moveTo(w * .76, h * .12);
      p.cubicTo(w * .96, h * .2, w * .98, h * .78, w * .76, h * .86);
      p.cubicTo(w * .56, h * .8, w * .58, h * .2, w * .76, h * .12);
    } else {
      // 7
      p.moveTo(w * .08, h * .18);
      p.quadraticBezierTo(w * .3, h * .06, w * .44, h * .14);
      p.quadraticBezierTo(w * .3, h * .5, w * .22, h * .9);
      p.moveTo(w * .14, h * .5);
      p.lineTo(w * .36, h * .46);
      // 5
      p.moveTo(w * .84, h * .12);
      p.quadraticBezierTo(w * .7, h * .12, w * .6, h * .16);
      p.lineTo(w * .56, h * .48);
      p.cubicTo(w * .72, h * .36, w * .96, h * .5, w * .86, h * .74);
      p.quadraticBezierTo(w * .72, h * .98, w * .54, h * .8);
    }
    canvas.drawPath(p, pen);
  }

  @override
  bool shouldRepaint(_HandPainter old) => old.color != color || old.arabic != arabic;
}

class _Compare extends StatelessWidget {
  const _Compare({required this.now, this.before, this.onRestore});
  final RevisionSample now;
  final RevisionSample? before;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = before;
    final delta = b == null ? 0.0 : now.accuracy - b.accuracy;
    return AppCard(
      key: const ValueKey('rv.compare'),
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(t('القراءة بهذا الإعداد', 'The read with this setting'), style: AppType.section(context))),
          AppBadgePill(pct(now.accuracy), color: confColor(context, now.accuracy, ok: now.ok && now.accuracy > 0)),
        ]),
        if (b != null) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(delta.abs() < .005 ? t('الدقة لم تتغير.', 'The accuracy did not change.') : (delta > 0 ? t('الدقة تحسّنت بهذا الاختيار.', 'The accuracy improved with this choice.') : t('الدقة قلّت بهذا الاختيار.', 'The accuracy dropped with this choice.')), style: AppType.meta(context).copyWith(color: delta.abs() < .005 ? null : (delta > 0 ? c.success : c.warning))),
          AppSpace.gapXs,
          Row(children: [
            Expanded(child: Text(t('قبل', 'Before'), style: AppType.meta(context))),
            Expanded(child: Text(t('الآن', 'Now'), style: AppType.meta(context))),
          ]),
          const Divider(height: AppSpace.sm),
          for (final row in compareSamples(b, now))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xxs),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(row.label, style: AppType.meta(context)),
                Row(children: [
                  Expanded(child: _CompareValue(value: row.before, conf: row.confBefore)),
                  Expanded(child: _CompareValue(value: row.after, conf: row.confAfter, highlight: row.changed)),
                ]),
              ]),
            ),
          if (onRestore != null) TextButton.icon(key: const ValueKey('rv.restore'), onPressed: onRestore, icon: const Icon(Icons.undo_rounded), label: Text(t('الرجوع إلى الإعداد السابق', 'Go back to the previous setting'))),
        ] else
          Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: Text(t('غيّر اختيارًا وسنقرأ نفس الورقة مرة أخرى لتقارن.', 'Change a choice and we read the same paper again so you can compare.'), style: AppType.meta(context))),
      ]),
    );
  }
}

class _CompareValue extends StatelessWidget {
  const _CompareValue({this.value, this.conf, this.highlight = false});
  final String? value;
  final double? conf;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(value ?? '—', textDirection: TextDirection.ltr, style: AppType.bodyStrong(context).copyWith(color: highlight ? revisionAccent(context) : null)),
      if (conf != null) ...[
        AppSpace.gapXs,
        Flexible(child: Text(pct(conf!), maxLines: 1, style: AppType.meta(context))),
      ],
    ]);
  }
}
