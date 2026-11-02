// lib/features/admin/models/ai_models_view.dart
//
// The AI Models page drawn from plain values (D-152, requirement 7.4): the library grouped by role as the hub lists
// them, each role a card — active / fallback / previous, its resource limits, an activation in progress, and its
// models as a table on wide windows (name, size, source, status, disk / RAM, last test, actions) or as cards on
// phones (no wide table on a phone). [AiModelsHistory] is the change log. No provider, no request: the page
// (ai_models_page.dart) passes the data and the callbacks; test/ui/models_hub_layout_test.dart pumps these.
library;

import 'package:flutter/material.dart';

import '../../../config/theme/theme_config_provider.dart';
import '../../../core/models_hub/models_hub_api.dart';
import '../../../design/app_bidi.dart';
import '../../../design/app_kit.dart';
import '../../../design/app_tokens.dart';
import '../admin_common.dart' show t;
import 'models_hub_text.dart';

/// Wide enough for the table (below: cards).
const kModelsTableWidth = 900.0;

/// What a row / role can ask the page to do. Every callback may be null (the action is then not offered).
class AiModelsActions {
  const AiModelsActions({
    this.onDownload,
    this.onActivate,
    this.onFallback,
    this.onTest,
    this.onDelete,
    this.onPause,
    this.onResume,
    this.onCancelDownload,
    this.onRollback,
    this.onLimits,
    this.onReview,
    this.onCancelPending,
    this.onReindexNow,
    this.onAdd,
  });

  final void Function(HubModel m)? onDownload, onActivate, onTest, onDelete;

  /// Sets [m] as its role's fallback, or clears it when [m] is the fallback already.
  final void Function(HubRole r, HubModel m)? onFallback;
  final void Function(HubDownload d)? onPause, onResume, onCancelDownload;
  final void Function(HubRole r)? onRollback, onLimits, onReview, onCancelPending, onReindexNow;
  final VoidCallback? onAdd;
}

Color hubStatusColor(BuildContext context, String status) {
  final c = context.colors;
  return switch (status) {
    'active' => c.success,
    'ready' => c.primary,
    'downloading' => c.primary,
    'paused' => c.warning,
    'failed' => c.danger,
    _ => c.textLight,
  };
}

IconData hubStatusIcon(String status) => switch (status) {
      'active' => Icons.check_circle_rounded,
      'ready' => Icons.inventory_2_outlined,
      'downloading' => Icons.downloading_rounded,
      'paused' => Icons.pause_circle_outline_rounded,
      'failed' => Icons.error_outline_rounded,
      _ => Icons.cloud_download_outlined,
    };

/// The page body: summary, alerts, one card per role.
class AiModelsView extends StatelessWidget {
  const AiModelsView({
    super.key,
    required this.overview,
    this.downloads = const {},
    this.alerts = const [],
    this.system,
    this.busy = const {},
    this.actions = const AiModelsActions(),
  });

  final HubOverview overview;

  /// model id → its live download (queued / running / paused).
  final Map<int, HubDownload> downloads;
  final List<HubAlert> alerts;
  final HubSystem? system;

  /// Models with a request in flight (their buttons wait).
  final Set<int> busy;
  final AiModelsActions actions;

