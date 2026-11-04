// lib/features/admin/admin_data_lab_page.dart
// Admin: what teachers and students may do in the Data Lab, and per-course on/off.
// Register it as a service tile (admin_services_hub.dart) → AdminDataLabPage().
//
// Every switch saves on tap (PUT /admin/data-lab/settings with the one changed key). Saves are serialized and a
// failure puts back only the keys of THAT save, so quick taps can never restore a stale snapshot.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../teacher/data_lab/data_lab_api.dart';
import '../teacher/data_lab/data_lab_models.dart';
import 'admin_common.dart' show t;
import 'admin_page.dart';
import 'cfg_common.dart';

class AdminDataLabPage extends StatefulWidget {
  const AdminDataLabPage({super.key});

  @override
  State<AdminDataLabPage> createState() => _AdminDataLabPageState();
}

class _AdminDataLabPageState extends State<AdminDataLabPage> {
  final _api = DataLabApi();
  Map<String, dynamic> _s = {};
  bool _loaded = false;
  List<Map<String, dynamic>> _courses = [];
  int _coursesTotal = 0;
  bool _loading = true, _loadingCourses = false;
  Object? _error, _coursesError;
  String _search = '';
  int _coursesToken = 0; // a newer request supersedes an older one (typing while a page loads)
  final Set<Object> _busyCourses = {};
  Future<void> _saveChain = Future.value();
  int _pendingSaves = 0;
  DateTime? _loadedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool keep = false}) async {
    if (!keep || !_loaded) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final s = await _api.adminSettings();
      if (!mounted) return;
      _s = s;
      _loaded = true;
      _loadedAt = DateTime.now();
      await _loadCourses(reset: true);
    } catch (e) {
      if (!mounted) return;
      if (_loaded) {
        showAppNotice(cfgErrorMessage(ApiException.from(e)), error: true);
      } else {
        _error = ApiException.from(e);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Never throws: a failure is shown in the courses list (with Retry); the rows already loaded stay.
  Future<void> _loadCourses({bool reset = false}) async {
    final token = ++_coursesToken;
    setState(() {
      _loadingCourses = true;
      _coursesError = null;
    });
    try {
      final r = await _api.adminCourses(search: _search, skip: reset ? 0 : _courses.length);
      final items = dlList(r['items']);
      if (!mounted || token != _coursesToken) return;
      setState(() {
        _courses = reset ? items : [..._courses, ...items];
        _coursesTotal = (r['total'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      if (mounted && token == _coursesToken) setState(() => _coursesError = ApiException.from(e));
    } finally {
      if (mounted && token == _coursesToken) setState(() => _loadingCourses = false);
    }
  }

  /// Optimistic, serialized save of the keys in [patch]. A failure restores those keys only (and only when nothing
  /// newer changed them meanwhile).
  Future<void> _save(Map<String, dynamic> patch) {
    final before = {for (final k in patch.keys) k: _s[k]};
    setState(() {
      _s = {..._s, ...patch};
      _pendingSaves++;
    });
    return _saveChain = _saveChain.then((_) async {
      try {
        final saved = await _api.adminSave(patch);
        if (!mounted) return;
        setState(() {
          _pendingSaves--;
          // the server's answer is only taken when no other save is waiting behind this one
          if (_pendingSaves == 0) _s = {...saved, 'stats': _s['stats']};
        });
        showAppNotice('dl_saved'.tr);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _pendingSaves--;
          for (final k in patch.keys) {
            if (_s[k] == patch[k]) _s = {..._s, k: before[k]};
          }
        });
        showAppNotice(cfgErrorMessage(ApiException.from(e)), error: true);
      }
    });
  }

  bool _b(String k) => _s[k] != false;

  Future<void> _masterSwitch(bool v) async {
    if (!v) {
      final ok = await appConfirm(context,
          danger: true,
          confirmLabel: t('إيقاف', 'Switch off'),
          message: t('إيقاف معمل البيانات لكل المعلمين والطلاب في كل الكورسات؟ لا تُحذف أي بيانات وتعود عند إعادة التفعيل.',
              'Switch the Data Lab off for every teacher and student in every course? No data is deleted and it comes back when you switch it on again.'));
      if (!ok || !mounted) return;
    }
    _save({'enabled': v});
  }

  Future<void> _switchCourse(Map<String, dynamic> co, bool v) async {
    final id = co['id'];
    if (id == null || !_busyCourses.add(id)) return;
    setState(() => co['enabled'] = v);
    try {
      await _api.adminSwitchCourse((id as num).toInt(), v);
    } catch (e) {
      if (mounted) setState(() => co['enabled'] = !v);
      showAppNotice(cfgErrorMessage(ApiException.from(e)), error: true);
    }
    if (mounted) setState(() => _busyCourses.remove(id));
  }

  Widget _tile(IconData icon, String title, String sub, String key, {bool master = false}) => AppSwitchTile(
        icon: icon,
        title: title,
        subtitle: sub,
        value: _b(key),
        onChanged: master ? _masterSwitch : (v) => _save({key: v}),
      );

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      title: 'dl_admin_title'.tr,
      subtitle: 'dl_admin_sub'.tr,
      icon: Icons.science_rounded,
      onRefresh: () => _load(keep: true),
      updatedAt: _loadedAt,
      body: _loading && !_loaded
          ? const AppListSkeleton()
          : _error != null && !_loaded
              ? cfgErrorState(_error, onRetry: _load)
              : _content(context),
    );
  }

  Widget _content(BuildContext context) {
    final stats = dlMap(_s['stats']);
    final formats = ((_s['export_formats'] as List?) ?? const ['xlsx']).map((e) => '$e').toList();
    return AppRefresh(
      onRefresh: () => _load(keep: true),
      child: ListView(
        padding: AdminPage.bodyPadding(context),
        children: [
          AppKpiGrid(maxColumns: 3, children: [
            AppKpiCard(icon: Icons.menu_book_rounded, value: '${stats['courses_with_data'] ?? 0}', label: 'dl_admin_stat_courses'.tr),
            AppKpiCard(icon: Icons.add_chart_rounded, value: '${stats['custom_columns'] ?? 0}', label: 'dl_admin_stat_columns'.tr),
            AppKpiCard(icon: Icons.mark_chat_unread_rounded, value: '${stats['open_requests'] ?? 0}', label: 'dl_admin_stat_requests'.tr),
          ]),
          AppSpace.gapMd,
          AppCard(
              child: _tile(Icons.power_settings_new_rounded, 'dl_admin_enabled'.tr, 'dl_admin_enabled_sub'.tr, 'enabled', master: true)),
          AppSpace.gapLg,
          AppSection(
            title: 'dl_admin_teachers'.tr,
            child: AppCard(
              child: Column(children: [
                _tile(Icons.upload_file_rounded, 'dl_admin_import'.tr, 'dl_admin_import_sub'.tr, 'allow_import'),
                _tile(Icons.person_add_alt_1_rounded, 'dl_admin_accounts'.tr, 'dl_admin_accounts_sub'.tr, 'allow_create_accounts'),
                _tile(Icons.ios_share_rounded, 'dl_admin_export'.tr, 'dl_admin_export_sub'.tr, 'allow_export'),
                _tile(Icons.forward_to_inbox_rounded, 'dl_admin_email'.tr, 'dl_admin_email_sub'.tr, 'allow_email_export'),
                _tile(Icons.workspace_premium_rounded, 'dl_admin_certificates'.tr, 'dl_admin_certificates_sub'.tr, 'allow_certificates'),
                _tile(Icons.mark_chat_unread_rounded, 'dl_admin_requests'.tr, 'dl_admin_requests_sub'.tr, 'allow_student_requests'),
              ]),
            ),
          ),
          AppSpace.gapLg,
          AppSection(
            title: 'dl_admin_students'.tr,
            child: AppCard(child: _tile(Icons.insights_rounded, 'dl_admin_student_view'.tr, 'dl_admin_student_view_sub'.tr, 'student_view')),
          ),
          AppSpace.gapLg,
          AppSection(
            title: 'dl_admin_limits'.tr,
            child: AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _LimitRow(
                    key: ValueKey('max_import_rows:${_s['max_import_rows']}'),
                    label: 'dl_admin_max_rows'.tr,
                    value: (_s['max_import_rows'] as num?)?.toInt() ?? 2000,
                    min: 100,
                    max: 20000,
                    step: 100,
                    onChanged: (v) => _save({'max_import_rows': v})),
                const Divider(height: AppSpace.lg),
                _LimitRow(
                    key: ValueKey('max_custom_columns:${_s['max_custom_columns']}'),
                    label: 'dl_admin_max_cols'.tr,
                    value: (_s['max_custom_columns'] as num?)?.toInt() ?? 30,
                    min: 1,
                    max: 200,
                    step: 5,
                    onChanged: (v) => _save({'max_custom_columns': v})),
                const Divider(height: AppSpace.lg),
                Text('dl_admin_formats'.tr, style: AppType.label(context)),
                AppSpace.gapXs,
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                  for (final f in const ['xlsx', 'csv', 'pdf'])
                    AppChoiceChip(
                      label: f == 'xlsx' ? 'Excel' : f.toUpperCase(),
                      selected: formats.contains(f),
                      onTap: () {
                        final next = formats.contains(f) ? formats.where((x) => x != f).toList() : [...formats, f];
                        if (next.isEmpty) {
                          showAppNotice('dl_admin_one_format'.tr, error: true);
                          return;
                        }
                        _save({'export_formats': next});
                      },
                    ),
                ]),
              ]),
            ),
          ),
          AppSpace.gapLg,
          AppSection(
            title: 'dl_admin_courses'.tr,
            subtitle: 'dl_admin_courses_sub'.tr,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppSearchField(
                hint: 'search_course_hint'.tr,
                // '' (the clear button, or the text deleted) arrives immediately and reloads the full list
                onChanged: (v) {
                  _search = v;
                  _loadCourses(reset: true);
                },
              ),
              AppSpace.gapSm,
              if (_coursesError != null && _courses.isEmpty)
                AppCard(child: AppErrorState(compact: true, message: cfgErrorMessage(_coursesError), onRetry: () => _loadCourses(reset: true)))
              else if (_courses.isEmpty && !_loadingCourses)
                AppEmpty(icon: Icons.search_off_rounded, title: t('لا توجد كورسات', 'No courses'))
              else
                AppCard(
                  child: Column(children: [
                    for (final co in _courses)
                      AppSwitchTile(
                        icon: Icons.menu_book_rounded,
                        title: '${co['title']}',
                        subtitle: '${co['columns'] ?? 0} ${'dl_admin_stat_columns'.tr}',
                        value: co['enabled'] != false,
                        onChanged: _busyCourses.contains(co['id']) ? null : (v) => _switchCourse(co, v),
                      ),
                    if (_coursesError != null)
                      AppErrorState(compact: true, message: cfgErrorMessage(_coursesError), onRetry: () => _loadCourses()),
                    if (_courses.length < _coursesTotal && _coursesError == null)
                      Center(
                        child: AppButton.ghost(
                          label: 'dl_load_more'.tr,
                          busy: _loadingCourses,
                          onPressed: _loadingCourses ? null : () => _loadCourses(),
                        ),
                      ),
                  ]),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// A limit: − / + steps AND a typed number (committed on Enter or when the field loses focus).
class _LimitRow extends StatefulWidget {
  const _LimitRow({super.key, required this.label, required this.value, required this.min, required this.max, required this.step, required this.onChanged});

  final String label;
  final int value, min, max, step;
  final ValueChanged<int> onChanged;

  @override
  State<_LimitRow> createState() => _LimitRowState();
}

class _LimitRowState extends State<_LimitRow> {
  late final TextEditingController _ctl = TextEditingController(text: '${widget.value}');
  String? _error;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _commit() {
    final v = int.tryParse(_ctl.text.trim());
    if (v == null || v < widget.min || v > widget.max) {
      setState(() => _error = t('أدخل رقماً بين ${widget.min} و ${widget.max}.', 'Enter a number from ${widget.min} to ${widget.max}.'));
      return;
    }
    setState(() => _error = null);
    if (v != widget.value) widget.onChanged(v);
  }

  void _step(int d) {
    final cur = int.tryParse(_ctl.text.trim()) ?? widget.value;
    final next = (cur + d).clamp(widget.min, widget.max);
    _ctl.text = '$next';
    setState(() => _error = null);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final cur = int.tryParse(_ctl.text.trim()) ?? widget.value;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.label, style: AppType.label(context)),
      AppSpace.gapXs,
      Row(children: [
        AppIconButton(icon: Icons.remove_rounded, tooltip: t('تقليل', 'Decrease'), onPressed: cur - widget.step < widget.min ? null : () => _step(-widget.step)),
        AppSpace.gapXs,
        Expanded(
          child: Focus(
            onFocusChange: (has) {
              if (!has) _commit();
            },
            child: AppField(
              controller: _ctl,
              label: t('القيمة', 'Value'),
              keyboard: TextInputType.number,
              ltr: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _commit(),
            ),
          ),
        ),
        AppSpace.gapXs,
        AppIconButton(icon: Icons.add_rounded, tooltip: t('زيادة', 'Increase'), onPressed: cur + widget.step > widget.max ? null : () => _step(widget.step)),
      ]),
      if (_error != null) CfgFieldError(_error!),
    ]);
  }
}
