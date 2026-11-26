// lib/features/admin/admin_flags_settings_page.dart
//
// "Student review & read flags" — the bookmarks a student puts on exam questions to review later (review flags) and on
// lecture passages (read flags), NOT the app's feature flags (those are the Features page):
//   • allow review flags · allow read flags
//   • review-flag limit per exam / per course (0 = unlimited)
//   • teacher read-flag bank thresholds: students who failed × wrong tries per student
// GET / PUT /api/v1/admin/settings (the PUT carries the whole group; the same endpoint as the device limits, which
// this page leaves alone). It talks to the endpoint itself rather than through AdminSettingsProvider because that
// provider's save toast says "exam rules saved".
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'admin_common.dart' show asMap, t;
import 'admin_page.dart';
import 'cfg_common.dart';
import 'sup/sup_kit.dart';

const _settingsPath = '/api/v1/admin/settings';

class AdminFlagsSettingsPage extends StatefulWidget {
  const AdminFlagsSettingsPage({super.key});

  @override
  State<AdminFlagsSettingsPage> createState() => _AdminFlagsSettingsPageState();
}

class _AdminFlagsSettingsPageState extends State<AdminFlagsSettingsPage> {
  bool _allowReview = true;
  bool _allowRead = true;
  final _limitExam = TextEditingController();
  final _limitCourse = TextEditingController();
  final _minStudents = TextEditingController();
  final _minTries = TextEditingController();

