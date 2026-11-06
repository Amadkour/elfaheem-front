// lib/features/org/advising/adv_parts.dart — the pieces the Phase 3 advising pages share (docs/advising/PHASE3.md):
//   AdvPageFrame        the centred, padded list every page draws its cards in
//   AdvSectionTitle     a section title inside that list
//   AdvLoadBar          an advisor's load against their maximum (warn / over colours), optionally with a "before"
//   AdvStatusPill       available · on leave · sabbatical · left
//   AdvRowCard          one tappable card row: avatar, title, subtitle, a trailing pill and an extra block
//   AdvStepper          − value + for a whole number (max load, warn %)
//   AdvPersonField      a field showing the chosen person (advisor / student), tap to pick, clear
//   AdvConflictList     the conflicts of an advisor or a student, add / remove
//   AdvLoadState        loading · failed · needs a server update, in one place
//   pickAdvAdvisor / pickAdvStudent / showAdvConflictSheet   the sheets that load from AdvApi
// Everything takes plain values except the three sheet functions; sizes from app_tokens.dart, colours from
// context.colors.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_icons.dart' show DirIcons;
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import '../org_v3.dart' show orgCall, orgErrorText;
import 'adv_api.dart';
import 'adv_models.dart';

/// The direction of text someone typed (a note, a reason): its first strong letter decides, so an English note in
/// the Arabic app (or the reverse) keeps its punctuation at the right end.
TextDirection advTextDirection(String text) {
  for (final r in text.runes) {
    if ((r >= 0x0590 && r <= 0x08FF) || (r >= 0xFB1D && r <= 0xFDFF) || (r >= 0xFE70 && r <= 0xFEFF)) return TextDirection.rtl;
    if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) return TextDirection.ltr;
  }
  return AppConfig.lang == 'ar' ? TextDirection.rtl : TextDirection.ltr;
}

/// A date-only value (status dates) or a timestamp, as a calm date in the organization's timezone.
String advDate(DateTime? d, {bool dateOnly = false}) {
  if (d == null) return '';
  return AppTime.date(dateOnly ? DateTime.utc(d.year, d.month, d.day, 12) : d.toUtc());
}

/// The colour of a load: over the maximum → danger, at the warning share → warning, else the brand.
Color advLoadColor(BuildContext context, {required bool warn, required bool over}) {
  final c = context.colors;
  return over ? c.danger : (warn ? c.warning : c.primary);
}

/// The list every page draws its cards in: centred, at most [maxWidth] wide, padded; [fab] leaves room for the
/// phone's floating primary action.
class AdvPageFrame extends StatelessWidget {
  const AdvPageFrame({super.key, required this.children, this.fab = false, this.maxWidth = 880, this.controller});
  final List<Widget> children;
  final bool fab;
  final double maxWidth;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final room = fab && box.maxWidth < 600;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: ListView(
              controller: controller,
              padding: EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, room ? AppSpace.xxl + AppTouch.primary : AppSpace.xl),
              children: children,
            ),
          ),
        );
      });
}

class AdvSectionTitle extends StatelessWidget {
  const AdvSectionTitle(this.title, {super.key, this.subtitle, this.trailing, this.first = false});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// The first block of a page: less room above.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    return Padding(
      padding: EdgeInsets.only(top: first ? AppSpace.xs : AppSpace.lg, bottom: AppSpace.xs),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: Text(title, style: AppType.section(context))),
            if (sub != null && sub.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xxs),
              Text(sub, style: AppType.meta(context)),
            ],
          ]),
        ),
        ?trailing,
      ]),
    );
  }
}

class AdvBusyStrip extends StatelessWidget {
  const AdvBusyStrip({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.xs),
        child: Semantics(
          label: label ?? t('جارٍ العمل', 'Working'),
          child: ClipRRect(borderRadius: AppRadius.chipAll, child: LinearProgressIndicator(minHeight: 3, color: context.colors.primary)),
        ),
      );
}

