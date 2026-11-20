// lib/features/store/store_vault.dart — where a bought file is kept on this device (D-1333). Phones and desktops get
// the encrypted copy (store_vault_io.dart: the offline-video scheme of lib/core/offline/, "EFV1" | nonce | AES-CTR,
// the key in the Keystore / Keychain); the web keeps nothing and opens the short link (store_vault_stub.dart).
library;

export 'store_vault_stub.dart' if (dart.library.io) 'store_vault_io.dart';
