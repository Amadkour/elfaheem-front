// lib/features/org/org_access_joining.dart — joining an organization and its departments, in one place
// (API: org_join_router.py — /orgs/{o}/join/…, /join-requests/…, /public/join/code, /public/me/join-status).
//
// Staff (org admin)
//   OrgAccessJoiningPage   Requests (organization + departments, select many → accept / reject) ·
//                          Codes (generate with role / department / expiry / max uses, QR + share, rotate, revoke) ·
//                          Settings (how people join THIS organization + the default for departments)
// Members
//   OrgJoinPage            one "Join" experience: enter any code · browse & request · track my requests
//   openOrgJoin            push it (respects AppConfig.orgsEnabled)
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart' show AdminAvatar;
import 'org_access_page.dart' show OrgAccessPage;
import 'org_join_pages.dart' show JoinRequestCard, OrgUnitJoinScreen, unitKindLabel;
import 'org_join_scan.dart' show joinScannerAvailable, openJoinScanner;
import 'org_providers.dart';
import 'org_ui.dart';
import 'org_v3.dart';

const _pub = '$orgBase/public';

Map<String, String> _roleLabels() => {
      'student': t('طالب', 'Student'),
      'teacher': t('عضو هيئة تدريس', 'Teacher'),
      'teacher_assistant': t('معيد / مساعد تدريس', 'Teaching assistant'),
    };

/// Friendly texts for the codes this workstream adds (the shared table covers the rest).
String joinErrorText(OrgCall r) => switch (r.code) {
      'role_mismatch' => r.detail['role'] == 'student'
          ? t('هذا الكود مخصص للطلاب — اطلب كود هيئة التدريس من إدارة المؤسسة', 'This code is for students — ask your institution for a staff code')
          : t('هذا الكود مخصص لهيئة التدريس — اطلب كود الطلاب من إدارة المؤسسة', 'This code is for teaching staff — ask your institution for a student code'),
      'closed' => t('هذه المؤسسة لا تستقبل أعضاء جدداً الآن', 'This organization isn\'t taking new members right now'),
      'bad_code' => t('لم نتعرف على هذا الكود — تأكد من الحروف واطلبه من مؤسستك', 'We don\'t recognise this code — check it and ask your institution'),
      _ => orgErrorText(r.error!),
    };

// ═════════════════════════════════════════════════════════════════════════════
//  Staff
// ═════════════════════════════════════════════════════════════════════════════

class OrgAccessJoiningPage extends StatefulWidget {
  const OrgAccessJoiningPage({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<OrgAccessJoiningPage> createState() => _OrgAccessJoiningPageState();
}

class _OrgAccessJoiningPageState extends State<OrgAccessJoiningPage> {
  Map<String, dynamic>? _settings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final s = context.read<OrgSession>();
    final r = await orgCall(() => s.api.get('${s.base}/join/settings'), quiet: true);
    if (mounted && r.ok) setState(() => _settings = r.map);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.read<OrgSession>();
    final admin = s.can('organization', 'update');
    final counts = asMap(_settings?['counts']);
    final pending = asInt(counts['org_requests'] ?? 0) + asInt(counts['unit_requests'] ?? 0);
    final tabs = <(String, IconData, Widget)>[
      (pending > 0 ? t('الطلبات · $pending', 'Requests · $pending') : t('الطلبات', 'Requests'), Icons.inbox_rounded,
          _RequestsInbox(onChanged: _load)),
      if (admin) (t('أكواد الانضمام', 'Join codes'), Icons.qr_code_2_rounded, _OrgCodesTab(settings: _settings, onChanged: _load)),
      if (admin) (t('طريقة الانضمام', 'How people join'), Icons.tune_rounded, _JoinSettingsTab(settings: _settings, onSaved: _load)),
    ];
    return DefaultTabController(
      length: tabs.length,
      initialIndex: widget.initialTab.clamp(0, tabs.length - 1),
      child: Column(children: [
        TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: c.primary,
          indicatorColor: c.primary,
          tabs: [for (final x in tabs) Tab(icon: Icon(x.$2, size: 20), text: x.$1)],
        ),
        Expanded(child: TabBarView(children: [for (final x in tabs) x.$3])),
      ]),
    );
  }
}

// ── Requests: organization + departments, bulk decisions ─────────────────────

class _RequestsInbox extends StatefulWidget {
  const _RequestsInbox({required this.onChanged});
  final Future<void> Function() onChanged;

  @override
  State<_RequestsInbox> createState() => _RequestsInboxState();
}