/// "23 / 40" with its bar. [before] draws a tick where the load was (a distribution preview).
class AdvLoadBar extends StatelessWidget {
  const AdvLoadBar({super.key, required this.load, required this.max, this.warn = false, this.over = false, this.before, this.trailing});
  final int load, max;
  final bool warn, over;
  final int? before;

  /// Shown after the numbers (e.g. "+ 3 co").
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final col = advLoadColor(context, warn: warn, over: over);
    final b = before;
    final numbers = b == null || b == load ? '$load / $max' : '$b → $load / $max';
    final label = t('الحمل $load من $max', 'Load $load of $max');
    return Semantics(
      label: over ? '$label, ${t('فوق الحد', 'over the maximum')}' : (warn ? '$label, ${t('قريب من الحد', 'close to the maximum')}' : label),
      excludeSemantics: true,
      child: Row(children: [
        Expanded(
          child: AppProgressBar(value: load.toDouble(), max: (max <= 0 ? 1 : (load > max ? load : max)).toDouble(), color: col, marker: b?.toDouble(), height: 6),
        ),
        const SizedBox(width: AppSpace.sm),
        // numbers read left to right in both languages ("38 / 35", never "35 / 38" in Arabic)
        Text(numbers, textDirection: TextDirection.ltr, style: AppType.meta(context).copyWith(color: over || warn ? col : null, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
        if (trailing != null) ...[
          const SizedBox(width: AppSpace.xs),
          Flexible(child: Text(trailing!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context))),
        ],
      ]),
    );
  }
}

class AdvStatusPill extends StatelessWidget {
  const AdvStatusPill({super.key, required this.status, this.away = false});
  final String status;
  final bool away;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (color, icon) = switch (status) {
      'leave' => (c.warning, Icons.beach_access_rounded),
      'sabbatical' => (c.warning, Icons.menu_book_rounded),
      'left' => (c.danger, DirIcons.logout),
      _ => away ? (c.warning, Icons.person_off_rounded) : (c.success, Icons.check_rounded),
    };
    final label = status == 'available' && away ? t('غير متاح', 'Away') : advStatusLabel(status);
    return AppBadgePill(label, color: color, icon: icon);
  }
}

/// One tappable card: avatar · title · subtitle · a trailing pill, and an optional block under them.
class AdvRowCard extends StatelessWidget {
  const AdvRowCard({
    super.key,
    required this.title,
    this.subtitle,
    this.avatarName,
    this.leading,
    this.trailing,
    this.below,
    this.onTap,
    this.semanticLabel,
  });

  final String title;
  final String? subtitle;

  /// The avatar's initials come from it (null: [leading], else no avatar).
  final String? avatarName;
  final Widget? leading, trailing, below;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    final lead = avatarName != null ? AppAvatar(name: avatarName!, size: 40) : leading;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Semantics(
        button: onTap != null,
        label: semanticLabel,
        child: AppCard(
          onTap: onTap,
          padding: const EdgeInsets.all(AppSpace.sm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            child: LayoutBuilder(builder: (context, box) {
              // a pill at the end needs room: on a narrow card (a phone, a large text size) it goes under the title
              final scale = MediaQuery.textScalerOf(context).scale(1);
              final tr = trailing;
              final atEnd = tr != null && (tr is Icon || box.maxWidth >= 360 * scale);
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  if (lead != null) ...[ExcludeSemantics(child: lead), const SizedBox(width: AppSpace.sm)],
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (sub != null && sub.isNotEmpty) Text(sub, style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (tr != null && !atEnd) ...[const SizedBox(height: AppSpace.xxs), tr],
                    ]),
                  ),
                  if (atEnd) ...[const SizedBox(width: AppSpace.xs), tr],
                ]),
                if (below != null) ...[const SizedBox(height: AppSpace.xs), below!],
              ]);
            }),
          ),
        ),
      ),
    );
  }
}

