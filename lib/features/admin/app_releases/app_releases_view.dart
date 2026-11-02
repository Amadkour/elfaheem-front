// lib/features/admin/app_releases/app_releases_view.dart
//
// App versions drawn from plain values (D-143): the build server strip, the filters, and the releases grouped by
// platform with their status chips (the live one marked). No provider, no request: app_releases_page.dart passes the
// data and the callbacks; test/ui/app_releases_layout_test.dart pumps these.
library;

import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/display/app_fonts.dart';
import '../../../design/app_kit.dart';
import '../../../design/app_tokens.dart';
import '../admin_common.dart' show t;
import 'app_releases_models.dart';
import 'app_releases_text.dart';

/// A small status chip: icon + the status's words in its colour.
class ReleaseStatusChip extends StatelessWidget {
  const ReleaseStatusChip(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) =>
      AppBadgePill(releaseStatusName(status), color: releaseStatusColor(context, status), icon: releaseStatusIcon(status));
}

/// The chip of [r]: a live release that a newer one replaced reads "Replaced".
Widget releaseChipOf(AppRelease r) => ReleaseStatusChip(r.shownStatus);

/// "2 min ago" for a UTC instant (the date past a week, in the platform timezone).
String releaseAgo(DateTime? utc) => utc == null ? '' : relTime(utc.toIso8601String());

/// The build server: online / offline, last seen, the job it runs, and the token rotation.
class BuilderStatusBanner extends StatelessWidget {
  const BuilderStatusBanner({super.key, required this.status, this.onRotateToken, this.onOpenBusy});

  /// null while it loads (or when the status could not be read).
  final BuilderStatus? status;
  final VoidCallback? onRotateToken;

  /// Opens the release the build server works on.
  final VoidCallback? onOpenBusy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = status;
    final online = s?.online ?? false;
    final col = s == null ? c.textLight : (online ? c.success : c.danger);
    final title = s == null
        ? t('خادم البناء', 'Build server')
        : online
            ? t('خادم البناء متصل', 'Build server online')
            : t('خادم البناء غير متصل', 'Build server offline');
    final meta = <String>[
      if (s?.lastSeen != null) t('آخر ظهور ${releaseAgo(s!.lastSeen)}', 'Last seen ${releaseAgo(s.lastSeen)}'),
      if (s?.version != null) 'v${s!.version}',
      if (s != null && !online && s.lastSeen == null) t('لم يتصل بعد', 'Never connected'),
    ].join(' · ');
    final busy = s != null && s.busy;
    final setup = s == null
        ? null
        : !s.configured
            ? t('الإصدارات غير مُعدّة على هذا الخادم بعد (لا يوجد مجلد الإصدارات): يمكن تسجيل الآيفون وويندوز وماك فقط',
                'Releases are not set up on this server yet (no releases folder): only iPhone, Windows and macOS can be recorded')
            : !s.tokenSet
                ? t('لا يوجد رمز لخادم البناء بعد — أنشئ رمزاً وضعه في إعداداته', 'No build server token yet — create one and put it in its settings')
                : null;
    return AppCard(
      key: const ValueKey('releases.builder'),
      padding: const EdgeInsets.all(AppSpace.sm),
      child: LayoutBuilder(builder: (context, box) {
        final narrow = box.maxWidth < 520;
        final info = Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: AppRadius.chipAll),
            child: Icon(online ? Icons.dns_rounded : Icons.cloud_off_rounded, color: col, size: 22),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
                const SizedBox(width: AppSpace.xs),
                Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontFamily: AppFonts.family))),
              ]),
              if (meta.isNotEmpty)
                Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(fontFamily: AppFonts.family)),
              if (busy)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xxs),
                  child: InkWell(
                    onTap: onOpenBusy,
                    borderRadius: AppRadius.chipAll,
                    child: AppBadgePill(
                      s.busyVersion == null
                          ? t('يبني الآن', 'Building now')
                          : t('يبني الآن: ${releasePlatformShort(s.busyPlatform ?? '')} ${s.busyVersion}', 'Building now: ${releasePlatformShort(s.busyPlatform ?? '')} ${s.busyVersion}'),
                      color: c.warning,
                      icon: Icons.construction_rounded,
                    ),
                  ),
                ),
            ]),
          ),
        ]);
        final rotate = onRotateToken == null
            ? null
            : TextButton.icon(
                key: const ValueKey('releases.rotate'),
                onPressed: onRotateToken,
                icon: const Icon(Icons.key_rounded, size: 18),
                label: Text(t('رمز جديد لخادم البناء', 'New build server token'), style: TextStyle(fontFamily: AppFonts.family)),
              );
        final note = setup == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: AppBanner(key: const ValueKey('releases.setup'), icon: Icons.settings_suggest_outlined, color: c.warning, text: setup),
              );
        final Widget top;
        if (rotate == null) {
          top = info;
        } else if (narrow) {
          top = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [info, Align(alignment: AlignmentDirectional.centerEnd, child: rotate)]);
        } else {
          top = Row(children: [Expanded(child: info), rotate]);
        }
        return note == null ? top : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [top, note]);
      }),
    );
  }
}

