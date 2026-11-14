// Non-web half of `url_strategy.dart`: no browser, nothing to configure.

void configureUrlStrategy() {}

/// Web only — no-op on mobile.
void replaceBrowserUrl(String url) {}

/// Web only — no-op on mobile.
void reloadPage() {}

/// Web only — no-op on mobile.
Future<bool> browserGo(int delta, {Duration timeout = const Duration(milliseconds: 700)}) async => false;
