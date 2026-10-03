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

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';

import 'admin_common.dart';
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

abstract class AdminPagedProvider extends AdminBase {
  final List<Map<String, dynamic>> rows = [];
  int page = 0;
  int pages = 1;
  int total = 0;
  bool loadingMore = false;
  bool loaded = false;
  String? error;
  Map<String, dynamic> extra = {};

  String get path;
  Map<String, dynamic> get filters;

  bool get hasMore => page < pages;

  Future<void> refresh() async {
    rows.clear();
    page = 0;
    pages = 1;
    total = 0;
    loaded = false;
    error = null;
    await _fetch(1);
  }

  Future<void> loadMore() async {
    if (loadingMore || isLoading || !hasMore) return;
    await _fetch(page + 1);
  }

  Future<void> _fetch(int p) async {
    if (p > 1) {
      loadingMore = true;
      notifyListeners();
    }
    final query = <String, dynamic>{
      for (final e in filters.entries)
        if (e.value != null && '${e.value}'.isNotEmpty) e.key: e.value,
      'page': p,
      'size': 20,
    };
    final r = await run(() => api.get(path, queryParams: query),
        makLoading: p == 1);
    if (r is Map) {
      final d = PageData(Map<String, dynamic>.from(r));
      rows.addAll(d.items);
      page = d.page;
      pages = d.pages;
      total = d.total;
      extra = d.extra;
      error = null;
    } else if (p == 1) {
      error = errorMessage ?? t('تعذر تحميل البيانات', 'Could not load data');
    }
    loaded = true;
    loadingMore = false;
    notifyListeners();
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
      error = errorMessage ?? t('تعذر تحميل البيانات', 'Could not load data');
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

  String search = '';
  String? status; // active | inactive | pending_deletion
  bool? subscribed;

  @override
  String get path => '$_base/users';

  @override
  Map<String, dynamic> get filters => {
        'role': role,
        'search': search,
        'status': status,
        'subscribed': subscribed,
      };

  List<AdminUser> get users => rows.map(AdminUser.new).toList();

  Future<void> setSearch(String v) {
    search = v;
    return refresh();
  }

  Future<void> setStatus(String? v) {
    status = v;
    return refresh();
  }

  Future<void> setSubscribed(bool? v) {
    subscribed = v;
    return refresh();
  }

  Future<UserDetail?> detail(int id) async {
    final r = await run(() => api.get('$_base/users/$id'), makLoading: false);
    return r is Map ? UserDetail(Map<String, dynamic>.from(r)) : null;
  }

  Future<bool> create(Map<String, dynamic> body) async {
    final r = await call(() => api.post('$_base/users', body: body),
        ok: t('تمت الإضافة', 'Created'));
    if (r != null) await refresh();
    return r != null;
  }

  Future<bool> update(int id, Map<String, dynamic> body) async {
    final r = await call(() => api.put('$_base/users/$id', body: body),
        ok: t('تم الحفظ', 'Saved'));
    if (r != null) await refresh();
    return r != null;
  }

  Future<bool> setActive(int id, bool active) => update(id, {'is_active': active});

  Future<bool> remove(int id) async {
    final r = await call(() => api.delete('$_base/users/$id'),
        ok: t('تم الحذف', 'Deleted'));
    if (r != null) await refresh();
    return r != null;
  }

  Future<bool> resetDevices(int id) async =>
      await call(() => api.post('$_base/users/$id/reset-devices'),
          ok: t('تمت إعادة ضبط الأجهزة', 'Devices reset')) !=
      null;

  Future<bool> removeDevice(int userId, int rowId) async =>
      await call(() => api.delete('$_base/users/$userId/devices/$rowId'),
          ok: t('تم حذف الجهاز', 'Device removed')) !=
      null;

  Future<bool> enroll(int userId, int courseId) async {
    final r = await call(
        () => api.post('$_base/users/$userId/enroll', body: {'course_id': courseId}),
        ok: t('تم التسجيل في الكورس', 'Enrolled'));
    if (r != null) await refresh();
    return r != null;
  }

  Future<bool> unenroll(int userId, int courseId) async {
    final r = await call(() => api.delete('$_base/users/$userId/enrollments/$courseId'),
        ok: t('تم إلغاء التسجيل', 'Removed from course'));
    if (r != null) await refresh();
    return r != null;
  }

  Future<bool> grant(int userId, {String? planCode, int? days}) async {
    final r = await call(
        () => api.post('$_base/users/$userId/subscription/grant', body: {
              'plan_code': ?planCode,
              'days': ?days,
            }),
        ok: t('تم منح الاشتراك', 'Subscription granted'));
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
  String search = '';
  bool? published;
  String? status;
  int? teacherId;

  @override
  String get path => '$_base/courses';

  @override
  Map<String, dynamic> get filters => {
        'search': search,
        'published': published,
        'status': status,
        'teacher_id': teacherId,
      };

  List<AdminCourse> get courses => rows.map(AdminCourse.new).toList();
  double get totalIncome => asDouble(asMap(extra['totals'])['income']);

  Future<void> setSearch(String v) {
    search = v;
    return refresh();
  }

  Future<void> setPublished(bool? v) {
    published = v;
    return refresh();
  }

  Future<void> setStatus(String? v) {
    status = v;
    return refresh();
  }

  Future<AdminCourse?> detail(int id) async {
    final r = await run(() => api.get('$_base/courses/$id'), makLoading: false);
    return r is Map ? AdminCourse(Map<String, dynamic>.from(r)) : null;
  }

  Future<bool> create(Map<String, dynamic> body) async {
    final r = await call(() => api.post('$_base/courses', body: body),
        ok: t('تمت إضافة الكورس', 'Course created'));
    if (r != null) await refresh();
    return r != null;
  }

  Future<bool> update(int id, Map<String, dynamic> body) async {
    final r = await call(() => api.put('$_base/courses/$id', body: body),
        ok: t('تم الحفظ', 'Saved'));
    if (r != null) await refresh();
    return r != null;
  }

  Future<bool> remove(int id, {bool force = false}) async {
    final r = await call(
        () => api.delete('$_base/courses/$id', queryParams: {'force': force}),
        ok: t('تم حذف الكورس', 'Course deleted'));
    if (r != null) await refresh();
    return r != null;
  }

  /// `body` keys are sent as-is, so `{'payment_provider': null}` RESETS that
  /// field to the system default while omitted keys stay untouched.
  Future<bool> savePaymentSettings(int id, Map<String, dynamic> body) async {
    final r = await call(
        () => api.put('$_base/courses/$id/payment-settings', body: body),
        ok: t('تم حفظ إعدادات الدفع', 'Payment settings saved'));
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

class AdminCategoriesProvider extends AdminBase {
  List<AdminCategory> items = [];
  String? error;

  Future<void> load() async {
    final r = await run(() => api.get('$_base/categories'));
    if (r is Map) {
      items = asMapList(r['items']).map(AdminCategory.new).toList();
      error = null;
    } else {
      error = errorMessage ?? t('تعذر تحميل البيانات', 'Could not load data');
    }
    notifyListeners();
  }

  Future<bool> save({int? id, required Map<String, dynamic> body}) async {
    final r = await call(
        () => id == null
            ? api.post('$_base/categories', body: body)
            : api.put('$_base/categories/$id', body: body),
        ok: t('تم الحفظ', 'Saved'));
    if (r != null) await load();
    return r != null;
  }

  Future<bool> remove(int id) async {
    final r = await call(() => api.delete('$_base/categories/$id'),
        ok: t('تم الحذف', 'Deleted'));
    if (r != null) await load();
    return r != null;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Subscriptions (switch + plans + requests)
// ═════════════════════════════════════════════════════════════════════════════

class AdminSubscriptionsProvider extends AdminPagedProvider {
  String? statusFilter = 'pending';
  String search = '';

  bool required = false;
  List<Plan> plans = [];
  bool settingsLoaded = false;

  @override
  String get path => '$_base/subscriptions';

  @override
  Map<String, dynamic> get filters => {'status': statusFilter, 'search': search};

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

  Future<void> setStatusFilter(String? v) {
    statusFilter = v;
    return refresh();
  }

  Future<void> setSearch(String v) {
    search = v;
    return refresh();
  }

  Future<bool> setRequired(bool v) async {
    final r = await call(
        () => api.put('$_base/settings', body: {'subscription_required': v}),
        ok: v
            ? t('تم تفعيل الاشتراك الإجباري', 'Subscription is now required')
            : t('التطبيق الآن مجاني', 'The app is now free'));
    if (r != null) {
      required = v;
      notifyListeners();
    }
    return r != null;
  }

  Future<bool> savePlan(String code, Map<String, dynamic> body) async {
    final r = await call(() => api.put('$_base/subscription-plans/$code', body: body),
        ok: t('تم حفظ الخطة', 'Plan saved'));
    if (r != null) await loadPlans();
    return r != null;
  }

  Future<bool> approve(int id) async {
    final r = await call(() => api.post('$_base/subscriptions/$id/approve'),
        ok: t('تم قبول الاشتراك', 'Approved'));
    if (r != null) await refresh();
    return r != null;
  }

  Future<bool> reject(int id, String? reason) async {
    final r = await call(
        () => api.post('$_base/subscriptions/$id/reject', body: {'reason': reason}),
        ok: t('تم رفض الطلب', 'Rejected'));
    if (r != null) await refresh();
    return r != null;
  }

  Future<bool> cancel(int id) async {
    final r = await call(() => api.post('$_base/subscriptions/$id/cancel'),
        ok: t('تم إلغاء الاشتراك', 'Cancelled'));
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
  int get switchDays => asInt(values['device_switch_days'], 30);
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
      error = errorMessage ?? t('تعذر تحميل البيانات', 'Could not load data');
    }
    notifyListeners();
  }

  Future<bool> save(Map<String, dynamic> body) async {
    final r = await call(() => api.put('$_base/settings', body: body),
        ok: t('تم حفظ الإعدادات', 'Settings saved'));
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
      error = errorMessage ?? t('تعذر تحميل البيانات', 'Could not load data');
    }
    notifyListeners();
  }

  Future<bool> save(String method, Map<String, dynamic> body) async {
    final r = await call(() => api.put('$_base/payment-methods/$method', body: body),
        ok: t('تم الحفظ', 'Saved'));
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
      error = errorMessage ?? t('تعذر تحميل البيانات', 'Could not load data');
    }
    notifyListeners();
  }

  /// Activates a preset for every platform (or just [platforms]).
  Future<bool> activate(int id, {List<String>? platforms}) async {
    final r = await call(
        () => api.post('$_base/themes/$id/activate',
            body: {'platforms': platforms}),
        ok: t('تم تفعيل الثيم — سيظهر للمستخدمين عند فتح التطبيق',
            'Theme activated — users get it on next app start'));
    if (r is Map) _apply(r);
    return r != null;
  }

  Future<bool> save({int? id, required String nameAr, required String nameEn, required Map<String, String> colors}) async {
    final body = {'name_ar': nameAr, 'name_en': nameEn, 'colors': colors};
    final r = await call(
        () => id == null
            ? api.post('$_base/themes', body: body)
            : api.put('$_base/themes/$id', body: body),
        ok: t('تم حفظ الثيم', 'Theme saved'));
    if (r != null) await load();
    return r != null;
  }

  Future<bool> remove(int id) async {
    final r = await call(() => api.delete('$_base/themes/$id'),
        ok: t('تم حذف الثيم', 'Theme deleted'));
    if (r != null) await load();
    return r != null;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Features (hide / unhide)
// ═════════════════════════════════════════════════════════════════════════════

class AdminFeaturesProvider extends AdminBase {
  List<FeatureItem> items = [];
  List<String> platforms = ['android', 'ios', 'web'];
  String? error;

  Future<void> load() async {
    final r = await run(() => api.get('$_base/features'));
    _apply(r);
  }

  void _apply(dynamic r) {
    if (r is Map) {
      items = asMapList(r['items']).map(FeatureItem.new).toList();
      if (r['platforms'] is List) {
        platforms = (r['platforms'] as List).map((e) => '$e').toList();
      }
      error = null;
    } else {
      error = errorMessage ?? t('تعذر تحميل البيانات', 'Could not load data');
    }
    notifyListeners();
  }

  Future<void> set(String key, bool hidden, {List<String>? platforms}) async {
    final r = await call(() => api.put('$_base/features/$key',
        body: {'hidden': hidden, 'platforms': platforms}));
    if (r is Map) _apply(r);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  App versions (existing /app/* endpoints, now admin-only for writes)
// ═════════════════════════════════════════════════════════════════════════════

class AdminVersionsProvider extends AdminBase {
  List<Map<String, dynamic>> items = [];
  String? error;

  Future<void> load() async {
    final r = await run(() => api.get('/app/'));
    if (r is List) {
      items = asMapList(r);
      error = null;
    } else {
      error = errorMessage ?? t('تعذر تحميل البيانات', 'Could not load data');
    }
    notifyListeners();
  }

  Future<bool> create(Map<String, dynamic> body) async {
    final r = await call(() => api.post('/app/', body: body),
        ok: t('تم نشر الإصدار', 'Version published'));
    if (r != null) await load();
    return r != null;
  }

  Future<bool> update(int id, Map<String, dynamic> body) async {
    final r = await call(() => api.patch('/app/$id', body: body),
        ok: t('تم الحفظ', 'Saved'));
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
        ok: t('تم الحذف', 'Deleted'));
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
      error = errorMessage ?? t('تعذر تحميل البيانات', 'Could not load data');
    }
    if (about is Map) {
      aboutInfo = about['info'] is Map ? asMap(about['info']) : null;
    }
    notifyListeners();
  }

  Future<bool> saveMeta(Map<String, dynamic> body) async {
    final r = await call(() => api.patch('$_content/terms/meta', body: body),
        ok: t('تم الحفظ', 'Saved'));
    if (r != null) await load();
    return r != null;
  }

  Future<bool> saveSection({int? id, required Map<String, dynamic> body}) async {
    final r = await call(
        () => id == null
            ? api.post('$_content/terms/sections', body: body)
            : api.patch('$_content/terms/sections/$id', body: body),
        ok: t('تم الحفظ', 'Saved'));
    if (r != null) await load();
    return r != null;
  }

  Future<bool> deleteSection(int id) async {
    final r = await call(() => api.delete('$_content/terms/sections/$id'),
        ok: t('تم الحذف', 'Deleted'));
    if (r != null) await load();
    return r != null;
  }

  Future<bool> saveAbout(Map<String, dynamic> body) async {
    final r = await call(() => api.patch('$_content/about/info', body: body),
        ok: t('تم الحفظ', 'Saved'));
    if (r != null) await load();
    return r != null;
  }
}
