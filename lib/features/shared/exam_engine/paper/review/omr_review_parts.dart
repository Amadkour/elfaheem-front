// The review queue's plain-value widgets (brief 4.4, Examples 6 and 7): the kind filter with counts, the item card
// (the cropped region next to the system's reading and why it is here, and the one-click fix of its kind), the
// queue list, the score line after a fix and the full paper with the detected answers drawn over it. They read no
// provider and call no API, so test/org/omr_review_test.dart pumps them under the layout harness.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_bidi.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import '../../../../admin/admin_common.dart' show t;
import '../scan/omr_scan.dart' show OmrReplaceResult;
import 'omr_review.dart';
import 'omr_review_written.dart';
import '../omr_counts.dart';

IconData omrKindIcon(String kind) => switch (kind) {
      'identifier' => Icons.badge_outlined,
      'form' => Icons.qr_code_2_rounded,
      'bubble' => Icons.radio_button_checked_rounded,
      'handwriting' || 'completion' => Icons.draw_outlined,
      'short_answer' => Icons.notes_rounded,
      'quality' => Icons.image_search_rounded,
      _ => Icons.help_outline_rounded,
    };

// ── filter ──────────────────────────────────────────────────────────────────────────────────────────────────────

/// "All 7 · Student ID 2 · Form 1 · Answers 3 · Image quality 1 · Resolved". [selected] is a kind, null (all open)
/// or `resolved`.
class OmrKindFilter extends StatelessWidget {
  const OmrKindFilter({super.key, required this.list, required this.selected, required this.onPick});
  final OmrReviewList list;
  final String? selected;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
      AppChoiceChip(
          key: const ValueKey('omr.filter.all'),
          label: t('الكل · ${list.openTotal}', 'All · ${list.openTotal}'),
          icon: Icons.inbox_rounded,
          selected: selected == null,
          onTap: () => onPick(null)),
      for (final k in list.kinds)
        AppChoiceChip(
            key: ValueKey('omr.filter.$k'),
            label: '${omrKindLabel(k)} · ${list.openByKind[k] ?? 0}',
            icon: omrKindIcon(k),
            selected: selected == k,
            onTap: () => onPick(k)),
      AppChoiceChip(
          key: const ValueKey('omr.filter.resolved'),
          label: t('تمت مراجعته', 'Resolved'),
          icon: Icons.history_rounded,
          selected: selected == 'resolved',
          onTap: () => onPick('resolved')),
    ]);
  }
}

// ── images ──────────────────────────────────────────────────────────────────────────────────────────────────────

/// The cropped region of the sheet (a framed white card: the paper stays paper in dark mode).
class OmrCropView extends StatelessWidget {
  const OmrCropView({super.key, required this.bytes, this.loading = false, this.maxHeight = 220, this.label});
  final Uint8List? bytes;
  final bool loading;
  final double maxHeight;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget body;
    if (loading) {
      body = const AppSkeletonBox(height: 96);
    } else if (bytes == null || bytes!.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.hide_image_outlined, color: c.textLight, size: 20),
          const SizedBox(width: AppSpace.xs),
          Flexible(child: Text(t('صورة الجزء غير متاحة', 'The cropped image is not available'), style: appText(13, c: c.textMedium))),
        ]),
      );
    } else {
      body = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Image.memory(bytes!, fit: BoxFit.contain, gaplessPlayback: true, filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Text(t('تعذّر عرض الصورة', 'The image could not be shown'), style: appText(13, c: c.textMedium)))),
      );
    }
    return Semantics(
      image: true,
      label: label ?? t('الجزء المقصوص من الورقة', 'The cropped part of the sheet'),
      child: Container(
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(AppSpace.xs),
        decoration: BoxDecoration(
          color: loading || bytes == null ? c.inputBg : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: c.divider),
        ),
        child: body,
      ),
    );
  }
}

// ── the item card ───────────────────────────────────────────────────────────────────────────────────────────────

/// What a fix sends back to the page (which calls the server).
class OmrFixCallbacks {
  const OmrFixCallbacks({
    this.onChoose,
    this.onBlank,
    this.onAccept,
    this.onFix,
    this.onAssign,
    this.onSearch,
    this.onConfirmForm,
    this.onDismiss,
    this.onReplace,
    this.onOpenPaper,
    this.onSetScore,
    this.onFixText,
    this.onReplacePage,
    this.onNewStudent,
  });

  final ValueChanged<List<String>>? onChoose;
  final VoidCallback? onBlank;
  final VoidCallback? onAccept;
  final ValueChanged<String>? onFix;
  final ValueChanged<OmrStudent>? onAssign;

  /// Searches the exam's students; null result = the search is not available here (type the student's number).
  final Future<List<OmrStudent>?> Function(String query)? onSearch;
  final ValueChanged<String>? onConfirmForm;
  final VoidCallback? onDismiss;
  final VoidCallback? onReplace;
  final VoidCallback? onOpenPaper;

  /// Handwritten answers: set the score (0 … points, step 0.5) / fix the recognised text (one text per blank).
  final ValueChanged<double>? onSetScore;
  final ValueChanged<List<String>>? onFixText;

  /// Image quality: a clearer image of the page, through the same replace flow as the batch page (the page's open
  /// items close as "replaced" once the gate accepts it).
  final VoidCallback? onReplacePage;

  /// D-672, a correction with no course: the paper's student is a new one, typed (name, ID; either may be empty).
  final void Function(String name, String code)? onNewStudent;
}

/// One review item: the crop next to the system's reading, why it is here, and its one-click fix.
class OmrReviewItemCard extends StatelessWidget {
  const OmrReviewItemCard({
    super.key,
    required this.item,
    required this.crop,
    this.cropLoading = false,
    this.busy = false,
    this.fix = const OmrFixCallbacks(),
    this.picked = const {},
    this.onToggle,
    this.position,
    this.meId,
  });

  final OmrReviewItem item;
  final Uint8List? crop;
  final bool cropLoading;
  final bool busy;
  final OmrFixCallbacks fix;

  /// mcq_multi: the letters ticked so far (the page owns them, so the keyboard can tick too).
  final Set<String> picked;
  final ValueChanged<String>? onToggle;