class _RequestsInboxState extends State<_RequestsInbox> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>>? _org, _units;
  String _filter = 'all';
  final Set<String> _sel = {};          // "org:12" · "unit:7"
  bool _busy = false;
  bool _tipHidden = false;

  /// From this many waiting requests, the admin is advised to share the approval permission.
  static const _shareLoadAt = 5;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final s = context.read<OrgSession>();
    final rs = await Future.wait([
      s.can('requests', 'approve') ? orgCall(() => s.api.get('${s.base}/join/requests'), quiet: true) : Future.value(const OrgCall(null)),
      orgCall(() => s.api.get('${s.base}/join-requests/inbox'), quiet: true),
    ]);
    if (!mounted) return;
    setState(() {
      _org = rs[0].ok ? asMapList(asMap(rs[0].data)['items']) : const [];
      _units = rs[1].ok ? asMapList(rs[1].map['items']) : const [];
      _sel.removeWhere((k) => !_all.any((x) => x.$1 == k));
    });
  }

  List<(String, Map<String, dynamic>)> get _all => [
        if (_filter != 'units') for (final r in _org ?? const <Map<String, dynamic>>[]) ('org:${r['id']}', r),
        if (_filter != 'org') for (final r in _units ?? const <Map<String, dynamic>>[]) ('unit:${r['id']}', r),
      ];

  Future<void> _decide(bool approve, {Set<String>? only}) async {
    final keys = only ?? _sel;
    final orgIds = [for (final k in keys) if (k.startsWith('org:')) int.parse(k.substring(4))];
    final unitIds = [for (final k in keys) if (k.startsWith('unit:')) int.parse(k.substring(5))];
    final needsVerify = (_units ?? const []).any((r) => unitIds.contains(asInt(r['id'])) && r['needs_verification'] == true);
    String? note;
    if (!approve || needsVerify) {
      note = await _askNote(
        approve
            ? t('بعض الطلبات تحتاج تحققاً — اكتب ما تحققت منه', 'Some requests need verification — write what you checked')
            : t('سبب الرفض (يصل للمتقدمين)', 'Reason for rejecting (sent to the applicants)'),
      );
      if (note == null) return;
    } else if (!await appConfirm(context,
        message: t('قبول ${keys.length} طلباً؟ يعيد الخادم التحقق من أهلية كل طلب الآن.', 'Accept ${keys.length} request(s)? The server re-checks each one now.'))) {
      return;
    }
    if (!mounted) return;
    final s = context.read<OrgSession>();
    setState(() => _busy = true);
    var done = 0, unplaced = 0;
    final failed = <String>[];
    final body = {'decision': approve ? 'approve' : 'reject', 'note': ?note};
    if (orgIds.isNotEmpty) {
      final r = await orgCall(() => s.api.post('${s.base}/join/requests/bulk', body: {...body, 'ids': orgIds}), quiet: true);
      if (r.ok) {
        final rows = asMapList(r.map['done']);
        done += rows.length;
        unplaced += rows.where((x) => x['department'] is Map && asMap(x['department'])['placed'] != true).length;
        failed.addAll(asMapList(r.map['failed']).map((f) => '${f['message'] ?? ''}'));
      } else {
        failed.add(orgErrorText(r.error!));
      }
    }
    if (unitIds.isNotEmpty) {
      final r = await orgCall(() => s.api.post('${s.base}/join-requests/bulk', body: {...body, 'ids': unitIds}), quiet: true);
      if (r.ok) {
        done += asMapList(r.map['done']).length;
        for (final f in asMapList(r.map['failed'])) {
          final reasons = asMapList(f['reasons']).map(joinReasonText).join('، ');
          failed.add(reasons.isEmpty ? '${f['message'] ?? ''}' : reasons);
        }
      } else {
        failed.add(orgErrorText(r.error!));
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _sel.clear();
    });
    if (done > 0) {
      toast(approve ? t('قُبل $done طلباً وأُبلغ أصحابها 🎉', '$done accepted — applicants notified 🎉') : t('رُفض $done طلباً وأُبلغ أصحابها', '$done rejected — applicants notified'));
    }
    if (unplaced > 0) {
      toast(t('$unplaced لم يُضَف لقسم الكود (الشروط أو السعة) — بقي عضواً عاماً', '$unplaced not placed in the code\'s department (rules or capacity) — kept as general members'));
    }
    if (failed.isNotEmpty) {
      toast(t('تعذّر ${failed.length}: ${failed.toSet().take(2).join(' — ')}', '${failed.length} couldn\'t be done: ${failed.toSet().take(2).join(' — ')}'), error: true);
    }
    await _load();
    await widget.onChanged();
  }

  Future<String?> _askNote(String title) async {
    final ctrl = TextEditingController();
    final ok = await showAppSheet<bool>(context, (ctx) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), // the sheet already lifts above the keyboard
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppSheetHeader(title),
            Field(controller: ctrl, label: t('الملاحظة', 'Note'), maxLines: 3),
            AppPrimaryButton(label: t('متابعة', 'Continue'), onPressed: () {
              if (ctrl.text.trim().isEmpty) return toast(t('اكتب الملاحظة أولاً', 'Write the note first'), error: true);
              Navigator.pop(ctx, true);
            }),
          ]),
        ));
    final v = ctrl.text.trim();
    ctrl.dispose();
    return ok == true ? v : null;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.colors;
    if (_org == null || _units == null) return const AppListSkeleton();
    final rows = _all;
    final selecting = _sel.isNotEmpty;
    final s = context.watch<OrgSession>();
    final shareTip = s.isOrgAdmin && !_tipHidden && (_org!.length + _units!.length) >= _shareLoadAt;
    return Column(children: [
      if (shareTip)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: AppBanner(
            icon: Icons.diversity_3_rounded,
            text: t('طلبات كثيرة تنتظرك. وزّع العمل: امنح صلاحية «اعتماد طلبات الانضمام» لأحد الموظفين من الأدوار والصلاحيات.',
                'Many requests are waiting. Share the load: give a staff member the "Approve join requests" permission in Roles & privileges.'),
            action: Wrap(children: [
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider.value(
                        value: s,
                        child: BasePage(useWebCard: true, maxWith: 1100,
                            appBar: ScreenAppBar(title: t('الأدوار والصلاحيات', 'Roles & privileges')), child: const OrgAccessPage())))),
                child: Text(t('منح الصلاحية', 'Give permission')),
              ),
              IconButton(
                tooltip: t('إخفاء', 'Hide'),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _tipHidden = true),
                icon: Icon(Icons.close_rounded, size: 18, color: c.textLight),
              ),
            ]),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AppChoiceChip(label: t('الكل', 'All'), selected: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
          AppChoiceChip(label: t('المؤسسة · ${_org!.length}', 'Organization · ${_org!.length}'), icon: Icons.domain_rounded,
              selected: _filter == 'org', onTap: () => setState(() => _filter = 'org')),
          AppChoiceChip(label: t('الأقسام · ${_units!.length}', 'Departments · ${_units!.length}'), icon: Icons.account_tree_rounded,
              selected: _filter == 'units', onTap: () => setState(() => _filter = 'units')),
        ]),
      ),
      if (rows.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            Checkbox(
              tristate: true,
              value: _sel.isEmpty ? false : (_sel.length == rows.length ? true : null),
              onChanged: (_) => setState(() => _sel.length == rows.length ? _sel.clear() : _sel.addAll(rows.map((e) => e.$1))),
            ),
            Expanded(
              child: Text(selecting ? t('محدد ${_sel.length}', '${_sel.length} selected') : t('تحديد الكل', 'Select all'),
                  style: orgText(context, size: 12.5, w: FontWeight.w700, color: c.textMedium)),
            ),
          ]),
        ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: rows.isEmpty
              ? ListView(children: [
                  AppEmpty(
                    icon: Icons.inbox_rounded,
                    title: t('لا طلبات تنتظر قرارك', 'No requests waiting for you'),
                    message: t('تظهر هنا طلبات الانضمام للمؤسسة ولأقسامها التي تعتمدها.', 'Requests to join the organization and the departments you approve appear here.'),
                  ),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 110),
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final (key, r) = rows[i];
                    final on = _sel.contains(key);
                    final card = key.startsWith('org:')
                        ? _OrgRequestCard(row: r, busy: _busy, onDecide: (ok) => _decide(ok, only: {key}))
                        : JoinRequestCard(row: r, showUnit: true, onChanged: () async {
                            await _load();
                            await widget.onChanged();
                          });
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 8, top: 18),
                        child: Checkbox(value: on, onChanged: (_) => setState(() => on ? _sel.remove(key) : _sel.add(key))),
                      ),
                      Expanded(child: card),
                    ]);
                  },
                ),
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 180),
        child: !selecting
            ? const SizedBox(width: double.infinity)
            : SafeArea(
                top: false,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider))),
                  child: Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : () => _decide(true),
                        icon: const Icon(Icons.done_all_rounded),
                        label: FittedBox(child: Text(t('قبول (${_sel.length})', 'Accept (${_sel.length})'))),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _decide(false),
                        icon: Icon(Icons.close_rounded, color: c.danger),
                        label: FittedBox(child: Text(t('رفض (${_sel.length})', 'Reject (${_sel.length})'), style: TextStyle(color: c.danger))),
                      ),
                    ),
                  ]),
                ),
              ),
      ),
    ]);
  }
}

