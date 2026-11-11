// lib/features/shared/course/course_list_card.dart
//
// THE course card of every course list — the student's "My courses", the catalogue, favourites, categories and
// public profiles (through CourseCard in course_row.dart) and the teacher's "My courses" — so both roles read the
// same card. Plain values only (no provider, no model): each screen maps its own course into it.
//
//   phone (< 600 px)  → CourseCardShape.row:  a slim media row, picture on the start side, the text beside it
//   wider             → CourseCardShape.tile: a grid tile, 16:9 cover on top (CourseCardSliver picks columns)
//
//   ┌──────────────────────────────────┐     ┌───────────────┐
//   │ ┌──────┐ Title over two lines  ♥ │     │ [Live]      ⋮ │ ← cover: at most two overlays
//   │ │ pic  │ Teacher · 12 lessons    │     │     cover     │   (type / status chip · heart or menu)
//   │ └[Live]┘ ━━━━━━━━━━━━━━━── 40%   │     ├───────────────┤
//   └──────────────────────────────────┘     │ Title, 2 lines│
//                                            │ meta line     │
//                                            │ footer        │ ← progress · price · teacher figures
//                                            └───────────────┘
//
// A grid row is as tall as its tallest tile (CourseCardSliver lays each row out by its content): a lone tile or a
// row of one-line titles has no blank band between the meta line and the footer; a footer sits at the bottom of
// its row so the row's footers line up. Under a fixed height (another screen's SliverGrid) the footer still sits
// at the bottom and a long title gives way first.
//
// Editorial theme (D-610 – D-629): paper on a warm hairline, radius `card`, no resting shadow; the title in the
// editorial serif (AppType.section), meta in the UI sans; the card leans a little under the pointer (AppTilt.subtle)
// and its cover drifts against the scroll (AppParallaxImage). A course with no picture gets a BOOK cover: a block
// tone picked by its title (AppBlockTone.forKey, the same tone on every screen), a spine on the start edge and the
// title's first letter set large in the editorial face. One accent per card. Premium dashboard (D-631): a tile's cover
// is an inset picture with its own rounded corners inside the paper card (the reference's course cards), and the
// price reads in the primary ink. The header
// parts of a course list (CourseSearchField, CourseSegments) and its states (CourseListSkeleton, CourseListEmpty,
// CourseListError) live here too, so the two screens build the same calm block.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_charts.dart' show appCompactNumber;
import 'package:flutter_education_app/design/app_badges.dart' show AppStatusBadge, AppTone;
import 'package:flutter_education_app/design/app_blocks.dart';
import 'package:flutter_education_app/design/app_depth.dart' show AppParallaxImage;
import 'package:flutter_education_app/design/app_inputs.dart' show appFieldDecoration, appFieldTextStyle;
import 'package:flutter_education_app/design/app_kit.dart' show AppShimmer, AppSkeletonBox;
import 'package:flutter_education_app/design/app_states.dart' show AppEmpty, AppErrorState;
import 'package:flutter_education_app/design/app_tabs.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';

enum CourseCardShape { row, tile }

/// Rows on a phone, tiles in a grid once the list is 600 px wide.
CourseCardShape courseCardShapeFor(double width) => width < 600 ? CourseCardShape.row : CourseCardShape.tile;

/// Grid columns for the tile shape.
int courseGridColumns(double width) => width >= 1040 ? 4 : (width >= 760 ? 3 : 2);

/// The text scale used to size a tile (the harness checks 1.3; very large scales clip the title, never overflow).
double _scale(BuildContext context) => (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 1.6).toDouble();

/// The theme's primary as ink that stays readable: on a dark surface it is lifted toward the text colour (a deep
/// navy primary disappears on a dark card).
Color coursePrimaryInk(BuildContext context) {
  final c = context.colors;
  return c.isDark ? Color.lerp(c.primary, c.textDark, 0.55)! : c.primary;
}

