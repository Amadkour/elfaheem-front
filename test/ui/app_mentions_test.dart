// @mentions (D-075): the pure token / insertion logic, the suggestion list and the field on every screen size, the
// keyboard (Up / Down / Enter / Esc, also through the app-wide keyboard layer) and the read-view renderer.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_keyboard.dart';
import 'package:flutter_education_app/design/app_mentions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _people = [
  MentionPerson(id: 1, name: 'Ali Hassan', username: 'ali_h'),
  MentionPerson(id: 2, name: 'Alia Mohammed Abdelrahman Al-Khatib the Second', username: 'alia.mohammed_abdelrahman_x'),
  MentionPerson(id: 3, name: 'أحمد علي', username: 'ahmed.ali'),
];

final asked = <String>[];

Future<List<MentionPerson>> _fake(String q) async {
  asked.add(q);
  final l = q.toLowerCase();
  return _people.where((p) => p.username.startsWith(l) || p.name.toLowerCase().contains(l)).toList();
}

class _Host extends StatefulWidget {
  const _Host({this.maxLines = 3, this.above = false});
  final int maxLines;
  final bool above;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final ctrl = TextEditingController();

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MentionTextField(
            key: const ValueKey('field'),
            controller: ctrl,
            source: _fake,
            maxLines: widget.maxLines,
            above: widget.above,
          ),
          FilledButton(onPressed: () => ctrl.text = 'SUBMITTED', child: const Text('Send')),
        ]),
      );
}

TextEditingController _ctrlOf(WidgetTester tester) =>
    tester.state<_HostState>(find.byType(_Host)).ctrl;

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(const Duration(milliseconds: 300)); // the 250 ms debounce
  await tester.pump();
}

