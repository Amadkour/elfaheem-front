// lib/features/games/learner/coupon_unlock_card.dart — the daily winner's coupon that waits for friends (Games v4 T74,
// CONTRACT §11).
//
//   CouponUnlockCard   locked: a progress ring "1 of 3 friends joined", the Share-my-link button and a live countdown
//                      to the deadline. Unlocked: the code, a countdown to the expiry and "Choose your course"
//                      (any course, or one of the allowed list). Plain values in, callbacks out (no provider)
//   unlockCountdownText  "6 days 22 hours" / "3 hours 12 min" / "12 min 05 s", the units through countText
//   UnlockRing         the progress ring (a painter; a full ring with a tick when done)
//
// The countdown is the only moving part: ONE 1-second ticker that rebuilds the countdown line alone, only while the
// card is mounted. Times of day go through AppTime; Reduce motion keeps the ring still (no sweep).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show appMotionOff;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/rewards/rewards_models.dart';

String _daysUnit(int n) => countText(n, ar1: 'يوم', ar2: 'يومان', arFew: '{n} أيام', arMany: '{n} يومًا', en1: '1 day', en: '{n} days');
String _hoursUnit(int n) => countText(n, ar1: 'ساعة', ar2: 'ساعتان', arFew: '{n} ساعات', arMany: '{n} ساعة', en1: '1 hour', en: '{n} hours');
String _minutesUnit(int n) => countText(n, ar1: 'دقيقة', ar2: 'دقيقتان', arFew: '{n} دقائق', arMany: '{n} دقيقة', en1: '1 min', en: '{n} min');
String _secondsUnit(int n) => countText(n, ar1: 'ثانية', ar2: 'ثانيتان', arFew: '{n} ثوانٍ', arMany: '{n} ثانية', en1: '1 s', en: '{n} s');

/// A time left in its two biggest units; "now" at zero or below.
String unlockCountdownText(Duration d) {
  if (d <= Duration.zero) return t('انتهى الوقت', 'Time is up');
  final days = d.inDays, hours = d.inHours % 24, mins = d.inMinutes % 60, secs = d.inSeconds % 60;
  final parts = days > 0
      ? [_daysUnit(days), if (hours > 0) _hoursUnit(hours)]
      : d.inHours > 0
          ? [_hoursUnit(hours), if (mins > 0) _minutesUnit(mins)]
          : [if (d.inMinutes > 0) _minutesUnit(mins), _secondsUnit(secs)];
  return parts.join(t(' و', ' '));
}

/// "1 of 3 friends joined".
String unlockProgressText(int have, int need) => t(
      'انضم ${countText(have, ar1: 'صديق واحد', ar2: 'صديقان', arFew: '$have أصدقاء', arMany: '$have صديقًا', en1: '1 friend', en: '$have friends', ar0: 'لم ينضم أحد بعد', en0: 'No friends yet')} من $need',
      '$have of $need friends joined',
    );

class CouponUnlockCard extends StatefulWidget {
  const CouponUnlockCard({
    super.key,
    required this.coupon,
    this.now,
    this.courseTitles = const {},
    this.onShare,
    this.onChooseCourse,
  });

  final Coupon coupon;

  /// A fixed clock for tests and goldens (UTC); null = the real clock, ticking.
  final DateTime? now;

  /// Titles of the allowed courses (id → title), when the page has them.
  final Map<int, String> courseTitles;

  /// Share my invite link; null hides the button (referral switched off).
  final VoidCallback? onShare;

  /// "Choose your course": the page opens the list or the course catalogue.
  final VoidCallback? onChooseCourse;

  @override
  State<CouponUnlockCard> createState() => _CouponUnlockCardState();
}

class _CouponUnlockCardState extends State<CouponUnlockCard> {
  Timer? _timer;
  late final ValueNotifier<DateTime> _clock = ValueNotifier(widget.now ?? DateTime.now().toUtc());

