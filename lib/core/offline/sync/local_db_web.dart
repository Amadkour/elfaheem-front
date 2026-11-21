// The web build has no device database (D-1353): the offline-first layer stays online-only there.
import 'local_db.dart';

Future<LocalDb> openDeviceDb() async => MemoryLocalDb();