void main() {
  late List<String> prevDisable;
  setUp(() {
    AppConfig.lang = 'en';
    prevDisable = List.of(AppConfig.disableList);
    AppConfig.disableList = [];
    asked.clear();
  });
  tearDown(() {
    AppConfig.disableList = prevDisable;
    AppKeyboard.keyClaim = null;
    AppKeyboardSupport.enabledOverride = null;
  });

  group('mentionQueryAt', () {
    test('the "@…" at the caret', () {
      expect(mentionQueryAt('hi @al', 6), const MentionQuery(3, 6, 'al'));
      expect(mentionQueryAt('@', 1), const MentionQuery(0, 1, ''));
      expect(mentionQueryAt('مرحبا @أحم', 10), const MentionQuery(6, 10, 'أحم'), reason: 'a name search in Arabic');
      expect(mentionQueryAt('hi @ali_h.x and', 7), const MentionQuery(3, 11, 'ali'), reason: 'caret inside the word');
    });
    test('not a mention', () {
      expect(mentionQueryAt('mail a@b', 8), isNull, reason: 'an e-mail address');
      expect(mentionQueryAt('@@x', 3), isNull);
      expect(mentionQueryAt('hi @al bob', 10), isNull, reason: 'a space ends it');
      expect(mentionQueryAt('plain', 5), isNull);
      expect(mentionQueryAt('', 0), isNull);
      expect(mentionQueryAt('@${'a' * 31}', 32), isNull, reason: 'too long to be a username or a name start');
      expect(mentionQueryAt('x', 9), isNull);
    });
  });

  group('insertMention', () {
    test('replaces the word and adds one space', () {
      final q = mentionQueryAt('hi @al', 6)!;
      expect(insertMention('hi @al', q, 'ali_h'), ('hi @ali_h ', 10));
      final q2 = mentionQueryAt('hi @al there', 6)!;
      expect(insertMention('hi @al there', q2, '@ALI_H'), ('hi @ali_h there', 10), reason: 'the space is reused');
      final q3 = mentionQueryAt('x @alxyz,', 5)!;
      expect(insertMention('x @alxyz,', q3, 'ali_h'), ('x @ali_h ,', 9));
    });
  });

  group('mentionSegments', () {
    test('the server token rule', () {
      expect(mentionSegments('Hi @Ali_H, see @bob.k. mail a@bob_k.com @me'), const [
        MentionSegment('Hi '),
        MentionSegment('@Ali_H', 'ali_h'),
        MentionSegment(', see '),
        MentionSegment('@bob.k', 'bob.k'),
        MentionSegment('. mail a@bob_k.com @me'),
      ]);
      expect(mentionSegments('no mentions'), const [MentionSegment('no mentions')]);
      expect(mentionSegments(''), const <MentionSegment>[]);
      expect(mentionSegments('@ali_h'), const [MentionSegment('@ali_h', 'ali_h')]);
    });
  });

  test('MentionPerson.fromJson', () {
    final p = MentionPerson.fromJson({'id': 4, 'name': 'Sara', 'username': '@sara', 'image_url': ''})!;
    expect((p.id, p.name, p.username, p.imageUrl), (4, 'Sara', 'sara', null));
    expect(MentionPerson.fromJson({'id': 4, 'name': 'x'}), isNull);
    expect(MentionPerson.fromJson({'username': 'x'}), isNull);
    expect(MentionPerson.fromJson('x'), isNull);
    expect(MentionPerson.fromJson({'id': 5, 'username': 'zed'})!.name, 'zed');
  });

  testWidgets('the suggestion list fits every screen', (tester) async {
    await expectNoLayoutErrors(tester, () => Padding(
          padding: const EdgeInsets.all(16),
          child: MentionSuggestionList(people: _people, highlighted: 1, onPick: (_) {}),
        ));
  });

  testWidgets('the field with its list open fits every screen (below and above)', (tester) async {
    for (final above in [false, true]) {
      await expectNoLayoutErrors(tester, () => Align(alignment: Alignment.bottomCenter, child: _Host(above: above)),
          act: (t) async {
        await t.tap(find.byType(TextField));
        await _type(t, 'Hello @al');
        expect(find.byType(MentionSuggestionList), findsOneWidget);
      });
    }
  });

  testWidgets('typing "@al" suggests, a tap inserts "@username "', (tester) async {
    await tester.pumpWidget(layoutHost(const _Host(), scale: 1));
    await tester.tap(find.byType(TextField));
    await _type(tester, 'Hello @al');
    expect(asked, ['al']);
    expect(find.text('@ali_h'), findsOneWidget);
    expect(find.text('@alia.mohammed_abdelrahman_x'), findsOneWidget);
    await tester.tap(find.text('Ali Hassan'));
    await tester.pump();
    expect(_ctrlOf(tester).text, 'Hello @ali_h ');
    expect(_ctrlOf(tester).selection.baseOffset, 13);
    expect(find.byType(MentionSuggestionList), findsNothing);
    await _type(tester, 'Hello @ali_h there');
    expect(find.byType(MentionSuggestionList), findsNothing, reason: 'the caret left the mention');
  });

  testWidgets('keyboard: Down + Enter picks, Esc closes (field focus handler)', (tester) async {
    await tester.pumpWidget(layoutHost(const _Host(), scale: 1));
    await tester.tap(find.byType(TextField));
    await _type(tester, '@al');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(_ctrlOf(tester).text, '@alia.mohammed_abdelrahman_x ');
    await _type(tester, 'x @ah');
    expect(find.byType(MentionSuggestionList), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(MentionSuggestionList), findsNothing);
    expect(_ctrlOf(tester).text, 'x @ah');
  });

  testWidgets('web keyboard layer: Enter picks the suggestion instead of submitting', (tester) async {
    AppKeyboardSupport.enabledOverride = true;
    await tester.pumpWidget(layoutHost(const AppKeyboardSupport(child: _Host(maxLines: 1)), scale: 1));
    await tester.tap(find.byType(TextField));
    await _type(tester, '@al');
    expect(AppKeyboard.keyClaim, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(_ctrlOf(tester).text, '@ali_h ', reason: 'not "SUBMITTED": the open list owns Enter');
    expect(AppKeyboard.keyClaim, isNull, reason: 'released once the list closed');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('kill switch: a plain field, nothing looked up', (tester) async {
    AppConfig.disableList = [kMentionsFeatureKey];
    await tester.pumpWidget(layoutHost(const _Host(), scale: 1));
    expect(find.byType(Mentions), findsOneWidget);
    await tester.tap(find.byType(TextField));
    await _type(tester, '@al');
    expect(asked, isEmpty);
    expect(find.byType(MentionSuggestionList), findsNothing);
  });

  group('MentionText', () {
    List<TextSpan> mentionSpans(WidgetTester tester) {
      final out = <TextSpan>[];
      for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
        rt.text.visitChildren((s) {
          if (s is TextSpan && s.recognizer != null) out.add(s);
          return true;
        });
      }
      return out;
    }

    testWidgets('highlights each mention and reports a tap', (tester) async {
      final tapped = <String>[];
      await tester.pumpWidget(layoutHost(
          MentionText('Thanks @Ali_H and @bob.k. (a@b.com)', onTap: tapped.add, maxLines: 3), scale: 1));
      final spans = mentionSpans(tester);
      expect(spans, hasLength(2));
      expect(spans.first.text, contains('@Ali_H'));
      (spans.first.recognizer! as TapGestureRecognizer).onTap!();
      (spans.last.recognizer! as TapGestureRecognizer).onTap!();
      expect(tapped, ['ali_h', 'bob.k']);
    });

    testWidgets('plain when switched off or nobody is mentioned', (tester) async {
      await tester.pumpWidget(layoutHost(const MentionText('no one here'), scale: 1));
      expect(find.text('no one here'), findsOneWidget);
      AppConfig.disableList = [kMentionsFeatureKey];
      await tester.pumpWidget(layoutHost(const MentionText('hi @ali_h'), scale: 1));
      expect(find.text('hi @ali_h'), findsOneWidget);
      expect(mentionSpans(tester), isEmpty);
    });

    testWidgets('fits every screen, selectable too', (tester) async {
      await expectNoLayoutErrors(tester, () => const Padding(
            padding: EdgeInsets.all(16),
            child: Column(children: [
              MentionText('اجتماع مع @ali_h و @ahmed.ali لمراجعة الخطة', maxLines: 2, overflow: TextOverflow.ellipsis),
              MentionText('Selectable @alia.mohammed_abdelrahman_x text', selectable: true),
            ]),
          ));
    });
  });
}
