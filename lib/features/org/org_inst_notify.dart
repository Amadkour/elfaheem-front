// lib/features/org/org_inst_notify.dart
//
// Institutions v2, phase 2: notification routing on the app side (plan docs/institutions/V2_PLAN.md, back D-985 – D-988).
//   OrgPushPref · orgPushPrefOf     the phone-push setting for organization requests: all · important · off
//   OrgNotifyApi                    GET|PUT …/public/governance/{org}/me/notify-prefs · POST …/units/{dept}/message
//   OrgNotifyPrefsView              plain values: the three choice cards and the "always in the app" sentence
//   OrgNotifyPrefsPage              loads the setting, saves a pick at once (showAppNotice), reverts on failure
//                                  (opened from the member's Organization quick actions and the staff's Settings)
//   unitMessageProblem · unitMessageErrorText   the sheet's check and the server's 403 / 404 texts
//   UnitMessageView                 plain values: optional subject, the message, Send
//   showUnitMessageSheet            "Message this department": sends, tells who is notified, opens the new item
//   OrgDeptLink · orgDeptLinkTarget where a tap on an `org_department` notification goes (pure)
//   openOrgDepartmentLink           AppNavigator's opener for `org_department` (the department dashboard)
//
// In-app notifications are always kept; the setting only changes phone alerts. Tests:
// test/org/institutions_v2_p2_test.dart.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show asInt, asMap, t;
import 'governance/gov_api.dart' show GovApi;
import 'governance/gov_item_screen.dart' show GovItemScreen;
import 'org_department_dashboard.dart' show OrgDepartmentDashboard, departmentTabsOf;
import 'org_page_header.dart' show OrgPushedPage, orgUsesDashboardHeader;
import 'org_providers.dart' show OrgSession;
import 'org_ui.dart' show orgNameOf;
import 'org_v3.dart' show OrgCall, orgCall, orgEndpointMissing, orgErrorText;

// ═════════════════════════════════════════════════════════════════════════════
//  Pure parts
// ═════════════════════════════════════════════════════════════════════════════

/// The phone-push setting for organization requests. `important` = escalations, overdue, assigned to me, urgent.
enum OrgPushPref { all, important, off }

/// The server's `push` value; anything unknown (an older server) is `all`, the default.
OrgPushPref orgPushPrefOf(Object? v) => OrgPushPref.values.firstWhere((p) => p.name == '$v', orElse: () => OrgPushPref.all);

/// The check of the message sheet: null when it may be sent.
String? unitMessageProblem(String body) =>
    body.trim().isEmpty ? t('اكتب رسالتك', 'Write your message') : null;

/// The text of a refused message: the unit's audience excludes me (403), the unit is inactive or a council (422 entity_kind_invalid, or 404), else the usual.
String unitMessageErrorText(ApiException e) {
  if (e.statusCode == 403 && (e.code == 'unit_audience' || e.code == 'audience' || e.code == 'forbidden' || e.code == null)) {
    return t('هذه الإدارة لا تستقبل رسائل منك', 'This department does not take messages from you');
  }
  if (e.code == 'entity_kind_invalid' || (e.statusCode == 404 && !orgEndpointMissing(e))) return t('هذه الإدارة لم تعد متاحة', 'This department is no longer available');
  return orgErrorText(e);
}

/// Where an `org_department` notification goes.
enum OrgDeptLink { notifications, departments, dashboard }

/// [manages]: the organization is one I manage (staff). Organizations off, the departments switched off, or a
/// member → the notifications list; a staff tap without a department id → the departments list.
OrgDeptLink orgDeptLinkTarget({
  required int? deptId,
  required int? orgId,
  required bool orgsEnabled,
  required List<String> disabled,
  required bool manages,
}) {
  if (!orgsEnabled || orgId == null || disabled.contains('org.departments') || !manages) return OrgDeptLink.notifications;
  return deptId == null ? OrgDeptLink.departments : OrgDeptLink.dashboard;
}

// ═════════════════════════════════════════════════════════════════════════════
//  API
// ═════════════════════════════════════════════════════════════════════════════

class OrgNotifyApi {
  static Future<OrgPushPref> prefs(int orgId, {ApiClient? client}) async =>
      orgPushPrefOf(asMap(await (client ?? ApiClient()).get('${GovApi.memberBase}/$orgId/me/notify-prefs'))['push']);

  static Future<OrgPushPref> savePrefs(int orgId, OrgPushPref p, {ApiClient? client}) async {
    final r = asMap(await (client ?? ApiClient()).put('${GovApi.memberBase}/$orgId/me/notify-prefs', body: {'push': p.name}));
    return r.containsKey('push') ? orgPushPrefOf(r['push']) : p;
  }