  @override
  Widget build(BuildContext context) {
    final roles = overview.roles;
    final active = roles.where((r) => r.activeId != null).length;
    final s = system;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= kModelsTableWidth;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          _Fact(icon: Icons.hub_outlined, value: '$active/${roles.length}', label: t('أدوار مُفعّلة', 'roles active')),
          if (downloads.isNotEmpty)
            _Fact(icon: Icons.downloading_rounded, value: '${downloads.length}', label: t('تنزيل', 'downloading')),
          if (s?.diskFreeMb != null)
            _Fact(icon: Icons.storage_rounded, value: hubMb(s!.diskFreeMb!), label: t('مساحة متاحة', 'disk free')),
          if (s?.ramAvailableMb != null)
            _Fact(icon: Icons.memory_rounded, value: hubMb(s!.ramAvailableMb!), label: t('ذاكرة متاحة', 'RAM available')),
          if (s?.cpuCount != null)
            _Fact(icon: Icons.developer_board_rounded, value: '${s!.cpuCount}', label: t('أنوية', 'cores')),
        ]),
        for (final a in alerts) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(icon: Icons.warning_amber_rounded, color: context.colors.warning, text: _alertText(a)),
        ],
        for (final r in roles) ...[
          const SizedBox(height: AppSpace.md),
          HubRoleCard(role: r, wide: wide, downloads: downloads, busy: busy, actions: actions),
        ],
      ]);
    });
  }

  String _alertText(HubAlert a) {
    final role = a.role == null ? '' : '${hubRoleName(a.role!)}: ';
    final d = a.detail;
    // the refs and the server's error keep their own (English) order inside the Arabic sentence
    String ref(Object? v) => bidiIsolate('${v ?? ''}');
    final err = d['error'] == null ? '' : ' (${bidiIsolate('${d['error']}')})';
    return switch (a.kind) {
      'model_fallback' => role +
          t('يعمل النموذج الاحتياطي ${ref(d['fallback'])} لأن ${ref(d['active'])} تعذّر$err',
              'the fallback ${ref(d['fallback'])} is serving because ${ref(d['active'])} failed$err'),
      'health_failed' => role + t('فشل اختبار السلامة لـ ${ref(d['ref'])}$err', 'the health test of ${ref(d['ref'])} failed$err'),
      'download_failed' => t('فشل تنزيل ${ref(d['ref'])}$err', 'The download of ${ref(d['ref'])} failed$err'),
      _ => '$role${a.key}',
    };
  }
}

/// One role: header, limits, the activation in progress, the models.
class HubRoleCard extends StatelessWidget {
  const HubRoleCard({
    super.key,
    required this.role,
    required this.wide,
    this.downloads = const {},
    this.busy = const {},
    this.actions = const AiModelsActions(),
  });

  final HubRole role;
  final bool wide;
  final Map<int, HubDownload> downloads;
  final Set<int> busy;
  final AiModelsActions actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = role;
    final l = r.limits;
    final hint = hubRoleHint(r.role);
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(hubRoleName(r.role), style: AppType.section(context)),
              if (hint.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(hint, style: AppType.meta(context)),
              ],
            ]),
          ),
          if (actions.onRollback != null && r.previousId != null)
            _HeaderButton(
              key: ValueKey('rollback_${r.role}'),
              icon: Icons.history_rounded,
              label: t('رجوع', 'Roll back'),
              compact: !wide,
              onTap: () => actions.onRollback!(r),
            ),
          if (actions.onLimits != null)
            _HeaderButton(
              key: ValueKey('limits_${r.role}'),
              icon: Icons.tune_rounded,
              label: t('الموارد', 'Limits'),
              compact: !wide,
              onTap: () => actions.onLimits!(r),
            ),
        ]),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          if (r.active != null)
            AppBadgePill('${t('المُفعّل', 'Active')}: ${r.activeModel?.name ?? r.active}', color: c.success, icon: Icons.check_circle_rounded)
          else
            AppBadgePill(t('لا نموذج مُفعّل', 'No active model'), color: c.textLight, icon: Icons.radio_button_unchecked_rounded),
          if (r.fallback != null)
            AppBadgePill('${t('الاحتياطي', 'Fallback')}: ${r.byId(r.fallbackId)?.name ?? r.fallback}', color: c.primary, icon: Icons.shield_outlined),
          if (r.previous != null)
            AppBadgePill('${t('السابق', 'Previous')}: ${r.previousModel?.name ?? r.previous}', color: c.textMedium, icon: Icons.history_rounded),
          AppBadgePill(
            '${l.threads == 1 ? t('خيط واحد', '1 thread') : t('${l.threads} خيوط', '${l.threads} threads')} · ${t('${l.maxConcurrency} في آنٍ واحد', '${l.maxConcurrency} at a time')} · ${hubPriorityLabel(l.priority)}',
            color: c.textMedium,
            icon: Icons.speed_rounded,
          ),
        ]),
        if (r.pending != null) ...[
          const SizedBox(height: AppSpace.sm),
          _PendingStrip(role: r, actions: actions),
        ],
        const SizedBox(height: AppSpace.sm),
        if (r.models.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
            child: Text(t('لا نماذج لهذا الدور بعد — أضف نموذجاً من الزر أعلى الصفحة.', 'No models for this role yet — add one with the button at the top.'),
                style: AppType.meta(context)),
          )
        else if (wide)
          _ModelsTable(role: r, downloads: downloads, busy: busy, actions: actions)
        else
          for (final m in r.models) ...[
            Divider(height: AppSpace.md, color: c.divider),
            _ModelCard(role: r, model: m, download: downloads[m.id], busy: busy.contains(m.id), actions: actions),
          ],
      ]),
    );
  }
}

