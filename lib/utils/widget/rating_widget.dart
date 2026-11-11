import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:provider/provider.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../core/api_client.dart'; // adjust import path as needed
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';

import '../../features/shared/guest/guest_state.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/plural.dart';
// ══════════════════════════════════════════════
//  ENUM  (mirrors Python RateType)
// ══════════════════════════════════════════════

enum RateType {
  course,
  session,
  material,
  doctor;

  String get value => name.toUpperCase(); // 'course' | 'session' | 'material' | 'doctor'

  String get label => switch (this) {
    RateType.course => 'Course',
    RateType.session => 'Session',
    RateType.material => 'Material',
    RateType.doctor => 'Doctor',
  };

  /// The GET endpoint for fetching summary + ratings list
  String ratingPath(String sourceId) => switch (this) {
    RateType.course => '/api/v1/courses/$sourceId/ratings',
    RateType.session => '/api/v1/sessions/$sourceId/ratings',
  // material & doctor use the generic session endpoint pattern —
  // adjust to your actual backend paths if they differ
    RateType.material => '/api/v1/materials/$sourceId/ratings',
    RateType.doctor => '/api/v1/doctors/$sourceId/ratings',
  };
}

// ══════════════════════════════════════════════
//  MODELS
// ══════════════════════════════════════════════

class RateResponse {
  final int id;
  final int studentId;
  final int sourceId;
  final RateType type;
  final int value;
  final String? review;
  final DateTime createdAt;

  const RateResponse({
    required this.id,
    required this.studentId,
    required this.sourceId,
    required this.type,
    required this.value,
    this.review,
    required this.createdAt,
  });

  factory RateResponse.fromJson(Map<String, dynamic> j) => RateResponse(
    id: j['id'] as int,
    studentId: j['student_id'] as int,
    sourceId: j['source_id'] as int,
    type: RateType.values.firstWhere((e) => e.value == j['type']),
    value: j['value'] as int,
    review: j['review'] as String?,
    createdAt: (j['created_at'] as String).toLocalSaTime,
  );
}

class RatingSummary {
  final List<RateResponse> ratings;
  final int total;
  final double average;

  const RatingSummary({
    required this.ratings,
    required this.total,
    required this.average,
  });

  factory RatingSummary.fromJson(Map<String, dynamic> j) => RatingSummary(
    ratings: (j['ratings'] as List)
        .map((e) => RateResponse.fromJson(e as Map<String, dynamic>))
        .toList(),
    total: (j['total'] as num?)?.toInt() ?? 0,
    average: (j['average'] as num?)?.toDouble() ?? 0,
  );

  /// Distribution: how many ratings per star value (1–5)
  Map<int, int> get distribution {
    final map = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final r in ratings) {
      map[r.value] = (map[r.value] ?? 0) + 1;
    }
    return map;
  }
}

// ══════════════════════════════════════════════
//  SERVICE
// ══════════════════════════════════════════════

class RatingService {
  final _api = ApiClient();

  Future<RatingSummary> fetchSummary(RateType type, String sourceId) async {
    final data = await _api.get(type.ratingPath(sourceId));
    return RatingSummary.fromJson(data as Map<String, dynamic>);
  }

  Future<RateResponse> submitRate({
    required String sourceId,
    required RateType type,
    required int value,
    String? review,
  }) async {
    print({
      'source_id': sourceId,
      'type': type.name.toUpperCase(),
      'value': value,
      if (review != null && review.isNotEmpty) 'review': review,
    });
    final data = await _api.post(
      '/api/v1/rates',
      body: {
        'source_id': sourceId,
        'type': type.value,
        'value': value,
        if (review != null && review.isNotEmpty) 'review': review,
      },
    );
    return RateResponse.fromJson(data as Map<String, dynamic>);
  }
}

// ══════════════════════════════════════════════
//  MAIN WIDGET
// ══════════════════════════════════════════════

class RatingWidget extends StatefulWidget {
  /// The type of entity being rated (course / session / material / doctor).
  final RateType type;

  /// The database ID of the entity.
  final String sourceId;

