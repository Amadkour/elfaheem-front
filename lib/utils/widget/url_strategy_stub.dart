// Non-web half of `url_strategy.dart`: no browser, nothing to configure.

void configureUrlStrategy() {}

/// Web only — no-op on mobile.
void replaceBrowserUrl(String url) {}