  /// "3 of 7".
  final String? position;
  final int? meId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final head = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: c.warning.withValues(alpha: .14), borderRadius: BorderRadius.circular(AppRadius.chip)),
        child: Icon(omrKindIcon(item.kind), color: c.warning, size: 22),
      ),
      const SizedBox(width: AppSpace.sm),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.reason, key: const ValueKey('omr.item.reason'), style: appText(16, w: FontWeight.w700, c: c.textDark)),
          const SizedBox(height: 2),
          Text(_where(), style: appText(12.5, c: c.textMedium)),
          // which paper: "Page 3 · wa01.jpg · Today, 10:42 AM" (two items of one kind told apart)
          if (item.whereText.isNotEmpty) Text(item.whereText, key: const ValueKey('omr.item.where'), style: appText(12, c: c.textLight)),
          if (item.detail != null && item.open) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(item.detail!, key: const ValueKey('omr.item.detail'), style: appText(13, c: c.textDark, h: 1.35)),
          ],
        ]),
      ),
      if (position != null) ...[const SizedBox(width: AppSpace.xs), AppBadgePill(position!, color: c.textMedium)],
    ]);
    final reading = _ReadingBlock(item: item);
    final fixBody = item.open ? _fixFor(context) : OmrResolvedNote(item: item, meId: meId);
    return AppCard(
      key: ValueKey('omr.item.${item.id}'),
      padding: AppSpace.card,
      child: AbsorbPointer(
        absorbing: busy,
        child: AnimatedOpacity(
          opacity: busy ? .6 : 1,
          duration: AppMotion.of(context).fast,
          child: LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 640;
            final cropView = OmrCropView(bytes: crop, loading: cropLoading, maxHeight: wide ? 240 : 180);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              head,
              const SizedBox(height: AppSpace.md),
              if (wide)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 5, child: cropView),
                  const SizedBox(width: AppSpace.md),
                  Expanded(flex: 4, child: reading),
                ])
              else ...[cropView, const SizedBox(height: AppSpace.sm), reading],
              const SizedBox(height: AppSpace.md),
              Divider(height: 1, color: c.divider),
              const SizedBox(height: AppSpace.md),
              fixBody,
              if (fix.onOpenPaper != null && item.scanPageId != null) ...[
                const SizedBox(height: AppSpace.xs),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey('omr.item.paper'),
                    onPressed: fix.onOpenPaper,
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: Text(t('عرض الورقة كاملة', 'View the whole paper')),
                  ),
                ),
              ],
            ]);
          }),
        ),
      ),
    );
  }

  /// "Sara Mahmoud · Answers · Question 3 · 1 pt" — what it is and whose.
  String _where() {
    final parts = <String>[
      ?item.studentText,
      omrKindLabel(item.kind),
      if (item.kind == 'bubble' && item.n != null) t('السؤال ${item.n}', 'Question ${item.n}'),
      if (item.question != null) omrPointsText(item.question!.points),
    ];
    return parts.join(' · ');
  }

  Widget _fixFor(BuildContext context) => switch (item.kind) {
        'bubble' when item.code == 'key_missing' => const OmrKeyMissingFix(),
        'bubble' => OmrBubbleFix(item: item, picked: picked, onToggle: onToggle, onChoose: fix.onChoose, onBlank: fix.onBlank),
        'identifier' => OmrIdentifierFix(key: ValueKey('omr.idfix.${item.id}'), item: item, fix: fix),
        'form' => OmrFormFix(item: item, onConfirm: fix.onConfirmForm, onDismiss: fix.onDismiss),
        'completion' || 'short_answer' => OmrWrittenFix(
            // a fresh reading (matched again / recomputed) starts a fresh form
            key: ValueKey('omr.wfix.${item.id}.${item.writtenText.hashCode}.${item.pending}.${item.suggestedScore}'),
            item: item,
            onAccept: fix.onAccept,
            onSetScore: fix.onSetScore,
            onFixText: fix.onFixText),
        // image quality (and a kind the app does not know yet): Replace this page, or set it aside
        _ => OmrDismissFix(item: item, onDismiss: fix.onDismiss, onReplacePage: item.kind == 'quality' && item.scanPageId != null ? fix.onReplacePage : null),
      };
}

/// What the system read, in words and numbers (the fill of each bubble; the digits with their confidence; the
/// markers; the quality instruction).
class _ReadingBlock extends StatelessWidget {
  const _ReadingBlock({required this.item});
  final OmrReviewItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = Text(t('ما قرأه النظام', 'What the system read'), style: appText(12.5, w: FontWeight.w700, c: c.textMedium));
    final List<Widget> body;
    switch (item.kind) {
      case 'completion' || 'short_answer':
        body = [OmrWrittenReading(item: item)];
      case 'bubble':
        final fills = item.fills;
        body = [
          Text(item.selected.isEmpty ? t('لا تظليل واضح', 'No clear mark') : t('مظلّل: ${item.selected.join('، ')}', 'Shaded: ${item.selected.join(', ')}'),
              style: appText(15, w: FontWeight.w600, c: c.textDark)),
          const SizedBox(height: AppSpace.xs),
          for (final l in item.letters)
            if (fills.containsKey(l)) _FillRow(letter: l, fill: fills[l]!, marked: item.selected.contains(l)),
        ];
      case 'identifier':
        final cands = item.candidates;
        final graded = item.code == 'student_already_scanned' ? item.gradedStudentText : null;
        final gradedPage = item.code == 'student_already_scanned' ? item.gradedPageText : null;
        body = [
          if (item.readValue.isNotEmpty)
            Directionality(textDirection: TextDirection.ltr, child: Text(item.readValue, style: appText(18, w: FontWeight.w700, c: c.textDark)))
          // a duplicate found by its QR code names its student below: "no number" would only distract there
          else if (graded == null)
            Text(t('تعذّرت قراءة أي رقم', 'No number could be read'),
                key: const ValueKey('omr.id.nothingRead'), style: appText(15, w: FontWeight.w600, c: c.textDark)),
          if (!item.nothingRead && item.digits.any((d) => d.confidence != null)) ...[const SizedBox(height: AppSpace.xs), OmrDigitsRow(digits: item.digits)],
          if (cands.length > 1 && item.code == 'identifier_duplicate') ...[
            const SizedBox(height: AppSpace.xs),
            Text(t('${omrStudentsText(cands.length)} لديهم هذا الرقم', '${cands.length} students have this ID'), style: appText(13, c: c.textMedium)),
          ],
          if (item.namedText != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(t('الطالب على الورقة', 'The student on the sheet'), style: appText(12.5, w: FontWeight.w700, c: c.textMedium)),
            Text(item.namedText!, key: const ValueKey('omr.id.named'), style: appText(15, w: FontWeight.w700, c: c.textDark)),
          ],
          if (graded != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(t('مصحّحة بالفعل للطالب', 'Already graded for'), style: appText(12.5, w: FontWeight.w700, c: c.textMedium)),
            Text(graded, key: const ValueKey('omr.dup.student'), style: appText(15, w: FontWeight.w700, c: c.textDark)),
          ],
          if (gradedPage != null) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(t('الورقة المصحّحة: $gradedPage', 'The graded sheet: $gradedPage'), key: const ValueKey('omr.dup.page'), style: appText(13, c: c.textMedium)),
          ],
        ];
      case 'form':
        final read = item.markersRead;
        body = [
          if (read.isEmpty) Text(t('لم يُقرأ أي علامة', 'No marker could be read'), style: appText(15, w: FontWeight.w600, c: c.textDark)),
          for (final e in read.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(t('${omrMarkerText(e.key)}: النموذج ${e.value}', '${omrMarkerText(e.key)}: form ${e.value}'),
                  style: appText(15, w: FontWeight.w600, c: c.textDark)),
            ),
        ];
      default:
        final issues = asIssues(item);
        body = [
          for (final s in issues) Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(s, style: appText(14, w: FontWeight.w600, c: c.textDark))),
          if (issues.isEmpty) Text(item.reason, style: appText(14, c: c.textDark)),
        ];
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: AppSpace.xs), ...body]);
  }

  /// The gate's instructions ("Too blurry, hold steady.").
  static List<String> asIssues(OmrReviewItem item) {
    final q = item.systemReading['quality'];
    final list = q is Map && q['issues'] is List ? q['issues'] as List : const [];
    return [
      for (final i in list)
        if (i is Map) '${(AppConfig.lang == 'ar' ? i['ar'] : i['en']) ?? ''}',
    ].where((s) => s.isNotEmpty).toList();
  }
}

