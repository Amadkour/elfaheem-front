// lib/features/org/org_invitations_pages.dart — the screens of the invitations feature (contract C1, kill switch
// `org.invitations`; pure parts and the API are in org_invitations.dart).
//
// Staff
//   showOrgInviteSheet     "Invite people": e-mail or phone, paste many contacts, role, department / program,
//                          message, expiry → the result (created with Share / Copy per link, skipped with reasons)
//   OrgInvitationsPage     the pending list: status filter, search, resend, cancel, expiry
// Invitee
//   OrgInviteePage         `/i/<token>`: the organization, the role, Accept / Decline; signed out → sign in and back
//   OrgMyInvitationsCard   the invitations addressed to me (`GET /me/invitations`), for the homes
//
// Plain-value widgets (`InviteResultView`, `OrgInvitationCard`, `InviteeView`) are what the layout harness pumps.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart' show AppModeController;
import 'package:flutter_education_app/core/plural.dart' show countText;
import 'package:flutter_education_app/design/context_switcher.dart' show openJoinedOrganization;
import 'package:flutter_education_app/design/app_icons.dart' show DirIcons;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/web_entry_route.dart' show SignInReturn;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../admin/admin_common.dart' show asMap, asMapList, asInt, t;
import 'org_invitations.dart';
import 'org_page_header.dart' show OrgPushedPage;
import 'org_page_kit.dart' show OrgFilterButton, OrgPageBody, OrgPrimaryAction;
import 'org_providers.dart' show OrgSession, orgBase;
import 'org_ui.dart' show orgNameOf;
import 'org_v3.dart';

/// The native share sheet, or a copy when there is none (desktop browsers).
Future<void> shareInviteText(String text) async {
  try {
    // ignore: deprecated_member_use
    await Share.share(text);
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: text));
    showAppNotice(t('نُسخ الرابط', 'Link copied'));
  }
}

Future<void> _copy(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  showAppNotice(t('نُسخ الرابط', 'Link copied'));
}

// ═════════════════════════════════════════════════════════════════════════════
//  Staff: invite
// ═════════════════════════════════════════════════════════════════════════════

/// Opens the "Invite people" sheet of organization [orgId]; resolves with the result once something was created.
Future<InviteResult?> showOrgInviteSheet(BuildContext context, {required int orgId, String orgName = '', String initialRole = 'student', OrgInvitationsApi? api}) =>
    showAppSheet<InviteResult>(
      context,
      (_) => ParentComponent(
        featureKey: invitationsFeatureKey,
        child: OrgInviteSheet(orgId: orgId, orgName: orgName, initialRole: initialRole, api: api),
      ),
    );

class OrgInviteSheet extends StatefulWidget {
  const OrgInviteSheet({super.key, required this.orgId, this.orgName = '', this.initialRole = 'student', this.api});
  final int orgId;
  final String orgName, initialRole;
  final OrgInvitationsApi? api;

  @override
  State<OrgInviteSheet> createState() => _OrgInviteSheetState();
}

class _OrgInviteSheetState extends State<OrgInviteSheet> {
  late final OrgInvitationsApi _api = widget.api ?? OrgInvitationsApi();
  final _contacts = TextEditingController(), _message = TextEditingController();
  String _channel = 'email';
  late String _role = inviteRoles.contains(widget.initialRole) ? widget.initialRole : 'student';
  String _place = ''; // '' · 'd:<id>' · 'p:<id>'
  int _days = inviteDefaultExpiryDays;
  bool _busy = false;
  String? _error;
  InviteResult? _result;
  List<Map<String, dynamic>> _depts = const [], _programs = const [];

  @override
  void initState() {
    super.initState();
    _loadPlaces();
  }

