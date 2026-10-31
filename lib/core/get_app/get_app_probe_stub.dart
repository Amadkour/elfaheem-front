// Non-web builds: there is no browser to describe (the "Get the app" banner is web only).
import 'get_app_rules.dart';

/// The browser this page runs in (web: get_app_probe_web.dart).
GetAppEnv probeGetAppEnv() => GetAppEnv.native;

/// The absolute URL of a file published next to index.html (web only).
String? getAppSiteFile(String name) => null;
