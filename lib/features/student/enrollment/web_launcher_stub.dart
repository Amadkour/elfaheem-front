/// No-op stub for mobile/desktop platforms where dart:html is unavailable.
/// The kIsWeb guard in enrollment_provider.dart ensures this is never
/// called at runtime — it exists only so the project compiles on all platforms.
void redirectCurrentTab(String url) {
  // intentionally empty
}