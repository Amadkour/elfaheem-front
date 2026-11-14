// S10: the organization-creation payment token lives in the platform keystore on devices (flutter_secure_storage),
// an older build's SharedPreferences copy is moved there once and wiped; the web keeps SharedPreferences.
import 'package:flutter_education_app/features/org/org_creation_fee.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'org_fee_token_v1';
const _secure = FlutterSecureStorage();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('device: written to the keystore, never to SharedPreferences', () async {
    final s = OrgFeeTokenStore(web: false);
    await s.write('tok-1');
    expect(await _secure.read(key: _key), 'tok-1');
    expect((await SharedPreferences.getInstance()).getString(_key), isNull);
    expect(await s.read(), 'tok-1');
    await s.write(null);
    expect(await _secure.read(key: _key), isNull);
    expect(await s.read(), isNull);
  });

  test('device: an older build\'s plain copy is moved once, then wiped', () async {
    SharedPreferences.setMockInitialValues({_key: 'old-tok'});
    final s = OrgFeeTokenStore(web: false);
    expect(await s.read(), 'old-tok');
    expect(await _secure.read(key: _key), 'old-tok');
    expect((await SharedPreferences.getInstance()).getString(_key), isNull);
    expect(await s.read(), 'old-tok', reason: 'read from the keystore the second time');
  });

  test('device: the keystore copy wins over a stray plain copy, and a write clears the plain one', () async {
    FlutterSecureStorage.setMockInitialValues({_key: 'secure-tok'});
    SharedPreferences.setMockInitialValues({_key: 'stray'});
    final s = OrgFeeTokenStore(web: false);
    expect(await s.read(), 'secure-tok');
    await s.write('new-tok');
    expect((await SharedPreferences.getInstance()).getString(_key), isNull);
    expect(await s.read(), 'new-tok');
  });

  test('web: SharedPreferences (no keystore in a browser)', () async {
    final s = OrgFeeTokenStore(web: true);
    await s.write('web-tok');
    expect((await SharedPreferences.getInstance()).getString(_key), 'web-tok');
    expect(await _secure.read(key: _key), isNull);
    expect(await s.read(), 'web-tok');
    await s.write(null);
    expect(await s.read(), isNull);
  });
}