  @override
  void dispose() {
    _contacts.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _loadPlaces() async {
    final base = '$orgBase/orgs/${widget.orgId}';
    final rs = await Future.wait([
      orgCall(() => ApiClient().get('$base/departments'), quiet: true),
      orgCall(() => ApiClient().get('$base/academic/programs'), quiet: true),
    ]);
    if (!mounted) return;
    setState(() {
      _depts = rs[0].ok ? asMapList(rs[0].map['items']) : const [];
      _programs = rs[1].ok ? asMapList(rs[1].map['items']).where((p) => p['is_active'] != false).toList() : const [];
    });
  }

  ContactParse get _parsed => parseContacts(_contacts.text, _channel);

  Future<void> _send() async {
    final p = _parsed;
    if (p.valid.isEmpty) {
      setState(() => _error = p.invalid.isEmpty
          ? t('أضف بريداً أو رقماً واحداً على الأقل', 'Add at least one e-mail or phone number')
          : t('لا يوجد بين ما كتبته عنوان صالح', 'None of what you typed is a valid address'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _api.create(
      widget.orgId,
      inviteBody(
        channel: _channel,
        contacts: p.valid,
        role: _role,
        deptId: _place.startsWith('d:') ? int.tryParse(_place.substring(2)) : null,
        programId: _place.startsWith('p:') ? int.tryParse(_place.substring(2)) : null,
        message: _message.text,
        expiresDays: _days,
      ),
    );
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = false;
        _error = orgErrorText(r.error!);
      });
      return;
    }
    setState(() {
      _busy = false;
      _result = InviteResult.fromJson(r.map);
    });
  }

  @override
  Widget build(BuildContext context) {
    final res = _result;
    if (res != null) {
      return AppSheetContent(
        title: t('نتيجة الدعوات', 'Invitation results'),
        children: [
          InviteResultView(result: res, orgName: widget.orgName, role: _role),
          AppSpace.gapMd,
          AppButton.primary(label: t('تم', 'Done'), expand: true, onPressed: () => Navigator.pop(context, res)),
        ],
      );
    }
    final p = _parsed;
    final c = context.colors;
    return AppSheetContent(
      title: t('دعوة أشخاص', 'Invite people'),
      children: [
        OrgInviteChannelPicker(value: _channel, onChanged: (v) => setState(() => _channel = v)),
        AppSpace.gapSm,
        AppField(
          controller: _contacts,
          label: _channel == 'phone' ? t('أرقام الهاتف (رقم في كل سطر)', 'Phone numbers (one per line)') : t('عناوين البريد (الصقها كلها)', 'E-mail addresses (paste as many as you like)'),
          hint: _channel == 'phone' ? '+201001234567' : 'name@example.com, other@example.com',
          maxLines: 5,
          keyboard: _channel == 'phone' ? TextInputType.phone : TextInputType.emailAddress,
          ltr: true,
          onChanged: (_) => setState(() => _error = null),
        ),
        _ContactSummary(parsed: p),
        AppSpace.gapSm,
        AppDropdown<String>(
          value: _role,
          decoration: InputDecoration(labelText: t('الدور', 'Role')),
          items: [for (final r in inviteRoles) DropdownMenuItem(value: r, child: Text(inviteRoleLabel(r)))],
          onChanged: (v) => setState(() => _role = v ?? _role),
        ),
        if (_depts.isNotEmpty || _programs.isNotEmpty) ...[
          AppSpace.gapSm,
          AppDropdown<String>(
            value: _place,
            decoration: InputDecoration(labelText: t('القسم (اختياري)', 'Department (optional)')),
            items: [
              DropdownMenuItem(value: '', child: Text(t('بدون قسم محدد', 'No specific department'))),
              for (final d in _programs) DropdownMenuItem(value: 'p:${d['id']}', child: Text(orgNameOf(d), overflow: TextOverflow.ellipsis)),
              for (final d in _depts) DropdownMenuItem(value: 'd:${d['id']}', child: Text(orgNameOf(d), overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _place = v ?? ''),
          ),
        ],
        AppSpace.gapSm,
        AppDropdown<int>(
          value: _days,
          decoration: InputDecoration(labelText: t('مدة صلاحية الدعوة', 'Invitation valid for')),
          items: [for (final d in inviteExpiryDays) DropdownMenuItem(value: d, child: Text(t('$d يوماً', '$d days')))],
          onChanged: (v) => setState(() => _days = v ?? _days),
        ),
        AppSpace.gapMd,
        AppField(controller: _message, label: t('رسالة (اختياري)', 'Message (optional)'), maxLines: 3),
        if (_channel == 'phone')
          AppBanner(icon: Icons.info_outline_rounded, color: c.textMedium, text: t('لا نرسل رسائل نصية: شارك الرابط بنفسك بعد الإنشاء.', 'We do not send text messages: share each link yourself after creating them.')),
        if (_error != null) ...[
          AppSpace.gapSm,
          AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!),
        ],
        AppSpace.gapMd,
        AppButton.primary(
          key: const ValueKey('org.invite.send'),
          label: p.valid.isEmpty ? t('إرسال الدعوات', 'Send invitations') : t('إرسال ${p.valid.length}', 'Send ${p.valid.length}'),
          icon: Icons.send_rounded,
          expand: true,
          busy: _busy,
          onPressed: _busy ? null : _send,
        ),
      ],
    );
  }
}

/// E-mail / phone as one segmented choice.
class OrgInviteChannelPicker extends StatelessWidget {
  const OrgInviteChannelPicker({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final ch in inviteChannels)
          ChoiceChip(
            key: ValueKey('org.invite.channel.$ch'),
            avatar: Icon(ch == 'phone' ? Icons.phone_rounded : Icons.mail_rounded, size: AppIconSize.sm),
            label: Text(inviteChannelLabel(ch)),
            selected: value == ch,
            onSelected: (_) => onChanged(ch),
          ),
      ]);
}

class _ContactSummary extends StatelessWidget {
  const _ContactSummary({required this.parsed});
  final ContactParse parsed;

