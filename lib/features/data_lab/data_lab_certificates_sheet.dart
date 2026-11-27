// lib/features/data_lab/data_lab_certificates_sheet.dart
// Send a certificate to every student who passed.
//   1. pick the certificate of the course
//   2. pick the column that decides "passed" (e.g. the calculated Final) and the pass mark in %
//   3. see how many students reached it, then send by notification, e-mail or both
// If lines are selected in the sheet, only those are considered.
// Students who already hold this certificate are skipped unless "send again" is switched on.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show toast, showAdminSheet, SheetHeader;

import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_api.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_models.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_provider.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_widgets.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton;

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
  late double _mark = p.config.passPercent.clamp(0, 100).toDouble();
  String _delivery = 'notification';
  Map<String, dynamic>? _plan;
  bool _loading = true, _busy = false, _checking = false, _resend = false;
  int _checkGen = 0;

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
      toast(apiErrorText(ApiException.from(e)), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Asks the server how many students would receive it. Only the latest answer is kept (the slider fires often).
  Future<void> _check() async {
    if (_certId == null || _column == null) return;
    final gen = ++_checkGen;
    setState(() => _checking = true);
    try {
      final r = await _api.sendCertificates(p.courseId,
          certificateId: _certId!,
          columnKey: _column!,
          minPercent: _mark,
          delivery: _delivery,
          rowIds: p.selected.isEmpty ? null : p.selected.toList(),
          resend: _resend,
          dryRun: true);
      if (mounted && gen == _checkGen) setState(() => _plan = r);
    } catch (e) {
      if (mounted && gen == _checkGen) setState(() => _plan = null);
      toast(apiErrorText(ApiException.from(e)), error: true);
    } finally {
      if (mounted && gen == _checkGen) setState(() => _checking = false);
    }
  }

  void _nudge(double d) {
    setState(() => _mark = (_mark + d).clamp(0, 100).roundToDouble());
    _check();
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
          resend: _resend,
          dryRun: false);
      toast('${r['queued'] ?? 0} ${'dl_cert_queued'.tr}');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      toast(apiErrorText(ApiException.from(e)), error: true);
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
            ? const AppListSkeleton(items: 4, withAvatar: false)
            : ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, AppSpace.lg, 24),
          children: [
            Text('dl_cert_explain'.tr, style: AppType.meta(context).copyWith(color: c.textMedium)),
            if (_certs.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: DlCard(child: Row(children: [
                  Icon(Icons.info_outline_rounded, color: c.warning),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(child: Text('dl_cert_none'.tr, style: AppType.label(context).copyWith(color: c.textDark))),
                ])),
              )
            else ...[
              DlSectionTitle('dl_cert_which'.tr),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
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
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
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
              const SizedBox(height: AppSpace.sm),
              Row(children: [
                Expanded(child: Text('${'dl_cert_pass_mark'.tr}: ${_mark.round()}%', style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark))),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: AppConfig.lang == 'ar' ? 'إنقاص' : 'Decrease',
                  onPressed: _mark <= 0 ? null : () => _nudge(-1),
                  icon: Icon(Icons.remove_circle_outline_rounded, color: c.textMedium),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: AppConfig.lang == 'ar' ? 'زيادة' : 'Increase',
                  onPressed: _mark >= 100 ? null : () => _nudge(1),
                  icon: Icon(Icons.add_circle_outline_rounded, color: c.textMedium),
                ),
              ]),
              Slider(
                value: _mark,
                min: 0,
                max: 100,
                divisions: 100,
                activeColor: c.primary,
                label: '${_mark.round()}%',
                onChanged: (v) => setState(() => _mark = v),
                onChangeEnd: (_) => _check(),
              ),
              DlCard(
                padding: const EdgeInsets.all(AppSpace.md),
                child: _checking
                    ? const Center(child: Padding(padding: EdgeInsets.all(AppSpace.xs), child: CircularProgressIndicator(strokeWidth: 2.4)))
                    : Row(children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: c.success.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: Center(child: Text('$eligible', style: AppType.pageTitle(context).copyWith(color: c.success))),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('dl_cert_reached'.tr, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
                      Text(
                        [
                          if (p.selected.isNotEmpty) '${'dl_exp_only'.tr} ${p.selected.length}',
                          if (already > 0) '$already ${'dl_cert_already'.tr}',
                          if ((_plan?['preview'] as List?)?.isNotEmpty == true) (_plan!['preview'] as List).take(3).join((AppConfig.lang == 'ar' ? '، ' : ', ')),
                        ].join(' · '),
                        style: AppType.meta(context).copyWith(color: c.textMedium),
                      ),
                    ]),
                  ),
                ]),
              ),
              if (already > 0) ...[
                const SizedBox(height: AppSpace.sm),
                Container(
                  padding: const EdgeInsetsDirectional.fromSTEB(14, AppSpace.xs, AppSpace.xs, 6),
                  decoration: BoxDecoration(
                    color: c.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: c.warning.withValues(alpha: 0.25)),
                  ),
                  child: Row(children: [
                    Icon(Icons.replay_rounded, color: c.warning, size: 20),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        _resend
                            ? dlTr('dl_cert_resend_on', 'They will receive it again (the same certificate, not a new one).')
                            : '$already ${dlTr('dl_cert_resend_off', 'already have it and will be skipped. Switch on to send it again.')}',
                        style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark),
                      ),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    AppSwitch(
                      value: _resend,
                      activeColor: c.warning,
                      onChanged: (v) {
                        setState(() => _resend = v);
                        _check();
                      },
                    ),
                  ]),
                ),
              ],
              DlSectionTitle('dl_cert_how'.tr),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                DlChoiceChip(label: 'dl_cert_notification'.tr, icon: Icons.notifications_active_rounded, selected: _delivery == 'notification', onTap: () => setState(() => _delivery = 'notification')),
                if (emailOk) DlChoiceChip(label: 'dl_cert_email'.tr, icon: Icons.mail_rounded, selected: _delivery == 'email', onTap: () => setState(() => _delivery = 'email')),
                if (emailOk) DlChoiceChip(label: 'dl_cert_both'.tr, icon: Icons.done_all_rounded, selected: _delivery == 'both', onTap: () => setState(() => _delivery = 'both')),
              ]),
              const SizedBox(height: AppSpace.xs),
              Text('dl_cert_note'.tr, style: AppType.meta(context).copyWith(color: c.textLight)),
              const SizedBox(height: AppSpace.md),
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
