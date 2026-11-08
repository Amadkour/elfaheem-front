// lib/features/shared/records/records_share_parts.dart — the plain-values widgets of sharing a record (D-312): no API,
// no player, no provider, so test/ui/records_share_layout_test.dart pumps them with the layout harness.
//
//   RecordShareLayout     the Share sheet's body: who may watch (Only people I choose · Anyone with the link), the
//                         chosen people (opened or not, remove), Add people, the link (LTR) with Copy / Share, Save,
//                         Stop sharing
//   SharePeopleLayout     the people picker: the search slot, the results with a check, the chosen count
//   SharedRecordTile      one item of "Shared with me": cover, title, who shared it, when, length
//   SharedRecordsLayout   the Shared-with-me list: skeleton · error · empty · the tiles
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import 'records_api.dart' show mmss;
import 'records_share_api.dart';

/// A person's row: avatar, name, @username or what they did, and a trailing control.
class SharePersonRow extends StatelessWidget {
  const SharePersonRow({super.key, required this.person, this.subtitle, this.trailing, this.onTap, this.showImage = true});

  final RecordSharePerson person;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showImage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sub = subtitle ?? (person.username == null ? null : '@${person.username}');
    return InkWell(
      key: ValueKey('records.share.person.${person.id}'),
      borderRadius: BorderRadius.circular(AppRadius.chip),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
          child: Row(children: [
            AppAvatar(name: person.name, url: showImage ? person.imageUrl : null, size: 36),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(person.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w600, c: c.textDark)),
                if (sub != null)
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: AppSpace.xs), trailing!],
          ]),
        ),
      ),
    );
  }
}

/// One audience choice: a selectable card with an icon, the label and its hint.
class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.mode, required this.selected, required this.icon, this.onTap});

  final RecordShareMode mode;
  final bool selected;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        key: ValueKey('records.share.mode.${mode.wire}'),
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: AnimatedContainer(
          duration: motion.fast,
          curve: AppMotion.curve,
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(
            color: selected ? c.primaryTint : c.cardBg,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: selected ? c.primary : c.divider, width: selected ? AppBorder.strong : AppBorder.hairline),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: selected ? c.primary : c.textMedium, size: AppIconSize.lg),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(mode.label, style: appText(14, w: FontWeight.w700, c: c.textDark)),
                const SizedBox(height: 2),
                Text(mode.hint, style: appText(12, c: c.textMedium, h: 1.4)),
              ]),
            ),
            const SizedBox(width: AppSpace.xs),
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                color: selected ? c.primary : c.textLight, size: AppIconSize.md),
          ]),
        ),
      ),
    );
  }
}

class RecordShareLayout extends StatelessWidget {
  const RecordShareLayout({
    super.key,
    required this.mode,
    required this.people,
    this.link,
    this.active = false,
    this.views = 0,
    this.busy = false,
    this.dirty = false,
    this.error,
    this.showImages = true,
    this.onMode,
    this.onAdd,
    this.onRemove,
    this.onCopy,
    this.onSystemShare,
    this.onSave,
    this.onStop,
  });

  /// The chosen audience (never off: the sheet starts on "people").
  final RecordShareMode mode;
  final List<RecordSharePerson> people;

  /// The share's link once it exists on the server.
  final String? link;

  /// Shared on the server (Stop sharing shows).
  final bool active;
  final int views;
  final bool busy;

