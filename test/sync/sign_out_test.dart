// A sign-out the person chose never silently deletes unsent offline work (7.R): online, the outbox is sent first
// and nothing is asked when it empties; offline (or the push failed), the person confirms the count and Cancel
// keeps them signed in.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/offline/sync/local_db.dart';
import 'package:flutter_education_app/core/offline/sync/outbox.dart';
import 'package:flutter_education_app/core/offline/sync/sync_status.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MemoryLocalDb db;
  late Outbox box;
  setUp(() async {
    db = MemoryLocalDb();
    box = Outbox(open: () async => db, userId: () async => 7, available: () => true, viewingAs: () => false, status: SyncStatus());
    await box.enqueue(id: 'op-left-0001', kind: SyncKinds.gamePlay, payload: {'game_id': 1});
  });

  test('online: the outbox is sent first; once it is empty nothing is asked', () async {
    var synced = 0;
    final asked = <int>[];
    final ok = await MyAuthProvider.settleUnsentWork(
      outbox: box,
      online: () => true,
      sync: () async {
        synced++;
        await db.outboxDelete(['op-left-0001']);
      },
      confirm: (n) async {
        asked.add(n);
        return false;
      },
    );
    expect(ok, isTrue);
    expect(synced, 1);
    expect(asked, isEmpty);
  });

  test('offline, or the push failed: the person confirms the count, Cancel stays signed in', () async {
    final asked = <int>[];
    var synced = 0;
    expect(
      await MyAuthProvider.settleUnsentWork(outbox: box, online: () => false, sync: () async => synced++, confirm: (n) async {
        asked.add(n);
        return false;
      }),
      isFalse,
    );
    expect(synced, 0);
    expect(asked, [1]);
    expect(await db.outboxRows(), hasLength(1));   // nothing deleted

    // online but the push hangs: at most the timeout, then the question
    expect(
      await MyAuthProvider.settleUnsentWork(
        outbox: box,
        online: () => true,
        sync: () => Future<void>.delayed(const Duration(seconds: 30)),
        timeout: const Duration(milliseconds: 10),
        confirm: (n) async => true,
      ),
      isTrue,
    );
    AppConfig.lang = 'en';
    expect(MyAuthProvider.unsentWorkLossText(3), '3 changes made offline have not reached your account and will be deleted');
  });

  test('nothing waiting: no push, no question', () async {
    await db.wipe();
    var synced = 0;
    expect(await MyAuthProvider.settleUnsentWork(outbox: box, online: () => true, sync: () async => synced++, confirm: (_) async => false), isTrue);
    expect(synced, 0);
  });
}
