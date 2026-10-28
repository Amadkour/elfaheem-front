// lib/features/org/org_sharing_pages.dart — Sharing with other organizations (org admin / `sharing` module).
//
//   Offers    what my organization shares (department · program · course · graduate verification), each with its
//             access methods, window, grants and use log; create / edit / revoke / regenerate the invite code.
//   Requests  grants other organizations asked for → approve / reject.
//   Partners  discover what other organizations offer (request / redeem a code) and what my organization holds.
//   Verify    "is X a graduate of yours?" against a grantor's graduates share: paste identifiers or upload a file.
//   Keys      (org admins) API keys for machine verification (POST /api/v1/verify/graduates, X-Api-Key).
// Server routes: FLUTTER_API_CHANGES.md (phase 3). Pure logic + tests: org_sharing.dart.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show asInt, asMap, asMapList, ErrorRetry, t;
import 'org_providers.dart';
import 'org_sharing.dart';
import 'org_ui.dart';
import 'org_v3.dart';
import 'package:flutter_education_app/design/app_icons.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Presentational pieces (plain values → tested by the layout harness)
// ═════════════════════════════════════════════════════════════════════════════

/// One share as the grantor sees it.
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.share, this.onTap, this.grantorName});
  final Map<String, dynamic> share;
  final VoidCallback? onTap;
  /// Set when the card shows another organization's offer (Partners tab).
  final String? grantorName;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = '${share['state'] ?? share['status'] ?? 'active'}';
    final methods = (share['methods'] as List? ?? const []).map((e) => '$e').toList();
    final type = '${share['resource_type'] ?? ''}';
    final grants = asInt(share['grants']);
    final pending = asInt(share['pending']);
    final expires = orgParseUtc(share['expires_at']);
    final tone = state == 'active' ? c.success : (state == 'not_yet_valid' ? c.warning : c.textLight);
    return AppCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_iconFor(type), color: c.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(shareTitleOf(share), maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: orgText(context, size: 15, w: FontWeight.w800, color: c.textDark)),
              Text(grantorName ?? shareResourceLabel(type), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: orgText(context, size: 12, color: c.textMedium)),
            ]),
          ),
          const SizedBox(width: 8),
          Flexible(child: OrgPill(shareStateText(state), color: tone)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final m in methods) AppTag(shareMethodLabel(m), c.primary, icon: _methodIcon(m)),
          if (type == 'graduates')
            AppTag(asMap(share['scope'])['year'] == true ? t('مع سنة التخرج', 'with graduation year') : t('نعم / لا فقط', 'yes / no only'),
                c.purple, icon: Icons.verified_rounded),
        ]),
        if (grantorName == null || expires != null) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 4, children: [
            if (grantorName == null)
              _mini(context, Icons.handshake_rounded, t('$grants مؤسسة لديها وصول', '$grants organizations have access')),
            if (grantorName == null && pending > 0) _mini(context, Icons.hourglass_top_rounded, t('$pending طلب بانتظارك', '$pending pending'), c.warning),
            if (expires != null) _mini(context, Icons.event_rounded, t('ينتهي ${AppTime.date(expires.toUtc())}', 'ends ${AppTime.date(expires.toUtc())}')),
          ]),
        ],
      ]),
    );
  }

  Widget _mini(BuildContext context, IconData icon, String text, [Color? color]) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color ?? context.colors.textMedium),
        const SizedBox(width: 4),
        Flexible(child: Text(text, maxLines: 2, style: orgText(context, size: 12, color: color ?? context.colors.textMedium))),
      ]);
}

IconData _iconFor(String type) => switch (type) {
      'department' => Icons.account_tree_rounded,
      'program' => Icons.school_rounded,
      'course' => Icons.menu_book_rounded,
      'graduates' => Icons.verified_user_rounded,
      _ => Icons.share_rounded,
    };

IconData _methodIcon(String m) => switch (m) {
      'invite' => Icons.key_rounded,
      'auto' => Icons.flash_on_rounded,
      'request' => Icons.how_to_reg_rounded,
      'public' => Icons.public_rounded,
      _ => Icons.circle,
    };

/// One grant (a request, an access): from the grantor side it names the grantee, from the grantee side the share.
class GrantCard extends StatelessWidget {
  const GrantCard({super.key, required this.grant, this.actions = const [], this.onTap});
  final Map<String, dynamic> grant;
  final List<Widget> actions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = '${grant['state'] ?? grant['status'] ?? ''}';
    final share = asMap(grant['share']);
    final grantee = asMap(grant['grantee']);
    final grantor = asMap(share['grantor']);
    final title = grantee.isNotEmpty ? orgNameOfBrief(grantee) : shareTitleOf(share);
    final sub = grantee.isNotEmpty
        ? (share.isNotEmpty ? shareTitleOf(share) : '#${grant['share_id']}')
        : (grantor.isNotEmpty ? orgNameOfBrief(grantor) : shareResourceLabel('${share['resource_type'] ?? ''}'));
    final tone = switch (state) { 'active' => c.success, 'pending' => c.warning, _ => c.textLight };
    final note = '${grant['note'] ?? ''}'.trim();
    return AppCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(grantee.isNotEmpty ? Icons.account_balance_rounded : _iconFor('${share['resource_type'] ?? ''}'), color: c.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: orgText(context, size: 15, w: FontWeight.w800, color: c.textDark)),
              Text('$sub · ${grantViaText('${grant['via'] ?? ''}')}', maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: orgText(context, size: 12, color: c.textMedium)),
            ]),
          ),
          const SizedBox(width: 8),
          Flexible(child: OrgPill(grantStateText(state), color: tone)),
        ]),
        if (note.isNotEmpty) ...[const SizedBox(height: 8), Text(note, style: orgText(context, size: 12.5, color: c.textMedium))],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: actions),
        ],
      ]),
    );
  }
}

