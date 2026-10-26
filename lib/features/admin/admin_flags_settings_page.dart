// lib/features/admin/admin_flags_settings_page.dart
//
// Admin controls for review flags / read flags:
//   • allow review flags · allow read flags
//   • review-flag limit per exam / per course (0 = unlimited)
//   • teacher read-flag bank thresholds: students who failed × wrong tries per student
// Saves through the existing PUT /api/v1/admin/settings (AdminSettingsProvider).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:provider/provider.dart';

import '../../design/app_switch.dart';
import '../../utils/widget/base_page.dart';
import 'admin_providers.dart';

class AdminFlagsSettingsPage extends StatelessWidget {
  const AdminFlagsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => AdminSettingsProvider()..load(),
    child: const _View(),
  );
}

class _View extends StatefulWidget {
  const _View();

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  bool _allowReview = true;
  bool _allowRead = true;
  final _limitExam = TextEditingController();
  final _limitCourse = TextEditingController();
  final _minStudents = TextEditingController();
  final _minTries = TextEditingController();
  bool _filled = false;
  bool _saving = false;

  @override
  void dispose() {
    _limitExam.dispose();
    _limitCourse.dispose();
    _minStudents.dispose();
    _minTries.dispose();
    super.dispose();
  }

  void _fill(Map<String, dynamic> v) {
    _allowReview = v['allow_review_flags'] != false;
    _allowRead = v['allow_read_flags'] != false;
    _limitExam.text = '${(v['review_limit_per_exam'] as num?)?.toInt() ?? 0}';
    _limitCourse.text =
        '${(v['review_limit_per_course'] as num?)?.toInt() ?? 0}';
    _minStudents.text =
        '${(v['read_flag_teacher_min_students'] as num?)?.toInt() ?? 3}';
    _minTries.text =
        '${(v['read_flag_teacher_min_wrong_tries'] as num?)?.toInt() ?? 2}';
    _filled = true;
  }

  int _n(TextEditingController c, int fallback) =>
      int.tryParse(c.text.trim()) ?? fallback;

  Future<void> _save(AdminSettingsProvider p) async {
    setState(() => _saving = true);
    await p.save({
      'allow_review_flags': _allowReview,
      'allow_read_flags': _allowRead,
      'review_limit_per_exam': _n(_limitExam, 0),
      'review_limit_per_course': _n(_limitCourse, 0),
      'read_flag_teacher_min_students': _n(_minStudents, 3).clamp(1, 100000),
      'read_flag_teacher_min_wrong_tries': _n(_minTries, 2).clamp(1, 1000),
    });
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.watch<AdminSettingsProvider>();
    if (!_filled && p.values.isNotEmpty) _fill(p.values);

    return BasePage(
      useWebCard: true,
      maxWith: 1100,
      appBar: ScreenAppBar(title: 'admin_flags_title'.tr),
      child: p.isLoading && !_filled
            ? const Center(child: AppLoadingIndicator())
            : p.error != null && !_filled
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(p.error!),
                    const SizedBox(height: 10),
                    ElevatedButton(onPressed: p.load, child: Text('retry'.tr)),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                children: [
                  _Section(
                    title: 'admin_flags_students_section'.tr,
                    icon: Icons.bookmark_rounded,
                    children: [
                      AppSwitchTile(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        value: _allowReview,
                        onChanged: (v) => setState(() => _allowReview = v),
                        title: 'admin_flags_allow_review'.tr,
                      ),
                      AppSwitchTile(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        value: _allowRead,
                        onChanged: (v) => setState(() => _allowRead = v),
                        title: 'admin_flags_allow_read'.tr,
                      ),
                      _NumField(
                        controller: _limitExam,
                        label: 'admin_flags_limit_exam'.tr,
                        enabled: _allowReview,
                        minValue: 0,
                        maxValue: 100000,
                      ),
                      _NumField(
                        controller: _limitCourse,
                        label: 'admin_flags_limit_course'.tr,
                        enabled: _allowReview,
                        minValue: 0,
                        maxValue: 100000,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          'admin_flags_limit_hint'.tr,
                          style: TextStyle(
                            fontFamily: 'bahji',
                            fontSize: 12,
                            color: context.colors.textLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _Section(
                    title: 'admin_flags_teacher_section'.tr,
                    icon: Icons.flag_rounded,
                    children: [
                      _NumField(
                        controller: _minStudents,
                        label: 'admin_flags_min_students'.tr,
                        enabled: _allowRead,
                        minValue: 1,
                        maxValue: 100000,
                      ),
                      _NumField(
                        controller: _minTries,
                        label: 'admin_flags_min_tries'.tr,
                        enabled: _allowRead,
                        minValue: 1,
                        maxValue: 1000,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Text(
                          'admin_flags_teacher_hint'.tr,
                          style: TextStyle(
                            fontFamily: 'bahji',
                            fontSize: 12,
                            color: context.colors.textLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : () => _save(p),
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(
                        'admin_flags_save'.tr,
                        style: const TextStyle(
                          fontFamily: 'bahji',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                Icon(icon, color: c.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'bahji',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool enabled;
  final int minValue;
  final int maxValue;

  const _NumField({
    required this.controller,
    required this.label,
    required this.enabled,
    required this.minValue,
    required this.maxValue,
  });

  int get _value =>
      (int.tryParse(controller.text.trim()) ?? minValue).clamp(minValue, maxValue);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final value = _value;

    void update(int next) {
      final bounded = next.clamp(minValue, maxValue);
      controller.text = '$bounded';
      // Rebuild the counter after updating its controller value.
      (context as Element).markNeedsBuild();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: enabled ? c.cardBg : c.cardBg.withOpacity(0.55),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: enabled ? c.primary.withOpacity(0.22) : context.colors.textLight.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'bahji',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: enabled ? null : context.colors.textLight,
                ),
              ),
            ),
            const SizedBox(width: 12),
            _CounterButton(
              icon: Icons.remove_rounded,
              enabled: enabled && value > minValue,
              onTap: () => update(value - 1),
            ),
            Container(
              constraints: const BoxConstraints(minWidth: 58),
              margin: const EdgeInsets.symmetric(horizontal: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: enabled ? c.primary.withOpacity(0.09) : context.colors.textLight.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: enabled ? c.primary : context.colors.textLight,
                ),
              ),
            ),
            _CounterButton(
              icon: Icons.add_rounded,
              enabled: enabled && value < maxValue,
              onTap: () => update(value + 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _CounterButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _CounterButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = context.colors.primary;
    return Material(
      color: enabled ? primary : context.colors.textLight.withOpacity(0.12),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(11),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(
            icon,
            size: 20,
            color: enabled ? Colors.white : context.colors.textLight,
          ),
        ),
      ),
    );
  }
}
