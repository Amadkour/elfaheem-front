// lib/features/admin/consoles/admin_demand_page.dart
//
// The super admin's "Teacher demand" console (redesign WP, docs/redesign/api/demand.md §2): the three numbers behind
// the public "students waiting for a teacher" counts, and a recompute of today's snapshot now.
//   GET|PUT /api/v1/admin/teacher-demand/settings   {threshold 1–100, group_min 1–50, stale_days 1–30}
//   POST    /api/v1/admin/teacher-demand/recompute  → {day, rows}
// Kill switch `admin.teacher_demand`. The PUT always sends the three numbers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart' show Trans;
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../admin_common.dart' show trp;
import '../cfg_common.dart';
import '../sup/sup_kit.dart';
import 'console_parts.dart';

const kAdminTeacherDemandKey = 'admin.teacher_demand';

class AdminTeacherDemandPage extends StatefulWidget {
  const AdminTeacherDemandPage({super.key});

  @override
  State<AdminTeacherDemandPage> createState() => _AdminTeacherDemandPageState();
}

class _AdminTeacherDemandPageState extends State<AdminTeacherDemandPage> {
  final _api = ApiClient();
  final _threshold = TextEditingController();
  final _groupMin = TextEditingController();
  final _stale = TextEditingController();
  Map<String, dynamic>? _data;
  Object? _error;
  bool _saving = false;
  bool _recomputing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _threshold.dispose();
    _groupMin.dispose();
    _stale.dispose();
    super.dispose();
  }

  void _take(Map<String, dynamic> d) {
    _data = d;
    _threshold.text = cNumText(d['threshold']);
    _groupMin.text = cNumText(d['group_min']);
    _stale.text = cNumText(d['stale_days']);
  }

  bool get _dirty {
    final d = _data;
    if (d == null) return false;
    return _threshold.text.trim() != cNumText(d['threshold']) ||
        _groupMin.text.trim() != cNumText(d['group_min']) ||
        _stale.text.trim() != cNumText(d['stale_days']);
  }

  Future<void> _load() async {
    try {
      final r = cMap(await _api.get('/api/v1/admin/teacher-demand/settings'));
      if (!mounted) return;
      setState(() {
        _take(r);
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (_data == null) {
        setState(() => _error = e);
      } else {
        showAppNotice(cfgErrorMessage(e), error: true);
      }
    }
  }

  Future<void> _save() async {
    final th = cInt(_threshold.text), gm = cInt(_groupMin.text), st = cInt(_stale.text);
    if (th == null || th < 1 || th > 100 || gm == null || gm < 1 || gm > 50 || st == null || st < 1 || st > 30) {
      showAppNotice('a2_dm_invalid'.tr, error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final r = cMap(await _api.put('/api/v1/admin/teacher-demand/settings',
          body: {'threshold': th, 'group_min': gm, 'stale_days': st}));
      if (!mounted) return;
      setState(() => _take({..._data ?? {}, ...r}));
      showAppNotice('a2_saved'.tr);
    } catch (e) {
      showAppNotice(cfgErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _recompute() async {
    setState(() => _recomputing = true);
    try {
      final r = cMap(await _api.post('/api/v1/admin/teacher-demand/recompute'));
      showAppNotice(trp('a2_dm_recomputed', {'rows': '${cInt(r['rows']) ?? 0}'}));
      await _load();
    } catch (e) {
      showAppNotice(cfgErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _recomputing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final last = cStr(d?['last_day']);
    return SupPage(
      pageKey: const ValueKey(kAdminTeacherDemandKey),
      title: 'a2_dm_title'.tr,
      kicker: 'a2_dm_kicker'.tr,
      headline: 'a2_dm_head'.tr,
      line: last.isEmpty ? 'a2_dm_never'.tr : trp('a2_dm_last', {'day': last}),
      onRefresh: _load,
      dirty: _dirty,
      width: AppWidth.form,
      actions: [
        if (d != null) cfgSaveButton(dirty: _dirty, busy: _saving, onSave: _save),
        if (d != null)
          SupHeroButton(label: 'a2_dm_recompute'.tr, icon: Icons.refresh_rounded, busy: _recomputing, onTap: _recompute),
      ],
      body: _error != null && d == null
          ? cfgErrorState(_error, onRetry: _load)
          : d == null
              ? const AppListSkeleton(items: 3, withAvatar: false)
              : ListView(padding: SupPage.bodyPadding(context), children: [
                  SupCard(
                    title: 'a2_dm_numbers'.tr,
                    subtitle: 'a2_dm_numbers_d'.tr,
                    icon: Icons.tune_rounded,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      ConsoleNumberField(
                          controller: _threshold,
                          label: 'a2_dm_threshold'.tr,
                          helper: 'a2_dm_threshold_d'.tr,
                          onChanged: (_) => setState(() {})),
                      ConsoleNumberField(
                          controller: _groupMin,
                          label: 'a2_dm_group_min'.tr,
                          helper: 'a2_dm_group_min_d'.tr,
                          onChanged: (_) => setState(() {})),
                      ConsoleNumberField(
                          controller: _stale,
                          label: 'a2_dm_stale'.tr,
                          helper: 'a2_dm_stale_d'.tr,
                          onChanged: (_) => setState(() {})),
                    ]),
                  ),
                ]),
    );
  }
}
