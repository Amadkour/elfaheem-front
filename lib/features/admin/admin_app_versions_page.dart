// lib/features/admin/admin_app_versions_page.dart — App versions: ONE screen for what every platform's users are asked
// to update to and the builds behind it (D-309; it merges the former "Build & publish" and "Update prompt" tabs).
//
//   header      App versions · the ONE primary action "Build a version" (super admin, switch `admin.app_releases` on:
//               the Codemagic / runner page, deferred, D-171) · refresh
//   platforms   one card per platform (Android, iOS, Windows, macOS, Linux, Web): latest · minimum · "Who sees
//               what" (blocked / asked, can choose Later / nothing) · the live build behind it · what needs care
//               (no link, a legacy flag that also asked the newest version, a newer live build → "Use v…")
//   editor      one platform, pushed (UpdatePolicyEditorPage): Ask users to update · latest (+ "Use the live build")
//               · minimum (+ "Require the latest" / "No minimum") · the message ar / en (+ "Release notes") · the
//               store / download link · checks inline · the LIVE preview: who sees what, "Try a version", and the
//               very dialog users get (blocking or dismissible) with the message in the app's language
//   history     every update prompt row (the former list, AdminVersionsPage: toggle, edit, delete) one tap away
//
// The rules and the model: admin_update_policy.dart. Server: GET /app/policy, PUT /app/policy/{platform}; old apps keep
// reading GET /app/version-check, unchanged apart from additive fields.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../core/routing/deferred_screens.dart';
import '../../core/version_check_service.dart' show UpdateDialog;
import '../../core/plural.dart';
import '../../design/app_kit.dart';
import 'admin_common.dart';
import 'admin_page.dart';
import 'admin_update_policy.dart';
import 'admin_versions_page.dart';
import 'app_releases/app_releases_page.dart' show AppReleasesPage, kAppReleasesFeatureKey;
import 'sup/sup_kit.dart';

class AdminAppVersionsPage extends StatefulWidget {
  const AdminAppVersionsPage({super.key, this.provider});

  /// Tests hand a loaded provider in.
  final AdminUpdatePolicyProvider? provider;

  @override
  State<AdminAppVersionsPage> createState() => _AdminAppVersionsPageState();
}

class _AdminAppVersionsPageState extends State<AdminAppVersionsPage> {
  late final AdminUpdatePolicyProvider _p = widget.provider ?? AdminUpdatePolicyProvider();

  @override
  void initState() {
    super.initState();
    if (widget.provider == null) _p.load();
  }

  @override
  void dispose() {
    if (widget.provider == null) _p.dispose();
    super.dispose();
  }

  void _openBuild() => Navigator.of(context)
      .push(MaterialPageRoute(settings: const RouteSettings(name: AppReleasesPage.routeName), builder: (_) => deferredAppReleases()))
      .then((_) => _p.load());

  void _openHistory() =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminVersionsPage())).then((_) => _p.load());

  Future<void> _edit(UpdatePolicy policy, {UpdatePolicyDraft? start}) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => UpdatePolicyEditorPage(policy: policy, start: start, onSave: (d) => _p.save(policy.platform, d)),
      ));

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppConfig.disableListVersion,
      builder: (context, _, _) {
        final buildAvailable = isSuperNow(context) && !AppConfig.disableList.contains(kAppReleasesFeatureKey);
        return ChangeNotifierProvider<AdminUpdatePolicyProvider>.value(
          value: _p,
          child: Builder(builder: (context) {
            final p = context.watch<AdminUpdatePolicyProvider>();
            return SupPage(
        kicker: 'a2_rel_kicker'.tr, headline: 'a2_versions_head'.tr, line: 'a2_versions_line'.tr,
        key: const ValueKey('admin_app_versions'),
        width: AppWidth.wide,
        title: t('إصدارات التطبيق', 'App versions'),
        onRefresh: p.load,
        body: UpdatePolicyOverview(
                items: p.items,
                loading: p.isLoading && p.items.isEmpty,
                error: p.items.isEmpty ? p.error : null,
                onRetry: p.load,
                onRefresh: p.load,
                onEdit: (x) => _edit(x),
                onUseSuggestion: (x) => _edit(x, start: x.startDraft()),
                onOpenHistory: _openHistory,
              ),
        actions: [?(buildAvailable
                  ? AppButton.primary(
                      key: const ValueKey('admin_app_versions.build'),
                      icon: Icons.rocket_launch_rounded,
                      label: t('بناء إصدار', 'Build a version'),
                      onPressed: _openBuild,
                    )
                  : null)],
      );
          }),
        );
      },
    );
  }
}

