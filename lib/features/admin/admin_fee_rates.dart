// lib/features/admin/admin_fee_rates.dart  (NEW FILE)
//
// Admin control of EVERY fee, each as a percent, a fixed amount, or both:
//   • gateway fee of each payment method:
//       mada · visa · mastercard · apple_pay · creditcard (hosted checkout) · instapay · bank_transfer
//   • platform fee (percent = system default, fixed = per course)
//   • VAT charged to STUDENTS on the platform fee (percent, has a default)
//   • VAT deducted from TEACHERS on the platform fee (percent, has a default)
//   GET /api/v1/admin/fees              list (items + platform + vat)
//   PUT /api/v1/admin/fees/{method}     {percent?, fixed?} or {reset: true}
//   PUT /api/v1/admin/fees/platform     {percent?, fixed?} or {reset: true}
//   PUT /api/v1/admin/fees/vat          {percent} or {reset: true}      (students)
//   PUT /api/v1/admin/fees/teacher-vat  {percent} or {reset: true}      (teachers)
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
import '../../utils/widget/app_loading_indicator.dart';
import '../../utils/widget/primary_button.dart';
import '../student/enrollment/enrollment_models.dart' show asJsonMap;
import 'admin_common.dart';
import 'admin_premium_widgets.dart';

class AdminFeeRatesProvider extends BaseProvider {
  AdminFeeRatesProvider({ApiClient? api}) : api = api ?? ApiClient();
  final ApiClient api;

  List<Map<String, dynamic>> items = [];
  Map<String, dynamic> platform = {};
  Map<String, dynamic> vat = {};
  Map<String, dynamic> teacherVat = {};
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
    platform = json['platform'] is Map ? Map<String, dynamic>.from(json['platform'] as Map) : {};
    vat = json['vat'] is Map ? Map<String, dynamic>.from(json['vat'] as Map) : {};
    teacherVat = json['teacher_vat'] is Map ? Map<String, dynamic>.from(json['teacher_vat'] as Map) : {};
    vatPercent = ((vat['percent'] ?? json['vat_percent']) as num?)?.toDouble() ?? 0;
    loaded = true;
    notifyListeners();
  }

  /// Saves one method. Pass [reset] to go back to the built-in default.
  Future<bool> save(String method, {double? percent, double? fixed, bool reset = false}) async {
    final json = asJsonMap(await run(() async => api.put(
      '/api/v1/admin/fees/$method',
      body: {
        'percent': ?percent,
        'fixed': ?fixed,
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

  /// Platform fee: [percent] is the system default %, [fixed] a fixed amount added per course.
  Future<bool> savePlatform({double? percent, double? fixed, bool reset = false}) async {
    final json = asJsonMap(await run(() async => api.put(
      '/api/v1/admin/fees/platform',
      body: {
        'percent': ?percent,
        'fixed': ?fixed,
        if (reset) 'reset': true,
      },
    )));
    if (json == null) {
      notifyListeners();
      return false;
    }
    platform = json;
    notifyListeners();
    return true;
  }

  /// VAT charged on the platform fee.
  Future<bool> saveVat({double? percent, bool reset = false}) async {
    final json = asJsonMap(await run(() async => api.put(
      '/api/v1/admin/fees/vat',
      body: {
        'percent': ?percent,
        if (reset) 'reset': true,
      },
    )));
    if (json == null) {
      notifyListeners();
      return false;
    }
    vat = json;
    vatPercent = (json['percent'] as num?)?.toDouble() ?? vatPercent;
    notifyListeners();
    return true;
  }
  /// VAT deducted from the teacher's earning (on the platform fee).
  Future<bool> saveTeacherVat({double? percent, bool reset = false}) async {
    final json = asJsonMap(await run(() async => api.put(
      '/api/v1/admin/fees/teacher-vat',
      body: {
        'percent': ?percent,
        if (reset) 'reset': true,
      },
    )));
    if (json == null) {
      notifyListeners();
      return false;
    }
    teacherVat = json;
    notifyListeners();
    return true;
  }
}

typedef _FeeSave = Future<bool> Function({double? percent, double? fixed, bool reset});

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

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
        const Padding(padding: EdgeInsets.all(20), child: Center(child: AppLoadingIndicator()))
      else if (!p.loaded)
        ErrorRetry(message: p.errorMessage ?? 'admin_could_not_load'.tr, onRetry: p.load)
      else ...[
          if (p.platform.isNotEmpty)
            _FeeRateCard(
              title: _t('رسوم المنصة', 'Platform fee'),
              m: p.platform,
              icon: Icons.account_balance_rounded,
              colors: AdminPalette.indigo,
              onSave: p.savePlatform,
              provider: p,
              note: _t(
                'النسبة هي الافتراضية لكل الكورسات (يمكن تخصيصها لكل كورس)، والمبلغ الثابت يُضاف على كل كورس.',
                'The percent is the default for all courses (a course can override it); the fixed amount is added per course.',
              ),
            ),
          if (p.vat.isNotEmpty)
            _FeeRateCard(
              title: _t('ضريبة الطلاب (القيمة المضافة)', 'Student VAT'),
              m: p.vat,
              icon: Icons.receipt_long_rounded,
              colors: AdminPalette.orange,
              onSave: ({double? percent, double? fixed, bool reset = false}) =>
                  p.saveVat(percent: percent, reset: reset),
              provider: p,
              hasFixed: false,
              note: _t('تُضاف على سعر الاشتراك للطالب، وتُحسب على رسوم المنصة فقط.',
                  'Added to what the student pays; charged on the platform fee only.'),
            ),
          if (p.teacherVat.isNotEmpty)
            _FeeRateCard(
              title: _t('ضريبة المعلّم (القيمة المضافة)', 'Teacher VAT'),
              m: p.teacherVat,
              icon: Icons.cast_for_education_rounded,
              colors: AdminPalette.rose,
              onSave: ({double? percent, double? fixed, bool reset = false}) =>
                  p.saveTeacherVat(percent: percent, reset: reset),
              provider: p,
              hasFixed: false,
              note: _t('تُخصم من أرباح المعلّم، وتُحسب على رسوم المنصة المخصومة منه.',
                  'Deducted from the teacher\'s earnings; charged on the platform fee taken from them.'),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(_t('رسوم بوابات الدفع', 'Payment gateway fees'),
                style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, fontSize: 14, color: c.textDark)),
          ),
          for (final m in p.items)
            _FeeRateCard(
              title: asStr(AppConfig.lang == 'ar' ? m['label_ar'] : m['label_en']),
              m: m,
              onSave: ({double? percent, double? fixed, bool reset = false}) =>
                  p.save(asStr(m['method']), percent: percent, fixed: fixed, reset: reset),
              provider: p,
              note: m['group'] == 'manual' ? 'admin_fee_manual_note'.tr : null,
            ),
          const SizedBox(height: 12),
        ],
    ]);
  }
}

