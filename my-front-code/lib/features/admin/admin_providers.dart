// lib/features/admin/admin_providers.dart
//
// Every provider here extends the app's own BaseProvider and talks to the
// backend through the shared ApiClient (so token refresh, device headers and
// the envelope-encryption tunnel apply automatically).
//
// Screens create them locally:
//     ChangeNotifierProvider(create: (_) => AdminUsersProvider('student')..refresh())
// so nothing here has to be added to core/providers.dart.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';

import 'admin_common.dart';
import 'admin_filter_models.dart';
import 'admin_models.dart';

const _base = '/api/v1/admin';

class AdminBase extends BaseProvider {
  final ApiClient api = ApiClient();

  /// Runs a mutation. Returns the response body (or `true` when the body is
  /// empty) on success and `null` on failure, after toasting the server's
  /// message. [ok] is the success toast.
  Future<dynamic> call(Future<dynamic> Function() fn, {String? ok}) async {
    try {
      final r = await fn();
      if (ok != null) toast(ok);
      return r ?? true;
    } on ApiException catch (e) {
      toast(e.message, error: true);
      return null;
    } catch (e) {
      toast('$e', error: true);
      return null;
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Paged list base
// ═════════════════════════════════════════════════════════════════════════════

abstract class AdminPagedProvider extends AdminBase implements AdminQueryHost {
  final List<Map<String, dynamic>> rows = [];
  int page = 0;
  int pages = 1;
  int total = 0;
  bool loadingMore = false;
  bool loaded = false;
  String? error;
  Map<String, dynamic> extra = {};

  // ── premium search / filter / sort (shared by every paged admin list) ─────
  /// Free-text search. Multi-word, Arabic-aware, also matches phones and `#id`.
  String search = '';

  /// Active advanced filters: query key -> String | bool | num | DateTime | LookupValue.
  final Map<String, Object?> adv = {};

  /// Sort key (null = the server default).
  String? sort;

  Timer? _debounce;
  bool _disposed = false;
  int _gen = 0; // drops answers of requests that were replaced meanwhile

  String get path;
  Map<String, dynamic> get filters;

  bool get hasMore => page < pages;

  @override
  int? get resultCount => loaded ? total : null;

  /// Anything that narrows the list (search, filters, sort).
  @override
  bool get hasActiveQuery => search.isNotEmpty || adv.isNotEmpty || sort != null;

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// The search field already waits 1 s after the last key (kSearchDelay), so this
  /// applies at once — a second delay here would just make the admin wait longer.
  /// Timer.zero still coalesces several calls in the same frame into one request.
  Future<void> setSearch(String v) async {
    final t = v.trim();
    if (t == search) return;
    search = t;
    _debounce?.cancel();
    _debounce = Timer(Duration.zero, () {
      if (!_disposed) refresh();
    });
  }

  /// Set (or, with null, remove) one filter.
  Future<void> setAdv(String key, Object? value) {
    if (value == null) {
      adv.remove(key);
    } else {
      adv[key] = value;
    }
    return refresh();
  }

  /// Replace every advanced filter + the sort at once (the filter sheet's "Apply").
  Future<void> applyAdv(Map<String, Object?> values, {String? sortKey}) {
    adv
      ..clear()
      ..addAll({
        for (final e in values.entries)
          if (e.value != null) e.key: e.value,
      });
    sort = sortKey;
    return refresh();
  }

  /// Removes the given filters (a chip's "x").
  Future<void> removeAdv(Iterable<String> keys) {
    keys.forEach(adv.remove);
    return refresh();
  }

  Future<void> setSort(String? v) {
    sort = v;
    return refresh();
  }

  /// Search + filters + sort back to the defaults.
  Future<void> clearAll() {
    _debounce?.cancel();
    search = '';
    adv.clear();
    sort = null;
    return refresh();
  }

  Future<void> refresh() async {
    _debounce?.cancel();
    rows.clear();
    page = 0;
    pages = 1;
    total = 0;
    loaded = false;
    loadingMore = false;
    error = null;
    await _fetch(1);
  }

  Future<void> loadMore() async {
    if (loadingMore || isLoading || !hasMore) return;
    await _fetch(page + 1);
  }

  Future<void> _fetch(int p) async {
    final gen = p == 1 ? ++_gen : _gen;
    if (p > 1) {
      loadingMore = true;
      _notify();
    }
    final query = <String, dynamic>{
      for (final e in filters.entries)
        if (e.value != null && '${e.value}'.isNotEmpty) e.key: e.value,
      ...encodeFilters(adv),
      if (search.isNotEmpty) 'search': search,
      if (sort != null) 'sort': sort,
      'page': p,
      'size': 20,
    };
    final r = await run(() => api.get(path, queryParams: query),
        makLoading: p == 1);
    if (_disposed || gen != _gen) return; // a newer search / filter replaced this request
    if (r is Map) {
      final d = PageData(Map<String, dynamic>.from(r));
      rows.addAll(d.items);
      page = d.page;
      pages = d.pages;
      total = d.total;
      extra = d.extra;
      error = null;
    } else if (p == 1) {
      error = errorMessage ?? 'admin_could_not_load_data'.tr;
    }
    loaded = true;
    loadingMore = false;
    _notify();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Overview
// ═════════════════════════════════════════════════════════════════════════════

class AdminOverviewProvider extends AdminBase {
  Overview? data;
  String? error;

  Future<void> load() async {
    final r = await run(() => api.get('$_base/overview'));
    if (r is Map) {
      data = Overview(Map<String, dynamic>.from(r));
      error = null;
    } else {
      error = errorMessage ?? 'admin_could_not_load_data'.tr;
    }
    notifyListeners();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Users (students / teachers)
// ═════════════════════════════════════════════════════════════════════════════

class AdminUsersProvider extends AdminPagedProvider {
  AdminUsersProvider(this.role);
  final String role; // student | teacher | admin

  // Live in [adv] so the filter sheet, the chips and these getters never disagree.
  String? get status => adv['status'] as String?; // active | inactive | pending_deletion
  bool? get subscribed => adv['subscribed'] as bool?;

  @override
  String get path => '$_base/users';

  @override
  Map<String, dynamic> get filters => {'role': role};

  List<AdminUser> get users => rows.map(AdminUser.new).toList();

  Future<void> setStatus(String? v) => setAdv('status', v);

  Future<void> setSubscribed(bool? v) => setAdv('subscribed', v);

  Future<UserDetail?> detail(int id) async {
    final r = await run(() => api.get('$_base/users/$id'), makLoading: false);
    return r is Map ? UserDetail(Map<String, dynamic>.from(r)) : null;
  }

  Future<bool> create(Map<String, dynamic> body) async {
    final r = await call(() => api.post('$_base/users', body: body),
        ok: 'admin_created'.tr);
    if (r != null) await refresh();
    return r != null;
  }

  Future<bool> update(int id, Map<String, dynamic> body) async {
    final r = await call(() => api.put('$_base/users/$id', body: body),
        ok: 'admin_saved'.tr);
    if (r != null) await refresh();
    return r != null;
  }

  Future<bool> setActive(int id, bool active) => update(id, {'is_active': active});
  Future<bool> setVerified(int id, bool verified) => update(id, {'is_verified': verified});

  Future<bool> remove(int id) async {
    final r = await call(() => api.delete('$_base/users/$id'),
        ok: 'admin_deleted'.tr);
    if (r != null) await refresh();
    return r != null;
  }

  Future<bool> resetDevices(int id) async =>
      await call(() => api.post('$_base/users/$id/reset-devices'),
          ok: 'admin_devices_reset'.tr) !=
          null;

  Future<bool> removeDevice(int userId, int rowId) async =>
      await call(() => api.delete('$_base/users/$userId/devices/$rowId'),
          ok: 'admin_device_removed'.tr) !=
          null;

  Future<bool> enroll(int userId, int courseId) async {
    final r = await call(
            () => api.post('$_base/users/$userId/enroll', body: {'course_id': courseId}),
        ok: 'admin_enrolled'.tr);
    if (r != null) await refresh();
    return r != null;
  }

  /// mode: 'allow_payment' (student pays again) | 'reopen' (admin re-activates, no payment)
  Future<bool> allowResubscribe(int userId, int courseId,
      {String mode = 'allow_payment', String? plan, int? days}) async {
    final r = await call(
            () => api.post('$_base/users/$userId/courses/$courseId/allow-resubscribe',
            body: {'mode': mode, 'plan': ?plan, 'days': ?days}),
        ok: 'admin_saved'.tr);
    if (r != null) await refresh();
    return r != null;
  }

  Future<bool> unenroll(int userId, int courseId) async {
    final r = await call(() => api.delete('$_base/users/$userId/enrollments/$courseId'),
        ok: 'admin_removed_from_course'.tr);
    if (r != null) await refresh();
    return r != null;
  }

  Future<bool> grant(int userId, {String? planCode, int? days}) async {
    final r = await call(
            () => api.post('$_base/users/$userId/subscription/grant', body: {
        'plan_code': ?planCode,
        'days': ?days,
        }),
        ok: 'admin_subscription_granted'.tr);
    if (r != null) await refresh();
    return r != null;
  }

  /// Courses for the "enrol in course" picker.
  Future<List<AdminCourse>> courseChoices() async {
    final r = await run(
            () => api.get('$_base/courses', queryParams: {'page': 1, 'size': 100}),
        makLoading: false);
    return r is Map ? PageData(Map<String, dynamic>.from(r)).items.map(AdminCourse.new).toList() : [];
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Courses
// ═════════════════════════════════════════════════════════════════════════════

class AdminCoursesProvider extends AdminPagedProvider {
  bool? get published => adv['published'] as bool?;
  String? get status => adv['status'] as String?;
  int? get teacherId {
    final v = adv['teacher_id'];
    if (v is! LookupValue) return null;
    return v.id is int ? v.id as int : int.tryParse('${v.id}');
  }

  @override
  String get path => '$_base/courses';

  @override
  Map<String, dynamic> get filters => const {};

  List<AdminCourse> get courses => rows.map(AdminCourse.new).toList();
  double get totalIncome => asDouble(asMap(extra['totals'])['income']);

  /// Same total split by currency (the single number above adds EGP + SAR + USD together).
  Map<String, double> get incomeByCurrency =>
      asMap(asMap(extra['totals'])['income_by_currency']).map((c, v) => MapEntry(c, asDouble(v)));

  Future<void> setPublished(bool? v) => setAdv('published', v);

  Future<void> setStatus(String? v) => setAdv('status', v);

  Future<AdminCourse?> detail(int id) async {
    final r = await run(() => api.get('$_base/courses/$id'), makLoading: false);
    return r is Map ? AdminCourse(Map<String, dynamic>.from(r)) : null;
  }

  /// Raw course map (includes is_private / access_code / allow_resubscribe).
  Future<Map<String, dynamic>?> detailRaw(int id) async {
    final r = await run(() => api.get('$_base/courses/$id'), makLoading: false);
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  Future<bool> create(Map<String, dynamic> body) async {
    final r = await call(() => api.post('$_base/courses', body: body),
        ok: 'admin_course_created'.tr);
    if (r != null) await refresh();
    return r != null;
  }

  Future<bool> update(int id, Map<String, dynamic> body) async {
    final r = await call(() => api.put('$_base/courses/$id', body: body),
        ok: 'admin_saved'.tr);
    if (r != null) await refresh();
    return r != null;
  }

  Future<bool> remove(int id, {bool force = false}) async {
    final r = await call(
            () => api.delete('$_base/courses/$id', queryParams: {'force': force}),
        ok: 'admin_course_deleted'.tr);
    if (r != null) await refresh();
    return r != null;
  }

  /// `body` keys are sent as-is, so `{'payment_provider': null}` RESETS that
  /// field to the system default while omitted keys stay untouched.
  Future<bool> savePaymentSettings(int id, Map<String, dynamic> body) async {
    final r = await call(
            () => api.put('$_base/courses/$id/payment-settings', body: body),
        ok: 'admin_payment_settings_saved'.tr);
    if (r != null) await refresh();
    return r != null;
  }

  Future<List<AdminUser>> teacherChoices() async {
    final r = await run(
            () => api.get('$_base/users',
            queryParams: {'role': 'teacher', 'page': 1, 'size': 100}),
        makLoading: false);
    return r is Map ? PageData(Map<String, dynamic>.from(r)).items.map(AdminUser.new).toList() : [];
  }

  Future<List<AdminCategory>> categoryChoices() async {
    final r = await run(() => api.get('$_base/categories'), makLoading: false);
    return r is Map ? asMapList(r['items']).map(AdminCategory.new).toList() : [];
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Categories
// ═════════════════════════════════════════════════════════════════════════════

class AdminCategoriesProvider extends AdminBase implements AdminQueryHost {
  List<AdminCategory> items = [];
  String? error;

  // premium search / filter / sort (same contract as AdminPagedProvider)
  String search = '';
  final Map<String, Object?> adv = {};
  String? sort;
  Timer? _debounce;
  bool _disposed = false;
  int _gen = 0;

  @override
  bool get hasActiveQuery => search.isNotEmpty || adv.isNotEmpty || sort != null;

  @override
  int? get resultCount => _loadedOnce ? items.length : null;
  bool _loadedOnce = false;

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Future<void> setSearch(String v) async {
    final t = v.trim();
    if (t == search) return;
    search = t;
    _debounce?.cancel();
    _debounce = Timer(Duration.zero, () {
      if (!_disposed) load();
    });
  }

  Future<void> applyAdv(Map<String, Object?> values, {String? sortKey}) {
    adv
      ..clear()
      ..addAll({
        for (final e in values.entries)
          if (e.value != null) e.key: e.value,
      });
    sort = sortKey;
    return load();
  }

  Future<void> removeAdv(Iterable<String> keys) {
    keys.forEach(adv.remove);
    return load();
  }

  Future<void> setSort(String? v) {
    sort = v;
    return load();
  }

  Future<void> clearAll() {
    _debounce?.cancel();
    search = '';
    adv.clear();
    sort = null;
    return load();
  }

  Future<void> load() async {
    _debounce?.cancel();
    final gen = ++_gen;
    final r = await run(() => api.get('$_base/categories', queryParams: {
      ...encodeFilters(adv),
      if (search.isNotEmpty) 'search': search,
      if (sort != null) 'sort': sort,
    }));
    if (_disposed || gen != _gen) return;
    if (r is Map) {
      items = asMapList(r['items']).map(AdminCategory.new).toList();
      error = null;
      _loadedOnce = true;
    } else {
      error = errorMessage ?? 'admin_could_not_load_data'.tr;
    }
    notifyListeners();
  }

  Future<bool> save({int? id, required Map<String, dynamic> body}) async {
    final r = await call(
            () => id == null
            ? api.post('$_base/categories', body: body)
            : api.put('$_base/categories/$id', body: body),
        ok: 'admin_saved'.tr);
    if (r != null) await load();
    return r != null;
  }

  Future<bool> remove(int id) async {
    final r = await call(() => api.delete('$_base/categories/$id'),
        ok: 'admin_deleted'.tr);
    if (r != null) await load();
    return r != null;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Subscriptions (switch + plans + requests)
// ═════════════════════════════════════════════════════════════════════════════

class AdminSubscriptionsProvider extends AdminPagedProvider {
  AdminSubscriptionsProvider() {
    adv['status'] = 'pending'; // the admin opens the page to review requests
  }

  String? get statusFilter => adv['status'] as String?;

  bool required = false;
  List<Plan> plans = [];
  bool settingsLoaded = false;

  @override
  String get path => '$_base/subscriptions';

  @override
  Map<String, dynamic> get filters => const {};

  List<SubInfo> get requests => rows.map((e) => SubInfo(e)).toList();

  Future<void> loadAll() async {
    await loadPlans();
    await refresh();
  }

  Future<void> loadPlans() async {
    final r = await run(() => api.get('$_base/subscription-plans'), makLoading: false);
    if (r is Map) {
      required = asBool(r['required']);
      plans = asMapList(r['items']).map(Plan.new).toList();
      settingsLoaded = true;
      notifyListeners();
    }
  }

  Future<void> setStatusFilter(String? v) => setAdv('status', v);

  Future<bool> setRequired(bool v) async {
    final r = await call(
            () => api.put('$_base/settings', body: {'subscription_required': v}),
        ok: v
            ? 'admin_subscription_is_now_required'.tr
            : 'admin_the_app_is_now_free'.tr);
    if (r != null) {
      required = v;
      notifyListeners();
    }
    return r != null;
  }

  Future<bool> savePlan(String code, Map<String, dynamic> body) async {
    final r = await call(() => api.put('$_base/subscription-plans/$code', body: body),
        ok: 'admin_plan_saved'.tr);
    if (r != null) await loadPlans();
    return r != null;
  }

  Future<bool> approve(int id) async {
    final r = await call(() => api.post('$_base/subscriptions/$id/approve'),
        ok: 'admin_approved_2'.tr);
    if (r != null) await refresh();
    return r != null;
  }

  Future<bool> reject(int id, String? reason) async {
    final r = await call(
            () => api.post('$_base/subscriptions/$id/reject', body: {'reason': reason}),
        ok: 'admin_rejected_2'.tr);
    if (r != null) await refresh();
    return r != null;
  }

  Future<bool> cancel(int id) async {
    final r = await call(() => api.post('$_base/subscriptions/$id/cancel'),
        ok: 'admin_cancelled'.tr);
    if (r != null) await refresh();
    return r != null;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  System settings (devices, default gateway, platform fee)
// ═════════════════════════════════════════════════════════════════════════════

class AdminSettingsProvider extends AdminBase {
  Map<String, dynamic> values = {};
  String? error;

  int get maxDevices => asInt(values['max_devices'], 1);
  int get maxVideos => asInt(values['max_monthly_view'], 1);
  int get switchDays => asInt(values['device_switch_days'], 30);
  bool get allowResubscribe => values['allow_resubscribe'] != false;
  String? get defaultProvider => asStrOrNull(values['default_payment_provider']);
  double? get platformFee => values['platform_fee_percent'] == null
      ? null
      : asDouble(values['platform_fee_percent']);

  Future<void> load() async {
    final r = await run(() => api.get('$_base/settings'));
    if (r is Map) {
      values = Map<String, dynamic>.from(r);
      error = null;
    } else {
      error = errorMessage ?? 'admin_could_not_load_data'.tr;
    }
    notifyListeners();
  }

  Future<bool> save(Map<String, dynamic> body) async {
    final r = await call(() => api.put('$_base/settings', body: body),
        ok: 'exam_rules_saved_snack'.tr);
    if (r is Map) {
      values = Map<String, dynamic>.from(r);
      notifyListeners();
    }
    return r != null;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Payment methods (existing endpoints)
// ═════════════════════════════════════════════════════════════════════════════

class AdminPaymentMethodsProvider extends AdminBase {
  List<Map<String, dynamic>> items = [];
  String? error;

  Future<void> load() async {
    final r = await run(() => api.get('$_base/payment-methods'));
    if (r is Map) {
      items = asMapList(r['items']);
      error = null;
    } else {
      error = errorMessage ?? 'admin_could_not_load_data'.tr;
    }
    notifyListeners();
  }

  Future<bool> save(String method, Map<String, dynamic> body) async {
    final r = await call(() => api.put('$_base/payment-methods/$method', body: body),
        ok: 'admin_saved'.tr);
    if (r != null) await load();
    return r != null;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Themes
// ═════════════════════════════════════════════════════════════════════════════

class AdminThemesProvider extends AdminBase {
  List<ThemePresetModel> items = [];
  String? activeKey;
  String? error;

  Future<void> load() async {
    final r = await run(() => api.get('$_base/themes'));
    _apply(r);
  }

  void _apply(dynamic r) {
    if (r is Map) {
      items = asMapList(r['items']).map(ThemePresetModel.new).toList();
      activeKey = asStrOrNull(r['active_preset']);
      error = null;
    } else {
      error = errorMessage ?? 'admin_could_not_load_data'.tr;
    }
    notifyListeners();
  }

  /// Activates a preset for every platform (or just [platforms]).
  Future<bool> activate(int id, {List<String>? platforms}) async {
    final r = await call(
            () => api.post('$_base/themes/$id/activate',
            body: {'platforms': platforms}),
        ok: 'admin_theme_activated_users_get_it_on_next'.tr);
    if (r is Map) _apply(r);
    return r != null;
  }

  Future<bool> save({int? id, required String nameAr, required String nameEn, required Map<String, String> colors}) async {
    final body = {'name_ar': nameAr, 'name_en': nameEn, 'colors': colors};
    final r = await call(
            () => id == null
            ? api.post('$_base/themes', body: body)
            : api.put('$_base/themes/$id', body: body),
        ok: 'admin_theme_saved'.tr);
    if (r != null) await load();
    return r != null;
  }

  Future<bool> remove(int id) async {
    final r = await call(() => api.delete('$_base/themes/$id'),
        ok: 'admin_theme_deleted'.tr);
    if (r != null) await load();
    return r != null;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Features (hide / unhide)
//  GET  /admin/features?tab=&page=&size=   one page (20) of one class (tab)
//  PUT  /admin/features/{key}              hide / unhide
//  PUT  /admin/features/{key}/access       super-admin: grant / revoke for admins
//  POST /admin/features                    super-admin: add a new feature
//  No change to admin_models.dart is needed: tab / access info is kept here.
// ═════════════════════════════════════════════════════════════════════════════
/// One feature class (tab) as sent by GET /admin/features → `tabs`.
class FeatureTab {
  FeatureTab(Map<String, dynamic> j)
      : id = '${j['id']}',
        titleAr = asStrOrNull(j['title_ar']) ?? '',
        titleEn = asStrOrNull(j['title_en']) ?? '',
        count = asInt(j['count']);

  final String id;
  final String titleAr;
  final String titleEn;

  /// Number of features in this class (for the current role).
  final int count;

  /// Cached items of this tab (empty = not loaded yet).
  List<FeatureItem> items = [];

  // Pagination state of the cached page
  int page = 1;
  int pages = 1;
  int total = 0;

  String label(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ar' ? titleAr : titleEn;
}

class AdminFeaturesProvider extends AdminBase {
  static const pageSize = 20;

  List<FeatureTab> tabs = [];
  List<String> platforms = ['android', 'ios', 'web'];

  int selectedTabIndex = 0;
  int page = 1;
  int pages = 1;
  int total = 0;

  /// Super-admin: sees everything, can grant features to admins and add new ones.
  bool isSuperAdmin = false;
  bool loaded = false;
  String? error;

  bool get canAddCustom => isSuperAdmin;
  bool get hasPrev => page > 1;
  bool get hasNext => page < pages;

  // ── infinite scroll: the next page is APPENDED to the class that is on screen ──
  bool loadingMore = false;

  /// The last append failed: stop auto-filling the viewport (otherwise it would retry in a tight loop).
  bool loadMoreFailed = false;
  bool get hasMore => page < pages;

  /// Items of the selected tab (safe when tabs are empty).
  List<FeatureItem> get currentItems =>
      (selectedTabIndex >= 0 && selectedTabIndex < tabs.length)
          ? tabs[selectedTabIndex].items
          : const [];

  /// true = admins can see / toggle this feature.
  /// Read from the cached items, so it stays correct across tab switches.
  bool allowedToAdmin(String key) {
    for (final t in tabs) {
      for (final f in t.items) {
        if (f.key == key) return f.allowToAdmin;
      }
    }
    return false;
  }

  /// Fetches from the server. [tabIndex] null = server picks the default class.
  Future<void> load({int toPage = 1}) async {
    final tabId = (selectedTabIndex >= 0 && selectedTabIndex < tabs.length)
        ? tabs[selectedTabIndex].id
        : null;
    final r = await run(() => api.get('$_base/features', queryParams: {
      'tab': ?tabId,
      'page': toPage,
      'size': pageSize,
    }));
    _apply(r);
  }

  /// Pull-to-refresh / retry: back to page 1 of the selected class.
  Future<void> refresh() {
    loadMoreFailed = false;
    return load();
  }

  /// After a toggle: re-read every page that is already on screen, so the scroll position
  /// and the pages the user loaded are kept (a plain refresh would collapse back to page 1).
  Future<void> reloadLoaded() async {
    final upTo = page < 1 ? 1 : page;
    await load();
    while (page < upTo && hasMore) {
      if (!await _appendNext(silent: true)) break;
    }
  }

  /// Scroll reached the bottom → fetch the next page and append it.
  Future<void> loadMore() async {
    if (loadingMore || isLoading || !hasMore || tabs.isEmpty) return;
    await _appendNext();
  }

  Future<bool> _appendNext({bool silent = false}) async {
    if (selectedTabIndex < 0 || selectedTabIndex >= tabs.length) return false;
    final tab = tabs[selectedTabIndex];
    loadingMore = true;
    notifyListeners();
    var ok = false;
    try {
      final r = await api.get('$_base/features', queryParams: {
        'tab': tab.id,
        'page': tab.page + 1,
        'size': pageSize,
      });
      if (r is Map) {
        final known = tab.items.map((e) => e.key).toSet();
        final fresh = asMapList(r['items'])
            .map(FeatureItem.new)
            .where((e) => !known.contains(e.key))
            .toList();
        tab.items = [...tab.items, ...fresh];
        tab.page = asInt(r['page'], tab.page + 1);
        tab.pages = asInt(r['pages'], tab.pages);
        tab.total = asInt(r['total'], tab.total);
        final stillSelected =
            selectedTabIndex < tabs.length && identical(tabs[selectedTabIndex], tab);
        if (stillSelected) {
          page = tab.page;
          pages = tab.pages;
          total = tab.total;
        }
        loadMoreFailed = false;
        ok = true;
      }
    } on ApiException catch (e) {
      loadMoreFailed = true;
      if (!silent) toast(e.message, error: true);
    } catch (e) {
      loadMoreFailed = true;
      if (!silent) toast('$e', error: true);
    }
    loadingMore = false;
    notifyListeners();
    return ok;
  }

  /// Switch tab. Hits the server only if the destination tab is empty.
  Future<void> selectTab(int index) async {
    selectedTabIndex = index;
    loadMoreFailed = false;

    if (index < 0 || index >= tabs.length) return;
    final t = tabs[index];

    if (t.items.isNotEmpty || t.count == 0) {
      page = t.page;
      pages = t.pages;
      total = t.total;
      notifyListeners();
      return;
    }

    await load();
  }

  Future<void> goToPage(int p) => load(
      toPage: p.clamp(1, pages).toInt());

  /// Applies a GET/POST response.
  /// Tabs (and their counts) are rebuilt every time; cached items of the other
  /// tabs are kept. Items are stored in the tab the SERVER says it returned
  /// (`selected_tab`), never blindly in the tab the UI has selected.
  void _apply(dynamic r, {bool followServerTab = false}) {
    if (r is Map) {
      final oldById = {for (final t in tabs) t.id: t};
      final previousId =
      (selectedTabIndex >= 0 && selectedTabIndex < tabs.length)
          ? tabs[selectedTabIndex].id
          : null;

      final newTabs = asMapList(r['tabs']).map(FeatureTab.new).toList();
      for (final t in newTabs) {
        final old = oldById[t.id];
        if (old != null) {
          t.items = old.items;
          t.page = old.page;
          t.pages = old.pages;
          t.total = old.total;
        }
      }
      tabs = newTabs;

      final serverId =
      r['selected_tab'] == null ? null : '${r['selected_tab']}';
      final serverIdx = tabs.indexWhere((e) => e.id == serverId);

      if (followServerTab && serverIdx >= 0) {
        selectedTabIndex = serverIdx;
      } else {
        final keep = tabs.indexWhere((e) => e.id == previousId);
        selectedTabIndex = keep >= 0 ? keep : (serverIdx >= 0 ? serverIdx : 0);
      }

      page = asInt(r['page'], 1);
      pages = asInt(r['pages'], 1);
      total = asInt(r['total']);
      isSuperAdmin = asBool(r['is_super_admin']);

      if (serverIdx >= 0) {
        final t = tabs[serverIdx];
        t.items = asMapList(r['items']).map(FeatureItem.new).toList();
        t.page = page;
        t.pages = pages;
        t.total = total;
      }

      if (r['platforms'] is List) {
        platforms = (r['platforms'] as List).map((e) => '$e').toList();
      }
      error = null;
    } else {
      error = errorMessage ?? 'admin_could_not_load_data'.tr;
    }
    loaded = true;
    notifyListeners();
  }

  /// Hide / unhide [key] on [platforms] (all when null).
  Future<void> set(String key, bool hidden, {List<String>? platforms}) async {
    final r = await call(() => api.put('$_base/features/$key', body: {
      'hidden': hidden,
      'platforms': platforms,
    }));
    // The PUT response is not tied to the tab / page being viewed,
    // so reload the page the user is looking at.
    if (r != null) await reloadLoaded();
  }

  /// Super-admin: let admins see / toggle [key] (or take it back).
  Future<void> setAllowToAdmin(String key, bool allow) async {
    final r = await call(() => api.put('$_base/features/$key/access',
        body: {'allow_to_admin': allow}));
    if (r != null) await reloadLoaded();
  }

  /// Super-admin: add a feature. Pass [tabId] for an existing class, or
  /// [tabAr] + [tabEn] to create a new one.
  Future<bool> createFeature({
    required String key,
    required String titleAr,
    required String titleEn,
    String? tabId,
    String? tabAr,
    String? tabEn,
    bool allowToAdmin = false,
    bool hidden = false,
  }) async {
    final r = await call(
            () => api.post('$_base/features', body: {
          'key': key,
          'title_ar': titleAr,
          'title_en': titleEn,
          'tab_id': tabId,
          'tab_ar': tabAr,
          'tab_en': tabEn,
          'allow_to_admin': allowToAdmin,
          'hidden': hidden,
        }),
        ok: 'admin_created'.tr);
    if (r is Map) {
      _apply(r, followServerTab: true); // jump to the new feature's tab
      await load(); // re-fetch page 1 with this screen's page size
    }
    return r != null;
  }
}
class AdminVersionsProvider extends AdminBase {
  List<Map<String, dynamic>> items = [];
  String? error;

  Future<void> load() async {
    final r = await run(() => api.get('/app/'));
    if (r is List) {
      items = asMapList(r);
      error = null;
    } else {
      error = errorMessage ?? 'admin_could_not_load_data'.tr;
    }
    notifyListeners();
  }

  Future<bool> create(Map<String, dynamic> body) async {
    final r = await call(() => api.post('/app/', body: body),
        ok: 'admin_version_published'.tr);
    if (r != null) await load();
    return r != null;
  }

  Future<bool> update(int id, Map<String, dynamic> body) async {
    final r = await call(() => api.patch('/app/$id', body: body),
        ok: 'admin_saved'.tr);
    if (r != null) await load();
    return r != null;
  }

  Future<bool> toggle(int id) async {
    final r = await call(() => api.patch('/app/$id/toggle'));
    if (r != null) await load();
    return r != null;
  }

  Future<bool> remove(int id) async {
    final r = await call(() => api.delete('/app/$id'),
        ok: 'admin_deleted'.tr);
    if (r != null) await load();
    return r != null;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Terms & About content
// ═════════════════════════════════════════════════════════════════════════════

class AdminContentProvider extends AdminBase {
  static const _content = '/api/v1/app-content';

  Map<String, dynamic>? termsMeta;
  List<Map<String, dynamic>> sections = [];
  Map<String, dynamic>? aboutInfo;
  String? error;

  Future<void> load() async {
    final terms = await run(() => api.get('$_base/content/terms'));
    final about = await run(() => api.get('$_base/content/about'), makLoading: false);
    if (terms is Map) {
      termsMeta = terms['meta'] is Map ? asMap(terms['meta']) : null;
      sections = asMapList(terms['sections']);
      error = null;
    } else {
      error = errorMessage ?? 'admin_could_not_load_data'.tr;
    }
    if (about is Map) {
      aboutInfo = about['info'] is Map ? asMap(about['info']) : null;
    }
    notifyListeners();
  }

  Future<bool> saveMeta(Map<String, dynamic> body) async {
    final r = await call(() => api.patch('$_content/terms/meta', body: body),
        ok: 'admin_saved'.tr);
    if (r != null) await load();
    return r != null;
  }

  Future<bool> saveSection({int? id, required Map<String, dynamic> body}) async {
    final r = await call(
            () => id == null
            ? api.post('$_content/terms/sections', body: body)
            : api.patch('$_content/terms/sections/$id', body: body),
        ok: 'admin_saved'.tr);
    if (r != null) await load();
    return r != null;
  }

  Future<bool> deleteSection(int id) async {
    final r = await call(() => api.delete('$_content/terms/sections/$id'),
        ok: 'admin_deleted'.tr);
    if (r != null) await load();
    return r != null;
  }

  Future<bool> saveAbout(Map<String, dynamic> body) async {
    final r = await call(() => api.patch('$_content/about/info', body: body),
        ok: 'admin_saved'.tr);
    if (r != null) await load();
    return r != null;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Payouts (admin): requests · per-teacher permission · global settings
// ═════════════════════════════════════════════════════════════════════════════

/// Withdrawal requests. The existing endpoint paginates with skip/limit.
class AdminPayoutRequestsProvider extends AdminPagedProvider {
  String? status = 'pending'; // null = all
  final Set<int> busy = {};

  // Required by AdminPagedProvider; unused because this endpoint paginates with
  // skip/limit, so refresh / loadMore / hasMore are overridden below.
  @override
  String get path => '$_base/withdrawals';
  @override
  Map<String, dynamic> get filters => {'status': status};

  List<Withdrawal> get items => rows.map(Withdrawal.new).toList();

  @override
  bool get hasMore => rows.length < total;

  Future<void> setStatus(String? s) {
    status = s;
    return refresh();
  }

  @override
  Future<void> refresh() async {
    rows.clear();
    total = 0;
    loaded = false;
    error = null;
    await _fetchSkip(0);
  }

  @override
  Future<void> loadMore() async {
    if (loadingMore || isLoading || !hasMore) return;
    await _fetchSkip(rows.length);
  }

  Future<void> _fetchSkip(int skip) async {
    if (skip > 0) {
      loadingMore = true;
      notifyListeners();
    }
    final r = await run(
            () => api.get('$_base/withdrawals', queryParams: {
          if (status != null) 'status': status,
          'skip': skip,
          'limit': 20,
        }),
        makLoading: skip == 0);
    if (r is Map) {
      rows.addAll(asMapList(r['items']));
      total = asInt(r['total']);
      error = null;
    } else if (skip == 0) {
      error = errorMessage ?? 'admin_could_not_load_data'.tr;
    }
    loaded = true;
    loadingMore = false;
    notifyListeners();
  }

  Future<bool> _act(int id, Future<dynamic> Function() fn, String ok) async {
    busy.add(id);
    notifyListeners();
    final r = await call(fn, ok: ok);
    busy.remove(id);
    if (r != null) {
      await refresh();
    } else {
      notifyListeners();
    }
    return r != null;
  }

  /// Approve. For Moyasar / Paymob accounts the SERVER then sends the money by itself.
  Future<bool> approve(int id, {String? note}) => _act(
      id,
          () => api.post('$_base/withdrawals/$id/approve', body: {'admin_note': note}),
      'doc_approved'.tr);

  Future<bool> markPaid(int id, String reference, {String? note}) => _act(
      id,
          () => api.post('$_base/withdrawals/$id/mark-paid',
          body: {'bank_reference': reference, 'admin_note': note}),
      'admin_marked_as_paid'.tr);

  /// Uploads the transfer receipt (image / PDF) for [id]. No list refresh and no
  /// success toast — the caller confirms the transfer right after, which refreshes.
  Future<bool> uploadReceipt(
      int id, {
        required String fileName,
        String? filePath, // mobile / desktop
        Uint8List? bytes, // web
      }) async {
    busy.add(id);
    notifyListeners();
    final r = await call(() => api.postMultipart(
      '$_base/payouts/withdrawals/$id/receipt',
      fields: const {},
      fileField: 'file',
      fileName: fileName,
      filePath: filePath,
      fileBytes: bytes,
    ));
    busy.remove(id);
    notifyListeners();
    return r != null;
  }

  /// Fresh signed link to the receipt (PDFs sit in a private bucket, so the stored URL is not openable).
  Future<Map<String, dynamic>?> receiptLink(int id) async {
    final r = await call(() => api.get('$_base/payouts/withdrawals/$id/receipt-url'));
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  Future<bool> reject(int id, String reason) => _act(
      id,
          () => api.post('$_base/withdrawals/$id/reject', body: {'rejected_reason': reason}),
      'admin_rejected_2'.tr);

  Future<bool> retry(int id) => _act(id, () => api.post('$_base/payouts/withdrawals/$id/retry'),
      'admin_retried'.tr);

  Future<bool> sync(int id) => _act(id, () => api.post('$_base/payouts/withdrawals/$id/sync'),
      'admin_status_refreshed'.tr);

  Future<bool> resolve(int id, {required bool sent, String? reference}) => _act(
      id,
          () => api.post('$_base/payouts/withdrawals/$id/resolve',
          body: {'sent': sent, 'reference': reference}),
      'admin_resolved'.tr);
}

/// Per-teacher payout permission.
class AdminPayoutTeachersProvider extends AdminPagedProvider {
  String? only; // allowed | blocked

  @override
  String get path => '$_base/payouts/teachers';

  @override
  Map<String, dynamic> get filters => {'only': only};

  Future<void> setOnly(String? v) {
    only = v;
    return refresh();
  }

  /// `enabled`: true allow · false block · null follow the global switch.
  /// `methods`: list restricts, null follows the global list. Only keys in [body] are sent.
  Future<bool> save(int teacherId, Map<String, dynamic> body) async {
    final r = await call(() => api.put('$_base/payouts/teachers/$teacherId', body: body),
        ok: 'admin_saved'.tr);
    if (r != null) await refresh();
    return r != null;
  }
}

/// Global payout settings.
class AdminPayoutSettingsProvider extends AdminBase {
  Map<String, dynamic> data = {};
  String? error;

  bool get all => asBool(data['payouts_enabled_for_all']);
  bool get auto => asBool(data['payout_auto_enabled'], true);
  double? get minAmount => data['payout_min_amount'] == null ? null : asDouble(data['payout_min_amount']);
  double get defaultMin => asDouble(data['default_min_amount']);
  List<String> get allowed =>
      (data['payout_allowed_methods'] is List) ? (data['payout_allowed_methods'] as List).map((e) => '$e').toList() : [];
  List<Map<String, dynamic>> get methods => asMapList(data['methods']);

  Future<void> load() async {
    final r = await run(() => api.get('$_base/payouts/settings'));
    if (r is Map) {
      data = Map<String, dynamic>.from(r);
      error = null;
    } else {
      error = errorMessage ?? 'admin_could_not_load_data'.tr;
    }
    notifyListeners();
  }

  Future<bool> save(Map<String, dynamic> body) async {
    final r = await call(() => api.put('$_base/payouts/settings', body: body), ok: 'admin_saved'.tr);
    if (r is Map) {
      data = Map<String, dynamic>.from(r);
      notifyListeners();
    }
    return r != null;
  }
}


/// Number of withdrawal requests waiting for the admin (status = pending).
/// Feeds the badge on the dashboard "More" tab and on the payout tile —
/// same idea as the teacher's transfer-requests badge. Never throws and never
/// toasts: a failing badge must not break the dashboard.
class AdminPendingPayoutsProvider extends ChangeNotifier {
  AdminPendingPayoutsProvider({ApiClient? api}) : _api = api ?? ApiClient();
  final ApiClient _api;

  int count = 0;
  bool _disposed = false;

  Future<void> refresh() async {
    try {
      final r = await _api.get('$_base/withdrawals',
          queryParams: {'status': 'pending', 'skip': 0, 'limit': 1});
      if (_disposed || r is! Map) return;
      final n = (r['total'] != null ? asInt(r['total']) : asMapList(r['items']).length);
      if (n != count) {
        count = n;
        notifyListeners();
      }
    } catch (_) {
      // keep the last known number
    }
  }

  void clear() {
    count = 0;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}