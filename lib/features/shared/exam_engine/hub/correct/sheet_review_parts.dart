// The corrected sheet's presentational widgets (Exam Hub, F4): plain values in, callbacks out, so the layout harness and
// the visual renders pump them directly. SheetReviewView is the whole screen; sheet_review_screen.dart feeds it.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_display.dart' show syncMotionLoop;
import 'package:flutter_education_app/design/app_kit.dart';

import '../../../../admin/admin_common.dart' show t;
import 'sheet_models.dart';
import 'sheet_painter.dart';

/// Below this width the photo is the whole screen and the questions open in a sheet.
const kSheetSidePanelWidth = 900.0;

SheetMarkColors sheetMarkColors(BuildContext context) {
  final c = context.colors;
  return SheetMarkColors(right: c.success, wrong: c.danger, open: c.warning, key: c.primary, chip: c.heroShade, onChip: c.onHero);
}

/// "Question 7"'s list row, the degree and how it went, in words as well as in colour.
String sheetAnswerText(List<String> letters) => letters.isEmpty ? t('بدون إجابة', 'No answer') : letters.join(t('، ', ', '));

// ── the photo ───────────────────────────────────────────────────────────────────────────────────────────────────

/// The real photo, fitted and zoomable, with the marks over it. Tapping a row asks to correct that question.
class SheetPhotoStage extends StatelessWidget {
  const SheetPhotoStage({super.key, this.bytes, this.view, this.scanning = false, this.focusN, this.onQuestion, this.padding = EdgeInsets.zero});

  final Uint8List? bytes;

  /// The corrected sheet (null: nothing known yet).
  final SheetView? view;

  /// The photo waits for its reading: the sweep runs over it.
  final bool scanning;
  final int? focusN;
  final ValueChanged<int>? onQuestion;

  /// Room left for the glass bars, so nothing of the paper hides under them.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = view;
    return Padding(
      padding: padding,
      child: LayoutBuilder(builder: (context, box) {
        final size = box.biggest;
        return InteractiveViewer(
          key: const ValueKey('sheet.photo'),
          minScale: 1,
          maxScale: 6,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: v == null || onQuestion == null
                ? null
                : (d) {
                    final n = sheetHitQuestion(d.localPosition, v, size);
                    if (n != null) onQuestion!(n);
                  },
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Stack(fit: StackFit.expand, children: [
                if (bytes != null)
                  Image.memory(bytes!, fit: BoxFit.contain, gaplessPlayback: true, errorBuilder: (_, _, _) => _NoPhoto(color: c.onHeroMuted))
                else
                  _NoPhoto(color: c.onHeroMuted),
                if (v != null && v.ready && v.canDraw)
                  RepaintBoundary(
                    child: CustomPaint(
                      key: const ValueKey('sheet.marks'),
                      painter: SheetMarksPainter(
                        questions: v.questions,
                        source: v.source!,
                        colors: sheetMarkColors(context),
                        degreeStyle: appText(9.5, w: FontWeight.w800),
                        focusN: focusN,
                      ),
                    ),
                  ),
                if (scanning) const IgnorePointer(child: _ScanSweep()),
              ]),
            ),
          ),
        );
      }),
    );
  }
}

class _NoPhoto extends StatelessWidget {
  const _NoPhoto({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Center(child: Icon(Icons.description_outlined, size: AppIconSize.hero, color: color));
}

/// A soft band sweeping down the photo while it is read. Parked under Reduce motion (the "Reading" pill still speaks).
class _ScanSweep extends StatefulWidget {
  const _ScanSweep();

  @override
  State<_ScanSweep> createState() => _ScanSweepState();
}

class _ScanSweepState extends State<_ScanSweep> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _c, rest: .5);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tone = context.colors.primary;
    return AnimatedBuilder(animation: _c, builder: (_, _) => CustomPaint(painter: _SweepPainter(_c.value, tone)));
  }
}

class _SweepPainter extends CustomPainter {
  const _SweepPainter(this.t, this.tone);
  final double t;
  final Color tone;