  /// Something changed since the last save.
  final bool dirty;
  final String? error;
  final bool showImages;
  final ValueChanged<RecordShareMode>? onMode;
  final VoidCallback? onAdd;
  final ValueChanged<RecordSharePerson>? onRemove;
  final VoidCallback? onCopy;
  final VoidCallback? onSystemShare;
  final VoidCallback? onSave;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final saveLabel = active ? t('حفظ التغييرات', 'Save changes') : t('مشاركة', 'Share');
    final canSave = !busy && (dirty || !active) && (mode == RecordShareMode.link || people.isNotEmpty);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(t('من يمكنه المشاهدة؟', 'Who can watch?'), style: AppType.section(context)),
      const SizedBox(height: AppSpace.xs),
      _ModeCard(
        mode: RecordShareMode.people,
        icon: Icons.group_rounded,
        selected: mode == RecordShareMode.people,
        onTap: busy ? null : () => onMode?.call(RecordShareMode.people),
      ),
      const SizedBox(height: AppSpace.xs),
      _ModeCard(
        mode: RecordShareMode.link,
        icon: Icons.link_rounded,
        selected: mode == RecordShareMode.link,
        onTap: busy ? null : () => onMode?.call(RecordShareMode.link),
      ),
      const SizedBox(height: AppSpace.md),
      Row(children: [
        Expanded(
          child: Text(
            mode == RecordShareMode.link ? t('أخبر أشخاصاً أيضاً', 'Also tell people') : t('الأشخاص', 'People'),
            style: AppType.section(context),
          ),
        ),
        AppButton(
          key: const ValueKey('records.share.add'),
          label: t('إضافة أشخاص', 'Add people'),
          icon: Icons.person_add_alt_1_rounded,
          variant: AppButtonVariant.tonal,
          size: AppButtonSize.sm,
          onPressed: busy ? null : onAdd,
        ),
      ]),
      const SizedBox(height: AppSpace.xxs),
      if (people.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          child: Text(
            mode == RecordShareMode.link
                ? t('يصل الرابط لمن ترسله إليه. أضف أشخاصاً ليصلهم إشعار.', 'The link reaches whoever you send it to. Add people to notify them.')
                : t('لم تختر أحداً بعد.', 'Nobody chosen yet.'),
            style: appText(12.5, c: c.textMedium, h: 1.45),
          ),
        )
      else
        for (final p in people)
          SharePersonRow(
            person: p,
            showImage: showImages,
            subtitle: p.openedAt != null
                ? t('شاهده · ${AppTime.date(p.openedAt!)}', 'Opened · ${AppTime.date(p.openedAt!)}')
                : (p.addedAt != null ? t('لم يفتحه بعد', 'Not opened yet') : t('سيصله إشعار', 'Will be notified')),
            trailing: IconButton(
              key: ValueKey('records.share.remove.${p.id}'),
              tooltip: t('إزالة', 'Remove'),
              constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
              icon: Icon(Icons.close_rounded, color: c.textMedium),
              onPressed: busy ? null : () => onRemove?.call(p),
            ),
          ),
      if (link != null) ...[
        const SizedBox(height: AppSpace.md),
        Text(t('الرابط', 'Link'), style: AppType.section(context)),
        const SizedBox(height: AppSpace.xs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
          decoration: BoxDecoration(
            color: c.inputBg,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: c.divider),
          ),
          child: Text(link!,
              key: const ValueKey('records.share.link'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: appText(12.5, w: FontWeight.w600, c: c.textDark)),
        ),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppButton(
            key: const ValueKey('records.share.copy'),
            label: t('نسخ الرابط', 'Copy link'),
            icon: Icons.copy_rounded,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.sm,
            onPressed: onCopy,
          ),
          if (onSystemShare != null)
            AppButton(
              key: const ValueKey('records.share.system'),
              label: t('مشاركة عبر…', 'Share via…'),
              icon: Icons.ios_share_rounded,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.sm,
              onPressed: onSystemShare,
            ),
        ]),
        if (views > 0) ...[
          const SizedBox(height: AppSpace.xs),
          Text(t('$views مشاهدة', '$views views'), style: appText(12, c: c.textMedium)),
        ],
      ],
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        Text(error!, style: appText(12.5, w: FontWeight.w600, c: c.danger, h: 1.4)),
      ],
      const SizedBox(height: AppSpace.md),
      AppButton.primary(
        key: const ValueKey('records.share.save'),
        label: saveLabel,
        icon: Icons.check_rounded,
        busy: busy,
        expand: true,
        onPressed: canSave ? onSave : null,
      ),
      if (active) ...[
        const SizedBox(height: AppSpace.xs),
        AppButton(
          key: const ValueKey('records.share.stop'),
          label: t('إيقاف المشاركة', 'Stop sharing'),
          icon: Icons.link_off_rounded,
          variant: AppButtonVariant.ghost,
          dangerOutline: true,
          expand: true,
          onPressed: busy ? null : onStop,
        ),
      ],
    ]);
  }
}

/// The people picker's body: [search] (the page owns the field), the results with a check each.
class SharePeopleLayout extends StatelessWidget {
  const SharePeopleLayout({
    super.key,
    required this.search,
    required this.results,
    required this.chosen,
    this.loading = false,
    this.error,
    this.query = '',
    this.showImages = true,
    this.onToggle,
    this.onDone,
  });

  final Widget search;
  final List<RecordSharePerson> results;
  final Set<int> chosen;
  final bool loading;
  final String? error;
  final String query;
  final bool showImages;
  final ValueChanged<RecordSharePerson>? onToggle;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Widget body;
    if (loading && results.isEmpty) {
      body = const AppListSkeleton(items: 4);
    } else if (error != null && results.isEmpty) {
      body = AppBanner(icon: Icons.error_outline_rounded, text: error!, color: c.danger);
    } else if (results.isEmpty) {
      body = AppEmpty(
        icon: Icons.person_search_rounded,
        title: t('لا نتائج', 'No results'),
        message: query.trim().isEmpty
            ? t('ابحث بالاسم، أو اكتب @اسم المستخدم كاملاً لأي شخص على المنصة.', 'Search by name, or type the full @username of anyone on the platform.')
            : t('جرّب @اسم المستخدم كاملاً.', 'Try the full @username.'),
      );
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final p in results)
          SharePersonRow(
            person: p,
            showImage: showImages,
            onTap: onToggle == null ? null : () => onToggle!(p),
            trailing: Icon(
              chosen.contains(p.id) ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
              color: chosen.contains(p.id) ? c.success : c.textLight,
              semanticLabel: chosen.contains(p.id) ? t('مختار', 'Chosen') : t('غير مختار', 'Not chosen'),
            ),
          ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      search,
      const SizedBox(height: AppSpace.xs),
      body,
      const SizedBox(height: AppSpace.sm),
      AppButton.primary(
        key: const ValueKey('records.share.people.done'),
        label: chosen.isEmpty ? t('تم', 'Done') : t('تم · ${chosen.length}', 'Done · ${chosen.length}'),
        expand: true,
        onPressed: onDone,
      ),
    ]);
  }
}

