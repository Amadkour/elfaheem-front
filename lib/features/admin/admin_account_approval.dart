// lib/features/admin/admin_account_approval.dart
//
// Registration modes (D-1121) in the admin screens: new accounts waiting for a platform admin's approval.
//   • AdminPendingAccountsPage — the queue (waiting / turned down), filter by role, approve / reject with a reason
//   • PendingAccountCard — one account from plain values (what the layout harness tests)
//   • PendingAccountsBanner — "3 accounts waiting for approval" on the users page, from the `admin.users` attention
//     count; hidden at 0
//   • approvalStatus / decideAccount — the user detail sheet's badge and buttons
//
//   GET  /api/v1/admin/accounts/pending?status=pending|rejected&role=   {items, total, ready}
//   POST /api/v1/admin/users/{id}/approve · /reject {reason?}
//
// An account of a "pay, then approval" role that has not paid yet is listed with "Has not paid the fee yet" and
// is not counted in the badge; the page reloads on the `attention_changed` event of its tab (a new sign-up, another
// admin's decision), never on a timer.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/live_events.dart';

import '../org/org_creation_fee.dart' show money;
import '../org/org_v3.dart' show orgCall, orgParseUtc;
import 'admin_account_fee_widgets.dart' show accountFeeRoleTitle;
import 'admin_common.dart' show asMapList, t;
import 'admin_labels.dart' show disposeAfterRoute;
import 'admin_page.dart';
import 'adm_kit.dart' show AdmPage;
import 'package:flutter_education_app/config/app_config.dart' show Trans;
import 'cfg_common.dart' show cfgErrorState;

const _pendingPath = '/api/v1/admin/accounts/pending';

String _roleLabel(String role) => switch (role) {
      'parent' => t('ولي أمر', 'Parent'),
      'student' => t('طالب', 'Student'),
      _ => t('معلم', 'Teacher'),
    };

/// `pending` · `rejected` · null (approved, or never asked) for a user row of the admin users list.
String? approvalStatus(Map<String, dynamic> user) {
  if (user['approval_required'] != true || user['approved_at'] != null) return null;
  return user['rejected_at'] != null ? 'rejected' : 'pending';
}

/// Approve, or reject after asking for an optional reason the account sees. True when the server took it.
Future<bool> decideAccount(BuildContext context, int userId, String name, bool approve) async {
  String reason = '';
  if (!approve) {
    final note = TextEditingController();
    final ok = await showAppSheet<bool>(
        context,
        (ctx) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.lg),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AppSheetHeader(t('رفض حساب $name', 'Reject $name')),
                AppField(
                    key: const ValueKey('pending_accounts.reason'),
                    controller: note,
                    label: t('السبب (اختياري) — يراه صاحب الحساب', 'Reason (optional) — the account sees it'),
                    maxLines: 3),
                AppSpace.gapSm,
                AppButton.danger(
                    label: t('رفض الحساب', 'Reject the account'),
                    icon: Icons.person_off_rounded,
                    onPressed: () => Navigator.pop(ctx, true)),
              ]),
            ));
    reason = note.text.trim();
    disposeAfterRoute([note]);
    if (ok != true) return false;
  }
  final r = await orgCall(
      () => ApiClient().post('/api/v1/admin/users/$userId/${approve ? 'approve' : 'reject'}',
          body: approve ? const {} : {'reason': reason}),
      ok: approve ? t('تمت الموافقة على الحساب', 'Account approved') : t('تم رفض الحساب', 'Account rejected'));
  if (r.ok) unawaited(AttentionService.instance.refresh());
  return r.ok;
}

// ═════════════════════════════════════════════════════════════════════════════
//  The queue
// ═════════════════════════════════════════════════════════════════════════════

class AdminPendingAccountsPage extends StatefulWidget {
  const AdminPendingAccountsPage({super.key});

  @override
  State<AdminPendingAccountsPage> createState() => _AdminPendingAccountsPageState();
}