class _FillRow extends StatelessWidget {
  const _FillRow({required this.letter, required this.fill, required this.marked});
  final String letter;
  final double fill;
  final bool marked;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pct = (fill * 100).clamp(0, 100).round();
    return Semantics(
      label: t('الخيار $letter مظلّل بنسبة $pct٪', 'Option $letter filled $pct%'),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(width: 22, child: Text(letter, style: appText(13, w: FontWeight.w700, c: c.textDark))),
          Expanded(child: AppProgressBar(value: pct.toDouble(), color: marked ? c.primary : c.warning)),
          const SizedBox(width: AppSpace.xs),
          SizedBox(width: 44, child: Text('$pct%', textAlign: TextAlign.end, style: appText(12.5, c: c.textMedium))),
        ]),
      ),
    );
  }
}

/// Example 7: each digit as read, the unsure ones marked.
class OmrDigitsRow extends StatelessWidget {
  const OmrDigitsRow({super.key, required this.digits});
  final List<OmrDigit> digits;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Wrap(spacing: 4, runSpacing: 4, children: [
        for (final d in digits)
          Semantics(
            label: d.low
                ? t('الخانة ${d.index + 1}: ${d.digit} غير مؤكدة', 'Digit ${d.index + 1}: ${d.digit}, not sure')
                : t('الخانة ${d.index + 1}: ${d.digit}', 'Digit ${d.index + 1}: ${d.digit}'),
            excludeSemantics: true,
            child: Container(
              width: 30,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: d.low ? c.warning.withValues(alpha: .14) : c.inputBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: d.low ? c.warning : c.divider, width: d.low ? 1.6 : 1),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(d.digit.isEmpty ? '?' : d.digit, style: appText(16, w: FontWeight.w700, c: c.textDark)),
                if (d.confidence != null)
                  Text('${(d.confidence! * 100).round()}', style: appText(9.5, c: d.low ? c.warning : c.textLight)),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ── fixes ───────────────────────────────────────────────────────────────────────────────────────────────────────

/// A big option button (A–E, 1–5 on the keyboard) with its own label for screen readers.
class OmrOptionButton extends StatelessWidget {
  const OmrOptionButton({super.key, required this.label, required this.semantics, required this.onTap, this.selected = false, this.hint});
  final String label;
  final String semantics;
  final VoidCallback? onTap;
  final bool selected;

  /// The key on the keyboard, shown small under the letter on web / desktop.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.onHero : c.textDark;
    return Semantics(
      button: true,
      selected: selected,
      label: semantics,
      excludeSemantics: true,
      child: Material(
        color: selected ? c.primary : c.cardBg,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.chip), side: BorderSide(color: selected ? c.primary : c.divider, width: 1.4)),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          onTap: onTap,
          child: SizedBox(
            width: AppTouch.primary,
            height: AppTouch.primary,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(label, style: appText(20, w: FontWeight.w800, c: fg)),
              if (hint != null) Text(hint!, style: appText(9.5, c: selected ? c.onHeroMuted : c.textLight)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Bubble: tap the right option (one tap for a one-answer question), or mark it blank.
class OmrBubbleFix extends StatelessWidget {
  const OmrBubbleFix({super.key, required this.item, this.picked = const {}, this.onToggle, this.onChoose, this.onBlank});
  final OmrReviewItem item;
  final Set<String> picked;
  final ValueChanged<String>? onToggle;
  final ValueChanged<List<String>>? onChoose;
  final VoidCallback? onBlank;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final letters = item.letters;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(item.multi ? t('اختر الإجابات الصحيحة على الورقة ثم احفظ', 'Tick every answer on the sheet, then save') : t('اضغط الإجابة الصحيحة على الورقة', 'Tap the answer on the sheet'),
          style: appText(14, w: FontWeight.w600, c: c.textDark)),
      const SizedBox(height: AppSpace.sm),
      // the printed sheet runs A → E left to right (the crop above shows it so): the buttons follow it in Arabic too
      Wrap(textDirection: TextDirection.ltr, spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final (i, l) in letters.indexed)
          OmrOptionButton(
            key: ValueKey('omr.opt.$l'),
            label: l,
            hint: '${i + 1}',
            selected: item.multi && picked.contains(l),
            semantics: item.multi
                ? t('الإجابة $l${picked.contains(l) ? '، محددة' : ''}', 'Answer $l${picked.contains(l) ? ', ticked' : ''}')
                : t('اختر الإجابة $l للسؤال ${item.n ?? ''}', 'Choose answer $l for question ${item.n ?? ''}'),
            onTap: item.multi ? (onToggle == null ? null : () => onToggle!(l)) : (onChoose == null ? null : () => onChoose!([l])),
          ),
      ]),
      const SizedBox(height: AppSpace.sm),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (item.multi)
          FilledButton.icon(
            key: const ValueKey('omr.multi.save'),
            onPressed: picked.isEmpty || onChoose == null ? null : () => onChoose!(letters.where(picked.contains).toList()),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(t('حفظ الإجابات', 'Save answers')),
          ),
        OutlinedButton.icon(
          key: const ValueKey('omr.blank'),
          onPressed: onBlank,
          icon: const Icon(Icons.block_rounded, size: 18),
          label: Text(t('بلا إجابة (0)', 'No answer (0)')),
        ),
      ]),
    ]);
  }
}

