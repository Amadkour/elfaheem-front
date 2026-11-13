// lib/design/app_sheet_header.dart — the header and the content frame of every sheet (D-711).
//
//   AppSheetContent(title: …, tone: AppTone.info, icon: Icons.download_rounded, children: […])
//   AppSheetHeader(title, tone: AppTone.danger, icon: Icons.delete_outline_rounded)
//
// The header is a tinted band inset in the sheet: the tone's opaque tint fading towards the paper, a solid tone
// well with the icon, the title in the editorial page-title role and the close button. Every colour comes from the
// theme roles (`appToneColor`), the title is the text ink on an opaque tint (AA in both modes) and the icon takes
// whichever ink reads best on its solid well (`appInkOnFill`). The tone says what the sheet is about:
//
//   brand    (default) a normal sheet: a form, a picker, settings
//   info     imports, exports, details to read, help
//   success  a result, a share link ready, a finished job
//   warning  something to check before going on
//   danger   delete, remove, revoke, anything that cannot be undone
//   neutral  a quiet utility sheet (filters, sort)
//
// The admin `SheetHeader` draws this same header.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_badges.dart';
import 'app_contrast.dart' show ensureContrast;
import 'app_tokens.dart';

export 'app_badges.dart' show AppTone;

/// A sheet's header: a tinted band in [tone] with an optional [icon] well, the title (and an optional [subtitle]),
/// an optional [trailing] widget (a Reset button) and the close button. Without an icon the title starts 20 px
/// from the sheet's edge, the inset [AppSheetContent] gives the body.
class AppSheetHeader extends StatelessWidget {
  const AppSheetHeader(
    this.title, {
    super.key,
    this.trailing,
    this.tone = AppTone.brand,
    this.icon,
    this.subtitle,
    this.closeTooltip,
  });

  final String title;
  final Widget? trailing;
  final AppTone tone;
  final IconData? icon;
  final String? subtitle;

  /// The close button's tooltip ('close'.tr by default).
  final String? closeTooltip;

  /// The band's outer margin: the band sits [margin] in from the sheet's edges.
  static const double margin = AppSpace.xs;

  /// The well that holds the icon.
  static const double iconWell = AppTouch.min - AppSpace.xs;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final base = appSheetToneColor(context, tone);
    final tint = appTintOn(context, base);
    final fade = Color.alphaBlend(base.withValues(alpha: c.isDark ? 0.10 : 0.05), c.cardBg);
    final edge = base.withValues(alpha: c.isDark ? 0.34 : 0.20);
    final ink = c.textDark;
    final sub = subtitle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(margin, margin, margin, AppSpace.sm),
      child: DecoratedBox(
        key: const ValueKey('app.sheet.header'),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [tint, fade],
          ),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: edge, width: AppBorder.hairline),
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(icon == null ? AppSpace.sm : AppSpace.xs + AppSpace.xxs, AppSpace.sm,
              AppSpace.xs, AppSpace.sm),
          child: Row(children: [
            if (icon != null) ...[
              ExcludeSemantics(
                child: Container(
                  width: iconWell,
                  height: iconWell,
                  decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(AppRadius.card)),
                  child: Icon(icon, size: AppIconSize.md, color: appInkOnFill(context, base)),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
            ],
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Semantics(
                  header: true,
                  child: Text(title,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.pageTitle(context).copyWith(color: ink)),
                ),
                if (sub != null && sub.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xxs / 2),
                    child: Text(sub,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.body(context).copyWith(color: ensureContrast(c.textMedium, [tint, fade]))),
                  ),
              ]),
            ),
            ?trailing,
            AppSpace.gapXs,
            IconButton(
              key: const ValueKey('app.sheet.close'),
              tooltip: closeTooltip ?? 'close'.tr,
              constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
              style: IconButton.styleFrom(backgroundColor: c.cardBg.withValues(alpha: c.isDark ? 0.55 : 0.75)),
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.close_rounded, color: c.textMedium, size: AppIconSize.md),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The colour of a sheet header's [tone]: the badge tones ([appToneColor]) except [AppTone.info], which is the
/// theme's violet here — the charcoal of an info badge made every import / export header a grey band (D-711).
Color appSheetToneColor(BuildContext context, AppTone tone) =>
    tone == AppTone.info ? context.colors.purple : appToneColor(context, tone);

/// A sheet's whole content: its [AppSheetHeader] and a body with the kit's side padding (in line with the header's
/// title) that scrolls when it is taller than the sheet. `showAppSheet` draws no padding of its own — a body put
/// straight under the header touches the sheet's edges — so a sheet is `showAppSheet(context, (_) =>
/// AppSheetContent(title: …, children: […]))`. The sheet sizes to this content (a dialog on wide windows, a bottom
/// sheet on phones) and the body scrolls once it reaches the sheet's height. Pumped on its own (a layout test,
/// unbounded height) the body simply takes its height.
class AppSheetContent extends StatelessWidget {
  const AppSheetContent({
    super.key,
    required this.title,
    required this.children,
    this.headerTrailing,
    this.tone = AppTone.brand,
    this.icon,
    this.subtitle,
  });

  final String title;
  final List<Widget> children;
  final Widget? headerTrailing;

  /// The header band's tone and icon (see the file header).
  final AppTone tone;
  final IconData? icon;
  final String? subtitle;

  /// The body's padding: the header title's start inset on both sides, a section gap under the last widget.
  static const EdgeInsets padding = EdgeInsets.fromLTRB(AppSpace.md + AppSpace.xxs, 0, AppSpace.md + AppSpace.xxs, AppSpace.lg);

  @override
  Widget build(BuildContext context) {
    final body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    return LayoutBuilder(builder: (context, box) {
      final header = AppSheetHeader(title, trailing: headerTrailing, tone: tone, icon: icon, subtitle: subtitle);
      if (!box.maxHeight.isFinite) {
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          header,
          Padding(padding: padding, child: body),
        ]);
      }
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        Flexible(child: SingleChildScrollView(padding: padding, child: body)),
      ]);
    });
  }
}