String _num(Object? v) {
  final d = (v as num?)?.toDouble() ?? 0;
  return d.truncateToDouble() == d ? d.toStringAsFixed(0) : d.toString();
}

class _FeeRateCard extends StatelessWidget {
  const _FeeRateCard({
    required this.title,
    required this.m,
    required this.onSave,
    required this.provider,
    this.hasFixed = true,
    this.note,
    this.icon = Icons.credit_score_rounded,
    this.colors,
  });
  final IconData icon;
  final List<Color>? colors;
  final String title;
  final Map<String, dynamic> m;
  final _FeeSave onSave;
  final AdminFeeRatesProvider provider;
  final bool hasFixed;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isCustom = m['is_default'] != true;

    return Section(
      icon: icon,
      colors: colors ?? AdminPalette.teal,
      title: title,
      trailing: isCustom
          ? Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: context.colors.warning.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('admin_fee_custom'.tr,
            style: TextStyle(fontFamily: 'tajawal', fontSize: 11, color: context.colors.warning)),
      )
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        KeyValue('admin_fee_percent'.tr, '${_num(m['percent'])}%'),
        if (hasFixed) KeyValue('admin_fee_fixed'.tr, _num(m['fixed'])),
        if (note != null)
          Text(note!, style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textLight)),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: Text('admin_edit_details'.tr),
            onPressed: () => showAdminSheet(
              context,
                  (_) => _FeeEditSheet(provider: provider, m: m, title: title, onSave: onSave, hasFixed: hasFixed),
            ),
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
  const _FeeEditSheet({
    required this.provider,
    required this.m,
    required this.title,
    required this.onSave,
    this.hasFixed = true,
  });
  final AdminFeeRatesProvider provider;
  final Map<String, dynamic> m;
  final String title;
  final _FeeSave onSave;
  final bool hasFixed;

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
    final fx = widget.hasFixed ? double.tryParse(_fixed.text.trim()) : null;
    if (pct == null || pct < 0 || pct > 100) {
      toast('admin_fee_percent_invalid'.tr, error: true);
      return;
    }
    if (widget.hasFixed && (fx == null || fx < 0)) {
      toast('admin_fee_fixed_invalid'.tr, error: true);
      return;
    }
    _run(() => widget.onSave(percent: pct, fixed: fx));
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
            if (widget.hasFixed)
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
                    : () => _run(() => widget.onSave(reset: true)),
                child: Text(
                  widget.hasFixed
                      ? '${'admin_fee_reset'.tr} (${_num(m['default_percent'])}% + ${_num(m['default_fixed'])})'
                      : '${'admin_fee_reset'.tr} (${_num(m['default_percent'])}%)',
                ),
              ),
          ]),
        ),
      ),
    ]);
  }
}