/// Identifier: accept the read value, fix the digits, pick one of the candidates, or search the exam's students.
class OmrIdentifierFix extends StatefulWidget {
  const OmrIdentifierFix({super.key, required this.item, required this.fix});
  final OmrReviewItem item;
  final OmrFixCallbacks fix;

  @override
  State<OmrIdentifierFix> createState() => _OmrIdentifierFixState();
}

class _OmrIdentifierFixState extends State<OmrIdentifierFix> {
  late final _value = TextEditingController(text: widget.item.readValue);
  final _query = TextEditingController();
  final _typedId = TextEditingController();
  final _newName = TextEditingController();
  final _newCode = TextEditingController();
  List<OmrStudent>? _hits;
  bool _searching = false;
  bool _noSearch = false;
  int _seq = 0;

  /// Names of the students a conflict names (the audience's first page; else "#id").
  final Map<int, OmrStudent> _known = {};

  static const _noAccept = {'identifier_no_match', 'identifier_duplicate', 'identifier_blank', 'identifier_missing', 'identifier_not_set', 'identifier_conflict'};

  @override
  void initState() {
    super.initState();
    for (final c in widget.item.candidates) {
      _known[c.id] = c;
    }
    final s = widget.fix.onSearch;
    // nothing was read: the students are listed at once (choosing is the way on, typing the ID the fallback)
    if (widget.item.nothingRead && widget.item.can('assign') && widget.fix.onAssign != null && s != null &&
        !const {'identifier_conflict', 'student_already_scanned'}.contains(widget.item.code)) {
      Future.microtask(() {
        if (mounted && _hits == null) _search('');
      });
    }
    if (widget.item.code == 'identifier_conflict' && s != null) {
      s('').then((r) {
        if (!mounted || r == null) return;
        setState(() {
          for (final x in r) {
            _known.putIfAbsent(x.id, () => x);
          }
        });
      });
    }
  }

  /// identifier_conflict: the students the page points at, each with why (uploaded for · shaded ID · QR code).
  List<(OmrStudent, String)> _conflictChoices() {
    final it = widget.item;
    final out = <(OmrStudent, String)>[];
    final seen = <int>{};
    void add(OmrStudent? named, String why) {
      if (named == null || !seen.add(named.id)) return;
      out.add((named.name.trim().isNotEmpty ? named : (_known[named.id] ?? named), why));
    }

    add(it.namedStudent('uploaded_for'), t('رُفعت الورقة باسمه', 'The page was uploaded for this student'));
    add(it.namedStudent('read_'),
        it.readValue.isEmpty ? t('رقمه على الورقة', "The sheet shows this student's ID") : t('رقمه مظلّل على الورقة: ${it.readValue}', "The sheet shows this student's ID: ${it.readValue}"));
    add(it.namedStudent('qr_'), t('رمز QR في الورقة يحمل اسمه', "The sheet's QR code names this student"));
    return out;
  }

