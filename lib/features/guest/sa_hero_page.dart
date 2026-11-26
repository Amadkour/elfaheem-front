// lib/features/guest/sa_hero_page.dart — the redesign's page head for the S-A pages that keep their own body
// (categories, journey, recommendations, guest search, share link, guest live, legal): the area hero (kicker, one
// line, one squiggled word) above the page's body, under the page's area scope.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_area.dart';
import 'package:flutter_education_app/design/app_hero.dart';

class SaHeroPage extends StatelessWidget {
  const SaHeroPage({
    super.key,
    required this.area,
    required this.title,
    required this.child,
    this.kicker,
    this.squiggle,
    this.subtitle,
  });

  final AppArea area;
  final String title;
  final String? kicker, squiggle, subtitle;

  /// The page's body (it scrolls on its own).
  final Widget child;

  @override
  Widget build(BuildContext context) => AppAreaScope(
        area: area,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppHero(kicker: kicker, title: title, squiggle: squiggle, subtitle: subtitle, overlap: false),
          Expanded(child: child),
        ]),
      );
}
