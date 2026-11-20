// lib/features/store/store_item_page.dart — one store item (D-1333): cover, kind, title, the price as net / VAT /
// gross with the currency and the points price, a preview, Buy and Add to cart.
//
//   StoreItemPage     loads GET /api/v1/store/items/{id}; Buy goes through GuestGuard with the pending intent
//                     `buy_store_item` (a guest signs in and lands back here with the checkout open, D-1324);
//                     [openCheckout] = that resume, done only by [storeResumeAction]'s rules
//   StoreItemView     the page's body with plain values (test/ui/store_layout_test.dart)
//   storeResumeAction what a resumed `buy_store_item` may do: nothing with the tab off, the page alone when the item
//                     is owned or buying is off, the page with its checkout otherwise
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/routing/pending_intent.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/guest/guest_state.dart';
import 'package:flutter_education_app/features/store/store_api.dart';
import 'package:flutter_education_app/features/store/store_checkout.dart';
import 'package:flutter_education_app/features/store/store_library.dart';
import 'package:flutter_education_app/features/store/store_models.dart';
import 'package:flutter_education_app/features/store/store_widgets.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:url_launcher/url_launcher.dart';

/// What a resumed "buy this item" may open.
enum StoreResumeAction { none, page, checkout }

/// The store tab off → nothing; the item owned, or buying off → its page only; else the page with its checkout.
/// [owned] null = not known yet (the page decides once the item is loaded).
StoreResumeAction storeResumeAction({bool? owned, List<String> disabled = const []}) {
  if (disabled.contains(kStoreTabKey)) return StoreResumeAction.none;
  if (owned == true || storeBuyOff(disabled)) return StoreResumeAction.page;
  return StoreResumeAction.checkout;
}

/// MyAuthProvider.resumePendingIntent's `buy_store_item`: opens the item page, with its checkout when allowed.
Future<void> resumeStoreBuy(NavigatorState nav, PendingIntent intent, {List<String>? disabled}) async {
  final id = int.tryParse(intent.id);
  if (id == null || !nav.mounted) return;
  final action = storeResumeAction(disabled: disabled ?? AppConfig.disableList);
  if (action == StoreResumeAction.none) return;
  nav.push(MaterialPageRoute<void>(
    settings: RouteSettings(name: '/store/$id'),
    builder: (_) => StoreItemPage(itemId: id, openCheckout: action == StoreResumeAction.checkout),
  ));
}

class StoreItemPage extends StatefulWidget {
  const StoreItemPage({super.key, required this.itemId, this.initial, this.openCheckout = false, this.api});

  final int itemId;

  /// The browse card, drawn while the full item loads.
  final StoreItem? initial;

  /// Open the checkout once loaded (a guest's resumed "buy"), unless [storeResumeAction] says no.
  final bool openCheckout;
  final StoreApi? api;

  @override
  State<StoreItemPage> createState() => _StoreItemPageState();
}

class _StoreItemPageState extends State<StoreItemPage> {
  late final StoreApi _api = widget.api ?? StoreApi();
  StoreItem? _item;
  bool _loading = true;
  String? _error;
  bool _resumed = false;

  @override
  void initState() {
    super.initState();
    _item = widget.initial;
    StoreCart.instance.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    StoreCart.instance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final it = await _api.item(widget.itemId);
      if (!mounted) return;
      setState(() {
        _item = it;
        _loading = false;
      });
      if (widget.openCheckout && !_resumed) {
        _resumed = true;
        if (storeResumeAction(owned: it.owned, disabled: AppConfig.disableList) == StoreResumeAction.checkout) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _buy();
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = storeErrorText(e);
        _loading = false;
      });
    }
  }

  Future<void> _buy() async {
    final it = _item;
    if (it == null) return;
    final paid = await showStoreCheckout(context, [it], api: _api);
    if (!paid || !mounted) return;
    _load();
    Navigator.of(context).push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/store/library'),
      builder: (_) => StoreLibraryPage(api: _api),
    ));
  }

  void _onBuy() {
    final it = _item;
    if (it == null) return;
    GuestGuard.run(
      context,
      _buy,
      reasonKey: 'guest_reason_generic',
      intent: PendingIntent(kind: PendingIntentKind.buyStoreItem, id: '${it.id}'),
    );
  }

  void _toggleCart() {
    final it = _item;
    if (it == null) return;
    final cart = StoreCart.instance;
    if (cart.contains(it.id)) {
      cart.remove(it.id);
    } else {
      cart.add(it);
      showAppNotice(t('أُضيف إلى السلة', 'Added to the cart'));
    }
  }

  Future<void> _preview() async {
    final u = Uri.tryParse(_item?.previewUrl ?? '');
    if (u == null) return;
    final ok = await launchUrl(u, mode: LaunchMode.externalApplication);
    if (!ok) showAppNotice(t('تعذّر فتح المعاينة', 'The preview could not be opened'), error: true);
  }

  @override
  Widget build(BuildContext context) {
    final it = _item;
    return BasePage(
      width: AppWidth.content,
      appBar: ScreenAppBar(title: it?.title ?? t('المتجر', 'Store')),
      child: SafeArea(
        child: it == null
            ? (_loading
                ? const AppListSkeleton(items: 4)
                : AppErrorState(message: _error, onRetry: _load))
            : StoreItemView(
                item: it,
                inCart: StoreCart.instance.contains(it.id),
                buyOff: storeBuyOff(),
                onBuy: _onBuy,
                onToggleCart: _toggleCart,
                onPreview: it.previewUrl == null || it.previewIsImage ? null : _preview,
              ),
      ),
    );
  }
}

