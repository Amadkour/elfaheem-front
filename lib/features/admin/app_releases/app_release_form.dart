// lib/features/admin/app_releases/app_release_form.dart
//
// "New version" (D-143, docs/release/APP_RELEASES.md "Flow" 1) as a full page: the platform as cards, version +
// build number (prefilled from the newest one + 1), what's new in Arabic and English, the update policy + the minimum
// supported version, the branch (default `production`) and the gate for the platforms the build server builds, the
// download source with its link, and "publish when the build succeeds".
// D-144 (docs/release/APP_RELEASES_CODEMAGIC.md): the download channel per platform (store | website, only the valid
// ones), the Codemagic settings prefilled from `GET …/config` defaults and editable (workflow, Play track + package
// name, store link, branch — never a secret), and a readiness box listing what the server still lacks (env names);
// Create stays OFF while the chosen platform + channel is not ready, and a 400 `channel_not_configured` lands there too. Create asks for the account password (the
// re-auth sheet) and sends it with the request; the server's refusals land on their field (version_exists → the
// version, branch_invalid / branch_not_found → the branch) or in the strip above the button (reauth_failed,
// build_running). On success the page pops with the new release.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/app_config.dart';
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
    this.initialChannel,
    this.askPassword = askReleasePassword,
    this.config,
  });

  final AppReleasesApi api;

  /// The newest release of each platform (the version / build number are prefilled from it + 1).
  final Map<String, AppRelease> latest;

  /// The server's default build number per platform (`next_build_number` of the list).
  final Map<String, int> nextBuild;
  final String initialPlatform;

  /// The channel picked at open (the platform's default when null or not offered).
  final String? initialChannel;
  final ReleasePasswordPrompt askPassword;

  /// The Codemagic setup, when the caller has it already (fetched from [api] otherwise).
  final ReleaseConfig? config;

  @override
  State<NewAppReleasePage> createState() => NewAppReleasePageState();
}

class NewAppReleasePageState extends State<NewAppReleasePage> {
  late String _platform = widget.initialPlatform;
  late String _channel = _validChannel(widget.initialPlatform, widget.initialChannel);
  final _version = TextEditingController();
  final _build = TextEditingController();
  final _notesAr = TextEditingController();
  final _notesEn = TextEditingController();
  final _min = TextEditingController();
  final _branch = TextEditingController(text: 'production');
  final _url = TextEditingController();
  final _workflow = TextEditingController();
  final _package = TextEditingController();
  String _track = 'internal';
  String _policy = 'recommended';
  String _gate = 'test_first';

  /// D-146: `runner` (your computer, free) or `codemagic`; the server's default once the config is in.
  String _executor = 'codemagic';
  bool _auto = true;
  bool _busy = false;
  Map<String, String> _errors = const {};

  /// A refusal that belongs to no field (wrong password, a build already running, …).
  String? _general;

  /// The Codemagic setup (`GET …/config`); null while it loads or when it failed ([_configError]).
  late ReleaseConfig? _config = widget.config;
  String? _configError;

  /// What the server listed in a 400 `channel_not_configured`, per `platform:channel` (cleared by a new check).
  final Map<String, ReleaseReadiness> _serverMissing = {};

  static String _validChannel(String platform, String? channel) {
    final offered = releaseChannelsFor(platform);
    return channel != null && offered.contains(channel) ? channel : offered.first;
  }

  @override
  void initState() {
    super.initState();
    _prefill();
    _executor = _defaultExecutor(_config);
    if (_config == null) _loadConfig();
  }

  /// The executor the form starts on: the server's default (runner), Codemagic on an older server.
  static String _defaultExecutor(ReleaseConfig? cfg) {
    if (cfg == null || !cfg.supportsRunner) return 'codemagic';
    return kReleaseExecutors.contains(cfg.defaultExecutor) ? cfg.defaultExecutor! : 'runner';
  }

