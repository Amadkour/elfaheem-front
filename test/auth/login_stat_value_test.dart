import 'package:flutter_education_app/features/auth/auth_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('login stats come out in one digit style, big numbers grouped', () {
    expect(loginStatValue('60000'), '60,000');
    expect(loginStatValue('٥٠+'), '50+');
    expect(loginStatValue('٦٠٠٠٠'), '60,000');
    expect(loginStatValue('۱۲۳۴۵۶۷'), '1,234,567');
    expect(loginStatValue(' 1200+ '), '1200+');
    expect(loginStatValue('60,000'), '60,000');
    expect(loginStatValue('4.98765'), '4.98765');
    expect(loginStatValue('98%'), '98%');
    expect(loginStatValue('+١٠٠٠٠٠ طالب'), '+100,000 طالب');
  });
}