  @override
  void dispose() {
    _value.dispose();
    _query.dispose();
    _typedId.dispose();
    _newName.dispose();
    _newCode.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final s = widget.fix.onSearch;
    if (s == null) return;
    final seq = ++_seq;
    setState(() => _searching = true);
    final r = await s(q.trim());
    if (!mounted || seq != _seq) return;
    setState(() {
      _searching = false;
      _noSearch = r == null;
      _hits = r;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final it = widget.item;
    final f = widget.fix;
    final conflict = it.code == 'identifier_conflict' ? _conflictChoices() : const <(OmrStudent, String)>[];
    final dup = it.code == 'student_already_scanned';
    // the student the sheet names (QR) or the system proposes, first; a conflict lists its own choices
    final proposed = conflict.isEmpty && !dup ? it.proposed : null;
    final cands = conflict.isNotEmpty ? const <OmrStudent>[] : [for (final s in it.candidates) if (s.id != proposed?.id) s];
    // never "The ID is right: ??": only a value read in full is offered as right
    final canAccept = it.can('accept') && it.readValue.isNotEmpty && !it.partlyRead && !_noAccept.contains(it.code);
    // nothing read: choosing the student leads (a duplicate's Replace leads there: its student is known)
    final choosing = it.nothingRead && !dup;
    final section = appText(13, w: FontWeight.w700, c: c.textMedium);
    final dupName = it.gradedStudentName;
    final fixBlock = <Widget>[
      if (it.can('fix') && f.onFix != null && !dup) ...[
        Text(choosing ? t('أو اكتب الرقم كما على الورقة', 'Or type the ID as on the sheet') : t('صحّح الرقم', 'Fix the ID'), style: section),
        const SizedBox(height: AppSpace.xs),
        Row(children: [
          Expanded(
            child: EnterSubmits(
              onSubmit: () => _value.text.trim().isEmpty ? null : f.onFix!(_value.text.trim()),
              child: TextField(
                key: const ValueKey('omr.id.value'),
                controller: _value,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩A-Za-z\-]')), LengthLimitingTextInputFormatter(64)],
                decoration: InputDecoration(hintText: t('الرقم كما على الورقة', 'The ID as on the sheet')),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          OutlinedButton(
            key: const ValueKey('omr.id.fix'),
            onPressed: () => _value.text.trim().isEmpty ? null : f.onFix!(_value.text.trim()),
            child: Text(t('طابِق', 'Match')),
          ),
        ]),
        const SizedBox(height: AppSpace.md),
      ],
    ];
    final chooseBlock = <Widget>[
      if (it.can('assign') && f.onAssign != null) ...[
        Text(choosing ? t('اختر الطالب', 'Choose the student') : t('أو اختر الطالب', 'Or choose the student'), key: const ValueKey('omr.id.chooseTitle'), style: section),
        const SizedBox(height: AppSpace.xs),
        if (!_noSearch && f.onSearch != null)
          TextField(
            key: const ValueKey('omr.id.search'),
            controller: _query,
            onChanged: _search,
            onSubmitted: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: t('ابحث بالاسم أو برقم الطالب', 'Search by name or student ID'),
            ),
          )
        else
          Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey('omr.id.typed'),
                controller: _typedId,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(hintText: t('رقم الطالب على المنصة', "The student's number on the platform")),
              ),
            ),
            const SizedBox(width: AppSpace.xs),
            OutlinedButton(
              key: const ValueKey('omr.id.assignTyped'),
              onPressed: () {
                final id = int.tryParse(_typedId.text.trim());
                if (id != null) f.onAssign!(OmrStudent(id, ''));
              },
              child: Text(t('تعيين', 'Assign')),
            ),
          ]),
        if (_searching) const Padding(padding: EdgeInsets.only(top: AppSpace.xs), child: AppSkeletonBox(height: 44)),
        if (!_searching && _hits != null) ...[
          const SizedBox(height: AppSpace.xs),
          if (_hits!.isEmpty) Text(t('لا يوجد طالب بهذا الاسم', 'No student matches'), style: appText(13, c: c.textMedium)),
          for (final s in _hits!.take(8)) _StudentRow(student: s, onTap: () => f.onAssign!(s)),
        ],
        const SizedBox(height: AppSpace.sm),
      ],
      if (it.can('assign') && f.onNewStudent != null) ...[
        Text(t('أو طالب جديد', 'Or a new student'), key: const ValueKey('omr.id.newTitle'), style: section),
        const SizedBox(height: AppSpace.xs),
        TextField(
          key: const ValueKey('omr.id.newName'),
          controller: _newName,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(hintText: t('اسم الطالب', "The student's name")),
        ),
        const SizedBox(height: AppSpace.xs),
        Row(children: [
          Expanded(
            child: TextField(
              key: const ValueKey('omr.id.newCode'),
              controller: _newCode,
              textDirection: TextDirection.ltr,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩A-Za-z\-]')), LengthLimitingTextInputFormatter(40)],
              decoration: InputDecoration(hintText: t('رقمه (اختياري)', 'ID (optional)')),
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          OutlinedButton(
            key: const ValueKey('omr.id.newAdd'),
            onPressed: () {
              final n = _newName.text.trim(), c = _newCode.text.trim();
              if (n.isNotEmpty || c.isNotEmpty) f.onNewStudent!(n, c);
            },
            child: Text(t('إضافة', 'Add')),
          ),
        ]),
        const SizedBox(height: AppSpace.sm),
      ],
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (conflict.isNotEmpty && it.can('assign') && f.onAssign != null) ...[
        Text(t('لمن هذه الورقة؟', 'Whose sheet is this?'), style: section),
        const SizedBox(height: AppSpace.xs),
        for (final (s, why) in conflict) _StudentRow(student: s, note: why, onTap: () => f.onAssign!(s)),
        const SizedBox(height: AppSpace.md),
      ],
      if (canAccept) ...[
        FilledButton.icon(
          key: const ValueKey('omr.id.accept'),
          onPressed: f.onAccept,
          icon: const Icon(Icons.check_rounded),
          label: Text(t('الرقم صحيح: ${it.readValue}', 'The ID is right: ${it.readValue}')),
        ),
        const SizedBox(height: AppSpace.md),
      ],
      if (dup && it.can('replace')) ...[
        FilledButton.icon(
          key: const ValueKey('omr.id.replace'),
          onPressed: f.onReplace,
          icon: const Icon(Icons.swap_horiz_rounded),
          label: Text(dupName == null
              ? t('اعتمد هذه الورقة لهذا الطالب (تحلّ محل المصحّحة)', 'Use this sheet for this student (replaces the graded one)')
              : t('اعتمد هذه الورقة للطالب $dupName (تحلّ محل المصحّحة)', 'Use this sheet for $dupName (replaces the graded one)')),
        ),
        const SizedBox(height: AppSpace.md),
      ],
      if (proposed != null && it.can('assign') && f.onAssign != null) ...[
        Text(t('هل هي ورقة هذا الطالب؟', "Is it this student's sheet?"), style: section),
        const SizedBox(height: AppSpace.xs),
        _StudentRow(key: const ValueKey('omr.id.proposed'), student: proposed, note: it.proposedWhy, onTap: () => f.onAssign!(proposed)),
        const SizedBox(height: AppSpace.md),
      ],
      if (cands.isNotEmpty && it.can('assign')) ...[
        Text(cands.length == 1 ? t('هل هي ورقة هذا الطالب؟', "Is it this student's sheet?") : t('لمن هذه الورقة؟', 'Whose sheet is this?'), style: section),
        const SizedBox(height: AppSpace.xs),
        for (final s in cands) _StudentRow(student: s, onTap: f.onAssign == null ? null : () => f.onAssign!(s)),
        const SizedBox(height: AppSpace.md),
      ],
      // nothing read: choosing the student leads, typing the ID is the fallback; otherwise fixing the read ID leads
      if (choosing) ...[...chooseBlock, ...fixBlock] else ...[...fixBlock, ...chooseBlock],
      if (it.can('dismiss'))
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey('omr.dismiss'),
            onPressed: f.onDismiss,
            icon: const Icon(Icons.do_not_disturb_on_outlined, size: 18),
            label: Text(t('تنحية الورقة (لا تُصحَّح)', 'Set the paper aside (not graded)')),
          ),
        ),
    ]);
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({super.key, required this.student, required this.onTap, this.note});
  final OmrStudent student;
  final VoidCallback? onTap;

  /// Why this student is offered (a conflict's "uploaded for" / "shaded ID").
  final String? note;

  /// The second line: why, the masked ID (left to right), how close it is, else the e-mail.
  String get _sub => [
        if ((note ?? '').isNotEmpty) note!,
        if ((student.identifier ?? '').isNotEmpty) omrLtr(student.identifier!),
        if (student.distance != null && student.distance! > 0)
          t('يختلف في ${omrBoxesText(student.distance!, after: true)}', '${student.distance} digit${student.distance == 1 ? '' : 's'} differ${student.distance == 1 ? 's' : ''}'),
        if ((student.identifier ?? '').isEmpty && (student.email ?? '').isNotEmpty) student.email!,
      ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: t('عيّن الورقة إلى ${student.label}${_sub.isEmpty ? '' : '، $_sub'}', 'Assign the sheet to ${student.label}${_sub.isEmpty ? '' : ', $_sub'}'),
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('omr.student.${student.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
            child: Row(children: [
              AppAvatar(name: student.label, size: 32),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(student.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w600, c: c.textDark)),
                  if (_sub.isNotEmpty) Text(_sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
                ]),
              ),
              Icon(Icons.person_add_alt_1_rounded, size: 20, color: c.primary),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Form: choose the form the sheet really is (Example 4), or set the paper aside.
class OmrFormFix extends StatelessWidget {
  const OmrFormFix({super.key, required this.item, this.onConfirm, this.onDismiss});
  final OmrReviewItem item;
  final ValueChanged<String>? onConfirm;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final forms = item.forms.isNotEmpty ? item.forms : ({...item.markersRead.values}.toList()..sort());
    // another exam's / version's sheet: its bubbles were read with THIS sheet's layout — it can only be set aside
    final confirm = item.can('confirm') && onConfirm != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!confirm)
        Text(t('لا تُصحَّح هذه الورقة هنا', 'This sheet is not graded here'), key: const ValueKey('omr.form.noConfirm'), style: appText(14, w: FontWeight.w600, c: c.textDark))
      else ...[
        Text(t('ما نموذج هذه الورقة؟', 'Which form is this sheet?'), style: appText(14, w: FontWeight.w600, c: c.textDark)),
        const SizedBox(height: AppSpace.sm),
        Wrap(textDirection: TextDirection.ltr, spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final (i, f) in forms.indexed)
            OmrOptionButton(
              key: ValueKey('omr.form.$f'),
              label: f,
              hint: '${i + 1}',
              semantics: t('النموذج $f', 'Form $f'),
              onTap: onConfirm == null ? null : () => onConfirm!(f),
            ),
        ]),
      ],
      if (item.can('dismiss')) ...[
        const SizedBox(height: AppSpace.sm),
        TextButton.icon(
          key: const ValueKey('omr.dismiss'),
          onPressed: onDismiss,
          icon: const Icon(Icons.do_not_disturb_on_outlined, size: 18),
          label: Text(t('تنحية الورقة (لا تُصحَّح)', 'Set the paper aside (not graded)')),
        ),
      ],
    ]);
  }
}

