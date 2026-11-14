// lib/features/org/org_danger_zone.dart
//
// The destructive organization actions, shared by the Super Admin's organization page and the org admin's Settings
// ("Danger zone"):
//   orgNameConfirmed / orgReasonOk     pure checks (unit-tested): the typed name must equal the organization's Arabic or
//                                       English name, a reason has at least 5 characters
//   askTypedNameConfirm                the dialog: type the organization's name (and a reason) before the button wakes up
//   showOrgTransferAdmin               pick a live member as the new admin and say what happens to the old one
//                                       platform: POST /api/v1/admin/orgs/{id}/transfer-admin   (C4, platform admins)
//                                       org admin: POST /api/v1/org/orgs/{id}/transfer-admin    (C4, the current admin only)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import 'org_v3.dart';

/// True when [typed] is the organization's Arabic or English name (trimmed, case-insensitive, inner spaces folded).
bool orgNameConfirmed(String typed, Map<String, dynamic> org) {
  String norm(Object? s) => '$s'.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  final x = norm(typed);
  if (x.isEmpty) return false;
  return [org['name_ar'], org['name_en']].map(norm).where((n) => n.isNotEmpty).contains(x);
}

bool orgReasonOk(String reason, {int min = 5}) => reason.trim().length >= min;

/// The new admin's old seat: keep them as staff, or take them out.
const orgOldAdminChoices = ['staff', 'remove'];

/// The body of a transfer-admin call (C4).
Map<String, dynamic> orgTransferBody({required int userId, required String oldAdmin, required String reason}) =>
    {'user_id': userId, 'old_admin': orgOldAdminChoices.contains(oldAdmin) ? oldAdmin : 'staff', 'reason': reason.trim()};

/// Asks the person to type [org]'s name (and, with [askReason], a reason of 5+ characters). Returns the reason
/// ('' when none was asked), or null when cancelled. The confirm button stays off until the name matches.
Future<String?> askTypedNameConfirm(
  BuildContext context, {
  required Map<String, dynamic> org,
  required String title,
  required String body,
  required String confirmLabel,
  bool askReason = true,
}) {
  return showAppDialog<String>(
    context,
    title: title,
    icon: Icons.warning_amber_rounded,
    danger: true,
    body: _TypedNameBody(org: org, body: body, confirmLabel: confirmLabel, askReason: askReason),
  );
}

class _TypedNameBody extends StatefulWidget {
  const _TypedNameBody({required this.org, required this.body, required this.confirmLabel, required this.askReason});
  final Map<String, dynamic> org;
  final String body, confirmLabel;
  final bool askReason;

  @override
  State<_TypedNameBody> createState() => _TypedNameBodyState();
}

class _TypedNameBodyState extends State<_TypedNameBody> {
  final _name = TextEditingController(), _reason = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _reason.dispose();
    super.dispose();
  }

  bool get _ok => orgNameConfirmed(_name.text, widget.org) && (!widget.askReason || orgReasonOk(_reason.text));

  @override
  Widget build(BuildContext context) {
    final shown = t('${widget.org['name_ar'] ?? ''}'.isNotEmpty ? '${widget.org['name_ar']}' : '${widget.org['name_en']}',
        '${widget.org['name_en'] ?? ''}'.isNotEmpty ? '${widget.org['name_en']}' : '${widget.org['name_ar']}');
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.body, style: AppType.body(context)),
      AppSpace.gapSm,
      Text(t('اكتب اسم المؤسسة للتأكيد: $shown', 'Type the organization\'s name to confirm: $shown'), style: AppType.bodyStrong(context)),
      AppSpace.gapXs,
      TextField(
        key: const ValueKey('danger.name'),
        controller: _name,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(hintText: shown),
      ),
      if (widget.askReason) ...[
        AppSpace.gapSm,
        TextField(
          key: const ValueKey('danger.reason'),
          controller: _reason,
          minLines: 2,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: t('السبب (5 أحرف على الأقل)', 'Reason (at least 5 characters)')),
        ),
      ],
      AppSpace.gapMd,
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, alignment: WrapAlignment.end, children: [
        AppButton.ghost(label: t('إلغاء', 'Cancel'), onPressed: () => Navigator.pop(context)),
        AppButton.danger(
          key: const ValueKey('danger.confirm'),
          label: widget.confirmLabel,
          icon: Icons.delete_outline_rounded,
          onPressed: _ok ? () => Navigator.pop(context, _reason.text.trim()) : null,
        ),
      ]),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Transfer the admin seat
// ═════════════════════════════════════════════════════════════════════════════

/// Opens the transfer sheet. [platform] = the Super Admin's route, else the current org admin's. Returns true when
/// the transfer went through.
Future<bool> showOrgTransferAdmin(BuildContext context,
    {required int orgId, required String orgName, required bool platform}) async {
  final done = await showAppSheet<bool>(context, (ctx) => OrgTransferAdminSheet(orgId: orgId, orgName: orgName, platform: platform));
  return done == true;
}