/// The reply of a verification call: summary line + one row per identifier.
class VerifyResultsList extends StatelessWidget {
  const VerifyResultsList({super.key, required this.result, this.labels = const {}});
  final Map<String, dynamic> result;
  /// ref → the identifier typed, so rows read "name@x.io → Graduate" instead of "1 → Graduate".
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (yes, no, bad) = verificationSummary(result);
    final yearIncluded = result['year_included'] == true;
    final rows = asMapList(result['results']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        AppTag(t('$yes خريج', '$yes graduates'), c.success, icon: Icons.check_circle_rounded),
        AppTag(t('$no غير خريج', '$no not graduates'), c.textMedium, icon: Icons.cancel_rounded),
        if (bad > 0) AppTag(t('$bad بدون معرّف', '$bad without identifier'), c.warning, icon: Icons.help_rounded),
      ]),
      const SizedBox(height: 10),
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(r['graduate'] == true ? Icons.check_circle_rounded : (r['graduate'] == false ? Icons.cancel_rounded : Icons.help_rounded),
                size: 18, color: r['graduate'] == true ? c.success : (r['graduate'] == false ? c.textLight : c.warning)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(labels['${r['ref'] ?? ''}'] ?? '${r['ref'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: orgText(context, size: 13, color: c.textDark)),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(verificationLine(r, yearIncluded: yearIncluded), maxLines: 2, textAlign: TextAlign.end,
                  style: orgText(context, size: 12.5, w: FontWeight.w700, color: c.textMedium)),
            ),
          ]),
        ),
    ]);
  }
}

