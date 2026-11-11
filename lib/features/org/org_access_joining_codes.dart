// lib/features/org/org_access_joining_codes.dart — part of org_access_joining.dart
part of 'org_access_joining.dart';

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
        final link = joinLinkFor(code);
        final share = t('انضم إلى ${_orgName()} على التطبيق: $link\nأو باستخدام الكود: $code', 'Join ${_orgName()} in the app: $link\nOr with the code: $code');
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.xl),
          child: Column(children: [
            AppSheetHeader(t('كود الانضمام جاهز', 'Your join code is ready')),
            Container(
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: c.divider)),
              child: QrImageView(data: joinLinkFor(code), size: 180, backgroundColor: Colors.white),
            ),
            const SizedBox(height: AppSpace.sm),
            FittedBox(
              child: SelectableText(code,
                  textDirection: TextDirection.ltr,
                  style: AppType.display(context).copyWith(fontFamily: AppFonts.display, letterSpacing: 5, color: c.primary)),
            ),
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, alignment: WrapAlignment.center, children: [
              AppBadgePill(_roleLabels()[row['default_role']] ?? t('طالب', 'Student'), icon: Icons.person_rounded),
              if (row['default_program_id'] != null) AppBadgePill(_programLabel(row['default_program_id']), icon: Icons.account_tree_rounded),
            ]),
            const SizedBox(height: AppSpace.sm),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, alignment: WrapAlignment.center, children: [
              AppButton.secondary(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  toast(t('نُسخ الكود', 'Code copied'));
                },
                icon: Icons.copy_rounded,
                label: t('نسخ', 'Copy'),
              ),
              AppButton.primary(
                onPressed: () => SharePlus.instance.share(ShareParams(text: share)),
                icon: Icons.share_rounded,
                label: t('مشاركة', 'Share'),
              ),
            ]),
            const SizedBox(height: AppSpace.sm),
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
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.lg), // the sheet already lifts above the keyboard
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppSheetHeader(row == null ? t('كود انضمام جديد', 'New join code') : t('تعديل الكود', 'Edit code')),
              Field(controller: label, label: t('وصف داخلي (مثلاً: طلاب الفرقة الأولى 2026)', 'Internal label (e.g. Year 1 students 2026)')),
              Text(t('ينضم صاحب الكود بصفته', 'People who use it join as'), style: AppType.label(ctx).copyWith(fontWeight: FontWeight.w600, color: c.textMedium)),
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (final e in _roleLabels().entries) AppChoiceChip(label: e.value, selected: role == e.key, onTap: () => set(() => role = e.key)),
              ]),
              const SizedBox(height: AppSpace.sm),
              if (_programs.isNotEmpty) ...[
                Text(t('القسم العلمي (اختياري)', 'Academic department (optional)'), style: AppType.label(ctx).copyWith(fontWeight: FontWeight.w600, color: c.textMedium)),
                Text(t('للطلاب: يُضافون للقسم إن استوفوا شروطه، وإلا ينضمون للمؤسسة فقط ونخبرهم بالسبب.',
                        'Students are placed in it when they meet its rules; otherwise they join the organization only and see why.'),
                    style: AppType.meta(ctx).copyWith(color: c.textLight)),
                const SizedBox(height: AppSpace.xs),
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                  AppChoiceChip(label: t('بلا قسم', 'None'), selected: program == null, onTap: () => set(() => program = null)),
                  for (final p in _programs.where((x) => x['is_active'] != false))
                    AppChoiceChip(label: '${p['code']}', selected: program == asInt(p['id']), onTap: () => set(() => program = asInt(p['id']))),
                ]),
                const SizedBox(height: AppSpace.sm),
              ],
              Text(t('مدة الصلاحية (اختياري)', 'Validity (optional)'), style: AppType.label(ctx).copyWith(fontWeight: FontWeight.w600, color: c.textMedium)),
              const SizedBox(height: AppSpace.xs),
              Row(children: [
                Expanded(
                    child: AppButton.secondary(expand: true, onPressed: () => pick(true), icon: Icons.play_arrow_rounded, label: from == null ? t('من الآن', 'From now') : shortDate(from!.toIso8601String()))),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                    child: AppButton.secondary(expand: true, onPressed: () => pick(false), icon: Icons.flag_rounded, label: until == null ? t('بلا انتهاء', 'No end') : shortDate(until!.toIso8601String()))),
              ]),
              if (from != null || until != null)
                TextButton(onPressed: () => set(() => from = until = null), child: Text(t('بلا حدود زمنية', 'No time limits'))),
              const SizedBox(height: AppSpace.xs),
              if (row == null)
                AppSwitchTile(
                    title: t('استخدام واحد فقط', 'One use only'),
                    subtitle: t('دعوة شخصية لشخص واحد', 'A personal invitation for one person'),
                    value: oneTime,
                    onChanged: (v) => set(() => oneTime = v)),
              if (!oneTime)
                OrgNumberField(controller: maxC, label: t('أقصى عدد استخدامات (فارغ = بلا حد)', 'Maximum uses (empty = unlimited)')),
              if (err != null) Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: AppBanner(icon: Icons.error_outline_rounded, text: err!, color: c.danger)),
              AppButton.primary(
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
    // The printed general code is a row of the multi-code table now (C6): rotate it through the same route as every
    // code. `legacy_code_id` is the row's id; a server that does not send it yet gets a fresh general code instead.
    final cid = widget.settings?['legacy_code_id'];
    final OrgCall r;
    if (cid != null) {
      r = await orgCall(() => s.api.post('$_url/$cid/regenerate'));
    } else {
      r = await orgCall(() => s.api.post(_url, body: {'default_role': 'student', 'label': t('الكود العام', 'General code')}));
    }
    if (r.ok) {
      if (r.map['code'] != null && mounted) await _showPlain('${r.map['code']}', r.map);
      _load();
      widget.onChanged();
    }
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
        icon: Icon(Icons.add_rounded, color: c.onHero),
        label: Text(t('كود جديد', 'New code'), style: TextStyle(fontFamily: AppFonts.family, color: c.onHero)),
      ),
      body: AppRefresh(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxxl + AppSpace.xl), children: [
          if (closed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: AppBanner(icon: Icons.pause_circle_rounded, color: c.warning,
                  text: t('الانضمام موقوف من «طريقة الانضمام» — لن تعمل أي أكواد حتى تعيد فتحه.', 'Joining is paused in "How people join" — no code works until you reopen it.')),
            ),
          AppBanner(
            icon: Icons.verified_user_rounded,
            text: t('كل كود يحدد الدور والقسم ومدة الصلاحية وعدد الاستخدامات. يُخزَّن مشفّراً ويظهر كاملاً مرة واحدة.',
                'Each code sets the role, department, validity and number of uses. It is stored hashed and shown in full once.'),
          ),
          const SizedBox(height: AppSpace.sm),
          if (legacy != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: AppCard(
                child: Row(children: [
                  Icon(Icons.key_rounded, color: c.textMedium),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t('الكود العام للمؤسسة', 'General organization code'), style: AppType.bodyStrong(context)),
                      SelectableText('$legacy', textDirection: TextDirection.ltr, style: AppType.section(context).copyWith(color: c.primary)),
                      Text(t('ينضم به الطلاب والمدرسون بلا حدود — للتحكم الكامل استخدم الأكواد أدناه.', 'Students and teachers join with it without limits — use the codes below for full control.'),
                          style: AppType.meta(context).copyWith(color: c.textLight)),
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
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppCard(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.xxs, AppSpace.sm),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: (live ? c.success : c.textLight).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.control)),
            child: Icon(Icons.qr_code_2_rounded, color: live ? c.success : c.textLight),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r['hint'] ?? ''}${'${r['label'] ?? ''}'.isEmpty ? '' : ' · ${r['label']}'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              const SizedBox(height: AppSpace.xxs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
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

