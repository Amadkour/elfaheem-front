// Plain-value widgets of the bubble-sheet flow (D-340 – D-343), so the layout harness pumps them: the wizard's progress,
// a step's card, the review panel, the key grid, the Data Lab preview. No provider, no API in here.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/paper/exam_setup_wizard.dart' show SetupChoiceTile;
import 'package:flutter_education_app/features/exams/paper/bubble/bubble_flow.dart';
import 'package:flutter_education_app/features/exams/paper/bubble/bubble_sheet_view.dart';

/// The four pictures + detection + confirm, as a clear progress bar.
class BubbleWizardProgress extends StatelessWidget {
  const BubbleWizardProgress({super.key, required this.current, required this.done, this.detected = false, this.onTap});

  final BubbleStep? current;
  final Set<BubbleStep> done;
  final bool detected;
  final void Function(BubbleStep)? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = BubbleStep.values.length + 1;
    final finished = done.length + (detected ? 1 : 0);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: LinearProgressIndicator(value: finished / total, minHeight: 6, backgroundColor: c.inputBg, color: c.primary),
      ),
      const SizedBox(height: AppSpace.sm),
      Row(children: [
        for (final (i, s) in BubbleStep.values.indexed) ...[
          Expanded(child: _Pill(n: i + 1, label: s.shortTitle, active: current == s, done: done.contains(s), onTap: onTap == null ? null : () => onTap!(s))),
          if (i != BubbleStep.values.length - 1) const SizedBox(width: AppSpace.xxs),
        ],
      ]),
    ]);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.n, required this.label, required this.active, required this.done, this.onTap});
  final int n;
  final String label;
  final bool active, done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = done ? c.success : (active ? c.primary : c.textLight);
    return Semantics(
      button: onTap != null,
      selected: active,
      label: '$n: $label',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: col.withValues(alpha: active || done ? 0.16 : 0.08),
              child: done ? Icon(Icons.check_rounded, size: AppIconSize.xs, color: col) : Text('$n', style: appText(12, w: FontWeight.w800, c: col)),
            ),
            const SizedBox(height: AppSpace.xxs),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11, w: active ? FontWeight.w700 : FontWeight.w500, c: active ? c.textDark : c.textMedium)),
          ]),
        ),
      ),
    );
  }
}

/// A small drawing of what to capture for each step.
class BubbleStepIllustration extends StatelessWidget {
  const BubbleStepIllustration({super.key, required this.step, this.shape = 'circle'});
  final BubbleStep step;
  final String shape;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 112,
      width: 160,
      child: CustomPaint(painter: _IllustrationPainter(step: step, ink: c.textMedium, accent: c.primary, paper: c.cardBg2, line: c.divider, shape: shape)),
    );
  }
}

class _IllustrationPainter extends CustomPainter {
  _IllustrationPainter({required this.step, required this.ink, required this.accent, required this.paper, required this.line, required this.shape});
  final BubbleStep step;
  final Color ink, accent, paper, line;
  final String shape;