/// The cover of a shared item (or a tinted mark), with its length.
class _SharedCover extends StatelessWidget {
  const _SharedCover({required this.item, this.showImage = true});
  final SharedRecord item;
  final bool showImage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const w = 112.0, h = w * 9 / 16;
    final mark = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [c.primary.withValues(alpha: 0.24), c.accent.withValues(alpha: 0.10)],
        ),
      ),
      child: Center(child: Icon(item.audio ? Icons.graphic_eq_rounded : Icons.play_circle_outline_rounded, color: c.primary, size: 30)),
    );
    final url = item.coverUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(fit: StackFit.expand, children: [
          if (showImage && url != null && url.startsWith('http'))
            Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => mark)
          else
            mark,
          if (item.durationSeconds > 0)
            PositionedDirectional(
              end: AppSpace.xxs,
              bottom: AppSpace.xxs,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: c.heroShade.withValues(alpha: 0.78), borderRadius: BorderRadius.circular(6)),
                child: Text(mmss(item.durationSeconds),
                    textDirection: TextDirection.ltr, style: appText(10.5, w: FontWeight.w700, c: c.onHero)),
              ),
            ),
        ]),
      ),
    );
  }
}

class SharedRecordTile extends StatelessWidget {
  const SharedRecordTile({super.key, required this.item, this.onTap, this.showImage = true});

  final SharedRecord item;
  final VoidCallback? onTap;
  final bool showImage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = item;
    final from = r.ownerName.isEmpty ? null : t('من ${r.ownerName}', 'From ${r.ownerName}');
    return AppCard(
      key: ValueKey('records.shared.${r.token}'),
      padding: const EdgeInsets.all(AppSpace.sm),
      onTap: onTap,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SharedCover(item: r, showImage: showImage),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: c.textDark, h: 1.3)),
            const SizedBox(height: 2),
            Text(
              [?from, if (r.sharedAt != null) AppTime.date(r.sharedAt!)].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: appText(12, c: c.textMedium, h: 1.35),
            ),
          ]),
        ),
        const SizedBox(width: AppSpace.xxs),
        SizedBox(
          width: AppTouch.min,
          height: AppTouch.min,
          child: Center(child: Icon(Icons.play_arrow_rounded, color: c.primary, semanticLabel: t('تشغيل', 'Play'))),
        ),
      ]),
    );
  }
}

class SharedRecordsLayout extends StatelessWidget {
  const SharedRecordsLayout({
    super.key,
    required this.items,
    this.loading = false,
    this.error,
    this.onTap,
    this.onReload,
    this.showImages = true,
    this.padding = const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xxl * 2),
  });

  final List<SharedRecord> items;
  final bool loading;
  final String? error;
  final ValueChanged<SharedRecord>? onTap;
  final VoidCallback? onReload;
  final bool showImages;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (loading && items.isEmpty) return const AppListSkeleton(items: 4);
    if (error != null && items.isEmpty) {
      return AppEmpty(
        icon: Icons.cloud_off_rounded,
        title: t('تعذّر التحميل', "Couldn't load"),
        message: error,
        actionLabel: onReload == null ? null : t('إعادة المحاولة', 'Try again'),
        onAction: onReload,
      );
    }
    if (items.isEmpty) {
      return AppEmpty(
        icon: Icons.folder_shared_outlined,
        title: t('لم يشاركك أحد تسجيلاً بعد', 'Nothing shared with you yet'),
        message: t('حين يشارك أحدهم تسجيلاً معك يصلك إشعار ويظهر هنا.', 'When someone shares a recording with you, you get a notification and it shows up here.'),
      );
    }
    return ListView.separated(
      key: const ValueKey('records.shared.list'),
      padding: padding,
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpace.xs),
      itemBuilder: (context, i) => SharedRecordTile(
        item: items[i],
        showImage: showImages,
        onTap: onTap == null ? null : () => onTap!(items[i]),
      ),
    );
  }
}
