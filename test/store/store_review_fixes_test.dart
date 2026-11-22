// The 5.R front review fixes (D-1339): the kept copies are wiped at sign-out (and pruned when a library row goes),
// a retry after a lost answer keeps the checkout's Idempotency-Key, buyers see a failure code's text, never the
// provider's raw reason, and a relative cover path is put on the API base.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/store/store_api.dart';
import 'package:flutter_education_app/features/store/store_checkout.dart';
import 'package:flutter_education_app/features/store/store_models.dart';
import 'package:flutter_education_app/features/store/store_vault_io.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

class _FakeStore extends StoreApi {
  _FakeStore() : super(deviceHeaders: () async => const {});

  final keys = <String>[];
  int _calls = 0;

  @override
  Future<StoreQuote> quote(List<int> itemIds) async => StoreQuote.fromJson({
        'lines': [
          {'item_id': 1, 'title': 'Book', 'net': 0, 'vat': 0, 'gross': 0},
        ],
        'subtotal': 0,
        'vat_amount': 0,
        'total': 0,
        'currency': 'EGP',
        'vat_percent': 0,
        'includes_vat': true,
      });

  @override
  Future<StoreOrderAnswer> order(List<int> itemIds, {required String method, required String idempotencyKey, String? provider}) async {
    keys.add(idempotencyKey);
    if (_calls++ == 0) throw TimeoutException('lost answer');
    return StoreOrderAnswer.fromJson({
      'order': {'id': 7, 'status': 'paid', 'method': 'free', 'currency': 'EGP', 'subtotal': 0, 'vat_amount': 0, 'total': 0},
    });
  }
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('StoreVault at sign-out', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('store_vault_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('wipeStoreFiles leaves no .enc and no keys', () async {
      final keys = <String, String>{'store_file_key_1': 'a', 'store_file_key_2': 'b', 'store_file_key_9': 'orphan', 'other': 'x'};
      final vault = StoreVault.test(dir: dir, keys: keys);
      File('${dir.path}/1.enc').writeAsBytesSync([1, 2, 3]);
      File('${dir.path}/2.enc').writeAsBytesSync([4, 5, 6]);
      expect(await vault.keptIds(), {1, 2});
      await MyAuthProvider.wipeStoreFiles(wipe: vault.wipe);
      expect(dir.listSync().where((e) => e.path.endsWith('.enc')), isEmpty);
      expect(keys.keys.where((k) => k.startsWith('store_file_key_')), isEmpty);
      expect(keys['other'], 'x'); // only the store's keys
    });

    test('prune drops the copies of items no longer owned', () async {
      final keys = <String, String>{'store_file_key_1': 'a', 'store_file_key_2': 'b'};
      final vault = StoreVault.test(dir: dir, keys: keys);
      File('${dir.path}/1.enc').writeAsBytesSync([1]);
      File('${dir.path}/2.enc').writeAsBytesSync([2]);
      await vault.prune({1});
      expect(await vault.keptIds(), {1});
      expect(keys.keys, ['store_file_key_1']);
    });
  });

  testWidgets('a retry after a lost answer sends the same Idempotency-Key', (tester) async {
    final api = _FakeStore();
    Future<void> frames() async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.pumpWidget(layoutHost(SingleChildScrollView(child: StoreCheckoutSheet(items: const [], api: api)), scale: 1));
    await frames();
    await tester.tap(find.byKey(const ValueKey('store.checkout.pay')));
    await frames();
    expect(api.keys, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('store.checkout.pay')));
    await frames();
    expect(api.keys, hasLength(2));
    expect(api.keys[1], api.keys[0]);
  });

  test('a definite server answer is a new attempt; a lost one is not', () {
    expect(storeDefiniteAnswer(ApiException(statusCode: 409, message: 'x')), isTrue);
    expect(storeDefiniteAnswer(ApiException(statusCode: 0, message: 'x')), isFalse);
    expect(storeDefiniteAnswer(TimeoutException('t')), isFalse);
  });

  test('buyers see the failure code text, never the raw reason', () {
    final o = StoreOrder.fromJson({'id': 1, 'status': 'failed', 'failure_code': 'amount_mismatch', 'failure_reason': 'amount_mismatch expected=11400 actual=1'});
    expect(o.failureCode, 'amount_mismatch');
    final text = storeFailureText(o.failureCode);
    expect(text.contains('11400'), isFalse);
    expect(text, contains('did not match'));
    expect(storeFailureText(null), contains('nothing was charged'));
  });

  test('a relative cover path is put on the API base', () {
    expect(storeCoverUrl('https://cdn.test/c.png'), 'https://cdn.test/c.png');
    expect(storeCoverUrl('/api/v1/org/files/tok'), endsWith('/api/v1/org/files/tok'));
    expect(storeCoverUrl('/api/v1/org/files/tok'), startsWith(AppConfig.baseUrl.replaceAll(RegExp(r'/$'), '')));
    expect(storeCoverUrl(null), '');
  });
}