  @override
  Widget build(BuildContext context) {
    if (parsed.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final bits = <Widget>[
      AppStatusBadge(
        label: countText(parsed.valid.length, ar1: 'جهة صالحة', arFew: 'جهات صالحة', arMany: 'جهة صالحة', en1: '1 valid contact', en: '${parsed.valid.length} valid contacts'),
        tone: AppTone.success,
        icon: Icons.check_rounded,
      ),
      if (parsed.invalid.isNotEmpty)
        AppStatusBadge(label: t('${parsed.invalid.length} غير صالح', '${parsed.invalid.length} invalid'), tone: AppTone.danger, icon: Icons.close_rounded),
      if (parsed.duplicates > 0) AppStatusBadge(label: t('${parsed.duplicates} مكرر', '${parsed.duplicates} repeated'), tone: AppTone.neutral),
      if (parsed.overLimit > 0)
        AppStatusBadge(label: t('${parsed.overLimit} فوق الحد ($maxInviteContacts)', '${parsed.overLimit} over the limit ($maxInviteContacts)'), tone: AppTone.warning),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: bits),
      if (parsed.invalid.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs),
          child: Text(
            parsed.invalid.take(5).join('  ·  ') + (parsed.invalid.length > 5 ? '  …' : ''),
            textDirection: TextDirection.ltr,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.meta(context).copyWith(color: c.danger),
          ),
        ),
    ]);
  }
}

/// The create result: how many went out, a Share / Copy per link, and the skipped contacts with the reason.
class InviteResultView extends StatelessWidget {
  const InviteResultView({super.key, required this.result, this.orgName = '', this.role = 'student'});
  final InviteResult result;
  final String orgName, role;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final withLink = result.created.where((i) => i.link != null).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppStatusBadge(label: t('أُنشئت ${result.created.length}', '${result.created.length} created'), tone: AppTone.success, icon: Icons.check_rounded),
        if (result.skipped.isNotEmpty) AppStatusBadge(label: t('تُخطّيت ${result.skipped.length}', '${result.skipped.length} skipped'), tone: AppTone.warning),
      ]),
      if (withLink.isNotEmpty) ...[
        AppSpace.gapSm,
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton.tonal(
            key: const ValueKey('org.invite.copy_all'),
            label: t('نسخ كل الروابط', 'Copy all links'),
            icon: Icons.copy_all_rounded,
            size: AppButtonSize.sm,
            onPressed: () => _copy(result.allLinks),
          ),
        ),
        AppSpace.gapSm,
        for (final i in withLink)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
              child: Row(children: [
                Icon(i.channel == 'phone' ? Icons.phone_rounded : Icons.mail_outline_rounded, size: AppIconSize.md, color: c.textMedium),
                AppSpace.gapSm,
                Expanded(
                  child: Text(i.contact, textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                ),
                AppIconButton(icon: Icons.copy_rounded, tooltip: t('نسخ الرابط', 'Copy link'), onPressed: () => _copy(i.link!)),
                AppIconButton(
                  icon: Icons.ios_share_rounded,
                  tooltip: t('مشاركة الرابط', 'Share link'),
                  onPressed: () => shareInviteText(inviteShareText(orgName.isEmpty ? t('المؤسسة', 'the organization') : orgName, i.role.isEmpty ? role : i.role, i.link!)),
                ),
              ]),
            ),
          ),
      ],
      if (result.skipped.isNotEmpty) ...[
        AppSpace.gapSm,
        Text(t('لم تُرسل إلى', 'Not invited'), style: AppType.bodyStrong(context)),
        AppSpace.gapXs,
        for (final s in result.skipped)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xxs),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.remove_circle_outline_rounded, size: AppIconSize.sm, color: c.warning),
              AppSpace.gapXs,
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: s.contact, style: AppType.row(context)),
                    TextSpan(text: '  ${inviteSkipText(s.code)}', style: AppType.meta(context)),
                  ]),
                ),
              ),
            ]),
          ),
      ],
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Staff: pending list
// ═════════════════════════════════════════════════════════════════════════════