  void _bubble(Canvas c, Offset o, double r, bool fill) {
    final p = Paint()
      ..style = fill ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = fill ? accent : ink;
    if (shape == 'rect') {
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: r * 2.2, height: r * 1.6), const Radius.circular(2)), p);
    } else {
      c.drawCircle(o, r, p);
    }
  }

  @override
  void paint(Canvas c, Size s) {
    final card = RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(14));
    c.drawRRect(card, Paint()..color = paper);
    c.drawRRect(card, Paint()..style = PaintingStyle.stroke..color = line);
    switch (step) {
      case BubbleStep.question:
        final tp = Paint()..color = ink.withValues(alpha: 0.6)..strokeWidth = 2;
        c.drawLine(Offset(20, s.height * .3), Offset(s.width - 20, s.height * .3), tp);
        for (var i = 0; i < 4; i++) {
          _bubble(c, Offset(30.0 + i * 33, s.height * .62), 9, i == 1);
        }
      case BubbleStep.identifier:
        for (var col = 0; col < 7; col++) {
          for (var row = 0; row < 5; row++) {
            _bubble(c, Offset(20.0 + col * 20, 22.0 + row * 18), 5.5, col == 2 && row == 3 || col == 4 && row == 1);
          }
        }
      case BubbleStep.empty:
      case BubbleStep.filled:
        final m = Paint()..color = ink;
        c.drawRect(const Rect.fromLTWH(14, 14, 6, 6), m);
        c.drawRect(Rect.fromLTWH(s.width - 20, 14, 6, 6), m);
        for (var col = 0; col < 2; col++) {
          for (var row = 0; row < 5; row++) {
            for (var o = 0; o < 4; o++) {
              final filled = step == BubbleStep.filled && (row + col * 2 + o) % 4 == 0;
              _bubble(c, Offset(30.0 + col * 62 + o * 12, 34.0 + row * 14), 4.2, filled);
            }
          }
        }
    }
  }

  @override
  bool shouldRepaint(_IllustrationPainter o) => o.step != step || o.ink != ink || o.accent != accent || o.shape != shape;
}

/// What a checked picture needs (each issue says how to fix it).
class BubbleIssueList extends StatelessWidget {
  const BubbleIssueList({super.key, required this.issues});
  final List<BubbleIssue> issues;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final i in issues) ...[
        AppBanner(icon: Icons.tips_and_updates_rounded, color: c.warning, text: i.text),
        const SizedBox(height: AppSpace.xs),
      ],
    ]);
  }
}

/// The wizard's step: the instruction + what was understood from the picture.
class BubbleStepCard extends StatelessWidget {
  const BubbleStepCard({
    super.key,
    required this.step,
    required this.result,
    required this.preview,
    required this.onCamera,
    required this.onFiles,
    required this.onContinue,
    this.onCrop,
    this.busy = false,
    this.error,
  });

  final BubbleStep step;
  final BubbleStepResult? result;
  final Uint8List? preview;
  final VoidCallback? onCamera, onFiles, onContinue, onCrop;
  final bool busy;
  final String? error;

  String? _understood() {
    final r = result;
    if (r == null || !r.ok) return null;
    return switch (step) {
      BubbleStep.question => '${r.options ?? '?'} ${t('اختيارات', 'choices')} · ${r.shape == 'rect' ? t('مستطيلات', 'rectangles') : t('دوائر', 'circles')}',
      BubbleStep.identifier => switch (r.kind) {
          'qr' => t('رمز QR', 'A QR code'),
          'barcode' => t('باركود', 'A barcode'),
          'boxes' => '${r.digits ?? ''} ${t('خانات تُكتب يدويًا', 'write-in boxes')}',
          _ => '${r.digits ?? ''} ${t('خانات مظلّلة', 'shaded digits')}',
        },
      BubbleStep.empty => t('تم التعرف على الورقة', 'The sheet was recognised'),
      BubbleStep.filled => t('تطابق الورقة الفارغة', 'It matches the empty sheet'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = result;
    final understood = _understood();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(step.title, style: AppType.headline(context)),
      const SizedBox(height: AppSpace.xxs),
      Text(step.help, style: AppType.body(context).copyWith(color: c.textMedium)),
      const SizedBox(height: AppSpace.md),
      if (preview != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            color: c.inputBg,
            constraints: const BoxConstraints(maxHeight: 320),
            alignment: Alignment.center,
            child: Image.memory(preview!, fit: BoxFit.contain),
          ),
        )
      else
        Center(child: BubbleStepIllustration(step: step)),
      const SizedBox(height: AppSpace.md),
      if (r != null && r.issues.isNotEmpty) ...[
        BubbleIssueList(issues: r.issues),
        const SizedBox(height: AppSpace.xxs),
      ],
      if (understood != null) ...[
        AppBanner(icon: Icons.check_circle_rounded, color: c.success, text: understood),
        const SizedBox(height: AppSpace.sm),
      ],
      if (error != null) ...[
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
        const SizedBox(height: AppSpace.sm),
      ],
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        if (onCamera != null) AppButton.secondary(label: t('التقاط صورة', 'Take a photo'), icon: Icons.photo_camera_rounded, onPressed: busy ? null : onCamera),
        if (onFiles != null) AppButton.secondary(label: t('اختيار ملف', 'Choose a file'), icon: Icons.upload_file_rounded, onPressed: busy ? null : onFiles),
        if (onCrop != null && preview != null) AppButton.ghost(label: t('قصّ الصورة', 'Crop'), icon: Icons.crop_rounded, onPressed: busy ? null : onCrop),
      ]),
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(label: t('التالي', 'Continue'), icon: Icons.arrow_forward_rounded, busy: busy, onPressed: (r?.ok ?? false) ? onContinue : null),
    ]);
  }
}

