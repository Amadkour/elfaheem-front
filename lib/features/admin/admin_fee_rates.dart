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
import '../student/enrollment/enrollment_models.dart' show asJsonMap;
import 'admin_common.dart';
import 'admin_money_p8.dart' show AdminMoneyPage, parseAmountLoose;
import 'package:flutter_education_app/design/app_kit.dart';

class AdminFeeRatesProvider extends BaseProvider {
  AdminFeeRatesProvider({ApiClient? api}) : api = api ?? ApiClient();
  final ApiClient api;

  List<Map<String, dynamic>> items = [];
  Map<String, dynamic> platform = {};
  Map<String, dynamic> vat = {};
  Map<String, dynamic> teacherVat = {};
  double vatPercent = 0;
  bool loaded = false;

  /// Why the last save failed (the server's own message), or null. A save that fails must never read as
  /// "could not load".
  String? saveError;

  /// One PUT through [run]. A rejected save is a failure ([saveError]), never an exception for the caller.
  Future<Map<String, dynamic>?> _put(String path, Map<String, dynamic> body) async {
    try {
      return asJsonMap(await run(() async => api.put(path, body: body)));
    } on ApiException catch (e) {
      setError(e.message);
      return null;
    }
  }

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
    final json = await _put('/api/v1/admin/fees/$method', {
        'percent': ?percent,
        'fixed': ?fixed,
        if (reset) 'reset': true,
      });
    if (json == null) {
      saveError = hasError ? errorMessage : null;
      notifyListeners();
      return false;
    }
    saveError = null;
    final i = items.indexWhere((e) => e['method'] == method);
    if (i >= 0) items[i] = json;
    notifyListeners();
    return true;
  }

  /// Platform fee: [percent] is the system default %, [fixed] a fixed amount added per course.
  Future<bool> savePlatform({double? percent, double? fixed, bool reset = false}) async {
    final json = await _put('/api/v1/admin/fees/platform', {
        'percent': ?percent,
        'fixed': ?fixed,
        if (reset) 'reset': true,
      });
    if (json == null) {
      saveError = hasError ? errorMessage : null;
      notifyListeners();
      return false;
    }
    saveError = null;
    platform = json;
    notifyListeners();
    return true;
  }

  /// VAT charged on the platform fee.
  Future<bool> saveVat({double? percent, bool reset = false}) async {
    final json = await _put('/api/v1/admin/fees/vat', {
        'percent': ?percent,
        if (reset) 'reset': true,
      });
    if (json == null) {
      saveError = hasError ? errorMessage : null;
      notifyListeners();
      return false;
    }
    saveError = null;
    vat = json;
    vatPercent = (json['percent'] as num?)?.toDouble() ?? vatPercent;
    notifyListeners();
    return true;
  }
  /// VAT deducted from the teacher's earning (on the platform fee).
  Future<bool> saveTeacherVat({double? percent, bool reset = false}) async {
    final json = await _put('/api/v1/admin/fees/teacher-vat', {
        'percent': ?percent,
        if (reset) 'reset': true,
      });
    if (json == null) {
      saveError = hasError ? errorMessage : null;
      notifyListeners();
      return false;
    }
    saveError = null;
    teacherVat = json;
    notifyListeners();
    return true;
  }
}

typedef _FeeSave = Future<bool> Function({double? percent, double? fixed, bool reset});

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

class AdminFeeRatesSection extends StatelessWidget {
  const AdminFeeRatesSection({super.key, this.showPolicyLink = true});