/// "12 sessions" in the current language (Arabic plural forms) — the course page's word for every lecture and
/// section ("Session").
String courseLessonsLabel(int n) {
  final key = n == 1
      ? 'course_list_lessons_1'
      : n == 2
          ? 'course_list_lessons_2'
          : (n >= 3 && n <= 10 ? 'course_list_lessons_few' : 'course_list_lessons_many');
  return key.tr.replaceAll('{n}', '$n');
}

/// "12 h".
String courseHoursLabel(num h) => 'course_list_hours'.tr.replaceAll('{n}', h.round().toString());

/// The ONE letter a book cover carries: the first letter of the first word, after the Arabic article "ال" (every
/// "ال…" title would draw the same alef). Empty for an empty title.
String courseInitialOf(String title) {
  final words = title.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '';
  final w = words.first;
  final stem = w.startsWith('ال') && w.characters.length > 3 ? w.substring(2) : w;
  return stem.characters.first.toUpperCase();
}

/// The cover of a course with no picture: a book. Its block tone comes from [toneKey] (the title in a list; the
/// same course keeps its tone on every screen), a spine runs down the start edge, and [label]'s first letter is set
/// large in the editorial face; without a [label] a quiet book glyph stands in for it. Decorative: never read out.
class CourseCoverArt extends StatelessWidget {
  const CourseCoverArt({
    super.key,
    required this.seed,
    this.width,
    this.height,
    this.iconSize = AppIconSize.xl,
    this.label,
    this.toneKey,
  });

  final int seed;
  final double? width, height;
  final double iconSize;

  /// The title whose first letter the cover carries.
  final String? label;

  /// What picks the block tone (default: [seed]).
  final String? toneKey;

  /// The spine's width, as a share of the cover's shorter side.
  static const double _spine = 0.07;

  /// The letter's line box, as a share of the cover's height (a little less on a small thumbnail, where it sits
  /// above the chip at the bottom).
  static const double _letter = 0.62, _letterSmall = 0.56;

  /// Below this height a cover is a thumbnail.
  static const double _small = 120;

  @override
  Widget build(BuildContext context) {
    final tone = AppBlockTone.forKey(toneKey ?? 'course-$seed');
    final b = AppBlockColors.of(context, tone);
    final initial = label == null ? '' : courseInitialOf(label!);
    final spine = Color.lerp(b.surface, b.ink, context.colors.isDark ? 0.10 : 0.08)!;
    return ExcludeSemantics(
      child: SizedBox(
        width: width ?? double.infinity,
        height: height,
        child: ColoredBox(
          color: b.surface,
          child: LayoutBuilder(builder: (context, box) {
            final short = box.hasBoundedHeight ? math.min(box.maxWidth, box.maxHeight) : box.maxWidth;
            return Stack(children: [
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                width: short.isFinite ? short * _spine : AppSpace.xs,
                child: ColoredBox(color: spine),
              ),
              Positioned.fill(
                child: initial.isEmpty || !box.hasBoundedHeight
                    ? Center(child: Icon(Icons.auto_stories_rounded, size: iconSize, color: b.muted))
                    : Align(
                        alignment: box.maxHeight < _small ? const Alignment(0, -0.7) : Alignment.center,
                        child: SizedBox(
                          height: box.maxHeight * (box.maxHeight < _small ? _letterSmall : _letter),
                          // the whole line box is scaled, so an Arabic letter's tail is never cut
                          child: FittedBox(child: Text(initial, style: AppType.display(context).copyWith(color: b.muted))),
                        ),
                      ),
              ),
            ]);
          }),
        ),
      ),
    );
  }
}

/// One course in a list. [corner] is the heart (student) or the ⋮ menu (teacher); [chip] the type / status chip;
/// [metaLead] leads the meta line (the organization badge of a mixed list); [footer] is the role's last line.