/// The review of a detection: the sheet with its regions, what's unsure, tap tools, the note, Confirm.
class BubbleReviewPanel extends StatelessWidget {
  const BubbleReviewPanel({
    super.key,
    required this.data,
    required this.image,
    required this.tapMode,
    required this.onMode,
    required this.taps,
    required this.onTapSheet,
    required this.onRemoveTaps,
    required this.note,
    required this.onDetect,
    required this.onConfirm,
    required this.onUndo,
    required this.name,
    this.onShape,
    this.busy = false,
    this.error,
    this.wide = false,
  });

  final BubbleImport data;
  final Uint8List? image;
  final BubbleTapMode? tapMode;
  final ValueChanged<BubbleTapMode?> onMode;
  final List<BubbleTap> taps;
  final void Function(Offset) onTapSheet;
  final VoidCallback onRemoveTaps;
  final TextEditingController note;
  final VoidCallback onDetect, onConfirm, onUndo;
  final TextEditingController name;

  /// The teacher says the bubbles are circles or rectangles.
  final ValueChanged<String>? onShape;
  final bool busy;
  final String? error;
  final bool wide;

  String _understoodText() => [
        for (final u in data.understood)
          switch (u['type']) {
            'questions' => t('${u['value']} سؤال', '${u['value']} questions'),
            'options' => t('${u['value']} اختيارات', '${u['value']} choices'),
            'id_digits' => t('رقم من ${u['value']} خانات', 'a ${u['value']}-digit ID'),
            'shape' => u['value'] == 'rect' ? t('مستطيلات', 'rectangles') : t('دوائر', 'circles'),
            'direction' => u['value'] == 'rtl' ? t('من اليمين', 'right to left') : t('من اليسار', 'left to right'),
            'order' => u['value'] == 'across' ? t('صفًا بعد صف', 'across') : t('عمودًا بعد عمود', 'down'),
            _ => '${u['type']}: ${u['value']}',
          },
      ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sheet = BubbleSheetView(image: image, aspect: data.imageW == 0 ? 1.414 : data.imageH / data.imageW, blocks: data.blocks, unsure: data.unsure, taps: taps, onTap: tapMode == null ? null : onTapSheet);
    final stats = AppCard(
      padding: AppSpace.card,
      child: Row(children: [
        Expanded(child: _Fact(value: '${data.questions}', label: t('سؤال', 'questions'))),
        Expanded(child: _Fact(value: '${data.options}', label: t('اختيارات', 'choices'))),
        Expanded(child: _Fact(value: data.idDigits > 0 ? '${data.idDigits}' : (data.idKind == 'none' ? '—' : data.idKind.toUpperCase()), label: t('رقم الطالب', 'student ID'))),
        Expanded(child: _Fact(value: data.shape == 'rect' ? t('مستطيل', 'Rect') : t('دائرة', 'Circle'), label: t('الشكل', 'shape'), small: true)),
      ]),
    );
    final tools = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('انقر على الورقة لتصحيح', 'Tap the sheet to correct'), style: AppType.section(context)),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final m in BubbleTapMode.legacy)
          AppChoiceChip(label: m.label, selected: tapMode == m, onTap: () => onMode(tapMode == m ? null : m)),
      ]),
      if (taps.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xs),
        Row(children: [
          Expanded(child: Text(t('لديك ${taps.length} تعديل لم يُطبَّق بعد', '${taps.length} edits not applied yet'), style: AppType.meta(context).copyWith(color: c.warning))),
          TextButton(onPressed: onRemoveTaps, child: Text(t('مسح', 'Clear'))),
        ]),
      ],
      if (onShape != null) ...[
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(t('الفقاعات:', 'Bubbles:'), style: AppType.meta(context)),
          AppChoiceChip(label: t('دوائر', 'Circles'), selected: data.shape != 'rect', onTap: () => onShape!('circle')),
          AppChoiceChip(label: t('مستطيلات', 'Rectangles'), selected: data.shape == 'rect', onTap: () => onShape!('rect')),
        ]),
      ],
      const SizedBox(height: AppSpace.sm),
      AppField(controller: note, label: t('أو اكتب ملاحظة', 'Or write a note'), hint: t('مثلًا: 50 سؤال، 4 اختيارات', 'e.g. 50 questions, 4 choices')),
      const SizedBox(height: AppSpace.sm),
      AppButton.secondary(label: t('طبّق واكتشف من جديد', 'Apply and detect again'), icon: Icons.auto_fix_high_rounded, expand: true, busy: busy, onPressed: busy ? null : onDetect),
      if (data.rounds > 1) ...[
        const SizedBox(height: AppSpace.xxs),
        AppButton.ghost(label: t('تراجع', 'Undo'), icon: Icons.undo_rounded, expand: true, onPressed: busy ? null : onUndo),
      ],
    ]);
    final unsureCard = data.unsure.isEmpty
        ? AppBanner(icon: Icons.verified_rounded, color: c.success, text: t('لا يوجد ما يحتاج تأكيدًا. راجع الورقة ثم أكّد.', 'Nothing needs a second look. Check the sheet, then confirm.'))
        : AppBanner(icon: Icons.report_gmailerrorred_rounded, color: c.warning, text: '${data.unsure.length} ${t('موضع يحتاج تأكيدًا:', 'places need your eye:')} ${data.unsure.take(3).map((u) => u.text).join(' · ')}');
    final understoodLine = data.understood.isEmpty
        ? const SizedBox.shrink()
        : Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: AppBanner(icon: Icons.check_rounded, color: c.success, text: t('فهمنا: ${_understoodText()}', 'Understood: ${_understoodText()}')));
    final confirm = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppField(controller: name, label: t('اسم الورقة', 'Sheet name')),
      const SizedBox(height: AppSpace.sm),
      if (error != null) ...[AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!), const SizedBox(height: AppSpace.sm)],
      AppPrimaryButton(key: const ValueKey('bubble.confirm'), label: t('تأكيد الاكتشاف', 'Confirm detection'), icon: Icons.task_alt_rounded, busy: busy, onPressed: busy ? null : onConfirm),
      const SizedBox(height: AppSpace.xxs),
      Text(t('لن تُستخدم الورقة قبل هذا التأكيد.', "Nothing is used before you confirm."), style: AppType.meta(context), textAlign: TextAlign.center),
    ]);
    final side = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      stats,
      const SizedBox(height: AppSpace.sm),
      understoodLine,
      unsureCard,
      const SizedBox(height: AppSpace.md),
      tools,
      const SizedBox(height: AppSpace.md),
      confirm,
    ]);
    if (wide) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [sheet, const SizedBox(height: AppSpace.xs), const BubbleSheetLegend()])),
        const SizedBox(width: AppSpace.lg),
        Expanded(flex: 2, child: side),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      stats,
      const SizedBox(height: AppSpace.sm),
      sheet,
      const SizedBox(height: AppSpace.xs),
      const BubbleSheetLegend(),
      const SizedBox(height: AppSpace.sm),
      understoodLine,
      unsureCard,
      const SizedBox(height: AppSpace.md),
      tools,
      const SizedBox(height: AppSpace.md),
      confirm,
    ]);
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.value, required this.label, this.small = false});
  final String value, label;

  /// A word rather than a number.
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(children: [
      Text(value, style: (small ? AppType.section(context) : AppType.figureLarge(context)).copyWith(color: c.textDark), maxLines: 1, overflow: TextOverflow.ellipsis),
      Text(label, style: AppType.meta(context), maxLines: 1, overflow: TextOverflow.ellipsis),
    ]);
  }
}

