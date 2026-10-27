// Which API a build talks to (review R3 M1). Requirements:
// - no API_BASE_URL → production, in every build mode;
// - debug / profile builds may point at the local gateway over plain http;
// - a release build accepts only an https:// override; anything else falls back to production (never cleartext).
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const prod = 'https://nextbrain.site/api';

  test('production is the default in every mode', () {
    expect(AppConfig.productionBaseUrl, prod);
    for (final release in [true, false]) {
      expect(resolveApiBaseUrl('', release: release), prod);
      expect(resolveApiBaseUrl('   ', release: release), prod);
    }
  });

  test('debug / profile builds take the local http gateway', () {
    expect(resolveApiBaseUrl('http://10.0.2.2:18080/api', release: false), 'http://10.0.2.2:18080/api');
    expect(resolveApiBaseUrl('http://127.0.0.1:8080/api', release: false), 'http://127.0.0.1:8080/api');
    expect(resolveApiBaseUrl('https://staging.example.org/api', release: false), 'https://staging.example.org/api');
  });

  test('a release build accepts an https override', () {
    expect(resolveApiBaseUrl('https://staging.example.org/api', release: true), 'https://staging.example.org/api');
    expect(resolveApiBaseUrl(' https://nextbrain.site/api ', release: true), prod);
  });

  test('a release build never ships plain http or a malformed URL', () {
    for (final bad in [
      'http://10.0.2.2:18080/api',
      'HTTP://nextbrain.site/api',
      'http://nextbrain.site/api',
      'nextbrain.site/api',
      'https:/nextbrain.site/api',
      'https://',
      'ftp://nextbrain.site/api',
      'ws://nextbrain.site/api',
    ]) {
      expect(resolveApiBaseUrl(bad, release: true), prod, reason: bad);
    }
  });
}
