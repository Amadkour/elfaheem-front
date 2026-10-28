// lib/features/auth/username.dart
//
// The optional, unique @username (D-071). The server is the authority; the app mirrors its rules so the person sees
// what is wrong while typing, then asks the server whether the name is free.
//
//   UsernameRules           normalize (trim, one leading "@", lowercase) · problemOf → the rule that failed · codeOf
//   UsernameInputFormatter  lowercases and drops every character a username can never hold
//   UsernameCheck           GET /api/v1/auth/username/check, parsed defensively (missing keys never throw)
//   UsernameError           a USERNAME_* error of register / PUT /auth/me, with the server's suggestions
//   UsernameApi.check       the check call; an older server's bare 404 / 405 = "can't check", the submit decides
//   identifierFieldSpec     label / keyboard of the sign-in identifier field (e-mail · phone · username)
//
// Pure apart from UsernameApi; tests: test/auth/username_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';

/// Kill switch: hides the username field (sign-up, profile) and the "or username" wording at login.
const kUsernameFeatureKey = 'auth.username';

const _codeInvalid = 'USERNAME_INVALID';
const _codeReserved = 'USERNAME_RESERVED';
const _codeTaken = 'USERNAME_TAKEN';

/// The rule a username breaks, in the order the app checks them.
enum UsernameProblem {
  reserved,
  badChars,
  tooShort,
  tooLong,
  noLetter,
  dotEdge,
  doubleDot,
  startsWww,
  domainSuffix,
}

/// The username rules of the shared contract, mirrored from the server (`../back`). Keep the lists here only.
class UsernameRules {
  UsernameRules._();

  static const minLength = 3;
  static const maxLength = 30;

  /// Refused whatever the case.
  static const reserved = <String>{
    'admin',
    'administrator',
    'root',
    'system',
    'support',
    'help',
    'security',
    'official',
    'nextbrain',
    'elfaheem',
    'api',
    'www',
    'mail',
    'owner',
    'moderator',
    'staff',
    'null',
    'undefined',
    'me',
    'you',
    'login',
    'register',
    'settings',
  };

  /// `name.com`, `name.io` … (a dot + one of these at the end) look like a domain and are refused.
  static const domainSuffixes = <String>[
    'com',
    'net',
    'org',
    'io',
    'app',
    'site',
    'co',
    'me',
    'info',
    'edu',
    'gov',
    'dev',
    'ai',
  ];

  static final _allowed = RegExp(r'^[a-z0-9._]+$');
  static final _letter = RegExp(r'[a-z]');

  /// Trim, strip ONE leading "@", lowercase — what the server stores.
  static String normalize(String raw) {
    var s = raw.trim();
    if (s.startsWith('@')) s = s.substring(1);
    return s.toLowerCase();
  }

  /// The first rule [raw] breaks, or null when it is a valid username. An empty value is [UsernameProblem.tooShort].
  static UsernameProblem? problemOf(String raw) {
    final s = normalize(raw);
    if (reserved.contains(s)) return UsernameProblem.reserved;
    if (s.isNotEmpty && !_allowed.hasMatch(s)) return UsernameProblem.badChars;
    if (s.length < minLength) return UsernameProblem.tooShort;
    if (s.length > maxLength) return UsernameProblem.tooLong;
    if (!_letter.hasMatch(s)) return UsernameProblem.noLetter;
    if (s.startsWith('.') || s.endsWith('.')) return UsernameProblem.dotEdge;
    if (s.contains('..')) return UsernameProblem.doubleDot;
    if (s.startsWith('www')) return UsernameProblem.startsWww;
    if (domainSuffixes.any((d) => s.endsWith('.$d'))) {
      return UsernameProblem.domainSuffix;
    }
    return null;
  }

  /// The server's code for [raw]: null (valid), USERNAME_RESERVED or USERNAME_INVALID.
  static String? codeOf(String raw) => switch (problemOf(raw)) {
        null => null,
        UsernameProblem.reserved => _codeReserved,
        _ => _codeInvalid,
      };

  /// True when [raw] is a valid username.
  static bool isValid(String raw) => problemOf(raw) == null;