class OrgTransferAdminSheet extends StatefulWidget {
  const OrgTransferAdminSheet({super.key, required this.orgId, required this.orgName, required this.platform});
  final int orgId;
  final String orgName;
  final bool platform;

  @override
  State<OrgTransferAdminSheet> createState() => _OrgTransferAdminSheetState();
}

class _OrgTransferAdminSheetState extends State<OrgTransferAdminSheet> {
  final _reason = TextEditingController();
  List<Map<String, dynamic>> _members = [];
  bool _loading = true, _busy = false;
  String? _loadError, _error;
  int? _userId;
  String _old = 'staff';
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final r = await orgCall(
        () => ApiClient().get('/api/v1/org/orgs/${widget.orgId}/members',
            queryParams: {'status': 'active', 'size': 30, if (q.trim().isNotEmpty) 'search': q.trim()}),
        quiet: true);
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _members = asMapList(r.map['items']);
      } else {
        _loadError = orgErrorText(r.error!);
      }
    });
  }

  bool get _canSend => _userId != null && orgReasonOk(_reason.text);

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final path = widget.platform
        ? '/api/v1/admin/orgs/${widget.orgId}/transfer-admin'
        : '/api/v1/org/orgs/${widget.orgId}/transfer-admin';
    final r = await orgCall(
        () => ApiClient().post(path, body: orgTransferBody(userId: _userId!, oldAdmin: _old, reason: _reason.text)),
        quiet: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) return setState(() => _error = orgErrorText(r.error!));
    final admin = asMap(r.map['admin']);
    showAppNotice(admin['name'] == null
        ? t('تم نقل إدارة المؤسسة', 'The admin seat was transferred')
        : t('${admin['name']} هو مدير المؤسسة الآن', '${admin['name']} is now the organization admin'));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppSheetContent(
      title: t('تغيير مدير المؤسسة', 'Change the organization admin'),
      children: [
        Text(
            t('اختر عضواً نشطاً في «${widget.orgName}» ليصبح المدير. لا يُحذف أي عضو.',
                'Pick an active member of "${widget.orgName}" to become the admin. Nobody is deleted.'),
            style: AppType.body(context)),
        AppSpace.gapSm,
        AppSearchField(hint: t('ابحث بالاسم أو البريد', 'Search by name or e-mail'), onChanged: _load),
        AppSpace.gapSm,
        if (_loading)
          const AppListSkeleton(items: 3)
        else if (_loadError != null)
          AppErrorState(message: _loadError, onRetry: () => _load(''), compact: true)
        else if (_members.isEmpty)
          AppEmpty(
              icon: Icons.group_off_rounded,
              title: t('لا يوجد أعضاء نشطون', 'No active members'),
              message: t('أضف الشخص إلى المؤسسة أولاً.', 'Add the person to the organization first.'))
        else
          for (final m in _members) _pick(context, m),
        AppSpace.gapSm,
        Text(t('ماذا يحدث للمدير الحالي؟', 'What happens to the current admin?'), style: AppType.bodyStrong(context)),
        AppSpace.gapXs,
        Text(t('«إداري مساعد»: يبقى عضواً بصلاحيات أقل. «تنتهي عضويته»: يفقد الوصول إلى المؤسسة.', '"Administrative staff": stays a member with fewer rights. "Membership ends": loses access to the organization.'), style: AppType.meta(context)),
        AppSpace.gapXs,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppChoiceChip(
              label: t('يبقى كإداري مساعد', 'Stays as administrative staff'),
              selected: _old == 'staff',
              onTap: () => setState(() => _old = 'staff')),
          AppChoiceChip(
              label: t('تنتهي عضويته في المؤسسة', 'Membership ends (removed)'),
              selected: _old == 'remove',
              onTap: () => setState(() => _old = 'remove')),
        ]),
        AppSpace.gapSm,
        TextField(
          key: const ValueKey('transfer.reason'),
          controller: _reason,
          minLines: 2,
          maxLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              labelText: t('السبب (5 أحرف على الأقل)', 'Reason (at least 5 characters)')),
        ),
        if (_error != null) ...[
          AppSpace.gapSm,
          Text(_error!, style: AppType.meta(context).copyWith(color: c.danger)),
        ],
        AppSpace.gapMd,
        AppButton.primary(
          key: const ValueKey('transfer.send'),
          label: t('نقل الإدارة', 'Transfer the admin seat'),
          icon: Icons.swap_horiz_rounded,
          busy: _busy,
          expand: true,
          onPressed: _canSend && !_busy ? _send : null,
        ),
      ],
    );
  }

  Widget _pick(BuildContext context, Map<String, dynamic> m) {
    final c = context.colors;
    final u = asMap(m['user']);
    final id = asInt(u['id'] ?? m['user_id']);
    final sel = _userId == id && id != 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xxs),
      child: InkWell(
        borderRadius: AppRadius.cardAll,
        onTap: id == 0 ? null : () => setState(() => _userId = id),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
            child: Row(children: [
              Icon(sel ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: sel ? c.primary : c.textLight, size: AppIconSize.md),
              AppSpace.gapSm,
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${u['name'] ?? m['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                  Text('${u['email'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.meta(context)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
