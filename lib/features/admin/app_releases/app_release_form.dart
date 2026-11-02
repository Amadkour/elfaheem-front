// lib/features/admin/app_releases/app_release_form.dart
//
// "New version" (D-143, docs/release/APP_RELEASES.md "Flow" 1) as a full page: the platform as cards, version +
// build number (prefilled from the newest one + 1), what's new in Arabic and English, the update policy + the minimum
// supported version, the branch (default `production`) and the gate for the platforms the build server builds, the
// download source with its link, and "publish when the build succeeds". Create asks for the account password (the
// re-auth sheet) and sends it with the request; the server's refusals land on their field (version_exists → the
// version, branch_invalid / branch_not_found → the branch) or in the strip above the button (reauth_failed,
// build_running). On success the page pops with the new release.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/theme/theme_config_provider.dart';
import '../../../core/display/app_fonts.dart';
import '../../../design/app_kit.dart';
import '../../../design/app_notice.dart';
import '../../../design/app_tokens.dart';
import '../../../utils/widget/app_bar.dart';
import '../../../utils/widget/base_page.dart';
import '../../auth/reauth_sheet.dart';
import '../admin_common.dart' show t;
import 'app_releases_api.dart';
import 'app_releases_models.dart';
import 'app_releases_text.dart';

/// Asks for the account password (the re-auth sheet, without the two-step code field); null when dismissed.
typedef ReleasePasswordPrompt = Future<String?> Function(BuildContext context);

Future<String?> askReleasePassword(BuildContext context) async {
  final r = await showAppSheet<Reauth>(context, (ctx) => ReauthSheetBody(showMfa: false, onSubmit: (r) => Navigator.pop(ctx, r)));
  return r?.password;
}

/// The branch the live site is built from today (shown as a hint under the branch field).
const String kLiveSiteBranch = 'organizations';

class NewAppReleasePage extends StatefulWidget {
  const NewAppReleasePage({
    super.key,
    this.api = const AppReleasesApi(),
    this.latest = const {},
    this.nextBuild = const {},
    this.initialPlatform = 'android',
    this.askPassword = askReleasePassword,
  });

  final AppReleasesApi api;

  /// The newest release of each platform (the version / build number are prefilled from it + 1).
  final Map<String, AppRelease> latest;

  /// The server's default build number per platform (`next_build_number` of the list).
  final Map<String, int> nextBuild;
  final String initialPlatform;
  final ReleasePasswordPrompt askPassword;

  @override
  State<NewAppReleasePage> createState() => NewAppReleasePageState();
}

class NewAppReleasePageState extends State<NewAppReleasePage> {
  late String _platform = widget.initialPlatform;
  final _version = TextEditingController();
  final _build = TextEditingController();
  final _notesAr = TextEditingController();
  final _notesEn = TextEditingController();
  final _min = TextEditingController();
  final _branch = TextEditingController(text: 'production');
  final _url = TextEditingController();
  String _policy = 'recommended';
  String _gate = 'test_first';
  String _source = 'website';
  bool _auto = true;
  bool _busy = false;
  Map<String, String> _errors = const {};

  /// A refusal that belongs to no field (wrong password, a build already running, …).
  String? _general;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  @override
  void dispose() {
    for (final c in [_version, _build, _notesAr, _notesEn, _min, _branch, _url]) {
      c.dispose();
    }
    super.dispose();
  }

  void _prefill() {
    final last = widget.latest[_platform];
    _version.text = last == null ? '1.0.0' : nextPatchVersion(last.version);
    _build.text = '${widget.nextBuild[_platform] ?? (last?.buildNumber ?? 0) + 1}';
    if (!releaseSourcesFor(_platform).contains(_source)) _source = 'website';
  }

  void _pickPlatform(String p) {
    if (p == _platform) return;
    setState(() {
      _platform = p;
      _errors = const {};
      _general = null;
      _prefill();
    });
  }

  AppReleaseDraft get _draft => AppReleaseDraft(
        platform: _platform,
        version: _version.text.trim(),
        buildNumber: int.tryParse(_build.text.trim()),
        notesAr: _notesAr.text.trim(),
        notesEn: _notesEn.text.trim(),
        policy: _policy,
        minSupported: _min.text.trim().isEmpty ? null : _min.text.trim(),
        branch: _branch.text.trim(),
        gate: _gate,
        source: _platform == 'web' ? 'website' : _source,
        storeUrl: _url.text.trim(),
        autoPublish: _auto,
      );