  Map<String, Object> _saved = {}; // what the server holds
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _limitExam.dispose();
    _limitCourse.dispose();
    _minStudents.dispose();
    _minTries.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_saved.isNotEmpty && _dirty) {
      final ok = await appConfirm(context,
          message: t('لديك تعديلات لم تُحفظ. التحديث سيتجاهلها. متابعة؟', 'You have unsaved changes. Refreshing discards them. Continue?'));
      if (!ok || !mounted) return;
    }
    setState(() {
      _loading = _saved.isEmpty;
      _error = null;
    });
    try {
      final v = asMap(await ApiClient().get(_settingsPath));
      if (!mounted) return;
      _fill(v);
    } catch (e) {
      if (!mounted) return;
      final err = ApiException.from(e);
      // a failed refresh keeps the form that is on screen
      if (_saved.isNotEmpty) {
        showAppNotice(cfgErrorMessage(err), error: true);
      } else {
        _error = err;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _fill(Map<String, dynamic> v) {
    setState(() {
      _allowReview = v['allow_review_flags'] != false;
      _allowRead = v['allow_read_flags'] != false;
      _limitExam.text = '${(v['review_limit_per_exam'] as num?)?.toInt() ?? 0}';
      _limitCourse.text = '${(v['review_limit_per_course'] as num?)?.toInt() ?? 0}';
      _minStudents.text = '${(v['read_flag_teacher_min_students'] as num?)?.toInt() ?? 3}';
      _minTries.text = '${(v['read_flag_teacher_min_wrong_tries'] as num?)?.toInt() ?? 2}';
      _saved = _current();
    });
  }

  int? _n(TextEditingController c) => int.tryParse(c.text.trim());

  Map<String, Object> _current() => {
        'allow_review_flags': _allowReview,
        'allow_read_flags': _allowRead,
        'review_limit_per_exam': (_n(_limitExam) ?? 0).clamp(0, 100000),
        'review_limit_per_course': (_n(_limitCourse) ?? 0).clamp(0, 100000),
        'read_flag_teacher_min_students': (_n(_minStudents) ?? 3).clamp(1, 100000),
        'read_flag_teacher_min_wrong_tries': (_n(_minTries) ?? 2).clamp(1, 1000),
      };

  bool get _valid =>
      [(_limitExam, 0, 100000), (_limitCourse, 0, 100000), (_minStudents, 1, 100000), (_minTries, 1, 1000)]
          .every((f) => _numError(f.$1, f.$2, f.$3) == null);

  bool get _dirty {
    if (_saved.isEmpty) return false;
    final now = _current();
    for (final k in now.keys) {
      if (now[k] != _saved[k]) return true;
    }
    return false;
  }

  String? _numError(TextEditingController c, int min, int max) {
    final v = _n(c);
    if (v == null || v < min || v > max) {
      return t('أدخل رقماً صحيحاً بين $min و $max.', 'Enter a whole number from $min to $max.');
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving || !_valid) return;
    setState(() => _saving = true);
    try {
      final body = _current();
      final r = asMap(await ApiClient().put(_settingsPath, body: body));
      if (!mounted) return;
      setState(() => _saved = body);
      if (r.isNotEmpty) _fill({...r});
      showAppNotice(t('تم حفظ إعدادات علامات المراجعة والقراءة', 'Review & read flag settings saved'));
    } catch (e) {
      showAppNotice(cfgErrorMessage(ApiException.from(e)), error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return SupPage(
        kicker: 'a2_platform_kicker'.tr, headline: t('العلامات اللي يحطها الطالب عشان يرجع لها', 'The marks students set to come back to'),
        width: AppWidth.reading,
        title: t('علامات المراجعة والقراءة للطلاب', 'Student review & read flags'),
        onRefresh: _load,
        dirty: _dirty,
        body: _loading
          ? const AppListSkeleton()
          : _error != null
              ? cfgErrorState(_error, onRetry: _load)
              : ListView(
                  padding: AdminPage.bodyPadding(context),
                  children: [
                    AppSection(
                      title: 'admin_flags_students_section'.tr,
                      child: AppCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          AppSwitchTile(
                            icon: Icons.bookmark_rounded,
                            value: _allowReview,
                            onChanged: (v) => setState(() => _allowReview = v),
                            title: 'admin_flags_allow_review'.tr,
                          ),
                          AppSwitchTile(
                            icon: Icons.menu_book_rounded,
                            value: _allowRead,
                            onChanged: (v) => setState(() => _allowRead = v),
                            title: 'admin_flags_allow_read'.tr,
                          ),
                          const Divider(height: AppSpace.lg),
                          _NumRow(
                              controller: _limitExam,
                              label: 'admin_flags_limit_exam'.tr,
                              enabled: _allowReview,
                              min: 0,
                              max: 100000,
                              error: _allowReview ? _numError(_limitExam, 0, 100000) : null,
                              onChanged: () => setState(() {})),
                          _NumRow(
                              controller: _limitCourse,
                              label: 'admin_flags_limit_course'.tr,
                              enabled: _allowReview,
                              min: 0,
                              max: 100000,
                              error: _allowReview ? _numError(_limitCourse, 0, 100000) : null,
                              onChanged: () => setState(() {})),
                          Text('admin_flags_limit_hint'.tr, style: AppType.meta(context)),
                        ]),
                      ),
                    ),
                    AppSpace.gapLg,
                    AppSection(
                      title: 'admin_flags_teacher_section'.tr,
                      child: AppCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          _NumRow(
                              controller: _minStudents,
                              label: 'admin_flags_min_students'.tr,
                              enabled: _allowRead,
                              min: 1,
                              max: 100000,
                              error: _allowRead ? _numError(_minStudents, 1, 100000) : null,
                              onChanged: () => setState(() {})),
                          _NumRow(
                              controller: _minTries,
                              label: 'admin_flags_min_tries'.tr,
                              enabled: _allowRead,
                              min: 1,
                              max: 1000,
                              error: _allowRead ? _numError(_minTries, 1, 1000) : null,
                              onChanged: () => setState(() {})),
                          Text('admin_flags_teacher_hint'.tr, style: AppType.meta(context)),
                        ]),
                      ),
                    ),
                  ],
                ),
        actions: [cfgSaveButton(dirty: _dirty, enabled: _valid && _saved.isNotEmpty, busy: _saving, onSave: _save)],
      );
  }
}

/// A label, a typed number and the − / + helpers (48 px targets).
class _NumRow extends StatelessWidget {
  const _NumRow({
    required this.controller,
    required this.label,
    required this.enabled,
    required this.min,
    required this.max,
    required this.onChanged,
    this.error,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final int min, max;
  final VoidCallback onChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppNumberField(controller: controller, label: label, min: min, max: max, enabled: enabled, onChanged: (_) => onChanged()),
        if (error != null) CfgFieldError(error!),
      ]),
    );
  }
}
