// lib/features/store/store_models.dart — the digital store's wire shapes (Learning Hub Phase 5, D-1333, CONTRACT §5,
// ../back/FLUTTER_API_CHANGES.md "Learning Hub phase 5"). Plain values, parsed by hand, tested against the API
// doc's examples in test/store/store_models_test.dart.
//
//   StorePrice        an item's {net, vat, gross, currency, vat_percent, includes_vat}
//   StoreItem         a browse card; the item page adds descriptions, the file, the preview link
//   StoreQuote        POST /store/quote: the lines and the sums the order will charge
//   StoreOrder        an order (history, the answer of POST /store/orders) + StoreCheckout (card only)
//   StoreLibraryItem  one owned item of GET /store/library
//   StoreDownload     POST /store/library/{id}/download: the short single-use link
library;

import 'package:flutter_education_app/config/app_config.dart';

double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

int? _intOrNull(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

String _str(Object? v) => v is String ? v : (v == null ? '' : '$v');

/// A cover URL the app can load: a server-relative path (`/api/v1/…`, older covers) is put on the API's base, as
/// [orgFileUrl] does; an absolute one is kept (D-1339).
String storeCoverUrl(Object? v) {
  final u = _str(v).trim();
  if (!u.startsWith('/')) return u;
  final base = AppConfig.baseUrl.endsWith('/') ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1) : AppConfig.baseUrl;
  return '$base$u';
}

DateTime? _date(Object? v) {
  final s = _str(v);
  if (s.isEmpty) return null;
  final d = DateTime.tryParse(s);
  if (d == null) return null;
  // the server stores naive UTC
  return d.isUtc ? d : DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second, d.millisecond);
}

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};

List<Map<String, dynamic>> _maps(Object? v) => v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : const [];

/// "12.50 SAR": money always shows two decimals here (the VAT lines must add up on screen).
String storeMoney(double amount, String currency) {
  final s = amount.toStringAsFixed(2);
  return currency.isEmpty ? s : '$s $currency';
}

/// Title / description in the app's language, the other one when it is empty.
String storeText(String ar, String en) {
  final arFirst = AppConfig.lang == 'ar';
  final a = arFirst ? ar : en, b = arFirst ? en : ar;
  return a.trim().isNotEmpty ? a : b;
}

/// The item kinds (`ebook | summary | notes | other`).
const storeKinds = ['ebook', 'summary', 'notes', 'other'];

class StorePrice {
  const StorePrice({
    required this.net,
    required this.vat,
    required this.gross,
    required this.currency,
    this.vatPercent = 0,
    this.includesVat = false,
  });

  factory StorePrice.fromJson(Object? j) {
    final m = _map(j);
    return StorePrice(
      net: _num(m['net']),
      vat: _num(m['vat']),
      gross: _num(m['gross']),
      currency: _str(m['currency']),
      vatPercent: _num(m['vat_percent']),
      includesVat: m['includes_vat'] == true,
    );
  }

  final double net, vat, gross;
  final String currency;
  final double vatPercent;
  final bool includesVat;

  bool get isFree => gross <= 0;

  /// "15 %" without a trailing ".0".
  String get vatPercentText =>
      '${vatPercent == vatPercent.roundToDouble() ? vatPercent.toStringAsFixed(0) : vatPercent.toStringAsFixed(2)} %';
}

class StoreItem {
  const StoreItem({
    required this.id,
    required this.kind,
    required this.titleAr,
    required this.titleEn,
    required this.price,
    this.coverUrl = '',
    this.pointsPrice,
    this.stageId,
    this.gradeId,
    this.subjectId,
    this.categoryId,
    this.pages,
    this.countryCode,
    this.owned = false,
    this.descriptionAr = '',
    this.descriptionEn = '',
    this.fileName = '',
    this.fileSize = 0,
    this.previewUrl,
  });