class CourseListCard extends StatelessWidget {
  const CourseListCard({
    super.key,
    required this.shape,
    required this.title,
    required this.imageUrl,
    required this.footer,
    this.heroTag,
    this.chip,
    this.corner,
    this.meta = const [],
    this.metaLead,
    this.isPrivate = false,
    this.onTap,
  });

  final CourseCardShape shape;
  final String title;
  final String imageUrl;
  final String? heroTag;
  final Widget? chip;
  final Widget? corner;
  final List<String> meta;
  final Widget? metaLead;
  final bool isPrivate;
  final Widget footer;
  final VoidCallback? onTap;

  /// The text block and footer under a tile's cover at text scale 1 (two editorial title lines, the meta line, the
  /// footer and the insets).
  static const double _tileText = 148;

  /// Row height is the content's; a tile's height for a grid cell of [width] is this (the cover is inset by
  /// [_RenderTileLayout.inset] on its three outer sides).
  static double tileHeight(BuildContext context, double width) =>
      (width - 2 * _RenderTileLayout.inset) * 9 / 16 + _RenderTileLayout.inset + _tileText * _scale(context);

  /// The phone row's picture.
  static const Size _thumb = Size(104, 80);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = AppRadius.cardAll;
    // depth (D-620): leans 2 degrees under the mouse, presses in on touch; the cover drifts with the scroll
    return AppTilt.subtle(
      radius: AppRadius.card,
      child: Material(
        color: c.cardBg,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.divider, width: AppBorder.hairline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: shape == CourseCardShape.row ? _row(context) : _tile(context),
        ),
      ),
    );
  }

  Widget _title(BuildContext context) => Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppType.section(context),
      );

  Widget _meta(BuildContext context) {
    final c = context.colors;
    final style = AppType.meta(context).copyWith(height: 1.4);
    // each part in its own direction: an English teacher name beside an Arabic count read "12 Dr. Mona Adel · جلسة"
    final text = meta.where((m) => m.trim().isNotEmpty).map(bidiIsolate).join('  ·  ');
    return Row(children: [
      if (isPrivate)
        ParentComponent(
          featureKey: 'course_card.private_flag',
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: AppSpace.xxs),
            child: Tooltip(
              message: 'private'.tr,
              child: Icon(Icons.lock_outline_rounded, size: AppIconSize.xs, color: c.textMedium),
            ),
          ),
        ),
      if (metaLead == null && text.isNotEmpty)
        Flexible(
          child: ParentComponent(
            featureKey: 'course_card.meta',
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
          ),
        ),
      if (metaLead != null) Expanded(child: _ledMeta(context, text, style)),
    ]);
  }

  /// The badge, then the text: the text keeps its own width up to half the line, the badge takes the rest.
  Widget _ledMeta(BuildContext context, String text, TextStyle style) => LayoutBuilder(builder: (context, box) {
        if (text.isEmpty) return Align(alignment: AlignmentDirectional.centerStart, child: metaLead);
        final tail = '  ·  $text';
        final painter = TextPainter(
          text: TextSpan(text: tail, style: DefaultTextStyle.of(context).style.merge(style)),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final textW = math.min(painter.width + AppSpace.xs, box.maxWidth / 2);
        painter.dispose();
        return Row(children: [
          Flexible(child: metaLead!),
          SizedBox(
            width: textW,
            child: ParentComponent(
              featureKey: 'course_card.meta',
              child: Text(tail, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
            ),
          ),
        ]);
      });

  Widget _picture({double? width, double? height}) => ParentComponent(
        featureKey: 'course_card.thumbnail',
        child: imageUrl.trim().isEmpty
            ? CourseCoverArt(seed: title.hashCode, width: width, height: height, label: title, toneKey: title)
            : AppNetworkImage(
          url: imageUrl,
          width: width ?? double.infinity,
          height: height,
          fit: BoxFit.cover,
          borderRadius: BorderRadius.zero,
          heroTag: heroTag,
        ),
      );

  Widget _row(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          // concentric with the card: its radius less the inset
          borderRadius: BorderRadius.circular(AppRadius.card - AppSpace.xxs),
          child: SizedBox.fromSize(
            size: _thumb,
            child: Stack(children: [
              Positioned.fill(child: AppParallaxImage(maxShift: AppSpace.xxs, image: _picture())),
              if (chip case final chip?)
                PositionedDirectional(
                  start: AppSpace.xxs,
                  end: AppSpace.xxs,
                  bottom: AppSpace.xxs,
                  // the chip ellipsizes inside the picture instead of running off its edge
                  child: Align(alignment: AlignmentDirectional.centerStart, child: chip),
                ),
            ]),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _title(context)),
              if (corner != null) ...[const SizedBox(width: AppSpace.xxs), corner!],
            ]),
            const SizedBox(height: AppSpace.xxs),
            _meta(context),
            const SizedBox(height: AppSpace.sm),
            footer,
          ]),
        ),
      ]),
    );
  }

  Widget _tile(BuildContext context) {
    final cover = ClipRRect(
      // concentric with the card: its radius less the inset
      borderRadius: BorderRadius.circular(AppRadius.card - _RenderTileLayout.inset),
      child: AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(children: [
        Positioned.fill(child: AppParallaxImage(image: _picture())),
        if (chip != null)
          PositionedDirectional(
            start: AppSpace.sm,
            end: AppSpace.xxl,
            top: AppSpace.sm,
            child: Align(alignment: AlignmentDirectional.centerStart, child: chip!),
          ),
        if (corner != null) PositionedDirectional(end: AppSpace.xs, top: AppSpace.xs, child: _CornerBackdrop(child: corner!)),
      ]),
      ),
    );
    // cover · title + meta · footer; the tile is its content's height, or the height it is given with the footer at
    // the bottom (a row's footers line up) — the same tree either way, so nothing is rebuilt between the two
    return _TileLayout(children: [
      cover,
      ClipRect(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          // a very large text scale in a fixed-height grid clips the title, never overflows
          Flexible(child: _title(context)),
          const SizedBox(height: AppSpace.xxs),
          _meta(context),
        ]),
      ),
      footer,
    ]);
  }
}

