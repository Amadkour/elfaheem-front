// lib/features/games/champions/winner_sheet.dart — my win, said once (Games v3 §2.4, CONTRACT §6; kill switch
// `games.champions`).
//
//   WinnerSeen         the champion ids whose sheet this device has shown (SharedPreferences; the last 50)
//   showWinnerSheet    the sheet: a laurel in gold with ONE burst, "ما شاء الله، أنت بطل اليوم", the scope and the
//                      day, the reward (the coupon from GET /me/rewards when one was issued, "being checked" while
//                      pending) and "Use it" → My rewards on that coupon
//   WinnerSheetBody    the sheet's body with plain values (test/ui/champions_layout_test.dart)
//   HomeChampionLine   the line on the student home from the `champion` block of GET /me/home (no request of its
//                      own); the first time a win is drawn on this device it opens the sheet
//   WinnerBurstPainter at most 24 particles, one shot, nothing under Reduce motion
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppPopIn, appMotionOff;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/champions/champions_models.dart';
import 'package:flutter_education_app/features/rewards/rewards_api.dart';
import 'package:flutter_education_app/features/rewards/rewards_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WinnerSeen {
  WinnerSeen._();

  static const String prefKey = 'games.champion.seen.v1';
  static const int keepLast = 50;

  /// [ids] with [id] added at the end, the oldest dropped past [keepLast].
  static List<String> add(List<String> ids, int id) {
    final out = [for (final x in ids) if (x != '$id') x, '$id'];
    return out.length > keepLast ? out.sublist(out.length - keepLast) : out;
  }

  static Future<bool> has(int id) async {
    try {
      final p = await SharedPreferences.getInstance();
      return (p.getStringList(prefKey) ?? const []).contains('$id');
    } catch (_) {
      return true; // no storage: never nag
    }
  }

  static Future<void> mark(int id) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(prefKey, add(p.getStringList(prefKey) ?? const [], id));
    } catch (_) {}
  }
}

/// "ما شاء الله، أنت بطل اليوم" and its kin.
String winnerHeadline(HomeChampion w) {
  if (w.rank == 1) {
    return w.weekly ? t('ما شاء الله، أنت بطل الأسبوع', 'Masha\'Allah, you are this week\'s champion') : t('ما شاء الله، أنت بطل اليوم', 'Masha\'Allah, you are today\'s champion');
  }
  return w.weekly
      ? t('ما شاء الله، أنت في المركز ${w.rank} هذا الأسبوع', 'Masha\'Allah, you came number ${w.rank} this week')
      : t('ما شاء الله، أنت في المركز ${w.rank} اليوم', 'Masha\'Allah, you came number ${w.rank} today');
}

/// "Everyone · 22 Nov 2026" (the period's first day; a week names its first day too).
String winnerScopeLine(HomeChampion w) {
  final day = w.periodStart == null ? '' : ' · ${AppTime.date(w.periodStart!)}';
  return '${w.scope.name}$day';
}

/// Opens the sheet for [win]. [onUse] = "Use it" (My rewards on the coupon); [onHall] = the Hall on that board.
Future<void> showWinnerSheet(BuildContext context, HomeChampion win, {VoidCallback? onUse, VoidCallback? onHall, RewardsApi? api}) {
  WinnerSeen.mark(win.championId);
  return showAppSheet<void>(context, (ctx) => _WinnerSheet(win: win, api: api ?? RewardsApi(), onUse: onUse, onHall: onHall));
}

class _WinnerSheet extends StatefulWidget {
  const _WinnerSheet({required this.win, required this.api, this.onUse, this.onHall});

  final HomeChampion win;
  final RewardsApi api;
  final VoidCallback? onUse, onHall;

  @override
  State<_WinnerSheet> createState() => _WinnerSheetState();
}

class _WinnerSheetState extends State<_WinnerSheet> {
  Coupon? _coupon;

  @override
  void initState() {
    super.initState();
    final id = widget.win.couponId;
    if (id != null && widget.win.rewardStatus == 'issued' && !couponsOff()) {
      widget.api.mine().then((r) {
        if (!mounted) return;
        final c = r.coupons.where((c) => c.id == id).firstOrNull;
        if (c != null) setState(() => _coupon = c);
      }).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) => AppSheetContent(
        title: championTitle(widget.win),
        icon: Icons.emoji_events_rounded,
        tone: AppTone.gold,
        children: [
          WinnerSheetBody(
            win: widget.win,
            coupon: _coupon,
            onUse: widget.onUse == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    widget.onUse!();
                  },
            onHall: widget.onHall == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    widget.onHall!();
                  },
          ),
        ],
      );
}

class WinnerSheetBody extends StatelessWidget {
  const WinnerSheetBody({super.key, required this.win, this.coupon, this.onUse, this.onHall, this.burst = true});

