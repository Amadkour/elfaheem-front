// ─────────────────────────────────────────────────────────────────────────────
// features/shared/about/about_terms_provider.dart
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

  // ── Getters ───────────────────────────────────────────────────────────────
  AboutPageModel? get about => _about;
  TermsPageModel? get terms => _terms;

  // ── Fetch About ───────────────────────────────────────────────────────────
  Future<void> loadAbout({bool forceRefresh = false}) async {
    if (_about != null && !forceRefresh) return; // already cached
    isLoadingAbout = true;
    aboutError = null;
    notifyListeners();

    try {
      final res = await _api.get('/api/v1/app-content/about');
      if (res != null && res is Map) {
        _about = AboutPageModel.fromJson(res as Map<String, dynamic>);
      }
    } catch (e) {
      aboutError = 'تعذّر تحميل البيانات، حاول مرة أخرى';
      log('loadAbout ❌ $e');
    } finally {
      isLoadingAbout = false;
      notifyListeners();
    }
  }

  // ── Fetch Terms ───────────────────────────────────────────────────────────
  Future<void> loadTerms({bool forceRefresh = false}) async {
    if (_terms != null && !forceRefresh) return; // already cached
    isLoadingTerms = true;
    termsError = null;
    notifyListeners();

    try {
      final res = await _api.get('/api/v1/app-content/terms');
      if (res != null && res is Map) {
        _terms = TermsPageModel.fromJson(res as Map<String, dynamic>);
      }
    } catch (e) {
      termsError = 'تعذّر تحميل البيانات، حاول مرة أخرى';
      log('loadTerms ❌ $e');
    } finally {
      isLoadingTerms = false;
      notifyListeners();
    }
  }
}