  /// The executor that builds this channel: your computer cannot upload to a store, so a store channel is Codemagic's.
  String get _effectiveExecutor => _channel == 'store' ? 'codemagic' : _executor;

  @override
  void dispose() {
    for (final c in [_version, _build, _notesAr, _notesEn, _min, _branch, _url, _workflow, _package]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() => _configError = null);
    try {
      final cfg = await widget.api.config();
      if (!mounted) return;
      setState(() {
        _config = cfg;
        _executor = _defaultExecutor(cfg);
        _serverMissing.clear();
        _prefillConfig();
      });
    } catch (e) {
      if (mounted) setState(() => _configError = ReleaseFailure.from(e).message);
    }
  }

  void _prefill() {
    final last = widget.latest[_platform];
    _version.text = last == null ? '1.0.0' : nextPatchVersion(last.version);
    _build.text = '${widget.nextBuild[_platform] ?? (last?.buildNumber ?? 0) + 1}';
    _prefillConfig();
  }

  /// The server's defaults for this platform + channel into the fields (editable).
  void _prefillConfig() {
    final d = _config?.defaultsFor(_platform, _channel);
    _workflow.text = d?.workflow ?? '';
    _package.text = d?.packageName ?? '';
    _url.text = d?.storeUrl ?? '';
    _track = kPlayTracks.contains(d?.track) ? d!.track! : 'internal';
    if (d?.branch != null) _branch.text = d!.branch!;
  }

  void _pickPlatform(String p) {
    if (p == _platform) return;
    setState(() {
      _platform = p;
      _channel = _validChannel(p, _channel);
      _errors = const {};
      _general = null;
      _prefill();
    });
  }

  void _pickChannel(String ch) {
    if (ch == _channel) return;
    setState(() {
      _channel = ch;
      _errors = const {};
      _general = null;
      _prefillConfig();
    });
  }

  bool get _builds => releaseChannelBuilds(_platform, _channel);

  String get _key => '$_effectiveExecutor/${releaseChannelKey(_platform, _channel)}';

  /// What blocks this platform + channel: the server's check, plus a refusal it sent; null while it is unknown.
  ReleaseReadiness? get _readiness {
    final cfg = _config;
    final refused = _serverMissing[_key];
    ReleaseReadiness? r =
        cfg?.readiness(_platform, _channel, executor: _effectiveExecutor).without(_fixedByForm) ?? (_builds ? null : ReleaseReadiness.ok);
    if (refused != null) r = (r ?? ReleaseReadiness.ok).and(refused);
    return r;
  }

  /// What this version's own values cover (the server applies the same overrides when it re-checks): a workflow id,
  /// a real Play package name, a known track.
  Set<String> get _fixedByForm {
    final out = <String>{};
    if (kWorkflowPattern.hasMatch(_workflow.text.trim())) out.addAll(kCodemagicWorkflowEnvs);
    if (AppReleaseDraft.playFields(_platform, _channel)) {
      final pkg = _package.text.trim();
      if (kPackageNamePattern.hasMatch(pkg) && !pkg.toLowerCase().startsWith('com.example.')) {
        out.addAll(const {'PLAY_PACKAGE_NAME', 'package_name_example'});
      }
      if (kPlayTracks.contains(_track)) out.add('PLAY_TRACK');
    }
    return out;
  }

  bool get _ready => _readiness?.ready ?? false;

