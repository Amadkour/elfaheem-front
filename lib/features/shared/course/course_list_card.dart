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
// Type: titles w600, meta w400 muted, figures w600; hairline border, no shadow, one accent per card. The header
// parts of a course list (CourseSearchField, CourseSegments) and its states (CourseListSkeleton, CourseListEmpty,
// CourseListError) live here too, so the two screens build the same calm block.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_charts.dart' show appCompactNumber;
import 'package:flutter_education_app/design/app_kit.dart' show appText, AppShimmer, AppSkeletonBox;
import 'package:flutter_education_app/design/app_mesh.dart' show AppMeshSurface;
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

/// One course in a list. [corner] is the heart (student) or the ⋮ menu (teacher); [chip] the type / status chip;
/// [metaLead] leads the meta line (the organization badge of a mixed list); [footer] is the role's last line.
/// The cover of a course with no picture: the app's gradient, a different shape per course.
class CourseCoverArt extends StatelessWidget {
  const CourseCoverArt({super.key, required this.seed, this.width, this.height, this.iconSize = 34});

  final int seed;
  final double? width, height;
  final double iconSize;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width ?? double.infinity,
        height: height,
        child: AppMeshSurface(
          seed: seed,
          child: Center(child: Icon(Icons.auto_stories_rounded, size: iconSize, color: context.colors.onHero.withValues(alpha: 0.55))),
        ),
      );
}

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

  /// Row height is the content's; a tile's height for a grid cell of [width] is this.
  static double tileHeight(BuildContext context, double width) => width * 9 / 16 + 128 * _scale(context);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(16);
    // depth (D-583): tilts toward the mouse, presses in on touch; the cover shifts inside it
    return AppTilt(
      radius: 16,
      maxTilt: 3,
      child: Material(
        color: c.cardBg,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.divider)),
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
        style: appText(15, w: FontWeight.w600, c: context.colors.textDark, h: 1.35),
      );

  Widget _meta(BuildContext context) {
    final c = context.colors;
    final style = appText(12.5, w: FontWeight.w400, c: c.textMedium, h: 1.4);
    final text = meta.where((m) => m.trim().isNotEmpty).join('  ·  ');
    return Row(children: [
      if (isPrivate)
        ParentComponent(
          featureKey: 'course_card.private_flag',
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 4),
            child: Tooltip(
              message: 'private'.tr,
              child: Icon(Icons.lock_outline_rounded, size: 14, color: c.textMedium),
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
        final textW = math.min(painter.width + 8, box.maxWidth / 2);
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
        child: imageUrl.trim().isEmpty ? CourseCoverArt(seed: title.hashCode, width: width, height: height) : AppNetworkImage(
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
      padding: const EdgeInsets.all(12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 104,
            height: 80,
            child: Stack(children: [
              Positioned.fill(child: _picture()),
              if (chip case final chip?) PositionedDirectional(start: 6, bottom: 6, child: chip),
            ]),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _title(context)),
              if (corner != null) ...[const SizedBox(width: 4), corner!],
            ]),
            const SizedBox(height: 4),
            _meta(context),
            const SizedBox(height: 12),
            footer,
          ]),
        ),
      ]),
    );
  }

  Widget _tile(BuildContext context) {
    final cover = AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(children: [
        Positioned.fill(child: ClipRect(child: AppTiltLayer(depth: 1.2, overscan: true, child: _picture()))),
        if (chip != null) PositionedDirectional(start: 12, top: 12, child: chip!),
        if (corner != null) PositionedDirectional(end: 8, top: 8, child: _CornerBackdrop(child: corner!)),
      ]),
    );
    // cover · title + meta · footer; the tile is its content's height, or the height it is given with the footer at
    // the bottom (a row's footers line up) — the same tree either way, so nothing is rebuilt between the two
    return _TileLayout(children: [
      cover,
      ClipRect(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          // a very large text scale in a fixed-height grid clips the title, never overflows
          Flexible(child: _title(context)),
          const SizedBox(height: 4),
          _meta(context),
        ]),
      ),
      footer,
    ]);
  }
}

/// A tile's three parts — cover (full width), text block, footer — inset 16 · 12 · 16 · 16 with 12 px between the
/// text and the footer. Unbounded height → the content's height; a bounded one → that height, the footer at the
/// bottom and the text block given what is left.
class _TileLayout extends MultiChildRenderObjectWidget {
  const _TileLayout({required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTileLayout();
}

class _TileParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderTileLayout extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _TileParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _TileParentData> {
  static const _side = 16.0, _top = 12.0, _gap = 12.0, _bottom = 16.0;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TileParentData) child.parentData = _TileParentData();
  }

