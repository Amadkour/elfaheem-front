// ─────────────────────────────────────────────────────────────────────────────
// features/shared/about/about_terms_provider.dart  (v2 – bilingual)
// ─────────────────────────────────────────────────────────────────────────────
//
// Sends  Accept-Language: ar  or  Accept-Language: en  on every request so
// the server returns already-localised strings.
//
// AppLocale is resolved from your existing localisation setup.
// Swap the import / call to match whatever you use (Get.locale, etc.).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';

import 'about_terms_model.dart';

class AboutTermsProvider extends BaseProvider {
  AboutTermsProvider({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  // ── State ─────────────────────────────────────────────────────────────────
  AboutPageModel? _about;
  TermsPageModel? _terms;

  bool isLoadingAbout = false;
  bool isLoadingTerms = false;
  String? aboutError;
  String? termsError;

  // Track which language was last loaded so we re-fetch on language change
  String _lastAboutLang = '';
  String _lastTermsLang = '';

  // ── Getters ───────────────────────────────────────────────────────────────
  AboutPageModel? get about => _about;

  TermsPageModel? get terms => _terms;

  // ── Language helper ───────────────────────────────────────────────────────
  /// Returns 'ar' or 'en' based on the current device locale.
  static String currentLang(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return locale.languageCode == 'en' ? 'en' : 'ar';
  }
 void clear(){
    int length=(_terms?.sections.length)??0;
    for(int i=0;i<length;i++){
      _terms?.sections[i].accept=false;
    }
    notifyListeners();
 }
  // ── Fetch About ───────────────────────────────────────────────────────────
  Future<void> loadAbout(BuildContext context,
      {bool forceRefresh = false}) async {
    final lang = currentLang(context);

    // Skip if already loaded for this language and not forced
    if (_about != null && !forceRefresh && _lastAboutLang == lang) return;

    isLoadingAbout = true;
    aboutError = null;
    notifyListeners();

    try {
      final res = await _api.get(
        '/api/v1/app-content/about',
      );
      if (res != null && res is Map) {
        _about = AboutPageModel.fromJson(res as Map<String, dynamic>);
        _lastAboutLang = lang;
      }
    } catch (e) {
      aboutError = lang == 'ar'
          ? 'تعذّر تحميل البيانات، حاول مرة أخرى'
          : 'Failed to load data, please try again';
      log('loadAbout ❌ $e');
    } finally {
      isLoadingAbout = false;
      notifyListeners();
    }
  }

  void clearSelection() {
    if (terms == null) {
      for (int i = 0; i < terms!.sections.length; i++) {
        terms!.sections[i].toggle();
      }
    }
    notifyListeners();
  }

  // ── Fetch Terms ───────────────────────────────────────────────────────────
  Future<void> loadTerms(BuildContext context,
      {bool forceRefresh = false}) async {
    final lang = currentLang(context);

    if (_terms != null && !forceRefresh && _lastTermsLang == lang) return;

    isLoadingTerms = true;
    termsError = null;
    notifyListeners();

    try {
      final res = await _api.get(
        '/api/v1/app-content/terms',
      );
      if (res != null && res is Map) {
        _terms = TermsPageModel.fromJson(res as Map<String, dynamic>);
        _lastTermsLang = lang;
      }
    } catch (e) {
      termsError = lang == 'ar'
          ? 'تعذّر تحميل البيانات، حاول مرة أخرى'
          : 'Failed to load data, please try again';
      log('loadTerms ❌ $e');
    } finally {
      isLoadingTerms = false;
      notifyListeners();
    }
  }

  /// Call this when the user switches the in-app language so cached
  /// pages are invalidated and re-fetched with the new language.
  void onLanguageChanged() {
    _lastAboutLang = '';
    _lastTermsLang = '';
    _about = null;
    _terms = null;
    notifyListeners();
  }
}