/// The page body: the filters and one card per platform.
class AppReleasesView extends StatelessWidget {
  const AppReleasesView({
    super.key,
    required this.releases,
    this.platform,
    this.status,
    this.onPlatform,
    this.onStatus,
    this.onOpen,
    this.onNew,
    this.hasMore = false,
    this.onMore,
  });

  final List<AppRelease> releases;

  /// The filters (null = all).
  final String? platform, status;
  final ValueChanged<String?>? onPlatform, onStatus;
  final ValueChanged<AppRelease>? onOpen;
  final VoidCallback? onNew;
  final bool hasMore;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<AppRelease>>{};
    for (final r in releases) {
      groups.putIfAbsent(r.platform, () => []).add(r);
    }
    final order = [...kReleasePlatformOrder.where(groups.containsKey), ...groups.keys.where((k) => !kReleasePlatformOrder.contains(k))];
    final filtered = platform != null || status != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Filters(platform: platform, status: status, onPlatform: onPlatform, onStatus: onStatus),
      const SizedBox(height: AppSpace.sm),
      if (releases.isEmpty)
        AppEmpty(
          icon: filtered ? Icons.filter_alt_off_rounded : Icons.rocket_launch_rounded,
          title: filtered ? t('لا إصدارات بهذا الاختيار', 'No versions match') : t('لا إصدارات بعد', 'No versions yet'),
          message: filtered
              ? t('غيّر المنصة أو الحالة لترى غيرها', 'Change the platform or the status to see others')
              : t('أنشئ إصداراً: يبنيه خادم البناء من الفرع الذي تختاره ثم ينشره', 'Create a version: the build server builds it from the branch you pick, then publishes it'),
          actionLabel: filtered ? null : t('إصدار جديد', 'New version'),
          onAction: filtered ? null : onNew,
        )
      else
        for (final p in order) ...[
          _PlatformGroup(platform: p, releases: groups[p]!, onOpen: onOpen),
          const SizedBox(height: AppSpace.md),
        ],
      if (hasMore && onMore != null)
        Center(
          child: TextButton.icon(
            key: const ValueKey('releases.more'),
            onPressed: onMore,
            icon: const Icon(Icons.expand_more_rounded),
            label: Text(t('عرض المزيد', 'Show more'), style: TextStyle(fontFamily: AppFonts.family)),
          ),
        ),
    ]);
  }
}

class _Filters extends StatelessWidget {
  const _Filters({this.platform, this.status, this.onPlatform, this.onStatus});

  final String? platform, status;
  final ValueChanged<String?>? onPlatform, onStatus;

