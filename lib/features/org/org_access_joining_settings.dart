// lib/features/org/org_access_joining_settings.dart — part of org_access_joining.dart
part of 'org_access_joining.dart';

// ── Settings ─────────────────────────────────────────────────────────────────

class _JoinSettingsTab extends StatefulWidget {
  const _JoinSettingsTab({required this.settings, required this.onSaved, this.error});
  final Map<String, dynamic>? settings;
  final Future<void> Function() onSaved;
  final String? error;

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
    if (_paused == null) {
      return widget.error != null
          ? ErrorRetry(message: widget.error!, onRetry: widget.onSaved)
          : const AppListSkeleton(items: 3, withAvatar: false);
    }
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
    return ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxl), children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppSectionTitle(t('الانضمام إلى المؤسسة', 'Joining the organization'), subtitle: t('خاص بمؤسستك فقط', 'For your organization only')),
          const SizedBox(height: AppSpace.xs),
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
          const SizedBox(height: AppSpace.xs),
          AppBanner(icon: Icons.info_outline_rounded, text: summary, color: _paused! ? c.warning : c.primary),
        ]),
      ),
      const SizedBox(height: AppSpace.sm),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppSectionTitle(t('الانضمام للأقسام (الافتراضي)', 'Joining departments (default)'),
              subtitle: t('للأقسام التي لم تُضبط لها سياسة خاصة — يمكن لكل قسم تغييرها من صفحته', 'For departments without their own policy — each can override it on its page')),
          const SizedBox(height: AppSpace.xs),
          for (final (k, icon, title, sub) in [
            ('closed', Icons.lock_rounded, t('مغلق', 'Closed'), t('لا انضمام إلا بإضافة من الإدارة', 'Only staff add people')),
            ('approval', Icons.how_to_reg_rounded, t('بطلب وموافقة', 'Request + approval'), t('مدير القسم أو إدارة المؤسسة يقبل الطلب', 'The department manager or org admins decide')),
            ('auto', Icons.bolt_rounded, t('قبول تلقائي', 'Auto-accept'), t('يُقبل فوراً عند استيفاء الشروط', 'Accepted at once when eligible')),
            ('code', Icons.qr_code_2_rounded, t('بكود دعوة', 'Invitation code'), t('بكود يصدره القسم', 'With a code the department issues')),
            ('code_req', Icons.verified_user_rounded, t('كود + طلب وموافقة', 'Code + request'),
                t('الكود الصحيح يرسل الطلب، ثم يقرر المعتمد', 'A valid code sends the request, then an approver decides')),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.control),
                onTap: () => setState(() => _unit = k),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.all(AppSpace.sm),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    color: _unit == k ? c.primary.withValues(alpha: 0.08) : Colors.transparent,
                    border: Border.all(color: _unit == k ? c.primary : c.divider),
                  ),
                  child: Row(children: [
                    Icon(icon, color: _unit == k ? c.primary : c.textMedium, size: AppIconSize.md),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, style: AppType.bodyStrong(context)),
                        Text(sub, style: AppType.meta(context).copyWith(color: c.textMedium)),
                      ]),
                    ),
                    if (_unit == k) Icon(Icons.check_circle_rounded, color: c.primary),
                  ]),
                ),
              ),
            ),
          Text(t('القبول التلقائي والأكواد لا تتجاوز شروط القسم ولا سعته.', 'Auto-accept and codes never bypass a department\'s rules or capacity.'),
              style: AppType.meta(context).copyWith(color: c.textLight)),
        ]),
      ),
      const SizedBox(height: AppSpace.md),
      AppButton.primary(label: t('حفظ', 'Save'), icon: Icons.check_rounded, busy: _busy, onPressed: _busy ? null : _save),
    ]);
  }
}

