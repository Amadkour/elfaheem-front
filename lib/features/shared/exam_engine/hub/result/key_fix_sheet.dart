// Fix the key (D-664, D-666): the results' "Check these keys" card, the sheet that picks the right answer (with what the
// class and the top group chose) and the confirm (it changes marks). The fix is one synchronous call that marks every
// answer again (key_fix.dart), so the flow ends with a notice saying what moved. Pure part: key_fix.dart.
// Plain-value widgets (the layout harness pumps them): ResultKeyCheckCard · KeyFixSheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../../../admin/admin_common.dart' show t;
import '../../exam_insights.dart' show itemFlagText;
import 'key_fix.dart';

/// The whole flow for one question: pick → confirm → fix (every answer is marked again in the same call). True when the
/// key was saved, so the caller reloads its marks.
Future<bool> openKeyFix(BuildContext context, {required int examId, required KeyFixCandidate question, KeyFixApi? api}) async {
  final a = api ?? KeyFixApi();
  final picked = await showAppSheet<Set<String>>(context, (_) => KeyFixSheet(question: question));
  if (picked == null || !context.mounted) return false;
  final ok = await appConfirm(context, danger: true, message: keyFixConfirmText, confirmLabel: t('حفظ وإعادة التصحيح', 'Save and mark again'));
  if (!ok || !context.mounted) return false;
  final r = await a.fixKey(examId, question.questionId, keyFixRequest(question, picked, reason: '${t('تحليل الأسئلة', 'Item analysis')}: ${question.reason}'));
  if (!r.ok) {
    showAppNotice(keyFixErrorText(r), error: true);
    return false;
  }
  showAppNotice(keyFixOutcomeText(KeyFixOutcome.fromJson(r.map)));
  return true;
}

/// "Check these keys": the questions the analysis flagged, each with Fix the key.
class ResultKeyCheckCard extends StatelessWidget {
  const ResultKeyCheckCard({super.key, required this.questions, this.onFix});
  final List<KeyFixCandidate> questions;
  final ValueChanged<KeyFixCandidate>? onFix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      key: const ValueKey('result.keys'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('راجع هذه المفاتيح', 'Check these keys'), style: AppType.section(context)),
        const SizedBox(height: AppSpace.xxs),
        Text(t('أشار تحليل الأسئلة إلى أن مفتاحها قد يكون خاطئًا أو أن السؤال ملتبس.', 'The item analysis says their key may be wrong or the question unclear.'),
            style: AppType.meta(context).copyWith(height: 1.4)),
        for (final q in questions.take(5))
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${t('سؤال', 'Question')} ${q.n}', style: AppType.bodyStrong(context)),
              if (q.prompt.trim().isNotEmpty) Text(q.prompt.trim(), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              const SizedBox(height: AppSpace.xxs),
              // a wrap, not a row: on a phone the button goes under the reason instead of squeezing it
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                AppStatusBadge(dense: true, label: q.reason, tone: q.flags.contains('negative') || q.flags.contains('key_suspect') ? AppTone.danger : AppTone.warning),
                AppButton.tonal(
                    key: ValueKey('result.keys.fix.${q.questionId}'),
                    label: t('تصحيح المفتاح', 'Fix the key'),
                    icon: Icons.key_rounded,
                    onPressed: onFix == null ? null : () => onFix!(q)),
              ]),
            ]),
          ),
        if (questions.length > 5)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Text(t('والمزيد في تحليل الأسئلة.', 'More in the item analysis.'), style: AppType.meta(context).copyWith(color: c.textLight)),
          ),
      ]),
    );
  }
}

/// Picks the right answer; pops the picked ids.
class KeyFixSheet extends StatefulWidget {
  const KeyFixSheet({super.key, required this.question});
  final KeyFixCandidate question;

  @override
  State<KeyFixSheet> createState() => _KeyFixSheetState();
}

class _KeyFixSheetState extends State<KeyFixSheet> {
  late Set<String> _picked = {...widget.question.correct};

  void _tap(String id) => setState(() {
        if (widget.question.multi) {
          _picked = _picked.contains(id) ? ({..._picked}..remove(id)) : {..._picked, id};
        } else {
          _picked = {id};
        }
      });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = widget.question;
    String pct(double v) => '${(v * 100).round()}%';
    return AppSheetContent(title: '${t('تصحيح مفتاح السؤال', 'Fix the key of question')} ${q.n}', children: [
      if (q.prompt.trim().isNotEmpty) Text(q.prompt.trim(), style: AppType.body(context)),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final f in q.flags) AppStatusBadge(dense: true, label: itemFlagText(f), tone: f == 'negative' || f == 'key_suspect' ? AppTone.danger : AppTone.warning),
      ]),
      const SizedBox(height: AppSpace.sm),
      Text(q.multi ? t('اختر كل الإجابات الصحيحة', 'Pick every correct answer') : t('اختر الإجابة الصحيحة', 'Pick the correct answer'),
          style: AppType.label(context).copyWith(fontWeight: FontWeight.w600)),
      for (final o in q.options)
        InkWell(
          key: ValueKey('keyfix.option.${o.id}'),
          onTap: () => _tap(o.id),
          borderRadius: AppRadius.cardAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs, horizontal: AppSpace.xxs),
            child: Row(children: [
              Icon(
                _picked.contains(o.id)
                    ? (q.multi ? Icons.check_box_rounded : Icons.radio_button_checked_rounded)
                    : (q.multi ? Icons.check_box_outline_blank_rounded : Icons.radio_button_unchecked_rounded),
                color: _picked.contains(o.id) ? appInk(context, c.primary) : c.textLight,
                size: AppIconSize.lg,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.text, style: AppType.body(context)),
                  if (o.share != null)
                    Text(
                        o.upperShare == null
                            ? t('اختاره ${pct(o.share!)}', '${pct(o.share!)} chose it')
                            : t('اختاره ${pct(o.share!)} · ${pct(o.upperShare!)} من الأعلى درجات', '${pct(o.share!)} chose it · ${pct(o.upperShare!)} of the top group'),
                        style: AppType.meta(context).copyWith(color: c.textLight)),
                ]),
              ),
              if (q.correct.contains(o.id)) ...[
                const SizedBox(width: AppSpace.xs),
                AppStatusBadge(dense: true, label: t('المفتاح الحالي', 'Current key'), tone: AppTone.neutral),
              ],
            ]),
          ),
        ),
      const SizedBox(height: AppSpace.sm),
      AppPrimaryButton(
        key: const ValueKey('keyfix.continue'),
        label: t('متابعة', 'Continue'),
        icon: Icons.arrow_forward_rounded,
        onPressed: keyFixReady(q, _picked) ? () => Navigator.of(context).pop(_picked) : null,
      ),
    ]);
  }
}