class OrgInvitationsPage extends StatefulWidget {
  const OrgInvitationsPage({super.key, required this.orgId, this.orgName = '', this.canInvite = true, this.api});
  final int orgId;
  final String orgName;
  final bool canInvite;
  final OrgInvitationsApi? api;

  @override
  State<OrgInvitationsPage> createState() => _OrgInvitationsPageState();
}

class _OrgInvitationsPageState extends State<OrgInvitationsPage> {
  late final OrgInvitationsApi _api = widget.api ?? OrgInvitationsApi();
  final _items = <OrgInvitation>[];
  String _status = 'pending', _q = '';
  int _page = 0, _total = 0, _seq = 0;
  bool _loading = true, _more = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    final seq = ++_seq;
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _more = true);
    }
    final next = reset ? 1 : _page + 1;
    final r = await _api.list(widget.orgId, status: _status, q: _q, page: next);
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      _more = false;
      if (!r.ok) {
        _error = r.error;
        return;
      }
      if (reset) _items.clear();
      _items.addAll(asMapList(r.map['items']).map(OrgInvitation.fromJson));
      _total = asInt(r.map['total'], _items.length);
      _page = next;
    });
  }

  Future<void> _invite() async {
    final r = await showOrgInviteSheet(context, orgId: widget.orgId, orgName: widget.orgName, api: _api);
    if (r != null && mounted) _load(reset: true);
  }

  Future<void> _resend(OrgInvitation i) async {
    final r = await _api.resend(widget.orgId, i.id);
    if (!mounted) return;
    if (!r.ok) {
      showAppNotice(orgErrorText(r.error!), error: true);
      return;
    }
    final n = OrgInvitation.fromJson(r.map);
    showAppNotice(t('أُعيد إرسال الدعوة', 'Invitation sent again'));
    _replace(n);
    if (n.link != null) {
      // resend rotates the token: the new link is the only one that works
      await showAppSheet<void>(
        context,
        (ctx) => AppSheetContent(title: t('رابط جديد للدعوة', 'New invitation link'), children: [
          AppBanner(icon: Icons.info_outline_rounded, color: ctx.colors.warning, text: t('الرابط القديم لم يعد يعمل — شارك هذا الرابط الجديد.', 'The old link no longer works — share this new one.')),
          AppSpace.gapSm,
          InviteResultView(result: InviteResult([n], const []), orgName: widget.orgName),
        ]),
      );
    }
  }

  Future<void> _cancel(OrgInvitation i) async {
    if (!await appConfirm(context, danger: true, message: t('إلغاء الدعوة إلى ${i.contact}؟ لن يعمل رابطها بعد الآن.', 'Cancel the invitation to ${i.contact}? Its link stops working.'))) return;
    final r = await _api.cancel(widget.orgId, i.id);
    if (!mounted) return;
    if (!r.ok) {
      showAppNotice(orgErrorText(r.error!), error: true);
      return;
    }
    showAppNotice(t('أُلغيت الدعوة', 'Invitation cancelled'));
    if (_status == 'pending') {
      setState(() {
        _items.removeWhere((x) => x.id == i.id);
        _total = (_total - 1).clamp(0, 1 << 30);
      });
    } else {
      _replace(OrgInvitation.fromJson(r.map));
    }
  }

  void _replace(OrgInvitation n) => setState(() {
        final k = _items.indexWhere((x) => x.id == n.id);
        if (k >= 0) _items[k] = n;
      });

  @override
  Widget build(BuildContext context) {
    return ParentComponent(
      featureKey: invitationsFeatureKey,
      child: OrgPushedPage(
        title: t('الدعوات', 'Invitations'),
        subtitle: t('من دعوتهم إلى المؤسسة', 'People you invited'),
        refresh: null,
        child: OrgPageBody(
          primary: widget.canInvite ? OrgPrimaryAction(id: 'invite', icon: Icons.person_add_alt_1_rounded, label: t('دعوة أشخاص', 'Invite people'), onTap: _invite) : null,
          search: AppSearchField(hint: t('بحث بالبريد أو الهاتف', 'Search e-mail or phone'), onChanged: (v) {
            _q = v;
            _load(reset: true);
          }),
          filter: OrgFilterButton<String>(
            value: _status,
            options: {for (final s in inviteStatuses) s: inviteStatusLabel(s)},
            defaultValue: 'pending',
            label: t('الحالة', 'Status'),
            onChanged: (v) {
              _status = v;
              _load(reset: true);
            },
          ),
          child: InvitationsList(
            items: _items,
            loading: _loading,
            error: _error,
            total: _total,
            loadingMore: _more,
            onRetry: () => _load(reset: true),
            onMore: () => _load(),
            onResend: _resend,
            onCancel: _cancel,
            onInvite: widget.canInvite ? _invite : null,
            filtered: _status != 'pending' || _q.isNotEmpty,
          ),
        ),
      ),
    );
  }
}