  /// A field the readiness depends on changed.
  void _rebuild(String _) => setState(() {});

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
        channel: _channel,
        storeUrl: _url.text.trim(),
        workflow: _workflow.text.trim(),
        track: _track,
        packageName: _package.text.trim(),
        autoPublish: _auto,
        executor: (_config?.supportsRunner ?? false) ? _effectiveExecutor : null,
      );

  Future<void> _submit() async {
    if (_busy || !_ready) return;
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
      showAppNotice(!d.builds
          ? t('سُجّل الإصدار ${created.label}', 'Version ${created.label} saved')
          : (d.executor == 'runner'
              ? t('أُنشئ الإصدار ${created.label} — ينتظر مشغّل البناء على حاسوبك', 'Version ${created.label} created — waiting for the build runner on your computer')
              : t('أُنشئ الإصدار ${created.label} — بدأ Codemagic بناءه', 'Version ${created.label} created — Codemagic is building it')));
      Navigator.of(context).pop(created);
    } catch (e) {
      final f = ReleaseFailure.from(e);
      if (!mounted) return;
      final field = releaseErrorField(f.code);
      setState(() {
        if (f.code == 'channel_not_configured') {
          // the readiness box lists what the server says is missing; Confirm stays off until a new check
          final refused = ReleaseReadiness.fromJson({...f.extra, 'ready': false});
          _serverMissing[_key] = refused.missing.isEmpty ? const ReleaseReadiness(missing: ['channel_not_configured']) : refused;
        } else if (field != null || f.code == 'config_invalid') {
          // config_invalid names its field (workflow, track, package_name, store_url, branch)
          final at = field ?? '${f.extra['field'] ?? ''}';
          if (at.isEmpty || at == 'config') {
            _general = f.message;
          } else {
            _errors = {..._errors, at: f.message};
          }
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
    final builds = _builds;
    final last = widget.latest[_platform];
    final readiness = _readiness;
    final needsUrl = AppReleaseDraft.needsUrl(_platform, _channel);
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
                    _Section(
                      title: t('قناة التنزيل', 'Download channel'),
                      subtitle: t('من أين يحصل الناس على هذا الإصدار', 'Where people get this version'),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        _ChoiceGrid(
                          minWidth: 280,
                          children: [
                            for (final ch in releaseChannelsFor(_platform))
                              _ChoiceCard(
                                key: ValueKey('release.channel.$ch'),
                                icon: releaseChannelIcon(_platform, ch),
                                title: releaseChannelName(_platform, ch),
                                subtitle: releaseChannelHint(_platform, ch),
                                badge: releaseChannelBuilds(_platform, ch) ? null : t('تسجيل فقط', 'Record only'),
                                selected: _channel == ch,
                                onTap: () => _pickChannel(ch),
                              ),
                          ],
                        ),
                        if (_channel == 'store' && builds) ...[
                          const SizedBox(height: AppSpace.sm),
                          AppBanner(key: const ValueKey('release.store_note'), icon: Icons.gavel_rounded, color: c.warning, text: releaseStoreReviewNote(_platform)),
                        ],
                        if (builds && (_config?.supportsRunner ?? false) && _channel != 'store') ...[
                          const SizedBox(height: AppSpace.sm),
                          _executorPicker(context),
                        ],
                        const SizedBox(height: AppSpace.sm),
                        ReleaseReadinessBox(
                          key: const ValueKey('release.readiness'),
                          builds: builds,
                          builder: releaseExecutorName(_effectiveExecutor),
                          readiness: readiness,
                          loading: _config == null && _configError == null && builds,
                          error: _config == null && builds ? _configError : null,
                          onRetry: _loadConfig,
                          what: '${releasePlatformShort(_platform)} · ${releaseChannelName(_platform, _channel)}',
                        ),
                        const SizedBox(height: AppSpace.sm),
                      ]),
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
                      subtitle: _channel == 'store' && builds
                          ? t('يظهر في نافذة التحديث، ويُرسل إلى المتجر كملاحظات الإصدار', 'Shown in the update prompt and sent to the store as the release notes')
                          : t('يظهر في نافذة التحديث وشريط التنزيل', 'Shown in the update prompt and the download strip'),
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
                    if (builds) _buildSection(context) else if (needsUrl) _linkSection(context),
                    _Section(
                      title: t('النشر', 'Publishing'),
                      child: AppCard(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xxs),
                        child: AppSwitchTile(
                          key: const ValueKey('release.auto_publish'),
                          icon: Icons.rocket_launch_rounded,
                          title: builds
                              ? (_channel == 'store'
                                  ? t('اعتبره منشوراً حين يُنهي Codemagic الرفع إلى المتجر', 'Mark it live when Codemagic finishes the store upload')
                                  : t('انشر تلقائياً عند نجاح البناء', 'Publish automatically when the build succeeds'))
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
          enabled: _ready,
          disabledHint: _ready
              ? null
              : (readiness == null
                  ? (_configError != null
                      ? t('تعذّر التحقق من إعداد البناء — أعد المحاولة أعلاه', 'Could not check the build setup — retry above')
                      : t('يجري التحقق من إعداد البناء…', 'Checking the build setup…'))
                  : t('هذه القناة غير جاهزة بعد — ما ينقصها مذكور أعلاه', 'This channel is not ready yet — what is missing is listed above')),
          label: builds ? t('أنشئ الإصدار وابدأ البناء', 'Create and start the build') : t('سجّل الإصدار', 'Save the version'),
          onSubmit: _submit,
        ),
      ]),
    );
  }

  /// D-146: "Build on" — your computer (free) or Codemagic, with a note when no runner for this platform is on.
  Widget _executorPicker(BuildContext context) {
    final c = context.colors;
    final runners = _config?.runners ?? const ReleaseRunners();
    final noRunner = _executor == 'runner' && !runners.onlineFor(_platform);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('يُبنى على', 'Build on'), style: AppType.row(context).copyWith(fontFamily: AppFonts.family, fontWeight: FontWeight.w700)),
      const SizedBox(height: AppSpace.xs),
      _ChoiceGrid(
        minWidth: 280,
        children: [
          for (final ex in kReleaseExecutors)
            _ChoiceCard(
              key: ValueKey('release.executor.$ex'),
              icon: ex == 'runner' ? Icons.computer_rounded : Icons.cloud_outlined,
              title: releaseExecutorName(ex),
              subtitle: releaseExecutorHint(ex),
              selected: _executor == ex,
              onTap: () => setState(() {
                _executor = ex;
                _general = null;
              }),
            ),
        ],
      ),
      if (noRunner) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(
          key: const ValueKey('release.runner_off'),
          icon: Icons.power_settings_new_rounded,
          color: c.warning,
          text: t('لا يعمل الآن مشغّل يبني ${releasePlatformShort(_platform)}. يُنشأ الإصدار وينتظر في الطابور حتى تشغّل tools/runner/nextbrain_runner.py على حاسوبك.',
              'No runner that builds ${releasePlatformShort(_platform)} is on now. The version is created and waits in the queue until you start tools/runner/nextbrain_runner.py on your computer.'),
        ),
      ],
    ]);
  }

  /// Branch, the Codemagic workflow, Play's track and package name, the store link, the gate — the server's defaults,
  /// editable for this version (never a secret).
  Widget _buildSection(BuildContext context) {
    final c = context.colors;
    final play = AppReleaseDraft.playFields(_platform, _channel);
    final store = _channel == 'store';
    return _Section(
      title: _effectiveExecutor == 'runner' ? t('إعدادات البناء', 'Build settings') : t('البناء على Codemagic', 'Build on Codemagic'),
      subtitle: t('القيم الافتراضية من إعداد الخادم؛ يمكنك تغييرها لهذا الإصدار', "The server's defaults; you may change them for this version"),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Pair(
          first: _Field(
            fieldKey: 'release.branch',
            controller: _branch,
            label: t('الفرع', 'Branch'),
            helper: t('الموقع المنشور الآن مبني من الفرع $kLiveSiteBranch', 'The live site is currently built from $kLiveSiteBranch'),
            ltr: true,
            error: _errors['branch'],
          ),
          second: _Field(
            fieldKey: 'release.workflow',
            controller: _workflow,
            onChanged: _rebuild,
            label: _effectiveExecutor == 'runner' ? t('سير العمل', 'Workflow') : t('سير العمل في Codemagic', 'Codemagic workflow'),
            hint: releaseDefaultWorkflow(_platform, _channel),
            helper: t('كما في codemagic.yaml', 'As in codemagic.yaml'),
            ltr: true,
            error: _errors['workflow'],
          ),
        ),
        if (play)
          _Pair(
            first: Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: AppDropdown<String>(
                key: const ValueKey('release.track'),
                value: _track,
                decoration: InputDecoration(labelText: t('مسار Google Play', 'Google Play track'), errorText: _errors['track']),
                items: [
                  for (final tr in kPlayTracks)
                    DropdownMenuItem(value: tr, child: Text(releaseTrackName(tr), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _track = v ?? _track),
              ),
            ),
            second: _Field(
              fieldKey: 'release.package_name',
              controller: _package,
              onChanged: _rebuild,
              label: t('اسم الحزمة', 'Package name'),
              hint: 'com.doubley.nextbrain',
              helper: t('يُسجَّل مع الإصدار؛ تغيير معرّف التطبيق قرار منفصل', 'Recorded with the version; changing the app id is a separate decision'),
              ltr: true,
              error: _errors['package_name'],
            ),
          ),
        if (store)
          _Field(
            fieldKey: 'release.store_url',
            controller: _url,
            label: _platform == 'android' ? t('رابط التطبيق على Google Play', 'Google Play link') : t('رابط التطبيق على App Store', 'App Store link'),
            hint: 'https://',
            helper: t('ما يفتحه زر «حدّث الآن» في التطبيق', "What the app's Update button opens"),
            ltr: true,
            keyboard: TextInputType.url,
            error: _errors['store_url'],
          ),
        const SizedBox(height: AppSpace.xxs),
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
    );
  }

  /// A recorded-only macOS version: the file or store link the app's Update button opens.
  Widget _linkSection(BuildContext context) => _Section(
        title: t('الرابط', 'Link'),
        subtitle: t('ما يفتحه زر «حدّث الآن» في التطبيق', "What the app's Update button opens"),
        child: _Field(
          fieldKey: 'release.store_url',
          controller: _url,
          label: _channel == 'store' ? t('رابط المتجر', 'Store link') : t('رابط الملف (اختياري)', 'File link (optional)'),
          hint: 'https://',
          ltr: true,
          keyboard: TextInputType.url,
          error: _errors['store_url'],
        ),
      );
}