class _OrgRequestCard extends StatelessWidget {
  const _OrgRequestCard({required this.row, required this.onDecide, required this.busy});
  final Map<String, dynamic> row;
  final ValueChanged<bool> onDecide;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final u = asMap(row['user']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AdminAvatar(name: '${u['name'] ?? ''}', url: u['image_url'] as String?),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${u['name'] ?? '#${row['id']}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, w: FontWeight.w800)),
                Text('${t('للانضمام إلى المؤسسة', 'To join the organization')} · ${_roleLabels()[row['role']] ?? row['role']}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, size: 12, color: c.textMedium)),
                Text(relTime(row['created_at']), style: orgText(context, size: 11.5, color: c.textLight)),
              ]),
            ),
          ]),
          if (row['code_verified'] == true) ...[
            const SizedBox(height: 6),
            AppBadgePill(t('الكود صحيح', 'Code verified'), color: c.success, icon: Icons.verified_rounded),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            FilledButton.icon(onPressed: busy ? null : () => onDecide(true), icon: const Icon(Icons.check_rounded), label: Text(t('قبول', 'Accept'))),
            OutlinedButton.icon(onPressed: busy ? null : () => onDecide(false), icon: const Icon(Icons.close_rounded), label: Text(t('رفض', 'Reject'))),
          ]),
        ]),
      ),
    );
  }
}

// ── Codes ─────────────────────────────────────────────────────────────────────

class _OrgCodesTab extends StatefulWidget {
  const _OrgCodesTab({required this.settings, required this.onChanged});
  final Map<String, dynamic>? settings;
  final Future<void> Function() onChanged;

  @override
  State<_OrgCodesTab> createState() => _OrgCodesTabState();
}