  @override
  void paint(Canvas canvas, Size size) {
    final band = size.height * .22;
    final y = -band + (size.height + band) * t;
    final r = Rect.fromLTWH(0, y, size.width, band);
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tone.withValues(alpha: 0), tone.withValues(alpha: .30), tone.withValues(alpha: 0)],
        ).createShader(r),
    );
  }

  @override
  bool shouldRepaint(covariant _SweepPainter o) => o.t != t || o.tone != tone;
}

// ── glass ───────────────────────────────────────────────────────────────────────────────────────────────────────

class _Glass extends StatelessWidget {
  const _Glass({required this.child, this.radius = AppRadius.sheet, this.padding = const EdgeInsets.all(AppSpace.sm)});
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: c.heroShade.withValues(alpha: .62),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: c.heroGlassBorder),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onTap, super.key});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IconButton(
      tooltip: label,
      constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
      onPressed: onTap,
      icon: Icon(icon, color: onTap == null ? c.onHeroFaint : c.onHero),
    );
  }
}

/// A number with its sign in icon form, on glass ("✓ 17").
class _CountChip extends StatelessWidget {
  const _CountChip({required this.icon, required this.value, required this.color, this.semantics});
  final IconData icon;
  final String value;
  final Color color;
  final String? semantics;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: semantics,
      child: ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: AppIconSize.sm, color: color),
          const SizedBox(width: AppSpace.xxs),
          Text(value, style: appText(13, w: FontWeight.w700, c: c.onHero)),
        ]),
      ),
    );
  }
}

/// Top glass strip: who this paper belongs to and the total, large.
class SheetTopStrip extends StatelessWidget {
  const SheetTopStrip({
    super.key,
    required this.name,
    this.identifier,
    this.position,
    this.score,
    this.max,
    this.right,
    this.wrong,
    this.review = 0,
    this.reading = false,
    this.onBack,
    this.onReview,
  });

  final String name;
  final String? identifier;

  /// "Paper 3 of 12".
  final String? position;
  final double? score, max;
  final int? right, wrong;
  final int review;

  /// The paper is still being read: no number yet.
  final bool reading;
  final VoidCallback? onBack;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sub = [if ((identifier ?? '').isNotEmpty) identifier!, if ((position ?? '').isNotEmpty) position!].join(' · ');
    return _Glass(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xxs, AppSpace.xs, AppSpace.md, AppSpace.xs),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _RoundButton(icon: Icons.arrow_back_rounded, label: t('رجوع', 'Back'), onTap: onBack),
          const SizedBox(width: AppSpace.xxs),
          Expanded(
            flex: 3,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(name, key: const ValueKey('sheet.name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(16, w: FontWeight.w800, c: c.onHero)),
              if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.onHeroMuted)),
            ]),
          ),
          const SizedBox(width: AppSpace.sm),
          if (reading)
            Text(t('تُقرأ…', 'Reading…'), style: appText(14, w: FontWeight.w700, c: c.onHeroMuted))
          else
            Flexible(
              flex: 2,
              child: Semantics(
              label: t('الدرجة ${score == null ? '' : sheetNum(score!)} من ${max == null ? '' : sheetNum(max!)}', 'Score ${score == null ? '' : sheetNum(score!)} of ${max == null ? '' : sheetNum(max!)}'),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: ExcludeSemantics(
                child: Directionality(textDirection: TextDirection.ltr, child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, mainAxisSize: MainAxisSize.min, children: [
                  Text(score == null ? '–' : sheetNum(score!), key: const ValueKey('sheet.total'), style: appText(32, w: FontWeight.w800, c: c.onHero, h: 1.05)),
                  if (max != null) Text(' / ${sheetNum(max!)}', style: appText(14.5, w: FontWeight.w600, c: c.onHeroMuted)),
                ])),
                ),
              ),
              ),
            ),
        ]),
        if (!reading && ((right ?? 0) + (wrong ?? 0) > 0 || review > 0))
          Padding(
            padding: const EdgeInsetsDirectional.only(start: AppTouch.min + AppSpace.xxs, top: AppSpace.xxs),
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpace.sm, runSpacing: AppSpace.xxs, children: [
              if ((right ?? 0) > 0) _CountChip(icon: Icons.check_circle_rounded, value: '$right', color: c.success, semantics: t('$right صحيحة', '$right right')),
              if ((wrong ?? 0) > 0) _CountChip(icon: Icons.cancel_rounded, value: '$wrong', color: c.danger, semantics: t('$wrong خاطئة', '$wrong wrong')),
              if (review > 0)
                InkWell(
                  key: const ValueKey('sheet.review'),
                  borderRadius: BorderRadius.circular(AppRadius.hero),
                  onTap: onReview,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 32),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                    decoration: BoxDecoration(color: c.warning, borderRadius: BorderRadius.circular(AppRadius.hero)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.rate_review_rounded, size: AppIconSize.sm, color: c.charcoalDark),
                      const SizedBox(width: AppSpace.xxs),
                      Text(t('$review للمراجعة', '$review to review'), style: appText(12.5, w: FontWeight.w800, c: c.charcoalDark)),
                    ]),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }
}

