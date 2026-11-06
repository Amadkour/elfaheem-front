// lib/design/master_detail/entity_chip.dart — THE way to mention a student / course / teacher / category (D-290).
//
//   EntityChip(ref)                    a small pill: the kind's icon + the name; a tap opens the entity
//   EntityLink(ref, child: …)          any widget (a list row) that opens the entity; read as "<kind>: <name>"
//   EntityGuardedChip(ref)             a chip for a mention the viewer may or may not reach: a link only once the
//                                      server says so (EntityAccess); until then, or without access, plain text
//
// Both open through EntityNavigator.open: inside a detail panel they drill in, in a list they open the panel, anywhere
// else they push the full page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/entities/entity_access.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';

import '../app_kit.dart' show AppAvatar, appText;
import '../app_tokens.dart';
import 'entity_navigator.dart';

/// The icon of a kind.
IconData entityKindIcon(EntityKind kind) => switch (kind) {
      EntityKind.student => Icons.school_rounded,
      EntityKind.course => Icons.auto_stories_rounded,
      EntityKind.teacher => Icons.co_present_rounded,
      EntityKind.category => Icons.category_rounded,
    };

/// "Student", "Course" … in the app language.
String entityKindLabel(EntityKind kind) => 'md_kind_${kind.name}'.tr;

/// A tappable mention of [ref]: the kind's icon and the name, on a soft tint. At least 48 px tall to tap (the pill
/// itself is smaller and centred in that area); [minHeight] lowers that in a compact table on a pointer device.
/// [avatar] draws a person's picture (or initials) instead of the kind's icon.
class EntityChip extends StatelessWidget {
  const EntityChip(this.ref,
      {super.key,
      this.showIcon = true,
      this.maxWidth = 220,
      this.onOpen,
      this.avatar = false,
      this.minHeight = AppTouch.min,
      this.enabled = true});

  final EntityRef ref;
  final bool showIcon;
  final double maxWidth;
  final bool avatar;
  final double minHeight;

  /// False: the viewer has no access; the same name, muted, and not a link.
  final bool enabled;

  /// Instead of [EntityNavigator.open] (tests, a page that opens it its own way).
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = ref.name.isEmpty ? '#${ref.id}' : ref.name;
    final ink = enabled ? Color.lerp(c.primary, c.textDark, 0.35)! : c.textMedium;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
      decoration: BoxDecoration(color: enabled ? c.primaryTint : c.divider.withValues(alpha: 0.45), borderRadius: AppRadius.chipAll),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (avatar && ref.isPerson) ...[
          AppAvatar(name: name, url: ref.imageUrl, size: AppSpace.md + AppSpace.xxs),
          const SizedBox(width: AppSpace.xxs),
        ] else if (showIcon) ...[
          Icon(entityKindIcon(ref.kind), size: AppIconSize.xs, color: ink),
          const SizedBox(width: AppSpace.xxs),
        ],
        Flexible(
          child: Text(name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, w: FontWeight.w600, c: ink)),
        ),
      ]),
    );
    if (!enabled) {
      return Semantics(
        label: '${entityKindLabel(ref.kind)}: $name',
        excludeSemantics: true,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: pill),
      );
    }
    return Semantics(
      button: true,
      label: '${entityKindLabel(ref.kind)}: $name',
      excludeSemantics: true,
      child: InkWell(
        onTap: onOpen ?? () => EntityNavigator.open(context, ref),
        borderRadius: AppRadius.chipAll,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight, maxWidth: maxWidth),
          child: Align(widthFactor: 1, child: pill),
        ),
      ),
    );
  }
}

/// An [EntityChip] for a mention that is not this viewer's by construction (a name in a request, a report, a council
/// item): a link only once the server has said the viewer may open it. The rows of one list share one request.
class EntityGuardedChip extends StatefulWidget {
  const EntityGuardedChip(this.ref, {super.key, this.showIcon = true, this.maxWidth = 220});

  final EntityRef ref;
  final bool showIcon;
  final double maxWidth;

  @override
  State<EntityGuardedChip> createState() => _EntityGuardedChipState();
}

class _EntityGuardedChipState extends State<EntityGuardedChip> {
  bool? _allowed;

  @override
  void initState() {
    super.initState();
    _ask();
  }

  @override
  void didUpdateWidget(covariant EntityGuardedChip old) {
    super.didUpdateWidget(old);
    if (old.ref != widget.ref) _ask();
  }

  void _ask() {
    final want = widget.ref;
    _allowed = EntityAccess.instance.known(want);
    if (_allowed != null) return;
    EntityAccess.instance.check(want).then((v) {
      if (mounted && want == widget.ref) setState(() => _allowed = v);
    });
  }

  @override
  Widget build(BuildContext context) => EntityChip(widget.ref,
      showIcon: widget.showIcon, maxWidth: widget.maxWidth, enabled: _allowed == true);
}

/// [child] opening [ref] when tapped (a sub-list row, a title). Never put an [EntityChip] inside it: one row, one
/// link.
class EntityLink extends StatelessWidget {
  const EntityLink(this.ref, {super.key, required this.child, this.borderRadius, this.onOpen, this.label});

  final EntityRef ref;
  final Widget child;
  final BorderRadius? borderRadius;
  final VoidCallback? onOpen;

  /// The screen reader's text (default: "Course: Python Basics").
  final String? label;

  @override
  Widget build(BuildContext context) {
    final name = ref.name.isEmpty ? '#${ref.id}' : ref.name;
    return Semantics(
      button: true,
      label: label ?? '${entityKindLabel(ref.kind)}: $name',
      child: InkWell(
        onTap: onOpen ?? () => EntityNavigator.open(context, ref),
        borderRadius: borderRadius ?? AppRadius.cardAll,
        child: child,
      ),
    );
  }
}
