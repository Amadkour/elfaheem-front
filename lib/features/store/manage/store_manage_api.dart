// lib/features/store/manage/store_manage_api.dart
//
// The digital store's management API (learning hub phase 5, CONTRACT §5, D-1336): the teacher's / super admin's own
// items (`/api/v1/store/manage/items…`), the private file upload (presign → PUT → confirm), publishing, and the super
// admin's review queue and orders (`/api/v1/admin/store/…`). Plain models with tolerant readers; every call goes
// through orgCall (never throws; it toasts the error unless quiet) and the store codes get their own texts.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';

import '../../admin/admin_common.dart' show asMap, asMapList, asInt, asDouble, asBool, asStr, asStrOrNull, t, toast;
import '../../org/org_v3.dart' show OrgCall, orgCall, orgErrorText;

const kStoreManagePath = '/api/v1/store/manage/items';
const kStoreAdminPath = '/api/v1/admin/store';

/// Kill switches (CONTRACT §5).
const kStoreManageFeatureKey = 'store.manage';
const kAdminStoreFeatureKey = 'admin.store';

/// The item kinds the server accepts.
const kStoreKinds = ['ebook', 'summary', 'notes', 'other'];

/// The statuses an item can be in. A rejected item goes back to `draft` on the server.
const kStoreStatuses = ['draft', 'pending', 'published', 'hidden'];

/// The largest file the server takes (200 MB).
const kStoreMaxFileBytes = 200 * 1024 * 1024;

String storeKindLabel(String kind) => switch (kind) {
      'ebook' => t('كتاب إلكتروني', 'E-book'),
      'summary' => t('ملخص', 'Summary'),
      'notes' => t('مذكرة', 'Notes'),
      _ => t('أخرى', 'Other'),
    };

String storeStatusLabel(String status) => switch (status) {
      'draft' => t('مسودة', 'Draft'),
      'pending' => t('بانتظار المراجعة', 'Pending review'),
      'published' => t('منشور', 'Published'),
      'hidden' => t('مخفي', 'Hidden'),
      _ => status,
    };

String storeOrderStatusLabel(String status) => switch (status) {
      'pending' => t('بانتظار الدفع', 'Pending'),
      'paid' => t('مدفوع', 'Paid'),
      'failed' => t('فشل', 'Failed'),
      'cancelled' => t('ملغى', 'Cancelled'),
      'refunded' => t('مسترد', 'Refunded'),
      _ => status,
    };

String storeMethodLabel(String method) => switch (method) {
      'card' => t('بطاقة', 'Card'),
      'points' => t('نقاط', 'Points'),
      'free' => t('مجاني', 'Free'),
      _ => method,
    };