/// One fact of the summary row: icon · value · label (the label gives way on a narrow phone).
class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value, label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xs, AppSpace.xxs + 2, AppSpace.sm, AppSpace.xxs + 2),
      decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(30), border: Border.all(color: c.divider)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: c.primary),
        const SizedBox(width: AppSpace.xs - 2),
        Flexible(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: value, style: appText(13, w: FontWeight.w800, c: c.textDark)),
              TextSpan(text: '  $label', style: appText(12, w: FontWeight.w600, c: c.textMedium)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({super.key, required this.icon, required this.label, required this.onTap, this.compact = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// A phone: the icon alone (the label is its tooltip and its semantics).
  final bool compact;

  @override
  Widget build(BuildContext context) => compact
      ? IconButton(tooltip: label, onPressed: onTap, icon: Icon(icon, size: 22, color: context.colors.primary))
      : TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min), padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs)),
        icon: Icon(icon, size: 18),
        label: Text(label, style: appText(13, w: FontWeight.w700, c: context.colors.primary)),
      );
}

/// The activation in progress of a role.
class _PendingStrip extends StatelessWidget {
  const _PendingStrip({required this.role, required this.actions});

  final HubRole role;
  final AiModelsActions actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = role.pending!;
    final name = role.byId(p.modelId)?.name ?? p.ref;
    final color = p.failed ? c.danger : (p.readyToConfirm ? c.success : c.primary);
    final lines = <String>[
      '$name — ${hubStageLabel(p.stage)}',
      if (p.stage == 'downloading' || p.stage == 'testing')
        t('${role.activeModel?.name ?? role.active ?? 'النموذج الحالي'} يبقى مُفعّلاً حتى تؤكد.',
            '${role.activeModel?.name ?? role.active ?? 'The current model'} stays active until you confirm.'),
      if (p.failed) failureText(p, role),
      if (p.stage == 'reindexing' && p.reindex?.total != null && p.reindex!.total! > 0)
        t('${p.reindex!.done ?? 0} من ${p.reindex!.total}', '${p.reindex!.done ?? 0} of ${p.reindex!.total}'),
    ];
    Widget button(String label, VoidCallback onTap, {bool primary = false, Key? key}) => Padding(
          padding: const EdgeInsetsDirectional.only(end: AppSpace.xs, top: AppSpace.xs),
          child: primary
              ? FilledButton(key: key, onPressed: onTap, style: FilledButton.styleFrom(minimumSize: const Size(AppTouch.min, 40)), child: Text(label))
              : OutlinedButton(key: key, onPressed: onTap, style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, 40)), child: Text(label)),
        );
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(p.failed ? Icons.error_outline_rounded : (p.readyToConfirm ? Icons.verified_outlined : Icons.autorenew_rounded), color: color, size: 20),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final (i, s) in lines.indexed)
                Text(s, style: i == 0 ? appText(13, w: FontWeight.w700, c: c.textDark) : appText(12, c: c.textMedium, h: 1.4)),
            ]),
          ),
        ]),
        if (p.stage == 'reindexing' && p.reindex?.total != null && p.reindex!.total! > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: AppProgressBar(value: (p.reindex!.done ?? 0).toDouble(), max: p.reindex!.total!.toDouble()),
          ),
        Wrap(children: [
          if (p.readyToConfirm && actions.onReview != null)
            button(t('مراجعة وتفعيل', 'Review and activate'), () => actions.onReview!(role), primary: true, key: ValueKey('review_${role.role}')),
          if (p.stage == 'reindex_later' || p.stage == 'reindex_failed')
            if (actions.onReindexNow != null)
              button(
                  (p.reindex?.vectorsReady ?? false) ? t('التبديل الآن', 'Switch now') : t('إعادة البناء الآن', 'Rebuild now'),
                  () => actions.onReindexNow!(role),
                  primary: true),
          if (p.stage != 'reindexing' && actions.onCancelPending != null)
            button(p.failed ? t('تجاهل', 'Dismiss') : t('إلغاء التفعيل', 'Cancel activation'), () => actions.onCancelPending!(role)),
        ]),
      ]),
    );
  }
}

