// lib/features/games/learner/wardrobe.dart — coins and the wardrobe (Games v4 T73, kill switch `games.cosmetics`).
//
//   CoinsPill       the learner's coins as a gold pill (reusable: the games home, a result sheet); the number counts
//                   down when coins are spent and a "-N" floats up (parked under Reduce motion).
//   WardrobePage    the stateful screen: GET /games/cosmetics, buy (coins only, with a confirm), equip / unequip
//                   (PUT /me/games/profile {equipped}); `showWardrobe(context, api:, ageBand:)` pushes it.
//   WardrobeView    plain values (test/ui/wardrobe_test.dart, the goldens): the character previewed live with the
//                   idle motion, tabs by slot (hat / outfit / vehicle / trail), item cards: owned, price in coins, or
//                   locked with its unlock rule. A tap on a card tries the item on the character; the one button of a
//                   card buys or equips. The character always wears the TRY-ON first, then what is equipped.
//
// Never real money: a price is coins earned by playing. Calm / sacred rounds ignore the wardrobe on purpose
// (GameCharacter draws the default look there); this screen is not a sacred round.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/profile/sd_area.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show appMotionOff;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/content/games_v4_api.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';
import 'package:flutter_education_app/features/games/core/game_character.dart';
import 'package:flutter_education_app/features/games/games_api.dart' show gamesErrorText;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

/// The fixed width of the wardrobe's stage column on a wide screen.
const double _kStageW = 380;

const kGamesCosmeticsKey = 'games.cosmetics';
bool gamesCosmeticsOff() => AppConfig.disableList.contains(kGamesCosmeticsKey);

const kWardrobeSlots = ['hat', 'outfit', 'vehicle', 'trail'];

String slotName(String slot) => switch (slot) {
      'hat' => t('القبعات', 'Hats'),
      'outfit' => t('الملابس', 'Outfits'),
      'vehicle' => t('المركبات', 'Rides'),
      'trail' => t('الأثر', 'Trails'),
      _ => slot,
    };

IconData slotIcon(String slot) => switch (slot) {
      'hat' => Icons.emoji_events_rounded,
      'outfit' => Icons.checkroom_rounded,
      'vehicle' => Icons.rocket_launch_rounded,
      'trail' => Icons.auto_awesome_rounded,
      _ => Icons.star_rounded,
    };

String cosmeticName(V4CosmeticItem i) => t(i.nameAr.isEmpty ? i.nameEn : i.nameAr, i.nameEn.isEmpty ? i.nameAr : i.nameEn);

/// The unlock rule in words (no plural nouns: the figures stand beside a label).
String unlockText(Map<String, dynamic> lock) {
  final have = lock['have'] is num ? (lock['have'] as num).toInt() : 0;
  final count = lock['count'] is num ? (lock['count'] as num).toInt() : 0;
  return switch ('${lock['type']}') {
    'stars' => t('النجوم: $have / $count', 'Stars: $have / $count'),
    'levels' => t('مستويات بنجمة: $have / $count', 'Levels with a star: $have / $count'),
    'champion' => t('تفوز بتحدٍّ مرة', 'Win a championship once'),
    _ => t('مقفل', 'Locked'),
  };
}

// ---------------------------------------------------------------------------------------------------------------------
// coins pill

/// The gold coins pill. [coins] changing downwards counts down and floats "-N"; upwards it counts up.
class CoinsPill extends StatefulWidget {
  const CoinsPill({super.key, required this.coins, this.theme});
  final int coins;

  /// Null = the surrounding [AgeThemeScope].
  final AgeTheme? theme;

  @override
  State<CoinsPill> createState() => _CoinsPillState();
}

