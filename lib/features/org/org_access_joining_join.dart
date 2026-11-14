// lib/features/org/org_access_joining_join.dart — part of org_access_joining.dart
part of 'org_access_joining.dart';

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
  const OrgJoinPage({super.key, this.initialCode, this.isParent, this.scannerAvailable});
  final String? initialCode;

  /// A parent account can't join (role_cannot_join): null = ask the session.
  final bool? isParent;

  /// The camera scanner exists (false on web): null = [joinScannerAvailable].
  final bool? scannerAvailable;

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
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AppSheetHeader(''),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: AppIconSize.hero),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(title, textAlign: TextAlign.center, style: AppType.section(ctx)),
            const SizedBox(height: AppSpace.xs),
            Text(body, textAlign: TextAlign.center, style: AppType.row(ctx).copyWith(color: c.textMedium)),
            if (dept.isNotEmpty) ...[
              const SizedBox(height: AppSpace.sm),
              AppBanner(
                icon: dept['placed'] == true ? Icons.account_tree_rounded : Icons.info_outline_rounded,
                color: dept['placed'] == true ? c.success : c.warning,
                text: dept['placed'] == true
                    ? t('وانضممت أيضاً إلى قسم ${orgNameOf(asMap(dept['unit']))}.', 'You also joined the ${orgNameOf(asMap(dept['unit']))} department.')
                    : t('لم تُضف إلى قسم ${orgNameOf(asMap(dept['unit']))} بعد: ${joinReasonText(asMap(dept['reason']))}',
                        'You weren\'t added to ${orgNameOf(asMap(dept['unit']))} yet: ${joinReasonText(asMap(dept['reason']))}'),
              ),
            ],
            const SizedBox(height: AppSpace.md),
            AppButton.primary(label: t('تم', 'Done'), onPressed: () => Navigator.pop(ctx)),
          ]),
        );
      });

  Future<void> _cancelUnit(Map<String, dynamic> r) async {
    if (!await appConfirm(context, message: t('إلغاء هذا الطلب؟', 'Cancel this request?'))) return;
    final res = await orgCall(() => OrgApi.i.api.post('$_pub/me/unit-requests/${r['id']}/cancel'), ok: t('أُلغي الطلب', 'Request cancelled'));
    if (res.ok) _loadStatus();
  }

  /// Withdraw my own pending request to an organization (POST /public/{org}/join-request/cancel).
  Future<void> _cancelOrg(Map<String, dynamic> r) async {
    final org = asMap(r['organization']);
    if (!await appConfirm(context, message: t('سحب طلب الانضمام إلى «${orgNameOf(org)}»؟', 'Withdraw your request to join "${orgNameOf(org)}"?'))) return;
    final res = await orgCall(() => OrgApi.i.api.post('$_pub/${org['id']}/join-request/cancel'), quiet: true);
    if (!mounted) return;
    if (!res.ok) {
      // already decided meanwhile: just show the new state
      showAppNotice(orgErrorText(res.error!), error: true);
    } else {
      showAppNotice(t('سُحب الطلب', 'Request withdrawn'));
    }
    _loadStatus();
    _search(_q.text);
  }

  bool get _parent {
    if (widget.isParent != null) return widget.isParent!;
    try {
      return Provider.of<MyAuthProvider>(context, listen: false).isParent;
    } catch (_) {
      return false;
    }
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
    if (_parent) {
      // parents follow their child's organization instead (C2); say so before they type a code
      return BasePage(
        appBar: ScreenAppBar(title: t('انضمام', 'Join')),
        child: AppEmpty(icon: Icons.family_restroom_rounded, title: t('حساب ولي الأمر لا ينضم للمؤسسات', 'Parent accounts can\'t join organizations'), message: orgCodeText('role_cannot_join')),
      );
    }
    final orgReqs = asMapList(_status?['organizations']);
    final unitReqs = asMapList(_status?['units']);
    return BasePage(
      useWebCard: true,
      maxWith: 760,
      appBar: ScreenAppBar(title: t('انضمام', 'Join')),
      child: AppRefresh(
        onRefresh: () async {
          await Future.wait([_loadStatus(), _search(_q.text)]);
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxl), children: [
          AppHero(
            title: t('انضم إلى مؤسستك', 'Join your institution'),
            subtitle: t('أدخل كود الانضمام، أو ابحث عن جامعتك وأرسل طلباً.', 'Enter a join code, or find your university and send a request.'),
            icon: Icons.domain_add_rounded,
          ),
          const SizedBox(height: AppSpace.md),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.qr_code_2_rounded, color: c.primary),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: Text(t('لديك كود؟', 'Have a code?'), style: AppType.bodyStrong(context))),
              ]),
              Text(t('يصلح لأي كود: كود المؤسسة أو كود قسم.', 'Works for any code: an organization\'s or a department\'s.'),
                  style: AppType.meta(context).copyWith(color: c.textMedium)),
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                autocorrect: false,
                onSubmitted: (_) => _joinCode(),
                onChanged: (_) => _codeError == null ? null : setState(() => _codeError = null),
                style: AppType.pageTitle(context).copyWith(fontFamily: AppFonts.display, letterSpacing: 4, color: c.textDark),
                decoration: InputDecoration(
                  hintText: 'ABCD2345XY',
                  errorText: _codeError,
                  errorMaxLines: 3,
                  filled: true,
                  fillColor: c.inputBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              AppButton.primary(label: t('انضمام', 'Join'), icon: DirIcons.login, busy: _busy, onPressed: _busy ? null : _joinCode),
              if (widget.scannerAvailable ?? joinScannerAvailable) ...[
                const SizedBox(height: AppSpace.xs),
                SizedBox(
                  width: double.infinity,
                  child: AppButton.secondary(expand: true, onPressed: _busy ? null : _scanCode, icon: Icons.qr_code_scanner_rounded, label: t('مسح رمز QR', 'Scan QR')),
                ),
              ] else ...[
                const SizedBox(height: AppSpace.xs),
                // the camera scanner is a phone feature (mobile_scanner loads ZXing from a CDN on the web)
                Row(key: const ValueKey('org.join.no_scan'), crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.qr_code_scanner_rounded, size: AppIconSize.md, color: c.textLight),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(
                    child: Text(
                      t('مسح رمز QR متاح في تطبيق الهاتف. هنا اكتب الكود بالأعلى، أو افتح الرابط الذي وصلك.',
                          'Scanning a QR code works in the phone app. Here, type the code above or open the link you were sent.'),
                      style: AppType.meta(context).copyWith(color: c.textMedium),
                    ),
                  ),
                ]),
              ],
            ]),
          ),
          if (orgReqs.isNotEmpty || unitReqs.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            AppSectionTitle(t('طلباتي', 'My requests'), subtitle: t('تابع حالة طلباتك هنا', 'Follow your requests here')),
            const SizedBox(height: AppSpace.xs),
            for (final r in orgReqs)
              _statusTile(
                context,
                orgNameOf(asMap(r['organization'])),
                t('المؤسسة', 'Organization'),
                '${r['status']}',
                r['created_at'],
                onCancel: r['status'] == 'pending' ? () => _cancelOrg(r) : null,
                onAgain: r['status'] == 'rejected' ? () => _request(asMap(r['organization'])) : null,
              ),
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
          const SizedBox(height: AppSpace.md),
          AppSectionTitle(t('ابحث عن مؤسستك', 'Find your institution')),
          const SizedBox(height: AppSpace.xs),
          TextField(
            controller: _q,
            onChanged: _search,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: t('اسم الجامعة أو الكلية', 'University or faculty name'),
              filled: true,
              fillColor: c.inputBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: AppSpace.xs),
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

  Widget _statusTile(BuildContext context, String title, String sub, String status, dynamic at, {String note = '', VoidCallback? onCancel, VoidCallback? onAgain}) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppCard(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.sm),
        child: Row(children: [
          Icon(
            switch (status) { 'approved' => Icons.check_circle_rounded, 'rejected' => Icons.cancel_rounded, 'cancelled' => Icons.remove_circle_outline_rounded, _ => Icons.hourglass_top_rounded },
            color: statusColor(context, status)),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              Text('$sub · ${relTime(at)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
              if (note.isNotEmpty) Text('💬 $note', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: context.colors.textDark)),
            ]),
          ),
          AppBadgePill(requestStatusLabels()[status] ?? statusLabel(status), color: statusColor(context, status)),
          if (onCancel != null) IconButton(tooltip: t('إلغاء الطلب', 'Cancel request'), onPressed: onCancel, icon: const Icon(Icons.close_rounded, size: AppIconSize.md)),
          if (onAgain != null) TextButton(onPressed: _busy ? null : onAgain, child: Text(t('اطلب مجدداً', 'Request again'))),
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
                : AppButton.tonal(size: AppButtonSize.sm, onPressed: _busy ? null : () => _request(o), label: mode == 'open' ? t('انضم', 'Join') : t('اطلب', 'Request'));
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Row(children: [
          AppAvatar(name: orgNameOf(o), url: o['logo_url'] as String?),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(orgNameOf(o), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              Text(
                mode == 'open'
                    ? t('قبول فوري', 'Instant join')
                    : mode == 'approval'
                        ? t('بموافقة الإدارة', 'Needs approval')
                        : mode == 'code_req'
                            ? t('أدخل كود المؤسسة بالأعلى ليُرسل طلبك، ثم تقرر الإدارة', 'Enter the institution\'s code above to send a request, then it decides')
                            : t('اطلب الكود من المؤسسة', 'Ask the institution for a code'),
                style: AppType.meta(context).copyWith(color: c.textMedium),
              ),
            ]),
          ),
          const SizedBox(width: AppSpace.xs),
          trailing,
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  /j/<CODE>: a shared join link
// ═════════════════════════════════════════════════════════════════════════════