class _OrgCodesTabState extends State<_OrgCodesTab> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>>? _rows;
  List<Map<String, dynamic>> _programs = const [];
  bool _failed = false;

  @override
  bool get wantKeepAlive => true;

  String get _url => '${context.read<OrgSession>().base}/join/codes';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final s = context.read<OrgSession>();
    final rs = await Future.wait([
      orgCall(() => s.api.get(_url), quiet: true),
      orgCall(() => s.api.get('${s.base}/academic/programs'), quiet: true),
    ]);
    if (!mounted) return;
    setState(() {
      _rows = rs[0].ok ? asMapList(rs[0].map['items']) : _rows;
      _failed = !rs[0].ok && _rows == null;
      if (rs[1].ok) _programs = asMapList(rs[1].map['items']);
    });
  }

  String _orgName() => context.read<OrgSession>().name;

  String _programLabel(dynamic id) {
    if (id == null) return t('بلا قسم', 'No department');
    final p = _programs.where((x) => asInt(x['id']) == asInt(id)).firstOrNull;
    return p == null ? '#$id' : '${p['code']} · ${orgNameOf(p)}';
  }

  Future<void> _showPlain(String code, Map<String, dynamic> row) => showAppSheet<void>(context, (ctx) {
        final c = ctx.colors;
        final share = t('انضم إلى ${_orgName()} على التطبيق باستخدام الكود: $code', 'Join ${_orgName()} in the app with the code: $code');
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(children: [
            AppSheetHeader(t('كود الانضمام جاهز', 'Your join code is ready')),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: c.divider)),
              child: QrImageView(data: code, size: 180, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 12),
            FittedBox(
              child: SelectableText(code,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontFamily: 'bahji', fontSize: 30, letterSpacing: 5, fontWeight: FontWeight.w800, color: c.primary)),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
              AppBadgePill(_roleLabels()[row['default_role']] ?? t('طالب', 'Student'), icon: Icons.person_rounded),
              if (row['default_program_id'] != null) AppBadgePill(_programLabel(row['default_program_id']), icon: Icons.account_tree_rounded),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  toast(t('نُسخ الكود', 'Code copied'));
                },
                icon: const Icon(Icons.copy_rounded),
                label: Text(t('نسخ', 'Copy')),
              ),
              FilledButton.icon(
                onPressed: () => SharePlus.instance.share(ShareParams(text: share)),
                icon: const Icon(Icons.share_rounded),
                label: Text(t('مشاركة', 'Share')),
              ),
            ]),
            const SizedBox(height: 12),
            AppBanner(
              icon: Icons.visibility_off_rounded,
              color: c.warning,
              text: t('يظهر الكود كاملاً مرة واحدة فقط — انسخه أو شاركه الآن. يمسح الأعضاء رمز QR بزر «مسح رمز QR» في شاشة «انضمام» أو يُدخلون الكود فيها.',
                  'The full code is shown only once — copy or share it now. Members scan the QR with "Scan QR" on the "Join" screen, or type the code there.'),
            ),
          ]),
        );
      });

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final s = context.read<OrgSession>();
    final label = TextEditingController(text: '${row?['label'] ?? ''}');
    final maxC = TextEditingController(text: row?['max_uses'] == null ? '' : '${row!['max_uses']}');
    DateTime? from = orgParseUtc(row?['valid_from']), until = orgParseUtc(row?['valid_until']);
    String role = '${row?['default_role'] ?? 'student'}';
    int? program = row?['default_program_id'] == null ? null : asInt(row!['default_program_id']);
    bool oneTime = false, busy = false;
    String? err;
    await showAppSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final c = ctx.colors;
          Future<void> pick(bool isFrom) async {
            final d = await showDatePicker(
                context: ctx, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime(2100), initialDate: (isFrom ? from : until) ?? DateTime.now());
            if (d == null) return;
            set(() => isFrom ? from = DateTime(d.year, d.month, d.day) : until = DateTime(d.year, d.month, d.day, 23, 59, 59));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), // the sheet already lifts above the keyboard
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppSheetHeader(row == null ? t('كود انضمام جديد', 'New join code') : t('تعديل الكود', 'Edit code')),
              Field(controller: label, label: t('وصف داخلي (مثلاً: طلاب الفرقة الأولى 2026)', 'Internal label (e.g. Year 1 students 2026)')),
              Text(t('ينضم صاحب الكود بصفته', 'People who use it join as'), style: orgText(ctx, size: 12.5, w: FontWeight.w800, color: c.textMedium)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in _roleLabels().entries) AppChoiceChip(label: e.value, selected: role == e.key, onTap: () => set(() => role = e.key)),
              ]),
              const SizedBox(height: 12),
              if (_programs.isNotEmpty) ...[
                Text(t('القسم العلمي (اختياري)', 'Academic department (optional)'), style: orgText(ctx, size: 12.5, w: FontWeight.w800, color: c.textMedium)),
                Text(t('للطلاب: يُضافون للقسم إن استوفوا شروطه، وإلا ينضمون للمؤسسة فقط ونخبرهم بالسبب.',
                        'Students are placed in it when they meet its rules; otherwise they join the organization only and see why.'),
                    style: orgText(ctx, size: 11.5, color: c.textLight)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  AppChoiceChip(label: t('بلا قسم', 'None'), selected: program == null, onTap: () => set(() => program = null)),
                  for (final p in _programs.where((x) => x['is_active'] != false))
                    AppChoiceChip(label: '${p['code']}', selected: program == asInt(p['id']), onTap: () => set(() => program = asInt(p['id']))),
                ]),
                const SizedBox(height: 12),
              ],
              Text(t('مدة الصلاحية (اختياري)', 'Validity (optional)'), style: orgText(ctx, size: 12.5, w: FontWeight.w800, color: c.textMedium)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: () => pick(true),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: FittedBox(child: Text(from == null ? t('من الآن', 'From now') : shortDate(from!.toIso8601String()))))),
                const SizedBox(width: 8),
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: () => pick(false),
                        icon: const Icon(Icons.flag_rounded),
                        label: FittedBox(child: Text(until == null ? t('بلا انتهاء', 'No end') : shortDate(until!.toIso8601String()))))),
              ]),
              if (from != null || until != null)
                TextButton(onPressed: () => set(() => from = until = null), child: Text(t('بلا حدود زمنية', 'No time limits'))),
              const SizedBox(height: 6),
              if (row == null)
                AppSwitchTile(
                    title: t('استخدام واحد فقط', 'One use only'),
                    subtitle: t('دعوة شخصية لشخص واحد', 'A personal invitation for one person'),
                    value: oneTime,
                    onChanged: (v) => set(() => oneTime = v)),
              if (!oneTime)
                Field(controller: maxC, label: t('أقصى عدد استخدامات (فارغ = بلا حد)', 'Maximum uses (empty = unlimited)'), keyboard: TextInputType.number, ltr: true),
              if (err != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: AppBanner(icon: Icons.error_outline_rounded, text: err!, color: c.danger)),
              AppPrimaryButton(
                busy: busy,
                icon: row == null ? Icons.qr_code_2_rounded : Icons.check_rounded,
                label: row == null ? t('إنشاء الكود', 'Create code') : t('حفظ', 'Save'),
                onPressed: () async {
                  if (from != null && until != null && !from!.isBefore(until!)) return set(() => err = orgCodeText('bad_window'));
                  final max = maxC.text.trim().isEmpty ? null : int.tryParse(maxC.text.trim());
                  if (!oneTime && maxC.text.trim().isNotEmpty && (max == null || max < 1)) {
                    return set(() => err = t('عدد الاستخدامات رقم صحيح أكبر من صفر', 'Uses must be a whole number above 0'));
                  }
                  final body = {
                    'label': label.text.trim().isEmpty ? null : label.text.trim(),
                    'valid_from': orgUtc(from),
                    'valid_until': orgUtc(until),
                    'default_role': role,
                    'default_program_id': program,
                    if (row == null) 'one_time': oneTime,
                    if (!oneTime) 'max_uses': max,
                  };
                  set(() {
                    busy = true;
                    err = null;
                  });
                  final r = await orgCall(() => row == null ? s.api.post(_url, body: body) : s.api.put('$_url/${row['id']}', body: body), quiet: true);
                  if (!ctx.mounted) return;
                  set(() => busy = false);
                  if (!r.ok) return set(() => err = orgErrorText(r.error!));
                  Navigator.pop(ctx);
                  if (r.map['code'] != null) await _showPlain('${r.map['code']}', r.map);
                  if (row != null) toast(t('تم الحفظ', 'Saved'));
                },
              ),
            ]),
          );
        }));
    label.dispose();
    maxC.dispose();
    _load();
    widget.onChanged();
  }

  Future<void> _act(Map<String, dynamic> row, String action) async {
    final s = context.read<OrgSession>();
    final id = row['id'];
    OrgCall r;
    switch (action) {
      case 'on' || 'off':
        r = await orgCall(() => s.api.put('$_url/$id', body: {'status': action == 'on' ? 'active' : 'inactive'}),
            ok: action == 'on' ? t('الكود يعمل الآن', 'Code switched on') : t('أُوقف الكود — من انضموا به يبقون أعضاء', 'Code paused — people who joined stay'));
      case 'revoke':
        if (!await appConfirm(context,
            danger: true, message: t('إلغاء الكود نهائياً؟ لن يعمل بعد الآن، ولا يُخرج من انضموا به.', 'Revoke for good? It stops working; people who joined with it stay.'))) {
          return;
        }
        r = await orgCall(() => s.api.post('$_url/$id/revoke'), ok: t('أُلغي الكود', 'Code revoked'));
      default:
        if (!await appConfirm(context, message: t('تدوير الكود: يُلغى الحالي ويصدر كود جديد بنفس الإعدادات. متابعة؟', 'Rotate: the current code is revoked and a new one with the same settings is issued. Continue?'))) {
          return;
        }
        r = await orgCall(() => s.api.post('$_url/$id/regenerate'));
        if (r.ok && r.map['code'] != null && mounted) await _showPlain('${r.map['code']}', r.map);
    }
    if (r.ok) {
      _load();
      widget.onChanged();
    }
  }

  Future<void> _rotateLegacy() async {
    if (!await appConfirm(context, message: t('إصدار كود عام جديد يوقف الكود الحالي فوراً. متابعة؟', 'A new general code stops the current one at once. Continue?'))) return;
    if (!mounted) return;
    final s = context.read<OrgSession>();
    final r = await orgCall(() => s.api.post('${s.base}/join-code/regenerate'), ok: t('صدر كود جديد', 'New code issued'));
    if (r.ok) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.colors;
    final rows = _rows;
    if (rows == null) {
      return _failed
          ? AppEmpty(icon: Icons.cloud_off_rounded, title: t('تعذّر التحميل', 'Couldn\'t load'), actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
          : const AppListSkeleton();
    }
    final legacy = widget.settings?['legacy_code'];
    final closed = widget.settings?['join_mode'] == 'closed';
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'org_join_code_new',
        backgroundColor: c.primary,
        onPressed: () => _edit(),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(t('كود جديد', 'New code'), style: const TextStyle(fontFamily: 'tajawal', color: Colors.white)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
          if (closed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppBanner(icon: Icons.pause_circle_rounded, color: c.warning,
                  text: t('الانضمام موقوف من «طريقة الانضمام» — لن تعمل أي أكواد حتى تعيد فتحه.', 'Joining is paused in "How people join" — no code works until you reopen it.')),
            ),
          AppBanner(
            icon: Icons.verified_user_rounded,
            text: t('كل كود يحدد الدور والقسم ومدة الصلاحية وعدد الاستخدامات. يُخزَّن مشفّراً ويظهر كاملاً مرة واحدة.',
                'Each code sets the role, department, validity and number of uses. It is stored hashed and shown in full once.'),
          ),
          const SizedBox(height: 10),
          if (legacy != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                child: Row(children: [
                  Icon(Icons.key_rounded, color: c.textMedium),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t('الكود العام للمؤسسة', 'General organization code'), style: orgText(context, w: FontWeight.w800)),
                      SelectableText('$legacy', textDirection: TextDirection.ltr, style: orgText(context, size: 15, w: FontWeight.w800, color: c.primary)),
                      Text(t('ينضم به الطلاب والمدرسون بلا حدود — للتحكم الكامل استخدم الأكواد أدناه.', 'Students and teachers join with it without limits — use the codes below for full control.'),
                          style: orgText(context, size: 11.5, color: c.textLight)),
                    ]),
                  ),
                  IconButton(tooltip: t('تدوير', 'Rotate'), onPressed: _rotateLegacy, icon: const Icon(Icons.autorenew_rounded)),
                ]),
              ),
            ),
          if (rows.isEmpty)
            AppEmpty(
              icon: Icons.qr_code_2_rounded,
              title: t('لا أكواد بعد', 'No codes yet'),
              message: t('أنشئ كوداً لكل دفعة أو قسم، وشاركه برمز QR.', 'Create a code per class or department and share it as a QR.'),
              actionLabel: t('إنشاء كود', 'Create a code'),
              onAction: () => _edit(),
            ),
          for (final r in rows) _codeCard(context, r),
        ]),
      ),
    );
  }

  Widget _codeCard(BuildContext context, Map<String, dynamic> r) {
    final c = context.colors;
    final state = '${r['state']}';
    final live = state == 'active';
    final revoked = r['status'] == 'revoked';
    final until = orgParseUtc(r['valid_until']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 4, 12),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: (live ? c.success : c.textLight).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.qr_code_2_rounded, color: live ? c.success : c.textLight),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r['hint'] ?? ''}${'${r['label'] ?? ''}'.isEmpty ? '' : ' · ${r['label']}'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, w: FontWeight.w800)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                AppBadgePill(codeStateLabels()[state] ?? state, color: live ? c.success : (revoked ? c.danger : c.warning)),
                AppBadgePill(_roleLabels()[r['default_role']] ?? t('طالب', 'Student'), icon: Icons.person_rounded),
                if (r['default_program_id'] != null) AppBadgePill(_programLabel(r['default_program_id']).split(' · ').first, icon: Icons.account_tree_rounded),
                AppBadgePill(r['max_uses'] == null ? t('${r['uses']} استخدام', '${r['uses']} uses') : '${r['uses']} / ${r['max_uses']}', icon: Icons.how_to_reg_rounded),
                if (until != null) AppBadgePill('${t('حتى', 'until')} ${AppTime.date(until)}', icon: Icons.timer_rounded, color: c.warning),
              ]),
            ]),
          ),
          if (!revoked)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'edit' ? _edit(r) : _act(r, v),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(t('تعديل', 'Edit'))),
                if (r['status'] == 'active') PopupMenuItem(value: 'off', child: Text(t('إيقاف مؤقت', 'Pause'))),
                if (r['status'] == 'inactive') PopupMenuItem(value: 'on', child: Text(t('تفعيل', 'Resume'))),
                PopupMenuItem(value: 'regenerate', child: Text(t('تدوير (كود بديل)', 'Rotate (new code)'))),
                PopupMenuItem(value: 'revoke', child: Text(t('إلغاء نهائي', 'Revoke'), style: TextStyle(color: c.danger))),
              ],
            ),
        ]),
      ),
    );
  }
}

