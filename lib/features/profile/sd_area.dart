// lib/features/profile/sd_area.dart
//
// Shared pieces of the S-D student pages (money, store, games, Quran, Nahw, teachers, profile; redesign phase 2).
//
//   SdArea(area: AppArea.money, child: ...)       the page's ONE area scope. Several of these pages are also opened
//                                                 by teachers, parents and admins (the points wallet, the profile,
//                                                 the downloads); for them the page keeps the role accent of the
//                                                 signed-in user, and only a student (or a guest) gets the area.
//   SdHeroList(hero: AppHero(...), children: [...])  the student page body: the hero band, the first card riding up
//                                                 over its lower edge (AppHeroOverlap), the rest under it, all in the
//                                                 page's reading width.
//   SdSection(title:, trailing:, child:)          a heading row over a card's content (title + one small action).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/utils/widget/view_as_state.dart';
import 'package:provider/provider.dart';

/// The role accent of the person the page is drawn for; null for a student or a guest.
AppRoleAccent? sdRoleOf(BuildContext context) {
  if (ViewAsState.active) return appRoleAccentFor(ViewAsState.instance.role);
  try {
    return appRoleAccentFor(Provider.of<MyAuthProvider>(context, listen: false).currentUser?.role);
  } on ProviderNotFoundException {
    return null;
  }
}

class SdArea extends StatelessWidget {
  const SdArea({super.key, required this.area, required this.child, this.role});

  final AppArea area;
  final Widget child;

  /// Test seam: forces a role accent (null = read the signed-in user).
  final AppRoleAccent? role;

  @override
  Widget build(BuildContext context) {
    final r = role ?? sdRoleOf(context);
    return r == null ? AppAreaScope(area: area, child: child) : AppAreaScope.role(role: r, child: child);
  }
}

/// A student page: [hero] full width, then [children] in the [width] column; the first child rides up over the
/// hero's lower edge. Scrolls (always, so a pull refresh works on a short page).
class SdHeroList extends StatelessWidget {
  const SdHeroList({
    super.key,
    required this.hero,
    required this.children,
    this.width = AppWidth.reading,
    this.controller,
  });

  final Widget hero;
  final List<Widget> children;
  final AppWidth width;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final side = AppSpace.gutter(box.maxWidth);
        final body = Padding(
          padding: EdgeInsets.symmetric(horizontal: side),
          child: AppWidthBox(
            width: width,
            gutters: false,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
          ),
        );
        return ListView(
          controller: controller,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: AppSpace.xxl),
          children: [AppHeroOverlap(hero: hero, body: body)],
        );
      });
}

/// A heading row (the card-title face) with an optional small action at the end, 12 above the content.
class SdSection extends StatelessWidget {
  const SdSection({super.key, required this.title, required this.child, this.trailing, this.top = AppSpace.lg});

  final String title;
  final Widget child;
  final Widget? trailing;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsetsDirectional.only(top: top),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: AppSpace.xs), trailing!],
          ]),
          const SizedBox(height: AppSpace.sm),
          child,
        ]),
      );
}

/// A student sub-page whose body keeps its own scrolling: the hero band (no ride-up) on top, the body under it.
/// On a short phone window the hero is left out so the body keeps the room.
class SdHeroColumn extends StatelessWidget {
  const SdHeroColumn({super.key, required this.title, this.subtitle, this.icon, required this.child});

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;

  static const double _minHeight = 560;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        if (box.hasBoundedHeight && box.maxHeight < _minHeight) return child;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppHero(title: title, subtitle: subtitle, icon: icon, overlap: false),
          Expanded(child: child),
        ]);
      });
}