  @override
  void performLayout() {
    final w = constraints.maxWidth;
    final cover = firstChild!, text = childAfter(cover)!, foot = childAfter(text)!;
    final inner = math.max(0.0, w - 2 * _side);
    cover.layout(BoxConstraints.tightFor(width: w), parentUsesSize: true);
    foot.layout(BoxConstraints(minWidth: inner, maxWidth: inner), parentUsesSize: true);
    final fixed = cover.size.height + _top + _gap + foot.size.height + _bottom;
    // the text block gets what a given height leaves (a finite bound either way: its title is Flexible)
    final room = constraints.hasBoundedHeight ? math.max(0.0, constraints.maxHeight - fixed) : 100000.0;
    text.layout(BoxConstraints(minWidth: inner, maxWidth: inner, maxHeight: room), parentUsesSize: true);
    size = constraints.constrain(Size(w, fixed + text.size.height));
    (cover.parentData! as _TileParentData).offset = Offset.zero;
    (text.parentData! as _TileParentData).offset = Offset(_side, cover.size.height + _top);
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

/// The small glass chip on the cover: Live / Recorded for a student, Draft / Published for a teacher.
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: c.heroShade.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot != null)
          Container(width: 6, height: 6, decoration: BoxDecoration(color: dot, shape: BoxShape.circle))
        else if (icon != null)
          Icon(icon, size: 12, color: c.onHero),
        const SizedBox(width: 4),
        Text(label, maxLines: 1, style: appText(10.5, w: FontWeight.w500, c: c.onHero, h: 1.2)),
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
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(Icons.favorite_rounded, size: 16, color: context.colors.danger),
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
              borderRadius: BorderRadius.circular(2),
              child: AppFill(
                value: p / 100,
                builder: (_, v) => LinearProgressIndicator(
                  value: v,
                  minHeight: 4,
                  backgroundColor: c.divider,
                  valueColor: AlwaysStoppedAnimation(done ? c.success : coursePrimaryInk(context)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('$p%', style: appText(12, w: FontWeight.w600, c: done ? c.success : c.textDark, h: 1.2)),
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
      child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(price, style: appText(14, w: FontWeight.w600, c: free ? c.success : c.textDark, h: 1.2)),
        if (original != null)
          ParentComponent(
            featureKey: 'course_card.discount',
            child: Text(
              original!,
              style: appText(12, w: FontWeight.w400, c: c.textLight, h: 1.2)
                  .copyWith(decoration: TextDecoration.lineThrough, decorationColor: c.textLight),
            ),
          ),
        if (offPercent != null && offPercent! > 0)
          ParentComponent(
            featureKey: 'course_card.discount',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: c.danger.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(6)),
              child: Text('-$offPercent%', style: appText(11, w: FontWeight.w600, c: c.danger, h: 1.2)),
            ),
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
            Icon(icon, size: 15, color: tint ?? c.textLight),
            const SizedBox(width: 4),
            Text(value, style: appText(12.5, w: FontWeight.w600, c: c.textDark, h: 1.2)),
          ]),
        );
    return Wrap(spacing: 16, runSpacing: 4, children: [
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
            tint: c.accent,
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
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) => AppReveal(index: i, group: 'courses', child: itemBuilder(context, i, shape)),
      );
    }
    // rows sized by their tiles (no fixed cell height: a one-line title left a blank band above the footer), start
    // aligned — a lone course is one tile at the start, never stretched
    final cols = courseGridColumns(width);
    const gap = 16.0;
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
  const CourseListSkeleton({super.key, this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 16)});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      final width = math.max(0.0, box.maxWidth - padding.horizontal);
      final shape = courseCardShapeFor(width);
      Widget card(int i) {
        final lines = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          AppSkeletonBox(width: 120.0 + (i * 37) % 70, height: 13),
          const SizedBox(height: 8),
          AppSkeletonBox(width: 80.0 + (i * 23) % 50, height: 10),
          const SizedBox(height: 16),
          const AppSkeletonBox(height: 4, radius: 2),
        ]);
        final deco = BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.divider),
        );
        if (shape == CourseCardShape.row) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: deco,
            child: Row(children: [
              const AppSkeletonBox(width: 104, height: 80, radius: 12),
              const SizedBox(width: 12),
              Expanded(child: lines),
            ]),
          );
        }
        return Container(
          decoration: deco,
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const AspectRatio(aspectRatio: 16 / 9, child: AppSkeletonBox(radius: 0)),
            Padding(padding: const EdgeInsets.all(16), child: lines),
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

/// Nothing to list: one calm line, and the one thing to do about it.
class CourseListEmpty extends StatelessWidget {
  const CourseListEmpty({super.key, required this.icon, required this.message, this.actionLabel, this.onAction});

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
            child: Icon(icon, size: 22, color: coursePrimaryInk(context)),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: appText(14, w: FontWeight.w400, c: c.textMedium, h: 1.5),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!, style: appText(14, w: FontWeight.w600, c: coursePrimaryInk(context))),
            ),
          ],
        ]),
      ),
    );
  }
}