/// The answer key: one row per question, letters to tap, status of the row.
class BubbleKeyGrid extends StatelessWidget {
  const BubbleKeyGrid({super.key, required this.questions, required this.form, required this.flagged, required this.onToggle, this.onDetails, this.columns = 1});

  final List<BubbleKeyQuestion> questions;
  final BubbleKeyForm form;
  final Set<int> flagged;
  final void Function(BubbleKeyQuestion q, String letter) onToggle;
  final void Function(BubbleKeyQuestion q)? onDetails;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final cols = columns.clamp(1, 4);
    final perCol = (questions.length / cols).ceil();
    final chunks = <List<BubbleKeyQuestion>>[for (var i = 0; i < cols; i++) questions.skip(i * perCol).take(perCol).toList()];
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (i, chunk) in chunks.indexed) ...[
        Expanded(child: Column(children: [for (final q in chunk) _Row(q: q, form: form, flagged: flagged.contains(q.n), onToggle: onToggle, onDetails: onDetails)])),
        if (i != chunks.length - 1) const SizedBox(width: AppSpace.md),
      ],
    ]);
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.q, required this.form, required this.flagged, required this.onToggle, this.onDetails});
  final BubbleKeyQuestion q;
  final BubbleKeyForm form;
  final bool flagged;
  final void Function(BubbleKeyQuestion q, String letter) onToggle;
  final void Function(BubbleKeyQuestion q)? onDetails;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final chosen = form.key[q.n] ?? const [];
    return Opacity(
      opacity: q.voided ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpace.xxs),
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xs, 2, AppSpace.xxs, 2),
        decoration: BoxDecoration(
          color: flagged ? c.warning.withValues(alpha: 0.10) : c.cardBg,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: flagged ? c.warning : c.divider, width: AppBorder.hairline),
        ),
        child: Row(children: [
          SizedBox(width: 30, child: Text('${q.n}', style: appText(13, w: FontWeight.w800, c: c.textMedium), textAlign: TextAlign.center)),
          Expanded(
            child: Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
              for (final l in q.options)
                _Letter(letter: l, selected: chosen.contains(l), onTap: q.voided ? null : () => onToggle(q, l)),
            ]),
          ),
          if (q.voided) Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs), child: AppTag(t('ملغى', 'Cancelled'), c.textMedium)),
          if (chosen.length > 1) Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs), child: AppTag(q.multiAll ? t('كل المحدد', 'All') : t('أيٌّ منها', 'Any'), c.purple)),
          if (q.points != 1) Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs), child: Text('×${bubbleNumText(q.points)}', style: appText(12, w: FontWeight.w700, c: c.primary))),
          if (onDetails != null)
            IconButton(tooltip: t('إعدادات السؤال', 'Question options'), iconSize: 20, onPressed: () => onDetails!(q), icon: Icon(Icons.more_horiz_rounded, color: c.textLight)),
        ]),
      ),
    );
  }
}

