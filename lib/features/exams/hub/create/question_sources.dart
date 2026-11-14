// The questions step's list when the questions come from several sources (D-717), drawn: the "add more" bar (generate,
// Google Forms, an Excel file; writing one is the type row under the list), the strip above each written question
// (where it came from, move up / down), the card of a question held on the server (an import), and the separate
// choice of a ready exam paper, which cannot be mixed with questions in the app. Plain values only: the layout harness
// pumps each one (test/org/question_sources_test.dart); the calls live in the wizard.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/exam_quick.dart' show quickTypeLabel;
import 'package:flutter_education_app/features/exams/exam_quick_screen.dart' show quickTypeIcon;
import 'package:flutter_education_app/features/exams/hub/create/exam_create_logic.dart';

/// "Add more questions": every source appends to the end of the one list.
class CreateSourceBar extends StatelessWidget {
  const CreateSourceBar({super.key, this.onGenerate, this.onForms, this.onExcel});

  /// Null = not offered here (no course, or its switch is off).
  final VoidCallback? onGenerate, onForms, onExcel;

  @override
  Widget build(BuildContext context) {
    if (onGenerate == null && onForms == null && onExcel == null) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('أضف أسئلة من مصدر آخر', 'Add questions from another source'), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: AppSpace.xxs),
      Text(t('تُضاف في آخر القائمة، ويمكنك ترتيبها أو حذف أي منها', 'They go to the end of the list; you can reorder or remove any of them'), style: AppType.meta(context)),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        if (onGenerate != null) AppPill(key: const ValueKey('create.source.generate'), icon: Icons.auto_awesome_rounded, label: t('توليد تلقائي', 'Generate'), onTap: onGenerate!),
        if (onForms != null) AppPill(key: const ValueKey('create.source.forms'), icon: Icons.dynamic_form_outlined, label: t('من Google Forms', 'From Google Forms'), onTap: onForms!),
        if (onExcel != null) AppPill(key: const ValueKey('create.source.excel'), icon: Icons.table_chart_outlined, label: t('من ملف Excel', 'From an Excel file'), onTap: onExcel!),
      ]),
    ]);
  }
}

/// Above the list when the questions come from more than one source: how many from each.
class QuestionSourcesSummary extends StatelessWidget {
  const QuestionSourcesSummary({super.key, required this.counts});
  final Map<QuestionOrigin, int> counts;

  @override
  Widget build(BuildContext context) {
    final used = [for (final o in QuestionOrigin.values) if ((counts[o] ?? 0) > 0) o];
    if (used.length < 2) return const SizedBox.shrink();
    return Wrap(key: const ValueKey('create.sources.summary'), spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text(t('مصادر الأسئلة:', 'Sources:'), style: AppType.meta(context)),
      for (final o in used) AppBadgePill('${questionOriginLabel(o)} · ${counts[o]}', color: context.colors.textMedium),
    ]);
  }
}

/// A small tag naming where a question came from.
class QuestionOriginTag extends StatelessWidget {
  const QuestionOriginTag({super.key, required this.origin});
  final QuestionOrigin origin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = switch (origin) {
      QuestionOrigin.manual => c.textMedium,
      QuestionOrigin.generated => c.primary,
      QuestionOrigin.forms || QuestionOrigin.excel => c.success,
      QuestionOrigin.editor => c.textMedium,
    };
    return AppBadgePill(questionOriginLabel(origin), color: tone);
  }
}

/// Move up / move down, the same pair on every row. Null = at that end.
class _MoveButtons extends StatelessWidget {
  const _MoveButtons({required this.onUp, required this.onDown});
  final VoidCallback? onUp, onDown;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        AppIconButton(icon: Icons.arrow_upward_rounded, tooltip: t('تحريك لأعلى', 'Move up'), onPressed: onUp),
        AppIconButton(icon: Icons.arrow_downward_rounded, tooltip: t('تحريك لأسفل', 'Move down'), onPressed: onDown),
      ]);
}

/// Above a written question: where it came from, and moving it in the list.
class CreateEntryStrip extends StatelessWidget {
  const CreateEntryStrip({super.key, required this.origin, required this.onUp, required this.onDown});
  final QuestionOrigin origin;
  final VoidCallback? onUp, onDown;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: QuestionOriginTag(origin: origin))),
        _MoveButtons(onUp: onUp, onDown: onDown),
      ]);
}