  Future<void> _submit() async {
    if (_busy) return;
    final d = _draft;
    final errs = validateReleaseDraft(d);
    if (_build.text.trim().isNotEmpty && d.buildNumber == null) errs['build_number'] = 'build_number';
    setState(() {
      _errors = {for (final e in errs.entries) e.key: releaseFieldError(e.value)};
      _general = null;
    });
    if (errs.isNotEmpty) {
      showAppNotice(t('راجع الحقول المعلَّمة', 'Check the marked fields'), error: true);
      return;
    }
    final password = await widget.askPassword(context);
    if (password == null || password.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final created = await widget.api.create(d, password: password);
      if (!mounted) return;
      showAppNotice(t('أُنشئ الإصدار ${created.label} — يبدأ خادم البناء العمل عليه', 'Version ${created.label} created — the build server picks it up next'));
      Navigator.of(context).pop(created);
    } catch (e) {
      final f = ReleaseFailure.from(e);
      if (!mounted) return;
      final field = releaseErrorField(f.code);
      setState(() {
        if (field != null) {
          _errors = {..._errors, field: f.message};
        } else {
          _general = f.message;
        }
      });
      showAppNotice(f.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final buildable = releasePlatformBuildable(_platform);
    final last = widget.latest[_platform];
    return BasePage(
      key: const ValueKey('release.form'),
      appBar: ScreenAppBar(title: t('إصدار جديد', 'New version')),
      child: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.lg),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _Section(
                      title: t('المنصة', 'Platform'),
                      child: _PlatformCards(selected: _platform, onPick: _pickPlatform),
                    ),
                    if (_platform == 'ios')
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.md),
                        child: AppBanner(icon: Icons.info_outline_rounded, text: releasePlatformHint('ios')),
                      ),
                    _Section(
                      title: t('الإصدار', 'Version'),
                      subtitle: last == null
                          ? t('أول إصدار لهذه المنصة', 'The first version for this platform')
                          : t('الأحدث الآن: ${last.label} (${releaseStatusName(last.status)})', 'Newest now: ${last.label} (${releaseStatusName(last.status)})'),
                      child: _Pair(
                        breakAt: 280, // two short fields: side by side on a phone too
                        first: _Field(
                          fieldKey: 'release.version',
                          controller: _version,
                          label: t('رقم الإصدار', 'Version'),
                          hint: '1.4.0',
                          ltr: true,
                          error: _errors['version'],
                          keyboard: const TextInputType.numberWithOptions(decimal: true),
                        ),
                        second: _Field(
                          fieldKey: 'release.build',
                          controller: _build,
                          label: t('رقم البناء', 'Build number'),
                          hint: '52',
                          ltr: true,
                          error: _errors['build_number'],
                          keyboard: TextInputType.number,
                          digitsOnly: true,
                        ),
                      ),
                    ),
                    _Section(
                      title: t('ما الجديد', "What's new"),
                      subtitle: t('يظهر في نافذة التحديث وصفحة التنزيلات', 'Shown in the update prompt and on the downloads page'),
                      child: _Pair(
                        first: _Field(fieldKey: 'release.notes_ar', controller: _notesAr, label: t('بالعربية', 'In Arabic'), maxLines: 4, rtl: true),
                        second: _Field(fieldKey: 'release.notes_en', controller: _notesEn, label: t('بالإنجليزية', 'In English'), maxLines: 4, ltr: true),
                      ),
                    ),
                    _Section(
                      title: t('سياسة التحديث', 'Update policy'),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        _ChoiceGrid(
                          minWidth: 220,
                          children: [
                            for (final p in const ['optional', 'recommended', 'must'])
                              _ChoiceCard(
                                key: ValueKey('release.policy.$p'),
                                icon: switch (p) {
                                  'must' => Icons.priority_high_rounded,
                                  'recommended' => Icons.thumb_up_alt_outlined,
                                  _ => Icons.notifications_off_outlined,
                                },
                                title: releasePolicyName(p),
                                subtitle: releasePolicyHint(p),
                                selected: _policy == p,
                                color: p == 'must' ? c.danger : null,
                                onTap: () => setState(() => _policy = p),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpace.sm),
                        _Field(
                          fieldKey: 'release.min_supported',
                          controller: _min,
                          label: t('أقل إصدار مدعوم (اختياري)', 'Minimum supported version (optional)'),
                          hint: t('ما دونه يُجبَر على التحديث، مثل 1.2.0', 'Anything older must update, e.g. 1.2.0'),
                          ltr: true,
                          error: _errors['min_supported'],
                        ),
                      ]),
                    ),
                    if (buildable)
                      _Section(
                        title: t('البناء', 'Build'),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          _Field(
                            fieldKey: 'release.branch',
                            controller: _branch,
                            label: t('الفرع', 'Branch'),
                            helper: t('الموقع المنشور الآن مبني من الفرع $kLiveSiteBranch', 'The live site is currently built from $kLiveSiteBranch'),
                            ltr: true,
                            error: _errors['branch'],
                          ),
                          const SizedBox(height: AppSpace.sm),
                          _ChoiceGrid(
                            minWidth: 280,
                            children: [
                              _ChoiceCard(
                                key: const ValueKey('release.gate.test_first'),
                                icon: Icons.fact_check_outlined,
                                title: releaseGateName('test_first'),
                                subtitle: t('يُشغَّل المحلل وكل مجموعات الاختبار قبل البناء؛ يضيف ٢٠–٣٠ دقيقة لكنه يوقف إصداراً معطوباً',
                                    'The analyzer and every test suite run before the build; adds 20–30 minutes but stops a broken version'),
                                selected: _gate == 'test_first',
                                onTap: () => setState(() => _gate = 'test_first'),
                              ),
                              _ChoiceCard(
                                key: const ValueKey('release.gate.direct'),
                                icon: Icons.bolt_rounded,
                                title: releaseGateName('direct'),
                                subtitle: t('يبني ويرفع فوراً دون اختبارات — للإصلاحات العاجلة على فرع مُختبَر',
                                    'Builds and uploads at once, no tests — for urgent fixes on a branch already tested'),
                                selected: _gate == 'direct',
                                color: c.warning,
                                onTap: () => setState(() => _gate = 'direct'),
                              ),
                            ],
                          ),
                        ]),
                      ),
                    if (_platform != 'web') _sourceSection(context),
                    _Section(
                      title: t('النشر', 'Publishing'),
                      child: AppCard(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xxs),
                        child: AppSwitchTile(
                          key: const ValueKey('release.auto_publish'),
                          // a Google Play release goes live by hand after the Play Console upload
                          subtitleWidget: _source == 'google_play' && _platform == 'android'
                              ? Text(t('إصدار Google Play يُنشر يدوياً بعد رفعه في Play Console', 'A Google Play version goes live by hand after the Play Console upload'),
                                  style: AppType.meta(context).copyWith(fontFamily: AppFonts.family, color: c.warning))
                              : null,
                          icon: Icons.rocket_launch_rounded,
                          title: buildable
                              ? t('انشر تلقائياً عند نجاح البناء', 'Publish automatically when the build succeeds')
                              : t('اجعله المنشور فور حفظه', 'Make it live as soon as it is saved'),
                          subtitle: t('وإلا يبقى «جاهزاً» حتى تضغط «انشره الآن»', 'Otherwise it stays Ready until you press Make live'),
                          value: _auto,
                          onChanged: (v) => setState(() => _auto = v),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
        _SubmitBar(
          error: _general,
          busy: _busy,
          label: buildable ? t('أنشئ الإصدار وابدأ البناء', 'Create and start the build') : t('سجّل الإصدار', 'Save the version'),
          onSubmit: _submit,
        ),
      ]),
    );
  }

  Widget _sourceSection(BuildContext context) {
    final sources = releaseSourcesFor(_platform);
    final needsUrl = AppReleaseDraft.needsUrl(_platform, _source);
    final urlLabel = switch (_source) {
      'google_play' => t('رابط التطبيق على Google Play', 'Google Play link'),
      'app_store' => t('رابط التطبيق على App Store', 'App Store link'),
      'custom' => t('الرابط', 'Link'),
      _ => t('رابط الملف', 'File link'),
    };
    return _Section(
      title: t('مصدر التنزيل', 'Download source'),
      subtitle: t('ما يفتحه زر «حدّث الآن» في التطبيق', 'What the app\'s Update button opens'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final s in sources)
            AppChoiceChip(
              key: ValueKey('release.source.$s'),
              label: releaseSourceName(s),
              icon: releaseSourceIcon(s),
              selected: _source == s,
              onTap: () => setState(() => _source = s),
            ),
        ]),
        if (needsUrl) ...[
          const SizedBox(height: AppSpace.sm),
          _Field(
            fieldKey: 'release.store_url',
            controller: _url,
            label: urlLabel,
            hint: 'https://',
            ltr: true,
            keyboard: TextInputType.url,
            error: _errors['store_url'],
          ),
        ],
        if (_source == 'google_play' || _source == 'app_store') ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(
            icon: Icons.back_hand_outlined,
            color: context.colors.warning,
            text: _source == 'google_play'
                ? t('الرفع إلى Google Play يدوي في هذه المرحلة: نزّل ملف AAB من صفحة الإصدار وارفعه في Play Console، ثم اجعله منشوراً.',
                    'Uploading to Google Play is done by hand for now: download the AAB from the version page, upload it in the Play Console, then make it live.')
                : t('لا يُبنى تطبيق للآيفون هنا: يُسجَّل الرابط فقط لتطبيق المتجر مستقبلاً.',
                    'No iPhone app is built here: the link is recorded for a future store app.'),
          ),
        ],
      ]),
    );
  }
}

