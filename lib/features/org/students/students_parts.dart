// lib/features/org/students/students_parts.dart — the small pieces every Students screen shares (contract §5).
//
//   StudentStatusChip(chip)        THE one chip of a student (§3.2): label + tone, a glyph for danger / gold
//   StudentFlagChips(flags)        the active flags as quiet chips (wraps, never overflows)
//   StudentStandingChip(row)       the academic standing beside THE chip when another dimension speaks and the
//                                  standing is not `regular` (a warning must not hide behind "missing data")
//   MissingBadge(count, onTap)     "3 missing" — amber, tappable; hidden at 0 / null and under `org.students.missing`
//   StudentAvatar(user)            photo or the first letter on the primary tint
//   StudentRowCard(row, onTap)     the phone card of the list: avatar · name · code / program / level · chip · badge
//
// Plain values only (no provider, no network), so the layout harness pumps them as they are.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import 'students_models.dart';

class StudentStatusChip extends StatelessWidget {
  const StudentStatusChip(this.chip, {super.key, this.dense = true});
  final StudentChip chip;
  final bool dense;

  @override
  Widget build(BuildContext context) => AppStatusBadge(
        key: ValueKey('students.chip.${chip.dimension}.${chip.value}'),
        label: chip.label,
        tone: chip.tone,
        dot: true,
        dense: dense,
      );
}

/// The standing to show beside [chip] ([acadStanding]); null when the chip already is the standing, or it is regular.
String? studentExtraStanding(StudentChip chip, String? acadStanding) {
  final s = acadStanding;
  if (s == null || s.isEmpty || s == 'regular' || chip.dimension == 'standing') return null;
  return s;
}

/// "Academic warning" / "Final chance" … next to the main chip (nothing when [studentExtraStanding] is null).
class StudentStandingChip extends StatelessWidget {
  const StudentStandingChip({super.key, required this.chip, this.acadStanding});
  final StudentChip chip;
  final String? acadStanding;

  @override
  Widget build(BuildContext context) {
    final s = studentExtraStanding(chip, acadStanding);
    if (s == null) return const SizedBox.shrink();
    return AppStatusBadge(
      key: ValueKey('students.standing.$s'),
      label: standingLabel(s),
      tone: chipTone(StudentChip('standing', s)),
      dense: true,
    );
  }
}

class StudentFlagChips extends StatelessWidget {
  const StudentFlagChips(this.flags, {super.key, this.max});
  final List<String> flags;

  /// Show at most this many and "+n" for the rest; null = all.
  final int? max;

  @override
  Widget build(BuildContext context) {
    if (flags.isEmpty) return const SizedBox.shrink();
    final cap = max;
    final shown = cap == null || flags.length <= cap ? flags : flags.take(cap).toList();
    final rest = flags.length - shown.length;
    return Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
      for (final f in shown) AppStatusBadge(label: flagLabel(f), tone: flagTone(f), dense: true),
      if (rest > 0) AppStatusBadge(label: '+$rest', dense: true),
    ]);
  }
}

/// Whether the missing-data badge may show at all (its own kill switch).
bool missingBadgeOn() => !AppConfig.disableList.contains(kStudentsMissingKey);

class MissingBadge extends StatelessWidget {
  const MissingBadge({super.key, required this.count, this.onTap});
  final int? count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final n = count ?? 0;
    if (n <= 0 || !missingBadgeOn()) return const SizedBox.shrink();
    final c = context.colors;
    final ink = appToneInk(context, AppTone.warning);
    final label = countText(n, ar1: 'ينقصه بند واحد', ar2: 'ينقصه بندان', arFew: 'ينقصه {n} بنود', arMany: 'ينقصه {n} بندًا',
        en1: '1 item missing', en: '{n} items missing');
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs / 2),
      decoration: BoxDecoration(
        color: appTintOn(context, appToneColor(context, AppTone.warning)),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.assignment_late_outlined, size: AppIconSize.xs, color: ink),
        const SizedBox(width: AppSpace.xxs),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: ink, fontWeight: FontWeight.w600))),
        if (onTap != null) ...[
          const SizedBox(width: AppSpace.xxs / 2),
          Icon(Icons.chevron_right_rounded, size: AppIconSize.xs, color: ink),
        ],
      ]),
    );
    if (onTap == null) return Semantics(label: label, child: ExcludeSemantics(child: body));
    return Semantics(
      button: true,
      label: '$label, ${t('اعرض التفاصيل', 'show details')}',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const ValueKey('students.missing.badge'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          hoverColor: c.primary.withValues(alpha: 0.04),
          // a 48 px tall target around the small pill
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            child: Align(alignment: AlignmentDirectional.centerStart, widthFactor: 1, child: body),
          ),
        ),
      ),
    );
  }
}

class StudentAvatar extends StatelessWidget {
  const StudentAvatar({super.key, required this.user, this.size = AppTouch.min - AppSpace.xxs});
  final StudentUser user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = user.displayName.trim();
    final letter = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: appTintOn(context, c.primary)),
      child: Text(letter, style: appText(size * 0.4, w: FontWeight.w700, c: appToneInk(context, AppTone.brand))),
    );
    final url = user.imageUrl;
    final child = url == null || url.isEmpty
        ? fallback
        : ClipOval(
            child: SizedBox(
              width: size,
              height: size,
              child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
            ),
          );
    return ExcludeSemantics(child: child);
  }
}

/// "CS · Year 2 · 20261234": what identifies a student besides the name.
String studentMetaLine(StudentRow r) {
  final level = r.level;
  return [
    if (r.program != null && r.program!.label.isNotEmpty) r.program!.label,
    if (level != null) t('المستوى $level', 'Level $level'),
  ].join(' · ');
}

class StudentRowCard extends StatelessWidget {
  const StudentRowCard({super.key, required this.row, this.onTap, this.onMissing, this.selected = false});
  final StudentRow row;
  final VoidCallback? onTap;

  /// Opens the missing-data sheet; null = the badge is not tappable.
  final VoidCallback? onMissing;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final meta = studentMetaLine(row);
    final code = row.studentCode;
    return AppCard(
      key: ValueKey('students.row.${row.id}'),
      highlight: selected,
      padding: const EdgeInsets.all(AppSpace.sm),
      onTap: onTap,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StudentAvatar(user: row.user),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(row.name.isEmpty ? t('بدون اسم', 'No name') : row.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
            if (meta.isNotEmpty || code != null) ...[
              const SizedBox(height: AppSpace.xxs / 2),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs / 2, children: [
                if (meta.isNotEmpty) Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                if (code != null)
                  Text(code, textDirection: TextDirection.ltr, style: AppType.meta(context).copyWith(color: c.textMedium)),
              ]),
            ],
            AppSpace.gapXs,
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StudentStatusChip(row.chip),
              if (studentExtraStanding(row.chip, row.acadStanding) != null) StudentStandingChip(chip: row.chip, acadStanding: row.acadStanding),
              if (row.flags.isNotEmpty) StudentFlagChips(row.flags, max: 2),
              if (row.hasMissing) MissingBadge(count: row.missingCount, onTap: onMissing),
            ]),
          ]),
        ),
      ]),
    );
  }
}