  @override
  void initState() {
    super.initState();
    if (widget.now == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _clock.value = DateTime.now().toUtc());
    }
  }

  @override
  void didUpdateWidget(CouponUnlockCard old) {
    super.didUpdateWidget(old);
    if (widget.now != null) _clock.value = widget.now!;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final k = widget.coupon;
    final need = k.unlockNeed ?? 0;
    final locked = k.status == 'locked';
    final have = locked ? k.unlockHave.clamp(0, need) : need;
    final tone = locked ? AppTone.warning : AppTone.success;
    final gold = AppBlockColors.of(context, AppBlockTone.gold);
    final end = locked ? k.unlockDeadline : k.expiresAt;
    return Container(
      key: ValueKey('rewards.coupon.${k.id}.unlock'),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: locked ? c.divider : c.success, width: locked ? AppBorder.hairline : AppBorder.strong),
      ),
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: AppTouch.min,
            height: AppTouch.min,
            decoration: BoxDecoration(color: gold.surface, shape: BoxShape.circle),
            child: Icon(locked ? Icons.lock_rounded : Icons.lock_open_rounded, color: gold.ink),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(k.valueText, style: AppType.bodyStrong(context)),
              const SizedBox(height: AppSpace.xxs),
              Text('${k.sourceText} · ${_scopeText(k)}', style: AppType.meta(context)),
            ]),
          ),
          const SizedBox(width: AppSpace.xs),
          AppStatusBadge(label: locked ? t('مقفلة', 'Locked') : t('مفتوحة', 'Unlocked'), tone: tone, dense: true),
        ]),
        const SizedBox(height: AppSpace.md),
        if (locked) ...[
          Row(children: [
            UnlockRing(key: const ValueKey('unlock.ring'), have: have, need: need, done: false),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(unlockProgressText(have, need), key: const ValueKey('unlock.progress'), style: AppType.bodyStrong(context)),
                const SizedBox(height: AppSpace.xxs),
                Text(
                  t('ادعُ أصدقاءك للتسجيل برابطك لتفتح القسيمة${k.validHours == null ? '' : '، وتبقى صالحة ${_hoursUnit(k.validHours!)} بعد الفتح'}.',
                      'Friends who sign up with your link unlock it${k.validHours == null ? '' : ', then it stays valid ${_hoursUnit(k.validHours!)}'}.'),
                  style: AppType.meta(context),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: AppSpace.sm),
        ] else ...[
          Row(children: [
            UnlockRing(key: const ValueKey('unlock.ring'), have: need, need: need, done: true),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('انفتحت قسيمتك', 'Your coupon is unlocked'), style: AppType.bodyStrong(context)),
                const SizedBox(height: AppSpace.xxs),
                Text(t('اختر الكورس الذي تريده وخذ الخصم.', 'Choose the course you want and take the discount.'), style: AppType.meta(context)),
              ]),
            ),
          ]),
          const SizedBox(height: AppSpace.sm),
          _CodeRow(code: k.code, id: k.id),
          const SizedBox(height: AppSpace.sm),
        ],
        if (end != null) _Countdown(clock: _clock, end: end, locked: locked),
        const SizedBox(height: AppSpace.sm),
        if (locked && widget.onShare != null)
          AppButton.primary(
            key: ValueKey('rewards.coupon.${k.id}.share'),
            label: t('شارك رابط دعوتك', 'Share my invite link'),
            icon: Icons.share_rounded,
            expand: true,
            onPressed: widget.onShare,
          ),
        if (!locked && widget.onChooseCourse != null)
          AppButton.primary(
            key: ValueKey('rewards.coupon.${k.id}.choose'),
            label: t('اختر كورسك', 'Choose your course'),
            icon: Icons.school_rounded,
            expand: true,
            onPressed: widget.onChooseCourse,
          ),
      ]),
    );
  }

  String _scopeText(Coupon k) {
    final ids = k.courseIds;
    if (ids == null || ids.isEmpty) return t('لكورس واحد تختاره', 'For one course you choose');
    if (ids.length == 1) {
      final title = widget.courseTitles[ids.first];
      return title == null ? t('لكورس محدد', 'For one set course') : t('لكورس $title', 'For $title');
    }
    return t('لكورس واحد من ${ids.length}', 'For one of ${ids.length} courses');
  }
}