/// "3 platforms" in the app's language.
String updatePlatformsText(int n) =>
    countText(n, ar1: 'منصة واحدة', ar2: 'منصتان', arFew: '{n} منصات', arMany: '{n} منصة', en1: '1 platform', en: '{n} platforms');

bool updatePolicyNeedsCare(UpdatePolicy p) =>
    p.legacyForce || p.legacyRecommend || p.suggestion != null || (p.enabled && !p.linkOk && updateNeedsLink(p.platform));

/// The overview's body from plain values (the layout harness pumps it).
class UpdatePolicyOverview extends StatelessWidget {
  const UpdatePolicyOverview({
    super.key,
    required this.items,
    required this.onEdit,
    this.onUseSuggestion,
    this.onOpenHistory,
    this.onRefresh,
    this.onRetry,
    this.loading = false,
    this.error,
  });

  final List<UpdatePolicy> items;
  final bool loading;
  final String? error;
  final ValueChanged<UpdatePolicy> onEdit;
  final ValueChanged<UpdatePolicy>? onUseSuggestion;
  final VoidCallback? onOpenHistory;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) return const AppListSkeleton();
    if (error != null) return AppErrorState(message: error, onRetry: onRetry);
    final c = context.colors;
    final asking = items.where((p) => p.enabled).length;
    final care = items.where(updatePolicyNeedsCare).length;
    final history = items.fold<int>(0, (s, p) => s + p.historyCount);
    final list = ListView(
      padding: AdminPage.bodyPadding(context),
      children: [
        AppBanner(
          icon: care == 0 ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
          text: care == 0
              ? t('${updatePlatformsText(asking)} تطلب من المستخدمين التحديث، ولا شيء يحتاج انتباهك.',
                  '${updatePlatformsText(asking)} asking users to update. Nothing needs you.')
              : t('${updatePlatformsText(asking)} تطلب التحديث · ${updatePlatformsText(care)} تحتاج انتباهك.',
                  '${updatePlatformsText(asking)} asking users to update · ${updatePlatformsText(care)} to look at.'),
        ),
        AppSpace.gapMd,
        LayoutBuilder(builder: (context, box) {
          final cols = box.maxWidth >= 1000 ? 3 : (box.maxWidth >= 640 ? 2 : 1);
          final w = ((box.maxWidth - AppSpace.md * (cols - 1)) / cols).floorToDouble();
          return Wrap(
            spacing: AppSpace.md,
            runSpacing: AppSpace.md,
            children: [
              for (final p in items)
                SizedBox(
                  width: w,
                  child: UpdatePolicyCard(
                    policy: p,
                    onEdit: () => onEdit(p),
                    onUseSuggestion: onUseSuggestion == null ? null : () => onUseSuggestion!(p),
                  ),
                ),
            ],
          );
        }),
        if (onOpenHistory != null) ...[
          AppSpace.gapLg,
          AppCard(
            onTap: onOpenHistory,
            child: Row(children: [
              Icon(Icons.history_rounded, color: appInk(context, c.primary)),
              AppSpace.gapSm,
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('سجل رسائل التحديث', 'Update prompt history'), style: AppType.row(context)),
                  Text(
                    t('كل الإصدارات المسجّلة ($history): تفعيل وإيقاف، تعديل، حذف', 'Every recorded version ($history): turn on or off, edit, delete'),
                    style: AppType.meta(context),
                  ),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: c.textLight),
            ]),
          ),
        ],
      ],
    );
    return onRefresh == null ? list : AppRefresh(onRefresh: onRefresh!, child: list);
  }
}

