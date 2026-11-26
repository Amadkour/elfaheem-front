// lib/features/store/store_widgets.dart — the store's small shared pieces (D-1333): kind names and glyphs, the cover
// (a picture, else the course book cover), the price block (net / VAT / gross with the currency, the points price)
// and the browse card. Plain values only.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/courses/course_list_card.dart' show CourseCoverArt;
import 'package:flutter_education_app/features/store/store_models.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';

String storeKindLabel(String kind) => switch (kind) {
      'ebook' => t('كتاب إلكتروني', 'E-book'),
      'summary' => t('ملخص', 'Summary'),
      'notes' => t('مذكرة', 'Notes'),
      _ => t('ملف', 'File'),
    };

IconData storeKindIcon(String kind) => switch (kind) {
      'ebook' => Icons.menu_book_rounded,
      'summary' => Icons.summarize_rounded,
      'notes' => Icons.sticky_note_2_rounded,
      _ => Icons.description_rounded,
    };

String storePagesText(int pages) => t('$pages صفحة', pages == 1 ? '1 page' : '$pages pages');

/// "2.4 MB".
String storeSizeText(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// An item's cover: its picture, else the book cover the courses use (tone from the title).
class StoreCover extends StatelessWidget {
  const StoreCover({super.key, required this.id, required this.title, this.url = '', this.width, this.height});

  final int id;
  final String title, url;
  final double? width, height;

  @override
  Widget build(BuildContext context) {
    final art = CourseCoverArt(seed: id, label: title, toneKey: title, width: width, height: height);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: AppRadius.cardAll,
        child: url.isEmpty ? art : AppNetworkImage(url: url, width: width, height: height),
      ),
    );
  }
}

/// The price of an item: the gross large, then net · VAT (percent) with the currency, and the points price.
class StorePriceBlock extends StatelessWidget {
  const StorePriceBlock({super.key, required this.price, this.pointsPrice, this.compact = false});

  final StorePrice price;
  final int? pointsPrice;

  /// One line (the browse card).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = price;
    if (compact) {
      return Text(
        p.isFree ? 'sd_no_fee'.tr : storeMoney(p.gross, p.currency),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppType.bodyStrong(context).copyWith(color: c.primary),
      );
    }
    final lines = <(String, String)>[
      (t('السعر قبل الضريبة', 'Price before VAT'), storeMoney(p.net, p.currency)),
      (
        p.vat <= 0 && p.vatPercent <= 0 ? t('ضريبة القيمة المضافة', 'VAT') : '${t('ضريبة القيمة المضافة', 'VAT')} (${p.vatPercentText})',
        p.vat <= 0 && p.vatPercent <= 0 ? t('معفى', 'Exempt') : storeMoney(p.vat, p.currency),
      ),
    ];
    return Column(
      key: const ValueKey('store.price'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(p.isFree ? 'sd_no_fee'.tr : storeMoney(p.gross, p.currency),
            style: AppType.figureLarge(context).copyWith(color: c.textDark)),
        if (!p.isFree) ...[
          Text(t('الإجمالي شامل الضريبة', 'Total including VAT'), style: AppType.meta(context)),
          const SizedBox(height: AppSpace.xs),
          for (final (label, value) in lines)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xxs),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Text(label, style: AppType.meta(context))),
                const SizedBox(width: AppSpace.sm),
                Text(value, style: AppType.row(context)),
              ]),
            ),
        ],
        if (pointsPrice != null) ...[
          const SizedBox(height: AppSpace.xs),
          Row(children: [
            Icon(Icons.stars_rounded, size: AppIconSize.sm, color: c.primary),
            const SizedBox(width: AppSpace.xxs),
            Flexible(
              child: Text(t('أو $pointsPrice نقطة', 'or $pointsPrice points'),
                  style: AppType.row(context).copyWith(color: c.primary, fontWeight: FontWeight.w600)),
            ),
          ]),
        ],
      ],
    );
  }
}

/// The accent of an item's drawn cover: the same item keeps its colour on every screen.
AppAccent storeAccentOf(StoreItem item) => AppAccent.values[item.id.abs() % AppAccent.values.length];

/// A drawn book (an item without a picture): the accent's colour fading to its deep end, a darker spine on the
/// closing edge, the kind as a glass tag at the top and the title at the bottom. With [url] the picture is drawn
/// instead, in the same frame.
class StoreBookCover extends StatelessWidget {
  const StoreBookCover({super.key, required this.item, this.showTitle = true});

