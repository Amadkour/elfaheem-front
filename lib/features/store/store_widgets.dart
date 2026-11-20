// lib/features/store/store_widgets.dart — the store's small shared pieces (D-1333): kind names and glyphs, the cover
// (a picture, else the course book cover), the price block (net / VAT / gross with the currency, the points price)
// and the browse card. Plain values only.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
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
        p.isFree ? t('مجاني', 'Free') : storeMoney(p.gross, p.currency),
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
        Text(p.isFree ? t('مجاني', 'Free') : storeMoney(p.gross, p.currency),
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

/// A browse card: cover, kind, title, price, "owned" / "in cart".
class StoreItemCard extends StatelessWidget {
  const StoreItemCard({super.key, required this.item, this.inCart = false, this.onTap});

  final StoreItem item;
  final bool inCart;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: '${item.title}, ${item.price.isFree ? t('مجاني', 'Free') : storeMoney(item.price.gross, item.price.currency)}',
      child: ExcludeSemantics(
        child: AppCard(
          key: ValueKey('store.card.${item.id}'),
          padding: const EdgeInsets.all(AppSpace.sm),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: StoreCover(id: item.id, title: item.title, url: item.coverUrl),
              ),
              const SizedBox(height: AppSpace.xs),
              Row(children: [
                Icon(storeKindIcon(item.kind), size: AppIconSize.sm, color: c.textMedium),
                const SizedBox(width: AppSpace.xxs),
                Expanded(
                  child: Text(
                    [storeKindLabel(item.kind), if (item.pages != null && item.pages! > 0) storePagesText(item.pages!)].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.meta(context),
                  ),
                ),
              ]),
              const SizedBox(height: AppSpace.xxs),
              Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              const SizedBox(height: AppSpace.xs),
              StorePriceBlock(price: item.price, pointsPrice: item.pointsPrice, compact: true),
              if (item.owned || inCart) ...[
                const SizedBox(height: AppSpace.xxs),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: item.owned
                      ? AppStatusBadge(label: t('في مكتبتك', 'Owned'), tone: AppTone.success, dense: true)
                      : AppStatusBadge(label: t('في السلة', 'In cart'), tone: AppTone.brand, dense: true),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