/// A tile's three parts — cover (inset [_RenderTileLayout.inset] on its outer sides), text block, footer — the text
/// inset 16 on the sides with 12 px between the text and the footer. Unbounded height → the content's height; a bounded one → that height, the footer at the
/// bottom and the text block given what is left.
class _TileLayout extends MultiChildRenderObjectWidget {
  const _TileLayout({required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTileLayout();
}

class _TileParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderTileLayout extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _TileParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _TileParentData> {
  static const _side = AppSpace.md, _top = AppSpace.sm, _gap = AppSpace.sm, _bottom = AppSpace.md;

  /// The cover's inset inside the card.
  static const inset = AppSpace.xs;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TileParentData) child.parentData = _TileParentData();
  }

  @override
  void performLayout() {
    final w = constraints.maxWidth;
    final cover = firstChild!, text = childAfter(cover)!, foot = childAfter(text)!;
    final inner = math.max(0.0, w - 2 * _side);
    cover.layout(BoxConstraints.tightFor(width: math.max(0.0, w - 2 * inset)), parentUsesSize: true);
    foot.layout(BoxConstraints(minWidth: inner, maxWidth: inner), parentUsesSize: true);
    final fixed = inset + cover.size.height + _top + _gap + foot.size.height + _bottom;
    // the text block gets what a given height leaves (a finite bound either way: its title is Flexible)
    final room = constraints.hasBoundedHeight ? math.max(0.0, constraints.maxHeight - fixed) : 100000.0;
    text.layout(BoxConstraints(minWidth: inner, maxWidth: inner, maxHeight: room), parentUsesSize: true);
    size = constraints.constrain(Size(w, fixed + text.size.height));
    (cover.parentData! as _TileParentData).offset = const Offset(inset, inset);
    (text.parentData! as _TileParentData).offset = Offset(_side, inset + cover.size.height + _top);
    (foot.parentData! as _TileParentData).offset = Offset(_side, size.height - _bottom - foot.size.height);
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);
}

