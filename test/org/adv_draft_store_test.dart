// Academic Advising, Phase 4 (#23): the offline note store (lib/features/org/advising/adv_draft_store.dart). A draft
// is kept per user, organization and student and comes back after a restart; a note sent offline is queued with its
// client_id and posted on reconnect with the SAME id (so a request that reached the server before the connection
// dropped is never written twice); a network failure keeps it queued; a definite "no" is kept with its reason and
// not retried until the author reopens or discards it.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/org/advising/adv_draft_store.dart';
import 'package:flutter_education_app/features/org/advising/adv_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The device, in memory (survives a "restart" = a new store over the same backend).
class _Memory implements AdvDraftBackend {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }
}

/// The server: records every POST; [fail] decides the answer of the next ones.
class _Server {
  final calls = <(int, int, String?)>[];
  final made = <String, AdvNote>{};
  ApiException? Function(AdvNoteDraft d)? fail;

  Future<AdvNote> post(int org, int member, AdvNoteDraft d) async {
    calls.add((org, member, d.clientId));
    final f = fail?.call(d);
    if (f != null) throw f;
    // the server is idempotent by client_id
    return made.putIfAbsent(d.clientId!, () => AdvNote(id: 900 + made.length, author: const AdvRef(userId: 31, name: 'Huda'), body: d.body.trim(), mine: true));
  }
}

const _network = ApiException(statusCode: 0, type: ApiErrorType.network, message: 'offline');
const _refused = ApiException(statusCode: 422, type: ApiErrorType.validation, message: 'bad', code: 'advising_bad_visibility');
const _conflict = ApiException(statusCode: 409, message: 'conflict', code: 'advising_client_id_conflict');
const _busy =ApiException(statusCode: 429, type: ApiErrorType.unknown, message: 'slow down', code: 'advising_rate_limited');