/// The bottom glass bar: previous · (questions) · Finish · Next, which becomes "Next paper" with the camera on the last.
class SheetBottomBar extends StatelessWidget {
  const SheetBottomBar({super.key, this.onPrev, this.onNext, this.nextIsCamera = false, this.onFinish, this.onQuestions, this.onRetake});

  final VoidCallback? onPrev, onNext, onFinish, onQuestions;
  final bool nextIsCamera;

  /// "Retake": offered when a better photo is suggested.
  final VoidCallback? onRetake;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      final tight = box.maxWidth < 420;
      return _Glass(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
        child: Row(children: [
          _RoundButton(key: const ValueKey('sheet.prev'), icon: Icons.arrow_back_rounded, label: t('الطالب السابق', 'Previous student'), onTap: onPrev),
          if (onQuestions != null)
            _RoundButton(key: const ValueKey('sheet.questions'), icon: Icons.format_list_numbered_rounded, label: t('الأسئلة', 'Questions'), onTap: onQuestions),
          if (onRetake != null)
            _RoundButton(key: const ValueKey('sheet.retake'), icon: Icons.camera_enhance_rounded, label: t('إعادة التصوير', 'Retake'), onTap: onRetake),
          if (onFinish != null)
            tight
                ? _RoundButton(key: const ValueKey('sheet.finish'), icon: Icons.done_all_rounded, label: t('إنهاء', 'Finish'), onTap: onFinish)
                : TextButton.icon(
                    key: const ValueKey('sheet.finish'),
                    style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min), foregroundColor: c.onHero),
                    onPressed: onFinish,
                    icon: const Icon(Icons.done_all_rounded, size: AppIconSize.md),
                    label: Text(t('إنهاء', 'Finish'), maxLines: 1),
                  ),
          const SizedBox(width: AppSpace.xxs),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                key: const ValueKey('sheet.next'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(AppTouch.min, AppTouch.min),
                  padding: EdgeInsets.symmetric(horizontal: tight ? AppSpace.xs : AppSpace.md),
                  backgroundColor: c.primary,
                  foregroundColor: c.onHero,
                ),
                onPressed: onNext,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(nextIsCamera ? Icons.photo_camera_rounded : Icons.arrow_forward_rounded, size: AppIconSize.md),
                  const SizedBox(width: AppSpace.xxs),
                  Flexible(child: Text(nextIsCamera ? t('الورقة التالية', 'Next paper') : t('التالي', 'Next'), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ),
            ),
          ),
        ]),
      );
    });
  }
}

// ── the questions ───────────────────────────────────────────────────────────────────────────────────────────────