/// "Time left to unlock: 6 days 22 hours" with the date under it; rebuilt every second on its own.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.clock, required this.end, required this.locked});

  final ValueListenable<DateTime> clock;
  final DateTime end;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final gold = AppBlockColors.of(context, AppBlockTone.gold);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
      decoration: BoxDecoration(color: gold.surface, borderRadius: AppRadius.controlAll),
      child: Row(children: [
        Icon(Icons.timer_outlined, size: AppIconSize.md, color: gold.ink),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: ValueListenableBuilder<DateTime>(
            valueListenable: clock,
            builder: (context, now, _) {
              final left = end.difference(now);
              return Semantics(
                container: true,
                label: '${locked ? t('الوقت المتبقي للفتح', 'Time left to unlock') : t('الوقت المتبقي للاستخدام', 'Time left to use it')}: ${unlockCountdownText(left)}',
                excludeSemantics: true,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    '${locked ? t('يتبقى لفتحها', 'Time left to unlock') : t('تنتهي بعد', 'Expires in')}: ${unlockCountdownText(left)}',
                    key: const ValueKey('unlock.countdown'),
                    style: AppType.bodyStrong(context).copyWith(color: gold.ink),
                  ),
                  Text(
                    locked ? t('الموعد النهائي ${AppTime.dateTime(end)}', 'Deadline ${AppTime.dateTime(end)}') : t('صالحة حتى ${AppTime.dateTime(end)}', 'Valid until ${AppTime.dateTime(end)}'),
                    style: AppType.meta(context).copyWith(color: c.textMedium),
                  ),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _CodeRow extends StatelessWidget {
  const _CodeRow({required this.code, required this.id});

  final String code;
  final int id;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      Expanded(
        child: Semantics(
          label: t('رمز القسيمة $code', 'Coupon code $code'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
            decoration: BoxDecoration(color: c.background, borderRadius: AppRadius.controlAll, border: Border.all(color: c.divider, width: AppBorder.hairline)),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(code, maxLines: 1, style: AppType.bodyStrong(context).copyWith(letterSpacing: 1.5)),
            ),
          ),
        ),
      ),
      const SizedBox(width: AppSpace.xs),
      IconButton(
        key: ValueKey('rewards.coupon.$id.copy'),
        tooltip: t('نسخ الرمز', 'Copy the code'),
        icon: const Icon(Icons.copy_rounded),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: code));
          showAppNotice(t('نُسخ الرمز', 'Code copied'));
        },
      ),
    ]);
  }
}

/// The ring: [have] of [need] as an arc from the top, the number in the middle; [done] = a full ring and a tick.
/// The arc sweeps in once (a tween), still under Reduce motion.
class UnlockRing extends StatelessWidget {
  const UnlockRing({super.key, required this.have, required this.need, this.done = false});

  final int have, need;
  final bool done;

  static double get size => AppTouch.primary * 2;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final gold = AppBlockColors.of(context, AppBlockTone.gold);
    final target = need <= 0 ? 1.0 : (have / need).clamp(0.0, 1.0);
    final off = appMotionOff(context);
    final fill = done ? c.success : appToneColor(context, AppTone.gold);
    return Semantics(
      label: unlockProgressText(have, need),
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: off ? target : 0, end: target),
          duration: AppMotion.of(context).slow * 3,
          curve: AppMotion.curve,
          builder: (context, v, child) => CustomPaint(
            painter: _RingPainter(progress: v, track: gold.surface, fill: fill, width: AppSpace.xs),
            child: child,
          ),
          child: Center(
            child: done
                ? Icon(Icons.check_rounded, size: AppIconSize.xl, color: c.success)
                : Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '$have', style: AppType.headline(context)),
                        TextSpan(text: ' / $need', style: AppType.meta(context)),
                      ]),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.track, required this.fill, required this.width});

  final double progress, width;
  final Color track, fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, p..color = track);
    if (progress > 0) canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, p..color = fill);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.track != track || old.fill != fill;
}