class _CoinsPillState extends State<CoinsPill> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late int _from = widget.coins;
  int _delta = 0;

  @override
  void didUpdateWidget(CoinsPill old) {
    super.didUpdateWidget(old);
    if (old.coins != widget.coins) {
      _from = old.coins;
      _delta = widget.coins - old.coins;
      if (appMotionOff(context)) {
        _c.value = 1;
      } else {
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final age = widget.theme ?? AgeThemeScope.of(context);
    final gold = age.palette.gold;
    return Semantics(
      label: t('${widget.coins} عملة', '${widget.coins} coins'),
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final k = Curves.easeOutCubic.transform(_c.value);
          final shown = (_delta == 0 || _c.value >= 1) ? widget.coins : (_from + (_delta * k)).round();
          final float = _delta < 0 && _c.value > 0 && _c.value < 1;
          return Stack(clipBehavior: Clip.none, alignment: AlignmentDirectional.center, children: [
            Container(
              key: const ValueKey('games.coins'),
              constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xs),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
              decoration: BoxDecoration(
                color: Color.alphaBlend(gold.withValues(alpha: 0.22), c.cardBg),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: gold, width: age.age == GameAge.kids ? AppBorder.strong : AppBorder.hairline),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Transform.scale(
                  scale: float ? 1 + 0.25 * (1 - (2 * _c.value - 1).abs()) : 1,
                  child: Icon(Icons.monetization_on_rounded, color: gold, size: AppIconSize.md),
                ),
                const SizedBox(width: AppSpace.xs),
                Text('$shown', style: AppType.figure(context)),
              ]),
            ),
            if (float)
              PositionedDirectional(
                top: -AppSpace.md - AppSpace.sm * _c.value,
                end: AppSpace.xs,
                child: Opacity(
                  opacity: (1 - _c.value).clamp(0.0, 1.0),
                  child: Text('$_delta', style: AppType.bodyStrong(context).copyWith(color: age.palette.accent), textDirection: TextDirection.ltr),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// the screen

Future<void> showWardrobe(BuildContext context, {GamesV4Api? api, String? ageBand}) => Navigator.of(context).push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/games/wardrobe'),
      builder: (_) => WardrobePage(api: api, ageBand: ageBand),
    ));

class WardrobePage extends StatefulWidget {
  const WardrobePage({super.key, this.api, this.ageBand});
  final GamesV4Api? api;
  final String? ageBand;

  @override
  State<WardrobePage> createState() => _WardrobePageState();
}

class _WardrobePageState extends State<WardrobePage> {
  late final GamesV4Api _api = widget.api ?? GamesV4Api();
  V4Cosmetics? _data;
  Map<String, String?> _equipped = {};
  String? _ageBand;
  String? _error;
  bool _busy = false;
  int _tab = 0;
  final Map<String, String> _tryOn = {};

  @override
  void initState() {
    super.initState();
    _ageBand = widget.ageBand;
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _api.cosmetics();
      V4Profile? p;
      if (_ageBand == null || _data == null) {
        try {
          p = await _api.profile();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
        _ageBand ??= p?.ageBand;
        _equipped = {for (final i in d.items) if (i.equipped) i.slot: i.key};
      });
    } catch (e) {
      if (mounted) setState(() => _error = gamesErrorText(e));
    }
  }

  Future<void> _buy(V4CosmeticItem i) async {
    if (_busy) return;
    final ok = await appConfirm(context,
        message: t('تشتري «${cosmeticName(i)}» مقابل ${i.priceCoins} عملة؟', 'Buy “${cosmeticName(i)}” for ${i.priceCoins} coins?'),
        confirmLabel: t('اشترِ', 'Buy'));
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await _api.buy(i.key);
      if (!mounted) return;
      await _equip(i, bought: r.coins);
      if (mounted) showAppNotice(t('صار لك «${cosmeticName(i)}»', 'You got “${cosmeticName(i)}”'));
    } catch (e) {
      if (!mounted) return;
      showAppNotice(_buyError(e), error: true);
      _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _buyError(Object e) {
    final code = _code(e);
    return switch (code) {
      'not_enough_coins' => t('عملاتك لا تكفي بعد', 'Not enough coins yet'),
      'cosmetic_locked' => t('هذا العنصر ما زال مقفلًا', 'This item is still locked'),
      'cosmetic_owned' => t('تملكه بالفعل', 'You already own it'),
      _ => gamesErrorText(e),
    };
  }

  String _code(Object e) {
    try {
      return '${(e as dynamic).code ?? ''}';
    } catch (_) {
      return '';
    }
  }

  /// Wear [i] (or take it off when it is already worn).
  Future<void> _equip(V4CosmeticItem i, {int? bought}) async {
    final d = _data;
    if (d == null) return;
    final wearing = _equipped[i.slot] == i.key && bought == null;
    final next = {..._equipped};
    if (wearing) {
      next.remove(i.slot);
    } else {
      next[i.slot] = i.key;
    }
    setState(() {
      _busy = true;
      _data = V4Cosmetics(coins: bought ?? d.coins, items: [
        for (final x in d.items)
          V4CosmeticItem({
            ...x.raw,
            if (x.key == i.key && bought != null) 'owned': true,
            'equipped': next[x.slot] == x.key,
          }),
      ]);
      _equipped = next;
      _tryOn.remove(i.slot);
    });
    try {
      await _api.saveProfile(equipped: {for (final s in kWardrobeSlots) s: next[s]});
    } catch (e) {
      if (mounted) {
        showAppNotice(gamesErrorText(e), error: true);
        _load();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final theme = AgeTheme.of(context, band: _ageBand);
    final Widget body;
    if (d == null) {
      body = _error == null
          ? const Padding(padding: EdgeInsets.all(AppSpace.md), child: AppListSkeleton(items: 4, padding: EdgeInsets.zero))
          : AppErrorState(message: _error, onRetry: _load);
    } else {
      body = AgeThemeScope(
        theme: theme,
        child: WardrobeView(
          coins: d.coins,
          items: d.items,
          equipped: _equipped,
          tab: _tab,
          tryOn: _tryOn,
          busy: _busy,
          theme: theme,
          onTab: (v) => setState(() => _tab = v),
          onTry: (i) => setState(() => _tryOn[i.slot] = i.key),
          onBuy: _buy,
          onEquip: _equip,
        ),
      );
    }
    return SdArea(area: AppArea.games, child: BasePage(
      key: const ValueKey(kGamesCosmeticsKey),
      width: AppWidth.wide,
      appBar: ScreenAppBar(title: t('خزانتي', 'My wardrobe'), helpPageId: 'games.wardrobe'),
      child: SdHeroColumn(title: 'sd_h_wardrobe'.tr, subtitle: 'sd_h_wardrobe_d'.tr, icon: Icons.checkroom_rounded, child: SafeArea(child: body)),
    ));
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// plain values

class WardrobeView extends StatelessWidget {
  const WardrobeView({
    super.key,
    required this.coins,
    required this.items,
    required this.equipped,
    required this.theme,
    this.tab = 0,
    this.tryOn = const {},
    this.busy = false,
    this.onTab,
    this.onTry,
    this.onBuy,
    this.onEquip,
  });

  final int coins;
  final List<V4CosmeticItem> items;

  /// slot → the worn key.
  final Map<String, String?> equipped;
  final AgeTheme theme;
  final int tab;

  /// slot → a key tried on (shown on the character, not saved).
  final Map<String, String> tryOn;
  final bool busy;
  final ValueChanged<int>? onTab;
  final ValueChanged<V4CosmeticItem>? onTry, onBuy, onEquip;

  @override
  Widget build(BuildContext context) {
    final slot = kWardrobeSlots[tab.clamp(0, kWardrobeSlots.length - 1)];
    final shown = [for (final i in items) if (i.slot == slot) i];
    final worn = {...equipped, ...tryOn};
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 900;
      final gutter = AppSpace.gutter(box.maxWidth);
      final stage = _Stage(coins: coins, worn: worn, theme: theme, compact: !wide && box.maxHeight < 700);
      final tabs = AppTabs(
        items: [for (final s in kWardrobeSlots) AppTabItem(slotName(s), icon: slotIcon(s))],
        index: tab,
        onChanged: (v) => onTab?.call(v),
      );
      Widget grid(double width) {
        if (shown.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: AppSpace.lg),
            child: AppEmpty(icon: slotIcon(slot), title: t('لا شيء هنا بعد', 'Nothing here yet')),
          );
        }
        final cols = width >= 700 ? 3 : (width >= 420 ? 2 : 1);
        final gap = AppSpace.sm;
        final w = (width - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final i in shown)
            SizedBox(
              width: w,
              child: _ItemCard(
                item: i,
                worn: equipped[i.slot] == i.key,
                tried: tryOn[i.slot] == i.key,
                coins: coins,
                busy: busy,
                theme: theme,
                onTry: () => onTry?.call(i),
                onBuy: () => onBuy?.call(i),
                onEquip: () => onEquip?.call(i),
              ),
            ),
        ]);
      }

      if (wide) {
        return Padding(
          padding: EdgeInsets.fromLTRB(gutter, AppSpace.md, gutter, AppSpace.md),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: _kStageW, child: stage),
            const SizedBox(width: AppSpace.lg),
            Expanded(
              child: ListView(children: [
                tabs,
                const SizedBox(height: AppSpace.md),
                grid(box.maxWidth - gutter * 2 - 380 - AppSpace.lg),
              ]),
            ),
          ]),
        );
      }
      return ListView(
        padding: EdgeInsets.fromLTRB(gutter, AppSpace.md, gutter, AppSpace.xl),
        children: [
          stage,
          const SizedBox(height: AppSpace.md),
          tabs,
          const SizedBox(height: AppSpace.md),
          grid(box.maxWidth - gutter * 2),
        ],
      );
    });
  }
}

