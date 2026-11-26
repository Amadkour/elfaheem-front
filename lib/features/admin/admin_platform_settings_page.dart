// lib/features/admin/admin_platform_settings_page.dart
//
// Super admin → "Platform settings", four groups:
//   1. Organizations — master switch for the whole Organizations feature set + the creation fee
//      (amount · currency · which payment methods) + manual-transfer receipts waiting for review
//   2. New accounts (D-1120, D-1121) — per role (teachers, parents, students): free / paid / approval / paid +
//      approval, the fee's amount and currency, + the payment methods and the receipts of account fees
//   3. Time & region — default timezone (Egypt → KSA → UAE → Arab world → others) and 12h / 24h
//   4. Features — opens the feature catalog (search, groups, org-manageable features)
//
// GET/PUT /api/v1/admin/platform-settings (PUT = full object, super admin only; admins read)
// GET /org-fee/payments?status=&purpose= · POST /org-fee/payments/{id}/approve|reject?purpose=
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart' show Trans;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../org/org_creation_fee.dart' show money;
import '../org/org_v3.dart';
import 'admin_common.dart' show asMap, asMapList, t;
import 'admin_labels.dart' show disposeAfterRoute;
import 'admin_page.dart';
import 'cfg_common.dart';
import 'admin_features_page.dart';
import 'admin_feedback_settings.dart' show AdminFeedbackSettingsPage;
import 'admin_account_fee_widgets.dart';
import 'admin_platform_widgets.dart';
import 'sup/sup_kit.dart';

const _path = '/api/v1/admin/platform-settings';

class AdminPlatformSettingsPage extends StatefulWidget {
  const AdminPlatformSettingsPage({super.key});

  @override
  State<AdminPlatformSettingsPage> createState() => _AdminPlatformSettingsPageState();
}

class _AdminPlatformSettingsPageState extends State<AdminPlatformSettingsPage> {
  Map<String, dynamic>? _s; // last saved
  ApiException? _error;
  bool _saving = false;

  // draft
  bool _orgs = true;
  bool _sharing = true;            // cross-organization data sharing (brief §4)
  final _amount = TextEditingController();
  String _currency = 'EGP';
  Set<String> _methods = {};
  String _zone = AppTime.fallbackZone;
  String _fmt = '12h';
  // account fee (D-1120), per role
  final _acc = {for (final r in accountFeeRoles) r: AccountFeeDraft()};
  Set<String> _accMethods = {};

  bool get _canEdit => _s?['can_edit'] == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    for (final d in _acc.values) {
      d.amount.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final r = await orgCall(() => ApiClient().get(_path), quiet: true);
    if (!mounted) return;
    if (!r.ok) {
      // a failed refresh keeps the form that is on screen (and the unsaved edits in it)
      if (_s != null) {
        showAppNotice(orgErrorText(r.error!), error: true);
        return;
      }
      return setState(() => _error = r.error);
    }
    _take(r.map);
  }

  void _take(Map<String, dynamic> s) {
    final fee = asMap(s['org_creation_fee']);
    setState(() {
      _s = s;
      _error = null;
      _orgs = s['orgs_enabled'] != false;
      _sharing = s['sharing_enabled'] != false;
      final a = (fee['amount'] as num?) ?? 0;
      _amount.text = a == 0 ? '' : (a == a.roundToDouble() ? '${a.toInt()}' : a.toStringAsFixed(2));
      _currency = '${fee['currency'] ?? 'EGP'}';
      _methods = {for (final m in (fee['methods'] as List? ?? const [])) '$m'};
      _zone = '${s['timezone'] ?? AppTime.fallbackZone}';
      _fmt = '${s['time_format'] ?? '12h'}';
      final acc = asMap(s['account_fee']);
      for (final r in accountFeeRoles) {
        _acc[r]!.take(asMap(acc[r]));
      }
      _accMethods = {for (final m in (acc['methods'] as List? ?? const [])) '$m'};
    });
  }