void main() {
  setUp(() => AppConfig.lang = 'en');

  late _Memory disk;
  late _Server server;
  var online = true;
  var user = 31;

  AdvDraftStore store() => AdvDraftStore(backend: disk, poster: server.post, userId: () async => user, online: () => online);

  setUp(() {
    disk = _Memory();
    server = _Server();
    online = true;
    user = 31;
  });

  test('a draft is kept per user and student, comes back after a restart, and an empty one is removed', () async {
    final s = store();
    await s.saveDraft(3, 601, const AdvNoteDraft(body: 'Called about the midterm', visibility: 'private', contactMode: 'phone'));
    await s.saveDraft(3, 602, const AdvNoteDraft(body: 'Another student'));

    final again = store(); // the app was closed and opened again
    final d = await again.draft(3, 601);
    expect(d!.body, 'Called about the midterm');
    expect(d.visibility, 'private');
    expect(d.contactMode, 'phone');
    expect(await again.draft(4, 601), isNull, reason: 'another organization');

    user = 32;
    expect(await again.draft(3, 601), isNull, reason: 'another user on the same device sees nothing');

    user = 31;
    await again.saveDraft(3, 601, const AdvNoteDraft(body: '   '));
    expect(await again.draft(3, 601), isNull);
    expect((await again.draft(3, 602))!.body, 'Another student');
  });

  test('online: the note is posted with a fresh client_id and the draft is cleared', () async {
    final s = store();
    await s.saveDraft(3, 601, const AdvNoteDraft(body: 'Met in the office'));
    final r = await s.send(3, 601, const AdvNoteDraft(body: 'Met in the office'));
    expect(r.state, AdvSendState.sent);
    expect(r.note!.body, 'Met in the office');
    expect(server.calls.single.$3, isNotNull);
    expect(server.calls.single.$3!.length, lessThanOrEqualTo(40));
    expect(await s.draft(3, 601), isNull);
    expect(await s.queued(3, 601), isEmpty);
  });

  test('offline: queued with its client_id, posted on reconnect, and a retry after a lost answer reuses the id', () async {
    online = false;
    final s = store();
    var changes = 0;
    s.changes.addListener(() => changes++);
    final r = await s.send(3, 601, const AdvNoteDraft(body: 'Written on the bus', sensitive: true));
    expect(r.state, AdvSendState.queued);
    expect(server.calls, isEmpty, reason: 'no request while offline');
    final q = await s.queued(3, 601);
    expect(q.single.clientId, isNotEmpty);
    expect(q.single.failed, isFalse);
    expect(changes, greaterThan(0));

    // back online, but the first attempt's answer is lost on the way back
    online = true;
    server.fail = (_) => _network;
    expect(await store().flush(), 0);
    expect((await s.queued(3, 601)).single.clientId, q.single.clientId, reason: 'still queued, same id');

    // the next reconnect posts it — twice in a row changes nothing (idempotent on the server, gone from the queue)
    server.fail = null;
    await s.onReconnect();
    expect(await s.queued(3, 601), isEmpty);
    await s.onReconnect();
    expect(server.made, hasLength(1));
    expect(server.calls.map((c) => c.$3).toSet(), {q.single.clientId}, reason: 'every attempt carried the same client_id');
  });

  test('a network failure while online queues the note instead of losing it', () async {
    server.fail = (_) => _network;
    final s = store();
    final r = await s.send(3, 601, const AdvNoteDraft(body: 'Flaky Wi-Fi'));
    expect(r.state, AdvSendState.queued);
    expect(await s.queued(3, 601), hasLength(1));
  });

  test('a definite "no" while online stays in the composer; in the queue it is kept with its reason, not retried', () async {
    server.fail = (_) => _refused;
    final s = store();
    await s.saveDraft(3, 601, const AdvNoteDraft(body: 'Shown to the student'));
    final r = await s.send(3, 601, const AdvNoteDraft(body: 'Shown to the student'));
    expect(r.state, AdvSendState.failed);
    expect(r.error!.code, 'advising_bad_visibility');
    expect(await s.draft(3, 601), isNotNull, reason: 'the draft is kept to fix it');

    online = false;
    await s.send(3, 601, const AdvNoteDraft(body: 'Queued then refused'));
    online = true;
    expect(await s.flush(), 0);
    final failed = (await s.queued(3, 601)).single;
    expect(failed.failed, isTrue);
    expect(failed.error, 'advising_bad_visibility');
    expect(failed.message, isNotEmpty);
    final before = server.calls.length;
    await s.flush();
    expect(server.calls.length, before, reason: 'a refused note is not sent again by itself');

    // the author takes it back into the composer: a new id next time
    final back = await s.reopen(failed);
    expect(back.body, 'Queued then refused');
    expect(back.clientId, isNull);
    expect(await s.queued(3, 601), isEmpty);
    expect((await s.draft(3, 601))!.body, 'Queued then refused');
  });

  test('a busy server (429) keeps the queue; discard drops a note', () async {
    online = false;
    final s = store();
    await s.send(3, 601, const AdvNoteDraft(body: 'One'));
    await s.send(3, 601, const AdvNoteDraft(body: 'Two'));
    online = true;
    server.fail = (_) => _busy;
    expect(await s.flush(), 0);
    final q = await s.queued(3, 601);
    expect(q, hasLength(2));
    expect(q.every((x) => !x.failed), isTrue);
    expect(server.calls, hasLength(1), reason: 'stops at the first note that must wait');
    await s.discard(q.first);
    expect((await s.queued(3, 601)).single.draft.body, 'Two');
  });

  test('a client_id the server holds for another student: a new id, the same text, posted again', () async {
    server.fail = (d) => d.clientId == 'nreused' ? _conflict : null;
    final s = store();
    final r = await s.send(3, 601, const AdvNoteDraft(body: 'Kept text', clientId: 'nreused'));
    expect(r.state, AdvSendState.sent);
    expect(r.note!.body, 'Kept text');
    expect(server.calls, hasLength(2));
    expect(server.calls.first.$3, 'nreused');
    expect(server.calls.last.$3, isNot('nreused'));

    // queued: the entry takes the new id, so the next reconnect does not run into the conflict again
    online = false;
    await s.send(3, 601, const AdvNoteDraft(body: 'Offline text', clientId: 'nreused2'));
    online = true;
    server.fail = (d) => d.clientId == 'nreused2' ? _conflict : _network;
    expect(await s.flush(), 0);
    final q = (await s.queued(3, 601)).single;
    expect(q.clientId, isNot('nreused2'));
    expect(q.draft.body, 'Offline text');
    expect(q.failed, isFalse);
  });

  test('flush posts only the signed-in user\'s notes, oldest first', () async {
    online = false;
    final s = store();
    await s.send(3, 601, const AdvNoteDraft(body: 'Mine 1'));
    user = 32;
    await s.send(3, 601, const AdvNoteDraft(body: 'Someone else'));
    user = 31;
    await s.send(3, 602, const AdvNoteDraft(body: 'Mine 2'));
    online = true;
    expect(await s.flush(), 2);
    expect([for (final c in server.calls) c.$2], [601, 602]);
    user = 32;
    expect((await s.queued(3, 601)).single.draft.body, 'Someone else');
  });
}
