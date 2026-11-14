// lib/features/org/org_status_screen.dart
//
// What an organization admin sees while the organization is NOT approved yet (pending · rejected · suspended):
// a calm, human status page instead of errors — a 3-step timeline, the reviewer's note, when the application was
// sent, where the creation fee stands (paid · receipt under review · not paid) and the actions that move things
// forward (edit the application · resubmit · contact the platform team). The page follows the server: it reloads on
// `org_access_changed` and polls slowly as the fallback (EventOrPoll), so an approval shows without a manual refresh.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' hide money;
import '../admin/admin_list.dart' show IconBadge;
import 'package:flutter_education_app/features/profile/about/about_and_terms_screen.dart' show AboutScreen;
import 'org_common.dart';
import 'org_creation_fee.dart' show money;
import 'org_dashboard_screen.dart' show showOrgForm, showOrgSwitcher;
import 'org_providers.dart';
import 'org_ui.dart';
import 'org_v3.dart' show orgCall, orgParseUtc;
import 'package:flutter_education_app/features/profile/profile_provider.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_refresh.dart';
import 'package:flutter_education_app/design/app_icons.dart';

/// Where the creation fee stands for the signed-in applicant, from `GET /org/creation-fee`:
/// `free` (no fee is set) · `paid` (a usable payment) · `review` (a receipt waits for the platform) · `unpaid`.
/// Null = unknown (the call failed or the server has no fee route): the page then says nothing about the fee.
String? orgFeeState(Map<String, dynamic>? s) {
  if (s == null) return null;
  if (s['required'] != true) return 'free';
  final p = asMap(s['payment']);
  if (p['usable'] == true) return 'paid';
  if ('${p['status']}' == 'review') return 'review';
  return 'unpaid';
}

/// What the status page offers, by organization status (pure, unit-tested).
({bool edit, bool resubmit, bool contact}) orgStatusActions(String status) => (
      edit: status != 'suspended',
      resubmit: status == 'rejected',
      contact: status == 'rejected' || status == 'suspended',
    );

class OrgStatusScreen extends StatefulWidget {
  const OrgStatusScreen({super.key});

  @override
  State<OrgStatusScreen> createState() => _OrgStatusScreenState();
}

class _OrgStatusScreenState extends State<OrgStatusScreen> {
  bool _busy = false;
  Map<String, dynamic>? _fee;
  EventOrPoll? _watch;

  @override
  void initState() {
    super.initState();
    _loadFee();
    // follows the review: the event when the stream is open, a slow poll otherwise
    _watch = EventOrPoll(
      poll: _silent,
      every: const Duration(seconds: 20),
      fallbackEvery: const Duration(seconds: 90),
      names: {LiveEvents.orgAccessChanged},
    )..start();
  }

  @override
  void dispose() {
    _watch?.dispose();
    super.dispose();
  }

  Future<void> _silent() async {
    if (!mounted) return;
    await context.read<OrgSession>().load();
    await _loadFee();
  }

  Future<void> _loadFee() async {
    final r = await orgCall(() => ApiClient().get('/api/v1/org/creation-fee'), quiet: true);
    if (mounted) setState(() => _fee = r.ok ? r.map : null);
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    await _silent();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    final org = s.current!;
    final c = context.colors;
    final status = s.status;
    final note = '${org['review_note'] ?? ''}'.trim();
    final acts = orgStatusActions(status);
    final sent = orgParseUtc('${org['submitted_at'] ?? org['created_at'] ?? ''}');
    final fee = orgFeeState(_fee);
    final (IconData icon, Color tone, String title, String body) = switch (status) {
      'rejected' => (
          Icons.edit_note_rounded,
          c.warning,
          t('طلبك يحتاج بعض التعديلات', 'Your application needs a few changes'),
          t('راجع ملاحظة فريق المنصة بالأسفل، عدّل البيانات ثم أعد الإرسال — عادةً ما تكون المراجعة الثانية أسرع.',
              'Read the review note below, update the details and resubmit — the second review is usually quicker.'),
        ),
      'suspended' => (
          Icons.pause_circle_rounded,
          c.danger,
          t('المؤسسة موقوفة مؤقتاً', 'This organization is paused'),
          t('بيانات مؤسستك محفوظة بالكامل ولم يُحذف شيء. تواصل مع إدارة المنصة لإعادة التفعيل.',
              'All your data is safe — nothing was deleted. Contact the platform team to reactivate it.'),
        ),
      _ => (
          Icons.hourglass_top_rounded,
          c.primary,
          t('شكراً لك! طلبك قيد المراجعة', 'Thank you! Your application is under review'),
          t('يتحقق فريق المنصة من بيانات المؤسسة لحماية الطلاب والمعلمين. سنرسل لك إشعاراً فور الاعتماد — يمكنك تحسين البيانات في هذه الأثناء.',
              "We're verifying your organization to keep students and teachers safe. You'll get a notification as soon as it's approved — you can polish the details meanwhile."),
        ),
    };

    Widget step(int i, String label, {required bool done, required bool active, bool bad = false}) {
      final col = bad ? c.warning : done ? c.success : active ? c.primary : c.divider;
      return Expanded(
        child: Column(children: [
          Row(children: [
            Expanded(child: Container(height: 2, color: i == 0 ? Colors.transparent : col.withValues(alpha: 0.5))),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(shape: BoxShape.circle, color: col.withValues(alpha: done || active || bad ? 1 : 0.3)),
              child: Icon(bad ? Icons.priority_high_rounded : done ? Icons.check_rounded : Icons.circle,
                  color: c.onHero, size: done || bad ? AppIconSize.md - 2 : 8),
            ),
            Expanded(child: Container(height: 2, color: i == 2 ? Colors.transparent : col.withValues(alpha: 0.5))),
          ]),
          AppSpace.gapXs,
          Text(label, textAlign: TextAlign.center, style: AppType.meta(context)),
        ]),
      );
    }

