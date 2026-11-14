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
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';

import 'package:flutter_education_app/features/profile/about/about_terms_model.dart';

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
  /// The APP language ('ar' | 'en').
  /// (AppConfig.lang, the same value the MaterialApp locale follows (core/app_locale.dart). That locale used to be
  /// English-only, which is why this never read Localizations.localeOf.)
  static String currentLang(BuildContext context) => AppConfig.lang == 'en' ? 'en' : 'ar';

  /// Language of the data currently held (empty = nothing loaded yet).
  String get aboutLang => _lastAboutLang;
  String get termsLang => _lastTermsLang;
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
        queryParams: {'lang': lang}, // the server resolves ar/en for us
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

  // ── Fetch Terms / Privacy (D-308) ─────────────────────────────────────────
  /// The terms of service: GET /api/v1/app-content/legal/terms (an older server without it: /terms).
  Future<void> loadTerms(BuildContext context, {bool forceRefresh = false}) async {
    final lang = currentLang(context);

    if (_terms != null && !forceRefresh && _lastTermsLang == lang) return;

    isLoadingTerms = true;
    termsError = null;
    notifyListeners();

    try {
      _terms = await _fetchLegal('terms', lang, fallback: '/api/v1/app-content/terms');
      _lastTermsLang = lang;
    } catch (e) {
      termsError = _loadError(lang);
      log('loadTerms ❌ $e');
    } finally {
      isLoadingTerms = false;
      notifyListeners();
    }
  }

  TermsPageModel? _privacy;
  bool isLoadingPrivacy = false;
  String? privacyError;
  String _lastPrivacyLang = '';

  TermsPageModel? get privacy => _privacy;
  String get privacyLang => _lastPrivacyLang;

  /// The privacy policy: GET /api/v1/app-content/legal/privacy (public: guests and the sign-in screens read it).
  Future<void> loadPrivacy(BuildContext context, {bool forceRefresh = false}) async {
    final lang = currentLang(context);
    if (_privacy != null && !forceRefresh && _lastPrivacyLang == lang) return;
    isLoadingPrivacy = true;
    privacyError = null;
    notifyListeners();
    try {
      _privacy = await _fetchLegal('privacy', lang);
      _lastPrivacyLang = lang;
    } catch (e) {
      privacyError = _loadError(lang);
      log('loadPrivacy ❌ $e');
    } finally {
      isLoadingPrivacy = false;
      notifyListeners();
    }
  }

  Future<TermsPageModel> _fetchLegal(String doc, String lang, {String? fallback}) async {
    try {
      final res = await _api.get('/api/v1/app-content/legal/$doc', queryParams: {'lang': lang});
      if (res is Map) return TermsPageModel.fromLegal(Map<String, dynamic>.from(res));
      throw const FormatException('legal: not an object');
    } on ApiException catch (e) {
      if (fallback == null || e.statusCode != 404) rethrow;
      final res = await _api.get(fallback, queryParams: {'lang': lang});
      if (res is Map) return TermsPageModel.fromJson(Map<String, dynamic>.from(res));
      throw const FormatException('terms: not an object');
    }
  }

  static String _loadError(String lang) =>
      lang == 'ar' ? 'تعذّر تحميل البيانات، حاول مرة أخرى' : 'Failed to load data, please try again';

  /// Call this when the user switches the in-app language so cached
  /// pages are invalidated and re-fetched with the new language.
  void onLanguageChanged() {
    _lastAboutLang = '';
    _lastTermsLang = '';
    _lastPrivacyLang = '';
    _about = null;
    _terms = null;
    _privacy = null;
    notifyListeners();
  }
}
