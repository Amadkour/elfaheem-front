// lib/features/admin/admin_fee_rates.dart  (NEW FILE)
//
// Admin control of the gateway fee of EVERY payment method:
//   mada · visa · mastercard · apple_pay · creditcard (hosted checkout) · instapay · bank_transfer
// Each has a percent and a fixed amount (charged once per payment).
//   GET /api/v1/admin/fees              list
//   PUT /api/v1/admin/fees/{method}     {percent?, fixed?} or {reset: true}
//
// Drop <AdminFeeRatesSection/> anywhere under a ChangeNotifierProvider<AdminFeeRatesProvider>
// (admin_system_page.dart does exactly that).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../core/api_client.dart';
import '../../core/base_provider.dart';
import '../../utils/widget/primary_button.dart';
import '../student/enrollment/enrollment_models.dart' show asJsonMap;
import 'admin_common.dart';

class AdminFeeRatesProvider extends BaseProvider {
  AdminFeeRatesProvider({ApiClient? api}) : api = api ?? ApiClient();
  final ApiClient api;

  List<Map<String, dynamic>> items = [];
  double vatPercent = 0;
  bool loaded = false;

  Future<void> load() async {
    final json = asJsonMap(await run(() async => api.get('/api/v1/admin/fees')));
    if (json == null) {
      notifyListeners();
      return;
    }
    items = [
      for (final raw in (json['items'] as List? ?? const []))
        Map<String, dynamic>.from(raw as Map),
    ];
    vatPercent = (json['vat_percent'] as num?)?.toDouble() ?? 0;
    loaded = true;
    notifyListeners();
  }

  /// Saves one method. Pass [reset] to go back to the built-in default.
  Future<bool> save(String method, {double? percent, double? fixed, bool reset = false}) async {
    final json = asJsonMap(await run(() async => api.put(
      '/api/v1/admin/fees/$method',
      body: {
        if (percent != null) 'percent': percent,
        if (fixed != null) 'fixed': fixed,
        if (reset) 'reset': true,
      },
    )));
    if (json == null) {
      notifyListeners();
      return false;
    }
    final i = items.indexWhere((e) => e['method'] == method);
    if (i >= 0) items[i] = json;
    notifyListeners();
    return true;
  }
}

class AdminFeeRatesSection extends StatelessWidget {
  const AdminFeeRatesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminFeeRatesProvider>();
    final c = context.colors;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('admin_fee_rates'.tr,
          style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w900, fontSize: 16, color: c.textDark)),
      const SizedBox(height: 4),
      Text('admin_fee_rates_hint'.tr,
          style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textLight)),
      const SizedBox(height: 8),
      if (!p.loaded && p.isLoading)
        const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
      else if (!p.loaded)
        ErrorRetry(message: p.errorMessage ?? 'admin_could_not_load'.tr, onRetry: p.load)
      else ...[
          for (final m in p.items) _FeeRateCard(m),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Text('${'admin_vat_note'.tr}: ${p.vatPercent.toStringAsFixed(p.vatPercent.truncateToDouble() == p.vatPercent ? 0 : 2)}%',
                style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textLight)),
          ),
        ],
    ]);
  }
}

String _num(Object? v) {
  final d = (v as num?)?.toDouble() ?? 0;
  return d.truncateToDouble() == d ? d.toStringAsFixed(0) : d.toString();
}

class _FeeRateCard extends StatelessWidget {
  const _FeeRateCard(this.m);
  final Map<String, dynamic> m;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.read<AdminFeeRatesProvider>();
    final isCustom = m['is_default'] != true;
    final title = asStr(AppConfig.lang == 'ar' ? m['label_ar'] : m['label_en']);

    return Section(
      title: title,
      trailing: isCustom
          ? Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('admin_fee_custom'.tr,
            style: TextStyle(fontFamily: 'tajawal', fontSize: 11, color: Colors.amber.shade800)),
      )
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        KeyValue('admin_fee_percent'.tr, '${_num(m['percent'])}%'),
        KeyValue('admin_fee_fixed'.tr, _num(m['fixed'])),
        if (m['group'] == 'manual')
          Text('admin_fee_manual_note'.tr,
              style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textLight)),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: Text('admin_edit_details'.tr),
            onPressed: () => showAdminSheet(context, (_) => _FeeEditSheet(provider: p, m: m, title: title)),
          ),
        ),
      ]),
    );
  }
}

/// The edit sheet owns its text controllers and disposes them in State.dispose, i.e. only once the
/// sheet has fully left the screen. (Disposing them when the route future completes — as soon as it is
/// popped — crashes: the sheet still rebuilds during its closing animation, e.g. when the keyboard hides.)
class _FeeEditSheet extends StatefulWidget {
  const _FeeEditSheet({required this.provider, required this.m, required this.title});
  final AdminFeeRatesProvider provider;
  final Map<String, dynamic> m;
  final String title;

  @override
  State<_FeeEditSheet> createState() => _FeeEditSheetState();
}

class _FeeEditSheetState extends State<_FeeEditSheet> {
  late final TextEditingController _percent = TextEditingController(text: _num(widget.m['percent']));
  late final TextEditingController _fixed = TextEditingController(text: _num(widget.m['fixed']));
  bool _busy = false;

  @override
  void dispose() {
    _percent.dispose();
    _fixed.dispose();
    super.dispose();
  }

  Future<void> _run(Future<bool> Function() action) async {
    FocusScope.of(context).unfocus(); // hide the keyboard BEFORE closing, so nothing rebuilds mid-animation
    setState(() => _busy = true);
    final ok = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Navigator.pop(context);
    } else {
      toast(widget.provider.errorMessage ?? 'admin_could_not_load'.tr, error: true);
    }
  }

  void _save() {
    final pct = double.tryParse(_percent.text.trim());
    final fx = double.tryParse(_fixed.text.trim());
    if (pct == null || pct < 0 || pct > 100) {
      toast('admin_fee_percent_invalid'.tr, error: true);
      return;
    }
    if (fx == null || fx < 0) {
      toast('admin_fee_fixed_invalid'.tr, error: true);
      return;
    }
    _run(() => widget.provider.save(asStr(widget.m['method']), percent: pct, fixed: fx));
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SheetHeader(widget.title),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(children: [
            Field(
              controller: _percent,
              label: 'admin_fee_percent'.tr,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
            Field(
              controller: _fixed,
              label: 'admin_fee_fixed'.tr,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
            PrimaryButton(label: 'save'.tr, isLoading: _busy, onPressed: _save),
            if (m['is_default'] != true)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() => widget.provider.save(asStr(m['method']), reset: true)),
                child: Text(
                  '${'admin_fee_reset'.tr} (${_num(m['default_percent'])}% + ${_num(m['default_fixed'])})',
                ),
              ),
          ]),
        ),
      ),
    ]);
  }
}