/// A question held on the server (an import): its number, type, source, text and marks; moved and removed here, edited
/// in the full editor.
class HeldQuestionCard extends StatelessWidget {
  const HeldQuestionCard({super.key, required this.number, required this.question, required this.onRemove, this.onUp, this.onDown, this.onEdit, this.marks});
  final int number;
  final HeldQuestion question;
  final VoidCallback? onUp, onDown, onRemove, onEdit;

  /// "2 marks", said by the caller (plural rules live with the wizard's texts).
  final String? marks;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = question;
    return AppCard(
      key: ValueKey('create.held.${q.placementId}'),
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('$number', style: AppType.headline(context).copyWith(height: 1, fontFeatures: const [FontFeature.liningFigures()])),
          const SizedBox(width: AppSpace.sm),
          Icon(quickTypeIcon(q.type), size: AppIconSize.sm, color: c.textMedium),
          const SizedBox(width: AppSpace.xxs),
          Expanded(child: Text(quickTypeLabel(q.type), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600))),
          AppIconButton(icon: Icons.delete_outline_rounded, tooltip: t('حذف من الاختبار', 'Remove from the exam'), onPressed: onRemove),
        ]),
        Padding(
          padding: const EdgeInsetsDirectional.only(end: AppSpace.sm),
          child: Text(q.prompt.trim().isEmpty ? t('سؤال بلا نص', 'A question with no text') : q.prompt.trim(),
              maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.body(context).copyWith(color: c.textDark)),
        ),
        const SizedBox(height: AppSpace.xs),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              QuestionOriginTag(origin: q.origin),
              if (marks != null) Text(marks!, style: AppType.meta(context)),
              if (onEdit != null)
                AppButton.ghost(key: ValueKey('create.held.${q.placementId}.edit'), size: AppButtonSize.sm, icon: Icons.edit_outlined, label: t('تعديل في المحرر الكامل', 'Edit in the full editor'), onPressed: onEdit),
            ]),
          ),
          _MoveButtons(onUp: onUp, onDown: onDown),
        ]),
      ]),
    );
  }
}

/// The ready exam paper: a choice of its own, since the file prints as it is and cannot sit beside questions in the app.
/// [usingFile] = chosen now (then the way back is offered).
class CreatePaperFileChoice extends StatelessWidget {
  const CreatePaperFileChoice({super.key, required this.usingFile, required this.onTap, this.questionsKept = 0});
  final bool usingFile;
  final VoidCallback? onTap;

  /// Questions written here, kept for the way back.
  final int questionsKept;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (usingFile) {
      // the way back sits under the banner: its own action slot is too narrow for the label on a phone
      return Column(key: const ValueKey('create.paper_file.on'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppBanner(
        icon: Icons.description_outlined,
        text: questionsKept > 0
            ? t('الامتحان ملف جاهز يُطبع كما هو، فلا تُضاف إليه أسئلة. أسئلتك المكتوبة محفوظة إن رجعت إليها.',
                'The exam is a ready file printed as it is, so no questions are added to it. Your written questions are kept if you go back.')
            : t('الامتحان ملف جاهز يُطبع كما هو، فلا تُضاف إليه أسئلة من التطبيق.', 'The exam is a ready file printed as it is, so questions in the app are not added to it.'),
        ),
        if (onTap != null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppButton.ghost(key: const ValueKey('create.paper_file.back'), size: AppButtonSize.sm, icon: Icons.quiz_outlined, label: t('ارجع إلى أسئلة التطبيق', 'Back to questions in the app'), onPressed: onTap),
          ),
      ]);
    }
    return Material(
      key: const ValueKey('create.paper_file'),
      color: c.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card), side: BorderSide(color: c.divider)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.primary),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Row(children: [
              Icon(Icons.upload_file_rounded, color: onTap == null ? c.textLight : c.textMedium),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('أو استخدم ملف امتحان جاهزًا بدلًا من ذلك', 'Or use a ready exam paper instead'), style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
                  const SizedBox(height: AppSpace.xxs),
                  Text(t('PDF أو Word أو صورة تُطبع كما هي. لا تُجمع مع أسئلة التطبيق', 'A PDF, Word file or photo printed as it is. It is not combined with questions in the app'),
                      style: AppType.meta(context)),
                ]),
              ),
              const SizedBox(width: AppSpace.xs),
              Icon(Icons.chevron_right_rounded, color: c.textLight),
            ]),
          ),
        ),
      ),
    );
  }
}
