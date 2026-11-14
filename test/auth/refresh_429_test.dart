// S16: a 429 on POST /auth/refresh is the server's throttle, not a verdict on the refresh token — the session
// is kept and the call fails for now; every other 4xx still signs the person out.
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('4xx other than 429 rejects the refresh token', () {
    for (final s in [400, 401, 403, 404, 422]) {
      expect(refreshStatusRejects(s), isTrue, reason: '$s');
    }
  });

  test('429, 5xx and no status are transient — the session is kept', () {
    for (final s in [429, 500, 502, 503, null, 0]) {
      expect(refreshStatusRejects(s), isFalse, reason: '$s');
    }
  });
}
