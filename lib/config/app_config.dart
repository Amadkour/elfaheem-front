import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:timeago/timeago.dart' as timeago;

/// Application configuration and context.colors.
class AppConfig {
  static const String baseUrl =
      'https://nextbrain.site/api';
  static String lang = 'ar';
  static bool testMode = false;

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

  /// Bumped every time the disable list really changes. BasePage listens to it.
  static final ValueNotifier<int> disableListVersion = ValueNotifier<int>(0);

  /// Single entry point for replacing the list (push refresh, theme fetch…).
  /// Rebuilds every BasePage only if the content actually changed.
  /// Returns true if it changed.
  static bool setDisableList(Iterable<String> items) {
    final next = items.toList();
    debugPrint('[AppConfig] setDisableList old=$disableList new=$next');
    if (disableList.length == next.length &&
        disableList.toSet().containsAll(next)) {
      return false;
    }
    disableList = next;
    disableListVersion.value++;
    _rebuildWholeApp();
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

Map<String, dynamic> translation = {};

Future<void> readLanguage() async {
  final String response = await rootBundle.loadString(
    'assets/translation.json',
  );
  translation = await json.decode(response);
}

String translate(String key) {
  return translation[key]?[AppConfig.lang] ?? key;
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