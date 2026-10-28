// The @username, v2 (D-071): the identifier kind the app shares with the server's `usernames.classify`, the new
// UserModel fields (confirmation, change cooldown), the once-only prompt gate, the confirm route's bodies, the 429
// USERNAME_CHANGE_TOO_SOON error, and the people-row reader.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/design/app_username.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/username.dart';
import 'package:flutter_education_app/features/auth/username_confirm.dart';
import 'package:flutter_test/flutter_test.dart';

ApiException _err(int status, String? code, Object? body) =>
    ApiException(statusCode: status, message: 'x', code: code, body: body);

Map<String, dynamic> _user([Map<String, dynamic> extra = const {}]) => {
      'id': 7,
      'name': 'Ahmed',
      'gmail': 'ahmed@example.com',
      'role': 'student',
      ...extra,
    };

void main() {
  group('identifierKindOf (mirrors usernames.classify)', () {
    test('e-mail: an "@" left after stripping ONE leading "@"', () {
      expect(identifierKindOf('ahmed@example.com'), IdentifierKind.email);
      expect(identifierKindOf('  Ahmed@Example.com '), IdentifierKind.email);
      expect(identifierKindOf('@ahmed@example.com'), IdentifierKind.email);
      expect(identifierKindOf('@@ahmed'), IdentifierKind.email);
    });

    test('username: 3–30 of a–z 0–9 . _ with a letter, case-insensitive, one "@" allowed in front', () {
      expect(identifierKindOf('ahmed_1'), IdentifierKind.username);
      expect(identifierKindOf('@ahmed_1'), IdentifierKind.username);
      expect(identifierKindOf('Ahmed.Hamdy'), IdentifierKind.username);
      expect(identifierKindOf('abc'), IdentifierKind.username);
      expect(identifierKindOf('a' * 30), IdentifierKind.username);
      // the shape only: reserved / web-address-like names are still "username" (the lookup finds nobody)
      expect(identifierKindOf('admin'), IdentifierKind.username);
      expect(identifierKindOf('ahmed.com'), IdentifierKind.username);
      // an ID login with letters goes the username way first, as on the server
      expect(identifierKindOf('S2023001'), IdentifierKind.username);
    });

    test('phone / ID: everything else', () {
      expect(identifierKindOf('01012345678'), IdentifierKind.phoneOrId);
      expect(identifierKindOf('+201012345678'), IdentifierKind.phoneOrId);
      expect(identifierKindOf('+20 101 234 5678'), IdentifierKind.phoneOrId);
      expect(identifierKindOf('٠١٠١٢٣٤٥٦٧٨'), IdentifierKind.phoneOrId);
      expect(identifierKindOf('20231234'), IdentifierKind.phoneOrId); // digits only: no letter
      expect(identifierKindOf('ab'), IdentifierKind.phoneOrId); // too short
      expect(identifierKindOf('a' * 31), IdentifierKind.phoneOrId); // too long
      expect(identifierKindOf('أحمد'), IdentifierKind.phoneOrId); // not ASCII
      expect(identifierKindOf('ahmed hamdy'), IdentifierKind.phoneOrId); // a space
      expect(identifierKindOf(''), IdentifierKind.phoneOrId);
    });

    test('identifierLooksLikeEmail is the e-mail case of the same helper', () {
      expect(identifierLooksLikeEmail('a@b.co'), isTrue);
      expect(identifierLooksLikeEmail('@ahmed'), isFalse);
      expect(identifierLooksLikeEmail('0100'), isFalse);
    });
  });

  group('UserModel v2 fields', () {
    test('an older server (no keys): confirmed, no cooldown — never prompts', () {
      final u = UserModel.fromJson(_user({'username': 'ahmed'}));
      expect(u.usernameConfirmed, isTrue);
      expect(u.usernameChangeAvailableAt, isNull);
      expect(u.needsUsernameConfirm, isFalse);
      expect(u.usernameLockedUntil(), isNull);
    });

    test('an auto-filled name is not confirmed', () {
      final u = UserModel.fromJson(_user({'username': 'ahmed', 'username_confirmed': false}));
      expect(u.needsUsernameConfirm, isTrue);
      // no name → nothing to confirm
      expect(UserModel.fromJson(_user({'username_confirmed': false})).needsUsernameConfirm, isFalse);
      // a non-bool is treated like a missing key
      expect(UserModel.fromJson(_user({'username': 'a_b', 'username_confirmed': 'no'})).usernameConfirmed, isTrue);
    });

    test('username_change_available_at: ISO UTC, a naive value is UTC, junk is null', () {
      final z = UserModel.fromJson(_user({'username': 'ahmed', 'username_change_available_at': '2026-11-11T08:30:00Z'}));
      expect(z.usernameChangeAvailableAt, DateTime.utc(2026, 11, 11, 8, 30));
      final naive = UserModel.fromJson(_user({'username': 'ahmed', 'username_change_available_at': '2026-11-11T08:30:00'}));
      expect(naive.usernameChangeAvailableAt, DateTime.utc(2026, 11, 11, 8, 30));
      final off = UserModel.fromJson(_user({'username': 'ahmed', 'username_change_available_at': '2026-11-11T10:30:00+02:00'}));
      expect(off.usernameChangeAvailableAt, DateTime.utc(2026, 11, 11, 8, 30));
      for (final junk in [null, '', 'soon', 42]) {
        expect(UserModel.fromJson(_user({'username_change_available_at': junk})).usernameChangeAvailableAt, isNull,
            reason: '$junk');
      }
    });

    test('usernameLockedUntil: only while the cooldown runs and there is a name', () {
      final at = DateTime.utc(2026, 11, 11);
      final u = UserModel.fromJson(_user({'username': 'ahmed', 'username_change_available_at': at.toIso8601String()}));
      expect(u.usernameLockedUntil(DateTime.utc(2026, 11, 1)), at);
      expect(u.usernameLockedUntil(DateTime.utc(2026, 11, 12)), isNull);
      final none = UserModel.fromJson(_user({'username_change_available_at': at.toIso8601String()}));
      expect(none.usernameLockedUntil(DateTime.utc(2026, 11, 1)), isNull);
    });

    test('the cache round-trip keeps both fields', () {
      final u = UserModel.fromJson(_user({
        'username': 'ahmed',
        'username_confirmed': false,
        'username_change_available_at': '2026-11-11T08:30:00Z',
      }));
      final back = UserModel.fromJson(u.toJson());
      expect(back.usernameConfirmed, isFalse);
      expect(back.usernameChangeAvailableAt, DateTime.utc(2026, 11, 11, 8, 30));
    });
  });

  group('usernamePromptDue', () {
    final now = DateTime(2026, 10, 28, 12);
    final unconfirmed = UserModel.fromJson(_user({'username': 'ahmed', 'username_confirmed': false}));

    test('asks an unconfirmed name, never a confirmed / missing one', () {
      expect(usernamePromptDue(user: unconfirmed, featureOff: false, now: now), isTrue);
      expect(usernamePromptDue(user: UserModel.fromJson(_user({'username': 'ahmed'})), featureOff: false, now: now), isFalse);
      expect(usernamePromptDue(user: null, featureOff: false, now: now), isFalse);
    });

    test('the kill switch hides it', () {
      expect(usernamePromptDue(user: unconfirmed, featureOff: true, now: now), isFalse);
    });

    test('a dismissal waits 7 days', () {
      final day = const Duration(days: 1).inMilliseconds;
      final t = now.millisecondsSinceEpoch;
      expect(usernamePromptDue(user: unconfirmed, featureOff: false, snoozedAtMs: t - day, now: now), isFalse);
      expect(usernamePromptDue(user: unconfirmed, featureOff: false, snoozedAtMs: t - 6 * day, now: now), isFalse);
      expect(usernamePromptDue(user: unconfirmed, featureOff: false, snoozedAtMs: t - 7 * day, now: now), isTrue);
      expect(usernamePromptKey(7), 'username_confirm_snoozed_7');
    });
  });

  test('UsernameConfirmApi bodies: keep {} · change the normalized name · remove null', () {
    expect(UsernameConfirmApi.body(UsernameConfirmAction.keep), <String, dynamic>{});
    expect(UsernameConfirmApi.body(UsernameConfirmAction.change, username: ' @Ahmed.H '), {'username': 'ahmed.h'});
    final remove = UsernameConfirmApi.body(UsernameConfirmAction.remove);
    expect(remove.containsKey('username'), isTrue);
    expect(remove['username'], isNull);
    expect(UsernameConfirmApi.path, '/api/v1/auth/me/username/confirm');
  });

  group('USERNAME_CHANGE_TOO_SOON', () {
    final e = _err(429, 'USERNAME_CHANGE_TOO_SOON', {
      'detail': {'code': 'USERNAME_CHANGE_TOO_SOON', 'message': 'م', 'retry_at': '2026-11-11T08:30:00Z'},
    });

    test('UsernameError reads retry_at', () {
      final u = UsernameError.from(e, submitted: 'new_name');
      expect(u, isNotNull);
      expect(u!.tooSoon, isTrue);
      expect(u.taken, isFalse);
      expect(u.retryAt, DateTime.utc(2026, 11, 11, 8, 30));
      final bare = UsernameError.from(_err(429, 'USERNAME_CHANGE_TOO_SOON', null), submitted: 'x');
      expect(bare!.retryAt, isNull);
    });

    test('apiErrorText names the date in both languages, and works without one', () {
      final prev = AppConfig.lang;
      addTearDown(() => AppConfig.lang = prev);
      AppConfig.lang = 'en';
      expect(apiErrorText(e), contains('change it again on'));
      expect(apiErrorText(e), contains('2026'));
      expect(apiErrorText(_err(429, 'USERNAME_CHANGE_TOO_SOON', null)), contains('recently'));
      AppConfig.lang = 'ar';
      expect(apiErrorText(e), contains('مرة أخرى في'));
    });
  });

  test('usernameFrom: the row, then its user / student map; junk is null', () {
    expect(usernameFrom({'username': 'ahmed'}), 'ahmed');
    expect(usernameFrom({'username': '@ahmed'}), 'ahmed');
    expect(usernameFrom({'user': {'username': 'sara_1'}}), 'sara_1');
    expect(usernameFrom({'student': {'username': 'omar'}}), 'omar');
    expect(usernameFrom({'username': ''}), isNull);
    expect(usernameFrom({'username': 5}), isNull);
    expect(usernameFrom({'name': 'x'}), isNull);
    expect(usernameFrom(null), isNull);
    expect(usernameFrom('ahmed'), isNull);
  });
}