// ── pieces ────────────────────────────────────────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.xs),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSectionTitle(title, subtitle: subtitle),
          child,
        ]),
      );
}

/// Two fields side by side on a wide window, one under the other on a phone.
class _Pair extends StatelessWidget {
  const _Pair({required this.first, required this.second, this.breakAt = 560});

  final Widget first, second;

  /// Narrower than this: one under the other.
  final double breakAt;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < breakAt) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [first, second]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: first),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: second),
        ]);
      });
}

class _Field extends StatelessWidget {
  const _Field({
    required this.fieldKey,
    required this.controller,
    required this.label,
    this.hint,
    this.helper,
    this.error,
    this.maxLines = 1,
    this.ltr = false,
    this.rtl = false,
    this.keyboard,
    this.digitsOnly = false,
  });

  final String fieldKey;
  final TextEditingController controller;
  final String label;
  final String? hint, helper, error;
  final int maxLines;
  final bool ltr, rtl, digitsOnly;
  final TextInputType? keyboard;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: TextField(
        key: ValueKey(fieldKey),
        controller: controller,
        maxLines: maxLines,
        minLines: maxLines > 1 ? 2 : 1,
        keyboardType: maxLines > 1 ? TextInputType.multiline : keyboard,
        inputFormatters: digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
        textDirection: ltr ? TextDirection.ltr : (rtl ? TextDirection.rtl : null),
        style: appText(14, c: c.textDark).copyWith(fontFamilyFallback: AppFonts.fallback), // Arabic notes in an English UI
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          helperMaxLines: 2,
          errorText: error,
          errorMaxLines: 3,
          alignLabelWithHint: maxLines > 1,
        ),
      ),
    );
  }
}