class SheetQuestionsList extends StatelessWidget {
  const SheetQuestionsList({super.key, required this.questions, this.onQuestion, this.focusN, this.shrinkWrap = false});
  final List<SheetQuestion> questions;
  final ValueChanged<int>? onQuestion;
  final int? focusN;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (questions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Text(t('لا توجد درجات لهذه الورقة بعد', 'No marks for this paper yet'), textAlign: TextAlign.center, style: appText(14, c: c.textMedium)),
      );
    }
    return ListView.separated(
      key: const ValueKey('sheet.list'),
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      itemCount: questions.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: c.divider),
      itemBuilder: (context, i) {
        final q = questions[i];
        final (tone, icon, how) = switch (q.tone) {
          SheetTone.right => (c.success, Icons.check_circle_rounded, t('صحيحة', 'Right')),
          SheetTone.wrong => (c.danger, Icons.cancel_rounded, t('خاطئة', 'Wrong')),
          SheetTone.open => (c.warning, Icons.rate_review_rounded, t('للمراجعة', 'To review')),
        };
        return Semantics(
          button: onQuestion != null,
          label: t('السؤال ${q.n}: $how. الدرجة ${q.degreeText}', 'Question ${q.n}: $how. Degree ${q.degreeText}'),
          child: InkWell(
            key: ValueKey('sheet.q.${q.n}'),
            onTap: onQuestion == null ? null : () => onQuestion!(q.n),
            child: Container(
              constraints: const BoxConstraints(minHeight: AppTouch.primary),
              color: q.n == focusN ? c.primaryTint : null,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
              child: ExcludeSemantics(
                child: Row(children: [
                  Icon(icon, color: appInk(context, tone), size: AppIconSize.lg),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t('السؤال ${q.n}', 'Question ${q.n}'), style: appText(14.5, w: FontWeight.w700, c: c.textDark)),
                      Text(
                        q.isCorrect == true
                            ? t('إجابة الطالب: ${sheetAnswerText(q.selected)}', 'Answer: ${sheetAnswerText(q.selected)}')
                            : t('إجابة الطالب: ${sheetAnswerText(q.selected)} · الصحيحة: ${sheetAnswerText(q.correct)}',
                                'Answer: ${sheetAnswerText(q.selected)} · Right: ${sheetAnswerText(q.correct)}'),
                        style: appText(12.5, c: c.textMedium, h: 1.3),
                      ),
                    ]),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  Directionality(textDirection: TextDirection.ltr, child: Text(q.degreeText, style: appText(15, w: FontWeight.w800, c: c.textDark))),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// What the rectangles mean: the shapes say it, not only the colours.
class SheetLegend extends StatelessWidget {
  const SheetLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget item(IconData i, Color tone, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: AppIconSize.sm, color: appInk(context, tone)),
          const SizedBox(width: AppSpace.xxs),
          Flexible(child: Text(label, style: appText(12, c: c.textMedium))),
        ]);
    return Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, children: [
      item(Icons.check_box_outlined, c.success, t('إجابة صحيحة', 'Right answer')),
      item(Icons.disabled_by_default_outlined, c.danger, t('إجابة خاطئة', 'Wrong answer')),
      item(Icons.crop_din_rounded, c.primary, t('المتقطع: الإجابة الصحيحة', 'Dashed: the right answer')),
    ]);
  }
}

// ── the whole screen ────────────────────────────────────────────────────────────────────────────────────────────

/// Everything the screen shows, as plain values.
class SheetReviewView extends StatelessWidget {
  const SheetReviewView({
    super.key,
    required this.waitingName,
    this.view,
    this.photo,
    this.position,
    this.error,
    this.notBubble = false,
    this.focusN,
    this.onBack,
    this.onPrev,
    this.onNext,
    this.nextIsCamera = false,
    this.onFinish,
    this.onQuestion,
    this.onReview,
    this.onRetake,
    this.onRetry,
    this.onWritten,
  });

  /// The student's name known from the batch list, or the screen's own "Reading…" line, while [view] is not ready.
  final String waitingName;
  final SheetView? view;
  final Uint8List? photo;
  final String? position;

