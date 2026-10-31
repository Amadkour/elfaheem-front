// Non-web builds: there is no browser to describe (the "Get the app" banner is web only).
import 'get_app_rules.dart';

/// The browser this page runs in (web: get_app_probe_web.dart).
GetAppEnv probeGetAppEnv() => GetAppEnv.native;

/// The absolute URL of a file published at the site root, e.g. `releases/releases.json` (web only).
String? getAppSiteFile(String path) => null;

/// Calls [onChange] when the browser starts / stops offering to install the web app (web only).
void listenPwaInstallable(void Function(bool installable) onChange) {}

/// Shows the browser's own "Install app" prompt: 'accepted', 'dismissed' or 'unavailable' (web only).
Future<String> promptPwaInstall() async => 'unavailable';

/// The CPU arch from Chromium's client hints, when the browser says (web only).
Future<String?> probeArchHint(GetAppOs os) async => null;

/// The page's own address, for "copy the link" (web only).
String currentPageUrl() => '';

/// The browser's notification permission: 'default', 'granted', 'denied' or 'unsupported' (web only).
String webNotificationPermission() => 'unsupported';

/// Asks for notification permission; must run inside the tap's own event (iOS Safari needs the gesture).
Future<String> requestWebNotificationPermission() async => 'unsupported';
