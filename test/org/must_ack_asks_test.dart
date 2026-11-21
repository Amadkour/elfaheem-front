// Student lifecycle phase 4 (D-1400): OrgMustAckHost's second source, GET /me/asks. A full-screen ask covers the app
// until answered, a waiting must-ack message is drawn first, a popup ask can be put off for the session, the
// `student_lifecycle` live event reads the asks again, and the payload parses (MyAsksState, MyAsk).
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/org_messages_models.dart';
import 'package:flutter_education_app/features/org/org_must_ack.dart';
import 'package:flutter_education_app/features/org/org_v3.dart' show OrgCall;
import 'package:flutter_education_app/features/org/students/my_ask_page.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

Map<String, dynamic> ask({int id = 7, String kind = 'confirm', String presentation = 'fullscreen', String status = 'open'}) => {
      'id': id,
      'org_id': 1,
      'user_id': 9,
      'kind': kind,
      'presentation': presentation,
      'title': 'Confirm your address',
      'body': 'I confirm that my address in the file is correct.',
      'fields': const [],
      'doc_keys': const [],
      'status': status,
      'answer': null,
      'due_at': '2026-12-01T10:00:00',
      'review_note': null,
      'org': {'id': 1, 'name': 'كلية الهندسة', 'name_en': 'Faculty of Engineering', 'logo': null},
      'created_by': {'id': 3, 'name': 'Student affairs'},
      'meeting': null,
      'can': {'answer': status == 'open' || status == 'returned', 'cancel': false, 'accept': false},
    };

class _Ack implements MustAckSource {
  _Ack([this.item]);
  Map<String, dynamic>? item;

  @override
  Future<MustAckState> fetch() async => item == null ? MustAckState.none : MustAckState.fromJson({'item': item, 'queued': 0});

  @override
  Future<OrgCall> acknowledge(int id) async {
    item = null;
    return const OrgCall({'next': null});
  }
}

class _Asks implements MyAskSource {
  _Asks(this.open);
  List<Map<String, dynamic>> open;
  int fetches = 0, answers = 0;

  @override
  Future<MyAsksState> fetch() async {
    fetches++;
    final full = open.where((a) => a['presentation'] == 'fullscreen').firstOrNull;
    final pop = open.where((a) => a['presentation'] == 'popup').firstOrNull;
    return MyAsksState.fromJson({'items': open, 'fullscreen': full, 'popup': pop});
  }

  @override
  Future<OrgCall> one(int id) async => OrgCall(open.firstWhere((a) => a['id'] == id));

  @override
  Future<OrgCall> answer(int id, {Map<String, dynamic> values = const {}, bool? confirm}) async {
    answers++;
    final a = open.firstWhere((a) => a['id'] == id);
    open = open.where((a) => a['id'] != id).toList();
    return OrgCall({...a, 'status': 'answered', 'can': {'answer': false}});
  }

  @override
  Future<OrgCall> upload(int id, {required String reqKey, required String fileName, String? path, Uint8List? bytes}) async => const OrgCall({});
}

Map<String, dynamic> msg() => {
      'id': 12,
      'org_id': 1,
      'delivery': 'must_ack',
      'title': 'Exam dates changed',
      'body': 'Read the new dates.',
      'reason': 'Rules changed',
      'sender': {'id': 4, 'name': 'Dean'},
      'org': {'id': 1, 'name_ar': 'كلية', 'name_en': 'Faculty'},
      'needs_ack': true,
      'acked_at': null,
    };

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  Widget host(_Ack ack, _Asks asks) =>
      layoutHost(OrgMustAckHost(source: ack, asks: asks, signedIn: () => true, child: const Scaffold(body: Text('home'))), scaffold: false);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  test('MyAsksState parses, picks the full-screen ask and skips put-off popups', () {
    final s = MyAsksState.fromJson({
      'items': [ask(id: 1, presentation: 'popup'), ask(id: 2), 'junk', {'id': 0}],
      'fullscreen': ask(id: 2),
      'popup': ask(id: 1, presentation: 'popup'),
    });
    expect(s.items.length, 2);
    expect(s.nextFullscreen()?.id, 2);
    expect(s.nextPopup({}), isNotNull);
    expect(s.nextPopup({1}), isNull);
    expect(MyAsksState.fromJson(const {}).items, isEmpty);
    expect(myAsksShouldAsk(signedIn: true, viewAs: false, enabled: true), isTrue);
    expect(myAsksShouldAsk(signedIn: true, viewAs: true, enabled: true), isFalse);
    expect(myAsksShouldAsk(signedIn: true, viewAs: false, enabled: false), isFalse);
    final a = MyAsk.fromJson(ask())!;
    expect(a.canAnswer, isTrue);
    expect(a.org, 'Faculty of Engineering');
    expect(a.dueAt, isNotNull);
  });

  testWidgets('a full-screen ask covers the app until it is answered', (tester) async {
    final asks = _Asks([ask()]);
    await tester.pumpWidget(host(_Ack(), asks));
    await settle(tester);
    expect(asks.fetches, 1);
    expect(find.byType(MyAskOverlay), findsOneWidget);
    expect(find.byKey(const ValueKey('my_ask.later')), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('my_ask.confirm')));
    await tester.tap(find.byKey(const ValueKey('my_ask.confirm')));
    await settle(tester);
    expect(asks.answers, 1);
    expect(asks.fetches, 2);
    expect(find.byType(MyAskOverlay), findsNothing);
    expect(find.text('home'), findsOneWidget);
    await done(tester);
  });

  testWidgets('a waiting must-ack message is drawn before the ask', (tester) async {
    final ack = _Ack(msg());
    await tester.pumpWidget(host(ack, _Asks([ask()])));
    await settle(tester);
    expect(find.byType(MustAckCardView), findsOneWidget);
    expect(find.byType(MyAskOverlay), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('must_ack.ok')));
    await tester.tap(find.byKey(const ValueKey('must_ack.ok')));
    await settle(tester);
    expect(find.byType(MustAckCardView), findsNothing);
    expect(find.byType(MyAskOverlay), findsOneWidget);
    await done(tester);
  });

  testWidgets('a popup can be put off; the live event reads the asks again', (tester) async {
    final asks = _Asks([ask(presentation: 'popup')]);
    await tester.pumpWidget(host(_Ack(), asks));
    await settle(tester);
    expect(find.byType(MyAskOverlay), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('my_ask.later')));
    await tester.tap(find.byKey(const ValueKey('my_ask.later')));
    await settle(tester);
    expect(find.byType(MyAskOverlay), findsNothing);
    asks.open = [...asks.open, ask(id: 8, presentation: 'fullscreen')];
    LiveEvents.instance.emit(kStudentLifecycleEvent, {'ask_id': '8'});
    await settle(tester);
    expect(asks.fetches, 2);
    expect(find.byKey(const ValueKey('my_ask.8')), findsOneWidget);
    await done(tester);
  });

  testWidgets('the switch off: no asks are read or drawn', (tester) async {
    AppConfig.disableList = [kMyAsksFeatureKey];
    final asks = _Asks([ask()]);
    await tester.pumpWidget(host(_Ack(), asks));
    await settle(tester);
    expect(asks.fetches, 0);
    expect(find.byType(MyAskOverlay), findsNothing);
    await done(tester);
  });
}