/// A failed load: a quiet banner with Retry (above the list when courses are already shown).
class CourseListError extends StatelessWidget {
  const CourseListError({super.key, required this.message, required this.onRetry, this.margin});

  final String message;
  final VoidCallback onRetry;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: margin ?? const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: c.danger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.danger.withValues(alpha: 0.20)),
      ),
      child: Row(children: [
        Icon(Icons.error_outline_rounded, size: 18, color: c.danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: appText(13, w: FontWeight.w400, c: c.textDark, h: 1.4),
          ),
        ),
        Flexible(
          child: TextButton(
            onPressed: onRetry,
            child: Text(
              'retry'.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: appText(13, w: FontWeight.w600, c: coursePrimaryInk(context)),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

/// The list's search box: 44 px, hairline border, a clear button while it holds text.
class CourseSearchField extends StatefulWidget {
  const CourseSearchField({super.key, required this.controller, required this.hint, required this.onChanged});

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<CourseSearchField> createState() => _CourseSearchFieldState();
}

class _CourseSearchFieldState extends State<CourseSearchField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
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
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final focused = _focus.hasFocus;
    final style = appText(14, w: FontWeight.w400, c: c.textDark);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: focused ? c.primary.withValues(alpha: 0.55) : c.divider),
      ),
      child: Row(children: [
        Icon(Icons.search_rounded, size: 18, color: c.textLight),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            onChanged: widget.onChanged,
            textInputAction: TextInputAction.search,
            style: style,
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              hintText: widget.hint.tr,
              hintStyle: style.copyWith(color: c.textLight),
            ),
          ),
        ),
        if (widget.controller.text.isNotEmpty)
          IconButton(
            tooltip: 'clear'.tr,
            onPressed: () {
              widget.controller.clear();
              widget.onChanged('');
            },
            icon: Icon(Icons.close_rounded, size: 18, color: c.textMedium),
          ),
      ]),
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

/// The list's filter: a calm segmented control (All · In progress · Completed / All · Published · Drafts).
class CourseSegments<T> extends StatelessWidget {
  const CourseSegments({super.key, required this.segments, required this.selected, required this.onSelect});

  final List<CourseSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = coursePrimaryInk(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.divider),
      ),
      child: Row(children: [
        for (final s in segments)
          Expanded(
            child: Semantics(
              button: true,
              selected: s.value == selected,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onSelect(s.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  constraints: const BoxConstraints(minHeight: 36),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: s.value == selected ? ink.withValues(alpha: 0.10) : null,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: s.value == selected ? ink.withValues(alpha: 0.30) : Colors.transparent),
                  ),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: s.label),
                      if (s.count != null)
                        TextSpan(
                          text: '  ${s.count}',
                          style: appText(12, w: FontWeight.w400, c: s.value == selected ? ink : c.textLight),
                        ),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: appText(
                      13,
                      w: s.value == selected ? FontWeight.w600 : FontWeight.w500,
                      c: s.value == selected ? ink : c.textMedium,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 640;
        if (wide) {
          return Row(children: [
            if (search != null) Expanded(child: search!),
            if (search != null && filter != null) const SizedBox(width: 16),
            if (filter != null) SizedBox(width: math.min(340, box.maxWidth * 0.42), child: filter!),
            if (action != null) ...[const SizedBox(width: 16), action!],
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          ?search,
          if (search != null && filter != null) const SizedBox(height: 8),
          ?filter,
          if (action != null) ...[
            const SizedBox(height: 8),
            Align(alignment: AlignmentDirectional.centerEnd, child: action),
          ],
        ]);
      }),
    );
  }
}

/// True when the kill switch [key] is off (the screen leaves that part out).
bool courseFeatureOff(String key) => AppConfig.disableList.contains(key);