    return AppRefresh(
      onRefresh: _refresh,
      child: ListView(padding: const EdgeInsets.only(bottom: AppSpace.xxl), children: [
        OrgHero(
          org: org,
          subtitle: statusLabel(status),
          trailing: s.items.length > 1
              ? AppIconButton(icon: Icons.swap_horiz_rounded, tooltip: t('تبديل المؤسسة', 'Switch organization'), onPressed: () => showOrgSwitcher(context))
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          child: AppCard(
            padding: const EdgeInsets.all(AppSpace.lg - 4),
            child: Column(children: [
              IconBadge(icon, tone, size: 64),
              AppSpace.gapSm,
              Text(title, textAlign: TextAlign.center, style: AppType.headline(context)),
              AppSpace.gapXs,
              Text(body, textAlign: TextAlign.center, style: AppType.body(context)),
              const SizedBox(height: AppSpace.lg - 2),
              Row(children: [
                step(0, t('أُرسل الطلب', 'Sent'), done: true, active: false),
                step(1, t('المراجعة', 'Review'), done: status == 'suspended', active: status == 'pending', bad: status == 'rejected'),
                step(2, status == 'suspended' ? t('موقوفة', 'Paused') : t('جاهزة للعمل', 'Live'),
                    done: false, active: false, bad: status == 'suspended'),
              ]),
              if (sent != null || (fee != null && fee != 'free')) ...[
                const Divider(height: AppSpace.lg),
                if (sent != null) _InfoLine(icon: Icons.event_available_rounded, label: t('أُرسل الطلب', 'Application sent'), value: AppTime.dateTime(sent)),
                if (fee != null && fee != 'free') _FeeLine(state: fee, amount: money(_fee?['amount'], '${_fee?['currency'] ?? ''}')),
              ],
            ]),
          ),
        ),
        if (note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm + 2, AppSpace.md, 0),
            child: AppBanner(icon: Icons.format_quote_rounded, color: tone, text: '${t('ملاحظة فريق المنصة', 'Note from the platform team')}: $note'),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.lg - 4, AppSpace.md, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (acts.edit)
              AppButton.primary(
                label: t('تعديل بيانات الطلب', 'Edit the application'),
                icon: Icons.edit_rounded,
                expand: true,
                onPressed: () => showOrgForm(context, edit: org),
              ),
            if (acts.resubmit) ...[
              AppSpace.gapXs,
              AppButton.secondary(
                label: t('إعادة الإرسال للمراجعة', 'Resubmit for review'),
                icon: Icons.send_rounded,
                expand: true,
                busy: _busy,
                onPressed: () async {
                  setState(() => _busy = true);
                  await s.resubmit();
                  if (mounted) setState(() => _busy = false);
                },
              ),
            ],
            if (acts.contact) ...[
              AppSpace.gapXs,
              AppButton.tonal(
                key: const ValueKey('status.contact'),
                label: status == 'suspended' ? t('تواصل مع المنصة لإعادة التفعيل', 'Contact the platform team to reactivate') : t('تواصل مع فريق المنصة', 'Contact the platform team'),
                icon: Icons.support_agent_rounded,
                expand: true,
                // ROUTE: profile.about (Contact & support)
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
              ),
            ],
            AppSpace.gapXs,
            AppButton.ghost(
              label: t('تحقق من الحالة الآن', 'Check the status now'),
              icon: Icons.refresh_rounded,
              expand: true,
              onPressed: _busy ? null : _refresh,
            ),
            // A waiting / rejected / suspended org admin can always leave (before: no way out of this screen).
            AppButton.ghost(
              label: 'logout'.tr,
              icon: DirIcons.logout,
              expand: true,
              onPressed: () async {
                if (await confirm(context, message: 'logout_confirm'.tr) && context.mounted) {
                  await context.read<ProfileProvider>().logout(context);
                }
              },
            ),
          ]),
        ),
      ]),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.xs),
        child: Row(children: [
          Icon(icon, size: AppIconSize.md, color: context.colors.textLight),
          AppSpace.gapXs,
          Expanded(child: Text(label, style: AppType.meta(context))),
          Flexible(child: Text(value, textAlign: TextAlign.end, style: AppType.row(context))),
        ]),
      );
}

class _FeeLine extends StatelessWidget {
  const _FeeLine({required this.state, required this.amount});
  final String state, amount;

  @override
  Widget build(BuildContext context) {
    final (String label, AppTone tone) = switch (state) {
      'paid' => (t('مدفوعة', 'Paid'), AppTone.success),
      'review' => (t('الإيصال قيد المراجعة', 'Receipt under review'), AppTone.warning),
      _ => (t('غير مدفوعة', 'Not paid'), AppTone.danger),
    };
    return Row(children: [
      Icon(Icons.receipt_long_rounded, size: AppIconSize.md, color: context.colors.textLight),
      AppSpace.gapXs,
      Expanded(child: Text('${t('رسوم إنشاء المؤسسة', 'Organization fee')} · $amount', style: AppType.meta(context))),
      AppStatusBadge(label: label, tone: tone),
    ]);
  }
}