/// One platform on the overview.
class UpdatePolicyCard extends StatelessWidget {
  const UpdatePolicyCard({super.key, required this.policy, required this.onEdit, this.onUseSuggestion});

  final UpdatePolicy policy;
  final VoidCallback onEdit;
  final VoidCallback? onUseSuggestion;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = policy;
    final rel = p.release;
    final sug = p.suggestion;
    final on = p.enabled && p.latest != null;
    return AppCard(
      key: ValueKey('update_policy.${p.platform}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(AppRadius.chip)),
            child: Icon(updatePlatformIcon(p.platform), color: appInk(context, c.primary)),
          ),
          AppSpace.gapSm,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(updatePlatformName(p.platform), style: AppType.section(context)),
              Text(
                on
                    ? [t('الأحدث ${p.latest}', 'Latest ${p.latest}'), if (p.minimum != null) t('الأدنى ${p.minimum}', 'Minimum ${p.minimum}')].join(' · ')
                    : t('لا يُطلب التحديث', 'Not asking to update'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.meta(context),
              ),
            ]),
          ),
          AppSpace.gapXs,
          AppStatusBadge(label: on ? t('مفعّل', 'On') : t('متوقف', 'Off'), tone: on ? AppTone.success : AppTone.neutral, dot: true),
        ]),
        if (on) ...[
          AppSpace.gapSm,
          UpdateBandsView(
            bands: updateBands(latest: p.latest, minimum: p.minimum, legacyForce: p.legacyForce, legacyRecommend: p.legacyRecommend),
            dense: true,
          ),
        ],
        if (rel != null) ...[
          AppSpace.gapSm,
          Text(t('الإصدار المنشور: ${rel.version} (بناء ${rel.build})', 'Live build: ${rel.version} (build ${rel.build})'),
              style: AppType.meta(context)),
        ],
        if (p.platform == 'web') ...[
          AppSpace.gapXs,
          Text(t('تطبيق الويب يعمل دائماً بأحدث نسخة، فلا تظهر فيه رسالة.', 'The web app always runs the newest build, so it shows no prompt.'),
              style: AppType.meta(context)),
        ],
        if (p.legacyForce || p.legacyRecommend) ...[
          AppSpace.gapSm,
          _Note(
            danger: false,
            text: t('إعداد قديم يطلب التحديث حتى من أحدث إصدار. احفظ السياسة لتصحيحه.',
                'An old setting also asks users on the newest version. Save the policy to fix it.'),
          ),
        ],
        if (p.enabled && !p.linkOk && updateNeedsLink(p.platform)) ...[
          AppSpace.gapSm,
          _Note(danger: true, text: t('لا رابط: زر التحديث لا يفتح شيئاً.', 'No link: the update button opens nothing.')),
        ],
        AppSpace.gapSm,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppButton.secondary(
            key: ValueKey('update_policy.${p.platform}.edit'),
            icon: Icons.tune_rounded,
            label: t('تعديل', 'Edit'),
            size: AppButtonSize.sm,
            onPressed: onEdit,
          ),
          if (sug != null && onUseSuggestion != null)
            AppButton.tonal(
              key: ValueKey('update_policy.${p.platform}.use'),
              icon: Icons.auto_awesome_rounded,
              label: t('اعتمد ${sug.latest}', 'Use ${sug.latest}'),
              size: AppButtonSize.sm,
              tooltip: t('إصدار أحدث منشور: يُملأ رقمه وملاحظاته', 'A newer live build: its version and notes are filled in'),
              onPressed: onUseSuggestion,
            ),
        ]),
      ]),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.danger, required this.text});

  final bool danger;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(danger ? Icons.error_outline_rounded : Icons.info_outline_rounded, size: 18, color: appInk(context, danger ? c.danger : c.warning)),
      const SizedBox(width: AppSpace.xs),
      Expanded(child: Text(text, style: AppType.meta(context).copyWith(color: c.textDark))),
    ]);
  }
}

