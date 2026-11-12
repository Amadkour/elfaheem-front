// Fix the key (D-664): the results' "Check these keys" card, the sheet that picks the right answer (with what the class
// and the top group chose), the confirm (it changes marks) and the re-marking progress, which follows `job_updated`
// through JobWatch with a slow poll of the question's open answers as the fallback. Pure part: key_fix.dart.
// Plain-value widgets (the layout harness pumps them): ResultKeyCheckCard · KeyFixSheet · KeyFixProgressView.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../../../admin/admin_common.dart' show asInt, t;
import '../../exam_insights.dart' show itemFlagText;
import 'key_fix.dart';

/// The whole flow for one question: pick → confirm → save the key → regrade → follow it. True when the key was saved.
Future<bool> openKeyFix(BuildContext context, {required int examId, required KeyFixCandidate question, KeyFixApi? api}) async {
  final a = api ?? KeyFixApi();
  final picked = await showAppSheet<Set<String>>(context, (_) => KeyFixSheet(question: question));
  if (picked == null || !context.mounted) return false;
  final ok = await appConfirm(context, danger: true, message: keyFixConfirmText, confirmLabel: t('حفظ وإعادة التصحيح', 'Save and mark again'));
  if (!ok || !context.mounted) return false;
  final saved = await a.saveKey(question.questionId, keyFixBody(question, picked));
  if (!saved.ok) {
    showAppNotice(keyFixErrorText(saved), error: true);
    return false;
  }
  final rg = await a.regrade(examId, question.questionId);
  if (!rg.ok) {
    showAppNotice('${t('حُفظ المفتاح، ولم تبدأ إعادة التصحيح:', 'The key is saved, but marking again did not start:')} ${keyFixErrorText(rg)}', error: true);
    return true;
  }
  final attempts = asInt(rg.map['attempts']);
  if (attempts == 0) {
    showAppNotice(keyFixNothingText);
    return true;
  }
  if (!context.mounted) return true;
  final finished = await _follow(context, a, examId, question.questionId, attempts);
  showAppNotice(finished ? keyFixDoneText(attempts) : t('يستمر التصحيح في الخلفية، وتظهر الدرجات الجديدة عند انتهائه.', 'Marking carries on in the background; the new marks appear when it ends.'));
  return true;
}

/// Shows the progress until no answer of the question waits for the grader (or the teacher leaves it running).
Future<bool> _follow(BuildContext context, KeyFixApi api, int examId, int questionId, int attempts) async {
  final progress = ValueNotifier<int?>(null);
  var stop = false, finished = false;
  final watch = JobWatch();
  final closed = Completer<void>();
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ValueListenableBuilder<int?>(
      valueListenable: progress,
      builder: (_, waiting, _) => KeyFixProgressView(attempts: attempts, waiting: waiting, onBackground: () {
        stop = true;
        Navigator.of(context, rootNavigator: true).pop();
      }),
    ),
  ).whenComplete(closed.complete));
  try {
    for (var i = 0; i < 40 && !stop; i++) {
      final r = await api.openAnswers(examId, questionId);
      if (r.ok) {
        final left = keyFixWaiting(r.map);
        progress.value = left;
        if (left == 0) {
          finished = true;
          break;
        }
      }
      await watch.next(const Duration(seconds: 3), fallbackEvery: const Duration(seconds: 6));
    }
  } finally {
    watch.dispose();
    if (!stop && context.mounted) Navigator.of(context, rootNavigator: true).pop();
    await closed.future;
  }
  return finished;
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

/// The re-marking under way: how many answers still wait ([waiting] null = not read yet).
class KeyFixProgressView extends StatelessWidget {
  const KeyFixProgressView({super.key, required this.attempts, this.waiting, this.onBackground});
  final int attempts;
  final int? waiting;
  final VoidCallback? onBackground;

  @override
  Widget build(BuildContext context) {
    final w = waiting;
    return PopScope(
      canPop: false,
      child: Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppWidth.form.max),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(keyFixQueuedText(attempts), style: AppType.section(context)),
              const SizedBox(height: AppSpace.sm),
              AppProgressBar(value: w == null || attempts <= 0 ? null : ((attempts - w).clamp(0, attempts) / attempts) * 100, height: AppSpace.xs),
              const SizedBox(height: AppSpace.xs),
              Text(
                  w == null
                      ? t('يبدأ المصحح الآلي ...', 'The grader is starting ...')
                      : countText(w, ar1: 'إجابة واحدة بانتظار المصحح', ar2: 'إجابتان بانتظار المصحح', arFew: '{n} إجابات بانتظار المصحح', arMany: '{n} إجابة بانتظار المصحح',
                          en1: '1 answer waiting for the grader', en: '{n} answers waiting for the grader'),
                  style: AppType.meta(context)),
              const SizedBox(height: AppSpace.xs),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(key: const ValueKey('keyfix.background'), onPressed: onBackground, child: Text(t('متابعة في الخلفية', 'Keep it running'))),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