  /// When false the widget is read-only — no stars can be tapped.
  final bool canEdit;

  /// Compact single-line mode (just stars + average).
  final bool compact;

  /// Called after a successful submission.
  final void Function(RateResponse rate)? onRated;
  final RatingSummary? rateSummary;

  const RatingWidget({
    super.key,
    required this.type,
    required this.sourceId,
    required this.canEdit,
    this.compact = true,
    this.onRated, this.rateSummary,
  });

  @override
  State<RatingWidget> createState() => _RatingWidgetState();
}

class _RatingWidgetState extends State<RatingWidget>
    with SingleTickerProviderStateMixin {
  final _service = RatingService();

  // ── State ──────────────────────────────────────────────────────────
  bool _loading = true;
  String? _error;
  RatingSummary? _summary;

  int _hovered = 0;       // star under pointer (desktop hover)
  int _selected = 0;      // confirmed selection before submit
  int _submitted = 0;     // last submitted value
  bool _submitting = false;

  bool _showReview = false;
  final _reviewController = TextEditingController();
  final _reviewFocus = FocusNode();

  late AnimationController _popAnim;
  late Animation<double> _popScale;

  // ── Lifecycle ──────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _popAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _popScale = CurvedAnimation(parent: _popAnim, curve: Curves.elasticOut);
    if(widget.rateSummary==null) {
      _load();
    }else{
      _summary=widget.rateSummary;
      setState(() {
        _loading = false;
        _error = null;
      });
    }
  }

  @override
  void dispose() {
    _popAnim.dispose();
    _reviewController.dispose();
    _reviewFocus.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await _service.fetchSummary(widget.type, widget.sourceId);
      // Try to find current user's existing rating
      RateResponse? mine;
      int? studentId=context.read<MyAuthProvider>().currentUser?.id;
      if (studentId != null) {
        try {
          mine = summary.ratings.firstWhere(
                  (r) => r.studentId == studentId);
        } catch (_) {}
      } else if (summary.ratings.isNotEmpty) {
        // If only one rating is returned (user-scoped endpoint), use it
        mine = summary.ratings.first;
      }

      if (mounted) {
        setState(() {
          _summary = summary;
          _submitted = mine?.value ?? 0;
          _selected = mine?.value ?? 0;
          _reviewController.text = mine?.review ?? '';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _submit() async {
    if (_selected == 0 || _submitting) return;
    if (!GuestGuard.ensure(context, reasonKey: 'guest_reason_rate')) return;
    if(mounted) setState(() => _submitting = true);
    try {
      final result = await _service.submitRate(
        sourceId: widget.sourceId,
        type: widget.type,
        value: _selected,
        review: _reviewController.text.trim().isEmpty
            ? null
            : _reviewController.text.trim(),
      );
      setState(() {
        _submitted = result.value;
        _submitting = false;
        _showReview = false;
      });
      _popAnim.forward(from: 0);
      widget.onRated?.call(result);
      await _load(); // refresh summary
    } catch (e) {
      if(mounted) setState(() => _submitting = false);
      if (mounted) {
        showAppNotice(e.toString(), error: true);
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────

  int get _displayValue => _hovered > 0 ? _hovered : _selected;

  String _starLabel(int v) => switch (v) {
    1 => 'Poor',
    2 => 'Fair',
    3 => 'Good',
    4 => 'Very Good',
    5 => 'Excellent',
    _ => '',
  };

  // ══════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_loading) return _Skeleton(compact: widget.compact);
    if (_error != null) return _ErrorState(onRetry: _load, error: _error!);
    if (widget.compact) return _buildCompact();
    return _buildFull();
  }

  // ── Compact mode ───────────────────────────────────────────────────

  Widget _buildCompact() {
    final c = context.colors;
    final avg = _summary?.average ?? 0.0;
    final total = _summary?.total ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StarRow(
          value: avg.round().clamp(0, 5),
          displayValue: avg,
          canEdit: widget.canEdit,
          hovered: _hovered,
          selected: _selected,
          size: AppIconSize.xs,
          onHover: (v) { if(mounted) setState(() => _hovered = v);},
          onTap: widget.canEdit
              ? (v) {
            setState(() {
              _selected = v;
              _showReview = true;
            });
          }
              : null,
        ),
        const SizedBox(width: AppSpace.xxs + AppSpace.xxs / 2),
        Text(
          avg.toStringAsFixed(1),
          style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600, fontFeatures: _tabular),
        ),
        const SizedBox(width: AppSpace.xxs),
        Flexible(
          child: Text(
            '($total)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.meta(context).copyWith(fontFeatures: _tabular),
          ),
        ),
        if (widget.canEdit && _showReview) ...[
          _SubmitButton(
            onTap: _submit,
            loading: _submitting,
            compact: true,
          ),
        ],
      ],
    );
  }

  // ── Full mode ──────────────────────────────────────────────────────

  /// A paper card: the average as the card's one large editorial figure beside the five distribution bars, then (when
  /// the person may rate) the stars to pick, the word for the pick and the review well under a hairline.
  Widget _buildFull() {
    final c = context.colors;
    final summary = _summary!;
    final motion = AppMotion.of(context);

    return AppCard(
      padding: AppSpace.block,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.star_rounded, color: c.primary, size: AppIconSize.sm),
              const SizedBox(width: AppSpace.xxs),
              Flexible(
                child: Text(
                  widget.type.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label(context).copyWith(color: c.textMedium),
                ),
              ),
              const Spacer(),
              if (_submitted > 0)
                ScaleTransition(
                  scale: _popScale,
                  child: const AppStatusBadge(label: 'Rated', icon: Icons.check_circle_rounded, tone: AppTone.success, dense: true),
                ),
            ],
          ),

          AppSpace.gapMd,

          // ── Score + bars (side by side; stacked in a narrow card so the bars keep their length) ──
          LayoutBuilder(builder: (context, box) {
            final score = Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Big average score: the card's one editorial figure.
                AppCountUp(
                  summary.average.toStringAsFixed(1),
                  memoryKey: 'rating-${widget.type.name}-${widget.sourceId}',
                  style: AppType.display(context).copyWith(color: c.textDark, height: 1, fontFeatures: _tabular),
                ),
                AppSpace.gapXs,
                _StarRow(
                  value: summary.average.round().clamp(0, 5),
                  displayValue: summary.average,
                  canEdit: false,
                  hovered: 0,
                  selected: 0,
                  size: AppIconSize.sm,
                ),
                const SizedBox(height: AppSpace.xxs),
                Text(
                  countText(summary.total, ar1: 'تقييم واحد', ar2: 'تقييمان', arFew: '{n} تقييمات', arMany: '{n} تقييمًا', en1: '1 rating', en: '{n} ratings'),
                  style: AppType.meta(context),
                ),
              ],
            );
            final bars = Column(
              children: List.generate(5, (i) {
                final star = 5 - i;
                final count = summary.distribution[star] ?? 0;
                final fraction = summary.total > 0
                    ? count / summary.total
                    : 0.0;
                return _DistributionBar(
                  star: star,
                  fraction: fraction,
                  count: count,
                );
              }),
            );
            if (box.maxWidth < _stackBelow) {
              return Column(children: [score, AppSpace.gapMd, bars]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [score, const SizedBox(width: AppSpace.lg), Expanded(child: bars)],
            );
          }),

          // ── Divider ───────────────────────────────────────────
          if (widget.canEdit) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
              child: Divider(color: c.divider, height: AppBorder.hairline, thickness: AppBorder.hairline),
            ),

            // ── Interactive stars ────────────────────────────
            Text(
              _submitted > 0 ? _t('حدّث تقييمك', 'Update your rating') : _t('أضف تقييمك', 'Rate this ${widget.type.label.toLowerCase()}'),
              style: AppType.section(context),
            ),
            AppSpace.gapSm,

            Center(
              child: Column(
                children: [
                  _StarRow(
                    value: _displayValue,
                    displayValue: _displayValue.toDouble(),
                    canEdit: true,
                    hovered: _hovered,
                    selected: _selected,
                    size: AppIconSize.xl,
                    onHover: (v) { if(mounted) setState(() => _hovered = v);},
                    onLeave: () { if(mounted) setState(() => _hovered = 0);},
                    onTap: (v) => setState(() {
                      _selected = v;
                      _showReview = true;
                    }),
                  ),
                  if (_displayValue > 0) ...[
                    AppSpace.gapXs,
                    AnimatedSwitcher(
                      duration: motion.fast,
                      child: Text(
                        _starLabel(_displayValue),
                        key: ValueKey(_displayValue),
                        style: AppType.bodyStrong(context).copyWith(color: _starColor(c, _displayValue)),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Review text box ─────────────────────────────
            AnimatedSize(
              duration: motion.slow,
              curve: AppEase.out,
              alignment: AlignmentDirectional.topStart,
              child: _showReview
                  ? Padding(
                padding: const EdgeInsets.only(top: AppSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ReviewField(
                      controller: _reviewController,
                      focusNode: _reviewFocus,
                    ),
                    AppSpace.gapSm,
                    _SubmitButton(
                      onTap: _submit,
                      loading: _submitting,
                    ),
                  ],
                ),
              )
                  : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }

  /// The word for a pick: danger for 1–2, warning (as text-safe ink) for 3, the primary above.
  Color _starColor(ThemeConfigProvider c, int v) => switch (v) {
    1 || 2 => c.danger,
    3 => appInkOn(context, c.warning, c.cardBg),
    _ => c.primary,
  };
}

const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

/// Below this card width the average sits above the distribution bars instead of beside them.
const double _stackBelow = 320;

// ══════════════════════════════════════════════
//  STAR ROW
// ══════════════════════════════════════════════

class _StarRow extends StatelessWidget {
  final int value;           // filled count (integer)
  final double displayValue; // for fractional display when read-only
  final bool canEdit;
  final int hovered;
  final int selected;
  final double size;
  final void Function(int)? onHover;
  final void Function()? onLeave;
  final void Function(int)? onTap;

  const _StarRow({
    required this.value,
    required this.displayValue,
    required this.canEdit,
    required this.hovered,
    required this.selected,
    required this.size,
    this.onHover,
    this.onLeave,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    return MouseRegion(
      onExit: onLeave != null ? (_) => onLeave!() : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final starNum = i + 1;
          final active = hovered > 0
              ? starNum <= hovered
              : starNum <= (canEdit ? selected : displayValue.round());
          final star = AnimatedScale(
            scale: canEdit && active ? 1 : (canEdit ? 0.92 : 1),
            duration: motion.fast,
            curve: AppEase.out,
            child: Icon(
              active ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: active ? c.primary : c.textLight,
            ),
          );
          if (!canEdit || size < AppIconSize.lg) {
            // Read-only and the compact inline row (inside cards of a fixed height) keep the star's own size.
            if (canEdit) {
              return GestureDetector(
                onTap: () => onTap?.call(starNum),
                child: MouseRegion(
                  onEnter: (_) => onHover?.call(starNum),
                  cursor: SystemMouseCursors.click,
                  child: Padding(padding: EdgeInsets.symmetric(horizontal: size * 0.08), child: star),
                ),
              );
            }
            return Padding(padding: EdgeInsets.symmetric(horizontal: size * 0.08), child: star);
          }
          // A star to pick is a full 48 px target.
          return Semantics(
            button: true,
            selected: starNum <= selected,
            label: '$starNum / 5',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap?.call(starNum),
              child: MouseRegion(
                onEnter: (_) => onHover?.call(starNum),
                cursor: SystemMouseCursors.click,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: size < AppTouch.min ? AppTouch.min * 0.75 : size, minHeight: AppTouch.min),
                  child: Center(widthFactor: 1, child: star),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ══════════════════════════════════════════════
//  DISTRIBUTION BAR
// ══════════════════════════════════════════════

class _DistributionBar extends StatelessWidget {
  final int star;
  final double fraction;
  final int count;

  const _DistributionBar({
    required this.star,
    required this.fraction,
    required this.count,
  });

  /// The bar's thickness and the count column's width.
  static const double _bar = 6, _countWidth = 28;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.pill);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs / 2),
      child: Row(
        children: [
          Text(
            '$star',
            style: AppType.meta(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w600, fontFeatures: _tabular),
          ),
          const SizedBox(width: AppSpace.xxs / 2),
          Icon(Icons.star_rounded, color: c.textLight, size: AppIconSize.xs * 0.8),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                children: [
                  Container(height: _bar, color: c.inputBg),
                  AppFill(
                    value: fraction,
                    builder: (context, v) => FractionallySizedBox(
                      widthFactor: v.clamp(0.0, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: c.primary, borderRadius: radius),
                        child: const SizedBox(height: _bar),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          SizedBox(
            width: _countWidth,
            child: Text(
              '$count',
              maxLines: 1,
              style: AppType.meta(context).copyWith(fontFeatures: _tabular),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════
//  REVIEW TEXT FIELD
// ══════════════════════════════════════════════

class _ReviewField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  const _ReviewField({
    required this.controller,
    required this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      maxLines: 3,
      minLines: 2,
      style: appFieldTextStyle(context),
      decoration: appFieldDecoration(context, hint: _t('شاركنا تجربتك (اختياري)…', 'Share your experience (optional)…')),
    );
  }
}

// ══════════════════════════════════════════════
//  SUBMIT BUTTON
// ══════════════════════════════════════════════

class _SubmitButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool loading;
  final bool compact;

  const _SubmitButton({
    required this.onTap,
    required this.loading,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      // Inline beside the stars inside a card of a fixed height: a small solid send mark, not a full button.
      final c = context.colors;
      return Padding(
        padding: const EdgeInsetsDirectional.only(start: AppSpace.xs),
        child: Tooltip(
          message: 'send_btn'.tr,
          child: SizedBox.square(
            dimension: AppIconSize.xl,
            child: Material(
              color: loading ? c.divider : c.primary,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: loading ? null : onTap,
                child: Center(
                  child: loading
                      ? const SizedBox.square(dimension: AppIconSize.xs, child: AppLoadingIndicator())
                      : Icon(Icons.send_rounded, color: c.onHero, size: AppIconSize.xs),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: AppButton.primary(label: 'send_btn'.tr, icon: Icons.send_rounded, busy: loading, onPressed: onTap),
    );
  }
}

// ══════════════════════════════════════════════
//  SKELETON LOADER
// ══════════════════════════════════════════════

class _Skeleton extends StatelessWidget {
  final bool compact;
  const _Skeleton({required this.compact});

  /// The bones' sizes: a compact star, the full card's label, figure and bar.
  static const double _star = 16, _label = 80, _figure = 64, _bar = 6;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          5,
          (_) => const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpace.xxs / 2),
            child: AppSkeletonBox(width: _star, height: _star, radius: AppRadius.pill),
          ),
        ),
      );
    }
    return AppCard(
      padding: AppSpace.block,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSkeletonBox(width: _label),
          AppSpace.gapMd,
          Row(
            children: [
              const AppSkeletonBox(width: _figure, height: _figure, radius: AppRadius.card),
              const SizedBox(width: AppSpace.lg),
              Expanded(
                child: Column(
                  children: List.generate(5, (_) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpace.xxs),
                    child: AppSkeletonBox(height: _bar, radius: AppRadius.pill),
                  )),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════
//  ERROR STATE
// ══════════════════════════════════════════════

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.dangerTint,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.danger.withValues(alpha: 0.2), width: AppBorder.hairline),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xxs, AppSpace.xxs, AppSpace.xxs),
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded, color: c.danger, size: AppIconSize.md),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                _t('تعذّر تحميل التقييمات', 'Could not load ratings'),
                style: AppType.body(context).copyWith(color: appInkOn(context, c.danger, c.dangerTint)),
              ),
            ),
            AppButton.ghost(label: 'Retry', icon: Icons.refresh_rounded, size: AppButtonSize.sm, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;
