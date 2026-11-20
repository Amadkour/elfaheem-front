// lib/features/store/store_vault_stub.dart — the web: no file is kept, the library opens the short link instead.
library;

import 'dart:typed_data';

class StoreVault {
  StoreVault._();

  static final StoreVault instance = StoreVault._();

  /// False on the web: the library opens the download link in the browser.
  bool get available => false;

  Future<bool> has(int itemId) async => false;

  Future<void> save(int itemId, Uri url, {String sha256 = '', void Function(double progress)? onProgress}) =>
      throw UnsupportedError('No local store files on the web');

  Future<Uint8List> read(int itemId) => throw UnsupportedError('No local store files on the web');

  Future<void> remove(int itemId) async {}

  Future<void> wipe() async {}
}
