// lib/features/store/store_library.dart — My Library (D-1333): what the person bought, and their purchase history.
//
//   StoreLibraryPage  GET /api/v1/store/library + GET /api/v1/store/orders. Each download is
//                     POST /api/v1/store/library/{id}/download (with X-Device-Id) → a short single-use link:
//                       • phone / desktop: the file is fetched through it and kept AES-CTR encrypted (StoreVault,
//                         the offline-video scheme), then read in StoreReaderPage under ScreenSecurity; a kept copy
//                         opens with no request. A file the reader cannot draw (EPUB) opens by its link.
//                       • web: the link opens in the browser (nothing is kept).
//                     Reloads when an order is paid (StoreLibraryBus). Offline (D-1351): the list comes from the
//                     device (ReadCache) and a kept copy opens as usual; a download says it needs a connection.
//   StoreLibraryView  the page's body with plain values (test/ui/store_layout_test.dart)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/offline/sync/offline_reads.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/store/store_api.dart';
import 'package:flutter_education_app/features/store/store_checkout.dart';
import 'package:flutter_education_app/features/store/store_models.dart';
import 'package:flutter_education_app/features/store/store_reader.dart';
import 'package:flutter_education_app/features/store/store_vault.dart';
import 'package:flutter_education_app/features/store/store_widgets.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:url_launcher/url_launcher.dart';

class StoreLibraryPage extends StatefulWidget {
  const StoreLibraryPage({super.key, this.api});

  final StoreApi? api;

  @override
  State<StoreLibraryPage> createState() => _StoreLibraryPageState();
}

class _StoreLibraryPageState extends State<StoreLibraryPage> {
  late final StoreApi _api = widget.api ?? StoreApi();
  final StoreVault _vault = StoreVault.instance;

  int _tab = 0;
  List<StoreLibraryItem> _items = const [];
  List<StoreOrder> _orders = const [];
  Set<int> _kept = const {};
  final Map<int, double> _progress = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    StoreLibraryBus.revision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    StoreLibraryBus.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Future.wait([
        _api.library(),
        // the purchase history is never kept: offline it is empty and the library still opens
        _api.orders(limit: 50).catchError((Object e) => isTransportFailure(e) ? const StoreOrderPage(items: [], total: 0, hasMore: false) : throw e),
      ]);
      final items = r[0] as List<StoreLibraryItem>;
      final kept = <int>{};
      if (_vault.available) {
        // a revoked library row: its kept copy and key go too (D-1339)
        await _vault.prune({for (final i in items) i.itemId});
        for (final i in items) {
          if (await _vault.has(i.itemId)) kept.add(i.itemId);
        }
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _orders = (r[1] as StoreOrderPage).items;
        _kept = kept;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = storeErrorText(e);
        _loading = false;
      });
    }
  }

  /// A kept PDF opens at once; everything else asks for a fresh short link first.
  Future<void> _open(StoreLibraryItem it) async {
    if (_vault.available && it.isPdf && _kept.contains(it.itemId)) return _read(it);
    await _download(it);
  }

  Future<void> _download(StoreLibraryItem it) async {
    if (_progress.containsKey(it.itemId) || offlineBlocked()) return;
    setState(() => _progress[it.itemId] = 0);
    try {
      final d = await _api.download(it.itemId);
      final url = d.absolute();
      if (!_vault.available || !it.isPdf) {
        final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
        if (!ok) showAppNotice(t('تعذّر فتح الرابط', 'The link could not be opened'), error: true);
        return;
      }
      await _vault.save(it.itemId, url, sha256: d.sha256.isNotEmpty ? d.sha256 : it.sha256, onProgress: (p) {
        if (mounted) setState(() => _progress[it.itemId] = p);
      });
      if (!mounted) return;
      setState(() => _kept = {..._kept, it.itemId});
      await _read(it);
    } catch (e) {
      showAppNotice(
          '$e' == 'store_file_corrupt' ? storeCodeText('store_file_corrupt')! : storeErrorText(e),
          error: true);
    } finally {
      if (mounted) setState(() => _progress.remove(it.itemId));
    }
  }

  Future<void> _read(StoreLibraryItem it) async {
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      settings: RouteSettings(name: '/store/library/${it.itemId}'),
      builder: (_) => StoreReaderPage(itemId: it.itemId, title: it.title, load: () => _vault.read(it.itemId)),
    ));
  }

  Future<void> _removeCopy(StoreLibraryItem it) async {
    final ok = await appConfirm(context,
        message: t('حذف النسخة المحفوظة على هذا الجهاز؟ يبقى العنصر في مكتبتك ويمكنك تنزيله مرة أخرى.',
            'Remove the copy kept on this device? The item stays in your library and you can download it again.'));
    if (!ok) return;
    await _vault.remove(it.itemId);
    if (mounted) setState(() => _kept = {..._kept}..remove(it.itemId));
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      width: AppWidth.content,
      appBar: ScreenAppBar(title: t('مكتبتي', 'My Library'), helpPageId: 'store.library'),
      child: SafeArea(
        child: StoreLibraryView(
          tab: _tab,
          onTab: (i) => setState(() => _tab = i),
          items: _items,
          orders: _orders,
          kept: _kept,
          progress: _progress,
          keepsFiles: _vault.available,
          loading: _loading,
          error: _error,
          onRetry: _load,
          onRefresh: _load,
          onOpen: _open,
          onDownloadAgain: _download,
          onRemoveCopy: _removeCopy,
        ),
      ),
    );
  }
}

