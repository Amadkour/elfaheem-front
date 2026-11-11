// lib/features/org/org_access_joining_requests.dart — part of org_access_joining.dart
part of 'org_access_joining.dart';

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
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.lg), // the sheet already lifts above the keyboard
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppSheetHeader(title),
            Field(controller: ctrl, label: t('الملاحظة', 'Note'), maxLines: 3),
            AppButton.primary(label: t('متابعة', 'Continue'), onPressed: () {
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
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
          child: AppBanner(
            icon: Icons.diversity_3_rounded,
            text: t('طلبات كثيرة تنتظرك. وزّع العمل: امنح صلاحية «اعتماد طلبات الانضمام» لأحد الموظفين من الأدوار والصلاحيات.',
                'Many requests are waiting. Share the load: give a staff member the "Approve join requests" permission in Roles & privileges.'),
            action: Wrap(children: [
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider.value(
                        value: s,
                        // staff only (the org admin's tip): the dashboard's own header
                        child: OrgPushedPage(title: t('الأدوار والصلاحيات', 'Roles & privileges'), child: const OrgAccessPage())))),
                child: Text(t('منح الصلاحية', 'Give permission')),
              ),
              IconButton(
                tooltip: t('إخفاء', 'Hide'),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _tipHidden = true),
                icon: Icon(Icons.close_rounded, size: AppIconSize.md, color: c.textLight),
              ),
            ]),
          ),
        ),
      // ONE row: "select all" at the start, ONE filter (All · Organization · Departments) at the end
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xs, AppSpace.sm, AppSpace.md, AppSpace.xxs),
        child: Row(children: [
          if (rows.isNotEmpty) ...[
            Checkbox(
              tristate: true,
              value: _sel.isEmpty ? false : (_sel.length == rows.length ? true : null),
              onChanged: (_) => setState(() => _sel.length == rows.length ? _sel.clear() : _sel.addAll(rows.map((e) => e.$1))),
            ),
            Expanded(
              child: Text(selecting ? t('محدد ${_sel.length}', '${_sel.length} selected') : t('تحديد الكل', 'Select all'),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.textMedium)),
            ),
          ] else
            const Spacer(),
          AppSpace.gapXs,
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: OrgFilterButton<String>(
              value: _filter,
              defaultValue: 'all',
              label: t('الطلبات', 'Requests'),
              options: {
                'all': t('الكل · ${_org!.length + _units!.length}', 'All · ${_org!.length + _units!.length}'),
                'org': t('المؤسسة · ${_org!.length}', 'Organization · ${_org!.length}'),
                'units': t('الأقسام · ${_units!.length}', 'Departments · ${_units!.length}'),
              },
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
        ]),
      ),
      Expanded(
        child: AppRefresh(
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
                  padding: const EdgeInsets.only(bottom: AppSpace.xxxl + AppSpace.xxl),
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
                        padding: const EdgeInsetsDirectional.only(start: AppSpace.xs, top: AppSpace.md),
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
                  padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
                  decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider))),
                  child: Row(children: [
                    Expanded(
                      child: AppButton.primary(expand: true, busy: _busy, onPressed: _busy ? null : () => _decide(true), icon: Icons.done_all_rounded, label: t('قبول (${_sel.length})', 'Accept (${_sel.length})')),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Expanded(
                      child: AppButton(variant: AppButtonVariant.danger, dangerOutline: true, expand: true, onPressed: _busy ? null : () => _decide(false), icon: Icons.close_rounded, label: t('رفض (${_sel.length})', 'Reject (${_sel.length})')),
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
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xxs, AppSpace.xxs, AppSpace.md, AppSpace.xxs),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AdminAvatar(name: '${u['name'] ?? ''}', url: u['image_url'] as String?),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${u['name'] ?? '#${row['id']}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
                Text('${t('للانضمام إلى المؤسسة', 'To join the organization')} · ${_roleLabels()[row['role']] ?? row['role']}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
                Text(relTime(row['created_at']), style: AppType.meta(context).copyWith(color: c.textLight)),
              ]),
            ),
          ]),
          if (row['code_verified'] == true) ...[
            const SizedBox(height: AppSpace.xs),
            AppBadgePill(t('الكود صحيح', 'Code verified'), color: c.success, icon: Icons.verified_rounded),
          ],
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            AppButton.secondary(size: AppButtonSize.sm, onPressed: busy ? null : () => onDecide(true), icon: Icons.check_rounded, label: t('قبول', 'Accept')),
            AppButton.ghost(size: AppButtonSize.sm, onPressed: busy ? null : () => onDecide(false), icon: Icons.close_rounded, label: t('رفض', 'Reject')),
          ]),
        ]),
      ),
    );
  }
}

