// Web / desktop keyboard layer (lib/design/app_keyboard.dart): Enter walks a form and presses its primary button,
// Ctrl+Enter submits a multi-line field, search boxes and fields with their own handler are left alone, hidden
// buttons are skipped, EnterSubmits decides by hand, Esc leaves a field, Ctrl+K / "/" reach the search box.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_keyboard.dart';
import 'package:flutter_education_app/utils/top_route_observer.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const kA = Key('a');
const kB = Key('b');
const kSearch = Key('search');

Widget host(Widget page) => layoutHost(AppKeyboardSupport(child: page), scale: 1);

Future<void> focusField(WidgetTester t, Key key) async {
  await t.showKeyboard(find.byKey(key));
  await t.pump();
}

bool hasFocus(WidgetTester t, Key key) =>
    t.widget<EditableText>(find.descendant(of: find.byKey(key), matching: find.byType(EditableText))).focusNode.hasFocus;

Future<void> enter(WidgetTester t) async {
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.pump();
  await t.pump();
}

Future<void> ctrlEnter(WidgetTester t) async {
  await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pump();
  await t.pump();
}

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppKeyboardSupport.enabledOverride = true;
  });
  tearDown(() => AppKeyboardSupport.enabledOverride = null);

  testWidgets('Enter moves to the next field, then presses the primary button', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(host(Column(children: [
      const TextField(key: kA),
      const TextField(key: kB),
      FilledButton(onPressed: () => pressed++, child: const Text('Save')),
    ])));
    await focusField(tester, kA);
    await enter(tester);
    expect(hasFocus(tester, kB), isTrue);
    expect(pressed, 0);
    await enter(tester);
    expect(pressed, 1);
  });

  testWidgets('the app PrimaryButton (a gesture detector) is pressed too', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(host(Column(children: [
      const TextField(key: kA),
      PrimaryButton(isLoading: false, label: 'Login', onPressed: () => pressed++),
    ])));
    await focusField(tester, kA);
    await enter(tester);
    expect(pressed, 1);
  });

  testWidgets('a busy or disabled PrimaryButton is not pressed', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(host(Column(children: [
      const TextField(key: kA),
      PrimaryButton(isLoading: true, label: 'Login', onPressed: () => pressed++),
    ])));
    await focusField(tester, kA);
    await enter(tester);
    expect(pressed, 0);
  });

  testWidgets('a search box never submits', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(host(Column(children: [
      const TextField(key: kA, decoration: InputDecoration(prefixIcon: Icon(Icons.search_rounded))),
      const TextField(key: kB, decoration: InputDecoration(hintText: 'ابحث عن طالب')),
      FilledButton(onPressed: () => pressed++, child: const Text('Create')),
    ])));
    await focusField(tester, kA);
    await enter(tester);
    await focusField(tester, kB);
    await enter(tester);
    expect(pressed, 0);
  });

  testWidgets('a field with its own onSubmitted is left to the engine', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(host(Column(children: [
      TextField(key: kA, onSubmitted: (_) {}),
      FilledButton(onPressed: () => pressed++, child: const Text('Save')),
    ])));
    await focusField(tester, kA);
    await enter(tester);
    expect(pressed, 0);
  });

  testWidgets('multi-line: Enter stays a newline, Ctrl+Enter submits (onSubmitted first, else the button)', (tester) async {
    var pressed = 0;
    var submitted = 0;
    await tester.pumpWidget(host(Column(children: [
      const TextField(key: kA, maxLines: 3),
      TextField(key: kB, maxLines: 3, onSubmitted: (_) => submitted++),
      FilledButton(onPressed: () => pressed++, child: const Text('Send')),
    ])));
    await focusField(tester, kA);
    await enter(tester);
    expect(pressed, 0);
    await ctrlEnter(tester);
    expect(pressed, 1);
    await focusField(tester, kB);
    await ctrlEnter(tester);
    expect((submitted, pressed), (1, 1));
  });

  testWidgets('the button closest to the field in the tree wins', (tester) async {
    var a = 0, b = 0;
    await tester.pumpWidget(host(Column(children: [
      Row(children: [
        const Expanded(child: TextField(key: kA, textInputAction: TextInputAction.done)),
        FilledButton(onPressed: () => a++, child: const Text('A')),
      ]),
      Row(children: [
        const Expanded(child: TextField(key: kB)),
        FilledButton(onPressed: () => b++, child: const Text('B')),
      ]),
    ])));
    await focusField(tester, kA);
    await enter(tester); // "done": submits right away, with A — not B
    await focusField(tester, kB);
    await enter(tester);
    expect((a, b), (1, 1));
  });

  testWidgets('a button on a tab that is not shown is skipped', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(host(IndexedStack(index: 0, children: [
      const Column(children: [TextField(key: kA)]),
      Column(children: [FilledButton(onPressed: () => pressed++, child: const Text('Hidden'))]),
    ])));
    await focusField(tester, kA);
    await enter(tester);
    expect(pressed, 0);
  });

  testWidgets('EnterSubmits decides by hand; EnterSubmits.none switches Enter off', (tester) async {
    var submitted = 0, pressed = 0;
    await tester.pumpWidget(host(Column(children: [
      EnterSubmits(
        onSubmit: () => submitted++,
        child: const Column(children: [TextField(key: kA), TextField(key: kB)]),
      ),
      const EnterSubmits.none(child: TextField(key: kSearch)),
      FilledButton(onPressed: () => pressed++, child: const Text('Save')),
    ])));
    await focusField(tester, kA);
    await enter(tester);
    expect((submitted, pressed), (1, 0));
    expect(hasFocus(tester, kA), isTrue); // no walking inside an explicit scope
    await focusField(tester, kSearch);
    await enter(tester);
    expect((submitted, pressed), (1, 0));
  });

  testWidgets('a dialog with text buttons only: Enter presses the last one', (tester) async {
    String? answer;
    await tester.pumpWidget(host(const SizedBox()));
    final ctx = tester.element(find.byType(SizedBox).first);
    final future = showDialog<String>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        content: const TextField(key: kA, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, 'cancel'), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dctx, 'ok'), child: const Text('OK')),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(hasFocus(tester, kA), isTrue);
    await enter(tester);
    await tester.pumpAndSettle();
    answer = await future;
    expect(answer, 'ok');
  });

  testWidgets('Esc takes the focus out of a field on a page', (tester) async {
    await tester.pumpWidget(host(const Column(children: [TextField(key: kA)])));
    await focusField(tester, kA);
    expect(hasFocus(tester, kA), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(hasFocus(tester, kA), isFalse);
  });

  testWidgets('Ctrl+K jumps to the search box and selects its text', (tester) async {
    final search = TextEditingController(text: 'old');
    addTearDown(search.dispose);
    await tester.pumpWidget(host(Column(children: [
      const TextField(key: kA),
      TextField(key: kSearch, controller: search, decoration: const InputDecoration(hintText: 'Search')),
    ])));
    await focusField(tester, kA);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(hasFocus(tester, kSearch), isTrue);
    expect(search.selection, const TextSelection(baseOffset: 0, extentOffset: 3));
  });

  testWidgets('"/" reaches the search box while nothing is focused, and types while a field is', (tester) async {
    final other = TextEditingController();
    addTearDown(other.dispose);
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [topRouteObserver],
      home: AppKeyboardSupport(
        child: Scaffold(
          body: Column(children: [
            TextField(key: kA, controller: other),
            const TextField(key: kSearch, decoration: InputDecoration(labelText: 'Filter by name')),
          ]),
        ),
      ),
    ));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pump();
    expect(hasFocus(tester, kSearch), isTrue);

    await focusField(tester, kA);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pump();
    expect(hasFocus(tester, kA), isTrue); // not intercepted while typing
  });
}