String storeOrderStatusText(StoreOrderStatus s) => switch (s) {
      StoreOrderStatus.paid => t('مدفوع', 'Paid'),
      StoreOrderStatus.pending => t('بانتظار الدفع', 'Pending'),
      StoreOrderStatus.failed => t('فشل', 'Failed'),
      StoreOrderStatus.cancelled => t('أُلغي', 'Cancelled'),
      StoreOrderStatus.refunded => t('مُسترد', 'Refunded'),
    };

AppTone storeOrderTone(StoreOrderStatus s) => switch (s) {
      StoreOrderStatus.paid => AppTone.success,
      StoreOrderStatus.pending => AppTone.warning,
      StoreOrderStatus.refunded => AppTone.info,
      _ => AppTone.danger,
    };

String storeMethodText(String m) => switch (m) {
      'points' => t('بالنقاط', 'Points'),
      'free' => t('مجاني', 'Free'),
      _ => t('بطاقة', 'Card'),
    };

/// My Library's body with plain values: tab 0 = the files, tab 1 = the purchase history.
class StoreLibraryView extends StatelessWidget {
  const StoreLibraryView({
    super.key,
    required this.tab,
    required this.items,
    required this.orders,
    this.onTab,
    this.kept = const {},
    this.progress = const {},
    this.keepsFiles = true,
    this.loading = false,
    this.error,
    this.onRetry,
    this.onRefresh,
    this.onOpen,
    this.onDownloadAgain,
    this.onRemoveCopy,
  });

  final int tab;
  final ValueChanged<int>? onTab;
  final List<StoreLibraryItem> items;
  final List<StoreOrder> orders;

  /// Items with a copy kept on this device.
  final Set<int> kept;

  /// Downloads in progress (0..1).
  final Map<int, double> progress;