  factory StoreItem.fromJson(Map<String, dynamic> j) => StoreItem(
        id: _intOrNull(j['id']) ?? 0,
        kind: _str(j['kind']),
        titleAr: _str(j['title_ar']),
        titleEn: _str(j['title_en']),
        coverUrl: storeCoverUrl(j['cover_url']),
        price: StorePrice.fromJson(j['price']),
        pointsPrice: _intOrNull(j['points_price']),
        stageId: _intOrNull(j['stage_id']),
        gradeId: _intOrNull(j['grade_id']),
        subjectId: _intOrNull(j['subject_id']),
        categoryId: _intOrNull(j['category_id']),
        pages: _intOrNull(j['pages']),
        countryCode: _str(j['country_code']).isEmpty ? null : _str(j['country_code']),
        owned: j['owned'] == true,
        descriptionAr: _str(j['description_ar']),
        descriptionEn: _str(j['description_en']),
        fileName: _str(j['file_name']),
        fileSize: _intOrNull(j['file_size']) ?? 0,
        previewUrl: _str(j['preview_url']).isEmpty ? null : _str(j['preview_url']),
      );

  final int id;
  final String kind, titleAr, titleEn, coverUrl;
  final StorePrice price;
  final int? pointsPrice, stageId, gradeId, subjectId, categoryId, pages;
  final String? countryCode;
  final bool owned;

  // the item page only
  final String descriptionAr, descriptionEn, fileName;
  final int fileSize;

  /// A signed link (120 s) to the preview, or null.
  final String? previewUrl;

  String get title => storeText(titleAr, titleEn);
  String get description => storeText(descriptionAr, descriptionEn);

  /// The preview is a picture (shown on the page) rather than a PDF (opened).
  bool get previewIsImage {
    final p = Uri.tryParse(previewUrl ?? '')?.path.toLowerCase() ?? '';
    return p.endsWith('.png') || p.endsWith('.jpg') || p.endsWith('.jpeg') || p.endsWith('.webp');
  }
}

class StoreItemList {
  const StoreItemList({required this.items, required this.total, required this.hasMore});

  factory StoreItemList.fromJson(Object? j) {
    final m = _map(j);
    return StoreItemList(
      items: [for (final e in _maps(m['items'])) StoreItem.fromJson(e)],
      total: _intOrNull(m['total']) ?? 0,
      hasMore: m['has_more'] == true,
    );
  }

  final List<StoreItem> items;
  final int total;
  final bool hasMore;
}

class StoreQuoteLine {
  const StoreQuoteLine({required this.itemId, required this.title, required this.net, required this.vat, required this.gross, this.vatExempt = false});

  factory StoreQuoteLine.fromJson(Map<String, dynamic> j) => StoreQuoteLine(
        itemId: _intOrNull(j['item_id']) ?? 0,
        title: _str(j['title']),
        vatExempt: j['vat_exempt'] == true,
        net: _num(j['net']),
        vat: _num(j['vat']),
        gross: _num(j['gross']),
      );

  final int itemId;
  final String title;
  final bool vatExempt;
  final double net, vat, gross;
}

class StoreQuote {
  const StoreQuote({
    required this.lines,
    required this.subtotal,
    required this.vatAmount,
    required this.total,
    required this.currency,
    this.vatPercent = 0,
    this.includesVat = false,
    this.pointsTotal,
    this.couponDiscount = 0,
    this.couponCode,
  });

  factory StoreQuote.fromJson(Object? j) {
    final m = _map(j);
    return StoreQuote(
      lines: [for (final e in _maps(m['lines'])) StoreQuoteLine.fromJson(e)],
      subtotal: _num(m['subtotal']),
      vatAmount: _num(m['vat_amount']),
      total: _num(m['total']),
      currency: _str(m['currency']),
      vatPercent: _num(m['vat_percent']),
      includesVat: m['includes_vat'] == true,
      pointsTotal: _intOrNull(m['points_total']),
      couponDiscount: _num(m['coupon_discount']),
      couponCode: _str(m['coupon_code']).isEmpty ? null : _str(m['coupon_code']),
    );
  }

  /// Games v3 (CONTRACT §7): what the coupon took off the net subtotal (0 without one), and its code.
  final double couponDiscount;
  final String? couponCode;

  final List<StoreQuoteLine> lines;
  final double subtotal, vatAmount, total;
  final String currency;
  final double vatPercent;
  final bool includesVat;