/// Why an activation stopped, in words (the test's error, the failing checks, or the stage).
String failureText(HubPending p, HubRole role) {
  final keep = t('${role.activeModel?.name ?? role.active ?? 'النموذج الحالي'} يبقى مُفعّلاً.',
      '${role.activeModel?.name ?? role.active ?? 'The current model'} stays active.');
  final failing = bidiIsolate(p.checks.where((c) => !c.ok).map(hubCheckLine).join('; '));
  // the server's English error keeps its own order inside the Arabic sentence (not "s is below the floor of 5.0/s/3.7")
  final testErr = p.test?.error == null ? null : bidiIsolate(p.test!.error!);
  final indexErr = p.reindex?.error == null ? null : bidiIsolate(p.reindex!.error!);
  final why = switch (p.reason) {
    'checks_failed' => t('لا يناسب هذا الخادم: $failing', 'It does not fit this server: $failing'),
    'health_test_crashed' => t('تعطّل اختبار السلامة.', 'The health test crashed.'),
    _ when p.stage == 'reindex_failed' => t('تعذّرت إعادة بناء الفهرس${indexErr == null ? '' : ': $indexErr'}',
        'The index could not be rebuilt${indexErr == null ? '' : ': $indexErr'}'),
    _ => t('فشل اختبار السلامة${testErr == null ? '' : ': $testErr'}', 'The health test failed${testErr == null ? '' : ': $testErr'}'),
  };
  return '$why $keep';
}

/// The primary action of a row, and the rest for its menu.
class _RowActions {
  _RowActions(this.role, this.m, this.d, this.a, this.busy);

  final HubRole role;
  final HubModel m;
  final HubDownload? d;
  final AiModelsActions a;
  final bool busy;

  bool get _pending => role.pending?.modelId == m.id;

  /// (label, icon, callback, key)
  (String, IconData, VoidCallback, String)? get primary {
    final d = this.d;
    if (d != null) {
      if (d.paused && a.onResume != null) return (t('استئناف', 'Resume'), Icons.play_arrow_rounded, () => a.onResume!(d), 'resume_${m.id}');
      if (!d.paused && a.onPause != null) return (t('إيقاف مؤقت', 'Pause'), Icons.pause_rounded, () => a.onPause!(d), 'pause_${m.id}');
      return null;
    }
    if (m.isActive || _pending) return null;
    if ((m.status == 'not_downloaded' || m.status == 'failed') && a.onDownload != null) {
      return (t('تنزيل', 'Download'), Icons.download_rounded, () => a.onDownload!(m), 'download_${m.id}');
    }
    if (m.status == 'ready' && a.onActivate != null) return (t('تفعيل', 'Activate'), Icons.bolt_rounded, () => a.onActivate!(m), 'activate_${m.id}');
    return null;
  }