/// A form key without this question (several forms): no answer chosen here can be graded — the key is fixed in the
/// exam setup, and the sheets are graded again at once (the server's manual change).
class OmrKeyMissingFix extends StatelessWidget {
  const OmrKeyMissingFix({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.key_off_rounded, color: c.warning, size: 22),
      const SizedBox(width: AppSpace.xs),
      Expanded(
        child: Text(
          t('لا قرار هنا: الإجابة المظلّلة مقروءة بوضوح، لكن لا يوجد مفتاح يُصحَّح به هذا السؤال لهذا النموذج.',
              'Nothing to decide here: the shaded answer is read clearly, but this form has no key to grade the question with.'),
          key: const ValueKey('omr.keyMissing'),
          style: appText(14, c: c.textDark, h: 1.35),
        ),
      ),
    ]);
  }
}

/// Image quality (and any kind the app does not know yet): the only decision is to set it aside.
class OmrDismissFix extends StatelessWidget {
  const OmrDismissFix({super.key, required this.item, this.onDismiss, this.onReplacePage});
  final OmrReviewItem item;
  final VoidCallback? onDismiss;

  /// "Replace this page" (a rejected page's quality item): the batch page's replace flow, right here.
  final VoidCallback? onReplacePage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final replace = onReplacePage != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
          replace
              ? t('ارفع صورة أوضح لهذه الصفحة: تُقرأ من جديد ويُغلق هذا العنصر وحده', 'Upload a clearer image of this page: it is read again and this item closes by itself')
              : t('ارفع صورة أوضح لهذه الصفحة من صفحة الدفعة («الأوراق الممسوحة» ← الدفعة ← «استبدال هذه الصفحة»)، ثم أغلق هذا العنصر',
                  'Upload a clearer image of this page from its batch (Scanned pages → the batch → Replace this page), then close this item'),
          style: appText(14, c: c.textDark, h: 1.35)),
      const SizedBox(height: AppSpace.sm),
      if (replace) ...[
        FilledButton.icon(
          key: const ValueKey('omr.quality.replace'),
          style: FilledButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
          onPressed: onReplacePage,
          icon: const Icon(Icons.find_replace_rounded),
          label: Text(t('استبدال هذه الصفحة', 'Replace this page')),
        ),
        const SizedBox(height: AppSpace.xs),
      ],
      if (item.can('dismiss'))
        OutlinedButton.icon(
          key: const ValueKey('omr.dismiss'),
          onPressed: onDismiss,
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text(t('تمت إعادة المسح أو لا حاجة لها', 'Rescanned, or not needed')),
        ),
    ]);
  }
}

/// "Changed by you · 10:42 — A" (the server's audited decision, D-158).
class OmrResolvedNote extends StatelessWidget {
  const OmrResolvedNote({super.key, required this.item, this.meId});
  final OmrReviewItem item;
  final int? meId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reason = '${item.resolution['reason'] ?? ''}';
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.history_rounded, size: 20, color: c.success),
      const SizedBox(width: AppSpace.xs),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.resolutionText, style: appText(15, w: FontWeight.w700, c: c.textDark)),
          Text(omrChangedBy(item.resolvedBy, item.resolvedAt, meId: meId), key: const ValueKey('omr.item.changedBy'), style: appText(12.5, c: c.textMedium)),
          if (reason.isNotEmpty) AutoDirText(reason, style: appText(12.5, c: c.textMedium)),
        ]),
      ),
    ]);
  }
}

/// The line after a fix: the new score (or what still waits on that paper).
class OmrScoreBanner extends StatelessWidget {
  const OmrScoreBanner({super.key, required this.reply});
  final OmrResolveReply reply;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final graded = reply.attempt?.graded == true;
    return Semantics(
      liveRegion: true,
      child: AppBanner(
        key: const ValueKey('omr.score'),
        icon: graded ? Icons.verified_rounded : Icons.check_circle_outline_rounded,
        color: graded ? c.success : c.primary,
        text: reply.summary,
      ),
    );
  }
}