class _Letter extends StatelessWidget {
  const _Letter({required this.letter, required this.selected, required this.onTap});
  final String letter;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: letter,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.of(context).fast,
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? c.primary : c.inputBg,
            border: Border.all(color: selected ? c.primary : c.divider),
          ),
          child: Text(letter, style: appText(13, w: FontWeight.w800, c: selected ? c.onHero : c.textMedium)),
        ),
      ),
    );
  }
}

/// Data Lab: before and after, row by row.
class BubbleLabPreviewView extends StatelessWidget {
  const BubbleLabPreviewView({super.key, required this.preview, this.onSheet});
  final LabPreview preview;
  final void Function(LabRow row)? onSheet;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppTag(t('${preview.changes} ستتغير', '${preview.changes} will change'), c.primary),
        if (preview.overwrites > 0) AppTag(t('${preview.overwrites} فوق درجات موجودة', '${preview.overwrites} overwrite'), c.warning),
        if (preview.blocked > 0) AppTag(t('${preview.blocked} بانتظار المراجعة', '${preview.blocked} await review'), c.textMedium),
      ]),
      const SizedBox(height: AppSpace.sm),
      for (final r in preview.rows) _LabRowView(row: r, onSheet: onSheet),
    ]);
  }
}

class _LabRowView extends StatelessWidget {
  const _LabRowView({required this.row, this.onSheet});
  final LabRow row;
  final void Function(LabRow row)? onSheet;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final blocked = row.blocked != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
      child: Row(children: [
        Expanded(child: Text(row.name ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
        const SizedBox(width: AppSpace.xs),
        Text(bubbleNumText(row.oldValue), style: appText(12, w: FontWeight.w600, c: row.oldValue == null ? c.textLight : c.textMedium)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs), child: Icon(Icons.arrow_forward_rounded, size: 14, color: c.textLight)),
        Text(blocked ? '…' : bubbleNumText(row.newValue), style: appText(12, w: FontWeight.w800, c: blocked ? c.textLight : (row.overwrites ? c.warning : c.primary))),
        if (onSheet != null && row.pageId != null)
          IconButton(tooltip: t('الورقة الأصلية', 'Original sheet'), iconSize: 18, onPressed: () => onSheet!(row), icon: Icon(Icons.image_outlined, color: c.textLight)),
      ]),
    );
  }
}

