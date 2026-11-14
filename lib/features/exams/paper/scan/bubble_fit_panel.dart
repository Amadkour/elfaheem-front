// The resolution panel of "Print bubble sheets" when questions have more choices than the sheet's bubbles (D-720 –
// D-722): which questions, how many choices against the sheet's, and per question (or for all at once) Remove wrong
// choices · Leave off the sheet · Answer on the written sheet, plus Use another sheet. A trim shows which choices go
// and changes nothing before the teacher confirms; a trimmed question is listed with Undo. After a trim or an Undo an
// alert names the questions and the choices and says the question paper changed with it (D-725, `BubbleFitChangesBody`).
// `BubbleFitView` takes plain values (the layout harness pumps it); `BubbleFitSection` owns the calls (bubble_fit.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t, asMap;
import 'package:flutter_education_app/features/exams/paper/bubble/bubble_import_screen.dart' show openBubbleSheetFinder;
import 'package:flutter_education_app/features/exams/paper/exam_setup.dart' show ExamSetupApi, OmrTemplateItem;
import 'package:flutter_education_app/features/exams/paper/scan/bubble_fit.dart';

/// A question's own text keeps its own direction (an English question in the Arabic app reads "Which …?", not "?Which …"),
/// aligned to the page's start.
Text _own(String s, TextStyle style, {int maxLines = 2, Key? key}) {
  var dir = TextDirection.ltr;
  for (final r in s.runes) {
    if ((r >= 0x0590 && r <= 0x08FF) || (r >= 0xFB1D && r <= 0xFDFF) || (r >= 0xFE70 && r <= 0xFEFF)) {
      dir = TextDirection.rtl;
      break;
    }
    if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) break;
  }
  return Text(s, key: key, maxLines: maxLines, overflow: TextOverflow.ellipsis, textDirection: dir,
      textAlign: AppConfig.lang == 'ar' ? TextAlign.right : TextAlign.left, style: style);
}

const _actions = [BubbleFitAction.trim, BubbleFitAction.ignore, BubbleFitAction.written];

IconData _icon(BubbleFitAction a) => switch (a) {
      BubbleFitAction.trim => Icons.content_cut_rounded,
      BubbleFitAction.ignore => Icons.edit_note_rounded,
      BubbleFitAction.written => Icons.assignment_outlined,
      _ => Icons.radio_button_checked_rounded,
    };

/// The panel, plain values.
class BubbleFitView extends StatelessWidget {
  const BubbleFitView({
    super.key,
    required this.fit,
    required this.chosen,
    required this.onChoose,
    required this.onApply,
    this.onAll,
    this.sheets,
    this.onUseSheet,
    this.onOwnSheet,
    this.onRestore,
    this.onDone,
    this.busy = false,
    this.error,
  });

  final BubbleFit fit;
  final Map<int, BubbleFitAction> chosen;
  final void Function(int questionId, BubbleFitAction action) onChoose;
  final ValueChanged<BubbleFitAction>? onAll;
  final VoidCallback? onApply;

  /// The sheets with enough choices; null while they load.
  final List<OmrTemplateItem>? sheets;
  final ValueChanged<OmrTemplateItem>? onUseSheet;
  final VoidCallback? onOwnSheet;
  final ValueChanged<int>? onRestore;

  /// Back to printing: offered once every question has its way (nothing left open).
  final VoidCallback? onDone;
  final bool busy;
  final String? error;