// ── Settings ─────────────────────────────────────────────────────────────────

class _JoinSettingsTab extends StatefulWidget {
  const _JoinSettingsTab({required this.settings, required this.onSaved});
  final Map<String, dynamic>? settings;
  final Future<void> Function() onSaved;

  @override
  State<_JoinSettingsTab> createState() => _JoinSettingsTabState();
}

class _JoinSettingsTabState extends State<_JoinSettingsTab> {
  bool? _paused, _requests, _auto, _withCode;
  String? _unit;
  bool _busy = false;

  void _sync() {
    final s = widget.settings;
    if (s == null || _paused != null) return;
    final mode = '${s['join_mode']}';
    _paused = mode == 'closed';
    _requests = mode == 'open' || mode == 'approval' || mode == 'code_req';
    _auto = mode == 'open';
    _withCode = mode == 'code_req';
    _unit = '${s['unit_default'] ?? 'closed'}';
  }

  /// `code_req` = a valid code AND an approval (the code only submits the request).
  String get _mode => _paused!
      ? 'closed'
      : (_requests! ? (_auto! ? 'open' : (_withCode! ? 'code_req' : 'approval')) : 'code');

  Future<void> _save() async {
    final s = context.read<OrgSession>();
    setState(() => _busy = true);
    final r = await orgCall(() => s.api.put('${s.base}/join/settings', body: {'join_mode': _mode, 'unit_default': _unit}),
        ok: t('حُفظت طريقة الانضمام', 'Joining settings saved'));
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    _sync();
    if (_paused == null) return const AppListSkeleton(items: 3, withAvatar: false);
    final summary = _paused!
        ? t('لا أحد ينضم الآن — لا طلبات ولا أكواد.', 'Nobody can join right now — no requests, no codes.')
        : _requests!
            ? (_auto!
                ? t('أي طالب أو مدرس يطلب الانضمام يُقبل فوراً، والأكواد تعمل.', 'Anyone who asks is accepted at once; codes work too.')
                : _withCode!
                    ? t('يلزم كود صالح وطلب معاً: الكود يرسل الطلب فقط، ثم تقبله أو ترفضه. الطلب بلا كود يُرفض.',
                        'A valid code AND a request: the code only sends the request, then you accept or reject it. Requests without a code are refused.')
                    : t('الطلبات تصلك لتقبلها أو ترفضها، والأكواد تعمل.', 'Requests come to you to accept or reject; codes work too.'))
            : t('الانضمام بالأكواد فقط — لا تظهر المؤسسة كخيار «طلب انضمام».', 'Codes only — people can\'t send a request.');
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppSectionTitle(t('الانضمام إلى المؤسسة', 'Joining the organization'), subtitle: t('خاص بمؤسستك فقط', 'For your organization only')),
          const SizedBox(height: 6),
          AppSwitchTile(
            icon: Icons.pause_circle_rounded,
            title: t('إيقاف الانضمام مؤقتاً', 'Pause all joining'),
            subtitle: t('يوقف الطلبات والأكواد معاً', 'Stops requests and codes together'),
            value: _paused!,
            onChanged: (v) => setState(() => _paused = v),
          ),
          if (!_paused!) ...[
            AppSwitchTile(
              icon: Icons.mark_email_unread_rounded,
              title: t('استقبال طلبات الانضمام', 'Accept join requests'),
              subtitle: t('يجد الناس مؤسستك بالبحث ويطلبون الانضمام', 'People find you by search and ask to join'),
              value: _requests!,
              onChanged: (v) => setState(() => _requests = v),
            ),
            if (_requests!)
              AppSwitchTile(
                icon: Icons.bolt_rounded,
                title: t('قبول تلقائي', 'Auto-accept'),
                subtitle: t('يُقبل كل طلب فوراً دون مراجعة', 'Every request is accepted at once, no review'),
                value: _auto!,
                onChanged: (v) => setState(() {
                  _auto = v;
                  if (v) _withCode = false;
                }),
              ),
            if (_requests! && !_auto!)
              AppSwitchTile(
                icon: Icons.qr_code_2_rounded,
                title: t('الطلب يحتاج كوداً صالحاً', 'Requests need a valid code'),
                subtitle: t('كود + طلب: الكود وحده لا يكفي، والطلب بلا كود يُرفض', 'Code + request: a code alone isn\'t enough, and a request without one is refused'),
                value: _withCode!,
                onChanged: (v) => setState(() => _withCode = v),
              ),
          ],
          const SizedBox(height: 6),
          AppBanner(icon: Icons.info_outline_rounded, text: summary, color: _paused! ? c.warning : c.primary),
        ]),
      ),
      const SizedBox(height: 12),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppSectionTitle(t('الانضمام للأقسام (الافتراضي)', 'Joining departments (default)'),
              subtitle: t('للأقسام التي لم تُضبط لها سياسة خاصة — يمكن لكل قسم تغييرها من صفحته', 'For departments without their own policy — each can override it on its page')),
          const SizedBox(height: 8),
          for (final (k, icon, title, sub) in [
            ('closed', Icons.lock_rounded, t('مغلق', 'Closed'), t('لا انضمام إلا بإضافة من الإدارة', 'Only staff add people')),
            ('approval', Icons.how_to_reg_rounded, t('بطلب وموافقة', 'Request + approval'), t('مدير القسم أو إدارة المؤسسة يقبل الطلب', 'The department manager or org admins decide')),
            ('auto', Icons.bolt_rounded, t('قبول تلقائي', 'Auto-accept'), t('يُقبل فوراً عند استيفاء الشروط', 'Accepted at once when eligible')),
            ('code', Icons.qr_code_2_rounded, t('بكود دعوة', 'Invitation code'), t('بكود يصدره القسم', 'With a code the department issues')),
            ('code_req', Icons.verified_user_rounded, t('كود + طلب وموافقة', 'Code + request'),
                t('الكود الصحيح يرسل الطلب، ثم يقرر المعتمد', 'A valid code sends the request, then an approver decides')),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _unit = k),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: _unit == k ? c.primary.withValues(alpha: 0.08) : Colors.transparent,
                    border: Border.all(color: _unit == k ? c.primary : c.divider),
                  ),
                  child: Row(children: [
                    Icon(icon, color: _unit == k ? c.primary : c.textMedium, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, style: orgText(context, w: FontWeight.w800)),
                        Text(sub, style: orgText(context, size: 12, color: c.textMedium)),
                      ]),
                    ),
                    if (_unit == k) Icon(Icons.check_circle_rounded, color: c.primary),
                  ]),
                ),
              ),
            ),
          Text(t('القبول التلقائي والأكواد لا تتجاوز شروط القسم ولا سعته.', 'Auto-accept and codes never bypass a department\'s rules or capacity.'),
              style: orgText(context, size: 11.5, color: c.textLight)),
        ]),
      ),
      const SizedBox(height: 16),
      AppPrimaryButton(label: t('حفظ', 'Save'), icon: Icons.check_rounded, busy: _busy, onPressed: _busy ? null : _save),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Members: one "Join" experience