/// The small action row for buttons kept together in a card.
class BubbleActions extends StatelessWidget {
  const BubbleActions({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: children);
}


/// What the model answer gave (D-671): the questions found and keyed, and the rows to check before correcting.
/// Plain values in, so the layout harness can pump it.
class BubbleKeyReadBanner extends StatelessWidget {
  const BubbleKeyReadBanner({super.key, required this.read, this.onCheck});
  final BubbleKeyRead read;
  final VoidCallback? onCheck;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = read.questions;
    final found = countText(n, ar1: 'سؤال واحد', ar2: 'سؤالين', arFew: '$n أسئلة', arMany: '$n سؤالًا', en1: '1 question', en: '$n questions');
    final printed = read.printed > n ? t(' (من ${read.printed} في الورقة)', ' (of ${read.printed} on the sheet)') : '';
    final ok = read.check.isEmpty;
    final nums = read.check.take(12).map((x) => '${x.n}').join(t('، ', ', '));
    final more = read.check.length > 12 ? ' …' : '';
    return AppCard(
      padding: AppSpace.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.rule_rounded, color: ok ? c.success : c.warning),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text(t('قرأنا الإجابة النموذجية: $found$printed', 'Model answer read: $found$printed'), style: AppType.bodyStrong(context))),
        ]),
        const SizedBox(height: AppSpace.xs),
        Text(
          ok
              ? t('مفتاح الإجابة جاهز لكل الأسئلة. ارفع أوراق الطلاب الآن.', 'The key is ready for every question. Upload the students\' sheets now.')
              : t('هذه الأسئلة غير واضحة في الإجابة النموذجية، أدخل مفتاحها: $nums$more', 'These questions are not clear on the model answer, enter their key: $nums$more'),
          style: AppType.meta(context).copyWith(color: ok ? c.textLight : c.warning),
        ),
        if (!ok && onCheck != null) ...[
          const SizedBox(height: AppSpace.sm),
          Align(alignment: AlignmentDirectional.centerStart, child: AppButton.secondary(label: t('مراجعة المفتاح', 'Check the key'), icon: Icons.key_rounded, onPressed: onCheck)),
        ],
      ]),
    );
  }
}