  @override
  Widget build(BuildContext context) {
    final chips = Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
      AppChoiceChip(
        key: const ValueKey('releases.filter.all'),
        label: t('كل المنصات', 'All platforms'),
        selected: platform == null,
        onTap: () => onPlatform?.call(null),
      ),
      for (final p in kReleasePlatformOrder)
        AppChoiceChip(
          key: ValueKey('releases.filter.$p'),
          label: releasePlatformShort(p),
          icon: releasePlatformIcon(p),
          selected: platform == p,
          onTap: () => onPlatform?.call(p),
        ),
    ]);
    final dropdown = AppDropdown<String?>(
      key: const ValueKey('releases.filter.status'),
      value: status,
      decoration: InputDecoration(labelText: t('الحالة', 'Status')),
      items: [
        DropdownMenuItem(value: null, child: Text(t('كل الحالات', 'All statuses'))),
        for (final s in kReleaseStatuses) DropdownMenuItem(value: s, child: Text(releaseStatusName(s))),
      ],
      onChanged: (v) => onStatus?.call(v),
    );
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < 760) {
        // a phone: the platforms as one row that scrolls sideways, the status under it
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppHScroll(thumbVisibility: false, padding: const EdgeInsets.only(bottom: 2), child: Row(children: [for (final ch in chips.children) Padding(padding: const EdgeInsetsDirectional.only(end: AppSpace.xs), child: ch)])),
          const SizedBox(height: AppSpace.sm),
          dropdown,
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: chips),
        const SizedBox(width: AppSpace.md),
        SizedBox(width: 240, child: dropdown),
      ]);
    });
  }
}

class _PlatformGroup extends StatelessWidget {
  const _PlatformGroup({required this.platform, required this.releases, this.onOpen});

  final String platform;
  final List<AppRelease> releases;
  final ValueChanged<AppRelease>? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final live = releases.where((r) => r.isLive).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs, bottom: AppSpace.xs),
        child: LayoutBuilder(
          builder: (context, box) => Row(children: [
            Icon(releasePlatformIcon(platform), size: 20, color: c.primary),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Text(releasePlatformName(platform),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(fontFamily: AppFonts.family)),
            ),
            if (live != null) ...[
              const SizedBox(width: AppSpace.xs),
              // at the row's end; on a narrow card it shortens rather than pushing the row out
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: box.maxWidth * 0.55),
                child: AppBadgePill(t('المنشور: ${live.label}', 'Live: ${live.label}'), color: c.success, icon: Icons.check_circle_rounded),
              ),
            ],
          ]),
        ),
      ),
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (var i = 0; i < releases.length; i++) ...[
            if (i > 0) Divider(height: 1, color: c.divider),
            ReleaseRow(release: releases[i], onTap: onOpen == null ? null : () => onOpen!(releases[i])),
          ],
        ]),
      ),
    ]);
  }
}

/// One release in its platform card.
class ReleaseRow extends StatelessWidget {
  const ReleaseRow({super.key, required this.release, this.onTap});

  final AppRelease release;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = release;
    final col = releaseStatusColor(context, r.shownStatus);
    final meta = <String>[
      if (releasePlatformBuildable(r.platform)) ...[releaseGateName(r.gate), if (r.branch != null) r.branch!],
      releasePolicyName(r.policy),
      if (r.source != 'website') releaseSourceName(r.source),
      if (r.createdAt != null) AppTime.dateTime(r.createdAt!),
    ].join(' · ');
    final notes = (AppConfig.lang == 'ar' ? r.notesAr : r.notesEn).trim();
    return Material(
      color: r.isLive ? c.success.withValues(alpha: 0.06) : Colors.transparent,
      child: InkWell(
        key: ValueKey('releases.row.${r.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: AppRadius.chipAll),
              child: Icon(releaseStatusIcon(r.shownStatus), color: col, size: 21),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(r.label, textDirection: TextDirection.ltr, style: AppType.row(context).copyWith(fontFamily: AppFonts.family, fontWeight: FontWeight.w700)),
                  releaseChipOf(r),
                  if (r.isLive && r.status != 'live') AppBadgePill(t('منشور', 'Live'), color: c.success, icon: Icons.check_circle_rounded),
                ]),
                const SizedBox(height: 2),
                Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(fontFamily: AppFonts.family)),
                if (r.active) ...[
                  const SizedBox(height: AppSpace.xs),
                  AppProgressBar(value: r.progress ?? 0, color: col, height: 6),
                  if (r.step != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(r.step!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(fontFamily: AppFonts.family, fontSize: 11.5)),
                    ),
                ] else if (notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(notes, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(fontFamily: AppFonts.family, color: c.textMedium)),
                  ),
              ]),
            ),
            const SizedBox(width: AppSpace.xs),
            Icon(Icons.chevron_right_rounded, color: c.textLight),
          ]),
        ),
      ),
    );
  }
}