/// "Page 3 · wa01.jpg · Today, 10:42 AM" on one line: the page and file give way (an ellipsis), the time never does.
class OmrWhereLine extends StatelessWidget {
  const OmrWhereLine({super.key, required this.item});
  final OmrReviewItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = appText(11.5, c: c.textLight);
    final place = item.placeText, when = item.whenText;
    if (place.isEmpty || when == null) return Text(item.whereText, maxLines: 2, overflow: TextOverflow.ellipsis, style: style);
    final tail = ' · $when';
    return LayoutBuilder(builder: (context, box) {
      final painter = TextPainter(
          text: TextSpan(text: tail, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1)
        ..layout();
      final tailWidth = painter.width;
      painter.dispose();
      // too narrow to keep the time beside even a short page name: the line wraps instead (two lines at most)
      if (!box.hasBoundedWidth || tailWidth + 48 > box.maxWidth) {
        return Text(item.whereText, maxLines: 2, overflow: TextOverflow.ellipsis, style: style);
      }
      return Semantics(
        label: item.whereText,
        excludeSemantics: true,
        child: Row(children: [
          Flexible(child: Text(place, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
          Text(tail, maxLines: 1, softWrap: false, style: style),
        ]),
      );
    });
  }
}

// ── queue ───────────────────────────────────────────────────────────────────────────────────────────────────────

/// The queue as compact rows (the side list on desktop, the sheet on phones).
class OmrQueueList extends StatelessWidget {
  const OmrQueueList({super.key, required this.items, required this.currentId, required this.onTap});
  final List<OmrReviewItem> items;
  final int? currentId;
  final ValueChanged<OmrReviewItem> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final it in items)
        Material(
          color: it.id == currentId ? c.primaryTint : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          child: InkWell(
            key: ValueKey('omr.queue.${it.id}'),
            borderRadius: BorderRadius.circular(AppRadius.chip),
            onTap: () => onTap(it),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
                child: Row(children: [
                  Icon(omrKindIcon(it.kind), size: 20, color: it.open ? c.warning : c.success),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(it.reason, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w600, c: c.textDark)),
                      Text(
                          [
                            ?it.studentText,
                            omrKindLabel(it.kind),
                            if (it.kind == 'bubble' && it.n != null) t('س${it.n}', 'Q${it.n}'),
                            if (!it.open) it.resolutionText,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: appText(12, c: c.textMedium)),
                      // which paper: page · file · when (two "Student ID is empty" rows told apart); a long file name
                      // gives way, the time stays whole (it was cut to "Today, 3:18…" in the desktop side list)
                      if (it.whereText.isNotEmpty) OmrWhereLine(item: it, key: ValueKey('omr.queue.where.${it.id}')),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}

// ── the full paper ──────────────────────────────────────────────────────────────────────────────────────────────

/// The page image with the detected bubbles drawn over it: clear answers in one colour, the ones that wait for a
/// person in another, the ID / form bubbles in a third; flagged questions boxed. Zoom and pan.
class OmrPaperOverlay extends StatelessWidget {
  const OmrPaperOverlay({super.key, required this.page, required this.bytes, this.loading = false, this.focusN});
  final OmrPageView page;
  final Uint8List? bytes;
  final bool loading;

  /// The question of the item being reviewed: drawn thicker.
  final int? focusN;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final w = page.width ?? 1654, h = page.height ?? 2339;
    final ratio = w / h;
    Widget image;
    if (loading) {
      image = const SizedBox.expand(child: AppShimmer(child: ColoredBox(color: Colors.white10)));
    } else if (bytes == null || bytes!.isEmpty) {
      image = ColoredBox(
        color: c.inputBg,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Text(page.imageUrl == null ? t('حُذفت صورة الورقة بعد مدة الاحتفاظ', 'The page image was removed after the retention period') : t('تعذّر تحميل صورة الورقة', 'The page image could not be loaded'),
                textAlign: TextAlign.center, style: appText(13, c: c.textMedium)),
          ),
        ),
      );
    } else {
      image = Image.memory(bytes!, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => ColoredBox(color: c.inputBg));
    }
    final flagged = page.answers.where((a) => a.flagged).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, children: [
        _Legend(color: c.success, label: t('إجابة واضحة', 'Clear answer')),
        _Legend(color: c.warning, label: t('تحتاج مراجعة ($flagged)', 'Needs review ($flagged)')),
        _Legend(color: c.primary, label: t('رقم الطالب / النموذج', 'Student ID / form')),
      ]),
      const SizedBox(height: AppSpace.xs),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          child: ColoredBox(
            color: c.inputBg,
            child: InteractiveViewer(
              key: const ValueKey('omr.paper.viewer'),
              minScale: 1,
              maxScale: 6,
              child: Center(
                child: AspectRatio(
                  aspectRatio: ratio,
                  child: Semantics(
                    image: true,
                    label: t('الورقة الممسوحة مع الإجابات المكتشفة', 'The scanned paper with the detected answers'),
                    child: Stack(fit: StackFit.expand, children: [
                      image,
                      CustomPaint(
                        painter: OmrOverlayPainter(
                          page: page,
                          sourceW: w,
                          sourceH: h,
                          clear: c.success,
                          flagged: c.warning,
                          other: c.primary,
                          focusN: focusN,
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 2.5))),
        const SizedBox(width: AppSpace.xxs),
        Flexible(child: Text(label, style: appText(12, c: context.colors.textMedium))),
      ]);
}

/// Draws [page]'s marks scaled from source pixels to the widget.
class OmrOverlayPainter extends CustomPainter {
  OmrOverlayPainter({
    required this.page,
    required this.sourceW,
    required this.sourceH,
    required this.clear,
    required this.flagged,
    required this.other,
    this.focusN,
  });

  final OmrPageView page;
  final double sourceW, sourceH;
  final Color clear, flagged, other;
  final int? focusN;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / sourceW, sy = size.height / sourceH;
    final s = (sx + sy) / 2;
    for (final m in page.marks) {
      final col = m.isAnswer ? (m.flagged ? flagged : clear) : other;
      final focus = focusN != null && m.n == focusN;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (focus ? 4.0 : 2.6)
        ..color = col;
      canvas.drawCircle(Offset(m.cx * sx, m.cy * sy), m.r * s + 3, p);
      if (m.mark == 'mid') {
        canvas.drawCircle(Offset(m.cx * sx, m.cy * sy), m.r * s + 3, Paint()..color = col.withValues(alpha: .18));
      }
    }
    for (final a in page.answers) {
      final b = a.box;
      if (b == null || !a.flagged) continue;
      final focus = focusN != null && a.n == focusN;
      // the engine's crop box carries part of the rows above and below: drawn at the question's own row height
      final r0 = Rect.fromLTWH(b[0] * sx, b[1] * sy, b[2] * sx, b[3] * sy);
      final r = Rect.fromCenter(center: r0.center, width: r0.width + 4, height: r0.height * .64);
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(4)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = focus ? 3.2 : 2
            ..color = flagged);
      if (focus) canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), Paint()..color = flagged.withValues(alpha: .10));
    }
  }

  @override
  bool shouldRepaint(OmrOverlayPainter old) =>
      old.page != page || old.focusN != focusN || old.clear != clear || old.flagged != flagged || old.other != other;
}

/// The page's state in words, and for a rejected page "Replace this page" with the gate's answer (accepted → open
/// the new page; refused → the exact reason, nothing stored).
class OmrPageStatusCard extends StatelessWidget {
  const OmrPageStatusCard({super.key, required this.page, this.replacing = false, this.result, this.onReplace, this.onOpenNew});
  final OmrPageView page;
  final bool replacing;
  final OmrReplaceResult? result;
  final VoidCallback? onReplace;
  final VoidCallback? onOpenNew;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final res = result;
    final (Color color, IconData icon, String text) = switch (page.status) {
      'rejected' => (c.danger, Icons.image_not_supported_outlined,
          page.problem.isNotEmpty ? page.problem : t('رُفضت صورة هذه الصفحة ولم تُصحَّح', 'This page was refused and not graded')),
      'replaced' => (c.primary, Icons.find_replace_rounded, t('استُبدلت هذه الصفحة بصورة أوضح', 'This page was replaced with a clearer image')),
      'review' => (c.warning, Icons.rate_review_outlined, t('تنتظر قرارك قبل حساب الدرجة', 'Waits for your decision before it is scored')),
      'processed' => (c.success, Icons.check_circle_outline_rounded, t('قُرئت وصُححت', 'Read and graded')),
      'dismissed' => (c.textMedium, Icons.do_not_disturb_on_outlined, t('نُحّيت — لا تُصحَّح', 'Set aside — not graded')),
      'purged' => (c.textMedium, Icons.auto_delete_outlined, t('حُذفت الصورة بعد مدة الاحتفاظ', 'The image was removed after the retention period')),
      'failed' => (c.danger, Icons.error_outline_rounded, t('تعذّرت قراءة هذه الصفحة', 'This page could not be read')),
      _ => (c.primary, Icons.hourglass_top_rounded, t('تُقرأ الآن', 'Being read now')),
    };
    return AppCard(
      key: const ValueKey('omr.page.status'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text(text, style: appText(14.5, w: FontWeight.w700, c: c.textDark, h: 1.35))),
        ]),
        if (res != null) ...[
          const SizedBox(height: AppSpace.sm),
          Semantics(
            liveRegion: true,
            child: AppBanner(
              key: const ValueKey('omr.page.replaceResult'),
              icon: res.accepted ? Icons.check_circle_outline_rounded : Icons.block_rounded,
              color: res.accepted ? c.success : c.danger,
              text: res.accepted ? res.text : res.refusal,
            ),
          ),
          if (res.accepted && onOpenNew != null) ...[
            const SizedBox(height: AppSpace.xs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('omr.page.openNew'),
                onPressed: onOpenNew,
                icon: const Icon(Icons.description_outlined, size: 18),
                label: Text(t('افتح الصفحة الجديدة', 'Open the new page')),
              ),
            ),
          ],
        ],
        if (onReplace != null && !(res?.accepted ?? false)) ...[
          const SizedBox(height: AppSpace.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: replacing
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: AppSpace.xs),
                    Text(t('تُفحص الصورة…', 'Checking the photo…'), style: appText(13.5, c: c.textMedium)),
                  ])
                : FilledButton.tonalIcon(
                    key: const ValueKey('omr.page.replace'),
                    style: FilledButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
                    onPressed: onReplace,
                    icon: const Icon(Icons.find_replace_rounded),
                    label: Text(t('استبدال هذه الصفحة', 'Replace this page')),
                  ),
          ),
        ],
      ]),
    );
  }
}