// ═════════════════════════════════════════════════════════════════════════════

/// Opens the join screen; [onDone] runs after it closes (refresh "my organizations").
Future<void> openOrgJoin(BuildContext context, {VoidCallback? onDone, String? code}) async {
  if (!AppConfig.orgsEnabled) {
    toast(orgCodeText('orgs_disabled'), error: true);
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgJoinPage(initialCode: code)));
  onDone?.call();
}

class OrgJoinPage extends StatefulWidget {
  const OrgJoinPage({super.key, this.initialCode});
  final String? initialCode;

  @override
  State<OrgJoinPage> createState() => _OrgJoinPageState();
}

class _OrgJoinPageState extends State<OrgJoinPage> {
  late final _code = TextEditingController(text: widget.initialCode ?? '');
  final _q = TextEditingController();
  String? _codeError;
  bool _busy = false;
  List<Map<String, dynamic>>? _results;
  Map<String, dynamic>? _status;
  int _searchSeq = 0;

  @override
  void initState() {
    super.initState();
    _search('');
    _loadStatus();
  }

  @override
  void dispose() {
    _code.dispose();
    _q.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    final r = await orgCall(() => OrgApi.i.api.get('$_pub/me/join-status'), quiet: true);
    if (mounted && r.ok) setState(() => _status = r.map);
  }

