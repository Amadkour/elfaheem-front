// lib/features/admin/admin_data_lab_page.dart
// Admin: what teachers and students may do in the Data Lab, and per-course on/off.
// Register it as a service tile (admin_services_hub.dart) → AdminDataLabPage().
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart';
import '../../teacher/data_lab/data_lab_api.dart';
import '../../teacher/data_lab/data_lab_models.dart';
import '../../teacher/data_lab/data_lab_widgets.dart';

class AdminDataLabPage extends StatefulWidget {
  const AdminDataLabPage({super.key});

  @override
  State<AdminDataLabPage> createState() => _AdminDataLabPageState();
}

class _AdminDataLabPageState extends State<AdminDataLabPage> {
  final _api = DataLabApi();
  Map<String, dynamic> _s = {};
  List<Map<String, dynamic>> _courses = [];
  int _coursesTotal = 0;
  bool _loading = true, _loadingCourses = false;
  String? _error;
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _err(Object e) => e is ApiException ? e.message : '$e';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _s = await _api.adminSettings();
      await _loadCourses(reset: true);
    } catch (e) {
      _error = _err(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCourses({bool reset = false}) async {
    if (_loadingCourses) return;
    setState(() => _loadingCourses = true);
    try {
      final r = await _api.adminCourses(search: _search, skip: reset ? 0 : _courses.length);
      final items = dlList(r['items']);
      if (!mounted) return;
      setState(() {
        _courses = reset ? items : [..._courses, ...items];
        _coursesTotal = (r['total'] as num?)?.toInt() ?? 0;
      });
    } finally {
      if (mounted) setState(() => _loadingCourses = false);
    }
  }

  Future<void> _save(Map<String, dynamic> patch) async {
    final before = Map<String, dynamic>.from(_s);
    setState(() => _s = {..._s, ...patch}); // optimistic
    try {
      final saved = await _api.adminSave(patch);
      if (mounted) setState(() => _s = {...saved, 'stats': before['stats']});
      toast('dl_saved'.tr);
    } catch (e) {
      if (mounted) setState(() => _s = before);
      toast(_err(e), error: true);
    }
  }

  bool _b(String k) => _s[k] != false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget body;
    if (_loading) {
      body = const Center(child: AppLoadingIndicator());
    } else if (_error != null) {
      body = ErrorRetry(message: _error!, onRetry: _load);
    } else {
      final stats = dlMap(_s['stats']);
      final formats = ((_s['export_formats'] as List?) ?? const ['xlsx']).map((e) => '$e').toList();
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 60),
          children: [
            DlHero(
              title: 'dl_admin_title'.tr,
              subtitle: 'dl_admin_sub'.tr,
              icon: Icons.science_rounded,
              stats: [
                DlHeroStat(icon: Icons.menu_book_rounded, value: '${stats['courses_with_data'] ?? 0}', label: 'dl_admin_stat_courses'.tr),
                DlHeroStat(icon: Icons.add_chart_rounded, value: '${stats['custom_columns'] ?? 0}', label: 'dl_admin_stat_columns'.tr),
                DlHeroStat(icon: Icons.mark_chat_unread_rounded, value: '${stats['open_requests'] ?? 0}', label: 'dl_admin_stat_requests'.tr),
              ],
            ),
            _Switch(Icons.power_settings_new_rounded, 'dl_admin_enabled'.tr, 'dl_admin_enabled_sub'.tr, _b('enabled'), c.danger, (v) => _save({'enabled': v})),
            DlSectionTitle('dl_admin_teachers'.tr),
            _Switch(Icons.upload_file_rounded, 'dl_admin_import'.tr, 'dl_admin_import_sub'.tr, _b('allow_import'), c.primary, (v) => _save({'allow_import': v})),
            _Switch(Icons.person_add_alt_1_rounded, 'dl_admin_accounts'.tr, 'dl_admin_accounts_sub'.tr, _b('allow_create_accounts'), c.primary, (v) => _save({'allow_create_accounts': v})),
            _Switch(Icons.ios_share_rounded, 'dl_admin_export'.tr, 'dl_admin_export_sub'.tr, _b('allow_export'), c.success, (v) => _save({'allow_export': v})),
            _Switch(Icons.forward_to_inbox_rounded, 'dl_admin_email'.tr, 'dl_admin_email_sub'.tr, _b('allow_email_export'), c.success, (v) => _save({'allow_email_export': v})),
            _Switch(Icons.workspace_premium_rounded, 'dl_admin_certificates'.tr, 'dl_admin_certificates_sub'.tr, _b('allow_certificates'), c.warning, (v) => _save({'allow_certificates': v})),
            _Switch(Icons.mark_chat_unread_rounded, 'dl_admin_requests'.tr, 'dl_admin_requests_sub'.tr, _b('allow_student_requests'), c.warning, (v) => _save({'allow_student_requests': v})),
            DlSectionTitle('dl_admin_students'.tr),
            _Switch(Icons.insights_rounded, 'dl_admin_student_view'.tr, 'dl_admin_student_view_sub'.tr, _b('student_view'), c.purple, (v) => _save({'student_view': v})),
            DlSectionTitle('dl_admin_limits'.tr),
            DlCard(
              child: Column(children: [
                _Stepper('dl_admin_max_rows'.tr, (_s['max_import_rows'] as num?)?.toInt() ?? 2000, 100, 20000, 100, (v) => _save({'max_import_rows': v})),
                Divider(color: c.divider, height: 22),
                _Stepper('dl_admin_max_cols'.tr, (_s['max_custom_columns'] as num?)?.toInt() ?? 30, 1, 200, 5, (v) => _save({'max_custom_columns': v})),
                Divider(color: c.divider, height: 22),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('dl_admin_formats'.tr, style: dlText(13, w: FontWeight.w700, c: c.textDark)),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Wrap(spacing: 8, children: [
                    for (final f in const ['xlsx', 'csv', 'pdf'])
                      DlChoiceChip(
                        label: f == 'xlsx' ? 'Excel' : f.toUpperCase(),
                        selected: formats.contains(f),
                        onTap: () {
                          final next = formats.contains(f) ? (formats.where((x) => x != f).toList()) : [...formats, f];
                          if (next.isEmpty) return toast('dl_admin_one_format'.tr, error: true);
                          _save({'export_formats': next});
                        },
                      ),
                  ]),
                ),
              ]),
            ),
            DlSectionTitle('dl_admin_courses'.tr, subtitle: 'dl_admin_courses_sub'.tr),
            TextField(
              controller: _searchCtrl,
              onSubmitted: (v) {
                _search = v;
                _loadCourses(reset: true);
              },
              style: dlText(14, c: c.textDark),
              decoration: InputDecoration(
                hintText: 'search_course_hint'.tr,
                prefixIcon: Icon(Icons.search_rounded, color: c.textMedium),
                filled: true,
                fillColor: c.cardBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.divider)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.divider)),
              ),
            ),
            const SizedBox(height: 10),
            for (final co in _courses)
              _Switch(
                Icons.menu_book_rounded,
                '${co['title']}',
                '${co['columns'] ?? 0} ${'dl_admin_stat_columns'.tr}',
                co['enabled'] != false,
                c.primary,
                    (v) async {
                  setState(() => co['enabled'] = v);
                  try {
                    await _api.adminSwitchCourse((co['id'] as num).toInt(), v);
                  } catch (e) {
                    setState(() => co['enabled'] = !v);
                    toast(_err(e), error: true);
                  }
                },
              ),
            if (_courses.length < _coursesTotal)
              Center(
                child: TextButton(
                  onPressed: _loadingCourses ? null : _loadCourses,
                  child: Text(_loadingCourses ? '...' : 'dl_load_more'.tr),
                ),
              ),
          ],
        ),
      );
    }
    return BasePage(
      useWebCard: true,
      appBar: ScreenAppBar(title: 'dl_admin_title'.tr),
      child: body,
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch(this.icon, this.title, this.sub, this.value, this.color, this.onChanged);

  final IconData icon;
  final String title, sub;
  final bool value;
  final Color color;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DlCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 8, 10),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(13.5, w: FontWeight.w800, c: c.textDark)),
            Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: dlText(11.5, c: c.textMedium, h: 1.35)),
          ]),
        ),
        const SizedBox(width: 8),
        AppSwitch(value: value, activeColor: color, onChanged: onChanged, semanticLabel: title),
        const SizedBox(width: 4),
      ]),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper(this.label, this.value, this.min, this.max, this.step, this.onChanged);

  final String label;
  final int value, min, max, step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      Expanded(child: Text(label, style: dlText(13, w: FontWeight.w700, c: c.textDark))),
      IconButton(
        style: IconButton.styleFrom(backgroundColor: c.inputBg),
        onPressed: value - step < min ? null : () => onChanged(value - step),
        icon: const Icon(Icons.remove_rounded),
      ),
      SizedBox(width: 62, child: Text('$value', textAlign: TextAlign.center, style: dlText(15, w: FontWeight.w800, c: c.primary))),
      IconButton(
        style: IconButton.styleFrom(backgroundColor: c.inputBg),
        onPressed: value + step > max ? null : () => onChanged(value + step),
        icon: const Icon(Icons.add_rounded),
      ),
    ]);
  }
}
