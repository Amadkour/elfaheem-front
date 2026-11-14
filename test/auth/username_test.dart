// The @username (D-071): the mirrored rules, the input formatter, the defensive check parser, the submit-error
// reader, the identifier field spec of login / forgot password, and the UserModel field.
import 'package:flutter/services.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/username.dart';
import 'package:flutter_test/flutter_test.dart';

ApiException _err(int status, String? code, Object? body) =>
    ApiException(statusCode: status, message: 'x', code: code, body: body);

void main() {
  group('UsernameRules.normalize', () {
    test('trims, strips ONE leading @, lowercases', () {
      expect(UsernameRules.normalize('  @Ahmed_1 '), 'ahmed_1');
      expect(UsernameRules.normalize('@@ahmed'), '@ahmed');
      expect(UsernameRules.normalize('Ahmed'), 'ahmed');
      expect(UsernameRules.normalize(''), '');
    });
  });

  group('UsernameRules.problemOf', () {
    test('valid names', () {
      for (final s in ['ahmed', 'ahmed_1', 'a.b_c', '@Ahmed.Ali', 'x12', 'abc.co1', 'ahmedcom', 'a' * 30]) {
        expect(UsernameRules.problemOf(s), isNull, reason: s);
        expect(UsernameRules.codeOf(s), isNull, reason: s);
        expect(UsernameRules.isValid(s), isTrue, reason: s);
      }
    });

    test('each rule', () {
      const cases = {
        '': UsernameProblem.tooShort,
        'ab': UsernameProblem.tooShort,
        'ahmed ali': UsernameProblem.badChars,
        'أحمد': UsernameProblem.badChars,
        'ahmed-ali': UsernameProblem.badChars,
        'a@b.io': UsernameProblem.badChars,
        '12345': UsernameProblem.noLetter,
        '1_2.3': UsernameProblem.noLetter,
        '.ahmed': UsernameProblem.dotEdge,
        'ahmed.': UsernameProblem.dotEdge,
        'ahm..ed': UsernameProblem.doubleDot,
        'wwwahmed': UsernameProblem.startsWww,
        'www.ahmed': UsernameProblem.startsWww,
        'ahmed.com': UsernameProblem.domainSuffix,
        'ahmed.io': UsernameProblem.domainSuffix,
        'ahmed.ai': UsernameProblem.domainSuffix,
        'Admin': UsernameProblem.reserved,
        '@nextbrain': UsernameProblem.reserved,
        'me': UsernameProblem.reserved,
      };
      cases.forEach((input, problem) {
        expect(UsernameRules.problemOf(input), problem, reason: input);
      });
      expect(UsernameRules.problemOf('a' * 31), UsernameProblem.tooLong);
    });

    test('codes follow the server', () {
      expect(UsernameRules.codeOf('admin'), 'USERNAME_RESERVED');
      expect(UsernameRules.codeOf('ahmed.com'), 'USERNAME_INVALID');
      expect(UsernameRules.codeOf('ab'), 'USERNAME_INVALID');
    });

    test('every reserved word is refused and every problem has a text key', () {
      for (final w in UsernameRules.reserved) {
        expect(UsernameRules.problemOf(w.toUpperCase()), UsernameProblem.reserved, reason: w);
      }
      for (final p in UsernameProblem.values) {
        expect(UsernameRules.problemKey(p), startsWith('username_'));
      }
    });
  });

  group('UsernameInputFormatter', () {
    const f = UsernameInputFormatter();
    TextEditingValue fmt(String text, [int? cursor]) => f.formatEditUpdate(
          TextEditingValue.empty,
          TextEditingValue(text: text, selection: TextSelection.collapsed(offset: cursor ?? text.length)),
        );

    test('lowercases and drops impossible characters', () {
      expect(fmt('Ahmed').text, 'ahmed');
      expect(fmt('@ahmed ali').text, 'ahmedali');
      expect(fmt('أحمدahmed-1').text, 'ahmed1');
      expect(fmt('a.b_c9').text, 'a.b_c9');
    });

    test('keeps the cursor after the kept characters', () {
      final v = fmt('a bc', 3); // cursor after "a b"
      expect(v.text, 'abc');
      expect(v.selection.baseOffset, 2);
    });

    test('an already clean value is returned as is', () {
      final input = TextEditingValue(text: 'abc', selection: const TextSelection.collapsed(offset: 1));
      expect(f.formatEditUpdate(TextEditingValue.empty, input), same(input));
    });
  });

  group('UsernameCheck.fromJson', () {
    test('available', () {
      final c = UsernameCheck.fromJson(
          {'username': 'ahmed', 'available': true, 'code': null, 'message': null, 'suggestions': []});
      expect(c.available, isTrue);
      expect(c.checked, isTrue);
      expect(c.taken, isFalse);
      expect(c.username, 'ahmed');
    });

    test('taken with suggestions (max 3, blanks dropped)', () {
      final c = UsernameCheck.fromJson({
        'username': 'ahmed',
        'available': false,
        'code': 'USERNAME_TAKEN',
        'suggestions': ['ahmed.1', '', 'ahmed_2', 'ahmed23', 'ahmed99'],
      });
      expect(c.taken, isTrue);
      expect(c.suggestions, ['ahmed.1', 'ahmed_2', 'ahmed23']);
    });

    test('reserved / invalid', () {
      expect(UsernameCheck.fromJson({'available': false, 'code': 'USERNAME_RESERVED'}).reserved, isTrue);
      final i = UsernameCheck.fromJson({'available': false, 'code': 'USERNAME_INVALID', 'message': 'rule'});
      expect(i.invalid, isTrue);
      expect(i.message, 'rule');
    });

    test('missing or odd keys never throw', () {
      final c = UsernameCheck.fromJson({'available': 'yes', 'code': 5, 'suggestions': 'x'}, requested: 'ahmed');
      expect(c.available, isFalse);
      expect(c.code, isNull);
      expect(c.suggestions, isEmpty);
      expect(c.username, 'ahmed');
      expect(c.taken, isTrue); // checked, not available, no code
      final empty = UsernameCheck.fromJson(const {}, requested: 'x');
      expect(empty.available, isFalse);
      expect(empty.checked, isTrue);
    });

    test('a body that is not a map is "can\'t check"', () {
      for (final body in [null, 'Not Found', 42, <Object>[]]) {
        final c = UsernameCheck.fromJson(body, requested: 'ahmed');
        expect(c.checked, isFalse, reason: '$body');
        expect(c.taken, isFalse);
      }
    });
  });

  group('UsernameError.from', () {
    test('409 taken with suggestions inside detail', () {
      final e = UsernameError.from(
        _err(409, 'USERNAME_TAKEN', {
          'detail': {'code': 'USERNAME_TAKEN', 'message': 'م', 'suggestions': ['a.1', 'a_2']},
        }),
        submitted: '@Ahmed',
      );
      expect(e, isNotNull);
      expect(e!.taken, isTrue);
      expect(e.username, 'ahmed');
      expect(e.suggestions, ['a.1', 'a_2']);
      expect(e.message, 'م');
    });

    test('suggestions next to detail', () {
      final e = UsernameError.from(
        _err(409, 'USERNAME_TAKEN', {
          'detail': {'code': 'USERNAME_TAKEN'},
          'suggestions': ['a.1'],
        }),
        submitted: 'a',
      );
      expect(e!.suggestions, ['a.1']);
    });

    test('reserved / invalid; any other code is not a username error', () {
      expect(UsernameError.from(_err(400, 'USERNAME_RESERVED', null), submitted: 'admin')!.reserved, isTrue);
      expect(UsernameError.from(_err(400, 'USERNAME_INVALID', 'raw text'), submitted: 'a.')!.code, 'USERNAME_INVALID');
      expect(UsernameError.from(_err(409, 'PHONE_TAKEN', null), submitted: 'a'), isNull);
      expect(UsernameError.from(_err(500, null, null), submitted: 'a'), isNull);
    });
  });

  test('usernameRouteMissing: bare 404 / 405 only', () {
    expect(usernameRouteMissing(_err(404, null, {'detail': 'Not Found'})), isTrue);
    expect(usernameRouteMissing(_err(405, null, null)), isTrue);
    expect(usernameRouteMissing(_err(404, null, {'detail': 'user not found'})), isFalse);
    expect(usernameRouteMissing(_err(429, null, null)), isFalse);
  });

  test('identifierLooksLikeEmail follows the server rule', () {
    expect(identifierLooksLikeEmail('a@b.io'), isTrue);
    expect(identifierLooksLikeEmail('@ahmed_1'), isFalse);
    expect(identifierLooksLikeEmail('ahmed_1'), isFalse);
    expect(identifierLooksLikeEmail('+201001234567'), isFalse);
    expect(identifierLooksLikeEmail(' @a@b.io'), isTrue);
  });

  group('identifierFieldSpec', () {
    String key(bool e, bool p, bool u) => identifierFieldSpec(email: e, phone: p, username: u).labelKey;

    test('without username: the screen\'s old combos', () {
      expect(key(true, false, false), 'email');
      expect(key(false, true, false), 'phone');
      expect(key(true, true, false), 'email_or_phone');
      expect(key(false, false, false), 'phone'); // no e-mail = phone field, as before
      expect(identifierFieldSpec(email: false, phone: true, username: false).keyboard, TextInputType.phone);
      expect(identifierFieldSpec(email: true, phone: false, username: false).keyboard, TextInputType.emailAddress);
    });

    test('with username: never a phone-only keyboard', () {
      expect(key(true, false, true), 'email_or_username');
      expect(key(false, true, true), 'phone_or_username');
      expect(key(true, true, true), 'email_phone_or_username');
      for (final e in [true, false]) {
        for (final p in [true, false]) {
          final s = identifierFieldSpec(email: e, phone: p, username: true);
          expect(s.keyboard, isNot(TextInputType.phone));
          expect(s.icon, IdentifierIcon.person);
        }
      }
    });
  });

  group('UserModel.username', () {
    Map<String, dynamic> base() => {'id': 1, 'name': 'A', 'gmail': 'a@b.io', 'role': 'student'};

    test('parsed, cached and read back', () {
      final u = UserModel.fromJson({...base(), 'username': 'ahmed_1'});
      expect(u.username, 'ahmed_1');
      expect(UserModel.fromJson(u.toJson()).username, 'ahmed_1');
    });

    test('an older server (no key), null or "" = none', () {
      expect(UserModel.fromJson(base()).username, isNull);
      expect(UserModel.fromJson({...base(), 'username': null}).username, isNull);
      expect(UserModel.fromJson({...base(), 'username': ''}).username, isNull);
      expect(UserModel.fromJson({...base(), 'username': 7}).username, isNull);
    });
  });
}
