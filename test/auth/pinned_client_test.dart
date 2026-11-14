// S2 / F3 (D-946): the encryption handshake and the retry after `encryption_session_expired` go through pinned
// clients — the handshake through ApiClient's bare pinned Dio, the retry back through the owning (pinned) Dio so
// every interceptor runs again — and a refused pin on our host reads "update the app".
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/cert_pin.dart';
import 'package:flutter_education_app/core/version_check_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

/// Answers every request with [reply] and records what it was asked.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.reply);

  final ({int status, Map<String, dynamic> body}) Function(RequestOptions o) reply;
  final seen = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    seen.add(options);
    final r = reply(options);
    return ResponseBody.fromString(jsonEncode(r.body), r.status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late String serverPublic;
  var handshakes = 0;

  setUpAll(() async {
    final pair = await X25519().newKeyPair();
    serverPublic = base64Encode((await pair.extractPublicKey()).bytes);
  });

  /// The bare client: only ever asked for handshakes; each gives a new session id.
  ({Dio dio, _FakeAdapter adapter}) bare() {
    final a = _FakeAdapter((o) {
      handshakes++;
      return (status: 200, body: {'server_public_key': serverPublic, 'session_id': 's$handshakes'});
    });
    return (dio: Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = a, adapter: a);
  }

  /// The owning client with the encryption interceptor first and a stand-in for the auth interceptor after it.
  ({Dio dio, _FakeAdapter adapter}) owner(Dio bareDio, ({int status, Map<String, dynamic> body}) Function(RequestOptions o) reply,
      {required String Function() token}) {
    final a = _FakeAdapter(reply);
    final d = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = a;
    d.interceptors.add(ApiClient.debugEncryptionInterceptor(bare: () => bareDio, owner: () => d));
    d.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      o.headers['Authorization'] = 'Bearer ${token()}';
      h.next(o);
    }));
    return (dio: d, adapter: a);
  }

  setUp(() => handshakes = 0);

  group('pinned clients', () {
    test('the main client and the bare handshake client both carry the pinned HttpClient factory', () {
      expect(ApiClient.debugIsPinned(ApiClient.instance.dio), isTrue);
      expect(ApiClient.debugIsPinned(ApiClient.instance.debugBareDio), isTrue);
      expect(ApiClient.instance.debugBareDio.interceptors.whereType<InterceptorsWrapper>(), isEmpty);
      expect(ApiClient.debugIsPinned(Dio()), isFalse);
    });

    test('the handshake goes through the bare client, never through the owning one', () async {
      final b = bare();
      final o = owner(b.dio, (_) => (status: 200, body: {'ok': true}), token: () => 't');
      await o.dio.post('/api/v1/x', data: {'a': 1});
      expect(handshakes, 1);
      expect(b.adapter.seen.single.path, '/api/v1/security/handshake');
      expect(o.adapter.seen.map((r) => r.path), ['/api/v1/x']);
      final sent = o.adapter.seen.single;
      expect(sent.headers['X-Enc-Session'], 's1');
      expect((sent.data as Map).keys, containsAll(['n', 'ct']));
    });

    test('session expired: one new handshake, the retry runs the owning chain again (fresh bearer, new session)', () async {
      final b = bare();
      var token = 'old';
      var calls = 0;
      final o = owner(b.dio, (r) {
        calls++;
        if (calls == 1) {
          token = 'fresh'; // the stand-in auth interceptor must put THIS on the retry
          return (status: 400, body: {'error': 'encryption_session_expired'});
        }
        return (status: 200, body: {'ok': true});
      }, token: () => token);

      final res = await o.dio.post('/api/v1/x', data: {'a': 1});
      expect(res.data, {'ok': true});
      expect(handshakes, 2);
      expect(b.adapter.seen.every((r) => r.path == '/api/v1/security/handshake'), isTrue);
      expect(o.adapter.seen.length, 2);
      final retry = o.adapter.seen[1];
      expect(retry.headers['X-Enc-Session'], 's2');
      expect(retry.headers['Authorization'], 'Bearer fresh');
      expect(retry.extra['_encRetried'], isTrue);
      expect((retry.data as Map).keys, containsAll(['n', 'ct'])); // re-encrypted from the plaintext, not twice
    });

    test('a second expiry on the retry is passed on, not retried again', () async {
      final b = bare();
      final o = owner(b.dio, (_) => (status: 400, body: {'error': 'encryption_session_expired'}), token: () => 't');
      await expectLater(o.dio.post('/api/v1/x', data: {'a': 1}), throwsA(isA<DioException>()));
      expect(o.adapter.seen.length, 2);
      expect(handshakes, 2);
    });

    test('the retry\'s own error surfaces, not the stale expiry', () async {
      final b = bare();
      var calls = 0;
      final o = owner(b.dio, (_) {
        calls++;
        return calls == 1
            ? (status: 400, body: {'error': 'encryption_session_expired'})
            : (status: 403, body: {'detail': {'code': 'DEVICE_MISMATCH', 'message': 'm'}});
      }, token: () => 't');
      try {
        await o.dio.get('/api/v1/x');
        fail('should throw');
      } on DioException catch (e) {
        expect(e.response?.statusCode, 403);
      }
    });
  });

  group('update message on a refused pin', () {
    setUp(CertPin.debugReset);
    tearDown(CertPin.debugReset);

    DioException handshakeFailure() => DioException(
          requestOptions: RequestOptions(path: '/api/v1/x'),
          error: const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
        );

    test('our host showed an unknown key: the error says "update the app"', () {
      CertPin.updateRequired = true;
      final e = ApiException.fromDio(handshakeFailure());
      expect(e.code, kPinUpdateCode);
      expect(e.message, translate('tls_pin_update_required'));
    });

    test('any other TLS failure keeps the network message', () {
      final e = ApiException.fromDio(handshakeFailure());
      expect(e.code, isNot(kPinUpdateCode));
      expect(e.message, ApiMessages.network);
    });

    test('the version check blocks without the server: pin first, then Remote Config', () {
      const pinErr = ApiException(statusCode: 0, type: ApiErrorType.network, message: 'm', code: kPinUpdateCode);
      expect(updateBlockWithoutServer(serverAnswer: pinErr, pinFlag: false, rcMinBuild: 0, installedBuild: 40),
          'tls_pin_update_required');
      expect(updateBlockWithoutServer(serverAnswer: null, pinFlag: true, rcMinBuild: 0, installedBuild: 40),
          'tls_pin_update_required');
      expect(updateBlockWithoutServer(serverAnswer: null, pinFlag: false, rcMinBuild: 41, installedBuild: 40),
          'app_update_required_generic');
      expect(updateBlockWithoutServer(serverAnswer: null, pinFlag: false, rcMinBuild: 40, installedBuild: 40), isNull);
      expect(updateBlockWithoutServer(serverAnswer: null, pinFlag: false, rcMinBuild: 0, installedBuild: 40), isNull);
      // a readable server answer wins over Remote Config
      expect(updateBlockWithoutServer(serverAnswer: <String, dynamic>{}, pinFlag: false, rcMinBuild: 99, installedBuild: 40),
          isNull);
    });

    testWidgets('the blocking dialog shows the reason and no "Later"', (tester) async {
      for (final lang in ['ar', 'en']) {
        AppConfig.lang = lang;
        await expectNoLayoutErrors(
          tester,
          () => UpdateDialog(
            force: true,
            version: '',
            source: 'custom',
            message: translate('tls_pin_update_required'),
            onUpdate: () {},
            onLater: () {},
          ),
        );
      }
      await tester.pumpWidget(layoutHost(
          UpdateDialog(force: true, version: '', source: 'custom', message: 'why', onUpdate: () {}, onLater: () {}),
          scale: 1));
      expect(find.text('why'), findsOneWidget);
      expect(find.text(translate('get_app_update_later')), findsNothing);
    });
  });
}