class _AdminPendingAccountsPageState extends State<AdminPendingAccountsPage> {
  String _status = 'pending';
  String _role = '';
  List<Map<String, dynamic>>? _items;
  int _total = 0;
  String? _error;
  final _busy = <int>{};
  StreamSubscription<LiveEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = LiveEvents.instance.listen({LiveEvents.attentionChanged}, (e) {
      if (e.data['tab'] == AttentionTabs.adminUsers) _load(keep: true);
    });
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool keep = false}) async {
    if (!keep) {
      setState(() {
        _items = null;
        _error = null;
      });
    }
    final r = await orgCall(
        () => ApiClient().get(_pendingPath,
            queryParams: {'status': _status, if (_role.isNotEmpty) 'role': _role, 'size': 100}),
        quiet: true);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _items = asMapList(r.map['items']);
        _total = (r.map['total'] as num?)?.toInt() ?? _items!.length;
        _error = null;
      } else if (_items == null) {
        _error = r.error?.message;
      }
    });
  }

  Future<void> _decide(Map<String, dynamic> u, bool approve) async {
    final id = (u['id'] as num).toInt();
    setState(() => _busy.add(id));
    final ok = await decideAccount(context, id, '${u['name'] ?? ''}', approve);
    if (!mounted) return;
    setState(() => _busy.remove(id));
    if (ok) _load(keep: true);
  }

  @override
  Widget build(BuildContext context) {
    final statuses = {'pending': t('بانتظار الموافقة', 'Waiting'), 'rejected': t('مرفوضة', 'Rejected')};
    final roles = {'': t('كل الأدوار', 'All roles'), 'teacher': t('معلمون', 'Teachers'), 'parent': t('أولياء أمور', 'Parents'), 'student': t('طلاب', 'Students')};
    return AdmPage(
      kicker: 'a1_group_approvals'.tr,
      title: t('حسابات تنتظر الموافقة', 'Accounts waiting for approval'),
      icon: Icons.how_to_reg_rounded,
      // redesign A1 (AdmApprovals accounts): how many wait, as the hero's headline
      headline: _items == null
          ? t('حسابات تنتظر الموافقة', 'Accounts waiting for approval')
          : countText(_total,
              ar0: 'ما فيه حسابات تنتظرك', ar1: 'حساب جديد واحد ينتظرك', ar2: 'حسابين جديدين ينتظرونك', arFew: '{n} حسابات جديدة تنتظرك', arMany: '{n} حساب جديد ينتظرك',
              en0: 'No account waits for you', en1: 'One new account waits for you', en: '{n} new accounts wait for you'),
      subtitle: t('معلمين وأولياء أمور سجّلوا وينتظرون موافقة الإدارة قبل ما يبدون.',
          'Teachers and parents who signed up and wait for the admins before they start.'),
      onRefresh: () => _load(keep: _items != null),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.fromLTRB(AppSpace.gutter(MediaQuery.sizeOf(context).width), AppSpace.sm, AppSpace.md, AppSpace.xs),
          child: Row(children: [
            for (final f in statuses.entries)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
                child: AppChoiceChip(
                    key: ValueKey('pending_accounts.status.${f.key}'),
                    label: f.value,
                    selected: _status == f.key,
                    onTap: () {
                      _status = f.key;
                      _load();
                    }),
              ),
            const SizedBox(width: AppSpace.sm),
            for (final f in roles.entries)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
                child: AppChoiceChip(
                    label: f.value,
                    selected: _role == f.key,
                    onTap: () {
                      _role = f.key;
                      _load();
                    }),
              ),
          ]),
        ),
        Expanded(
          child: _items == null
              ? (_error != null ? cfgErrorState(_error, onRetry: _load) : const AppListSkeleton())
              : _items!.isEmpty
                  ? AppEmpty(
                      icon: Icons.how_to_reg_rounded,
                      title: _status == 'pending'
                          ? t('لا حسابات تنتظر الموافقة', 'No accounts waiting')
                          : t('لا حسابات مرفوضة', 'No rejected accounts'),
                      message: t('تظهر هنا الحسابات الجديدة للأدوار التي تحتاج موافقة الإدارة.',
                          'New accounts of the roles that need an admin\'s approval show here.'))
                  : AppRefresh(
                      onRefresh: () => _load(keep: true),
                      child: ListView.separated(
                        padding: AdminPage.bodyPadding(context),
                        itemCount: _items!.length,
                        separatorBuilder: (_, _) => AppSpace.gapSm,
                        itemBuilder: (_, i) {
                          final u = _items![i];
                          final id = (u['id'] as num).toInt();
                          return PendingAccountCard(
                            user: u,
                            busy: _busy.contains(id),
                            onApprove: () => _decide(u, true),
                            onReject: u['rejected_at'] == null ? () => _decide(u, false) : null,
                          );
                        },
                      ),
                    ),
        ),
      ]),
    );
  }
}