/// The rows over plain values: states, cards, "load more".
class InvitationsList extends StatelessWidget {
  const InvitationsList({
    super.key,
    required this.items,
    required this.loading,
    this.error,
    this.total = 0,
    this.loadingMore = false,
    this.onRetry,
    this.onMore,
    this.onResend,
    this.onCancel,
    this.onInvite,
    this.filtered = false,
  });

  final List<OrgInvitation> items;
  final bool loading, loadingMore, filtered;
  final Object? error;
  final int total;
  final VoidCallback? onRetry, onMore, onInvite;
  final void Function(OrgInvitation)? onResend, onCancel;

  @override
  Widget build(BuildContext context) {
    return AppStateView<List<OrgInvitation>>(
      loading: loading,
      error: error,
      data: loading || error != null ? null : items,
      onRetry: onRetry,
      isEmpty: (l) => l.isEmpty,
      empty: AppEmpty(
        icon: Icons.mark_email_unread_outlined,
        title: filtered ? t('لا دعوات بهذه الحالة', 'No invitations match') : t('لا توجد دعوات قائمة', 'No pending invitations'),
        message: filtered ? null : t('ادعُ طلاباً أو مدرسين بالبريد أو الهاتف.', 'Invite students or teachers by e-mail or phone.'),
        actionLabel: !filtered && onInvite != null ? t('دعوة أشخاص', 'Invite people') : null,
        onAction: onInvite,
      ),
      builder: (context, list) => ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, 100),
        children: [
          for (final i in list)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: OrgInvitationCard(
                invitation: i,
                onResend: onResend == null ? null : () => onResend!(i),
                onCancel: onCancel == null ? null : () => onCancel!(i),
              ),
            ),
          if (list.length < total)
            Align(
              child: AppButton.secondary(label: t('عرض المزيد', 'Show more'), busy: loadingMore, onPressed: loadingMore ? null : onMore),
            ),
        ],
      ),
    );
  }
}

class OrgInvitationCard extends StatelessWidget {
  const OrgInvitationCard({super.key, required this.invitation, this.onResend, this.onCancel, this.now});
  final OrgInvitation invitation;
  final VoidCallback? onResend, onCancel;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final i = invitation;
    final c = context.colors;
    final st = i.effectiveStatus(now: now);
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(i.channel == 'phone' ? Icons.phone_rounded : Icons.mail_outline_rounded, size: AppIconSize.md, color: c.textMedium),
          AppSpace.gapSm,
          Expanded(child: Text(i.contact, textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context))),
          AppSpace.gapXs,
          AppStatusBadge(label: inviteStatusLabel(st), tone: inviteStatusTone(st), dense: true),
        ]),
        AppSpace.gapXs,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AppStatusBadge(label: inviteRoleLabel(i.role), tone: AppTone.brand, dense: true),
          Text(inviteExpiryText(i.expiresAt, now: now), style: AppType.meta(context)),
          if (i.invitedBy.isNotEmpty) Text('· ${i.invitedBy}', style: AppType.meta(context)),
          if (i.sentCount > 1) Text(t('· أُرسلت ${i.sentCount} مرات', '· sent ${i.sentCount} times'), style: AppType.meta(context)),
        ]),
        if (i.canAct(now: now) && (onResend != null || onCancel != null)) ...[
          AppSpace.gapXs,
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            if (onResend != null)
              AppButton.tonal(key: ValueKey('org.invite.resend.${i.id}'), label: t('إعادة الإرسال', 'Resend'), icon: Icons.refresh_rounded, size: AppButtonSize.sm, onPressed: onResend),
            if (onCancel != null)
              AppButton.ghost(key: ValueKey('org.invite.cancel.${i.id}'), label: t('إلغاء', 'Cancel'), icon: Icons.close_rounded, size: AppButtonSize.sm, onPressed: onCancel),
          ]),
        ],
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Invitee: /i/<token>
// ═════════════════════════════════════════════════════════════════════════════