  /// → the new item's id (null when an older server does not say).
  static Future<int?> messageUnit(int orgId, int deptId, {String? subject, required String body, ApiClient? client}) async {
    final r = asMap(await (client ?? ApiClient()).post('${GovApi.memberBase}/$orgId/units/$deptId/message', body: {
      if (subject != null && subject.trim().isNotEmpty) 'subject': subject.trim(),
      'body': body.trim(),
    }));
    return r['item_id'] == null ? null : asInt(r['item_id']);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Notification settings
// ═════════════════════════════════════════════════════════════════════════════

/// The three choice cards. [value] null = still loading (the cards show, none selected); [saving] dims the others.
class OrgNotifyPrefsView extends StatelessWidget {
  const OrgNotifyPrefsView({super.key, required this.value, required this.onPick, this.saving = false});
  final OrgPushPref? value;
  final ValueChanged<OrgPushPref> onPick;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final options = <(OrgPushPref, IconData, String, String)>[
      (OrgPushPref.all, Icons.notifications_active_rounded, t('كل التنبيهات', 'All'),
          t('تنبيه على الهاتف لكل طلب أو رد أو تحديث', 'A phone alert for every request, reply and update')),
      (OrgPushPref.important, Icons.priority_high_rounded, t('المهم فقط', 'Important only'),
          t('التصعيد والمتأخر وما أُسند إليّ والعاجل', 'Escalations, overdue, assigned to me and urgent')),
      (OrgPushPref.off, Icons.notifications_off_rounded, t('إيقاف', 'Off'),
          t('لا تنبيهات على الهاتف من طلبات المؤسسة', 'No phone alerts for organization requests')),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppBanner(
        key: const ValueKey('org.notify.always'),
        icon: Icons.info_outline_rounded,
        color: c.primary,
        text: t('ستراها دائماً داخل التطبيق؛ هذا يغيّر تنبيهات الهاتف فقط.', 'You always see them in the app; this only changes phone alerts.'),
      ),
      const SizedBox(height: AppSpace.sm),
      for (final o in options)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: _ChoiceCard(
            key: ValueKey('org.notify.${o.$1.name}'),
            icon: o.$2,
            title: o.$3,
            subtitle: o.$4,
            selected: value == o.$1,
            onTap: saving || value == o.$1 ? null : () => onPick(o.$1),
          ),
        ),
    ]);
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({super.key, required this.icon, required this.title, required this.subtitle, required this.selected, this.onTap});
  final IconData icon;
  final String title, subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.card);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? c.primaryWash : c.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: selected ? c.primary : c.divider, width: selected ? AppBorder.focus : AppBorder.hairline),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Row(children: [
                Icon(icon, size: AppIconSize.lg, color: selected ? c.primary : c.textMedium),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
                    const SizedBox(height: AppSpace.xxs),
                    Text(subtitle, style: AppType.meta(context).copyWith(color: c.textMedium)),
                  ]),
                ),
                const SizedBox(width: AppSpace.xs),
                Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    size: AppIconSize.md, color: selected ? c.primary : c.textMedium),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Organization notifications": loads `push`, saves each pick immediately.
class OrgNotifyPrefsPage extends StatefulWidget {
  const OrgNotifyPrefsPage({super.key, required this.orgId, this.embedded = false, this.client});
  final int orgId;
  final ApiClient? client;

  /// Inside a page that already draws the header (orgPush): the body only.
  final bool embedded;

  static String title() => t('إشعارات المؤسسة', 'Organization notifications');

  @override
  State<OrgNotifyPrefsPage> createState() => _OrgNotifyPrefsPageState();
}

class _OrgNotifyPrefsPageState extends State<OrgNotifyPrefsPage> {
  OrgPushPref? _value;
  bool _loading = true, _saving = false;
  OrgCall? _failed;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = null;
    });
    final r = await orgCall(() => OrgNotifyApi.prefs(widget.orgId, client: widget.client), quiet: true);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _value = r.data as OrgPushPref;
      } else {
        _failed = r;
      }
    });
  }

  Future<void> _pick(OrgPushPref p) async {
    final before = _value;
    setState(() {
      _value = p;
      _saving = true;
    });
    final r = await orgCall(() => OrgNotifyApi.savePrefs(widget.orgId, p, client: widget.client), quiet: true);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _value = r.ok ? r.data as OrgPushPref : before;
    });
    showAppNotice(r.ok ? t('تم الحفظ', 'Saved') : orgErrorText(r.error!), error: !r.ok);
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (_loading) {
      content = const AppListSkeleton(items: 3);
    } else if (_failed != null) {
      content = AppEmpty(
        icon: Icons.cloud_off_rounded,
        title: _failed!.endpointMissing ? t('غير متاح بعد', 'Not available yet') : t('تعذّر التحميل', 'Could not load'),
        message: _failed!.endpointMissing ? t('يحتاج تحديث الخادم', 'The server needs an update') : orgErrorText(_failed!.error!),
        actionLabel: t('إعادة المحاولة', 'Retry'),
        onAction: _load,
      );
    } else {
      content = ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xl),
        children: [OrgNotifyPrefsView(value: _value, saving: _saving, onPick: _pick)],
      );
    }
    if (widget.embedded) return content;
    if (orgUsesDashboardHeader(context, widget.orgId)) {
      return OrgPushedPage(title: OrgNotifyPrefsPage.title(), width: AppWidth.form, child: content);
    }
    return BasePage(useWebCard: true, width: AppWidth.form, appBar: ScreenAppBar(title: OrgNotifyPrefsPage.title()), child: content);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Message this department
