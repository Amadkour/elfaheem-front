// S14: a hung server must not hold a spinner for an hour. Every call through the app's one Dio waits 20 s to
// connect and 30 s for the answer; only uploads (FormData, a byte stream) and binary downloads keep the long
// transfer timeouts, whether they go through ApiClient's helpers or straight through `ApiClient().dio`.
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';

/// Records the options each request reached the adapter with.
class _Capture implements HttpClientAdapter {
  final seen = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    seen.add(o);
    return ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Capture cap;
  late FakeApi fake;

  setUp(() {
    mockRequestPlugins();
    // FakeApi.install takes the encryption interceptor out; the capture adapter then replaces FakeApi itself
    fake = FakeApi(const {}, latency: Duration.zero)..install();
    cap = _Capture();
    ApiClient.instance.dio.httpClientAdapter = cap;
  });

  tearDown(() => fake.uninstall());

  test('the client defaults: 20 s to connect, 30 s for the answer', () {
    final o = ApiClient.instance.dio.options;
    expect(o.connectTimeout, kApiConnectTimeout);
    expect(o.receiveTimeout, kApiReceiveTimeout);
    expect(kApiConnectTimeout, const Duration(seconds: 20));
    expect(kApiReceiveTimeout, const Duration(seconds: 30));
  });

  test('a JSON call and a call straight through dio keep the short timeouts', () async {
    await ApiClient.instance.get('/api/v1/me/home');
    await ApiClient.instance.post('/api/v1/x', body: {'a': 1});
    await ApiClient.instance.dio.get('/api/v1/y');
    for (final o in cap.seen) {
      expect(o.connectTimeout, kApiConnectTimeout, reason: o.path);
      expect(o.receiveTimeout, kApiReceiveTimeout, reason: o.path);
    }
    expect(cap.seen, hasLength(3));
  });

  test('uploads and binary downloads get the long transfer timeouts', () async {
    await ApiClient.instance.postForm('/api/v1/upload', fields: {'a': '1'}, fileField: 'f', fileName: 'r.png', fileBytes: Uint8List(4));
    await ApiClient.instance.dio.post('/api/v1/direct-upload', data: FormData.fromMap({'b': '2'}));
    await ApiClient.instance.getBytes('/api/v1/file.pdf');
    expect(cap.seen, hasLength(3));
    for (final o in cap.seen) {
      expect(o.receiveTimeout, kApiTransferTimeout, reason: o.path);
      expect(o.sendTimeout, kApiTransferTimeout, reason: o.path); // the VM test host is not web
      expect(o.connectTimeout, kApiConnectTimeout, reason: o.path);
    }
  });

  test('a caller that asked for its own receive timeout keeps it', () async {
    await ApiClient.instance.dio.get('/api/v1/z', options: Options(receiveTimeout: const Duration(seconds: 5)));
    expect(cap.seen.single.receiveTimeout, const Duration(seconds: 5));
  });
}
