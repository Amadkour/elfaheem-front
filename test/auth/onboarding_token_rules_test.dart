// Teacher onboarding token (docs/SECURITY_SCAN.md F2) and the MFA enrollment prompt, from the requirements:
// - every onboarding call carries `X-Onboarding-Token` (POST /auth/teacher-profile, /auth/teacher-documents
//   overview · upload-attachment/{email} · create · finalize, DELETE /auth/teacher-documents/{id});
// - no other route gets it; a header the caller set wins; no token → no header;
// - the token is forgotten at the end of onboarding (finalize) and when the server says so (`onboarding_token: null`);
// - only a path on the API itself matches (an absolute URL to another host never gets the token);
// - a 403 `mfa_enrollment_required` opens the MFA page, never twice at once, never for guests / view-as / the MFA
//   routes themselves; after the user backs out it comes back on a later refused call (after a short pause).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/auth/teacher_document_provider.dart';
import 'package:flutter_education_app/features/auth/teacher_onboarding_token.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what the provider hands to ApiClient (ApiClient is a singleton; this stands in through its interface).
class _RecordingApi implements ApiClient {
  final calls = <(Symbol, String, Map<String, String>?)>[];

  @override
  dynamic noSuchMethod(Invocation i) {
    final path = i.positionalArguments.isEmpty ? '' : '${i.positionalArguments.first}';
    calls.add((i.memberName, path, i.namedArguments[#headers] as Map<String, String>?));
    if (path.endsWith('/finalize')) {
      return Future<dynamic>.value(<String, dynamic>{'requirements': [], 'custom_documents': [], 'all_required_fulfilled': true});
    }
    return Future<dynamic>.value(<String, dynamic>{});
  }
}

const _tok = 'onb.jwt.value';

void main() {
  tearDown(TeacherOnboardingToken.clear);

  group('which routes are onboarding routes', () {
    // Written from the server's route list (test/contract/api_paths.json) and back/routers/teacher_documents_router.py
    // + routers/auth.py: the routes that call `onboarding_user` (+ delete, which the app must also send it on).
    const onboarding = {
      'POST /api/v1/auth/teacher-profile',
      'POST /api/v1/auth/teacher-documents',
      'POST /api/v1/auth/teacher-documents/overview',
      'POST /api/v1/auth/teacher-documents/finalize',
      'POST /api/v1/auth/teacher-documents/upload-attachment/{email}',
      'DELETE /api/v1/auth/teacher-documents/{document_id:int}',
    };

    String concrete(String template) => template
        .replaceAll(RegExp(r'\{[a-z_]+:int\}'), '42')
        .replaceAll('{email}', 'teacher@x.io');

    test('every teacher-profile / teacher-documents route of the server snapshot is classified as specified', () {
      final snap = jsonDecode(File('test/contract/api_paths.json').readAsStringSync()) as Map<String, dynamic>;
      final routes = (snap['core'] as List).cast<String>().where(
          (r) => r.contains('/api/v1/auth/teacher-documents') || r.contains('/api/v1/auth/teacher-profile'));
      expect(routes, isNotEmpty);
      for (final o in onboarding) {
        expect(routes, contains(o), reason: 'server route list changed: $o');
      }
      for (final r in routes) {
        final path = concrete(r.split(' ').last);
        expect(isTeacherOnboardingPath(path), onboarding.contains(r), reason: r);
      }
    });

    test('query strings and a trailing slash do not change the answer; other routes never match', () {
      expect(isTeacherOnboardingPath('/api/v1/auth/teacher-documents/overview?lang=ar'), isTrue);
      expect(isTeacherOnboardingPath('/api/v1/auth/teacher-profile/'), isTrue);
      expect(isTeacherOnboardingPath('/api/v1/auth/teacher-profile-extras'), isFalse);
      expect(isTeacherOnboardingPath('/api/v1/auth/teacher-documents/required-types'), isFalse);
      expect(isTeacherOnboardingPath('/api/v1/auth/teacher-documents/7/public'), isFalse);
      expect(isTeacherOnboardingPath('/api/v1/admin/required-documents/3'), isFalse);
      expect(isTeacherOnboardingPath('/api/v1/auth/login'), isFalse);
      expect(isTeacherOnboardingPath('/api/v1/auth/teacher-documents/upload-attachment/a@b.c/x'), isFalse);
    });

    test('only a path on the API itself matches: an absolute URL to any host never gets the token (R3 L3)', () {
      expect(isTeacherOnboardingPath('api/v1/auth/teacher-profile'), isTrue);
      expect(isTeacherOnboardingPath('https://evil.example/api/v1/auth/teacher-profile'), isFalse);
      expect(isTeacherOnboardingPath('https://evil.example/x/api/v1/auth/teacher-documents/finalize'), isFalse);
      expect(isTeacherOnboardingPath('/proxy/api/v1/auth/teacher-profile'), isFalse);
      expect(isTeacherOnboardingPath('//evil.example/api/v1/auth/teacher-profile'), isFalse);
      expect(onboardingHeaderFor('https://evil.example/api/v1/auth/teacher-profile', _tok, {}), isEmpty);
    });
  });

  group('header injection', () {
    test('an onboarding route gets the token; a non-onboarding route or no token gets nothing', () {
      expect(onboardingHeaderFor('/api/v1/auth/teacher-profile', _tok, {}), {'X-Onboarding-Token': _tok});
      expect(onboardingHeaderFor('/api/v1/auth/teacher-documents/12', _tok, {}), {'X-Onboarding-Token': _tok});
      expect(onboardingHeaderFor('/api/v1/courses', _tok, {}), isEmpty);
      expect(onboardingHeaderFor('/api/v1/auth/teacher-profile', null, {}), isEmpty);
      expect(onboardingHeaderFor('/api/v1/auth/teacher-profile', '', {}), isEmpty);
    });

    test('a header the caller set wins (any case)', () {
      expect(onboardingHeaderFor('/api/v1/auth/teacher-profile', _tok, {'x-onboarding-token': 'other'}), isEmpty);
      expect(onboardingHeaderFor('/api/v1/auth/teacher-profile', _tok, {'X-Onboarding-Token': 'other'}), isEmpty);
    });
  });

  group('token store', () {
    test('kept from an answer, forgotten by onboarding_token: null, untouched by answers without the field', () {
      TeacherOnboardingToken.readFrom({'onboarding_token': _tok});
      expect(TeacherOnboardingToken.headers, {'X-Onboarding-Token': _tok});
      TeacherOnboardingToken.readFrom({'user': {}});
      expect(TeacherOnboardingToken.value, _tok);
      TeacherOnboardingToken.readFrom('not a map');
      expect(TeacherOnboardingToken.value, _tok);
      TeacherOnboardingToken.readFrom({'onboarding_token': null});
      expect(TeacherOnboardingToken.value, isNull);
      expect(TeacherOnboardingToken.headers, isNull);
    });
  });

  group('documents provider', () {
    test('overview, finalize and delete send the token; finalize ends onboarding and forgets it', () async {
      TeacherOnboardingToken.readFrom({'onboarding_token': _tok});
      final api = _RecordingApi();
      final p = TeacherDocumentProvider(api: api);

      expect(await p.deleteDocument(5, email: 't@x.io'), isTrue);
      final del = api.calls.firstWhere((c) => c.$1 == #delete);
      expect(del.$2, '/api/v1/auth/teacher-documents/5');
      expect(del.$3, {'X-Onboarding-Token': _tok});
      final overview = api.calls.firstWhere((c) => c.$2.endsWith('/overview'));
      expect(overview.$3, {'X-Onboarding-Token': _tok});

      expect(await p.finalizeRegistration(email: 't@x.io'), isTrue);
      final fin = api.calls.firstWhere((c) => c.$2.endsWith('/finalize'));
      expect(fin.$3, {'X-Onboarding-Token': _tok});
      expect(TeacherOnboardingToken.value, isNull, reason: 'onboarding is complete');
      p.dispose();
    });

    test('the upload call passes the token too (source check: the multipart upload is behind a file picker)', () {
      final src = File('lib/features/auth/teacher_document_provider.dart').readAsStringSync();
      final upload = RegExp(r"postMultipart\(\s*'/api/v1/auth/teacher-documents/upload-attachment/\$email',[\s\S]*?\);")
          .firstMatch(src);
      expect(upload, isNotNull);
      expect(upload!.group(0), contains('headers: TeacherOnboardingToken.headers'));
    });
  });

  group('MFA enrollment prompt', () {
    bool open({
      int? status = 403,
      String? code = 'mfa_enrollment_required',
      String path = '/api/v1/courses',
      bool needsAuth = true,
      bool guest = false,
      bool viewingAs = false,
      bool pageOpen = false,
      Duration? sinceDismissed,
    }) =>
        shouldOpenMfaEnrollment(
            status: status, code: code, path: path, needsAuth: needsAuth, guest: guest, viewingAs: viewingAs,
            pageOpen: pageOpen, sinceDismissed: sinceDismissed);

    test('opens on a 403 mfa_enrollment_required of a signed-in call', () => expect(open(), isTrue));

    test('never for guests, view-as, public calls, other codes or statuses', () {
      expect(open(guest: true), isFalse);
      expect(open(viewingAs: true), isFalse);
      expect(open(needsAuth: false), isFalse);
      expect(open(code: 'DEVICE_MISMATCH'), isFalse);
      expect(open(code: null), isFalse);
      expect(open(status: 401), isFalse);
      expect(open(status: 423), isFalse);
    });

    test('never stacks a second page and never from the MFA routes (no loop)', () {
      expect(open(pageOpen: true), isFalse);
      expect(open(path: '/api/v1/auth/mfa/status'), isFalse);
      expect(open(path: '/api/v1/auth/mfa/setup'), isFalse);
    });

    test('backing out does not lose the requirement: the page comes back after the pause (R3 M2)', () {
      expect(open(sinceDismissed: Duration.zero), isFalse);
      expect(open(sinceDismissed: const Duration(seconds: 5)), isFalse);
      expect(open(sinceDismissed: mfaPromptCooldown - const Duration(milliseconds: 1)), isFalse);
      expect(open(sinceDismissed: mfaPromptCooldown), isTrue);
      expect(open(sinceDismissed: const Duration(minutes: 10)), isTrue);
      // still never while it is on screen, nor for guests / view-as
      expect(open(sinceDismissed: const Duration(minutes: 10), pageOpen: true), isFalse);
      expect(open(sinceDismissed: const Duration(minutes: 10), viewingAs: true), isFalse);
    });
  });
}
