// ignore: avoid_web_libraries_in_flutter
library;
import 'dart:html' as html;

/// Navigates the current browser tab to [url].
/// Used on Flutter Web so the Moyasar checkout redirect chain stays in one tab.
void redirectCurrentTab(String url) {
  html.window.location.href = url;
}
// https://checkout.moyasar.com/v2?publishable_api_key=pk_test_Ut6582RweTo7JgUEuVYBYrQv4v3RAMW7VRW3Umw5&amount=329&currency=SAR&description=%D9%83%D9%88%D8%B1%D8%B3%3A+testing+for+payment&callback_url=https%3A%2F%2Fcigarettes-knows-induced-instances.trycloudflare.com%2Fapi%2Fv1%2Fpayments%2Fweb-callback%3Ftoken%3Dbaf81f3c-5a90-4717-b1fa-e55e3800c7c6