  bool get _changed => fit.items.any((x) => chosen[x.questionId] != null && chosen[x.questionId] != x.choice);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (fit.items.isNotEmpty) AppBanner(icon: Icons.warning_amber_rounded, text: bubbleFitHeadline(fit), color: c.warning),
      if (fit.locked) ...[
        const SizedBox(height: AppSpace.xs),
        AppBanner(
            icon: Icons.lock_outline_rounded,
            text: t('طُبعت أوراق الإجابة أو صُوّرت: يمكن حذف الخيارات الخاطئة فقط، ولا تنتقل الأسئلة بين الأوراق.',
                'Answer sheets were printed or scanned: you can still remove wrong choices, but questions can no longer move between sheets.')),
      ],
      if (fit.items.length > 1 && onAll != null && !fit.locked) ...[
        const SizedBox(height: AppSpace.md),
        Text(t('للأسئلة كلها', 'For all of them'), style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final a in _actions)
            if (a != BubbleFitAction.trim || fit.items.every((x) => x.canTrim))
              AppChoiceChip(
                  key: ValueKey('fit.all.${a.name}'),
                  label: bubbleFitActionTitle(a),
                  icon: _icon(a),
                  selected: fit.items.every((x) => chosen[x.questionId] == a),
                  onTap: () => onAll!(a)),
        ]),
      ],
      for (final x in fit.items) ...[
        const SizedBox(height: AppSpace.sm),
        _ItemCard(item: x, fit: fit, choice: chosen[x.questionId], onChoose: (a) => onChoose(x.questionId, a)),
      ],
      if (fit.items.isNotEmpty) ...[
        if (error != null) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(icon: Icons.error_outline_rounded, text: error!, color: c.danger),
        ],
        const SizedBox(height: AppSpace.md),
        AppPrimaryButton(
            key: const ValueKey('fit.apply'),
            label: t('طبّق الاختيارات', 'Apply these choices'),
            icon: Icons.check_rounded,
            onPressed: busy || !_changed ? null : onApply,
            busy: busy),
      ],
      if (fit.trimmed.isNotEmpty) ...[
        const SizedBox(height: AppSpace.md),
        _TrimmedCard(trimmed: fit.trimmed, onRestore: busy ? null : onRestore),
      ],
      if (onDone != null && fit.items.every((x) => x.choice != null)) ...[
        const SizedBox(height: AppSpace.sm),
        AppButton.secondary(key: const ValueKey('fit.done'), label: t('العودة إلى الطباعة', 'Back to printing'), icon: Icons.print_outlined, onPressed: busy ? null : onDone),
      ],
      if (fit.items.isNotEmpty) ...[
        const SizedBox(height: AppSpace.md),
        _SheetsCard(need: fit.maxOptions, sheets: sheets, onUse: busy ? null : onUseSheet, onOwn: busy ? null : onOwnSheet),
      ],
    ]);
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, required this.fit, required this.choice, required this.onChoose});
  final BubbleFitItem item;
  final BubbleFit fit;
  final BubbleFitAction? choice;
  final ValueChanged<BubbleFitAction> onChoose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    final remove = item.trimRemoves.toSet();
    return Container(
      key: ValueKey('fit.q.${item.questionId}'),
      padding: AppSpace.card,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: choice == null ? c.warning.withValues(alpha: .55) : c.textLight.withValues(alpha: .3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            constraints: const BoxConstraints(minWidth: AppIconSize.xl, minHeight: AppIconSize.xl),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
            decoration: BoxDecoration(color: c.primary.withValues(alpha: .1), borderRadius: AppRadius.cardAll),
            child: Text('${item.number}', style: appText(14, w: FontWeight.w800, c: appInk(context, c.primary))),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                  width: double.infinity,
                  child: _own(item.prompt.isEmpty ? t('السؤال ${item.number}', 'Question ${item.number}') : item.prompt,
                      appText(14, w: FontWeight.w700, c: c.textDark, h: 1.35))),
              const SizedBox(height: 2),
              Text(bubbleFitCountLine(item, fit.sheetOptions), style: appText(12.5, w: FontWeight.w600, c: c.danger)),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final a in _actions)
            if ((a != BubbleFitAction.trim || item.canTrim) && (a == BubbleFitAction.trim || !fit.locked || item.choice == a))
              AppChoiceChip(
                  key: ValueKey('fit.q.${item.questionId}.${a.name}'),
                  label: bubbleFitActionTitle(a),
                  icon: _icon(a),
                  selected: choice == a,
                  onTap: () => onChoose(a)),
        ]),
        if (!item.canTrim) ...[
          const SizedBox(height: AppSpace.xs),
          Text(t('لا يمكن حذف خيارات منه: إجاباته الصحيحة وحدها أكثر من فقاعات الورقة.', 'Its choices cannot be trimmed: its correct answers alone need more bubbles.'),
              style: appText(12.5, c: c.textMedium, h: 1.35)),
        ],
        if (choice != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text(bubbleFitActionLine(choice!, onNb2: fit.onNb2, sheetOptions: fit.sheetOptions), style: appText(12.5, c: c.textMedium, h: 1.4)),
        ],
        if (choice == BubbleFitAction.trim) ...[
          const SizedBox(height: AppSpace.xs),
          for (var i = 0; i < item.options.length; i++)
            _OptionRow(letter: bubbleFitLetter(i, ar: ar), option: item.options[i], removed: remove.contains(item.options[i].id)),
        ],
      ]),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.letter, required this.option, required this.removed});
  final String letter;
  final BubbleFitOption option;
  final bool removed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = appText(13, c: removed ? c.textMedium : c.textDark, h: 1.35);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: AppSpace.lg, child: Text(letter, style: style.copyWith(fontWeight: FontWeight.w700))),
        Flexible(child: _own(option.text.isEmpty ? '—' : option.text, removed ? style.copyWith(decoration: TextDecoration.lineThrough, decorationColor: c.danger) : style)),
        const SizedBox(width: AppSpace.xs),
        if (removed)
          AppTag(t('يُحذف', 'Removed'), c.danger)
        else if (option.correct)
          Semantics(label: t('الإجابة الصحيحة', 'Correct answer'), child: Icon(Icons.check_circle_rounded, size: AppIconSize.sm, color: c.success)),
      ]),
    );
  }
}