/// − value + for a whole number between [min] and [max].
class AdvStepper extends StatelessWidget {
  const AdvStepper({super.key, required this.value, required this.onChanged, this.min = 1, this.max = 1000, this.step = 1, this.suffix, required this.label});
  final int value, min, max, step;
  final ValueChanged<int>? onChanged;
  final String? suffix;

  /// What the number is, for screen readers ("Maximum students per advisor").
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = onChanged;
    Widget btn(IconData icon, String tip, int? next) => IconButton(
          tooltip: tip,
          onPressed: on == null || next == null ? null : () => on(next),
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          icon: Icon(icon, size: AppIconSize.md),
        );
    final down = value - step < min ? (value > min ? min : null) : value - step;
    final up = value + step > max ? (value < max ? max : null) : value + step;
    return Semantics(
      label: label,
      value: '$value${suffix ?? ''}',
      increasedValue: up == null ? null : '$up',
      decreasedValue: down == null ? null : '$down',
      onIncrease: on == null || up == null ? null : () => on(up),
      onDecrease: on == null || down == null ? null : () => on(down),
      child: Container(
        decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ExcludeSemantics(child: btn(Icons.remove_rounded, t('أقل', 'Less'), down)),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44),
            child: ExcludeSemantics(
              child: Text('$value${suffix ?? ''}',
                  textAlign: TextAlign.center, style: AppType.figure(context).copyWith(fontSize: 17, fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ),
          ExcludeSemantics(child: btn(Icons.add_rounded, t('أكثر', 'More'), up)),
        ]),
      ),
    );
  }
}

/// A field that shows the chosen person: tap to pick, × to clear (when [onClear] is set).
class AdvPersonField extends StatelessWidget {
  const AdvPersonField(
      {super.key, required this.label, this.name, this.detail, this.placeholder, required this.onPick, this.onClear, this.icon = Icons.person_rounded, this.avatar = true});
  final String label;