/// The page's decisions that are not one question's bubbles (student ID, form, handwriting, image quality): one tap
/// opens the item in the review queue.
class OmrPageItemsList extends StatelessWidget {
  const OmrPageItemsList({super.key, required this.page, this.onItem});
  final OmrPageView page;
  final ValueChanged<int>? onItem;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final open = [for (final i in page.items) if (i.status == 'open' && i.kind != 'bubble') i];
    if (open.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('ينتظر قرارك', 'Waiting for your decision'), style: appText(14, w: FontWeight.w700, c: c.textDark)),
      const SizedBox(height: AppSpace.xs),
      for (final i in open)
        Semantics(
          button: onItem != null,
          label: '${omrKindLabel(i.kind)}: ${omrCodeText(i.code)}',
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey('omr.page.item.${i.id}'),
            onTap: onItem == null ? null : () => onItem!(i.id),
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
                child: Row(children: [
                  Icon(omrKindIcon(i.kind), size: 20, color: c.warning),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(omrCodeText(i.code), maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w600, c: c.textDark)),
                      Text(omrKindLabel(i.kind), style: appText(12, c: c.textMedium)),
                    ]),
                  ),
                  if (onItem != null) Icon(Icons.chevron_right_rounded, color: c.textMedium),
                ]),
              ),
            ),
          ),
        ),
      const SizedBox(height: AppSpace.sm),
    ]);
  }
}

/// The page's questions as read, under the image: "Q4 · multiple · A, D · waiting".
class OmrPageAnswers extends StatelessWidget {
  const OmrPageAnswers({super.key, required this.page, this.onItem});
  final OmrPageView page;
  final ValueChanged<int>? onItem;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
      for (final a in page.answers)
        Builder(builder: (context) {
          final item = page.items.where((i) => i.questionId == a.questionId && i.status == 'open').firstOrNull;
          final col = a.flagged ? c.warning : c.success;
          final score = a.finalScore == null ? t('بانتظار المراجعة', 'waiting') : omrNum(a.finalScore);
          final picked = a.selected.isEmpty ? '—' : a.selected.join(', ');
          final text = '${t('السؤال', 'Question')} ${a.n} · $picked · $score';
          final chip = Container(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
            decoration: BoxDecoration(color: col.withValues(alpha: .10), borderRadius: BorderRadius.circular(AppRadius.chip), border: Border.all(color: col.withValues(alpha: .5))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('${t('س', 'Q')}${a.n}', style: appText(12.5, w: FontWeight.w800, c: c.textDark)),
              const SizedBox(width: AppSpace.xs),
              Text(picked, textDirection: TextDirection.ltr, style: appText(12.5, w: FontWeight.w600, c: c.textDark)),
              const SizedBox(width: AppSpace.xs),
              Flexible(child: Text(score, style: appText(12, c: a.flagged ? c.warning : c.textMedium))),
            ]),
          );
          if (item == null || onItem == null) return Semantics(label: '$text · ${omrStateText(a.state)}', excludeSemantics: true, child: chip);
          return Semantics(
            button: true,
            label: t('افتح مراجعة السؤال ${a.n}', 'Open the review of question ${a.n}'),
            excludeSemantics: true,
            child: InkWell(onTap: () => onItem!(item.id), borderRadius: BorderRadius.circular(AppRadius.chip), child: chip),
          );
        }),
    ]);
  }
}

/// The append-only trail of manual changes (D-158), newest first.
class OmrChangesList extends StatelessWidget {
  const OmrChangesList({super.key, required this.changes, this.meId});
  final List<OmrChange> changes;
  final int? meId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (changes.isEmpty) {
      return AppEmpty(icon: Icons.history_rounded, title: t('لا تعديلات بعد', 'No changes yet'), message: t('كل تعديل يدوي يُسجَّل هنا', 'Every manual change is recorded here'));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final ch in changes)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.edit_note_rounded, size: 20, color: c.primary),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ch.summary, style: appText(14, w: FontWeight.w600, c: c.textDark)),
                Text(omrChangedBy(ch.actorId, ch.at, meId: meId), style: appText(12.5, c: c.textMedium)),
                if ((ch.reason ?? '').isNotEmpty) AutoDirText(ch.reason!, style: appText(12.5, c: c.textMedium)),
              ]),
            ),
          ]),
        ),
    ]);
  }
}