class _TrimmedCard extends StatelessWidget {
  const _TrimmedCard({required this.trimmed, this.onRestore});
  final List<BubbleFitTrimmed> trimmed;
  final ValueChanged<int>? onRestore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t('أسئلة حُذفت منها خيارات', 'Questions with choices removed'), style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
        const SizedBox(height: AppSpace.xxs),
        Text(t('أعد طباعة ورقة الأسئلة. التراجع متاح ما لم تُسجَّل إجابات.', 'Print the question paper again. Undo works until answers come in.'),
            style: appText(12.5, c: c.textMedium, h: 1.35)),
        for (final x in trimmed)
          Row(children: [
            Expanded(
              child: Text(
                  x.removedOptions.isEmpty
                      ? '${t('السؤال ${x.number}', 'Question ${x.number}')} · ${countText(x.removed.length, ar1: 'خيار محذوف', ar2: 'خياران محذوفان', arFew: '{n} خيارات محذوفة', arMany: '{n} خيارًا محذوفًا', en1: '1 choice removed', en: '{n} choices removed')}'
                      : bubbleFitChangeLine(BubbleFitChange(questionId: x.questionId, number: x.number, restored: false, removed: x.removedOptions),
                          ar: AppConfig.lang == 'ar'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: appText(13, c: c.textDark)),
            ),
            AppButton.ghost(
                key: ValueKey('fit.restore.${x.questionId}'),
                label: t('تراجع', 'Undo'),
                icon: Icons.undo_rounded,
                onPressed: onRestore == null ? null : () => onRestore!(x.questionId)),
          ]),
      ]),
    );
  }
}

class _SheetsCard extends StatelessWidget {
  const _SheetsCard({required this.need, required this.sheets, this.onUse, this.onOwn});
  final int need;
  final List<OmrTemplateItem>? sheets;
  final ValueChanged<OmrTemplateItem>? onUse;
  final VoidCallback? onOwn;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = sheets;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.swap_horiz_rounded, color: appInk(context, c.primary)),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(t('أو استخدم ورقة أخرى', 'Or use another sheet'), style: appText(13.5, w: FontWeight.w700, c: c.textDark))),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Text(t('ورقة فيها $need خيارات على الأقل لكل سؤال: تبقى الأسئلة كما هي.', 'A sheet with at least $need choices per question: the questions stay as they are.'),
            style: appText(12.5, c: c.textMedium, h: 1.35)),
        const SizedBox(height: AppSpace.xs),
        if (list == null)
          const AppListSkeleton(items: 1, padding: EdgeInsets.zero)
        else if (list.isEmpty)
          Text(t('لا توجد في المكتبة ورقة بهذا العدد من الخيارات.', 'No sheet in the library has that many choices.'), style: appText(12.5, c: c.textMedium))
        else
          for (final s in list.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xxs),
              child: Row(children: [
                Expanded(
                  child: Text(
                      '${s.name} · ${t('${s.questions} سؤال · ${s.options} خيارات', '${s.questions} questions · ${s.options} choices')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: appText(13, c: c.textDark)),
                ),
                const SizedBox(width: AppSpace.xs),
                AppButton.secondary(key: ValueKey('fit.sheet.${s.id}'), label: t('استخدمها', 'Use it'), onPressed: onUse == null ? null : () => onUse!(s)),
              ]),
            ),
        if (onOwn != null || list != null) ...[
          const SizedBox(height: AppSpace.xxs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.ghost(
                key: const ValueKey('fit.own'), label: t('أضف ورقتك الخاصة', 'Add your own sheet'), icon: Icons.add_photo_alternate_outlined, onPressed: onOwn),
          ),
        ],
      ]),
    );
  }
}

