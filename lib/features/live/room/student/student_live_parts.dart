// lib/features/live/room/student/student_live_parts.dart
//
// The small pieces the student's prejoin page and private room share (Stu1Learn prejoin, SubjectProfile live): the
// dark area surface, the initial avatar, the round control with its label, the "started 12 min ago" pill, and the
// strings helper. Plain values only: everything here is pumped by test/ui/sb_live_layout_test.dart.
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';

/// `'key'.tr` with `{name}` placeholders filled.
String sbLiveTr(String key, [Map<String, String> args = const {}]) {
  var s = key.tr;
  args.forEach((k, v) => s = s.replaceAll('{$k}', v));
  return s;
}

/// The first letter of a person's name for an avatar: a title (أ. / د. / Mr / Dr …) is skipped.
String liveInitial(String? name) {
  final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '؟';
  const titles = {'أ.', 'أ', 'د.', 'د', 'م.', 'mr', 'mr.', 'mrs', 'mrs.', 'ms', 'ms.', 'dr', 'dr.', 'prof.', 'prof'};
  final word = parts.firstWhere((p) => !titles.contains(p.toLowerCase()), orElse: () => parts.first);
  return word.characters.first.toUpperCase();
}

/// Whole minutes since [startsAt] (null before it starts or when it is not known).
int? liveStartedMinutes(DateTime? startsAt, {DateTime? now}) {
  if (startsAt == null) return null;
  final d = (now ?? DateTime.now()).toUtc().difference(startsAt.toUtc());
  if (d.isNegative) return null;
  return d.inMinutes;
}

/// The page under the student's live screens: the learn area's hero gradient, no drifting shapes (the room is a
/// place to look at the teacher, nothing moves behind it).
class StudentLiveSurface extends StatelessWidget {
  const StudentLiveSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AppHeroSurface(shapes: false, child: child);
}

/// A round initial avatar. [self] paints it in the kit's sky → grape (the student), otherwise the area's pair
/// (the teacher). [ring] draws a glass ring around it.
class StudentLiveAvatar extends StatelessWidget {
  const StudentLiveAvatar({super.key, required this.name, this.size = AppDashSize.avatar, this.self = false, this.ring = false});

  final String? name;
  final double size;
  final bool self;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final set = AppAreaScope.of(context);
    final colors = self ? [kit.accent(AppAccent.sky).color, kit.accent(AppAccent.grape).color] : [set.a, set.b];
    final circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        border: ring ? Border.all(color: c.onHero, width: AppBorder.focus) : null,
      ),
      child: ExcludeSemantics(
        child: Text(
          liveInitial(name),
          style: AppType.display(context).copyWith(color: c.onHero, fontSize: size * 0.42, height: 1),
        ),
      ),
    );
    if (!ring) return circle;
    return Container(
      padding: const EdgeInsets.all(AppSpace.xs),
      decoration: BoxDecoration(shape: BoxShape.circle, color: c.heroGlass),
      child: circle,
    );
  }
}

/// The look of a round control.
enum StudentLiveTone { glass, warm, danger }

/// A round control (mic, camera, hand, ask) with an optional label under it. [onTap] null draws it disabled.
class StudentLiveRoundButton extends StatelessWidget {
  const StudentLiveRoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.label,
    this.tone = StudentLiveTone.glass,
    this.selected,
    this.size = AppDashSize.disc,
  });

  final IconData icon;
  final String tooltip;
  final String? label;
  final VoidCallback? onTap;
  final StudentLiveTone tone;

  /// A toggle's state for screen readers.
  final bool? selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final enabled = onTap != null;
    final (Color fill, Color ink) = switch (tone) {
      StudentLiveTone.glass => (c.heroGlass, c.onHero),
      StudentLiveTone.warm => (kit.warmTone.tint, kit.warmTone.ink),
      StudentLiveTone.danger => (kit.live.color, c.onHero),
    };
    final disc = AppJelly(
      enabled: enabled,
      child: Material(
        color: enabled ? fill : c.heroGlass,
        shape: CircleBorder(side: BorderSide(color: c.heroGlassBorder, width: AppBorder.hairline)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: AppIconSize.lg, color: enabled ? ink : c.onHeroFaint),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      toggled: selected,
      label: label ?? tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            disc,
            if (label != null) ...[
              const SizedBox(height: AppSpace.xs),
              Text(
                label!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.label(context).copyWith(color: c.onHeroMuted, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "بدأت من ١٢ د": a glass pill with the live dot.
class StudentLiveStartedPill extends StatelessWidget {
  const StudentLiveStartedPill({super.key, required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
      decoration: BoxDecoration(
        color: c.heroGlass,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: AppSpace.xs,
            height: AppSpace.xs,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.kit.live.color),
          ),
          const SizedBox(width: AppSpace.xs),
          Flexible(
            child: Text(
              sbLiveTr('sb_live_started', {'n': appDigits('$minutes')}),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// True in Arabic: the reading start is the right edge.
bool get liveRtl => AppConfig.lang == 'ar';