/// A row of [columns] equal cells, as tall as its tallest child: each child is laid out at its content's height,
/// then the shorter ones again at the row's (a tile puts its footer at the bottom). Cells follow [textDirection];
/// a short last row leaves its end cells empty.
class _EqualHeightRow extends MultiChildRenderObjectWidget {
  const _EqualHeightRow({required this.columns, required this.gap, required this.textDirection, required super.children});

  final int columns;
  final double gap;
  final TextDirection textDirection;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderEqualHeightRow(columns, gap, textDirection);

  @override
  void updateRenderObject(BuildContext context, _RenderEqualHeightRow renderObject) => renderObject
    ..columns = columns
    ..gap = gap
    ..textDirection = textDirection;
}

class _RenderEqualHeightRow extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _TileParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _TileParentData> {
  _RenderEqualHeightRow(this._columns, this._gap, this._dir);

  int _columns;
  double _gap;
  TextDirection _dir;

  set columns(int v) {
    if (v == _columns) return;
    _columns = v;
    markNeedsLayout();
  }

  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  set textDirection(TextDirection v) {
    if (v == _dir) return;
    _dir = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TileParentData) child.parentData = _TileParentData();
  }

  @override
  void performLayout() {
    final w = constraints.maxWidth;
    final cell = math.max(0.0, (w - _gap * (_columns - 1)) / _columns);
    var h = 0.0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      c.layout(BoxConstraints.tightFor(width: cell), parentUsesSize: true);
      h = math.max(h, c.size.height);
    }
    var i = 0;
    for (var c = firstChild; c != null; c = childAfter(c), i++) {
      if (c.size.height != h) c.layout(BoxConstraints.tightFor(width: cell, height: h), parentUsesSize: true);
      final x = i * (cell + _gap);
      (c.parentData! as _TileParentData).offset = Offset(_dir == TextDirection.rtl ? w - x - cell : x, 0);
    }
    size = constraints.constrain(Size(w, h));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);
}

/// A soft disc behind a corner control that sits on the cover.
class _CornerBackdrop extends StatelessWidget {
  const _CornerBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: context.colors.cardBg.withValues(alpha: 0.92), shape: BoxShape.circle),
        child: child,
      );
}

/// The small paper chip on the cover: Live / Recorded for a student, Draft / Published for a teacher. Paper with ink
/// reads on a photograph and on a book cover alike; the live / status dot carries the colour.
class CourseCoverChip extends StatelessWidget {
  const CourseCoverChip({super.key, required this.label, this.icon, this.dot});

  /// Live / recorded type chip.
  factory CourseCoverChip.type(BuildContext context, {required bool live}) => CourseCoverChip(
        label: live ? 'course_list_live'.tr : 'course_list_recorded'.tr,
        dot: live ? context.colors.danger : null,
        icon: live ? null : Icons.play_arrow_rounded,
      );

  /// Draft / published status chip.
  factory CourseCoverChip.status(BuildContext context, {required bool published}) => CourseCoverChip(
        label: published ? 'status_published'.tr : 'status_draft'.tr,
        dot: published ? context.colors.success : context.colors.warning,
      );

  final String label;
  final IconData? icon;
  final Color? dot;

  static const double _dot = 6;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xs, AppSpace.xxs, AppSpace.xs + 2, AppSpace.xxs),
      decoration: BoxDecoration(
        color: c.cardBg.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot != null)
          Container(width: _dot, height: _dot, decoration: BoxDecoration(color: dot, shape: BoxShape.circle))
        else if (icon != null)
          Icon(icon, size: AppIconSize.xs, color: c.textDark),
        const SizedBox(width: AppSpace.xxs),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark, height: 1.2),
          ),
        ),
      ]),
    );
  }
}