/// The page behind `https://alfheemacademy.com/j/<CODE>`: the Join page with the code filled in (not sent: the person
/// confirms). Signed out, it explains and sends to sign-in / sign-up; the link is remembered through
/// [SignInReturn] (D-170) so the first signed-in page opens it again with the same code.
class OrgJoinLinkPage extends StatelessWidget {
  const OrgJoinLinkPage({super.key, required this.code, this.signedIn});
  final String code;

  /// null = ask the session (tests pass it).
  final bool? signedIn;

  @override
  Widget build(BuildContext context) {
    final norm = parseJoinQr(code) ?? code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (signedIn ?? ApiClient().hasSession) return OrgJoinPage(initialCode: norm);
    void go(String route) {
      SignInReturn.pending = '/j/$norm';
      Navigator.of(context).pushNamed(route);
    }

    return BasePage(
      useWebCard: true,
      maxWith: 560,
      appBar: ScreenAppBar(title: t('انضمام', 'Join')),
      child: JoinLinkSignedOut(code: norm, onSignIn: () => go('/login'), onRegister: () => go('/register')),
    );
  }
}

/// What a signed-out visitor of a join link sees (plain values).
class JoinLinkSignedOut extends StatelessWidget {
  const JoinLinkSignedOut({super.key, required this.code, this.onSignIn, this.onRegister});
  final String code;
  final VoidCallback? onSignIn, onRegister;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
      AppCard(
        child: Column(children: [
          Icon(Icons.domain_add_rounded, size: AppIconSize.hero, color: c.primary),
          AppSpace.gapSm,
          Text(t('دعوة للانضمام إلى مؤسسة', 'You have a link to join an organization'), textAlign: TextAlign.center, style: AppType.pageTitle(context)),
          AppSpace.gapSm,
          FittedBox(
            child: Text(code, textDirection: TextDirection.ltr, style: AppType.display(context).copyWith(fontFamily: AppFonts.display, letterSpacing: 4, color: c.primary)),
          ),
          AppSpace.gapSm,
          Text(t('سجّل الدخول أو أنشئ حساباً وسنكمل الانضمام بهذا الكود.', 'Sign in or create an account and we continue joining with this code.'),
              textAlign: TextAlign.center, style: AppType.body(context)),
        ]),
      ),
      AppSpace.gapMd,
      AppButton.primary(key: const ValueKey('org.join_link.sign_in'), label: t('تسجيل الدخول', 'Sign in'), icon: DirIcons.login, expand: true, onPressed: onSignIn),
      AppSpace.gapXs,
      AppButton.secondary(key: const ValueKey('org.join_link.register'), label: t('إنشاء حساب', 'Create an account'), expand: true, onPressed: onRegister),
    ]);
  }
}