/// The alert's body after a trim or an Undo (D-725), plain values: what changed per question, what follows it, and
/// "print the question paper again".
class BubbleFitChangesBody extends StatelessWidget {
  const BubbleFitChangesBody({super.key, required this.changes});
  final List<BubbleFitChange> changes;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    final restored = changes.every((x) => x.restored);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (final x in changes)
        Padding(
          key: ValueKey('fit.change.${x.questionId}'),
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(x.restored ? Icons.undo_rounded : Icons.content_cut_rounded, size: AppIconSize.sm, color: appInk(context, x.restored ? c.primary : c.danger)),
            ),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(bubbleFitChangeLine(x, ar: ar), style: appText(14, w: FontWeight.w600, c: c.textDark, h: 1.4))),
          ]),
        ),
      const SizedBox(height: AppSpace.xxs),
      Text(bubbleFitChangesFollow(changes), style: appText(13, c: c.textMedium, h: 1.45)),
      const SizedBox(height: AppSpace.sm),
      AppBanner(key: const ValueKey('fit.change.reprint'), icon: Icons.print_outlined, text: bubbleFitReprintLine(changes), color: restored ? null : c.warning),
    ]);
  }
}

/// The alert after a trim or an Undo. Resolves when the teacher closes it.
Future<void> showBubbleFitChanges(BuildContext context, List<BubbleFitChange> changes) => showAppDialog<void>(
      context,
      title: bubbleFitChangesTitle(changes),
      icon: Icons.description_outlined,
      body: BubbleFitChangesBody(changes: changes),
      actions: [
        Builder(
            builder: (ctx) => AppButton.primary(
                key: const ValueKey('fit.change.ok'), label: t('حسنًا', 'Got it'), icon: Icons.check_rounded, onPressed: () => Navigator.pop(ctx))),
      ],
    );

/// The panel with its calls. [onResolved]: the sheet can print now (every question has a way, or the sheet changed).
class BubbleFitSection extends StatefulWidget {
  const BubbleFitSection({super.key, required this.examId, required this.onResolved, this.api, this.setupApi, this.bubbleQuestions = 0});
  final int examId;
  final VoidCallback onResolved;
  final BubbleFitApi? api;
  final ExamSetupApi? setupApi;

  /// How many questions go on the sheet (another sheet needs that many rows); 0 = unknown.
  final int bubbleQuestions;

  @override
  State<BubbleFitSection> createState() => _BubbleFitSectionState();
}

class _BubbleFitSectionState extends State<BubbleFitSection> {
  late final BubbleFitApi _api = widget.api ?? BubbleFitApi();
  late final ExamSetupApi _setup = widget.setupApi ?? ExamSetupApi();
  BubbleFit? _fit;
  final Map<int, BubbleFitAction> _chosen = {};
  List<OmrTemplateItem>? _sheets;
  String? _loadError;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _take(BubbleFit f) {
    _fit = f;
    _chosen
      ..clear()
      ..addAll({for (final x in f.items) if (x.choice != null) x.questionId: x.choice!});
  }

