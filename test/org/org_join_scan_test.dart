import 'package:flutter_education_app/features/org/org_join_scan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseJoinQr', () {
    test('the bare code the Codes panel encodes', () {
      expect(parseJoinQr('ABCD2345XY'), 'ABCD2345XY');
      expect(parseJoinQr('  abcd2345xy \n'), 'ABCD2345XY');
      expect(parseJoinQr('ABCD-2345-XY'), 'ABCD2345XY');
      expect(parseJoinQr('ABCD 2345 XY'), 'ABCD2345XY');
    });

    test('the shared invitation text (Arabic and English)', () {
      expect(parseJoinQr('انضم إلى جامعة القاهرة على التطبيق باستخدام الكود: K7M2PQ9XZA'), 'K7M2PQ9XZA');
      expect(parseJoinQr('Join Cairo University in the app with the code: k7m2pq9xza'), 'K7M2PQ9XZA');
      expect(parseJoinQr('Join Faculty of Science in the app with the code: K7M2-PQ9X-ZA.'), 'K7M2PQ9XZA');
    });

    test('links carrying the code', () {
      expect(parseJoinQr('https://alfheemacademy.com/join?code=ABCD2345XY'), 'ABCD2345XY');
      expect(parseJoinQr('https://alfheemacademy.com/#/org/join?join_code=abcd2345xy'), 'ABCD2345XY');
      expect(parseJoinQr('nextbrain://join?code=ABCD-2345-XY'), 'ABCD2345XY');
      expect(parseJoinQr('https://example.com/some/page'), isNull);
    });

    test('not a join code', () {
      expect(parseJoinQr(null), isNull);
      expect(parseJoinQr(''), isNull);
      expect(parseJoinQr('AB1'), isNull); // too short
      expect(parseJoinQr('WIFI:S:home;T:WPA;P:secret;;'), isNull);
      expect(parseJoinQr('{"type":"attendance","id":5}'), isNull);
      expect(parseJoinQr('A' * 60), isNull); // too long
    });
  });

  test('scanner is hidden on web only', () {
    expect(joinScannerAvailable, isTrue); // VM test = not web
  });
}