  /// The menu: (value, label, icon, danger).
  List<(String, String, IconData, bool)> get menu {
    final p = primary;
    final d = this.d;
    return [
      if (d != null && a.onCancelDownload != null) ('cancel', t('إلغاء التنزيل', 'Cancel download'), Icons.close_rounded, true),
      if (!m.isActive && !_pending && m.status != 'ready' && d == null && a.onActivate != null && (p == null || p.$4 != 'activate_${m.id}'))
        ('activate', t('تنزيل وتفعيل', 'Download and activate'), Icons.bolt_rounded, false),
      if (!m.isActive && m.onDisk && a.onFallback != null)
        ('fallback', m.isFallback ? t('إزالة كاحتياطي', 'Remove as fallback') : t('تعيين كاحتياطي', 'Set as fallback'), Icons.shield_outlined, false),
      if (m.onDisk && d == null && a.onTest != null) ('test', t('اختبار السلامة', 'Run health test'), Icons.health_and_safety_outlined, false),
      if ((m.deletable || m.isActive || m.usedAs.isNotEmpty || m.pinned) && m.onDisk && a.onDelete != null)
        ('delete', t('حذف', 'Delete'), Icons.delete_outline_rounded, true),
    ];
  }

  void run(String v) {
    switch (v) {
      case 'cancel':
        if (d != null) a.onCancelDownload?.call(d!);
      case 'activate':
        a.onActivate?.call(m);
      case 'fallback':
        a.onFallback?.call(role, m);
      case 'test':
        a.onTest?.call(m);
      case 'delete':
        a.onDelete?.call(m);
    }
  }
}

class _ActionsCell extends StatelessWidget {
  const _ActionsCell({required this.x});

  final _RowActions x;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = x.primary;
    final menu = x.menu;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (x.busy)
        const SizedBox(width: AppTouch.min, height: AppTouch.min, child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))))
      else if (p != null)
        Flexible(
          child: OutlinedButton.icon(
            key: ValueKey(p.$4),
            onPressed: p.$3,
            style: OutlinedButton.styleFrom(minimumSize: const Size(AppTouch.min, 40), padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm)),
            icon: Icon(p.$2, size: 18),
            label: Text(p.$1, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      if (menu.isNotEmpty)
        PopupMenuButton<String>(
          key: ValueKey('menu_${x.m.id}'),
          tooltip: t('المزيد', 'More'),
          icon: Icon(Icons.more_vert_rounded, color: c.textMedium),
          onSelected: x.run,
          itemBuilder: (_) => [
            for (final (v, label, icon, danger) in menu)
              PopupMenuItem(
                value: v,
                child: Row(children: [
                  Icon(icon, size: 20, color: danger ? c.danger : c.textMedium),
                  const SizedBox(width: AppSpace.sm),
                  Flexible(child: Text(label, style: appText(14, c: danger ? c.danger : c.textDark))),
                ]),
              ),
          ],
        ),
    ]);
  }
}

/// The status chip, with the download's progress under it.
class _StatusCell extends StatelessWidget {
  const _StatusCell({required this.model, this.download});

  final HubModel model;
  final HubDownload? download;

  @override
  Widget build(BuildContext context) {
    final d = download;
    final status = d == null ? model.status : (d.paused ? 'paused' : 'downloading');
    final col = hubStatusColor(context, status);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
        AppBadgePill(hubStatusLabel(status), color: col, icon: hubStatusIcon(status)),
        if (model.isFallback) AppBadgePill(t('احتياطي', 'Fallback'), color: context.colors.primary),
        if (model.pinned) AppBadgePill(t('مثبّت', 'Pinned'), color: context.colors.textMedium, icon: Icons.push_pin_outlined),
      ]),
      if (d != null) ...[
        const SizedBox(height: AppSpace.xxs),
        SizedBox(width: 140, child: AppProgressBar(value: (d.fraction ?? 0) * 100, height: 5, color: col)),
        const SizedBox(height: 2),
        Text(hubDownloadLine(d), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
      ] else if (model.status == 'failed' && model.error != null) ...[
        const SizedBox(height: 2),
        AutoDirText(model.error!, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(11, c: context.colors.danger)),
      ],
    ]);
  }
}