  /// Draw the chosen person's initials (false: always [icon], e.g. a date).
  final bool avatar;
  final String? name, detail, placeholder;
  final VoidCallback? onPick;
  final VoidCallback? onClear;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final has = name != null && name!.isNotEmpty;
    return Semantics(
      button: true,
      label: '$label: ${has ? name : (placeholder ?? t('لم يُختر', 'None chosen'))}',
      excludeSemantics: true,
      child: Material(
        color: c.inputBg,
        borderRadius: AppRadius.chipAll,
        child: InkWell(
          borderRadius: AppRadius.chipAll,
          onTap: onPick,
          child: Container(
            constraints: const BoxConstraints(minHeight: AppTouch.primary),
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.xxs, AppSpace.xs),
            decoration: BoxDecoration(borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
            child: Row(children: [
              has && avatar ? AppAvatar(name: name!, size: 32) : Icon(icon, color: has ? c.primary : c.textLight, size: AppIconSize.md),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(label, style: AppType.meta(context), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(has ? name! : (placeholder ?? t('اختر', 'Choose')),
                      style: has ? AppType.row(context).copyWith(fontWeight: FontWeight.w600) : AppType.body(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (has && detail != null && detail!.isNotEmpty) Text(detail!, style: AppType.meta(context), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              if (has && onClear != null)
                IconButton(
                  tooltip: t('إزالة', 'Remove'),
                  constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                  onPressed: onClear,
                  icon: Icon(Icons.close_rounded, size: AppIconSize.md, color: c.textMedium),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                  child: Icon(Icons.expand_more_rounded, color: c.textLight),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The conflicts of interest of one advisor ([ofAdvisor]) or one student: who · why · note, with remove; [onAdd]
/// opens the add sheet. null [conflicts] = still loading.
class AdvConflictList extends StatelessWidget {
  const AdvConflictList({super.key, required this.conflicts, required this.ofAdvisor, this.onAdd, this.onRemove});
  final List<AdvConflict>? conflicts;
  final bool ofAdvisor;
  final VoidCallback? onAdd;
  final ValueChanged<AdvConflict>? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = conflicts;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AdvSectionTitle(
        t('تعارض المصالح', 'Conflicts of interest'),
        subtitle: ofAdvisor
            ? t('طلاب لا يُسندون إلى هذا المرشد أبداً', 'Students this advisor must never advise')
            : t('مرشدون لا يُسندون إلى هذا الطالب أبداً', 'Advisors this student must never have'),
      ),
      if (list == null)
        const AppListSkeleton(items: 1, withAvatar: false, padding: EdgeInsets.zero)
      else if (list.isEmpty)
        Text(t('لا يوجد تعارض مسجّل.', 'No conflict is recorded.'), style: AppType.body(context))
      else
        for (final x in list)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Container(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.xxs, AppSpace.xs),
              decoration: BoxDecoration(color: c.danger.withValues(alpha: 0.05), borderRadius: AppRadius.chipAll, border: Border.all(color: c.danger.withValues(alpha: 0.2))),
              child: Row(children: [
                ExcludeSemantics(child: Icon(Icons.block_rounded, size: AppIconSize.md, color: c.danger)),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(ofAdvisor ? (x.studentName.isEmpty ? '#${x.memberId}' : x.studentName) : x.advisor.shown,
                        style: AppType.row(context), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text([advConflictReasonLabel(x.reason), if (x.note != null) x.note!].join(' · '),
                        style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                if (onRemove != null)
                  IconButton(
                    tooltip: t('إزالة التعارض', 'Remove the conflict'),
                    constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                    onPressed: () => onRemove!(x),
                    icon: Icon(Icons.delete_outline_rounded, size: AppIconSize.md, color: c.textMedium),
                  ),
              ]),
            ),
          ),
      if (onAdd != null)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: AppIconSize.md),
            label: Text(t('إضافة تعارض', 'Add a conflict')),
          ),
        ),
    ]);
  }
}

/// What a list page shows while it has no rows to draw: loading, failed (retry), or "needs a server update".
enum AdvLoad { loading, failed, missing, ready }

class AdvLoadState extends StatelessWidget {
  const AdvLoadState({super.key, required this.state, this.errorText, this.onRetry, this.items = 5});
  final AdvLoad state;
  final String? errorText;
  final VoidCallback? onRetry;
  final int items;

  @override
  Widget build(BuildContext context) => switch (state) {
        AdvLoad.loading => Semantics(
            label: t('جارٍ التحميل', 'Loading'),
            child: Align(alignment: Alignment.topCenter, child: AppListSkeleton(items: items)),
          ),
        AdvLoad.missing => AppEmpty(
            icon: Icons.system_update_alt_rounded,
            title: t('يحتاج تحديث الخادم', 'Needs a server update'),
            message: t('هذا الجزء من الإرشاد الأكاديمي لم يصل إلى الخادم بعد.', 'This part of academic advising is not on the server yet.'),
          ),
        _ => AppEmpty(
            icon: Icons.cloud_off_rounded,
            title: t('تعذّر التحميل', 'Could not load'),
            message: errorText,
            actionLabel: onRetry == null ? null : t('إعادة المحاولة', 'Retry'),
            onAction: onRetry,
          ),
      };
}

/// A field label above a group of chips / a control.
class AdvFieldLabel extends StatelessWidget {
  const AdvFieldLabel(this.text, {super.key, this.hint});
  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.xs),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: AppType.bodyStrong(context)),
          if (hint != null && hint!.isNotEmpty) Text(hint!, style: AppType.meta(context)),
        ]),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Sheets that load
// ═════════════════════════════════════════════════════════════════════════════

/// Search and pick one advisor (the advisors list: loads, status). [exclude] are left out; away advisors are shown
/// but can't be picked ([allowAway] lets a filter pick them, e.g. "whose students move").
Future<AdvAdvisor?> pickAdvAdvisor(BuildContext context, AdvApi api, {String? title, Set<int> exclude = const {}, bool allowAway = false}) {
  List<AdvAdvisor>? rows;
  String? error;
  var query = '';
  var started = false;
  return showAppSheet<AdvAdvisor>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> load() async {
          final r = await orgCall(() => api.advisors(q: query, status: 'all', sort: 'name', size: 50), quiet: true);
          if (!ctx.mounted) return;
          set(() {
            rows = r.ok ? (r.data as AdvPage<AdvAdvisor>).items : const [];
            error = r.ok ? null : orgErrorText(r.error!);
          });
        }

        if (!started) {
          started = true;
          load();
        }
        final shown = [for (final a in rows ?? const <AdvAdvisor>[]) if (!exclude.contains(a.userId)) a];
        return AppSheetContent(
          title: title ?? t('اختر مرشداً', 'Choose an advisor'),
          children: [
            AppSearchField(
              hint: t('ابحث بالاسم', 'Search by name'),
              onChanged: (q) {
                query = q;
                load();
              },
            ),
            const SizedBox(height: AppSpace.sm),
            if (rows == null)
              const AppListSkeleton(items: 4, padding: EdgeInsets.zero)
            else if (error != null)
              AppBanner(icon: Icons.error_outline_rounded, color: ctx.colors.danger, text: error!)
            else if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Text(t('لا نتائج', 'No results'), textAlign: TextAlign.center, style: AppType.body(ctx)),
              )
            else
              for (final a in shown)
                AdvRowCard(
                  title: a.shown,
                  subtitle: a.subtitle,
                  avatarName: a.shown,
                  trailing: a.away || a.status != 'available' ? AdvStatusPill(status: a.status, away: a.away) : null,
                  below: AdvLoadBar(load: a.load, max: a.maxLoad, warn: a.warn, over: a.over),
                  onTap: a.away && !allowAway ? null : () => Navigator.pop(ctx, a),
                ),
          ],
        );
      }));
}