  Map<String, dynamic> get _accBody => {
        for (final r in accountFeeRoles) r: _acc[r]!.body,
        'methods': _accMethods.toList(),
      };

  bool get _accOn => _acc.values.any((d) => d.on);

  String? get _accError {
    for (final d in _acc.values) {
      if (d.on && (d.value == null || d.value! <= 0)) {
        return t('اكتب مبلغ رسوم الحساب (أكبر من صفر) أو أوقفها.', 'Enter the account fee (above 0) or switch it off.');
      }
    }
    if (_accOn && _accMethods.isEmpty) {
      return t('اختر طريقة دفع واحدة على الأقل لرسوم الحسابات.', 'Pick at least one payment method for account fees.');
    }
    return null;
  }

  bool get _accDirty {
    final acc = asMap(_s?['account_fee']);
    final saved = {for (final m in (acc['methods'] as List? ?? const [])) '$m'};
    return _acc.entries.any((e) => e.value.differs(asMap(acc[e.key]))) ||
        saved.length != _accMethods.length ||
        !saved.containsAll(_accMethods);
  }

  /// An empty field is 0 (free); text that is not a non-negative number is an error, never a silent 0.
  double get _amountValue => cfgParseNumber(_amount.text) ?? 0;

  String? get _amountError {
    final txt = _amount.text.trim();
    if (txt.isEmpty) return null;
    final v = cfgParseNumber(txt);
    if (v == null || v < 0) {
      return t('أدخل مبلغاً صحيحاً (أرقام فقط، 0 = مجاني).', 'Enter a valid amount (numbers only, 0 = free).');
    }
    return null;
  }

  Map<String, dynamic> get _body => {
        'orgs_enabled': _orgs,
        'sharing_enabled': _sharing,
        'org_creation_fee': {'amount': _amountValue, 'currency': _currency, 'methods': _methods.toList()},
        'account_fee': _accBody,
        'timezone': _zone,
        'time_format': _fmt,
      };

  bool get _dirty {
    final s = _s;
    if (s == null) return false;
    final fee = asMap(s['org_creation_fee']);
    return _orgs != (s['orgs_enabled'] != false) || _sharing != (s['sharing_enabled'] != false) ||
        _amountValue != ((fee['amount'] as num?) ?? 0).toDouble() ||
        _currency != fee['currency'] ||
        _methods.length != (fee['methods'] as List? ?? const []).length ||
        !_methods.containsAll([for (final m in (fee['methods'] as List? ?? const [])) '$m']) ||
        _zone != s['timezone'] ||
        _fmt != s['time_format'] ||
        _accDirty;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_amountError != null) {
      showAppNotice(_amountError!, error: true);
      return;
    }
    if (_accError != null) {
      showAppNotice(_accError!, error: true);
      return;
    }
    final wasOn = _s?['orgs_enabled'] != false;
    if (wasOn && !_orgs) {
      final ok = await appConfirm(context,
          danger: true,
          confirmLabel: t('إيقاف المؤسسات', 'Switch off'),
          message: t(
              'سيختفي كل ما يخص المؤسسات من التطبيق: لوحات المؤسسات، الانضمام، وطلبات الإنشاء. لن تُحذف أي بيانات وتعود كما هي عند إعادة التفعيل. متابعة؟',
              'Everything about organizations disappears from the app: dashboards, joining and creation requests. No data is deleted and it all comes back when you switch it on again. Continue?'));
      if (!ok) return;
    }
    setState(() => _saving = true);
    final r = await orgCall(() => ApiClient().put(_path, body: _body), ok: t('تم حفظ الإعدادات', 'Settings saved'));
    if (!mounted) return;
    setState(() => _saving = false);
    if (r.ok) {
      _take(r.map);
      // apply to this device right away (other devices get a silent push)
      if (mounted) context.read<ThemeConfigProvider>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SupPage(
        kicker: 'a2_platform_kicker'.tr, headline: 'a2_settings_head'.tr, line: 'a2_settings_line'.tr,
        width: AppWidth.reading,
        title: t('إعدادات المنصة', 'Platform settings'),
        onRefresh: _load,
        dirty: _canEdit && _dirty,
        body: _error != null
          ? cfgErrorState(_error, onRetry: _load)
          : _s == null
              ? const AppListSkeleton(items: 5)
              : _content(context),
        actions: [?(_canEdit
          ? cfgSaveButton(dirty: _dirty && _amountError == null, busy: _saving, onSave: _save)
          : null)],
      );
  }