/// The student's favourite mark (drawn only for a favourite course).
class CourseFavoriteMark extends StatelessWidget {
  const CourseFavoriteMark({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'favorite'.tr,
        child: SizedBox.square(
          dimension: AppIconSize.lg + AppSpace.xxs,
          child: Icon(Icons.favorite_rounded, size: AppIconSize.sm, color: context.colors.danger),
        ),
      );
}

// ── Footers ─────────────────────────────────────────────────────────────────

/// An enrolled student's progress: a thin bar and the percentage.
class CourseProgressFooter extends StatelessWidget {
  const CourseProgressFooter({super.key, required this.progress});

  final int progress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = progress.clamp(0, 100);
    final done = p >= 100;
    return ParentComponent(
      featureKey: 'course_card.progress',
      child: Semantics(
        label: 'course_list_progress_sem'.tr.replaceAll('{n}', '$p'),
        excludeSemantics: true,
        child: Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: AppFill(
                value: p / 100,
                builder: (_, v) => LinearProgressIndicator(
                  value: v,
                  minHeight: AppSpace.xxs + 2,
                  backgroundColor: c.divider,
                  valueColor: AlwaysStoppedAnimation(done ? c.success : coursePrimaryInk(context)),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          Text(
            '$p%',
            style: AppType.label(context).copyWith(
              fontWeight: FontWeight.w600,
              color: done ? c.success : c.textDark,
              height: 1.2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ]),
      ),
    );
  }
}

/// A price ("EGP 450", "Free"), with the original struck through and the saving when a discount runs.
class CoursePriceFooter extends StatelessWidget {
  const CoursePriceFooter({super.key, required this.price, this.free = false, this.original, this.offPercent});

  final String price;
  final bool free;
  final String? original;
  final int? offPercent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ParentComponent(
      featureKey: 'course_card.price',
      child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(price,
            style: AppType.bodyStrong(context).copyWith(
                color: free ? c.success : coursePrimaryInk(context),
                height: 1.2,
                fontFeatures: const [FontFeature.tabularFigures()])),
        if (original != null)
          ParentComponent(
            featureKey: 'course_card.discount',
            child: Text(
              original!,
              style: AppType.meta(context)
                  .copyWith(color: c.textLight, height: 1.2, decoration: TextDecoration.lineThrough, decorationColor: c.textLight),
            ),
          ),
        if (offPercent != null && offPercent! > 0)
          ParentComponent(
            featureKey: 'course_card.discount',
            child: AppStatusBadge(label: '-$offPercent%', tone: AppTone.danger, dense: true),
          ),
      ]),
    );
  }
}

/// The teacher's figures: students · sessions · rating.
class CourseStatsFooter extends StatelessWidget {
  const CourseStatsFooter({super.key, required this.students, required this.sessions, this.rating});

  final int students;
  final int sessions;
  final double? rating;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget figure(IconData icon, String value, String semantics, {Color? tint}) => Semantics(
          label: semantics,
          excludeSemantics: true,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: AppIconSize.sm, color: tint ?? c.textLight),
            const SizedBox(width: AppSpace.xxs),
            Text(
              value,
              style: AppType.label(context).copyWith(
                fontWeight: FontWeight.w600,
                color: c.textDark,
                height: 1.2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ]),
        );
    return Wrap(spacing: AppSpace.md, runSpacing: AppSpace.xxs, children: [
      // compact like the home's figures ("1.3K", the exact number is read out)
      figure(Icons.people_outline_rounded, appCompactNumber(students), 'course_list_students_sem'.tr.replaceAll('{n}', '$students')),
      figure(Icons.play_circle_outline_rounded, appCompactNumber(sessions), 'course_list_sessions_sem'.tr.replaceAll('{n}', '$sessions')),
      if (rating != null && rating! > 0)
        ParentComponent(
          featureKey: 'course_card.rating',
          child: figure(
            Icons.star_rounded,
            rating!.toStringAsFixed(1),
            'course_list_rating_sem'.tr.replaceAll('{n}', rating!.toStringAsFixed(1)),
            // a rating is a mark earned: gold, as an icon fill only (system.md §2)
            tint: c.accent2,
          ),
        ),
    ]);
  }
}