  final StoreItem item;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = c.kit.accent(storeAccentOf(item));
    final end = Color.lerp(tone.color, c.kit.deep, .28)!;
    final radius = BorderRadiusDirectional.only(
      topStart: const Radius.circular(AppRadius.tile),
      bottomStart: const Radius.circular(AppRadius.tile),
      topEnd: const Radius.circular(AppRadius.chip),
      bottomEnd: const Radius.circular(AppRadius.chip),
    );
    final tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
      decoration: BoxDecoration(color: c.heroGlass, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(storeKindLabel(item.kind), maxLines: 1, style: AppType.overline(context).copyWith(color: c.onHero)),
    );
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: radius,
        child: item.coverUrl.isNotEmpty
            ? Stack(fit: StackFit.expand, children: [
                AppNetworkImage(url: item.coverUrl),
                PositionedDirectional(top: AppSpace.xs, start: AppSpace.xs, child: tag),
              ])
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [tone.color, end]),
                ),
                child: Stack(fit: StackFit.expand, children: [
                  // the spine on the closing edge
                  PositionedDirectional(
                    top: 0,
                    bottom: 0,
                    end: 0,
                    width: AppSpace.sm,
                    child: ColoredBox(color: c.kit.deep.withValues(alpha: .18)),
                  ),
                  PositionedDirectional(top: AppSpace.xs, start: AppSpace.xs, child: tag),
                  if (showTitle)
                    PositionedDirectional(
                      start: AppSpace.sm,
                      end: AppSpace.md,
                      bottom: AppSpace.sm,
                      child: Text(item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.tileTitle(context).copyWith(color: c.onHero)),
                    ),
                ]),
              ),
      ),
    );
  }
}

/// "45 ريال أو 450 نقطة" (no "free" as a selling point: a free item says "بدون رسوم").
String storeCardPrice(StoreItem item) {
  final p = item.price;
  final money = p.isFree ? 'sd_no_fee'.tr : storeMoney(p.gross, p.currency);
  return item.pointsPrice == null || p.isFree ? money : '$money ${'sd_or_points'.tr.replaceAll('{n}', '${item.pointsPrice}')}';
}

/// A browse card (Stu2Store): the drawn book, the title, the pages, the price, and "في مكتبتك" / "في السلة" / a
/// round add button.
class StoreItemCard extends StatelessWidget {
  const StoreItemCard({super.key, required this.item, this.inCart = false, this.onTap, this.onAdd});

  final StoreItem item;
  final bool inCart;
  final VoidCallback? onTap;

  /// Puts the item in the cart; null hides the button.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final set = AppAreaScope.of(context);
    final price = storeCardPrice(item);
    final Widget? foot = item.owned
        ? AppStatusBadge(label: t('في مكتبتك', 'Owned'), tone: AppTone.success, dense: true)
        : inCart
            ? AppStatusBadge(label: t('في السلة', 'In cart'), tone: AppTone.warning, dense: true)
            : onAdd == null || item.price.isFree
                ? null
                : AppPop(
                    child: Semantics(
                      button: true,
                      label: 'sd_store_add'.tr,
                      child: AppJelly(
                        child: Material(
                          key: ValueKey('store.add.${item.id}'),
                          color: set.a,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onAdd,
                            child: SizedBox.square(
                              dimension: AppTouch.min,
                              child: Icon(Icons.add_rounded, color: set.btnFg, size: AppIconSize.md),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
    return Semantics(
      button: true,
      label: '${item.title}, $price',
      child: AppCard(
        key: ValueKey('store.card.${item.id}'),
        variant: AppCardVariant.flat,
        padding: const EdgeInsets.all(AppSpace.sm),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(child: AspectRatio(aspectRatio: 3 / 4, child: StoreBookCover(item: item))),
            const SizedBox(height: AppSpace.sm),
            ExcludeSemantics(
              child: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.tileTitle(context)),
            ),
            if (item.pages != null && item.pages! > 0)
              ExcludeSemantics(
                child: Text(appDigits(storePagesText(item.pages!)), maxLines: 1, style: AppType.meta(context)),
              ),
            const SizedBox(height: AppSpace.xs),
            ExcludeSemantics(
              child: Text(appDigits(price),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong(context).copyWith(color: context.colors.textDark)),
            ),
            if (foot != null) ...[
              const SizedBox(height: AppSpace.xs),
              Align(alignment: AlignmentDirectional.centerStart, child: foot),
            ],
          ],
        ),
      ),
    );
  }
}