/// "Who sees what": one line per band.
class UpdateBandsView extends StatelessWidget {
  const UpdateBandsView({super.key, required this.bands, this.dense = false});

  final List<UpdateBand> bands;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Color tone(UpdateAsk a) => switch (a) {
          UpdateAsk.blocking => c.danger,
          UpdateAsk.dismissible => c.warning,
          UpdateAsk.none => c.success,
        };
    IconData icon(UpdateAsk a) => switch (a) {
          UpdateAsk.blocking => Icons.lock_rounded,
          UpdateAsk.dismissible => Icons.notifications_active_rounded,
          UpdateAsk.none => Icons.check_circle_rounded,
        };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final b in bands)
        Padding(
          padding: EdgeInsets.symmetric(vertical: dense ? 2 : AppSpace.xxs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon(b.ask), size: dense ? 16 : 18, color: appInk(context, tone(b.ask))),
            ),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: b.range, style: AppType.meta(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
                  TextSpan(text: ' · ${updateAskLabel(b.ask)}', style: AppType.meta(context)),
                ]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Editor
// ═════════════════════════════════════════════════════════════════════════════

/// One platform's policy, pushed from the overview.
class UpdatePolicyEditorPage extends StatelessWidget {
  const UpdatePolicyEditorPage({super.key, required this.policy, required this.onSave, this.start});

  final UpdatePolicy policy;
  final UpdatePolicyDraft? start;
  final Future<Map<String, String>?> Function(UpdatePolicyDraft) onSave;

  @override
  Widget build(BuildContext context) => SupPage(
        kicker: 'a2_prompt_kicker'.tr, headline: 'a2_prompt_head'.tr, line: 'a2_prompt_line'.tr,
        key: ValueKey('update_policy_editor.${policy.platform}'),
        title: t('التحديث على ${updatePlatformName(policy.platform)}', 'Updates on ${updatePlatformName(policy.platform)}'),
        body: UpdatePolicyEditor(policy: policy, start: start, onSave: onSave, onSaved: () => Navigator.of(context).maybePop()),
      );
}

class UpdatePolicyEditor extends StatefulWidget {
  const UpdatePolicyEditor({super.key, required this.policy, required this.onSave, this.start, this.onSaved});

  final UpdatePolicy policy;
  final UpdatePolicyDraft? start;
  final Future<Map<String, String>?> Function(UpdatePolicyDraft) onSave;
  final VoidCallback? onSaved;

  @override
  State<UpdatePolicyEditor> createState() => _UpdatePolicyEditorState();
}

class _UpdatePolicyEditorState extends State<UpdatePolicyEditor> {
  late final UpdatePolicyDraft _start = widget.start ?? widget.policy.startDraft();
  late bool _enabled = _start.enabled;
  late final _latest = TextEditingController(text: _start.latest);
  late final _min = TextEditingController(text: _start.minimum);
  late final _msgAr = TextEditingController(text: _start.messageAr);
  late final _msgEn = TextEditingController(text: _start.messageEn);
  late final _url = TextEditingController(text: _start.storeUrl);
  final _try = TextEditingController();
  Map<String, String> _serverErr = const {};
  bool _busy = false;
  bool _touched = false;

  @override
  void dispose() {
    for (final x in [_latest, _min, _msgAr, _msgEn, _url, _try]) {
      x.dispose();
    }
    super.dispose();
  }

  UpdatePolicyDraft get _draft => UpdatePolicyDraft(
        enabled: _enabled,
        latest: _latest.text,
        minimum: _min.text,
        messageAr: _msgAr.text,
        messageEn: _msgEn.text,
        storeUrl: _url.text,
      );