/// The workflow id codemagic.yaml gives a platform + channel (the field's hint when the server sends no default).
String releaseDefaultWorkflow(String platform, String channel) => switch (platform) {
      'android' => channel == 'store' ? 'android-store' : 'android-website',
      'ios' => 'ios-store',
      'web' => 'web-website',
      'linux' => 'linux-website',
      'windows' => 'windows-website',
      _ => '',
    };

/// "Ready to build" or what is missing on the server (env names for the owner, sentences for the admin), the check
/// still running, or a check that failed with a Retry — drawn from plain values (test/ui/app_releases_layout_test.dart).
class ReleaseReadinessBox extends StatelessWidget {
  /// The server's own sentence for the item (it sends one per item, parallel to `missing`), else ours.
  static String _text(ReleaseReadiness r, String item) {
    final own = r.reasonFor(item, AppConfig.lang);
    return own.isNotEmpty ? own : releaseMissingText(item);
  }

  const ReleaseReadinessBox({
    super.key,
    required this.builds,
    required this.readiness,
    required this.what,
    this.builder = 'Codemagic',
    this.loading = false,
    this.error,
    this.onRetry,
  });

  /// Codemagic builds this channel (a recorded-only one needs no setup and shows nothing when ready).
  final bool builds;
  final ReleaseReadiness? readiness;