String _diskRam(HubModel m) => '${m.diskBytes > 0 ? hubBytes(m.diskBytes) : '—'} / ${hubMb(m.ramMb)}';

String _lastTest(HubModel m) {
  final x = m.lastTest;
  if (x == null) return t('لم يُختبر', 'Not tested');
  final when = x.at == null ? '' : ' · ${relTime(x.at!.toIso8601String())}';
  return '${hubTestLine(x)}$when';
}

class _ModelsTable extends StatelessWidget {
  const _ModelsTable({required this.role, required this.downloads, required this.busy, required this.actions});

  final HubRole role;
  final Map<int, HubDownload> downloads;
  final Set<int> busy;
  final AiModelsActions actions;

  static const _flex = [5, 2, 2, 3, 2, 3];
  static const _actionsWidth = 200.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget cell(int i, Widget child) => Expanded(flex: _flex[i], child: Padding(padding: const EdgeInsetsDirectional.only(end: AppSpace.sm), child: child));
    Widget head(String s) => Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11, w: FontWeight.w700, c: c.textLight));
    final meta = AppType.meta(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        child: Row(children: [
          cell(0, head(t('النموذج', 'Model'))),
          cell(1, head(t('الحجم', 'Size'))),
          cell(2, head(t('المصدر', 'Source'))),
          cell(3, head(t('الحالة', 'Status'))),
          cell(4, head(t('القرص / الذاكرة', 'Disk / RAM'))),
          cell(5, head(t('آخر اختبار', 'Last test'))),
          SizedBox(width: _actionsWidth, child: Align(alignment: AlignmentDirectional.centerEnd, child: head(t('إجراءات', 'Actions')))),
        ]),
      ),
      for (final m in role.models)
        DecoratedBox(
          key: ValueKey('model_row_${m.id}'),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.divider))),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
            child: Row(children: [
              cell(0, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: c.textDark)),
                Text([m.version, if (m.quantization != null) m.quantization!].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: meta),
              ])),
              cell(1, Text(hubBytes(m.sizeBytes), style: AppType.row(context))),
              cell(2, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(hubSourceLabel(m.source), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                Text(m.provider, maxLines: 1, overflow: TextOverflow.ellipsis, style: meta),
              ])),
              cell(3, _StatusCell(model: m, download: downloads[m.id])),
              cell(4, Text(_diskRam(m), style: AppType.row(context))),
              cell(5, Text(_lastTest(m), maxLines: 2, overflow: TextOverflow.ellipsis, style: meta)),
              SizedBox(
                width: _actionsWidth,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: _ActionsCell(x: _RowActions(role, m, downloads[m.id], actions, busy.contains(m.id))),
                ),
              ),
            ]),
          ),
        ),
    ]);
  }
}

Widget _kv(BuildContext context, String label, String value) => Text.rich(
      TextSpan(children: [
        TextSpan(text: '$label  ', style: AppType.meta(context)),
        TextSpan(text: value, style: appText(12, w: FontWeight.w700, c: context.colors.textDark)),
      ]),
    );