/// The share form (create / edit). Stateless over a draft the sheet owns; `resources` are the pickable items of the
/// chosen type (department / program / course) as the server lists them.
class ShareFormBody extends StatelessWidget {
  const ShareFormBody({
    super.key,
    required this.draft,
    required this.resources,
    required this.onChanged,
    this.editing = false,
    this.titleController,
    this.descriptionController,
    this.maxController,
  });
  final ShareDraft draft;
  final List<Map<String, dynamic>> resources;
  final VoidCallback onChanged;
  final bool editing;
  final TextEditingController? titleController, descriptionController, maxController;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!editing) ...[
        Text(t('ماذا تشارك؟', 'What do you share?'), style: orgText(context, size: 13, w: FontWeight.w800, color: c.textDark)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final tp in shareResourceTypes)
            ChoiceChip(
              key: ValueKey('share.type.$tp'),
              label: Text(shareResourceLabel(tp)),
              avatar: Icon(_iconFor(tp), size: 16),
              selected: draft.resourceType == tp,
              onSelected: (_) {
                draft.resourceType = tp;
                draft.resourceId = null;
                onChanged();
              },
            ),
        ]),
        if (draft.needsResource) ...[
          const SizedBox(height: 10),
          AppDropdown<int>(
            key: const ValueKey('share.resource'),
            value: draft.resourceId,
            hint: Text(t('اختر ${shareResourceLabel(draft.resourceType)}', 'Pick a ${shareResourceLabel(draft.resourceType).toLowerCase()}')),
            items: [
              for (final r in resources)
                DropdownMenuItem(value: asInt(r['id']), child: Text(t('${r['name_ar'] ?? r['title'] ?? ''}', '${r['name_en'] ?? r['title'] ?? ''}'), overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              draft.resourceId = v;
              onChanged();
            },
          ),
        ],
        const SizedBox(height: 14),
      ],
      Text(t('كيف تحصل المؤسسات الأخرى على الوصول؟ (يمكن الجمع)', 'How do other organizations get access? (combinable)'),
          style: orgText(context, size: 13, w: FontWeight.w800, color: c.textDark)),
      for (final m in shareMethods)
        AppSwitchTile(
          key: ValueKey('share.method.$m'),
          dense: true,
          icon: _methodIcon(m),
          title: shareMethodLabel(m),
          subtitle: shareMethodHint(m),
          value: draft.methods.contains(m),
          onChanged: (v) {
            v ? draft.methods.add(m) : draft.methods.remove(m);
            onChanged();
          },
        ),
      if (draft.isGraduates)
        AppSwitchTile(
          key: const ValueKey('share.year'),
          dense: true,
          icon: Icons.calendar_month_rounded,
          title: t('السماح بإرجاع سنة التخرج', 'Allow the graduation year in answers'),
          subtitle: t('بدونها الجواب نعم / لا فقط', 'Without it the answer is yes / no only'),
          value: draft.year,
          onChanged: (v) {
            draft.year = v;
            onChanged();
          },
        ),
      const SizedBox(height: 10),
      if (titleController != null) AppField(controller: titleController!, label: t('عنوان (اختياري)', 'Title (optional)')),
      if (descriptionController != null) ...[
        const SizedBox(height: 8),
        AppField(controller: descriptionController!, label: t('وصف يظهر للمؤسسات الأخرى (اختياري)', 'Description shown to other organizations (optional)'), maxLines: 2),
      ],
      if (maxController != null) ...[
        const SizedBox(height: 8),
        AppField(controller: maxController!, label: t('الحد الأقصى للمؤسسات (اختياري)', 'Max organizations (optional)'), keyboard: TextInputType.number),
      ],
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _DateButton(key: const ValueKey('share.starts'), label: t('يبدأ', 'Starts'), value: draft.startsAt, onPick: (d) { draft.startsAt = d; onChanged(); })),
        const SizedBox(width: 8),
        Expanded(child: _DateButton(key: const ValueKey('share.expires'), label: t('ينتهي', 'Ends'), value: draft.expiresAt, onPick: (d) { draft.expiresAt = d; onChanged(); })),
      ]),
    ]);
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({super.key, required this.label, required this.value, required this.onPick});
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return OutlinedButton.icon(
      onPressed: () async {
        final now = DateTime.now();
        final d = await showDatePicker(context: context, initialDate: value ?? now, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 10));
        onPick(d);
      },
      icon: Icon(Icons.event_rounded, size: 18, color: c.primary),
      label: Text(value == null ? label : '$label: ${AppTime.date(value!.toUtc())}', maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The page
// ═════════════════════════════════════════════════════════════════════════════

class OrgSharingPage extends StatefulWidget {
  const OrgSharingPage({super.key});

  @override
  State<OrgSharingPage> createState() => _OrgSharingPageState();
}

class _OrgSharingPageState extends State<OrgSharingPage> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  int get _tabCount => _s.isOrgAdmin ? 5 : 4;
  Map<String, dynamic>? _overview;
  List<Map<String, dynamic>>? _requests, _incoming, _discover, _keys;
  bool _missing = false;
  String? _error; // the overview could not be loaded
  String _q = '';

  OrgSession get _s => context.read<OrgSession>();
  String get _base => '${_s.base}/sharing';
  bool get _canEdit => _s.can('sharing', 'update');
  bool get _canCreate => _s.can('sharing', 'insert');
  bool get _canApprove => _s.can('sharing', 'approve');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabCount, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tabs.length != _tabCount) {              // the admin flag changed after a permission refresh: keep TabBar and TabBarView in step
      final i = _tabs.index.clamp(0, _tabCount - 1);
      _tabs.dispose();
      _tabs = TabController(length: _tabCount, vsync: this, initialIndex: i);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _idsCtl.dispose();
    _codeCtl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final r = await orgCall(() => ApiClient().get(_base), quiet: true);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _missing = r.endpointMissing;
        _error = r.endpointMissing ? null : orgErrorText(r.error!);
      });
      return;
    }
    setState(() {
      _overview = r.map;
      _error = null;
    });
    _loadRequests();
    _loadIncoming();
    _loadDiscover();
    if (_s.isOrgAdmin) _loadKeys();
  }

  Future<void> _loadRequests() async {
    final r = await OrgApi.i.getMap('$_base/requests');
    if (mounted) setState(() => _requests = asMapList(r?['items']));
  }

  Future<void> _loadIncoming() async {
    final r = await OrgApi.i.getMap('$_base/incoming');
    if (mounted) setState(() => _incoming = asMapList(r?['items']));
  }

  Future<void> _loadDiscover() async {
    final r = await OrgApi.i.getMap('$_base/discover', _q.isEmpty ? null : {'q': _q});
    if (mounted) setState(() => _discover = asMapList(r?['items']));
  }

  Future<void> _loadKeys() async {
    final r = await OrgApi.i.getMap('$_base/api-keys');
    if (mounted) setState(() => _keys = asMapList(r?['items']));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_missing) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        AppBanner(icon: Icons.cloud_off_rounded, text: t('المشاركة بين المؤسسات تحتاج تحديث الخادم', 'Sharing needs a server update'), color: c.warning),
      ]);
    }
    final ov = _overview;
    if (ov == null) {
      return _error != null
          ? ErrorRetry(message: _error!, onRetry: _loadAll)
          : const AppListSkeleton(items: 4, withAvatar: false);
    }
    final shares = asMapList(ov['shares']);
    final active = shares.fold<int>(0, (n, s) => n + asInt(s['grants']));
    final enabled = ov['enabled'] == true && ov['platform_enabled'] == true;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: AppHero(
          icon: Icons.handshake_rounded,
          title: t('المشاركة مع المؤسسات الأخرى', 'Sharing with other organizations'),
          subtitle: enabled
              ? t('كل مشاركة محددة النطاق، لها مدة، قابلة للإلغاء ومسجّلة في سجل النشاط.', 'Every share is scoped, expiring, revocable and audit-logged.')
              : t('المشاركة متوقفة لهذه المؤسسة من إدارة المنصة.', 'Sharing is switched off for this organization by the platform.'),
          stats: [
            AppHeroStat(icon: Icons.share_rounded, label: t('مشاركاتنا', 'Our shares'), value: '${shares.length}'),
            AppHeroStat(icon: Icons.handshake_rounded, label: t('مؤسسات لديها وصول', 'Orgs with access'), value: '$active'),
            AppHeroStat(icon: Icons.hourglass_top_rounded, label: t('طلبات بانتظارنا', 'Pending requests'), value: '${asInt(ov['pending'])}'),
          ],
        ),
      ),
      if (!enabled)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: AppBanner(icon: Icons.block_rounded, color: c.danger, text: t('لا يمكن إنشاء مشاركات أو استخدام الأكواد أو التحقق حتى تُفعَّل.', 'Shares, codes and verification are refused until it is switched on.')),
        ),
      TabBar(
        controller: _tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: [
          Tab(text: t('عروضنا', 'Offers')),
          Tab(text: t('الطلبات', 'Requests') + (asInt(ov['pending']) > 0 ? ' (${asInt(ov['pending'])})' : '')),
          Tab(text: t('الشركاء', 'Partners')),
          Tab(text: t('التحقق', 'Verify')),
          if (_s.isOrgAdmin) Tab(text: t('مفاتيح API', 'API keys')),
        ],
      ),
      Expanded(
        child: TabBarView(controller: _tabs, children: [
          _offers(shares, enabled),
          _requestsTab(),
          _partnersTab(enabled),
          _verifyTab(),
          if (_s.isOrgAdmin) _keysTab(),
        ]),
      ),
    ]);
  }

  // ── Offers ──
  Widget _offers(List<Map<String, dynamic>> shares, bool enabled) => ListView(padding: const EdgeInsets.all(16), children: [
        if (_canCreate && enabled)
          AppPrimaryButton(key: const ValueKey('sharing.new'), icon: Icons.add_rounded, label: t('مشاركة جديدة', 'New share'), onPressed: () => _shareForm()),
        const SizedBox(height: 12),
        if (shares.isEmpty)
          AppEmpty(icon: Icons.share_rounded, title: t('لا توجد مشاركات بعد', 'Nothing shared yet'),
              message: t('شارك قسماً أو برنامجاً أو مقرراً، أو اسمح لمؤسسات أخرى بالتحقق من خريجيك.', 'Share a department, a program or a course, or let other organizations verify your graduates.')),
        for (final s in shares) Padding(padding: const EdgeInsets.only(bottom: 10), child: ShareCard(share: s, onTap: () => _shareSheet(s))),
      ]);

  Future<void> _shareForm({Map<String, dynamic>? existing}) async {
    final draft = existing == null ? ShareDraft() : ShareDraft.fromShare(existing);
    final title = TextEditingController(text: draft.title);
    final desc = TextEditingController(text: draft.description);
    final max = TextEditingController(text: draft.maxGrantees?.toString() ?? '');
    List<Map<String, dynamic>> resources = const [];
    String? loadedType;
    await showAppSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, setS) {
          Future<void> loadResources() async {
            if (!draft.needsResource || loadedType == draft.resourceType) return;
            loadedType = draft.resourceType;
            final r = await OrgApi.i.getMap('$_base/resources', {'type': draft.resourceType});
            resources = asMapList(r?['items']);
            if (ctx.mounted) setS(() {});
          }
          if (existing == null) loadResources();
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppSheetHeader(existing == null ? t('مشاركة جديدة', 'New share') : t('تعديل المشاركة', 'Edit share')),
              ShareFormBody(
                draft: draft,
                resources: resources,
                editing: existing != null,
                titleController: title,
                descriptionController: desc,
                maxController: max,
                onChanged: () {
                  loadResources();
                  setS(() {});
                },
              ),
              const SizedBox(height: 16),
              AppPrimaryButton(
                key: const ValueKey('share.save'),
                label: existing == null ? t('إنشاء', 'Create') : t('حفظ', 'Save'),
                onPressed: () async {
                  draft.title = title.text;
                  draft.description = desc.text;
                  draft.maxGrantees = int.tryParse(max.text.trim());
                  final problem = draft.validate();
                  if (problem != null) {
                    appToast(problem, error: true);
                    return;
                  }
                  final r = existing == null
                      ? await orgCall(() => ApiClient().post('$_base/shares', body: draft.toBody()), ok: t('تم إنشاء المشاركة', 'Share created'))
                      : await orgCall(() => ApiClient().put('$_base/shares/${existing['id']}', body: draft.patch(existing)), ok: t('تم الحفظ', 'Saved'));
                  if (!r.ok || !ctx.mounted) return;
                  Navigator.pop(ctx);
                  final code = r.map['code'];
                  if (!mounted) return;
                  if (code != null) _showCode(this.context, '$code');
                  _loadAll();
                },
              ),
            ]),
          );
        }));
    title.dispose();
    desc.dispose();
    max.dispose();
  }

  void _showCode(BuildContext context, String code) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('كود الدعوة', 'Invite code')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText(code, key: const ValueKey('share.code'), style: orgText(ctx, size: 22, w: FontWeight.w900, color: ctx.colors.primary), textDirection: TextDirection.ltr),
          const SizedBox(height: 8),
          Text(t('يظهر مرة واحدة فقط — انسخه الآن وأرسله للمؤسسة. يمكنك تجديده لاحقاً.', 'Shown once — copy it now and hand it to the organization. You can regenerate it later.'),
              style: orgText(ctx, size: 12.5, color: ctx.colors.textMedium)),
        ]),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              appToast(t('تم النسخ', 'Copied'));
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: Text(t('نسخ', 'Copy')),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('تم', 'Done'))),
        ],
      ),
    );
  }

  Future<void> _shareSheet(Map<String, dynamic> share) async {
    final sid = asInt(share['id']);
    final grants = asMapList((await OrgApi.i.getMap('$_base/shares/$sid/grants'))?['items']);
    final uses = asMapList((await OrgApi.i.getMap('$_base/shares/$sid/uses'))?['items']);
    if (!mounted) return;
    final active = '${share['state']}' == 'active';
    await showAppSheet<void>(context, (ctx) {
      final c = ctx.colors;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSheetHeader(shareTitleOf(share)),
          ShareCard(share: share),
          if ('${share['description'] ?? ''}'.isNotEmpty) ...[const SizedBox(height: 8), Text('${share['description']}', style: orgText(ctx, color: c.textMedium))],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (_canEdit && active) OutlinedButton.icon(onPressed: () { Navigator.pop(ctx); _shareForm(existing: share); }, icon: const Icon(Icons.edit_rounded, size: 18), label: Text(t('تعديل', 'Edit'))),
            if (_canEdit && active && (share['methods'] as List? ?? const []).contains('invite'))
              OutlinedButton.icon(
                onPressed: () async {
                  if (!await appConfirm(ctx, message: t('الكود الحالي سيتوقف فوراً. تجديده؟', 'The current code stops working at once. Regenerate?'))) return;
                  final r = await orgCall(() => ApiClient().post('$_base/shares/$sid/code/regenerate'));
                  if (r.ok && ctx.mounted) _showCode(ctx, '${r.map['code']}');
                },
                icon: const Icon(Icons.autorenew_rounded, size: 18),
                label: Text(t('تجديد الكود', 'Regenerate code')),
              ),
            if (_s.can('sharing', 'delete') && active)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: c.danger),
                onPressed: () async {
                  if (!await appConfirm(ctx, danger: true, message: t('إلغاء المشاركة ينهي وصول كل المؤسسات إليها. متابعة؟', 'Revoking ends every organization\'s access to it. Continue?'))) return;
                  final r = await orgCall(() => ApiClient().post('$_base/shares/$sid/revoke', body: {}), ok: t('أُلغيت المشاركة', 'Share revoked'));
                  if (r.ok && ctx.mounted) {
                    Navigator.pop(ctx);
                    _loadAll();
                  }
                },
                icon: const Icon(Icons.block_rounded, size: 18),
                label: Text(t('إلغاء المشاركة', 'Revoke')),
              ),
          ]),
          const SizedBox(height: 16),
          AppSectionTitle(t('المؤسسات', 'Organizations'), subtitle: t('${grants.length} سجل', '${grants.length} records')),
          if (grants.isEmpty) Text(t('لا توجد مؤسسات بعد', 'No organizations yet'), style: orgText(ctx, color: c.textMedium)),
          for (final g in grants)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GrantCard(grant: g, actions: [
                if (_canEdit && ('${g['status']}' == 'active' || '${g['status']}' == 'pending'))
                  TextButton.icon(
                    onPressed: () async {
                      final r = await orgCall(() => ApiClient().post('$_base/grants/${g['id']}/revoke', body: {}), ok: t('أُنهي الوصول', 'Access ended'));
                      if (r.ok && ctx.mounted) {
                        Navigator.pop(ctx);
                        _loadAll();
                      }
                    },
                    icon: const Icon(Icons.person_off_rounded, size: 18),
                    label: Text(t('إنهاء الوصول', 'End access')),
                  ),
              ]),
            ),
          const SizedBox(height: 12),
          AppSectionTitle(t('سجل الاستخدام', 'Use log'), subtitle: t('آخر ${uses.length} عملية', 'last ${uses.length}')),
          if (uses.isEmpty) Text(t('لم يُستخدم بعد', 'Not used yet'), style: orgText(ctx, color: c.textMedium)),
          for (final u in uses.take(50))
            AppInfoRow(
              u['kind'] == 'content' ? Icons.visibility_rounded : Icons.fact_check_rounded,
              '${u['kind'] == 'content' ? t('قراءة', 'Read') : t('تحقق', 'Verify')} · ${t('المؤسسة', 'org')} #${u['grantee_org_id']}'
              '${asInt(u['count']) > 1 ? ' · ${u['count']} ${t('معرّف', 'ids')}' : ''}'
              '${u['created_at'] != null ? ' · ${AppTime.dateTime(orgParseUtc(u['created_at'])!.toUtc())}' : ''}',
            ),
        ]),
      );
    });
  }

  // ── Requests ──
  Widget _requestsTab() {
    final rows = _requests;
    if (rows == null) return const AppListSkeleton(items: 3, withAvatar: false);
    return AppRefresh(onRefresh: _loadRequests, child: ListView(padding: const EdgeInsets.all(16), children: [
      if (rows.isEmpty) AppEmpty(icon: Icons.inbox_rounded, title: t('لا توجد طلبات', 'No requests'), message: t('عندما تطلب مؤسسة الوصول إلى إحدى مشاركاتكم يظهر طلبها هنا.', 'When an organization asks for one of your shares, it shows up here.')),
      for (final g in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GrantCard(grant: g, actions: [
            if (_canApprove) ...[
              TextButton.icon(
                key: ValueKey('grant.reject.${g['id']}'),
                style: TextButton.styleFrom(foregroundColor: context.colors.danger),
                onPressed: () => _decide(g, false),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: Text(t('رفض', 'Reject')),
              ),
              FilledButton.icon(
                key: ValueKey('grant.approve.${g['id']}'),
                onPressed: () => _decide(g, true),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(t('موافقة', 'Approve')),
              ),
            ],
          ]),
        ),
    ]));
  }

  Future<void> _decide(Map<String, dynamic> g, bool approve) async {
    String note = '';
    if (!approve) {
      final ctl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('سبب الرفض', 'Reason for rejecting')),
          content: TextField(controller: ctl, maxLines: 3, autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('إلغاء', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('رفض', 'Reject'))),
          ],
        ),
      );
      note = ctl.text.trim();
      ctl.dispose();
      if (ok != true) return;
      if (note.isEmpty) {
        appToast(t('اكتب سبب الرفض', 'Write the reason'), error: true);
        return;
      }
    }
    final r = await orgCall(() => ApiClient().post('$_base/grants/${g['id']}/${approve ? 'approve' : 'reject'}', body: {'note': note}),
        ok: approve ? t('تمت الموافقة', 'Approved') : t('تم الرفض', 'Rejected'));
    if (r.ok) _loadAll();
  }

  // ── Partners ──
  Widget _partnersTab(bool enabled) {
    final c = context.colors;
    final inc = _incoming;
    final disc = _discover;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (_canEdit && enabled) ...[
        AppSectionTitle(t('لديك كود دعوة؟', 'Got an invite code?')),
        Row(children: [
          Expanded(child: AppField(controller: _codeCtl, label: t('كود الدعوة', 'Invite code'), ltr: true)),
          const SizedBox(width: 8),
          FilledButton(
            key: const ValueKey('sharing.redeem'),
            onPressed: () async {
              final r = await orgCall(() => ApiClient().post('$_base/redeem', body: {'code': _codeCtl.text.trim()}), ok: t('حصلت مؤسستك على الوصول', 'Your organization now has access'));
              if (r.ok) {
                _codeCtl.clear();
                _loadAll();
              }
            },
            child: Text(t('استخدام', 'Redeem')),
          ),
        ]),
        const SizedBox(height: 16),
      ],
      AppSectionTitle(t('ما تملكه مؤسستك', 'What your organization holds')),
      if (inc == null) const AppListSkeleton(items: 2, withAvatar: false),
      if (inc != null && inc.isEmpty) Text(t('لا يوجد وصول بعد — اطلب من العروض أدناه أو استخدم كوداً.', 'No access yet — ask from the offers below or redeem a code.'), style: orgText(context, color: c.textMedium)),
      for (final g in inc ?? const <Map<String, dynamic>>[])
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GrantCard(
            grant: g,
            onTap: '${g['state']}' == 'active' && '${asMap(g['share'])['resource_type']}' != 'graduates' ? () => _openContent(asInt(g['share_id'])) : null,
            actions: [
              if ('${g['state']}' == 'active' && '${asMap(g['share'])['resource_type']}' != 'graduates')
                TextButton.icon(onPressed: () => _openContent(asInt(g['share_id'])), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: Text(t('عرض', 'Open'))),
              if ('${g['state']}' == 'active' && '${asMap(g['share'])['resource_type']}' == 'graduates')
                TextButton.icon(onPressed: () => _tabs.animateTo(3), icon: const Icon(Icons.fact_check_rounded, size: 18), label: Text(t('تحقّق', 'Verify'))),
              if (_canEdit && ('${g['status']}' == 'active' || '${g['status']}' == 'pending'))
                TextButton.icon(
                  onPressed: () async {
                    if (!await appConfirm(context, danger: true, message: t('التخلي عن هذا الوصول؟', 'Give up this access?'))) return;
                    final r = await orgCall(() => ApiClient().post('$_base/grants/${g['id']}/revoke', body: {}), ok: t('تم', 'Done'));
                    if (r.ok) _loadAll();
                  },
                  icon: const Icon(DirIcons.logout, size: 18),
                  label: Text(t('تخلٍّ', 'Give up')),
                ),
            ],
          ),
        ),
      const SizedBox(height: 16),
      AppSectionTitle(t('عروض المؤسسات الأخرى', 'Offers from other organizations')),
      TextField(
        key: const ValueKey('sharing.search'),
        decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: t('ابحث باسم المؤسسة أو العرض', 'Search by organization or offer')),
        onSubmitted: (v) {
          _q = v.trim();
          _loadDiscover();
        },
      ),
      const SizedBox(height: 10),
      if (disc == null) const AppListSkeleton(items: 3, withAvatar: false),
      if (disc != null && disc.isEmpty) Text(t('لا توجد عروض الآن', 'No offers right now'), style: orgText(context, color: c.textMedium)),
      for (final s in disc ?? const <Map<String, dynamic>>[])
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ShareCard(share: s, grantorName: orgNameOfBrief(asMap(s['grantor'])), onTap: s['readable'] == true && '${s['resource_type']}' != 'graduates' ? () => _openContent(asInt(s['id'])) : null),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8, top: 4),
              child: Wrap(spacing: 8, children: [
                if (s['readable'] == true && '${s['resource_type']}' != 'graduates')
                  TextButton.icon(onPressed: () => _openContent(asInt(s['id'])), icon: const Icon(Icons.open_in_new_rounded, size: 18), label: Text(t('عرض', 'Open'))),
                if (_canEdit && enabled && s['my_grant'] == null && ((s['methods'] as List? ?? const []).contains('auto') || (s['methods'] as List? ?? const []).contains('request')))
                  FilledButton.tonalIcon(
                    key: ValueKey('discover.request.${s['id']}'),
                    onPressed: () async {
                      final r = await orgCall(() => ApiClient().post('$_base/request', body: {'share_id': s['id']}), ok: t('تم الإرسال', 'Sent'));
                      if (r.ok) _loadAll();
                    },
                    icon: const Icon(Icons.how_to_reg_rounded, size: 18),
                    label: Text((s['methods'] as List? ?? const []).contains('auto') ? t('الحصول على الوصول', 'Get access') : t('طلب الوصول', 'Request access')),
                  ),
                if (s['my_grant'] != null) OrgPill(grantStateText('${asMap(s['my_grant'])['state'] ?? ''}'), color: c.textMedium),
              ]),
            ),
          ]),
        ),
    ]);
  }

  Future<void> _openContent(int shareId) async {
    final r = await orgCall(() => ApiClient().get('$_base/content/$shareId'));
    if (!r.ok || !mounted) return;
    final d = r.map;
    final body = asMap(d['department']).isNotEmpty ? asMap(d['department']) : (asMap(d['program']).isNotEmpty ? asMap(d['program']) : asMap(d['course']));
    await showAppSheet<void>(context, (ctx) {
      final c = ctx.colors;
      final courses = asMapList(body['courses']);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSheetHeader(t('${body['name_ar'] ?? body['title'] ?? ''}', '${body['name_en'] ?? body['title'] ?? ''}')),
          AppInfoRow(Icons.account_balance_rounded, orgNameOfBrief(asMap(d['grantor']))),
          if ('${body['code'] ?? ''}'.isNotEmpty) AppInfoRow(Icons.tag_rounded, '${body['code']}', ltr: true),
          if ('${body['teacher'] ?? ''}'.isNotEmpty) AppInfoRow(Icons.person_rounded, '${body['teacher']}'),
          if ('${body['description'] ?? ''}'.isNotEmpty) ...[const SizedBox(height: 8), Text('${body['description']}', style: orgText(ctx, color: c.textMedium))],
          if (courses.isNotEmpty) ...[
            const SizedBox(height: 12),
            AppSectionTitle(t('المقررات', 'Courses'), subtitle: '${courses.length}'),
            for (final k in courses) AppInfoRow(Icons.menu_book_rounded, '${k['title'] ?? ''}'),
          ],
        ]),
      );
    });
  }

  // ── Verify ──
  int? _verifyShare;
  bool _withYear = false;
  final _idsCtl = TextEditingController();
  final _codeCtl = TextEditingController();   // Partners tab: survives rebuilds while lists load
  Map<String, dynamic>? _verifyResult;
  Map<String, String> _verifyLabels = const {};
  bool _verifying = false;

  Widget _verifyTab() {
    final c = context.colors;
    final grads = (_incoming ?? const <Map<String, dynamic>>[])
        .where((g) => '${g['state']}' == 'active' && '${asMap(g['share'])['resource_type']}' == 'graduates')
        .toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(t('اسأل مؤسسة أخرى: هل فلان خريج لديكم؟ الجواب نعم أو لا فقط (وسنة التخرج إن سمحت المؤسسة).', 'Ask another organization: is X a graduate of yours? The answer is yes or no only (and the year when that organization allows it).'),
          style: orgText(context, color: c.textMedium)),
      const SizedBox(height: 12),
      if (grads.isEmpty)
        AppBanner(icon: Icons.info_rounded, color: c.warning, text: t('لا يوجد وصول للتحقق بعد — اطلبه من تبويب الشركاء.', 'No verification access yet — ask for one in Partners.')),
      if (grads.isNotEmpty) ...[
        AppDropdown<int>(
          key: const ValueKey('verify.share'),
          // the chosen grant may have been revoked since: a value outside the items would assert
          value: grads.any((g) => asInt(g['share_id']) == _verifyShare) ? _verifyShare : asInt(grads.first['share_id']),
          items: [for (final g in grads) DropdownMenuItem(value: asInt(g['share_id']), child: Text(orgNameOfBrief(asMap(asMap(g['share'])['grantor'])), overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _verifyShare = v),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('verify.ids'),
          controller: _idsCtl,
          maxLines: 6,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: t('معرّف في كل سطر: بريد إلكتروني، هاتف أو رقم جامعي', 'One identifier per line: e-mail, phone or student code'),
          ),
        ),
        AppSwitchTile(dense: true, icon: Icons.calendar_month_rounded, title: t('اطلب سنة التخرج إن كانت متاحة', 'Ask for the graduation year when allowed'), value: _withYear, onChanged: (v) => setState(() => _withYear = v)),
        Row(children: [
          Expanded(child: AppPrimaryButton(key: const ValueKey('verify.run'), icon: Icons.fact_check_rounded, label: t('تحقّق', 'Verify'), busy: _verifying, onPressed: () => _runVerify(grads))),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            key: const ValueKey('verify.file'),
            onPressed: () => _bulkVerify(grads),
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: Text(t('ملف', 'File')),
          ),
        ]),
        if (_verifyResult != null) ...[
          const SizedBox(height: 16),
          AppCard(child: VerifyResultsList(result: _verifyResult!, labels: _verifyLabels)),
        ],
      ],
    ]);
  }

  Future<void> _runVerify(List<Map<String, dynamic>> grads) async {
    final queries = parseIdentifiers(_idsCtl.text);
    if (queries.isEmpty) {
      appToast(t('أدخل معرّفاً واحداً على الأقل', 'Enter at least one identifier'), error: true);
      return;
    }
    setState(() => _verifying = true);
    final r = await orgCall(() => ApiClient().post('$_base/verify', body: {
          'share_id': _verifyShare ?? asInt(grads.first['share_id']),
          'include_year': _withYear,
          'queries': queries,
        }));
    if (!mounted) return;
    setState(() {
      _verifying = false;
      if (r.ok) {
        _verifyResult = r.map;
        _verifyLabels = {for (final q in queries) '${q['ref']}': '${q['email'] ?? q['phone'] ?? q['student_code']}'};
      }
    });
  }

  Future<void> _bulkVerify(List<Map<String, dynamic>> grads) async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['csv', 'txt', 'xlsx']);
    if (f == null) return;
    final bytes = kIsWeb ? await f.readAsBytes() : null;
    if (!mounted) return;
    setState(() => _verifying = true);
    final shareId = _verifyShare ?? asInt(grads.first['share_id']);
    final r = await orgCall(() => ApiClient().postMultipart('$_base/verify/bulk',
        fields: {'share_id': '$shareId', 'include_year': '$_withYear', 'format': 'json'},
        fileField: 'file', fileName: f.name, filePath: kIsWeb ? null : f.path, fileBytes: bytes));
    if (!mounted) return;
    setState(() {
      _verifying = false;
      if (r.ok) {
        _verifyResult = r.map;
        _verifyLabels = const {};
      }
    });
  }

  // ── API keys ──
  Widget _keysTab() {
    final c = context.colors;
    final keys = _keys;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(t('مفتاح API يمثّل مؤسستك على POST /api/v1/verify/graduates (ترويسة X-Api-Key) ويستخدم صلاحياتها وحدودها.', 'An API key stands for your organization on POST /api/v1/verify/graduates (header X-Api-Key) and uses its grants and limits.'),
          style: orgText(context, color: c.textMedium)),
      const SizedBox(height: 12),
      AppPrimaryButton(key: const ValueKey('keys.new'), icon: Icons.vpn_key_rounded, label: t('مفتاح جديد', 'New key'), onPressed: _newKey),
      const SizedBox(height: 12),
      if (keys == null) const AppListSkeleton(items: 2, withAvatar: false),
      if (keys != null && keys.isEmpty) AppEmpty(icon: Icons.vpn_key_off_rounded, title: t('لا توجد مفاتيح', 'No keys')),
      for (final k in keys ?? const <Map<String, dynamic>>[])
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            child: Row(children: [
              Icon(k['active'] == true ? Icons.vpn_key_rounded : Icons.vpn_key_off_rounded, color: k['active'] == true ? c.primary : c.textLight),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${k['name']}', style: orgText(context, size: 14.5, w: FontWeight.w800, color: c.textDark)),
                  Text('nbk_${k['prefix']}_…${k['last_used_at'] != null ? ' · ${t('آخر استخدام', 'last used')} ${AppTime.dateTime(orgParseUtc(k['last_used_at'])!.toUtc())}' : ''}',
                      style: orgText(context, size: 12, color: c.textMedium), textDirection: TextDirection.ltr),
                ]),
              ),
              if (k['active'] == true)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: c.danger),
                  onPressed: () async {
                    if (!await appConfirm(context, danger: true, message: t('إلغاء هذا المفتاح نهائي.', 'Revoking this key is final.'))) return;
                    final r = await orgCall(() => ApiClient().post('$_base/api-keys/${k['id']}/revoke'), ok: t('أُلغي المفتاح', 'Key revoked'));
                    if (r.ok) _loadKeys();
                  },
                  child: Text(t('إلغاء', 'Revoke')),
                )
              else
                OrgPill(t('ملغى', 'Revoked'), color: c.textLight),
            ]),
          ),
        ),
    ]);
  }

  Future<void> _newKey() async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('مفتاح API جديد', 'New API key')),
        content: TextField(controller: ctl, autofocus: true, decoration: InputDecoration(labelText: t('اسم (مثل: نظام شؤون الطلاب)', 'Name (e.g. registrar system)'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('إنشاء', 'Create'))),
        ],
      ),
    );
    final name = ctl.text.trim();
    ctl.dispose();
    if (ok != true) return;
    final r = await orgCall(() => ApiClient().post('$_base/api-keys', body: {'name': name.isEmpty ? 'API key' : name}));
    if (!r.ok || !mounted) return;
    _showCode(context, '${r.map['key']}');
    _loadKeys();
  }
}