  Future<void> _load() async {
    final r = await _api.get(widget.examId);
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _loadError = bubbleFitCodeText(r));
      return;
    }
    final f = BubbleFit.fromJson(r.map);
    setState(() => _take(f));
    if (f.items.isEmpty && f.trimmed.isEmpty) {
      widget.onResolved();
      return;
    }
    final s = await _setup.templates(orgId: f.orgId);
    if (!mounted) return;
    final items = [for (final m in (s.ok && s.map['items'] is List ? s.map['items'] as List : const [])) if (m is Map) OmrTemplateItem.fromJson(asMap(m))];
    setState(() => _sheets = bubbleFitSheets([for (final x in items) if (x.status == 'published') x],
        options: f.maxOptions, questions: widget.bubbleQuestions, current: f.templateId));
  }

  Future<void> _apply() async {
    final f = _fit!;
    final body = bubbleFitBody(f, _chosen);
    final trims = [for (final x in f.items) if (_chosen[x.questionId] == BubbleFitAction.trim && x.choice != BubbleFitAction.trim) x];
    if (trims.isNotEmpty) {
      final ar = AppConfig.lang == 'ar';
      final lines = [
        for (final x in trims)
          '${t('السؤال ${x.number}', 'Question ${x.number}')}: ${[for (var i = 0; i < x.options.length; i++) if (x.trimRemoves.contains(x.options[i].id)) bubbleFitLetter(i, ar: ar)].join('، ')}',
      ];
      final ok = await appConfirm(context,
          message: '${t('ستُحذف هذه الخيارات الخاطئة:', 'These wrong choices will be removed:')}\n${lines.join('\n')}\n\n'
              '${t('الإجابة الصحيحة تبقى. يمكنك التراجع هنا ما لم تُسجَّل إجابات، وأعد طباعة ورقة الأسئلة.', 'The correct answer stays. You can undo it here until answers come in; print the question paper again.')}',
          confirmLabel: t('احذفها', 'Remove them'));
      if (!ok || !mounted) return;
    }
    await _send(body);
  }

  Future<void> _send(Map<String, dynamic> body) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _api.put(widget.examId, body);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = false;
        _error = bubbleFitCodeText(r);
      });
      return;
    }
    final f = BubbleFit.fromJson(r.map);
    setState(() {
      _busy = false;
      _take(f);
    });
    final changes = bubbleFitChangesOf(r.map);
    if (changes.isNotEmpty) {
      await showBubbleFitChanges(context, changes);
      if (!mounted) return;
    }
    if (f.items.every((x) => x.choice != null)) {
      showAppNotice(t('جاهزة للطباعة', 'Ready to print'));
      widget.onResolved();
    }
  }

  Future<void> _restore(int questionId) => _send({'questions': {'$questionId': BubbleFitAction.restore.name}});

  Future<void> _useSheet(OmrTemplateItem s) async {
    final ok = await appConfirm(context,
        message: t('استخدام الورقة "${s.name}" لهذا الاختبار؟ تبقى الأسئلة كما هي.', 'Use the sheet "${s.name}" for this exam? The questions stay as they are.'),
        confirmLabel: t('استخدمها', 'Use it'));
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final r = await _setup.putSetup(widget.examId, {'omr_template_id': s.id});
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!r.ok) _error = bubbleFitCodeText(r);
    });
    if (r.ok) widget.onResolved();
  }

  Future<void> _ownSheet() async {
    final s = await openBubbleSheetFinder(context, orgId: _fit?.orgId);
    if (s != null && mounted) await _useSheet(s);
  }

  @override
  Widget build(BuildContext context) {
    final f = _fit;
    if (_loadError != null) return AppBanner(icon: Icons.error_outline_rounded, text: _loadError!, color: context.colors.danger);
    if (f == null) return const AppListSkeleton(items: 2, padding: EdgeInsets.zero);
    return BubbleFitView(
      fit: f,
      chosen: _chosen,
      onChoose: (q, a) => setState(() => _chosen[q] = a),
      onAll: (a) => setState(() {
        for (final x in f.items) {
          _chosen[x.questionId] = a;
        }
      }),
      onApply: _apply,
      sheets: _sheets,
      onUseSheet: _useSheet,
      onOwnSheet: _ownSheet,
      onRestore: _restore,
      onDone: widget.onResolved,
      busy: _busy,
      error: _error,
    );
  }
}