  /// The sheet could not be fetched.
  final String? error;

  /// 409 exam_not_bubble: this exam has no bubble sheets to draw.
  final bool notBubble;
  final int? focusN;
  final VoidCallback? onBack, onPrev, onNext, onFinish, onReview, onRetake, onRetry, onWritten;
  final bool nextIsCamera;
  final ValueChanged<int>? onQuestion;

  bool get _ready => view?.ready ?? false;
  bool get _dead => view?.dead ?? false;
  bool get _reading => view == null || (!_ready && !_dead);

  Future<void> _openList(BuildContext context) => showAppSheet<void>(
        context,
        (ctx) => AppSheetContent(title: t('الأسئلة', 'Questions'), children: [
          const SheetLegend(),
          SheetQuestionsList(
            questions: view?.questions ?? const [],
            shrinkWrap: true,
            focusN: focusN,
            onQuestion: onQuestion == null
                ? null
                : (n) {
                    Navigator.of(ctx).pop();
                    onQuestion!(n);
                  },
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (notBubble) {
      return Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(title: Text(t('الورقة', 'Paper'))),
        body: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: AppEmpty(
            icon: Icons.history_edu_rounded,
            title: t('هذا الاختبار ليس بورقة تظليل', 'This exam does not use a bubble sheet'),
            message: t('تُراجع أوراقه الممسوحة من صفحة التصحيح الكتابي.', 'Its scanned papers are checked on the written correction page.'),
            actionLabel: t('فتح التصحيح الكتابي', 'Open written correction'),
            onAction: onWritten,
          ),
        ),
      );
    }
    final v = view;
    final safe = MediaQuery.paddingOf(context);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= kSheetSidePanelWidth;
      final noBoxes = _ready && !(v?.canDraw ?? false);
      final inlineList = noBoxes && !wide;
      final stage = SheetPhotoStage(
        bytes: photo,
        view: v,
        scanning: _reading && error == null,
        focusN: focusN,
        onQuestion: _ready ? onQuestion : null,
        padding: EdgeInsets.only(top: safe.top + 116, bottom: inlineList ? AppSpace.xs : safe.bottom + 84),
      );
      final top = Positioned(
        left: AppSpace.xs,
        right: AppSpace.xs,
        top: safe.top + AppSpace.xs,
        child: SheetTopStrip(
          name: _ready ? ((v!.studentName ?? '').isNotEmpty ? v.studentName! : t('طالب غير محدد', 'Student not identified')) : waitingName,
          identifier: v?.identifier,
          position: position,
          score: v?.score,
          max: v?.max,
          right: _ready ? v!.rightCount : null,
          wrong: _ready ? v!.wrongCount : null,
          review: v?.reviewCount ?? 0,
          reading: !_ready,
          onBack: onBack,
          onReview: onReview,
        ),
      );
      final centerNote = _dead
          ? _DeadNote(onRetake: onRetake)
          : error != null
              ? _ErrorNote(message: error!, onRetry: onRetry)
              : _reading
                  ? const _ReadingPill()
                  : noBoxes && !inlineList
                      ? null
                      : null;
      final bottom = SheetBottomBar(
        onPrev: onPrev,
        onNext: onNext,
        nextIsCamera: nextIsCamera,
        onFinish: onFinish,
        onQuestions: _ready && !wide && !inlineList ? () => _openList(context) : null,
        onRetake: _ready ? onRetake : null,
      );
      final stageArea = Stack(children: [
        Positioned.fill(child: stage),
        top,
        if (centerNote != null)
          Positioned(left: AppSpace.md, right: AppSpace.md, bottom: safe.bottom + 88, child: Center(child: centerNote)),
        if (!inlineList)
          Positioned(left: AppSpace.xs, right: AppSpace.xs, bottom: safe.bottom + AppSpace.xs, child: bottom),
      ]);
      if (wide) {
        return ColoredBox(
          color: c.charcoalDark,
          child: Row(children: [
            Expanded(child: stageArea),
            SizedBox(
              width: 380,
              child: Material(
                color: c.cardBg,
                child: SafeArea(
                  left: false,
                  right: false,
                  child: _SidePanel(view: v, ready: _ready, focusN: focusN, onQuestion: onQuestion, noBoxes: noBoxes),
                ),
              ),
            ),
          ]),
        );
      }
      if (inlineList) {
        return ColoredBox(
          color: c.charcoalDark,
          child: Column(children: [
            Expanded(flex: 5, child: stageArea),
            Expanded(
              flex: 6,
              child: Material(
                color: c.cardBg,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
                    child: Text(t('هذه الورقة بلا مواضع على الصورة: الدرجات هنا', 'This paper has no positions on the photo: the marks are here'),
                        style: appText(13, c: c.textMedium, h: 1.35)),
                  ),
                  Expanded(child: SheetQuestionsList(questions: v?.questions ?? const [], onQuestion: onQuestion, focusN: focusN)),
                  Padding(padding: EdgeInsets.fromLTRB(AppSpace.xs, 0, AppSpace.xs, safe.bottom + AppSpace.xs), child: bottom),
                ]),
              ),
            ),
          ]),
        );
      }
      return ColoredBox(color: c.charcoalDark, child: stageArea);
    });
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.view, required this.ready, this.focusN, this.onQuestion, this.noBoxes = false});
  final SheetView? view;
  final bool ready;
  final int? focusN;
  final ValueChanged<int>? onQuestion;
  final bool noBoxes;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (!ready) {
      return const Padding(padding: EdgeInsets.all(AppSpace.md), child: AppListSkeleton(items: 8, withAvatar: false));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xs),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('الأسئلة', 'Questions'), style: appText(17, w: FontWeight.w800, c: c.textDark)),
          const SizedBox(height: AppSpace.xxs),
          if (noBoxes)
            Text(t('هذه الورقة بلا مواضع على الصورة: الدرجات هنا', 'This paper has no positions on the photo: the marks are here'),
                style: appText(13, c: c.textMedium, h: 1.35))
          else
            const SheetLegend(),
        ]),
      ),
      Divider(height: 1, color: c.divider),
      Expanded(child: SheetQuestionsList(questions: view?.questions ?? const [], onQuestion: onQuestion, focusN: focusN)),
    ]);
  }
}