/// Search and pick one student of the organization.
Future<AdvStudent?> pickAdvStudent(BuildContext context, AdvApi api, {String? title, Set<int> exclude = const {}}) {
  List<AdvStudent>? rows;
  String? error;
  var query = '';
  var started = false;
  return showAppSheet<AdvStudent>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> load() async {
          final r = await orgCall(() => api.students(q: query, size: 50), quiet: true);
          if (!ctx.mounted) return;
          set(() {
            rows = r.ok ? (r.data as AdvPage<AdvStudent>).items : const [];
            error = r.ok ? null : orgErrorText(r.error!);
          });
        }

        if (!started) {
          started = true;
          load();
        }
        final shown = [for (final s in rows ?? const <AdvStudent>[]) if (!exclude.contains(s.memberId)) s];
        return AppSheetContent(
          title: title ?? t('اختر طالباً', 'Choose a student'),
          children: [
            AppSearchField(
              hint: t('ابحث بالاسم أو الرقم', 'Search by name or ID'),
              onChanged: (q) {
                query = q;
                load();
              },
            ),
            const SizedBox(height: AppSpace.sm),
            if (rows == null)
              const AppListSkeleton(items: 4, padding: EdgeInsets.zero)
            else if (error != null)
              AppBanner(icon: Icons.error_outline_rounded, color: ctx.colors.danger, text: error!)
            else if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Text(t('لا نتائج', 'No results'), textAlign: TextAlign.center, style: AppType.body(ctx)),
              )
            else
              for (final s in shown)
                AdvRowCard(title: s.shown, subtitle: s.subtitle, avatarName: s.shown, onTap: () => Navigator.pop(ctx, s)),
          ],
        );
      }));
}

/// The "add a conflict" form (plain values).
class AdvConflictForm extends StatelessWidget {
  const AdvConflictForm({
    super.key,
    required this.ofAdvisor,
    required this.otherName,
    required this.reason,
    required this.note,
    required this.onPick,
    required this.onReason,
    required this.onSubmit,
    this.busy = false,
    this.error,
  });