/// A phone's row: the same facts, stacked.
class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.role, required this.model, this.download, this.busy = false, required this.actions});

  final HubRole role;
  final HubModel model;
  final HubDownload? download;
  final bool busy;
  final AiModelsActions actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = model;
    final meta = AppType.meta(context);
    return Column(key: ValueKey('model_row_${m.id}'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(m.name, style: appText(14, w: FontWeight.w700, c: c.textDark)),
      Text([m.version, if (m.quantization != null) m.quantization!].join(' · '), style: meta),
      const SizedBox(height: AppSpace.xs),
      _StatusCell(model: m, download: download),
      const SizedBox(height: AppSpace.xs),
      // one fact per piece: each is its own paragraph, so Arabic labels and Latin numbers never interleave
      Wrap(spacing: AppSpace.md, runSpacing: 2, children: [
        _kv(context, t('الحجم', 'Size'), hubBytes(m.sizeBytes)),
        _kv(context, t('القرص / الذاكرة', 'Disk / RAM'), _diskRam(m)),
        _kv(context, hubSourceLabel(m.source), m.provider),
      ]),
      LayoutBuilder(
        builder: (context, box) => Row(children: [
          Expanded(child: Text('${t('آخر اختبار', 'Last test')}: ${_lastTest(m)}', style: meta)),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: box.maxWidth * 0.6),
            child: _ActionsCell(x: _RowActions(role, m, download, actions, busy)),
          ),
        ]),
      ),
    ]);
  }
}

/// The change log: who changed what, when.
class AiModelsHistory extends StatelessWidget {
  const AiModelsHistory({super.key, required this.audit, this.overview, this.me});

  final List<HubAudit> audit;
  final HubOverview? overview;
  final int? me;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (audit.isEmpty) {
      return AppEmpty(icon: Icons.history_rounded, title: t('لا تغييرات بعد', 'No changes yet'));
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
      child: Column(children: [
        for (final (i, a) in audit.indexed) ...[
          if (i > 0) Divider(height: 1, color: c.divider),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Icon(Icons.circle, size: 8, color: a.actor == null ? c.textLight : c.primary),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    [hubAuditAction(a.action), if (a.role != null) hubRoleName(a.role!)].join(' · '),
                    style: appText(13, w: FontWeight.w700, c: c.textDark),
                  ),
                  if (_what(a).isNotEmpty) Text(_what(a), style: appText(12, c: c.textMedium, h: 1.4)),
                  Text(
                    '${hubActor(a.actor, me)} · ${a.at == null ? '' : AppTime.dateTime(a.at!)}',
                    style: AppType.meta(context),
                  ),
                ]),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  /// The model and the change, in a few words.
  String _what(HubAudit a) {
    final ov = overview;
    String ref(Object? id) => ov?.model(id is int ? id : int.tryParse('${id ?? ''}'))?.ref ?? (id == null ? '—' : '#$id');
    final n = a.next ?? const {};
    final o = a.old ?? const {};
    // the change of a fallback names both models itself; a deleted row is gone from the library: its ref is in `old`
    final model = a.modelId == null || a.action == 'set_fallback'
        ? null
        : (ov?.model(a.modelId) == null && o['ref'] != null ? '${o['ref']}' : ref(a.modelId));
    final change = switch (a.action) {
      'activate' || 'seed_active' => n['ref'] ?? n['active'],
      'rollback' => n['ref'] ?? n['active'],
      'set_fallback' => '${o['fallback_id'] == null ? '—' : ref(o['fallback_id'])} → ${n['fallback_id'] == null ? '—' : ref(n['fallback_id'])}',
      'set_limits' => [for (final e in n.entries) if (!e.key.startsWith('_') && o[e.key] != e.value) '${e.key}: ${o[e.key] ?? '—'} → ${e.value}'].join(', '),
      'health_test' => n['ok'] == true ? t('نجح', 'passed') : '${t('فشل', 'failed')}${n['error'] == null ? '' : ': ${bidiIsolate('${n['error']}')}'}',
      'delete' => n['freed_bytes'] is num ? t('حُرّر ${hubBytes((n['freed_bytes'] as num).toInt())}', 'freed ${hubBytes((n['freed_bytes'] as num).toInt())}') : null,
      'fallback' => '${o['active'] ?? ''} → ${n['served_by'] ?? ''}',
      _ => null,
    };
    return [?model, if (change != null && '$change'.isNotEmpty && '$change' != model) '$change', if (a.detail != null) a.detail!].join(' · ');
  }
}
