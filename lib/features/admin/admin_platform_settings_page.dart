// lib/features/admin/admin_platform_settings_page.dart
//
// Super admin → "Platform settings", three groups:
//   1. Organizations — master switch for the whole Organizations feature set + the creation fee
//      (amount · currency · which payment methods) + manual-transfer receipts waiting for review
//   2. Time & region — default timezone (Egypt → KSA → UAE → Arab world → others) and 12h / 24h
//   3. Features — opens the feature catalog (search, groups, org-manageable features)
//
// GET/PUT /api/v1/admin/platform-settings (PUT = full object, super admin only; admins read)
// GET /org-fee/payments?status= · POST /org-fee/payments/{id}/approve|reject
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../org/org_creation_fee.dart' show money;
import '../org/org_v3.dart';
import 'admin_common.dart' show asMap, asMapList, t;
import 'admin_features_page.dart';
import 'admin_feedback_settings.dart' show AdminFeedbackSettingsPage;
import 'admin_platform_widgets.dart';

const _path = '/api/v1/admin/platform-settings';

class AdminPlatformSettingsPage extends StatefulWidget {
  const AdminPlatformSettingsPage({super.key});

  @override
  State<AdminPlatformSettingsPage> createState() => _AdminPlatformSettingsPageState();
}

class _AdminPlatformSettingsPageState extends State<AdminPlatformSettingsPage> {
  Map<String, dynamic>? _s; // last saved
  String? _error;
  bool _saving = false;

  // draft
  bool _orgs = true;
  bool _sharing = true;            // cross-organization data sharing (brief §4)
  final _amount = TextEditingController();
  String _currency = 'EGP';
  Set<String> _methods = {};
  String _zone = AppTime.fallbackZone;
  String _fmt = '12h';