/// One account of the queue: name, role, contact, when it signed up, the fee state, the reason it was turned down.
class PendingAccountCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final bool busy;
  final VoidCallback onApprove;

  /// null: already rejected (it can still be approved).
  final VoidCallback? onReject;

  const PendingAccountCard({super.key, required this.user, required this.onApprove, this.onReject, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final role = '${user['role'] ?? ''}';
    final feeDue = user['fee_due'] == true;
    final paid = user['account_fee_paid_at'] != null;
    final rejected = user['rejected_at'] != null;
    final reason = '${user['rejection_reason'] ?? ''}'.trim();
    final created = orgParseUtc(user['created_at']);
    final contact = [user['gmail'], user['phone']].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
    return AppCard(
      key: ValueKey('pending_accounts.${user['id']}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${user['name'] ?? '#${user['id']}'}',
            maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
        if (contact.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(contact, maxLines: 2, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.meta(context)),
        ],
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AppStatusBadge(label: _roleLabel(role), tone: AppTone.neutral),
          if (rejected)
            AppStatusBadge(label: t('مرفوض', 'Rejected'), tone: AppTone.danger)
          else
            AppStatusBadge(label: t('بانتظار الموافقة', 'Waiting'), tone: AppTone.warning),
          if (feeDue)
            AppStatusBadge(
                key: const ValueKey('pending_accounts.fee_due'),
                label: t('لم يدفع الرسوم بعد · ${money(user['fee_amount'], '${user['fee_currency'] ?? ''}')}',
                    'Has not paid the fee yet · ${money(user['fee_amount'], '${user['fee_currency'] ?? ''}')}'),
                tone: AppTone.warning)
          else if (paid)
            AppStatusBadge(label: t('دفع الرسوم', 'Fee paid'), tone: AppTone.success),
          if (created != null) Text(t('سجّل ${AppTime.dateTime(created)}', 'Signed up ${AppTime.dateTime(created)}'), style: AppType.meta(context)),
        ]),
        if (rejected && reason.isNotEmpty) ...[
          AppSpace.gapXs,
          Text(t('السبب: $reason', 'Reason: $reason'), style: AppType.meta(context).copyWith(color: c.danger)),
        ],
        if (feeDue) ...[
          AppSpace.gapXs,
          Text(t('${accountFeeRoleTitle(role)}: يدفع الحساب أولاً ثم يُوافق عليه.', '${accountFeeRoleTitle(role)}: the account pays first, then is approved.'),
              style: AppType.meta(context)),
        ],
        AppSpace.gapSm,
        LayoutBuilder(builder: (context, box) {
          final approve = AppButton.primary(
              key: const ValueKey('pending_accounts.approve'),
              expand: true,
              label: t('موافقة', 'Approve'),
              icon: Icons.check_rounded,
              onPressed: busy ? null : onApprove);
          if (onReject == null) return approve;
          final reject = AppButton.secondary(
              key: const ValueKey('pending_accounts.reject'),
              expand: true,
              label: t('رفض', 'Reject'),
              icon: Icons.close_rounded,
              onPressed: busy ? null : onReject);
          if (box.maxWidth < 360) return Column(children: [approve, AppSpace.gapXs, reject]);
          return Row(children: [Expanded(child: approve), AppSpace.gapXs, Expanded(child: reject)]);
        }),
      ]),
    );
  }
}

/// "3 accounts waiting for approval · Review" above the users list; nothing at 0.
class PendingAccountsBanner extends StatelessWidget {
  const PendingAccountsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AttentionService.instance,
      builder: (context, _) {
        final n = AttentionService.instance.count(AttentionTabs.adminUsers);
        if (n <= 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: PendingAccountsBannerView(
            count: n,
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const AdminPendingAccountsPage())),
          ),
        );
      },
    );
  }
}

class PendingAccountsBannerView extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const PendingAccountsBannerView({super.key, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppActionCard(
      key: const ValueKey('pending_accounts.banner'),
      icon: Icons.how_to_reg_rounded,
      title: countText(count,
          ar1: 'حساب جديد ينتظر موافقتك', ar2: 'حسابان جديدان ينتظران موافقتك', arFew: '{n} حسابات جديدة تنتظر موافقتك',
          arMany: '{n} حساباً جديداً ينتظر موافقتك', en1: '1 new account waiting for your approval',
          en: '{n} new accounts waiting for your approval'),
      subtitle: t('راجع وافق أو ارفض', 'Review: approve or reject'),
      color: c.warning,
      onTap: onTap,
    );
  }
}
