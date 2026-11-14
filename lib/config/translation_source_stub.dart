// Phones and desktop: translation.json ships inside the app, so the bundled copy is always the right one.

/// The text of translation.json fetched past the browser cache; null = use the bundled asset.
Future<String?> fetchFreshTranslations() async => null;