  bool get _canEdit => _s?['can_edit'] == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await orgCall(() => ApiClient().get(_path), quiet: true);
    if (!mounted) return;
    if (!r.ok) {
      return setState(() => _error = r.endpointMissing
          ? t('هذه الصفحة تحتاج تحديث الخادم.', 'This page needs a server update.')
          : orgErrorText(r.error!));
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
    });
  }

  double get _amountValue => double.tryParse(_amount.text.trim().replaceAll(',', '.')) ?? 0;

  Map<String, dynamic> get _body => {
        'orgs_enabled': _orgs,
        'sharing_enabled': _sharing,
        'org_creation_fee': {'amount': _amountValue, 'currency': _currency, 'methods': _methods.toList()},
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
        _fmt != s['time_format'];
  }

  Future<void> _save() async {
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
    return BasePage(
      useWebCard: true,
      maxWith: 900,
      appBar: ScreenAppBar(title: t('إعدادات المنصة', 'Platform settings')),
      child: _error != null
          ? AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Try again'), onAction: _load)
          : _s == null
              ? const AppListSkeleton(items: 5)
              : _content(context),
    );
  }

  Widget _content(BuildContext context) {
    final c = context.colors;
    final methods = asMapList(_s!['available_methods']);
    final currencies = [for (final x in (_s!['currencies'] as List? ?? const ['EGP'])) '$x'];
    final awaiting = (_s!['awaiting_fee_review'] as num?)?.toInt() ?? 0;
    final free = _amountValue <= 0;

    return Stack(children: [
      RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 110), children: [
          AppHero(
            title: t('إعدادات المنصة', 'Platform settings'),
            subtitle: t('المؤسسات، الوقت والمنطقة، والميزات — في مكان واحد.', 'Organizations, time & region, and features — in one place.'),
            icon: Icons.settings_suggest_rounded,
            stats: [
              AppHeroStat(icon: Icons.account_balance_rounded, value: _orgs ? t('مفعّلة', 'On') : t('متوقفة', 'Off'), label: t('المؤسسات', 'Organizations')),
              AppHeroStat(icon: Icons.public_rounded, value: AppTime.zoneInfo(_zone).label, label: t('المنطقة', 'Zone')),
              AppHeroStat(icon: Icons.schedule_rounded, value: _fmt == '24h' ? '24h' : '12h', label: t('الساعة', 'Clock')),
            ],
          ),
          if (!_canEdit) ...[
            const SizedBox(height: 12),
            AppBanner(icon: Icons.visibility_rounded, text: t('عرض فقط — التعديل لمدير المنصة الأعلى.', 'Read only — only the super admin can change these.')),
          ],
          const SizedBox(height: 16),

          // ── 1. Organizations ──────────────────────────────────────────
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PlatformSectionHeader(
                  icon: Icons.account_balance_rounded,
                  title: t('المؤسسات', 'Organizations'),
                  subtitle: t('الجامعات والكليات والمعاهد على المنصة.', 'Universities, faculties and institutes on the platform.')),
              AppSwitchTile(
                icon: Icons.power_settings_new_rounded,
                title: t('تفعيل المؤسسات على المنصة', 'Organizations on this platform'),
                subtitle: _orgs
                    ? t('تظهر لوحات المؤسسات والانضمام وطلبات الإنشاء.', 'Org dashboards, joining and creation requests are available.')
                    : t('مخفية بالكامل لكل المستخدمين — البيانات محفوظة.', 'Hidden for everyone — all data is kept.'),
                value: _orgs,
                onChanged: _canEdit ? (v) => setState(() => _orgs = v) : null,
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
                  onChanged: _canEdit ? (v) => setState(() => _sharing = v) : null,
                ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                child: !_orgs
                    ? const SizedBox(width: double.infinity)
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Divider(height: 24),
                        Text(t('رسوم طلب إنشاء مؤسسة', 'Organization creation fee'),
                            style: appText(14, w: FontWeight.w800, c: c.textDark)),
                        const SizedBox(height: 4),
                        Text(
                            t('تُدفع قبل إرسال الطلب. صفر = مجاني. دفعة واحدة تغطي طلباً واحداً، وإن رُفض الطلب تبقى صالحة لإعادة إرساله.',
                                'Paid before sending the request. 0 = free. One payment covers one request; if it is turned down, the payment stays valid for re-submitting it.'),
                            style: appText(12, c: c.textLight, h: 1.5)),
                        const SizedBox(height: 10),
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
                            const SizedBox(width: 12),
                            Expanded(flex: 2, child: currency),
                          ]);
                        }),
                        if (!free) ...[
                          const SizedBox(height: 10),
                          Text(t('طرق الدفع المقبولة', 'Accepted payment methods'),
                              style: appText(12.5, w: FontWeight.w700, c: c.textMedium)),
                          const SizedBox(height: 4),
                          for (final m in methods) _methodTile(context, m),
                          if (_methods.isEmpty)
                            AppBanner(icon: Icons.warning_amber_rounded, color: c.warning, text: t('اختر طريقة دفع واحدة على الأقل.', 'Pick at least one payment method.')),
                        ],
                        const SizedBox(height: 8),
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
          const SizedBox(height: 16),

          // ── 2. Time & region ─────────────────────────────────────────
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PlatformSectionHeader(
                  icon: Icons.schedule_rounded,
                  title: t('الوقت والمنطقة', 'Time & region'),
                  subtitle: t('الافتراضي لكل المستخدمين — يمكن لكل مؤسسة تغييره لنفسها.', 'Default for everyone — each organization may override it for itself.')),
              RegionEditor(
                zone: _zone,
                timeFormat: _fmt,
                enabled: _canEdit,
                onZone: (v) => setState(() => _zone = v ?? _zone),
                onFormat: (v) => setState(() => _fmt = v ?? _fmt),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // ── 3. Features ──────────────────────────────────────────────
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PlatformSectionHeader(
                  icon: Icons.dashboard_customize_rounded,
                  title: t('الميزات', 'Features'),
                  subtitle: t('إظهار وإخفاء أجزاء التطبيق، وما يمكن لمديري المؤسسات التحكم فيه.',
                      'Show or hide parts of the app, and what organization admins may control.')),
              AppActionCard(
                icon: Icons.toggle_on_rounded,
                title: t('قائمة الميزات', 'Feature list'),
                subtitle: t('بحث، مجموعات، إضافة وحذف', 'Search, groups, add & remove'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminFeaturesPage())),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PlatformSectionHeader(
                  icon: Icons.school_rounded,
                  title: t('بيانات تعلم المصحح الآلي', 'Grader learning data'),
                  subtitle: t('جمع تصحيحات المعلمين (بأسماء مستعارة) لتحسين التصحيح الآلي — للمشرف العام.',
                      'Collect teachers’ corrections (pseudonymous) to improve automatic grading — Super Admin.')),
              AppActionCard(
                icon: Icons.tune_rounded,
                title: t('إعدادات وتصدير بيانات التصحيح', 'Feedback store settings & export'),
                subtitle: t('تفعيل، افتراضي المؤسسات، مدة الاحتفاظ', 'On/off, organizations default, retention'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminFeedbackSettingsPage())),
              ),
            ]),
          ),
        ]),
      ),
      if (_canEdit)
        PositionedDirectional(
          start: 16,
          end: 16,
          bottom: 16,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            offset: _dirty ? Offset.zero : const Offset(0, 2),
            child: SafeArea(
              top: false,
              child: AppPrimaryButton(
                label: t('حفظ التغييرات', 'Save changes'),
                icon: Icons.check_rounded,
                busy: _saving,
                onPressed: _saving || !_dirty ? null : _save,
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _methodTile(BuildContext context, Map<String, dynamic> m) {
    final c = context.colors;
    final id = '${m['id']}';
    final needs = m['currency'] as String?;
    final wrongCurrency = needs != null && needs != _currency;
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
          style: appText(11.5, c: (wrongCurrency || !ready) ? c.warning : c.textLight)),
      value: _methods.contains(id) && !wrongCurrency,
      onChanged: selectable
          ? (v) => setState(() => v ? _methods.add(id) : _methods.remove(id))
          : null,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Fee receipts / payments
// ═════════════════════════════════════════════════════════════════════════════

class AdminOrgFeePaymentsPage extends StatefulWidget {
  const AdminOrgFeePaymentsPage({super.key});

  @override
  State<AdminOrgFeePaymentsPage> createState() => _AdminOrgFeePaymentsPageState();
}

class _AdminOrgFeePaymentsPageState extends State<AdminOrgFeePaymentsPage> {
  String _status = 'review';
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _items = null;
      _error = null;
    });
    final r = await orgCall(() => ApiClient().get('$_path/org-fee/payments',
        queryParams: {if (_status.isNotEmpty) 'status': _status, 'size': 100}), quiet: true);
    if (!mounted) return;
    setState(() {
      _items = r.ok ? asMapList(r.map['items']) : const [];
      _error = r.ok ? null : orgErrorText(r.error!);
    });
  }

  Future<void> _decide(Map<String, dynamic> p, bool approve) async {
    final note = TextEditingController();
    final ok = await showAppSheet<bool>(context, (ctx) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSheetHeader(approve ? t('اعتماد الدفعة', 'Approve payment') : t('رفض الإيصال', 'Reject receipt')),
            AppField(controller: note, label: approve ? t('ملاحظة (اختياري)', 'Note (optional)') : t('السبب — يراه المتقدم', 'Reason — the applicant sees it'), maxLines: 2),
            const SizedBox(height: 12),
            AppPrimaryButton(
                label: approve ? t('اعتماد', 'Approve') : t('رفض', 'Reject'),
                icon: approve ? Icons.check_rounded : Icons.close_rounded,
                onPressed: () => Navigator.pop(ctx, true)),
          ]),
        ));
    if (ok != true) return;
    final r = await orgCall(
        () => ApiClient().post('$_path/org-fee/payments/${p['id']}/${approve ? 'approve' : 'reject'}', body: {'note': note.text.trim()}),
        ok: approve ? t('تم الاعتماد', 'Approved') : t('تم الرفض', 'Rejected'));
    if (r.ok) _load();
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
    return BasePage(
      useWebCard: true,
      maxWith: 900,
      appBar: ScreenAppBar(title: t('إيصالات رسوم المؤسسات', 'Organization fee receipts')),
      child: Column(children: [
        // no fixed height: the chips grow with the text size
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(children: [
            for (final f in filters.entries)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: AppChoiceChip(label: f.value, selected: _status == f.key, onTap: () {
                  _status = f.key;
                  _load();
                }),
              ),
          ]),
        ),
        Expanded(
          child: _items == null
              ? const AppListSkeleton()
              : _error != null
                  ? AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Try again'), onAction: _load)
                  : _items!.isEmpty
                  ? AppEmpty(icon: Icons.inbox_rounded, title: t('لا شيء هنا', 'Nothing here'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _items!.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final p = _items![i];
                          final st = '${p['status']}';
                          final color = switch (st) {
                            'paid' => c.success,
                            'review' => c.warning,
                            'rejected' || 'failed' => c.danger,
                            _ => c.textLight,
                          };
                          return AppCard(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(
                                  child: Text('${p['sender_name'] ?? p['user_name'] ?? p['email'] ?? '#${p['id']}'}',
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14.5, w: FontWeight.w800, c: c.textDark)),
                                ),
                                const SizedBox(width: 8),
                                AppBadgePill(filters[st] ?? st, color: color),
                              ]),
                              const SizedBox(height: 6),
                              Wrap(spacing: 12, runSpacing: 4, children: [
                                Text(money(p['amount'], '${p['currency']}'), style: appText(13, w: FontWeight.w800, c: c.primary)),
                                Text('${p['method']}', style: appText(12, c: c.textMedium)),
                                if (p['email'] != null) Text('${p['email']}', style: appText(12, c: c.textMedium)),
                                if (p['transfer_reference'] != null) Text('#${p['transfer_reference']}', style: appText(12, c: c.textMedium)),
                                if (p['created_at'] != null)
                                  Text(AppTime.dateTime(orgParseUtc(p['created_at'])!), style: appText(12, c: c.textLight)),
                                if (p['org_id'] != null) Text(t('استُخدمت لطلب #${p['org_id']}', 'Used by request #${p['org_id']}'), style: appText(12, c: c.textLight)),
                              ]),
                              if (p['proof_image_url'] != null) ...[
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network('${p['proof_image_url']}', height: 160, width: double.infinity, fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const SizedBox.shrink()),
                                ),
                              ],
                              if (st == 'review' || st == 'pending') ...[
                                const SizedBox(height: 10),
                                Wrap(spacing: 8, runSpacing: 8, children: [
                                  FilledButton.icon(onPressed: () => _decide(p, true), icon: const Icon(Icons.check_rounded), label: Text(t('اعتماد', 'Approve'))),
                                  OutlinedButton.icon(onPressed: () => _decide(p, false), icon: const Icon(Icons.close_rounded), label: Text(t('رفض', 'Reject'))),
                                ]),
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