// ── The list ────────────────────────────────────────────────────────────────

/// Course cards as a sliver: rows below 600 px, a grid of tiles above. [width] is the list's inner width.
class CourseCardSliver extends StatelessWidget {
  const CourseCardSliver({super.key, required this.width, required this.count, required this.itemBuilder});

  final double width;
  final int count;
  final Widget Function(BuildContext context, int index, CourseCardShape shape) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final shape = courseCardShapeFor(width);
    if (shape == CourseCardShape.row) {
      return SliverList.separated(
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
        itemBuilder: (context, i) => AppReveal(index: i, group: 'courses', child: itemBuilder(context, i, shape)),
      );
    }
    // rows sized by their tiles (no fixed cell height: a one-line title left a blank band above the footer), start
    // aligned — a lone course is one tile at the start, never stretched
    final cols = courseGridColumns(width);
    const gap = AppSpace.md;
    final rows = (count + cols - 1) ~/ cols;
    return SliverList.builder(
      itemCount: rows,
      itemBuilder: (context, r) => Padding(
        padding: EdgeInsets.only(bottom: r == rows - 1 ? 0 : gap),
        child: _EqualHeightRow(
          columns: cols,
          gap: gap,
          textDirection: Directionality.of(context),
          children: [
            for (var i = r * cols; i < math.min(count, (r + 1) * cols); i++)
              AppReveal(index: i, group: 'courses', child: itemBuilder(context, i, shape)),
          ],
        ),
      ),
    );
  }
}

/// Loading placeholder in the card's own shapes.
class CourseListSkeleton extends StatelessWidget {
  const CourseListSkeleton({super.key, this.padding = const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.md)});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      final width = math.max(0.0, box.maxWidth - padding.horizontal);
      final shape = courseCardShapeFor(width);
      Widget card(int i) {
        final lines = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          AppSkeletonBox(width: 120.0 + (i * 37) % 70, height: AppSpace.md),
          const SizedBox(height: AppSpace.xs),
          AppSkeletonBox(width: 80.0 + (i * 23) % 50, height: AppSpace.sm - 2),
          const SizedBox(height: AppSpace.md),
          const AppSkeletonBox(height: AppSpace.xxs + 2, radius: AppRadius.pill),
        ]);
        final deco = BoxDecoration(
          color: c.cardBg,
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: c.divider, width: AppBorder.hairline),
        );
        if (shape == CourseCardShape.row) {
          return Container(
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: deco,
            child: Row(children: [
              AppSkeletonBox(
                width: CourseListCard._thumb.width,
                height: CourseListCard._thumb.height,
                radius: AppRadius.card - AppSpace.xxs,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: lines),
            ]),
          );
        }
        return Container(
          decoration: deco,
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const AspectRatio(aspectRatio: 16 / 9, child: AppSkeletonBox(radius: 0)),
            Padding(padding: const EdgeInsets.all(AppSpace.md), child: lines),
          ]),
        );
      }

      return AppShimmer(
        child: CustomScrollView(
          physics: const NeverScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: padding,
              sliver: CourseCardSliver(width: width, count: 6, itemBuilder: (_, i, _) => card(i)),
            ),
          ],
        ),
      );
    });
  }
}

/// Nothing to list: the kit's drawn plate, the line as an editorial headline, and the one thing to do about it.
class CourseListEmpty extends StatelessWidget {
  const CourseListEmpty({super.key, required this.icon, required this.message, this.actionLabel, this.onAction});

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) =>
      AppEmpty(icon: icon, title: message, actionLabel: actionLabel, onAction: onAction);
}

