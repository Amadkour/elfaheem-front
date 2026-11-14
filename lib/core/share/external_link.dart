// lib/core/share/external_link.dart — THE one way the app hands a link to the browser / the OS (security S5).
//
// A link that reaches `launchUrl` may come from the server or from another person (a chat message, an ad target, a
// class's online link, an advisor's video link): `intent:`, `file:`, `sms:`, a custom scheme or `javascript:` (on
// the web) must never be handed on as is. So:
//
//   * https only, plus `mailto:` / `tel:` when the caller asks for them ([allowMail] / [allowTel]);
//   * http only to the developer's own machine (localhost, 127.0.0.1, 10.0.2.2) and never in a release build — the
//     same cleartext rule as the API client (D-010);
//   * our own in-app routes (`/c/<id>`, `/s/<kind>/<id>`, `/s/page/<id>`, see app_links.dart) open in place through
//     the app's router, like a deep link; our https links (`https://nextbrain.site/…`) are plain https and go out as
//     before, where App Links / Universal Links bring them back into the phone app;
//   * always LaunchMode.externalApplication; a refused link is a bilingual notice, never an exception.
//
// test/ui/external_link_test.dart checks the rules; test/ui/external_link_guard_test.dart fails on a raw
// `launchUrl(` anywhere else in lib/.
library;

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_education_app/config/app_config.dart';

import 'app_links.dart';

/// What [checkExternalLink] decided.
sealed class ExternalLinkTarget {
  const ExternalLinkTarget();
}

/// Hand [uri] to the OS / the browser.
class ExternalLinkOut extends ExternalLinkTarget {
  const ExternalLinkOut(this.uri);
  final Uri uri;
}

/// One of our own routes: open [route] in the app.
class ExternalLinkInApp extends ExternalLinkTarget {
  const ExternalLinkInApp(this.route);
  final String route;
}

/// Not allowed (or not a link at all).
class ExternalLinkRefused extends ExternalLinkTarget {
  const ExternalLinkRefused();
}

const _devHosts = {'localhost', '127.0.0.1', '10.0.2.2'};

/// The pure decision behind [openExternalLink]. [release] is `kReleaseMode` (a parameter so tests can check both).
ExternalLinkTarget checkExternalLink(String? raw,
    {bool allowMail = false, bool allowTel = false, bool release = kReleaseMode}) {
  final s = raw?.trim() ?? '';
  if (s.isEmpty) return const ExternalLinkRefused();
  // an in-app route of the one link scheme (not `//host/…`, which is a link to another site)
  if (s.startsWith('/') && !s.startsWith('//')) {
    return AppLink.parse(s) != null ? ExternalLinkInApp(s) : const ExternalLinkRefused();
  }
  final uri = Uri.tryParse(s);
  if (uri == null || !uri.hasScheme) return const ExternalLinkRefused();
  switch (uri.scheme.toLowerCase()) {
    case 'https':
      return uri.host.isEmpty ? const ExternalLinkRefused() : ExternalLinkOut(uri);
    case 'http':
      return !release && _devHosts.contains(uri.host) ? ExternalLinkOut(uri) : const ExternalLinkRefused();
    case 'mailto':
      return allowMail && uri.path.isNotEmpty ? ExternalLinkOut(uri) : const ExternalLinkRefused();
    case 'tel':
      return allowTel && uri.path.isNotEmpty ? ExternalLinkOut(uri) : const ExternalLinkRefused();
    default:
      return const ExternalLinkRefused();
  }
}

/// The launcher behind [openExternalLink]; tests swap it.
@visibleForTesting
Future<bool> Function(Uri uri, String? webOnlyWindowName) externalLinkLauncher = _launch;

Future<bool> _launch(Uri uri, String? webOnlyWindowName) =>
    launchUrl(uri, mode: LaunchMode.externalApplication, webOnlyWindowName: webOnlyWindowName);

/// Opens [raw] outside the app (or, for one of our own routes, inside it). True when something opened.
///
/// A refused link shows `link_refused`; a link the device could not open shows [failText] (default
/// `link_open_failed`). [quiet] shows neither, for a caller with a fallback of its own (copy the text, another
/// link). [webOnlyWindowName] goes to url_launcher on the web (`_blank` for a download).
Future<bool> openExternalLink(String? raw,
    {bool allowMail = false,
    bool allowTel = false,
    String? failText,
    bool quiet = false,
    String? webOnlyWindowName}) async {
  final target = checkExternalLink(raw, allowMail: allowMail, allowTel: allowTel);
  switch (target) {
    case ExternalLinkRefused():
      if (!quiet) showAppNotice('link_refused'.tr, error: true);
      return false;
    case ExternalLinkInApp(:final route):
      final nav = navigatorKey.currentState;
      if (nav == null) return false;
      nav.pushNamed(route);
      return true;
    case ExternalLinkOut(:final uri):
      var ok = false;
      try {
        ok = await externalLinkLauncher(uri, webOnlyWindowName);
      } catch (_) {}
      if (!ok && !quiet) showAppNotice(failText ?? 'link_open_failed'.tr, error: true);
      return ok;
  }
}