  /// "Android · Google Play"
  final String what;

  /// Who builds it: "Codemagic" or "My computer (free)" (D-146).
  final String builder;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = readiness;
    if (loading && r == null) {
      return AppBanner(icon: Icons.hourglass_top_rounded, color: c.textMedium, text: t('يجري التحقق من إعداد البناء…', 'Checking the build setup…'));
    }
    if (r == null) {
      // the Retry button under the sentence (beside it, a large text size squeezes the sentence to nothing)
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppBanner(
          icon: Icons.cloud_off_rounded,
          color: c.warning,
          text: t('تعذّر التحقق من إعداد البناء، فلا يمكن البدء الآن', 'Could not check the build setup, so a build cannot start now') +
              (error == null || error!.isEmpty ? '' : ' — ${error!}'),
        ),
        if (onRetry != null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              key: const ValueKey('release.readiness.retry'),
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: c.primary, minimumSize: const Size(48, AppTouch.min)),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(t('أعد المحاولة', 'Retry'), style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700)),
            ),
          ),
      ]);
    }
    if (r.ready) {
      if (!builds) return const SizedBox.shrink();
      return AppBanner(
        icon: Icons.check_circle_outline_rounded,
        color: c.success,
        text: t('جاهز: يبني $builder ‏$what', 'Ready: $builder builds $what'),
      );
    }
    final col = c.danger;
    final meta = AppType.meta(context).copyWith(fontFamily: AppFonts.family, height: 1.4);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.sm, AppSpace.sm, AppSpace.xs),
        decoration: BoxDecoration(
          color: col.withValues(alpha: 0.07),
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: col.withValues(alpha: 0.28)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.block_rounded, size: 20, color: col),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('غير جاهز بعد: $what', 'Not ready yet: $what'),
                    style: AppType.row(context).copyWith(fontFamily: AppFonts.family, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(t('زر الإنشاء متوقف حتى يُضبط ما يلي في ‎.env.production على الخادم (أو في Codemagic):',
                        'The Create button stays off until these are set in .env.production on the server (or in Codemagic):'),
                    style: meta),
              ]),
            ),
          ]),
          const SizedBox(height: AppSpace.xs),
          for (final m in r.missing)
            Padding(
              key: ValueKey('release.readiness.missing.$m'),
              padding: const EdgeInsetsDirectional.only(start: AppSpace.lg, bottom: AppSpace.xs),
              child: Wrap(
                spacing: AppSpace.xs,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(_text(r, m), style: AppType.row(context).copyWith(fontFamily: AppFonts.family, fontSize: 13.5, height: 1.4)),
                  if (releaseMissingIsEnv(m))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
                      child: Text(m,
                          textDirection: TextDirection.ltr,
                          style: appText(12, w: FontWeight.w600, c: c.textDark).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                    ),
                ],
              ),
            ),
        ]),
      ),
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
    this.onChanged,
  });

  final String fieldKey;
  final TextEditingController controller;
  final String label;
  final String? hint, helper, error;
  final int maxLines;
  final bool ltr, rtl, digitsOnly;
  final TextInputType? keyboard;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: TextField(
        key: ValueKey(fieldKey),
        controller: controller,
        onChanged: onChanged,
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
                  badge: releaseChannelsFor(p).any((ch) => releaseChannelBuilds(p, ch)) ? null : t('تسجيل فقط', 'Record only'),
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
  const _SubmitBar({required this.label, required this.onSubmit, this.busy = false, this.error, this.enabled = true, this.disabledHint});

  final String label;
  final VoidCallback onSubmit;
  final bool busy;
  final String? error;

  /// false: the chosen platform + channel is not ready (the button is off and [disabledHint] says why).
  final bool enabled;
  final String? disabledHint;

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
                  if (!enabled && disabledHint != null) ...[
                    Text(disabledHint!,
                        key: const ValueKey('release.submit.hint'),
                        textAlign: TextAlign.center,
                        style: AppType.meta(context).copyWith(fontFamily: AppFonts.family, color: c.textMedium)),
                    const SizedBox(height: AppSpace.xs),
                  ],
                  AppPrimaryButton(
                    key: const ValueKey('release.submit'),
                    label: label,
                    icon: Icons.lock_outline_rounded,
                    busy: busy,
                    onPressed: busy || !enabled ? null : onSubmit,
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