  Future<void> _search(String q) async {
    final seq = ++_searchSeq;
    final r = await orgCall(() => OrgApi.i.api.get('$_pub/search', queryParams: {if (q.trim().isNotEmpty) 'q': q.trim(), 'size': 30}), quiet: true);
    if (!mounted || seq != _searchSeq) return;
    setState(() => _results = r.ok ? asMapList(r.map['items']) : const []);
  }

  /// "Scan QR": the camera fills in the code and submits it (the manual field stays).
  Future<void> _scanCode() async {
    final code = await openJoinScanner(context);
    if (!mounted || code == null) return;
    setState(() {
      _code.text = code;
      _codeError = null;
    });
    await _joinCode();
  }

  Future<void> _joinCode() async {
    final code = _code.text.trim();
    if (code.length < 4) return setState(() => _codeError = t('أدخل الكود كاملاً', 'Enter the whole code'));
    setState(() {
      _busy = true;
      _codeError = null;
    });
    final r = await orgCall(() => OrgApi.i.api.post('$_pub/join/code', body: {'code': code}), quiet: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) return setState(() => _codeError = joinErrorText(r));
    final m = r.map;
    if (m['needs_form'] == true) {
      final unit = {...asMap(m['unit']), 'policy': m['policy']};
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrgUnitJoinScreen(orgId: asInt(m['org_id']), unit: unit)));
      return _loadStatus();
    }
    _code.clear();
    await _outcome(m);
    _loadStatus();
    _search(_q.text);
  }

  Future<void> _request(Map<String, dynamic> o) async {
    setState(() => _busy = true);
    final r = await orgCall(() => OrgApi.i.api.post('$_pub/join', body: {'org_id': o['id']}), quiet: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      if (r.code == 'code_required') {
        toast(t('هذه المؤسسة تقبل الانضمام بالكود فقط — اطلبه منها ثم أدخله بالأعلى', 'This organization joins by code only — ask it for one and enter it above'), error: true);
      } else if (r.code == 'request_code_required') {
        toast(t('هذه المؤسسة تحتاج كوداً صالحاً مع الطلب — أدخل الكود بالأعلى ليُرسل طلبك', 'This organization needs a valid code with the request — enter it above to send your request'), error: true);
      } else {
        toast(joinErrorText(r), error: true);
      }
      return;
    }
    await _outcome({'kind': 'org', 'status': r.map['status'], 'code_verified': r.map['code_verified'], 'organization': r.map['organization'] ?? o});
    _loadStatus();
    _search(_q.text);
  }

  Future<void> _outcome(Map<String, dynamic> m) => showAppSheet<void>(context, (ctx) {
        final c = ctx.colors;
        final isOrg = m['kind'] == 'org';
        final pending = isOrg ? m['status'] == 'pending' : m['joined'] != true;
        final name = isOrg ? orgNameOf(asMap(m['organization'])) : orgNameOf(asMap(m['unit']));
        final dept = asMap(m['department']);
        final verified = m['code_verified'] == true;
        final (icon, color, title, body) = pending
            ? (
                verified ? Icons.verified_rounded : Icons.hourglass_top_rounded,
                c.warning,
                verified
                    ? t('تم التحقق من الكود — طلبك بانتظار الموافقة', 'Code verified — request submitted, awaiting approval')
                    : t('وصل طلبك ✉️', 'Request sent ✉️'),
                t('طلبك للانضمام إلى «$name» قيد المراجعة. سنرسل لك إشعاراً فور القرار، وتتابعه من «طلباتي».',
                    'Your request to join "$name" is being reviewed. We\'ll notify you once it\'s decided — follow it under "My requests".'),
              )
            : (
                Icons.celebration_rounded,
                c.success,
                m['already'] == true ? t('أنت عضو بالفعل', 'You\'re already a member') : t('أهلاً بك! 🎉', 'Welcome aboard! 🎉'),
                t('أصبحت عضواً في «$name».', 'You\'re now a member of "$name".'),
              );
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AppSheetHeader(''),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 36),
            ),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: orgText(ctx, size: 18, w: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center, style: orgText(ctx, color: c.textMedium)),
            if (dept.isNotEmpty) ...[
              const SizedBox(height: 12),
              AppBanner(
                icon: dept['placed'] == true ? Icons.account_tree_rounded : Icons.info_outline_rounded,
                color: dept['placed'] == true ? c.success : c.warning,
                text: dept['placed'] == true
                    ? t('وانضممت أيضاً إلى قسم ${orgNameOf(asMap(dept['unit']))}.', 'You also joined the ${orgNameOf(asMap(dept['unit']))} department.')
                    : t('لم تُضف إلى قسم ${orgNameOf(asMap(dept['unit']))} بعد: ${joinReasonText(asMap(dept['reason']))}',
                        'You weren\'t added to ${orgNameOf(asMap(dept['unit']))} yet: ${joinReasonText(asMap(dept['reason']))}'),
              ),
            ],
            const SizedBox(height: 16),
            AppPrimaryButton(label: t('تم', 'Done'), onPressed: () => Navigator.pop(ctx)),
          ]),
        );
      });

  Future<void> _cancelUnit(Map<String, dynamic> r) async {
    if (!await appConfirm(context, message: t('إلغاء هذا الطلب؟', 'Cancel this request?'))) return;
    final res = await orgCall(() => OrgApi.i.api.post('$_pub/me/unit-requests/${r['id']}/cancel'), ok: t('أُلغي الطلب', 'Request cancelled'));
    if (res.ok) _loadStatus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (!AppConfig.orgsEnabled) {
      return BasePage(
        appBar: ScreenAppBar(title: t('انضمام', 'Join')),
        child: AppEmpty(icon: Icons.domain_disabled_rounded, title: orgCodeText('orgs_disabled')),
      );
    }
    final orgReqs = asMapList(_status?['organizations']);
    final unitReqs = asMapList(_status?['units']);
    return BasePage(
      useWebCard: true,
      maxWith: 760,
      appBar: ScreenAppBar(title: t('انضمام', 'Join')),
      child: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([_loadStatus(), _search(_q.text)]);
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
          AppHero(
            title: t('انضم إلى مؤسستك', 'Join your institution'),
            subtitle: t('أدخل كود الانضمام، أو ابحث عن جامعتك وأرسل طلباً.', 'Enter a join code, or find your university and send a request.'),
            icon: Icons.domain_add_rounded,
          ),
          const SizedBox(height: 14),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.qr_code_2_rounded, color: c.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(t('لديك كود؟', 'Have a code?'), style: orgText(context, w: FontWeight.w800))),
              ]),
              Text(t('يصلح لأي كود: كود المؤسسة أو كود قسم.', 'Works for any code: an organization\'s or a department\'s.'),
                  style: orgText(context, size: 12, color: c.textMedium)),
              const SizedBox(height: 10),
              TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                autocorrect: false,
                onSubmitted: (_) => _joinCode(),
                onChanged: (_) => _codeError == null ? null : setState(() => _codeError = null),
                style: TextStyle(fontFamily: 'bahji', fontSize: 20, letterSpacing: 4, fontWeight: FontWeight.w800, color: c.textDark),
                decoration: InputDecoration(
                  hintText: 'ABCD2345XY',
                  errorText: _codeError,
                  errorMaxLines: 3,
                  filled: true,
                  fillColor: c.inputBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              AppPrimaryButton(label: t('انضمام', 'Join'), icon: Icons.login_rounded, busy: _busy, onPressed: _busy ? null : _joinCode),
              if (joinScannerAvailable) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _scanCode,
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: Text(t('مسح رمز QR', 'Scan QR')),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ]),
          ),
          if (orgReqs.isNotEmpty || unitReqs.isNotEmpty) ...[
            const SizedBox(height: 18),
            AppSectionTitle(t('طلباتي', 'My requests'), subtitle: t('تابع حالة طلباتك هنا', 'Follow your requests here')),
            const SizedBox(height: 8),
            for (final r in orgReqs) _statusTile(context, orgNameOf(asMap(r['organization'])), t('المؤسسة', 'Organization'), '${r['status']}', r['created_at']),
            for (final r in unitReqs.take(10))
              _statusTile(
                context,
                orgNameOf(asMap(r['unit'])),
                '${unitKindLabel('${r['unit_type']}')} · ${orgNameOf(asMap(r['organization']))}',
                '${r['status']}',
                r['created_at'],
                note: '${r['note'] ?? ''}',
                onCancel: r['status'] == 'pending' ? () => _cancelUnit(r) : null,
              ),
          ],
          const SizedBox(height: 18),
          AppSectionTitle(t('ابحث عن مؤسستك', 'Find your institution')),
          const SizedBox(height: 8),
          TextField(
            controller: _q,
            onChanged: _search,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: t('اسم الجامعة أو الكلية', 'University or faculty name'),
              filled: true,
              fillColor: c.inputBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),
          if (_results == null)
            const SizedBox(height: 200, child: AppListSkeleton(items: 3))
          else if (_results!.isEmpty)
            AppEmpty(icon: Icons.search_off_rounded, title: t('لا نتائج', 'No results'), message: t('جرّب اسماً آخر أو اطلب الكود من مؤسستك.', 'Try another name or ask your institution for a code.'))
          else
            for (final o in _results!) _orgTile(context, o),
        ]),
      ),
    );
  }

  Widget _statusTile(BuildContext context, String title, String sub, String status, dynamic at, {String note = '', VoidCallback? onCancel}) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 6, 10),
        child: Row(children: [
          Icon(
            switch (status) { 'approved' => Icons.check_circle_rounded, 'rejected' => Icons.cancel_rounded, 'cancelled' => Icons.remove_circle_outline_rounded, _ => Icons.hourglass_top_rounded },
            color: statusColor(context, status),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, w: FontWeight.w800)),
              Text('$sub · ${relTime(at)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, size: 12, color: c.textMedium)),
              if (note.isNotEmpty) Text('💬 $note', maxLines: 2, overflow: TextOverflow.ellipsis, style: orgText(context, size: 12)),
            ]),
          ),
          AppBadgePill(requestStatusLabels()[status] ?? statusLabel(status), color: statusColor(context, status)),
          if (onCancel != null) IconButton(tooltip: t('إلغاء الطلب', 'Cancel request'), onPressed: onCancel, icon: const Icon(Icons.close_rounded, size: 18)),
        ]),
      ),
    );
  }

  Widget _orgTile(BuildContext context, Map<String, dynamic> o) {
    final c = context.colors;
    final my = '${o['my_status'] ?? ''}';
    final mode = '${o['join_mode']}';
    final Widget trailing = my == 'active'
        ? AppBadgePill(t('عضو', 'Member'), color: c.success, icon: Icons.check_rounded)
        : my == 'pending'
            ? AppBadgePill(t('قيد المراجعة', 'Pending'), color: c.warning)
            : mode == 'code' || mode == 'code_req'
                ? AppBadgePill(mode == 'code' ? t('بكود فقط', 'Code only') : t('كود + موافقة', 'Code + approval'),
                    color: c.textMedium, icon: Icons.qr_code_2_rounded)
                : FilledButton(
                    onPressed: _busy ? null : () => _request(o),
                    child: Text(mode == 'open' ? t('انضم', 'Join') : t('اطلب', 'Request')),
                  );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          AppAvatar(name: orgNameOf(o), url: o['logo_url'] as String?),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(orgNameOf(o), maxLines: 2, overflow: TextOverflow.ellipsis, style: orgText(context, w: FontWeight.w800)),
              Text(
                mode == 'open'
                    ? t('قبول فوري', 'Instant join')
                    : mode == 'approval'
                        ? t('بموافقة الإدارة', 'Needs approval')
                        : mode == 'code_req'
                            ? t('أدخل كود المؤسسة بالأعلى ليُرسل طلبك، ثم تقرر الإدارة', 'Enter the institution\'s code above to send a request, then it decides')
                            : t('اطلب الكود من المؤسسة', 'Ask the institution for a code'),
                style: orgText(context, size: 12, color: c.textMedium),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          trailing,
        ]),
      ),
    );
  }
}