  /// Null unless points are on and every item has a points price.
  final int? pointsTotal;

  bool get isFree => total <= 0;
}

/// `pending | paid | failed | cancelled | refunded`.
enum StoreOrderStatus {
  pending,
  paid,
  failed,
  cancelled,
  refunded;

  static StoreOrderStatus parse(Object? v) =>
      values.firstWhere((s) => s.name == v, orElse: () => StoreOrderStatus.pending);
}

class StoreOrderLine {
  const StoreOrderLine({required this.itemId, required this.title, required this.unitNet, required this.unitVat, required this.unitGross});

  factory StoreOrderLine.fromJson(Map<String, dynamic> j) => StoreOrderLine(
        itemId: _intOrNull(j['item_id']) ?? 0,
        title: _str(j['title']),
        unitNet: _num(j['unit_net']),
        unitVat: _num(j['unit_vat']),
        unitGross: _num(j['unit_gross']),
      );

  final int itemId;
  final String title;
  final double unitNet, unitVat, unitGross;
}

class StoreOrder {
  const StoreOrder({
    required this.id,
    required this.status,
    required this.method,
    required this.currency,
    required this.subtotal,
    required this.vatAmount,
    required this.total,
    this.provider,
    this.countryCode,
    this.vatPercent = 0,
    this.pointsSpent,
    this.failureCode,
    this.createdAt,
    this.paidAt,
    this.items = const [],
  });

  factory StoreOrder.fromJson(Object? j) {
    final m = _map(j);
    return StoreOrder(
      id: _intOrNull(m['id']) ?? 0,
      status: StoreOrderStatus.parse(m['status']),
      method: _str(m['method']),
      provider: _str(m['provider']).isEmpty ? null : _str(m['provider']),
      currency: _str(m['currency']),
      countryCode: _str(m['country_code']).isEmpty ? null : _str(m['country_code']),
      subtotal: _num(m['subtotal']),
      vatPercent: _num(m['vat_percent']),
      vatAmount: _num(m['vat_amount']),
      total: _num(m['total']),
      pointsSpent: _intOrNull(m['points_spent']),
      failureCode: _str(m['failure_code']).isEmpty ? null : _str(m['failure_code']),
      createdAt: _date(m['created_at']),
      paidAt: _date(m['paid_at']),
      items: [for (final e in _maps(m['items'])) StoreOrderLine.fromJson(e)],
    );
  }

  final int id;
  final StoreOrderStatus status;

  /// `card | points | free`.
  final String method;
  final String? provider, countryCode;
  final String currency;
  final double subtotal, vatPercent, vatAmount, total;
  final int? pointsSpent;
  /// Why a failed order failed: `declined | amount_mismatch | currency_mismatch | transaction_reused` (D-1339; the
  /// provider's own text stays with the super admin).
  final String? failureCode;
  final DateTime? createdAt, paidAt;
  final List<StoreOrderLine> items;

  bool get paid => status == StoreOrderStatus.paid;

  /// Settled one way or the other: nothing more to wait for.
  bool get done => status != StoreOrderStatus.pending;
}

class StoreCheckout {
  const StoreCheckout({required this.url, required this.token, this.provider, this.amountMinor = 0, this.isSandbox = false});

  static StoreCheckout? fromJson(Object? j) {
    if (j is! Map) return null;
    final m = Map<String, dynamic>.from(j);
    return StoreCheckout(
      url: _str(m['url']),
      token: _str(m['token']),
      provider: _str(m['provider']).isEmpty ? null : _str(m['provider']),
      amountMinor: _intOrNull(m['amount_minor']) ?? 0,
      isSandbox: m['is_sandbox'] == true,
    );
  }

  final String url, token;
  final String? provider;
  final int amountMinor;
  final bool isSandbox;

  bool get canOpen => url.isNotEmpty;
}

/// `{order, checkout}`: the answer of POST /store/orders and GET /store/orders/{id}.
class StoreOrderAnswer {
  const StoreOrderAnswer({required this.order, this.checkout});

  factory StoreOrderAnswer.fromJson(Object? j) {
    final m = _map(j);
    return StoreOrderAnswer(order: StoreOrder.fromJson(m['order']), checkout: StoreCheckout.fromJson(m['checkout']));
  }

