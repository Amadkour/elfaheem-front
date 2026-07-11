import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:provider/provider.dart';
import '../../config/theme/app_theme.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../core/api_client.dart'; // adjust import path as needed

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
        total: j['total'] as int,
        average: (j['average'] as num).toDouble(),
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
      int? studentId=context.read<AuthProvider>().currentUser?.id;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: context.themeConfig.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
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
          size: 14,
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
        const SizedBox(width: 6),
        Text(
          avg.toStringAsFixed(1),
          style: c.bodyBold.copyWith(color: AppTheme.accent, fontSize: 13),
        ),
        const SizedBox(width: 4),
        Text(
          '($total)',
          style: c.caption.copyWith(fontSize: 11),
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

  Widget _buildFull() {
    final c = context.colors;
    final summary = _summary!;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: c.brMedium,
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: c.accentTint,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, color: AppTheme.accent, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      widget.type.label,
                      style: c.caption.copyWith(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (_submitted > 0)
                ScaleTransition(
                  scale: _popScale,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.successTint,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            color: c.success, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          'Rated',
                          style: c.caption.copyWith(
                            color: c.success,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Score + bars ──────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Big average score
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    summary.average.toStringAsFixed(1),
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.accent,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _StarRow(
                    value: summary.average.round().clamp(0, 5),
                    displayValue: summary.average,
                    canEdit: false,
                    hovered: 0,
                    selected: 0,
                    size: 16,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${summary.total} ratings',
                    style: c.caption.copyWith(fontSize: 11),
                  ),
                ],
              ),

              const SizedBox(width: 20),

              // Star distribution bars
              Expanded(
                child: Column(
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
                ),
              ),
            ],
          ),

          // ── Divider ───────────────────────────────────────────
          if (widget.canEdit) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Divider(color: c.divider, height: 1),
            ),

            // ── Interactive stars ────────────────────────────
            Text(
              _submitted > 0 ? 'Update your rating' : 'Rate this ${widget.type.label.toLowerCase()}',
              style: c.h4,
            ),
            const SizedBox(height: 12),

            Center(
              child: Column(
                children: [
                  _StarRow(
                    value: _displayValue,
                    displayValue: _displayValue.toDouble(),
                    canEdit: true,
                    hovered: _hovered,
                    selected: _selected,
                    size: 36,
                    onHover: (v) { if(mounted) setState(() => _hovered = v);},
                    onLeave: () { if(mounted) setState(() => _hovered = 0);},
                    onTap: (v) => setState(() {
                      _selected = v;
                      _showReview = true;
                    }),
                  ),
                  if (_displayValue > 0) ...[
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        _starLabel(_displayValue),
                        key: ValueKey(_displayValue),
                        style: c.bodyBold.copyWith(
                          color: _starColor(_displayValue),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Review text box ─────────────────────────────
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOutCubic,
              child: _showReview
                  ? Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        children: [
                          _ReviewField(
                            controller: _reviewController,
                            focusNode: _reviewFocus,
                          ),
                          const SizedBox(height: 12),
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

  Color _starColor(int v) => switch (v) {
        1 || 2 => AppTheme.danger,
        3 => AppTheme.warning,
        _ => AppTheme.accent,
      };
}

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
    return MouseRegion(
      onExit: onLeave != null ? (_) => onLeave!() : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final starNum = i + 1;
          final active = hovered > 0
              ? starNum <= hovered
              : starNum <= (canEdit ? selected : displayValue.round());

          return GestureDetector(
            onTap: canEdit ? () => onTap?.call(starNum) : null,
            child: MouseRegion(
              onEnter: canEdit ? (_) => onHover?.call(starNum) : null,
              cursor: canEdit
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: EdgeInsets.symmetric(horizontal: size * 0.08),
                child: Icon(
                  active ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: size,
                  color: active
                      ? AppTheme.accent
                      : Theme.of(context).brightness == Brightness.dark
                          ? AppTheme.darkTextLight
                          : AppTheme.textLight,
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            '$star',
            style: c.caption.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.star_rounded, color: AppTheme.accent, size: 10),
          const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(height: 6, color: c.divider),
                  FractionallySizedBox(
                    widthFactor: fraction,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        gradient: AppTheme.accentGradient,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 20,
            child: Text(
              '$count',
              style: c.caption.copyWith(fontSize: 10),
              textAlign: TextAlign.right,
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
    final c = context.colors;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      maxLines: 3,
      minLines: 2,
      style: c.body.copyWith(fontSize: 13),
      decoration: InputDecoration(
        hintText: 'Share your experience (optional)...',
        hintStyle: c.caption,
        filled: true,
        fillColor: c.inputBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: BorderSide(color: c.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: BorderSide(color: c.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          borderSide: BorderSide(color: AppTheme.primary, width: 1.5),
        ),
      ),
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
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: compact ? 28 : 48,
        padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 24),
        decoration: BoxDecoration(
          gradient: loading
              ? AppTheme.disableGradient
              : AppTheme.accentGradient,
             shape: BoxShape.circle,
          boxShadow: loading ? null : AppTheme.primaryShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: loading
              ? [
                  SizedBox(
                    width: compact ? 14 : 18,
                    height: compact ? 14 : 18,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                ]
              : [
                  Icon(Icons.send_rounded,
                      color: Colors.white, size: compact ? 14 : 16),

                ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════
//  SKELETON LOADER
// ══════════════════════════════════════════════

class _Skeleton extends StatefulWidget {
  final bool compact;
  const _Skeleton({required this.compact});

  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _shimmer = CurvedAnimation(parent: _anim, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (_, _) {
        final color = Color.lerp(c.divider, c.inputBg, _shimmer.value)!;
        if (widget.compact) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              5,
              (_) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  width: 16, height: 16,
                  decoration: BoxDecoration(
                      color: color, shape: BoxShape.circle),
                ),
              ),
            ),
          );
        }
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: c.brMedium,
            boxShadow: c.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 80, height: 12,
                  decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6))),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(width: 64, height: 64,
                      decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(8))),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      children: List.generate(5, (_) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(3))),
                      )),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.dangerTint,
        borderRadius: c.brMedium,
        border: Border.all(color: c.danger.withValues(alpha:0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, color: c.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Could not load ratings',
              style: c.body.copyWith(color: c.danger, fontSize: 13),
            ),
          ),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: c.danger.withValues(alpha:0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Retry',
                style: c.caption.copyWith(
                  color: c.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