/// "12.4 MB".
String storeSizeLabel(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// The bilingual text of a store error code; null → the generic org text.
String? storeErrorText(String? code) => switch (code) {
      'store_manage_forbidden' => t('إدارة المتجر غير متاحة لحسابك', 'Store management is not available for your account'),
      'store_bad_kind' => t('نوع العنصر غير صحيح', 'The item type is not valid'),
      'store_bad_country' => t('الدولة غير معروفة', 'Unknown country'),
      'store_bad_currency' => t('العملة غير صحيحة', 'The currency is not valid'),
      'store_bad_price' => t('السعر غير صحيح', 'The price is not valid'),
      'store_bad_status' => t('لا يمكن تغيير الحالة هكذا', 'The status cannot be changed this way'),
      'store_title_required' => t('اكتب عنواناً للعنصر', 'Give the item a title'),
      'store_bad_file_type' => t('نوع الملف غير مسموح (PDF أو EPUB، والمعاينة PDF أو صورة)', 'File type not allowed (PDF or EPUB; the preview PDF or an image)'),
      'store_file_too_large' => t('الملف أكبر من 200 ميجابايت', 'The file is larger than 200 MB'),
      'store_bad_upload_id' || 'store_upload_missing' => t('لم يكتمل رفع الملف، حاول مرة أخرى', 'The upload did not finish, try again'),
      'store_file_missing' => t('ارفع ملف العنصر قبل النشر', 'Upload the item file before publishing'),
      'store_item_not_found' => t('العنصر غير موجود', 'The item was not found'),
      'store_not_pending' => t('العنصر لم يعد بانتظار المراجعة', 'The item is no longer pending review'),
      'admin_required' => t('للمشرف العام فقط', 'Super admins only'),
      'feature_disabled' => t('هذه الخدمة متوقفة حالياً', 'This service is switched off right now'),
      _ => null,
    };

/// One price as the server shows it (net / vat / gross).
class StorePrice {
  const StorePrice({this.net = 0, this.vat = 0, this.gross = 0, this.currency = '', this.vatPercent = 0, this.includesVat = false});

  final double net, vat, gross;
  final String currency;
  final double vatPercent;
  final bool includesVat;

  static StorePrice from(dynamic v) {
    final m = asMap(v);
    return StorePrice(
      net: asDouble(m['net']),
      vat: asDouble(m['vat']),
      gross: asDouble(m['gross']),
      currency: asStr(m['currency']),
      vatPercent: asDouble(m['vat_percent']),
      includesVat: asBool(m['includes_vat']),
    );
  }
}

/// A manage item (CONTRACT §5 "manage item": the card + description, status, file facts).
class StoreManageItem {
  const StoreManageItem({
    required this.id,
    this.kind = 'ebook',
    this.titleAr = '',
    this.titleEn = '',
    this.descriptionAr = '',
    this.descriptionEn = '',
    this.coverUrl,
    this.status = 'draft',
    this.basePrice = 0,
    this.price = const StorePrice(),
    this.pointsPrice,
    this.currency = '',
    this.countryCode,
    this.vatExempt = false,
    this.stageId,
    this.gradeId,
    this.subjectId,
    this.categoryId,
    this.pages,
    this.fileName,
    this.fileSize = 0,
    this.hasFile = false,
    this.hasPreview = false,
    this.salesCount = 0,
    this.ownerId,
    this.updatedAt,
  });

  final int id;
  final String kind, titleAr, titleEn, descriptionAr, descriptionEn;
  final String? coverUrl;
  final String status;
  final double basePrice;
  final StorePrice price;
  final int? pointsPrice;
  final String currency;
  final String? countryCode;
  final bool vatExempt;
  final int? stageId, gradeId, subjectId, categoryId, pages;
  final String? fileName;
  final int fileSize;
  final bool hasFile, hasPreview;
  final int salesCount;
  final int? ownerId;
  final String? updatedAt;

  String get title {
    final ar = AppConfig.lang == 'ar';
    final first = ar ? titleAr : titleEn, second = ar ? titleEn : titleAr;
    return first.isNotEmpty ? first : (second.isNotEmpty ? second : t('بدون عنوان', 'Untitled'));
  }

  bool get canPublish => hasFile && (status == 'draft' || status == 'hidden');

  static int? _id(dynamic v) => v == null ? null : asInt(v);

  static StoreManageItem from(Map<String, dynamic> m) => StoreManageItem(
        id: asInt(m['id']),
        kind: asStr(m['kind'], 'ebook'),
        titleAr: asStr(m['title_ar']),
        titleEn: asStr(m['title_en']),
        descriptionAr: asStr(m['description_ar']),
        descriptionEn: asStr(m['description_en']),
        coverUrl: asStrOrNull(m['cover_url']),
        status: asStr(m['status'], 'draft'),
        basePrice: asDouble(m['base_price']),
        price: StorePrice.from(m['price']),
        pointsPrice: _id(m['points_price']),
        currency: asStr(m['currency']),
        countryCode: asStrOrNull(m['country_code']),
        vatExempt: asBool(m['vat_exempt']),
        stageId: _id(m['stage_id']),
        gradeId: _id(m['grade_id']),
        subjectId: _id(m['subject_id']),
        categoryId: _id(m['category_id']),
        pages: _id(m['pages']),
        fileName: asStrOrNull(m['file_name']),
        fileSize: asInt(m['file_size']),
        hasFile: asBool(m['has_file']),
        hasPreview: asBool(m['has_preview']),
        salesCount: asInt(m['sales_count']),
        ownerId: _id(m['owner_id']),
        updatedAt: asStrOrNull(m['updated_at']),
      );
}

/// One order in the super admin's list.
class StoreOrderRow {
  const StoreOrderRow({
    required this.id,
    this.status = 'pending',
    this.method = '',
    this.provider,
    this.currency = '',
    this.countryCode,
    this.subtotal = 0,
    this.vatPercent = 0,
    this.vatAmount = 0,
    this.total = 0,
    this.pointsSpent,
    this.createdAt,
    this.paidAt,
    this.userName = '',
    this.username,
    this.items = const [],
    this.needsRefund = false,
  });

  final int id;
  final String status, method;
  final String? provider;
  final String currency;
  final String? countryCode;
  final double subtotal, vatPercent, vatAmount, total;
  final int? pointsSpent;
  final String? createdAt, paidAt;
  final String userName;
  final String? username;

  /// The item titles.
  final List<String> items;

  /// The order charged an item the buyer already owned: an admin must refund it.
  final bool needsRefund;

  static StoreOrderRow from(Map<String, dynamic> m) {
    final u = asMap(m['user']);
    return StoreOrderRow(
      id: asInt(m['id']),
      status: asStr(m['status'], 'pending'),
      method: asStr(m['method']),
      provider: asStrOrNull(m['provider']),
      currency: asStr(m['currency']),
      countryCode: asStrOrNull(m['country_code']),
      subtotal: asDouble(m['subtotal']),
      vatPercent: asDouble(m['vat_percent']),
      vatAmount: asDouble(m['vat_amount']),
      total: asDouble(m['total']),
      pointsSpent: m['points_spent'] == null ? null : asInt(m['points_spent']),
      createdAt: asStrOrNull(m['created_at']),
      paidAt: asStrOrNull(m['paid_at']),
      userName: asStr(u['name'], asStr(u['username'], '#${asInt(u['id'])}')),
      username: asStrOrNull(u['username']),
      items: [for (final i in asMapList(m['items'])) asStr(i['title'])],
      needsRefund: asBool(m['needs_refund']),
    );
  }
}

/// A page of rows.
class StorePage<T> {
  const StorePage(this.items, this.total, this.hasMore);
  final List<T> items;
  final int total;
  final bool hasMore;
}

/// A simple `{id, name}` choice (category, country).
class StoreChoice<K> {
  const StoreChoice(this.id, this.nameAr, this.nameEn, {this.currency});
  final K id;
  final String nameAr, nameEn;
  final String? currency;
  String get name => AppConfig.lang == 'ar' ? (nameAr.isNotEmpty ? nameAr : nameEn) : (nameEn.isNotEmpty ? nameEn : nameAr);
}

/// The answer of one upload: the item after the confirm, or null with the error already shown.
typedef StoreUploadProgress = void Function(double fraction);

class StoreManageApi {
  const StoreManageApi();

  Future<OrgCall> _call(Future<dynamic> Function() fn, {String? ok, bool quiet = false}) async {
    final r = await orgCall(fn, quiet: true);
    if (r.ok) {
      if (ok != null) toast(ok);
    } else if (!quiet) {
      toast(storeCallErrorText(r), error: true);
    }
    return r;
  }

  /// The text of a failed call: the store code's text, plus the `allowed` values when the server lists them
  /// (`store_bad_file_type`, `store_bad_currency`).
  static String storeCallErrorText(OrgCall r) {
    final base = storeErrorText(r.code) ?? orgErrorText(r.error!);
    final allowed = r.detail['allowed'];
    if (allowed is! List || allowed.isEmpty) return base;
    return '$base. ${t('المسموح', 'Allowed')}: ${allowed.join(', ')}';
  }

  // ── items ────────────────────────────────────────────────────────────────
  /// Null = failed; [OrgCall.code] tells why (`store_manage_forbidden` → the account cannot sell).
  Future<(StorePage<StoreManageItem>?, String?)> items({String? status, int skip = 0, int limit = 50}) async {
    final r = await _call(
        () => ApiClient().get(kStoreManagePath, queryParams: {'status': ?status, 'skip': skip, 'limit': limit}),
        quiet: true);
    if (!r.ok) return (null, r.code ?? 'error');
    final m = r.map;
    return (StorePage([for (final i in asMapList(m['items'])) StoreManageItem.from(i)], asInt(m['total']), asBool(m['has_more'])), null);
  }

  Future<StoreManageItem?> item(int id) async {
    final r = await _call(() => ApiClient().get('$kStoreManagePath/$id'));
    return r.ok ? StoreManageItem.from(r.map) : null;
  }

  Future<StoreManageItem?> create(Map<String, dynamic> body) async {
    final r = await _call(() => ApiClient().post(kStoreManagePath, body: body), ok: t('أُنشئ العنصر', 'Item created'));
    return r.ok ? StoreManageItem.from(r.map) : null;
  }

  /// [wasStatus] = the item's status before the edit: a teacher's edit to a published / pending item comes back
  /// `pending` (the store's review is on), which the toast says.
  Future<StoreManageItem?> update(int id, Map<String, dynamic> body, {String? ok, String? wasStatus}) async {
    final r = await _call(() => ApiClient().patch('$kStoreManagePath/$id', body: body));
    if (!r.ok) return null;
    final it = StoreManageItem.from(r.map);
    final reReview = it.status == 'pending' && (wasStatus == 'published' || wasStatus == 'pending') && !body.containsKey('status');
    toast(reReview ? t('حُفظ وأُرسل للمراجعة مرة أخرى', 'Saved and sent for review again') : (ok ?? t('حُفظ', 'Saved')));
    return it;
  }

  /// `(deleted, hidden)`: an item someone bought is hidden, never deleted.
  Future<(bool, bool)?> delete(int id) async {
    final r = await _call(() => ApiClient().delete('$kStoreManagePath/$id'));
    if (!r.ok) return null;
    return (asBool(r.map['deleted']), asBool(r.map['hidden']));
  }

  Future<StoreManageItem?> publish(int id) async {
    final r = await _call(() => ApiClient().post('$kStoreManagePath/$id/publish'));
    if (!r.ok) return null;
    final it = StoreManageItem.from(r.map);
    toast(it.status == 'pending' ? t('أُرسل للمراجعة', 'Sent for review') : t('نُشر العنصر', 'Item published'));
    return it;
  }

  /// Presign → PUT the bytes straight to storage (a bare Dio: the signed URL is the only credential) → confirm.
  /// [kind] is `file` (pdf / epub) or `preview` (pdf / image).
  Future<StoreManageItem?> upload(int id, {required String kind, required String fileName, required Uint8List bytes, required String contentType, StoreUploadProgress? onProgress}) async {
    if (bytes.length > kStoreMaxFileBytes) {
      toast(storeErrorText('store_file_too_large')!, error: true);
      return null;
    }
    final pre = await _call(() => ApiClient().post('$kStoreManagePath/$id/file',
        body: {'kind': kind, 'file_name': fileName, 'content_type': contentType, 'size': bytes.length}));
    if (!pre.ok) return null;
    final url = asStr(pre.map['upload_url']);
    final uploadId = asStr(pre.map['upload_id']);
    final type = asStr(pre.map['content_type'], contentType);
    try {
      final put = await Dio().put(url,
          data: bytes,
          options: Options(contentType: type, headers: {Headers.contentLengthHeader: bytes.length}),
          onSendProgress: (sent, total) => onProgress?.call(total > 0 ? sent / total : 0));
      if ((put.statusCode ?? 0) >= 300) throw StateError('upload ${put.statusCode}');
    } catch (_) {
      toast(t('تعذّر رفع الملف، حاول مرة أخرى', 'The file could not be uploaded, try again'), error: true);
      return null;
    }
    final done = await _call(() => ApiClient().post('$kStoreManagePath/$id/file', body: {'kind': kind, 'upload_id': uploadId, 'file_name': fileName}),
        ok: t('رُفع الملف', 'File uploaded'));
    return done.ok ? StoreManageItem.from(done.map) : null;
  }

  /// A cover image (already cropped): stored through the member upload route, which answers a signed, lasting link.
  Future<String?> uploadCover(Uint8List png, String fileName) async {
    final r = await _call(() => ApiClient().postMultipart('/api/v1/org/public/uploads', fields: const {}, fileField: 'file', fileName: fileName, fileBytes: png));
    if (!r.ok) return null;
    final u = asStr(r.map['url']);
    return u.isEmpty ? null : u;
  }

  // ── super admin ──────────────────────────────────────────────────────────
  Future<StorePage<StoreManageItem>?> pending({int skip = 0, int limit = 50}) async {
    final r = await _call(() => ApiClient().get('$kStoreAdminPath/items', queryParams: {'status': 'pending', 'skip': skip, 'limit': limit}), quiet: true);
    if (!r.ok) return null;
    return StorePage([for (final i in asMapList(r.map['items'])) StoreManageItem.from(i)], asInt(r.map['total']), asBool(r.map['has_more']));
  }

  Future<StoreManageItem?> review(int id, {required bool approve, String? note}) async {
    final r = await _call(
        () => ApiClient().post('$kStoreAdminPath/items/$id/review', body: {'approve': approve, if (note != null && note.trim().isNotEmpty) 'note': note.trim()}),
        ok: approve ? t('نُشر العنصر', 'Item approved') : t('أُعيد العنصر لصاحبه', 'Item returned to its owner'));
    return r.ok ? StoreManageItem.from(r.map) : null;
  }

  Future<StorePage<StoreOrderRow>?> orders({String? status, int skip = 0, int limit = 50}) async {
    final r = await _call(() => ApiClient().get('$kStoreAdminPath/orders', queryParams: {'status': ?status, 'skip': skip, 'limit': limit}),
        quiet: true);
    if (!r.ok) return null;
    return StorePage([for (final i in asMapList(r.map['items'])) StoreOrderRow.from(i)], asInt(r.map['total']), asBool(r.map['has_more']));
  }

  // ── form choices ─────────────────────────────────────────────────────────
  Future<List<StoreChoice<int>>> categories() async {
    final r = await _call(() => ApiClient().get('/api/v1/categories'), quiet: true);
    if (!r.ok || r.data is! List) return const [];
    return [for (final c in asMapList(r.data)) StoreChoice(asInt(c['id']), asStr(c['name_ar']), asStr(c['name_en']))];
  }

  Future<List<StoreChoice<String>>> countries() async {
    final r = await _call(() => ApiClient().get('/api/v1/edu/countries'), quiet: true);
    if (!r.ok || r.data is! List) return const [];
    return [
      for (final c in asMapList(r.data)) StoreChoice(asStr(c['code']), asStr(c['name_ar']), asStr(c['name_en']), currency: asStrOrNull(c['currency'])),
    ];
  }
}