class OrgInviteePage extends StatefulWidget {
  const OrgInviteePage({super.key, required this.token, this.signedIn, this.myContact = '', this.api, this.onAccepted});
  final String token;

  /// null = ask the session (tests pass it).
  final bool? signedIn;

  /// The signed-in account's e-mail, to explain a contact mismatch.
  final String myContact;
  final OrgInvitationsApi? api;
  final void Function(int orgId)? onAccepted;

  @override
  State<OrgInviteePage> createState() => _OrgInviteePageState();
}

class _OrgInviteePageState extends State<OrgInviteePage> {
  late final OrgInvitationsApi _api = widget.api ?? OrgInvitationsApi();
  InviteLookup? _lookup;
  String? _error, _mismatch, _doneText;
  bool _loading = true, _busy = false;

  bool get _signedIn => widget.signedIn ?? ApiClient().hasSession;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _api.lookup(widget.token);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _lookup = InviteLookup.fromJson(r.map);
      } else {
        _error = orgErrorText(r.error!);
      }
    });
  }

  /// Signed out: remember this page, sign in (or up), and the first signed-in page opens it again (D-170).
  void _signIn(String route) {
    SignInReturn.pending = '/i/${widget.token}';
    Navigator.of(context).pushNamed(route);
  }

  Future<void> _answer(bool accept) async {
    setState(() {
      _busy = true;
      _mismatch = null;
    });
    final r = accept ? await _api.accept(widget.token) : await _api.decline(widget.token);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = false;
        if (r.code == 'invite_contact_mismatch') {
          _mismatch = _lookup?.contactMasked ?? '';
        } else {
          _error = orgErrorText(r.error!);
        }
      });
      return;
    }
    final lk = _lookup;
    setState(() {
      _busy = false;
      _doneText = accept
          ? t('أصبحت عضواً في «${lk?.orgName ?? ''}».', 'You are now a member of "${lk?.orgName ?? ''}".')
          : t('رفضت الدعوة.', 'You declined the invitation.');
    });
    if (accept && lk != null) {
      _afterAccepted();
      widget.onAccepted?.call(lk.orgId);
    }
  }

  bool _accepted = false;

  /// I am a member now: the memberships (the switcher, the mode) and the dashboard's organizations reload.
  void _afterAccepted() {
    _accepted = true;
    unawaited(AppModeController.instance.refresh());
    try {
      unawaited(context.read<OrgSession>().load());
    } catch (_) {/* no OrgSession in scope (a signed-in app always has one) */}
  }

  /// "Open the organization": the one switching rule (dashboard for staff, member home for a student).
  Future<void> _openOrg() async {
    final lk = _lookup;
    if (lk == null) return;
    await AppModeController.instance.ready();
    if (!mounted) return;
    await openJoinedOrganization(context, lk.orgId, staff: lk.role != 'student');
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      useWebCard: true,
      maxWith: 560,
      appBar: ScreenAppBar(title: t('دعوة للانضمام', 'Invitation')),
      child: ParentComponent(
        featureKey: invitationsFeatureKey,
        child: InviteeView(
          lookup: _lookup,
          loading: _loading,
          error: _error,
          signedIn: _signedIn,
          busy: _busy,
          mismatchMasked: _mismatch,
          myContact: widget.myContact,
          doneText: _doneText,
          onAccept: () => _answer(true),
          onDecline: () => _answer(false),
          onOpenOrg: _accepted ? _openOrg : null,
          onSignIn: () => _signIn('/login'),
          onRegister: () => _signIn('/register'),
          onRetry: _load,
          onClose: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }
}

/// The invitee's page over plain values.
class InviteeView extends StatelessWidget {
  const InviteeView({
    super.key,
    this.lookup,
    this.loading = false,
    this.error,
    this.signedIn = true,
    this.busy = false,
    this.mismatchMasked,
    this.myContact = '',
    this.doneText,
    this.onAccept,
    this.onDecline,
    this.onOpenOrg,
    this.onSignIn,
    this.onRegister,
    this.onRetry,
    this.onClose,
  });

  final InviteLookup? lookup;
  final bool loading, signedIn, busy;
  final String? error, mismatchMasked, doneText;
  final String myContact;
  final VoidCallback? onAccept, onDecline, onOpenOrg, onSignIn, onRegister, onRetry, onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lk = lookup;
    if (lk == null) {
      if (loading) return const AppListSkeleton(items: 2);
      return AppErrorState(title: t('تعذّر فتح الدعوة', 'This invitation can\'t be opened'), message: error, onRetry: onRetry);
    }
    return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
      AppCard(
        child: Column(children: [
          AppAvatar(name: lk.orgName, url: lk.logoUrl),
          AppSpace.gapSm,
          Text(lk.orgName, textAlign: TextAlign.center, style: AppType.pageTitle(context)),
          AppSpace.gapXs,
          Text(
            t('تمت دعوتك للانضمام بصفة ${inviteRoleLabel(lk.role)}', 'You are invited to join as ${inviteRoleLabel(lk.role)}'),
            textAlign: TextAlign.center,
            style: AppType.body(context),
          ),
          if (lk.contactMasked.isNotEmpty) ...[
            AppSpace.gapXs,
            Text(t('أُرسلت إلى ${lk.contactMasked}', 'Sent to ${lk.contactMasked}'), textDirection: TextDirection.ltr, textAlign: TextAlign.center, style: AppType.meta(context)),
          ],
          AppSpace.gapXs,
          Text(inviteExpiryText(lk.expiresAt), textAlign: TextAlign.center, style: AppType.meta(context)),
        ]),
      ),
      AppSpace.gapMd,
      if (doneText != null) ...[
        AppBanner(icon: Icons.check_circle_rounded, color: c.success, text: doneText!),
        AppSpace.gapMd,
        if (onOpenOrg != null) ...[
          AppButton.primary(key: const ValueKey('org.invitee.open'), label: t('فتح المؤسسة', 'Open the organization'), expand: true, onPressed: onOpenOrg),
          AppSpace.gapXs,
          AppButton.secondary(label: t('تم', 'Done'), expand: true, onPressed: onClose),
        ] else
          AppButton.primary(label: t('تم', 'Done'), expand: true, onPressed: onClose),
      ] else if (!lk.pending) ...[
        AppBanner(
          icon: Icons.info_outline_rounded,
          color: c.warning,
          text: lk.status == 'expired'
              ? orgCodeText('invite_expired')
              : t('هذه الدعوة ${inviteStatusLabel(lk.status)} ولم تعد صالحة.', 'This invitation is ${inviteStatusLabel(lk.status).toLowerCase()} and no longer valid.'),
        ),
      ] else ...[
        if (mismatchMasked != null) ...[
          AppBanner(
            icon: Icons.person_off_rounded,
            color: c.danger,
            text: t(
              'هذه الدعوة موجهة إلى ${mismatchMasked!.isEmpty ? 'حساب آخر' : mismatchMasked}${myContact.isEmpty ? '' : '، وأنت مسجّل بحساب $myContact'}. سجّل الدخول بالحساب الذي يملك هذا البريد/الهاتف موثّقاً، أو وثّقه أولاً.',
              'This invitation was sent to ${mismatchMasked!.isEmpty ? 'another account' : mismatchMasked}${myContact.isEmpty ? '' : ', and you are signed in as $myContact'}. Sign in with the account that has this verified e-mail/phone, or verify it first.',
            ),
          ),
          AppSpace.gapMd,
        ],
        if (error != null) ...[
          AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
          AppSpace.gapMd,
        ],
        if (signedIn)
          AppButtonRow(
            primary: AppButton.primary(key: const ValueKey('org.invitee.accept'), label: t('قبول الدعوة', 'Accept'), icon: Icons.check_rounded, busy: busy, onPressed: busy ? null : onAccept),
            secondary: [AppButton.secondary(key: const ValueKey('org.invitee.decline'), label: t('رفض', 'Decline'), onPressed: busy ? null : onDecline)],
          )
        else ...[
          AppBanner(icon: DirIcons.login, color: c.primary, text: t('سجّل الدخول أو أنشئ حساباً لقبول الدعوة، ثم نعود إلى هذه الصفحة.', 'Sign in or create an account to answer, then you come back to this page.')),
          AppSpace.gapMd,
          AppButton.primary(key: const ValueKey('org.invitee.sign_in'), label: t('تسجيل الدخول', 'Sign in'), icon: DirIcons.login, expand: true, onPressed: onSignIn),
          AppSpace.gapXs,
          AppButton.secondary(key: const ValueKey('org.invitee.register'), label: t('إنشاء حساب', 'Create an account'), expand: true, onPressed: onRegister),
        ],
      ],
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Invitee: my invitations (for the homes)
// ═════════════════════════════════════════════════════════════════════════════

/// The invitations addressed to me; draws nothing while there are none (or the feature is switched off).
class OrgMyInvitationsCard extends StatefulWidget {
  const OrgMyInvitationsCard({super.key, this.onChanged, this.api});

  /// Runs after one was accepted (reload "my organizations").
  final void Function(MyInvitation accepted)? onChanged;
  final OrgInvitationsApi? api;

  @override
  State<OrgMyInvitationsCard> createState() => _OrgMyInvitationsCardState();
}

class _OrgMyInvitationsCardState extends State<OrgMyInvitationsCard> {
  late final OrgInvitationsApi _api = widget.api ?? OrgInvitationsApi();
  List<MyInvitation> _items = const [];
  int? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.mine();
    if (!mounted || !r.ok) return;
    setState(() => _items = [for (final x in asMapList(asMap(r.data)['items'])) MyInvitation.fromJson(x)]);
  }

  Future<void> _answer(MyInvitation i, bool accept) async {
    setState(() => _busyId = i.id);
    final r = accept ? await _api.acceptMine(i.id) : await _api.declineMine(i.id);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (!r.ok) {
      showAppNotice(orgErrorText(r.error!), error: true);
      if (r.code == 'invite_expired' || r.code == 'invite_not_pending') _load();
      return;
    }
    setState(() => _items = _items.where((x) => x.id != i.id).toList());
    showAppNotice(accept ? t('أصبحت عضواً في «${i.orgName}»', 'You joined "${i.orgName}"') : t('رُفضت الدعوة', 'Invitation declined'));
    if (accept) widget.onChanged?.call(i);
  }

  @override
  Widget build(BuildContext context) => ParentComponent(
        featureKey: invitationsFeatureKey,
        child: MyInvitationsView(items: _items, busyId: _busyId, onAccept: (i) => _answer(i, true), onDecline: (i) => _answer(i, false)),
      );
}

class MyInvitationsView extends StatelessWidget {
  const MyInvitationsView({super.key, required this.items, this.busyId, this.onAccept, this.onDecline});
  final List<MyInvitation> items;
  final int? busyId;
  final void Function(MyInvitation)? onAccept, onDecline;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return AppCard(
      key: const ValueKey('org.my_invitations'),
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.mark_email_unread_rounded, size: AppIconSize.md, color: context.colors.primary),
          AppSpace.gapSm,
          Expanded(child: Text(t('دعوات بانتظارك', 'Invitations waiting for you'), style: AppType.section(context))),
        ]),
        for (final i in items) ...[
          AppSpace.gapSm,
          Row(children: [
            AppAvatar(name: i.orgName, url: i.logoUrl),
            AppSpace.gapSm,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(i.orgName, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
                Text('${inviteRoleLabel(i.role)} · ${inviteExpiryText(i.expiresAt)}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              ]),
            ),
          ]),
          AppSpace.gapXs,
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            AppButton.tonal(
              key: ValueKey('org.my_invitation.accept.${i.id}'),
              label: t('قبول', 'Accept'),
              size: AppButtonSize.sm,
              busy: busyId == i.id,
              onPressed: busyId != null ? null : () => onAccept?.call(i),
            ),
            AppButton.ghost(
              key: ValueKey('org.my_invitation.decline.${i.id}'),
              label: t('رفض', 'Decline'),
              size: AppButtonSize.sm,
              onPressed: busyId != null ? null : () => onDecline?.call(i),
            ),
          ]),
        ],
      ]),
    );
  }
}
