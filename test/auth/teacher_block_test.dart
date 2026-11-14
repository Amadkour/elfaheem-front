// A course's / the doctors list's `teacher` block (TeacherProfileData.fromJson): the server blanks the contact fields
// there (back PublicTeacherResponse: `gmail` "", `phone` null) and may drop them and the account fields later; the
// parser must take all three shapes.
import 'package:flutter_education_app/features/home/student/models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> serverBlock() => {
      'id': 7,
      'name': 'Ahmed Teacher',
      'gmail': '',
      'phone': null,
      'username': 'ahmed',
      'role': 'teacher',
      'country': 'EG',
      'image_url': 'https://img.test/a.png',
      'is_verified': true,
      'is_active': true,
      'login_times': 4,
      'registration_step': 'complete',
      'created_at': '2026-01-02T10:00:00',
      'teacher_profile': null,
    };

void main() {
  test('the server shape: blank contacts', () {
    final t = TeacherProfileData.fromJson(serverBlock());
    expect(t.id, 7);
    expect(t.name, 'Ahmed Teacher');
    expect(t.gmail, '');
    expect(t.phone, isNull);
    expect(t.isVerified, isTrue);
    expect(t.loginTimes, 4);
  });

  test('contact and account fields missing: defaults, no throw', () {
    final j = serverBlock()
      ..remove('gmail')
      ..remove('phone')
      ..remove('role')
      ..remove('is_verified')
      ..remove('is_active')
      ..remove('login_times')
      ..remove('registration_step');
    final t = TeacherProfileData.fromJson(j);
    expect(t.gmail, '');
    expect(t.phone, isNull);
    expect(t.role, 'teacher');
    expect(t.isVerified, isFalse);
    expect(t.isActive, isTrue);
    expect(t.loginTimes, 0);
    expect(t.registrationStep, '');
  });
}