  /// Adding to an advisor: the other side is a student (else an advisor).
  final bool ofAdvisor;
  final String? otherName;
  final String reason;
  final TextEditingController note;
  final VoidCallback onPick;
  final ValueChanged<String> onReason;
  final VoidCallback onSubmit;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AdvPersonField(
        label: ofAdvisor ? t('الطالب', 'Student') : t('المرشد', 'Advisor'),
        name: otherName,
        icon: ofAdvisor ? Icons.school_rounded : Icons.person_rounded,
        onPick: busy ? null : onPick,
      ),
      const SizedBox(height: AppSpace.md),
      AdvFieldLabel(t('السبب', 'Reason')),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final r in advConflictReasons)
          AppChoiceChip(label: advConflictReasonLabel(r), selected: r == reason, onTap: () => onReason(r)),
      ]),
      const SizedBox(height: AppSpace.md),
      AppField(controller: note, label: t('ملاحظة (اختياري)', 'Note (optional)'), maxLines: 2),
      const SizedBox(height: AppSpace.sm),
      AppBanner(
        icon: Icons.shield_outlined,
        text: t('لن يُسند هذا الطالب إلى هذا المرشد، لا تلقائياً ولا يدوياً.', 'This student will never be assigned to this advisor, automatically or by hand.'),
      ),
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.md),
      AppPrimaryButton(icon: Icons.block_rounded, label: t('تسجيل التعارض', 'Record the conflict'), busy: busy, onPressed: otherName == null ? null : onSubmit),
    ]);
  }
}

/// Records a conflict between [advisor] (or a picked one) and [student] (or a picked one). Returns the new conflict.
Future<AdvConflict?> showAdvConflictSheet(BuildContext context, AdvApi api, {AdvRef? advisor, AdvStudent? student}) {
  final note = TextEditingController();
  final ofAdvisor = advisor != null;
  AdvRef? pickedAdvisor = advisor;
  AdvStudent? pickedStudent = student;
  var reason = 'relative';
  var busy = false;
  String? error;
  return showAppSheet<AdvConflict>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> pick() async {
          if (ofAdvisor) {
            final s = await pickAdvStudent(ctx, api);
            if (s != null) set(() => pickedStudent = s);
          } else {
            final a = await pickAdvAdvisor(ctx, api, allowAway: true);
            if (a != null) set(() => pickedAdvisor = AdvRef(userId: a.userId, name: a.name));
          }
        }

        Future<void> submit() async {
          final a = pickedAdvisor, s = pickedStudent;
          if (a == null || s == null) return;
          set(() {
            busy = true;
            error = null;
          });
          final r = await orgCall(() => api.addConflict(advisorUserId: a.userId, memberId: s.memberId, reason: reason, note: note.text), quiet: true);
          if (!ctx.mounted) return;
          if (!r.ok) {
            set(() {
              busy = false;
              error = orgErrorText(r.error!);
            });
            return;
          }
          Navigator.pop(ctx, r.data as AdvConflict);
        }

        return AppSheetContent(
          title: t('تعارض مصالح', 'Conflict of interest'),
          children: [
            Text(
              ofAdvisor
                  ? t('المرشد: ${advisor.shown}', 'Advisor: ${advisor.shown}')
                  : t('الطالب: ${student?.shown ?? ''}', 'Student: ${student?.shown ?? ''}'),
              style: AppType.meta(ctx),
            ),
            const SizedBox(height: AppSpace.sm),
            AdvConflictForm(
              ofAdvisor: ofAdvisor,
              otherName: ofAdvisor ? pickedStudent?.shown : pickedAdvisor?.shown,
              reason: reason,
              note: note,
              busy: busy,
              error: error,
              onPick: pick,
              onReason: (r) => set(() => reason = r),
              onSubmit: submit,
            ),
          ],
        );
      }));
}