  Widget _content(BuildContext context) {
    final c = context.colors;
    final methods = asMapList(_s!['available_methods']);
    final currencies = [for (final x in (_s!['currencies'] as List? ?? const ['EGP'])) '$x'];
    final awaiting = (_s!['awaiting_fee_review'] as num?)?.toInt() ?? 0;
    final accAwaiting = (_s!['awaiting_account_fee_review'] as num?)?.toInt() ?? 0;
    final free = _amountValue <= 0;

    final amountError = _amountError;

    return AppRefresh(
      onRefresh: _load,
      child: ListView(padding: AdminPage.bodyPadding(context), children: [
        AppKpiGrid(maxColumns: 3, children: [
          AppStatCard(
              icon: Icons.account_balance_rounded,
              value: _orgs ? t('مفعّلة', 'On') : t('متوقفة', 'Off'),
              label: t('المؤسسات', 'Organizations')),
          AppStatCard(icon: Icons.public_rounded, value: AppTime.zoneInfo(_zone).label, label: t('المنطقة', 'Zone')),
          AppStatCard(
              icon: Icons.schedule_rounded, value: _fmt == '24h' ? '24h' : '12h', label: t('الساعة', 'Clock')),
        ]),
        if (!_canEdit) ...[
          AppSpace.gapSm,
          AppBanner(icon: Icons.visibility_rounded, text: t('عرض فقط — التعديل لمدير المنصة الأعلى.', 'Read only — only the super admin can change these.')),
        ],
        AppSpace.gapLg,

        // ── 1. Organizations ──────────────────────────────────────────
        AppSection(
          title: t('المؤسسات', 'Organizations'),
          subtitle: t('الجامعات والكليات والمعاهد على المنصة.', 'Universities, faculties and institutes on the platform.'),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppSwitchTile(
                icon: Icons.power_settings_new_rounded,
                title: t('تفعيل المؤسسات على المنصة', 'Organizations on this platform'),
                subtitle: _orgs
                    ? t('تظهر لوحات المؤسسات والانضمام وطلبات الإنشاء.', 'Org dashboards, joining and creation requests are available.')
                    : t('مخفية بالكامل لكل المستخدمين — البيانات محفوظة.', 'Hidden for everyone — all data is kept.'),
                value: _orgs,
                onChanged: _canEdit && !_saving ? (v) => setState(() => _orgs = v) : null,
              ),
              if (_orgs)
                AppSwitchTile(
                  key: const ValueKey('platform.sharing'),
                  icon: Icons.handshake_rounded,
                  title: t('مشاركة البيانات بين المؤسسات', 'Data sharing between organizations'),
                  subtitle: _sharing
                      ? t('يقرر مدير كل مؤسسة ما يشاركه؛ يمكن إيقافها لمؤسسة بعينها من صفحة المؤسسة.', 'Each organization admin decides what to share; it can be switched off per organization from its page.')
                      : t('لا تُشارك أي بيانات بين المؤسسات ولا يعمل التحقق من الخريجين.', 'Nothing is shared between organizations and graduate verification is off.'),
                  value: _sharing,
                  onChanged: _canEdit && !_saving ? (v) => setState(() => _sharing = v) : null,
                ),
              AnimatedSize(
                duration: AppMotion.of(context).base,
                child: !_orgs
                    ? const SizedBox(width: double.infinity)
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Divider(height: AppSpace.lg),
                        Text(t('رسوم طلب إنشاء مؤسسة', 'Organization creation fee'), style: AppType.section(context)),
                        const SizedBox(height: AppSpace.xxs),
                        Text(
                            t('تُدفع قبل إرسال الطلب. صفر = مجاني. دفعة واحدة تغطي طلباً واحداً، وإن رُفض الطلب تبقى صالحة لإعادة إرساله.',
                                'Paid before sending the request. 0 = free. One payment covers one request; if it is turned down, the payment stays valid for re-submitting it.'),
                            style: AppType.meta(context)),
                        AppSpace.gapSm,
                        LayoutBuilder(builder: (context, box) {
                          final amount = AbsorbPointer(
                            absorbing: !_canEdit,
                            child: AppField(
                                controller: _amount,
                                label: t('المبلغ (0 = مجاني)', 'Amount (0 = free)'),
                                keyboard: const TextInputType.numberWithOptions(decimal: true),
                                ltr: true,
                                onChanged: (_) => setState(() {})),
                          );
                          final currency = AbsorbPointer(
                            absorbing: !_canEdit,
                            child: AppPicker<String>(
                              label: t('العملة', 'Currency'),
                              icon: Icons.currency_exchange_rounded,
                              value: _currency,
                              options: {for (final x in currencies) x: x},
                              onChanged: (v) => setState(() => _currency = v ?? _currency),
                            ),
                          );
                          if (box.maxWidth < 460) return Column(children: [amount, currency]);
                          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(flex: 3, child: amount),
                            AppSpace.gapSm,
                            Expanded(flex: 2, child: currency),
                          ]);
                        }),
                        if (amountError != null) CfgFieldError(amountError),
                        if (!free) ...[
                          AppSpace.gapSm,
                          Text(t('طرق الدفع المقبولة', 'Accepted payment methods'), style: AppType.label(context)),
                          const SizedBox(height: AppSpace.xxs),
                          for (final m in methods) _methodTile(context, m, selected: _methods, currencies: {_currency}),
                          if (_methods.isEmpty)
                            AppBanner(icon: Icons.warning_amber_rounded, color: c.warning, text: t('اختر طريقة دفع واحدة على الأقل.', 'Pick at least one payment method.')),
                        ],
                        AppSpace.gapSm,
                        AppActionCard(
                          icon: Icons.receipt_long_rounded,
                          title: t('إيصالات الرسوم', 'Fee receipts'),
                          subtitle: awaiting > 0
                              ? t('$awaiting بانتظار المراجعة', '$awaiting waiting for review')
                              : t('كل المدفوعات والتحويلات', 'Every payment and transfer'),
                          color: awaiting > 0 ? c.warning : c.primary,
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminOrgFeePaymentsPage()));
                            _load();
                          },
                        ),
                      ]),
              ),
            ]),
          ),
        ),
        AppSpace.gapLg,

        // ── 2. New accounts: registration modes + fees (D-1120, D-1121) ─
        AppSection(
          title: t('فتح الحسابات الجديدة', 'New accounts'),
          subtitle: t('اختر لكل دور كيف يبدأ الحساب الجديد. الحسابات الموجودة والتي ينشئها المدير لا تتأثر، والتحويل إلى «مجاني» يفتح كل من ينتظر.',
              'Pick how a new account of each role starts. Existing accounts and those an admin creates are not affected; switching to Free lets everyone waiting in.'),
          child: AppCard(
            key: const ValueKey('platform.account_fee'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final r in accountFeeRoles) ...[
                if (r != accountFeeRoles.first) const Divider(height: AppSpace.md),
                AccountFeeRoleRow(
                  role: r,
                  draft: _acc[r]!,
                  currencies: currencies,
                  enabled: _canEdit && !_saving,
                  onChanged: () => setState(() {}),
                ),
              ],
              if (_accOn) ...[
                const Divider(height: AppSpace.lg),
                Text(t('طرق الدفع المقبولة', 'Accepted payment methods'), style: AppType.label(context)),
                const SizedBox(height: AppSpace.xxs),
                for (final m in methods)
                  _methodTile(context, m,
                      selected: _accMethods,
                      currencies: {for (final d in _acc.values) if (d.on) d.currency}),
              ],
              if (_accError != null && _accDirty) CfgFieldError(_accError!),
              AppSpace.gapSm,
              AppActionCard(
                icon: Icons.receipt_long_rounded,
                title: t('إيصالات رسوم الحسابات', 'Account fee receipts'),
                subtitle: accAwaiting > 0
                    ? t('$accAwaiting بانتظار المراجعة', '$accAwaiting waiting for review')
                    : t('كل المدفوعات والتحويلات', 'Every payment and transfer'),
                color: accAwaiting > 0 ? c.warning : c.primary,
                onTap: () async {
                  await Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const AdminOrgFeePaymentsPage(purpose: 'account')));
                  _load();
                },
              ),
            ]),
          ),
        ),
        AppSpace.gapLg,

        // ── 3. Time & region ─────────────────────────────────────────
        AppSection(
          title: t('الوقت والمنطقة', 'Time & region'),
          subtitle: t('الافتراضي لكل المستخدمين — يمكن لكل مؤسسة تغييره لنفسها.', 'Default for everyone — each organization may override it for itself.'),
          child: AppCard(
            child: RegionEditor(
              zone: _zone,
              timeFormat: _fmt,
              enabled: _canEdit,
              onZone: (v) => setState(() => _zone = v ?? _zone),
              onFormat: (v) => setState(() => _fmt = v ?? _fmt),
            ),
          ),
        ),
        AppSpace.gapLg,

        // ── 4. Features ──────────────────────────────────────────────
        AppSection(
          title: t('الميزات', 'Features'),
          subtitle: t('إظهار وإخفاء أجزاء التطبيق، وما يمكن لمديري المؤسسات التحكم فيه.',
              'Show or hide parts of the app, and what organization admins may control.'),
          child: AppCard(
            child: AppActionCard(
              icon: Icons.toggle_on_rounded,
              title: t('قائمة الميزات', 'Feature list'),
              subtitle: t('بحث، مجموعات، إضافة وحذف', 'Search, groups, add & remove'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminFeaturesPage())),
            ),
          ),
        ),
        AppSpace.gapLg,
        AppSection(
          title: t('بيانات تعلم المصحح الآلي', 'Grader learning data'),
          subtitle: t('جمع تصحيحات المعلمين (بأسماء مستعارة) لتحسين التصحيح الآلي — للمشرف العام.',
              'Collect teachers’ corrections (pseudonymous) to improve automatic grading — Super Admin.'),
          child: AppCard(
            child: AppActionCard(
              icon: Icons.tune_rounded,
              title: t('إعدادات وتصدير بيانات التصحيح', 'Feedback store settings & export'),
              subtitle: t('تفعيل، افتراضي المؤسسات، مدة الاحتفاظ', 'On/off, organizations default, retention'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminFeedbackSettingsPage())),
            ),
          ),
        ),
      ]),
    );
  }

  /// One payment method of a fee: [selected] is that fee's set, [currencies] the currencies it charges in.
  Widget _methodTile(BuildContext context, Map<String, dynamic> m,
      {required Set<String> selected, required Set<String> currencies}) {
    final c = context.colors;
    final id = '${m['id']}';
    final needs = m['currency'] as String?;
    final wrongCurrency = needs != null && currencies.any((x) => x != needs);
    final ready = m['ready'] == true;
    final note = wrongCurrency
        ? t('تتعامل بعملة $needs فقط', 'Charges in $needs only')
        : !ready
            ? (m['reason'] == 'disabled'
                ? t('متوقفة من إعدادات طرق الدفع', 'Switched off in payment methods')
                : t('غير مهيأة على الخادم', 'Not configured on the server'))
            : (m['kind'] == 'card' ? t('دفع فوري بالبطاقة', 'Instant card payment') : t('يراجع فريق المنصة الإيصال', 'The platform team reviews the receipt'));
    final selectable = _canEdit && !wrongCurrency;
    return AppSwitchTile(
      dense: true,
      icon: m['kind'] == 'card' ? Icons.credit_card_rounded : Icons.account_balance_rounded,
      title: t('${m['label_ar']}', '${m['label_en']}'),
      subtitleWidget: Text(note,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppType.meta(context).copyWith(color: (wrongCurrency || !ready) ? c.warning : c.textLight)),
      value: selected.contains(id) && !wrongCurrency,
      onChanged: selectable
          ? (v) => setState(() => v ? selected.add(id) : selected.remove(id))
          : null,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Fee receipts / payments
// ═════════════════════════════════════════════════════════════════════════════

class AdminOrgFeePaymentsPage extends StatefulWidget {
  /// `org` (organization-creation fees) or `account` (teacher / parent account fees, D-1120).
  final String purpose;

  const AdminOrgFeePaymentsPage({super.key, this.purpose = 'org'});

  @override
  State<AdminOrgFeePaymentsPage> createState() => _AdminOrgFeePaymentsPageState();
}

class _AdminOrgFeePaymentsPageState extends State<AdminOrgFeePaymentsPage> {
  String _status = 'review';
  List<Map<String, dynamic>>? _items;
  ApiException? _error;
  bool _deciding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// [keep]: a refresh (pull, after a decision) leaves the rows on screen — the skeleton is only for the first load
  /// and for a changed filter.
  Future<void> _load({bool keep = false}) async {
    if (!keep) {
      setState(() {
        _items = null;
        _error = null;
      });
    }
    final r = await orgCall(() => ApiClient().get('$_path/org-fee/payments',
        queryParams: {if (_status.isNotEmpty) 'status': _status, 'size': 100, 'purpose': widget.purpose}), quiet: true);
    if (!mounted) return;
    if (!r.ok && _items != null && keep) {
      showAppNotice(orgErrorText(r.error!), error: true);
      return;
    }
    setState(() {
      _items = r.ok ? asMapList(r.map['items']) : null;
      _error = r.ok ? null : r.error;
    });
  }

  Future<void> _decide(Map<String, dynamic> p, bool approve) async {
    if (_deciding) return;
    final note = TextEditingController();
    final ok = await showAppSheet<bool>(context, (ctx) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.lg),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSheetHeader(approve ? t('اعتماد الدفعة', 'Approve payment') : t('رفض الإيصال', 'Reject receipt')),
            AppField(controller: note, label: approve ? t('ملاحظة (اختياري)', 'Note (optional)') : t('السبب — يراه المتقدم', 'Reason — the applicant sees it'), maxLines: 2),
            AppSpace.gapSm,
            AppButton.primary(
                label: approve ? t('اعتماد', 'Approve') : t('رفض', 'Reject'),
                icon: approve ? Icons.check_rounded : Icons.close_rounded,
                onPressed: () => Navigator.pop(ctx, true)),
          ]),
        ));
    final text = note.text.trim();
    disposeAfterRoute([note]);
    if (ok != true || !mounted) return;
    setState(() => _deciding = true);
    final r = await orgCall(
        () => ApiClient().post(
            '$_path/org-fee/payments/${p['id']}/${approve ? 'approve' : 'reject'}',
            body: {'note': text}, queryParams: {'purpose': widget.purpose}),
        ok: approve ? t('تم الاعتماد', 'Approved') : t('تم الرفض', 'Rejected'));
    if (!mounted) return;
    setState(() => _deciding = false);
    if (r.ok) _load(keep: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final filters = {
      'review': t('بانتظار المراجعة', 'Waiting review'),
      'paid': t('مدفوعة', 'Paid'),
      'pending': t('دفع إلكتروني لم يكتمل', 'Online, unfinished'),
      'rejected': t('مرفوضة', 'Rejected'),
      '': t('الكل', 'All'),
    };
    return SupPage(
        kicker: 'a2_platform_kicker'.tr, headline: 'a2_fee_receipts_head'.tr,
        title: widget.purpose == 'account'
          ? t('إيصالات رسوم الحسابات', 'Account fee receipts')
          : t('إيصالات رسوم المؤسسات', 'Organization fee receipts'),
        onRefresh: () => _load(keep: _items != null),
        body: Column(children: [
        // no fixed height: the chips grow with the text size
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.fromLTRB(AppSpace.gutter(MediaQuery.sizeOf(context).width), AppSpace.sm, AppSpace.md, AppSpace.xs),
          child: Row(children: [
            for (final f in filters.entries)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
                child: AppChoiceChip(label: f.value, selected: _status == f.key, onTap: () {
                  _status = f.key;
                  _load();
                }),
              ),
          ]),
        ),
        Expanded(
          child: _items == null
              ? (_error != null ? cfgErrorState(_error, onRetry: _load) : const AppListSkeleton())
              : _items!.isEmpty
                  ? AppEmpty(icon: Icons.inbox_rounded, title: t('لا شيء هنا', 'Nothing here'))
                  : AppRefresh(
                      onRefresh: () => _load(keep: true),
                      child: ListView.separated(
                        padding: AdminPage.bodyPadding(context),
                        itemCount: _items!.length,
                        separatorBuilder: (_, _) => AppSpace.gapSm,
                        itemBuilder: (_, i) {
                          final p = _items![i];
                          final st = '${p['status']}';
                          final tone = switch (st) {
                            'paid' => AppTone.success,
                            'review' => AppTone.warning,
                            'rejected' || 'failed' => AppTone.danger,
                            _ => AppTone.neutral,
                          };
                          return AppCard(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${p['sender_name'] ?? p['user_name'] ?? p['email'] ?? '#${p['id']}'}',
                                  maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                              const SizedBox(height: AppSpace.xxs),
                              Align(alignment: AlignmentDirectional.centerStart, child: AppStatusBadge(label: filters[st] ?? st, tone: tone)),
                              const SizedBox(height: AppSpace.xs),
                              Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, children: [
                                Text(money(p['amount'], '${p['currency']}'), style: AppType.label(context).copyWith(color: c.primary)),
                                Text('${p['method']}', style: AppType.meta(context)),
                                if (p['email'] != null) Text('${p['email']}', style: AppType.meta(context)),
                                if (p['transfer_reference'] != null) Text('#${p['transfer_reference']}', style: AppType.meta(context)),
                                if (p['created_at'] != null)
                                  Text(AppTime.dateTime(orgParseUtc(p['created_at'])!), style: AppType.meta(context)),
                                if (p['org_id'] != null) Text(t('استُخدمت لطلب #${p['org_id']}', 'Used by request #${p['org_id']}'), style: AppType.meta(context)),
                              ]),
                              if (p['proof_image_url'] != null) ...[
                                AppSpace.gapSm,
                                ClipRRect(
                                  borderRadius: AppRadius.cardAll,
                                  child: Image.network('${p['proof_image_url']}', height: 160, width: double.infinity, fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const SizedBox.shrink()),
                                ),
                              ],
                              if (st == 'review' || st == 'pending') ...[
                                AppSpace.gapSm,
                                LayoutBuilder(builder: (context, box) {
                                  final approveBtn = AppButton.primary(expand: true, label: t('اعتماد', 'Approve'), icon: Icons.check_rounded, onPressed: _deciding ? null : () => _decide(p, true));
                                  final rejectBtn = AppButton.secondary(expand: true, label: t('رفض', 'Reject'), icon: Icons.close_rounded, onPressed: _deciding ? null : () => _decide(p, false));
                                  // side by side only when both fit; stacked on a phone
                                  if (box.maxWidth < 360) return Column(children: [approveBtn, AppSpace.gapXs, rejectBtn]);
                                  return Row(children: [Expanded(child: approveBtn), AppSpace.gapXs, Expanded(child: rejectBtn)]);
                                }),
                              ],
                            ]),
                          );
                        },
                      ),
                    ),
        ),
      ]),
      );
  }
}
