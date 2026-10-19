// lib/features/shared/data_lab/data_lab_certificates_sheet.dart
// Send a certificate to every student who passed.
//   1. pick the certificate of the course
//   2. pick the column that decides "passed" (e.g. the calculated Final) and the pass mark in %
//   3. see how many students reached it, then send by notification, e-mail or both
// If lines are selected in the sheet, only those are considered.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show toast, showAdminSheet, SheetHeader;

import 'data_lab_api.dart';
import 'data_lab_models.dart';
import 'data_lab_provider.dart';
import 'data_lab_widgets.dart';

Future<void> showCertificatesSheet(BuildContext context, DataLabProvider p) =>
    showAdminSheet(context, (_) => _CertSheet(p: p));

class _CertSheet extends StatefulWidget {
  const _CertSheet({required this.p});

  final DataLabProvider p;

  @override
  State<_CertSheet> createState() => _CertSheetState();
}

class _CertSheetState extends State<_CertSheet> {
  final _api = DataLabApi();
  List<Map<String, dynamic>> _certs = [];
  int? _certId;
  String? _column;
  double _mark = 50;
  String _delivery = 'notification';
  Map<String, dynamic>? _plan;
  bool _loading = true, _busy = false, _checking = false;

  DataLabProvider get p => widget.p;
  List<DlColumn> get _numeric => p.columns.where((c) => c.isNumber && c.source != 'read_flags' && c.source != 'review_flags').toList();

  @override
  void initState() {
    super.initState();
    final calc = _numeric.where((c) => c.isCalculated).toList();
    _column = (calc.isNotEmpty ? calc.last : _numeric.firstOrNull)?.key;
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _api.certificates(p.courseId);
      if (!mounted) return;
      setState(() {
        _certs = items;
        _certId = items.isEmpty ? null : (items.first['id'] as num).toInt();
      });
      await _check();
    } catch (e) {
      toast(e is ApiException ? e.message : '$e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _check() async {
    if (_certId == null || _column == null) return;
    setState(() => _checking = true);
    try {
      final r = await _api.sendCertificates(p.courseId,
          certificateId: _certId!,
          columnKey: _column!,
          minPercent: _mark,
          delivery: _delivery,
          rowIds: p.selected.isEmpty ? null : p.selected.toList(),
          dryRun: true);
      if (mounted) setState(() => _plan = r);
    } catch (e) {
      if (mounted) setState(() => _plan = null);
      toast(e is ApiException ? e.message : '$e', error: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      final r = await _api.sendCertificates(p.courseId,
          certificateId: _certId!,
          columnKey: _column!,
          minPercent: _mark,
          delivery: _delivery,
          rowIds: p.selected.isEmpty ? null : p.selected.toList(),
          dryRun: false);
      toast('${r['queued'] ?? 0} ${'dl_cert_queued'.tr}');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      toast(e is ApiException ? e.message : '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final eligible = (_plan?['eligible'] as num?)?.toInt() ?? 0;
    final already = (_plan?['already_issued'] as num?)?.toInt() ?? 0;
    final emailOk = p.config.allowEmailExport;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SheetHeader('dl_certificates'.tr),
      Flexible(
        child: _loading
            ? const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            : ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('dl_cert_explain'.tr, style: dlText(12.5, c: c.textMedium, h: 1.55)),
            if (_certs.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: DlCard(child: Row(children: [
                  Icon(Icons.info_outline_rounded, color: c.warning),
                  const SizedBox(width: 10),
                  Expanded(child: Text('dl_cert_none'.tr, style: dlText(13, c: c.textDark, h: 1.5))),
                ])),
              )
            else ...[
              DlSectionTitle('dl_cert_which'.tr),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final ct in _certs)
                  DlChoiceChip(
                    label: '${ct['title']}',
                    icon: Icons.workspace_premium_rounded,
                    selected: _certId == (ct['id'] as num).toInt(),
                    onTap: () {
                      setState(() => _certId = (ct['id'] as num).toInt());
                      _check();
                    },
                  ),
              ]),
              DlSectionTitle('dl_cert_passed_by'.tr, subtitle: 'dl_cert_passed_by_sub'.tr),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final col in _numeric)
                  DlChoiceChip(
                    label: col.label,
                    icon: col.isCalculated ? Icons.functions_rounded : null,
                    selected: _column == col.key,
                    onTap: () {
                      setState(() => _column = col.key);
                      _check();
                    },
                  ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Text('${'dl_cert_pass_mark'.tr}: ${_mark.round()}%', style: dlText(13.5, w: FontWeight.w800, c: c.textDark))),
              ]),
              Slider(
                value: _mark,
                min: 0,
                max: 100,
                divisions: 20,
                activeColor: c.primary,
                label: '${_mark.round()}%',
                onChanged: (v) => setState(() => _mark = v),
                onChangeEnd: (_) => _check(),
              ),
              DlCard(
                padding: const EdgeInsets.all(14),
                child: _checking
                    ? const Center(child: Padding(padding: EdgeInsets.all(6), child: CircularProgressIndicator(strokeWidth: 2.4)))
                    : Row(children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: c.success.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: Center(child: Text('$eligible', style: dlText(20, w: FontWeight.w800, c: c.success))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('dl_cert_reached'.tr, style: dlText(13.5, w: FontWeight.w800, c: c.textDark)),
                      Text(
                        [
                          if (p.selected.isNotEmpty) '${'dl_exp_only'.tr} ${p.selected.length}',
                          if (already > 0) '$already ${'dl_cert_already'.tr}',
                          if ((_plan?['preview'] as List?)?.isNotEmpty == true) (_plan!['preview'] as List).take(3).join('، '),
                        ].join(' · '),
                        style: dlText(11.5, c: c.textMedium, h: 1.4),
                      ),
                    ]),
                  ),
                ]),
              ),
              DlSectionTitle('dl_cert_how'.tr),
              Wrap(spacing: 8, runSpacing: 8, children: [
                DlChoiceChip(label: 'dl_cert_notification'.tr, icon: Icons.notifications_active_rounded, selected: _delivery == 'notification', onTap: () => setState(() => _delivery = 'notification')),
                if (emailOk) DlChoiceChip(label: 'dl_cert_email'.tr, icon: Icons.mail_rounded, selected: _delivery == 'email', onTap: () => setState(() => _delivery = 'email')),
                if (emailOk) DlChoiceChip(label: 'dl_cert_both'.tr, icon: Icons.done_all_rounded, selected: _delivery == 'both', onTap: () => setState(() => _delivery = 'both')),
              ]),
              const SizedBox(height: 6),
              Text('dl_cert_note'.tr, style: dlText(11.5, c: c.textLight, h: 1.5)),
              const SizedBox(height: 18),
              DlPrimaryButton(
                label: '${'dl_cert_send'.tr} ($eligible)',
                icon: Icons.workspace_premium_rounded,
                busy: _busy,
                onPressed: eligible > 0 && !_checking ? _send : null,
              ),
            ],
          ],
        ),
      ),
    ]);
  }
}