class _ReadingPill extends StatelessWidget {
  const _ReadingPill();

  @override
  Widget build(BuildContext context) => _Glass(
        radius: AppRadius.hero,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
        child: Semantics(
          liveRegion: true,
          child: Text(t('تُقرأ الورقة… يمكنك تصوير الورقة التالية', 'Reading this paper… you can shoot the next one'),
              key: const ValueKey('sheet.reading'), textAlign: TextAlign.center, style: appText(14, w: FontWeight.w700, c: context.colors.onHero)),
        ),
      );
}

class _DeadNote extends StatelessWidget {
  const _DeadNote({this.onRetake});
  final VoidCallback? onRetake;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: AppCard(
        key: const ValueKey('sheet.dead'),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('تعذّرت قراءة هذه الورقة', "This paper couldn't be read"), style: appText(16, w: FontWeight.w800, c: c.textDark)),
          const SizedBox(height: AppSpace.xxs),
          Text(t('لم تُصحَّح. صوّرها مرة أخرى في إضاءة جيدة.', 'It was not graded. Take it again in good light.'), style: appText(13.5, c: c.textMedium, h: 1.35)),
          if (onRetake != null) ...[
            const SizedBox(height: AppSpace.sm),
            AppPrimaryButton(label: t('إعادة التصوير', 'Retake'), icon: Icons.camera_alt_rounded, onPressed: onRetake),
          ],
        ]),
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: AppCard(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(message, style: appText(14.5, w: FontWeight.w700, c: c.textDark, h: 1.35)),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpace.sm),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(t('إعادة المحاولة', 'Try again')),
            ),
          ],
        ]),
      ),
    );
  }
}
