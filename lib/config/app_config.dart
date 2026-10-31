import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/translation_source_stub.dart'
    if (dart.library.js_interop) 'package:flutter_education_app/config/translation_source_web.dart';
import 'package:timeago/timeago.dart' as timeago;

/// Application configuration and context.colors.
class AppConfig {
  /// The production API. Its leaf certificate is the one ApiClient pins on mobile.
  static const String productionBaseUrl = 'https://nextbrain.site/api';

  /// `--dart-define=API_BASE_URL=http://10.0.2.2:18080/api` points a debug/profile build at the local stack
  /// (back/scripts/dev/setup.*); without it every build talks to production. A release build accepts only an
  /// `https://` override (see [resolveApiBaseUrl]).
  static const String _baseUrlOverride = String.fromEnvironment('API_BASE_URL');
  static final String baseUrl = resolveApiBaseUrl(_baseUrlOverride, release: kReleaseMode);
  static String lang = 'ar';
  static bool testMode = !kReleaseMode; // request/response logging and debug helpers: never in release

  /// Feature kill-switch list. This default is the OFFLINE FALLBACK only —
  /// ThemeConfigProvider overwrites this with the server-side list (cached
  /// in SharedPreferences) right after GET /api/v1/theme/{platform} resolves.
  static List<String> disableList = [
    // 'profile.delete_account',
    // 'notifications'
    // 'profile.logout',
    // "profile.exit_group",
    // "teacher_tab_my_profile",
    // "teacher_tab_my_schedule",
    // "teacher_tab_analysis",
    // "teacher_home_stats",
    // "teacher_home_courses",
    // "teacher_home_schedule",
    // "teacher_home_add_course"
  ];

  /// Super-admin master switch for the whole Organizations feature set (point 7). When false the app behaves as
  /// a pure individual-courses app: no org dashboards, no mode switcher, no "create / join organization" flows.
  /// Set from the theme / platform-settings response (ThemeConfigProvider); true until the server says otherwise.
  static bool orgsEnabled = true;

  /// Notifies when [orgsEnabled] flips (the org gate screen and home tabs listen to it).
  static final ValueNotifier<bool> orgsEnabledNotifier = ValueNotifier<bool>(true);

  /// Feature keys of every organization ENTRY POINT. While organizations are switched off they are merged into
  /// the effective disable list, so each entry point disappears through the normal kill-switch mechanism.
  static const List<String> orgEntryKeys = [
    'register.organization', // "register an institution" on the login screen
    'student_home.org', // join / my organizations card on the student home
    'teacher_home_org', // same on the teacher home
    'home.org_tab', // "My organization" tab on the home screens (HomeTabsBar)
  ];

  /// Platform layer of the kill-switch (theme response / push refresh) and the open organization's layer
  /// (GET /org/orgs/{id}/context). The effective [disableList] = platform ∪ organization ∪ org entry points (when
  /// organizations are off). Super-admin OFF always wins: an organization can only ADD keys.
  static List<String> platformDisableList = [];
  static List<String> orgDisableList = [];

  /// Bumped every time the disable list really changes. BasePage listens to it.
  static final ValueNotifier<int> disableListVersion = ValueNotifier<int>(0);

  /// Single entry point for replacing the list (push refresh, theme fetch…). [items] is the PLATFORM list;
  /// pass [org] to also replace the open organization's list (an empty list clears it).
  /// Rebuilds every BasePage only if the effective content actually changed. Returns true if it changed.
  static bool setDisableList(Iterable<String> items, {Iterable<String>? org}) {
    platformDisableList = items.toList();
    if (org != null) orgDisableList = org.toList();
    final next = <String>{
      ...platformDisableList,
      ...orgDisableList,
      if (!orgsEnabled) ...orgEntryKeys,
    }.toList();
    debugPrint('[AppConfig] setDisableList old=$disableList new=$next');
    if (disableList.length == next.length && disableList.toSet().containsAll(next)) {
      return false;
    }
    disableList = next;
    disableListVersion.value++;
    _rebuildWholeApp();
    return true;
  }

  /// Replaces only the open organization's layer (null / empty = no organization open).
  static bool setOrgDisableList(Iterable<String>? org) =>
      setDisableList(platformDisableList, org: org ?? const <String>[]);