/// A failed load: a quiet banner with Retry (above the list when courses are already shown).
class CourseListError extends StatelessWidget {
  const CourseListError({super.key, required this.message, required this.onRetry, this.margin});

  final String message;
  final VoidCallback onRetry;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) => Padding(
        padding: margin ?? const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
        child: AppErrorState(compact: true, message: message, onRetry: onRetry),
      );
}

// ── Header ──────────────────────────────────────────────────────────────────

/// The list's search box: the kit's input well (48 px, warm fill, the focus ring), a clear button while it holds
/// text. Every keystroke reaches [onChanged] at once (the screens filter or debounce themselves).
class CourseSearchField extends StatefulWidget {
  const CourseSearchField({super.key, required this.controller, required this.hint, required this.onChanged});

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<CourseSearchField> createState() => _CourseSearchFieldState();
}

class _CourseSearchFieldState extends State<CourseSearchField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant CourseSearchField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTouch.min),
      child: TextField(
        controller: widget.controller,
        onChanged: widget.onChanged,
        textInputAction: TextInputAction.search,
        style: appFieldTextStyle(context),
        decoration: appFieldDecoration(
          context,
          hint: widget.hint.tr,
          icon: Icons.search_rounded,
          suffix: widget.controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'clear'.tr,
                  onPressed: () {
                    widget.controller.clear();
                    widget.onChanged('');
                  },
                  icon: const Icon(Icons.close_rounded, size: AppIconSize.md),
                ),
        ),
      ),
    );
  }
}

/// One option of [CourseSegments].
class CourseSegment<T> {
  const CourseSegment(this.value, this.label, {this.count});

  final T value;
  final String label;

  /// Drawn after the label when known.
  final int? count;
}

/// The list's filter (All · In progress · Completed / All · Published · Drafts): the kit's pill track (AppTabs) —
/// the chosen pill solid emerald that slides to the tab, each count in its bubble; the tabs keep their own widths
/// from the start edge and scroll sideways when they do not fit. (Not `expand`: its fractional shares can overflow
/// the track by half a pixel, see the open issue on AppTabs.)
class CourseSegments<T> extends StatelessWidget {
  const CourseSegments({super.key, required this.segments, required this.selected, required this.onSelect});

  final List<CourseSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final index = segments.indexWhere((s) => s.value == selected);
    return AppTabs(
      index: index < 0 ? 0 : index,
      onChanged: (i) => onSelect(segments[i].value),
      items: [for (final s in segments) AppTabItem(s.label, count: s.count)],
    );
  }
}

/// The search box and the filter, stacked on a phone and side by side once there is room.
class CourseListToolbar extends StatelessWidget {
  const CourseListToolbar({super.key, this.search, this.filter, this.action});

  final Widget? search;
  final Widget? filter;

  /// An extra button at the end on wide screens (the teacher's "New course").
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 900; // below it the four filters keep whole labels on their own row
        if (wide) {
          return Row(children: [
            if (search != null) Expanded(child: search!),
            if (search != null && filter != null) const SizedBox(width: AppSpace.md),
            if (filter != null) SizedBox(width: math.min(560, box.maxWidth * 0.5), child: filter!),
            if (action != null) ...[const SizedBox(width: AppSpace.md), action!],
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          ?search,
          if (search != null && filter != null) const SizedBox(height: AppSpace.sm),
          ?filter,
          if (action != null) ...[
            const SizedBox(height: AppSpace.xs),
            Align(alignment: AlignmentDirectional.centerEnd, child: action),
          ],
        ]);
      }),
    );
  }
}

/// [s] as a directional isolate (FSI … PDI): a run in the other script keeps its own order inside a joined line.
String bidiIsolate(String s) => '${String.fromCharCode(0x2068)}$s${String.fromCharCode(0x2069)}';

/// True when the kill switch [key] is off (the screen leaves that part out).
bool courseFeatureOff(String key) => AppConfig.disableList.contains(key);