  /// False on the web: "Open" opens the link.
  final bool keepsFiles;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final Future<void> Function()? onRefresh;
  final ValueChanged<StoreLibraryItem>? onOpen, onDownloadAgain, onRemoveCopy;

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (loading && items.isEmpty && orders.isEmpty) {
      body = const AppListSkeleton(items: 4, padding: EdgeInsets.zero);
    } else if (error != null) {
      body = AppErrorState(message: error, onRetry: onRetry);
    } else if (tab == 0) {
      body = items.isEmpty
          ? AppEmpty(
              key: const ValueKey('store.library.empty'),
              icon: Icons.local_library_rounded,
              title: t('مكتبتك فارغة', 'Your library is empty'),
              message: t('ما تشتريه من المتجر يظهر هنا.', 'What you buy in the store shows up here.'),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final it in items) _ItemRow(item: it, view: this),
            ]);
    } else {
      body = orders.isEmpty
          ? AppEmpty(
              key: const ValueKey('store.history.empty'),
              icon: Icons.receipt_long_rounded,
              title: t('لا توجد مشتريات بعد', 'No purchases yet'),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final o in orders) _OrderRow(order: o),
            ]);
    }
    final list = ListView(
      padding: const EdgeInsets.all(AppSpace.md),
      children: [
        AppTabs(
          items: [
            AppTabItem(t('ملفاتي', 'My files'), icon: Icons.menu_book_rounded, count: items.isEmpty ? null : items.length),
            AppTabItem(t('المشتريات', 'Purchases'), icon: Icons.receipt_long_rounded),
          ],
          index: tab,
          onChanged: (i) => onTab?.call(i),
        ),
        const SizedBox(height: AppSpace.md),
        body,
      ],
    );
    return onRefresh == null ? list : AppRefresh(onRefresh: onRefresh!, child: list);
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.view});

  final StoreLibraryItem item;
  final StoreLibraryView view;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = view.progress[item.itemId];
    final kept = view.kept.contains(item.itemId);
    final meta = [
      storeKindLabel(item.kind),
      if (item.pages != null && item.pages! > 0) storePagesText(item.pages!),
      if (item.fileSize > 0) storeSizeText(item.fileSize),
      if (view.keepsFiles && kept) t('محفوظ على الجهاز', 'On this device'),
    ].join(' · ');
    final last = item.lastDownloadAt;
    final readable = view.keepsFiles && item.isPdf;
    final label = readable && kept
        ? t('اقرأ', 'Read')
        : readable
            ? t('نزّل واقرأ', 'Download & read')
            : t('افتح', 'Open');
    return AppCard(
      key: ValueKey('store.library.${item.itemId}'),
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: AppTouch.primary + AppSpace.sm,
            height: (AppTouch.primary + AppSpace.sm) * 4 / 3,
            child: StoreCover(id: item.itemId, title: item.title, url: item.coverUrl),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              const SizedBox(height: AppSpace.xxs),
              Text(meta, style: AppType.meta(context)),
              if (last != null) ...[
                const SizedBox(height: AppSpace.xxs),
                Text('${t('آخر تنزيل', 'Last downloaded')}: ${AppTime.dateTime(last)}', style: AppType.meta(context)),
              ],
            ]),
          ),
        ]),
        if (p != null) ...[
          const SizedBox(height: AppSpace.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
                value: p > 0 ? p : null, minHeight: AppSpace.xxs, color: c.primary, backgroundColor: c.primaryTint),
          ),
        ],
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppButton.primary(
            key: ValueKey('store.library.open.${item.itemId}'),
            label: label,
            icon: readable ? Icons.auto_stories_rounded : Icons.open_in_new_rounded,
            size: AppButtonSize.sm,
            busy: p != null,
            onPressed: p != null ? null : () => view.onOpen?.call(item),
          ),
          if (readable && kept) ...[
            AppButton.ghost(
              label: t('نزّل من جديد', 'Download again'),
              icon: Icons.download_rounded,
              size: AppButtonSize.sm,
              onPressed: p != null ? null : () => view.onDownloadAgain?.call(item),
            ),
            AppButton.ghost(
              label: t('احذف من الجهاز', 'Remove from device'),
              icon: Icons.delete_outline_rounded,
              size: AppButtonSize.sm,
              onPressed: p != null ? null : () => view.onRemoveCopy?.call(item),
            ),
          ],
        ]),
      ]),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});

  final StoreOrder order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final when = o.paidAt ?? o.createdAt;
    final amount = o.method == 'points' && o.pointsSpent != null
        ? t('${o.pointsSpent} نقطة', '${o.pointsSpent} points')
        : storeMoney(o.total, o.currency);
    return AppCard(
      key: ValueKey('store.order.${o.id}'),
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Wrap(
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('${t('طلب', 'Order')} #${o.id}', style: AppType.bodyStrong(context)),
            AppStatusBadge(label: storeOrderStatusText(o.status), tone: storeOrderTone(o.status), dense: true),
          ],
        ),
        const SizedBox(height: AppSpace.xxs),
        for (final l in o.items)
          Text('• ${l.title}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.body(context)),
        const SizedBox(height: AppSpace.xxs),
        Text(
          [
            amount,
            storeMethodText(o.method),
            if (o.method != 'points' && o.vatAmount > 0) '${t('منها ضريبة', 'incl. VAT')} ${storeMoney(o.vatAmount, o.currency)}',
            if (when != null) AppTime.dateTime(when),
          ].join(' · '),
          style: AppType.meta(context),
        ),
        if (o.failureCode != null && o.status != StoreOrderStatus.paid) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(storeFailureText(o.failureCode), style: AppType.meta(context)),
        ],
      ]),
    );
  }
}