  void _changed([String? _]) => setState(() {
        _touched = true;
        _serverErr = const {};
      });

  void _set(TextEditingController ctl, String v) {
    ctl.text = v;
    _changed();
  }

  Future<void> _save() async {
    final d = _draft;
    final errs = validateUpdatePolicy(widget.policy.platform, d, hasReleaseLink: widget.policy.hasReleaseLink);
    if (errs.isNotEmpty) {
      setState(() => _touched = true);
      showAppNotice(errs.values.first, error: true);
      return;
    }
    // raising the minimum blocks people: say who, once
    final oldMin = widget.policy.enabled ? (widget.policy.minimum ?? '') : '';
    final newMin = d.minimum.trim();
    if (d.enabled && newMin.isNotEmpty && (oldMin.isEmpty || compareUpdateVersions(newMin, oldMin) > 0)) {
      final ok = await confirm(
        context,
        message: t('سيُحجب من يستخدم إصداراً أقدم من $newMin حتى يحدّث التطبيق. متابعة؟',
            'Everyone on a version older than $newMin will be blocked until they update. Continue?'),
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    final r = await widget.onSave(d);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _serverErr = r ?? const {};
    });
    if (r == null) widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.policy;
    final d = _draft;
    final errs = {
      if (_touched) ...validateUpdatePolicy(p.platform, d, hasReleaseLink: p.hasReleaseLink),
      ..._serverErr,
    };
    final form = _form(context, p, errs);
    final preview = UpdatePromptPreview(policy: p, draft: d, tryController: _try, onTry: _changed);
    return ListView(padding: AdminPage.bodyPadding(context), children: [
      LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < 900) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [form, AppSpace.gapLg, preview]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 6, child: form),
          AppSpace.gapLg,
          Expanded(flex: 5, child: preview),
        ]);
      }),
    ]);
  }

  Widget _form(BuildContext context, UpdatePolicy p, Map<String, String> errs) {
    final c = context.colors;
    final sug = p.suggestion;
    final rel = p.release;
    final relNotes = (rel?.notesAr ?? '').isNotEmpty || (rel?.notesEn ?? '').isNotEmpty;
    Widget err(String key) => (errs[key] ?? '').isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: Text(errs[key]!, style: AppType.meta(context).copyWith(color: appInk(context, c.danger))),
          );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSwitchTile(
            title: t('اطلب من المستخدمين التحديث', 'Ask users to update'),
            subtitle: t('عند إيقافه لا تظهر رسالة التحديث على هذه المنصة', 'When off, this platform shows no update prompt'),
            value: _enabled,
            onChanged: (v) => setState(() {
              _enabled = v;
              _touched = true;
            }),
          ),
          if (p.kind == 'releases')
            Text(
              t('بدون إصدار هنا يتبع ${updatePlatformName(p.platform)} الإصدار المنشور من «بناء إصدار».',
                  'Without a version here, ${updatePlatformName(p.platform)} follows its live build from Build a version.'),
              style: AppType.meta(context),
            ),
        ]),
      ),
      AppSpace.gapMd,
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('الإصدارات', 'Versions'), style: AppType.section(context)),
          AppSpace.gapSm,
          AppField(controller: _latest, label: t('أحدث إصدار', 'Latest version'), hint: '2.1.0', ltr: true, onChanged: _changed),
          err('latest_version'),
          if (sug != null && sug.latest != _latest.text.trim())
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton.ghost(
                key: const ValueKey('update_policy.use_live'),
                icon: Icons.auto_awesome_rounded,
                label: t('استخدم الإصدار المنشور ${sug.latest}', 'Use the live build ${sug.latest}'),
                size: AppButtonSize.sm,
                onPressed: () {
                  _latest.text = sug.latest;
                  if (sug.minimum.isNotEmpty && _min.text.trim().isEmpty) _min.text = sug.minimum;
                  _changed();
                },
              ),
            ),
          AppSpace.gapSm,
          AppField(controller: _min, label: t('أقل إصدار مسموح (اختياري)', 'Minimum supported (optional)'), hint: '1.5.0', ltr: true, onChanged: _changed),
          err('min_supported'),
          AppSpace.gapXs,
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            AppButton.ghost(
              key: const ValueKey('update_policy.require'),
              icon: Icons.lock_rounded,
              label: t('اجعل الأحدث إجبارياً', 'Require the latest'),
              size: AppButtonSize.sm,
              onPressed: validUpdateVersion(_latest.text) ? () => _set(_min, _latest.text.trim()) : null,
            ),
            AppButton.ghost(
              icon: Icons.lock_open_rounded,
              label: t('بدون حد أدنى', 'No minimum'),
              size: AppButtonSize.sm,
              onPressed: _min.text.trim().isEmpty ? null : () => _set(_min, ''),
            ),
          ]),
        ]),
      ),
      AppSpace.gapMd,
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(t('رسالة التحديث', 'Update message'), style: AppType.section(context))),
            if (relNotes)
              Flexible(
                child: AppButton.ghost(
                  key: const ValueKey('update_policy.use_notes'),
                  icon: Icons.notes_rounded,
                  label: t('من ملاحظات الإصدار', 'From release notes'),
                  size: AppButtonSize.sm,
                  onPressed: () {
                    if ((rel?.notesAr ?? '').isNotEmpty) _msgAr.text = rel!.notesAr!;
                    if ((rel?.notesEn ?? '').isNotEmpty) _msgEn.text = rel!.notesEn!;
                    _changed();
                  },
                ),
              ),
          ]),
          Text(t('تظهر تحت «ما الجديد» في نافذة التحديث.', 'Shown under “What’s new” in the update dialog.'), style: AppType.meta(context)),
          AppSpace.gapSm,
          AppField(controller: _msgAr, label: t('بالعربية', 'Arabic'), maxLines: 3, onChanged: _changed),
          AppSpace.gapSm,
          AppField(controller: _msgEn, label: t('بالإنجليزية', 'English'), maxLines: 3, ltr: true, onChanged: _changed),
        ]),
      ),
      if (updateNeedsLink(p.platform)) ...[
        AppSpace.gapMd,
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('رابط التحديث', 'Update link'), style: AppType.section(context)),
            AppSpace.gapSm,
            AppField(
              controller: _url,
              label: switch (p.platform) {
                'android' => t('رابط Google Play', 'Google Play link'),
                'ios' => t('رابط App Store', 'App Store link'),
                _ => t('رابط التنزيل', 'Download link'),
              },
              hint: switch (p.platform) {
                'android' => 'https://play.google.com/store/apps/details?id=…',
                'ios' => 'https://apps.apple.com/app/id…',
                _ => 'https://…',
              },
              ltr: true,
              keyboard: TextInputType.url,
              onChanged: _changed,
            ),
            err('store_url'),
            if (p.hasReleaseLink) ...[
              AppSpace.gapXs,
              Text(t('الزر يفتح رابط الإصدار المنشور؛ هذا الرابط احتياطي.', 'The button opens the live build’s link; this one is the fallback.'),
                  style: AppType.meta(context)),
            ],
          ]),
        ),
      ],
      AppSpace.gapLg,
      AppButton.primary(
        key: const ValueKey('update_policy.save'),
        icon: Icons.check_rounded,
        label: t('حفظ', 'Save'),
        busy: _busy,
        expand: true,
        onPressed: _save,
      ),
    ]);
  }
}