  /// The "Fee policy & organizations" button; the Fees page has the policy in its own tab and turns it off.
  final bool showPolicyLink;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AdminFeeRatesProvider>();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppSection(
        title: 'admin_fee_rates'.tr,
        subtitle: 'admin_fee_rates_hint'.tr,
        // Phase 8: fee policy, per-organization fees, ledger report
        child: !showPolicyLink ? const SizedBox.shrink() : Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton.secondary(
            label: _t('سياسة الرسوم والمؤسسات', 'Fee policy & organizations'),
            icon: Icons.tune_rounded,
            size: AppButtonSize.sm,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminMoneyPage())),
          ),
        ),
      ),
      AppSpace.gapXs,
      if (!p.loaded && p.isLoading)
        const AppLoadingState(shape: AppLoadingShape.cards, items: 3)
      else if (!p.loaded)
        AppErrorState(message: p.errorMessage ?? 'admin_could_not_load'.tr, onRetry: p.load)
      else ...[
          if (p.platform.isNotEmpty)
            _FeeRateCard(
              title: _t('رسوم المنصة', 'Platform fee'),
              m: p.platform,
              icon: Icons.account_balance_rounded,
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
              onSave: ({double? percent, double? fixed, bool reset = false}) =>
                  p.saveTeacherVat(percent: percent, reset: reset),
              provider: p,
              hasFixed: false,
              note: _t('تُخصم من أرباح المعلّم، وتُحسب على رسوم المنصة المخصومة منه.',
                  'Deducted from the teacher\'s earnings; charged on the platform fee taken from them.'),
            ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm, bottom: AppSpace.xs),
            child: Text(_t('رسوم بوابات الدفع', 'Payment gateway fees'), style: AppType.section(context)),
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
          AppSpace.gapSm,
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
  });
  final IconData icon;
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

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: c.primaryTint, borderRadius: AppRadius.chipAll),
              child: Icon(icon, size: AppIconSize.md, color: c.primary),
            ),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(title, style: AppType.section(context))),
            if (isCustom) AppStatusBadge(label: 'admin_fee_custom'.tr, tone: AppTone.warning, dense: true),
          ]),
          AppSpace.gapXs,
          KeyValue('admin_fee_percent'.tr, '${_num(m['percent'])}%'),
          if (hasFixed) KeyValue('admin_fee_fixed'.tr, _num(m['fixed'])),
          if (note != null) Text(note!, style: AppType.meta(context)),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppButton.tonal(
              icon: Icons.edit_rounded,
              size: AppButtonSize.sm,
              label: 'admin_edit_details'.tr,
              onPressed: () => showAdminSheet(
                context,
                (_) => _FeeEditSheet(provider: provider, m: m, title: title, onSave: onSave, hasFixed: hasFixed),
              ),
            ),
          ),
        ]),
      ),
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
      // the server's own reason, never "could not load"
      toast(widget.provider.saveError ?? _t('تعذّر الحفظ، حاول مجددًا', 'Could not save, try again'), error: true);
    }
  }

  String _was(Object? v) => _num(v);

  Future<void> _save() async {
    final pct = parseAmountLoose(_percent.text);
    final fx = widget.hasFixed ? parseAmountLoose(_fixed.text) : null;
    if (pct == null || pct < 0 || pct > 100) {
      toast('admin_fee_percent_invalid'.tr, error: true);
      return;
    }
    if (widget.hasFixed && (fx == null || fx < 0)) {
      toast('admin_fee_fixed_invalid'.tr, error: true);
      return;
    }
    // fees apply to every LATER payment: say what changes before it does
    final change = StringBuffer('${_was(widget.m['percent'])}% \u2192 ${_num(pct)}%');
    if (widget.hasFixed) change.write('  |  ${_was(widget.m['fixed'])} \u2192 ${_num(fx)}');
    final ok = await appConfirm(
      context,
      message: '${widget.title}\n${change.toString()}\n\n${_t('ينطبق التغيير على كل عملية دفع قادمة. حفظ؟', 'The change applies to every later payment. Save?')}',
    );
    if (!ok || !mounted) return;
    await _run(() => widget.onSave(percent: pct, fixed: fx));
  }

  Future<void> _reset() async {
    final ok = await appConfirm(
      context,
      message: '${widget.title}\n\n${_t('ستعود الرسوم إلى قيمتها الافتراضية وتنطبق على كل عملية دفع قادمة. متابعة؟', 'The fee goes back to its default and applies to every later payment. Continue?')}',
    );
    if (!ok || !mounted) return;
    await _run(() => widget.onSave(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SheetHeader(widget.title),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
          child: Column(children: [
            AppNumberField(controller: _percent, label: 'admin_fee_percent'.tr, min: 0, max: 100, decimals: 2),
            if (widget.hasFixed) ...[
              AppSpace.gapSm,
              AppNumberField(controller: _fixed, label: 'admin_fee_fixed'.tr, min: 0, decimals: 2),
            ],
            AppButton.primary(label: 'save'.tr, busy: _busy, onPressed: _busy ? null : _save),
            if (m['is_default'] != true)
              TextButton(
                onPressed: _busy ? null : _reset,
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