/// Lays [children] out in as many equal columns as fit at [minWidth] each.
class _ChoiceGrid extends StatelessWidget {
  const _ChoiceGrid({required this.children, this.minWidth = 200});

  final List<Widget> children;
  final double minWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final cols = (box.maxWidth / minWidth).floor().clamp(1, children.length);
        const gap = AppSpace.xs;
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [for (final ch in children) SizedBox(width: w, child: ch)]);
      });
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.badge,
    this.color,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? c.primary;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? col.withValues(alpha: 0.08) : c.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: BorderSide(color: selected ? col : c.divider, width: selected ? 1.6 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: selected ? col : c.textMedium, size: 22),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: AppType.row(context).copyWith(fontFamily: AppFonts.family, fontWeight: FontWeight.w700)),
                  if (badge != null) ...[
                    const SizedBox(height: 3),
                    AppBadgePill(badge!, color: c.textMedium),
                  ],
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: AppType.meta(context).copyWith(fontFamily: AppFonts.family, height: 1.4)),
                  ],
                ]),
              ),
              const SizedBox(width: AppSpace.xxs),
              Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  size: 20, color: selected ? col : c.textLight),
            ]),
          ),
        ),
      ),
    );
  }
}

class _PlatformCards extends StatelessWidget {
  const _PlatformCards({required this.selected, required this.onPick});

  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        // a phone: two compact columns (name + "Record only"), the chosen platform's line under them
        final compact = box.maxWidth < 560;
        final hint = releasePlatformHint(selected);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _ChoiceGrid(
            minWidth: compact ? 150 : 250,
            children: [
              for (final p in kReleasePlatformOrder)
                _ChoiceCard(
                  key: ValueKey('release.platform.$p'),
                  icon: releasePlatformIcon(p),
                  title: compact ? releasePlatformShort(p) : releasePlatformName(p),
                  subtitle: compact ? null : (p == 'ios' ? t('تطبيق الويب للآيفون', 'The web app for iPhone') : releasePlatformHint(p)),
                  badge: releasePlatformBuildable(p) ? null : t('تسجيل فقط', 'Record only'),
                  selected: selected == p,
                  onTap: () => onPick(p),
                ),
            ],
          ),
          if (compact && selected != 'ios' && hint.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs, top: AppSpace.xs, bottom: AppSpace.xs),
              child: Text(hint, style: AppType.meta(context).copyWith(fontFamily: AppFonts.family, height: 1.4)),
            ),
        ]);
      });
}

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({required this.label, required this.onSubmit, this.busy = false, this.error});

  final String label;
  final VoidCallback onSubmit;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.cardBg,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.divider))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (error != null) ...[
                    AppBanner(key: const ValueKey('release.error'), icon: Icons.error_outline_rounded, color: c.danger, text: error!),
                    const SizedBox(height: AppSpace.xs),
                  ],
                  AppPrimaryButton(
                    key: const ValueKey('release.submit'),
                    label: label,
                    icon: Icons.lock_outline_rounded,
                    busy: busy,
                    onPressed: busy ? null : onSubmit,
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