  final StoreOrder order;
  final StoreCheckout? checkout;
}

class StoreOrderPage {
  const StoreOrderPage({required this.items, required this.total, required this.hasMore});

  factory StoreOrderPage.fromJson(Object? j) {
    final m = _map(j);
    return StoreOrderPage(
      items: [for (final e in _maps(m['items'])) StoreOrder.fromJson(e)],
      total: _intOrNull(m['total']) ?? 0,
      hasMore: m['has_more'] == true,
    );
  }

  final List<StoreOrder> items;
  final int total;
  final bool hasMore;
}

class StoreLibraryItem {
  const StoreLibraryItem({
    required this.itemId,
    required this.kind,
    required this.titleAr,
    required this.titleEn,
    this.coverUrl = '',
    this.pages,
    this.fileName = '',
    this.fileSize = 0,
    this.sha256 = '',
    this.orderId,
    this.grantedAt,
    this.lastDownloadAt,
  });

  factory StoreLibraryItem.fromJson(Map<String, dynamic> j) => StoreLibraryItem(
        itemId: _intOrNull(j['item_id']) ?? 0,
        kind: _str(j['kind']),
        titleAr: _str(j['title_ar']),
        titleEn: _str(j['title_en']),
        coverUrl: storeCoverUrl(j['cover_url']),
        pages: _intOrNull(j['pages']),
        fileName: _str(j['file_name']),
        fileSize: _intOrNull(j['file_size']) ?? 0,
        sha256: _str(j['sha256']),
        orderId: _intOrNull(j['order_id']),
        grantedAt: _date(j['granted_at']),
        lastDownloadAt: _date(j['last_download_at']),
      );

  final int itemId;
  final String kind, titleAr, titleEn, coverUrl, fileName, sha256;
  final int? pages, orderId;
  final int fileSize;
  final DateTime? grantedAt, lastDownloadAt;

  String get title => storeText(titleAr, titleEn);

  /// The in-app reader opens PDFs; an EPUB is kept and opened by its link on the web only.
  bool get isPdf => fileName.toLowerCase().endsWith('.pdf') || (fileName.isEmpty && kind != 'other');
}

class StoreDownload {
  const StoreDownload({required this.url, this.expiresIn = 120, this.fileName = '', this.fileSize = 0, this.sha256 = ''});

  factory StoreDownload.fromJson(Object? j) {
    final m = _map(j);
    return StoreDownload(
      url: _str(m['url']),
      expiresIn: _intOrNull(m['expires_in']) ?? 120,
      fileName: _str(m['file_name']),
      fileSize: _intOrNull(m['file_size']) ?? 0,
      sha256: _str(m['sha256']),
    );
  }

  final String url;
  final int expiresIn;
  final String fileName, sha256;
  final int fileSize;

  /// The link as a full URL: a server path (`/api/v1/store/dl/…`) is put under [AppConfig.baseUrl] the way every
  /// ApiClient call is.
  Uri absolute([String? base]) {
    final u = Uri.parse(url);
    if (u.hasScheme) return u;
    final b = (base ?? AppConfig.baseUrl).replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$b${url.startsWith('/') ? '' : '/'}$url');
  }
}

/// The browse query: the course bar's level + subject (CourseFilters), plus the store's own category, kind and search.
class StoreQuery {
  const StoreQuery({this.country, this.stageId, this.gradeId, this.subjectId, this.categoryId, this.kind, this.search = ''});

  final String? country, kind;
  final int? stageId, gradeId, subjectId, categoryId;
  final String search;

  Map<String, dynamic> toQuery({int skip = 0, int limit = 24}) => {
        if (country != null && country!.isNotEmpty) 'country': country,
        'stage_id': ?stageId,
        'grade_id': ?gradeId,
        'subject_id': ?subjectId,
        'category_id': ?categoryId,
        if (kind != null && kind!.isNotEmpty) 'kind': kind,
        if (search.trim().isNotEmpty) 'search': search.trim(),
        'skip': skip,
        'limit': limit,
      };
}
