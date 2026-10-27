// S11 / S9: the password rule is 8+ characters on the client too, and the server's account codes
// (WEAK_PASSWORD, PHONE_TAKEN, REAUTH_REQUIRED) have a sentence in both languages.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('password must be at least 8 characters', () {
    expect(Validators.validatePassword(''), isNotNull);
    expect(Validators.validatePassword('abc1234'), isNotNull); // 7
    expect(Validators.validatePassword('abc12345'), isNull); // 8
  });

  test('account codes have their own text in both languages', () {
    for (final code in ['WEAK_PASSWORD', 'PHONE_TAKEN', 'REAUTH_REQUIRED']) {
      final e = ApiException(statusCode: 400, message: 'server text', code: code);
      AppConfig.lang = 'en';
      final en = apiErrorText(e);
      AppConfig.lang = 'ar';
      final ar = apiErrorText(e);
      expect(en, isNot('server text'), reason: code);
      expect(ar, isNot('server text'), reason: code);
      expect(en, isNot(ar), reason: code);
    }
  });
}