  /// Translation key of the sentence that explains [p].
  static String problemKey(UsernameProblem p) => switch (p) {
        UsernameProblem.reserved => 'username_reserved',
        UsernameProblem.badChars => 'username_rule_chars',
        UsernameProblem.tooShort => 'username_rule_short',
        UsernameProblem.tooLong => 'username_rule_long',
        UsernameProblem.noLetter => 'username_rule_letter',
        UsernameProblem.dotEdge => 'username_rule_dot_edge',
        UsernameProblem.doubleDot => 'username_rule_double_dot',
        UsernameProblem.startsWww => 'username_rule_www',
        UsernameProblem.domainSuffix => 'username_rule_domain',
      };
}

/// Lowercases what is typed or pasted and drops every character a username can never hold (Arabic letters, spaces,
/// "@", "-" …), keeping the cursor where it was. The length cap is a separate LengthLimitingTextInputFormatter.
class UsernameInputFormatter extends TextInputFormatter {
  const UsernameInputFormatter();

  static final _keep = RegExp(r'[a-z0-9._]');

  static String clean(String s) =>
      s.toLowerCase().split('').where(_keep.hasMatch).join();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = clean(newValue.text);
    if (text == newValue.text) return newValue;
    int at(int offset) {
      if (offset < 0) return offset;
      final end = offset > newValue.text.length ? newValue.text.length : offset;
      return clean(newValue.text.substring(0, end)).length;
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: at(newValue.selection.baseOffset),
        extentOffset: at(newValue.selection.extentOffset),
      ),
    );
  }
}

/// Answer of GET /api/v1/auth/username/check.
class UsernameCheck {
  const UsernameCheck({
    required this.username,
    required this.available,
    this.code,
    this.message,
    this.suggestions = const [],
    this.checked = true,
  });

  /// "Can't check now" (an older server without the route, a throttle, no network): the submit decides.
  const UsernameCheck.unchecked(this.username)
      : available = false,
        code = null,
        message = null,
        suggestions = const [],
        checked = false;

  /// The normalized name the server looked at.
  final String username;
  final bool available;

  /// null · USERNAME_INVALID · USERNAME_RESERVED · USERNAME_TAKEN
  final String? code;

  /// The server's sentence (it names the rule for USERNAME_INVALID).
  final String? message;

  /// Free, valid variants (≤ 3), only when taken / reserved.
  final List<String> suggestions;

  /// False when the server could not be asked.
  final bool checked;

  bool get taken => code == _codeTaken || (checked && !available && code == null);
  bool get reserved => code == _codeReserved;
  bool get invalid => code == _codeInvalid;

  /// Never throws: a missing or odd key falls back to "not available, no code" — and a body that is not a map at
  /// all to [UsernameCheck.unchecked].
  factory UsernameCheck.fromJson(Object? json, {String requested = ''}) {
    if (json is! Map) return UsernameCheck.unchecked(requested);
    final name = json['username'];
    final code = json['code'];
    final message = json['message'];
    return UsernameCheck(
      username: name is String && name.isNotEmpty ? name : requested,
      available: json['available'] == true,
      code: code is String && code.isNotEmpty ? code : null,
      message: message is String && message.trim().isNotEmpty ? message : null,
      suggestions: suggestionsFrom(json['suggestions']),
    );
  }
}

/// At most 3 non-empty strings from a JSON value (anything else → empty).
List<String> suggestionsFrom(Object? v) {
  if (v is! List) return const [];
  return v
      .whereType<Object>()
      .map((e) => e.toString().trim())
      .where((s) => s.isNotEmpty)
      .take(3)
      .toList();
}

/// A USERNAME_* error from POST /auth/register or PUT /auth/me, kept for the field that showed [username].
class UsernameError {
  const UsernameError({
    required this.username,
    required this.code,
    this.message,
    this.suggestions = const [],
  });

  /// The normalized username that was submitted.
  final String username;
  final String code;
  final String? message;
  final List<String> suggestions;

  bool get taken => code == _codeTaken;
  bool get reserved => code == _codeReserved;