/// The sky panel: the character on a painted ground, the coins pill on top.
class _Stage extends StatelessWidget {
  const _Stage({required this.coins, required this.worn, required this.theme, this.compact = false});
  final int coins;
  final Map<String, String?> worn;
  final AgeTheme theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = theme.palette;
    final h = compact ? 200.0 : 280.0;
    return Semantics(
      label: t('معاينة الشخصية', 'Character preview'),
      child: Container(
        key: const ValueKey('games.wardrobe.stage'),
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.hero),
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [p.skyTop, p.skyMid, p.skyBottom]),
          border: Border.all(color: p.ink.withValues(alpha: theme.age == GameAge.kids ? 0.5 : 0.14), width: theme.age == GameAge.kids ? AppBorder.strong : AppBorder.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          // the ground and the sun's glow
          PositionedDirectional(
            start: 0,
            end: 0,
            bottom: 0,
            height: h * 0.22,
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [p.mid, p.near])),
            ),
          ),
          PositionedDirectional(
            end: AppSpace.lg,
            top: AppSpace.lg,
            child: Container(
              width: h * 0.16,
              height: h * 0.16,
              decoration: BoxDecoration(shape: BoxShape.circle, color: p.glow.withValues(alpha: 0.85)),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(top: AppSpace.xl).copyWith(bottom: h * 0.08),
              child: Center(child: GameCharacter(theme: theme, equipped: worn, size: compact ? 150 : 210)),
            ),
          ),
          PositionedDirectional(top: AppSpace.sm, start: AppSpace.sm, child: CoinsPill(coins: coins, theme: theme)),
        ]),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.worn,
    required this.tried,
    required this.coins,
    required this.busy,
    required this.theme,
    this.onTry,
    this.onBuy,
    this.onEquip,
  });
  final V4CosmeticItem item;
  final bool worn, tried, busy;
  final int coins;
  final AgeTheme theme;
  final VoidCallback? onTry, onBuy, onEquip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = theme.palette;
    final lock = item.locked;
    final locked = lock != null && !item.owned;
    final canAfford = coins >= item.priceCoins;
    final accent = p.accent;
    final edge = worn || tried ? accent : c.cardEdge;
    final kids = theme.age == GameAge.kids;

    final Widget action;
    if (item.owned) {
      action = AppButton(
        key: ValueKey('games.wardrobe.equip.${item.key}'),
        label: worn ? t('إزالة', 'Take off') : t('ارتدِ', 'Wear'),
        icon: worn ? Icons.check_circle_rounded : Icons.checkroom_rounded,
        variant: worn ? AppButtonVariant.secondary : AppButtonVariant.primary,
        expand: true,
        onPressed: busy ? null : onEquip,
      );
    } else if (locked) {
      action = const SizedBox.shrink();
    } else {
      action = AppButton(
        key: ValueKey('games.wardrobe.buy.${item.key}'),
        label: canAfford ? t('اشترِ · ${item.priceCoins}', 'Buy · ${item.priceCoins}') : t('تحتاج ${item.priceCoins - coins} أخرى', 'Need ${item.priceCoins - coins} more'),
        icon: Icons.monetization_on_rounded,
        expand: true,
        onPressed: busy || !canAfford ? null : onBuy,
      );
    }

    return Semantics(
      label: '${cosmeticName(item)}. ${item.owned ? (worn ? t('ترتديه', 'Worn') : t('تملكه', 'Owned')) : locked ? unlockText(lock) : t('${item.priceCoins} عملة', '${item.priceCoins} coins')}',
      child: Material(
        color: Color.alphaBlend(accent.withValues(alpha: worn ? 0.1 : 0), c.cardBg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: edge, width: worn || tried ? AppBorder.strong : AppBorder.hairline),
        ),
        child: InkWell(
          key: ValueKey('games.wardrobe.item.${item.key}'),
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: locked ? null : onTry,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Container(
                  width: AppTouch.min,
                  height: AppTouch.min,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.alphaBlend(accent.withValues(alpha: locked ? 0.06 : 0.16), c.cardBg),
                    border: kids ? Border.all(color: accent, width: AppBorder.strong) : null,
                  ),
                  child: Icon(locked ? Icons.lock_rounded : slotIcon(item.slot), color: locked ? c.textMedium : accent, size: AppIconSize.lg),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(cosmeticName(item), style: AppType.row(context), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: AppSpace.xxs),
                    _Status(item: item, worn: worn, locked: locked, theme: theme),
                  ]),
                ),
              ]),
              if (item.owned || !locked) ...[const SizedBox(height: AppSpace.sm), action],
            ]),
          ),
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.item, required this.worn, required this.locked, required this.theme});
  final V4CosmeticItem item;
  final bool worn, locked;
  final AgeTheme theme;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (item.owned) {
      return Text(worn ? t('ترتديه الآن', 'Wearing it') : t('في خزانتك', 'In your wardrobe'), style: AppType.meta(context).copyWith(color: worn ? theme.palette.accent : c.textMedium));
    }
    if (locked) {
      return Text(unlockText(item.locked!), style: AppType.meta(context).copyWith(color: c.textMedium));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.monetization_on_rounded, size: AppIconSize.sm, color: theme.palette.gold),
      const SizedBox(width: AppSpace.xxs),
      Text('${item.priceCoins}', style: AppType.meta(context)),
    ]);
  }
}