/// Where a paper's student comes from (D-672): one tile per source, the chosen one marked.
class BubbleIdSourceChoice extends StatelessWidget {
  const BubbleIdSourceChoice({super.key, required this.selected, required this.onPick, this.sources = BubbleIdSource.values});
  final BubbleIdSource selected;
  final ValueChanged<BubbleIdSource> onPick;
  final List<BubbleIdSource> sources;

  static IconData icon(BubbleIdSource s) => switch (s) {
        BubbleIdSource.bubble => Icons.grid_on_rounded,
        BubbleIdSource.image => Icons.draw_rounded,
        BubbleIdSource.fileName => Icons.drive_file_rename_outline_rounded,
        BubbleIdSource.manual => Icons.how_to_reg_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < sources.length; i++) ...[
        if (i > 0) const SizedBox(height: AppSpace.xs),
        SetupChoiceTile(
          key: ValueKey('bubble.idsrc.${sources[i].name}'),
          icon: icon(sources[i]),
          title: bubbleIdSourceLabel(sources[i]),
          subtitle: bubbleIdSourceHint(sources[i]),
          selected: sources[i] == selected,
          onTap: () => onPick(sources[i]),
        ),
      ],
    ]);
  }
}

/// The students of a correction with no course (D-672): how many, the first names, paste a list / edit.
class BubbleStudentsCard extends StatelessWidget {
  const BubbleStudentsCard({super.key, required this.students, this.onPaste, this.onEdit});
  final BubbleStudents students;
  final VoidCallback? onPaste, onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = students.people.length;
    final count = countText(n, ar1: 'طالب واحد', ar2: 'طالبان', arFew: '$n طلاب', arMany: '$n طالبًا', en1: '1 student', en: '$n students');
    final names = students.people.take(4).map((p) => p.label).where((x) => x.isNotEmpty).join(t('، ', ', '));
    return AppCard(
      padding: AppSpace.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.groups_2_rounded, color: c.primary),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text(t('طلاب هذا التصحيح', 'Students of this correction'), style: AppType.section(context))),
        ]),
        const SizedBox(height: AppSpace.xs),
        Text(
          n == 0
              ? t('بلا مقرر: يُضاف كل طالب من ورقته، أو الصق قائمة الطلاب الآن.', "No course: each student is added from their paper, or paste the class list now.")
              : '$count${names.isEmpty ? '' : ' · $names${n > 4 ? '…' : ''}'}',
          style: AppType.meta(context).copyWith(color: c.textMedium),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          if (onPaste != null) AppButton.secondary(key: const ValueKey('bubble.people.paste'), label: t('لصق قائمة الطلاب', 'Paste the class list'), icon: Icons.content_paste_rounded, onPressed: onPaste),
          if (onEdit != null && n > 0) AppButton.ghost(key: const ValueKey('bubble.people.edit'), label: t('تعديل الأسماء', 'Edit names'), icon: Icons.edit_rounded, onPressed: onEdit),
        ]),
      ]),
    );
  }
}