/// The live preview: who sees what, "Try a version", and the very dialog users get. It previews what a save stores,
/// so a legacy flag (cleared by the save) is not drawn.
class UpdatePromptPreview extends StatefulWidget {
  const UpdatePromptPreview({super.key, required this.policy, required this.draft, this.tryController, this.onTry});

  final UpdatePolicy policy;
  final UpdatePolicyDraft draft;
  final TextEditingController? tryController;
  final ValueChanged<String>? onTry;

  @override
  State<UpdatePromptPreview> createState() => _UpdatePromptPreviewState();
}

class _UpdatePromptPreviewState extends State<UpdatePromptPreview> {
  bool _blocking = false; // the tab picked when both kinds exist

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = widget.draft;
    final valid = d.enabled && validUpdateVersion(d.latest);
    final bands = valid ? updateBands(latest: d.latest, minimum: d.minimum) : const <UpdateBand>[];
    final asks = bands.map((b) => b.ask).toSet();
    final canBlock = asks.contains(UpdateAsk.blocking), canAsk = asks.contains(UpdateAsk.dismissible);
    final blocking = canBlock && (!canAsk || _blocking);
    final tryV = widget.tryController?.text.trim() ?? '';
    final tried = tryV.isEmpty || !valid ? null : updatePolicyAnswer(tryV, latest: d.latest, minimum: d.minimum);
    final mine = (AppConfig.lang == 'ar' ? d.messageAr : d.messageEn).trim();
    final notes = mine.isNotEmpty ? mine : (AppConfig.lang == 'ar' ? d.messageEn : d.messageAr).trim();
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.visibility_rounded, size: 20, color: appInk(context, c.primary)),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(t('معاينة مباشرة', 'Live preview'), style: AppType.section(context))),
        ]),
        AppSpace.gapSm,
        if (!valid)
          Text(
            d.enabled
                ? t('أدخل أحدث إصدار لترى ما يراه المستخدمون.', 'Enter the latest version to see what users get.')
                : t('متوقف: لا يرى أحد على ${updatePlatformName(widget.policy.platform)} رسالة تحديث.',
                    'Off: nobody on ${updatePlatformName(widget.policy.platform)} sees an update prompt.'),
            style: AppType.body(context).copyWith(color: c.textMedium),
          )
        else ...[
          Text(t('من يرى ماذا', 'Who sees what'), style: AppType.row(context)),
          AppSpace.gapXs,
          UpdateBandsView(bands: bands),
          if (widget.tryController != null) ...[
            AppSpace.gapMd,
            AppField(controller: widget.tryController!, label: t('جرّب إصداراً', 'Try a version'), hint: '1.4.0', ltr: true, onChanged: widget.onTry),
            if (tried != null) ...[
              AppSpace.gapXs,
              Text(
                validUpdateVersion(tryV) ? '$tryV · ${updateAskLabel(tried)}' : t('رقم غير صالح', 'Not a valid version'),
                key: const ValueKey('update_policy.try_result'),
                style: AppType.meta(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600),
              ),
            ],
          ],
          AppSpace.gapMd,
          if (canBlock && canAsk) ...[
            AppTabs(
              items: [
                AppTabItem(t('قابلة للتأجيل', 'Dismissible'), icon: Icons.notifications_active_rounded),
                AppTabItem(t('إجبارية', 'Blocking'), icon: Icons.lock_rounded),
              ],
              index: blocking ? 1 : 0,
              onChanged: (i) => setState(() => _blocking = i == 1),
            ),
            AppSpace.gapSm,
          ],
          if (canBlock || canAsk)
            // the very dialog users get, drawn in place (no taps)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: ColoredBox(
                color: c.background,
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            dialogTheme: Theme.of(context).dialogTheme.copyWith(insetPadding: const EdgeInsets.all(AppSpace.sm)),
                          ),
                          child: UpdateDialog(
                            key: const ValueKey('update_policy.preview_dialog'),
                            force: blocking,
                            version: d.latest.trim(),
                            notes: notes,
                            source: widget.policy.buttonSource(d),
                            onUpdate: () {},
                            onLater: () {},
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            Text(t('لا أحد يرى رسالة بهذه الإعدادات.', 'Nobody sees a prompt with these settings.'),
                style: AppType.body(context).copyWith(color: c.textMedium)),
        ],
      ]),
    );
  }
}