  static const codes = {_codeInvalid, _codeReserved, _codeTaken};

  /// Null unless [e] is a username error. `suggestions` is read from `detail` and, for a server that puts it next
  /// to `detail`, from the top of the body.
  static UsernameError? from(ApiException e, {required String submitted}) {
    if (!codes.contains(e.code)) return null;
    final body = ApiException.asMap(e.body);
    final detail = body?['detail'];
    var suggestions =
        detail is Map ? suggestionsFrom(detail['suggestions']) : <String>[];
    if (suggestions.isEmpty) suggestions = suggestionsFrom(body?['suggestions']);
    final message = detail is Map ? detail['message'] : null;
    return UsernameError(
      username: UsernameRules.normalize(submitted),
      code: e.code!,
      message: message is String && message.trim().isNotEmpty ? message : null,
      suggestions: suggestions,
    );
  }
}

/// True for FastAPI's bare 404 "Not Found" or a 405: the server has no check route yet.
bool usernameRouteMissing(ApiException e) =>
    e.statusCode == 405 ||
    (e.statusCode == 404 && ApiException.asMap(e.body)?['detail'] == 'Not Found');

class UsernameApi {
  UsernameApi._();

  /// Asks the server whether [raw] is free. Never throws: a missing route, a throttle (429) or a network error is
  /// [UsernameCheck.unchecked] — the register / save call is still checked by the server.
  static Future<UsernameCheck> check(String raw, {ApiClient? api}) async {
    final requested = UsernameRules.normalize(raw);
    try {
      final r = await (api ?? ApiClient()).get(
        '/api/v1/auth/username/check',
        queryParams: {'username': requested},
        auth: false,
      );
      return UsernameCheck.fromJson(r, requested: requested);
    } catch (_) {
      return UsernameCheck.unchecked(requested);
    }
  }
}

/// An identifier typed at sign-in is an e-mail when, after one leading "@" is stripped, it still holds an "@"
/// (the server's rule) — so "@ahmed_1" is a username, not an e-mail.
bool identifierLooksLikeEmail(String raw) {
  var s = raw.trim();
  if (s.startsWith('@')) s = s.substring(1);
  return s.contains('@');
}

/// What the single sign-in identifier field shows for the identifiers the admin allows.
enum IdentifierIcon { email, phone, person }

extension IdentifierIconData on IdentifierIcon {
  IconData get data => switch (this) {
        IdentifierIcon.email => Icons.email_outlined,
        IdentifierIcon.phone => Icons.phone_outlined,
        IdentifierIcon.person => Icons.person_outline,
      };
}

class IdentifierFieldSpec {
  const IdentifierFieldSpec(this.labelKey, this.keyboard, this.icon);

  /// Translation key of the label / hint.
  final String labelKey;
  final TextInputType keyboard;
  final IdentifierIcon icon;
}

/// [email] / [phone] from `login_identifiers`, [username] = `username_login` (and the kill switch is on).
/// Without e-mail the field is a phone field, as the login screen always did (the server keeps at least one).
IdentifierFieldSpec identifierFieldSpec({
  required bool email,
  required bool phone,
  required bool username,
}) {
  final e = email;
  final p = phone || !email;
  if (!username) {
    if (e && p) {
      return const IdentifierFieldSpec(
          'email_or_phone', TextInputType.text, IdentifierIcon.person);
    }
    if (p) {
      return const IdentifierFieldSpec(
          'phone', TextInputType.phone, IdentifierIcon.phone);
    }
    return const IdentifierFieldSpec(
        'email', TextInputType.emailAddress, IdentifierIcon.email);
  }
  if (e && p) {
    return const IdentifierFieldSpec(
        'email_phone_or_username', TextInputType.text, IdentifierIcon.person);
  }
  if (p) {
    return const IdentifierFieldSpec(
        'phone_or_username', TextInputType.text, IdentifierIcon.person);
  }
  // the e-mail keyboard has letters, digits, ".", "_" and "@" — right for a username too
  return const IdentifierFieldSpec(
      'email_or_username', TextInputType.emailAddress, IdentifierIcon.person);
}