/// Where the student's ID comes from, on the correction's page; [boxSet]: the name area is marked (written source).
class BubbleIdSourceCard extends StatelessWidget {
  const BubbleIdSourceCard({super.key, required this.source, this.boxSet = false, this.onChange, this.onMarkBox});
  final BubbleIdSource source;
  final bool boxSet;
  final VoidCallback? onChange, onMarkBox;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final needsBox = source == BubbleIdSource.image && !boxSet;
    return AppCard(
      padding: AppSpace.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(BubbleIdSourceChoice.icon(source), color: needsBox ? c.warning : c.primary),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('رقم الطالب', "The student's ID"), style: AppType.meta(context).copyWith(color: c.textMedium)),
              Text(bubbleIdSourceLabel(source), style: AppType.bodyStrong(context)),
            ]),
          ),
          if (onChange != null) AppButton.ghost(key: const ValueKey('bubble.idsrc.change'), size: AppButtonSize.sm, label: t('تغيير', 'Change'), onPressed: onChange),
        ]),
        if (source == BubbleIdSource.image && onMarkBox != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text(
            needsBox ? t('حدّد على الورقة مكان الاسم أو الرقم المكتوب.', 'Mark on the sheet where the name or ID is written.') : t('مكان الاسم محدد.', 'The name area is marked.'),
            style: AppType.meta(context).copyWith(color: needsBox ? c.warning : c.textMedium),
          ),
          const SizedBox(height: AppSpace.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.secondary(key: const ValueKey('bubble.idsrc.box'), label: needsBox ? t('تحديد مكان الاسم', 'Mark the name area') : t('تعديل المكان', 'Change the area'), icon: Icons.crop_free_rounded, onPressed: onMarkBox),
          ),
        ],
      ]),
    );
  }
}

/// Drag a box over the sheet where the name / ID is written. [onDone] gets [x, y, w, h] as shares of the picture.
class BubbleBoxPicker extends StatefulWidget {
  const BubbleBoxPicker({super.key, required this.image, this.initial, required this.onDone});
  final Uint8List image;
  final List<double>? initial;
  final ValueChanged<List<double>> onDone;

  @override
  State<BubbleBoxPicker> createState() => _BubbleBoxPickerState();
}

class _BubbleBoxPickerState extends State<BubbleBoxPicker> {
  Rect? _box;            // shares of the picture
  Offset? _start;

  @override
  void initState() {
    super.initState();
    final b = widget.initial;
    if (b != null) _box = Rect.fromLTWH(b[0], b[1], b[2], b[3]);
  }

  Offset _share(Offset p, Size s) => Offset((p.dx / s.width).clamp(0.0, 1.0), (p.dy / s.height).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final box = _box;
    final ok = box != null && box.width >= 0.02 && box.height >= 0.01;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('اسحب مستطيلًا حول مكان الاسم أو الرقم المكتوب', 'Drag a box around where the name or ID is written'), style: AppType.body(context)),
      const SizedBox(height: AppSpace.sm),
      LayoutBuilder(builder: (context, cons) {
        return Image.memory(widget.image, fit: BoxFit.fitWidth, width: cons.maxWidth, frameBuilder: (context, child, frame, _) {
          return LayoutBuilder(builder: (context, inner) {
            return GestureDetector(
              key: const ValueKey('bubble.box.area'),
              onPanStart: (d) {
                final size = context.size ?? Size(cons.maxWidth, cons.maxWidth);
                _start = _share(d.localPosition, size);
                setState(() => _box = Rect.fromPoints(_start!, _start!));
              },
              onPanUpdate: (d) {
                final size = context.size ?? Size(cons.maxWidth, cons.maxWidth);
                if (_start != null) setState(() => _box = Rect.fromPoints(_start!, _share(d.localPosition, size)));
              },
              child: Stack(children: [
                child,
                if (box != null)
                  Positioned.fill(
                    child: LayoutBuilder(builder: (context, s) {
                      return CustomPaint(painter: _BoxPainter(Rect.fromLTWH(box.left * s.maxWidth, box.top * s.maxHeight, box.width * s.maxWidth, box.height * s.maxHeight), c.primary));
                    }),
                  ),
              ]),
            );
          });
        });
      }),
      const SizedBox(height: AppSpace.md),
      AppButton.primary(
        key: const ValueKey('bubble.box.save'),
        label: t('حفظ المكان', 'Save the area'),
        icon: Icons.check_rounded,
        expand: true,
        onPressed: ok ? () => widget.onDone([box.left, box.top, box.width, box.height]) : null,
      ),
    ]);
  }
}

class _BoxPainter extends CustomPainter {
  _BoxPainter(this.rect, this.color);
  final Rect rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.15));
    canvas.drawRect(rect, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_BoxPainter old) => old.rect != rect || old.color != color;
}