/// The page's body with plain values.
class StoreItemView extends StatelessWidget {
  const StoreItemView({
    super.key,
    required this.item,
    this.inCart = false,
    this.buyOff = false,
    this.onBuy,
    this.onToggleCart,
    this.onPreview,
  });

  final StoreItem item;
  final bool inCart, buyOff;
  final VoidCallback? onBuy, onToggleCart, onPreview;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 720;
      final cover = StoreCover(id: item.id, title: item.title, url: item.coverUrl);
      final details = _details(context);
      if (wide) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: box.maxWidth * 0.36, child: AspectRatio(aspectRatio: 3 / 4, child: cover)),
            const SizedBox(width: AppSpace.lg),
            Expanded(child: details),
          ]),
        );
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: box.maxWidth * 0.75),
              child: AspectRatio(aspectRatio: 3 / 4, child: cover),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          details,
        ]),
      );
    });
  }

  Widget _details(BuildContext context) {
    final c = context.colors;
    final meta = [
      storeKindLabel(item.kind),
      if (item.pages != null && item.pages! > 0) storePagesText(item.pages!),
      if (item.fileSize > 0) storeSizeText(item.fileSize),
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Icon(storeKindIcon(item.kind), size: AppIconSize.sm, color: c.textMedium),
          const SizedBox(width: AppSpace.xxs),
          Expanded(child: Text(meta, style: AppType.meta(context))),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Semantics(header: true, child: Text(item.title, style: AppType.headline(context))),
        const SizedBox(height: AppSpace.md),
        AppCard(child: StorePriceBlock(price: item.price, pointsPrice: item.pointsPrice)),
        const SizedBox(height: AppSpace.md),
        if (item.owned)
          AppBanner(
            icon: Icons.check_circle_rounded,
            text: t('هذا العنصر في مكتبتك. افتحه من «مكتبتي».', 'This item is in your library. Open it from My Library.'),
            color: c.success,
          )
        else if (buyOff)
          AppBanner(icon: Icons.block_rounded, text: t('الشراء متوقف حالياً', 'Buying is switched off right now'), color: c.warning)
        else
          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
            AppButton.primary(
              key: const ValueKey('store.item.buy'),
              label: item.price.isFree ? t('احصل عليه مجاناً', 'Get it free') : t('اشترِ الآن', 'Buy now'),
              icon: Icons.shopping_bag_rounded,
              onPressed: onBuy,
            ),
            AppButton.secondary(
              key: const ValueKey('store.item.cart'),
              label: inCart ? t('إزالة من السلة', 'Remove from cart') : t('أضف إلى السلة', 'Add to cart'),
              icon: inCart ? Icons.remove_shopping_cart_rounded : Icons.add_shopping_cart_rounded,
              onPressed: onToggleCart,
            ),
          ]),
        if (item.description.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpace.lg),
          AppSectionTitle(t('عن هذا العنصر', 'About this item')),
          Text(item.description, style: AppType.body(context)),
        ],
        if (item.previewUrl != null) ...[
          const SizedBox(height: AppSpace.lg),
          AppSectionTitle(t('معاينة', 'Preview')),
          if (item.previewIsImage)
            ClipRRect(
              borderRadius: AppRadius.cardAll,
              child: AppNetworkImage(url: item.previewUrl!, fit: BoxFit.contain, enableFullscreen: true),
            )
          else
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton.ghost(
                key: const ValueKey('store.item.preview'),
                label: t('افتح المعاينة', 'Open the preview'),
                icon: Icons.visibility_rounded,
                onPressed: onPreview,
              ),
            ),
        ],
      ],
    );
  }
}
