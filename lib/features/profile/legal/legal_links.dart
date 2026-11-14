// The ways into the Privacy policy and the Terms of service (D-308). Both pages are TermsScreen
// (profile/about/about_and_terms_screen.dart) over GET /api/v1/app-content/legal/{privacy|terms}, public, so a guest
// can read them before signing in.
//
//   openLegalPage(context, privacy:)   the named routes '/privacy' · '/terms' (no sign-in; on the web the URL shows)
//   legalSettingsGroup(context)        the "Privacy & terms" group of a role's settings page (AppSettingsPage)
//   LegalLinksRow                      "Privacy policy · Terms of service" under the sign-in / sign-up card
//
// Kill switches: profile.privacy / profile.terms (the settings rows), terms.links (the row on the auth screens),
// terms.privacy / terms (the pages themselves).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_charts.dart' show appInk;
import 'package:flutter_education_app/design/app_gradients.dart' show AppHeadingHalo;
import 'package:flutter_education_app/design/app_kit.dart' show AppSettingsGroup, AppSettingsTile, AppSpace, AppTouch, appText;
import 'package:flutter_education_app/utils/widget/parent_component.dart';

/// Route names of the two pages.
const kPrivacyRoute = '/privacy';
const kTermsRoute = '/terms';

/// Opens the privacy policy ([privacy]) or the terms of service on top of the current page.
Future<void> openLegalPage(BuildContext context, {required bool privacy}) =>
    Navigator.of(context).pushNamed(privacy ? kPrivacyRoute : kTermsRoute);

/// The settings group with both documents. [onOpen] replaces the navigation (tests, a page with its own push).
AppSettingsGroup legalSettingsGroup(BuildContext context, {void Function(bool privacy)? onOpen}) {
  final c = context.colors;
  void open(bool privacy) => onOpen != null ? onOpen(privacy) : openLegalPage(context, privacy: privacy);
  return AppSettingsGroup(
    title: 'legal_group_title'.tr,
    icon: Icons.policy_rounded,
    children: [
      AppSettingsTile(
        featureKey: 'profile.privacy',
        icon: Icons.privacy_tip_rounded,
        color: c.success,
        label: 'privacy_policy'.tr,
        keywords: 'privacy data google drive cookies الخصوصية البيانات',
        onTap: () => open(true),
      ),
      AppSettingsTile(
        featureKey: 'profile.terms',
        icon: Icons.gavel_rounded,
        color: c.primary,
        label: 'terms_of_service'.tr,
        keywords: 'terms conditions rules refund الشروط الأحكام الاسترداد',
        onTap: () => open(false),
      ),
    ],
  );
}

/// "Privacy policy · Terms of service": two quiet links (48 dp targets) under the auth card. Plain values.
class LegalLinksRow extends StatelessWidget {
  const LegalLinksRow({super.key, this.onPrivacy, this.onTerms, this.onHero = false});

  final VoidCallback? onPrivacy;
  final VoidCallback? onTerms;

  /// Drawn on the brand hero (on-hero ink) instead of the page surface.
  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = onHero ? c.onHeroMuted : appInk(context, c.textMedium);
    Widget link(String label, VoidCallback onTap) => TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            minimumSize: const Size(AppTouch.min, AppTouch.min),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
            foregroundColor: ink,
          ),
          child: Text(
            label,
            style: appText(13, w: FontWeight.w600, c: ink)
                .copyWith(decoration: TextDecoration.underline, decorationColor: ink.withValues(alpha: 0.5)),
          ),
        );
    return ParentComponent(
      featureKey: 'terms.links',
      // D-650 r3: on the doodle canvas the links get the page-colour halo when the doodles would drop them below AA
      child: AppHeadingHalo(
        off: onHero,
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            link('privacy_policy'.tr, onPrivacy ?? () => openLegalPage(context, privacy: true)),
            ExcludeSemantics(child: Text('·', style: appText(13, w: FontWeight.w700, c: ink))),
            link('terms_of_service'.tr, onTerms ?? () => openLegalPage(context, privacy: false)),
          ],
        ),
      ),
    );
  }
}