// ═════════════════════════════════════════════════════════════════════════════

class UnitMessageView extends StatelessWidget {
  const UnitMessageView({
    super.key,
    required this.deptName,
    required this.subject,
    required this.body,
    required this.onSend,
    this.busy = false,
    this.error,
  });

  final String deptName;
  final TextEditingController subject, body;
  final VoidCallback onSend;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppSheetContent(
      title: t('مراسلة الإدارة', 'Message the department'),
      subtitle: deptName,
      icon: Icons.forward_to_inbox_rounded,
      children: [
        Text(t('تصل رسالتك إلى رئيس الإدارة، وتتابعها من معاملاتي.', 'Your message reaches the head of the department; follow it in My items.'),
            style: AppType.meta(context).copyWith(color: c.textMedium)),
        const SizedBox(height: AppSpace.sm),
        AppField(
          key: const ValueKey('unit.msg.subject'),
          controller: subject,
          label: t('الموضوع (اختياري)', 'Subject (optional)'),
          icon: Icons.short_text_rounded,
          maxLength: 200,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpace.xs),
        AppField(
          key: const ValueKey('unit.msg.body'),
          controller: body,
          label: t('الرسالة', 'Message'),
          icon: Icons.chat_bubble_outline_rounded,
          required: true,
          maxLines: 5,
          maxLength: 4000,
          errorText: error,
        ),
        const SizedBox(height: AppSpace.sm),
        AppPrimaryButton(
          key: const ValueKey('unit.msg.send'),
          label: t('إرسال', 'Send'),
          icon: Icons.send_rounded,
          busy: busy,
          onPressed: busy ? null : onSend,
        ),
      ],
    );
  }
}

/// "Message this department" → POST, the notice "Sent — the head of X will be notified", then the new item (member
/// view) so the sender can track it. Returns the item id, null when nothing was sent.
Future<int?> showUnitMessageSheet(BuildContext context, {required int orgId, required Map<String, dynamic> dept, ApiClient? client}) async {
  final name = orgNameOf(dept);
  final nav = Navigator.of(context);
  final r = await showAppSheet<_Sent>(context, (ctx) => _UnitMessageSheet(orgId: orgId, deptId: asInt(dept['id']), name: name, client: client));
  if (r == null) return null;
  showAppNotice(t('أُرسلت — سيُبلَّغ رئيس $name', 'Sent — the head of $name will be notified'));
  final id = r.itemId;
  if (id != null && nav.mounted) unawaited(nav.push(MaterialPageRoute(builder: (_) => GovItemScreen(id, orgId: orgId, member: true))));
  return id;
}

class _Sent {
  const _Sent(this.itemId);
  final int? itemId;
}

/// Owns the fields (disposed with the sheet, after its closing animation) and the send.
class _UnitMessageSheet extends StatefulWidget {
  const _UnitMessageSheet({required this.orgId, required this.deptId, required this.name, this.client});
  final int orgId, deptId;
  final String name;
  final ApiClient? client;

  @override
  State<_UnitMessageSheet> createState() => _UnitMessageSheetState();
}

class _UnitMessageSheetState extends State<_UnitMessageSheet> {
  final _subject = TextEditingController(), _body = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final problem = unitMessageProblem(_body.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await orgCall(
        () => OrgNotifyApi.messageUnit(widget.orgId, widget.deptId, subject: _subject.text, body: _body.text, client: widget.client),
        quiet: true);
    if (!mounted) return;
    if (r.ok) {
      Navigator.pop(context, _Sent(r.data is int ? r.data as int : null));
      return;
    }
    setState(() {
      _busy = false;
      _error = unitMessageErrorText(r.error!);
    });
  }

  @override
  Widget build(BuildContext context) =>
      UnitMessageView(deptName: widget.name, subject: _subject, body: _body, busy: _busy, error: _error, onSend: _send);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Deep link (AppNavigator `org_department`)
// ═════════════════════════════════════════════════════════════════════════════

/// I manage [orgId] (it is in the dashboard session's list).
bool orgManages(BuildContext ctx, int? orgId) {
  if (orgId == null) return false;
  try {
    return ctx.read<OrgSession>().items.any((o) => asInt(o['id']) == orgId);
  } catch (_) {
    return false;
  }
}

/// The department dashboard of [deptId] (a service department), carrying the organization session.
Future<void> openOrgDepartmentLink(NavigatorState nav, BuildContext ctx, int deptId) {
  final s = ctx.read<OrgSession>();
  final tabs = departmentTabsOf(ctx, 'dept', deptId, null);
  return nav.push(MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider.value(value: s, child: OrgDepartmentDashboard(unitType: 'dept', unitId: deptId, tabs: tabs))));
}
