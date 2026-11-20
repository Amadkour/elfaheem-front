// PendingIntent (D-1324): a guest's "book this course" is saved, resumed exactly once, gone after 24 h and on sign-out.
import 'dart:convert';

import 'package:flutter_education_app/core/routing/pending_intent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 20, 10);
  var now = t0;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = t0;
    PendingIntent.clock = () => now;
  });

  tearDown(() => PendingIntent.clock = DateTime.now);

  PendingIntent book() => PendingIntent(
      kind: PendingIntentKind.bookCourse, id: '42', plan: 'monthly', filters: {'stage_id': 3, 'delivery': 'online'});

  test('saved as the contract JSON and read back', () async {
    await PendingIntent.save(book());
    final raw = jsonDecode((await SharedPreferences.getInstance()).getString('pending_intent')!) as Map;
    expect(raw['v'], 1);
    expect(raw['kind'], 'book_course');
    expect(raw['id'], '42');
    expect(raw['plan'], 'monthly');
    expect(raw['filters'], {'stage_id': 3, 'delivery': 'online'});
    expect(raw['at'], t0.toIso8601String());

    final i = await PendingIntent.peek();
    expect(i, isNotNull);
    expect(i!.kind, PendingIntentKind.bookCourse);
    expect(i.id, '42');
    expect(i.plan, 'monthly');
    expect(i.filters, {'stage_id': 3, 'delivery': 'online'});
    expect(await PendingIntent.peek(), isNotNull, reason: 'peek does not consume');
  });

  test('resumed exactly once, even by two pages at the same time', () async {
    await PendingIntent.save(book());
    final opened = <String>[];
    Future<void> open(PendingIntent i) async => opened.add(i.id);

    final both = await Future.wait([PendingIntent.resume(open), PendingIntent.resume(open)]);
    expect(both.where((r) => r), hasLength(1));
    expect(await PendingIntent.resume(open), isFalse);
    expect(opened, ['42']);
    expect((await SharedPreferences.getInstance()).getString('pending_intent'), isNull);
  });

  test('a failing opener still clears it', () async {
    await PendingIntent.save(book());
    expect(await PendingIntent.resume((_) async => throw StateError('no navigator')), isTrue);
    expect(await PendingIntent.peek(), isNull);
  });

  test('expired after 24 h: dropped unread', () async {
    await PendingIntent.save(book());
    now = t0.add(const Duration(hours: 23, minutes: 59));
    expect(await PendingIntent.peek(), isNotNull);

    now = t0.add(const Duration(hours: 24, minutes: 1));
    var opened = 0;
    expect(await PendingIntent.resume((_) async => opened++), isFalse);
    expect(opened, 0);
    expect((await SharedPreferences.getInstance()).getString('pending_intent'), isNull);
  });

  test('cleared on sign-out (MyAuthProvider.logout calls clear)', () async {
    await PendingIntent.save(book());
    await PendingIntent.clear();
    expect(await PendingIntent.peek(), isNull);
  });

  test('the last intent wins; unreadable or other-version JSON is ignored', () async {
    await PendingIntent.save(book());
    await PendingIntent.save(PendingIntent(kind: PendingIntentKind.buyStoreItem, id: 'sku-7'));
    expect((await PendingIntent.peek())!.kind, PendingIntentKind.buyStoreItem);

    final p = await SharedPreferences.getInstance();
    await p.setString('pending_intent', '{not json');
    expect(await PendingIntent.peek(), isNull);
    await p.setString('pending_intent', jsonEncode({...book().toJson(), 'v': 2}));
    expect(await PendingIntent.peek(), isNull);
  });
}