  /// Super-admin master switch. Re-applies the disable list (entry points) and rebuilds when it really flips.
  static bool setOrgsEnabled(bool enabled) {
    if (orgsEnabled == enabled) return false;
    orgsEnabled = enabled;
    orgsEnabledNotifier.value = enabled;
    if (!setDisableList(platformDisableList)) _rebuildWholeApp();
    return true;
  }

  /// Widgets that read [disableList] inside their own build (buttons, tabs,
  /// stat cards…) are NOT rebuilt by BasePage's listener, because Flutter
  /// skips children whose widget instance did not change. So after the list
  /// changes we mark every mounted element dirty. State and navigation are
  /// kept — it is the same thing a hot reload does. Rare event, cheap enough.
  static void _rebuildWholeApp() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return;
    void rebuild(Element el) {
      el.markNeedsBuild();
      el.visitChildren(rebuild);
    }
    try {
      rebuild(root);
    } catch (e) {
      debugPrint('[AppConfig] rebuild after disableList change failed: $e');
    }
  }
}

/// The API base URL a build uses for the `API_BASE_URL` [override] ('' = not set).
///
/// - No override (or blank) → production.
/// - Debug / profile builds take the override as given: the local gateway is plain `http://`.
/// - A release build takes it only when it is an `https://` URL with a host. Anything else (`http://`, a typo, a
///   bare host) falls back to production instead of shipping a cleartext or broken endpoint: plain HTTP is not
///   covered by certificate pinning, and the envelope handshake is unauthenticated, so passwords, tokens and MFA
///   codes would be readable on the path. Falling back (rather than refusing to start) was chosen because a
///   release build can only really work against production anyway (mobile pins production's certificate, so any
///   other host fails closed), and a refusing app would turn an operator's leftover dev variable into an outage
///   for every user of a web deploy. The release pipeline should reject such a value at build time as well.
String resolveApiBaseUrl(String override, {required bool release}) {
  final o = override.trim();
  if (o.isEmpty) return AppConfig.productionBaseUrl;
  if (!release) return o;
  final uri = Uri.tryParse(o);
  final ok = uri != null && uri.scheme == 'https' && o.toLowerCase().startsWith('https://') && uri.host.isNotEmpty;
  return ok ? o : AppConfig.productionBaseUrl;
}

Map<String, dynamic> translation = {};

Future<void> readLanguage() async {
  Map<String, dynamic>? fresh;
  try {
    // web: past the browser's HTTP cache (translation_source_web.dart); null elsewhere
    final text = await fetchFreshTranslations();
    if (text != null) fresh = json.decode(text) as Map<String, dynamic>;
  } catch (_) {}
  translation = fresh ?? json.decode(await rootBundle.loadString('assets/translation.json')) as Map<String, dynamic>;
  // The start-up waits for this with a timeout: when it lands after the app is on screen, redraw it so no page keeps
  // the raw keys it was built with.
  try {
    if (WidgetsBinding.instance.rootElement != null) AppConfig._rebuildWholeApp();
  } catch (_) {}
}

/// The text of [key] in the open language; when that one is missing or empty, the other language (better than a
/// raw key), and only then the key itself.
String translate(String key) {
  final e = translation[key];
  if (e is! Map) return key;
  final v = e[AppConfig.lang];
  if (v is String && v.isNotEmpty) return v;
  for (final other in const ['en', 'ar']) {
    final o = e[other];
    if (o is String && o.isNotEmpty) return o;
  }
  return key;
}

TextDirection get pageDirection {
  return AppConfig.lang == 'ar' ? TextDirection.rtl : TextDirection.ltr;
}

class LangProvider with ChangeNotifier {
  final StorageService _storage;

  LangProvider({required StorageService storage}) : _storage = storage {
    // Restore the user from disk immediately so role/isTeacher are ready
    // before the first frame is drawn — no async gap, no null user.
    _loadCachedLang();
  }

  void _loadCachedLang() {
    String? saved = _storage.loadLanguage;
    if (saved != null) {
      AppConfig.lang = saved;
    }
  }

  List<String> languages = ['ar', 'en'];

  Future<void> changeLang(String? newLang) async {
    AppConfig.lang = newLang ?? languages.first;
    await _storage.saveLanguage(AppConfig.lang);
    notifyListeners();
  }
}

extension Trans on String {
  String get tr => translate(this);
}

extension PageSize on BuildContext {
  double get width => MediaQuery.of(this).size.width;

  double get height => MediaQuery.of(this).size.height;
}

extension DateTimeAge on DateTime {
  String get age => timeago.format(this, locale: AppConfig.lang);
}