  final HomeChampion win;
  final Coupon? coupon;
  final VoidCallback? onUse, onHall;
  final bool burst;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final gold = AppBlockColors.of(context, AppBlockTone.gold);
    final issued = win.rewardStatus == 'issued' && !couponsOff();
    final pending = win.rewardStatus == 'pending';
    final disc = AppTouch.primary * 2;
    return Column(key: const ValueKey('champions.winner'), crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Center(
        child: SizedBox(
          width: disc * 1.6,
          height: disc * 1.2,
          child: Stack(alignment: Alignment.center, children: [
            if (burst) const Positioned.fill(child: WinnerBurst()),
            AppPopIn(
              child: Container(
                width: disc,
                height: disc,
                decoration: BoxDecoration(
                  color: gold.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: gold.border ?? c.divider, width: AppBorder.strong),
                ),
                child: Icon(Icons.emoji_events_rounded, size: AppIconSize.xl * 1.5, color: appToneColor(context, AppTone.gold)),
              ),
            ),
          ]),
        ),
      ),
      AppSpace.gapSm,
      Semantics(
        header: true,
        liveRegion: true,
        child: Text(winnerHeadline(win), textAlign: TextAlign.center, style: AppType.headline(context)),
      ),
      AppSpace.gapXs,
      Text(winnerScopeLine(win), textAlign: TextAlign.center, style: AppType.meta(context)),
      AppSpace.gapMd,
      if (issued)
        AppCard(
          key: const ValueKey('champions.winner.coupon'),
          child: Row(children: [
            Icon(Icons.local_offer_rounded, color: c.primary),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(coupon?.valueText ?? t('قسيمة خصم في مكافآتي', 'A discount coupon in My rewards'), style: AppType.bodyStrong(context)),
                if (coupon?.expiresAt != null)
                  Text(t('صالحة حتى ${AppTime.date(coupon!.expiresAt!)}', 'Valid until ${AppTime.date(coupon!.expiresAt!)}'),
                      style: AppType.meta(context)),
              ]),
            ),
          ]),
        )
      else if (pending)
        Text(t('مكافأتك قيد المراجعة، وتصلك عند اعتمادها.', 'Your reward is being checked; it reaches you once approved.'),
            textAlign: TextAlign.center, style: AppType.body(context).copyWith(color: c.textMedium)),
      AppSpace.gapLg,
      if (issued && onUse != null)
        AppButton.primary(
          key: const ValueKey('champions.winner.use'),
          label: t('استخدمها', 'Use it'),
          icon: Icons.local_offer_rounded,
          expand: true,
          onPressed: onUse,
        ),
      if (onHall != null) ...[
        if (issued && onUse != null) AppSpace.gapXs,
        AppButton.ghost(
          key: const ValueKey('champions.winner.hall'),
          label: t('افتح لوحة الأبطال', 'Open the Hall of Champions'),
          expand: true,
          onPressed: onHall,
        ),
      ],
    ]);
  }
}

/// One burst of gold, sage and primary particles (at most 24), once; nothing under Reduce motion.
class WinnerBurst extends StatelessWidget {
  const WinnerBurst({super.key});

  @override
  Widget build(BuildContext context) {
    if (appMotionOff(context)) return const SizedBox.shrink();
    final c = context.colors;
    final colors = [appToneColor(context, AppTone.gold), c.success, c.primary];
    return RepaintBoundary(
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: AppMotion.of(context).slow * 3,
          builder: (context, v, _) => v >= 1 ? const SizedBox.shrink() : CustomPaint(painter: WinnerBurstPainter(t: v, colors: colors)),
        ),
      ),
    );
  }
}

class WinnerBurstPainter extends CustomPainter {
  WinnerBurstPainter({required this.t, required this.colors});

  static const int particles = 24;

  final double t;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final reach = size.shortestSide / 2;
    final ease = Curves.easeOutCubic.transform(t);
    final paint = Paint();
    for (var i = 0; i < particles; i++) {
      final a = (i / particles) * 2 * math.pi + (i.isEven ? 0.12 : -0.12);
      final d = reach * (0.45 + 0.55 * ease) * (i % 3 == 0 ? 1 : 0.8);
      final r = (1 - t) * (i % 2 == 0 ? 4.0 : 3.0);
      paint.color = colors[i % colors.length].withValues(alpha: (1 - t).clamp(0.0, 1.0));
      canvas.drawCircle(centre + Offset(math.cos(a) * d, math.sin(a) * d), r, paint);
    }
  }

  @override
  bool shouldRepaint(WinnerBurstPainter old) => old.t != t || old.colors != colors;
}

/// The student home's champion line (my newest win, from GET /me/home): trophy · "Champion of the day" · the board
/// and the day · chevron → [onOpen]. The first time a win is drawn on this device it opens the winner sheet
/// ([autoShow]; off in the layout tests).
class HomeChampionLine extends StatefulWidget {
  const HomeChampionLine({super.key, required this.win, this.onOpen, this.onUse, this.autoShow = true});

  final HomeChampion win;
  final VoidCallback? onOpen, onUse;
  final bool autoShow;

  @override
  State<HomeChampionLine> createState() => _HomeChampionLineState();
}

class _HomeChampionLineState extends State<HomeChampionLine> {
  @override
  void initState() {
    super.initState();
    if (widget.autoShow) _maybeShow();
  }

  @override
  void didUpdateWidget(HomeChampionLine old) {
    super.didUpdateWidget(old);
    if (widget.autoShow && old.win.championId != widget.win.championId) _maybeShow();
  }

  Future<void> _maybeShow() async {
    final id = widget.win.championId;
    if (await WinnerSeen.has(id)) return;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      showWinnerSheet(context, widget.win, onUse: widget.onUse, onHall: widget.onOpen);
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.win;
    final c = context.colors;
    final gold = AppBlockColors.of(context, AppBlockTone.gold);
    return Semantics(
      button: true,
      label: '${winnerHeadline(w)}, ${winnerScopeLine(w)}',
      excludeSemantics: true,
      child: AppCard(
        key: const ValueKey('home.champion'),
        onTap: widget.onOpen,
        child: Row(children: [
          Container(
            width: AppTouch.min,
            height: AppTouch.min,
            decoration: BoxDecoration(color: gold.surface, shape: BoxShape.circle),
            child: Icon(Icons.emoji_events_rounded, color: appToneColor(context, AppTone.gold)),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(championTitle(w), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
              Text(winnerScopeLine(w), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ]),
          ),
          const SizedBox(width: AppSpace.xs),
          Icon(Icons.chevron_right_rounded, color: c.textLight),
        ]),
      ),
    );
  }
}
